import AudioToolbox
import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Spatial mixer stream format")
struct AudioStreamBasicDescriptionSpatialMixerTests {
    @Test("accepts stereo float PCM")
    func acceptsStereoFloatPCM() {
        let format = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        #expect(format.isStereoFloatPCM)
    }

    @Test("rejects non-float and non-stereo formats")
    func rejectsUnsupportedFormats() {
        let int16Stereo = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var floatMono = int16Stereo
        floatMono.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian
        floatMono.mBytesPerPacket = 4
        floatMono.mBytesPerFrame = 4
        floatMono.mChannelsPerFrame = 1
        floatMono.mBitsPerChannel = 32

        #expect(!int16Stereo.isStereoFloatPCM)
        #expect(!floatMono.isStereoFloatPCM)
    }
}
