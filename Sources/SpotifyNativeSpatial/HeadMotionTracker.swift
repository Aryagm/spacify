import CoreMotion
import Foundation
import SpotifyNativeSpatialCore

@available(macOS 14.2, *)
final class HeadMotionTracker {
    enum StartResult: Equatable {
        case started
        case unavailable
        case denied
        case restricted

        var statusMessage: String {
            switch self {
            case .started:
                return "Head tracking on"
            case .unavailable:
                return "Head tracking unavailable"
            case .denied:
                return "Motion permission denied"
            case .restricted:
                return "Motion permission restricted"
            }
        }
    }

    var onOrientationChanged: (@MainActor @Sendable (HeadOrientation) -> Void)? {
        get {
            state.onOrientationChanged
        }
        set {
            state.onOrientationChanged = newValue
        }
    }

    var currentOrientation: HeadOrientation {
        state.currentOrientation
    }

    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue
    private let reducer = HeadMotionSampleReducer(minimumDeliveryInterval: 1.0 / 60.0)
    private let state = HeadMotionTrackerState()

    init() {
        queue = OperationQueue()
        queue.name = "SpotifyNativeSpatial.HeadMotion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    func start() -> StartResult {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized, .notDetermined:
            break
        @unknown default:
            break
        }

        guard manager.isDeviceMotionAvailable else {
            return .unavailable
        }

        reducer.reset()
        state.currentOrientation = .zero

        manager.startDeviceMotionUpdates(to: queue) { [reducer, state] motion, error in
            guard error == nil, let motion else {
                return
            }

            let absoluteOrientation = HeadOrientation(
                yawRadians: Float(motion.attitude.yaw),
                pitchRadians: Float(motion.attitude.pitch),
                rollRadians: Float(motion.attitude.roll)
            )

            guard let relativeOrientation = reducer.reduce(
                timestamp: motion.timestamp,
                orientation: absoluteOrientation
            ) else {
                return
            }

            state.currentOrientation = relativeOrientation

            DispatchQueue.main.async { [state, relativeOrientation] in
                state.deliverOnMain(relativeOrientation)
            }
        }

        return .started
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reducer.reset()
        state.currentOrientation = .zero
    }
}

private final class HeadMotionTrackerState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCurrentOrientation = HeadOrientation.zero
    private var storedOnOrientationChanged: (@MainActor @Sendable (HeadOrientation) -> Void)?

    var currentOrientation: HeadOrientation {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCurrentOrientation
        }
        set {
            lock.lock()
            storedCurrentOrientation = newValue
            lock.unlock()
        }
    }

    var onOrientationChanged: (@MainActor @Sendable (HeadOrientation) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnOrientationChanged
        }
        set {
            lock.lock()
            storedOnOrientationChanged = newValue
            lock.unlock()
        }
    }

    func deliverOnMain(_ orientation: HeadOrientation) {
        let handler = onOrientationChanged
        MainActor.assumeIsolated {
            handler?(orientation)
        }
    }
}

private final class HeadMotionSampleReducer: @unchecked Sendable {
    private let lock = NSLock()
    private let minimumDeliveryInterval: TimeInterval
    private var referenceOrientation: HeadOrientation?
    private var lastDeliveryTime: TimeInterval = 0

    init(minimumDeliveryInterval: TimeInterval) {
        self.minimumDeliveryInterval = minimumDeliveryInterval
    }

    func reduce(timestamp: TimeInterval, orientation: HeadOrientation) -> HeadOrientation? {
        lock.lock()
        defer { lock.unlock() }

        guard timestamp - lastDeliveryTime >= minimumDeliveryInterval else {
            return nil
        }

        lastDeliveryTime = timestamp

        let reference = referenceOrientation ?? orientation
        referenceOrientation = reference

        return orientation.relative(to: reference)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        referenceOrientation = nil
        lastDeliveryTime = 0
    }
}
