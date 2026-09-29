import Combine
import Foundation

/// 功能一：头部任意方向超过独立阈值并持续一小段时间 → 全屏模糊；转回来 → 恢复。
final class LookAwayBlurAction: ObservableObject, HeadAction {
    let id = "look-away-blur"
    let title = "看向别处时模糊屏幕"

    @Published var isEnabled: Bool { didSet { store(); if !isEnabled { reset() } } }
    /// 超过这个角度算「没看屏幕」
    @Published var leftDegrees: Double { didSet { store(); reset() } }
    @Published var rightDegrees: Double { didSet { store(); reset() } }
    @Published var upDegrees: Double { didSet { store(); reset() } }
    @Published var downDegrees: Double { didSet { store(); reset() } }
    @Published var verticalEnabled: Bool { didSet { store(); reset() } }
    @Published var autoCalibrationEnabled: Bool { didSet { store(); reset() } }
    @Published private(set) var forwardPose = HeadPose.zero
    private var calibration = ForwardCalibration()
    /// 转开之后要持续多久才模糊，避免随便瞟一眼就触发
    @Published var dwellSeconds: Double { didSet { store(); trigger.enterDwell = dwellSeconds } }
    /// 模糊之上再压一层暗色，0 = 纯模糊
    @Published var dimAmount: Double { didSet { store(); if isBlurred { overlay.request(id, dim: dimAmount) } } }

    @Published private(set) var isBlurred = false

    private let overlay = BlurOverlayController.shared
    private var trigger: DwellTrigger
    private let defaults: UserDefaults

    init(defaults d: UserDefaults = .standard) {
        defaults = d
        let threshold = max(1, d.object(forKey: "blur.threshold") as? Double ?? 35)
        let dwell = d.object(forKey: "blur.dwell") as? Double ?? 0.6
        isEnabled = d.object(forKey: "blur.enabled") as? Bool ?? true
        leftDegrees = d.object(forKey: "blur.left") as? Double ?? threshold
        rightDegrees = d.object(forKey: "blur.right") as? Double ?? threshold
        upDegrees = d.object(forKey: "blur.up") as? Double ?? 35
        downDegrees = d.object(forKey: "blur.down") as? Double ?? 35
        verticalEnabled = d.object(forKey: "blur.verticalEnabled") as? Bool ?? false
        autoCalibrationEnabled = d.object(forKey: "blur.autoCalibration") as? Bool ?? false
        dwellSeconds = dwell
        dimAmount = d.object(forKey: "blur.dim") as? Double ?? 0.15
        trigger = DwellTrigger(threshold: 0, enterDwell: dwell)
    }

    func updateForward(_ pose: HeadPose, allowed: Bool) {
        let p = calibration.corrected(pose)
        calibration.update(pose, allowed: autoCalibrationEnabled && allowed && !isBlurred
            && p.yaw > -leftDegrees * 0.5 && p.yaw < rightDegrees * 0.5
            && p.pitch > -downDegrees * 0.5 && p.pitch < upDegrees * 0.5,
            yawRange: (-leftDegrees * 0.5)...(rightDegrees * 0.5),
            pitchRange: (-downDegrees * 0.5)...(upDegrees * 0.5))
        forwardPose = calibration.corrected(pose)
    }

    func process(_ pose: HeadPose) {
        let p = calibration.corrected(pose)
        // Maximum signed overshoot: enter if any direction exceeds its limit,
        // exit only once all four directions are safely inside their limits.
        // Cap hysteresis so zero and small thresholds can still recover at center.
        trigger.hysteresis = min(8, min(leftDegrees, rightDegrees,
            verticalEnabled ? min(upDegrees, downDegrees) : .infinity) * 0.5)
        let overshoot = p.overshoot(left: leftDegrees, right: rightDegrees,
                                   up: upDegrees, down: downDegrees, includeVertical: verticalEnabled)
        if trigger.update(overshoot, at: pose.timestamp) {
            setBlurred(trigger.isActive)
        }
    }

    func reset() {
        trigger.reset()
        calibration = ForwardCalibration()
        forwardPose = .zero
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
        defaults.set(leftDegrees, forKey: "blur.left")
        defaults.set(rightDegrees, forKey: "blur.right")
        defaults.set(upDegrees, forKey: "blur.up")
        defaults.set(downDegrees, forKey: "blur.down")
        defaults.set(verticalEnabled, forKey: "blur.verticalEnabled")
        defaults.set(autoCalibrationEnabled, forKey: "blur.autoCalibration")
        defaults.set(dwellSeconds, forKey: "blur.dwell")
        defaults.set(dimAmount, forKey: "blur.dim")
    }
}
