import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Typist()
app.delegate = delegate
app.run()
