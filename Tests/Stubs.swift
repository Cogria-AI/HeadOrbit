import Foundation
import Combine
final class BlurOverlayController {
    static let shared = BlurOverlayController()
    var owners = Set<String>()
    func request(_ id: String, dim: Double, message: String? = nil) { owners.insert(id) }
    func release(_ id: String) { owners.remove(id) }
}
final class GlobalHotKey {
    static let escape: UInt32 = 53
    init(keyCode: UInt32, onPress: @escaping () -> Void) {}
    func register() {}
    func unregister() {}
}
final class L10n {
    static let shared = L10n()
    func t(_ key: String, _ args: CVarArg...) -> String { key }
}
final class HeadTracker {
    enum Status: Equatable { case tracking, disconnected
        var isTracking: Bool { self == .tracking }
    }
    @Published var status: Status = .tracking
    @Published var isCalibrated = false
    let samples = PassthroughSubject<HeadPose, Never>()
    let didRecenter = PassthroughSubject<Void, Never>()
}
