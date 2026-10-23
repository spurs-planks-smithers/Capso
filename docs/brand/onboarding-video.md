# Nextshot onboarding video

A 70-second video that shows Nextiva colleagues what Nextshot does: mark up screens, keep many screens and notes in one feedback session, and hand the whole session to an AI coding agent in one paste. Drew sends it with the DMG.

Two cuts exist:

| Cut | File | What it is |
|---|---|---|
| v3 (2026-10-23) | `build/releases/Nextshot-onboarding-2026.10.23.mp4`, poster `Nextshot-onboarding-poster.png` | Drew's line-by-line storyboard notes: his script, the OpenAI voice sage, and a style that moves from a rough yellow sketch to the brand look. 70.4 seconds. |
| v2 (2026-10-22) | `build/releases/Nextshot-onboarding-2026.10.22.mp4`, poster `Nextshot-onboarding-poster-v2.png` | The 36-second cut with Ava (Premium). It went out with the launch email and the email GIF. |

Git ignores `build/`. The render names each file by the date of the HEAD commit, so a new day's render never overwrites an older cut.

## Files

| Path | What it is |
|---|---|
| `scripts/video/nextshot-onboarding/script.json` | The voiceover lines, read directions, caption splits, pauses, and named cues (moments the picture and the sound effects share) |
| `scripts/video/nextshot-onboarding/make_audio.py` | Makes the voice clips, sound effects, and music. Writes `audio/final.wav`, `timing.json`, and `timing.js` |
| `scripts/video/nextshot-onboarding/check_voice.py` | Transcribes every voice clip with OpenAI Whisper and fails when a clip differs from its script line |
| `scripts/video/nextshot-onboarding/check_edges.py` | Fails when a voice clip starts or ends on sound (first and last 20 ms must be below -50 dB) |
| `scripts/video/nextshot-onboarding/index.html` | The HyperFrames composition: all seven scenes on one GSAP timeline that reads `timing.js` |
| `scripts/video/nextshot-onboarding/render.sh` | Runs everything and writes the video and the poster to `build/releases/` |
| `scripts/video/nextshot-onboarding/make_gif.py` | Renders the composition in GIF mode and cuts the email GIF (see "Email GIF") |
| `scripts/video/nextshot-onboarding/assets/` | Fonts: Permanent Marker (Apache License 2.0) and Patrick Hand (SIL Open Font License) for the sketch, Inter (SIL Open Font License) for the brand look. GSAP, Rough.js, the Nextshot icon. Caveat is no longer used. |
| `scripts/video/nextshot-onboarding/storyboard/build_storyboard.py` | Builds the storyboard review page and its PDF from the files above (see "Storyboard review page") |
| `scripts/video/nextshot-onboarding/storyboard/shots.json`, `template.html` | The page's hand-written text (what each line shows, scene jobs, cue names) and its design |

`audio/` (with the speech cache `audio/tts-cache/`), `renders/`, `timing.json`, `timing.js`, and `node_modules/` are generated. They are not in git.

## Script and storyboard (v3)

