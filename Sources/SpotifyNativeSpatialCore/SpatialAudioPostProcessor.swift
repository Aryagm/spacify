import AudioToolbox
import Foundation

public struct SpatialAudioPostProcessor {
    private let fadeInFrames: Int
    private let limiterThreshold: Float
    private let limiterCeiling: Float
    private var renderedFadeFrames = 0

    public init(
        fadeInFrames: Int = 576,
        limiterThreshold: Float = 0.98,
        limiterCeiling: Float = 0.999
    ) {
        self.fadeInFrames = max(0, fadeInFrames)
        self.limiterThreshold = max(0, min(limiterThreshold, limiterCeiling))
        self.limiterCeiling = max(0, min(limiterCeiling, 1))
    }

    public init(sampleRate: Float64) {
        let fadeFrames = Int((sampleRate * 0.012).rounded())
        self.init(fadeInFrames: fadeFrames)
    }

    public mutating func process(
        output: UnsafeMutablePointer<AudioBufferList>,
        frames requestedFrames: Int
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        let frames = min(max(0, requestedFrames), StereoFloatBufferBridge.frameCount(in: buffers))
        guard frames > 0 else {
            return
        }

        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }

            let channels = max(1, Int(buffer.mNumberChannels))
            for frame in 0..<frames {
                let fadeGain = gainForFrame(frame)
                let base = frame * channels

                for channel in 0..<channels {
                    let index = base + channel
                    data[index] = Self.processSample(
                        data[index],
                        fadeGain: fadeGain,
                        limiterThreshold: limiterThreshold,
                        limiterCeiling: limiterCeiling
                    )
                }
            }
        }

        renderedFadeFrames = min(fadeInFrames, renderedFadeFrames + frames)
    }

    static func processSample(
        _ sample: Float,
        fadeGain: Float,
        limiterThreshold: Float,
        limiterCeiling: Float
    ) -> Float {
        guard sample.isFinite else {
            return 0
        }

        return softLimit(
            sample * fadeGain,
            threshold: limiterThreshold,
            ceiling: limiterCeiling
        )
    }

    private func gainForFrame(_ frame: Int) -> Float {
        guard fadeInFrames > 0, renderedFadeFrames < fadeInFrames else {
            return 1
        }

        return Float(min(fadeInFrames, renderedFadeFrames + frame + 1)) / Float(fadeInFrames)
    }

    private static func softLimit(_ sample: Float, threshold: Float, ceiling: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > threshold else {
            return sample
        }

        let range = max(ceiling - threshold, Float.leastNonzeroMagnitude)
        let limitedMagnitude = threshold + range * tanh((magnitude - threshold) / range)
        return copysign(min(limitedMagnitude, ceiling), sample)
    }
}
