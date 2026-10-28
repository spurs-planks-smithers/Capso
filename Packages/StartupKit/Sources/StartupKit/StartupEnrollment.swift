import Foundation

public enum LoginItemStatus: Sendable {
    case off, on, approvalRequired, unavailable
}

@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func enable() throws
    func disable() throws
}

/// Records setup once. A launch never restores a saved enabled preference.
@MainActor
public final class StartupEnrollment {
    private static let completedKey = "nextshot.login.setupCompleted"
    private static let choiceKey = "nextshot.login.userChoice"
    private static let pendingKey = "nextshot.login.installerChoice"
    private let defaults: UserDefaults
    private let service: any LoginItemService
    public private(set) var firstUsePending = false
    public private(set) var lastChangeFailed = false
    public var status: LoginItemStatus { service.status }
    public var setupCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

    public init(defaults: UserDefaults, service: any LoginItemService) {
        self.defaults = defaults
        self.service = service
    }

    public func canOfferInstallerChoice(hasPriorUse: Bool, replacingApp: Bool) -> Bool {
        !setupCompleted && !hasPriorUse && !replacingApp && status == .off
    }

    /// Called only after the user accepts installation with a visible choice.
    public func stageInstallerChoice(enabled: Bool) -> String? {
        guard !setupCompleted, status == .off else { return nil }
        let token = UUID().uuidString
        defaults.set(true, forKey: Self.completedKey)
        defaults.set(["token": token, "enabled": enabled] as [String: Any], forKey: Self.pendingKey)
        guard defaults.synchronize() else { return nil }
        return token
    }

    /// A matching one-use handoff carries installer consent. All other launches
    /// only offer first-use setup, or preserve the existing system state.
    public func prepareLaunch(eligibleRelease: Bool, hasPriorUse: Bool, loginLaunch: Bool, installerToken: String?) -> Bool {
        guard eligibleRelease, !loginLaunch else { return false }
        let pending = defaults.dictionary(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.pendingKey)
        if let installerToken, !installerToken.isEmpty,
           pending?["token"] as? String == installerToken,
           let enabled = pending?["enabled"] as? Bool {
            defaults.set(true, forKey: Self.completedKey)
            guard defaults.synchronize() else { return false }
            // A system change after consent wins over the installer handoff.
            if status == .off { changeEnabled(enabled) }
            return false
        }
        guard !setupCompleted else { return false }
        defaults.set(true, forKey: Self.completedKey)
        guard defaults.synchronize(), !hasPriorUse, status == .off else { return false }
        firstUsePending = true
        return true
    }

    /// Closing setup without confirmation leaves the system registration off.
    public func finishFirstUse(enabled: Bool) {
        guard firstUsePending else { return }
        firstUsePending = false
        changeEnabled(enabled)
    }

    /// Only an explicit Settings action or consumed installer consent calls this.
    public func changeEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.completedKey)
        defaults.set(enabled, forKey: Self.choiceKey)
        defaults.removeObject(forKey: Self.pendingKey)
        lastChangeFailed = false
        let saved = defaults.synchronize()
        // Persist consent before enabling. Failure must never cause a retry.
        guard !enabled || saved else { lastChangeFailed = true; return }
        do {
            switch (enabled, service.status) {
            case (true, .off): try service.enable()
            case (false, .on), (false, .approvalRequired): try service.disable()
            case (_, .unavailable): lastChangeFailed = true
            default: break
            }
        } catch {
            lastChangeFailed = true
        }
    }
}
