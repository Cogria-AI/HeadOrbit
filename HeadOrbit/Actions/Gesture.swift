import Foundation

/// 六个固定动作。动作本身不带行为，行为由开启的场景提供；同一时间一个动作最多只属于一个开启的场景。
enum Gesture: String, Codable, CaseIterable, Identifiable {
    case turnLeft, turnRight, lookUp, lookDown, tiltLeft, tiltRight

    var id: String { rawValue }

    /// AirPods 的 roll 方向。真机实测后若左右反了，改这里一处即可
    static let rollSign = 1.0

    var isTilt: Bool { self == .tiltLeft || self == .tiltRight }

    /// 朝这个方向偏了多少度（朝该方向为正，反方向为负）。每个动作只看自己那根轴
    func value(_ p: HeadPose) -> Double {
        switch self {
        case .turnLeft: return -p.yaw
        case .turnRight: return p.yaw
        case .lookUp: return p.pitch
        case .lookDown: return -p.pitch
        case .tiltLeft: return -p.roll * Self.rollSign
        case .tiltRight: return p.roll * Self.rollSign
        }
    }

    /// 新加到场景里时的默认触发角度和保持时长
    var defaultThreshold: Double { isTilt ? 15 : (self == .turnLeft || self == .turnRight ? 35 : 25) }
    var defaultDwell: Double { isTilt ? 0.3 : 0.6 }
}

/// 界面上的三个动作：扭头、点头、歪头。每个动作两个方向，各自对应一个 Gesture
enum Axis: String, CaseIterable, Identifiable {
    case turn, nod, tilt

    var id: String { rawValue }

    /// 界面上的排列顺序
    var directions: [Gesture] {
        switch self {
        case .turn: return [.turnLeft, .turnRight]
        case .nod: return [.lookUp, .lookDown]
        case .tilt: return [.tiltLeft, .tiltRight]
        }
    }

    /// 带符号的角度：右扭、抬头、右歪为正
    func value(_ p: HeadPose) -> Double {
        switch self {
        case .turn: return p.yaw
        case .nod: return p.pitch
        case .tilt: return p.roll * Gesture.rollSign
        }
    }
}

extension Gesture {
    var axis: Axis { Axis.allCases.first { $0.directions.contains(self) }! }
    /// 在轴上的方向：右扭、抬头、右歪为 +1
    var sign: Double { (self == .turnLeft || self == .lookDown || self == .tiltLeft) ? -1 : 1 }
}
