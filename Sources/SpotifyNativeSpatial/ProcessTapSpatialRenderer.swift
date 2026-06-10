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
    private var transitionEnvelope: RouteTransitionEnvelope?
    private var isRunning = false
    private var configuredSampleRate: Float64 = 0
    private var rateListenerDeviceID = AudioObjectID.unknown
    private var rateListenerBlock: AudioObjectPropertyListenerBlock?

    /// Fired on the main actor when the output device's nominal sample rate
    /// no longer matches the rate this route was configured for (AirPods do
    /// this when reconfiguring, e.g. for head tracking). The owner should
    /// rebuild the route.
    var onOutputSampleRateChanged: (@MainActor () -> Void)?

    init(processes: [AppAudioProcess], headTrackingEnabled: Bool = false) {
        self.processes = processes
        self.headTrackingEnabled = headTrackingEnabled
        self.queue = DispatchQueue(label: "Spacify.ProcessTap", qos: .userInteractive)
    }

    /// Applies head tracking to the running mixer without rebuilding the
    /// route. Throws if there is no live mixer or the property set fails;
    /// the caller falls back to a route restart.
    func setHeadTrackingEnabled(_ enabled: Bool) throws {
        guard isRunning, let spatialMixer else {
            throw "No running spatial route to apply head tracking to."
        }

        try spatialMixer.setHeadTrackingEnabled(enabled)
        headTrackingEnabled = enabled
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

        // Enabling head tracking makes AirPods renegotiate their link to
        // start the motion channel shortly after the route starts; hold the
        // settle window longer so the renegotiation lands under silence.
        let envelope = RouteTransitionEnvelope(
            sampleRate: sampleRate,
            settleDuration: headTrackingEnabled ? 0.75 : 0.15,
            fadeInDuration: headTrackingEnabled ? 0.35 : 0.25
        )
        transitionEnvelope = envelope

        try checkOSStatus(
            // Capture the mixer strongly: weak loads take a runtime lock and
            // are not safe on the audio thread. The IO proc is destroyed in
            // stop() before the mixer is released.
            AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { _, inputData, _, outputData, outputTime in
                mixer.render(input: inputData, output: outputData, timeStamp: outputTime)
                envelope.apply(to: outputData, frames: StereoFloatBufferBridge.frameCount(in: UnsafeMutableAudioBufferListPointer(outputData)))
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )

        try checkOSStatus(
            AudioDeviceStart(aggregateDeviceID, deviceProcID),
            "AudioDeviceStart"
        )

        configuredSampleRate = sampleRate
        registerSampleRateListener(deviceID: outputDeviceID)

        print("Rendering selected audio through Apple Spatial Mixer (\(outputKind.description)) to \(outputName).")
    }

    func stop() {
        guard isRunning || tapID.isValid || aggregateDeviceID.isValid else {
            return
        }

        unregisterSampleRateListener()

        // Let the route fade to silence before tearing it down, so stopping
        // doesn't cut audio mid-waveform.
        if isRunning, let transitionEnvelope {
            transitionEnvelope.beginFadeOut()
            Thread.sleep(forTimeInterval: transitionEnvelope.fadeOutDuration + 0.02)
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
        transitionEnvelope = nil
        isRunning = false
    }

    deinit {
        stop()
    }
}

@available(macOS 14.2, *)
private extension ProcessTapSpatialRenderer {
    func registerSampleRateListener(deviceID: AudioObjectID) {
        guard let onChange = onOutputSampleRateChanged else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let expectedRate = configuredSampleRate
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated {
                let currentRate = (try? deviceID.readNominalSampleRate()) ?? 0
                guard currentRate > 0, abs(currentRate - expectedRate) > 0.5 else {
                    return
                }

                onChange()
            }
        }

        if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
            rateListenerDeviceID = deviceID
            rateListenerBlock = block
        }
    }

    func unregisterSampleRateListener() {
        guard let block = rateListenerBlock, rateListenerDeviceID.isValid else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectRemovePropertyListenerBlock(rateListenerDeviceID, &address, .main, block)
        rateListenerDeviceID = .unknown
        rateListenerBlock = nil
    }

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
