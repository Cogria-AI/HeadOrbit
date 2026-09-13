import AppKit

/// 每块屏幕盖一层透明、不吃鼠标的窗口，让 WindowServer 把窗口背后的内容高斯模糊（见 WindowBlur），
/// 再压一层可调的暗色。不需要录屏权限。可选在正中显示一行提示文字。
final class BlurOverlayController {
    enum Layer {
        case blur       // 普通模糊层
        case aboveBlur  // 压在模糊层之上（带文字的提示用这个，文字才不会被另一层糊掉）

        var windowLevel: NSWindow.Level {
            // 压在普通窗口和浮动面板之上，但在菜单栏之下：菜单栏和我们的图标永远清晰可点，
            // 万一调错参数也能从图标里关掉功能
            let base = NSWindow.Level.mainMenu.rawValue - 2
            return NSWindow.Level(rawValue: self == .blur ? base : base + 1)
        }
    }

    private var windows: [OverlayWindow] = []
    private(set) var isShown = false
    private let layer: Layer
    private let fadeDuration: TimeInterval = 0.35

    var dimAlpha: Double = 0.15 { didSet { windows.forEach { $0.dimAlpha = dimAlpha } } }
    /// 模糊半径（像素）。WindowBlur 不可用时这项无效，只剩压暗
    var blurRadius: Int = 30 { didSet { windows.forEach { $0.blurRadius = blurRadius } } }
    var message: String? { didSet { windows.forEach { $0.message = message } } }

    init(level: Layer = .blur) {
        self.layer = level
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        rebuildWindows()
        windows.forEach { w in
            w.alphaValue = 0
            w.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        let ws = windows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            ws.forEach { $0.orderOut(nil) }
        })
    }

    @objc private func screensChanged() {
        guard isShown else { return }
        rebuildWindows()
        windows.forEach { $0.alphaValue = 1; $0.orderFrontRegardless() }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen, level: layer.windowLevel)
            w.dimAlpha = dimAlpha
            w.blurRadius = blurRadius
            w.message = message
            return w
        }
    }
}

private final class OverlayWindow: NSWindow {
    private let dimView = NSView()
    private let label = NSTextField(labelWithString: "")

    var dimAlpha: Double = 0.15 {
        didSet { dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(max(dimAlpha, 0.01)).cgColor }
    }
    var blurRadius: Int = 30 {
        didSet { WindowBlur.apply(to: self, radius: blurRadius) }
    }
    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            label.isHidden = (message ?? "").isEmpty
            label.sizeToFit()
            label.frame.origin = CGPoint(
                x: (dimView.bounds.width - label.frame.width) / 2,
                y: (dimView.bounds.height - label.frame.height) / 2)
        }
    }

    init(screen: NSScreen, level: NSWindow.Level) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // 一定要有一点点不透明度，WindowServer 才会为这个窗口做背景模糊
        dimView.frame = contentRect(forFrameRect: frame)
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(max(dimAlpha, 0.01)).cgColor

        label.font = .systemFont(ofSize: 44, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.6)
            s.shadowBlurRadius = 12
            return s
        }()
        label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        label.isHidden = true
        dimView.addSubview(label)

        contentView = dimView
        WindowBlur.apply(to: self, radius: blurRadius)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
