import Foundation

/// 双屏模式的核心：两个屏幕各有一个「正前方」基准（屏幕 B 只存相对屏幕 A 的偏航角）。
/// 每帧把姿态重映射成「离最近那块屏幕的偏航」再喂给场景引擎，
/// 于是触发条件自然变成「头离开两块屏幕的覆盖区」。
/// 回到任一屏幕前稳定一小会，就把共享的 yaw 修正量快照过去，吸收漂移。
struct DualAnchor {
    /// 对 rawYaw 的加性修正（度）。快照重锚改的就是它
    private(set) var correction = 0.0
    /// 稳定性跟踪：连续帧的候选姿态
    private var candidate: (yaw: Double, pitch: Double, t: TimeInterval)?
    private var previousTime: TimeInterval?

    /// 离屏幕基准这么近（度）才算「在这块屏前」，可快照
    static let snapCone = 10.0
    /// 姿态稳定这么久（秒）才允许快照
    static let snapStability = 1.0
    /// 帧间抖动上限（度），超过视为不稳定、重新计时
    static let jitter = 2.0
    /// 相邻帧最大间隔（秒），超过重新计时
    static let maxGap = 0.5

    /// offsetB：屏幕 B 相对屏幕 A 的偏航（度，右转为正）。
    /// 返回给引擎的姿态：yaw 已重映射为「离最近屏幕的偏航」，pitch/roll 原样。
    /// allowSnap 为 false（有动作正在触发等）时只重映射、不修正。
    mutating func remap(_ pose: HeadPose, offsetB: Double, allowSnap: Bool) -> HeadPose {
        defer { previousTime = pose.timestamp }
        let y = pose.yaw - correction
        let dA = y
        let dB = y - offsetB
        let nearestIsA = abs(dA) <= abs(dB)

        // 稳定性判定：连续帧 yaw/pitch 都在抖动范围内，且持续满 snapStability
        var stable = false
        if allowSnap {
            if let pt = previousTime, pose.timestamp > pt, pose.timestamp - pt <= Self.maxGap,
               let cand = candidate,
               abs(pose.yaw - cand.yaw) <= Self.jitter, abs(pose.pitch - cand.pitch) <= Self.jitter {
                if pose.timestamp - cand.t >= Self.snapStability { stable = true }
            } else {
                candidate = (pose.yaw, pose.pitch, pose.timestamp)
            }
        } else {
            candidate = nil
        }

        var out = pose
        let d = nearestIsA ? dA : dB
        out.yaw = d
        // 快照重锚：确认稳稳待在某块屏前，把当前残差（漂移）一次性清零
        if stable, abs(d) < Self.snapCone {
            correction += d
            out.yaw = 0
        }
        return out
    }

    mutating func reset() {
        correction = 0
        candidate = nil
        previousTime = nil
    }
}
