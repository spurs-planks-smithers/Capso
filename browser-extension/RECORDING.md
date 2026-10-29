# Sampled recording trial

The local `recordingEnabled` setting starts false. Enable it in the popup, then press Start silent recording. The permission request asks for the current site and the offscreen capability. Basic capture starts no recorder.

The trial samples the visible armed tab at most once per second. Each retained frame passes the capture-time page proof and receives solid pixel masks over form fields and embedded frames. A changed page skips its frame. This does not provide continuous video coverage. Recording leaves the page DOM and animations unchanged. Pixel covers apply only in the offscreen image. A running animation on a private field or its ancestor causes a skipped frame. The extension badge shows REC while recording and II while paused. Stop clears the badge.

Click selectors, generic observed page-error markers, and sanitized completed resource URLs form the timeline. Typed values, audio, request headers/bodies, and console hooks are absent. Resource methods/status, failed requests, embedded-frame activity, and complete page-error coverage are unavailable.

Explicit recording retains evidence from Start until Stop. It preserves earliest frames and stops automatically at 24,000,000 frame bytes or 1,000 events per type. A coverage marker explains the stop. Stop freezes review. Pause and navigation produce gap markers. Tab switches pause sampling. Resume requires the original origin. A new origin requires a new recording. Review offers start/end/issue times, then creates one selected draft for the existing mark, note, save, export, and native-delivery flow.

Only selected frames are encoded to silent VP8/WebM. A still image remains when the encoder is unavailable. Each encoded frame is a keyframe. Review events retain original recording timestamps. The media starts at the first selected frame.

## APIs for Rolling Round

`recording.ts` exports `startRecording`, `pauseRecording`, `resumeRecording`, `stopRecording`, `recordingStatus`, `selectRecording`, and `discardRecording`. `recorderCall` is an internal offscreen transport. All times are milliseconds from start. `selectRecording` accepts start, end, and issue times. It consumes the buffer after draft creation.

`core/history.ts` exports `EvidenceHistory`. Its independent JPEG frames allow whole-frame eviction. Defaults retain 60 seconds, at most 24,000,000 frame bytes, and 1,000 entries per event type. Explicit mode uses `preserveStart=true` with no time eviction. It refuses new evidence at its ceiling. C5 uses the default eviction behavior. `select` filters every frame/event to the chosen interval. `clear` releases references. C5 must preserve these bounds and replace any review tab ownership deliberately.

Frames and events stay in the offscreen document's memory until selection. No raw history enters session/local storage or IndexedDB. The stopped review buffer remains there until selection, discard, review closure, permission removal, tab closure, or browser restart. Worker restart reattaches through owner metadata in `chrome.storage.session`. No media enters that metadata. Active sampling returns paused with an explicit restart gap. Stopped review survives without an inactivity expiry. A worker with no owner metadata clears orphaned offscreen state. No media track, native helper, listener server, or audio capture starts.

## Verification limits

The scratch headless runtime uses a copied manifest with broad host access to emulate the toolbar's activeTab grant. This is a fixture-only permission. It verifies actual screenshot sampling, a retained click, masked private-field pixels, selected WebM container decoding, and offscreen closure after selection. The shipping manifest retains optional site access.

The follow-up scratch check terminates and restarts the actual service worker. It verifies identical stopped frames, unchanged DOM and animation play state, animated-private-region rejection, REC badge, earliest evidence beyond 60 seconds, and automatic limit-stop cleanup. Scratch checks also cover memory limits, selected-only ranges, explicit pause, navigation gap markers, cross-site resume rejection, URL filtering, and discard cleanup. The real toolbar permission gesture, changing-page skips, and user review remain final smoke acceptance work. This trial stays outside the public release.
