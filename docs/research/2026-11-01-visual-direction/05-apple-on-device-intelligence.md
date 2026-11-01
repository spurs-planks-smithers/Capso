# Research note 05: Apple on-device intelligence for Nextshot

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

**Bottom line:** On macOS 27, Apple's on-device stack can do jobs (a), (d) and (g) locally with high or medium confidence. It can probably do (b), (c) and (e) for duplicates. Jobs (f), (h) and conflict detection in (e) need testing first. I found no Apple API that parses UI screens, and no published image latency or accuracy for Foundation Models. Read-only; no files edited.

**Method limits.** I read every page below through a summarizing fetch tool. Apple docs came from the developer.apple.com/tutorials/data JSON endpoints. Treat quotes as paraphrase. I omitted China-origin model names from comparisons, per your rule.

### 1. Capabilities

| Capability | macOS 26 and 27 | Evidence | Src | Implication |
|---|---|---|---|---|
| On-device model | 26: ~3B text model. 27: AFM 3 Core (3B dense) and AFM 3 Core Advanced (20B sparse, 1 to 4B active). `SystemLanguageModel.Variant` has `core3` and `coreAdvanced3`, new in 27.0 | Context size conflicts. Apple Updates page: 4,096. PCC article table: "4K". Session 241 code comment: 8192. M5 Max, macOS 27.0.1 test: `contextSize` 8192, a 8,128-token prompt accepted. An M-series Mac write-up: 4,096 | S1 S3 S5 S7 S17 S20 | Read `contextSize` at runtime. Plan prompts for 4K |
| Core Advanced hardware | 27 | Apple says "most capable silicon". Third parties say 12GB RAM minimum (Thoughtworks), M3 Mac with 12GB (leak). Apple has no list | S7 S22 | Many Macs likely get only the 3B model |
| Image input | 26: none. 27: `Attachment(image)`, capability `.vision` | Any size and aspect ratio. Larger images cost more tokens and latency. No token cost or image limit published. Docs do not say which variant has `.vision`. A write-up shows `fm respond --image` on AFM 3 Core | S1 S2 S21 S20 | Check `.vision` per Mac at runtime. Crop before prompting (Apple advises isolating a region) |
| Guided generation, tools, streaming | Since 26. 27 adds `ToolCallingMode`, image tool args, `OCRTool`, `BarcodeReaderTool` | `@Generable` enums use constrained decoding. Apple advises 3 to 5 tools per request and 2 to 15 few-shot examples. Image enum classification example uses `.greedy` | S21 S4 S3 | Good fit for label and pick tasks |
| Speed | 26 and 27 | M4 Max, macOS 26: 85.2 tok/s decode, 269 ms first token (n=3, plus or minus 20%, estimated tokens). M5 Max, macOS 27.0.1: first token 0.17 s back-to-back, 0.60 s after a 10 s pause. No image latency found | S17 | Text labels per capture take about 1 s. Image cost unknown |
| Limits and guardrails | On-device: "Unlimited". 26.4 cut false blocks. 27 improves more | `guardrailViolation` and `refusal` errors exist. Permissive mode works for string output only. Guided generation always keeps default guardrails. Guardrails work only in supported languages | S4 S5 S3 | Blunt notes or screen text can fail a typed label. Catch the error and fall back |
| Adapters | Toolkit 26.0.0 is the last release, not compatible with OS 27+ | About 160 MB per adapter, 100 to 1,000 samples. Needs 32GB Mac | S18 | No fine-tune on macOS 27 yet. Use few-shot prompts |
| Private Cloud Compute | 27 | 32K context, reasoning levels, daily quota, entitlement. Eligibility: App Store Small Business Program and fewer than 2M first-time downloads. Page silent on Developer ID | S5 S6 | PCC is a network path and Nextshot ships by Developer ID. Likely unavailable and against the local-only rule |
| Vision text | RecognizeTextRequest (macOS 15). RecognizeDocumentsRequest (macOS 26) | Documents request gives tables, lists, paragraphs, 26 languages, built-in data detection | S10 S11 | Group OCR lines into blocks with boxes |
| Vision new in 27 | macOS 27 | `GenerateIterativeSegmentationRequest`: tap, box or scribble, max 13 points (11 for a box), asset download. Vision's own updates page lists no 2026 entries, but the request's doc page says 27.0. No UI-element request found | S2 S11 | Built for photo objects. UI use is untested |
| Prints, faces, saliency | Feature print and face rectangles since macOS 15 | No accuracy numbers published | S11 | Free local duplicate and privacy signals |
| NL embeddings | `NLEmbedding.sentenceEmbedding` (macOS 10.15). `NLContextualEmbedding` (macOS 14) | Apple recommends `NLEmbedding` for similarity. Language list and accuracy not stated. No 2026 update found | S13 | Cheap duplicate prefilter. English quality unmeasured |
| Speech | `SpeechAnalyzer` and `SpeechTranscriber` (26). 2026 adds `CaptureInputSequenceProvider` | Word timing via `audioTimeRange`. Third-party test, M2 Pro, macOS 26.5.1, LibriSpeech English: WER 2.12% clean and 4.56% other. Whisper Small 3.74% and 7.95%. Legacy 9.02% and 16.25%. 12x to 40x real time. MacStories: 34 min in 0:45 | S14 S15 | In-app dictation is possible. Read speech only, not noisy desks |
| Apple model claims | 2025 report, 2026 blog | 2025: 300M-param vision encoder, human preference only, no readable scores. 2026 AFM 3 Core: preferred over 2025 on image understanding more than 61% of the time. No 2026 tech report found | S8 S9 S7 | No benchmark to trust yet. Run your own eval |
| UI research | Papers, no API | Ferret-UI Lite (3B): ScreenSpot-V2 91.6%, ScreenSpot-Pro 53.3%, OSWorld-G 61.2%. UI-JEPA: 50.5x lower cost, 6.6x lower latency. Ferret-UI 2 (ICLR 2025). ILuvUI: 335K examples. Newest Apple item found is Ferret-UI Lite (Feb 2026) | S16 | Not shippable. Shows UI grounding is hard for 3B models |

