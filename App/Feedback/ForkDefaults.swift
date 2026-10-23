// App/Feedback/ForkDefaults.swift
import Foundation

/// Fork: settings whose default differs from upstream's. These are registered
/// defaults, so they apply only while the user has not set the key, and the
/// Preferences toggles still win. `AppDelegate` registers them before any
/// coordinator reads a setting.
enum ForkDefaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            // Only the Nshot item shows in the menu bar by default (Drew,
            // 2026-10-22). Preferences > General > Show menu bar icon brings
            // back the capture menu's icon.
            "showMenuBarIcon": false,
        ])
    }
}
