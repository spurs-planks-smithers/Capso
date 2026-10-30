# Native trigger and review transport: feasibility record for #178

Date: 2026-10-30. Issue: [#178](https://github.com/spurs-planks-smithers/Capso/issues/178) (Chrome N1). Parent: [#124](https://github.com/spurs-planks-smithers/Capso/issues/124). Design inputs: [native-first decision](../decisions/2026-10-29-browser-native-first.md) and the [rendered checkpoint](../design/2026-10-30-native-browser-flow-checkpoint.md). All Chrome work stays in Later and outside v0.5.0. Spike code and raw output: [2026-10-30-n1-spikes](2026-10-30-n1-spikes/README.md).

This record holds small spikes only. No production editor, no change to the shipped helper, app, or extension.

## Evidence tiers

| Tier | Meaning in this record |
| --- | --- |
| **installed** | The installed Nextshot Dev 0.5.0-dev (build 909) and its signed helper, the installed Chrome 156 binary with a throwaway profile, or (section 3, installed Chrome run) Drew's regular Chrome with one throwaway extension that he loaded and then removed. Pilot and Dev extension installs were not touched. |
| **fixture** | A stand-in: a Python process that plays Chrome, spike binaries signed with the Dev team, or Chrome for Testing 153 with a throwaway extension. |
| **not observed** | Taken from documentation or reasoning only. |

The test Mac runs macOS 27.0.1. No macOS 15 machine was available, so every macOS 15 statement is **not observed**.

## Verdicts

| Item | Verdict | Tier |
| --- | --- | --- |
| 1a. Native shortcut starts ordinary capture with Chrome in front | **GO**. Needs Screen Recording only. No Chrome gesture, no site grant. | installed (code read, existing behavior), not re-run here |
| 1b. Native shortcut also brings page element details, with no held helper | **NO-GO as specified.** Nothing native can wake an idle extension. Drew chose option A on 2026-10-30 (see below). | fixture + docs |
| 2. Closed-app discovery through the Swift bridge | **GO** with one protocol addition. The current receipt cannot tell the states apart. | installed |
| 3. Temporary active-review transport with idle teardown | **GO** at fixture tier on Chrome for Testing 153. Installed Chrome 156 confirmed the real toolbar gesture, the Apple Event with a Chrome parent, and the message sizes. The 45 s idle hold and the oversize frame were **not cleanly observed** there. | fixture + installed (partial) |
| 4. macOS 15 media playback | **Partly proven.** MP4 with H.264 plays through the system stack. WebM does not. macOS 15 itself not observed. | installed on macOS 27, macOS 15 not observed |

#178 stays open until the macOS 15 media run exists.

## Decision on item 1b, 2026-10-30

Drew chose **option A**. The native shortcut makes an ordinary capture with no automatic page details. Page details come when the user starts from the Chrome key. Options B and C are not built. This supersedes the checkpoint's choice of "native shortcut with a drag" as the trigger for page-detail captures. The checkpoint's trigger remains the trigger for ordinary native capture (item 1a).

## 1. Native trigger and permissions

### 1a. Native capture alone

- The shortcut uses the `KeyboardShortcuts` library, which registers a Carbon system hot key. That path needs no Accessibility and no Input Monitoring permission. Source: `App/Feedback/FeedbackShortcuts.swift` (code read).
- Chrome as the frontmost app comes from `NSWorkspace.shared.frontmostApplication` in `CaptureCoordinator.currentSourceApplication()`. It needs no permission (code read).
- Pixels and window titles need Screen Recording, which Nextshot Dev already holds for every capture.
- Chrome sees nothing. No gesture, no extension, no site grant is involved.

### 1b. Chrome element details at the same moment

What the extension needs and what native can give it:

| Need | Result | Tier |
| --- | --- | --- |
| Permission to read the page | A persistent per-site host grant works with no gesture. With `127.0.0.1` granted, `executeScript` run from a plain message succeeded. On `localhost` (not granted) it failed with "Extension manifest must request permission to access this host." | fixture (Chrome for Testing 153) |
| `activeTab` from a non-gesture | `captureVisibleTab` from a plain message failed: "Either the '<all_urls>' or 'activeTab' permission is required." | fixture |
| `activeTab` from the native shortcut | Chrome lists four gestures: the extension action, a context menu item, a `commands` shortcut, and an omnibox suggestion ([activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab)). A system hot key is none of them. | docs |
| Wake an idle worker from the app | Not possible. Chrome starts the host and owns its pipes. A host cannot call into an extension that did not open it. A worker stops after 30 idle seconds ([lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)). | docs, fixture |
| Let the page or extension see the key press | The Carbon hot key consumes the key press before Chrome receives it (Apple behavior for registered hot keys). A page keydown handler cannot act as a trigger. | **not observed** |

Conclusion: the grant is solvable (the once-per-site optional grant already in the Pilot design). The wake is not. At the moment of the native key press the extension must already be awake and holding a native connection, or the details cannot arrive in time.

Options for Drew. None was built beyond the measurements shown.

| Option | What it does | Cost and limit | Fit with #178 rules |
| --- | --- | --- | --- |
| **A. Ordinary native capture, no automatic details** (recommended default) | Native shortcut and drag work as today. Page details come only when the user starts from the Chrome key (the checkpoint's 6-input fallback) | None added | Meets all rules. Drops "automatic details on the native shortcut" |
| **B. Focus-scoped port** | The extension opens `connectNative` when Chrome is frontmost on an approved site, and closes it on blur, tab change, or navigation away. At the key press the app asks the held helper, which asks the extension | One helper (about 11 MB, near zero CPU, measured in spike 3) and a worker kept awake for as long as the user stays on the page | Breaks "no permanent helper, no idle connection" in the strict sense. Needs Drew's yes |
| C. Accessibility read from the app | Native reads the page's accessibility tree for the selected region | New Accessibility permission. Chrome builds the tree only when enabled. Field values are reachable and must be filtered. No site grant concept | Not spiked. A larger privacy choice |
| D. Apple Events JavaScript into Chrome | App runs script in the page | Needs Chrome's "Allow JavaScript from Apple Events" setting, which lets any local process script every tab | Rejected. Not spiked |
| E. One short helper per focus event | Extension sends a native message on each focus or tab event | About 60 ms of helper time per event (measured 55 to 80 ms). Cannot know the drag region, so it would push whole-page indexes ahead of time | Stale and heavy. Not recommended |

The checkpoint recorded Drew's choice of "native shortcut with a drag". Item 1a delivers that trigger. Item 1b is the part that does not meet the stated limits, so this is the report that #178 promised before a fallback is chosen.

## 2. Closed-app discovery through the existing bridge

### What the current bridge returns (installed helper, driven as Chrome drives it)

Raw lines: [helper-states.jsonl](2026-10-30-n1-spikes/results/helper-states.jsonl).

| Situation | Receipt | Helper time |
| --- | --- | --- |
| App running, bridge flag on | `ready` | 57 to 80 ms |
| App closed (signed copy of the app, never launched) | `failed / unavailable` | 484 ms cold, 14 ms warm |
| App running, bridge flag off | `failed / unavailable` | 56 ms |
| Wrong extension origin | `failed / unavailable` | 8 ms |
| Protocol version 2 | `failed / unavailable` | 8 ms |

Closed, disabled, wrong origin, and incompatible produce the same bytes. This confirms the issue text: an unavailable reply does not show that the app is absent, and it cannot separate the other states. Chrome adds two more outcomes before the helper runs (fixture, [chromium-lifecycle.jsonl](2026-10-30-n1-spikes/results/chromium-lifecycle.jsonl)):

| Chrome outcome | Error text the extension sees |
| --- | --- |
| No host manifest | "Specified native messaging host not found." |
| Manifest points at a missing helper (app deleted) | "Specified native messaging host not found." (same text, so removed and never installed look the same) |
| Extension not in `allowed_origins` | "Access to the specified native messaging host is forbidden." |

### A helper can tell the states apart without opening the app

`discover.swift` is a 50-line prototype of what the helper can read with no launch and no macOS permission. Raw output: [discover.txt](2026-10-30-n1-spikes/results/discover.txt).

| State | How it is known | Result (installed Dev app) |
| --- | --- | --- |
| absent | Bundle or identity not found | `absent` for a missing path |
| incompatible | Signature check, plus a declared protocol number in Info.plist (key does not exist yet, so a missing key means 1) | `incompatible` when protocol 2 was required |
| disabled | `CFPreferencesCopyAppValue("flag.browserBridge")` in the app's preference domain | `disabled` with the flag off, running or closed |
| closed | Process list has no match for the app path | `closed`, 20 ms |
| running | Process list match | `running`, 113 ms cold |
| permission-denied | Only a running app knows its own Screen Recording state | **not observed**. The running app must report it in the handshake reply, or write a status line when it quits |

Chrome's site grants are the extension's to check (`chrome.permissions.contains`) and are not a native fact.

Proposed contract change (no code changed here): add a `discover` operation that never launches the app and returns one of the six states, and add the same state to the handshake reply. Keep `import` as the only operation that launches the app.

Observed side note: the installed Dev app is running right now with the argument `--nextshot-browser-bridge`, which means an earlier helper launched it quietly. This spike did not start, quit, or relaunch it. The bridge flag was set to off for a few seconds twice to observe the disabled state, then restored to on and confirmed.

## 3. Temporary active-review transport

### Design that was spiked

Browser starts it, so it respects Chrome's rules and the #178 limits:

1. A review begins with an extension gesture. The extension calls `connectNative`, which starts the helper.
2. The helper sends the app one Apple Event, `open`, and the app answers.
3. The helper sends a `wait` event. The app **holds the reply** (`suspendCurrentAppleEvent`, the call the shipped coordinator already uses). The app answers only when it has a command. There is no timer and no polling.
4. The helper relays the command to Chrome. Chrome's answer goes out on the next `wait` event, so one held event carries each direction in turn.
5. Either side ends the review. Closing the port ends the helper.

No local server, no permanent helper, no synthetic key press.

Authentication reuses `BrowserBridgeIdentity.validates` (a verbatim copy in the spike) in both directions: the app checks the helper's audit token, the helper checks the app's.

### Results, fixture tier (Python stands in for Chrome, spike binaries signed with the Dev team)

Raw lines: [transport.jsonl](2026-10-30-n1-spikes/results/transport.jsonl).

| Case | Observed |
| --- | --- |
| Open a review | 36 to 150 ms |
| App command reaches Chrome stand-in | 2 to 4 ms |
| Chrome result reaches app | 3 to 7 ms |
| Idle for 30 s with the wait held | Helper +0.01 s CPU, app +0.00 s CPU, helper 11 MB resident, app 36 MB, no change in memory |
| Chrome closes the port (stdin closed) | Helper exits in 23 ms. App ends the session in 8 ms |
| Chrome sends close | Helper exits in 9 ms |
| App cancels | Chrome gets `closed: app-cancel` in 1 ms. Helper exits in 6 ms |
| App killed (SIGKILL) | Helper sees Apple Event error -609 and tells Chrome `app-gone` in about 500 ms, then exits |
| Helper killed (SIGKILL) | App ends the session in 1 ms through a process-exit source (no polling) |
| Browser process killed | Helper is gone, app ends the session in 5 ms |
| Unsigned (ad hoc) impostor helper | App rejects it on identity and logs the sender. No session starts |
| App not running | Helper tells Chrome `no-app` (error -600) in 10 ms and exits |

Helper lifetime equals the review. A held review of 31 s lasted 31 s and ended within 25 ms of the close.

### Results, real Chromium engine (Chrome for Testing 153, throwaway extension, same host)

The extension drove itself with alarms, and the same helper ran as a native host. No debugger or script touched the worker. Raw lines: [chromium-nodebugger.jsonl](2026-10-30-n1-spikes/results/chromium-nodebugger.jsonl).

| Case | Observed |
| --- | --- |
| No port open, idle | The worker stopped and a new instance started at the 46 s alarm (instance `okvlur` then `9hak0q`). Matches the 30 s idle rule |
| Held native port, 90 s with no events | Same worker instance at the end (`9hak0q`). The port alone kept it alive for more than 3 times the idle limit |
| App command after the 90 s hold | Reached the extension in the same instance |
| Helper processes while held | 1 |
| Extension closes the port | Helper gone within 71 ms. App ended the session (`host-close`) |
| Extension reloads with the port open | Helper gone within 1.6 s. App ended the session (`host-close`) |

An earlier run attached Playwright to Chrome for Testing. There the worker never stopped in 46 idle seconds, because an attached debugger keeps a worker alive ([lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle) lists active debugger sessions for Chrome 118 and later). That run cannot show suspension. Its other lines stand: the three host error texts, the grant and gesture results, and the port, command, and teardown behavior. They sit in [chromium-lifecycle.jsonl](2026-10-30-n1-spikes/results/chromium-lifecycle.jsonl), which ends in a harness error (a page navigation blocked by the automation tool) after the reload case.

Consequence for the design: a held port keeps the worker alive, as documented, so the connection must exist only while a review is open. The suspension, port-close, and reload cases all end the helper and the app session.

### Results, installed Chrome 156 (Drew's regular Chrome, throwaway extension, 2026-10-30)

Drew loaded one throwaway extension (name "N1 throwaway (remove me)", ID `npgbeehfhbkbjcmbnjnljmhecnjppbci`, fixed throwaway key) and clicked its toolbar icon. Two host manifests named `com.nextshot.n1spike*` sat in Chrome's `NativeMessagingHosts` folder. The host was the spike stand-in, signed with the Dev team, talking to a stand-in app. It was not the shipped helper. Raw lines: [installed-chrome-run1-events.jsonl](2026-10-30-n1-spikes/results/installed-chrome-run1-events.jsonl).

| Case | Tier | Observed |
| --- | --- | --- |
| Real toolbar click grants `activeTab` | installed | `captureVisibleTab` returned 166,855 bytes right after the click. In the fixture, a plain message to the worker got no grant |
| Script on the page after the click | not observed | The tab was a `chrome://` page, which Chrome blocks. Not a result |
| Apple Event from a helper with a Chrome parent | installed | The stand-in app answered "ready" in 12 ms with no consent prompt. The helper sends with `kAEDoNotPromptForUserConsent`, so a missing grant would show as error -1744, not as a prompt. The Dev bundle was not a clean first-run install, so a clean install is **not observed** |
| Host to extension, 5 MB in 10 frames of 512 KB | installed | All 10 arrived, 131 ms |
| Extension to host, 2 MB single message | installed | Echoed back whole (2,097,152 bytes) |
| 45 s idle hold with an open port | **not observed** | Drew clicked the icon several times. Each click opened a second connection and ended the first ("Native host has exited"), so the hold did not run clean |
| Host to extension, 1.2 MB single frame | **not observed** | Same cause. The port had closed before the frame was sent |

A second pass with exactly one click was set up and waited 90 minutes. No click came, so it produced no events ([installed-chrome-run2.jsonl](2026-10-30-n1-spikes/results/installed-chrome-run2.jsonl)). The two **not observed** rows stay at fixture tier (section above) and documentation (1 MB host to extension limit, [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)).

The probe has no re-entrancy guard. A production extension must ignore a click while a review is open. The spike showed the cost of a repeat: the second connection replaced the first and the app denied the next opens as busy.

Cleanup: both host manifests were deleted and the stand-in processes stopped on 2026-10-30. Drew removes the throwaway extension at `chrome://extensions` with **Remove**.

### Limits and gaps

- The installed Chrome run covers the gesture, the Apple Event with a Chrome parent, and message sizes. The idle hold and the oversize frame stay at fixture tier.
- Apple Event consent on a clean install is **not observed**. The helper sends with `kAEDoNotPromptForUserConsent`, and the stand-in reached its target with no prompt from both a Python parent and a Chrome parent.
- Chrome limits host-to-extension messages to 1 MB. The installed run sent 512 KB frames successfully. The error text for an oversize frame is only from documentation here.
- The spike's wait timeout is 130 s and the app's session limit is configurable. A production limit and a reviewer-visible expiry are open for #179.

## 4. macOS 15 media playback

Host macOS: 27.0.1. macOS 15: **not observed**. Raw output: [media-fixtures-macos27.json](2026-10-30-n1-spikes/results/media-fixtures-macos27.json) and [mediarecorder-chrome156.json](2026-10-30-n1-spikes/results/mediarecorder-chrome156.json).

| File | Made by | AVFoundation on macOS 27.0.1 |
| --- | --- | --- |
| H.264 MP4 | ffmpeg | Playable, frame at 1 s read, player item ready |
| VP8 WebM | ffmpeg | "Cannot Open" |
| VP9 WebM | ffmpeg | "Cannot Open" |
| H.264 MP4 (`video/mp4;codecs=avc1`) | Chrome 156 MediaRecorder | Playable, frame read at 0.948 s, player item ready |
| `video/webm` (default), VP8, VP9, AV1, H.264 in WebM or Matroska | Chrome 156 MediaRecorder | All "Cannot Open" |
| Animated GIF | ffmpeg | "Cannot Open" as video (a GIF is an image sequence for ImageIO, not a video asset) |

Chrome 156 reports `MediaRecorder.isTypeSupported` true for `video/mp4` with H.264 and for several WebM types, and false for HEVC (`hvc1`). VP9 hardware decode is false on this Mac. The AVFoundation frame at "1.0 s" came back at 0.948 s from the Chrome MP4, so selection by time must use the file's own timestamps.

Secondary sources agree that AVPlayer has no WebM support ([Apple Developer Forums](https://developer.apple.com/forums/thread/832486)). They are forum posts, not Apple documentation.

Recommendation, no code changed:

1. When recording for native review, ask for `video/mp4;codecs=avc1` if `MediaRecorder.isTypeSupported` says yes. It plays through the system stack with no added dependency.
2. If it says no, keep review in the browser for that user, or send timestamped still frames (JPEG with capture time) and let the native window step through them. Do not rely on native acceptance of a WebM file.
3. Repeat the AVFoundation probe (`media/probe.swift`) on a macOS 15 Mac before #181 claims support there. One command, no install.
4. The lowest Chrome version that offers MP4 recording is **not verified** here. Check it before the support statement.

## What this changes for the plan

- #179 can assume the discovery states and the held-event transport as its connection model, with the Chromium numbers above confirmed first.
- #180 and #181 should not assume WebM playback.
- The native-shortcut-with-details question (item 1b) blocks a final trigger design but does not block #179, which needs only the browser-started connection.

## Not done

- A clean single-click installed Chrome run of the 45 s idle hold and the oversize frame. The probe is ready: `node docs/research/2026-10-30-n1-spikes/installed-chrome/run.mjs setup <bin> <work>`, one load, one click. It needs Drew for about 3 minutes.
- Source-tab closure and bounded reconnect are extension logic, not spiked. The cases that were measured (port close, reload, app death, helper death, browser death) all end both sides within about 2 s.
- A Chrome keyboard shortcut (commands API) as the starting gesture. The toolbar click was observed in installed Chrome.
- No macOS 15 run.
- No Accessibility spike (option C).
- No Astra use and no paid call.
- Windows is outside this item.
