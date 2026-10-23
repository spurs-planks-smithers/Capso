# Security baseline

- Date: 2026-10-20
- Code: upstream `8f07fb6` (v1.2.5), the fork base
- Status: Drew approved the recommendations on 2026-10-20. Applied: 1 (Sparkle off), 2 as "hide now" (the picker lists only Apple; full removal of the provider code moves to its own branch after Phase 1), 3 (Cloud Share tab hidden), 4 (nettop check at verification), 5 (no change).

## Summary

Capso has one outbound network call that needs no user setup: Sparkle's daily update check. Translation and cloud sharing make network calls only after the user picks a cloud provider or sets up a share destination. There is no analytics SDK, telemetry, crash reporter, socket server, or web view. The feedback session work adds no network code.

## Outbound network code

| Component | File | What it calls | When it runs |
|---|---|---|---|
| Sparkle 2.9.1 | `App/Resources/Info.plist`, `App/Sources/Preferences/Components/CheckForUpdatesView.swift` | `https://lzhgus.github.io/Capso/appcast.xml` | At launch (`startingUpdater: true`), then every 86400 seconds (24 hours). No user setup. |
| Cloud translation | `Packages/TranslationKit/Sources/TranslationKit/ProviderTranslationService.swift` | OpenAI-compatible, DeepSeek, OpenRouter, custom endpoint, DeepL, or Google Cloud | Only when the user picks a cloud provider and enters a key. |
| Apple translation | same file, provider `.apple` (the default) | On-device Apple Translation | The OS can download language packs. |
| Cloud Share | `Packages/ShareKit/Sources/ShareKit/` (S3, R2, Aliyun OSS, Tencent COS) | SigV4-signed uploads to the configured bucket | Only when Cloud Share is set up. `R2Destination` and `ShareDestinationFactory` also make a check request in `validateConfig()`. |

### Other checks

| Check | Result |
|---|---|
| Analytics, telemetry, or crash SDK | None. A search for common SDK names finds no match. |
| Socket server or listener (`NWListener`, `CFSocket`, `socket(`) | None |
| Web view (`WKWebView`) | None |
| Child processes | `App/Sources/OCR/OCRProcessFallback.swift` starts the app's own binary (`Bundle.main.executableURL`) for OCR recovery. |
| URL scheme | `capso://` ("Capso Automation"), handled in-process by `AutomationURLAction`. |

## Entitlements and permissions

| Item | Value | Note |
|---|---|---|
| `com.apple.security.device.audio-input` | true | Recording with microphone |
| `com.apple.security.device.camera` | true | Webcam overlay |
| `com.apple.security.network.client` | true | No effect: the app is not sandboxed |
| App Sandbox | off | No `com.apple.security.app-sandbox` key |
| Hardened runtime | on | `ENABLE_HARDENED_RUNTIME: YES` in `project.yml` |
| Screen Recording | TCC grant | TCC is the macOS privacy-permission database. The user grants it in System Settings. |

## Dependencies

| Package | Version | Pinned by |
|---|---|---|
| KeyboardShortcuts | 2.2.1 | `project.yml` exactVersion |
| Defaults | 9.0.6 | `project.yml` exactVersion |
| LaunchAtLogin-Modern | 1.1.0 | `project.yml` exactVersion |
| Sparkle | 2.9.1 | `project.yml` exactVersion |
| GRDB.swift | 7.4.1 | `Packages/HistoryKit/Package.swift` exact |

The feedback work adds no dependency.

## Feedback bundle data

- Bundles hold screenshots of work documents.
- They stay on disk in `~/Library/Application Support/Nextshot` (before 2026-10-21: `CapsoFeedback`). Only an agent that Drew starts reads them.
- FeedbackKit and `App/Feedback/` make no network call.

## Recommendations (none applied until Drew approves)

| # | Recommendation | Change | Upstream edit |
|---|---|---|---|
| 1 | Turn off Sparkle | Set `SUEnableAutomaticChecks` to false and remove `SUFeedURL` | 2 lines in `Info.plist` |
| 2 | Hide or remove cloud translation providers. Keep `.apple`. | DeepSeek conflicts with Drew's rule against models from China-based companies. | Settings UI, or provider code (removal deletes upstream code) |
| 3 | Leave Cloud Share unconfigured and hide its setup | Do not delete `ShareKit` | Settings UI |
| 4 | Add a run-time network check | Run `nettop -p <pid>` during a feedback session | None (a manual check) |
| 5 | Keep the existing `capso://` scheme | No change | None |

### Notes on recommendation 1

- Sparkle would also offer upstream builds. An upstream build replaces the fork.
- The app starts Sparkle at launch with `startingUpdater: true`. Sparkle 2 can report an error when `SUFeedURL` is missing. After approval and before the commit, I launch a build and check for a Sparkle startup error. If one shows, the fallback keeps `SUFeedURL` and sets only `SUEnableAutomaticChecks` to false.
- Upstream branch `feat/optional-update-check` (commit `bf8f796`) adds an "Automatically Check for Updates" toggle. It edits only two Swift files, so it does not conflict with an `Info.plist` change.
