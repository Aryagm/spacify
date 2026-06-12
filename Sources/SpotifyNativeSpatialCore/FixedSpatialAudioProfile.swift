import AudioToolbox
import AudioUnit

struct FixedSpatialAudioProfile {
    static let music = FixedSpatialAudioProfile(
        spatializationAlgorithm: AUSpatializationAlgorithm.spatializationAlgorithm_UseOutputType.rawValue,
        sourceMode: AUSpatialMixerSourceMode.spatialMixerSourceMode_AmbienceBed.rawValue,
        personalizedHRTFMode: AUSpatialMixerPersonalizedHRTFMode.auto.rawValue,
        parameterSettings: [
            AudioUnitParameterSetting(kSpatialMixerParam_Azimuth, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_Elevation, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_PlaybackRate, scope: kAudioUnitScope_Input, value: 1),
            AudioUnitParameterSetting(kSpatialMixerParam_ReverbBlend, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_GlobalReverbGain, scope: kAudioUnitScope_Global, value: -40),
            AudioUnitParameterSetting(kSpatialMixerParam_OcclusionAttenuation, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_ObstructionAttenuation, scope: kAudioUnitScope_Input, value: 0)
        ]
    )

    /// Same render as `music` but with the mixer's built-in room reverb
    /// engaged, which is closer to the character of Apple's native
    /// Spatialize Stereo. Still Apple's engine end to end.
    static let roomAmbience = FixedSpatialAudioProfile(
        spatializationAlgorithm: AUSpatializationAlgorithm.spatializationAlgorithm_UseOutputType.rawValue,
        sourceMode: AUSpatialMixerSourceMode.spatialMixerSourceMode_AmbienceBed.rawValue,
        personalizedHRTFMode: AUSpatialMixerPersonalizedHRTFMode.auto.rawValue,
        parameterSettings: [
            AudioUnitParameterSetting(kSpatialMixerParam_Azimuth, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_Elevation, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_PlaybackRate, scope: kAudioUnitScope_Input, value: 1),
            AudioUnitParameterSetting(kSpatialMixerParam_ReverbBlend, scope: kAudioUnitScope_Input, value: 30),
            AudioUnitParameterSetting(kSpatialMixerParam_GlobalReverbGain, scope: kAudioUnitScope_Global, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_OcclusionAttenuation, scope: kAudioUnitScope_Input, value: 0),
            AudioUnitParameterSetting(kSpatialMixerParam_ObstructionAttenuation, scope: kAudioUnitScope_Input, value: 0)
        ]
    )

    let spatializationAlgorithm: UInt32
    let sourceMode: UInt32
    let personalizedHRTFMode: UInt32
    let parameterSettings: [AudioUnitParameterSetting]

    func parameterValue(
        _ parameterID: AudioUnitParameterID,
        scope: AudioUnitScope,
        element: AudioUnitElement = 0
    ) -> AudioUnitParameterValue? {
        parameterSettings.first {
            $0.parameterID == parameterID &&
            $0.scope == scope &&
            $0.element == element
        }?.value
    }
}

struct AudioUnitParameterSetting: Equatable {
    let parameterID: AudioUnitParameterID
    let scope: AudioUnitScope
    let element: AudioUnitElement
    let value: AudioUnitParameterValue

    init(
        _ parameterID: AudioUnitParameterID,
        scope: AudioUnitScope,
        element: AudioUnitElement = 0,
        value: AudioUnitParameterValue
    ) {
        self.parameterID = parameterID
        self.scope = scope
        self.element = element
        self.value = value
    }
}
