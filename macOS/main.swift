import AppKit
import ApplicationServices

struct Target {
    let app: NSRunningApplication
    let element: AXUIElement
    let title: String
}

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
}

func listTargets(_ apps: [NSRunningApplication]) -> [Target] {
    var targets: [Target] = []
    for app in apps where app.activationPolicy == .regular && app.processIdentifier != getpid() {
        let process = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(process, 0.6)
        guard let windows = attribute(process, kAXWindowsAttribute as CFString) as? [AXUIElement] else { continue }
        for window in windows {
            let title = attribute(window, kAXTitleAttribute as CFString) as? String ?? ""
            targets.append(Target(app: app, element: window, title: title.isEmpty ? "(无标题)" : title))
        }
    }
    return targets
}

// Check the actual focused window before posting text, including after activation delays.
func typeText(_ text: String, into target: Target) -> String {
    let pid = target.app.processIdentifier
    let process = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(process, 0.6)
    func focused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let window = attribute(process, kAXFocusedWindowAttribute as CFString) else { return false }
        return CFEqual(window, target.element)
    }
    _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
    _ = AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    for _ in 0..<15 {
        if focused() { break }
        Thread.sleep(forTimeInterval: 0.08)
    }
    guard focused() else { return "无法聚焦所选窗口，请打开目标窗口后刷新。" }
    for scalar in text.unicodeScalars {
        guard focused() else { return "窗口焦点已改变，输入已停止。" }
        guard sendScalar(scalar, to: pid) else { return "无法生成按键，输入已停止。" }
    }
    return "按键已发送，请在目标窗口核对后按回车。"
}

