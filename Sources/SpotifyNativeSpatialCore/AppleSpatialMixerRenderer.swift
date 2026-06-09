import AudioToolbox
import AudioUnit
import Foundation

public struct AppleSpatialMixerConfiguration {
    public var sampleRate: Float64
    public var outputDeviceKind: SpatialOutputDeviceKind
    public var maximumFrames: Int

    public init(
        sampleRate: Float64,
        outputDeviceKind: SpatialOutputDeviceKind,
        maximumFrames: Int = 16_384
    ) {
        self.sampleRate = sampleRate
        self.outputDeviceKind = outputDeviceKind
        self.maximumFrames = maximumFrames
    }
}

public final class AppleSpatialMixerRenderer {
    private let maximumFrames: Int
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private let scratchOutput: UnsafeMutableAudioBufferListPointer
    private var postProcessor: SpatialAudioPostProcessor
    private var audioUnit: AudioUnit?
    private var currentInput: UnsafePointer<AudioBufferList>?

    public init(configuration: AppleSpatialMixerConfiguration) throws {
        self.maximumFrames = configuration.maximumFrames
        self.scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: configuration.maximumFrames)
        self.scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: configuration.maximumFrames)
        self.scratchOutput = AudioBufferList.allocate(maximumBuffers: 2)
        self.postProcessor = SpatialAudioPostProcessor(sampleRate: configuration.sampleRate)

        scratchOutput[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(configuration.maximumFrames * MemoryLayout<Float>.size),
            mData: scratchLeft
        )
        scratchOutput[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(configuration.maximumFrames * MemoryLayout<Float>.size),
            mData: scratchRight
        )

        do {
            try configureAudioUnit(configuration: configuration)
        } catch {
            scratchLeft.deallocate()
            scratchRight.deallocate()
            scratchOutput.unsafeMutablePointer.deallocate()
            throw error
        }
    }

    deinit {
        if let audioUnit {
            _ = AudioUnitUninitialize(audioUnit)
            _ = AudioComponentInstanceDispose(audioUnit)
        }

        scratchLeft.deallocate()
        scratchRight.deallocate()
        scratchOutput.unsafeMutablePointer.deallocate()
    }

    public func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        timeStamp: UnsafePointer<AudioTimeStamp>
    ) {
        let inputFrames = StereoFloatBufferBridge.frameCount(
            in: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        )
        let outputFrames = StereoFloatBufferBridge.frameCount(in: UnsafeMutableAudioBufferListPointer(output))
        let frames = min(inputFrames, outputFrames, maximumFrames)

        guard frames > 0, let audioUnit else {
            StereoFloatBufferBridge.zero(output: output)
            return
        }

        let byteSize = UInt32(frames * MemoryLayout<Float>.size)
        scratchOutput[0].mDataByteSize = byteSize
        scratchOutput[1].mDataByteSize = byteSize

        currentInput = input
        defer { currentInput = nil }

        var flags = AudioUnitRenderActionFlags()
        let status = AudioUnitRender(
            audioUnit,
            &flags,
            timeStamp,
            0,
            UInt32(frames),
            scratchOutput.unsafeMutablePointer
        )

        guard status == noErr else {
            StereoFloatBufferBridge.zero(output: output)
            return
        }

        StereoFloatBufferBridge.copy(
            input: UnsafePointer(scratchOutput.unsafeMutablePointer),
            output: output,
            frames: frames
        )
        postProcessor.process(output: output, frames: frames)
    }

    public func setHeadYawRadians(_ yawRadians: Float) {
        setHeadOrientation(HeadOrientation(yawRadians: yawRadians))
    }

    public func setHeadOrientation(_ orientation: HeadOrientation) {
        guard let audioUnit else {
            return
        }

        setHeadParameter(kSpatialMixerParam_HeadYaw, degrees: orientation.yawDegrees, audioUnit: audioUnit)
        setHeadParameter(kSpatialMixerParam_HeadPitch, degrees: orientation.pitchDegrees, audioUnit: audioUnit)
        setHeadParameter(kSpatialMixerParam_HeadRoll, degrees: orientation.rollDegrees, audioUnit: audioUnit)
    }
}

