# Master prompt for Codex: a better Nextshot onboarding video

Written 2026-10-22. Paste everything below the rule into Codex, started in `/Users/drewschulz/Developer/capso`. Codex also reads `AGENTS.md` on its own. The result competes with the Claude Code version in `scripts/video/nextshot-onboarding/`, and Drew scores both with the scorecard in section 10.

---

You are the creative director, motion designer, editor, and audio producer for a 30 to 38 second onboarding video for Nextshot. Build it in this repository. Then review and revise your own cut three times: as a video editor, as a curator, and as a CMO. An existing version of this video already exists. Beat it.

## 1. What Nextshot is

Nextshot is a macOS menu bar app, a fork of Capso, for giving feedback to AI coding agents. Press Option+Shift+F and drag over part of the screen. Press C to drop numbered circles on each problem. Boxes, arrows, and text work too. Press Command+S. Nextshot asks one question per circle, "Circle 1 (1 of 3): what should change?", then an optional general note. The reviewer types or dictates each answer. Then the reviewer grabs the next screen, and the next. One session holds every capture and every note. Copy Session Prompt in the Nshot menu copies one prompt, and the reviewer pastes it into Claude Code, Codex, or any agent. The agent gets every marked-up screenshot, the numbered answers, and the screen text under each mark. The prompt makes the agent write a plan before it edits anything. Feedback stays on the Mac until it is pasted. Read `.github/README.md` and the section "Use a feedback session" in `AGENTS.md`.

## 2. Audience and goal

Nextiva colleagues who use AI coding agents on Macs. Drew sends the video with a DMG link in email and Teams, where video starts muted. The goal: they install it today. The one idea that must land: many screens and many kinds of marks go into one session, and one paste hands the agent all of it.

## 3. The baseline to beat

- Video: `build/releases/Nextshot-onboarding-2026.10.22.mp4` (36 seconds). Watch it, or tile it: `ffmpeg -i <mp4> -vf "fps=1,scale=480:-1,tile=6x6" sheet.png`.
- Source: `scripts/video/nextshot-onboarding/` (`script.json`, `make_audio.py`, `index.html`, `render.sh`, `make_gif.py`). Guide: `docs/brand/onboarding-video.md`. Read all of it. Reuse any idea or code you want by copying it into your own folder.
- Its story: a sketched robot (the agent) builds a lemonade stand page with three problems: the sign says "Lemonaid", the price is "$9 a cup", and the Buy button is tiny. The reviewer suffers the screenshot loop. Nextshot appears, the sketch turns into the graphite and teal brand world, and the real flow plays on three staged pages (the stand, Checkout, Flavors). The close returns to the sketch with the stand fixed, beside an end card. Keep this story and the sketch-to-sleek turn unless you have a clearly better idea. If you change it, say why in your plan.
- Its weaknesses. Fix them:
  1. The sketch characters barely move. The robot never reacts. The reviewer only squints and sweats.
  2. The problem scene shows tally marks, a file pile, and a chat box at the same time. It reads as busy.
  3. The sleek scenes are flat: no camera move, no push-in on a circle when its question appears, a small note panel preview.
  4. The agent card packs six items in small type for three seconds.
  5. The music is a generated four-chord pluck loop. The sound design is a few pops and a shutter.
  6. The voice (macOS Ava) is clear but flat, with even pacing and no emphasis.
  7. The end card stops moving once it lands, and the call to action is text only.
  8. Scene changes are cuts and fades, except one circle wipe.

## 4. Hard requirements

Content, in this order:
1. Hook in the first 3 seconds: the agent built something, and it is almost right.
2. The pain: screenshot, save, drag, type "no, the other button", every time.
3. The turn: the Nextshot mark and the brand world.
4. The flow: Option, Shift, F keycaps; a drag selection; numbered circles that pop in; the note panel with its real question; a typed or dictated answer; "Nshot (1)" in the menu bar.
5. The session, the most important beat, at least 7 seconds: two more captures, each with different mark types (a box, an arrow, a general note), all landing in one session; the menu bar count going to "Nshot (3)".
6. The hand-off: Copy Session Prompt, then one paste into an agent that shows `<feedback_bundle captures="3" items="6">`, three thumbnails, the items grouped by capture, and the plan-first rule.
7. The close: the fixed stand, then the end card: the Nextshot mark, "Nextshot", "Mark it up. Hand it off.", Option Shift F keycaps with "starts a capture", "Get the DMG in this message.", and "Feedback stays on your Mac until you paste it."

