import Foundation

/// 带持续时间与恢复迟滞的阈值状态机，支持高于阈值或小于等于阈值触发。
struct DwellTrigger {
    enum Direction { case above, atOrBelow }
    var direction: Direction
    var threshold: Double
    var enterDwell: TimeInterval
    var hysteresis: Double = 8
    var exitDwell: TimeInterval = 0.25

    private(set) var isActive = false
    private var since: TimeInterval?

    init(threshold: Double, enterDwell: TimeInterval, hysteresis: Double = 8, exitDwell: TimeInterval = 0.25, direction: Direction = .above) {
        self.direction = direction
        self.threshold = threshold
        self.enterDwell = enterDwell
        self.hysteresis = hysteresis
        self.exitDwell = exitDwell
    }

    func isBeyondThreshold(_ value: Double) -> Bool {
        direction == .above ? value > threshold : value <= threshold
    }

    /// 喂一个值和时间戳，返回 true 表示状态刚刚翻转
    mutating func update(_ value: Double, at t: TimeInterval) -> Bool {
        let recovered = direction == .above ? value < threshold - hysteresis : value > threshold + hysteresis
        let crossed = isActive ? recovered : isBeyondThreshold(value)
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
