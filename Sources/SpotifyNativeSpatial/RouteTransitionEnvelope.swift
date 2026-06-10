import Accelerate
import AudioToolbox
import Foundation

/// Masks route transitions: holds silence while the tap pipeline fills and
/// the rate-matcher locks, fades in, and fades out before teardown so
/// toggling a route doesn't click or warble. Steady-state audio passes
/// through untouched.
final class RouteTransitionEnvelope: @unchecked Sendable {
    private let silenceFrames: Int
    private let fadeInFrames: Int
    private let fadeOutFrames: Int

    /// Total frames rendered; only the audio thread touches it.
    private var position = 0
    /// Frame index where fade-out begins; written once by the main thread.
    private var fadeOutStart = Int.max

    let fadeOutDuration: TimeInterval = 0.1

    init(sampleRate: Double) {
        silenceFrames = Int(sampleRate * 0.15)
        fadeInFrames = Int(sampleRate * 0.25)
        fadeOutFrames = Int(sampleRate * fadeOutDuration)
    }

    /// Called from the main thread right before teardown.
    func beginFadeOut() {
        fadeOutStart = position
    }

    /// Called from the IO proc after the mixer renders.
    func apply(to output: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else {
            return
        }

        let start = position
        position += frames

        let startGain = gain(at: start)
        let endGain = gain(at: start + frames - 1)

        if startGain == 1, endGain == 1 {
            return
        }

        let buffers = UnsafeMutableAudioBufferListPointer(output)

        if startGain == 0, endGain == 0 {
            for buffer in buffers {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return
        }

        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }

            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else {
                continue
            }

            var rampStart = startGain
            var rampStep = (endGain - startGain) / Float(sampleCount)
            vDSP_vrampmul(data, 1, &rampStart, &rampStep, data, 1, vDSP_Length(sampleCount))
        }
    }

    private func gain(at frame: Int) -> Float {
        var value: Float = 1

        if frame < silenceFrames {
            value = 0
        } else if frame < silenceFrames + fadeInFrames {
            value = Float(frame - silenceFrames) / Float(fadeInFrames)
        }

        let fadeOutStart = fadeOutStart
        if frame >= fadeOutStart {
            let fadedOut = Float(frame - fadeOutStart) / Float(fadeOutFrames)
            value *= max(0, 1 - fadedOut)
        }

        return value
    }
}
