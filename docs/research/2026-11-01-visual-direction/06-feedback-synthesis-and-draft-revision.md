# Research note 06: Theme synthesis and feedback on AI-made drafts

Date: 2026-11-01. A research agent (Sonnet) wrote this note for the visual direction study. It is raw evidence, not a decision. The synthesis is `docs/research/2026-11-01-visual-direction-research.md`. Numbers are as the agent read them; the synthesis marks the findings that were checked by hand.

No source I opened tests the exact Nextshot case: 5 to 14 scattered reviewer notes, turned into themes, then applied to an AI-made draft. The adjacent evidence points one way. Keep all items in one message. Add a themes-then-plan step, but test it, because it is unproven for feedback. Make verification use rendered evidence, not memory. Ask only on real conflicts. Pair each badge with text and a crop.

I read every source below in this session. "Abstract only" means I read just the abstract. Venues marked "per arXiv" come from the arXiv page, not the venue site. I did not edit any file. I read `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift` (lines 285 to 315) to check the current prompt rules.

### 1. Findings (strongest first)

| # | Finding | Evidence (numbers) | Src | Strength | Implication for Nextshot |
|---|---|---|---|---|---|
| 1 | All items in one up-front message beat items given piecemeal. | GPT-4o: Full 93.0, Concat 90.9, Sharded 59.1, Recap 76.6, Snowball 65.3. Mean drop 39% over six tasks. Aptitude fell 16%, unreliability rose 112%. Multi-IF: o1-preview 0.877 at turn 1, 0.707 at turn 3. | S1, S2 | Preprint | The round prompt is already the good "Concat" condition. When a chat continues, resend the full item list, not only the new items. |
| 2 | All-items success falls with item count, though each item is easy. | Claude 3.5 Sonnet, prompt-level: 0.95 at 1 instruction, 0.48 at 10. Per-instruction at 10: 0.93. GPT-4o: 0.94 to 0.21 (per-instruction 0.85). o3-mini at 10: low 0.53, medium 0.64, high 0.78. Long-context accuracy is best at the start and end (S4, no number read). | S3, S4 | Peer-reviewed | Expect a skipped item in rounds of 10 or more. Put the item ledger first and last. Higher reasoning effort helps. The tasks are keyword and format constraints, not edits. |
| 3 | Restate-then-plan prompting helps on reasoning and code. | Rephrase and Respond, GPT-4, mean of 10 tasks: 64.95 to 89.77, but CSQA only +1.36. Step-Back, PaLM-2L: +7% MMLU Physics, +11% Chemistry, +27% TimeQA, +7% MuSiQue. Self-planning: up to 25.4% relative Pass@1 vs direct, 11.9% vs chain of thought (abstract only). Plan-and-Solve targets missing-step errors (abstract only, no number read). | S5, S6, S7, S8 | Peer-reviewed (ICLR 2024, ACL 2023, TOSEM per arXiv), plus 1 preprint | A "state themes and intent, then plan" step is plausible. No source tested it on multi-comment feedback. |
| 4 | LLM theme extraction nears human quality on large corpora. | TopicGPT: harmonic mean purity 0.74 vs 0.64 for the best baseline, against human topics. App reviews: GPT-4 beat rule-based SAFE by 17% F1 zero-shot, +6% with 5 shots. A fine-tuned RE-BERT beat GPT-4 by 6%. LLM-in-the-loop: quality "similar to human coders" (abstract only). | S9, S10, S11 | Peer-reviewed (NAACL 2024, EMNLP 2023 Findings), plus 1 preprint | These are hundreds of items, not 5 to 14 captures. Use one direct call. Require each theme to cite its K.N ids so Drew can check it. |
| 5 | Verification works only with outside evidence. | Self-correction without external feedback "struggles", sometimes worse (abstract only). PPTArena, 3x render-and-fix loop: instruction following 2.36 to 2.84, visual quality 2.69 to 3.21 (0 to 5 scale). TICK checklist self-refinement: +7.8% absolute on LiveBench. | S12, S13, S14 | Peer-reviewed (ICLR 2024), plus 2 preprints | The current Verify says "re-check every item". Strengthen it to a per-item render or crop compare, plus a check that no fix undoes another item. |
| 6 | Feedback placed on the artifact beats chat description. | In-place vs multi-turn at turn 9: MATH-hard/Qwen 0.862 vs 0.928, GPQA/Gemma 0.270 vs 0.532. Chat feedback kept correct parts (CPR above 0.9) but rarely carried fixes into later steps (CTRR below 0.1). 15 experts: in-place won every dimension. | S15 | Preprint (per arXiv: EMNLP 2026) | Marks on the image match the in-place format. The main failure is fixes that do not propagate, which is the theme problem. Collateral damage is not the main failure. |
| 7 | Chat revision adds content. No unintended-edit rate exists for marked spans. | InkSync, 52 participants: major factual errors in 14.8% of documents with chat interfaces vs 6% without. Edits kept granular. Canvas: highlight a passage, then ask to rewrite. HyperEdit names over-editing (abstract only, no rate). | S16, S17, S18 | Preprint, product | For feedback pasted into the chat that made the draft, add: "Edit only the marked spans. Keep other text verbatim. Add no facts." Measure the rate ourselves. |
| 8 | Small marks are misread. | BlindTest: 4 VLMs average 58.07%, Claude 3.5 Sonnet best at 77.84%. Worst when shapes overlap or sit close, near 100% when separated. The tasks include naming the circled letter. Set-of-Mark and ViP-LLaVA (CVPR 2024) support marks as prompts (no numbers read). | S19, S20, S21 | Preprint, peer-reviewed | Pair each badge with text naming its place, plus the item crop. Do not rely on the badge number alone. |
| 9 | Deck and visual edits stay weak at document scale. | PPTArena: 1,340 edits, ChatGPT 2.07 / 2.22 vs PPTPilot 2.57 / 2.69 (0 to 5). 32% of edits depend on other slides. It does not measure untouched content. SWE-bench Multimodal: SWE-agent 12% vs 6%. | S12, S22 | Preprint | Deck feedback needs cross-slide themes and a render check. I found no data on marked-up screenshots. |
| 10 | Models rarely ask without being told. | Ambig-SWE: interaction recovered up to 80% of full-spec performance (Sonnet 3.5), 61% (Sonnet 4). Models almost never interact unprompted. "Knowing but Not Showing": models mostly answer directly (abstract only). | S23, S24 | Preprint | The "ask before you change it" rule may be ignored. Test it with injected conflicts. |
| 11 | Selective asking matches always-asking on accuracy. | Claude Sonnet 4.5 (resolve rate): Hidden 54.80%, single-agent 61.20%, ask-always 70.40% ($1.40 per task), selective multi-agent 69.40% ($3.50), Full 70.80%. When it did not ask, 76.92% resolved. ClarifyGPT: GPT-4 Pass@1 70.96% to 80.80% (10 participants). | S25, S26 | Preprint (per arXiv: EMNLP 2026) | Ask on a real conflict or a missing note. Otherwise decide and list the assumption. |

