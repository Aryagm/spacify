import AudioToolbox
import AudioUnit
import Foundation

public struct AppleSpatialMixerConfiguration {
    public var sampleRate: Float64
    public var outputDeviceKind: SpatialOutputDeviceKind
    public var maximumFrames: Int
    public var headTrackingEnabled: Bool

    public init(
        sampleRate: Float64,
        outputDeviceKind: SpatialOutputDeviceKind,
        maximumFrames: Int = 16_384,
        headTrackingEnabled: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.outputDeviceKind = outputDeviceKind
        self.maximumFrames = maximumFrames
        self.headTrackingEnabled = headTrackingEnabled
    }
}

public final class AppleSpatialMixerRenderer {
    private let maximumFrames: Int
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private let scratchOutput: UnsafeMutableAudioBufferListPointer
    private var audioUnit: AudioUnit?
    private var currentInput: UnsafePointer<AudioBufferList>?

    public init(configuration: AppleSpatialMixerConfiguration) throws {
        self.maximumFrames = configuration.maximumFrames
        self.scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: configuration.maximumFrames)
        self.scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: configuration.maximumFrames)
        self.scratchOutput = AudioBufferList.allocate(maximumBuffers: 2)

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
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let outputFrames = StereoFloatBufferBridge.frameCount(in: outputs)
        let frames = min(inputFrames, outputFrames, maximumFrames)

        guard frames > 0, let audioUnit else {
            StereoFloatBufferBridge.zero(output: output)
            return
        }

        // When the device buffers already use the mixer's planar stereo float
        // layout, let the mixer render straight into them; otherwise render
        // into scratch and bridge the layout afterwards.
        let renderDirectlyIntoOutput = outputs.count == 2
            && outputs[0].mNumberChannels == 1
            && outputs[1].mNumberChannels == 1
            && outputs[0].mData != nil
            && outputs[1].mData != nil

        let byteSize = UInt32(frames * MemoryLayout<Float>.size)
        scratchOutput[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: byteSize,
            mData: renderDirectlyIntoOutput ? outputs[0].mData : UnsafeMutableRawPointer(scratchLeft)
        )
        scratchOutput[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: byteSize,
            mData: renderDirectlyIntoOutput ? outputs[1].mData : UnsafeMutableRawPointer(scratchRight)
        )

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

        if renderDirectlyIntoOutput {
            StereoFloatBufferBridge.clear(output: outputs, fromFrame: frames, toFrame: outputFrames)
        } else {
            StereoFloatBufferBridge.copy(
                input: UnsafePointer(scratchOutput.unsafeMutablePointer),
                output: output,
                frames: frames
            )
        }
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

        try configureNativeHeadTracking(configuration.headTrackingEnabled)

        let profile = FixedSpatialAudioProfile.music

        var algorithm = profile.spatializationAlgorithm
        try setProperty(
            kAudioUnitProperty_SpatializationAlgorithm,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &algorithm,
            operation: "AudioUnitSetProperty(spatialization algorithm)"
        )

        var sourceMode = profile.sourceMode
        try setProperty(
            kAudioUnitProperty_SpatialMixerSourceMode,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &sourceMode,
            operation: "AudioUnitSetProperty(spatial source mode)"
        )

        if #available(macOS 13.0, *) {
            var hrtfMode = profile.personalizedHRTFMode
            try setProperty(
                kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode,
                scope: kAudioUnitScope_Global,
                element: 0,
                value: &hrtfMode,
                operation: "AudioUnitSetProperty(personalized HRTF mode)"
            )
        }

        try checkAudioUnitStatus(AudioUnitInitialize(createdUnit), "AudioUnitInitialize(AUSpatialMixer)")
        try configureFixedSpatialProfile(profile)
    }

    func configureFixedSpatialProfile(_ profile: FixedSpatialAudioProfile) throws {
        for setting in profile.parameterSettings {
            try setParameter(
                setting.parameterID,
                scope: setting.scope,
                element: setting.element,
                value: setting.value,
                operation: "AudioUnitSetParameter(fixed spatial profile)"
            )
        }
    }

    func configureNativeHeadTracking(_ enabled: Bool) throws {
        var value: UInt32 = enabled ? 1 : 0
        try setProperty(
            kAudioUnitProperty_SpatialMixerEnableHeadTracking,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &value,
            operation: "AudioUnitSetProperty(native head tracking)"
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

        // Zero-copy: when the tap already delivers planar stereo float, hand
        // the tap buffers to the mixer instead of copying them.
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: currentInput))
        let pulls = UnsafeMutableAudioBufferListPointer(ioData)
        let byteSize = UInt32(Int(frames) * MemoryLayout<Float>.size)
        if inputs.count == 2,
           pulls.count == 2,
           inputs[0].mNumberChannels == 1,
           inputs[1].mNumberChannels == 1,
           inputs[0].mDataByteSize >= byteSize,
           inputs[1].mDataByteSize >= byteSize,
           let left = inputs[0].mData,
           let right = inputs[1].mData {
            pulls[0].mData = left
            pulls[1].mData = right
            pulls[0].mDataByteSize = byteSize
            pulls[1].mDataByteSize = byteSize
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
