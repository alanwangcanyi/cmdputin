import AppKit

private extension NSScreen {
    var sidebarID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

final class EdgeDock {
    private let tab: NSPanel
    private let window: NSWindow
    var onClick: (() -> Void)?
    var onPositionChanged: ((SidebarPosition) -> Void)?
    var enabled = true
    var pinned: Bool { didSet { tab.level = pinned ? .floating : .normal } }
    var holdOpen: () -> Bool = { false }
    private var position: SidebarPosition?
    private var dragging = false
    private var docked = false
    private var outsideSince: Date?
    private var hoverSince: Date?
    private var timer: Timer?

    init(window: NSWindow, icon: NSImage?, position: SidebarPosition?, pinned: Bool) {
        self.window = window
        self.position = position
        self.pinned = pinned
        let ball = SidebarBall(icon: icon)
        tab = NSPanel(contentRect: ball.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tab.isOpaque = false; tab.backgroundColor = .clear; tab.hasShadow = true
        tab.level = pinned ? .floating : .normal; tab.hidesOnDeactivate = false
        tab.isMovableByWindowBackground = false
        tab.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ball.target = self; ball.action = #selector(tabClicked)
        ball.draggedTo = { [weak self] origin in self?.tab.setFrameOrigin(origin) }
        ball.droppedAt = { [weak self] point in self?.finishDrag(at: point) }
        tab.contentView = ball.glassView()
        timer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in self?.tick() }
    }
    func movedByUser() { dragging = true }
    func reset() { dragging = false; docked = false; outsideSince = nil; hoverSince = nil; tab.orderOut(nil) }
    func disable() {
        if docked && tab.isVisible { expand() }
        dragging = false; docked = false; outsideSince = nil
    }
    @objc private func tabClicked() { onClick?() }

    func collapseToSide(in screen: NSScreen) {
        reset()
        collapse(in: screen)
    }
    func expand() {
        tab.orderOut(nil); outsideSince = nil; hoverSince = nil
        window.orderFrontRegardless()
    }
    func screensChanged() {
        if tab.isVisible, let screen = window.screen ?? NSScreen.main { placeTab(fallback: screen) }
    }
    private func placeTab(fallback: NSScreen) {
        let diameter = tab.frame.width
        if let position, position.isValid, let saved = NSScreen.screens.first(where: { $0.sidebarID == position.displayID }) {
            tab.setFrameOrigin(position.origin(in: saved.visibleFrame, diameter: diameter))
        } else {
            let bounds = fallback.visibleFrame
            tab.setFrameOrigin(NSPoint(x: bounds.maxX - diameter, y: bounds.midY - diameter / 2))
        }
    }
    private func remember(center: NSPoint, on screen: NSScreen) {
        let next = SidebarPosition.at(center: center, in: screen.visibleFrame, diameter: tab.frame.width, displayID: screen.sidebarID)
        if next.isValid && next != position {
            position = next
            onPositionChanged?(next)
        }
    }
    private func finishDrag(at point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? tab.screen ?? NSScreen.main else { return }
        // A deliberate drop leaves the ball parked until the user clicks it.
        docked = false
        hoverSince = nil
        remember(center: NSPoint(x: point.x, y: tab.frame.midY), on: screen)
        placeTab(fallback: screen)
    }
    private func tick() {
        guard enabled else { return }
        if tab.isVisible {
            if docked, NSEvent.pressedMouseButtons == 0, tab.frame.contains(NSEvent.mouseLocation) {
                if let since = hoverSince {
                    if Date().timeIntervalSince(since) > 0.4 { expand() }
                } else { hoverSince = Date() }
            } else { hoverSince = nil }
            return
        }
        guard window.isVisible, !window.isMiniaturized, NSEvent.pressedMouseButtons == 0, let screen = window.screen else { return }
        let bounds = screen.visibleFrame
        if dragging {
            dragging = false
            let frame = window.frame
            let left = abs(frame.minX - bounds.minX) < abs(frame.maxX - bounds.maxX)
            docked = left ? frame.minX <= bounds.minX + 14 : frame.maxX >= bounds.maxX - 14
            if docked {
                let y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
                window.setFrameOrigin(NSPoint(x: left ? bounds.minX : bounds.maxX - frame.width, y: y))
                remember(center: NSPoint(x: left ? bounds.minX : bounds.maxX, y: window.frame.midY), on: screen)
                collapse(in: screen); return
            }
        }
        guard docked, !holdOpen(), !window.frame.contains(NSEvent.mouseLocation) else { outsideSince = nil; return }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.55 { collapse(in: screen) }
        } else { outsideSince = Date() }
    }
    private func collapse(in screen: NSScreen) {
        window.orderOut(nil)
        placeTab(fallback: screen)
        tab.orderFrontRegardless(); outsideSince = nil; hoverSince = nil
    }
    deinit { timer?.invalidate() }
}
