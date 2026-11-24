import AppKit

// Keep the whole glass surface clickable, including the area around the C.
final class SidebarBall: NSButton {
    static let diameter: CGFloat = 64
    var draggedTo: ((NSPoint) -> Void)?
    var droppedAt: ((NSPoint) -> Void)?
    private var start: NSPoint?
    private var startOrigin = NSPoint.zero
    private var dragging = false

    init(icon: NSImage?) {
        let size = Self.diameter
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        isBordered = false
        title = icon == nil ? "C" : ""
        image = icon
        image?.isTemplate = true
        imagePosition = icon == nil ? .noImage : .imageOnly
        font = .systemFont(ofSize: 32, weight: .medium)
        contentTintColor = .labelColor
        toolTip = "点击展开 CMDPutin，拖动调整停靠位置"
        setAccessibilityLabel("展开 CMDPutin")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = window.convertPoint(toScreen: event.locationInWindow)
        startOrigin = window.frame.origin
        dragging = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start, let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - start.x, dy = point.y - start.y
        guard dragging || hypot(dx, dy) >= 4 else { return }
        dragging = true
        draggedTo?(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil, let window else { return }
        start = nil
        if dragging {
            dragging = false
            droppedAt?(window.convertPoint(toScreen: event.locationInWindow))
        } else {
            performClick(nil)
        }
    }

    func glassView() -> NSVisualEffectView {
        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        let disc = NSBezierPath(ovalIn: bounds)
        glass.maskImage = NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.white.setFill()
            disc.fill()
            return true
        }
        glass.wantsLayer = true
        glass.layer?.cornerRadius = bounds.width / 2
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        glass.addSubview(self)
        return glass
    }
}
