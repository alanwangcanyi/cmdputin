import AppKit
import Carbon

final class HotKey {
    var show: (() -> Void)?
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var active: Shortcut?

    func register(_ shortcut: Shortcut) throws {
        if let active, active.code == shortcut.code, active.modifiers == shortcut.modifiers { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout.size(ofValue: id), nil, &id) == noErr, id.signature == 0x434D4450 else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().show?()
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw InputError("无法监听快捷键（\(status)）。") }
        }
        var next: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.code, shortcut.modifiers, EventHotKeyID(signature: 0x434D4450, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &next)
        guard status == noErr else { throw InputError("组合键可能已被占用（\(status)），请选择其他组合。") }
        if let registration { UnregisterEventHotKey(registration) }
        registration = next
        active = shortcut
    }
    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class Recorder: NSButton {
    var apply: ((Shortcut) -> Void)?
    var display = "" { didSet { title = display } }
    private var monitor: Any?
    override func performClick(_ sender: Any?) { start() }
    @objc func start() {
        stop()
        title = "请按组合键 · Esc 取消"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { self?.stop(); return event }
            if event.keyCode == kVK_Escape { self.stop(); return nil }
            let flags = event.modifierFlags
            let parts: [(NSEvent.ModifierFlags, Int, String)] = [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")]
            let used = parts.filter { flags.contains($0.0) }
            guard !flags.intersection([.control, .command, .option]).isEmpty else { NSSound.beep(); return nil }
            let raw = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
            let key = event.keyCode == kVK_Space ? "Space" : (raw.count == 1 && raw.unicodeScalars.allSatisfy { (33...126).contains($0.value) } ? raw : "键 \(event.keyCode)")
            self.stop()
            self.apply?(Shortcut(code: UInt32(event.keyCode), modifiers: UInt32(used.reduce(0) { $0 | $1.1 }), label: used.map { $0.2 }.joined() + key))
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        title = display
    }
}
