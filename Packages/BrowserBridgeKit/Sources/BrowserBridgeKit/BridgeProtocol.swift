import Foundation
import Security

public struct BrowserBridgeRequest: Codable, Sendable {
    public let version: Int
    public let channel: String
    public let operation: String
    public let id: String?
    public let digest: String?
    public let payload: Data?

    public func validatedAssist(channel expected: String) throws -> BrowserAssistRequest {
        guard version == 1, channel == expected, operation == "assist", let id, let digest, let payload,
              BrowserPayload.digest(payload) == digest else { throw BrowserBridgeError.invalid }
        let request = try BrowserAssistRequest.decode(payload)
        guard request.requestID == id else { throw BrowserBridgeError.invalid }
        return request
    }

    public func validated(channel expected: String) throws -> BrowserPayload {
        guard version == 1, channel == expected, operation == "import", let id, let digest, let payload else { throw BrowserBridgeError.invalid }
        return try BrowserPayload.decode(payload, id: id, digest: digest)
    }
}

public struct BrowserBridgeReceipt: Codable, Sendable {
    public let state: String
    public let id: String?
    public let digest: String?
    public let folder: String?
    public let captureIndex: Int?
    public let error: String?

    public init(state: String, id: String? = nil, digest: String? = nil, folder: String? = nil, captureIndex: Int? = nil, error: String? = nil) {
        self.state = state; self.id = id; self.digest = digest; self.folder = folder; self.captureIndex = captureIndex; self.error = error
    }
    public var data: Data { (try? JSONEncoder().encode(self)) ?? Data("{\"state\":\"failed\"}".utf8) }
}

public enum BrowserBridgeIdentity {
    public static let extensionID = "ghmidcmcjigfckaiopacgpfaffofgjel"
    public static func inboxURL(channel: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextshotBrowserBridge-\(channel)", isDirectory: true)
    }
    public static func prepareInbox(channel: String) throws -> URL {
        let folder = inboxURL(channel: channel), manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: folder.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              attributes[.ownerAccountID] as? UInt32 == getuid(),
              (attributes[.posixPermissions] as? Int ?? 0) & 0o077 == 0,
              (try folder.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw BrowserBridgeError.identity }
        for file in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])) ?? [] {
            guard file.pathExtension == "json", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate, date < Date().addingTimeInterval(-900) else { continue }
            try? manager.removeItem(at: file)
        }
        return folder
    }
    public static func requirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
    public static func team(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw BrowserBridgeError.identity }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { throw BrowserBridgeError.identity }
        return team
    }
    public static func executable(pid: pid_t) -> URL? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode, SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoMainExecutable as String] as? URL
    }

    /// The Apple Event Manager attaches this read-only kernel audit token.
    public static func validates(audit: Data, identifier: String, team: String, executable: URL) -> Bool {
        guard audit.count == 32 else { return false }
        var code: SecCode?, requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: audit] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecRequirementCreateWithString(Self.requirement(identifier: identifier, team: team) as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else { return false }
        var staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let url = (info as? [String: Any])?[kSecCodeInfoMainExecutable as String] as? URL else { return false }
        return url.resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
    }
}
