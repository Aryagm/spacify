import Foundation
import Testing

@Suite("Process tap renderer source")
struct ProcessTapSpatialRendererSourceTests {
    @Test("applies head tracking to the live mixer without rebuilding the route")
    func appliesHeadTrackingToTheLiveMixer() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/ProcessTapSpatialRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // Rebuilding the route for a head-tracking change tears down and
        // recreates the tap, which is audible; the property toggles live.
        #expect(source.contains("func setHeadTrackingEnabled"))
        #expect(source.contains("spatialMixer.setHeadTrackingEnabled"))
    }

    @Test("rate-matches the tap to the aggregate clock")
    func rateMatchesTheTapToTheAggregateClock() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/ProcessTapSpatialRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // The aggregate is clocked by the output device; the tap stream must
        // be drift-compensated to that clock or apps producing at a different
        // sample rate play pitch-shifted.
        #expect(source.contains("kAudioSubTapDriftCompensationKey: true"))
        #expect(!source.contains("kAudioSubTapDriftCompensationKey: false"))
    }
}
