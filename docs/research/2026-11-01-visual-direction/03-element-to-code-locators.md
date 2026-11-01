# Research note 03: Element-to-code locators: product prior art and macOS sources

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

**Outcome:** The only measured gain I found comes from a source file path plus line number, and Nextshot cannot read that from outside the page. Nextshot can cheaply add the page URL, DOM id and class names, role, title, and for documents the file path and page. No study isolates those fields.

### 1. Tool by field
Key: Y = in the source. n = the source lists its fields and omits it. ? = not confirmed. Numbers in brackets point to the source list. Most cells are product claims.

| Tool | Selector | Component | Src file:line | HTML | Styles | URL | Viewport | Logs | A11y |
|---|---|---|---|---|---|---|---|---|---|
| Agentation [4] | Y | Y | Y (dev mode) | part (tag, attributes, nearby text) | Y | Y | n | n | Y |
| React Grab [3] | ? | Y | Y | Y | ? | ? | ? | ? | ? |
| LocatorJS [1] | ? | Y (name only) | n (in benchmark) | ? | ? | ? | ? | ? | ? |
| Vercel Toolbar [5] | Y | Y | n | n | n | Y (path) | Y | n | n |
| Figma MCP [6] | n | Y (Code Connect) | Y (Code Connect) | n | tokens | n | n | n | n |
| Cursor Design Mode [7] | Y | Y | ? | part (id, classes, 200 chars of text) | Y (6) | ? | ? | Y (browser tool) | ? |
| Lovable Visual Edits [14] | ? | ? | Y (build-time ID to JSX) | ? | ? | ? | ? | ? | ? |
| Claude in Chrome [13] | ? | ? | n | Y ("DOM state") | ? | ? | ? | Y (console) | ? |
| Chrome DevTools MCP [8] | ? (uids) | n | n | Y (script) | Y | ? | ? | Y | Y |
| Playwright MCP [9] | Y (generate locator) | n | n | n | n | ? | boxes, opt-in | Y | Y |
| Jam [10] | ? | ? | ? | ? | ? | Y (filter) | ? | Y | ? |
| Marker.io [11] | ? | ? | ? | ? | ? | Y (marketing) | Y | Y | ? |
| Userback [12] | ? | ? | ? | ? | ? | ? | ? | Y | ? |
| BugHerd (search snippets, not opened) | Y | ? | ? | ? | ? | Y | Y | Y | ? |

Not found: SenAnnotate and Markagent (no primary page), AgentEcho (aggregator pages only), MarkUp.io (proxy annotation, no agent handoff found), v0 and Bolt (mirrored v0 docs only). Cursor's own docs conflict with a search summary: the page I opened says "CSS-style selector path", the summary said XPath and props. I trust the opened page.

