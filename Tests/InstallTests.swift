import CryptoKit
import Foundation
import Testing
@testable import EventHorizon

/// Builds tiny real app bundles so the unzip, signature check and replace run exactly as in an update.
struct InstallTests {
    private let identifier = "com.kasperback.eventhorizon"
    private let key = Curve25519.Signing.PrivateKey()
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("InstallTests-\(UUID().uuidString)")

    @Test func replacesOldAppWithNewVersion() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let zip = try makeZip(of: makeApp(version: "1.1", in: "release"))

        try install(zip, signature: sign(zip))

        #expect(version(of: installed) == "1.1")
    }

    @Test func rejectsUnsignedZip() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let zip = try makeZip(of: makeApp(version: "1.1", in: "release"))

        #expect(throws: UpdateChecker.UpdateError.unverified) { try install(zip, signature: Data()) }
        #expect(version(of: installed) == "1.0")
    }

    @Test func rejectsZipSignedByOtherKey() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let zip = try makeZip(of: makeApp(version: "1.1", in: "release"))
        let forged = try Curve25519.Signing.PrivateKey().signature(for: Data(contentsOf: zip)).base64EncodedString()

        #expect(throws: UpdateChecker.UpdateError.unverified) { try install(zip, signature: Data(forged.utf8)) }
        #expect(version(of: installed) == "1.0")
    }

    @Test func rejectsZipChangedAfterSigning() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let zip = try makeZip(of: makeApp(version: "1.1", in: "release"))
        let signature = try sign(zip)
        let handle = try FileHandle(forWritingTo: zip)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()

        #expect(throws: UpdateChecker.UpdateError.unverified) { try install(zip, signature: signature) }
        #expect(version(of: installed) == "1.0")
    }

    @Test func rejectsOtherApp() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let zip = try makeZip(of: makeApp(version: "9.9", in: "release", identifier: "com.someone.else"))

        #expect(throws: UpdateChecker.UpdateError.wrongApp) { try install(zip, signature: sign(zip)) }
        #expect(version(of: installed) == "1.0")
    }

    @Test func rejectsTamperedApp() throws {
        let installed = try makeApp(version: "1.0", in: "installed")
        let release = try makeApp(version: "1.1", in: "release")
        let binary = release.appendingPathComponent("Contents/MacOS/EventHorizon")
        let handle = try FileHandle(forWritingTo: binary)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()

        let zip = try makeZip(of: release)
        #expect(throws: UpdateChecker.UpdateError.commandFailed) { try install(zip, signature: sign(zip)) }
        #expect(version(of: installed) == "1.0")
    }

    private var installedApp: URL { root.appendingPathComponent("installed/EventHorizon.app") }

    private func install(_ zip: URL, signature: Data) throws {
        try UpdateChecker.install(zip: zip, signature: signature,
                                  publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                                  replacing: installedApp, identifier: identifier)
    }

    private func sign(_ zip: URL) throws -> Data {
        try Data((key.signature(for: Data(contentsOf: zip)).base64EncodedString() + "\n").utf8)
    }

    private func makeApp(version: String, in folder: String, identifier: String? = nil) throws -> URL {
        let app = root.appendingPathComponent(folder).appendingPathComponent("EventHorizon.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: macOS.appendingPathComponent("EventHorizon"))
        let plist: [String: String] = [
            "CFBundleIdentifier": identifier ?? self.identifier,
            "CFBundleExecutable": "EventHorizon",
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try shell("/usr/bin/codesign", "--force", "--sign", "-", app.path)
        return app
    }

    private func makeZip(of app: URL) throws -> URL {
        let zip = app.deletingLastPathComponent().appendingPathComponent("EventHorizon.zip")
        try shell("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path)
        return zip
    }

    private func version(of app: URL) -> String? {
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return plist?["CFBundleShortVersionString"] as? String
    }

    private func shell(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
