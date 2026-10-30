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
assert(runtime.process(corrected: pose(roll: leftRoll, at: 0), raw: pose(at: 0), isCalibrated: true).isEmpty)
let down = runtime.process(corrected: pose(roll: leftRoll, at: 0.25), raw: pose(at: 0.25), isCalibrated: true)
assert(down.count == 1 && down[0].0 == .tiltLeft && down[0].1)
assert(runtime.process(corrected: pose(roll: leftRoll * 0.6, at: 0.5), raw: pose(at: 0.5), isCalibrated: true).isEmpty, "Hysteresis keeps it held")
assert(runtime.process(corrected: pose(at: 0.75), raw: pose(at: 0.75), isCalibrated: true).isEmpty)
let up = runtime.process(corrected: pose(at: 0.9), raw: pose(at: 0.9), isCalibrated: true)
assert(up.count == 1 && up[0].0 == .tiltLeft && !up[0].1)
// A big tilt drags yaw/pitch along; once held it must stay held until the head comes back.
var tiltRuntime = SceneRuntime(scenes: [voice])
_ = tiltRuntime.process(corrected: pose(roll: leftRoll, at: 10), raw: pose(at: 10), isCalibrated: true)
assert(tiltRuntime.process(corrected: pose(roll: leftRoll, at: 10.25), raw: pose(at: 10.25), isCalibrated: true).first! == (.tiltLeft, true))
assert(tiltRuntime.process(corrected: pose(30, 28, roll: leftRoll * 2.5, at: 10.5), raw: pose(at: 10.5), isCalibrated: true).isEmpty,
       "Tilting further must not release")
assert(tiltRuntime.process(corrected: pose(30, 28, roll: leftRoll * 2.5, at: 10.75), raw: pose(at: 10.75), isCalibrated: true).isEmpty)
let interruptedHold = tiltRuntime.process(corrected: pose(roll: leftRoll, at: 12), raw: pose(at: 12), isCalibrated: true)
assert(interruptedHold.isEmpty, "A brief stream gap alone does not end a held gesture")
assert(tiltRuntime.process(corrected: pose(at: 12.25), raw: pose(at: 12.25), isCalibrated: true).isEmpty)
let returnedAfterGap = tiltRuntime.process(corrected: pose(at: 12.4), raw: pose(at: 12.4), isCalibrated: true)
assert(returnedAfterGap.count == 1 && returnedAfterGap[0] == (.tiltLeft, false), "Continuous return-to-forward samples release the held key")

// A short interruption must not rearm a one-shot key while the head stays tilted.
var tapRuntime = SceneRuntime(scenes: [voice])
let rightRoll = 20 * Gesture.rollSign
var tapCount = 0
for t in [0.0, 0.3, 1.0, 1.25, 1.6] {
    let flips = tapRuntime.process(corrected: pose(roll: rightRoll, at: t), raw: pose(at: t), isCalibrated: true)
    tapCount += flips.filter { $0 == (.tiltRight, true) }.count
    assert(flips.allSatisfy { $0.1 }, "A gap must not emit a spurious return-to-forward event")
}
assert(tapCount == 1, "Keeping the same tilt through a gap must press Return only once")
assert(tapRuntime.process(corrected: pose(at: 1.8), raw: pose(at: 1.8), isCalibrated: true).isEmpty)
assert(tapRuntime.process(corrected: pose(at: 1.95), raw: pose(at: 1.95), isCalibrated: true).first! == (.tiltRight, false))
assert(tapRuntime.process(corrected: pose(roll: rightRoll, at: 2.1), raw: pose(at: 2.1), isCalibrated: true).isEmpty)
assert(tapRuntime.process(corrected: pose(roll: rightRoll, at: 2.45), raw: pose(at: 2.45), isCalibrated: true).first! == (.tiltRight, true),
       "Returning forward rearms the next deliberate tap")

