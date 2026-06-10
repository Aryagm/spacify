import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Apple spatial mixer configuration")
struct AppleSpatialMixerConfigurationTests {
    @Test("native head tracking is opt-in")
    func nativeHeadTrackingIsOptIn() {
        let fixed = AppleSpatialMixerConfiguration(
            sampleRate: 48_000,
            outputDeviceKind: .headphones
        )
        let tracked = AppleSpatialMixerConfiguration(
            sampleRate: 48_000,
            outputDeviceKind: .headphones,
            headTrackingEnabled: true
        )

        #expect(!fixed.headTrackingEnabled)
        #expect(tracked.headTrackingEnabled)
    }
}
