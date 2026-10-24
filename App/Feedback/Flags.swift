// App/Feedback/Flags.swift
import FeedbackKit
import Foundation

/// Fork: the app's entry point to the feature flag registry (`FeatureFlag` in
/// FeedbackKit). A local override in UserDefaults wins, then the default for
/// the build channel. `scripts/nextshot-flags.sh` writes the overrides. There
/// is no interface for flags. The state is read on each call, so a change
/// shows up at the next check.
enum Flags {
    static func state(_ flag: FeatureFlag) -> FlagState {
        FlagResolver.state(of: flag, channel: BuildChannelDetector.current) {
            UserDefaults.standard.string(forKey: $0)
        }
    }

    static func isOn(_ flag: FeatureFlag) -> Bool {
        state(flag) == .on
    }
}