### 2. Nextshot jobs

| Job | On-device option | Confidence | Why |
|---|---|---|---|
| a. Note names a concrete change | Foundation Models text, `@Generable` enum (concrete, vague, question, empty), reasoning field first, greedy | Medium | Apple's own classification pattern. Fits 4K. Accuracy unknown. Guardrail errors possible |
| b. Split dictation by badge | Parse "circle N" in `SpeechTranscriber` text (word times available). Foundation Models array as fallback | Medium | Deterministic parse is cheap. Model only for messy speech. Not measured |
| c. Best search string from OCR | Model returns an index into a numbered OCR list (`@Guide` range), or a rarity score | Medium | Choosing from a list is the easiest model task. 4K caps the list. Measure with `tokenCount(for:)` |
| d. Crop with context | Mark box plus padding, expanded to the enclosing `RecognizeDocumentsRequest` paragraph or table box | High | Pure geometry and OCR. Segmentation is low confidence on UI |
| e. Duplicates and conflicts | Duplicates: sentence-embedding distance, OCR overlap, feature print on crops. Conflicts: model pair check | Medium (duplicates), Low (conflicts) | Pairs grow as n(n-1)/2, so prefilter. No similarity accuracy found |
| f. Severity | Model enum, few-shot | Low to medium | Subjective. No adapters on 27 |
| g. Private data | `DataDetector` (email, phone, link, address, money, tracking), `NLTagger` `.nameType`, `DetectFaceRectanglesRequest`, plus local regex for keys | High (email, phone, faces), Medium (names) | All deterministic and local. Secrets have no Apple API |
| h. Describe marked element | Model with image of the crop plus OCR text. Alternative: `AXUIElementCopyElementAtPosition` role and title | Low to medium | No image accuracy or latency published. Variant support unclear. The Accessibility call needs trust (page silent) |

### 3. Open questions

1. Which Macs return `.vision` in `capabilities`, and does an 8GB Mac get image input?
2. Is the real context 4,096 or 8,192, and does it depend on hardware?
3. Does PCC allow Developer ID apps? Would you accept a network exception?
4. Will an adapter toolkit for OS 27 ship?
5. How many users stay on macOS 26, where there is no image input and no `.vision`?

### 4. Test first

