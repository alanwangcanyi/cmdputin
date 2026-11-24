import Foundation

@main
struct ModelTests {
    static func main() throws {
        let command = "  echo 'a[b]:$c'  "
        let single = try InputMode.command.prepare(command + "\r\n")
        precondition(single == command)
        for invalid in ["", "\n", "a\n\n", "a\rb", "a\tb", "ls\u{1b}"] {
            precondition((try? InputMode.command.prepare(invalid)) == nil)
        }
        let original = "first\r\n\t second\r\n\r\nlast\r\n"
        let script = try InputMode.script.prepare(original)
        precondition(script == "first\n\t second\n\nlast\n")
        precondition((try? InputMode.script.prepare("last")) == "last")
        precondition((try? InputMode.script.prepare("\n")) == "\n")
        precondition((try? InputMode.script.prepare("a\u{7f}")) == nil)

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = Store(directory: temporary)
        var settings = try store.read("settings.json", default: Settings())
        precondition(!settings.saveHistory && settings.lastMode == .command)
        settings.target = TargetID(application: "fixture", title: "Console")
        settings.lastMode = .script
        try store.write(settings, to: "settings.json")
        try store.write([Entry(date: Date(), mode: .script, text: original)], to: "history.json")
        let reopened = Store(directory: temporary)
        let saved = try reopened.read("settings.json", default: Settings())
        let history = try reopened.read("history.json", default: [Entry]())
        precondition(saved.target == settings.target && saved.lastMode == .script)
        precondition(history.count == 1 && history[0].text == original && history[0].mode == .script)
        print("输入模式与本地配置、历史记录验证通过。")
    }
}
