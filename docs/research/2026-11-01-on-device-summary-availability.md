# On-device summary name: availability and default-on risks

Date: 2026-11-01. Read-only research for Nextshot 0.6.0. Every web source was read on 2026-11-01. Confidence is High, Medium, or Low.

## Verdict

Turn it on by default in 0.6.0, with four small conditions (see Recommendation). The feature fails safe: on any Mac that cannot run the model, the prompt keeps the cut name. The model is local, and the code uses `SystemLanguageModel.default` only. The real risks are small: one untested Developer ID build path, one wasted retry loop on errors, and different people seeing different name styles.

Expect the summary to appear on roughly half of all Macs (range 30% to 65%, Low confidence). Expect more for Nextshot's audience (range 50% to 80%, Low confidence). No public number is better than that.

## 1. Requirements

| Item | Requirement | Source | Confidence |
|---|---|---|---|
| macOS | macOS 26 or newer. The code gates with `#available(macOS 26, *)`. Apple lists macOS 27 "Golden Gate" in its current Apple Intelligence page. | [Apple Intelligence requirements](https://support.apple.com/en-us/121115) | High |
| Chip | Mac with M1 or later. No Intel Mac. | same | High |
| Apple Intelligence | Must be switched on in System Settings. It is opt-in. | same, plus [Kodeco](https://www.kodeco.com/53631607-getting-started-with-apple-s-foundation-models) | High |
| Language | 16 languages for Apple Intelligence. Device language and Siri language must match and be supported. | Apple page above | High |
| Region | Most regions. Devices bought in mainland China, or an Apple Account in mainland China, do not get Apple Intelligence. | Apple page above | High |
| Disk space | Up to 8 GB free. Up to 14 GB on Macs with M3 or later and 12 GB memory or more. | Apple page above | High |
| Model download | A system download after Apple Intelligence is switched on. The app does not control it. | Kodeco, community guides | Medium |
| Non-App Store app | Allowed. An Apple frameworks engineer says non-App Store apps can use the on-device model. No entitlement is named. | [Apple forums 832033](https://developer.apple.com/forums/thread/832033) | Medium |

The page is Apple's macOS 27 era page. Requirements for macOS 26 are the same in substance (M1 or later), but I did not read a macOS 26 snapshot.

### Availability states and what Nextshot does

Names come from community guides, because Apple's API pages returned no body text to the fetch tool. Verify the case names in Xcode.

| State | Meaning | Nextshot code | Result for the user |
|---|---|---|---|
| `available` | Model ready | `isAvailable` is true if `supportsLocale()` is also true | Summary requests run |
| `unavailable(.deviceNotEligible)` | Intel Mac or unsupported hardware, permanent | `isAvailable` is false | Cut name |
| `unavailable(.appleIntelligenceNotEnabled)` | User setting is off | `isAvailable` is false | Cut name. It switches on at the next copy once the user enables it |
| `unavailable(.modelNotReady)` | Downloading or not ready | `isAvailable` is false | Cut name. The next copy checks again |
| Any future reason | Unknown case | `isAvailable` is false (the check is `== .available`) | Cut name |
| `available`, but `supportsLocale()` is false | System locale unsupported | `isAvailable` is false | Cut name |
| Supported system locale, but notes in another language | Model throws `unsupportedLanguageOrLocale` or answers poorly | Lands in `.failed` or a bad reply (see risk 2) | Cut name, with a 60 second retry |

Source for the error cases: [Apple GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror.md). The code reading is from `FeedbackSummaryModel.swift:21-29` and `FeedbackSessionSummary.swift:100-113`.

## 2. Reach

No public source measures "Macs that can run the model with the switch on". The numbers below are ranges with the reasoning shown.

| Step | Estimate | Evidence | Confidence |
|---|---|---|---|
| Macs on macOS 26 or newer | 65% to 90% | TelemetryDeck (end of September 2026): macOS 27.0 at 13.06%, 26.6 at 36%, 26.5 at 13%, 26.3 at 2.38%. TelemetryDeck's sample is apps from developers who use it, so it skews to engaged users. One aggregator models Tahoe at 64% (mid 2026). One unverified site says 86% (July 2026). | Low |
| StatCounter | Cannot split. It reports every release since Catalina as Catalina (47.06% worldwide, June 2026). | [StatCounter](https://gs.statcounter.com/macos-version-market-share/desktop/worldwide), via search | Medium |
| Apple silicon among Macs on 26 or newer | 85% to 97% | macOS 26 is the last release for Intel Macs. Few Intel Macs run it. Only a handful of late Intel models qualify. macOS 27 is expected to drop Intel (secondary sources). No public installed base split exists. | Low |
| Apple Intelligence switched on, among eligible Macs | 50% to 85% | No Mac figure. Morgan Stanley (April 2025): nearly 80% of eligible US iPhone users had tried it in six months. Tim Cook (Apple fiscal Q1 2026): the majority of users on enabled iPhones use it. The Mac setup flow asks, but it is opt-in. | Low |
| Language and region fit | 90% to 98% for a US-weighted audience | 16 languages cover the main markets. See below for Nextshot downloads. | Medium |
| Combined, all Macs | 30% to 65% | Product of the ranges: 0.65 x 0.85 x 0.5 = 28% low, 0.9 x 0.97 x 0.85 = 74% high, then tightened because the extremes rarely line up | Low |
| Combined, Nextshot audience | 50% to 80% | Nextshot users run AI coding agents, so they tend to own recent Apple silicon Macs and update fast | Low |

Sources: [TelemetryDeck](https://telemetrydeck.com/survey/apple/macOS/versions/), [Apple Intelligence requirements](https://support.apple.com/en-us/121115), [TipRanks on Morgan Stanley](https://www.tipranks.com/news/apple-intelligence-is-more-popular-than-expected-says-morgan-stanley). Presenc.ai claims 940 million active devices with Apple Intelligence on. It cites no primary source, so I did not use it.

## 3. Nextshot's own audience

The download stats record only four fields per `/download`: time (UTC), version, country (Cloudflare edge country), and a bot flag. They keep no IP address and no raw user agent (`site/schema.sql`, `site/src/worker.js:195-199`). So they cannot tell the macOS version, chip, or language. I did not estimate macOS versions from them.

Read-only aggregate `SELECT` on `nextshot-downloads` (2026-11-01): 185 rows, 128 by people, from 2026-10-23 to 2026-11-01.

| Country | People |
|---|---|
| US | 87 (68%) |
| PL | 13 |
| CA | 8 |
| IN | 5 |
| NL, GB, FR | 3 each |
| TW | 2 |
| TR, RU, DK, DE | 1 each |

The audience is US-heavy and English-heavy. A few Polish and other non-English locales exist. Whether Polish is in the 16 supported languages is not verified here: rely on `supportsLocale()`.

Cheap way to learn the real share: add an opt-in, local-only line in the Nshot menu or Diagnostics. Do not add a macOS version field to the download table unless Drew accepts the privacy trade-off, because the site says it stores no user agent.

## 4. Risks and nuances

1. **Different name styles on different Macs.** A person with an M-series Mac sees "Pricing card layout". A person on an Intel Mac sees the first words they wrote. The same user with two Macs sees both. The names file `.summary-names.json` is local to each Mac (and shared by Dev and production on one Mac). The first paste of a round can differ from the second paste (decision record, "When it runs"). Impact: cosmetic. Confidence: High.
2. **Errors are all retried, including permanent ones.** `FeedbackSessionSummary.swift:110-112` treats every throw as `.failed` and retries after 60 seconds on any later copy. A guardrail violation or `unsupportedLanguageOrLocale` is permanent for that text. Each copy after 60 seconds would call the model again, uselessly. Cost: a short burst of work on copy, no UI block. Confidence: High on the code reading, Medium that those errors are what the model throws (Apple's page lists them: [GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror.md)).
3. **Guardrail refusals.** The 47-round test had 0 errors or refusals. Feedback text can still hold words that trip guardrails (profanity, a screenshot of a medical or legal screen, a note about a security flaw). The code cuts a refusal reply (`refusalStarts`) but a thrown guardrail error goes to risk 2. Confidence: Medium.
4. **Notes in unsupported languages.** `supportsLocale()` checks the system locale, not the note language. A Polish note on an English system could throw or return an odd name. The cleaner and the cut-name fallback cover the odd name. Confidence: Medium.
5. **Latency, battery, memory.** On Drew's idle Mac: median 0.36 s, longest 0.72 s, up to 1.77 s once on a busy Mac (decision record, measured). The model loads into memory on first use. First use after boot may take longer (no measurement). Each request is one short input (4,000 characters at most). Impact on battery: small. Confidence: Medium (one Mac).
6. **UI or copy blocking.** The request runs in an async `Task`. A copy never awaits it (`prime` returns at once). `isAvailable` is a synchronous property read on the main actor at each copy: it only reads a cached state, so I expect no stall, but nobody measured it on a Mac mid-download. `LanguageModelSession` also reports `concurrentRequests` errors, and the code runs one request per distinct input, so two inputs at once are possible. Confidence: Medium.
7. **Developer ID build, hardened runtime, notarization.** An Apple engineer confirms non-App Store apps can use the model and names no entitlement ([forum 832033](https://developer.apple.com/forums/thread/832033)). FoundationModels is weak-linked, so macOS 15 launches. The handover says the Dev build (Apple Development signature) was built and the model was tested on Drew's Mac. Nobody ran the notarized production DMG with the model, because the m5pro rule bars running production Nextshot. Confidence: Medium. This is the largest unverified step.
8. **Apple's usage terms.** Using the framework means agreeing to Apple's [Acceptable Use Requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/) and keeping reasonable guardrails. A short noun-phrase name for a screen note fits within them. Do not try to bypass guardrails. Confidence: High that naming is fine, Medium that Apple's license has no other clause for non-App Store distribution (I did not read the full license).
9. **macOS 27 SDK.** The SDK adds `PrivateCloudComputeLanguageModel`, a server model, plus an `fm` command-line tool and a provider protocol for other models. `GenerationOptions(sampling:)` is deprecated in the 27 SDK in favor of `samplingMode:`; the code keeps the old spelling for macOS 26 and logs a warning. Apple says the framework is going open source. Sources: [WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/), [Apple Foundation Models page](https://developer.apple.com/foundation-models-framework/). Confidence: Medium (secondary summaries for details).
10. **Privacy claims.**
    - The code calls `SystemLanguageModel.default` only. Apple describes this model as running on the device and working without internet ([Apple page](https://developer.apple.com/foundation-models-framework/)). Private Cloud Compute is a different type that the code never uses. Confidence: High for the code, Medium for Apple's wording (it does not say "never uses network" in a legal sense).
    - The system, not Nextshot, downloads the model when the user switches on Apple Intelligence. That is macOS network use, not Nextshot's.
    - Nothing stops a later edit from switching to the Private Cloud Compute type. The scan test does not check for it (decision record, "Open").
    - The wording "makes no network requests" stays true for Nextshot code. A site claim that the product is "offline" should not say the Mac never touches the network for Apple Intelligence.

## 5. Recommendation

Default on in 0.6.0, if these four conditions hold:

1. **Test the notarized DMG with the model.** Run it on another approved Mac (not m5pro) with Apple Intelligence on, then off. Confirm one summary name and one fallback name, with no crash. If no second Mac is available, ask Drew to decide on the Dev build evidence alone.
2. **Stop retrying permanent errors.** Treat guardrail violation and unsupported language as declined, not failed. A one-line change.
3. **Add the scan rule for `PrivateCloudComputeLanguageModel`** in `NetworkSourceScanTests`. This turns the privacy claim into a guard. Drew's repo rule says no tests unprompted, so Drew must approve this one.
4. **Set the flag default with a released-in build number,** as the registry requires, and review the Guides pages that describe session names.

Do not add a visible setting. A switch costs inputs for no benefit, and Settings > General already shows the Apple Intelligence state elsewhere in macOS.

### Suggested wording

Release notes (CHANGELOG, one line): "Session names now summarize all your captures when your Mac runs Apple Intelligence (Apple silicon, macOS 26 or newer). The summary is written on your Mac. Other Macs keep the name cut from your first note."

Guides (session names page): "Nextshot names a pasted round from your notes. On a Mac with Apple Intelligence, the name is a short summary written by Apple's on-device model. It runs on your Mac and sends nothing out. Without it, the name is the start of your first note. The same round can show a different name on another Mac."

Site and README: the claim "Nextshot stays offline" stays true. If a line mentions the feature, write: "Optional summary names use Apple's on-device model. Nextshot makes no request."

## Open questions for Drew

1. Which approved Mac can run the notarized DMG for condition 1?
2. Approve the scan test for `PrivateCloudComputeLanguageModel`?
3. Should a local-only counter record how often a summary is used, to replace the reach guess with a real number?
4. Is a different name style on a second Mac acceptable, or should the Guides say so?

## Sources

- [Apple Intelligence requirements](https://support.apple.com/en-us/121115), read 2026-11-01
- [Apple Foundation Models framework page](https://developer.apple.com/foundation-models-framework/), read 2026-11-01
- [Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/), read 2026-11-01
- [Apple forums 832033, non-App Store apps](https://developer.apple.com/forums/thread/832033), read 2026-11-01
- [GenerationError](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror.md), search result 2026-11-01
- [TelemetryDeck macOS versions](https://telemetrydeck.com/survey/apple/macOS/versions/), page dated 2026-10-01, read 2026-11-01
- [StatCounter macOS versions](https://gs.statcounter.com/macos-version-market-share/desktop/worldwide), search result 2026-11-01
- [Kodeco, Foundation Models](https://www.kodeco.com/53631607-getting-started-with-apple-s-foundation-models), search result 2026-11-01
- [TipRanks, Morgan Stanley survey](https://www.tipranks.com/news/apple-intelligence-is-more-popular-than-expected-says-morgan-stanley), search result 2026-11-01
- [WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/), search result 2026-11-01
- Local: `FeedbackSessionSummary.swift`, `FeedbackSummaryModel.swift`, `SummaryNames.swift`, `SessionName.swift`, `docs/decisions/2026-10-31-session-summary-name.md`, `site/schema.sql`, `site/src/worker.js`, D1 `nextshot-downloads` (SELECT only)
