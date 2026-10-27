# Nextshot Settings catalog

Source review: October 27, 2026, checkout `188ee7d`, `VERSION` 0.3.0. Status: baseline source catalog, with the eight visible tabs checked in Dev build 772. Drew selects feedback rounds first for the next release. Implementation plan: [[2026-10-27-settings-guide-and-feature-gates]].

### Scope and evidence

This catalogs the Settings window, its sheets, its contextual references, and related hidden preferences. Defaults mean a fresh settings domain. Existing users can retain different values. Personal usage frequency was not measured. The code defines nine tabs. Eight appear in the sidebar. Cloud Share is filtered out. See `App/Sources/Preferences/PreferencesView.swift`. The window is fixed at 680 by 480 points and each tab scrolls. This is source evidence, not a measured layout audit.

Baseline access is resolved on October 27. The running Dev copy lives under the original build folder and uses build 772. Its eight visible tabs match this catalog. Screenshots are saved under `build/settings-review/baseline` in the original checkout. Hidden and conditional controls retain source evidence only. This baseline does not certify the released binary or the new simplified layout.

Source keys: G = `App/Sources/Preferences/Tabs/GeneralSettingsView.swift`; S = `ScreenshotSettingsView.swift`; R = `RecordingSettingsView.swift`; Q = `QuickAccessSettingsView.swift`; E = `ExportSettingsView.swift`; T = `OCRSettingsView.swift`; K = `ShortcutSettingsView.swift`; P = `PermissionSettingsView.swift`. All abbreviated tab filenames share G's directory. Defaults live in `Packages/SharedKit/Sources/SharedKit/Settings/AppSettings.swift`, except where stated.

### General

| Control | Fresh default | What it does and scope |
| --- | --- | --- |
| Launch at Login | Off | LaunchAtLogin package starts Nextshot at login. Applies to round use. |
| Show Menu Bar Icon | Off | Shows the extra capture menu. The Nshot round menu remains visible. `App/Feedback/ForkDefaults.swift` sets the fork default. |
| Hide Icon / Cancel | n/a | Confirmation when hiding that extra menu. Current wording does not explain the separate Nshot menu. |
| Automation URLs | Off | Allows incoming capture commands from other apps. Does not configure feedback round App Intents. |
| Supported URLs / View Commands… | n/a | Opens a command reference, even while URL automation is off. |
| Shutter Sound | On | Plays after ordinary captures. Feedback captures explicitly suppress it. |
| Automatically Check for Updates | Off | Enables Sparkle background checks. No Nextshot feed is configured. |
| Check Frequency | Daily | Daily, Weekly, Monthly. Monthly means 30 days. Disabled while automatic checks are off. |
| Automatically Install Updates | Off | Stores Sparkle's install preference. Disabled while automatic checks are off, without clearing the saved choice. |
| Check for Updates | n/a | Probes for an update, then opens interactive update UI if one exists. Availability follows Sparkle. No working feed is configured. |
| Save to History | On | Stores ordinary captures in screenshot History. Feedback round storage is independent. |
| Keep History | 1 Month | 1 Week, 2 Weeks, 1 Month, Unlimited. Deletes older ordinary History items. Remains enabled when saving is off. |
| Diagnostic Logging | Off | Writes local troubleshooting logs. |
| Diagnostic Logs / Open | n/a | Prepares the local log file and reveals it in Finder. |
| Crash Reports / Open | n/a | Opens the macOS DiagnosticReports folder. |
| Version | Bundle value | Shows the installed app version and build. |
| Report a Bug / Report | n/a | Opens the fork's GitHub bug form. Does not submit a report itself. |
| Request a Feature / Request | n/a | Opens the fork's GitHub feature form. |
| Source Code / Open | n/a | Opens the fork repository. |
| Follow on X / Follow | n/a | Opens upstream author @lzhgus. This is not a Nextshot account. |

