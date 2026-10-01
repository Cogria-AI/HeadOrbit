import AppKit
import SwiftUI

/// 点一下进入录制，按下的下一个键（可带 ⌘⌥⌃⇧）就是它；单独按修饰键（含 Fn）也能录。再点一下取消
struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    @ObservedObject private var l10n = L10n.shared
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(monitor == nil ? combo.label : l10n.t("key.recording")) {
                monitor == nil ? start() : stop()
            }
            .frame(minWidth: 90)
            Menu(l10n.t("key.presets")) {
                ForEach(KeyCombo.presets, id: \.label) { k in
                    Button(k.label) { stop(); combo = k }
                }
            }
            .fixedSize()
        }
        .onDisappear { stop() }
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if let k = Self.combo(from: e) {
                combo = k
                stop()
                return nil
            }
            return e.type == .keyDown ? nil : e
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func combo(from e: NSEvent) -> KeyCombo? {
        let code = e.keyCode
        if e.type == .flagsChanged {
            // 只在按下时录（松开时对应的修饰位已经清掉）
            let pressed: Bool
            switch code {
            case 63: pressed = e.modifierFlags.contains(.function)
            case 54, 55: pressed = e.modifierFlags.contains(.command)
            case 56, 60: pressed = e.modifierFlags.contains(.shift)
            case 58, 61: pressed = e.modifierFlags.contains(.option)
            case 59, 62: pressed = e.modifierFlags.contains(.control)
            default: return nil
            }
            guard pressed else { return nil }
            return KeyCombo(keyCode: code, modifiers: 0, label: modifierNames[code] ?? "?")
        }
        let f = e.modifierFlags
        var mods = CGEventFlags()
        var prefix = ""
        if f.contains(.control) { mods.insert(.maskControl); prefix += "⌃" }
        if f.contains(.option) { mods.insert(.maskAlternate); prefix += "⌥" }
        if f.contains(.shift) { mods.insert(.maskShift); prefix += "⇧" }
        if f.contains(.command) { mods.insert(.maskCommand); prefix += "⌘" }
        let name = keyNames[code] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        return KeyCombo(keyCode: code, modifiers: mods.rawValue, label: prefix + name)
    }

    private static let modifierNames: [UInt16: String] = [
        63: "Fn", 55: "⌘", 54: "Right ⌘", 56: "⇧", 60: "Right ⇧",
        58: "⌥", 61: "Right ⌥", 59: "⌃", 62: "Right ⌃",
    ]

    private static let keyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