// A gap must not uncover the screen while the head is still turned away.
var blurRuntime = SceneRuntime(scenes: [SceneConfig.privacy])
for t in [0.0, 0.3] {
    assert(blurRuntime.process(corrected: pose(-40, at: t), raw: pose(at: t), isCalibrated: true).isEmpty)
}
assert(blurRuntime.process(corrected: pose(-40, at: 0.65), raw: pose(at: 0.65), isCalibrated: true).first! == (.turnLeft, true))
assert(blurRuntime.process(corrected: pose(-40, at: 1.5), raw: pose(at: 1.5), isCalibrated: true).isEmpty,
       "A brief stream gap does not release an active privacy blur")
// Posture reads the manual reference, not the auto-adjusted one.
var posture = SceneConfig.posture
posture.isEnabled = true
var postureRuntime = SceneRuntime(scenes: [posture])
for i in 0..<20 {
    let t = Double(i) / 4
    assert(postureRuntime.process(corrected: pose(at: t), raw: pose(0, 20, at: t), isCalibrated: true).isEmpty)
}
assert(postureRuntime.process(corrected: pose(at: 5.1), raw: pose(0, 20, at: 5.1), isCalibrated: true).first! == (.lookUp, true))
assert(postureRuntime.process(corrected: pose(at: 5.25), raw: pose(0, 20, at: 5.25), isCalibrated: true, skip: [.lookUp]).isEmpty)

// First launch and reconnection: uncalibrated angles cannot invoke any action.
var readinessRuntime = SceneRuntime(scenes: [SceneConfig.privacy, voice, posture])
for i in 0...24 {
    let t = Double(i) / 4
    let uncalibrated = pose(-50, 25, roll: leftRoll, at: t)
    assert(readinessRuntime.process(corrected: uncalibrated, raw: uncalibrated, isCalibrated: false).isEmpty)
}
let readyStart = pose(roll: leftRoll, at: 6.25)
assert(readinessRuntime.process(corrected: readyStart, raw: readyStart, isCalibrated: true).isEmpty,
       "Uncalibrated time must not count toward the first calibrated gesture")
let readyHeld = pose(roll: leftRoll, at: 6.5)
assert(readinessRuntime.process(corrected: readyHeld, raw: readyHeld, isCalibrated: true).first! == (.tiltLeft, true))
let lostCalibration = pose(roll: leftRoll, at: 6.75)
let calibrationRelease = readinessRuntime.process(corrected: lostCalibration, raw: lostCalibration, isCalibrated: false)
assert(calibrationRelease.count == 1 && calibrationRelease[0] == (.tiltLeft, false),
       "Losing calibration must release an already active key")
let stillUncalibrated = pose(roll: leftRoll, at: 7)
assert(readinessRuntime.process(corrected: stillUncalibrated, raw: stillUncalibrated, isCalibrated: false).isEmpty)
let recalibrated = pose(roll: leftRoll, at: 7.25)
assert(readinessRuntime.process(corrected: recalibrated, raw: recalibrated, isCalibrated: true).isEmpty)
let heldAgain = pose(roll: leftRoll, at: 7.5)
assert(readinessRuntime.process(corrected: heldAgain, raw: heldAgain, isCalibrated: true).first! == (.tiltLeft, true),
       "Recalibration starts a fresh dwell and permits gestures again")

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
assert(!trigger.update(2, at: 0.35))
assert(trigger.update(2, at: 0.7) && trigger.isActive)
assert(!trigger.update(-0.1, at: 1))
assert(!trigger.update(-1, at: 1.25))
assert(trigger.update(-1, at: 1.55) && !trigger.isActive)

