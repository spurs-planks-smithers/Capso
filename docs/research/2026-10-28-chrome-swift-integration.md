# Chrome and Swift integration: research record

Date: 2026-10-28. Status: documentation research only. Parent: [#124](https://github.com/spurs-planks-smithers/Capso/issues/124). Rolling Round: [#157](https://github.com/spurs-planks-smithers/Capso/issues/157). Apple Intelligence: optional [#148](https://github.com/spurs-planks-smithers/Capso/issues/148). All remain in Later. No implementation is authorized.

## Conclusion

Recommend a small TypeScript extension compiled to JavaScript, plus an optional signed Swift bridge. The browser owns capture, review, local save, and portable export. Native integration adds Nextshot library access and eligible native assistance. Core use must never depend on an installed, running, or connected Mac app.

This is an architecture recommendation. No source establishes that this design is the absolute smallest implementation. No extension, encoder, native host, or model runs during this research.

The October 28 direction supersedes the October 27 Mac-required scope. In particular, Mac disconnection cannot pause browser capture, block local save, or expire an otherwise valid browser draft.

## Platform facts

| Area | Primary evidence | Implication for Nextshot |
|---|---|---|
| Browser language | Chrome documents [HTML, CSS, and JavaScript](https://developer.chrome.com/docs/extensions/get-started) as extension technologies. | Use a small web runtime for Chrome. Swift stays in the optional native component. |
| Swift in the browser | Swift provides an official [WebAssembly SDK](https://www.swift.org/documentation/articles/wasm-getting-started.html). Embedded Swift is an experimental subset. | Possible code reuse does not establish lower total size or overhead. Defer Swift-to-WebAssembly until a measured need justifies its toolchain and JavaScript interface. |
| Idle background work | Chrome normally ends a worker after 30 seconds without activity. Its [lifecycle guide](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle) recommends avoiding indefinite keepalive. | Persist control state. Let the worker sleep. Avoid timers, heartbeats, polling, and idle native connections. |
| Page access | [Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts) support programmatic injection and normally use an isolated JavaScript environment. | Inject only for capture or an explicitly armed tab. Retained site permission does not require constant observers. |
| Permission timing | [activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) grants temporary access after extension invocation. [Optional permissions](https://developer.chrome.com/docs/extensions/reference/api/permissions) need a user gesture. | Keep the approved once-per-site grant. Request only the needed origin. A Mac hotkey does not itself grant Chrome access. |
| Recording | Chrome's [capture guide](https://developer.chrome.com/docs/extensions/how-to/web-platform/screen-capture) supports a worker-obtained tab stream consumed by an offscreen document from Chrome 116. | Prefer tab capture after explicit arming. It can avoid the general display chooser. Verify browser indicators, navigation, and automatic pause/resume in a later trial. |
| Offscreen lifetime | An [offscreen document](https://developer.chrome.com/docs/extensions/reference/api/offscreen) provides hidden DOM access. Most reasons have no automatic lifetime limit. | Create it for recording, review, or export work. Close it explicitly when no live task or unsaved buffer requires it. |
| Browser storage | [IndexedDB](https://developer.chrome.com/docs/extensions/develop/concepts/storage-and-cookies) is available to workers and extension pages. Extension data survives clearing browsing history. | Keep saved artifacts in extension-owned storage. Keep unsaved rolling media in bounded memory first. Do not rely on browser-history clearing for cleanup. |
| Session metadata | [storage.session](https://developer.chrome.com/docs/extensions/reference/api/storage) is memory-backed and clears on browser restart, extension update, reload, or disable. | Store small control metadata there. Keep binary media out of JSON settings. Do not sync screenshots, diagnostics, or browsing history. |
| Portable export | The [downloads API](https://developer.chrome.com/docs/extensions/reference/api/downloads) supports local downloads with its permission. | A portable bundle needs no Mac or server. Compare an ordinary user-initiated download with this API before adding another permission. |
| Native transport | Chrome [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) starts an installed host. A persistent port keeps that host alive. | Use a short-lived Swift host and operation-scoped connections. No localhost HTTP server or always-running background agent is needed by this proposal. |
| Host setup | The [native host manifest](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) names an absolute executable and exact extension origins. It has a per-user macOS location. | Nextshot setup registers its bundled helper. A Chrome-only installation cannot provision that executable itself. Repair registration after moving or updating the app. |
| Native trust | Chromium's [security FAQ](https://chromium.googlesource.com/chromium/src/+/main/extensions/docs/security_faq.md) says native messaging is not an authenticated secure channel by itself. | The origin allowlist is only one boundary. Validate callers, channel, operations, lengths, schemas, paths, and content. Do not accept arbitrary commands or file destinations. |
| Native delivery | Apple provides [NSWorkspace app opening](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)) and [native XPC services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html). | Evaluate a private inbox plus an opaque import identifier first. Compare XPC only if it reduces total complexity. App discovery and delivery remain unverified. |
| Swift packaging | Apple's [signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) covers nested executable code. | Bundle and sign the helper with Nextshot. Preserve separate Dev and release identities. Avoid a second helper installer or runtime. |
| Safari distinction | Apple's [Safari messaging model](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension) uses a containing app and native app extension. | Safari's Swift integration is a different distribution model. It does not provide Chrome with direct SwiftUI access. Safari is outside this request. |
| Network evidence | [webRequest](https://developer.chrome.com/docs/extensions/reference/api/webRequest) can observe requests. Subresource visibility needs destination and initiator access. | Capture permitted summaries while armed. Exclude headers and bodies. Record unavailable cross-origin coverage without repeated permission demands. |
| Deep diagnostics | [debugger](https://developer.chrome.com/docs/extensions/reference/api/debugger) offers richer protocol domains and can detach when DevTools opens. Chrome lists it among [permissions that cannot be optional](https://developer.chrome.com/docs/extensions/reference/api/permissions). | Prefer observable errors and permitted request summaries for the lightest mode. Broader coverage has a material permission and browser-notice trade-off. Ask Drew. |

## Architecture comparison

| Approach | Strength | Cost or limit | Recommendation |
|---|---|---|---|
| Small web extension plus optional Swift bridge | Browser independence and native integration with one capture contract | Some browser-side annotation, storage, and bundle logic must exist | Preferred direction |
| Thin extension with all work in Swift | More direct reuse of native code and UI | Requires the app and adds an interprocess hop to basic use | Reject for the October 28 scope |
| Swift compiled to WebAssembly | Potential reuse of portable logic | Added toolchain, runtime/interface work, and unmeasured package cost | Defer pending measured value |
| Extension plus persistent local server | Flexible bidirectional transport | Extra process lifetime, installation, port, and local-service behavior | Reject for the current low-overhead direction |
| Hosted capture application or remote backend | Cross-device storage and centralized services | Network dependency, accounts, data handling, and operating cost | Outside core scope; a standalone Jev service needs a separate product decision |

## Resource and integration limits

A retained native port also affects the worker lifetime. Use one short connection for an operation rather than a fresh process for every media chunk. Close it after acknowledgement. Use a cheap availability handshake only during a requested native action. Do not poll for app presence.

Native messages use framed UTF-8 JSON. Chrome limits host-to-extension messages to 1 megabyte and extension-to-host messages to 64 mebibytes. Keep control replies small. Use bounded acknowledged transfer for selected evidence, never the unsaved 60-second buffer. See [native protocol](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

Keep page access separate from recording state. Persistent site permission must never auto-arm a tab. Additional preview origins still require access. Restricted pages, protected frames, canvas content, and missing source maps need honest fallback coverage.

Pausing a recorder does not establish that its media stream stops all resource use. Stopping the stream may affect automatic resumption and gesture requirements. The later trial must measure this trade-off without breaking the approved pause/resume flow.

Use browser-native media APIs before a large codec runtime. Container chunks are not automatically independent playable clips. Prove exact excerpt export and decoding. A WebM recording is not automatically compatible with the Mac app's existing MP4/GIF path.

Avoid continuous GIF encoding, duplicated full-resolution frames, whole-page mutation tracking, and full DOM snapshots per video frame. Keep a bounded action index. Capture element context at the evidence time, rather than matching old images to the current page after a rerender.

Browser-local storage and automatic native import need explicit ownership rules. Proposed rule: save durably in the browser first. Native receipt confirms a separate import. Failed or duplicate transfers cannot lose or duplicate the browser result.

Jev's existing Swift client obtains a key through the Mac Keychain. A browser-only extension cannot reuse that native path without the bridge. Never embed the project's service key in a distributed extension. A new authenticated service is an explicit scope and network-policy decision. Local suggestions provide the existing fallback.

## Research outcome and next evidence

The recommendation targets low idle work, bounded active work, and few reviewer inputs. These are design objectives. No memory, energy, package-size, frame-rate, or latency measurements exist yet.

| Future check | Evidence required before a support claim |
|---|---|
| Idle | Worker sleeps after activity. No open native port, recorder, page observer, polling loop, or unneeded offscreen document remains. |
| Armed | One-tab capture obeys 60-second and resource bounds. Diagnostic and masking work is measured against an unextended browser baseline. |
| Paused/review | New evidence stops. Gaps remain explicit. Automatic resumption and required browser indicators are verified. |
| Export | Exact selected interval, readable key frames, accepted steps, diagnostics, and automatic format/size fallback are verified. |
| Native | Install order, app relocation, closed app, Dev/release pairing, duplicate delivery, and version mismatch preserve standalone use. |
| Failure | Browser-only save survives an unavailable helper, denied permission, unavailable Jev, and incomplete diagnostics. Memory pressure produces an honest capture gap. |

Next deliverable: the linked [architecture and specification plan](../superpowers/specs/2026-10-28-chrome-extension-architecture.md). This research does not authorize any of the future checks to run.
