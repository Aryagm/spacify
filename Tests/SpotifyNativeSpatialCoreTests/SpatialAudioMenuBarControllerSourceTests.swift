import Foundation
import Testing

@Suite("Spatial audio menu controller source")
struct SpatialAudioMenuBarControllerSourceTests {
    @Test("debounces route rebuilds instead of mutating the running mixer")
    func debouncesRouteRebuildsInsteadOfMutatingRunningMixer() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("scheduleRendererRestart"))
        #expect(source.contains("DispatchWorkItem"))
        #expect(!source.contains("setNativeHeadTrackingEnabled"))
    }

    @Test("head tracking changes apply live with a restart fallback")
    func headTrackingChangesApplyLiveWithRestartFallback() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("try renderer.setHeadTrackingEnabled(headTrackingEnabled)"))
        #expect(source.contains("activeHeadTrackingEnabled"))
        #expect(source.contains("headTrackingChangePending"))
        #expect(!source.contains("""
            guard oldValue != headTrackingEnabled else {
                return
            }
            scheduleRendererRestart()
        """))
    }

    @Test("pending head tracking can be applied with an explicit route restart")
    func pendingHeadTrackingCanBeAppliedWithExplicitRouteRestart() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("func restartRoutingToApplyHeadTracking()"))
        #expect(source.contains("restartRenderer(applyHeadTrackingPreference: true)"))
        #expect(source.contains("func restartRenderer(applyHeadTrackingPreference: Bool = false)"))
    }

    @Test("pending head tracking shows a restart menu item")
    func pendingHeadTrackingShowsRestartMenuItem() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuContent.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("if controller.headTrackingChangePending"))
        #expect(source.contains("controller.restartRoutingToApplyHeadTracking()"))
        #expect(source.contains("Restart Routing"))
    }

    @Test("route replacement stops the previous renderer before starting")
    func routeReplacementStopsPreviousRendererBeforeStarting() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("let previousRenderer = renderer"))
        #expect(source.contains("previousRenderer?.stop()"))

        // A second tap on already-tapped processes captures silence, so the
        // old route must be torn down before the replacement starts.
        let startIndex = try #require(source.range(of: "try nextRenderer.start()")?.lowerBound)
        let stopIndex = try #require(source.range(of: "previousRenderer?.stop()", options: .backwards)?.lowerBound)
        #expect(stopIndex < startIndex)
    }

    @Test("failed route replacement keeps the current selection")
    func failedRouteReplacementKeepsCurrentSelection() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("if previousRenderer == nil"))
        #expect(source.contains("selectedAppKeys.removeAll()"))
        #expect(source.contains("statusMessage = previousRenderer == nil ? \"Start failed\" : \"Restart failed\""))
    }

    @Test("menu bar UI uses the Control Center package")
    func menuBarUIUsesControlCenterPackage() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let packageURL = rootURL
            .appending(path: "Package.swift")
        let appSourceURL = rootURL
            .appending(path: "Sources/SpotifyNativeSpatial/main.swift")
        let contentSourceURL = rootURL
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuContent.swift")
        let controllerSourceURL = rootURL
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuBarController.swift")
        let packageSource = try String(contentsOf: packageURL, encoding: .utf8)
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let contentSource = try String(contentsOf: contentSourceURL, encoding: .utf8)
        let controllerSource = try String(contentsOf: controllerSourceURL, encoding: .utf8)

        #expect(packageSource.contains(".package(url: \"https://github.com/orchetect/MacControlCenterUI\", from: \"2.7.0\")"))
        #expect(packageSource.contains(".product(name: \"MacControlCenterUI\", package: \"MacControlCenterUI\")"))
        #expect(appSource.contains("import MacControlCenterUI"))
        #expect(appSource.contains("SpacifyMenuBarApp.main()"))
        #expect(appSource.contains("MenuBarExtra {"))
        #expect(appSource.contains("Image(nsImage: controller.menuBarIcon)"))
        #expect(appSource.contains("@State private var isMenuPresented = false"))
        #expect(appSource.contains(".menuBarExtraStyle(.window)"))
        #expect(appSource.contains(".menuBarExtraAccess(isPresented: $isMenuPresented)"))
        #expect(appSource.contains("SpatialAudioMenuContent(controller: controller, isMenuPresented: $isMenuPresented)"))
        #expect(appSource.contains("controller.refreshApps(restartSelected: false)"))
        #expect(contentSource.contains("import MacControlCenterUI"))
        #expect(contentSource.contains("MacControlCenterMenu("))
        #expect(contentSource.contains("isPresented: $isMenuPresented"))
        #expect(!appSource.contains(".menuBarExtraStyle(.menu)"))
        #expect(!appSource.contains("SpatialAudioPopoverView"))
        #expect(controllerSource.contains("menuBarIcon"))
        #expect(!controllerSource.contains("NSStatusItem"))
        #expect(!controllerSource.contains("NSPopover"))
        #expect(!controllerSource.contains("NSHostingController"))
        #expect(!controllerSource.contains("togglePopover"))
    }

    @Test("menu content delegates styling to Control Center controls")
    func menuContentDelegatesStylingToControlCenterControls() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let contentSourceURL = rootURL
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuContent.swift")
        let contentSource = try String(contentsOf: contentSourceURL, encoding: .utf8)

        #expect(contentSource.contains("MacControlCenterMenu("))
        #expect(contentSource.contains("isPresented: $isMenuPresented"))
        #expect(contentSource.contains("MenuHeader(\"Head Tracking\")"))
        #expect(contentSource.contains("MenuSection(\"Apps\""))
        #expect(contentSource.contains("MenuToggle("))
        #expect(contentSource.contains("MenuCommand(\"Refresh Apps\""))
        #expect(contentSource.contains("MenuCommand(\"Quit Spacify\")"))
        #expect(!contentSource.contains("MenuScrollView"))
        #expect(!contentSource.contains("NSViewRepresentable"))
        #expect(!contentSource.contains("NSSwitch"))
        #expect(!contentSource.contains("NSStackView"))
        #expect(!contentSource.contains("NSScrollView"))
        #expect(!contentSource.contains("Form {"))
        #expect(!contentSource.contains("LabeledContent"))
        #expect(!contentSource.contains("ContentUnavailableView"))
        #expect(!contentSource.contains(".background("))
        #expect(!contentSource.contains(".buttonStyle("))
        #expect(!contentSource.contains("Text(controller.statusMessage)"))
    }

    @Test("menu content does not use SwiftUI typography or layout")
    func menuContentDoesNotUseSwiftUITypographyOrLayout() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuContent.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains(".font("))
        #expect(!source.contains(".padding("))
        #expect(!source.contains(".frame("))
    }

    @Test("app items use Control Center menu toggles")
    func appItemsUseControlCenterMenuToggles() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/SpatialAudioMenuContent.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("ForEach(controller.availableApps"))
        #expect(source.contains("appSelectionBinding(for: app)"))
        #expect(source.contains("style: .icon(appIcon(for: app))"))
        #expect(source.contains("String(title.prefix(27)) + \"...\""))
        #expect(!source.contains("ForEach(Array(apps.enumerated())"))
        #expect(!source.contains(".padding(.leading, 58)"))
        #expect(!source.contains("appIcon(for: app, isSelected:"))
        #expect(!source.contains("Circle()"))
    }
}