Format: 1920 by 1080, 30 frames per second, H.264 yuv420p, AAC, faststart, 30 to 38 seconds, under 15 MB. Loudness -16 LUFS integrated (loudness units relative to full scale), true peak at or below -1.5 dBTP. Burned-in captions on every spoken line, one line each, 46 characters or fewer, readable at 640 pixels wide. No caption over the end card.

App text must match the source exactly. Copy these strings from the code, never from memory:
- The note panel question, the placeholder "Type or dictate, then press Return", and the help line under the field: `App/Feedback/FeedbackNotePanel.swift`.
- The general note question "Anything else about this capture? (optional)": the same file.
- The menu rows and their order, the version line (the DMG Drew sends reads "Nextshot 2026.10.22 (501)"), and "Session: feedback": `App/Feedback/FeedbackStatusItem.swift` and `App/Feedback/ForkBranding.swift`.
- One menu bar item only, titled "Nshot (N)" during a session: `App/Feedback/ForkDefaults.swift`.
- The toast after the last note step: `App/Feedback/FeedbackController.swift`, line 56. Copy Session Prompt shows no toast. Never show UI the app lacks.
- The prompt header and rules: `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift`.
- The badge: #FF543E with a white ring.

Brand: `docs/brand/nextshot-mark.md`. Graphite #23282C, Teal #3CCDBE (the square, at 60% opacity), Mint #8FF3E4. The mark: `docs/brand/nextshot-icon-512.png` and `docs/brand/nextshot-menu-bar.png`. The wordmark: "Nextshot" in Inter at weight 800. Sketch lettering: Caveat. Never show Capso's name or logo. The word "Capso" must not appear on screen.

Privacy and text: staged demo content only. No real screenshots from `~/Library/Application Support/Nextshot`; they hold customer and project data. No em dash, no middot, no italics, on screen or in docs. American English. No AI-made tells: fake browser chrome, drop shadows for their own sake, page counters, repeated captions.

## 5. Voice: OpenAI text to speech

Use the OpenAI Audio API with the key in `OPENAI_API_KEY`, which the shell already exports. Use the newest speech model the API lists (`GET /v1/models`; `gpt-4o-mini-tts` or newer). Pass an `instructions` string that sets the read: warm, bright, playful, a friendly product host, brisk but never rushed, a smile on the hook and the close, a dry beat on "Almost." Shortlist the voices the API offers today. The usual best for this read are marin, cedar, coral, sage, and nova; skip any the API does not list. Render the hook line with each shortlisted voice to `audio/voice-samples/<voice>.wav`, pick the warmest and clearest, and say why in your report. Keep the samples, because Drew may override the pick. Generate one clip per line, trim silence with peak detection, measure each clip, and derive every timing from the audio, as the baseline does. Target 160 to 175 words per minute. If the API fails, fall back to `say -v "Ava (Premium)"` and say so.

## 6. Music and sound

Make music and effects locally (the Python standard library and ffmpeg), or use files with a license Drew can show. No downloads from unknown sources. Give the music a real melody and a lift at the turn. Duck it under the voice. Give every pop, key, shutter, and whoosh a sound.

## 7. Tools on this Mac

- Node 25. HyperFrames 0.8.140 (pin this version; it renders an HTML page with a paused GSAP timeline to MP4 through headless Chrome). GSAP 3.15.0. Rough.js 4.6.6. Install into your own folder with `NODE_ENV=development npm install --save-exact ...`, because the shell exports `NODE_ENV=production`. Run `npx hyperframes telemetry disable` first. `npx hyperframes docs gsap`, `docs data-attributes`, and `docs compositions` explain the format. `npx hyperframes snapshot . --at 2,10,20 --describe false` writes key frames. Always pass `--describe false`, or frames go to Gemini. `--variables '{"k":"v"}'` passes values that `window.__hyperframes.getVariables()` reads.
- ffmpeg 9.0.2 and ffprobe. This build has no `subtitles` filter and no `drawtext` filter, so all text is HTML.
- Python 3.14 with the standard library only. A venv under your folder is fine.
- `say -v "Ava (Premium)"` as the voice fallback. `say -r` barely changes Ava's pace. ffmpeg `atempo` does.
- Fonts: copy `scripts/video/nextshot-onboarding/assets/fonts/` (Caveat and Inter, SIL Open Font License). Load fonts from local files, never from the network.
- No tool can record or click the real Nextshot windows. Rebuild the screens in HTML from the strings above.
- A render takes about one minute. Clip-path and blend animations fall back to screenshot capture, which is fine.

