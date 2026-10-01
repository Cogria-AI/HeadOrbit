import Combine
import Foundation

/// 场景里的一条：哪个动作、偏多少度、保持多久，触发什么行为
struct GestureBinding: Codable, Equatable, Identifiable {
    var gesture: Gesture
    var threshold: Double
    var dwell: Double
    var behavior: Behavior

    var id: Gesture { gesture }
}

/// 一组「动作 → 行为」。预置场景和用户自建场景是同一种东西，只是预置的不能删、名字走多语言
struct SceneConfig: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isBuiltin: Bool
    var isEnabled: Bool
    var bindings: [GestureBinding]

    var gestures: Set<Gesture> { Set(bindings.map(\.gesture)) }
    var needsAccessibility: Bool { bindings.contains { $0.behavior.needsAccessibility } }

    static let privacy = SceneConfig(id: "privacy", name: "", isBuiltin: true, isEnabled: true, bindings: [
        GestureBinding(gesture: .turnLeft, threshold: 35, dwell: 0.6, behavior: .blur(dim: 0.15)),
        GestureBinding(gesture: .turnRight, threshold: 35, dwell: 0.6, behavior: .blur(dim: 0.15)),
    ])
    static let posture = SceneConfig(id: "posture", name: "", isBuiltin: true, isEnabled: false, bindings: [
        GestureBinding(gesture: .lookUp, threshold: 15, dwell: 5, behavior: .posture),
    ])
    static let voice = SceneConfig(id: "voice", name: "", isBuiltin: true, isEnabled: false, bindings: [
        GestureBinding(gesture: .tiltLeft, threshold: 15, dwell: 0.2, behavior: .holdKey(.fn)),
        GestureBinding(gesture: .tiltRight, threshold: 15, dwell: 0.3, behavior: .tapKey(.returnKey)),
    ])
    static let builtins = [privacy, posture, voice]
}

/// 所有场景 + 校准相关设置，存在 UserDefaults
final class SceneStore: ObservableObject {
    @Published private(set) var scenes: [SceneConfig] { didSet { save() } }
    @Published var autoCalibration: Bool { didSet { defaults.set(autoCalibration, forKey: "blur.autoCalibration") } }

    private let defaults: UserDefaults
    private static let key = "scenes.v1"

    init(defaults d: UserDefaults = .standard) {
        defaults = d
        autoCalibration = d.object(forKey: "blur.autoCalibration") as? Bool ?? false
        var loaded = (d.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([SceneConfig].self, from: $0) }
            ?? Self.migrateLegacy(d)
        // 以后新增的预置场景，老用户也能看到（默认关）
        for b in SceneConfig.builtins where !loaded.contains(where: { $0.id == b.id }) {
            loaded.append(SceneConfig(id: b.id, name: b.name, isBuiltin: true, isEnabled: false, bindings: b.bindings))
        }
        scenes = loaded
        save()
    }

    /// 已开启的场景里，谁占着这个动作
    func owner(of gesture: Gesture, excluding id: String? = nil) -> SceneConfig? {
        scenes.first { $0.isEnabled && $0.id != id && $0.gestures.contains(gesture) }
    }

    /// 开启这个场景会和哪些已开启场景抢动作
    func conflicts(for id: String) -> [(Gesture, SceneConfig)] {
        guard let s = scene(id) else { return [] }
        return s.bindings.compactMap { b in owner(of: b.gesture, excluding: id).map { (b.gesture, $0) } }
    }

    /// 有冲突就不开启，返回冲突列表交给界面提示
    @discardableResult
    func setEnabled(_ id: String, _ on: Bool) -> [(Gesture, SceneConfig)] {
        if on {
            let c = conflicts(for: id)
            guard c.isEmpty else { return c }
        }
        update(id) { $0.isEnabled = on }
        return []
    }

    func scene(_ id: String) -> SceneConfig? { scenes.first { $0.id == id } }

    func update(_ id: String, _ change: (inout SceneConfig) -> Void) {
        guard let i = scenes.firstIndex(where: { $0.id == id }) else { return }
        var s = scenes[i]
        change(&s)
        // 同一场景里一个动作只出现一次
        var seen = Set<Gesture>()
        s.bindings = s.bindings.filter { seen.insert($0.gesture).inserted }
        if s != scenes[i] { scenes[i] = s }
    }

