# Research note 02: Agents that fix visual issues, and verification of the fix

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

**Outcome:** The evidence supports sending the marked image together with text and numeric locators, and verifying each item with a bounded render check. It does not support a free-form "take a screenshot and compare" step, and it does not support trusting a model alone to certify that a change was made. I opened every source below. "Abstract only" marks the ones where I read nothing more. Nothing was edited.

### 1. Findings (strongest first)

| Finding | Evidence | Source | Strength | Implication for Nextshot |
|---|---|---|---|---|
| Images help, but gains are small and screenshot tools are not reliably positive | Images necessary in 83.5% of 557 image tasks. Dev split with vs without images: 11.0 vs 8.0 (GPT-4o), 16.0 vs 13.0 (Claude 3.5 Sonnet). Test: SWE-agent with screenshot tools 12.2% vs base 12.0%. Web tools helped GPT-4o (19.6% vs 10.4% correct submissions) and hurt Claude 3.5 Sonnet. Vals, 480 tasks, Oct 29 2026: Claude Opus 5.5 70.21%, Sonnet 5.5 58.33%. No network cost every model 21 to 35 points | S1, S2 | Preprint (2024 models); leaderboard vendor | Keep instruction text and locators. The image alone does not carry the fix |
| Render the patched UI and judge it | GUIRepair, 517 tasks: base 136, +Image2Code 146, +Code2Image 148, both 157. Cost $0.08 to $0.29. Only about 17% of tasks ship reproduction code | S3 | Peer-reviewed (ASE 2025) | The screenshot is the missing reproduction. Use it as the before image |
| Structured render loops help on PDFs and decks | PPTArena (0 to 5): hybrid editing 2.36, with 3-pass render-verify loop 2.84. PaperFit (LaTeX) win rate: single-turn visual 0.295, text 0.280, multi-round visual 0.650, structured loop 0.895. Page-budget hit 0.805 vs 0.549. Render checks found 308 layout defects vs 212 by self-check (DeepPresenter). Failures: master-XML over-editing; one paper grew to 20 pages vs a 16-page target | S5, S6, S7 | Preprints | For PDF or deck code: render, list defects, make one constrained edit, enforce a page or scope check |
| Naive self-refinement from screenshots can degrade output | GPT-5.2 on Design2Code: all 15 rounds below round 0 (ends -2.73). GPT-5.4: 10 of 15 below start. One repair target per round gave +1.20 over naive at round 10 (18 settings). Frontier models show this without Qwen | S8 | Preprint | Bound "re-check every item": one target per round, accept only if other regions stay unchanged |
| A VLM misses most subtle UI changes when it is not told what to check | 4,400 pairs, 13 VLMs. Best recall 40.7% (Gemini 3.1 Pro); Opus 4.7 31.2%; GPT-5.4 30.5%. Hard tier below 23% for all. False alarms 0.4% (Opus 4.7, GPT-5.4). Line-height recall 4.0% (median); pixel size did not predict recall (r = -0.08) | S9 | Preprint | Do not let the model alone certify "done". Add a pixel diff of the marked box |
| Scoped judges agree with people | ArtifactsBench pair accuracy 79.06% no screenshot, 87.10% one, 90.95% several. DesignBench GPT-4o judge 95.54% (359 edits) and 91.89% (111 repairs). Web judge 85.7%; 87.9% with 3 or fewer checkpoints vs 76.3% with more. PPTArena: Pearson 0.72 instruction, 0.81 visual; 78% majority agreement over 5 runs | S10, S11, S12, S5 | Mostly preprint; S12 peer-reviewed (COLM 2025) | Judge each item with 3 or fewer checks, 2 screenshots, repeat runs |
| UI edit and repair fail at finding the code | DesignBench (2025 models): code-only edit 8.40 to 8.43 vs image-only 7.37 to 7.67. Image added to code gave no gain. Repair issue detection 0.2714. Top failures: unnecessary modification, partial edit, wrong edit, no repair attempt | S11 | Preprint | Put file or component hints in the manifest. "Change only listed items" guards the top failure |
| Words plus marks beat marks alone | Interaction2Code (GPT-4o): CLIP 0.3737 image-only, 0.4174 text-only, 0.6735 both. Highlighting raised Gemini IR 0.6738 to 0.7326. VP-Bench: GPT-4o reads points 49.28%, tags 69.95%, arrows 70.27%, boxes 74.18% (human 90.03% average) | S13, S14 | Preprints; S14 extends an AAAI 2026 paper | Badge dots are the weakest cue. Keep center, box, and spoken text. Old models |
| Underspecified items cost about 20 points | 23.7% vs 43.8% resolved (700 tasks). Claude Sonnet 4.5: 70.8% full, 54.8% hidden, 69.4% with an ask step, 70.4% always-ask. Detecting gaps: Sonnet 4 89%, Haiku 3.5 63%. Missing: errors 65%, expected behavior 33% | S15, S16, S17 | Two peer-reviewed (ICLR, EMNLP 2026); one preprint | The 16% empty and 53% deictic items need a flag or question before editing |
| Trackers: images are common, often bare, and their OCR is noisy | 17.10% of 481,603 issues had images. Visual reports are shorter (median 89 vs 103) and get a first comment sooner (0.238 vs 0.389 days). Closure 13.7 vs 15.0 days, effect 0.037 (negligible, correlation only). Android: 56.77% of images have no text; 2 of 42 reports reproduced only after image-to-text. OCR of UI labels: net +1.21% of queries (31.62% improved, 30.41% worsened); code and errors +11.03% and +7.48%. 22.5% of images fail to aid (abstract only) | S18, S19, S20, S21 | Peer-reviewed (venues from file name or arXiv note); S21 abstract only | Pair every image with observed and expected text. OCR under the mark helps only if it is code or error text |
| Gap-filling tools raise completeness but can invent facts | ImproBR (139 reports): complete 7.9% to 96.4%; executable steps 28.8% to 67.6%; wrong-information failures 4 to 19. BugScribe: step quality +44.1% to 82.3% (abstract only). Crash reports: top-1 localization 10.6% to 40.2 to 43.1% (abstract only) | S22, S23, S24 | Preprints | Ground any fill-in in captured state (OCR, box, DOM). Label inferred text as inferred |
| Crops and image size | Crop and grounding tools: 28.6% to 30.0% (+1.4 points, GPT-5.1). Base agent hallucinated DOM attributes on downsampled full-page screenshots. Standard tier: 1,568 px and 1,568 visual tokens (1920x1080 becomes 1456x819). Claude 4.7 and later: 2,576 px, 4,784 tokens. Returned coordinates use the resized image | S4, S28 | Preprint; vendor doc | Manifest pixels must match the image the agent sees. Send item crops. Newer models accept more than the zip's 1,568 px |
| Agents misread intent and misreport | 16,118 validated episodes: 26.95% misread intent (44.10% of those from underspecified instructions), 22.58% inaccurate self-report, 10.20% overreach. Vendor guidance: ask for evidence, "the screenshot" | S25, S29 | Preprint; vendor doc | A "re-check" line is a self-report. Require a crop and a verdict per item |

