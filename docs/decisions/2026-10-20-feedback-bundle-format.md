# Decision: feedback bundle format

- Date: 2026-10-20
- Status: Accepted (Drew approved the Phase 1 plan on 2026-10-20)
- Plan: `docs/plans/2026-10-20-feedback-sessions-phase1.md`

## Context

Drew reviews PDFs and web pages, captures regions, and marks them. An AI coding agent (Claude Code, Codex, or another tool) then acts on the marks. The first draft of the plan wrote numbered PNG files and a manifest with an empty note. The research below shows that this format gives poor results. Images with no paired text, marks with no label, and prompts with no scope or verify rules are the documented failure modes.

## Decision

Each feedback session writes one folder under `~/Feedback/`:

```
~/Feedback/2026-10-20-1912-pricing-page/
  manifest.md      entry point: how to read the bundle, then one section per capture
  prompt.md        the prompt that Copy Prompt puts on the clipboard
  feedback.json    machine-readable, schemaVersion 1, source of truth
  001.png          annotated, long edge <= 2000 px, <= 4784 visual tokens
  001-clean.png    same size, no marks
  002.png ...
```

- Every mark gets a written instruction. The text is the instruction. The image is the evidence.
- Counter badges give each mark a short ID. Item `2.3` is badge 3 in capture 2. The image and the text use the same ID.
- Each item records its pixel box in the exported PNG (origin top-left) and the on-device OCR text under the mark.
- A note line that starts with a badge number (`2: wrong price`) becomes that item's instruction. Other note text becomes the capture note.
- A missing value shows as `n/a`, never as a blank cell.
- `prompt.md` holds a goal, an authority rule (the written instruction wins), a work method (a located-items table before any edit, change only the listed items), a verify step (re-check every item), and a one-line-per-item report.

## Revision 2026-10-21 (Drew's in-app testing)

| Change | Why |
|---|---|
| A capture is named "Capture: <window title>, <date time zone>". The manifest heading quotes the title. Files are `<HHmm>-<title slug>.png`. | Drew: "capture 4" says nothing. He asked for the window title, date, and time with time zone, and no index number. |
| The manifest gives each capture an item prefix line ("Item prefix: 4 (badge N is item 4.N)"). | Agents still need short, unique item IDs. The prefix replaces the number that used to be in the heading. |
| The note panel asks one question per circle, then an optional general note, and saves each answer as that circle's instruction. | Drew expected one input per circle. It suits dictation, because he does not have to say "1:". The `N:` note syntax stays in `NoteParser` but the panel no longer needs it. |
| Each circle question shows a zoomed preview of the annotated capture around that circle. | Drew forgot which circle meant what by the time the questions came. |
| Window titles count as screen text: cleaned, capped, and quoted, and reading rule 8 lists them. | Any web page sets its own title, so it must not read as bundle structure or instructions. |
| After the last note step, the capture's own prompt goes on the clipboard. It names the annotated PNG and `manifest.md` by absolute path and lists the answers as items. Copy Prompt in the menu still copies the whole session. | Drew: one paste should hand a capture to any agent tool. He chose "this capture only" over the whole session. |
| The capture prompt holds only the reviewer's answers. OCR text and window titles stay in `manifest.md`. | A pasted prompt is the user's own message, so screen text in it would read as the user's instruction. |
| The capture is stored before OCR runs. OCR adds the screen text afterward (`setScreenText`). | Cold OCR took 30 s (measured 2026-10-20). The clipboard must hold the prompt when the last note step ends. |
| Bundles move from `~/Feedback` to `~/Library/Application Support/CapsoFeedback`. | Drew did not want a folder at the top of his home folder. Application Support is the standard macOS place for app data and is not privacy-protected, so every agent tool can read it. Documents, Desktop, and Downloads are protected, and `~/Developer` is an Obsidian vault. |

## Evidence

| Finding | Source | Design rule |
|---|---|---|
| Models struggle to turn visual feedback into functional requirements ("visual interpretation gap", 20 models tested). Visual feedback scored below text: 55.0% against 56.0% before the authors' fix, 60.2% against 65.3% after it. | FronTalk, Wu et al., ICML 2026, [arXiv 2601.04203](https://arxiv.org/abs/2601.04203) | Every mark gets a written instruction. Typed note in Phase 1. |
| Over multi-turn edits, models overwrite earlier fixes ("forgetting"). A self-check against all earlier instructions cut forgetting to near zero. | FronTalk (AceCoder method) | The prompt makes the agent re-verify every item at the end. |
| Agents lack fine-grained visual-to-code alignment, and they damage content that should stay unchanged. | MT-Web2Code, Aug 2026, [arXiv 2608.03474](https://arxiv.org/abs/2608.03474) | Exact pixel boxes and on-image text near each mark. The prompt says "change only the listed items." |
| Numbered marks on regions let a model refer to them by a short label. GPT-4V grounding beat a fine-tuned state-of-the-art model with this method. | Set-of-Mark, Yang et al., [arXiv 2310.11441](https://arxiv.org/abs/2310.11441) | Counter badges (key C or N) label marks. |
| A drawn red circle directs model attention to a region and keeps global context. | Shtedritski et al., ICCV 2023 | Keep shapes and arrows. Record their pixel boxes too. |
| Claude works best with absolute pixel coordinates on the image it sees. Oversized images are resized, which shifts coordinates. | Anthropic, [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates) | Export each PNG small enough that Claude does not resize it. Coordinates are pixels of that PNG. |
| Opus 5.5 reads up to 2576 px and 4784 visual tokens per image. Above 20 images in one request, any image over 2000 px is rejected. Lossy compression hurts text. | Anthropic, [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) | Cap the long edge at 2000 px and the cost at 4784 visual tokens with Anthropic's resize rule. Keep PNG. |
| Images work best before the text about them. Label each image so later text can name it. | Anthropic, [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) | The agent opens each image first, then reads its section. Files and headings use the same ID. |
| "Don't rely on the image alone." Name what the image shows, point to the area, state the outcome and constraints, ask for a new screenshot to verify. | OpenAI, [Codex image inputs](https://learn.chatgpt.com/docs/image-inputs?surface=cli) | The prompt has a goal, rules, a work method, and a verify step. `manifest.md` holds a ready `codex --image` command. |
| Give a check the agent can run, such as a screenshot compared with the target. Be specific: files, symptoms, constraints. | Anthropic, [Claude Code best practices](https://code.claude.com/docs/en/best-practices) | A located-items table before edits, then a screenshot comparison where the UI can render. |
| Feedback tools built for agents (Agentation, AgentEcho, Markagent, MarkUp, SenAnnotate) export numbered marks plus a Markdown report with locators the agent can search for. | Product pages, 2025 to 2026 | OCR text under each mark is the locator. Browser URL and DOM selectors come later. |

Two rules come from judgment, not from a cited result:

1. Keep a clean copy of each capture, because marks can hide the content they point at.
2. Keep the per-item fields few, per Drew's rule that a spec is a ceiling.

## Consequences

- `FeedbackKit` must port Anthropic's resize rule and scale mark coordinates to the exported size.
- The app must run OCR on the clean image and read the annotation objects at save time.
- Each image costs up to 4784 visual tokens, so the prompt tells the agent to open an image only when it works on that image's items.

## Alternatives considered

| Option | Why not |
|---|---|
| Numbered PNG files and a manifest with an empty note (first draft) | Images without paired text and unlabeled marks are the main failure modes above. |
| JPEG export | Lossy compression hurts text in screenshots. |
| Full-resolution PNG files | The model resizes them, which shifts the coordinates in the manifest. |
