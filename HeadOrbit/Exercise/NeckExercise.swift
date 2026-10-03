import Foundation

/// 颈部活动的一个动作：一条目标轨迹 + 用头的哪个部位来画。所有坐标单位是「度」，x 向右、y 向上。
/// 参数来自 2026-10-03 的实测录制：绕环半径约 50°、一圈约 3 秒；鼻尖画 8 左右 ±20~40°、上下 ±40°、一个约 6 秒
enum NeckExercise: String, CaseIterable {
    case rollClockwise, rollCounterClockwise, figureEight

    enum Pen {
        /// 头顶朝向：歪头左右走，前后点头上下走。适合绕环
        case crown
        /// 鼻尖朝向：转头左右走，抬低头上下走。适合在屏幕上描图形
        case nose
    }

    /// 默认流程：顺时针绕环、逆时针绕环、画 8，各 3 次
    static let routine: [NeckExercise] = [.rollClockwise, .rollCounterClockwise, .figureEight]
    static let reps = 3

    var pen: Pen { self == .figureEight ? .nose : .crown }

    /// 离目标轨迹多远之内算「跟上了」
    var tolerance: Double { self == .figureEight ? 15 : 20 }

    /// 轨迹在两个方向上的最大幅度，界面按它缩放
    var extent: (x: Double, y: Double) { self == .figureEight ? (25, 35) : (40, 40) }

    /// 轨迹上的点，s ∈ [0, 1) 走完一圈
    func point(_ s: Double) -> (x: Double, y: Double) {
        let a = s * 2 * .pi
        switch self {
        // 从最下面（下巴贴胸）开始，屏幕上顺时针：下 → 左 → 上 → 右
        case .rollClockwise: return (-40 * sin(a), -40 * cos(a))
        case .rollCounterClockwise: return (40 * sin(a), -40 * cos(a))
        // 竖着的 8（Gerono 双纽线）：从中心出发先往右上画上圈，回到中心再画下圈
        case .figureEight: return (50 * sin(a) * cos(a), 35 * sin(a))
        }
    }

    /// 当前姿态在这个动作的坐标系里的位置
    func position(_ p: HeadPose) -> (x: Double, y: Double) {
        pen == .crown ? (p.crownX, p.crownY) : (p.yaw, p.pitch)
    }
}

/// 跟着目标轨迹走：只往前、不往回，每次最多往前搜一小段，所以不会因为抄近路跳过半圈。
/// 用户按自己的节奏走，走完一整圈算一次。
struct PathFollower {
    let exercise: NeckExercise
    /// 累计走过多少圈（2.5 = 两圈半）
    private(set) var progress: Double = 0

    private let samples = 240
    /// 一帧最多往前找这么多圈。50 帧/秒、一圈 2 秒时每帧约 0.01，留足余量
    private let lookAhead = 0.12

    private var last: (x: Double, y: Double)?

    init(exercise: NeckExercise) { self.exercise = exercise }

    var completedReps: Int { Int(progress) }

    /// 喂一帧位置，返回这一帧是否刚好完成一圈
    @discardableResult
    mutating func update(x: Double, y: Double) -> Bool {
        let before = completedReps
        let steps = Int(lookAhead * Double(samples))
        var best: Double?
        for i in 0...steps {
            let s = progress + Double(i) / Double(samples)
            let p = exercise.point(s.truncatingRemainder(dividingBy: 1))
            if Self.distance(x, y, to: p) <= exercise.tolerance { best = s }
        }
        // 反着转时，用户会从窗口远端先进入容差范围，不拦的话每圈都会被往前推一点。
        // 所以要求这一帧的移动方向和轨迹方向不相反
        if let best, let last {
            let a = exercise.point(best.truncatingRemainder(dividingBy: 1))
            let b = exercise.point((best + 0.01).truncatingRemainder(dividingBy: 1))
            if (x - last.x) * (b.x - a.x) + (y - last.y) * (b.y - a.y) >= 0 { progress = best }
        }
        last = (x, y)
        return completedReps > before
    }

    /// 到目标点的距离。动作做得比目标大不算错（绕环实测半径 55~65°，比目标大），
    /// 所以量的是到「目标点 → 目标点放大 1.6 倍」这段线的距离
    static func distance(_ x: Double, _ y: Double, to t: (x: Double, y: Double)) -> Double {
        let len2 = t.x * t.x + t.y * t.y
        guard len2 > 0 else { return hypot(x, y) }
        let k = min(1.6, max(1, (x * t.x + y * t.y) / len2))
        return hypot(x - k * t.x, y - k * t.y)
    }
}