| Time | Voiceover | Picture |
|---|---|---|
| 0 to 5.5 s | (1.2 s of picture and music first) "So, you and AI just built a lemonade stand." | Yellow paper, marker strokes. The stand's web page draws in ("Lemonaid", "$9 a cup", a tiny Buy button). A robot labeled "AI" and a stick figure labeled "you". Then an app, legal docs, an email, and a flyer pop in with hand-written labels. |
| 5.5 to 29.7 s | "But AI output is far from perfect. Small things are wrong everywhere. So you screenshot. Crop. Paste. Prompt. But how do you tell AI what to change, and where? Page after page, into AI eternity. Why can't I give AI all my feedback at once?" | Seven red dots pop on the mistakes. A screenshot, crop marks, the crop drops into an AI chat, a messy prompt types out with red question marks. A tally climbs and pages pile up. Then the dots gather into one cluster. |
| 29.7 to 33.9 s | "Now you can. Introducing Nextshot." | The cluster becomes the Nextshot icon. A teal circle wipe turns the scene graphite. |
| 33.9 to 41.9 s | "Press Option Shift F. Grab the screen. Circle each problem. Say what should change." | Keycaps, the selection, badges 1 to 3, Command+S, and the note panel with its real question text and a preview of the whole sign. The menu bar shows "Nshot (1)". |
| 41.9 to 51.2 s | "Then grab the next screen, and the next. Circles, boxes, arrows, notes: one session holds it all." | A Checkout capture gets a circle and a box. A Flavors capture gets a circle, an arrow, and a general note. All three captures land in one "Session: feedback" tray. "Nshot (3)" shows enlarged. |
| 51.2 to 65.7 s | "One handoff gives your agent every screen, every note. All the context. Paste it into any AI agent as one prompt-optimized package." | The Nshot menu and Copy Session Prompt. "3 captures. 7 notes. 1 prompt." in large brand type. The agent gets one card, then a "Built for AI agents" panel lists Numbered marks, Screen text, Right-sized images, and Plan first. |
| 65.7 to 70.4 s | "Nextshot. Mark it up. Hand it off." | No return to the sketch: the fixed stand as a clean brand page with teal checks, and the end card. |

## Specs (v3)

- 1920 by 1080, 30 fps, H.264 yuv420p, AAC audio, faststart (the index comes first, so the file streams).
- 70.4 seconds, 11.1 MB.
- Loudness: -16.3 LUFS integrated (loudness units relative to full scale, the common web target), true peak -3.6 dBTP.
- Burned-in captions, one line each, 44 characters at most. Teams and Outlook start video muted.
- Voice: OpenAI `gpt-4o-mini-tts-2025-12-15`, voice sage, sped up 8% (pitch kept). Sound effects and a plucked-string music bed are made in Python from the standard library. No downloaded audio.

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
- Each clip is cached in `audio/tts-cache/` by model, voice, direction, text, and take, so a re-render buys no audio it already has.
- The install needs `NODE_ENV=development`, because Drew's shell exports `production`.
- A render takes about three minutes. It needs Node 22 or later and ffmpeg.
- HyperFrames telemetry is off on m5pro (`hyperframes telemetry disable`). Turn it off on any other Mac before the first render.
- To check frames without a full render, use `node_modules/.bin/hyperframes snapshot . --at 12.5,20 --describe false`. Without `--describe false`, the snapshot sends frames to Gemini when `GEMINI_API_KEY` is set.

## Email GIF

`build/releases/Nextshot-onboarding-hero.gif` is a 24-second cut of the video for the launch email: 640 by 360 pixels, 12 frames per second, one 255-color palette, about 1.2 MB. It goes into the email as an inline attachment with a content id, and the email wraps it in a link to the full video.

```bash
python3 scripts/video/nextshot-onboarding/make_gif.py
```

- `--no-render` reuses the last GIF-mode render in `renders/gif-source.mp4`.
- GIF mode is a composition variable (`--variables '{"gif":"on"}'`). It raises the captions to 66 pixels, one third of the frame's width maps to the GIF, so they read at 22 pixels there. It also drops the captions over the end card, which carries its own words.
- The ffmpeg on m5pro has no subtitle filter, so the captions come from the composition, never from ffmpeg.
- The segments are cut at cue times from `timing.json`, so a script change moves them with the voice.
- The first frame must stand alone: classic Outlook on Windows shows only the first frame of an animated GIF. Outlook for Mac, the new Outlook for Windows, Outlook on iPhone and Android, Apple Mail, and Gmail play the loop. The first frame is the finished lemonade stand with the caption "Your AI agent just built you a lemonade stand."
- Keep the file under about 3 MB. A larger GIF slows the email on a phone.
- The GIF is cut from v2. `make_gif.py` still names v2 cues (`squint`, `tally`, `chip_any`, and others), so it stops on v3 until its segments use v3 cue names. Cut a v3 GIF only on request.

## Storyboard review page

