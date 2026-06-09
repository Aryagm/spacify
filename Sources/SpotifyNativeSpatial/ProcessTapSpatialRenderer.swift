import AudioToolbox
import Foundation
import SpotifyNativeSpatialCore

@available(macOS 14.2, *)
final class ProcessTapSpatialRenderer {
    private let processes: [AppAudioProcess]
    private let queue = DispatchQueue(label: "SpotifyNativeSpatial.ProcessTap", qos: .userInteractive)

    private var tapID = AudioObjectID.unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var spatialMixer: AppleSpatialMixerRenderer?
    private var isRunning = false

    init(processes: [AppAudioProcess]) {
        self.processes = processes
    }

    func setYaw(_ yaw: Float) {
        spatialMixer?.setHeadYawRadians(yaw)
    }

    func setHeadOrientation(_ orientation: HeadOrientation) {
        spatialMixer?.setHeadOrientation(orientation)
    }

    func start() throws {
        guard !isRunning else {
            return
        }

        let objectIDs = processes.map(\.objectID)
        guard !objectIDs.isEmpty else {
            throw "No CoreAudio process objects were selected."
        }

        do {
            try startTapAndRenderer(objectIDs: objectIDs)
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    private func startTapAndRenderer(objectIDs: [AudioObjectID]) throws {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var createdTapID = AudioObjectID.unknown
        try checkOSStatus(
            AudioHardwareCreateProcessTap(tapDescription, &createdTapID),
            "AudioHardwareCreateProcessTap"
        )
        tapID = createdTapID

        let streamDescription = try tapID.readAudioTapStreamBasicDescription()

        let outputDeviceID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try outputDeviceID.readDeviceUID()
        let outputName = (try? outputDeviceID.readDeviceName()) ?? outputUID
        let outputKind = SpatialOutputDeviceKind.infer(deviceName: outputName, deviceUID: outputUID)
        let sampleRate = streamDescription.mSampleRate > 0
            ? streamDescription.mSampleRate
            : ((try? outputDeviceID.readNominalSampleRate()) ?? 48_000)

        spatialMixer = try AppleSpatialMixerRenderer(
            configuration: AppleSpatialMixerConfiguration(
                sampleRate: sampleRate,
                outputDeviceKind: outputKind
            )
        )

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SpotifyNativeSpatial",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var createdAggregateID = AudioObjectID.unknown
        try checkOSStatus(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &createdAggregateID),
            "AudioHardwareCreateAggregateDevice"
        )
        aggregateDeviceID = createdAggregateID

        try waitUntilAggregateDeviceIsReady(aggregateDeviceID)

        try checkOSStatus(
            AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] _, inputData, _, outputData, outputTime in
                guard let self else {
                    StereoFloatBufferBridge.zero(output: outputData)
                    return
                }

                guard let spatialMixer = self.spatialMixer else {
                    StereoFloatBufferBridge.zero(output: outputData)
                    return
                }

                spatialMixer.render(input: inputData, output: outputData, timeStamp: outputTime)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )

        try checkOSStatus(
            AudioDeviceStart(aggregateDeviceID, deviceProcID),
            "AudioDeviceStart"
        )

        print("Rendering selected audio through Apple Spatial Mixer (\(outputKind.description)) to \(outputName).")
    }

    func stop() {
        guard isRunning || tapID.isValid || aggregateDeviceID.isValid else {
            return
        }

        if aggregateDeviceID.isValid {
            _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)

            if let deviceProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                self.deviceProcID = nil
            }

            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        if tapID.isValid {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }

        spatialMixer = nil
        isRunning = false
    }

    deinit {
        stop()
    }
}

@available(macOS 14.2, *)
private extension ProcessTapSpatialRenderer {
    func waitUntilAggregateDeviceIsReady(_ deviceID: AudioObjectID) throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if (try? deviceID.readNominalSampleRate()) ?? 0 > 0 {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw "Aggregate device was created but did not become ready within 2 seconds."
    }
}

private extension SpatialOutputDeviceKind {
    var description: String {
        switch self {
        case .headphones:
            return "headphones"
        case .builtInSpeakers:
            return "built-in speakers"
        case .externalSpeakers:
            return "external speakers"
        }
    }
}
