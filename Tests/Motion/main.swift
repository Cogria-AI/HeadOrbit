import Foundation

let suite = "HeadOrbit.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let fresh = LookAwayBlurAction(defaults: defaults)
assert(!fresh.verticalEnabled && !fresh.autoCalibrationEnabled)
defaults.set(50.0, forKey: "blur.threshold")
let upgraded = LookAwayBlurAction(defaults: defaults)
assert(upgraded.leftDegrees == 50 && upgraded.rightDegrees == 50)
assert(!upgraded.verticalEnabled && !upgraded.autoCalibrationEnabled)
upgraded.verticalEnabled = true
upgraded.autoCalibrationEnabled = true
let restored = LookAwayBlurAction(defaults: defaults)
assert(restored.verticalEnabled && restored.autoCalibrationEnabled)
assert(pose(0, -80, at: 0).overshoot(left: 35, right: 35, up: 35, down: 35, includeVertical: false) < 0)
assert(pose(0, -80, at: 0).overshoot(left: 35, right: 35, up: 35, down: 35, includeVertical: true) > 0)

// Existing stability scenarios use a fixed test envelope.
extension ForwardCalibration {
    mutating func update(_ pose: HeadPose, allowed: Bool) {
        update(pose, allowed: allowed, yawRange: -10...10, pitchRange: -10...10)
    }
}

func pose(_ yaw: Double = 0, _ pitch: Double = 0, at time: Double) -> HeadPose {
    HeadPose(yaw: yaw, pitch: pitch, roll: 0, timestamp: time)
}

var calibration = ForwardCalibration()
for i in 0...70 { calibration.update(pose(6, -4, at: Double(i) / 10), allowed: true) }
assert(calibration.yaw == 0, "Must wait eight continuous seconds")
for i in 71...200 { calibration.update(pose(6, -4, at: Double(i) / 10), allowed: true) }
assert(abs(calibration.yaw - 6) < 0.01 && abs(calibration.pitch + 4) < 0.01)
assert(abs(calibration.corrected(pose(6, -4, at: 21)).yaw) < 0.01)
// The eight-second stability window controls only the anchor, not live head motion.
let suddenTurn = pose(60, -30, at: 20.1)
calibration.update(suddenTurn, allowed: true)
let immediate = calibration.corrected(suddenTurn)
assert(abs(immediate.yaw - 54) < 0.01 && abs(immediate.pitch + 26) < 0.01)
assert(immediate.timestamp == suddenTurn.timestamp, "Live pose must retain the current sample time")
let prior = calibration.yaw
for i in 201...500 { calibration.update(pose(25, at: Double(i) / 10), allowed: true) }
assert(calibration.yaw == prior, "Looking away must not become forward")
for i in 501...700 { calibration.update(pose(2, at: Double(i) / 10), allowed: false) }
assert(calibration.yaw == prior, "Reminder or disabled calibration must freeze correction")
calibration = ForwardCalibration()
for i in 0...70 { calibration.update(pose(5, at: Double(i) / 10), allowed: true) }
calibration.update(pose(5, at: 30), allowed: true)
assert(calibration.yaw == 0, "A stream gap must restart stability timing")
for i in 301...370 { calibration.update(pose(5, at: Double(i) / 10), allowed: true) }
assert(calibration.yaw == 0)
for i in 371...600 {
    calibration.update(pose(i % 2 == 0 ? 5 : -5, at: Double(i) / 10), allowed: true)
}
assert(calibration.yaw == 0, "Moving poses must not calibrate")

var trigger = DwellTrigger(threshold: 0, enterDwell: 0.6, hysteresis: 0.5)
// Independent envelopes derived from left/right/up/down limits of 50/30/40/60°.
for (yaw, pitch, accepted) in [(-24.0, 19.0, true), (14.0, -29.0, true),
                               (-26.0, 0.0, false), (16.0, 0.0, false),
                               (0.0, 21.0, false), (0.0, -31.0, false)] {
    var adaptive = ForwardCalibration()
    for i in 0...800 {
        adaptive.update(pose(yaw, pitch, at: Double(i) / 10), allowed: true,
                        yawRange: -25...15, pitchRange: -30...20)
    }
    assert(abs(adaptive.yaw - (accepted ? yaw : 0)) < 0.01)
    assert(abs(adaptive.pitch - (accepted ? pitch : 0)) < 0.01)
    // Even after learning an offset, a new pose outside the manual envelope is rejected.
    let priorYaw = adaptive.yaw
    for i in 801...1600 {
        adaptive.update(pose(-26, at: Double(i) / 10), allowed: true,
                        yawRange: -25...15, pitchRange: -30...20)
    }
    assert(adaptive.yaw == priorYaw)
}
for (sample, expected) in [(pose(-11, at: 0), 1.0), (pose(21, at: 0), 1.0),
                           (pose(0, 31, at: 0), 1.0), (pose(0, -41, at: 0), 1.0),
                           (pose(11, at: 0), -9.0), (pose(0, -31, at: 0), -9.0),
                           (pose(0, 30, at: 0), 0.0)] {
    assert(sample.overshoot(left: 10, right: 20, up: 30, down: 40) == expected,
           "Each direction must use its own signed threshold")
}
assert(!trigger.update(2, at: 0))
assert(trigger.update(2, at: 0.7) && trigger.isActive)
assert(!trigger.update(-0.1, at: 1))
assert(!trigger.update(-1, at: 2))
assert(trigger.update(-1, at: 2.3) && !trigger.isActive)
print("PASS: four directional limits, calibration stability, bounds, pause, stream gaps, motion rejection and dwell recovery")