Drew reviews each cut on one page and leaves notes on every voice line. The page is a private claude.ai artifact, first published 2026-10-23: https://claude.ai/artifact/7FfwHyYeL63MeLAp1yc46k. It puts four standard review formats in one place: an AV script (what you hear beside what you see), a storyboard (two frames per voice line), a timeline (scenes, voice, sounds, music), and timecoded notes. A plain-English glossary explains the editing terms.

```bash
python3 scripts/video/nextshot-onboarding/storyboard/build_storyboard.py --pdf
```

- Run it after each `render.sh`. It stops when `timing.json` is newer than the newest MP4, and when `script.json`, `timing.json`, and `shots.json` disagree on the lines, scenes, or cues.
- It writes `build/releases/storyboard/`: `page.html` for the artifact, `local.html` for a browser and the PDF, `video.mp4`, and `frames/`. With `--pdf` it also writes `build/releases/Nextshot-onboarding-storyboard.pdf` (Letter, two cards a page, printed by Chrome).
- `shots.json` holds the hand-written parts: what each line shows, each scene's job and look, the cue names, and the Frame.io link. A line can pin its two frames with `"frames": [0.3, 0.75]`, as fractions of the time from its start to the next line.
- Republish: bump `version` in `shots.json`, build, then publish `build/releases/storyboard/page.html` to the artifact URL with `video.mp4` and `frames/*.jpg` as files (root `build/releases/storyboard`).
- Notes live in the artifact's database, collection `notes`: one document per line id (in v3, `built`, `flawed`, `loop`, and so on) plus `overall`. Fields: `verdict` (keep, change, or cut), `rewrite`, `words`, `picture`, `timing` (`overall` has `whole` and `sound`), `cut`, `updated`. Claude reads them with the ArtifactData tool, answers in `reply`, and sets `status` to `done` when the change ships. The page shows the reply under the note.
- Opened as a local file, the page saves notes in that browser only, and Chrome's Save Page As drops typed notes. "Copy all notes" gives plain text either way. Drew's v2 notes came in that way on 2026-10-23, so review on the claude.ai link instead.
- A local preview needs a server with byte-range support, or the video cannot seek. Python's `http.server` has none.

## Change it

- **Words:** edit a line in `script.json` and render again. The audio sets every time, so the picture follows.
- **Timing:** a cue names a line, and optionally a word in it and an offset in seconds. Word times are estimates, proportional to the characters before the word.
- **Read:** each line has a `direction` that the OpenAI voice follows, on top of the shared `voice.style`. A new `take` number asks for a fresh reading of one line.
- **Pace:** the voice reads slower than its directions ask. `voice.tempo` (ffmpeg `atempo`, which keeps the pitch) speeds every clip. `voice.max_gap` caps the pauses inside a line, and a line can set its own `max_gap`. `voice.breath_db` sets the level under which a stretch of 0.35 s or more counts as a breath and gets cut.
- **Check:** run `check_voice.py` and `check_edges.py` after every audio change. A level cut that goes too far turns a word into another word ("prompt" became "cropped" at a 0.15 s pause cap).
- **App text:** the rebuilt screens copy strings from the app. Check them against the source after any change to the feedback UI:

| Screen in the video | Source |
|---|---|
| Note panel question, placeholder, and help line | `App/Feedback/FeedbackNotePanel.swift` |
| General note question | `App/Feedback/FeedbackNotePanel.swift` |
| Nshot menu rows, version line, "Session: feedback" | `App/Feedback/FeedbackStatusItem.swift`, `App/Feedback/ForkBranding.swift` |
| One menu bar item, "Nshot (N)" | `App/Feedback/ForkDefaults.swift` (the capture menu icon is hidden by default) |
| Session prompt header | `Packages/FeedbackKit` (`PromptBuilder.render`) |
| Badge color #FF543E | Sampled from a real capture |

## Choices and why

