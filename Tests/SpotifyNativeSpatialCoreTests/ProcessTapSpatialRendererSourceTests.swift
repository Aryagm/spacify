import Foundation
import Testing

@Suite("Process tap renderer source")
struct ProcessTapSpatialRendererSourceTests {
    @Test("does not mutate native head tracking on a running renderer")
    func doesNotMutateNativeHeadTrackingOnRunningRenderer() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/ProcessTapSpatialRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("func setNativeHeadTrackingEnabled"))
        #expect(!source.contains("spatialMixer?.setNativeHeadTrackingEnabled"))
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