1. **Note labels (job a) in shadow.** Run the local model beside Jev on the labeled set. Use `scripts/note-coach-eval.sh`. Compare agreement with Jev and with labels. Count guardrail errors, p50 and p95 latency in Instruments, and `tokenCount`.
2. **Local private-data pass (job g).** Feed `DataDetector`, `NLTagger` and face boxes into `dataGuard`. Measure precision and recall against hand-marked captures and the current rules. Confirm `NetworkSourceScanTests` still passes.
3. **Duplicate prefilter (job e).** Add sentence-embedding distance and a feature-print check. Score flagged pairs with `scripts/nextshot-jev-review.sh dupes`. Report recall at a fixed number of model calls.

### Sources
- S1 What's new in the Foundation Models framework, Apple Developer, WWDC26 (2026): https://developer.apple.com/videos/play/wwdc2026/241/
- S2 What's new in image understanding, Apple Developer, WWDC26 (2026): https://developer.apple.com/videos/play/wwdc2026/237/
- S3 Updates for Foundation Models, Apple docs, 2026: https://developer.apple.com/tutorials/data/documentation/updates/foundationmodels.json
- S4 Improving the safety of generative model output, Apple docs, 2026: https://developer.apple.com/tutorials/data/documentation/foundationmodels/improving-the-safety-of-generative-model-output.json
- S5 Adding server-side intelligence with Private Cloud Compute, Apple docs, 2026: https://developer.apple.com/tutorials/data/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute.json
- S6 Private Cloud Compute, Apple Developer, 2026: https://developer.apple.com/private-cloud-compute/
- S7 Introducing the Third Generation of Apple's Foundation Models, Apple MLR, June 8, 2026: https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models
- S8 Tech Report 2025, arXiv: https://arxiv.org/html/2507.13575v3
- S9 Apple Foundation Models 2025 updates, Apple MLR, 2025: https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
- S10 Read documents using the Vision framework, WWDC25 (2025): https://developer.apple.com/videos/play/wwdc2025/272/
- S11 Vision docs (RecognizeDocumentsRequest, GenerateIterativeSegmentationRequest, GenerateImageFeaturePrintRequest, DetectFaceRectanglesRequest, RecognizeTextRequest, updates), Apple, 2026: https://developer.apple.com/tutorials/data/documentation/vision.json
- S13 NLEmbedding and NLContextualEmbedding, Apple docs: https://developer.apple.com/tutorials/data/documentation/naturallanguage/nlembedding.json
- S14 Bring advanced speech-to-text with SpeechAnalyzer, WWDC25 (2025): https://developer.apple.com/videos/play/wwdc2025/277/ and Speech updates (June 2026): https://developer.apple.com/tutorials/data/documentation/updates/speech.json
- S15 Apple speech API benchmark, Inscribe/Lyonesse, 2026: https://lyonesse.app/blog/apple-speech-api-benchmark.html. MacStories, 2025: https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/
- S16 Ferret-UI Lite, Apple MLR (Feb 2026): https://machinelearning.apple.com/research/ferret-ui. arXiv 2509.26539, 2404.05719, 2410.18967, 2409.04081, 2310.04869.
- S17 apple-silicon-llm-bench (GitHub, 2026): https://github.com/john-rocky/apple-silicon-llm-bench. macos27-fm (GitHub, 2026): https://github.com/Shreetej/macos27-fm
- S18 Foundation Models Adapter Training Toolkit, Apple Developer, 2026: https://developer.apple.com/apple-intelligence/foundation-models-adapter/
- S20 AFM 3 Core and the fm command, note.com, 2026: https://note.com/unco3/n/nef0ada6af65d
- S21 Analyzing images with multimodal prompting, Apple docs, 2026: https://developer.apple.com/tutorials/data/documentation/foundationmodels/analyzing-images-with-multimodal-prompting.json
- S22 Local inference boundary, Thoughtworks, 2026: https://www.thoughtworks.com/insights/blog/generative-ai/local-inference-boundary-reflections-apple-afm3-token-economics

**Not confirmed:**
- A 2026 Apple tech report.
- Image token cost, image latency, or image accuracy.
- Which model variant has `.vision`.
- Any 2026 Natural Language change, or WWDC26 Speech session content.
- SpeechTranscriber language count. The one figure I saw ("around 30 locales") is third-party.
- Whether `AXUIElementCopyElementAtPosition` needs Accessibility trust. The page is silent.

**Contradiction.** The context window is 4,096 in some sources and 8,192 in others (see row 1).
