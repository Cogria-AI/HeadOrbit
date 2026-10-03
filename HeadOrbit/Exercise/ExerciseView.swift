import SwiftUI

/// 练习画面：上方说明和计数，中间目标轨迹（已走过的部分高亮）、前方引导光点、头部实时轨迹
struct ExerciseView: View {
    @ObservedObject var state: ExerciseState
    @ObservedObject private var l10n = L10n.shared

    private let accent = Color(red: 0.35, green: 0.85, blue: 0.75)
    private let headColor = Color(red: 1, green: 0.62, blue: 0.3)

    var body: some View {
        GeometryReader { geo in
            let ex = state.exercise
            let scale = 0.34 * min(geo.size.width, geo.size.height) / max(ex.extent.x, ex.extent.y)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 30)
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        draw(&ctx, ex: ex, center: center, scale: scale, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
                VStack(spacing: 10) {
                    Text(l10n.t("exercise.\(ex.rawValue)")).font(.system(size: 38, weight: .semibold))
                    Text(l10n.t(ex.pen == .crown ? "exercise.crownHint" : "exercise.noseHint"))
                        .font(.system(size: 20)).opacity(0.85)
                    if needsStart {
                        // 绕环的起点在最下面，第一次用的人不会想到要先低头（2026-10-03 实测卡了 9 秒）
                        Text(l10n.t(ex.pen == .crown ? "exercise.reachStartRoll" : "exercise.reachStart"))
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(cue)
                            .padding(.top, 6)
                    } else {
                        Text(status).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                            .padding(.top, 6)
                    }
                    Spacer()
                    Text(l10n.t("exercise.escHint")).font(.system(size: 15)).opacity(0.6)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8)
                .multilineTextAlignment(.center)
                .padding(.top, 70)
                .padding(.bottom, 40)
            }
        }
    }

    private let cue = Color(red: 1, green: 0.85, blue: 0.3)

    /// 练习已开始、但还没碰到起点
    private var needsStart: Bool {
        state.isTracking && state.phase == .active && state.follower.progress == 0
    }

    private var status: String {
        if !state.isTracking { return l10n.t("exercise.waiting") }
        switch state.phase {
        case .intro(let n): return String(format: l10n.t("exercise.getReady"), n)
        case .active: return "\(state.follower.completedReps) / \(NeckExercise.reps)"
        case .stepDone: return "✓ \(NeckExercise.reps) / \(NeckExercise.reps)"
        case .finished: return l10n.t("exercise.finished")
        }
    }

    private func draw(_ ctx: inout GraphicsContext, ex: NeckExercise, center: CGPoint, scale: Double, time: TimeInterval) {
        func pt(_ p: (x: Double, y: Double)) -> CGPoint {
            CGPoint(x: center.x + p.x * scale, y: center.y - p.y * scale)
        }
        func curve(from a: Double, to b: Double) -> Path {
            var path = Path()
            let n = max(2, Int((b - a) * 240))
            for i in 0...n {
                let p = pt(ex.point(a + (b - a) * Double(i) / Double(n)))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            return path
        }
        let round = StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)

        // 目标轨迹
        ctx.stroke(curve(from: 0, to: 1), with: .color(.white.opacity(0.22)), style: round)

        // 这一圈已走过的部分
        let done = state.phase == .stepDone || state.phase == .finished
        let frac = done ? 1 : state.follower.progress - Double(state.follower.completedReps)
        if frac > 0.002 {
            ctx.stroke(curve(from: 0, to: frac), with: .color(accent.opacity(0.85)), style: round)
        }

        // 引导光点：练习中在进度前方一点点，倒计时时停在起点；呼吸式闪动
        if !done {
            let lead = state.phase == .active ? frac + 0.04 : 0
            let p = pt(ex.point(lead.truncatingRemainder(dividingBy: 1)))
            let pulse = 0.5 + 0.5 * sin(time * 4)
            let r = 15 + 5 * pulse
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.8, y: p.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                     with: .color(.white.opacity(0.12 + 0.1 * pulse)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)), with: .color(.white))
        }

        // 头部实时轨迹，越旧越淡
        guard state.phase == .active, let newest = state.trail.last else { return }
        let trail = state.trail
        for i in trail.indices.dropFirst() {
            let age = (newest.t - trail[i].t) / 2.5
            var seg = Path()
            seg.move(to: pt((trail[i - 1].x, trail[i - 1].y)))
            seg.addLine(to: pt((trail[i].x, trail[i].y)))
            ctx.stroke(seg, with: .color(headColor.opacity(max(0, 0.9 * (1 - age)))),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        let h = pt((newest.x, newest.y))
        if needsStart { drawArrow(&ctx, from: h, to: pt(ex.point(0)), time: time) }
        ctx.fill(Path(ellipseIn: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)), with: .color(headColor))
    }

    /// 从头部光点指向起点的闪动虚线箭头，两端各留出光点的位置
    private func drawArrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, time: TimeInterval) {
        let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
        guard len > 80 else { return }
        let ux = dx / len, uy = dy / len
        let start = CGPoint(x: a.x + ux * 24, y: a.y + uy * 24)
        let end = CGPoint(x: b.x - ux * 34, y: b.y - uy * 34)
        let color = cue.opacity(0.55 + 0.4 * (0.5 + 0.5 * sin(time * 5)))
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 12], dashPhase: -time * 40))
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - ux * 22 - uy * 14, y: end.y - uy * 22 + ux * 14))
        head.addLine(to: CGPoint(x: end.x - ux * 22 + uy * 14, y: end.y - uy * 22 - ux * 14))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }
}
