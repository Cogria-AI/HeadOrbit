import AppKit
import Combine
import Foundation

/// 纯逻辑：开启的场景展开成「动作 → 触发器」，喂姿态、吐出哪些动作刚刚触发 / 解除。不碰屏幕和键盘，方便测试
struct SceneRuntime {
    struct Slot {
        var binding: GestureBinding
        var trigger: DwellTrigger
    }

    private(set) var slots: [Gesture: Slot] = [:]

    init(scenes: [SceneConfig]) {
        for scene in scenes where scene.isEnabled {
            for b in scene.bindings where slots[b.gesture] == nil {
                slots[b.gesture] = Slot(binding: b, trigger: Self.trigger(for: b))
            }
        }
    }

    static func trigger(for b: GestureBinding) -> DwellTrigger {
        switch b.behavior.kind {
        case .posture:
            return DwellTrigger(threshold: b.threshold, enterDwell: b.dwell, hysteresis: 5, exitDwell: 0.8)
        case .blur:
            // 迟滞封顶，保证阈值很小时回到正中也能解除
            return DwellTrigger(threshold: b.threshold, enterDwell: b.dwell, hysteresis: min(8, max(1, b.threshold) * 0.5), exitDwell: 0.25)
        case .tapKey, .holdKey:
            return DwellTrigger(threshold: b.threshold, enterDwell: b.dwell, hysteresis: min(8, max(1, b.threshold) * 0.5), exitDwell: 0.1)
        }
    }

    /// 坐姿提醒看手动校准的姿态（raw），其余看自动微调后的姿态（corrected）。skip 里的动作这一帧不处理
    mutating func process(corrected: HeadPose, raw: HeadPose, skip: Set<Gesture> = []) -> [(Gesture, Bool)] {
        var flips: [(Gesture, Bool)] = []
        for g in Gesture.allCases {
            guard var slot = slots[g], !skip.contains(g) else { continue }
            let pose = slot.binding.behavior.kind == .posture ? raw : corrected
            if slot.trigger.update(g.value(pose), at: pose.timestamp) {
                flips.append((g, slot.trigger.isActive))
            }
            slots[g] = slot
        }
        return flips
    }

    mutating func reset(_ g: Gesture) { slots[g]?.trigger.reset() }

    mutating func resetAll() {
        for g in slots.keys { slots[g]?.trigger.reset() }
    }

    func binding(_ g: Gesture) -> GestureBinding? { slots[g]?.binding }
}

/// 每帧都变的数据单独放一个对象，只让实时角度条订阅它，整页表单不跟着每帧重绘
final class PoseFeed: ObservableObject {
    /// 自动微调后的姿态，界面上的实时角度都看它
    @Published fileprivate(set) var forward = HeadPose.zero
    /// 只经过手动校准的姿态（坐姿提醒用）
    @Published fileprivate(set) var raw = HeadPose.zero
    @Published fileprivate(set) var active: Set<Gesture> = []
}

/// 把 HeadTracker 的数据喂给开启的场景，并执行行为（模糊、坐姿提醒、按键）。
/// 自身不发布任何东西，界面可以放心订阅它拿 posture / preview，不会被每帧数据拖着重绘
final class SceneEngine: ObservableObject {
    let feed = PoseFeed()
    let posture = PostureReminder()

    private var active: Set<Gesture> = [] { didSet { if active != feed.active { feed.active = active } } }

    private let tracker: HeadTracker
    private let store: SceneStore
    private var runtime = SceneRuntime(scenes: [])
    private var calibration = ForwardCalibration()
    private var heldKeys: [Gesture: KeyCombo] = [:]
    private var lastTrustPrompt: Date?
    private let overlay = BlurOverlayController.shared
    private var bag = Set<AnyCancellable>()

    init(tracker: HeadTracker, store: SceneStore) {
        self.tracker = tracker
        self.store = store

        posture.onDismiss = { [weak self] in
            guard let self else { return }
            for g in Gesture.allCases where self.runtime.binding(g)?.behavior == .posture {
                self.runtime.reset(g)
                self.active.remove(g)
            }
        }

        store.$scenes
            .removeDuplicates()
            .sink { [weak self] in self?.rebuild($0) }
            .store(in: &bag)

        store.$autoCalibration
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.resetAll() }
            .store(in: &bag)

