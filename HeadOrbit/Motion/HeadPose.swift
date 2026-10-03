import CoreMotion
import Foundation

/// 一帧头部姿态，角度单位为「度」，已经减去校准基准（校准后正对屏幕时三项都≈0）。
struct HeadPose: Equatable {
    var yaw: Double     // 左右转头。已取反成「向右转为正」（CoreMotion 原始值是向左为正），和屏幕坐标方向一致
    var pitch: Double   // 点头。低头为负、抬头为正
    var roll: Double    // 歪头
    /// 「头顶朝向」：想象头顶插一根杆，杆尖往哪倒。x 右歪为正，y 后仰为正（度）。
    /// 颈部绕环主要是歪头 + 点头，用欧拉角画是一团乱线，用它画是一个圆（2026-10-03 实测）
    var crownX: Double = 0
    var crownY: Double = 0
    var timestamp: TimeInterval

    static let zero = HeadPose(yaw: 0, pitch: 0, roll: 0, timestamp: 0)

    init(yaw: Double, pitch: Double, roll: Double, crownX: Double = 0, crownY: Double = 0, timestamp: TimeInterval) {
        self.yaw = yaw; self.pitch = pitch; self.roll = roll
        self.crownX = crownX; self.crownY = crownY; self.timestamp = timestamp
    }

    /// attitude 已经减去校准基准；current / reference 是未减基准的原始四元数，用来算头顶朝向
    init(attitude: CMAttitude, current: CMQuaternion, reference: CMQuaternion?, timestamp: TimeInterval) {
        let c = Self.crown(current: current, reference: reference)
        self.init(yaw: -attitude.yaw.degrees, pitch: attitude.pitch.degrees, roll: attitude.roll.degrees,
                  crownX: c.x, crownY: c.y, timestamp: timestamp)
    }

    static func crown(current: CMQuaternion, reference: CMQuaternion?) -> (x: Double, y: Double) {
        // 耳机坐标系实测：x 两耳连线，y 朝前，z 朝上
        let world = current.rotate(.init(0, 0, 1))
        let up = reference.map { $0.inverseRotate(world) } ?? world
        return (asin(max(-1, min(1, up.x))).degrees, -asin(max(-1, min(1, up.y))).degrees)
    }
}

private extension CMQuaternion {
    /// 把机身坐标系里的向量转到参考坐标系（q v q*）
    func rotate(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let u = SIMD3(x, y, z)
        return v + 2 * w * cross(u, v) + 2 * cross(u, cross(u, v))
    }

    /// 反方向转（q* v q）
    func inverseRotate(_ v: SIMD3<Double>) -> SIMD3<Double> {
        CMQuaternion(x: -x, y: -y, z: -z, w: w).rotate(v)
    }
}

private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

/// 数据来自哪只耳机。只戴一只时也能拿到数据，这里告诉你是哪只在提供。
enum SensorSide {
    case left, right, unknown

    init(_ location: CMDeviceMotion.SensorLocation) {
        switch location {
        case .headphoneLeft: self = .left
        case .headphoneRight: self = .right
        default: self = .unknown
        }
    }
}

extension Double {
    var degrees: Double { self * 180 / .pi }
}
