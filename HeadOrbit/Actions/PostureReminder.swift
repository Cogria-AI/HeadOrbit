import Combine
import Foundation
import os

private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "Posture")

/// 「坐姿提醒」行为：模糊 + 提示文字；Esc 或面板按钮解除并暂停 60 秒，免得姿势没变马上又弹。
/// 校准时的姿态算坐正。人一弯腰塌下去，为了继续看屏幕头就会越来越仰，所以它只挂在「抬头」上。
final class PostureReminder: ObservableObject {
    @Published private(set) var isReminding = false
    /// 解除之后暂停到这个时间点，期间不再提醒
    @Published private(set) var snoozedUntil: Date?

    let snoozeSeconds: TimeInterval = 60
    /// 解除时调用，让引擎把触发器复位
    var onDismiss: (() -> Void)?

    private let owner = "posture"
    private let overlay = BlurOverlayController.shared
    private let dim = 0.35
    private var pitch = 0.0
    private lazy var escapeKey = GlobalHotKey(keyCode: GlobalHotKey.escape) { [weak self] in self?.dismiss() }

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        if Date() < until { return true }
        snoozedUntil = nil
        return false
    }

    func update(pitch: Double) {
        self.pitch = pitch
        if isReminding { overlay.request(owner, dim: dim, message: message) }
    }

    func setReminding(_ on: Bool) {
        guard on != isReminding else { return }
        log.notice("posture → \(on) pitch=\(self.pitch, format: .fixed(precision: 1))")
        isReminding = on
        if on {
            escapeKey.register()
            overlay.request(owner, dim: dim, message: message)
        } else {
            escapeKey.unregister()
            overlay.release(owner)
        }
    }

    func dismiss() {
        guard isReminding else { return }
        setReminding(false)
        snoozedUntil = Date().addingTimeInterval(snoozeSeconds)
        onDismiss?()
    }

    func reset() {
        snoozedUntil = nil
        setReminding(false)
    }

    func preview(seconds: TimeInterval = 2) {
        overlay.request(owner + ".preview", dim: dim, message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.overlay.release(self.owner + ".preview")
        }
    }

    private var message: String { L10n.shared.t("posture.overlay", pitch, snoozeSeconds) }
}
