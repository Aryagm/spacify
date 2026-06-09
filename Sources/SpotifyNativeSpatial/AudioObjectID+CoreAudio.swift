import AudioToolbox
import Foundation

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != .unknown }

    static func readProcessList() throws -> [AudioObjectID] {
        try system.requireSystemObject()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        try checkOSStatus(
            AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize),
            "AudioObjectGetPropertyDataSize(process list)"
        )

        var value = [AudioObjectID](repeating: .unknown, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        try checkOSStatus(
            AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &value),
            "AudioObjectGetPropertyData(process list)"
        )

        return value
    }

    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try system.translatePIDToProcessObjectID(pid: pid)
    }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try system.read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try requireSystemObject()
        let processObject = try read(
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID.unknown,
            qualifier: pid
        )

        guard processObject.isValid else {
            throw "No CoreAudio process object for pid \(pid)."
        }

        return processObject
    }

    func readProcessPID() throws -> pid_t {
        try read(kAudioProcessPropertyPID, defaultValue: pid_t(-1))
    }

    func readProcessBundleID() -> String? {
        guard let value = try? readString(kAudioProcessPropertyBundleID), !value.isEmpty else {
            return nil
        }

        return value
    }

    func readProcessIsRunning() -> Bool {
        (try? readBool(kAudioProcessPropertyIsRunning)) ?? false
    }

    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }

    func readDeviceName() throws -> String {
        try readString(kAudioDevicePropertyDeviceNameCFString)
    }

    func readNominalSampleRate() throws -> Float64 {
        try read(kAudioDevicePropertyNominalSampleRate, defaultValue: Float64(0))
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    private func requireSystemObject() throws {
        guard self == .system else {
            throw "This CoreAudio property is only available on the system object."
        }
    }
}

extension AudioObjectID {
    func read<T, Q>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T,
        qualifier: Q
    ) throws -> T {
        var qualifier = qualifier
        return try withUnsafeMutablePointer(to: &qualifier) { pointer in
            try read(
                AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
                defaultValue: defaultValue,
                qualifierSize: UInt32(MemoryLayout<Q>.size),
                qualifierData: pointer
            )
        }
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        try read(
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
            defaultValue: defaultValue
        )
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        try read(
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
            defaultValue: "" as CFString
        ) as String
    }

    func readBool(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> Bool {
        let value: UInt32 = try read(
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
            defaultValue: UInt32(0)
        )

        return value != 0
    }

    private func read<T>(
        _ address: AudioObjectPropertyAddress,
        defaultValue: T,
        qualifierSize: UInt32 = 0,
        qualifierData: UnsafeRawPointer? = nil
    ) throws -> T {
        var address = address
        var dataSize: UInt32 = 0

        try checkOSStatus(
            AudioObjectGetPropertyDataSize(self, &address, qualifierSize, qualifierData, &dataSize),
            "AudioObjectGetPropertyDataSize(\(address.selectorDescription))"
        )

        var value = defaultValue
        try checkOSStatus(
            withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(self, &address, qualifierSize, qualifierData, &dataSize, pointer)
            },
            "AudioObjectGetPropertyData(\(address.selectorDescription))"
        )

        return value
    }
}

private extension AudioObjectPropertyAddress {
    var selectorDescription: String {
        String(format: "%c%c%c%c",
               (mSelector >> 24) & 0xff,
               (mSelector >> 16) & 0xff,
               (mSelector >> 8) & 0xff,
               mSelector & 0xff)
    }
}