- **Sketch, then sleek (Drew's pick).** The problem is drawn as a marker sketch, in the spirit of Bill Ackman's lemonade stand video. When Nextshot appears, the scene turns into the Nextshot brand colors (`docs/brand/nextshot-mark.md`).
- **Rebuilt screens (Drew's pick).** Computer-use tools cannot see or click Nextshot's windows, so an agent cannot record the flow, and small menu bar text blurs in real footage. The rebuilt screens use the app's own strings.
- **No real captures.** The saved sessions hold a customer snapshot with a customer name and MRR, and Claude app screens with other project names. A staged lemonade stand avoids both.
- **No toast after Copy Session Prompt.** The app shows no toast for that copy. The video uses a narrator line in large type instead, so it never shows UI the app lacks.
- **Session at the center (Drew, mid-build).** Drew asked that the video show many screenshots and many kinds of marks in one session. Scenes 5 and 6 carry it.
- **HyperFrames, not Remotion.** HyperFrames is Apache 2.0. Remotion needs a paid company license at a company with more than 3 employees.
- **Pinned packages.** `hyperframes` 0.8.140 (2026-10-07) is pinned, because the newest release came out on the day of the build, 2026-10-22.
- **v3 follows Drew's storyboard notes (2026-10-23).** His script, a better voice, and a rough-to-polished style: yellow paper and stick figures before the turn, the brand look after it, and a clean close with no sketch.
- **Visuals first.** The video opens with 1.2 s of picture and music before the first word. Drew found the v2 start too abrupt.
- **Red dots become the icon.** Every mistake gets a red dot in the badge red. At the turn the dots gather and become the Nextshot icon, so the problem and the product share one mark.
- **About 70 seconds (Drew, 2026-10-23).** He first set about 45 seconds. Measured on the same lines, sage reads 1.8 words per second and cedar 2.5. He kept sage and every word.
- **"Lemonaid" stays a typo (Drew).** It is mistake 1, and the clean close says "Lemonade".
- **"any AI agent", not "any AI tool".** The prompt names image files on the Mac by path. A web chat cannot open them. Claude Code, Codex, and other agents can.
- **"Paste it", not "One click pastes".** One click copies (Copy Session Prompt). The paste is the user's Command+V.
- **"7 notes", not "6 notes".** Drew wrote "6 notes", from v2's "6 items". The reviewer types seven notes: six answers to badge marks and one general note. The app counts only badge marks as items (`PromptBuilder`), so the bundle header on screen keeps its real text, `items="6"`.
- **Package claims match the app.** "Badge 1 in image 1 is item 1.1 in the text" (an image badge shows 1, not 1.1). Screen text, right-sized lossless images, and the plan-first rule follow `docs/plans/2026-10-20-feedback-sessions-phase1.md`.
- **One closing clip.** Asked to read the one-word line "Nextshot." alone, sage said it twice. It now reads "Nextshot. Mark it up. Hand it off." as one clip.
- **Breaths cut by level, not by word times.** A cut at Whisper's word times removed or changed words in six of fifteen lines (2026-10-23), so the cut uses quiet stretches of 0.35 s or more, and `check_voice.py` confirms every word.

## Sources

- Script length, 65 to 75 words per 30 seconds: VideoScribe, "How to write the perfect explainer video script" (blog.videoscribe.co).
- Speaking rate, about 150 words per minute: Breadnbeyond, "How many words are in a 60-second video script" (breadnbeyond.com).
- Problem in the first 1 to 3 seconds, design for muted viewing: Zubtitle, "Short-form explainer video guide" (zubtitle.com).
- HyperFrames: github.com/heygen-com/hyperframes. Remotion license: remotion.dev/docs/license/faq.
- Visuals before the first word: Uppbeat, "Ignace Aleya: 5 tips for video intros that hook viewers instantly" (uppbeat.io). Yans Media, "7 explainer video openings that hook viewers in 5 seconds" (yansmedia.com).
- Voice: OpenAI text to speech, `gpt-4o-mini-tts` with read instructions (platform.openai.com/docs/guides/text-to-speech).
