import AppKit
import Combine

enum Language: String, CaseIterable, Identifiable {
    case system, en, zh
    var id: String { rawValue }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

/// 极简多语言：一张 key → (en, zh) 表。运行时切换，不走 .strings 那套需要重启的机制。
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "ui.language") }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "ui.appearance"); applyAppearance() }
    }

    private init() {
        let d = UserDefaults.standard
        language = Language(rawValue: d.string(forKey: "ui.language") ?? "") ?? .system
        appearance = Appearance(rawValue: d.string(forKey: "ui.appearance") ?? "") ?? .system
        // 这里不要 applyAppearance()：App.init 阶段 NSApp 还没建好，会崩
    }

    /// 实际生效的语言：系统是中文就中文，其余一律英文
    var effective: Language {
        guard language == .system else { return language }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("zh") ? .zh : .en
    }

    func t(_ key: String) -> String {
        guard let pair = Self.table[key] else { return key }
        return effective == .zh ? pair.zh : pair.en
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    func applyAppearance() {
        let app = NSApplication.shared   // 用 shared 而不是 NSApp：前者按需创建，后者启动早期是 nil
        switch appearance {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Strings

    private static let table: [String: (en: String, zh: String)] = [
        // status
        "status.unsupported": ("Headphone motion not supported", "系统不支持耳机运动数据"),
        "status.denied": ("Motion & Fitness access denied", "「运动与健身」权限被拒绝"),
        "status.restricted": ("Motion access restricted", "权限受限"),
        "status.waitingPermission": ("Waiting for permission", "等待授权"),
        "status.waitingHeadphones": ("No head-tracking headphones", "未检测到支持头部追踪的耳机"),
        "status.tracking": ("Tracking (%@)", "正在追踪（%@）"),
        "side.left": ("left", "左耳"),
        "side.right": ("right", "右耳"),
        "side.unknown": ("unknown", "未知"),

        // device section
        "device.systemSupport": ("System support", "系统支持"),
        "device.yes": ("Yes", "是"),
        "device.no": ("No", "否"),
        "device.permission": ("Motion & Fitness", "运动与健身权限"),
        "auth.authorized": ("Granted", "已授权"),
        "auth.denied": ("Denied", "已拒绝"),
        "auth.restricted": ("Restricted", "受限"),
        "auth.notDetermined": ("Not asked", "未询问"),
        "auth.unknown": ("Unknown", "未知"),
        "device.openSettings": ("Settings…", "去设置"),
        "device.source": ("Data source", "数据来源"),
        "device.hint": ("Wear AirPods / Beats that support head tracking, and make sure they are connected to this Mac, not your iPhone.", "戴上支持头部追踪的 AirPods / Beats，并确认它连接的是这台 Mac，不是 iPhone。"),

        // pose section
        "pose.yaw": ("Yaw", "左右转头 Yaw"),
        "pose.pitch": ("Pitch", "点头 Pitch"),
        "pose.roll": ("Roll", "歪头 Roll"),
        "pose.calibrate": ("Set current pose as forward", "以当前姿态为正前方"),
        "pose.recalibrate": ("Recalibrate forward", "重新校准正前方"),
        "pose.help": ("Sit up straight and look at the screen, then click. All angles are measured from this pose. Right turn and head-up are positive.", "坐正、平视屏幕时点一下，之后所有角度都相对这个姿态计算。右转、抬头为正。"),

        // blur action
        "blur.title": ("Blur screen when looking away", "看向别处时模糊屏幕"),
        "blur.help": ("When your head turns left or right past the trigger angle and stays there, the screen blurs. It clears as soon as you look back.", "头向左或向右转过触发角度并停留一会儿，屏幕模糊；转回来即恢复。"),
        "blur.threshold": ("Trigger angle", "触发角度"),
        "blur.dwell": ("Delay before blur", "转开多久后触发"),
        "blur.dim": ("Dimming", "压暗程度"),
        "blur.blurred": ("Blurred", "已模糊"),

        // posture action
        "posture.title": ("Posture reminder", "坐姿提醒"),
        "posture.help": ("When you slouch, your head tilts up to keep looking at the screen. If pitch passes the trigger angle and stays there, the screen blurs until you sit up. Press Esc to dismiss and pause for a minute. A positive angle watches head-up only; a negative angle watches head-down only.", "弯腰塌下去时头会仰起来看屏幕。Pitch 越过触发角度并持续一段时间，屏幕模糊，坐直即恢复。按 Esc 解除并暂停 1 分钟。角度为正只盯抬头，为负只盯低头。"),
        "posture.threshold": ("Trigger angle (now %@°)", "触发角度（当前 %@°）"),
        "posture.dwell": ("Hold before reminding", "持续多久后提醒"),
        "posture.dismiss": ("Dismiss, pause 1 min", "解除并暂停 1 分钟"),
        "posture.reminding": ("Reminding", "提醒中"),
        "posture.snoozed": ("Paused until %@", "已暂停至 %@"),
        "posture.overlay": ("Sit up straight\nPitch %+.0f°\n\nPress Esc to pause for %.0f s", "坐直一点\nPitch %+.0f°\n\n按 Esc 暂停 %.0f 秒"),

        // common
        "common.preview": ("Preview 2 s", "预览 2 秒"),
        "common.quit": ("Quit", "退出"),
        "settings.language": ("Language", "语言"),
        "settings.appearance": ("Appearance", "外观"),
        "lang.system": ("System", "跟随系统"),
        "lang.en": ("English", "English"),
        "lang.zh": ("中文", "中文"),
        "appearance.system": ("System", "跟随系统"),
        "appearance.light": ("Light", "亮色"),
        "appearance.dark": ("Dark", "暗色"),
    ]
}
