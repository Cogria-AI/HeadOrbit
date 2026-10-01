import ApplicationServices
import Foundation

/// 一个动作触发后做什么
enum Behavior: Codable, Equatable {
    /// 全屏模糊，dim 为模糊之上再压的暗色
    case blur(dim: Double)
    /// 坐姿提醒：模糊 + 提示文字，Esc 解除并暂停
    case posture
    /// 动作触发时按一下
    case tapKey(KeyCombo)
    /// 动作保持期间一直按住，回正才松开
    case holdKey(KeyCombo)

    enum Kind: String, CaseIterable, Identifiable {
        case blur, posture, tapKey, holdKey
        var id: String { rawValue }
    }

    var kind: Kind {
        switch self {
        case .blur: return .blur
        case .posture: return .posture
        case .tapKey: return .tapKey
        case .holdKey: return .holdKey
        }
    }

    var needsAccessibility: Bool { kind == .tapKey || kind == .holdKey }

    var key: KeyCombo? {
        switch self {
        case .tapKey(let k), .holdKey(let k): return k
        default: return nil
        }
    }

    /// 某个动作能选哪些行为。坐姿提醒只在抬头上有意义（弯腰时头会仰起）
    static func kinds(for gesture: Gesture) -> [Kind] {
        gesture == .lookUp ? Kind.allCases : [.blur, .tapKey, .holdKey]
    }

    static func make(_ kind: Kind, keeping old: Behavior? = nil) -> Behavior {
        let key = old?.key ?? .returnKey
        switch kind {
        case .blur: return .blur(dim: 0.15)
        case .posture: return .posture
        case .tapKey: return .tapKey(key)
        case .holdKey: return .holdKey(key)
        }
    }
}

/// 一个按键（可带修饰键）。label 是录制时记下的显示文字，避免再按键盘布局反查
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    /// CGEventFlags 原始值，只含 ⌘⌥⌃⇧
    var modifiers: UInt64
    var label: String

    static let fn = KeyCombo(keyCode: 63, modifiers: 0, label: "Fn")
    static let returnKey = KeyCombo(keyCode: 36, modifiers: 0, label: "↩")
    static let space = KeyCombo(keyCode: 49, modifiers: 0, label: "Space")
    static let escape = KeyCombo(keyCode: 53, modifiers: 0, label: "Esc")
    static let reload = KeyCombo(keyCode: 15, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘R")
    static let pageDown = KeyCombo(keyCode: 121, modifiers: 0, label: "⇟")
    static let presets: [KeyCombo] = [.fn, .returnKey, .space, .escape, .reload, .pageDown]

    /// 修饰键本身（Fn、⌘、⇧…）要用 flagsChanged 事件发，不是 keyDown
    var modifierFlag: CGEventFlags? {
        switch keyCode {
        case 63: return .maskSecondaryFn
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        default: return nil
        }
    }
}

/// 模拟按键。需要「辅助功能」权限；只有场景里用到按键行为时才会去申请
enum KeySender {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹系统授权框（已授权时不弹）
    static func requestTrust() {
        let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
    }

    static func tap(_ k: KeyCombo) {
        down(k)
        up(k)
    }

    static func down(_ k: KeyCombo) { post(k, down: true) }
    static func up(_ k: KeyCombo) { post(k, down: false) }

    private static let source = CGEventSource(stateID: .hidSystemState)

    private static func post(_ k: KeyCombo, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: k.keyCode, keyDown: down) else { return }
        let mods = CGEventFlags(rawValue: k.modifiers)
        if let flag = k.modifierFlag {
            e.type = .flagsChanged
            e.flags = down ? mods.union(flag) : mods
        } else {
            e.flags = mods
        }
        e.post(tap: .cghidEventTap)
    }
}
