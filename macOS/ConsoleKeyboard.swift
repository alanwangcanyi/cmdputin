import Carbon
import CoreGraphics
import Foundation

// Physical ANSI keys as seen by a remote console configured for US English.
private struct Stroke {
    let code: CGKeyCode
    let shifted: Bool
}

private let asciiKeys: [Unicode.Scalar: Stroke] = {
    let rows: [(String, String, [Int])] = [
        ("`1234567890-=", "~!@#$%^&*()_+", [kVK_ANSI_Grave, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal]),
        ("qwertyuiop[]\\", "QWERTYUIOP{}|", [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Backslash]),
        ("asdfghjkl;'", "ASDFGHJKL:\"", [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote]),
        ("zxcvbnm,./", "ZXCVBNM<>?", [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash])
    ]
    var keys: [Unicode.Scalar: Stroke] = [" ": Stroke(code: CGKeyCode(kVK_Space), shifted: false)]
    keys["\n"] = Stroke(code: CGKeyCode(kVK_Return), shifted: false)
    keys["\t"] = Stroke(code: CGKeyCode(kVK_Tab), shifted: false)
    for (plain, shifted, codes) in rows {
        for ((lower, upper), code) in zip(zip(plain.unicodeScalars, shifted.unicodeScalars), codes) {
            keys[lower] = Stroke(code: CGKeyCode(code), shifted: false)
            keys[upper] = Stroke(code: CGKeyCode(code), shifted: true)
        }
    }
    return keys
}()

func sendScalar(_ scalar: Unicode.Scalar, to pid: pid_t) -> Bool {
    let stroke = asciiKeys[scalar]
    // Text-aware applications can still receive characters outside the US layout.
    let code = stroke?.code ?? 0xFF
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return false }
    let shifted = stroke?.shifted == true
    down.flags = shifted ? .maskShift : []; up.flags = down.flags
    if stroke == nil {
        let units = Array(String(scalar).utf16)
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    }
    var releaseShift: CGEvent?
    if shifted {
        guard let press = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true),
              let release = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false) else { return false }
        press.type = .flagsChanged; release.type = .flagsChanged
        press.flags = .maskShift; release.flags = []
        releaseShift = release
        press.postToPid(pid)
    }
    down.postToPid(pid)
    Thread.sleep(forTimeInterval: 0.007)
    up.postToPid(pid)
    releaseShift?.postToPid(pid)
    Thread.sleep(forTimeInterval: 0.008)
    return true
}
