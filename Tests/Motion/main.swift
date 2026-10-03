import Foundation

func freshDefaults() -> UserDefaults {
    let suite = "HeadOrbit.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

// Fresh install: only the privacy scene is on, turning left/right blurs; up/down/tilt do nothing.
let fresh = SceneStore(defaults: freshDefaults())
assert(fresh.scenes.map(\.id) == ["privacy", "posture", "voice"])
assert(fresh.scenes.filter(\.isEnabled).map(\.id) == ["privacy"])
assert(fresh.scene("privacy")!.gestures == [.turnLeft, .turnRight])
assert(!fresh.autoCalibration)

// Upgrade from v0.1.x keeps the old behaviour.
let legacy = freshDefaults()
legacy.set(50.0, forKey: "blur.threshold")
legacy.set(20.0, forKey: "blur.right")
legacy.set(0.3, forKey: "blur.dim")
legacy.set(true, forKey: "blur.verticalEnabled")
legacy.set(true, forKey: "posture.enabled")
legacy.set(-5.0, forKey: "posture.threshold.v2")
legacy.set(true, forKey: "blur.autoCalibration")
let upgraded = SceneStore(defaults: legacy)
let privacy = upgraded.scene("privacy")!
assert(privacy.bindings.first { $0.gesture == .turnLeft }!.threshold == 50)
assert(privacy.bindings.first { $0.gesture == .turnRight }!.threshold == 20)
assert(privacy.bindings.allSatisfy { $0.behavior == .blur(dim: 0.3) })
assert(privacy.gestures == [.turnLeft, .turnRight, .lookDown], "Posture keeps look-up when both were on")
assert(upgraded.scene("posture")!.isEnabled && upgraded.scene("posture")!.bindings[0].threshold == -5)
assert(upgraded.autoCalibration)
assert(upgraded.conflicts(for: "posture").isEmpty)
// Settings persist under the new key and win over legacy keys afterwards.
upgraded.setEnabled("privacy", false)
assert(!SceneStore(defaults: legacy).scene("privacy")!.isEnabled)

// One gesture belongs to at most one enabled scene.
let store = SceneStore(defaults: freshDefaults())
let custom = store.addScene(named: "Mine")
store.setBehavior(.blur, for: .turnLeft, in: custom)
let conflicts = store.setEnabled(custom, true)
assert(conflicts.count == 1 && conflicts[0].0 == .turnLeft && conflicts[0].1.id == "privacy")
assert(!store.scene(custom)!.isEnabled)
store.setEnabled("privacy", false)
assert(store.setEnabled(custom, true).isEmpty && store.scene(custom)!.isEnabled)
store.setBehavior(.holdKey, for: .turnLeft, in: custom)
assert(store.scene(custom)!.bindings.count == 1, "A scene lists each gesture once")
assert(store.scene(custom)!.bindings[0].behavior == .holdKey(.returnKey))
store.setBehavior(.posture, for: .lookUp, in: custom)
assert(store.scene(custom)!.bindings[1].threshold == 15 && store.scene(custom)!.bindings[1].dwell == 5)
store.setBehavior(nil, for: .turnLeft, in: custom)
assert(store.scene(custom)!.gestures == [.lookUp])
assert(Axis.tilt.value(pose(roll: 20, at: 0)) == 20 * Gesture.rollSign && Gesture.lookDown.axis == .nod)
store.delete("privacy")
assert(store.scene("privacy") != nil, "Built-in scenes cannot be deleted")
store.delete(custom)
assert(store.scene(custom) == nil)

// Gesture values.
func pose(_ yaw: Double = 0, _ pitch: Double = 0, roll: Double = 0, at time: Double) -> HeadPose {
    HeadPose(yaw: yaw, pitch: pitch, roll: roll, timestamp: time)
}
assert(Gesture.turnLeft.value(pose(-40, at: 0)) == 40 && Gesture.turnRight.value(pose(-40, at: 0)) == -40)
assert(Gesture.lookDown.value(pose(0, -30, at: 0)) == 30)
assert(Gesture.tiltRight.value(pose(roll: 20, at: 0)) == 20 * Gesture.rollSign)
assert(Gesture.tiltRight.value(pose(40, 30, roll: 20, at: 0)) == 20 * Gesture.rollSign, "Each gesture reads only its own axis")

// Runtime: hold-style flips on entry and release on return; disabled scenes are ignored.
var voice = SceneConfig.voice
voice.isEnabled = true
var runtime = SceneRuntime(scenes: [SceneConfig.privacy, voice, SceneConfig.posture])
assert(Set(runtime.slots.keys) == [.turnLeft, .turnRight, .tiltLeft, .tiltRight])
let leftRoll = -20 * Gesture.rollSign
assert(runtime.process(corrected: pose(roll: leftRoll, at: 0), raw: pose(at: 0)).isEmpty)
let down = runtime.process(corrected: pose(roll: leftRoll, at: 0.25), raw: pose(at: 0.25))
assert(down.count == 1 && down[0].0 == .tiltLeft && down[0].1)
assert(runtime.process(corrected: pose(roll: leftRoll * 0.6, at: 1), raw: pose(at: 1)).isEmpty, "Hysteresis keeps it held")
assert(runtime.process(corrected: pose(at: 2), raw: pose(at: 2)).isEmpty)
let up = runtime.process(corrected: pose(at: 2.15), raw: pose(at: 2.15))
assert(up.count == 1 && up[0].0 == .tiltLeft && !up[0].1)
// A big tilt drags yaw/pitch along; once held it must stay held until the head comes back.
var tiltRuntime = SceneRuntime(scenes: [voice])
_ = tiltRuntime.process(corrected: pose(roll: leftRoll, at: 10), raw: pose(at: 10))
assert(tiltRuntime.process(corrected: pose(roll: leftRoll, at: 10.25), raw: pose(at: 10.25)).first! == (.tiltLeft, true))
assert(tiltRuntime.process(corrected: pose(30, 28, roll: leftRoll * 2.5, at: 11), raw: pose(at: 11)).isEmpty,
       "Tilting further must not release")
assert(tiltRuntime.process(corrected: pose(30, 28, roll: leftRoll * 2.5, at: 12), raw: pose(at: 12)).isEmpty)
// Posture reads the manual reference, not the auto-adjusted one.
var posture = SceneConfig.posture
posture.isEnabled = true
var postureRuntime = SceneRuntime(scenes: [posture])
_ = postureRuntime.process(corrected: pose(0, 0, at: 0), raw: pose(0, 20, at: 0))
assert(postureRuntime.process(corrected: pose(0, 0, at: 5.1), raw: pose(0, 20, at: 5.1)).first! == (.lookUp, true))
assert(postureRuntime.process(corrected: pose(at: 6), raw: pose(0, 20, at: 6), skip: [.lookUp]).isEmpty)

// Existing stability scenarios use a fixed test envelope.
extension ForwardCalibration {
    mutating func update(_ pose: HeadPose, allowed: Bool) {
        update(pose, allowed: allowed, yawRange: -10...10, pitchRange: -10...10)
    }
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
assert(!trigger.update(2, at: 0))
assert(trigger.update(2, at: 0.7) && trigger.isActive)
assert(!trigger.update(-0.1, at: 1))
assert(!trigger.update(-1, at: 2))
assert(trigger.update(-1, at: 2.3) && !trigger.isActive)
// Neck exercise: follow the path in its own direction, overshoot is fine, reversing never counts.
func circle(_ ex: NeckExercise, radius: Double, turns: Double, sign: Double) -> PathFollower {
    var f = PathFollower(exercise: ex)
    for i in 0...Int(turns * 150) {
        let a = Double(i) / 150 * 2 * .pi
        f.update(x: sign * -radius * sin(a), y: -radius * cos(a))
    }
    return f
}
assert(circle(.rollClockwise, radius: 40, turns: 3.05, sign: 1).completedReps == 3)
assert(circle(.rollClockwise, radius: 60, turns: 3.05, sign: 1).completedReps == 3, "Bigger circles count")
assert(circle(.rollClockwise, radius: 15, turns: 3.05, sign: 1).progress < 0.2, "Tiny circles do not")
assert(circle(.rollClockwise, radius: 45, turns: 3.05, sign: -1).progress < 0.2, "Wrong direction does not")
assert(circle(.rollCounterClockwise, radius: 45, turns: 3.05, sign: -1).completedReps == 3)
var eight = PathFollower(exercise: .figureEight)
for i in 0...600 { let p = NeckExercise.figureEight.point(Double(i % 200) / 200); eight.update(x: p.x * 1.2, y: p.y * 1.2) }
assert(eight.completedReps == 3, "A 20% larger 8 counts")
print("PASS: scenes, legacy migration, conflicts, gestures, runtime, calibration stability, bounds, pause, stream gaps, motion rejection, dwell recovery and neck exercise paths")
