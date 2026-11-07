# Visual direction for AI agents: research synthesis

Date: 2026-11-01. Status: research done. The design that builds on it is `docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`. The raw evidence is in the eight notes in `docs/research/2026-11-01-visual-direction/`.

## Question

How can Nextshot build a better handoff (prompt, metadata, and images) so that any AI agent applies a reviewer's visual feedback well, above all across many captures? How can Apple's on-device models and Jev help?

## What Drew said (interview, 2026-11-01)

- **The main failure is synthesis.** In a large round, his notes circle around a few ideas across captures. Agents treat each item alone. He wants the agent to plan the whole change and still finish every item.
- **The second failure is scope.** Agents skip items, undo earlier fixes, or change things he did not mark.
- **One paste must work in any tool.** The prompt uses helper agents where the tool supports them. The user never makes that choice.
- **Agent output comes first.** He reviews what an AI made, then pastes the feedback into a coding agent or a new chat, never the chat that made the draft.
- **Success is fewer redo rounds,** and an agent that visibly plans and acknowledges every note and every link across captures.
- **The agent asks only when unsure.**
- **Themes are for the agent's own work.** They help it link ideas and stay consistent. No person labels, reviews, or grades them.
- **Apple on-device runs the helper jobs first.** Jev is a second path behind a flag, a setting, and network consent. Jev stays dev-only for now.
- **The core open problem is image travel:** how a round of many captures reaches a tool that cannot open files on the Mac.

## Baseline: 61 saved rounds on m5pro

| Measure | Value |
|---|---|
| Rounds, captures, numbered items | 61, 131, 270 |
| Items with no instruction | 44 (16%) |
| Instructions with "this", "that", "here", or similar | 119 (53%) |
| Words per instruction | median 9, 90th percentile 66, longest 209 |
| Rounds by capture count | 40 with one capture, 8 with two, 13 with three or more (largest 14) |
| Marks | 270 badges, 17 arrows, 16 text, 16 pixelate, 8 boxes |
| Capture size | median 1580 by 1294 px, largest 1988 by 1988 px |

A count by source app misleads. A capture of the Nshot menu records the app under the menu, often Claude. About 15 captures are tests, and only about 5 are real reviews of agent output. Read the notes before you count by app.

## Method

Eight research agents (Sonnet) each read sources on one topic and wrote a note. Findings that drive a design choice were then checked against the source by hand. The table column "Checked" marks them. Other numbers are as the agent read them. A paste test in a browser could not run: synthetic key presses fire no real paste, and the clipboard API refuses to read. The design keeps a manual paste test as its first build step.

## Findings

### 1. Many items in one handoff

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Each instruction alone is easy. All of them together are not. | Claude 3.5 Sonnet followed all instructions in 95% of prompts with one instruction and 48% with ten, while it followed 93% of single instructions at ten. GPT-4o: 94% to 21%. | Harada et al., ManyIFEval, EMNLP 2025 Findings | Yes |
| Give every item at once. Split work loses accuracy. | Splitting a task over chat turns lost 39% on average over six tasks. GPT-4o: 93.0 with the full task, 59.1 split. | Laban et al., 2025 | No |
| Order matters. | Shuffling related premises cut accuracy over 30%. GPT-4-turbo at 12 rules: 96.5% in order, 76.0% shuffled. | Chen et al., ICML 2024 | No |
| Frontier models start full-task work best. | "Performs best when given the complete task specification up front and left to run." | Anthropic, Prompting Claude Opus 5 | Yes |

Implication: one message holds every item. An item ledger opens and closes the handoff. Related items sit together, with the general item first.

### 2. Linking ideas across captures

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Linking scattered facts fails as context grows. | Claude 3.5 Sonnet followed a chain of linked facts 78.3% of the time at 1,200 tokens, 43.9% at 32,000, 5.6% at 128,000. | Roberts, Han, Albanie, 2025 | No |
| A record of state lifts multi-file work. | Base agents solved 22% of refactor tasks. A human solved 87%. State tracking added 43.9%. In about 44% of tests the agent never edited a named target file. | Gautam et al., RefactorBench, ICLR 2025 | Yes |
| A plan computed first beats edit-by-edit work. | CodePlan passed validity checks in 5 of 6 repositories. Baselines passed 0. | Bairi et al., Microsoft, FSE 2024 | No |
| Several examples of one edit reveal the shared rule. | From two or more examples: 99% precision, 89% recall. One example gave many false hits. | Meng, Kim, McKinley, ICSE 2013 (abstract) | No |
| Group summaries help questions that span many pieces. Clustering itself adds little. | GraphRAG won 72% to 83% of comprehensiveness comparisons. RAPTOR: clustered tree 56.6% against 55.8% for a plain tree. | Microsoft 2024; Sarthi et al., ICLR 2024 | No |
| Generic context costs money and adds nothing. | Model-written context files: 0.5% and 2% lower success, 20% to 23% more cost. | Gloaguen et al., 2026 | No |
| Restating the problem first helps reasoning. | Step-back prompting: +7 to +27 points (PaLM-2L). No study tests it on review notes. | Zheng et al., ICLR 2024 | No |

