# Settings visibility, October 27, 2026

Drew requests individual visibility controls for Settings tabs, sections, and components in the October 27 review round.

### Decision

Use a typed SettingsVisibilityFlag registry in FeedbackKit. Keep visibility separate from runtime capabilities. A hidden setting preserves its saved value. A visibility override never enables an optional tool.

Current ordinary settings remain visible by default. Diagnostics and centered-selection settings default off in both channels. Their parent flags also hide child controls. A hidden selected tab falls back to another available tab. With no available tabs, Settings shows a clear empty state.

SettingRow and SettingGroup require a typed visibility key. This compiler check prevents a new shared setting row from silently skipping its flag. Standalone controls and sheet actions use explicit visibility modifiers. Built-in presets have separate keys. Custom presets use stable instance keys.

### Local administration

Use scripts/nextshot-flags.sh list, set, and reset. Visibility names begin with settingsVisibility. The script derives its accepted names from the typed registry and rejects an empty registry. States are off and on. Unknown names and unsupported states fail.

Examples:

```bash
scripts/nextshot-flags.sh set settingsVisibility.general.diagnostics on
scripts/nextshot-flags.sh set settingsVisibility.shortcuts.selection on
scripts/nextshot-flags.sh reset settingsVisibility.general.diagnostics
scripts/nextshot-flags.sh reset settingsVisibility.shortcuts.selection
```

Quit and reopen the app after changing overrides for a complete review. App capability changes still require a restart.

### Review boundaries

Issues 128 through 137 track the ten review requests. Issue 134 waits for the screenshot workflow in issue 123. Drew chooses that dependency explicitly. The current Clipboard Format description stays unchanged until the implemented actions can be checked.

The app removes repository links and visible upstream branding. Internal identifiers and the required bundled license remain. Support buttons open the web form and submit nothing by themselves.

Screen Recording help follows Apple's Mac guide and the actual frozen capture path. It describes broad screen access, local defaults, explicit sharing controls, and access revocation.

### Guides review

The published Guides describe released Nextshot 0.4.0. Keep that reviewedFor value honest. The next app release must refresh the affected General, Permissions, Capture, and Shortcuts pages and their screenshots. The new native captures are review evidence for the Dev build, not released-app media. This change deploys no website or app release.

The clipboard guide also waits for issue 123. Do not describe its planned image-copy actions as implemented.