### 2. Contradictions and open questions

1. **Image vs code.** DesignBench finds code-only at least as good as image-only. SWE-bench M finds images necessary in 83.5% of tasks. DesignBench supplies the code and SWE-bench M does not. Nextshot agents start without the code, but no test isolates this.
2. **Screenshot loops.** GUIRepair gains 15% relative. WebGen-Agent reports 26.4% to 51.9% with Claude 3.5 Sonnet (abstract only, S30). Claude 3.5 Sonnet lost with screenshot tools in S1, and S8 shows decay. I found no test of current agents using free-form self-screenshots in a real repo.
3. **Judges.** Agreement of 87 to 95% (S10, S11) conflicts with 40.7% recall (S9). The first scores a described requirement. The second searches with no hint. I found no test of a judge given marked before and after images plus a one-line instruction.
4. **Report rewriting.** Every tool is measured on completeness or reproducibility. None is measured on agent success afterward. I found no study of dictated notes or "this/here" next to a screenshot.
5. **Comparability.** SWE-bench M splits changed (617, 517, 480 tasks). CodeV (ACL Findings 2025 per search listing; authors not captured, https://arxiv.org/html/2412.17315v1) reports images passed directly at 0.75% vs 11.28% via descriptions. It rests only on Qwen and DeepSeek models, so I did not use it.

### 3. Three changes to test first

1. **Per-item render check with a scope guard.** After the edit, for each item: crop before and after, answer pass or fail on 3 or fewer checks from the instruction, one item per round. Keep an edit only if the item improves and pixels outside all boxes stay near zero. Measure on 40 to 50 real bundles with 3 arms (no check, current prompt, per-item loop). Outcomes: blind human item fix rate, changed pixels outside boxes, tokens and minutes. Hand-label 100 judge verdicts and report precision and recall for "fixed".
2. **Flag before editing empty and deictic items.** Add a "needs reviewer" column to the plan table for items with no instruction, or only "this/that/here" that no OCR or box resolves. Measure item fix rate and wrong-edit rate by class (empty, deictic, full), plus flag rate. Over-flagging on full items should stay under 10%.
3. **Crops, resolution, and locator fit.** Send an item crop at native pixels plus the full image at the model's tier size. Write manifest coordinates in the delivered image's pixel space. Keep OCR only for code and error text. Arms: current, plus crops, plus 2,576 px for 4.7+ models. Measure plan-table file hit rate and item fix rate. Expect about +1.4 points, so use 100 or more items or a paired design. Add a unit check that coordinates map within 1 px.

### Sources (all opened 2026-11-01)

- S1 Yang et al., SWE-bench Multimodal, arXiv 2024. https://arxiv.org/html/2410.03859v1
- S2 Vals AI, SWE-bench Multimodal leaderboard, 2026. https://www.vals.ai/benchmarks/swebench-multimodal
- S3 Huang et al., Seeing is Fixing (GUIRepair), ASE 2025. https://arxiv.org/html/2506.16136v1
- S4 Ma et al., FailureMem, arXiv 2026. https://arxiv.org/html/2603.17826v1
- S5 Ofengenden et al., PPTArena, arXiv 2025. https://arxiv.org/html/2512.03042
- S6 Yu et al., PaperFit, arXiv 2026. https://arxiv.org/html/2605.10341
- S7 Zheng et al., DeepPresenter, arXiv 2026. https://arxiv.org/html/2602.22839
- S8 Xiong et al., Rubrics as Visual-Repair Context (RubSE), arXiv 2026. https://arxiv.org/html/2608.24138
- S9 Zhang et al., DiffSpot, arXiv 2026. https://arxiv.org/html/2605.29615
- S10 Zhang et al., ArtifactsBench, arXiv 2025. https://arxiv.org/html/2507.04952v2
- S11 Xiao et al., DesignBench, arXiv 2025 (v3 2026). https://arxiv.org/html/2506.06251v3
- S12 Xue et al., An Illusion of Progress, COLM 2025. https://arxiv.org/html/2504.01382
- S13 Xiao et al., Interaction2Code, arXiv v3. https://arxiv.org/html/2411.03292v3
- S14 Xu et al., VP-Bench, arXiv 2025. https://arxiv.org/html/2511.11438v1
- S15 Vijayvargiya et al., Asking What Matters, arXiv 2026. https://arxiv.org/html/2604.14624
- S16 Edwards and Schuster, Ask or Assume?, EMNLP 2026. https://arxiv.org/html/2603.26233v3
- S17 Vijayvargiya et al., Ambig-SWE, ICLR 2026. https://arxiv.org/html/2502.13069v3
- S18 Kuramoto et al., Visual Issue Reports, EMSE 2024 (file name). https://posl.ait.kyushu-u.ac.jp/~kamei/publications/Kuramoto_EMSE2024.pdf
- S19 Wang et al., Images in Automated Bug Report Reproduction, MSR 2025. https://arxiv.org/html/2502.15099
- S20 Yeasmin et al., IR-based Bug Localization with Multimedia, ICPC 2025 (file name). https://web.cs.dal.ca/~masud/papers/shamima-ICPC2025.pdf
- S21 Tan et al., ImageR, EASE 2025 (abstract only). https://arxiv.org/abs/2505.01925
- S22 Akyol et al., ImproBR, arXiv 2026 (alphaXiv mirror). https://www.alphaxiv.org/abs/2604.26142.md
- S23 Saha et al., BugScribe, arXiv 2026 (abstract only). https://arxiv.org/abs/2604.01148
- S24 Al Fahim et al., Crash Report Enhancement, arXiv 2025 (abstract only). https://arxiv.org/abs/2509.13535
- S25 Tang et al., How Coding Agents Fail Their Users, arXiv 2026. https://arxiv.org/html/2605.29442v2
- S27 Gandhi et al., PPT-Eval, ICML 2026 (judge Kendall 0.77; GUI agent 45% vs API agent 62% vs human 80%, not in the table). https://arxiv.org/html/2606.31154
- S28 Anthropic, Vision and Coordinates docs. https://platform.claude.com/docs/en/build-with-claude/vision and https://platform.claude.com/docs/en/build-with-claude/vision-coordinates
- S29 Anthropic, Best practices for Claude Code. https://code.claude.com/docs/en/best-practices
- S30 Lu et al., WebGen-Agent, arXiv 2025 (abstract only). https://arxiv.org/abs/2509.22644

Gaps: I found no benchmark of annotated-screenshot-to-code on an existing repo beyond the ones already in your evidence base. I found no study of voice-dictated notes with screenshots. I found no independent measure of element locators; the Agentation claim of fewer iterations (https://reactdevelopment.substack.com/p/how-agentation-cut-claude-code-ui) has no data.
