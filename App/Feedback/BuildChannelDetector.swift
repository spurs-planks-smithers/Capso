// App/Feedback/BuildChannelDetector.swift
import FeedbackKit
import Foundation
import Security

/// Fork: tells a release build from a dev build by the app's own code
/// signature, so the build scripts and Info.plist need no flag. Only a
/// Developer ID Application signature counts as release. Apple Development,
/// ad hoc (`CODE_SIGN_IDENTITY="-"`), and unsigned test builds are dev.
///
/// Dev-only flags (every Jev flag) can turn on only in dev, so the check
/// fails closed: when the Security framework cannot read the signature, the
/// build counts as release. Only a signature with no certificates (ad hoc or
/// unsigned) is dev without a certificate check.
enum BuildChannelDetector {
    /// Read once on first use. The signature cannot change while the app runs.
    static let current: BuildChannel = detect()

    private static func detect() -> BuildChannel {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .release }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .release }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return .release }
        guard let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return .dev }
        guard let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return .release }
        return summary.hasPrefix("Developer ID Application") ? .release : .dev
    }
}
