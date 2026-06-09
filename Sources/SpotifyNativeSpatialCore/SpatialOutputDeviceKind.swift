import AudioToolbox
import AudioUnit
import Foundation

public enum SpatialOutputDeviceKind {
    case headphones
    case builtInSpeakers
    case externalSpeakers

    public var audioUnitValue: UInt32 {
        switch self {
        case .headphones:
            return AUSpatialMixerOutputType.spatialMixerOutputType_Headphones.rawValue
        case .builtInSpeakers:
            return AUSpatialMixerOutputType.spatialMixerOutputType_BuiltInSpeakers.rawValue
        case .externalSpeakers:
            return AUSpatialMixerOutputType.spatialMixerOutputType_ExternalSpeakers.rawValue
        }
    }

    public static func infer(deviceName: String, deviceUID: String) -> SpatialOutputDeviceKind {
        let haystack = "\(deviceName) \(deviceUID)".lowercased()

        if haystack.contains("airpods") ||
            haystack.contains("headphones") ||
            haystack.contains("headphone") ||
            haystack.contains("headset") ||
            haystack.contains("beats") ||
            haystack.contains("earbuds") ||
            haystack.contains("buds") {
            return .headphones
        }

        if haystack.contains("builtinspeaker") ||
            haystack.contains("built-in speaker") ||
            haystack.contains("built in speaker") ||
            haystack.contains("macbook") {
            return .builtInSpeakers
        }

        return .externalSpeakers
    }
}
