# Research note 08: Delivery of many captures to chat tools

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

## Bottom line

No single option wins on both model fidelity and transport.

- Official docs prove limits and PDF handling for Claude, Gemini and the OpenAI API.
- Nothing I found proves that one macOS paste can carry text plus several images, or a PDF, into a web chat. Browser clipboard formats are narrow, and the Finder file paste evidence is old community reports.
- Per-message caps are below 28 (14 annotated plus 14 clean): claude.ai allows 20 images, Gemini Apps allows 10 files.
- Inference, not tested: the safest paste is self-sufficient text plus at most one image.

## 1. Tool by capability (as of 2026-11-01)

| Tool | Images per message | PDF page images read | Local stdio MCP | Paste of text plus files |
|---|---|---|---|---|
| claude.ai and Claude desktop (help does not separate them) | 20 per message (S1). Help says "20 files per chat" (S3). | Yes for PDFs of 100 pages or fewer (text plus visuals). Text only for 101 to 1000 pages (S3). | Desktop: yes, via .mcpb extensions (S11). Web: not verified. | Image paste and drag are documented (S3). Text plus image: unknown. Long text paste can reach the model empty (row 4). |
| ChatGPT web | 20 files per message since 2026-02-13 (secondary sites, unconfirmed). 20 MB per image (search excerpt of the help page). | API: yes, text plus page images (S6). Chat: unconfirmed. Excerpts say Visual Retrieval is Enterprise only. | No. Web uses remote MCP only (S8). | Community: text and image pasted together (Windows, 2024) (S17). Long text becomes pasted.txt (S18). |
| ChatGPT desktop (macOS) | Unknown | Unknown | Yes in the Codex surface, STDIO supported (S8). Regular chat: not stated. | Unknown |
| Gemini app | 10 files per prompt, any mix (S4) | App: not stated (S4). API: yes, native vision, 50 MB or 1000 pages, 258 tokens per page (S5). | App: no evidence. Gemini CLI: yes, images sent inline (S10). | Help documents drag and paste only for Gemini in Chrome (S4). |
| Cursor | No number in docs | Unknown. Docs list image files only. | Yes. Returned images are attached to the chat (S9). | Community and staff: attach button and drag work, Cmd+V is flaky (S16). |
| Codex app and CLI | No number in docs | Unknown | Yes. Desktop app, CLI and IDE share config (S8). Image results reach the model since PR #5600, 2025-10-27 (S12). | IDE: drag or paste (S15). CLI: drag the file. |

The OpenAI help pages (help.openai.com) returned HTTP 403. Their numbers come from search excerpts, not from pages I opened.

## 2. Findings, strongest first

| Finding | Evidence | Source | Strength | Implication for Nextshot |
|---|---|---|---|---|
| 1. Image caps are below 28 | claude.ai 20 images per message. Gemini Apps 10 files per prompt. API: more than 20 images forces a 3,000 px per-image limit. | S1, S4 | High | Drop clean images from chat paste. A 14-capture round exceeds Gemini's 10. |
| 2. PDFs are read as page images plus text | Claude renders each page to an image and extracts text. It costs 1,500 to 3,000 text tokens per page, plus image tokens. OpenAI API sends text and page images. Gemini uses native vision. | S2, S3, S5, S6 | High for Claude, Gemini API, OpenAI API. Unknown for ChatGPT chat. | A PDF works on Claude and Gemini. It is unproven on ChatGPT chat. |
| 3. Each image has its own size budget | Claude: 2,576 px and 4,784 visual tokens (Claude 4.7 and later). Other models: 1,568 px and 1,568 tokens. OpenAI "high": 2,500 patches. Claude says downscaling can make text less legible. | S1, S7 | High | A sheet shares one budget. My arithmetic, assuming 640x420 px cells: about 12 cells fit at full scale on the 2,576 px tier, but only about 4 on the 1,568 px tier. |
| 4. Long text paste can fail silently | Claude desktop and claude.ai turn long paste into a chip. The model gets an empty attachment. Open since 2026-07-15, latest comment 2026-10-09. Cmd+Shift+V avoids it. ChatGPT converts long paste to pasted.txt (Dec 2025). | S13, S18 | Medium (community reports, many reproductions) | Keep pasted text short, with instructions first. Test the threshold. |
| 5. Labels must be in the pixels | Anthropic advises a text label before each image. OpenAI says file names and metadata are not processed. Claude does not read image metadata. Marks improve GPT-4V grounding (abstract only). | S1, S7, S19 | High (docs), Medium (SoM) | Burn "K.N" and a header into each image. Do not rely on file names or order. |
| 6. Small text needs resolution | GPT-4o and Gemini 2.0 Flash match OCR near 300 ppi and drop sharply below 150 ppi (single characters). In VisualOverload (InternVL3), OCR tracks resolution strongly. | S20, S21 | Medium (narrow tasks) | Keep sheet cells near 1x point scale. Do not shrink a retina crop by more than half. |
| 7. Composite versus separate is mixed | ReMI (Gemini 1.5 only): separate images gain 19.8% on interleaved tasks, 4.9% on others. RealBench: closed models "generally perform worse" on composites. Its own table shows GPT-4o rising 65.33 to 71.81 and Qwen-VL-Max falling 82.94 to 7.76. MIMIC (open models): stitching "similar or slightly better". | S22, S23, S24 | Medium-low (2024 models, mixed) | No proof that a sheet beats separate images. No proof it fails for per-item tasks. |
| 8. More images degrade cross-image tasks | MileBench (22 models): the gap widens with image count. MuirBench: best model GPT-4o 68.0%. MIMIC: drop tracks sequence length. LLaVA-OV falls 79.0% to 66.5% with 34 distractors. | S25, S26, S24 | Medium (benchmarks of cross-image reasoning; open models) | Each item must stand alone in text. Do not require comparing images. |
| 9. Grids work for coarse tasks | IG-VLM: a frame grid beat prior zero-shot methods on 9 of 10 video QA sets (abstract only). | S27 | Low (video, not text-dense UI) | Weak support for a text-dense sheet. |
| 10. MCP image results are unreliable in Claude | One report: the model sees the image. Another (2026-08-01, open): "empty image slots" on claude.ai and Claude desktop. It works on Claude Code. Cursor, Gemini CLI and Codex handle images. | S14, S9, S10, S12 | Medium-low (community) | MCP is weakest on the chat apps that need it. |
| 11. Browser clipboard is narrow | MDN: paste exposes clipboardData and files. A paste inspector author reports browsers expose mostly text/plain, text/html and sometimes image/png. | S28, S29 | Medium-low | A PDF on the pasteboard probably never reaches a web chat. |
| 12. Finder multi-file paste is unproven | Apple: a pasteboard holds several items, each with several representations. Community: Chrome pasted non-image files as names only (2019, Chrome 76). Obsidian pasted names (2021 to 2022). | S30, S31, S32 | Low | Do not plan on file-URL paste. Test it. |

