import Foundation
import CoreGraphics

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
        let bounds = CGRect(x: -1440, y: 20, width: 1440, height: 964)
        let center = CGPoint(x: -1430, y: bounds.maxY - 32 - 600)
        let position = SidebarPosition.at(center: center, in: bounds, diameter: 64, displayID: "test screen")
        precondition(position.side == .left && position.heightFromTop == 2.0 / 3)
        precondition(position.origin(in: bounds, diameter: 64) == CGPoint(x: bounds.minX, y: center.y - 32))
        settings.sidebarPosition = position
        settings.sidebarPinned = false
        try store.write(settings, to: "settings.json")
        try store.write([Entry(date: Date(), mode: .script, text: original)], to: "history.json")
        let reopened = Store(directory: temporary)
        let saved = try reopened.read("settings.json", default: Settings())
        let history = try reopened.read("history.json", default: [Entry]())
        precondition(saved.target == settings.target && saved.lastMode == .script)
        precondition(history.count == 1 && history[0].text == original && history[0].mode == .script)
        precondition(saved.sidebarPosition == position && !saved.sidebarPinned)
        let decoder = JSONDecoder()
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        legacy.removeValue(forKey: "sidebarPosition")
        legacy.removeValue(forKey: "sidebarPinned")
        let migrated = try decoder.decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.sidebarPosition == nil && migrated.sidebarPinned && migrated.target == saved.target)
        for invalid: Any in ["bad data", ["displayID": "A", "side": "left", "heightFromTop": 1.1]] {
            legacy["sidebarPosition"] = invalid
            let recovered = try decoder.decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
            precondition(recovered.sidebarPosition == nil && recovered.lastMode == .script)
        }
        print("输入模式、历史记录、侧栏位置和旧设置迁移验证通过。")
    }
}
