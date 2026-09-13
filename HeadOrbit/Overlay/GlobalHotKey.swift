import Carbon

/// 用 Carbon RegisterEventHotKey 注册的全局热键：不需要「辅助功能」权限，
/// 应用不在前台也能收到。只在需要的时候 register()，用完 unregister()，避免长期霸占按键。
final class GlobalHotKey {
    static let escape = UInt32(kVK_Escape)

    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let onPress: () -> Void
    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32 = 0, onPress: @escaping () -> Void) {
        self.id = Self.nextID; Self.nextID += 1
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onPress = onPress
    }

    deinit { unregister() }

    var isRegistered: Bool { ref != nil }

    func register() {
        guard ref == nil else { return }
        Self.installHandlerIfNeeded()
        let hkID = EventHotKeyID(signature: OSType(0x484F5242) /* "HORB" */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr { Self.registry[id] = self } else { ref = nil }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { GlobalHotKey.registry[hkID.id]?.onPress() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