Implication: the agent needs an explicit structure that links items, names one shared decision per group, and records its progress. Nextshot can compute local signals that suggest which items belong together. The agent makes the final grouping. Every line in that structure must be specific to the round.

### 3. Images, marks, crops, and coordinates

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Words plus marks beat either alone. | GPT-4o: image only 0.37, text only 0.42, both 0.67 (CLIP score). | Xiao et al., Interaction2Code | No |
| Mark style changes results, and the best style differs by model. | A red-to-blue marker change can reorder leaderboards. A slightly larger marker lifted a small model to the level of large ones. | Feng et al., UC Berkeley, 2026 | Yes |
| Tags and boxes read better than points and arrows. | Mean over 27 models: box 87.49, tag 85.26, arrow 79.66, point 67.22. GPT-4o: box 74.18, tag 69.95, point 49.28. | Xu et al., VP-Bench, AAAI 2026 | No |
| Add a crop to the full image. Do not replace the full image. | Small targets: 39.38 to 69.95 with a crop added (an older open model). | Zhang et al., ICLR 2025 | No |
| Current Claude models do vision best with tools to crop and check. | "Vision performance is strongest when the model has tools to iteratively analyze, crop, and visually verify its work." | Anthropic, Prompting Claude Opus 5 | Yes |
| More images cost accuracy. | Models fail to combine information across many images. | MIMIC 2026, MileBench (abstracts) | No |

Implication: keep badge, box, and words together for every item. Send a crop of each item next to the full image, not in its place. Keep the image count low.

### 4. Scope, questions, and checks

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Asking once nearly matches a full specification. | Claude Sonnet 4.5 on vague coding tasks: 54.80% with no questions, 70.40% when it asked (about one question each time), 70.80% with a full specification. | Edwards and Schuster, Ask or Assume, EMNLP 2026 | Yes |
| Explicit verify lines cause over-verification on current Claude models. | "Remove them: instructions like these cause over-verification." | Anthropic, Prompting Claude Opus 5 | Yes |
| Without a named target, a model misses most subtle UI changes. | Best model found 40.7% of true changes. Hard tier: under 23% for every model. | Zhang et al., DiffSpot, 2026 | Yes |
| Free repair loops drift. One repair target per round keeps them stable. | A local fix can break regions that were correct. | Xiong et al., RubSE, 2026 | Yes |
| Agents misread intent and misreport what they did. | 26.95% misread intent, 22.58% inaccurate self-report, 10.20% overreach (16,118 episodes). | Tang et al., 2026 | No |
| Chat feedback rarely carries a fix into later parts of a draft. | Fix transfer rate under 0.1 for feedback given in chat. | Choi et al., 2025 | No |

Implication: the agent does every clear item, then asks one batch question about the rest. The report gives specific evidence per item. A general "re-check" line does not help.

### 5. Helper agents

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Delegate only large independent work, never verification. | "Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify." | Anthropic, Prompting Claude Opus 5 | Yes |
| Split work helps parallel tasks and hurts sequential ones. | +80.8% on decomposable tasks, 70.0% worse on sequential planning. | Kim et al., 2025 (abstract) | No |
| A helper sees only its brief. | A Claude Code subagent starts with fresh context and the delegation message. | Claude Code docs | No |

Implication: the prompt names a capability, not a product. Helpers take only groups in separate files. The lead agent keeps the groups, the shared decisions, and the plan.

### 6. Locating the code

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Only a source file and line moved file-finding in the one benchmark found. | 86% with no hint or a component name, 95% to 96% with file and line. | React Grab benchmark, 2026 (product claim) | No |
| A Mac app can read the page URL, the HTML id and classes, and a document's file path. | Chrome and WebKit expose AXURL, AXDOMIdentifier, AXDOMClassList. Preview exposes AXDocument. | Chromium and WebKit source, forums | No |
| These reads need the Accessibility permission. | A new one-time prompt. | Apple Support | No |

