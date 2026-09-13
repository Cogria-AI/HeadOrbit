import Foundation

/// 「超过阈值并持续一段时间才触发；回到阈值以内（带迟滞）并持续一小段时间才解除」的小状态机。
/// 左右转头模糊、坐姿提醒都用它。
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
        // 迟滞最多吃掉阈值的一半，否则阈值很小时回正条件会变成「< 0」永远不成立
        let exitAt = threshold - min(hysteresis, threshold / 2)
        let crossed = isActive ? value < exitAt : value > threshold
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
