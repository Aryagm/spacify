import AudioToolbox

public extension AudioStreamBasicDescription {
    var isStereoFloatPCM: Bool {
        mFormatID == kAudioFormatLinearPCM &&
            (mFormatFlags & kAudioFormatFlagIsFloat) != 0 &&
            mChannelsPerFrame == 2 &&
            mBitsPerChannel == 32
    }

    var spatialMixerFormatDescription: String {
        let formatID = String(format: "%c%c%c%c",
                              (mFormatID >> 24) & 0xff,
                              (mFormatID >> 16) & 0xff,
                              (mFormatID >> 8) & 0xff,
                              mFormatID & 0xff)
        return "\(formatID), flags=\(mFormatFlags), channels=\(mChannelsPerFrame), bits=\(mBitsPerChannel), rate=\(mSampleRate)"
    }
}
