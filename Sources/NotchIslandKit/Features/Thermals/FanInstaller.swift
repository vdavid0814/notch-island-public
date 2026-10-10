import Foundation

/// The fan helper installed the way privileged helpers always were, for a build macOS will not take
/// a daemon from: `SMAppService.daemon` wants the app notarized ("Apps that contain LaunchDaemons
/// must be notarized", its header says), and on a Mac the app was downloaded to it answers
/// `.notFound` and "Operation not permitted" otherwise — Fan Control said Unavailable there.
///
/// So, where registering fails, the helper is installed once with an administrator's password
/// (macOS's own prompt): a copy of the app's executable, owned by root, at
/// `/Library/PrivilegedHelperTools`, and its launchd job at `/Library/LaunchDaemons` — started by
/// launchd when the app asks for its Mach service, as the registered one is. Being root's, the copy
/// cannot be swapped by anything that is not; it is replaced (the password again) only when the
/// helper's own code has changed (`FanHelper.revision`).
nonisolated enum FanInstaller {
    static let tool = "/Library/PrivilegedHelperTools/" + FanHelper.label
    static let job = "/Library/LaunchDaemons/" + FanHelper.plistName

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: tool) && FileManager.default.fileExists(atPath: job)
    }

    nonisolated enum Outcome: Sendable, Equatable {
        case done
        /// The password was not given.
        case cancelled
        case failed(String)
    }

    /// The launchd job: the copy, started as the helper when its Mach service is asked for.
    static func jobData() -> Data {
        let job: [String: Any] = [
            "Label": FanHelper.label,
            "ProgramArguments": [tool, FanHelper.flag, FanHelper.installedFlag],
            "MachServices": [FanHelper.label: true],
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? "com.davidvarga.notchisland"],
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)) ?? Data()
    }

    /// What root runs to install: the job stopped, the copy and the job put in place as root's, the
    /// job started (tried a few times: a job just stopped takes a moment to go).
    static func installScript(executable: String, jobSource: String) -> String {
        """
        #!/bin/sh
        /bin/launchctl bootout system/\(FanHelper.label) 2>/dev/null
        set -e
        /bin/mkdir -p /Library/PrivilegedHelperTools
        /bin/cp -X \(quoted(executable)) \(quoted(tool + ".new"))
        /usr/sbin/chown root:wheel \(quoted(tool + ".new"))
        /bin/chmod 755 \(quoted(tool + ".new"))
        /bin/mv -f \(quoted(tool + ".new")) \(quoted(tool))
        /bin/cp -X \(quoted(jobSource)) \(quoted(job))
        /usr/sbin/chown root:wheel \(quoted(job))
        /bin/chmod 644 \(quoted(job))
        set +e
        for attempt in 1 2 3 4 5 6; do
            /bin/launchctl bootstrap system \(quoted(job)) 2>/dev/null && break
            /bin/sleep 1
        done
        /bin/launchctl print system/\(FanHelper.label) >/dev/null
        """
    }

    static func removeScript() -> String {
        """
        #!/bin/sh
        /bin/launchctl bootout system/\(FanHelper.label) 2>/dev/null
        /bin/rm -f \(quoted(tool)) \(quoted(job))
        """
    }

    /// For the shell: in single quotes, one inside it closed, escaped and opened again.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// For AppleScript: in double quotes, its backslashes and quotes escaped.
    static func scriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Installs the helper from this app's executable.
    static func install() async -> Outcome {
        guard let executable = Bundle.main.executablePath else { return .failed("The app's executable was not found.") }
        return await run(prompt: String(localized: "NotchIsland wants to install its fan helper, which sets the fans' speed for Fan Control.")) { folder in
            let source = folder.appendingPathComponent(FanHelper.plistName)
            try jobData().write(to: source)
            return installScript(executable: executable, jobSource: source.path)
        }
    }

    static func remove() async -> Outcome {
        await run(prompt: String(localized: "NotchIsland wants to remove its fan helper.")) { _ in removeScript() }
    }

    /// Runs the script `make` writes as root, after macOS has asked for an administrator's password
    /// (`do shell script … with administrator privileges`, in a process of its own: the app goes on
    /// while the prompt is up).
    private static func run(prompt: String, make: (URL) throws -> String) async -> Outcome {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIslandFanHelper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("install.sh")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try make(folder).write(to: script, atomically: true, encoding: .utf8)
        } catch {
            return .failed(error.localizedDescription)
        }
        let source = "do shell script \(scriptString("/bin/sh " + quoted(script.path))) with prompt \(scriptString(prompt)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
        if status == 0 { return .done }
        let message = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // -128: Cancel in the password prompt.
        if message.contains("-128") { return .cancelled }
        return .failed(message.isEmpty ? "The fan helper could not be installed." : message)
    }
}