## 8. Where to work, and what not to touch

- Work only in `scripts/video/nextshot-onboarding-codex/`. Write outputs to `build/releases/`. Both folders are git-ignored upstream. That is expected.
- Outputs: `build/releases/Nextshot-onboarding-codex-v1.mp4`, `-v2.mp4`, `-v3.mp4`, and `Nextshot-onboarding-codex-final.mp4` (a copy of the last), plus `Nextshot-onboarding-codex-poster.png` (the end card). If time allows, `Nextshot-onboarding-codex-hero.gif`: 640 pixels wide, under 3 MB, with a first frame that stands alone.
- Write `docs/brand/onboarding-video-codex.md`: the script, the storyboard table, the voice choice, the three review passes with what changed, the verification evidence, and the rebuild steps.
- Do not edit `scripts/video/nextshot-onboarding/`, the app code, `.gitignore`, or `AGENTS.md`. Do not commit, push, or switch branches. Drew compares first.

## 9. Process

1. Read: `AGENTS.md`, `.github/README.md`, `docs/brand/nextshot-mark.md`, `docs/brand/onboarding-video.md`, the baseline source, and the Swift files named above.
2. Plan before any build. Write into the docs page: the script (65 to 85 words), a storyboard table (time, voice line, picture, sound), the voice shortlist, and the music idea. Say what you keep from the baseline, what you change, and why.
3. Build v1. Snapshot the eight key beats and tile a 1 frame per second contact sheet. Look at every frame.
4. Review v1 three times, in writing, each time as a different person. Number every finding with a timecode and a concrete fix.
   - Video editor: pacing per beat (the pain starts by 3 seconds; the session beat gets 7 seconds or more), cut points on the voice, caption timing within 100 milliseconds of the line, continuity (the menu bar count, the session name, the badge numbers), motion (ease curves, nothing pops without a sound), audio (ducking, no clipped word starts or ends, no clicks).
   - Curator: one type system (Caveat for the sketch, Inter for the product, nothing else), brand colors only, hierarchy and negative space, character design that stays the same across scenes, caption style, no AI-made tells, every frame good enough to post as a still.
   - CMO: the hook lands in 3 seconds, one value proposition, the "one session, one paste" idea is unmistakable, the audience is Mac users with coding agents, the call to action is clear, the tone is fun without being cheesy, it works muted, and the Nextshot name is seen and heard at least twice.
5. Apply every fix you accept. Render v2. Repeat step 4 once more. Render v3. Keep a change log per round.
6. Verify the final cut, and paste the evidence into the docs page:
   - `ffprobe` shows 1920 by 1080, 30 fps, h264 yuv420p, aac, a duration of 30 to 38 seconds, a size under 15 MB, and the `moov` atom before `mdat`.
   - `ffmpeg -af ebur128=peak=true` shows about -16 LUFS integrated and a true peak at or below -1.5 dBTP.
   - Every voice clip starts and ends below -50 dB in its first and last 20 milliseconds.
   - A grep of the composition and the script finds no "Capso", no em dash, no middot, and no italic style.
   - Every app string in the video matches its Swift source. Show the grep.
   - Every caption is 46 characters or fewer.
   - The contact sheet shows no clipped or overlapping text.
7. Report back in under 60 lines: the paths, the voice you chose and why, your honest scores on the scorecard below, the three review passes in brief, and open questions.

## 10. Scorecard (Drew scores both videos with it)

Score each item 1 to 5 and give one line of reasons:
1. Hook: the first 3 seconds make a viewer stay.
2. Clarity: a first-time viewer can repeat the four steps afterward.
3. The session idea: many screens, many marks, one paste, unmistakable.
4. Visual polish: motion, typography, consistency, no tells.
5. Audio: voice quality, pacing, music, sound design, mix.
6. Accuracy: every string and behavior matches the app.
7. Fit for the channel: works muted, readable at 640 pixels, 30 to 38 seconds.
8. Evidence: the verification is complete and honest.
