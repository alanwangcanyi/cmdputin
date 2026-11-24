import AppKit
import ApplicationServices

final class CommandEditor: NSTextView {
    var mode = InputMode.command
    var submit: (() -> Void)?
    private func isReturn(_ event: NSEvent) -> Bool { event.keyCode == 36 || event.keyCode == 76 }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if mode == .script, isReturn(event), event.modifierFlags.intersection([.command, .control, .shift, .option]) == .command, !hasMarkedText() {
            submit?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if mode == .command, isReturn(event), !hasMarkedText(), event.modifierFlags.intersection([.command, .control, .shift, .option]).isEmpty {
            submit?(); return
        }
        super.keyDown(with: event)
    }
}

final class Typist: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 384), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let command = CommandEditor(), targets = NSPopUpButton(), status = NSTextField(labelWithString: "")
    let pin = NSButton(), refresh = NSButton(), send = NSButton(), permission = NSButton()
    var windows: [Target] = []
    private var displayedTrust: Bool?
    private var permissionTimer: Timer?
    var busy = false

    let store: Store
    let hotKey = HotKey()
    init(store: Store = Store()) { self.store = store; super.init() }
    var settings = Settings(), entries: [Entry] = []
    var statusItem: NSStatusItem!
    var edge: EdgeDock!
    let modePicker = NSSegmentedControl(labels: ["单条命令", "多行脚本"], trackingMode: .selectOne, target: nil, action: nil)
    let hint = NSTextField(labelWithString: "")
    var settingsPanel: NSPanel?, historyPanel: NSPanel?
    let recorder = Recorder(), historyList = NSPopUpButton(), preview = NSTextView()
    let historyReuse = NSButton(), historyDelete = NSButton(), historyClear = NSButton()
    private var pendingExternalApp: NSRunningApplication?
    private var selectedElement: AXUIElement?
    private var allowSavedTarget = true
    private var reloadPending = false
    var confirming = false
    var editingAtEdge = false

    func image(_ name: String, _ side: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: side, height: side)
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        rememberFrontmostApplication()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        var startupErrors: [String] = []
        do { settings = try store.read("settings.json", default: settings) } catch { startupErrors.append("读取设置失败：\(error.localizedDescription)") }
        do { entries = try store.read("history.json", default: entries) } catch { startupErrors.append("读取历史失败：\(error.localizedDescription)") }
        // Supply standard editing shortcuts even when launched without a storyboard.
        let menu = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        menu.addItem(appItem); menu.addItem(editItem)
        appItem.submenu = NSMenu(title: "CMDPutin")
        addActions(to: appItem.submenu!)
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
        place(label("CMDPutin", size: 19), 65, 330, 155, 27)
        let sidebar = NSButton(title: "收起到侧栏", target: self, action: #selector(collapseToSide))
        place(sidebar, 230, 327, 108, 32)
        button(pin, "置顶", "pin", #selector(togglePin)); place(pin, 446, 327, 94, 32)
        let history = NSButton(title: "历史记录", target: self, action: #selector(openHistory))
        place(history, 344, 327, 96, 32)
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        place(modePicker, 21, 288, 192, 29)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        place(hint, 220, 293, 317, 18)
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
        targets.target = self; targets.action = #selector(targetChanged)
        command.delegate = self
        command.submit = { [weak self] in self?.sendCommand() }
        applyMode(settings.startup == .last ? settings.lastMode : (settings.startup == .script ? .script : .command))
        applyPin()
        window.delegate = self; window.isReleasedWhenClosed = false
        edge = EdgeDock(window: window, icon: image("logo", 36), position: settings.sidebarPosition, pinned: settings.sidebarPinned)
        edge.enabled = settings.edgeEnabled
        edge.onPositionChanged = { [weak self] position in
            self?.settings.sidebarPosition = position
            self?.saveSettings()
        }
        edge.onClick = { [weak self] in self?.summon() }
        edge.holdOpen = { [weak self] in
            guard let self else { return false }
            return self.confirming || self.command.hasMarkedText() || (self.window.isKeyWindow && self.editingAtEdge) || self.settingsPanel?.isVisible == true || self.historyPanel?.isVisible == true || NSApp.modalWindow != nil
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let symbol = image("logo", 18); symbol?.isTemplate = true
        statusItem.button?.image = symbol; statusItem.button?.setAccessibilityLabel("CMDPutin")
        let tray = NSMenu(); addActions(to: tray)
        let collapse = tray.insertItem(withTitle: "收起到侧边", action: #selector(collapseToSide), keyEquivalent: "", at: 1)
        collapse.target = self
        tray.addItem(withTitle: "退出 CMDPutin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = tray
        hotKey.show = { [weak self] in self?.summon() }
        do { try hotKey.register(settings.shortcut) } catch { startupErrors.append("全局快捷键未启用。\(error.localizedDescription) 请在设置中更改。") }
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(command)
        NSApp.activate(ignoringOtherApps: true)
        reload()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPermissionChange()
        }
        permissionTimer?.tolerance = 0.2
        if !startupErrors.isEmpty { inform(startupErrors.joined(separator: "\n")) }
    }

    private func checkPermissionChange() {
        guard displayedTrust != nil, !busy, displayedTrust != AXIsProcessTrusted() else { return }
        reload()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        edge?.screensChanged()
    }

    @objc private func workspaceActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier != getpid() {
            pendingExternalApp = app
        } else if selectRecentWindow() {
            reload()
        }
    }

    private func rememberFrontmostApplication() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            pendingExternalApp = app
        }
    }

    @discardableResult private func selectRecentWindow() -> Bool {
        guard let app = pendingExternalApp, AXIsProcessTrusted() else { return false }
        pendingExternalApp = nil
        selectedElement = focusedWindow(of: app)
        allowSavedTarget = false
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if selectRecentWindow() { reload() } else { checkPermissionChange() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        permissionTimer?.invalidate()
    }

    @objc func togglePin() {
        settings.pinned.toggle(); applyPin(); saveSettings()
    }
    func applyPin() {
        window.level = settings.pinned ? .floating : .normal
        pin.title = settings.pinned ? "已置顶" : "置顶"
    }
    func saveSettings() {
        do { try store.write(settings, to: "settings.json") } catch { inform("设置保存失败：\(error.localizedDescription)") }
    }
    func inform(_ message: String) {
        let alert = NSAlert(); alert.messageText = "CMDPutin"; alert.informativeText = message; alert.runModal()
    }
    func applyMode(_ mode: InputMode) {
        command.mode = mode; modePicker.selectedSegment = mode == .command ? 0 : 1
        send.title = mode == .command ? "输入" : "发送脚本"
        hint.stringValue = mode == .command ? "回车输入 · 在目标窗口手动执行" : "回车换行 · ⌘回车发送脚本"
    }
    @objc func modeChanged() {
        applyMode(modePicker.selectedSegment == 0 ? .command : .script)
        settings.lastMode = command.mode; saveSettings(); window.makeFirstResponder(command)
        status.stringValue = ""
    }
    func textDidChange(_ notification: Notification) {
        editingAtEdge = true
        if command.mode == .command, (try? command.mode.prepare(command.string)) == nil, command.string.contains("\n"), !command.hasMarkedText() { status.stringValue = "正文中有换行，可切换到多行脚本。" }
        else if !busy { status.stringValue = "" }
    }
    @objc func collapseToSide() {
        guard !confirming, NSApp.modalWindow == nil, let screen = window.screen ?? NSScreen.main else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.setActivationPolicy(.accessory)
        edge.collapseToSide(in: screen)
    }
    @objc func summon() {
        if NSApp.modalWindow != nil || confirming { NSApp.activate(ignoringOtherApps: true); return }
        rememberFrontmostApplication()
        selectRecentWindow()
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        edge.expand(); window.deminiaturize(nil); NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(command); editingAtEdge = true
        reload()
    }
    func windowWillMove(_ notification: Notification) { edge.movedByUser(); editingAtEdge = false }
    func windowDidResignKey(_ notification: Notification) { editingAtEdge = false }
    func windowWillClose(_ notification: Notification) {
        edge.reset()
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { summon(); return false }
    @objc func targetChanged() {
        let i = targets.indexOfSelectedItem - 1
        guard windows.indices.contains(i) else { send.isEnabled = false; return }
        selectedElement = windows[i].element
        settings.target = windows[i].id; saveSettings(); send.isEnabled = true
        status.stringValue = ""
    }

    @objc func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    @objc func reload() {
        guard !busy else { reloadPending = true; return }
        reloadPending = false
        if NSApp.isActive { selectRecentWindow() }
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
                guard AXIsProcessTrusted(), !self.reloadPending else { self.reload(); return }
                self.windows = results; self.targets.removeAllItems()
                self.targets.addItem(withTitle: results.isEmpty ? "未找到窗口" : "请选择目标窗口")
                self.targets.item(at: 0)?.isEnabled = false
                for target in results {
                    self.targets.menu?.addItem(withTitle: target.label, action: nil, keyEquivalent: "")
                }
                var restored: Int?
                if let element = self.selectedElement {
                    restored = results.firstIndex { CFEqual($0.element, element) }
                } else if self.allowSavedTarget {
                    let matches = results.indices.filter { results[$0].id == self.settings.target }
                    if matches.count == 1 { restored = matches[0] }
                }
                if let index = restored {
                    self.targets.selectItem(at: index + 1)
                    self.selectedElement = results[index].element
                } else { self.targets.selectItem(at: 0) }
                self.targets.isEnabled = !results.isEmpty; self.send.isEnabled = restored != nil
                self.status.stringValue = results.isEmpty ? "打开目标窗口后点刷新。" : (restored != nil ? "已选中最近使用的目标窗口。" : "请重新选择目标窗口。")
            }
        }
    }

    @objc func sendCommand() {
        guard !busy, !confirming, !command.hasMarkedText() else { return }
        let original = command.string, mode = command.mode
        let text: String
        do { text = try mode.prepare(original) } catch { status.stringValue = error.localizedDescription; return }
        let index = targets.indexOfSelectedItem - 1
        guard windows.indices.contains(index) else { status.stringValue = "请先选择目标窗口。"; return }
        guard AXIsProcessTrusted() else { reload(); return }
        let target = windows[index]
        if mode == .script {
            let terminalReturn = text.hasSuffix("\n")
            let lines = text.components(separatedBy: "\n").count - (terminalReturn ? 1 : 0)
            let alert = NSAlert(); alert.messageText = "向所选窗口发送脚本？"
            alert.informativeText = "目标：\(target.label)\n共 \(lines) 行 · 末尾回车：\(terminalReturn ? "有" : "无")\n\n在 Shell 中，换行可能立即执行上一行，Tab 可能触发补全。请核对目标和正文。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "发送脚本")
            confirming = true
            alert.beginSheetModal(for: window) { response in
                self.confirming = false
                if response == .alertSecondButtonReturn {
                    self.dispatch(text, original: original, mode: mode, target: target)
                } else {
                    self.window.makeFirstResponder(self.command)
                }
            }
        } else { dispatch(text, original: original, mode: mode, target: target) }
    }
    func dispatch(_ text: String, original: String, mode: InputMode, target: Target) {
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
            let result = Result { try typeText(text, into: target) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .failure(let error): self.status.stringValue = error.localizedDescription
                case .success:
                    self.status.stringValue = mode == .command ? "已发送，请在目标窗口核对后按回车。" : "脚本按键已发送，请核对目标窗口。"
                    if self.settings.saveHistory { self.updateHistory([Entry(date: Date(), mode: mode, text: original)] + self.entries) }
                }
                self.send.isEnabled = true
                self.refresh.isEnabled = true
                self.targets.isEnabled = true
                if self.reloadPending { self.reload() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
