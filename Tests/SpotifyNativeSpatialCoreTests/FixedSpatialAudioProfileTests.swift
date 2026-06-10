import AudioToolbox
import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Fixed spatial audio profile")
struct FixedSpatialAudioProfileTests {
    @Test("uses clean fixed music defaults")
    func usesCleanFixedMusicDefaults() {
        let profile = FixedSpatialAudioProfile.music

        #expect(profile.spatializationAlgorithm == AUSpatializationAlgorithm.spatializationAlgorithm_UseOutputType.rawValue)
        #expect(profile.sourceMode == AUSpatialMixerSourceMode.spatialMixerSourceMode_AmbienceBed.rawValue)
        #expect(profile.parameterValue(kSpatialMixerParam_PlaybackRate, scope: kAudioUnitScope_Input) == 1)
        #expect(profile.parameterValue(kSpatialMixerParam_ReverbBlend, scope: kAudioUnitScope_Input) == 0)
        #expect(profile.parameterValue(kSpatialMixerParam_GlobalReverbGain, scope: kAudioUnitScope_Global) == -40)
        #expect(profile.parameterValue(kSpatialMixerParam_HeadYaw, scope: kAudioUnitScope_Global) == nil)
        #expect(profile.parameterValue(kSpatialMixerParam_HeadPitch, scope: kAudioUnitScope_Global) == nil)
        #expect(profile.parameterValue(kSpatialMixerParam_HeadRoll, scope: kAudioUnitScope_Global) == nil)
    }
}