## 3. Ranking

1. **Self-sufficient text plus one item sheet, in one paste (hardened option 2).**
   - Only this shape matches what documents and reports show crossing a single paste.
   - It counts as one image against every cap.
   - The text carries each instruction, so a dropped image costs context, not meaning.
   - Cap cells by tier (finding 3). Drop absolute paths from the chat text.
2. **Text plus separate annotated images (option 3).**
   - Best fidelity: each image gets its own budget.
   - Rank 1 if hand test T2 passes.
   - The cap is 10 on Gemini, so overflow needs a sheet.
3. **One PDF per round (option 1).**
   - Claude and Gemini read page images.
   - ChatGPT chat is unproven.
   - It needs an attach or drag, so it breaks "one paste".
   - It doubles tokens on Claude.
4. **Local MCP (option 4).**
   - Needs per-client setup and a model-triggered tool call.
   - ChatGPT web is remote only, which would need a hosted server.
   - The Claude desktop image bug adds risk.
   - It adds nothing for agents that read files.

## 4. Hand tests on the Mac (Chrome, Safari, each desktop app)

| Test | Expected result |
|---|---|
| T1. One pasteboard item: 300-character text plus one 2000 px PNG. Paste in claude.ai, ChatGPT, Gemini, both desktop apps, Cursor, Codex. | Chrome: text and one image chip, as in the ChatGPT report. Safari: text may be dropped when an image is present (WebKit policy from a search excerpt, not opened). Record each case. |
| T2. Three to four separate image items on one pasteboard. | Unknown. My guess: web apps attach one image or none. Count the chips. |
| T3. Copy three PNGs in Finder, then Cmd+V. | Unknown. Chrome may paste file names only (old reports). Cursor and Codex may attach. |
| T4. 5,000-character text plus image. Ask "quote the last line". | A Pasted content chip. Claude may answer "empty" (open bug). Repeat with Cmd+Shift+V. |
| T5. Render a 14-cell sheet. Ask each tool to read the 12 px label in cell 9 and the badge number. Compare with the same crop sent alone. | Sheet fails on 1,568 px tier models. It passes on the 2,576 px tier. |
| T6. Drag a 14-page PDF whose answer is only in a page image. | Claude and Gemini answer. ChatGPT chat: unknown. |
| T7. Claude desktop with a test MCP tool returning a PNG. Ask for text in the image in the same turn. | May show a blank image (reported 2026-07-14). |

## 5. Not confirmed

- OpenAI help pages (403): ChatGPT per-message count, PDF image reading, image limits.
- ChatGPT desktop chat behavior, and whether it is native or Electron.
- Gemini app PDF handling and web drag from disk.
- Any official statement on Chrome or Safari handling a multi-item pasteboard.
- Cursor and Codex image-count limits.
- Frontier-model results for composite versus separate (the studies use 2024 or open models).
- Claude desktop limits equal claude.ai limits: assumed.
- Summaries came from a fetch tool. Some arXiv entries are abstract only (S25, S26, S27).

