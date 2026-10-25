import AppKit
import SwiftUI

/// 点一下进入录制：先按修饰键时继续等待普通键，从而支持 ⌘⌥⌃⇧Fn + Key。
/// 如果只按一个修饰键并松开，仍然把它录成单独按键。再点一下取消。
struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    @ObservedObject private var l10n = L10n.shared
    @State private var monitor: Any?
    @State private var pressedModifierCodes: Set<UInt16> = []
    @State private var pressOrder: [UInt16] = []
    @State private var modifierOnlyCandidate: KeyCombo?

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
        pressedModifierCodes.removeAll()
        pressOrder.removeAll()
        modifierOnlyCandidate = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .flagsChanged {
                guard let modifier = Self.modifierCombo(from: e) else { return e }
                if Self.isModifierPressed(e) {
                    if pressedModifierCodes.insert(e.keyCode).inserted {
                        pressOrder.append(e.keyCode)
                    }
                    modifierOnlyCandidate = pressedModifierCodes.count == 1 ? modifier : nil
                    return nil
                }

                pressedModifierCodes.remove(e.keyCode)
                if pressedModifierCodes.isEmpty, modifierOnlyCandidate?.keyCode == e.keyCode {
                    combo = modifier
                    pressOrder.removeAll()
                    modifierOnlyCandidate = nil
                    stop()
                } else {
                    pressOrder.removeAll { $0 == e.keyCode }
                }
                return nil
            }

            if let k = Self.combo(fromKeyDown: e, pressOrder: pressOrder) {
                combo = k
                modifierOnlyCandidate = nil
                pressedModifierCodes.removeAll()
                pressOrder.removeAll()
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pressedModifierCodes.removeAll()
        pressOrder.removeAll()
        modifierOnlyCandidate = nil
    }

    private static func modifierCombo(from e: NSEvent) -> KeyCombo? {
        let code = e.keyCode
        guard modifierNames[code] != nil else { return nil }
        return KeyCombo(keyCode: code, modifiers: 0, label: modifierNames[code] ?? "?")
    }

    private static func isModifierPressed(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 63: return e.modifierFlags.contains(.function)
        case 54, 55: return e.modifierFlags.contains(.command)
        case 56, 60: return e.modifierFlags.contains(.shift)
        case 58, 61: return e.modifierFlags.contains(.option)
        case 59, 62: return e.modifierFlags.contains(.control)
        default: return false
        }
    }

    private static func combo(fromKeyDown e: NSEvent, pressOrder: [UInt16]) -> KeyCombo? {
        guard e.type == .keyDown else { return nil }
        let code = e.keyCode
        let f = e.modifierFlags
        var mods = CGEventFlags()
        if f.contains(.control) { mods.insert(.maskControl) }
        if f.contains(.option) { mods.insert(.maskAlternate) }
        if f.contains(.shift) { mods.insert(.maskShift) }
        if f.contains(.command) { mods.insert(.maskCommand) }
        if f.contains(.function) { mods.insert(.maskSecondaryFn) }
        let name = keyNames[code] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        let ordered = pressOrder + [code]
        let prefix = pressOrder.map { modifierSymbols[$0] ?? "" }.joined()
        return KeyCombo(
            keyCode: code,
            modifiers: mods.rawValue,
            label: prefix + name,
            pressOrder: ordered
        )
    }

    private static let modifierNames: [UInt16: String] = [
        63: "Fn", 55: "⌘", 54: "Right ⌘", 56: "⇧", 60: "Right ⇧",
        58: "⌥", 61: "Right ⌥", 59: "⌃", 62: "Right ⌃",
    ]

    private static let modifierSymbols: [UInt16: String] = [
        63: "Fn+", 54: "⌘", 55: "⌘", 56: "⇧", 60: "⇧",
        58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃",
    ]

    private static let keyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
