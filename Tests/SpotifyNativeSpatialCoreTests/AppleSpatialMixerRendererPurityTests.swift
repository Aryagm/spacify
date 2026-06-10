import Foundation
import Testing

@Suite("Apple spatial mixer render path")
struct AppleSpatialMixerRendererPurityTests {
    @Test("does not post-process Apple's spatial mixer output")
    func doesNotPostProcessSpatialMixerOutput() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/SpotifyNativeSpatialCore/AppleSpatialMixerRenderer.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("SpatialAudioPostProcessor"))
        #expect(!source.contains("postProcessor"))
        #expect(!source.contains("CoreMotion"))
        #expect(!source.contains("CMHeadphoneMotionManager"))
        #expect(!source.contains("setHeadOrientation"))
        #expect(!source.contains("kSpatialMixerParam_HeadYaw"))
        #expect(!source.contains("kSpatialMixerParam_HeadPitch"))
        #expect(!source.contains("kSpatialMixerParam_HeadRoll"))
        #expect(source.contains("kAudioUnitProperty_SpatialMixerEnableHeadTracking"))
    }
}
