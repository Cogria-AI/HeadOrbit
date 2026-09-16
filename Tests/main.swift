import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message); checks += 1
}
for threshold in [-15.0, 0.0, 15.0] {
    var t = DwellTrigger(threshold: threshold, enterDwell: 5, hysteresis: 5, exitDwell: 0.8, direction: .atOrBelow)
    check(!t.isBeyondThreshold(threshold + 0.1), "above threshold must not trigger")
    check(t.isBeyondThreshold(threshold), "equality must trigger")
    check(t.isBeyondThreshold(threshold - 1), "below must trigger")
    check(!t.update(threshold, at: 0), "must wait")
    check(!t.update(threshold, at: 4.9), "must finish dwell")
    check(t.update(threshold, at: 5) && t.isActive, "equal threshold dwell")
    check(!t.update(threshold + 5, at: 6), "exit hysteresis boundary")
    check(!t.update(threshold + 5.1, at: 7), "exit dwell")
    check(t.update(threshold + 5.1, at: 8) && !t.isActive, "recovery")
    t.reset()
    _ = t.update(threshold - 1, at: 10)
    _ = t.update(threshold + 1, at: 14)
    check(!t.update(threshold - 1, at: 15), "interruption resets dwell")
    check(t.update(threshold - 1, at: 20), "fresh dwell")
}
var yaw = DwellTrigger(threshold: 35, enterDwell: 0.6)
check(!yaw.isBeyondThreshold(35), "yaw retains strict above")
_ = yaw.update(36, at: 0)
check(yaw.update(36, at: 1), "yaw entry preserved")
_ = yaw.update(26, at: 2)
check(yaw.update(26, at: 3) && !yaw.isActive, "yaw exit preserved")
let suite = "HeadOrbit.Regression.\(UUID().uuidString)"
let d = UserDefaults(suiteName: suite)!
defer { d.removePersistentDomain(forName: suite) }
let action = PostureReminderAction(defaults: d)
check(action.thresholdDegrees == -15, "default -15")
action.isEnabled = true
action.dwellSeconds = 5
func pose(_ pitch: Double, _ t: Double) -> HeadPose { HeadPose(yaw: 0, pitch: pitch, roll: 0, timestamp: t) }
check(action.isOver(-15) && !action.isOver(-14), "UI boundary")
action.process(pose(-14, 0)); action.process(pose(-14, 10))
check(!action.isReminding, "wrong direction never reminds")
action.process(pose(-15, 11)); action.process(pose(-15, 16))
check(action.isReminding, "actual action equality")
action.thresholdDegrees = -20
check(!action.isReminding && !BlurOverlayController.shared.owners.contains(action.id), "setting clears old alert")
let tracker = HeadTracker()
let engine = ActionEngine(tracker: tracker, actions: [action])
tracker.samples.send(pose(-30, 20)); tracker.samples.send(pose(-30, 30))
check(!action.isReminding, "uncalibrated actions blocked")
tracker.isCalibrated = true
tracker.samples.send(pose(-30, 31)); tracker.samples.send(pose(-30, 37))
check(action.isReminding, "calibrated actions enabled")
tracker.isCalibrated = false
check(!action.isReminding, "calibration invalidation clears alert immediately")
tracker.samples.send(pose(-30, 50)); tracker.samples.send(pose(-30, 60))
check(!action.isReminding, "no stale-reference actions")
withExtendedLifetime(engine) {}
print("Passed \(checks) regression checks")
