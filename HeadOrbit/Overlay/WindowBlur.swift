import AppKit

/// 给透明窗口加「背后内容高斯模糊」。
/// macOS 26 上 NSVisualEffectView 的各种材质实测都是实心的，看不到背后的内容，
/// 只有 WindowServer 的 CGSSetWindowBackgroundBlurRadius 能做到真正的毛玻璃。
/// 它是私有 API：本地自用没问题，上 App Store 会被拒。找不到符号时静默降级成纯压暗。
enum WindowBlur {
    private typealias ConnectionID = Int32
    private typealias DefaultConnection = @convention(c) () -> ConnectionID
    private typealias SetBlurRadius = @convention(c) (ConnectionID, Int32, Int32) -> Int32

    private static let functions: (DefaultConnection, SetBlurRadius)? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let cid = dlsym(handle, "CGSDefaultConnectionForThread"),
              let set = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (unsafeBitCast(cid, to: DefaultConnection.self), unsafeBitCast(set, to: SetBlurRadius.self))
    }()

    static var isAvailable: Bool { functions != nil }

    @discardableResult
    static func apply(to window: NSWindow, radius: Int) -> Bool {
        guard let (connection, setRadius) = functions else { return false }
        return setRadius(connection(), Int32(window.windowNumber), Int32(radius)) == 0
    }
}
