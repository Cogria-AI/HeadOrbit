import Foundation

/// 「值高于阈值并持续一段时间才触发；回落到（阈值 - 迟滞）以下并持续一小段时间才解除」的小状态机。
/// 值和阈值都是带符号的普通数，阈值为 0 或负数也按同一条规则算。左右转头模糊、坐姿提醒都用它。
struct DwellTrigger {
    var threshold: Double
    var enterDwell: TimeInterval
    var hysteresis: Double = 8
    var exitDwell: TimeInterval = 0.25

    private(set) var isActive = false
    private var since: TimeInterval?

    init(threshold: Double, enterDwell: TimeInterval, hysteresis: Double = 8, exitDwell: TimeInterval = 0.25) {
        self.threshold = threshold
        self.enterDwell = enterDwell
        self.hysteresis = hysteresis
        self.exitDwell = exitDwell
    }

    /// 喂一个值和时间戳，返回 true 表示状态刚刚翻转
    mutating func update(_ value: Double, at t: TimeInterval) -> Bool {
        let crossed = isActive ? value < threshold - hysteresis : value > threshold
        guard crossed else { since = nil; return false }
        if since == nil { since = t }
        let dwell = isActive ? exitDwell : enterDwell
        guard t - (since ?? t) >= dwell else { return false }
        isActive.toggle()
        since = nil
        return true
    }

    mutating func reset() {
        isActive = false
        since = nil
    }
}
