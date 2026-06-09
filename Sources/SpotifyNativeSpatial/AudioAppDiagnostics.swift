import Foundation

@available(macOS 14.2, *)
enum AudioAppDiagnostics {
    static func listAudioApps() {
        do {
            let apps = try AudioProcessResolver.resolveApps()

            if apps.isEmpty {
                print("No CoreAudio app processes were found. Start audio in an app, then run again.")
                return
            }

            print("CoreAudio app processes:")
            for app in apps {
                let active = app.audioActive ? "active" : "idle"
                let bundle = app.bundleID ?? "no-bundle-id"
                let pids = app.processes.map(\.pid).map(String.init).joined(separator: ",")
                print("- \(app.displayName) [\(active)] \(bundle) pids=\(pids)")
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }
}
