import SwiftUI

/// 一个场景的详情：开关、名字，以及扭头 / 点头 / 歪头三个动作，每个动作分两个方向设置行为
struct SceneEditor: View {
    let sceneID: String
    @EnvironmentObject private var store: SceneStore
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var conflict: String?

    var body: some View {
        if let scene = store.scene(sceneID) {
            Form {
                Section {
                    Toggle(isOn: enabledBinding(scene)) {
                        if scene.isBuiltin {
                            Text(l10n.t("scene.enabled")).font(.headline)
                        } else {
                            TextField(l10n.t("scene.name"), text: nameBinding)
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .toggleStyle(.switch)
                    if scene.isBuiltin {
                        Text(l10n.t("scene.\(scene.id).desc")).font(.callout).foregroundStyle(.secondary)
                    }
                    if scene.needsAccessibility {
                        Text(l10n.t("scene.needsAccessibility")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(Axis.allCases) { axis in
                    AxisEditor(sceneID: sceneID, axis: axis)
                }
                Section {
                    HStack {
                        Button(l10n.t("scene.duplicate")) {
                            if let id = store.duplicate(sceneID, named: l10n.t("scene.copyName", scene.displayName)) {
                                router.selection = .scene(id)
                            }
                        }
                        Spacer()
                        if scene.isBuiltin {
                            Button(l10n.t("scene.reset")) { store.resetBuiltin(sceneID) }
                        } else {
                            Button(l10n.t("scene.delete"), role: .destructive) {
                                store.delete(sceneID)
                                router.selection = .scene("privacy")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(scene.displayName)
            .alert(l10n.t("scene.conflictTitle"), isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
                Button("OK") { conflict = nil }
            } message: {
                Text(conflict ?? "")
            }
            .onChange(of: scene.isEnabled && scene.needsAccessibility) { needs in
                if needs, !KeySender.isTrusted { KeySender.requestTrust() }
            }
        }
    }

    private func enabledBinding(_ scene: SceneConfig) -> Binding<Bool> {
        Binding(get: { scene.isEnabled }, set: { on in
            let c = store.setEnabled(sceneID, on)
            if !c.isEmpty {
                let list = c.map { l10n.t("scene.conflictItem", $0.0.title, $0.1.displayName) }.joined(separator: "\n")
                conflict = l10n.t("scene.conflictBody", list)
            }
        })
    }

    private var nameBinding: Binding<String> {
        Binding(get: { store.scene(sceneID)?.name ?? "" }, set: { v in store.update(sceneID) { $0.name = v } })
    }
}

/// 一个动作（扭头 / 点头 / 歪头）：一条双向的实时角度条，下面是两个方向各自的行为
private struct AxisEditor: View {
    let sceneID: String
    let axis: Axis
    @EnvironmentObject private var store: SceneStore
    @EnvironmentObject private var engine: SceneEngine
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let scene = store.scene(sceneID)
        let bindings = axis.directions.compactMap { g in scene?.bindings.first { $0.gesture == g } }
        Section(axis.title) {
            AxisGauge(feed: engine.feed, axis: axis, bindings: bindings, isMine: scene?.isEnabled == true)
            ForEach(axis.directions) { g in
                DirectionEditor(sceneID: sceneID, gesture: g)
            }
        }
    }
}

/// 一个方向：选行为（「无」就是这一边不触发），选了才展开参数
private struct DirectionEditor: View {
    let sceneID: String
    let gesture: Gesture
    @EnvironmentObject private var store: SceneStore
    @EnvironmentObject private var engine: SceneEngine
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let scene = store.scene(sceneID)
        let current = scene?.bindings.first { $0.gesture == gesture }
        let owner = scene?.isEnabled == true ? store.owner(of: gesture, excluding: sceneID) : nil
        VStack(alignment: .leading, spacing: 8) {
            Picker(l10n.t("dir." + gesture.rawValue), selection: kindBinding(current)) {
                Text(l10n.t("behavior.none")).tag(Behavior.Kind?.none)
                ForEach(Behavior.kinds(for: gesture)) { Text(l10n.t("behavior." + $0.rawValue)).tag(Behavior.Kind?.some($0)) }
            }
            .disabled(owner != nil)
            if let owner {
                Text(l10n.t("binding.usedBy", owner.displayName)).font(.caption).foregroundStyle(.secondary)
            }
            if let current {
                params(current)
                    .padding(.leading, 16)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func params(_ b: GestureBinding) -> some View {
        let isPosture = b.behavior.kind == .posture
        switch b.behavior {
        case .blur(let dim):
            HStack(alignment: .bottom) {
                LabeledSlider(label: l10n.t("binding.dim"), value: Binding(get: { dim }, set: { v in set { $0.behavior = .blur(dim: v) } }),
                              range: 0...0.6, step: 0.05, unit: "")
                Button(l10n.t("common.preview")) { engine.previewBlur(dim: dim) }
            }
        case .posture:
            HStack(alignment: .top) {
                Text(l10n.t("binding.postureHelp")).font(.caption).foregroundStyle(.secondary)
                Button(l10n.t("common.preview")) { engine.posture.preview() }
            }
        case .tapKey(let k), .holdKey(let k):
            LabeledContent(l10n.t("binding.key")) {
                KeyRecorder(combo: Binding(get: { k }, set: { new in
                    set { $0.behavior = $0.behavior.kind == .tapKey ? .tapKey(new) : .holdKey(new) }
                }))
            }
            Text(l10n.t(b.behavior.kind == .tapKey ? "binding.tapHelp" : "binding.holdHelp"))
                .font(.caption).foregroundStyle(.secondary)
        }
        LabeledSlider(label: l10n.t(isPosture ? "binding.postureThreshold" : "binding.threshold"),
                      value: Binding(get: { b.threshold }, set: { v in set { $0.threshold = v } }),
                      range: isPosture ? -90...90 : 1...90, step: 1, unit: "°")
        LabeledSlider(label: l10n.t("binding.dwell"),
                      value: Binding(get: { b.dwell }, set: { v in set { $0.dwell = v } }),
                      range: isPosture ? 1...30 : 0...2, step: isPosture ? 1 : 0.1, unit: "s")
    }

    private func kindBinding(_ current: GestureBinding?) -> Binding<Behavior.Kind?> {
        Binding(get: { current?.behavior.kind }, set: { store.setBehavior($0, for: gesture, in: sceneID) })
    }

    private func set(_ change: @escaping (inout GestureBinding) -> Void) {
        store.update(sceneID) { s in
            if let i = s.bindings.firstIndex(where: { $0.gesture == gesture }) { change(&s.bindings[i]) }
        }
    }
}

/// 只有它订阅每帧姿态。标出两个方向的触发线
private struct AxisGauge: View {
    @ObservedObject var feed: PoseFeed
    let axis: Axis
    let bindings: [GestureBinding]
    let isMine: Bool
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        // 坐姿提醒看的是手动校准的姿态，点头这条线跟着它走
        let usesRaw = bindings.contains { $0.behavior.kind == .posture }
        let value = axis.value(usesRaw ? feed.raw : feed.forward)
        let active = isMine && bindings.contains { feed.active.contains($0.gesture) }
        AngleGauge(label: l10n.t("binding.now"), value: value,
                   markers: bindings.map { $0.gesture.sign * $0.threshold },
                   highlight: active, labelWidth: 60)
    }
}