final class Typist: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 384), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let command = NSTextView(), targets = NSPopUpButton(), status = NSTextField(labelWithString: "")
    let pin = NSButton(), refresh = NSButton(), send = NSButton(), permission = NSButton()
    var windows: [Target] = []
    private var displayedTrust: Bool?
    private var permissionTimer: Timer?
    var busy = false

    func image(_ name: String, _ side: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: side, height: side)
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Supply standard editing shortcuts even when launched without a storyboard.
        let menu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        menu.addItem(appItem); menu.addItem(editItem)
        appItem.submenu = NSMenu(title: "CMDPutin")
        appItem.submenu?.addItem(withTitle: "退出 CMDPutin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        editItem.submenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editItem.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
        window.title = "CMDPutin"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        func place(_ view: NSView, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            view.frame = NSRect(x: x, y: y, width: w, height: h)
            window.contentView?.addSubview(view)
        }
        func label(_ title: String, size: CGFloat) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: size, weight: .semibold)
            return label
        }
        func button(_ control: NSButton, _ title: String, _ icon: String, _ action: Selector) {
            control.title = title; control.image = image(icon, 16); control.imagePosition = .imageLeading
            control.bezelStyle = .rounded; control.target = self; control.action = action
        }
        let logo = NSImageView(); logo.image = image("logo", 32)
        place(logo, 22, 327, 32, 32)
        place(label("CMDPutin", size: 19), 65, 330, 220, 27)
        button(pin, "置顶", "pin", #selector(togglePin)); place(pin, 446, 327, 94, 32)
        place(label("命令", size: 13), 24, 290, 100, 20)
        let editor = NSScrollView()
        editor.borderType = .bezelBorder
        editor.hasVerticalScroller = true
        editor.scrollerStyle = .legacy
        editor.autohidesScrollers = false
        place(editor, 24, 147, 512, 136)

        command.frame = NSRect(origin: .zero, size: editor.contentSize)
        command.isRichText = false
        command.allowsUndo = true
        command.isAutomaticQuoteSubstitutionEnabled = false
        command.isAutomaticDashSubstitutionEnabled = false
        command.isAutomaticTextReplacementEnabled = false
        command.isAutomaticSpellingCorrectionEnabled = false
        command.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        command.textContainerInset = NSSize(width: 6, height: 6)
        command.minSize = NSSize(width: 0, height: editor.contentSize.height)
        command.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        command.isHorizontallyResizable = false
        command.isVerticallyResizable = true
        command.autoresizingMask = [.width]
        command.textContainer?.containerSize = NSSize(width: editor.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        command.textContainer?.widthTracksTextView = true
        command.setAccessibilityLabel("命令")
        editor.documentView = command
        place(label("目标窗口", size: 13), 24, 112, 100, 20)
        targets.setAccessibilityLabel("目标窗口"); place(targets, 21, 75, 428, 32)
        button(refresh, "刷新", "refresh", #selector(reload)); place(refresh, 454, 75, 86, 32)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2; status.lineBreakMode = .byWordWrapping
        place(status, 24, 16, 310, 40)
        permission.title = "去授权"; permission.bezelStyle = .rounded; permission.target = self; permission.action = #selector(authorize)
        place(permission, 333, 20, 87, 32)
        button(send, "输入", "send", #selector(sendCommand)); place(send, 436, 20, 104, 32)
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(command)
        NSApp.activate(ignoringOtherApps: true)
        reload()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPermissionChange()
        }
        permissionTimer?.tolerance = 0.2
    }

    private func checkPermissionChange() {
        guard displayedTrust != nil, !busy, displayedTrust != AXIsProcessTrusted() else { return }
        reload()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkPermissionChange()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
    }

    @objc func togglePin() {
        window.level = window.level == .floating ? .normal : .floating
        pin.title = window.level == .floating ? "已置顶" : "置顶"
    }

    @objc func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    @objc func reload() {
        guard !busy else { return }
        let selection = targets.indexOfSelectedItem
        let previous = windows.indices.contains(selection) ? windows[selection].element : nil
        targets.removeAllItems(); windows = []; send.isEnabled = false; targets.isEnabled = false
        let trusted = AXIsProcessTrusted()
        displayedTrust = trusted
        permission.isHidden = trusted
        guard trusted else {
            targets.addItem(withTitle: "等待辅助功能授权")
            status.stringValue = "请在辅助功能中启用 CMDPutin，窗口列表会自动更新。"
            return
        }
        targets.addItem(withTitle: "正在读取窗口…")
        status.stringValue = "正在读取窗口，可以先编辑命令。"
        busy = true; refresh.isEnabled = false
        let apps = NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .userInitiated).async {
            let results = listTargets(apps)
            DispatchQueue.main.async {
                self.busy = false; self.refresh.isEnabled = true
                guard AXIsProcessTrusted() else { self.reload(); return }
                self.windows = results; self.targets.removeAllItems()
                for target in results {
                    self.targets.menu?.addItem(withTitle: "\(target.app.localizedName ?? "应用") — \(target.title)", action: nil, keyEquivalent: "")
                }
                if let previous, let index = results.firstIndex(where: { CFEqual(previous, $0.element) }) { self.targets.selectItem(at: index) }
                if results.isEmpty { self.targets.addItem(withTitle: "未找到窗口") }
                self.targets.isEnabled = !results.isEmpty; self.send.isEnabled = !results.isEmpty
                self.status.stringValue = results.isEmpty ? "打开目标窗口后点刷新。" : "选择目标窗口，输入后手动按回车。"
            }
        }
    }

    @objc func sendCommand() {
        let text = command.string
        guard !text.isEmpty else { status.stringValue = "请先输入一条命令。"; window.makeFirstResponder(command); return }
        guard text.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { status.stringValue = "请使用单行命令，移除换行、制表及控制字符。"; return }
        let index = targets.indexOfSelectedItem
        guard !busy else { return }
        guard windows.indices.contains(index) else { status.stringValue = "请先选择目标窗口。"; return }
        guard AXIsProcessTrusted() else { reload(); return }
        let target = windows[index]
        guard CGPreflightPostEventAccess() else {
            status.stringValue = "系统未允许发送按键，请检查辅助功能授权并重开应用。"
            return
        }
        guard target.app.activate(options: [.activateIgnoringOtherApps]) else {
            status.stringValue = "无法激活目标应用，请重新选择窗口。"
            return
        }
        busy = true
        send.isEnabled = false
        refresh.isEnabled = false
        targets.isEnabled = false
        status.stringValue = "正在向所选窗口发送按键…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = typeText(text, into: target)
            DispatchQueue.main.async {
                self.busy = false; self.status.stringValue = result
                self.send.isEnabled = true
                self.refresh.isEnabled = true
                self.targets.isEnabled = true
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Typist()
app.delegate = delegate
app.run()
