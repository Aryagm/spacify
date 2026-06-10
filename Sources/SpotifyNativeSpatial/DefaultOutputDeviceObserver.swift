import AudioToolbox
import Foundation

/// Watches the system default output device and reports changes on the main
/// actor, so active routing can follow AirPods/speaker switches.
@MainActor
final class DefaultOutputDeviceObserver {
    private static let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDefaultSystemOutputDevice
    ]

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func start(onChange: @escaping @MainActor () -> Void) {
        guard listenerBlock == nil else {
            return
        }

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated {
                onChange()
            }
        }

        forEachAddress { address in
            AudioObjectAddPropertyListenerBlock(.system, &address, .main, block)
        }
        listenerBlock = block
    }

    func stop() {
        guard let block = listenerBlock else {
            return
        }

        forEachAddress { address in
            AudioObjectRemovePropertyListenerBlock(.system, &address, .main, block)
        }
        listenerBlock = nil
    }

    private func forEachAddress(_ body: (inout AudioObjectPropertyAddress) -> OSStatus) {
        for selector in Self.selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = body(&address)
        }
    }
}