### 2. Contradictions and open questions

1. **Plan-first has no test on feedback.** Rephrase and Respond gained little on CSQA (+1.36). It also slightly lowered Sports accuracy for GPT-3.5 and Vicuna (no number given). Reasoning models may already plan internally (o3-mini high 0.78 vs low 0.53). A theme could also override a literal item. Keep "the written instruction wins".
2. **Self-check.** S12 says intrinsic self-correction does not help. S13 and S14 show gains with a render or a checklist. Nextshot's Verify sits between them.
3. **Ask vs assume.** Ask-always matched selective asking and cost less per task. The simulated user answers instantly. Nextshot's reviewer has left, so a question costs a round trip. I found no human-subject study of "ask" vs "proceed with a stated assumption".
4. **Unintended edits.** The only direct numbers are InkSync's 14.8% vs 6% factual errors and CPR above 0.9. I found no rate for edits outside a marked span.
5. **Model provenance.** S23, S25, and S15 also use Qwen, Kimi, or DeepSeek models. Every number above comes from Claude, GPT, Gemma, Llama, PaLM, or o3-mini rows. Only Qwen2.5-7B in S15 is a Chinese model, and the GPQA/Gemma gain stands without it. The constraint-following benchmarks test keywords and formats, so transfer to edits is uncertain.

### 3. First three tests in Nextshot

1. **Themes step before the plan table.** Behind a Jev-style flag, add: "List up to 5 themes. Cite K.N ids. A theme never overrides an item. The plan table still lists every item." Use 10 or more past rounds of 5 to 14 captures, with Drew-labeled gold themes, and 2 or more agents. Compare arms by diff and Report lines.
   - **Metrics:** item coverage (done items / total), regressions (items undone or edits tied to no item), and theme recall against gold. Add a second arm where a separate call writes the themes.
2. **Item ledger with evidence-based verify.** Print the ledger at the prompt start and end. Require a render or crop compare per item, plus a "did any fix undo another" check.
   - **Metrics:** skipped-item rate, and all-items success vs per-item success, binned by 1 to 5, 6 to 10, and 11 or more items. Run it against the current prompt.
