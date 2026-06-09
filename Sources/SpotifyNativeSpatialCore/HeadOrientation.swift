import Foundation

public struct HeadOrientation: Equatable, Sendable {
    public static let zero = HeadOrientation()

    public var yawRadians: Float
    public var pitchRadians: Float
    public var rollRadians: Float

    public init(
        yawRadians: Float = 0,
        pitchRadians: Float = 0,
        rollRadians: Float = 0
    ) {
        self.yawRadians = yawRadians
        self.pitchRadians = pitchRadians
        self.rollRadians = rollRadians
    }

    public var yawDegrees: Float {
        Self.radiansToDegrees(yawRadians)
    }

    public var pitchDegrees: Float {
        Self.radiansToDegrees(pitchRadians)
    }

    public var rollDegrees: Float {
        Self.radiansToDegrees(rollRadians)
    }

    public func relative(to reference: HeadOrientation) -> HeadOrientation {
        HeadOrientation(
            yawRadians: Self.normalizedRadians(yawRadians - reference.yawRadians),
            pitchRadians: Self.normalizedRadians(pitchRadians - reference.pitchRadians),
            rollRadians: Self.normalizedRadians(rollRadians - reference.rollRadians)
        )
    }

    public static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }

    private static func normalizedRadians(_ radians: Float) -> Float {
        let fullTurn = 2 * Float.pi
        var normalized = radians.truncatingRemainder(dividingBy: fullTurn)

        if normalized <= -.pi {
            normalized += fullTurn
        } else if normalized > .pi {
            normalized -= fullTurn
        }

        return normalized
    }
}
