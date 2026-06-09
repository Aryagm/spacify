import AudioToolbox
import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Stereo float buffer bridge")
struct StereoFloatBufferBridgeTests {
    @Test("copies interleaved stereo input to planar stereo output")
    func copiesInterleavedStereoToPlanarStereo() {
        var inputSamples: [Float] = [1, 10, 2, 20, 3, 30]
        var left = [Float](repeating: -1, count: 3)
        var right = [Float](repeating: -1, count: 3)
        let inputByteSize = UInt32(inputSamples.count * MemoryLayout<Float>.size)
        let outputByteSize = UInt32(left.count * MemoryLayout<Float>.size)

        inputSamples.withUnsafeMutableBufferPointer { inputPointer in
            left.withUnsafeMutableBufferPointer { leftPointer in
                right.withUnsafeMutableBufferPointer { rightPointer in
                    let inputList = audioBufferList([
                        AudioBuffer(
                            mNumberChannels: 2,
                            mDataByteSize: inputByteSize,
                            mData: inputPointer.baseAddress
                        )
                    ])
                    let outputList = audioBufferList([
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: outputByteSize,
                            mData: leftPointer.baseAddress
                        ),
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: outputByteSize,
                            mData: rightPointer.baseAddress
                        )
                    ])
                    defer {
                        inputList.unsafeMutablePointer.deallocate()
                        outputList.unsafeMutablePointer.deallocate()
                    }

                    StereoFloatBufferBridge.copy(
                        input: UnsafePointer(inputList.unsafeMutablePointer),
                        output: outputList.unsafeMutablePointer,
                        frames: 3
                    )
                }
            }
        }

        #expect(left == [1, 2, 3])
        #expect(right == [10, 20, 30])
    }

    @Test("clears extra output channels")
    func clearsExtraOutputChannels() {
        var leftIn: [Float] = [1, 2]
        var rightIn: [Float] = [10, 20]
        var leftOut = [Float](repeating: -1, count: 2)
        var rightOut = [Float](repeating: -1, count: 2)
        var centerOut = [Float](repeating: -1, count: 2)
        let inputByteSize = UInt32(leftIn.count * MemoryLayout<Float>.size)
        let outputByteSize = UInt32(leftOut.count * MemoryLayout<Float>.size)

        leftIn.withUnsafeMutableBufferPointer { leftInPointer in
            rightIn.withUnsafeMutableBufferPointer { rightInPointer in
                leftOut.withUnsafeMutableBufferPointer { leftOutPointer in
                    rightOut.withUnsafeMutableBufferPointer { rightOutPointer in
                        centerOut.withUnsafeMutableBufferPointer { centerOutPointer in
                            let inputList = audioBufferList([
                                AudioBuffer(
                                    mNumberChannels: 1,
                                    mDataByteSize: inputByteSize,
                                    mData: leftInPointer.baseAddress
                                ),
                                AudioBuffer(
                                    mNumberChannels: 1,
                                    mDataByteSize: inputByteSize,
                                    mData: rightInPointer.baseAddress
                                )
                            ])
                            let outputList = audioBufferList([
                                AudioBuffer(
                                    mNumberChannels: 1,
                                    mDataByteSize: outputByteSize,
                                    mData: leftOutPointer.baseAddress
                                ),
                                AudioBuffer(
                                    mNumberChannels: 1,
                                    mDataByteSize: outputByteSize,
                                    mData: rightOutPointer.baseAddress
                                ),
                                AudioBuffer(
                                    mNumberChannels: 1,
                                    mDataByteSize: outputByteSize,
                                    mData: centerOutPointer.baseAddress
                                )
                            ])
                            defer {
                                inputList.unsafeMutablePointer.deallocate()
                                outputList.unsafeMutablePointer.deallocate()
                            }

                            StereoFloatBufferBridge.copy(
                                input: UnsafePointer(inputList.unsafeMutablePointer),
                                output: outputList.unsafeMutablePointer,
                                frames: 2
                            )
                        }
                    }
                }
            }
        }

        #expect(leftOut == [1, 2])
        #expect(rightOut == [10, 20])
        #expect(centerOut == [0, 0])
    }

    @Test("copies planar stereo input to interleaved stereo output")
    func copiesPlanarStereoToInterleavedStereo() {
        var leftIn: [Float] = [1, 2, 3]
        var rightIn: [Float] = [10, 20, 30]
        var output = [Float](repeating: -1, count: 6)
        let inputByteSize = UInt32(leftIn.count * MemoryLayout<Float>.size)
        let outputByteSize = UInt32(output.count * MemoryLayout<Float>.size)

        leftIn.withUnsafeMutableBufferPointer { leftInPointer in
            rightIn.withUnsafeMutableBufferPointer { rightInPointer in
                output.withUnsafeMutableBufferPointer { outputPointer in
                    let inputList = audioBufferList([
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: inputByteSize,
                            mData: leftInPointer.baseAddress
                        ),
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: inputByteSize,
                            mData: rightInPointer.baseAddress
                        )
                    ])
                    let outputList = audioBufferList([
                        AudioBuffer(
                            mNumberChannels: 2,
                            mDataByteSize: outputByteSize,
                            mData: outputPointer.baseAddress
                        )
                    ])
                    defer {
                        inputList.unsafeMutablePointer.deallocate()
                        outputList.unsafeMutablePointer.deallocate()
                    }

                    StereoFloatBufferBridge.copy(
                        input: UnsafePointer(inputList.unsafeMutablePointer),
                        output: outputList.unsafeMutablePointer,
                        frames: 3
                    )
                }
            }
        }

        #expect(output == [1, 10, 2, 20, 3, 30])
    }

    @Test("clears output tail beyond requested frames")
    func clearsOutputTailBeyondRequestedFrames() {
        var inputSamples: [Float] = [1, 10, 2, 20]
        var output = [Float](repeating: -1, count: 6)
        let inputByteSize = UInt32(inputSamples.count * MemoryLayout<Float>.size)
        let outputByteSize = UInt32(output.count * MemoryLayout<Float>.size)

        inputSamples.withUnsafeMutableBufferPointer { inputPointer in
            output.withUnsafeMutableBufferPointer { outputPointer in
                let inputList = audioBufferList([
                    AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: inputByteSize,
                        mData: inputPointer.baseAddress
                    )
                ])
                let outputList = audioBufferList([
                    AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: outputByteSize,
                        mData: outputPointer.baseAddress
                    )
                ])
                defer {
                    inputList.unsafeMutablePointer.deallocate()
                    outputList.unsafeMutablePointer.deallocate()
                }

                StereoFloatBufferBridge.copy(
                    input: UnsafePointer(inputList.unsafeMutablePointer),
                    output: outputList.unsafeMutablePointer,
                    frames: 2
                )
            }
        }

        #expect(output == [1, 10, 2, 20, 0, 0])
    }

    private func audioBufferList(_ buffers: [AudioBuffer]) -> UnsafeMutableAudioBufferListPointer {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for index in buffers.indices {
            list[index] = buffers[index]
        }
        return list
    }
}
