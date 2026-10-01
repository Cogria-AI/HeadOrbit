import SwiftUI

/// 设置窗口：左边是场景列表和其他设置页，右边是详情
struct SettingsView: View {
    @EnvironmentObject private var store: SceneStore
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $router.selection) {
                Section(l10n.t("settings.scenes")) {
                    ForEach(store.scenes) { s in
                        HStack {
                            Circle()
                                .fill(s.isEnabled ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                            Text(s.displayName)
                        }
                        .tag(SettingsPage.scene(s.id))
                    }
                }
                Section(l10n.t("settings.more")) {
                    Label(l10n.t("settings.calibration"), systemImage: "scope").tag(SettingsPage.calibration)
                    Label(l10n.t("settings.general"), systemImage: "gearshape").tag(SettingsPage.general)
                    Label(l10n.t("settings.about"), systemImage: "info.circle").tag(SettingsPage.about)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    router.selection = .scene(store.addScene(named: l10n.t("scene.newName")))
                } label: {
                    Label(l10n.t("scene.new"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch router.selection {
            case .scene(let id) where store.scene(id) != nil:
                SceneEditor(sceneID: id).id(id)
            case .calibration: CalibrationPage()
            case .general: GeneralPage()
            case .about: AboutPage()
            default: Text(l10n.t("settings.pick")).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - 校准

private struct CalibrationPage: View {
    @EnvironmentObject private var tracker: HeadTracker
    @EnvironmentObject private var engine: SceneEngine
    @EnvironmentObject private var store: SceneStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                LivePose(feed: engine.feed)
                HStack {
                    Button(l10n.t(tracker.isCalibrated ? "pose.recalibrate" : "pose.calibrate")) { tracker.recenter() }
                        .disabled(!tracker.status.isTracking)
                    Spacer()
                }
                Text(l10n.t("pose.help")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(l10n.t("pose.auto"), isOn: $store.autoCalibration)
                Text(l10n.t("pose.autoHelp")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.t("settings.calibration"))
    }
}

/// 只有这个小视图订阅每帧姿态，别让整页跟着每帧重绘
private struct LivePose: View {
    @ObservedObject var feed: PoseFeed
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 6) {
            AngleGauge(label: l10n.t("pose.yaw"), value: feed.forward.yaw, labelWidth: 120)
            AngleGauge(label: l10n.t("pose.pitch"), value: feed.forward.pitch, labelWidth: 120)
            AngleGauge(label: l10n.t("pose.roll"), value: feed.forward.roll, labelWidth: 120)
        }
    }
}

// MARK: - 通用

private struct GeneralPage: View {
    @EnvironmentObject private var tracker: HeadTracker
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                Picker(l10n.t("settings.language"), selection: $l10n.language) {
                    ForEach(Language.allCases) { Text(l10n.t("lang.\($0.rawValue)")).tag($0) }
                }
                Picker(l10n.t("settings.appearance"), selection: $l10n.appearance) {
                    ForEach(Appearance.allCases) { Text(l10n.t("appearance.\($0.rawValue)")).tag($0) }
                }
            }
            Section(l10n.t("settings.device")) {
                LabeledContent(l10n.t("device.status"), value: StatusText.tracker(tracker))
                LabeledContent(l10n.t("device.systemSupport"), value: l10n.t(tracker.isDeviceMotionAvailable ? "device.yes" : "device.no"))
                if !tracker.status.isTracking, tracker.authorization == .authorized, !tracker.headphonesRoutedAway {
                    HStack {
                        Text(l10n.t("device.hint")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(l10n.t(tracker.isReconnecting ? "device.reconnecting" : "device.reconnect")) { tracker.reconnect() }
                            .disabled(tracker.isReconnecting)
                    }
                }
            }
            Section(l10n.t("settings.permissions")) {
                LabeledContent(l10n.t("device.permission")) {
                    HStack {
                        Text(motionText)
                        if tracker.authorization == .denied || tracker.authorization == .restricted {
                            Button(l10n.t("device.openSettings")) { Permissions.openMotionSettings() }
                        }
                    }
                }
                // 辅助功能授权没有回调，页面打开期间每 2 秒看一眼
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent(l10n.t("perm.accessibility")) {
                        HStack {
                            Text(l10n.t(KeySender.isTrusted ? "auth.authorized" : "perm.notGranted"))
                            if !KeySender.isTrusted {
                                Button(l10n.t("device.openSettings")) {
                                    KeySender.requestTrust()
                                    Permissions.openAccessibilitySettings()
                                }
                            }
                        }
                    }
                }
                Text(l10n.t("perm.accessibilityHelp")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.t("settings.general"))
        .onAppear { tracker.refresh() }
    }

    private var motionText: String {
        switch tracker.authorization {
        case .authorized: return l10n.t("auth.authorized")
        case .denied: return l10n.t("auth.denied")
        case .restricted: return l10n.t("auth.restricted")
        case .notDetermined: return l10n.t("auth.notDetermined")
        @unknown default: return l10n.t("auth.unknown")
        }
    }
}

// MARK: - 关于

private struct AboutPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("HeadOrbit").font(.largeTitle.weight(.semibold))
            Text(l10n.t("about.version", StatusText.version)).foregroundStyle(.secondary)
            Text(l10n.t("about.tagline")).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Link(l10n.t("about.website"), destination: URL(string: "https://headorbit.com")!)
                Link(l10n.t("about.author"), destination: URL(string: "https://x.com/rfboen")!)
                Link(l10n.t("about.github"), destination: URL(string: "https://github.com/Cogria-AI/HeadOrbit")!)
            }
            .padding(.top, 6)
            Text("MIT License · © 2026 Cogria").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(l10n.t("settings.about"))
    }
}
