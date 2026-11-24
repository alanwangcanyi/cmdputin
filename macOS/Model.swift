import Foundation
import CoreGraphics

enum InputMode: String, Codable, CaseIterable {
    case command, script
    var title: String { self == .command ? "单条命令" : "多行脚本" }

    func prepare(_ original: String) throws -> String {
        var text = original.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if self == .command {
            if text.hasSuffix("\n") { text.removeLast() }
            if text.contains("\n") { throw InputError("正文中有换行，请切换到多行脚本。") }
        }
        guard !text.isEmpty else { throw InputError("请先输入正文。") }
        for scalar in text.unicodeScalars where CharacterSet.controlCharacters.union(.newlines).contains(scalar) {
            if self == .script && (scalar == "\n" || scalar == "\t") { continue }
            throw InputError("含有不支持的控制字符 U+\(String(format: "%04X", scalar.value))。脚本模式支持换行和 Tab。")
        }
        return text
    }
}
struct InputError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
struct TargetID: Codable, Equatable {
    let application: String
    let title: String
}
struct Shortcut: Codable, Equatable {
    var code: UInt32 = 9
    var modifiers: UInt32 = 4352 // cmdKey | controlKey
    var label = "⌃⌘V"
}
enum Startup: String, Codable, CaseIterable { case last, command, script }
struct SidebarPosition: Codable, Equatable {
    enum Side: String, Codable { case left, right }
    var displayID: String
    var side: Side
    // 0 and 1 are the highest and lowest fully visible positions of the ball.
    var heightFromTop: Double

    var isValid: Bool { !displayID.isEmpty && (0...1).contains(heightFromTop) }

    static func at(center: CGPoint, in bounds: CGRect, diameter: CGFloat, displayID: String) -> Self {
        let travel = bounds.height - diameter
        let fraction = travel > 0 ? (bounds.maxY - diameter / 2 - center.y) / travel : 0.5
        return Self(displayID: displayID, side: center.x < bounds.midX ? .left : .right,
                    heightFromTop: min(1, max(0, fraction)))
    }

    func origin(in bounds: CGRect, diameter: CGFloat) -> CGPoint {
        CGPoint(x: side == .left ? bounds.minX : bounds.maxX - diameter,
                y: bounds.maxY - diameter - heightFromTop * max(0, bounds.height - diameter))
    }
}

struct Settings: Codable {
    var shortcut = Shortcut()
    var startup = Startup.last
    var lastMode = InputMode.command
    var pinned = false
    var edgeEnabled = true
    var saveHistory = false
    var target: TargetID?
    var sidebarPinned = true
    var sidebarPosition: SidebarPosition?

    init() {}

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try fields.decode(Shortcut.self, forKey: .shortcut)
        startup = try fields.decode(Startup.self, forKey: .startup)
        lastMode = try fields.decode(InputMode.self, forKey: .lastMode)
        pinned = try fields.decode(Bool.self, forKey: .pinned)
        edgeEnabled = try fields.decode(Bool.self, forKey: .edgeEnabled)
        saveHistory = try fields.decode(Bool.self, forKey: .saveHistory)
        target = try fields.decodeIfPresent(TargetID.self, forKey: .target)
        sidebarPinned = try fields.decodeIfPresent(Bool.self, forKey: .sidebarPinned) ?? true
        if let saved = try? fields.decode(SidebarPosition.self, forKey: .sidebarPosition), saved.isValid {
            sidebarPosition = saved
        }
    }
}
struct Entry: Codable {
    let date: Date
    let mode: InputMode
    let text: String
}
struct Store {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CMDPutin")) {
        self.directory = directory
    }
    func read<T: Decodable>(_ name: String, default fallback: T) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appendingPathComponent(name))) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return fallback }
    }
    func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(value)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