    /// 设置某个方向的行为；nil 表示「无」，从场景里去掉这个方向
    func setBehavior(_ kind: Behavior.Kind?, for g: Gesture, in id: String) {
        update(id) { s in
            guard let kind else { s.bindings.removeAll { $0.gesture == g }; return }
            if let i = s.bindings.firstIndex(where: { $0.gesture == g }) {
                var b = s.bindings[i]
                guard b.behavior.kind != kind else { return }
                b.behavior = Behavior.make(kind, keeping: b.behavior)
                if kind == .posture { b.threshold = 15; b.dwell = 5 }
                else {
                    if b.dwell > 2 { b.dwell = g.defaultDwell }
                    if b.threshold < 1 { b.threshold = g.defaultThreshold }
                }
                s.bindings[i] = b
            } else {
                let posture = kind == .posture
                s.bindings.append(GestureBinding(gesture: g, threshold: posture ? 15 : g.defaultThreshold,
                                                 dwell: posture ? 5 : g.defaultDwell, behavior: Behavior.make(kind)))
            }
        }
    }

    /// 新建空场景，返回 id
    func addScene(named name: String) -> String {
        let s = SceneConfig(id: UUID().uuidString, name: name, isBuiltin: false, isEnabled: false, bindings: [])
        scenes.append(s)
        return s.id
    }

    func duplicate(_ id: String, named name: String) -> String? {
        guard var s = scene(id) else { return nil }
        s.id = UUID().uuidString
        s.name = name
        s.isBuiltin = false
        s.isEnabled = false
        scenes.append(s)
        return s.id
    }

    func delete(_ id: String) {
        scenes.removeAll { $0.id == id && !$0.isBuiltin }
    }

    /// 预置场景恢复出厂参数（保留开关状态；恢复后若和别的场景冲突就关掉）
    func resetBuiltin(_ id: String) {
        guard let b = SceneConfig.builtins.first(where: { $0.id == id }) else { return }
        update(id) { $0.bindings = b.bindings }
        if !conflicts(for: id).isEmpty { update(id) { $0.isEnabled = false } }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) { defaults.set(data, forKey: Self.key) }
    }

    /// v0.1.x 的「看向别处模糊」「坐姿提醒」两套设置转成场景，升级后行为不变
    static func migrateLegacy(_ d: UserDefaults) -> [SceneConfig] {
        let threshold = max(1, d.object(forKey: "blur.threshold") as? Double ?? 35)
        let dwell = d.object(forKey: "blur.dwell") as? Double ?? 0.6
        let dim = d.object(forKey: "blur.dim") as? Double ?? 0.15
        var privacy = SceneConfig.privacy
        privacy.isEnabled = d.object(forKey: "blur.enabled") as? Bool ?? true
        privacy.bindings = [
            GestureBinding(gesture: .turnLeft, threshold: d.object(forKey: "blur.left") as? Double ?? threshold, dwell: dwell, behavior: .blur(dim: dim)),
            GestureBinding(gesture: .turnRight, threshold: d.object(forKey: "blur.right") as? Double ?? threshold, dwell: dwell, behavior: .blur(dim: dim)),
        ]
        var posture = SceneConfig.posture
        posture.isEnabled = d.object(forKey: "posture.enabled") as? Bool ?? false
        posture.bindings = [GestureBinding(
            gesture: .lookUp,
            threshold: d.object(forKey: "posture.threshold.v2") as? Double ?? 15,
            dwell: d.object(forKey: "posture.dwell") as? Double ?? 5,
            behavior: .posture)]
        if d.object(forKey: "blur.verticalEnabled") as? Bool ?? false {
            // 抬头只能归一个场景：坐姿提醒是用户主动打开的，它优先
            if !(privacy.isEnabled && posture.isEnabled) {
                privacy.bindings.append(GestureBinding(gesture: .lookUp, threshold: d.object(forKey: "blur.up") as? Double ?? 35, dwell: dwell, behavior: .blur(dim: dim)))
            }
            privacy.bindings.append(GestureBinding(gesture: .lookDown, threshold: d.object(forKey: "blur.down") as? Double ?? 35, dwell: dwell, behavior: .blur(dim: dim)))
        }
        return [privacy, posture, SceneConfig.voice]
    }
}
