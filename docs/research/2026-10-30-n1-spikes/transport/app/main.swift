// N1 spike 3: stand-in for the Mac app side of a temporary active-review connection.
// It is an accessory process, not Nextshot. It answers Apple Events from one signed host,
// holds the reply to a "wait" event until it has a command (no polling), and ends the session
// when the host process exits (DispatchSource, no timers except one bounded session limit).
//
// Control lines on stdin: "cmd <name>" sends a command, "cancel" cancels the review.
// Every event is logged as one JSON line on stdout.
import AppKit
import Carbon
import Foundation

let hostID = CommandLine.arguments[1]
let hostExecutable = URL(fileURLWithPath: CommandLine.arguments[2])
let sessionLimit = Double(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "120") ?? 120
let started = ProcessInfo.processInfo.systemUptime
let team = try BrowserBridgeIdentity.team(at: URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath())

func log(_ event: String, _ extra: [String: Any] = [:]) {
    var body = extra
    body["ev"] = event
    body["ms"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
    let data = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

final class Session {
    let id: String
    let hostPID: pid_t
    var suspension: NSAppleEventManager.SuspensionID?
    var queued: [String] = []
    var exitSource: DispatchSourceProcess?
    var limit: DispatchWorkItem?
    var sequence = 0
    init(id: String, hostPID: pid_t) { self.id = id; self.hostPID = hostPID }
}

var sessions: [String: Session] = [:]
let manager = NSAppleEventManager.shared()

func answer(_ session: Session, _ text: String) {
    guard let suspension = session.suspension else { session.queued.append(text); return }
    session.suspension = nil
    manager.replyAppleEvent(forSuspensionID: suspension)
        .setParam(NSAppleEventDescriptor(string: text), forKeyword: AEKeyword(keyDirectObject))
    manager.resume(withSuspensionID: suspension)
}

func end(_ session: Session, reason: String) {
    session.limit?.cancel()
    session.exitSource?.cancel()
    if session.suspension != nil { answer(session, "{\"cmd\":\"closed\"}") }
    sessions[session.id] = nil
    log("session-ended", ["id": session.id, "reason": reason])
}

final class Handler: NSObject {
    @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text), url.scheme == "spike" else { return }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? -1
        func deny(_ why: String) {
            log("rejected", ["why": why, "senderPID": senderPID, "op": url.host ?? ""])
            reply.setParam(NSAppleEventDescriptor(string: "{\"state\":\"denied\"}"), forKeyword: AEKeyword(keyDirectObject))
        }
        guard let audit = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data,
              BrowserBridgeIdentity.validates(audit: audit, identifier: hostID, team: team, executable: hostExecutable) else { deny("identity"); return }
        let id = String(url.path.dropFirst())
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func say(_ body: String) { reply.setParam(NSAppleEventDescriptor(string: body), forKeyword: AEKeyword(keyDirectObject)) }
        switch url.host ?? "" {
        case "open":
            guard sessions.isEmpty else { deny("busy"); return }
            let session = Session(id: id, hostPID: senderPID)
            let source = DispatchSource.makeProcessSource(identifier: senderPID, eventMask: .exit, queue: .main)
            source.setEventHandler { end(session, reason: "host-exited") }
            source.resume()
            session.exitSource = source
            let limit = DispatchWorkItem { end(session, reason: "session-limit") }
            session.limit = limit
            DispatchQueue.main.asyncAfter(deadline: .now() + sessionLimit, execute: limit)
            sessions[id] = session
            log("session-open", ["id": id, "hostPID": senderPID])
            say("{\"state\":\"opened\"}")
        case "wait":
            guard let session = sessions[id] else { deny("unknown-session"); return }
            if let result = query.first(where: { $0.name == "result" })?.value { log("result", ["id": id, "value": result]) }
            if !session.queued.isEmpty { say(session.queued.removeFirst()); return }
            session.suspension = manager.suspendCurrentAppleEvent()
            log("wait-held", ["id": id])
        case "close":
            if let session = sessions[id] { end(session, reason: "host-close") }
            say("{\"state\":\"closed\"}")
        default:
            deny("unknown-op")
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    let handler = Handler()
    func applicationWillFinishLaunching(_ notification: Notification) {
        manager.setEventHandler(handler, andSelector: #selector(Handler.handle(_:reply:)),
                                forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("ready", ["pid": getpid(), "team": team])
        Thread {
            while let line = readLine() {
                DispatchQueue.main.async {
                    guard let session = sessions.values.first else { log("no-session"); return }
                    if line == "cancel" { session.sequence += 1; answer(session, "{\"cmd\":\"cancel\"}"); log("cancel-sent"); return }
                    if line.hasPrefix("cmd ") {
                        session.sequence += 1
                        answer(session, "{\"cmd\":\"\(line.dropFirst(4))\",\"seq\":\(session.sequence)}")
                        log("cmd-sent", ["seq": session.sequence])
                    }
                }
            }
            DispatchQueue.main.async { exit(0) }
        }.start()
    }
}

let delegate = Delegate()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
