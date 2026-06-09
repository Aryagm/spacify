import AudioToolbox
import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Spatial audio post processor")
struct SpatialAudioPostProcessorTests {
    @Test("leaves normal samples unchanged when fade is disabled")
    func leavesNormalSamplesUnchanged() {
        var processor = SpatialAudioPostProcessor(fadeInFrames: 0)
        var samples: [Float] = [-0.75, 0.5, 0.25, -0.125]
        let byteSize = UInt32(samples.count * MemoryLayout<Float>.size)

        samples.withUnsafeMutableBufferPointer { pointer in
            let outputList = audioBufferList([
                AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: byteSize,
                    mData: pointer.baseAddress
                )
            ])
            defer { outputList.unsafeMutablePointer.deallocate() }

            processor.process(output: outputList.unsafeMutablePointer, frames: 2)
        }

        #expect(samples == [-0.75, 0.5, 0.25, -0.125])
    }

    @Test("soft limits overrange and removes non-finite samples")
    func softLimitsOverrangeAndRemovesNonFiniteSamples() {
        var processor = SpatialAudioPostProcessor(fadeInFrames: 0)
        var samples: [Float] = [1.5, -2.0, .nan, .infinity]
        let byteSize = UInt32(samples.count * MemoryLayout<Float>.size)

        samples.withUnsafeMutableBufferPointer { pointer in
            let outputList = audioBufferList([
                AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: byteSize,
                    mData: pointer.baseAddress
                )
            ])
            defer { outputList.unsafeMutablePointer.deallocate() }

            processor.process(output: outputList.unsafeMutablePointer, frames: 2)
        }

        #expect(samples[0] <= 0.999)
        #expect(samples[0] > 0.98)
        #expect(samples[1] >= -0.999)
        #expect(samples[1] < -0.98)
        #expect(samples[2] == 0)
        #expect(samples[3] == 0)
    }

    @Test("continues fade in across render calls")
    func continuesFadeInAcrossRenderCalls() {
        var processor = SpatialAudioPostProcessor(
            fadeInFrames: 4,
            limiterThreshold: 1,
            limiterCeiling: 1
        )
        var first: [Float] = [1, 1, 1, 1]
        var second: [Float] = [1, 1, 1, 1]

        process(&first, with: &processor)
        process(&second, with: &processor)

        #expect(first == [0.25, 0.25, 0.5, 0.5])
        #expect(second == [0.75, 0.75, 1, 1])
    }

    private func process(_ samples: inout [Float], with processor: inout SpatialAudioPostProcessor) {
        let byteSize = UInt32(samples.count * MemoryLayout<Float>.size)

        samples.withUnsafeMutableBufferPointer { pointer in
            let outputList = audioBufferList([
                AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: byteSize,
                    mData: pointer.baseAddress
                )
            ])
            defer { outputList.unsafeMutablePointer.deallocate() }

            processor.process(output: outputList.unsafeMutablePointer, frames: 2)
        }
    }

    private func audioBufferList(_ buffers: [AudioBuffer]) -> UnsafeMutableAudioBufferListPointer {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for index in buffers.indices {
            list[index] = buffers[index]
        }
        return list
    }
}
