import AppKit
import ApplicationServices

/// A command in the menu bar of the app the user is in ("New Window", "Export as PDF…"), as
/// Spotlight finds them: Return chooses it in that app.
nonisolated struct AssistantMenuItem: Hashable, Identifiable, @unchecked Sendable {
    let title: String
    /// The menus above it, from the menu bar down ("File", "Export").
    let path: [String]
    let appName: String
    let appPath: String
    let pid: pid_t
    /// The item, pressed through Accessibility.
    let element: AXUIElement

    var id: String { "\(pid):\(path.joined(separator: "/"))/\(title)" }
    /// "File ▸ Export".
    var location: String { path.joined(separator: " ▸ ") }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The front app's menu bar read through Accessibility (the permission the island already has),
/// off the main thread, once per Siri opening and only once a query asks for it: every menu's
/// items are fetched in one call per menu, with a short timeout, down two levels of submenus.
nonisolated enum AppMenus {
    static let timeout: Float = 0.25
    /// Enough for any app's menus; a runaway menu (a Recent list of hundreds) stops here.
    static let itemLimit = 800

    /// The menu items of the app with `pid`, the Apple menu left out (Spotlight lists the system's
    /// own commands already).
    @concurrent static func items(of app: NSRunningApplication) async -> [AssistantMenuItem] {
        guard AXIsProcessTrusted(), !app.isTerminated else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, timeout)
        guard let bar: AXUIElement = value(root, kAXMenuBarAttribute) else { return [] }
        var found: [AssistantMenuItem] = []
        let name = app.localizedName ?? ""
        let path = app.bundleURL?.path ?? ""
        let menus: [AXUIElement] = value(bar, kAXChildrenAttribute) ?? []
        for menuBarItem in menus.dropFirst() where found.count < itemLimit {
            guard let title: String = value(menuBarItem, kAXTitleAttribute), !title.isEmpty,
                  let menu = (value(menuBarItem, kAXChildrenAttribute) as [AXUIElement]?)?.first else { continue }
            collect(menu, path: [title], depth: 0, into: &found, app: (name, path, app.processIdentifier))
        }
        return found
    }

    private static func collect(_ menu: AXUIElement, path: [String], depth: Int, into found: inout [AssistantMenuItem],
                                app: (name: String, path: String, pid: pid_t)) {
        let items: [AXUIElement] = value(menu, kAXChildrenAttribute) ?? []
        for item in items where found.count < itemLimit {
            // Title, enabled and submenu in one round trip.
            var values: CFArray?
            let attributes = [kAXTitleAttribute, kAXEnabledAttribute, kAXChildrenAttribute] as CFArray
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, AXCopyMultipleAttributeOptions(), &values) == .success,
                  let list = values as? [Any], list.count == 3 else { continue }
            guard let title = list[0] as? String, !title.isEmpty else { continue }
            let submenu = (list[2] as? [AXUIElement])?.first
            if let submenu {
                if depth < 2 { collect(submenu, path: path + [title], depth: depth + 1, into: &found, app: app) }
                continue
            }
            guard (list[1] as? Bool) == true else { continue }
            found.append(AssistantMenuItem(title: title, path: path, appName: app.name, appPath: app.path, pid: app.pid, element: item))
        }
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Chooses the item in its app (which is still the front app under Siri).
    static func press(_ item: AssistantMenuItem) {
        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    }
}
