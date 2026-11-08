// scripts/dmg-update-harness/Stubs.swift
//
// Stand-ins for the two app types that the install files call. The harness
// offers no startup choice, as a Nextshot Dev build does not.
import AppKit

enum ForkBranding {
    nonisolated static let logSubsystem = Bundle.main.bundleIdentifier ?? "com.drewschulz.nextshot.installtest"
}

@MainActor
final class LoginStartupController {
    static let installerTokenArgument = "--nextshot-login-setup"

    static func canOfferInstallerChoice(destination: URL, runningCopies: [NSRunningApplication]) -> Bool { false }

    static func stageInstallerChoice(_ enabled: Bool) -> String? { nil }
}
