import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()

PerformanceProbe.markProcessStart()
ProcessInfo.processInfo.disableAutomaticTermination("vish stays resident as a menu-bar launcher")
ProcessInfo.processInfo.disableSuddenTermination()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