## Sources (all opened this session unless noted)

- S1 Anthropic, "Vision," Claude API docs, 2026: https://platform.claude.com/docs/en/build-with-claude/vision
- S2 Anthropic, "PDF support," 2026: https://platform.claude.com/docs/en/build-with-claude/pdf-support
- S3 Anthropic, "Uploading files to Claude," Help Center: https://support.claude.com/en/articles/8241126-uploading-files-to-claude
- S4 Google, "Upload and analyze files in Gemini Apps," Gemini Help: https://support.google.com/gemini/answer/14903178
- S5 Google, "Document understanding," Gemini API docs: https://ai.google.dev/gemini-api/docs/document-processing
- S6 OpenAI, "PDF inputs": https://developers.openai.com/api/docs/guides/pdf-files
- S7 OpenAI, "Images and vision": https://developers.openai.com/api/docs/guides/images-vision
- S8 OpenAI, "MCP," learn.chatgpt.com: https://learn.chatgpt.com/docs/extend/mcp
- S9 Cursor, "MCP": https://cursor.com/docs/context/mcp
- S10 Google, "MCP servers," Gemini CLI docs: https://geminicli.com/docs/tools/mcp-server/
- S11 Anthropic, "Getting started with local MCP servers on Claude Desktop": https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop
- S12 openai/codex issue #4819 (closed 2025-10-27): https://github.com/openai/codex/issues/4819
- S13 anthropics/claude-code issue #77946 (community report, open): https://github.com/anthropics/claude-code/issues/77946
- S14 anthropics/claude-ai-mcp issue #238 (community, open) https://github.com/anthropics/claude-ai-mcp/issues/238 and claude-code #53256: https://github.com/anthropics/claude-code/issues/53256
- S15 OpenAI, "Prompting," learn.chatgpt.com: https://learn.chatgpt.com/docs/prompting
- S16 Cursor forum threads (community and staff, 2026): https://forum.cursor.com/t/cursor-agent-cli-and-cursor-ide-chat-composer-image-attach/166119 and https://forum.cursor.com/t/file-pasting-and-dragging-in-cursor-3-1/158186
- S17 OpenAI Community, "How to prevent ChatGPT from pasting images every time I paste text?" (community, 2024 to 2026): https://community.openai.com/t/how-to-prevent-chatgpt-from-pasting-images-every-time-i-paste-text/995476
- S18 OpenAI Community, "ChatGPT converts pasted text to file attachment" (community, Dec 2025): https://community.openai.com/t/chatgpt-converts-pasted-text-to-file-attachment/1369430
- S19 Yang et al., "Set-of-Mark Prompting," arXiv 2023 (abstract only): https://arxiv.org/abs/2310.11441
- S20 Inoue, "Context-Independent OCR with Multimodal LLMs," arXiv 2025: https://arxiv.org/abs/2503.23667
- S21 Gavrikov et al., "VisualOverload," arXiv 2025 (CVPR 2026 per page): https://arxiv.org/abs/2509.25339
- S22 Kazemi et al., "ReMI," arXiv 2024: https://arxiv.org/abs/2406.09175
- S23 Zhao et al., "RealBench," Findings of EMNLP 2025: https://arxiv.org/abs/2509.17421
- S24 Das et al., "More Images, More Problems? (MIMIC)," arXiv 2601.07812, Jan 2026: https://arxiv.org/abs/2601.07812
- S25 Song et al., "MileBench," arXiv 2024 (abstract only): https://arxiv.org/abs/2404.18532
- S26 Wang et al., "MuirBench," arXiv 2024 (abstract only): https://arxiv.org/abs/2406.09411
- S27 Kim et al., "An Image Grid Can Be Worth a Video (IG-VLM)," arXiv 2024 (abstract only): https://arxiv.org/abs/2403.18406
- S28 MDN, "ClipboardEvent.clipboardData" and "DataTransfer.files": https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent/clipboardData
- S29 Evan Wallace, "Clipboard test" (community tool): https://madebyevan.com/clipboard-test/
- S30 Apple, "Pasteboard Programming Guide," archive: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/PasteboardGuide106/Articles/pbReading.html
- S31 Discourse Meta, "Google Chrome Mac pasting files broken" (community, 2019): https://meta.discourse.org/t/google-chrome-mac-pasting-files-broken/124636
- S32 Obsidian Forum, "macOS pastes file names from Finder" (community, 2021 to 2022): https://forum.obsidian.md/t/macos-pastes-file-names-from-finder-instead-of-adding-files-to-notes/17198

Not opened: help.openai.com pages (403), WebKit commit page (403), claudeissues.com mirrors (DNS failure). I edited no files.
