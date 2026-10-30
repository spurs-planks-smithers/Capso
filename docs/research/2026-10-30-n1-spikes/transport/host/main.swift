// N1 spike 3: stand-in for the browser-started helper during one active review.
// Chrome would start it with connectNative and keep it until the port closes.
// Usage: host <origin> <app pid> <app identifier> <app executable>
// It relays framed JSON between Chrome (stdio) and the app (one held Apple Event),
// and exits when Chrome closes the port, the app ends the review, or the app dies.
import AppKit
import Carbon
import Foundation

let args = CommandLine.arguments
let appPID = pid_t(args[2]) ?? 0
let appID = args[3]
let appExecutable = URL(fileURLWithPath: args[4])
// An ad-hoc signed impostor has no team, so use a placeholder and let the app reject it.
let team = (try? BrowserBridgeIdentity.team(at: URL(fileURLWithPath: args[0]).resolvingSymlinksInPath())) ?? "none"
let began = ProcessInfo.processInfo.systemUptime
let outputLock = NSLock()
let resultReady = DispatchSemaphore(value: 0)
var pendingResult = ""
var opened = false
let sessionID = "S1"

func emit(_ body: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    var count = UInt32(data.count).littleEndian
    outputLock.lock()
    FileHandle.standardOutput.write(Data(bytes: &count, count: 4) + data)
    outputLock.unlock()
}

func finish(_ reason: String) -> Never {
    if opened && !reason.hasPrefix("app-") { _ = try? send("spike://close/\(sessionID)", timeout: 1) }
    let lifetime = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
    FileHandle.standardError.write(Data("{\"host\":\"exit\",\"reason\":\"\(reason)\",\"lifetimeMs\":\(lifetime)}\n".utf8))
    exit(0)
}

func send(_ url: String, timeout: Double) throws -> String {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
        targetDescriptor: NSAppleEventDescriptor(processIdentifier: appPID),
        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(NSAppleEventDescriptor(string: url), forKeyword: AEKeyword(keyDirectObject))
    let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .init(rawValue: UInt(kAEDoNotPromptForUserConsent))], timeout: timeout)
    guard let audit = reply.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
          BrowserBridgeIdentity.validates(audit: audit, identifier: appID, team: team, executable: appExecutable),
          let text = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { throw BrowserBridgeError.identity }
    return text
}

func readFrame() -> [String: Any]? {
    let header = FileHandle.standardInput.readData(ofLength: 4)
    guard header.count == 4 else { return nil }
    let count = header.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
    guard count > 0, count <= 8_388_608 else { return nil }
    var body = Data()
    while body.count < count {
        let chunk = FileHandle.standardInput.readData(ofLength: count - body.count)
        if chunk.isEmpty { return nil }
        body.append(chunk)
    }
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func relayLoop() {
    var result = ""
    while true {
        var url = "spike://wait/\(sessionID)"
        if !result.isEmpty { url += "?result=" + (result.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
        do {
            let text = try send(url, timeout: 130)
            guard let command = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                  let name = command["cmd"] as? String else { emit(["type": "closed", "reason": "bad-reply"]); finish("app-bad-reply") }
            if ["cancel", "closed"].contains(name) { emit(["type": "closed", "reason": "app-\(name)"]); finish("app-\(name)") }
            emit(["type": "command", "command": command])
            resultReady.wait()
            result = pendingResult
        } catch {
            emit(["type": "closed", "reason": "app-gone", "code": (error as NSError).code]); finish("app-gone")
        }
    }
}

while let frame = readFrame() {
    switch frame["op"] as? String ?? "" {
    case "open":
        do {
            let reply = try send("spike://open/\(sessionID)", timeout: 5)
            guard reply.contains("opened") else { emit(["type": "closed", "reason": "denied"]); finish("denied") }
            opened = true
            emit(["type": "ready", "ms": Int((ProcessInfo.processInfo.systemUptime - began) * 1000)])
            Thread { relayLoop() }.start()
        } catch {
            emit(["type": "closed", "reason": "no-app", "code": (error as NSError).code]); finish("no-app")
        }
    case "result":
        pendingResult = String(describing: frame["value"] ?? "")
        resultReady.signal()
    case "burst":
        // Message-size probe: send `bytes` of filler to Chrome in frames of `chunk` characters.
        let total = frame["bytes"] as? Int ?? 0, size = max(1, frame["chunk"] as? Int ?? 1)
        let filler = String(repeating: "A", count: size), mark = ProcessInfo.processInfo.systemUptime
        var sent = 0, index = 0
        while sent < total { emit(["type": "chunk", "index": index, "data": filler]); sent += size; index += 1 }
        emit(["type": "burst-done", "chunks": index, "hostMs": Int((ProcessInfo.processInfo.systemUptime - mark) * 1000)])
    case "echo":
        emit(["type": "echo", "received": (frame["data"] as? String)?.count ?? 0])
    case "close":
        emit(["type": "closed", "reason": "chrome-close"]); finish("chrome-close")
    default:
        break
    }
}
finish("chrome-disconnect")
