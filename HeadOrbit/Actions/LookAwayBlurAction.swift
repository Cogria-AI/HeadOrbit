import Combine
import Foundation

/// 功能一：头转向左右（眼睛离开屏幕）超过阈值并持续一小段时间 → 全屏模糊；转回来 → 恢复。
final class LookAwayBlurAction: ObservableObject, HeadAction {
    let id = "look-away-blur"
    let title = "看向别处时模糊屏幕"

    @Published var isEnabled: Bool { didSet { store(); if !isEnabled { reset() } } }
    /// 超过这个角度算「没看屏幕」
    @Published var thresholdDegrees: Double { didSet { store(); trigger.threshold = thresholdDegrees } }
    /// 转开之后要持续多久才模糊，避免随便瞟一眼就触发
    @Published var dwellSeconds: Double { didSet { store(); trigger.enterDwell = dwellSeconds } }
    /// 模糊之上再压一层暗色，0 = 纯模糊
    @Published var dimAmount: Double { didSet { store(); if isBlurred { overlay.request(id, dim: dimAmount) } } }

    @Published private(set) var isBlurred = false

    private let overlay = BlurOverlayController.shared
    private var trigger: DwellTrigger
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        let threshold = d.object(forKey: "blur.threshold") as? Double ?? 35
        let dwell = d.object(forKey: "blur.dwell") as? Double ?? 0.6
        isEnabled = d.object(forKey: "blur.enabled") as? Bool ?? true
        thresholdDegrees = threshold
        dwellSeconds = dwell
        dimAmount = d.object(forKey: "blur.dim") as? Double ?? 0.15
        trigger = DwellTrigger(threshold: threshold, enterDwell: dwell)
    }

    func process(_ pose: HeadPose) {
        if trigger.update(abs(pose.yaw), at: pose.timestamp) {
            setBlurred(trigger.isActive)
        }
    }

    func reset() {
        trigger.reset()
        setBlurred(false)
    }

    /// 菜单里的「预览」：不管姿态，直接模糊 seconds 秒
    func preview(seconds: TimeInterval = 2) {
        overlay.request(id + ".preview", dim: dimAmount)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.overlay.release(self.id + ".preview")
        }
    }

    private func setBlurred(_ on: Bool) {
        guard on != isBlurred else { return }
        isBlurred = on
        on ? overlay.request(id, dim: dimAmount) : overlay.release(id)
    }

    private func store() {
        defaults.set(isEnabled, forKey: "blur.enabled")
        defaults.set(thresholdDegrees, forKey: "blur.threshold")
        defaults.set(dwellSeconds, forKey: "blur.dwell")
        defaults.set(dimAmount, forKey: "blur.dim")
    }
}
