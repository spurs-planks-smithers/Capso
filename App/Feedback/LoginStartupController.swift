import AppKit
import Foundation
import Observation
import Security
import ServiceManagement
import StartupKit

@MainActor
private final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .notRegistered: .off
        case .requiresApproval: .approvalRequired
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
}

/// Fork: login registration follows explicit consent, never a saved on value.
@Observable
@MainActor
final class LoginStartupController {
    static let shared = LoginStartupController()
    static let installerTokenArgument = "--nextshot-login-setup"
    private let enrollment = StartupEnrollment(defaults: .standard, service: SystemLoginItemService())
    private(set) var status: LoginItemStatus = .off
    private(set) var firstUsePending = false
    private(set) var lastChangeFailed = false
    var initialChoice = true

    var canControl: Bool { Self.isInstalledSignedApp }

    /// Inspect prior use before AppDelegate writes defaults or starts its trial.
    func prepareLaunch(loginLaunch: Bool) -> Bool {
        let args = CommandLine.arguments
        let tokenIndex = args.firstIndex(of: Self.installerTokenArgument)
        let token = tokenIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let showSetup = enrollment.prepareLaunch(
            eligibleRelease: Self.isRelease && canControl,
            hasPriorUse: Self.hasPriorUse,
            loginLaunch: loginLaunch,
            installerToken: token
        )
        refresh()
        return showSetup
    }

    static func canOfferInstallerChoice(destination: URL, runningCopies: [NSRunningApplication]) -> Bool {
        guard isRelease, hasTrustedSignature else { return false }
        return shared.enrollment.canOfferInstallerChoice(
            hasPriorUse: hasPriorUse,
            replacingApp: !runningCopies.isEmpty || FileManager.default.fileExists(atPath: destination.path)
        )
    }

    static func stageInstallerChoice(_ enabled: Bool) -> String? {
        shared.enrollment.stageInstallerChoice(enabled: enabled)
    }

    func confirmFirstUse() {
        guard canControl else { return }
        enrollment.finishFirstUse(enabled: initialChoice)
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard canControl else { return }
        enrollment.changeEnabled(enabled)
        refresh()
    }

    func refresh() {
        status = enrollment.status
        firstUsePending = enrollment.firstUsePending
        lastChangeFailed = enrollment.lastChangeFailed
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    private static var isRelease: Bool { Bundle.main.bundleIdentifier == "com.drewschulz.nextshot" }

    private static var hasPriorUse: Bool {
        guard let domain = Bundle.main.bundleIdentifier else { return true }
        if !(UserDefaults.standard.persistentDomain(forName: domain) ?? [:]).isEmpty { return true }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ["Nextshot", "CapsoFeedback"].contains {
            FileManager.default.fileExists(atPath: support.appendingPathComponent($0).path)
        }
    }

    private static let isInstalledSignedApp: Bool = {
        guard !CommandLine.arguments.contains("--capso-ocr-helper"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ["com.drewschulz.nextshot", "com.drewschulz.nextshot.dev"].contains(Bundle.main.bundleIdentifier ?? "")
        else { return false }
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let folders = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        guard app.pathExtension == "app", !app.lastPathComponent.hasPrefix("."),
              folders.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == app.deletingLastPathComponent() }),
              !DiskImageInstaller.isOnReadOnlyVolume(app) else { return false }
        return hasTrustedSignature
    }()

    /// Unlike BuildChannelDetector's security fallback, this requires a valid,
    /// positively identified app signature before any registration is allowed.
    private static var hasTrustedSignature: Bool {
        guard ["com.drewschulz.nextshot", "com.drewschulz.nextshot.dev"].contains(Bundle.main.bundleIdentifier ?? "") else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let certificate = certificates.first,
              let name = SecCertificateCopySubjectSummary(certificate) as String? else { return false }
        return name.hasPrefix(isRelease ? "Developer ID Application" : "Apple Development")
    }
}
