import AppKit
import MacControlCenterUI
import SwiftUI

@available(macOS 14.2, *)
@MainActor
struct SpatialAudioMenuContent: View {
    @ObservedObject var controller: SpatialAudioMenuBarController
    @Binding var isMenuPresented: Bool

    var body: some View {
        MacControlCenterMenu(
            isPresented: $isMenuPresented,
            activateAppOnCommandSelection: false
        ) {
            MenuHeader("Head Tracking") {
                Toggle("", isOn: $controller.headTrackingEnabled.animation(.macControlCenterMenuResize))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            MenuSection(divider: false) {
                if controller.headTrackingChangePending {
                    MenuCommand("Restart Routing", activatesApp: false, dismissesMenu: false) {
                        controller.restartRoutingToApplyHeadTracking()
                    }
                } else {
                    Text("Apple native")
                        .foregroundStyle(.secondary)
                        .textScale(.secondary)
                }
            }

            MenuHeader("Room Ambience") {
                Toggle("", isOn: $controller.roomAmbienceEnabled.animation(.macControlCenterMenuResize))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            MenuSection(divider: false) {
                Text("Closer to Apple's native render")
                    .foregroundStyle(.secondary)
                    .textScale(.secondary)
            }

            MenuSection("Apps", divider: true) {
                if controller.availableApps.isEmpty {
                    MenuCommand(height: .auto, activatesApp: false, dismissesMenu: false) {
                        controller.refreshApps(restartSelected: false)
                    } label: {
                        Text("No audio apps")
                        Text("Start playback, then refresh.")
                            .foregroundStyle(.secondary)
                            .textScale(.secondary)
                    }
                } else {
                    ForEach(controller.availableApps) { app in
                        MenuToggle(
                            isOn: appSelectionBinding(for: app),
                            style: .icon(appIcon(for: app))
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(appTitle(for: app))
                                    .lineLimit(1)
                                Text(appStatus(for: app))
                                    .foregroundStyle(.secondary)
                                    .textScale(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            MenuSection(divider: true) {
                MenuCommand("Refresh Apps", activatesApp: false, dismissesMenu: false) {
                    controller.refreshApps(restartSelected: false)
                }

                MenuCommand("Quit Spacify") {
                    controller.quit()
                }
            }
        }
    }
}

@available(macOS 14.2, *)
@MainActor
private extension SpatialAudioMenuContent {
    func appSelectionBinding(for app: AudioAppTarget) -> Binding<Bool> {
        Binding {
            controller.isSelected(app)
        } set: { isSelected in
            controller.setSelected(isSelected, for: app)
        }
    }

    func appIcon(for app: AudioAppTarget) -> Image {
        AppIconCache.icon(forPath: app.appPath)
    }

    func appTitle(for app: AudioAppTarget) -> String {
        let title = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count > 30 else {
            return title
        }

        return String(title.prefix(27)) + "..."
    }

    func appStatus(for app: AudioAppTarget) -> String {
        let playbackState = app.audioActive ? "Playing" : "Idle"

        guard app.processCount > 1 else {
            return playbackState
        }

        return "\(playbackState) - \(app.processCount) processes"
    }
}

@MainActor
private enum AppIconCache {
    private static var cache: [String: Image] = [:]

    static func icon(forPath path: String?) -> Image {
        let key = path ?? ""
        if let cached = cache[key] {
            return cached
        }

        let nsImage = path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage()
        let icon = Image(nsImage: nsImage)
        cache[key] = icon
        return icon
    }
}
