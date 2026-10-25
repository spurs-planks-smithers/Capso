# Nextshot onboarding video

An 82-second video that shows Nextiva colleagues what Nextshot does: mark up screens, keep many screens and notes in one round, and hand the whole round to an AI coding agent as one prompt. It plays on nextshot.dev beside the download button, and in email and Teams.

Four cuts exist:

| Cut | File | What it is |
|---|---|---|
| v3.2 (2026-10-24) | `build/releases/Nextshot-onboarding-2026.10.24.mp4`, poster `Nextshot-onboarding-poster.png` | v3.1 with the Mark line changed: the editor now opens on the red dot tool, so no C key comes first (Drew, 2026-10-24). Line h says "Click to drop a red dot on each issue." The C keycap and its key sound are gone. The silent cue `mark_click` starts the cursor, and the dots pop on "drop", "dot", and "each". The hand-off menu says "Round: feedback" and "All Rounds...", as the app does. The end card says "Stop trying to describe fixes to your agents. Start giving visual feedback. One-click handoffs built for LLMs." on three lines (Drew, 2026-10-24). 81.7 seconds. nextshot.dev serves it since 2026-10-24. |
| v3.1 (2026-10-24) | `build/releases/Nextshot-onboarding-2026.10.24-v3.1.mp4`, poster `Nextshot-onboarding-poster-v3.1.png` (copies kept before the v3.2 render wrote the dated name) | Drew's v3.1 notes: the round concept, new lines 4 to 6 and 8 to 13, a package screen with research, licensed stock music, and the call to action "Get it at nextshot.dev". Then two creative director review rounds. 82.4 seconds. nextshot.dev served it on 2026-10-24 until v3.2. |
| v3 (2026-10-23) | `build/releases/Nextshot-onboarding-2026.10.23.mp4`, poster `Nextshot-onboarding-poster-v3.png` | Drew's storyboard notes on v2: his script, the OpenAI voice sage, and a style that moves from a rough yellow sketch to the brand look. 70.4 seconds. |
| v2 (2026-10-22) | `build/releases/Nextshot-onboarding-2026.10.22.mp4`, poster `Nextshot-onboarding-poster-v2.png` | The 36-second cut with Ava (Premium). It went out with the launch email and the email GIF. |

Beside v3.1 sit two music options on the same picture, `Nextshot-onboarding-2026.10.24-musicB.mp4` and `-musicC.mp4`, and a sheet of six tagline options, `Nextshot-onboarding-tagline-options.png`.

Git ignores `build/`. The render names each file by the date of the HEAD commit, so a new day's render never overwrites an older cut.

## Files

| Path | What it is |
|---|---|
| `scripts/video/nextshot-onboarding/script.json` | The voiceover lines, read directions, tempos, caption splits, pauses, the music track, and named cues (moments the picture and the sound effects share) |
| `scripts/video/nextshot-onboarding/make_audio.py` | Makes the voice clips and sound effects, and mixes them with the music. Writes `audio/final.wav`, `timing.json`, and `timing.js` |
| `scripts/video/nextshot-onboarding/check_voice.py` | Transcribes every voice clip with OpenAI Whisper and fails when a clip differs from its script line |
| `scripts/video/nextshot-onboarding/check_edges.py` | Fails when a voice clip starts or ends on sound (first and last 20 ms must be below -50 dB) |
| `scripts/video/nextshot-onboarding/index.html` | The HyperFrames composition: all seven scenes on one GSAP timeline that reads `timing.js` |
| `scripts/video/nextshot-onboarding/render.sh` | Runs everything and writes the video and the poster to `build/releases/` |
| `scripts/video/nextshot-onboarding/make_poster.mjs` | Makes the nextshot.dev poster still: the lemonade page with its dots and the open Nshot menu (see `docs/site.md`, Poster) |
| `scripts/video/nextshot-onboarding/make_gif.py` | Renders the composition in GIF mode and cuts the email GIF (see "Email GIF") |
| `scripts/video/nextshot-onboarding/assets/` | Fonts: Permanent Marker (Apache License 2.0) and Patrick Hand (SIL Open Font License) for the sketch, Inter (SIL Open Font License) for the brand look. GSAP, Rough.js, the Nextshot icon. |
| `scripts/video/nextshot-onboarding/assets/music/` | The three Mixkit tracks. Not in git (see "Music"). |
| `scripts/video/nextshot-onboarding/storyboard/build_storyboard.py` | Builds the storyboard review page and its PDF from the files above (see "Storyboard review page") |
| `scripts/video/nextshot-onboarding/storyboard/shots.json`, `template.html` | The page's hand-written text (what each line shows, scene jobs, cue names) and its design |

