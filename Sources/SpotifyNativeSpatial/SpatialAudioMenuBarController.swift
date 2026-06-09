import AppKit
import Combine
import Foundation
import SwiftUI

@available(macOS 14.2, *)
@MainActor
final class SpatialAudioMenuBarController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var availableApps: [AudioAppTarget] = []
    @Published private(set) var selectedAppKeys = Set<String>()
    @Published private(set) var statusMessage = "Idle"
    @Published var headTrackingEnabled: Bool {
        didSet {
            guard oldValue != headTrackingEnabled else {
                return
            }
            updateHeadTracking()
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let headMotionTracker = HeadMotionTracker()
    private var renderer: ProcessTapSpatialRenderer?

    init(headTrackingEnabled: Bool) {
        self.headTrackingEnabled = headTrackingEnabled
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        refreshApps(restartSelected: false)

        if headTrackingEnabled {
            updateHeadTracking()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        headMotionTracker.stop()
        renderer?.stop()
    }

    func refreshApps(restartSelected: Bool = true) {
        do {
            availableApps = try AudioProcessResolver.resolveApps()
            let availableKeys = Set(availableApps.map(\.key))
            selectedAppKeys.formIntersection(availableKeys)

            if restartSelected {
                restartRenderer()
            } else {
                updateStatusButton()
            }
        } catch {
            statusMessage = "Refresh failed"
            updateStatusButton()
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
        restartRenderer()
    }

    func stopAll() {
        selectedAppKeys.removeAll()
        restartRenderer()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

@available(macOS 14.2, *)
private extension SpatialAudioMenuBarController {
    func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Spatial Audio")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Spatial Audio Router"
        button.target = self
        button.action = #selector(togglePopover(_:))
        updateStatusButton()
    }

    func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: SpatialAudioPopoverView(controller: self)
        )
    }

    func restartRenderer() {
        renderer?.stop()
        renderer = nil

        let selectedApps = availableApps.filter { selectedAppKeys.contains($0.key) }
        let processes = selectedApps.flatMap(\.processes)

        guard !processes.isEmpty else {
            statusMessage = "Idle"
            updateStatusButton()
            return
        }

        do {
            let nextRenderer = ProcessTapSpatialRenderer(processes: processes)
            try nextRenderer.start()
            nextRenderer.setHeadOrientation(headMotionTracker.currentOrientation)
            renderer = nextRenderer

            if selectedApps.count == 1, let app = selectedApps.first {
                statusMessage = "Spatializing \(app.displayName)"
            } else {
                statusMessage = "Spatializing \(selectedApps.count) apps"
            }
        } catch {
            statusMessage = "Start failed"
            selectedAppKeys.removeAll()
        }

        updateStatusButton()
    }

    func updateHeadTracking() {
        if headTrackingEnabled {
            headMotionTracker.onOrientationChanged = { [weak self] orientation in
                self?.renderer?.setHeadOrientation(orientation)
            }

            let result = headMotionTracker.start()
            if result == .started {
                renderer?.setHeadOrientation(.zero)
            } else {
                headTrackingEnabled = false
                statusMessage = result.statusMessage
            }
        } else {
            headMotionTracker.stop()
            headMotionTracker.onOrientationChanged = nil
            renderer?.setHeadOrientation(.zero)
        }

        updateStatusButton()
    }

    func updateStatusButton() {
        let active = !selectedAppKeys.isEmpty
        let symbolName = active ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Spatial Audio")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = statusMessage
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            refreshApps(restartSelected: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
