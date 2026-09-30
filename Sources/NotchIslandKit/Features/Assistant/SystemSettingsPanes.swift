import Foundation

/// A System Settings pane Spotlight opens by name (⌘5): its settings extension, and for Privacy &
/// Security's lists the section (`Privacy_Camera`). The links need no permission.
nonisolated struct SystemSettingsPane: Hashable, Sendable, Identifiable {
    let title: String
    let extensionID: String
    var anchor: String?
    /// Other words people use for it ("dock", "hot corners" for Desktop & Dock).
    var synonyms: [String] = []

    var id: String { anchor.map { "\(extensionID)?\($0)" } ?? extensionID }

    var url: URL? { URL(string: "x-apple.systempreferences:\(id)") }

    var searchNames: [String] { [title] + synonyms }

    /// Built when Spotlight first needs it and dropped when it closes (`AssistantModel.end`). Every
    /// extension was checked against /System/Library/ExtensionKit/Extensions on macOS 27; panes
    /// without one there (Screen Saver) are left out.
    @concurrent static func table() async -> [SystemSettingsPane] {
        let privacy = "com.apple.settings.PrivacySecurity.extension"
        func privacyPane(_ title: String, _ anchor: String, _ synonyms: [String] = []) -> SystemSettingsPane {
            SystemSettingsPane(title: title, extensionID: privacy, anchor: anchor, synonyms: synonyms)
        }
        return [
            SystemSettingsPane(title: "Wi-Fi", extensionID: "com.apple.wifi-settings-extension", synonyms: ["WiFi", "Wireless", "WLAN"]),
            SystemSettingsPane(title: "Bluetooth", extensionID: "com.apple.BluetoothSettings"),
            SystemSettingsPane(title: "Network", extensionID: "com.apple.Network-Settings.extension", synonyms: ["Ethernet", "Firewall", "Proxy", "DNS", "Internet"]),
            SystemSettingsPane(title: "VPN", extensionID: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"),
            SystemSettingsPane(title: "Battery", extensionID: "com.apple.Battery-Settings.extension", synonyms: ["Power", "Energy", "Low Power Mode", "Energy Saver"]),
            SystemSettingsPane(title: "General", extensionID: "com.apple.systempreferences.GeneralSettings"),
            SystemSettingsPane(title: "About", extensionID: "com.apple.SystemProfiler.AboutExtension", synonyms: ["About This Mac", "Serial Number", "Model", "macOS Version"]),
            SystemSettingsPane(title: "Software Update", extensionID: "com.apple.Software-Update-Settings.extension", synonyms: ["Update", "Upgrade"]),
            SystemSettingsPane(title: "Storage", extensionID: "com.apple.settings.Storage", synonyms: ["Disk Space", "Free Space"]),
            SystemSettingsPane(title: "AppleCare & Warranty", extensionID: "com.apple.Coverage-Settings.extension", synonyms: ["Warranty", "Coverage"]),
            SystemSettingsPane(title: "AirDrop & Handoff", extensionID: "com.apple.AirDrop-Handoff-Settings.extension", synonyms: ["AirPlay Receiver", "Continuity", "Handoff"]),
            SystemSettingsPane(title: "Login Items & Extensions", extensionID: "com.apple.LoginItems-Settings.extension", synonyms: ["Startup Items", "Background Items", "Extensions", "Open at Login"]),
            SystemSettingsPane(title: "Language & Region", extensionID: "com.apple.Localization-Settings.extension", synonyms: ["Language", "Region", "Locale", "Date Format", "Translation"]),
            SystemSettingsPane(title: "Date & Time", extensionID: "com.apple.Date-Time-Settings.extension", synonyms: ["Clock", "Time Zone"]),
            SystemSettingsPane(title: "Sharing", extensionID: "com.apple.Sharing-Settings.extension", synonyms: ["File Sharing", "Screen Sharing", "Remote Login", "SSH", "Computer Name", "Hostname"]),
            SystemSettingsPane(title: "Time Machine", extensionID: "com.apple.Time-Machine-Settings.extension", synonyms: ["Backup"]),
            SystemSettingsPane(title: "Transfer or Reset", extensionID: "com.apple.Transfer-Reset-Settings.extension", synonyms: ["Erase All", "Factory Reset", "Migration"]),
            SystemSettingsPane(title: "Startup Disk", extensionID: "com.apple.Startup-Disk-Settings.extension", synonyms: ["Boot"]),
            SystemSettingsPane(title: "Device Management", extensionID: "com.apple.Profiles-Settings.extension", synonyms: ["Profiles", "MDM"]),
            SystemSettingsPane(title: "Accessibility", extensionID: "com.apple.Accessibility-Settings.extension",
                               synonyms: ["VoiceOver", "Zoom", "Reduce Motion", "Increase Contrast", "Larger Text", "Voice Control", "Switch Control", "Captions", "Hover Text", "Universal Access"]),
            SystemSettingsPane(title: "Appearance", extensionID: "com.apple.Appearance-Settings.extension", synonyms: ["Dark Mode", "Light Mode", "Accent Color", "Theme", "Scroll Bars"]),
            SystemSettingsPane(title: "Apple Intelligence & Siri", extensionID: "com.apple.Siri-Settings.extension", synonyms: ["Siri", "ChatGPT", "Writing Tools"]),
            SystemSettingsPane(title: "Control Center", extensionID: "com.apple.ControlCenter-Settings.extension", synonyms: ["Menu Bar", "Status Bar"]),
            SystemSettingsPane(title: "Desktop & Dock", extensionID: "com.apple.Desktop-Settings.extension",
                               synonyms: ["Dock", "Mission Control", "Hot Corners", "Stage Manager", "Widgets", "Default Web Browser", "Window Tiling"]),
            SystemSettingsPane(title: "Displays", extensionID: "com.apple.Displays-Settings.extension",
                               synonyms: ["Monitor", "Screen", "Resolution", "Brightness", "Night Shift", "True Tone", "Arrangement"]),
            SystemSettingsPane(title: "Spotlight", extensionID: "com.apple.Spotlight-Settings.extension", synonyms: ["Search"]),
            SystemSettingsPane(title: "Wallpaper", extensionID: "com.apple.Wallpaper-Settings.extension", synonyms: ["Background", "Desktop Picture", "Screen Saver"]),
            SystemSettingsPane(title: "Notifications", extensionID: "com.apple.Notifications-Settings.extension", synonyms: ["Alerts", "Banners", "Badges"]),
            SystemSettingsPane(title: "Sound", extensionID: "com.apple.Sound-Settings.extension", synonyms: ["Volume", "Audio", "Output", "Input", "Speakers", "Alert Sound"]),
            SystemSettingsPane(title: "Headphones", extensionID: "com.apple.HeadphoneSettings", synonyms: ["AirPods"]),
            SystemSettingsPane(title: "Focus", extensionID: "com.apple.Focus-Settings.extension", synonyms: ["Do Not Disturb", "DND"]),
            SystemSettingsPane(title: "Screen Time", extensionID: "com.apple.Screen-Time-Settings.extension", synonyms: ["Parental Controls", "App Limits", "Downtime"]),
            SystemSettingsPane(title: "Lock Screen", extensionID: "com.apple.Lock-Screen-Settings.extension", synonyms: ["Screen Lock", "Require Password", "Login Window"]),
            SystemSettingsPane(title: "Privacy & Security", extensionID: privacy, synonyms: ["Privacy", "Security", "Permissions", "Gatekeeper", "Lockdown Mode"]),
            privacyPane("Location Services", "Privacy_LocationServices", ["Location", "GPS"]),
            privacyPane("Camera Access", "Privacy_Camera", ["Camera", "Webcam"]),
            privacyPane("Microphone Access", "Privacy_Microphone", ["Microphone", "Mic"]),
            privacyPane("Accessibility Access", "Privacy_Accessibility", ["Accessibility Permission"]),
            privacyPane("Screen & System Audio Recording", "Privacy_ScreenCapture", ["Screen Recording", "Screen Capture"]),
            privacyPane("Full Disk Access", "Privacy_AllFiles", ["Disk Access"]),
            privacyPane("Files & Folders", "Privacy_FilesAndFolders"),
            privacyPane("Input Monitoring", "Privacy_ListenEvent", ["Keyboard Monitoring"]),
            privacyPane("Automation", "Privacy_Automation", ["Apple Events", "AppleScript"]),
            privacyPane("Contacts Access", "Privacy_Contacts", ["Contacts"]),
            privacyPane("Calendars Access", "Privacy_Calendars", ["Calendars"]),
            privacyPane("Reminders Access", "Privacy_Reminders", ["Reminders"]),
            privacyPane("Photos Access", "Privacy_Photos", ["Photos"]),
            privacyPane("Bluetooth Access", "Privacy_Bluetooth"),
            privacyPane("App Management", "Privacy_AppBundles"),
            privacyPane("Developer Tools", "Privacy_DevTools"),
            privacyPane("Analytics & Improvements", "Privacy_Analytics", ["Analytics", "Diagnostics"]),
            privacyPane("FileVault", "FileVault", ["Disk Encryption", "Encryption"]),
            SystemSettingsPane(title: "Touch ID & Password", extensionID: "com.apple.Touch-ID-Settings.extension", synonyms: ["Fingerprint", "Login Password", "Change Password"]),
            SystemSettingsPane(title: "Users & Groups", extensionID: "com.apple.Users-Groups-Settings.extension", synonyms: ["Users", "Accounts", "Guest User"]),
            SystemSettingsPane(title: "Passwords", extensionID: "com.apple.Passwords-Settings.extension", synonyms: ["Passkeys", "AutoFill"]),
            SystemSettingsPane(title: "Internet Accounts", extensionID: "com.apple.Internet-Accounts-Settings.extension", synonyms: ["Mail Accounts", "Google Account", "Exchange"]),
            SystemSettingsPane(title: "Apple Account", extensionID: "com.apple.systempreferences.AppleIDSettings", synonyms: ["Apple ID", "iCloud", "Subscriptions"]),
            SystemSettingsPane(title: "Family", extensionID: "com.apple.Family-Settings.extension", synonyms: ["Family Sharing"]),
            SystemSettingsPane(title: "Wallet & Apple Pay", extensionID: "com.apple.WalletSettingsExtension", synonyms: ["Apple Pay", "Cards"]),
            SystemSettingsPane(title: "Game Center", extensionID: "com.apple.Game-Center-Settings.extension"),
            SystemSettingsPane(title: "Game Controllers", extensionID: "com.apple.Game-Controller-Settings.extension", synonyms: ["Gamepad", "Controller"]),
            SystemSettingsPane(title: "Keyboard", extensionID: "com.apple.Keyboard-Settings.extension",
                               synonyms: ["Keyboard Shortcuts", "Input Sources", "Dictation", "Text Replacements", "Key Repeat", "Function Keys"]),
            SystemSettingsPane(title: "Trackpad", extensionID: "com.apple.Trackpad-Settings.extension", synonyms: ["Gestures", "Tap to Click", "Scroll Direction", "Force Click"]),
            SystemSettingsPane(title: "Mouse", extensionID: "com.apple.Mouse-Settings.extension", synonyms: ["Pointer Speed", "Scroll Direction"]),
            SystemSettingsPane(title: "Printers & Scanners", extensionID: "com.apple.Print-Scan-Settings.extension", synonyms: ["Printer", "Scanner", "Print"]),
        ]
    }
}
