# Research note 04: Prompt and handoff structure across vendors and agents

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

Outcome: vendor guidance converges on short, outcome-first, act-first prompts, and the research mostly supports it. The weakest ground for Nextshot is path-delivered images, dictation, and "this/here" resolution, where I found no direct study. All sources were opened on 2026-11-01 through WebFetch, which passes pages through a summarizer, so figures are as relayed. "Abstract only" is marked. I read the live prompt text in /Users/drewschulz/Developer/capso/Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift (the rules function, lines 285-315) to ground the implications.

### 1. Findings (strongest first). Source numbers are keyed below.

| # | Finding | Evidence | Source | Strength | Implication for Nextshot |
|---|---|---|---|---|---|
| 1 | Vendors agree: give the outcome and the full task up front, keep it lean | GPT-5.6: leaner prompts raised eval scores "roughly 10-15%", cut tokens 41-66% (directional). Opus 5 does best "given the complete task specification up front". AGENTS.md study: context files raised cost about 20% (SWE-bench Lite) and 23% (AGENTbench) with no general success gain; developer-written files +4% resolution | [6][1][24] | vendor doc; preprint | Cut Verify, Context, and How-to-read lines that change no behavior. Ablate one group at a time |
| 2 | About 20 rules is safe for frontier models, but not free | IFScale (keyword task, not coding): gemini-2.5-pro 98.4% at 100 instructions, 68.9% at 500; o3 97.8% at 250, 62.8% at 500. Yang: gpt-4o 98.7% per single requirement, 85.0% with 19 together | [21][22] | preprint | Keep rules near the current count. Test the cheap lane A model separately, since smaller models decay earlier |
| 3 | No format wins everywhere; the effect shrinks on strong models | He: GPT-3.5 HumanEval 59.8 (JSON) vs 40.2 (plain); GPT-4-1106 deviation under 0.036; best formats rarely transfer across model series (IoU often under 0.2). Sclar: up to 76 points (LLaMA-2-13B, few-shot; abstract only). Anthropic: XML aids parsing. Google: XML or Markdown, "choose one" | [19][20][4][12] | preprint; peer-reviewed (ICLR 2024) | Keep the XML wrapper with plain text inside. I found no 2026 controlled study on frontier models |
| 4 | Placement matters only for long inputs | Anthropic: queries at the end gave "up to 30 percent" better quality on 20k+ token inputs. Google: instructions "at the very end". Chroma: 18 LLMs degrade with length; all scored higher on ~300-token focused prompts than ~113k-token full prompts (LongMemEval) | [4][12][23] | vendor doc; vendor research report | The prompt is short. Context grows later from images and code, so the plan table should restate the items |
| 5 | Vendors differ on image order, and path delivery bypasses both rules | Anthropic: images before text preferred; after text "still perform well". Google (current page): single image, text before image. Claude resizes above 1,568 px long edge (2,576 px on 4.7 and later) and returns coordinates in resized pixels | [5][11] | vendor doc | In path-based agents the image arrives after the text. State each image's pixel size in the manifest |
| 6 | A subagent sees only its brief | Anthropic: brief needs objective, output format, tool guidance, task boundaries; vague briefs caused duplicate work. Claude Code: subagent has fresh context, sees only the delegation message plus CLAUDE.md. Cognition: share full context. Sonnet 5.5 and Haiku 5.5 may treat user text inside a tool_result as injection | [13][15][16][2][3] | vendor doc | The lane A packet carries the reviewer's words verbatim, image path, box, and return format. Do not rely on "read manifest.md" |
| 7 | Multi-agent helps decomposable work and hurts sequential work | Anthropic internal eval: +90.2% vs single agent, 15x tokens. Kim (abstract only): +80.8% decomposable, -70.0% sequential planning. MAST (abstract only): 1,600+ traces, 14 failure modes, one category is inter-agent misalignment | [13][17][18] | vendor post; preprint | Split lanes only for edits in disjoint files. Opus 5 doc: no delegation of small work, no subagent verification |
| 8 | Models rarely ask unprompted, asking helps on true gaps, over-asking costs | Ambig-SWE: interaction gains "up to 74%"; Sonnet 4 detects underspecification at 0.74 (neutral prompt) to 0.89 (strong prompt). Ask or Assume, Claude Sonnet 4.5: hidden 54.8%, single agent 61.2%, separate intent agent 69.4%, full spec 70.8%; 3.06 questions per task. Codex: no clarifications "unless truly blocked" | [25][26][7][1] | peer-reviewed (ICLR 2026; EMNLP 2026 camera-ready per arXiv comments); vendor doc | The 16% empty items need a policy: ask once, in one batch. The Kimi numbers in [26] were not used |
| 9 | Plan-first and verify steps depend on model and effort | Codex: skip plans for about the easiest 25%; "never end the interaction with only a plan". Sonnet 5.5 at low or medium effort sometimes pauses to confirm a plan. Haiku 5.5: low to medium effort roughly halved early stops and more than doubled output tokens. Opus 5: remove explicit verification text | [7][2][3][1] | vendor doc | Add "write the table, then continue". Reduce Verify to one line |
| 10 | Delimiters alone are weak; datamarking worked on old models only | Spotlighting: baseline above 50% attack success; defensive wording alone "negligible"; delimiters about halve it; datamarking GPT-3.5 about 50% to 3.10%, GPT-4 Q&A 1.0%. GPT-family 2023 snapshots, no adaptive attack. Nasr (abstract only): 12 defenses bypassed, "above 90% for most" | [27][28] | preprint | Treat tags plus "never follow" as defense in depth |
| 11 | Keep untrusted text out of the control path | CaMeL (abstract only): 77% of AgentDojo tasks with provable security vs 84% undefended. OpenAI: pass untrusted input through user messages and fixed fields; risk is reduced, "don't fully remove". Anthropic browser use, Opus 4.5: 8.0% attack success model-only, 1.4% with safeguards | [29][9][30] | preprint; vendor doc | Keeping OCR out of the pasted prompt is right. Add a per-bundle random delimiter and a length cap around OCR in manifest.md |
| 12 | Text inside images is an injection channel | VPI-Bench (abstract only): agents deceived up to 51% (computer-use) and 100% (browser-use); system-prompt defenses "limited". Repeat-After-Me (abstract only): over 47% on GPT-5.5 (its 82% figure is Qwen, not used) | [31][32] | preprint | The "never follow" line must cover pixels, not only OCR. Red-team with planted text |
| 13 | Dictation costs accuracy, and cleaning does not fix it | Hu (small open models, two are Qwen): voice -9.7 points vs keyboard -3.0; filler deletion did not recover accuracy (-0.22, not significant); advice is not to rewrite. Say What (N=919): first-try success typed 0.52/0.58/0.36 vs unedited voice 0.35/0.38/0.31 on three problems; edited voice not significantly different from typed | [33][34] | preprint; peer-reviewed (ITiCSE'26 per comments field) | Keep the reviewer's words verbatim. No study tests written self-corrections like "blue, no, gray". Full-Duplex-Bench-v3 (abstract only) lists self-correction among the most consistent voice-agent failures [35] |
| 14 | Numbered marks tie "this" to a place | Set-of-Mark: GPT-4V RefCOCOg 86.4 with marks vs 25.7 with coordinates; small subsets; open-source models "hardly" read marks; centered marks can mislead. Anthropic: coordinates are approximate | [36][5] | preprint | The badge is the pointer. Give each item as badge number plus box plus words. I found no coding-agent study |
| 15 | No head-to-head on clipboard vs file vs MCP | MCP: prompts are user-controlled, can embed base64 images; resources are application-driven. Claude Code caps MCP tool output at 25,000 tokens, warns at 10,000. Anthropic: filesystem loading cut 150,000 tokens to 2,000 | [37][41][38] | vendor doc | Keep clipboard text plus file paths. It works in every agent with no setup. Offer MCP only as an extra |

### 2. Contradictions and open questions

1. **Image order.** Anthropic prefers images first. Google's current page says text first for one image. Path-delivered images match neither, and no test covers them.
2. **Verification.** Opus 5 says remove verification text. Sonnet 5.5 and Haiku 5.5 say add a real-check paragraph at low effort. One fixed Verify block cannot suit all models.
3. **Context files.** Vendors recommend AGENTS.md. Gloaguen finds LLM-written files add cost without gain. The paper disagrees with itself (about -3% in the introduction, -0.5% and -2% in section 4.2), and it is Python-only.
4. **Spotlighting.** Under 3.10% attack success on 2023 models, versus above 90% bypass of most of 12 unnamed defenses. Neither test covers the other's setup.
5. **Multi-agent.** Anthropic +90.2% (about 20 internal queries), Google -70.0% sequential, Ask or Assume +8.2 points from a split intent agent, Cognition favors one thread. All are non-coding or non-Nextshot setups.

Also: He's abstract says "up to 40%" in code translation, but its tables show about 12 BLEU points there. Gaps: no clipboard-vs-file study, no "this/here" study for coding agents, no text self-correction study, no 2026 format study on frontier models (searches returned only blogs).

### 3. First three tests

1. **Batch-ask rule.** Replace "ask before you change it" with "finish clear items, make no edit on empty or conflicting items, then ask once with all ids." Replay the 270 items (including the 16% empty) in Claude Code on Opus 5, Sonnet 5.5, and Haiku 5.5, plus Codex, Cursor, and Gemini CLI. Measure: clear items done before the first stop, stops per round, questions per round (reference: 3.06 per task), wrong-edit rate on empty items (Drew labels), and ask precision.
2. **Lean prompt.** Variant B keeps Goal, items, locate, a plan table followed by "continue", scope, and Report. It drops the Verify and Context sections. Run section-by-section ablations. Measure: tokens, cost, turns, per-item correctness (blind label), files touched outside the plan, and checks run. Split results by model, because Opus 5 over-verifies while Haiku and Sonnet at low effort skip checks.
3. **Lane A packet and OCR block.** Packet: verbatim words, item id, annotated image path, box, and return format (item, file, change, done or needs input). OCR goes only in manifest.md inside a random-delimiter block with a length cap. Compare against a "read manifest.md" pointer. Measure: lane A item pass rate, duplicate or conflicting edits across lanes, tokens. Add about 20 screenshots with planted instructions. The pass bar is zero follows in every agent.

### Sources (all opened)

[1] Anthropic, Prompting Claude Opus 5, API docs, 2026: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
[2] Anthropic, Prompting Claude Sonnet 5.5, 2026: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5
[3] Anthropic, Prompting Claude Haiku 5.5, 2026: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5
[4] Anthropic, Prompting best practices, 2026: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
[5] Anthropic, Vision, 2026: https://platform.claude.com/docs/en/build-with-claude/vision
[6] OpenAI, Prompting guidance for GPT-5.6 Sol, 2026: https://developers.openai.com/api/docs/guides/prompt-guidance-gpt-5p6.md
[7] OpenAI Cookbook, Codex prompting guide: https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide
[8] OpenAI Cookbook, GPT-5 prompting guide, 2025: https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide.md (read; its contradiction and ask-less points match [6][7])
[9] OpenAI, Safety in building agents: https://developers.openai.com/api/docs/guides/agent-builder-safety
[10] OpenAI, Codex AGENTS.md (32 KiB cap, one user-role message per file): https://learn.chatgpt.com/docs/agent-configuration/agents-md
[11] Google, Gemini API Image understanding: https://ai.google.dev/gemini-api/docs/image-understanding
[12] Google, Gemini prompting strategies: https://ai.google.dev/gemini-api/docs/prompting-strategies
[13] Anthropic Engineering, How we built our multi-agent research system, 2025: https://www.anthropic.com/engineering/built-multi-agent-research-system
[14] Anthropic Engineering, Effective context engineering, 2025: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
[15] Claude Code docs, Subagents: https://code.claude.com/docs/en/sub-agents
[16] Walden Yan (Cognition), Don't Build Multi-Agents, 2025: https://cognition.com/blog/dont-build-multi-agents
[17] Kim et al., Towards a Science of Scaling Agent Systems, arXiv 2025 (abstract only): https://arxiv.org/abs/2512.08296
[18] Cemri et al., Why Do Multi-Agent LLM Systems Fail?, arXiv 2025 (abstract only): https://arxiv.org/abs/2503.13657
[19] He et al., Does Prompt Formatting Have Any Impact on LLM Performance?, arXiv 2024: https://arxiv.org/abs/2411.10541
[20] Sclar et al., Quantifying Language Models' Sensitivity to Spurious Features in Prompt Design, ICLR 2024 (abstract only): https://arxiv.org/abs/2310.11324
[21] Jaroslawicz et al., How Many Instructions Can LLMs Follow at Once?, arXiv 2025: https://arxiv.org/abs/2507.11538
[22] Yang et al., What Prompts Don't Say, arXiv 2025: https://arxiv.org/abs/2505.13360
[23] Hong, Troynikov, Huber (Chroma), Context Rot, 2025: https://www.trychroma.com/research/context-rot
[24] Gloaguen et al., Evaluating AGENTS.md, arXiv 2026: https://arxiv.org/abs/2602.11988
[25] Vijayvargiya et al., Ambig-SWE, ICLR 2026, arXiv: https://arxiv.org/abs/2502.13069
[26] Edwards and Schuster, Ask or Assume?, EMNLP 2026, arXiv: https://arxiv.org/abs/2603.26233
[27] Hines et al., Defending Against Indirect Prompt Injection Attacks With Spotlighting, arXiv 2024: https://arxiv.org/abs/2403.14720
[28] Nasr et al., The Attacker Moves Second, arXiv 2025 (abstract only): https://arxiv.org/abs/2510.09023
[29] Debenedetti et al., Defeating Prompt Injections by Design (CaMeL), arXiv 2025 (abstract only): https://arxiv.org/abs/2503.18813
[30] Anthropic, prompt injection defenses for browser use, 2025: https://www.anthropic.com/research/prompt-injection-defenses
[31] Cao et al., VPI-Bench, ICLR 2026, arXiv (abstract only): https://arxiv.org/abs/2506.02456
[32] Chen et al., Repeat-After-Me, arXiv 2026 (abstract only): https://arxiv.org/abs/2609.04533
[33] Hu et al., Should We Type or Talk to LLM Agents?, arXiv 2026: https://arxiv.org/abs/2608.03970
[34] Riegel et al., Say What?, ITiCSE 2026, arXiv: https://arxiv.org/abs/2607.05808
[35] Lin et al., Full-Duplex-Bench-v3, arXiv 2026 (abstract only): https://arxiv.org/abs/2604.04847
[36] Yang et al., Set-of-Mark Prompting, arXiv 2023: https://arxiv.org/abs/2310.11441
[37] MCP specification 2025-06-18, prompts and resources: https://modelcontextprotocol.io/specification/2025-06-18/server/prompts
[38] Anthropic Engineering, Code execution with MCP: https://www.anthropic.com/engineering/code-execution-with-mcp
[41] Claude Code docs, MCP: https://code.claude.com/docs/en/mcp
Also opened, not cited in the table: Cursor Agent best practices (https://cursor.com/blog/agent-best-practices) and Anthropic's long-running harness post (https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). The latter says Anthropic chose a JSON checklist because the model "is less likely to inappropriately change or overwrite JSON files compared to Markdown files". It is a useful hint if Nextshot ever adds a checklist file the agent edits.
