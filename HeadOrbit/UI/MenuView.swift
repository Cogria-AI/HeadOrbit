import SwiftUI

/// 菜单栏面板：只用来快速看耳机在不在工作、灵不灵敏。配置都在设置窗口里
struct MenuView: View {
    @EnvironmentObject private var tracker: HeadTracker
    @EnvironmentObject private var engine: SceneEngine
    @EnvironmentObject private var exercise: ExerciseController
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            deviceHint
            Divider()
            MenuPose(feed: engine.feed)
            calibrateRow
            Divider()
            exerciseRow
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { tracker.refresh() }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(tracker.status.isTracking ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text("HeadOrbit").font(.headline)
            Spacer()
            Text(StatusText.tracker(tracker))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deviceHint: some View {
        if !tracker.status.isTracking, tracker.authorization == .authorized {
            HStack(spacing: 6) {
                if tracker.headphonesRoutedAway {
                    Text(l10n.t("device.routedAwayShort")).font(.caption).foregroundStyle(.secondary)
                } else {
                    InfoIcon("device.hint")
                    Spacer()
                    Button(l10n.t(tracker.isReconnecting ? "device.reconnecting" : "device.reconnect")) { tracker.reconnect() }
                        .controlSize(.small)
                        .disabled(tracker.isReconnecting)
                }
            }
        } else if tracker.authorization == .denied || tracker.authorization == .restricted {
            Button(l10n.t("device.openSettings")) { Permissions.openMotionSettings() }
                .controlSize(.small)
        }
        if let err = tracker.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
        }
    }

    private var calibrateRow: some View {
        HStack(spacing: 6) {
            Button(l10n.t(tracker.isCalibrated ? "pose.recalibrate" : "pose.calibrate")) { tracker.recenter() }
                .disabled(!tracker.status.isTracking)
                .controlSize(.small)
            InfoIcon("pose.help")
        }
    }

    private var exerciseRow: some View {
        HStack(spacing: 6) {
            Button(l10n.t("exercise.start")) {
                // 先收起面板，否则它会挡在练习画面上面
                NSApplication.shared.keyWindow?.close()
                exercise.start()
            }
            .disabled(!tracker.status.isTracking || exercise.isRunning)
            .controlSize(.small)
            InfoIcon("exercise.help")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(l10n.t("menu.settings")) { open(nil) }
                .keyboardShortcut(",")
            Button(l10n.t("menu.about")) { open(.about) }
            Spacer()
            Text("v" + StatusText.version).font(.caption).foregroundStyle(.secondary)
            Button(l10n.t("common.quit")) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
    }

    private func open(_ page: SettingsPage?) {
        if let page { SettingsRouter.shared.selection = page }
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// 只有它订阅每帧姿态
private struct MenuPose: View {
    @ObservedObject var feed: PoseFeed
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let p = feed.forward
        let active = feed.active
        VStack(alignment: .leading, spacing: 6) {
            AngleGauge(label: l10n.t("pose.yaw"), value: p.yaw, highlight: !active.isDisjoint(with: [.turnLeft, .turnRight]))
            AngleGauge(label: l10n.t("pose.pitch"), value: p.pitch, highlight: !active.isDisjoint(with: [.lookUp, .lookDown]))
            AngleGauge(label: l10n.t("pose.roll"), value: p.roll, highlight: !active.isDisjoint(with: [.tiltLeft, .tiltRight]))
        }
    }
}

enum Permissions {
    static func openMotionSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
