import AppKit
import Foundation

struct Options {
    var listOnly = false
    var headTracking = false
    var renderSpotify = false
}

let options = parseOptions()
var retainedMenuBarController: AnyObject?

if #available(macOS 14.2, *) {
    MainActor.assumeIsolated {
        run(options: options)
    }
} else {
    fputs("SpotifyNativeSpatial requires macOS 14.2 or newer for Core Audio Process Taps.\n", stderr)
    exit(1)
}

@available(macOS 14.2, *)
@MainActor
func run(options: Options) {
    if options.listOnly {
        AudioAppDiagnostics.listAudioApps()
        exit(0)
    }

    if !options.renderSpotify {
        runMenuBarApp(options: options)
        return
    }

    SpotifyDiagnosticRunner.run(headTrackingEnabled: options.headTracking)
}

@available(macOS 14.2, *)
@MainActor
func runMenuBarApp(options: Options) {
    let app = NSApplication.shared
    let delegate = SpatialAudioMenuBarController(headTrackingEnabled: options.headTracking)
    retainedMenuBarController = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

func parseOptions() -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--list":
            options.listOnly = true
        case "--no-head-tracking":
            options.headTracking = false
        case "--head-tracking":
            options.headTracking = true
        case "--render-spotify", "--spotify":
            options.renderSpotify = true
        case "--help", "-h":
            print("""
            Usage:
              SpotifyNativeSpatial [--list] [--head-tracking] [--render-spotify]

            With no arguments, launches the menu bar app.
            --head-tracking uses CoreMotion headphone motion to drive the spatial mixer's head pose.
            --render-spotify runs the previous terminal Spotify-only renderer for diagnostics.
            Run from the app bundle produced by `make app` for macOS audio-capture permission prompts.
            """)
            exit(0)
        default:
            fputs("Unknown option: \(argument)\n", stderr)
            exit(2)
        }
    }

    return options
}