Implication: locators (URL, document path, page or slide) are cheap but add a permission prompt. Test them in shadow before any prompt uses them.

### 7. Delivery to tools that cannot open files

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| A long paste can reach the model empty in Claude chat. | Claude desktop and claude.ai turn a long paste into an attachment chip. The model sees an empty attachment, and no error shows. Open since 2026-07-15, last report 2026-10-09. Shift+Command+V avoids it. | anthropics/claude-code issue 77946 | Yes |
| Image caps per message are low. | claude.ai: 20 images. Gemini app: 10 files. A 14-capture round with clean copies needs 28. | Anthropic and Google help | No |
| PDFs are read as page images plus text in Claude and Gemini. | Claude renders each page and extracts its text. ChatGPT chat is unconfirmed. A PDF needs an attach or a drag. | Anthropic PDF support, Gemini docs, OpenAI API docs | No |
| Labels must be in the pixels. | Models do not read file names or image metadata. Anthropic advises a text label for each image. | Anthropic and OpenAI vision docs | No |
| One paste with text and one image probably works in Chrome chats. | Users report that ChatGPT attaches an image whenever a pasted item holds both text and an image. Several images, file URLs, and PDFs on the clipboard are unproven. | OpenAI community, 2024 to 2026 | No |
| One composite image shares one size budget. | About 12 readable item cells fit in 2,576 px, and about 4 in 1,568 px (the research agent's arithmetic). Studies of composites against separate images disagree. | Anthropic vision docs; ReMI, RealBench, MIMIC | No |
| Local MCP image results fail in Claude chat. | Reports of empty image slots on claude.ai and Claude desktop. ChatGPT web supports remote MCP only. | Community reports, OpenAI docs | No |

Implication: one paste should carry short, self-contained text and at most one image with its labels drawn in. A hand test in each app decides whether several images can travel in the same paste.

### 8. Screen text and dictation

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| Delimiters alone are a weak guard. | Delimiters about halve attack success. Most of 12 published defenses were bypassed. | Hines et al., 2024; Nasr et al., 2025 | No |
| Text inside images can steer agents. | Agents deceived up to 51% (computer use) and 100% (browser use). | Cao et al., VPI-Bench, ICLR 2026 (abstract) | No |
| Dictation costs accuracy, and cleaning the words does not restore it. | Voice lost 9.7 points against 3.0 for typing. Removing filler words gave no gain. | Hu et al., 2026 | No |

Implication: keep screen text out of the pasted prompt, as today. Keep the reviewer's words exact.

### 9. Apple on-device models and Jev

| Finding | Evidence | Source | Checked |
|---|---|---|---|
| macOS 27 adds image input to the on-device model. | `Attachment` takes an image in a prompt. Apple advises isolating the region of interest first. | Apple docs, Analyzing images with multimodal prompting | Yes |
| Nextshot already runs the on-device model. | Summary names: 38 of 47 rounds named, median 0.36 s, longest 0.72 s on m5pro. | `docs/decisions/2026-10-31-session-summary-name.md` | Yes |
| Reach is partial. | The summary should appear on 30% to 65% of all Macs. Low confidence. | `docs/research/2026-11-01-on-device-summary-availability.md` | Yes |
| Local Vision and language APIs cover several jobs with no model. | Document structure (macOS 26), data detectors, face boxes, image feature prints, sentence embeddings. | Apple docs | No |
| Jev 1.14 (2026-10-14) is still TypeSafe's newest model. Image input is still experimental. | Models page lists 1.14 and 1.13 only. | TypeSafe docs | Yes |

Implication: on-device first for note checks, crops, private-data covers, and related-item signals. Jev stays a dev-only comparison path.

## What the evidence does not cover

1. No study tests grouped or themed review items in a coding agent prompt.
2. No study tests images that arrive by file path in a coding agent.
3. No study tests pointing words ("this one") with a badge in a coding agent.
4. No study measures a human's cost of answering a clarifying question.
5. Many visual-prompting results rest on older or open models. Some rest on models from Chinese companies, which this project does not use. The notes mark them.

## Research notes

| Note | Topic |
|---|---|
| 01 | Visual marks, crops, and coordinates |
| 02 | Agents that fix visual issues, and checks of the fix |
| 03 | Locating the code: product prior art and macOS sources |
| 04 | Prompt and handoff structure across vendors and agents |
| 05 | Apple on-device intelligence |
| 06 | Theme synthesis and feedback on AI-made drafts |
| 07 | Affinity and proximity for the agent's own work |
| 08 | Delivery of many captures to chat tools |
