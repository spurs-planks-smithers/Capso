import AppKit
import BrowserBridgeKit
import Carbon
import FeedbackKit

/// Fork: one authenticated local Apple Event path for deliberate browser saves.
@MainActor final class BrowserImportCoordinator {
    static let shared = BrowserImportCoordinator()
    func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) -> Bool {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text), ["browser-import", "browser-handshake"].contains(url.host ?? "") else { return false }
        func fail() { reply.setParam(NSAppleEventDescriptor(string: String(decoding: BrowserBridgeReceipt(state: "failed", error: "unavailable").data, as: UTF8.self)), forKeyword: AEKeyword(keyDirectObject)) }
        guard Flags.isOn(.browserBridge) else { fail(); return true }
        let channel = BuildChannelDetector.current.rawValue
        do {
            guard url.scheme == (channel == "dev" ? "nextshot-dev" : "nextshot"),
                  let audit = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
                  let identifier = Bundle.main.bundleIdentifier,
                  BrowserBridgeIdentity.validates(audit: audit, identifier: identifier + ".browser-host",
                    team: try BrowserBridgeIdentity.team(at: Bundle.main.bundleURL),
                    executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/NextshotBrowserHost")) else { throw BrowserBridgeError.identity }
            if url.host == "browser-handshake" {
                reply.setParam(NSAppleEventDescriptor(string: String(decoding: BrowserBridgeReceipt(state: "ready").data, as: UTF8.self)), forKeyword: AEKeyword(keyDirectObject)); return true
            }
            let nonce = String(url.path.dropFirst())
            guard UUID(uuidString: nonce) != nil, let digest = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "digest" })?.value else { throw BrowserBridgeError.invalid }
            let file = try BrowserBridgeIdentity.prepareInbox(channel: channel).appendingPathComponent("\(nonce).json")
            let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw BrowserBridgeError.invalid }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
                  info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 24 * 1024 * 1024 else { throw BrowserBridgeError.invalid }
            let bytes = try handle.read(upToCount: 24 * 1024 * 1024 + 1) ?? Data()
            guard bytes.count <= 24 * 1024 * 1024, BrowserPayload.digest(bytes) == digest else { throw BrowserBridgeError.invalid }
            let manager = NSAppleEventManager.shared()
            guard let suspension = manager.suspendCurrentAppleEvent() else { throw BrowserBridgeError.invalid }
            Task { @MainActor in
                let result = await self.receive(bytes, channel: channel)
                manager.replyAppleEvent(forSuspensionID: suspension).setParam(NSAppleEventDescriptor(string: String(decoding: result, as: UTF8.self)), forKeyword: AEKeyword(keyDirectObject))
                manager.resume(withSuspensionID: suspension)
            }
        } catch { fail() }
        return true
    }

    private func receive(_ bytes: Data, channel: String) async -> Data {
        guard Flags.isOn(.browserBridge) else { return BrowserBridgeReceipt(state: "failed", error: "disabled").data }
        do {
            let request = try JSONDecoder().decode(BrowserBridgeRequest.self, from: bytes)
            let payload = try request.validated(channel: channel)
            guard let digest = request.digest, let data = request.payload else { throw BrowserBridgeError.invalid }
            let evidenceName = "\(payload.capture.id)-browser.json"
            let capture = payload.nativeCapture(index: 1, digest: digest, evidenceFile: evidenceName)
            let receipt = try await FeedbackController.shared.store.importBrowserCapture(capture,
                assets: Dictionary(uniqueKeysWithValues: payload.assets.map { ($0.name, $0.bytes) }),
                evidence: BrowserPayload.evidence(from: data), ended: payload.capture.kind == "rolling")
            await FeedbackController.shared.refreshAfterBrowserImport()
            return BrowserBridgeReceipt(state: "imported", id: payload.capture.id, digest: digest,
                folder: receipt.folderName, captureIndex: receipt.captureIndex).data
        } catch {
            return BrowserBridgeReceipt(state: "failed", error: "invalid-or-unsaved").data
        }
    }
}
