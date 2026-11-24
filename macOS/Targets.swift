import AppKit
import ApplicationServices

struct Target {
    let app: NSRunningApplication
    let element: AXUIElement
    var id: TargetID { TargetID(application: app.bundleIdentifier ?? app.bundleURL?.path ?? "pid-\(app.processIdentifier)", title: title) }
    var label: String { "\(app.localizedName ?? "应用") — \(title)" }
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
func typeText(_ text: String, into target: Target) throws {
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
    guard focused() else { throw InputError("无法聚焦所选窗口，请打开目标窗口后刷新。") }
    for scalar in text.unicodeScalars {
        guard focused() else { throw InputError("焦点已改变，输入已停止。请检查已输入的部分。") }
        guard sendScalar(scalar, to: pid) else { throw InputError("生成按键失败，请检查已输入的部分。") }
    }
}
