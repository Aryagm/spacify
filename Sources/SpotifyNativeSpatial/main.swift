import AppKit
import Foundation
import MacControlCenterUI
import SwiftUI

struct Options {
    var listOnly = false
    var renderSpotify = false
    var headTracking: Bool?
}

let options = parseOptions()

if #available(macOS 14.2, *) {
    MainActor.assumeIsolated {
        run(options: options)
    }
} else {
    fputs("Spacify requires macOS 14.2 or newer for Core Audio Process Taps.\n", stderr)
    exit(1)
}

@available(macOS 14.2, *)
@MainActor
func run(options: Options) {
    if options.listOnly {
        AudioAppDiagnostics.listAudioApps()
        exit(0)
    }

    if options.renderSpotify {
        SpotifyDiagnosticRunner.run(headTrackingEnabled: options.headTracking ?? false)
        return
    }

    SpacifyLaunch.options = options
    SpacifyMenuBarApp.main()
}

@available(macOS 14.2, *)
@MainActor
private enum SpacifyLaunch {
    static var options = Options()
}

@available(macOS 14.2, *)
private struct SpacifyMenuBarApp: App {
    @NSApplicationDelegateAdaptor(SpacifyAppDelegate.self) private var appDelegate
    @StateObject private var controller: SpatialAudioMenuBarController
    @State private var isMenuPresented = false

    @MainActor
    init() {
        let controller = SpatialAudioMenuBarController(
            headTrackingEnabled: SpacifyLaunch.options.headTracking
        )
        _controller = StateObject(wrappedValue: controller)
        SpacifyAppDelegate.controller = controller
    }

    var body: some Scene {
        MenuBarExtra("Spacify", systemImage: controller.statusSymbolName) {
            SpatialAudioMenuContent(controller: controller, isMenuPresented: $isMenuPresented)
                .onAppear {
                    controller.refreshApps(restartSelected: false)
                }
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented)
        .menuBarExtraStyle(.window)
    }
}

@available(macOS 14.2, *)
@MainActor
private final class SpacifyAppDelegate: NSObject, NSApplicationDelegate {
    static weak var controller: SpatialAudioMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.controller?.restoreRoutingAtLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.controller?.shutdown()
    }
}

func parseOptions() -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--list":
            options.listOnly = true
        case "--render-spotify", "--spotify":
            options.renderSpotify = true
        case "--head-tracking":
            options.headTracking = true
        case "--no-head-tracking":
            options.headTracking = false
        case "--help", "-h":
            print("""
            Usage:
              Spacify [--list] [--render-spotify] [--head-tracking]

            With no arguments, launches the menu bar app.
            --head-tracking asks Apple's AUSpatialMixer to use native AirPods head tracking.
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
