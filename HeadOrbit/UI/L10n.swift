import AppKit
import Combine

enum Language: String, CaseIterable, Identifiable {
    case system, en, zh, ja
    var id: String { rawValue }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

/// 极简多语言：一张 key → (en, zh, ja) 表。运行时切换，不走 .strings 那套需要重启的机制。
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

    /// 实际生效的语言：系统是中文就中文，日文就日文，其余一律英文
    var effective: Language {
        guard language == .system else { return language }
        let first = Locale.preferredLanguages.first ?? "en"
        if first.hasPrefix("zh") { return .zh }
        if first.hasPrefix("ja") { return .ja }
        return .en
    }

    func t(_ key: String) -> String {
        guard let row = Self.table[key] else { return key }
        switch effective {
        case .zh: return row.zh
        case .ja: return row.ja
        case .en, .system: return row.en
        }
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

    private static let table: [String: (en: String, zh: String, ja: String)] = [
        // status
        "status.unsupported": ("Headphone motion not supported", "系统不支持耳机运动数据", "ヘッドフォンのモーションデータに非対応"),
        "status.denied": ("Motion & Fitness access denied", "「运动与健身」权限被拒绝", "「モーションとフィットネス」のアクセスが拒否されました"),
        "status.restricted": ("Motion access restricted", "权限受限", "モーションへのアクセスが制限されています"),
        "status.waitingPermission": ("Waiting for permission", "等待授权", "許可を待っています"),
        "status.waitingHeadphones": ("No head-tracking headphones", "未检测到支持头部追踪的耳机", "ヘッドトラッキング対応のヘッドフォンが見つかりません"),
        "status.tracking": ("Tracking (%@)", "正在追踪（%@）", "トラッキング中（%@）"),
        "side.left": ("left", "左耳", "左"),
        "side.right": ("right", "右耳", "右"),
        "side.unknown": ("unknown", "未知", "不明"),

        // device section
        "device.systemSupport": ("System support", "系统支持", "システムの対応"),
        "device.yes": ("Yes", "是", "はい"),
        "device.no": ("No", "否", "いいえ"),
        "device.permission": ("Motion & Fitness", "运动与健身权限", "モーションとフィットネス"),
        "auth.authorized": ("Granted", "已授权", "許可済み"),
        "auth.denied": ("Denied", "已拒绝", "拒否"),
        "auth.restricted": ("Restricted", "受限", "制限あり"),
        "auth.notDetermined": ("Not asked", "未询问", "未確認"),
        "auth.unknown": ("Unknown", "未知", "不明"),
        "device.openSettings": ("Settings…", "去设置", "設定を開く…"),
        "status.routedAway": ("Headphones are on another device", "耳机已切到其他设备", "ヘッドフォンは別のデバイスに接続中"),
        "device.routedAwayHint": ("Your AirPods are currently connected to another device (usually an iPhone or iPad that auto-switched). HeadOrbit does nothing about that. Tracking resumes on its own once they come back to this Mac.", "AirPods 现在连在别的设备上（通常是 iPhone / iPad 自动切换过去了）。HeadOrbit 不会去干预。等它回到这台 Mac，追踪会自动恢复。", "AirPods は現在別のデバイス（通常は自動で切り替わった iPhone / iPad）に接続されています。HeadOrbit はこれに干渉しません。この Mac に戻ると、トラッキングは自動的に再開します。"),
        "device.reconnect": ("Reconnect", "重新连接", "再接続"),
        "device.reconnecting": ("Connecting…", "连接中…", "接続中…"),
        "device.hint": ("Wear AirPods / Beats that support head tracking, and make sure they are connected to this Mac, not your iPhone.", "戴上支持头部追踪的 AirPods / Beats，并确认它连接的是这台 Mac，不是 iPhone。", "ヘッドトラッキング対応の AirPods / Beats を装着し、iPhone ではなくこの Mac に接続されていることを確認してください。"),

        // pose section
        "pose.auto": ("Adapt forward automatically", "自动微调正前方", "正面を自動微調整"),
        "pose.autoHelp": ("Calibrate manually first. Adapts after 8 s of stability near forward while nothing is triggered, within 50% of each direction's trigger angle. Posture reminders keep the manual reference. Recalibrate after larger changes.", "先手动校准。没有任何动作在触发、且在正前方附近稳定 8 秒后自动微调，各方向最多修正对应触发角度的 50%。坐姿提醒始终用手动基准；大幅调整后请重新校准。", "まず手動で校正してください。正面付近で8秒安定すると、手動基準から各方向のトリガー角度の50%以内で微調整します。姿勢の基準は変更しません。大きく動いたら再校正してください。"),
        "pose.yaw": ("Turn", "左右扭头", "左右の向き"),
        "pose.pitch": ("Nod", "上下点头", "上下の向き"),
        "pose.roll": ("Tilt", "左右歪头", "左右の傾き"),
        "pose.calibrate": ("Set current pose as forward", "以当前姿态为正前方", "現在の姿勢を正面に設定"),
        "pose.recalibrate": ("Recalibrate forward", "重新校准正前方", "正面を再キャリブレーション"),
        "pose.help": ("Sit up straight and look at the screen, then click. All angles are measured from this pose. Right turn, head-up and right tilt are positive.", "坐正、平视屏幕时点一下，之后所有角度都相对这个姿态计算。右转、抬头、右歪为正。", "背筋を伸ばして画面をまっすぐ見た状態でクリックしてください。以降の角度はすべてこの姿勢を基準に計測します。右向き・上向き・右への傾きが正の値です。"),

        // posture overlay
        "posture.overlay": ("Sit up straight\nPitch %+.0f°\n\nPress Esc to pause for %.0f s", "坐直一点\nPitch %+.0f°\n\n按 Esc 暂停 %.0f 秒", "背筋を伸ばしましょう\nPitch %+.0f°\n\nEsc キーで %.0f 秒間一時停止"),


        // menu
        "menu.settings": ("Settings…", "设置…", "設定…"),
        "menu.about": ("About", "关于", "情報"),

        // settings window
        "settings.scenes": ("Scenes", "场景", "シーン"),
        "settings.more": ("Settings", "设置", "設定"),
        "settings.calibration": ("Calibration", "校准", "キャリブレーション"),
        "settings.general": ("General", "通用", "一般"),
        "settings.about": ("About", "关于", "情報"),
        "settings.pick": ("Pick a scene on the left", "在左侧选择一个场景", "左側でシーンを選択してください"),
        "settings.device": ("Headphones", "耳机", "ヘッドフォン"),
        "settings.permissions": ("Permissions", "权限", "アクセス許可"),
        "device.status": ("Status", "状态", "状態"),
        "perm.accessibility": ("Accessibility", "辅助功能", "アクセシビリティ"),
        "perm.notGranted": ("Not granted", "未授权", "未許可"),
        "perm.accessibilityHelp": ("Only needed when a scene presses keys for you. Blur and posture reminders work without it.", "只有场景里用到「按键」时才需要。模糊和坐姿提醒不需要这项权限。", "シーンでキー操作を使う場合のみ必要です。ぼかしと姿勢リマインダーには不要です。"),

        // gestures
        "gesture.turnLeft": ("Turn left", "向左扭头", "左を向く"),
        "gesture.turnRight": ("Turn right", "向右扭头", "右を向く"),
        "gesture.lookUp": ("Look up", "抬头", "上を向く"),
        "gesture.lookDown": ("Look down", "低头", "下を向く"),
        "gesture.tiltLeft": ("Tilt left", "向左歪头", "左に傾ける"),
        "gesture.tiltRight": ("Tilt right", "向右歪头", "右に傾ける"),

        // axes and directions in the scene editor
        "axis.turn": ("Turn head", "扭头", "首を左右に向ける"),
        "axis.nod": ("Nod", "点头", "うなずき"),
        "axis.tilt": ("Tilt head", "歪头", "首をかしげる"),
        "dir.turnLeft": ("Left", "向左", "左"),
        "dir.turnRight": ("Right", "向右", "右"),
        "dir.lookUp": ("Up", "抬头", "上"),
        "dir.lookDown": ("Down", "低头", "下"),
        "dir.tiltLeft": ("Left", "向左", "左"),
        "dir.tiltRight": ("Right", "向右", "右"),
        "binding.usedBy": ("Used by %@", "已被「%@」使用", "「%@」で使用中"),

        // behaviors
        "behavior.none": ("None", "无", "なし"),
        "behavior.blur": ("Blur screen", "模糊屏幕", "画面をぼかす"),
        "behavior.posture": ("Posture reminder", "坐姿提醒", "姿勢リマインダー"),
        "behavior.tapKey": ("Press a key", "按一下按键", "キーを押す"),
        "behavior.holdKey": ("Hold a key", "按住按键", "キーを押し続ける"),
        "binding.behavior": ("Action", "行为", "動作"),
        "binding.now": ("Now", "当前", "現在"),
        "binding.dim": ("Dimming", "压暗程度", "暗さ"),
        "binding.key": ("Key", "按键", "キー"),
        "binding.threshold": ("Trigger angle", "触发角度", "トリガー角度"),
        "binding.postureThreshold": ("Trigger angle (head-up is positive)", "触发角度（抬头为正）", "トリガー角度（上向きが正）"),
        "binding.dwell": ("Hold for", "保持多久后触发", "トリガーまでの継続時間"),
        "binding.tapHelp": ("Pressed once each time you make the gesture.", "每做一次动作按一下。", "ジェスチャーのたびに 1 回押します。"),
        "binding.holdHelp": ("Held down while you keep the gesture, released when you return to forward.", "保持动作期间一直按住，回正时松开。", "ジェスチャーを続けている間は押したまま、正面に戻すと離します。"),
        "binding.postureHelp": ("When you slouch, your head tilts up to keep looking at the screen. The screen blurs until you sit up; press Esc to dismiss and pause for a minute. The angle may be 0 or negative if your calibrated pose wasn't perfectly straight.", "弯腰塌下去时头会仰起来看屏幕。超过角度并持续一段时间，屏幕模糊，坐直即恢复；按 Esc 解除并暂停 1 分钟。校准时没坐太直的话，角度也可以设成 0 或负数。", "猫背になると、画面を見続けるために頭が上を向きます。背筋を伸ばすまで画面がぼけます。Esc キーで解除して 1 分間一時停止します。キャリブレーション時の姿勢が完全にまっすぐでなかった場合は、角度を 0 や負の値にしても構いません。"),
        "key.recording": ("Press a key…", "请按键…", "キーを押してください…"),
        "key.presets": ("Common", "常用", "よく使うキー"),

        // scenes
        "scene.privacy": ("Privacy blur", "隐私模糊", "プライバシーぼかし"),
        "scene.privacy.desc": ("Turn away to talk to someone and the screen blurs; look back and it clears.", "转头和别人说话时屏幕自动模糊，转回来即恢复。", "顔をそむけて誰かと話すと画面がぼけ、戻すと元に戻ります。"),
        "scene.posture": ("Posture reminder", "坐姿提醒", "姿勢リマインダー"),
        "scene.posture.desc": ("Blurs the screen with a reminder when you slouch. Calibrate while sitting up straight first.", "弯腰塌下去时模糊屏幕并提醒坐直。请先坐正校准。", "猫背になると画面をぼかして知らせます。先に背筋を伸ばしてキャリブレーションしてください。"),
        "scene.voice": ("Voice input", "语音输入", "音声入力"),
        "scene.voice.desc": ("Tilt left to hold Fn and dictate (for input methods that start voice input on a long Fn press); tilt right to press Return.", "向左歪头按住 Fn 说话（适用于长按 Fn 开始语音输入的输入法），向右歪头按回车。", "左に傾けると Fn を押し続けて音声入力（Fn 長押しで音声入力を始める入力方式向け）、右に傾けると Return を押します。"),
        "scene.untitled": ("Untitled scene", "未命名场景", "名称未設定のシーン"),
        "scene.newName": ("My scene", "我的场景", "マイシーン"),
        "scene.copyName": ("%@ copy", "%@ 副本", "%@ のコピー"),
        "scene.new": ("New scene", "新建场景", "新規シーン"),
        "scene.name": ("Name", "名称", "名前"),
        "scene.enabled": ("Enabled", "启用", "有効"),
        "scene.duplicate": ("Duplicate", "复制", "複製"),
        "scene.reset": ("Restore defaults", "恢复默认", "デフォルトに戻す"),
        "scene.delete": ("Delete scene", "删除场景", "シーンを削除"),
        "scene.needsAccessibility": ("Pressing keys requires Accessibility permission. macOS will ask the first time.", "按键需要「辅助功能」权限，首次使用时系统会询问。", "キー操作にはアクセシビリティの許可が必要です。初回に macOS が確認します。"),
        "scene.conflictTitle": ("Gesture already in use", "动作已被占用", "ジェスチャーは使用中です"),
        "scene.conflictBody": ("Each gesture can belong to only one active scene:\n%@\n\nTurn that scene off or remove the gesture first.", "一个动作同时只能属于一个开启的场景：\n%@\n\n请先关闭那个场景，或从其中一个场景里移除这个动作。", "1 つのジェスチャーは同時に 1 つの有効なシーンにしか属せません：\n%@\n\n先にそのシーンをオフにするか、ジェスチャーを削除してください。"),
        "scene.conflictItem": ("%@ is used by %@", "%@ 已被「%@」使用", "%@ は「%@」で使用中"),

        // about
        "about.version": ("Version %@", "版本 %@", "バージョン %@"),
        "about.tagline": ("Your AirPods know where your head points.\nHeadOrbit turns that into small automations on your Mac.", "AirPods 知道你的头朝哪儿，\nHeadOrbit 把这件事变成 Mac 上的小自动化。", "AirPods はあなたの頭の向きを知っています。\nHeadOrbit はそれを Mac の小さな自動化に変えます。"),
        "about.website": ("Website: headorbit.com", "官网：headorbit.com", "公式サイト：headorbit.com"),
        "about.author": ("Contact the author on X: @rfboen", "联系作者（X）：@rfboen", "作者に連絡（X）：@rfboen"),
        "about.github": ("Source code and feedback on GitHub", "GitHub：源码与反馈", "GitHub：ソースコードとフィードバック"),

        // common
        "common.preview": ("Preview 2 s", "预览 2 秒", "2 秒プレビュー"),
        "common.quit": ("Quit", "退出", "終了"),
        "settings.language": ("Language", "语言", "言語"),
        "settings.appearance": ("Appearance", "外观", "外観"),
        "lang.system": ("System", "跟随系统", "システムに従う"),
        "lang.en": ("English", "English", "English"),
        "lang.zh": ("中文", "中文", "中文"),
        "lang.ja": ("日本語", "日本語", "日本語"),
        "appearance.system": ("System", "跟随系统", "システムに従う"),
        "appearance.light": ("Light", "亮色", "ライト"),
        "appearance.dark": ("Dark", "暗色", "ダーク"),
    ]
}
