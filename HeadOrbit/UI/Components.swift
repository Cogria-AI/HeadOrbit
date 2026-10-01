import SwiftUI

/// 菜单和设置窗口共用的小部件

/// 小 ⓘ 图标，鼠标悬停显示说明
struct InfoIcon: View {
    let key: String
    @ObservedObject private var l10n = L10n.shared

    init(_ key: String) { self.key = key }

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(l10n.t(key))
    }
}

/// -90…90° 的横条，点是当前值；可选标几条触发线
struct AngleGauge: View {
    let label: String
    let value: Double
    var markers: [Double] = []
    var highlight = false
    var labelWidth: CGFloat = 90

    var body: some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let x = { (v: Double) in half + (max(-90, min(90, v)) / 90) * half }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 6)
                    ForEach(markers.indices, id: \.self) { i in
                        Rectangle().fill(Color.orange.opacity(0.7)).frame(width: 2, height: 12).offset(x: x(markers[i]) - 1)
                    }
                    Capsule()
                        .fill(highlight ? Color.orange : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: x(value.isFinite ? value : 0) - 3)
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            Text(value.isFinite ? String(format: "%+.0f°", value) : "—")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 48, alignment: .trailing)
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: step < 1 ? "%.2f%@" : (range.lowerBound < 0 ? "%+.0f%@" : "%.0f%@"), value, unit))
                    .font(.system(.callout, design: .monospaced))
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

enum StatusText {
    static func tracker(_ tracker: HeadTracker) -> String {
        let l10n = L10n.shared
        switch tracker.status {
        case .unsupported: return l10n.t("status.unsupported")
        case .denied: return l10n.t("status.denied")
        case .restricted: return l10n.t("status.restricted")
        case .waitingForPermission: return l10n.t("status.waitingPermission")
        case .waitingForHeadphones: return l10n.t(tracker.headphonesRoutedAway ? "status.routedAway" : "status.waitingHeadphones")
        case .tracking(let s): return l10n.t("status.tracking", side(s))
        }
    }

    static func side(_ side: SensorSide) -> String {
        switch side {
        case .left: return L10n.shared.t("side.left")
        case .right: return L10n.shared.t("side.right")
        case .unknown: return L10n.shared.t("side.unknown")
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// 设置窗口当前页。菜单里点「关于」也是打开设置窗口并跳到这一页
enum SettingsPage: Hashable {
    case scene(String), calibration, general, about
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var selection: SettingsPage? = .scene("privacy")
}

extension Gesture {
    var title: String { L10n.shared.t("gesture." + rawValue) }
}

extension Axis {
    var title: String { L10n.shared.t("axis." + rawValue) }
}

extension SceneConfig {
    var displayName: String { isBuiltin ? L10n.shared.t("scene." + id) : (name.isEmpty ? L10n.shared.t("scene.untitled") : name) }
}
