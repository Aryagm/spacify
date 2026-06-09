import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Spatial output device selection")
struct SpatialOutputDeviceKindTests {
    @Test("AirPods are rendered with the headphone spatial profile")
    func airPodsUseHeadphones() {
        #expect(SpatialOutputDeviceKind.infer(deviceName: "Arya's AirPods Pro", deviceUID: "Bluetooth-AACP").audioUnitValue == SpatialOutputDeviceKind.headphones.audioUnitValue)
    }

    @Test("Built-in Mac speakers use the speaker spatial profile")
    func macBookSpeakersUseBuiltInSpeakers() {
        #expect(SpatialOutputDeviceKind.infer(deviceName: "MacBook Pro Speakers", deviceUID: "BuiltInSpeakerDevice").audioUnitValue == SpatialOutputDeviceKind.builtInSpeakers.audioUnitValue)
    }

    @Test("Unknown outputs default to external speakers")
    func unknownOutputUsesExternalSpeakers() {
        #expect(SpatialOutputDeviceKind.infer(deviceName: "Studio Display", deviceUID: "AppleDisplayAudio").audioUnitValue == SpatialOutputDeviceKind.externalSpeakers.audioUnitValue)
    }
}
