import AudioToolbox
import Foundation
import SpotifyNativeSpatialCore

@available(macOS 14.2, *)
final class ProcessTapSpatialRenderer {
    private let processes: [AppAudioProcess]
    private let queue: DispatchQueue

    private var headTrackingEnabled: Bool
    private var tapID = AudioObjectID.unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var spatialMixer: AppleSpatialMixerRenderer?
    private var isRunning = false

    init(processes: [AppAudioProcess], headTrackingEnabled: Bool = false) {
        self.processes = processes
        self.headTrackingEnabled = headTrackingEnabled
        self.queue = DispatchQueue(label: "Spacify.ProcessTap", qos: .userInteractive)
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
        guard streamDescription.isStereoFloatPCM else {
            throw "Unsupported tap stream format for Apple Spatial Mixer bridge: \(streamDescription.spatialMixerFormatDescription)"
        }

        let outputDeviceID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try outputDeviceID.readDeviceUID()
        let outputName = (try? outputDeviceID.readDeviceName()) ?? outputUID
        let outputKind = SpatialOutputDeviceKind.infer(deviceName: outputName, deviceUID: outputUID)

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spacify",
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
                    // The aggregate is clocked by the output device, not the
                    // tap. Drift compensation rate-matches the tap stream to
                    // that clock; without it a tap producing at a different
                    // rate (44.1kHz app on a 48kHz device) plays pitch-shifted.
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

        // The IO proc runs on the aggregate's clock, so the mixer must run at
        // the aggregate's rate -- not the tap's.
        let aggregateRate = (try? aggregateDeviceID.readNominalSampleRate()) ?? 0
        let sampleRate = aggregateRate > 0
            ? aggregateRate
            : ((try? outputDeviceID.readNominalSampleRate()) ?? streamDescription.mSampleRate)

        let mixer = try AppleSpatialMixerRenderer(
            configuration: AppleSpatialMixerConfiguration(
                sampleRate: sampleRate,
                outputDeviceKind: outputKind,
                headTrackingEnabled: headTrackingEnabled
            )
        )
        spatialMixer = mixer

        try checkOSStatus(
            // Capture the mixer strongly: weak loads take a runtime lock and
            // are not safe on the audio thread. The IO proc is destroyed in
            // stop() before the mixer is released.
            AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { _, inputData, _, outputData, outputTime in
                mixer.render(input: inputData, output: outputData, timeStamp: outputTime)
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
