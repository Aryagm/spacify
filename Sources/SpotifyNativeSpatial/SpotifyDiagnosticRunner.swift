import Foundation

@available(macOS 14.2, *)
@MainActor
enum SpotifyDiagnosticRunner {
    private static var signalSources: [DispatchSourceSignal] = []

    static func run(headTrackingEnabled: Bool) {
        do {
            let processes = try AudioProcessResolver.resolveSpotify()

            if processes.isEmpty {
                print("Spotify was not found in CoreAudio's process list. Start Spotify and play audio, then run again.")
                exit(1)
            }

            print("Spotify CoreAudio processes:")
            for process in processes {
                let active = process.audioActive ? "active" : "idle"
                let bundle = process.bundleID ?? "no-bundle-id"
                print("- pid \(process.pid) \(process.name) [\(active)] \(bundle)")
            }

            let activeProcesses = processes.filter(\.audioActive)
            let targetProcesses = activeProcesses.isEmpty ? processes : activeProcesses
            let renderer = ProcessTapSpatialRenderer(
                processes: targetProcesses,
                headTrackingEnabled: headTrackingEnabled
            )

            try renderer.start()
            print("Tap is running. Press Ctrl-C to stop.")

            installSignalHandlers(renderer: renderer)
            RunLoop.main.run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func installSignalHandlers(renderer: ProcessTapSpatialRenderer) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let stop: () -> Void = {
            renderer.stop()
            print("\nStopped.")
            exit(0)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler(handler: stop)
        sigint.resume()

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler(handler: stop)
        sigterm.resume()

        signalSources = [sigint, sigterm]
    }
}
