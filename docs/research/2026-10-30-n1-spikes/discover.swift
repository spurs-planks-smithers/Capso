// N1 spike 2: closed-app discovery without launching the app.
// Build: swiftc -O discover.swift -o discover
// Run:   discover <path to Nextshot Dev.app> [required protocol, default 1]
//
// A helper that Chrome starts lives inside the app bundle, so it can read
// the bundle, its signature, the running-process list and the app's
// preferences while the app is closed. It never opens the app and needs no
// macOS permission for these reads.
import AppKit
import Foundation
import Security

let appURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "").resolvingSymlinksInPath()
let required = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1

func team(at url: URL) -> String? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
    guard SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
    return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}

func report(_ state: String, _ extra: [String: Any] = [:]) -> Never {
    var body = extra
    body["state"] = state
    let data = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard let bundle = Bundle(url: appURL), let identifier = bundle.bundleIdentifier,
      ["com.drewschulz.nextshot.dev", "com.drewschulz.nextshot"].contains(identifier) else { report("absent") }
guard team(at: appURL) != nil else { report("incompatible", ["why": "signature"]) }
// The protocol key does not exist yet. A missing key means protocol 1.
let declared = (bundle.object(forInfoDictionaryKey: "NextshotBrowserBridgeProtocol") as? Int) ?? 1
guard declared >= required else { report("incompatible", ["why": "protocol", "declared": declared, "required": required]) }
// UserDefaults reads another app's preferences with no prompt on an unsandboxed process.
let flag = CFPreferencesCopyAppValue("flag.browserBridge" as CFString, identifier as CFString) as? String
guard flag == "on" else { report("disabled", ["flag": flag ?? "unset"]) }
let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .contains { $0.bundleURL?.resolvingSymlinksInPath() == appURL }
report(running ? "running" : "closed", ["build": (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"])
