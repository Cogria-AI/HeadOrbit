import Foundation

/// Small, bounded corrections relative to the user's manually confirmed forward pose.
struct ForwardCalibration {
    private(set) var yaw = 0.0
    private(set) var pitch = 0.0
    private var candidate: HeadPose?
    private var previousTime: TimeInterval?

    mutating func update(_ pose: HeadPose, allowed: Bool,
                         yawRange: ClosedRange<Double>, pitchRange: ClosedRange<Double>) {
        defer { previousTime = pose.timestamp }
        guard allowed, yawRange.contains(pose.yaw), pitchRange.contains(pose.pitch),
              abs(pose.roll) <= 10 else { candidate = nil; return }
        guard let previousTime, pose.timestamp > previousTime,
              pose.timestamp - previousTime < 0.5,
              let candidate,
              abs(pose.yaw - candidate.yaw) <= 2,
              abs(pose.pitch - candidate.pitch) <= 2,
              abs(pose.roll - candidate.roll) <= 2 else {
            candidate = pose
            return
        }
        guard pose.timestamp - candidate.timestamp >= 8 else { return }
        // At most 0.5 degrees per second; never accumulate beyond the manual anchor.
        let step = (pose.timestamp - previousTime) * 0.5
        yaw += max(-step, min(step, pose.yaw - yaw))
        pitch += max(-step, min(step, pose.pitch - pitch))
    }

    func corrected(_ pose: HeadPose) -> HeadPose {
        HeadPose(yaw: pose.yaw - yaw, pitch: pose.pitch - pitch,
                 roll: pose.roll, timestamp: pose.timestamp)
    }
}
