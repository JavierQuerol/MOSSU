import Foundation

final class LaunchAtLoginManager {
    private let fileManager = FileManager.default
    private let label: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.mossu.app") {
        self.label = bundleIdentifier + ".launchagent"
    }

    var isEnabled: Bool {
        return fileManager.fileExists(atPath: agentPlistURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try ensureDirectoryExists()
                try writePlist()
                bootstrapAgent()
            } catch {
                LogManager.shared.log("Error enabling launch at login: \(error.localizedDescription)")
            }
        } else {
            bootoutAgent()
            do {
                if fileManager.fileExists(atPath: agentPlistURL.path) {
                    try fileManager.removeItem(at: agentPlistURL)
                }
            } catch {
                LogManager.shared.log("Error disabling launch at login: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private var agentPlistURL: URL {
        let launchAgents = (fileManager.homeDirectoryForCurrentUser as NSURL).appendingPathComponent("Library/LaunchAgents", isDirectory: true)!
        return launchAgents.appendingPathComponent("\(label).plist")
    }

    private func ensureDirectoryExists() throws {
        let dirURL = agentPlistURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    private func writePlist() throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw NSError(domain: "LaunchAtLoginManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Executable path not found"]) 
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentPlistURL, options: .atomic)
    }

    private func bootstrapAgent() {
        // Try modern bootstrap; fall back to load
        let uid = getuid()
        let guiTarget = "gui/\(uid)"

        if runLaunchctl(["bootstrap", guiTarget, agentPlistURL.path]) != 0 {
            _ = runLaunchctl(["load", agentPlistURL.path])
        }
    }

    private func bootoutAgent() {
        let uid = getuid()
        let guiTarget = "gui/\(uid)"

        if runLaunchctl(["bootout", guiTarget, "\(label)"]) != 0 {
            _ = runLaunchctl(["unload", agentPlistURL.path])
        }
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            LogManager.shared.log("launchctl failed: \(error.localizedDescription)")
            return -1
        }
    }
}