// Missing samples cannot prove continuous entry or return-to-forward dwell.
var interrupted = DwellTrigger(threshold: 35, enterDwell: 0.6)
assert(!interrupted.update(40, at: 0))
assert(!interrupted.update(40, at: 1.5) && !interrupted.isActive, "An entry gap restarts dwell")
assert(!interrupted.update(40, at: 1.8))
assert(interrupted.update(40, at: 2.11) && interrupted.isActive, "Continuous samples after a gap can activate")
assert(!interrupted.update(40, at: 3) && interrupted.isActive, "A gap alone must preserve the active latch")
assert(!interrupted.update(40, at: 3.25))
assert(!interrupted.update(40, at: 3.5))
assert(!interrupted.update(40, at: 3.86) && interrupted.isActive, "An unchanged gesture must not fire twice")
assert(!interrupted.update(0, at: 4))
assert(!interrupted.update(0, at: 4.8) && interrupted.isActive, "A gap during exit dwell restarts the return timer")
assert(!interrupted.update(0, at: 4.9) && interrupted.isActive)
assert(interrupted.update(0, at: 5.1) && !interrupted.isActive, "Continuous neutral samples after the gap complete exit dwell")

// Duplicate/backward timestamps also break continuity instead of carrying old dwell.
var clockReset = DwellTrigger(threshold: 35, enterDwell: 0.5)
assert(!clockReset.update(40, at: 10))
assert(!clockReset.update(40, at: 10.3))
assert(!clockReset.update(40, at: 9))
assert(!clockReset.update(40, at: 9.3), "Backward time must discard the earlier entry timer")
assert(clockReset.update(40, at: 9.6) && clockReset.isActive)
assert(!clockReset.update(0, at: 9.8))
assert(!clockReset.update(0, at: 9.8) && clockReset.isActive, "Duplicate timestamps restart exit dwell without dropping the active latch")
assert(!clockReset.update(0, at: 10) && clockReset.isActive)
assert(!clockReset.update(0, at: 9) && clockReset.isActive, "Backward time also restarts exit dwell")
assert(!clockReset.update(0, at: 9.2) && clockReset.isActive)
assert(clockReset.update(0, at: 9.3) && !clockReset.isActive)
clockReset.reset()
assert(!clockReset.update(40, at: 0))
assert(!clockReset.update(40, at: 0.3))
assert(!clockReset.update(40, at: 0.3), "Duplicate timestamps discard pending entry dwell")
assert(!clockReset.update(40, at: 0.6))
assert(clockReset.update(40, at: 0.9) && clockReset.isActive)

var zeroDwell = DwellTrigger(threshold: 35, enterDwell: 0)
assert(zeroDwell.update(40, at: 0) && zeroDwell.isActive)
assert(!zeroDwell.update(40, at: 1) && zeroDwell.isActive, "A gap cannot rearm a zero-dwell gesture")
assert(!zeroDwell.update(40, at: 1.25) && zeroDwell.isActive)
// Dual screen: yaw reads as distance to the nearer screen; holding still re-anchors drift.
var dual = DualAnchor()
assert(dual.remap(pose(-38, at: 0), offsetB: -40, allowSnap: false).yaw == 2, "Near screen B reads as near forward")
assert(dual.remap(pose(30, at: 0.02), offsetB: -40, allowSnap: false).yaw == 30)
dual = DualAnchor()
for i in 0...100 { _ = dual.remap(pose(6, at: Double(i) / 50), offsetB: -40, allowSnap: true) }
assert(dual.correction == 6, "Holding still near a screen absorbs drift")
assert(abs(dual.remap(pose(-34, at: 2.04), offsetB: -40, allowSnap: false).yaw) < 0.01, "Shared correction keeps screen B aligned")
dual = DualAnchor()
for i in 0...100 { _ = dual.remap(pose(6, at: Double(i) / 50), offsetB: -40, allowSnap: false) }
assert(dual.correction == 0, "No snapping while a gesture is active")
// A slow turn must not drag the anchor along forever.
dual = DualAnchor()
var seen = 0.0
for i in 0...3000 { seen = dual.remap(pose(1.5 * Double(i) / 50, at: Double(i) / 50), offsetB: -40, allowSnap: true).yaw }
assert(dual.correction == DualAnchor.maxCorrection && abs(seen - (90 - DualAnchor.maxCorrection)) < 0.1)

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
print("PASS: scenes, legacy migration, conflicts, gestures, runtime, calibration stability, dual screen, bounds, pause, stream gaps, motion rejection, dwell recovery and neck exercise paths")
