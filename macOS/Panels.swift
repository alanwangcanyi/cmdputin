import AppKit

extension Typist {
    func addActions(to menu: NSMenu) {
        for (title, action, key) in [("打开 CMDPutin", #selector(summon), ""), ("历史记录…", #selector(openHistory), ""), ("设置…", #selector(openSettings), ","), ("关于 CMDPutin", #selector(openAbout), "")] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        menu.addItem(.separator())
    }
    @objc func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: "向选定的控制台窗口逐键输入命令和多行脚本。")])
    }
    private func panel(_ title: String, width: Int, height: Int) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.appearance = NSAppearance(named: .aqua); panel.center()
        return panel
    }
    private func place(_ view: NSView, in panel: NSPanel, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        view.frame = NSRect(x: x, y: y, width: w, height: h); panel.contentView?.addSubview(view)
    }
    @objc func openSettings() {
        if settingsPanel == nil {
            let pane = panel("CMDPutin 设置", width: 455, height: 254)
            settingsPanel = pane
            place(NSTextField(labelWithString: "全局唤起快捷键"), in: pane, 24, 207, 130, 20)
            recorder.bezelStyle = .rounded; recorder.display = settings.shortcut.label
            recorder.target = recorder; recorder.action = #selector(Recorder.start)
            recorder.apply = { [weak self] shortcut in
                guard let self else { return }
                do {
                    try self.hotKey.register(shortcut)
                    self.settings.shortcut = shortcut; self.recorder.display = shortcut.label
                    self.saveSettings()
                } catch { self.inform(error.localizedDescription) }
            }
            NotificationCenter.default.addObserver(self, selector: #selector(endRecording), name: NSWindow.didResignKeyNotification, object: pane)
            place(recorder, in: pane, 163, 202, 263, 32)
            let help = NSTextField(labelWithString: "点快捷键后按新组合，至少包含 ⌘、⌃ 或 ⌥。")
            help.font = .systemFont(ofSize: 12); help.textColor = .secondaryLabelColor
            place(help, in: pane, 25, 176, 402, 20)
            place(NSTextField(labelWithString: "启动输入模式"), in: pane, 24, 134, 130, 20)
            let startup = NSPopUpButton(); startup.addItems(withTitles: ["沿用上次模式", "单条命令", "多行脚本"])
            startup.selectItem(at: Startup.allCases.firstIndex(of: settings.startup)!)
            startup.target = self; startup.action = #selector(setStartup(_:)); place(startup, in: pane, 163, 129, 263, 32)
            let dock = NSButton(checkboxWithTitle: "拖到屏幕左侧或右侧时收起为 C 图标", target: self, action: #selector(setEdge(_:)))
            dock.state = settings.edgeEnabled ? .on : .off; place(dock, in: pane, 24, 91, 400, 25)
            let history = NSButton(checkboxWithTitle: "在本机保存成功发送的历史记录", target: self, action: #selector(setHistory(_:)))
            history.state = settings.saveHistory ? .on : .off; place(history, in: pane, 24, 52, 400, 25)
            let note = NSTextField(labelWithString: "命令和脚本可能包含密码。已保存的记录可在历史窗口清空。")
            note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor; place(note, in: pane, 25, 23, 412, 18)
        }
        NSApp.activate(ignoringOtherApps: true); settingsPanel?.makeKeyAndOrderFront(nil)
    }
    @objc private func endRecording() { recorder.stop() }
    @objc private func setStartup(_ sender: NSPopUpButton) { settings.startup = Startup.allCases[sender.indexOfSelectedItem]; saveSettings() }
    @objc private func setEdge(_ sender: NSButton) {
        settings.edgeEnabled = sender.state == .on
        if !settings.edgeEnabled { edge.disable() }
        edge.enabled = settings.edgeEnabled; saveSettings()
    }
    @objc private func setHistory(_ sender: NSButton) { settings.saveHistory = sender.state == .on; saveSettings() }

    @objc func openHistory() {
        if historyPanel == nil {
            let pane = panel("输入历史", width: 540, height: 328); historyPanel = pane
            historyList.target = self; historyList.action = #selector(previewEntry); historyList.setAccessibilityLabel("历史记录")
            place(historyList, in: pane, 16, 279, 508, 32)
            let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
            place(scroll, in: pane, 20, 67, 500, 202)
            preview.frame = NSRect(origin: .zero, size: scroll.contentSize); preview.autoresizingMask = [.width]
            preview.textContainer?.widthTracksTextView = true; preview.isVerticallyResizable = true
            preview.isEditable = false; preview.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            preview.setAccessibilityLabel("记录正文"); scroll.documentView = preview
            for (button, title, action, x) in [(historyClear, "清空历史…", #selector(clearHistory), 16), (historyDelete, "删除此条", #selector(deleteEntry), 132), (historyReuse, "回填到编辑区", #selector(reuseEntry), 382)] {
                button.title = title; button.bezelStyle = .rounded; button.action = action; button.target = self
                place(button, in: pane, x, 19, button === historyReuse ? 142 : 112, 32)
            }
        }
        refreshHistory(); NSApp.activate(ignoringOtherApps: true); historyPanel?.makeKeyAndOrderFront(nil)
    }
    func updateHistory(_ updated: [Entry]) {
        do { try store.write(updated, to: "history.json"); entries = updated; refreshHistory() }
        catch { inform("历史记录保存失败：\(error.localizedDescription)") }
    }
    private func refreshHistory() {
        guard historyPanel != nil else { return }
        historyList.removeAllItems()
        for entry in entries {
            let first = entry.text.split(whereSeparator: \.isNewline).first?.prefix(45) ?? ""
            // Direct menu insertion also preserves entries with identical labels.
            historyList.menu?.addItem(withTitle: "\(entry.date.formatted()) · \(entry.mode.title) · \(first)", action: nil, keyEquivalent: "")
        }
        if entries.isEmpty { historyList.addItem(withTitle: "暂无历史记录") }
        historyList.selectItem(at: 0); previewEntry()
        for control in [historyList, historyReuse, historyDelete, historyClear] { control.isEnabled = !entries.isEmpty }
    }
    @objc private func previewEntry() {
        let i = historyList.indexOfSelectedItem
        preview.string = entries.indices.contains(i) ? entries[i].text : (settings.saveHistory ? "发送完成后，记录会出现在这里。" : "要保存接下来发送的内容，请在设置中开启历史记录。")
        preview.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    @objc private func reuseEntry() {
        let i = historyList.indexOfSelectedItem
        guard entries.indices.contains(i) else { return }
        command.string = entries[i].text; applyMode(entries[i].mode)
        settings.lastMode = entries[i].mode; saveSettings(); historyPanel?.close(); summon()
    }
    @objc private func deleteEntry() {
        let i = historyList.indexOfSelectedItem
        guard entries.indices.contains(i) else { return }
        var remaining = entries; remaining.remove(at: i); updateHistory(remaining)
    }
    @objc private func clearHistory() {
        let alert = NSAlert(); alert.messageText = "清空全部 \(entries.count) 条历史记录？"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空历史")
        if alert.runModal() == .alertSecondButtonReturn { updateHistory([]) }
    }
}