        tracker.samples
            .sink { [weak self] in self?.process($0) }
            .store(in: &bag)

        tracker.$status
            .removeDuplicates()
            .sink { [weak self] status in if !status.isTracking { self?.resetAll() } }
            .store(in: &bag)

        tracker.didRecenter
            .sink { [weak self] in self?.resetAll() }
            .store(in: &bag)

        // 退出时一定松开按住的键，不能让 Fn 卡在按下状态
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.deactivateAll() }
            .store(in: &bag)
    }

    /// 场景编辑器里的「预览」
    func previewBlur(dim: Double, seconds: TimeInterval = 2) {
        overlay.request("preview", dim: dim)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.overlay.release("preview")
        }
    }

    // MARK: -

    private func process(_ pose: HeadPose) {
        updateCalibration(pose)
        let corrected = calibration.corrected(pose)
        feed.forward = corrected
        feed.raw = pose
        posture.update(pitch: pose.pitch)
        let skip = posture.isSnoozed ? Set(Gesture.allCases.filter { runtime.binding($0)?.behavior == .posture }) : []
        for (g, on) in runtime.process(corrected: corrected, raw: pose, skip: skip) {
            apply(g, on)
        }
    }

    private func updateCalibration(_ pose: HeadPose) {
        func limit(_ g: Gesture) -> Double {
            guard let b = runtime.binding(g), b.behavior != .posture else { return 35 }
            return max(1, b.threshold) * 0.5
        }
        let yawRange = -limit(.turnLeft)...limit(.turnRight)
        let pitchRange = -limit(.lookDown)...limit(.lookUp)
        let p = calibration.corrected(pose)
        let postureOver = Gesture.allCases.contains { g in
            guard let b = runtime.binding(g), b.behavior == .posture else { return false }
            return g.value(pose) > b.threshold
        }
        let allowed = store.autoCalibration && tracker.isCalibrated && active.isEmpty && !postureOver
            && yawRange.contains(p.yaw) && pitchRange.contains(p.pitch)
        calibration.update(pose, allowed: allowed, yawRange: yawRange, pitchRange: pitchRange)
    }

    private func apply(_ g: Gesture, _ on: Bool) {
        guard let b = runtime.binding(g) else { return }
        if on { active.insert(g) } else { active.remove(g) }
        switch b.behavior {
        case .blur(let dim):
            on ? overlay.request(owner(g), dim: dim) : overlay.release(owner(g))
        case .posture:
            posture.setReminding(on)
        case .tapKey(let k):
            if on, ensureTrusted() { KeySender.tap(k) }
        case .holdKey(let k):
            if on {
                if ensureTrusted() { KeySender.down(k); heldKeys[g] = k }
            } else if let held = heldKeys.removeValue(forKey: g) {
                KeySender.up(held)
            }
        }
    }

    /// 没有辅助功能权限时不发键，顺手弹一次授权（30 秒内不重复弹）
    private func ensureTrusted() -> Bool {
        if KeySender.isTrusted { return true }
        if lastTrustPrompt.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
            lastTrustPrompt = Date()
            KeySender.requestTrust()
        }
        return false
    }

    private func owner(_ g: Gesture) -> String { "gesture." + g.rawValue }

    private func rebuild(_ scenes: [SceneConfig]) {
        deactivateAll()
        runtime = SceneRuntime(scenes: scenes)
    }

    /// 追踪中断或重新校准：清掉所有状态，回到初始
    private func resetAll() {
        deactivateAll()
        runtime.resetAll()
        calibration = ForwardCalibration()
        feed.forward = .zero
        feed.raw = .zero
        posture.reset()
    }

    private func deactivateAll() {
        for g in active { apply(g, false) }
        for (_, k) in heldKeys { KeySender.up(k) }
        heldKeys.removeAll()
        for g in Gesture.allCases { overlay.release(owner(g)) }
        posture.setReminding(false)
        active.removeAll()
        runtime.resetAll()
    }
}
