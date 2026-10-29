import AppKit
import BrowserBridgeKit
import Carbon
import Foundation

@main struct NativeHost {
    @MainActor static func main() async {
        var receipt = BrowserBridgeReceipt(state: "failed", error: "unavailable").data
        do {
            guard CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "chrome-extension://\(BrowserBridgeIdentity.extensionID)/" else { throw BrowserBridgeError.identity }
            let header = FileHandle.standardInput.readData(ofLength: 4)
            guard header.count == 4 else { throw BrowserBridgeError.invalid }
            let count = header.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
            guard count > 0, count <= 24 * 1024 * 1024 else { throw BrowserBridgeError.oversized }
            var requestData = Data()
            while requestData.count < count {
                let chunk = FileHandle.standardInput.readData(ofLength: count - requestData.count)
                guard !chunk.isEmpty else { throw BrowserBridgeError.invalid }; requestData.append(chunk)
            }
            let request = try JSONDecoder().decode(BrowserBridgeRequest.self, from: requestData)
            let helperURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let appURL = helperURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard let bundle = Bundle(url: appURL), let identifier = bundle.bundleIdentifier, let executable = bundle.executableURL,
                  ["com.drewschulz.nextshot.dev", "com.drewschulz.nextshot"].contains(identifier) else { throw BrowserBridgeError.identity }
            let channel = identifier.hasSuffix(".dev") ? "dev" : "release", scheme = channel == "dev" ? "nextshot-dev" : "nextshot"
            guard request.version == 1, request.channel == channel else { throw BrowserBridgeError.invalid }
            let team = try BrowserBridgeIdentity.team(at: appURL)
            var running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { $0.bundleURL?.resolvingSymlinksInPath() == appURL }
            if request.operation == "import" {
                _ = try request.validated(channel: channel)
                if running == nil {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false; configuration.addsToRecentItems = false
                    configuration.arguments = ["--nextshot-browser-bridge"]
                    running = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                }
            } else if request.operation == "assist" {
                guard requestData.count <= 48 * 1024 else { throw BrowserBridgeError.oversized }
                let selected = try request.validatedAssist(channel: channel)
                receipt = BrowserAssistReply(state: "unavailable", request: selected).data
            } else if request.operation != "handshake" { throw BrowserBridgeError.invalid }
            guard let running else { throw BrowserBridgeError.unavailable }
            let nonce = UUID().uuidString.lowercased(), deadline = Date().addingTimeInterval(8)
            func send(_ url: String) throws -> Data {
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: running.processIdentifier),
                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(NSAppleEventDescriptor(string: url), forKeyword: AEKeyword(keyDirectObject))
                let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .init(rawValue: UInt(kAEDoNotPromptForUserConsent))], timeout: request.operation == "assist" ? 30 : 8)
                guard let audit = reply.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
                      BrowserBridgeIdentity.validates(audit: audit, identifier: identifier, team: team, executable: executable),
                      let text = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { throw BrowserBridgeError.identity }
                return Data(text.utf8)
            }
            var ready: Data?
            repeat {
                ready = try? send("\(scheme)://browser-handshake/\(nonce)")
                if ready == nil { try await Task.sleep(for: .milliseconds(50)) }
            } while ready == nil && Date() < deadline
            guard let ready, (try? JSONDecoder().decode(BrowserBridgeReceipt.self, from: ready))?.state == "ready" else { throw BrowserBridgeError.unavailable }
            if ["import", "assist"].contains(request.operation) {
                let folder = try BrowserBridgeIdentity.prepareInbox(channel: channel)
                let file = folder.appendingPathComponent("\(nonce).json")
                let descriptor = open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw BrowserBridgeError.identity }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
                try handle.write(contentsOf: requestData); try handle.synchronize()
                let host = request.operation == "assist" ? "browser-assist" : "browser-import"
                receipt = try send("\(scheme)://\(host)/\(nonce)?digest=\(BrowserPayload.digest(requestData))")
            } else { receipt = ready }
        } catch { /* Keep a correlated assist fallback after its request passes validation. */ }
        let count = UInt32(receipt.count), header = Data((0..<4).map { UInt8((count >> (8 * $0)) & 0xff) })
        FileHandle.standardOutput.write(header); FileHandle.standardOutput.write(receipt)
    }
}
