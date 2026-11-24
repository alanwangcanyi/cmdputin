import AppKit

// The small panel stays visible without taking keyboard focus from the target app.
final class EdgeDock {
    private let tab = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 32, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let window: NSWindow
    var enabled = true
    var holdOpen: () -> Bool = { false }
    private var dragging = false
    private var docked = false
    private var left = false
    private var outsideSince: Date?
    private var timer: Timer?

    init(window: NSWindow, icon: NSImage?) {
        self.window = window
        tab.isOpaque = false; tab.backgroundColor = .clear; tab.hasShadow = true
        tab.level = .floating; tab.hidesOnDeactivate = false
        tab.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let button = NSButton(image: icon ?? NSImage(), target: self, action: #selector(expand))
        button.frame = tab.contentView!.bounds; button.imageScaling = .scaleProportionallyDown
        button.toolTip = "展开 CMDPutin"; button.setAccessibilityLabel("展开 CMDPutin")
        tab.contentView?.addSubview(button)
        timer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in self?.tick() }
    }
    func movedByUser() { dragging = true }
    func reset() { dragging = false; docked = false; outsideSince = nil; tab.orderOut(nil) }
    func disable() { if tab.isVisible { expand() }; reset() }
    @objc func expand() {
        tab.orderOut(nil); outsideSince = nil
        window.orderFrontRegardless()
    }
    private func tick() {
        guard enabled else { return }
        if tab.isVisible {
            if tab.frame.contains(NSEvent.mouseLocation) { expand() }
            return
        }
        guard window.isVisible, !window.isMiniaturized, NSEvent.pressedMouseButtons == 0, let screen = window.screen else { return }
        let bounds = screen.visibleFrame
        if dragging {
            dragging = false
            let frame = window.frame
            left = abs(frame.minX - bounds.minX) < abs(frame.maxX - bounds.maxX)
            docked = left ? frame.minX <= bounds.minX + 14 : frame.maxX >= bounds.maxX - 14
            if docked {
                let y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
                window.setFrameOrigin(NSPoint(x: left ? bounds.minX : bounds.maxX - frame.width, y: y))
                collapse(in: bounds); return
            }
        }
        guard docked, !holdOpen(), !window.frame.contains(NSEvent.mouseLocation) else { outsideSince = nil; return }
        if let since = outsideSince {
            if Date().timeIntervalSince(since) > 0.55 { collapse(in: bounds) }
        } else { outsideSince = Date() }
    }
    private func collapse(in bounds: NSRect) {
        tab.setFrameOrigin(NSPoint(x: left ? bounds.minX : bounds.maxX - tab.frame.width, y: window.frame.midY - tab.frame.height / 2))
        window.orderOut(nil); tab.orderFrontRegardless(); outsideSince = nil
    }
    deinit { timer?.invalidate() }
}
