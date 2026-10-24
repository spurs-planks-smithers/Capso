// App/Feedback/BuildChannelDetector.swift
import FeedbackKit
import Foundation
import Security

/// Fork: tells a release build from a dev build by the app's own code
/// signature, so the build scripts and Info.plist need no flag. Only a
/// Developer ID Application signature counts as release. Apple Development,
/// ad hoc (`CODE_SIGN_IDENTITY="-"`), and unsigned test builds are dev.
enum BuildChannelDetector {
    /// Read once on first use. The signature cannot change while the app runs.
    static let current: BuildChannel = detect()

    private static func detect() -> BuildChannel {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .dev }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .dev }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String?
        else { return .dev }
        return summary.hasPrefix("Developer ID Application") ? .release : .dev
    }
}
