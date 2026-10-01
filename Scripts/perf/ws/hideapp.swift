import AppKit
// hideapp hide|show <bundle id>
let a = CommandLine.arguments
for app in NSRunningApplication.runningApplications(withBundleIdentifier: a[2]) {
    _ = a[1] == "hide" ? app.hide() : app.unhide()
}