`audio/` (with the speech cache `audio/tts-cache/`), `renders/`, `timing.json`, `timing.js`, and `node_modules/` are generated. They are not in git.

## Script and storyboard (v3.2)

| Time | Voiceover | Picture |
|---|---|---|
| 0 to 5.0 s | (1 s of picture and music first) "So, you and AI just built a lemonade stand." | Yellow paper, marker strokes. The stand's web page is drawn from the first frame ("Lemonaid", "$9 a cup", a tiny Buy button). A robot labeled "AI" and a stick figure labeled "you". Then an app, legal docs, an email, and a flyer pop in with hand-written labels. |
| 5.0 to 32.4 s | "But AI output is far from perfect. Small things are wrong everywhere. So you screenshot. Crop. Paste. Prompt. But with so many fixes, big and small, on so many screens, how do you give AI every direction? Page after page. Prompt after prompt. Into AI eternity. Why can't I gather all my feedback in one round, and give it to AI in one prompt?" | Seven red dots pop on the mistakes. A screenshot, crop marks, the crop drops into an AI chat, and a messy prompt types out. Four more AI chats stack up, a tally climbs, and pages pile up. Then the dots gather, a teal circle labeled "1 round" draws around them, and an arrow points to one box, "1 prompt". |
| 32.4 to 36.2 s | "Now you can. Introducing Nextshot." | The circle closes in, and the dots become the Nextshot icon. A teal circle wipe turns the scene graphite, then the name rises in. |
| 36.2 to 47.2 s | "Hit Option Shift F. Grab the area you want to give feedback on. Click to drop a red dot on each issue. Then say what should change." (v3.2. Until v3.1 it said "Hit C, then click to drop a dot on each issue.") | Step labels "1 Grab" and "2 Mark". Keycaps for Option Shift F (no C keycap since v3.2), the selection, the cursor dropping dots 1 to 3, Command+S with "saves the capture", and the note panel with its real question text and a preview of each dot. The menu bar shows "Nshot (1)" with the green round dot. |
| 47.2 to 56.0 s | "Then grab the next screen, and the next. Circles, boxes, arrows, notes. One round holds it all." | Step label "3 Repeat". A Checkout capture gets a circle and a box. A Flavors capture gets a circle, an arrow, and a general note. On "round", a teal "Round" outline moves to the center and every capture flies into it. "Nshot (3)" shows enlarged. |
| 56.0 to 75.9 s | "One click, one paste, and AI gets the whole round. Every screen, every dot, every note. Any AI agent gets one prompt, built the way AI reads: numbered dots, a note on each dot, exact pixels, and a plan before it edits." | Step label "4 Hand off". The Nshot menu zooms in, and the cursor clicks "Copy Prompt and End Round". The round ends. "One round. One prompt." in large brand type, then "3 screens", "6 dots", "7 notes". The agent gets one message, then a "Built the way AI reads" panel adds one row per spoken part, with a research footnote. Last, silent, the agent's plan table builds and checks three items. |
| 75.9 to 81.7 s | "Nextshot. Show AI what you mean." | The opening sketch returns and wipes into the fixed stand as a clean brand page with teal checks. The end card: icon and name, the tagline with a teal rule, "Stop trying to describe fixes to your agents. Start giving visual feedback. One-click handoffs built for LLMs." (v3.2. Until v3.1 it said "Visual feedback for AI coding agents, on your Mac."), a "Get it at nextshot.dev" button, and the start keys. |

## Specs (v3.1)

- 1920 by 1080, 30 fps, H.264 yuv420p, AAC audio, faststart (the index comes first, so the file streams).
- 82.4 seconds, 13.3 MB.
- Loudness: -16.2 LUFS integrated (loudness units relative to full scale, the common web target), true peak -1.8 dB.
- Burned-in captions, one line each, 46 characters at most. Teams and Outlook start video muted. No caption runs under the end card, which carries its own words.
- Voice: OpenAI `gpt-4o-mini-tts-2025-12-15`, voice sage. Each clip is sped up 0 to 18% (pitch kept): `voice.tempo` is 1.1, and a line can set its own `tempo`. Sound effects are made in Python from the standard library.

## Music