private extension AppleSpatialMixerRenderer {
    func configureAudioUnit(configuration: AppleSpatialMixerConfiguration) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_SpatialMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioUnitOperationError(operation: "AudioComponentFindNext(AUSpatialMixer)", status: kAudio_ParamError)
        }

        var createdUnit: AudioUnit?
        try checkAudioUnitStatus(
            AudioComponentInstanceNew(component, &createdUnit),
            "AudioComponentInstanceNew(AUSpatialMixer)"
        )

        guard let createdUnit else {
            throw AudioUnitOperationError(operation: "AudioComponentInstanceNew(AUSpatialMixer)", status: kAudio_ParamError)
        }

        audioUnit = createdUnit

        var inputBusCount: UInt32 = 1
        try setProperty(
            kAudioUnitProperty_ElementCount,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &inputBusCount,
            operation: "AudioUnitSetProperty(input bus count)"
        )

        var maximumFrames = UInt32(configuration.maximumFrames)
        try setProperty(
            kAudioUnitProperty_MaximumFramesPerSlice,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &maximumFrames,
            operation: "AudioUnitSetProperty(maximum frames per slice)"
        )

        var streamFormat = stereoFloatNonInterleavedFormat(sampleRate: configuration.sampleRate)
        try setProperty(
            kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &streamFormat,
            operation: "AudioUnitSetProperty(input stream format)"
        )
        try setProperty(
            kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Output,
            element: 0,
            value: &streamFormat,
            operation: "AudioUnitSetProperty(output stream format)"
        )

        var stereoLayout = stereoChannelLayout()
        try setProperty(
            kAudioUnitProperty_AudioChannelLayout,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &stereoLayout,
            operation: "AudioUnitSetProperty(input channel layout)"
        )
        try setProperty(
            kAudioUnitProperty_AudioChannelLayout,
            scope: kAudioUnitScope_Output,
            element: 0,
            value: &stereoLayout,
            operation: "AudioUnitSetProperty(output channel layout)"
        )

        var callback = AURenderCallbackStruct(
            inputProc: appleSpatialMixerInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setProperty(
            kAudioUnitProperty_SetRenderCallback,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &callback,
            operation: "AudioUnitSetProperty(input render callback)"
        )

        var outputType = configuration.outputDeviceKind.audioUnitValue
        try setProperty(
            kAudioUnitProperty_SpatialMixerOutputType,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &outputType,
            operation: "AudioUnitSetProperty(spatial output type)"
        )

        var algorithm = AUSpatializationAlgorithm.spatializationAlgorithm_UseOutputType.rawValue
        try setProperty(
            kAudioUnitProperty_SpatializationAlgorithm,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &algorithm,
            operation: "AudioUnitSetProperty(spatialization algorithm)"
        )

        var sourceMode = AUSpatialMixerSourceMode.spatialMixerSourceMode_AmbienceBed.rawValue
        try setProperty(
            kAudioUnitProperty_SpatialMixerSourceMode,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &sourceMode,
            operation: "AudioUnitSetProperty(spatial source mode)"
        )

        if #available(macOS 13.0, *) {
            var hrtfMode = AUSpatialMixerPersonalizedHRTFMode.auto.rawValue
            try setProperty(
                kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode,
                scope: kAudioUnitScope_Global,
                element: 0,
                value: &hrtfMode,
                operation: "AudioUnitSetProperty(personalized HRTF mode)"
            )
        }

        try checkAudioUnitStatus(AudioUnitInitialize(createdUnit), "AudioUnitInitialize(AUSpatialMixer)")
        try configureFixedSpatialProfile()
    }

    func configureFixedSpatialProfile() throws {
        try setParameter(
            kSpatialMixerParam_Azimuth,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(fixed azimuth)"
        )
        try setParameter(
            kSpatialMixerParam_Elevation,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(fixed elevation)"
        )
        try setParameter(
            kSpatialMixerParam_PlaybackRate,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 1,
            operation: "AudioUnitSetParameter(playback rate)"
        )
        try setParameter(
            kSpatialMixerParam_ReverbBlend,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(reverb blend)"
        )
        try setParameter(
            kSpatialMixerParam_GlobalReverbGain,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: -40,
            operation: "AudioUnitSetParameter(global reverb gain)"
        )
        try setParameter(
            kSpatialMixerParam_OcclusionAttenuation,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(occlusion attenuation)"
        )
        try setParameter(
            kSpatialMixerParam_ObstructionAttenuation,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(obstruction attenuation)"
        )
        try setParameter(
            kSpatialMixerParam_HeadYaw,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(head yaw)"
        )
        try setParameter(
            kSpatialMixerParam_HeadPitch,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(head pitch)"
        )
        try setParameter(
            kSpatialMixerParam_HeadRoll,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: 0,
            operation: "AudioUnitSetParameter(head roll)"
        )
    }

    func setHeadParameter(_ parameterID: AudioUnitParameterID, degrees: Float, audioUnit: AudioUnit) {
        _ = AudioUnitSetParameter(
            audioUnit,
            parameterID,
            kAudioUnitScope_Global,
            0,
            degrees,
            0
        )
    }

    func setParameter(
        _ parameterID: AudioUnitParameterID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: AudioUnitParameterValue,
        operation: String
    ) throws {
        guard let audioUnit else {
            throw AudioUnitOperationError(operation: operation, status: kAudio_ParamError)
        }

        try checkAudioUnitStatus(
            AudioUnitSetParameter(
                audioUnit,
                parameterID,
                scope,
                element,
                value,
                0
            ),
            operation
        )
    }

    func renderInput(
        frames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let ioData else {
            return noErr
        }

        guard let currentInput else {
            StereoFloatBufferBridge.zero(output: ioData)
            return noErr
        }

        StereoFloatBufferBridge.copy(
            input: currentInput,
            output: ioData,
            frames: Int(frames)
        )
        return noErr
    }

    func setProperty<T>(
        _ property: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout T,
        operation: String
    ) throws {
        guard let audioUnit else {
            throw AudioUnitOperationError(operation: operation, status: kAudio_ParamError)
        }

        try withUnsafeBytes(of: &value) { valueBytes in
            try checkAudioUnitStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    property,
                    scope,
                    element,
                    valueBytes.baseAddress,
                    UInt32(valueBytes.count)
                ),
                operation
            )
        }
    }
}

