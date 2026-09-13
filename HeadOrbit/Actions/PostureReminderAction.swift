import Combine
import Foundation
import os

private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "Posture")

/// 功能二：坐姿提醒。校准时的姿态算「坐正」。人一弯腰塌下去，为了继续看屏幕头就会越来越仰。
/// 规则只有一条：Pitch 高于触发角度并持续一段时间就提醒，回落到（触发角度 - 5°）以下就恢复。
/// 触发角度可以是 0 或负数（校准时没坐太直的话会用到），含义不变。
/// 实测 AirPods 抬头时 Pitch 为正、低头为负，所以默认 +15；低头永远不会高于阈值，自然不算。
final class PostureReminderAction: ObservableObject, HeadAction {
    let id = "posture-reminder"
    let title = "坐姿提醒"

    @Published var isEnabled: Bool { didSet { store(); if !isEnabled { reset() } } }
    /// 触发角度（带符号）：Pitch 高于它就算坐歪
    @Published var thresholdDegrees: Double { didSet { store(); trigger.threshold = thresholdDegrees } }
    /// 要持续多久才提醒
    @Published var dwellSeconds: Double { didSet { store(); trigger.enterDwell = dwellSeconds } }

    @Published private(set) var isReminding = false
    @Published private(set) var lastPitch: Double = 0
    /// 按 Esc 或点「解除」之后暂停到这个时间点，期间不再提醒
    @Published private(set) var snoozedUntil: Date?

    let snoozeSeconds: TimeInterval = 60

    private let overlay = BlurOverlayController.shared
    private let dim = 0.35
    private lazy var escapeKey = GlobalHotKey(keyCode: GlobalHotKey.escape) { [weak self] in self?.dismiss() }
    private var trigger: DwellTrigger
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        // 键名带 v2：旧版默认值方向写反了（-15），换个键让它作废
        let threshold = d.object(forKey: "posture.threshold.v2") as? Double ?? 15
        let dwell = d.object(forKey: "posture.dwell") as? Double ?? 5
        isEnabled = d.object(forKey: "posture.enabled") as? Bool ?? false
        thresholdDegrees = threshold
        dwellSeconds = dwell
        trigger = DwellTrigger(threshold: threshold, enterDwell: dwell, hysteresis: 5, exitDwell: 0.8)
    }

    func process(_ pose: HeadPose) {
        lastPitch = pose.pitch
        if let until = snoozedUntil {
            if Date() < until { return }
            snoozedUntil = nil
        }
        if trigger.update(pose.pitch, at: pose.timestamp) {
            log.notice("posture flip → \(self.trigger.isActive) pitch=\(pose.pitch, format: .fixed(precision: 1)) threshold=\(self.thresholdDegrees)")
            setReminding(trigger.isActive)
        }
        if isReminding {
            overlay.request(id, dim: dim, message: message(for: pose.pitch))
        }
    }

    func reset() {
        trigger.reset()
        snoozedUntil = nil
        setReminding(false)
    }

    /// 手动解除（Esc / 面板按钮）：关掉遮罩，并暂停一会儿，免得姿势没变马上又弹
    func dismiss() {
        guard isReminding else { return }
        log.notice("posture dismissed by user, snooze \(self.snoozeSeconds)s")
        trigger.reset()
        setReminding(false)
        snoozedUntil = Date().addingTimeInterval(snoozeSeconds)
    }

    func preview(seconds: TimeInterval = 2) {
        overlay.request(id + ".preview", dim: dim, message: message(for: lastPitch))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.overlay.release(self.id + ".preview")
        }
    }

    /// 面板高亮用：当前 Pitch 是否已经越过触发角度
    func isOver(_ pitch: Double) -> Bool { pitch > thresholdDegrees }

    private func message(for pitch: Double) -> String {
        L10n.shared.t("posture.overlay", pitch, snoozeSeconds)
    }

    private func setReminding(_ on: Bool) {
        guard on != isReminding else { return }
        isReminding = on
        if on {
            escapeKey.register()
            overlay.request(id, dim: dim, message: message(for: lastPitch))
        } else {
            escapeKey.unregister()
            overlay.release(id)
        }
    }

    private func store() {
        defaults.set(isEnabled, forKey: "posture.enabled")
        defaults.set(thresholdDegrees, forKey: "posture.threshold.v2")
        defaults.set(dwellSeconds, forKey: "posture.dwell")
    }
}