3. **Chat-bound variant for AI-draft review.** Inline the numbered items. Quote each marked span and attach the annotated image. Add the rules: edit only marked spans, add no facts, list each change per item, and ask only on conflict or a missing note.
   - **Metrics:** use 20 AI drafts (email, report, deck). Measure the edit-distance share of unmarked text that changed, items applied, new facts added, and badge misreads with and without crops. Inject 5 conflicts. Count whether the model asks, and how many assumptions it states.

### Sources

- S1: Laban, Hayashi, Zhou, Neville. "LLMs Get Lost In Multi-Turn Conversation." arXiv 2025. https://arxiv.org/abs/2505.06120
- S2: He et al. "Multi-IF." arXiv 2024. https://arxiv.org/abs/2410.15553
- S3: Harada et al. "When Instructions Multiply." Findings of EMNLP 2025. https://aclanthology.org/2025.findings-emnlp.896/ (numbers from https://arxiv.org/html/2509.21051v1)
- S4: Liu et al. "Lost in the Middle." TACL 2024. https://aclanthology.org/2024.tacl-1.9/
- S5: Deng, Zhang, Chen, Gu. "Rephrase and Respond." arXiv 2023/2024. https://ar5iv.labs.arxiv.org/html/2311.04205
- S6: Zheng et al. "Take a Step Back." ICLR 2024. https://arxiv.org/abs/2310.06117
- S7: Jiang et al. "Self-planning Code Generation." TOSEM per arXiv. https://arxiv.org/abs/2303.06689
- S8: Wang et al. "Plan-and-Solve Prompting." ACL 2023. https://arxiv.org/abs/2305.04091
- S9: Pham et al. "TopicGPT." NAACL 2024. https://arxiv.org/abs/2311.01449
- S10: Shah et al. "How Effectively Do LLMs Extract Feature-Sentiment Pairs from App Reviews?" arXiv 2024/2025. https://arxiv.org/abs/2409.07162
- S11: Dai, Xiong, Ku. "LLM-in-the-loop." EMNLP 2023 Findings per arXiv. https://arxiv.org/abs/2310.15100
- S12: Ofengenden et al. "PPTArena." arXiv 2025/2026. https://arxiv.org/html/2512.03042v3
- S13: Cook et al. "TICKing All the Boxes." arXiv 2024. https://arxiv.org/abs/2410.03608
- S14: Huang et al. "LLMs Cannot Self-Correct Reasoning Yet." ICLR 2024. https://arxiv.org/abs/2310.01798
- S15: Choi et al. "In-Place Feedback." arXiv 2025/2026. https://arxiv.org/html/2510.00777
- S16: Laban et al. "Beyond the Chat (InkSync)." arXiv 2023. https://arxiv.org/html/2309.15337
- S17: OpenAI Academy. "Canvas." https://academy.openai.com/public/clubs/work-users-ynjqu/resources/canvas (product behavior only). I could not open OpenAI's own Canvas page (HTTP 403).
- S18: Zeng et al. "HyperEdit." arXiv 2025. https://arxiv.org/abs/2512.12544
- S19: Rahmanzadehgervi et al. "Vision language models are blind." arXiv (v6, 2025). https://arxiv.org/abs/2407.06581
- S20: Yang et al. "Set-of-Mark Prompting." arXiv 2023. https://arxiv.org/abs/2310.11441
- S21: Cai et al. "ViP-LLaVA." CVPR 2024. https://arxiv.org/abs/2312.00784
- S22: Yang et al. "SWE-bench Multimodal." arXiv 2024. https://arxiv.org/abs/2410.03859
- S23: Vijayvargiya et al. "Interactive Agents to Overcome Ambiguity in Software Engineering (Ambig-SWE)." arXiv v2, 2026. https://arxiv.org/html/2502.13069v2
- S24: Su, Cardie. "Knowing but Not Showing." arXiv 2026. https://arxiv.org/abs/2605.25284
- S25: Edwards, Schuster. "Ask or Assume?" arXiv 2026 (EMNLP 2026 per arXiv comments). https://arxiv.org/html/2603.26233v3
- S26: Mu et al. "ClarifyGPT." arXiv 2023. https://arxiv.org/abs/2310.10996

### Gaps

- I found no study of reviewer-note-to-theme synthesis in small sets, or of marked screenshots applied to a deck.
- I found no human-cost data for clarifying questions.
- I opened but did not use these sources: Apple, "Improving UI Generation Models from Designer Feedback" (CHI 2026 per page), https://machinelearning.apple.com/research/designer-feedback, and Intent Mismatch, https://arxiv.org/abs/2602.07338.
