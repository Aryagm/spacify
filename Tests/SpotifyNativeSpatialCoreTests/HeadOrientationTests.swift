import Foundation
import Testing
@testable import SpotifyNativeSpatialCore

@Suite("Head orientation")
struct HeadOrientationTests {
    @Test("converts radians to Audio Unit degrees")
    func convertsRadiansToDegrees() {
        let orientation = HeadOrientation(
            yawRadians: .pi / 2,
            pitchRadians: -.pi / 4,
            rollRadians: .pi
        )

        #expect(orientation.yawDegrees == 90)
        #expect(orientation.pitchDegrees == -45)
        #expect(orientation.rollDegrees == 180)
    }

    @Test("normalizes relative yaw across wrap boundary")
    func normalizesRelativeYawAcrossWrapBoundary() {
        let reference = HeadOrientation(yawRadians: 179 * .pi / 180)
        let current = HeadOrientation(yawRadians: -179 * .pi / 180)

        let relative = current.relative(to: reference)

        #expect(abs(relative.yawDegrees - 2) < 0.001)
    }
}
