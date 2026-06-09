import AudioToolbox
import Foundation

struct AudioHardwareError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed: \(status) (\(status.fourCharacterCode))"
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
}

extension OSStatus {
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

@inline(__always)
func checkOSStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw AudioHardwareError(operation: operation, status: status)
    }
}
