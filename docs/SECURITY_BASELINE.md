# Security baseline

- Date: 2026-10-20
- Code: upstream `8f07fb6` (v1.2.5), the fork base
- Status: Drew approved the recommendations on 2026-10-20. Applied: 1 (Sparkle off), 2 as "hide now" (the picker lists only Apple; full removal of the provider code moves to its own branch after Phase 1), 3 (Cloud Share tab hidden), 4 (nettop check at verification), 5 (no change).
- Update 2026-10-24: the Jev base (#36) adds the fork's only network code, in `Packages/JevKit`. Drew confirmed the new local-only rule on 2026-10-24. The threat model is in `docs/superpowers/specs/2026-10-24-jev-base-design.md`.

## Summary

Capso has one outbound network call that needs no user setup: Sparkle's daily update check. Translation and cloud sharing make network calls only after the user picks a cloud provider or sets up a share destination. There is no analytics SDK, telemetry, crash reporter, socket server, or web view.

The fork's feedback code has one network path, the Jev package (JevKit). It calls only `https://api.typesafe.ai`, only when `jevBase` and a Jev feature flag are on, and only in a dev build. Every Jev flag starts off, and a release build ignores every Jev override. All other feedback code makes no network call.

## Outbound network code

| Component | File | What it calls | When it runs |
|---|---|---|---|
| Sparkle 2.9.1 | `App/Resources/Info.plist`, `App/Sources/Preferences/Components/CheckForUpdatesView.swift` | `https://lzhgus.github.io/Capso/appcast.xml` | At launch (`startingUpdater: true`), then every 86400 seconds (24 hours). No user setup. |
| Cloud translation | `Packages/TranslationKit/Sources/TranslationKit/ProviderTranslationService.swift` | OpenAI-compatible, DeepSeek, OpenRouter, custom endpoint, DeepL, or Google Cloud | Only when the user picks a cloud provider and enters a key. |
| Apple translation | same file, provider `.apple` (the default) | On-device Apple Translation | The OS can download language packs. |
| Cloud Share | `Packages/ShareKit/Sources/ShareKit/` (S3, R2, Aliyun OSS, Tencent COS) | SigV4-signed uploads to the configured bucket | Only when Cloud Share is set up. `R2Destination` and `ShareDestinationFactory` also make a check request in `validateConfig()`. |
| Jev (fork, #36) | `Packages/JevKit/Sources/JevKit/Client/URLSessionTransport.swift`, the only fork file that opens a connection | `POST https://api.typesafe.ai/v1/systemone`, model `jev-1.14.0` | Only in a dev build, with `jevBase` and a Jev feature flag on, after a capture's notes are final. All flags start off. |

### Jev requests

| Item | Value |
|---|---|
| Data sent by default | Reviewer text (instructions and notes) and item geometry |
| Screen text (OCR, window titles, app names) | Only with `jevSendScreenText` on |
| Images (capture PNGs or crops) | Only with `jevSendImages` on. Redact marks stay applied. |
| Consent check | Every request value carries its kind. The runner refuses a request with a kind that has no consent. |
| Key | Keychain item `TYPESAFE_API_KEY_NEXTSHOT`, read in memory only, sent only in the `Authorization` header |
| TLS | App Transport Security defaults (no exception in `Info.plist`). No certificate pinning: Nextshot has no automatic update, so a pin change would stop every installed copy. |
| Session | Ephemeral: no URL cache, cookies, or credential store. Redirects refused. Responses over 1 MiB refused. |
| Retention at TypeSafe | TypeSafe keeps each request, with no fixed retention period in its Data Processing Agreement. No training on inputs. Drew's account has no zero data retention. |
| Logs | Job ids, capture numbers, statuses, times, and token counts only. Never the key, bodies, notes, screen text, or file names. |
| Guard | `NetworkSourceScanTests` (JevKit) fails on network code anywhere else in fork code. |

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

The feedback work adds no dependency. JevKit uses only Apple frameworks (Foundation, CoreGraphics, ImageIO, Security) and no TypeSafe SDK.

## Feedback bundle data

- Bundles hold screenshots of work documents.
- They stay on disk in `~/Library/Application Support/Nextshot` (before 2026-10-21: `CapsoFeedback`). Only an agent that Drew starts reads them.
- FeedbackKit and `App/Feedback/` make no network call. JevKit makes the only one, under the rules in "Jev requests".
- With a Jev feature in shadow or on, a bundle also holds `jev.json` (answers and timings). With a feature on, it also holds the refined files, which can quote screen text.

## Recommendations (none applied until Drew approves)

| # | Recommendation | Change | Upstream edit |
|---|---|---|---|
| 1 | Turn off Sparkle | Set `SUEnableAutomaticChecks` to false and remove `SUFeedURL` | 2 lines in `Info.plist` |
| 2 | Hide or remove cloud translation providers. Keep `.apple`. | DeepSeek conflicts with Drew's rule against models from China-based companies. | Settings UI, or provider code (removal deletes upstream code) |
| 3 | Leave Cloud Share unconfigured and hide its setup | Do not delete `ShareKit` | Settings UI |
| 4 | Add a run-time network check | Run `nettop -p <pid>` during a feedback round | None (a manual check) |
| 5 | Keep the existing `capso://` scheme | No change | None |

### Notes on recommendation 1

- Sparkle would also offer upstream builds. An upstream build replaces the fork.
- The app starts Sparkle at launch with `startingUpdater: true`. Sparkle 2 can report an error when `SUFeedURL` is missing. After approval and before the commit, I launch a build and check for a Sparkle startup error. If one shows, the fallback keeps `SUFeedURL` and sets only `SUEnableAutomaticChecks` to false.
- Upstream branch `feat/optional-update-check` (commit `bf8f796`) adds an "Automatically Check for Updates" toggle. It edits only two Swift files, so it does not conflict with an `Info.plist` change.