### 2. Findings, strongest first
| Finding | Evidence | Source | Strength | Implication for Nextshot |
|---|---|---|---|---|
| Path plus line lifts file-finding from 86% to 95-96%. A component name alone stays at 86%. | 330 tasks (page says 331), claude-sonnet-4-6, one trial each, no confidence intervals. No hint: 285 solved, 45.1 s. Path hint: 20.7 to 31.5 s. Name only: 41.8 to 42.8 s. | [1][2] aidenybai, last run 2026-03-15 | Product claim (React Grab's own benchmark) | Name-like locators (AX title, role) probably add little. Only file:line moved accuracy. |
| More fields gave no accuracy gain. | Agentation (selector, styles, ARIA, source) 96% at 31.5 s. React Grab 96% at 20.7 s. | [2] | Product claim | Keep the locator block short. |
| Images help. | SWE-agent JS, Claude 3.5 Sonnet: 16.0% with, 13.0% without. GPT-4o: 11.0 vs 8.0. RAG: 14.1 vs 11.2, and 10.0 vs 8.0. Non-textual images: 13.0 to 8.7 without. Best system overall: 12.2%. | [15] Yang et al., ICLR 2025, Table 4, dev set | Peer-reviewed | Keep the annotated and clean PNGs. Images alone do not locate code. |
| Code-like tokens from a report raise file ranking. | BM25 MAP@1: 0.400 to 0.470 (SWE-bench Lite), 0.158 to 0.247 (Long Code Arena). File names untested. Stack traces did not help. The paper's prose and its Table 3 disagree. | [16] arXiv 2512.07022 | Preprint | Pass exact strings (ids, labels), not paraphrase. |
| Location quality in issue text tracks success. | File-level score 1.326 (resolved) vs 1.052 (unresolved). LLM-scored. | [17] arXiv 2411.10213 | Preprint, correlational | Supports a locator. Proves no cause. |
| Chrome and WebKit expose AXURL (page URL on the AXWebArea), AXDOMIdentifier (HTML id), AXDOMClassList (class names). | Chromium code returns all three. A WebKit layout test lists them on AXWebArea. | [18][19] | Source code, not Apple docs (Chromium revision is old) | Read at each badge point. No extension. Tailwind class lists are weak keys. |
| Chrome and Electron expose page content only when accessibility is on. | Chrome treats AXEnhancedUserInterface as the signal. On Sonoma, a role request with VoiceOver off turns on basic mode. Electron documents AXManualAccessibility for third-party apps. Outlook and Teams ignore both. | [20][21][22] | Official doc, source, forum | Set both attributes on the Chrome and Claude app before the hit test. Expect an empty first read. Test per app. |
| Latency is unmeasured. | "<1 ms" native, "10-50ms+" per query in Chromium and Electron, with no method or sample. Chrome's blog: 5-10% of users have it on, total cost "not yet known". | [23][24] | Anecdote | Budget up to 0.5 s per badge (my arithmetic: 10 queries). Read after Command+S. Measure p95. |
| Two new permission prompts. | Accessibility pane "allows apps to run scripts and system commands to control your Mac". Automation is a separate pane. The Apple Events entitlement lets an app prompt. | [25][26] | Official doc | Use AXURL to skip Automation. Upstream code already calls AXIsProcessTrustedWithOptions in Translation (off by default). |
| URL is easy. Page script and CDP are not. | Chrome: `URL of active tab of front window`. Safari: `URL of front document`. Page JavaScript needs "Allow JavaScript from Apple Events" (Safari asks an admin password, reported flaky). Chrome 136+ ignores --remote-debugging-port on the default profile. | [27][28][29] | Official (Chrome), forum | Take URL from AX or AppleScript. Do not plan on CDP. |
| Document locators are cheap. | AXDocument returns the window's file URL (URL-encoded, saved files only). PDF Creator and Producer name the generator (informational; from search summaries, not opened). PowerPoint normal view: `slide index of slide range of selection of document window 1`. | [30][31][32] | Forum | Path, page, slide, generator are readable. Matching capture text to the PDF text layer for the page is my inference. |

### Local-only check
Stays on the Mac: AX reads, Apple Events to a browser, AXDocument, PDFKit text, PDF metadata. Breaks the written rule: any cloud tool (Jam, Marker.io, Userback, BugHerd, Vercel comments, Figma's remote server at mcp.figma.com [6]) and any socket, including CDP or a localhost server (Agentation posts to localhost:4747 [4]). `NetworkSourceScanTests` would flag both. AX text sent to Jev needs its own consent kind (AGENTS.md). React Grab and LocatorJS live inside the target app, so they do not apply to Nextshot.

### 3. Open questions
1. Does an app-scoped hit test return a real element, not the top web area, in Chrome and the Claude app? A search summary of a Claude app bug report says AXManualAccessibility left the tree empty. I could not open it.
2. For how many of the 131 captures does a repo the agent can open produce the pixels? Claude app (41), PDF (18), and PowerPoint (6) may show third-party or generated content.
3. Can AXValue leak off-screen or password text? I found only a search snippet that Chromium trusts upstream masking. Skip AXValue by default.
4. Would a dev-build plugin that writes file:line into an id or class, read through AXDOMIdentifier, reproduce the file:line gain with no extension? Untested.
5. Does the URL path (route) help an agent find the route file? No study found.

### 4. Three changes to test first
Shared harness: replay 40 or more past captures whose fix commit is known. Run one agent with and without the locator block, 3 trials each. Score the returned file path (react-bench rule), seconds to first correct file, and tool calls. Use a paired test and report intervals, which react-bench lacks.
1. **URL and route.** Add the URL from AXURL, with Automation as fallback, to manifest.md. Measure the share of the 34 Chrome captures that get a URL, and the paired lift.
2. **Element block, shadow first.** Per badge: role, title, AXIdentifier, DOM id, class list, three ancestors. No AXValue, secure fields skipped. Write it to a review file before it enters any prompt, as Jev does. Measure fill rate and p50 and p95 milliseconds per app (Chrome, Safari, Claude app, Preview, PowerPoint, one native app), first call versus later.
3. **Document block.** Add AXDocument path, page or slide, and PDF Producer. Measure the correct-page rate on the 18 Preview and 6 PowerPoint captures, and whether the agent then finds the generator script.

### Sources (all opened unless marked)
[1] aidenybai, react-bench README, github.com, 2026. https://github.com/aidenybai/react-bench
[2] React Grab benchmarks, react-grab.com, 2026-03-15. https://react-grab.com/benchmarks
[3] React Grab README. https://github.com/aidenybai/react-grab
[4] Agentation schema, output, and MCP pages. https://www.agentation.com/schema , /output , /mcp
[5] Vercel, Copy visual context to agents, 2026-02-03. https://vercel.com/changelog/copy-visual-context-to-agents
[6] Figma, MCP server tools; intro. https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/ , https://developers.figma.com/docs/figma-mcp-server/
[7] Cursor, Design Mode and Browser docs. https://cursor.com/docs/agent/design-mode , https://cursor.com/docs/agent/browser
[8] Chrome DevTools MCP tool reference. https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md
[9] Microsoft, Playwright MCP README. https://github.com/microsoft/playwright-mcp
[10] Jam MCP docs. https://jam.dev/docs/jam-mcp
[11] Marker.io, MCP help article and features. https://help.marker.io/en/articles/14034657 , https://marker.io/features
[12] Userback MCP docs. https://docs.userback.io/docs/userback-mcp
[13] Anthropic, Use Claude Code with Chrome. https://code.claude.com/docs/en/chrome
[14] Lovable, Visual Edits. https://lovable.dev/blog/visual-edits
[15] Yang et al., SWE-bench Multimodal, ICLR 2025. https://arxiv.org/abs/2410.03859
[16] Reformulate, Retrieve, Localize, 2025 (authors not read). https://arxiv.org/abs/2512.07022
[17] LLM-based Agents for Automated Bug Fixing: How Far Are We? (authors not read). https://arxiv.org/abs/2411.10213
[18] Chromium browser_accessibility_cocoa.mm, revision edfbdceb. https://chromium.googlesource.com/chromium/src/+/edfbdceb6d2546de4ac8a1da7ff307bb5f6a31d0/content/browser/accessibility/browser_accessibility_cocoa.mm
[19] WebKit layout test. https://raw.githubusercontent.com/WebKit/WebKit/main/LayoutTests/accessibility/mac/document-attributes-expected.txt
[20] Chromium commit 34d5b59, Mac A11y Sonoma. https://chromium.googlesource.com/chromium/src/+/34d5b59a67da7b0ea1a3eb90835467eb63e7262e
[21] Electron, Accessibility tutorial. https://www.electronjs.org/docs/latest/tutorial/accessibility
[22] Apple Developer Forums, thread 756895. https://developer.apple.com/forums/thread/756895
[23] Cotabby issue 209. https://github.com/FuJacob/cotabby/issues/209
[24] Chrome for Developers, Improving the performance of Chromium accessibility. https://developer.chrome.com/blog/chromium-accessibility-performance
[25] Apple Support, Control access to your Mac. https://support.apple.com/guide/mac-help/control-access-to-your-mac-mchl211c911f/mac
[26] Apple, Apple Events Entitlement. https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events.md
[27] Chrome for Developers, remote debugging switches. https://developer.chrome.com/blog/remote-debugging-port
[28] AppleScript gist (ibehnam). https://gist.github.com/ibehnam/c00127071b54b00cbf2e8a67f7b90f63
[29] Apple Developer Forums, thread 100414. https://developer.apple.com/forums/thread/100414
[30] Keyboard Maestro forum, Preview AXDocument. https://forum.keyboardmaestro.com/t/get-preview-window-path/1039
[31] PDF Creator and Producer: search summaries only, not opened.
[32] MacScripter, PowerPoint slide index. https://macscripter.net/t/applescript-to-move-to-next-slide-in-normal-view-in-powerpoint/70815

Gaps: Apple's AXUIElement doc pages render client-side. My fetch returned only titles, so I did not cite them. The header constants and the native-devtools-mcp release (it uses AXUIElementCopyElementAtPosition and returns name, role, label, value, bounds, pid) back the attribute list. I did not verify AXUIElementSetMessagingTimeout. Repo facts come from /Users/drewschulz/Developer/capso/AGENTS.md and App/Feedback/FeedbackWindowTitle.swift (CGWindowListCopyWindowInfo). No file was edited.
