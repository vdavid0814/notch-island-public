// key <text> | key esc : types text (or Esc) with CGEvents at the HID level.
import CoreGraphics
import Foundation
let args = CommandLine.arguments
func post(_ code: CGKeyCode, _ text: String? = nil) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        if let text { let u = Array(text.utf16); e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u) }
        e.post(tap: .cghidEventTap); usleep(15000)
    }
}
if args[1] == "esc" { post(53) } else { for c in args[1] { post(0, String(c)) } }
