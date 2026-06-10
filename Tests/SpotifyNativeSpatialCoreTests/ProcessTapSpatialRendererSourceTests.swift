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

    @Test("does not enable aggregate drift compensation for process taps")
    func doesNotEnableAggregateDriftCompensationForProcessTaps() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatial/ProcessTapSpatialRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("kAudioSubTapDriftCompensationKey: false"))
        #expect(!source.contains("kAudioSubTapDriftCompensationKey: true"))
    }
}