Updates appear because `AppDelegate` supplies an `UpdateManager`. Supporting files: `App/Sources/Preferences/Components/UpdatesSettingsSection.swift`, `CheckForUpdatesView.swift`, `SoftwareUpdating.swift`, and `App/Resources/Info.plist`. Manual DMG updates remain the supported path. Full history reviewed: [Self-serve updates: Sparkle with a Nextshot feed](https://github.com/spurs-planks-smithers/Capso/issues/4). The automation reference sheet copies one command or all commands. Done closes it. Its groups cover Screenshots, Clipboard, Text & Translation, Recording, Desktop, and History & Settings. They include each capture mode, pinning, image editing, OCR, translation, recording, desktop visibility, History, and Preferences. These commands do not start or manage feedback rounds. `App/Sources/Preferences/Components/AutomationURLsSheetView.swift` hardcodes production `nextshot://` URLs, including in a dev build.

### Permissions

| Control | Fresh default | Purpose |
| --- | --- | --- |
| Screen Recording | macOS state | Required for round screenshots and screen recording. The permission name does not mean rounds record video. |
| Accessibility | macOS state | Selected-text translation. Not required for the round workflow. |
| Input Monitoring | macOS state | Recording key overlay. Not required for the round workflow. |
| Camera | macOS state | Camera overlay in recordings. |
| Microphone | macOS state | Microphone audio in recordings. |
| Allowed / Needs Access | Read-only | Reports each permission's current state. |
| Open / Request | n/a | Opens system settings for screen, accessibility, and input access. Requests camera or microphone access. |
| Open System Settings icon | n/a | Opens the system permission page for that row. |
| Refresh | n/a | Reads all permission states again. |

P and `PreferencesViewModel.requestPermission` show a mismatch: an allowed Camera or Microphone row says Open but requests access again. The separate settings icon opens the system page. No permission is requested during this review.

### Screenshots

| Control | Fresh default | What it does and scope |
| --- | --- | --- |
| Show Preview | On | Opens the ordinary screenshot preview. Does not control round notes or their preview. |
| Copy to Clipboard | Off | Copies ordinary captures immediately. Round prompt copy is separate. |
| Clipboard Content | Image | Image or File Path. Ordinary path copy uses the saved file or a temporary file kept for 24 hours. |
| Clipboard Format | PNG | PNG, JPEG, TIFF. Currently visible only when Clipboard Content is Image. Also controls Escape copy from an unmarked round capture. |
| Auto Save | Off | Writes ordinary screenshots to the export folder. Round captures save through their own store. |
| Show Cursor | Off | Includes the pointer in supported screenshots, including feedback area capture. |
| Capture Window Shadow | On | Includes native window shadow in window capture. Round capture selects an area. |
| Add Timestamp | Off | Adds capture time to image pixels, including feedback capture pixels. |
| Position | Bottom Right | Eight corner or edge positions. Appears when timestamp is on. |
| Format | Date & Time | Date & Time, Date, Time, ISO 8601. Appears when timestamp is on. |
| Color | #FFFFFF | Six-digit timestamp color. Invalid input falls back to white. Appears when timestamp is on. |
| Font Size | 14 points | 8 to 72 points. Appears when timestamp is on. |
| Beautify Every Screenshot | Off | Applies saved background, padding, corners, and shadow. Excludes feedback, pin, OCR, and editor capture actions. |
| Default Duration | 5 seconds | Self-timer delay, 1 to 60 seconds. Does not delay the round shortcut. |
| Tick Sound | On | Self-timer countdown sound. Separate from shutter sound. |
| Capture Presets | On | Offers aspect ratio or fixed size constraints during area selection, including feedback. Starts with Freeform selected. |
| 1:1 (Square), 4:3, 16:9, 3:2 | All visible | Individual built-in ratio toggles. Visible when presets are on. Freeform remains available. |
| 512 × 512, 1280 × 720 (720p), 1920 × 1080 (1080p) | All visible | Individual fixed size toggles. Visible when presets are on. |
| Custom preset minus button | No custom presets | Removes one saved custom preset. |
| Add Custom Preset | n/a | Opens the custom preset sheet. |
| Aspect Ratio / Fixed Size | Aspect Ratio | Selects the custom preset type. |
| Width ratio / Width (px) | Empty | Sets ratio width or pixel width. |
| Height ratio / Height (px) | Empty | Sets ratio height or pixel height. |
| Name (optional) | Empty | Adds a descriptive preset name. |
| Add / Cancel | n/a | Saves or cancels the custom preset. Current Add validation accepts zero and negative integers. |

S owns the controls. `App/Sources/Capture/CaptureCoordinator.swift` applies timestamps before the feedback sink, but excludes feedback from beautify, ordinary History, and preview actions. `App/Feedback/FeedbackController.swift` uses `ImageUtilities.copyToPasteboard` for Escape. October 27 documentation drift: AGENTS describes PNG/JPEG there; the current enum and encoder also support TIFF. Record current code behavior without silently changing that description.

### Recording

| Control | Fresh default | What it does |
| --- | --- | --- |
| Show Cursor | On | Includes the pointer in recordings. Distinct from screenshot Show Cursor. |
| Highlight Clicks | On | Displays a radial click overlay. |
| Show Key Presses | Off | Displays pressed keys with Input Monitoring. Window-target recording skips the overlay. |
| Show Countdown | On | Shows three seconds before recording when a selected screen exists. |
| Hide Desktop Icons | Off | Covers desktop icons with wallpaper during recording. |
| Open Editor After Recording | Off | Uses the recording editor workflow before export. |
| Copy to Clipboard | Off | Copies the finished MP4 or GIF file. |
| Remember Last Recording Area | Off | Reuses a stored recording selection. |
| Fade on Hover | Off | Makes the small camera picture-in-picture view nearly transparent under the pointer. Fullscreen stays solid. |
| Click Through PiP | Off | Passes clicks through the small camera view. Independent of fading. Does not apply in fullscreen. |

R owns these controls. `App/Sources/Recording/RecordingCoordinator.swift` consumes them. They do not affect round capture. Format, microphone, system audio, camera shape, camera size, and recording quality choices also exist in recording toolbars or camera menus. Those are contextual tool controls, not additional Settings rows.

### Quick Access

| Control | Fresh default | What it does |
| --- | --- | --- |
| Preview Position | Bottom Left | Bottom Left, Center, Bottom Right for the floating screenshot preview. |
| Auto-Close Preview | Off | Closes the ordinary preview after a timeout. |
| Close After | 5 seconds | 5, 10, 15, 30 seconds. Disabled while auto-close is off. |
| Close After Dragging | On | Closes after a successful drop into another app. |

Q and `App/Sources/QuickAccess/QuickAccessWindow.swift` own this behavior. It does not control the feedback help box, editor, note panel, or toast duration.

### Export

| Control | Fresh default | What it does |
| --- | --- | --- |
| Export Quality | Maximum | Maximum preserves source MP4 quality. Social selects a 1920 × 1080 preset; Web selects 1280 × 720. Smaller sources can pass through unchanged. GIF profiles use widths up to 1920/1080/720 pixels and rates up to 25/20/15 frames per second. Long GIFs reduce rate to limit total frames. |
| Screenshot Format | PNG | PNG, JPEG, HEIC. Only formats this Mac can encode appear. |
| Screenshot Quality | 85% | JPEG/HEIC only. Range 30% to 100%, in 5-point steps. |
| Export To / Choose… | Desktop | Selects the ordinary export folder. |
| Monthly Screenshot Folders | Off | Adds a yyyy-MM subfolder for ordinary screenshots. |
| Screenshot Filename | `Nextshot Screenshot{source} {timestamp}` | Edits ordinary screenshot names. Extension is added automatically. Empty input resets on submit or leaving the tab. |
| Filename info button | n/a | Lists `{date}`, `{time}`, `{timestamp}`, `{source}`, `{app}`, `{window}`, `{random}`. |
| Filename reset button | n/a | Restores the default template. |
| Preview | Generated example | Shows the resulting ordinary filename. |
| When Saving an Opened Image | Ask Every Time | Ask Every Time, Overwrite Original, Save New Copy for images opened from Finder or Open Image. |

E owns these controls. Feedback rounds retain their own location, filenames, PNG encoding, and `ImageSizing.feedbackExport` limits. Zip handoff has separate JPEG sizing rules. Export quality and the export folder do not configure either route.

### Text & Translation

| Control | Fresh default | What it does |
| --- | --- | --- |
| Keep Line Breaks | On | Joins standalone recognized lines with line breaks. Off uses spaces. |
| Detect Links | On | Detects URLs in the visual OCR overlay. Instant text copy does not linkify. OCR means optical character recognition. |
| Target Language | System language | Uses a supported locale language, with English fallback. Supported languages load asynchronously. |
| Provider | Apple | The visible picker lists Apple only. It does not override a saved external provider. |
| API Key / save checkmark | Empty | Conditional on a saved provider requiring a key. Saves or clears its Keychain item. |
| Endpoint | Provider default | Conditional on provider support. Sets its service address. |
| Model | Provider default | Conditional on provider support. Sets its model identifier. |
| Connection / Test Connection | n/a | Conditional external-provider test. Saves the current key and makes a service request. |
| Auto-Copy Translation | On | Replaces the clipboard with the translated result. |
| Show Original Text | On | Shows source text beside the translation. |
| Auto-Dismiss | Manual | Manual, Click outside, After delay. Stored delay defaults to 10 seconds. No delay control appears here. |

T owns these controls. `App/Sources/OCR/OCRCoordinator.swift` consumes the OCR options for standalone recognition. Round text extraction is separate. `TranslationCoordinator.swift` passes the saved provider to `Packages/TranslationKit/Sources/TranslationKit/ProviderTranslationService.swift`. Hidden provider choices do not enforce an on-device-only runtime. No translation request is made during this review.

### Shortcuts

K defines 21 standalone configurable actions. Defaults below use Option+Shift unless stated otherwise. The Nextshot group currently follows that long standalone group.

| Configurable action | Default | Scope |
| --- | --- | --- |
| Start Round or Capture Area | F | Starts a round capture. |
| Copy Last Capture Prompt | C | Active round only. |
| Copy Prompt and End Round | R | Active round only. Blocked during an open capture. |
| Open Round Folder | O | Active round only. |
| End Round | E | Active round only. Also copies the prompt. Blocked during an open capture. |
| All-in-One | Unassigned | Standalone capture selector. |
| Capture Area | 1 | Standalone screenshot. |
| Capture Fullscreen | 2 | Standalone screenshot. |
| Capture Window | 3 | Standalone window screenshot. |
| Capture Text (OCR) | 4 | Standalone recognized text. |
| Record Area | 5 | Video or GIF recording. |
| Scrolling Capture | 6 | Standalone long screenshot. |
| Capture Area to Clipboard | 7 | Direct screenshot copy. |
| Capture Area & Annotate | 8 | Standalone annotation editor. |
| Screenshot History | 9 | Ordinary capture History. |
| Capture and Share to Cloud | 0 | Capture with cloud upload. Visible despite hidden Cloud Share tab. |
| Capture & Translate | T | Translate a captured area. |
| Translate Selected Text | Y | Translate another app's selected text. |
| Self-Timer | Unassigned | Delayed standalone capture. |
| Capture Area & Pin | Unassigned | Float a capture above other windows. |
| Pin from Clipboard | Unassigned | Float copied images, text, colors, or files. |
| Edit Clipboard Image | Unassigned | Open the clipboard image in the editor. |
| Hide / Show All Pins | Unassigned | Toggle pin visibility. |
| Translate Typed Text | Unassigned | Open typed-text translation. |
| Capture Previous Area | Unassigned | Replay a stored area or fullscreen capture. Window replay is excluded. |
| Record Full Screen | Unassigned | Record the whole display. |
| Center 1:1 from click | Shift+C | Selection only. Shift is fixed; C can change. |

Shortcut recorders accept a new combination. Escape cancels and Delete removes it. Round shortcut recorders reject collisions and show a reason. The four round-only keys are unregistered outside rounds. Sources: `App/Feedback/FeedbackShortcutSettingsSection.swift`, `FeedbackShortcuts.swift`. Fixed contextual references cover All-in-One, Window Capture, and Quick Access. All-in-One copy uses Command+C, Return, or Command+Shift+C. Save uses Command+S, pin uses Command+P, and cancel uses Escape. Window Capture uses Shift+click for multiple windows and release Shift to capture them. Quick Access uses Command+C to copy, Command+S to save, Command+E to annotate, and Command+P to pin. These references cannot change. A system banner offers Open Keyboard Settings or adopting Shift+Command+3/4/5, based on current system and app bindings.

### Cloud Share, hidden tab

`App/Sources/Preferences/Tabs/CloudShareSettingsView.swift` remains implemented. Unconfigured state offers Set up Cloud Share. Configured state shows Provider, Public URL Prefix, Bucket, optional Region / Endpoint, and optional Path Prefix. Automatically Upload New Captures and Copy Link When Upload Starts both default off. Enabling upload requires its confirmation alert. Change Provider / Configure opens the wizard. Test Connection / Test validates the destination. Reset Configuration / Reset clears stored configuration and provider credentials immediately, without another confirmation.

`CloudShareWizard/CloudShareWizardView.swift` has introduction, provider, credential preparation, credential entry, public URL/test, and completion steps. Provider options are Cloudflare R2, Amazon S3, Tencent COS, and Aliyun OSS. Fields vary: Account ID for R2; Region for S3/COS; Endpoint / Region for OSS; optional S3 Endpoint; common Bucket name, access key, secret key, Path prefix, and Public URL prefix. Open Provider Dashboard opens the provider website. Back, Close, successful-test-dependent save/continue, and Take a test capture complete the flow. Secrets use Keychain.

Connection tests upload a test object, check access, and remove it. They are not read-only. Hiding the tab does not prevent `AppDelegate.makeShareCoordinator` from restoring a saved configuration. Ordinary capture and recording paths can still auto-upload. No cloud configuration, test, reset, or upload is performed during this review.

### Already hidden preferences and boundaries

Screenshot magnifier and remember-last-capture controls are commented out as unimplemented. Recording cursor smoothing, dim-other-screens, and default recording format controls are also commented out. OCR Primary Language is hidden because its value is not passed to recognition. Translation panel position and delay remain stored without rows. `AppSettings.startAtLogin` is not the active LaunchAtLogin control. Do not publish these as available choices. Annotation tool properties, Beautify panel values, recording editor controls, camera menus, and capture toolbar choices belong in tool-specific guides. They are outside this Settings window catalog. Jev, zip handoff, and support flags have no Settings UI. Their defaults follow the existing registry and review decisions.
