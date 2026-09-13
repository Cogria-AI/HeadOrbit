import AppKit

/// 菜单栏图标：自己画的矢量图，不用系统符号。
/// 一个头部剪影 + 一圈倾斜的轨道环 + 轨道上的一颗小卫星，呼应 HeadOrbit。
/// 未连接：头是空心的；已连接：头填实。模板图，跟随菜单栏亮暗自动着色。
enum MenuBarIcon {
    static let disconnected = make(connected: false)
    static let connected = make(connected: true)

    private static func make(connected: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current else { return false }
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.set()

            // 轨道：绕中心倾斜 -22° 的椭圆
            let rx: CGFloat = 9.6, ry: CGFloat = 3.4
            var tilt = AffineTransform(translationByX: c.x, byY: c.y)
            tilt.rotate(byDegrees: -22)
            tilt.translate(x: -c.x, y: -c.y)
            let orbit = NSBezierPath(ovalIn: NSRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
            orbit.transform(using: tilt)
            orbit.lineWidth = 1.4
            orbit.stroke()

            // 头：先把轨道在头附近挖掉一圈，做出「轨道从头后面绕过去」的层次
            let r: CGFloat = 4.4
            let headRect = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: headRect.insetBy(dx: -1.3, dy: -1.3)).fill()
            ctx.compositingOperation = .sourceOver
            let head = NSBezierPath(ovalIn: connected ? headRect : headRect.insetBy(dx: 0.75, dy: 0.75))
            if connected {
                head.fill()
            } else {
                head.lineWidth = 1.5
                head.stroke()
            }

            // 卫星：轨道右上方的一颗小点，周围同样挖一圈空隙
            let a = CGFloat(38) * .pi / 180
            var p = NSPoint(x: c.x + rx * cos(a), y: c.y + ry * sin(a))
            p = tilt.transform(p)
            let dr: CGFloat = 1.8
            let dot = NSRect(x: p.x - dr, y: p.y - dr, width: dr * 2, height: dr * 2)
            ctx.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.1, dy: -1.1)).fill()
            ctx.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
