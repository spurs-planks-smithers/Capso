// Packages/JevKit/Sources/JevKit/Client/KeychainKeyProvider.swift
import Foundation
import Security

/// Supplies the TypeSafe key. It never logs, stores, or copies the key.
public protocol JevKeyProvider: Sendable {
    /// The key, or nil when none is stored or it cannot be read.
    func key() async -> String?
}

/// Reads Nextshot's own key from the login keychain: a generic password with
/// service `TYPESAFE_API_KEY_NEXTSHOT` and account `$USER`, as
/// `keychain-store.sh` stores it.
///
/// The `security` tool made the item, so macOS asks once whether Nextshot may
/// read it. After Always Allow, the item's access list trusts Nextshot's
/// signature. The data protection keychain (Apple TN3137) would need a
/// keychain-access-groups entitlement and an item that the app made itself.
public struct KeychainKeyProvider: JevKeyProvider {
    public static let service = "TYPESAFE_API_KEY_NEXTSHOT"

    public let account: String

    public init(account: String = NSUserName()) {
        self.account = account
    }

    /// The read can wait for the macOS access dialog, so it runs on its own
    /// queue and never holds a Swift concurrency thread.
    public func key() async -> String? {
        let account = account
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.read(account: account))
            }
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum JevKey {
    /// A usable key is 1 to 512 characters with no space or line break, so it
    /// can never add a header line.
    static func isUsable(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 512 && !key.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20 || $0.value == 0x7F }
    }
}
