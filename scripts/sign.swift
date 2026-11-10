// Usage: swift scripts/sign.swift keygen        -> creates the signing key in the Keychain, prints the public key
//        swift scripts/sign.swift public        -> prints the public key
//        swift scripts/sign.swift sign <file>   -> prints the base64 signature of <file>
//        swift scripts/sign.swift import <public key> < key   -> saves a backed-up private key (read from stdin)
//                                                                in the Keychain if it matches <public key>
// The private key never leaves the Keychain through this script. Back it up from Keychain Access.
import CryptoKit
import Foundation
import Security

let service = "EventHorizon Signing Key"
let account = "release"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let stored = result as? Data,
          let text = String(data: stored, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func requireKey() -> Curve25519.Signing.PrivateKey {
    guard let key = storedKey() else { fail("No signing key in the Keychain (\"\(service)\"). Run ./build.sh keygen or restore it.") }
    return key
}

func save(_ key: Curve25519.Signing.PrivateKey) {
    let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrLabel as String: service,
        kSecValueData as String: Data(key.rawRepresentation.base64EncodedString().utf8),
    ]
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail("Keychain error \(status)") }
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "keygen":
    guard storedKey() == nil else { fail("A signing key already exists. Delete it in Keychain Access first.") }
    let key = Curve25519.Signing.PrivateKey()
    save(key)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "import":
    guard storedKey() == nil else { fail("A signing key already exists. Delete it in Keychain Access first.") }
    guard let expected = arguments.dropFirst().first else { fail("Usage: import <public key> < key") }
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("That is not a valid private key.") }
    guard key.publicKey.rawRepresentation.base64EncodedString() == expected else {
        fail("That key doesn't match the public key in the app.")
    }
    save(key)
    print("Signing key saved in the Keychain.")
case "public":
    print(requireKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = arguments.dropFirst().first,
          let data = FileManager.default.contents(atPath: path) else { fail("Usage: sign <file>") }
    print(try requireKey().signature(for: data).base64EncodedString())
default:
    fail("Usage: swift scripts/sign.swift keygen | public | sign <file> | import <public key>")
}
