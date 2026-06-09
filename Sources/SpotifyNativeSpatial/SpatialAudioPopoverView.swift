import AppKit
import SwiftUI

@available(macOS 14.2, *)
struct SpatialAudioPopoverView: View {
    @ObservedObject var controller: SpatialAudioMenuBarController

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            controls

            Divider()

            appList

            Divider()

            footer
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }
}

@available(macOS 14.2, *)
private extension SpatialAudioPopoverView {
    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.selectedAppKeys.isEmpty ? "waveform.circle" : "waveform.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("Spatial Audio Router")
                    .font(.headline)
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(16)
    }

    var controls: some View {
        VStack(spacing: 12) {
            Toggle("Head Tracking", isOn: $controller.headTrackingEnabled)
                .toggleStyle(.switch)

            HStack(spacing: 8) {
                Button {
                    controller.refreshApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    controller.stopAll()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(controller.selectedAppKeys.isEmpty)

                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }

    @ViewBuilder
    var appList: some View {
        if controller.availableApps.isEmpty {
            ContentUnavailableView(
                "No Apps Found",
                systemImage: "speaker.slash",
                description: Text("Start audio in an app, then refresh.")
            )
            .frame(height: 220)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(controller.availableApps) { app in
                        appRow(app)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 340)
        }
    }

    func appRow(_ app: AudioAppTarget) -> some View {
        Toggle(isOn: Binding(
            get: { controller.isSelected(app) },
            set: { controller.setSelected($0, for: app) }
        )) {
            HStack(spacing: 10) {
                appIcon(for: app)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.body)
                        .lineLimit(1)

                    Text(appSubtitle(app))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if controller.isSelected(app) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }
        }
    }

    func appIcon(for app: AudioAppTarget) -> some View {
        Group {
            if let appPath = app.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    func appSubtitle(_ app: AudioAppTarget) -> String {
        let activity = app.audioActive ? "Playing" : "Idle"
        if app.processCount > 1 {
            return "\(activity) - \(app.processCount) processes"
        }

        return activity
    }

    var footer: some View {
        HStack {
            Text("Process-level routing")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                controller.quit()
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
