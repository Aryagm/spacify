import Accelerate
import AudioToolbox
import Foundation

public enum StereoFloatBufferBridge {
    public static func copy(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        frames requestedFrames: Int
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let outputCapacity = frameCount(in: outputs)

        guard outputCapacity > 0 else {
            return
        }

        let inputCapacity = frameCount(in: inputs)
        let framesToCopy = min(max(0, requestedFrames), inputCapacity, outputCapacity)

        if framesToCopy > 0 {
            if !copyFastPath(input: inputs, output: outputs, frames: framesToCopy) {
                copyGeneric(input: inputs, output: outputs, frames: framesToCopy)
            }
        }

        clear(output: outputs, fromFrame: framesToCopy, toFrame: outputCapacity)
    }

    public static func zero(output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        clear(output: outputs, fromFrame: 0, toFrame: frameCount(in: outputs))
    }
}

extension StereoFloatBufferBridge {
    static func frameCount(in buffers: UnsafeMutableAudioBufferListPointer) -> Int {
        var minFrames = Int.max

        for buffer in buffers {
            let channels = max(1, Int(buffer.mNumberChannels))
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            minFrames = min(minFrames, samples / channels)
        }

        return minFrames == Int.max ? 0 : minFrames
    }

    static func clear(
        output: UnsafeMutableAudioBufferListPointer,
        fromFrame: Int,
        toFrame: Int
    ) {
        guard toFrame > fromFrame else {
            return
        }

        for buffer in output {
            guard let data = buffer.mData else {
                continue
            }

            let channels = max(1, Int(buffer.mNumberChannels))
            let startSample = fromFrame * channels
            let sampleCount = (toFrame - fromFrame) * channels
            memset(
                data.assumingMemoryBound(to: Float.self).advanced(by: startSample),
                0,
                sampleCount * MemoryLayout<Float>.size
            )
        }
    }
}

private extension StereoFloatBufferBridge {
    static func copyFastPath(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        if copyInterleavedStereoToPlanarStereo(input: input, output: output, frames: frames) {
            return true
        }

        if copyPlanarStereoToInterleavedStereo(input: input, output: output, frames: frames) {
            return true
        }

        if copyPlanarStereoToPlanarStereo(input: input, output: output, frames: frames) {
            return true
        }

        if copyInterleavedStereoToInterleavedStereo(input: input, output: output, frames: frames) {
            return true
        }

        return false
    }

    static func copyInterleavedStereoToPlanarStereo(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        guard input.count == 1,
              output.count == 2,
              input[0].mNumberChannels == 2,
              output[0].mNumberChannels == 1,
              output[1].mNumberChannels == 1,
              let inputData = input[0].mData?.assumingMemoryBound(to: Float.self),
              let leftOutput = output[0].mData?.assumingMemoryBound(to: Float.self),
              let rightOutput = output[1].mData?.assumingMemoryBound(to: Float.self) else {
            return false
        }

        var split = DSPSplitComplex(realp: leftOutput, imagp: rightOutput)
        inputData.withMemoryRebound(to: DSPComplex.self, capacity: frames) { interleaved in
            vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(frames))
        }
        return true
    }

    static func copyPlanarStereoToInterleavedStereo(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        guard input.count == 2,
              output.count == 1,
              input[0].mNumberChannels == 1,
              input[1].mNumberChannels == 1,
              output[0].mNumberChannels == 2,
              let leftInput = input[0].mData?.assumingMemoryBound(to: Float.self),
              let rightInput = input[1].mData?.assumingMemoryBound(to: Float.self),
              let outputData = output[0].mData?.assumingMemoryBound(to: Float.self) else {
            return false
        }

        var split = DSPSplitComplex(realp: leftInput, imagp: rightInput)
        outputData.withMemoryRebound(to: DSPComplex.self, capacity: frames) { interleaved in
            vDSP_ztoc(&split, 1, interleaved, 2, vDSP_Length(frames))
        }
        return true
    }

    static func copyPlanarStereoToPlanarStereo(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        guard input.count == 2,
              output.count == 2,
              input[0].mNumberChannels == 1,
              input[1].mNumberChannels == 1,
              output[0].mNumberChannels == 1,
              output[1].mNumberChannels == 1,
              let leftInput = input[0].mData,
              let rightInput = input[1].mData,
              let leftOutput = output[0].mData,
              let rightOutput = output[1].mData else {
            return false
        }

        let byteCount = frames * MemoryLayout<Float>.size
        memcpy(leftOutput, leftInput, byteCount)
        memcpy(rightOutput, rightInput, byteCount)
        return true
    }

    static func copyInterleavedStereoToInterleavedStereo(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) -> Bool {
        guard input.count == 1,
              output.count == 1,
              input[0].mNumberChannels == 2,
              output[0].mNumberChannels == 2,
              let inputData = input[0].mData,
              let outputData = output[0].mData else {
            return false
        }

        memcpy(outputData, inputData, frames * 2 * MemoryLayout<Float>.size)
        return true
    }

    static func copyGeneric(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        frames: Int
    ) {
        for frame in 0..<frames {
            write(output, frame: frame, left: sample(from: input, frame: frame, channel: 0), right: sample(from: input, frame: frame, channel: 1))
        }
    }

    static func sample(from buffers: UnsafeMutableAudioBufferListPointer, frame: Int, channel: Int) -> Float {
        var channelBase = 0

        for buffer in buffers {
            let channels = max(1, Int(buffer.mNumberChannels))
            defer { channelBase += channels }

            guard channel >= channelBase && channel < channelBase + channels else {
                continue
            }

            guard let data = buffer.mData else {
                return 0
            }

            return data.assumingMemoryBound(to: Float.self)[frame * channels + (channel - channelBase)]
        }

        return 0
    }

    static func write(_ buffers: UnsafeMutableAudioBufferListPointer, frame: Int, left: Float, right: Float) {
        var channelBase = 0

        for buffer in buffers {
            let channels = max(1, Int(buffer.mNumberChannels))
            guard let data = buffer.mData else {
                channelBase += channels
                continue
            }

            let samples = data.assumingMemoryBound(to: Float.self)
            let base = frame * channels
            for localChannel in 0..<channels {
                switch channelBase + localChannel {
                case 0:
                    samples[base + localChannel] = left
                case 1:
                    samples[base + localChannel] = right
                default:
                    samples[base + localChannel] = 0
                }
            }

            channelBase += channels
        }
    }
}
