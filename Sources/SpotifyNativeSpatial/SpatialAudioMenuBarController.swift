import AppKit
import AudioToolbox
import Combine
import Foundation

@available(macOS 14.2, *)
@MainActor
final class SpatialAudioMenuBarController: ObservableObject {
    @Published private(set) var availableApps: [AudioAppTarget] = []
    @Published private(set) var selectedAppKeys = Set<String>()
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var activeHeadTrackingEnabled = false
    @Published var headTrackingEnabled = false {
        didSet {
            guard oldValue != headTrackingEnabled else {
                return
            }
            applyHeadTrackingPreferenceChange()
        }
    }

    private var renderer: ProcessTapSpatialRenderer?
    private var restartWorkItem: DispatchWorkItem?
    private var routedOutputDeviceID: AudioObjectID?
    private let outputDeviceObserver = DefaultOutputDeviceObserver()

    private enum PreferenceKey {
        static let headTracking = "headTrackingEnabled"
        static let selectedApps = "selectedAppKeys"
    }

    init(headTrackingEnabled: Bool? = nil) {
        let defaults = UserDefaults.standard
        let resolvedHeadTracking = headTrackingEnabled ?? defaults.bool(forKey: PreferenceKey.headTracking)
        self.headTrackingEnabled = resolvedHeadTracking
        self.activeHeadTrackingEnabled = resolvedHeadTracking
        self.selectedAppKeys = Set(defaults.stringArray(forKey: PreferenceKey.selectedApps) ?? [])

        outputDeviceObserver.start { [weak self] in
            self?.handleDefaultOutputDeviceChange()
        }
    }

    var menuBarIcon: NSImage {
        selectedAppKeys.isEmpty ? MenuBarIconRenderer.idle : MenuBarIconRenderer.active
    }

    var headTrackingChangePending: Bool {
        renderer != nil && headTrackingEnabled != activeHeadTrackingEnabled
    }

    func refreshApps(restartSelected: Bool = true) {
        do {
            availableApps = try AudioProcessResolver.resolveApps()
            let availableKeys = Set(availableApps.map(\.key))
            selectedAppKeys.formIntersection(availableKeys)

            if restartSelected {
                scheduleRendererRestart()
            }
        } catch {
            statusMessage = "Refresh failed"
        }
    }

    func isSelected(_ app: AudioAppTarget) -> Bool {
        selectedAppKeys.contains(app.key)
    }

    func setSelected(_ isSelected: Bool, for app: AudioAppTarget) {
        if isSelected {
            selectedAppKeys.insert(app.key)
        } else {
            selectedAppKeys.remove(app.key)
        }
        persistSelection()
        scheduleRendererRestart()
    }

    func stopAll() {
        restartWorkItem?.cancel()
        selectedAppKeys.removeAll()
        persistSelection()
        restartRenderer()
    }

    func restoreRoutingAtLaunch() {
        guard !selectedAppKeys.isEmpty else {
            return
        }
        refreshApps()
    }

    func restartRoutingToApplyHeadTracking() {
        restartWorkItem?.cancel()
        restartRenderer(applyHeadTrackingPreference: true)
    }

    func shutdown() {
        outputDeviceObserver.stop()
        restartWorkItem?.cancel()
        restartWorkItem = nil
        renderer?.stop()
        renderer = nil
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

@available(macOS 14.2, *)
private extension SpatialAudioMenuBarController {
    func applyHeadTrackingPreferenceChange() {
        UserDefaults.standard.set(headTrackingEnabled, forKey: PreferenceKey.headTracking)

        guard let renderer else {
            activeHeadTrackingEnabled = headTrackingEnabled
            return
        }

        // Prefer toggling head tracking on the live mixer -- rebuilding the
        // whole route for one property is what made the switch sound rough.
        // The restart path remains as a fallback if the live set fails.
        do {
            try renderer.setHeadTrackingEnabled(headTrackingEnabled)
            activeHeadTrackingEnabled = headTrackingEnabled
        } catch {
            statusMessage = "Restart to apply"
        }
    }

    func persistSelection() {
        UserDefaults.standard.set(selectedAppKeys.sorted(), forKey: PreferenceKey.selectedApps)
    }

    func handleDefaultOutputDeviceChange() {
        guard renderer != nil else {
            return
        }

        // CoreAudio re-announces the default device without changing it (for
        // example when AirPods reconfigure for head tracking); only rebuild
        // when the device actually changed.
        let currentDevice = try? AudioObjectID.readDefaultSystemOutputDevice()
        guard currentDevice != routedOutputDeviceID else {
            return
        }

        // The route is bound to the device captured at start; rebuild it so
        // audio follows the new default output. Refreshing also re-resolves
        // process objects, and the rebuild itself is debounced.
        refreshApps()
    }

    func restartRenderer(applyHeadTrackingPreference: Bool = false) {
        let selectedApps = availableApps.filter { selectedAppKeys.contains($0.key) }
        let processes = selectedApps.flatMap(\.processes)
        let previousRenderer = renderer
        let wasRunning = previousRenderer != nil
        let nextHeadTrackingEnabled = applyHeadTrackingPreference || !wasRunning
            ? headTrackingEnabled
            : activeHeadTrackingEnabled

        guard !processes.isEmpty else {
            previousRenderer?.stop()
            renderer = nil
            routedOutputDeviceID = nil
            activeHeadTrackingEnabled = headTrackingEnabled
            statusMessage = "Idle"
            return
        }

        // Stop the old route before starting the next one: a second process
        // tap created while the same processes are already tapped (and muted)
        // captures only silence, so an overlapping replacement comes up dead.
        previousRenderer?.stop()
        renderer = nil

        do {
            let nextRenderer = ProcessTapSpatialRenderer(
                processes: processes,
                headTrackingEnabled: nextHeadTrackingEnabled
            )
            nextRenderer.onOutputSampleRateChanged = { [weak self] in
                self?.scheduleRendererRestart()
            }
            try nextRenderer.start()
            renderer = nextRenderer
            routedOutputDeviceID = try? AudioObjectID.readDefaultSystemOutputDevice()
            activeHeadTrackingEnabled = nextHeadTrackingEnabled

            if selectedApps.count == 1, let app = selectedApps.first {
                statusMessage = "Spatializing \(app.displayName)"
            } else {
                statusMessage = "Spatializing \(selectedApps.count) apps"
            }
        } catch {
            routedOutputDeviceID = nil
            statusMessage = previousRenderer == nil ? "Start failed" : "Restart failed"
            if previousRenderer == nil {
                selectedAppKeys.removeAll()
                persistSelection()
                activeHeadTrackingEnabled = headTrackingEnabled
            }
        }
    }

    func scheduleRendererRestart() {
        restartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.restartRenderer()
            }
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: workItem)
    }
}
