import AppKit
import CryptoKit

@MainActor
final class UpdateChecker {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    enum UpdateError: Error {
        case wrongApp, commandFailed, unverified
    }

    /// Public half of the release signing key. Only the private half in the developer's Keychain can sign updates.
    private static let releasePublicKey = "3BcReFNX2+kL+rO0PZa51lVuZ8FgWSjCaHTKkv1vK5U="
    private static let githubRelease = URL(string: "https://api.github.com/repos/Zapeman02/EventHorizon/releases/latest")!
    nonisolated static let enabledKey = "checksForUpdates"

    // Debug builds can point at a local test server; release builds always use GitHub and the real key.
    #if DEBUG
    private static let environment = ProcessInfo.processInfo.environment
    private static let latestRelease = environment["EVENTHORIZON_RELEASE_URL"].flatMap(URL.init(string:)) ?? githubRelease
    private static let publicKey = environment["EVENTHORIZON_PUBLIC_KEY"] ?? releasePublicKey
    #else
    private static let latestRelease = githubRelease
    private static let publicKey = releasePublicKey
    #endif

    func run() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(askPermission(), forKey: Self.enabledKey)
        }
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        Task { await check() }
    }

    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        let parse = { (version: String) in
            version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let new = parse(tag), old = parse(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private func askPermission() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Check for updates at startup?"
        alert.informativeText = "EventHorizon can look for a newer version on GitHub each time it starts."
        alert.addButton(withTitle: "Check for Updates")
        alert.addButton(withTitle: "Don't Check")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Any failure, including being offline, is ignored: the check simply runs again next launch.
    private func check() async {
        let request = URLRequest(url: Self.latestRelease, timeoutInterval: 10)
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(Release.self, from: data),
              Self.isNewer(release.tagName, than: current) else { return }

        let alert = NSAlert()
        alert.messageText = "Update available for EventHorizon"
        alert.informativeText = "Version \(release.tagName) is out. You have \(current)."
        let zip = release.assets.first { $0.name == "EventHorizon.zip" }
        let signature = release.assets.first { $0.name == "EventHorizon.zip.sig" }
        if zip != nil { alert.addButton(withTitle: "Download & Install") }
        alert.addButton(withTitle: "Open on GitHub")
        alert.addButton(withTitle: "Later")
        NSApp.activate()

        let response = alert.runModal()
        let openIndex = zip == nil ? NSApplication.ModalResponse.alertFirstButtonReturn : .alertSecondButtonReturn
        if let zip, response == .alertFirstButtonReturn {
            await install(zip.downloadURL, signature: signature?.downloadURL, fallback: release.htmlURL)
        } else if response == openIndex {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    /// Falls back to the release page if anything goes wrong, e.g. no write access to the app's folder.
    private func install(_ download: URL, signature: URL?, fallback: URL) async {
        do {
            guard let signature else { throw UpdateError.unverified }
            let (signatureData, _) = try await URLSession.shared.data(from: signature)
            let (zip, _) = try await URLSession.shared.download(from: download)
            guard let identifier = Bundle.main.bundleIdentifier else { throw UpdateError.wrongApp }
            let current = Bundle.main.bundleURL
            try Self.install(zip: zip, signature: signatureData, publicKey: Self.publicKey,
                             replacing: current, identifier: identifier)
            relaunch(current)
        } catch UpdateError.unverified {
            warnUnverified(fallback)
        } catch {
            NSLog("EventHorizon: update failed: \(error)")
            NSWorkspace.shared.open(fallback)
        }
    }

    private func warnUnverified(_ releasePage: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update couldn't be verified"
        alert.informativeText = "The download isn't signed by the EventHorizon developer, so it wasn't installed. "
            + "You can download it manually from GitHub instead."
        alert.addButton(withTitle: "Download Manually").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasePage) }
    }

    /// The signature file holds the base64 Ed25519 signature of the zip's exact bytes.
    nonisolated static func install(zip: URL, signature: Data, publicKey: String,
                                    replacing app: URL, identifier: String) throws {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signatureText = String(data: signature, encoding: .utf8),
              let signatureBytes = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(signatureBytes, for: try Data(contentsOf: zip)) else { throw UpdateError.unverified }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", "-x", "-k", zip.path, folder.path)

        let newApp = folder.appendingPathComponent("EventHorizon.app")
        guard Bundle(url: newApp)?.bundleIdentifier == identifier else { throw UpdateError.wrongApp }
        try run("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R=identifier \"\(identifier)\"", newApp.path)
        _ = try FileManager.default.replaceItemAt(app, withItemAt: newApp)
    }

    /// Waits for this process to exit before opening the new version, so only one instance runs.
    private func relaunch(_ app: URL) {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; open \"$1\"", pid, app.path]
        try? script.run()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.commandFailed }
    }
}
