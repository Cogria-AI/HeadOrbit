import CoreMotion
import Foundation

/// 调试用：启动参数带 `--record-motion` 时，把每一帧原始数据写进
/// ~/Library/Logs/HeadOrbit/motion-<时间>.csv，用来离线分析三个轴在各种动作下怎么变。
final class MotionRecorder {
    static let shared: MotionRecorder? = CommandLine.arguments.contains("--record-motion") ? MotionRecorder() : nil

    private let handle: FileHandle

    private init?() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HeadOrbit")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("motion-\(f.string(from: Date())).csv")
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let h = try? FileHandle(forWritingTo: url) else { return nil }
        handle = h
        write("t,yaw,pitch,roll,rawYaw,rawPitch,rawRoll,qw,qx,qy,qz,rotX,rotY,rotZ,gravX,gravY,gravZ,accX,accY,accZ,sensor\n")
    }

    /// pose 是减去校准基准后的角度（度，yaw 已取反），其余是 CoreMotion 原始值
    func record(_ m: CMDeviceMotion, pose: HeadPose) {
        let a = m.attitude, q = a.quaternion, r = m.rotationRate, g = m.gravity, u = m.userAcceleration
        let cols: [Double] = [m.timestamp, pose.yaw, pose.pitch, pose.roll,
                              a.yaw.degrees, a.pitch.degrees, a.roll.degrees,
                              q.w, q.x, q.y, q.z, r.x, r.y, r.z, g.x, g.y, g.z, u.x, u.y, u.z]
        write(cols.map { String(format: "%.4f", $0) }.joined(separator: ",") + ",\(m.sensorLocation.rawValue)\n")
    }

    /// 校准时打一行标记，分析时好切段
    func mark(_ label: String) { write("# \(label)\n") }

    private func write(_ s: String) { handle.write(Data(s.utf8)) }
}
