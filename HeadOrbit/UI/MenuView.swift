import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var tracker: HeadTracker
    @EnvironmentObject private var blur: LookAwayBlurAction
    @EnvironmentObject private var posture: PostureReminderAction
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            deviceSection
            Divider()
            poseSection
            Divider()
            blurSection
            Divider()
            postureSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { tracker.refresh() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Circle()
                .fill(tracker.status.isTracking ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text("HeadOrbit").font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(l10n.t("device.systemSupport"), l10n.t(tracker.isDeviceMotionAvailable ? "device.yes" : "device.no"))
            HStack {
                row(l10n.t("device.permission"), authorizationText)
                if tracker.authorization == .denied || tracker.authorization == .restricted {
                    Button(l10n.t("device.openSettings")) { openMotionPrivacySettings() }
                        .controlSize(.small)
                }
            }
            if case .tracking(let side) = tracker.status {
                row(l10n.t("device.source"), sideText(side))
            } else if tracker.authorization == .authorized {
                HStack(spacing: 6) {
                    Text(l10n.t("status.waitingHeadphones")).font(.callout).foregroundStyle(.secondary)
                    info("device.hint")
                    Spacer()
                    Button(l10n.t("device.reconnect")) { tracker.reconnect() }
                        .controlSize(.small)
                }
            }
            if let err = tracker.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var poseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            gauge(l10n.t("pose.yaw"), tracker.pose.yaw, highlight: blur.isEnabled && abs(tracker.pose.yaw) > blur.thresholdDegrees)
            gauge(l10n.t("pose.pitch"), tracker.pose.pitch, highlight: posture.isEnabled && posture.isOver(tracker.pose.pitch))
            HStack(spacing: 6) {
                Button(l10n.t(tracker.isCalibrated ? "pose.recalibrate" : "pose.calibrate")) { tracker.recenter() }
                    .disabled(!tracker.status.isTracking)
                    .controlSize(.small)
                info("pose.help")
            }
        }
    }

    private var blurSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle(l10n.t("blur.title"), isOn: $blur.isEnabled)
                info("blur.help")
            }
            Group {
                labeledSlider(l10n.t("blur.threshold"), value: $blur.thresholdDegrees, range: 0...90, step: 1, unit: "°")
                labeledSlider(l10n.t("blur.dwell"), value: $blur.dwellSeconds, range: 0...2, step: 0.1, unit: "s")
                labeledSlider(l10n.t("blur.dim"), value: $blur.dimAmount, range: 0...0.6, step: 0.05, unit: "")
            }
            .disabled(!blur.isEnabled)
            HStack {
                Button(l10n.t("common.preview")) { blur.preview() }
                    .controlSize(.small)
                Spacer()
                if blur.isBlurred {
                    Text(l10n.t("blur.blurred")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var postureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle(l10n.t("posture.title"), isOn: $posture.isEnabled)
                info("posture.help")
            }
            Group {
                labeledSlider(l10n.t("posture.threshold", String(format: "%+.0f", tracker.pose.pitch)),
                              value: $posture.thresholdDegrees, range: -90...90, step: 1, unit: "°")
                labeledSlider(l10n.t("posture.dwell"), value: $posture.dwellSeconds, range: 1...30, step: 1, unit: "s")
            }
            .disabled(!posture.isEnabled)
            HStack {
                Button(l10n.t("common.preview")) { posture.preview() }
                    .controlSize(.small)
                if posture.isReminding {
                    Button(l10n.t("posture.dismiss")) { posture.dismiss() }
                        .controlSize(.small)
                }
                Spacer()
                if posture.isReminding {
                    Text(l10n.t("posture.reminding")).font(.caption).foregroundStyle(.orange)
                } else if let until = posture.snoozedUntil, until > Date() {
                    Text(l10n.t("posture.snoozed", until.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Picker(l10n.t("settings.language"), selection: $l10n.language) {
                ForEach(Language.allCases) { Text(l10n.t("lang.\($0.rawValue)")).tag($0) }
            }
            Picker(l10n.t("settings.appearance"), selection: $l10n.appearance) {
                ForEach(Appearance.allCases) { Text(l10n.t("appearance.\($0.rawValue)")).tag($0) }
            }
            Spacer()
            Button(l10n.t("common.quit")) { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .labelsHidden()
    }

    // MARK: Text helpers

    private var statusText: String {
        switch tracker.status {
        case .unsupported: return l10n.t("status.unsupported")
        case .denied: return l10n.t("status.denied")
        case .restricted: return l10n.t("status.restricted")
        case .waitingForPermission: return l10n.t("status.waitingPermission")
        case .waitingForHeadphones: return l10n.t("status.waitingHeadphones")
        case .tracking(let side): return l10n.t("status.tracking", sideText(side))
        }
    }

    private func sideText(_ side: SensorSide) -> String {
        switch side {
        case .left: return l10n.t("side.left")
        case .right: return l10n.t("side.right")
        case .unknown: return l10n.t("side.unknown")
        }
    }

    private var authorizationText: String {
        switch tracker.authorization {
        case .authorized: return l10n.t("auth.authorized")
        case .denied: return l10n.t("auth.denied")
        case .restricted: return l10n.t("auth.restricted")
        case .notDetermined: return l10n.t("auth.notDetermined")
        @unknown default: return l10n.t("auth.unknown")
        }
    }

    // MARK: View helpers

    /// 小 ⓘ 图标，鼠标悬停显示说明
    private func info(_ key: String) -> some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(l10n.t(key))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private func gauge(_ label: String, _ value: Double, highlight: Bool) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let x = half + (max(-90, min(90, value)) / 90) * half
                    Capsule()
                        .fill(highlight ? Color.orange : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: x - 3)
                }
            }
            .frame(height: 6)
            Text(String(format: "%+.0f°", value))
                .font(.system(.callout, design: .monospaced))
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: step < 1 ? "%.2f%@" : (range.lowerBound < 0 ? "%+.0f%@" : "%.0f%@"), value.wrappedValue, unit))
                    .font(.system(.callout, design: .monospaced))
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func openMotionPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") {
            NSWorkspace.shared.open(url)
        }
    }
}