- The bed is "Curiosity" by Diego Nava, from Mixkit, under the Mixkit Stock Music Free License (mixkit.co/license/#musicFree). Drew chose licensed stock music on 2026-10-24, after he called the old plucked-string bed "terrible".
- The license allows the track inside a video. It does not allow sharing the file by itself, so the MP3s stay out of git. Download them again into `assets/music/` from the `source` links in `script.json`.
- Options B ("Pop Track 03" by Lily J) and C ("Lo-Fi 04" by Lily J) are in `music.options`. Drew kept A on 2026-10-24.
- `site/deploy.sh` publishes the newest main cut and skips the music option cuts. `make_audio.py --music <file> --out final-musicB.wav` mixes an option on the current timing and leaves `timing.json` alone.
- The mix backtimes the track, so it ends with the video. The track fades in over 1 second and out over 2.5 seconds. It sits 17 LU under the voice and effects, and it ducks (drops) while the voice speaks. A limiter and two-pass loudness normalization finish the mix.

## Rebuild it

```bash
NODE_ENV=development npm install --prefix scripts/video/nextshot-onboarding
```

```bash
scripts/video/nextshot-onboarding/render.sh
```

```bash
python3 scripts/video/nextshot-onboarding/check_voice.py
```

```bash
python3 scripts/video/nextshot-onboarding/check_edges.py
```

- The voice needs the Keychain item `OPENAI_API_KEY_NEXTSHOT`, a project key Drew stored on 2026-10-23. The scripts read it in memory and never print it. `make_audio.py --say` builds a test mix with the Mac voice Ava (Premium) and needs no key.
- The mix needs the music file named in `script.json` (see "Music").
- Each clip is cached in `audio/tts-cache/` by model, voice, direction, text, and take, so a re-render buys no audio it already has.
- The install needs `NODE_ENV=development`, because Drew's shell exports `production`.
- A render takes about five minutes. The blur behind the package screen turns off HyperFrames' fast capture. It needs Node 22 or later and ffmpeg.
- HyperFrames telemetry is off on m5pro (`hyperframes telemetry disable`). Turn it off on any other Mac before the first render.
- To check frames without a full render, use `node_modules/.bin/hyperframes snapshot . --at 12.5,20 --describe false`. Without `--describe false`, the snapshot sends frames to Gemini when `GEMINI_API_KEY` is set.

## Email GIF

`build/releases/Nextshot-onboarding-hero.gif` is a 24-second cut of the video for the launch email: 640 by 360 pixels, 12 frames per second, one 255-color palette, about 1.2 MB. It goes into the email as an inline attachment with a content id, and the email wraps it in a link to the full video.

```bash
python3 scripts/video/nextshot-onboarding/make_gif.py
```

- `--no-render` reuses the last GIF-mode render in `renders/gif-source.mp4`.
- GIF mode is a composition variable (`--variables '{"gif":"on"}'`). It raises the captions to 66 pixels, one third of the frame's width maps to the GIF, so they read at 22 pixels there. It also drops the captions over the end card, which carries its own words.
- The ffmpeg on m5pro has no subtitle filter and no text filter, so the captions come from the composition, never from ffmpeg.
- The segments are cut at cue times from `timing.json`, so a script change moves them with the voice.
- The first frame must stand alone: classic Outlook on Windows shows only the first frame of an animated GIF. Outlook for Mac, the new Outlook for Windows, Outlook on iPhone and Android, Apple Mail, and Gmail play the loop.
- Keep the file under about 3 MB. A larger GIF slows the email on a phone.
- The GIF is cut from v2. `make_gif.py` still names v2 cues (`squint`, `tally`, `chip_any`, and others), so it stops on v3 and later until its segments use the new cue names. Cut a new GIF only on request.

## Storyboard review page

Drew reviews each cut on one page and leaves notes on every voice line. The page is a private claude.ai artifact, first published 2026-10-23: https://claude.ai/artifact/7FfwHyYeL63MeLAp1yc46k. It shows cut v3.1 since 2026-10-24. It puts four standard review formats in one place: an AV script (what you hear beside what you see), a storyboard (two frames per voice line), a timeline (scenes, voice, sounds, music), and timecoded notes. A plain-English glossary explains the editing terms.

```bash
python3 scripts/video/nextshot-onboarding/storyboard/build_storyboard.py --pdf
```

- Run it after each `render.sh`. It uses the newest main cut in `build/releases/` and skips the music option cuts. It stops when `timing.json` is newer than that MP4, and when `script.json`, `timing.json`, and `shots.json` disagree on the lines, scenes, or cues.
- It writes `build/releases/storyboard/`: `page.html` for the artifact, `local.html` for a browser and the PDF, `video.mp4`, and `frames/`. With `--pdf` it also writes `build/releases/Nextshot-onboarding-storyboard.pdf` (Letter, two cards a page, printed by Chrome).
- `shots.json` holds the hand-written parts: what each line shows, each scene's job and look, the cue names, and the Frame.io link. A line can pin its two frames with `"frames": [0.3, 0.75]`, as fractions of the time from its start to the next line.
- Republish: bump `version` in `shots.json`, build, then publish `build/releases/storyboard/page.html` to the artifact URL with `video.mp4` and `frames/*.jpg` as files (root `build/releases/storyboard`).
- Run the `pdf-polish` wrap check on `local.html` at 816, 1024, 1280, 1440, and 1600 pixels after a text change. The glossary is one column, so its short definitions stay on one line at every width.
- Notes live in the artifact's database, collection `notes`: one document per line id (`built`, `flawed`, `loop`, and so on) plus `overall`. Fields: `verdict` (keep, change, or cut), `rewrite`, `words`, `picture`, `timing` (`overall` has `whole` and `sound`), `cut`, `updated`. Claude reads them with the ArtifactData tool, answers in `reply`, and sets `status` to `done` when the change ships. The page shows the reply under the note.
- Opened as a local file, the page saves notes in that browser only, and Chrome's Save Page As drops typed notes. "Copy all notes" gives plain text either way. Drew's v2 notes came in that way on 2026-10-23, so review on the claude.ai link instead.
- A local preview needs a server with byte-range support, or the video cannot seek. Python's `http.server` has none.

## Change it

- **Words:** edit a line in `script.json` and render again. The audio sets every time, so the picture follows.
- **Timing:** a cue names a line, and optionally a word in it and an offset in seconds. Word times are estimates, proportional to the characters before the word.
- **Read:** each line has a `direction` that the OpenAI voice follows, on top of the shared `voice.style`. A new `take` number asks for a fresh reading of one line.
- **Pace:** the voice reads slower than its directions ask. `voice.tempo` (ffmpeg `atempo`, which keeps the pitch) speeds every clip, and a line can set its own `tempo`. `voice.max_gap` caps the pauses inside a line, and a line can set its own `max_gap`. `voice.breath_db` sets the level under which a stretch of 0.35 s or more counts as a breath and gets cut.
- **Tagline:** the end card's teal rule measures the tagline, so any tagline gets a rule of its width. The spoken tagline is part of the line `tagline`.
- **Check:** run `check_voice.py` and `check_edges.py` after every audio change. A level cut that goes too far turns a word into another word ("prompt" became "cropped" at a 0.15 s pause cap).
- **App text:** the rebuilt screens copy strings from the app. Check them against the source after any change to the feedback UI:

| Screen in the video | Source |
|---|---|
| Note panel question, placeholder, and help line | `App/Feedback/FeedbackNotePanel.swift` |
| General note question | `App/Feedback/FeedbackNotePanel.swift` |
| Nshot menu rows, hotkeys, version line, "Round: feedback" | `App/Feedback/FeedbackStatusItem.swift`, `App/Feedback/ForkBranding.swift` |
| One menu bar item, "Nshot (N)" with the green round dot | `App/Feedback/ForkDefaults.swift` (the capture menu icon is hidden by default) |
| Round prompt header | `Packages/FeedbackKit` (`PromptBuilder.render`) |
| Badge color #FF543E | Sampled from a real capture |

## Choices and why

- **Sketch, then sleek (Drew's pick).** The problem is drawn as a marker sketch, in the spirit of Bill Ackman's lemonade stand video. When Nextshot appears, the scene turns into the Nextshot brand colors (`docs/brand/nextshot-mark.md`).
- **Rebuilt screens (Drew's pick).** Computer-use tools cannot see or click Nextshot's windows, so an agent cannot record the flow, and small menu bar text blurs in real footage. The rebuilt screens use the app's own strings.
- **No real captures.** The saved sessions hold a customer snapshot with a customer name and MRR, and Claude app screens with other project names. A staged lemonade stand avoids both.
- **A narrator line, not the app's toast.** After Copy Prompt and End Round, the app's toast says the round ended. The video shows "One round. One prompt." in large brand type instead, as a narrator line.
- **The round is the unit (Drew, 2026-10-24).** A round holds every capture, dot, and note that goes to AI in one prompt. The question on line 6 introduces it, a teal circle draws it, and the circle becomes the icon. Since v3.2 the menu shows "Round: feedback" and "All Rounds...", as the app does.
- **HyperFrames, not Remotion.** HyperFrames is Apache 2.0. Remotion needs a paid company license at a company with more than 3 employees.
- **Pinned packages.** `hyperframes` 0.8.140 (2026-10-07) is pinned, because the newest release came out on the day of the build, 2026-10-22.
- **Visuals first.** The video opens with 1 s of picture and music before the first word. Drew found the v2 start too abrupt. The stand page is drawn from the first frame, so the poster frame in Teams and email is not empty.
- **About 82 seconds (Drew, 2026-10-24).** His v3.1 lines add words, and he allowed a slightly longer cut. Most lines play 10% to 18% fast, and the problem section has short pauses. The key question (line 6) and the shortcut line (line 8) play at normal speed, as his notes ask.
- **Words changed from Drew's v3.1 notes.** Line 4 drops "and surfaces" and "gather and" (line 6 keeps "gather"). Line 9 says "Then say what should change." Line 11 drops "of captures". Line 12 is "One click, one paste, and AI gets the whole round." It keeps his "one-click paste" and matches the click on screen. Line 13 names the four parts of the prompt in place of "metadata and augmentation".
- **Research on the package screen.** The four rows follow published work: Set-of-Mark prompting (Microsoft Research, 2023) for numbered marks, FronTalk (arXiv 2601.04203, ICML 2026) and MT-Web2Code (arXiv 2608.03474) for visual feedback to coding agents. Both 2026 papers were checked on 2026-10-24. The screen names them in one footnote.
- **The proof shot.** After line 13, the agent's plan table (item, file, planned change) builds and checks three items with no voice, for 2.6 seconds. It shows the plan-first rule that all three prompts carry.
- **The bookend.** The opening sketch of the stand returns at the close and wipes into the clean page, so the start and the end match.
- **End card (Drew, 2026-10-24).** "Get it at nextshot.dev" as a teal button. "Feedback stays on your Mac until you paste it." is gone. Drew kept the tagline "Show AI what you mean." from six options, and music option A.
- **Two creative director rounds (2026-10-24).** A reviewer agent scored each cut and listed fixes. Round 1 scored 6 of 10 overall and round 2 scored 7. Both rounds' Must fixes and Should fixes shipped, apart from four declined items: a 0.5 s opening (Drew asked for the pause), "One click copies the whole round" (Drew's wording), the badges flying on into the close, and a voice line for the proof shot.
- **"Lemonaid" stays a typo (Drew).** It is mistake 1, and the clean close says "Lemonade".
- **"any AI agent", not "any AI tool".** The prompt names image files on the Mac by path. A web chat cannot open them. Claude Code, Codex, and other agents can.
- **"7 notes", not "6 notes".** The reviewer types seven notes: six answers to dots and one general note. The app counts only dots as items (`PromptBuilder`), so the bundle header on screen keeps its real text, `items="6"`.
- **Package claims match the app.** "Dot 1 in image 1 is item 1.1 in the text" (an image badge shows 1, not 1.1). Screen text, exact pixel boxes, and the plan-first rule follow `docs/plans/2026-10-20-feedback-sessions-phase1.md`.
- **One closing clip.** Asked to read the one-word line "Nextshot." alone, sage said it twice. It reads "Nextshot. Show AI what you mean." as one clip.
- **Breaths cut by level, not by word times.** A cut at Whisper's word times removed or changed words in six of fifteen lines (2026-10-23), so the cut uses quiet stretches of 0.35 s or more, and `check_voice.py` confirms every word.

## Sources

- Script length, 65 to 75 words per 30 seconds: VideoScribe, "How to write the perfect explainer video script" (blog.videoscribe.co).
- Speaking rate, about 150 words per minute: Breadnbeyond, "How many words are in a 60-second video script" (breadnbeyond.com).
- Problem in the first 1 to 3 seconds, design for muted viewing: Zubtitle, "Short-form explainer video guide" (zubtitle.com).
- HyperFrames: github.com/heygen-com/hyperframes. Remotion license: remotion.dev/docs/license/faq.
- Visuals before the first word: Uppbeat, "Ignace Aleya: 5 tips for video intros that hook viewers instantly" (uppbeat.io). Yans Media, "7 explainer video openings that hook viewers in 5 seconds" (yansmedia.com).
- Voice: OpenAI text to speech, `gpt-4o-mini-tts` with read instructions (platform.openai.com/docs/guides/text-to-speech).
- Music: Mixkit Stock Music Free License (mixkit.co/license/#musicFree).
- Set-of-Mark prompting: Yang and others, "Set-of-Mark Prompting Unleashes Extraordinary Visual Grounding in GPT-4V" (arXiv 2310.11441, Microsoft Research, 2023). FronTalk: arXiv 2601.04203. MT-Web2Code: arXiv 2608.03474.