private func appleSpatialMixerInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let renderer = Unmanaged<AppleSpatialMixerRenderer>
        .fromOpaque(inRefCon)
        .takeUnretainedValue()
    return renderer.renderInput(frames: inNumberFrames, ioData: ioData)
}

private func stereoFloatNonInterleavedFormat(sampleRate: Float64) -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian,
        mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
        mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
        mChannelsPerFrame: 2,
        mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
        mReserved: 0
    )
}

private func stereoChannelLayout() -> AudioChannelLayout {
    AudioChannelLayout(
        mChannelLayoutTag: kAudioChannelLayoutTag_Stereo,
        mChannelBitmap: AudioChannelBitmap(),
        mNumberChannelDescriptions: 0,
        mChannelDescriptions: AudioChannelDescription()
    )
}

private struct AudioUnitOperationError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed: \(status) (\(status.fourCharacterCode))"
    }
}

private func checkAudioUnitStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw AudioUnitOperationError(operation: operation, status: status)
    }
}

private extension OSStatus {
    var fourCharacterCode: String {
        let bigEndian = UInt32(bitPattern: self).bigEndian
        let bytes = [
            UInt8((bigEndian >> 24) & 0xff),
            UInt8((bigEndian >> 16) & 0xff),
            UInt8((bigEndian >> 8) & 0xff),
            UInt8(bigEndian & 0xff)
        ]

        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
            return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
        }

        return "0x" + String(UInt32(bitPattern: self), radix: 16)
    }
}
