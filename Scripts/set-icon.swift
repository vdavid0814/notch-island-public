import AppKit
// set-icon <image> <path>: gives a file, a folder or a mounted volume a custom Finder icon.
let a = CommandLine.arguments
guard a.count == 3, let image = NSImage(contentsOfFile: a[1]) else {
    FileHandle.standardError.write("usage: set-icon <image> <path>\n".data(using: .utf8)!); exit(64)
}
exit(NSWorkspace.shared.setIcon(image, forFile: a[2], options: []) ? 0 : 1)
