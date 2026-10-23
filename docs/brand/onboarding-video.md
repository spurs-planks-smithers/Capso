# Nextshot onboarding video

A 36-second video that shows Nextiva colleagues what Nextshot does: mark up screens, keep many screens and notes in one feedback session, and hand the whole session to an AI coding agent in one paste. Drew sends it with the DMG. He approved the cut on 2026-10-22.

The video is `build/releases/Nextshot-onboarding-2026.10.22.mp4` (git ignores `build/`). Its end card is `build/releases/Nextshot-onboarding-poster.png`, for an inline email image.

## Files

| Path | What it is |
|---|---|
| `scripts/video/nextshot-onboarding/script.json` | The voiceover lines, caption splits, pauses, and named cues (moments the picture and the sound effects share) |
| `scripts/video/nextshot-onboarding/make_audio.py` | Makes the voice clips, sound effects, and music. Writes `audio/final.wav`, `timing.json`, and `timing.js` |
| `scripts/video/nextshot-onboarding/index.html` | The HyperFrames composition: all seven scenes on one GSAP timeline that reads `timing.js` |
| `scripts/video/nextshot-onboarding/render.sh` | Runs everything and writes the video and the poster to `build/releases/` |
| `scripts/video/nextshot-onboarding/make_gif.py` | Renders the composition in GIF mode and cuts the email GIF (see "Email GIF") |
| `scripts/video/nextshot-onboarding/assets/` | Caveat and Inter fonts (SIL Open Font License), GSAP and Rough.js, the Nextshot icon |

`audio/`, `renders/`, `timing.json`, `timing.js`, and `node_modules/` are generated. They are not in git.

## Script and storyboard

| Time | Voiceover | Picture |
|---|---|---|
| 0 to 4 s | "Your AI agent just built you a lemonade stand. Almost." | Marker sketch. A robot shows a page that says "Lemonaid", "$9 a cup", and has a tiny Buy button. A stick figure squints. |
| 4 to 10 s | "So you screenshot. Save. Drag. Type: no, the other button. Every single time." | A screenshot flash, a pile of PNG files, a chat box that fills with a messy note, a tally of 10. |
| 10 to 12 s | "Meet Nextshot." | The Nextshot icon pops in. A circle wipe turns the scene graphite and teal. |
| 12 to 18 s | "Press Option Shift F. Grab the screen. Circle each problem. Say what should change." | Keycaps, the selection, badges 1 to 3, Command+S, and the note panel with its real question text. The menu bar shows "Nshot (1)". |
| 18 to 25 s | "Then grab the next screen, and the next. Circles, boxes, arrows, notes: one session holds it all." | A Checkout capture gets a circle and a box. A Flavors capture gets a circle, an arrow, and a general note. All three captures land in one "Session: feedback" tray. "Nshot (3)" shows enlarged. |
| 25 to 31 s | "One copy hands your agent every screen and every note. Paste it into Claude, Codex, any agent." | The Nshot menu and Copy Session Prompt. A hand-lettered note: "3 captures. 6 items. One prompt." The agent gets one card: `<feedback_bundle captures="3" items="6">`, three thumbnails, and the items grouped by capture. |
| 31 to 36 s | "Nextshot. Mark it up. Hand it off." | Back to the sketch: the stand is fixed ("Lemonade", "$3 a cup"). The end card: "Get the DMG in this message." and "Feedback stays on your Mac until you paste it." |

## Specs

- 1920 by 1080, 30 fps, H.264 yuv420p, AAC audio, faststart (the index comes first, so the file streams).
- 36.2 seconds, 5.6 MB.
- Loudness: -16 LUFS integrated (loudness units relative to full scale, the common web target), true peak below -1.5 dBTP.
- Burned-in captions, one line each, 46 characters at most. Teams and Outlook start video muted.
- Voice: Ava (Premium), the macOS voice. Sound effects and a plucked-string music bed are made in Python from the standard library. No downloaded audio.

## Rebuild it

```bash
NODE_ENV=development npm install --prefix scripts/video/nextshot-onboarding
```

```bash
scripts/video/nextshot-onboarding/render.sh
```

- The install needs `NODE_ENV=development`, because Drew's shell exports `production`.
- A render takes about one minute. It needs Node 22 or later, ffmpeg, and the Ava (Premium) voice.
- The output file name takes the date of the HEAD commit.
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

## Change it

- **Words:** edit a line in `script.json` and render again. The audio sets every time, so the picture follows.
- **Timing:** a cue names a line, and optionally a word in it and an offset in seconds. Word times are estimates, proportional to the characters before the word.
- **Pace:** `say -r` barely changes Ava's pace. The `tempo` value (ffmpeg `atempo`, which keeps the pitch) sets it.
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
- **No toast after Copy Session Prompt.** The app shows no toast for that copy. The video uses a hand-lettered note instead, so it never shows UI the app lacks.
- **Session at the center (Drew, mid-build).** Drew asked that the video show many screenshots and many kinds of marks in one session. Scenes 5 and 6 carry it.
- **HyperFrames, not Remotion.** HyperFrames is Apache 2.0. Remotion needs a paid company license at a company with more than 3 employees.
- **Pinned packages.** `hyperframes` 0.8.140 (2026-10-07) is pinned, because the newest release came out on the day of the build, 2026-10-22.

## Sources

- Script length, 65 to 75 words per 30 seconds: VideoScribe, "How to write the perfect explainer video script" (blog.videoscribe.co).
- Speaking rate, about 150 words per minute: Breadnbeyond, "How many words are in a 60-second video script" (breadnbeyond.com).
- Problem in the first 1 to 3 seconds, design for muted viewing: Zubtitle, "Short-form explainer video guide" (zubtitle.com).
- HyperFrames: github.com/heygen-com/hyperframes. Remotion license: remotion.dev/docs/license/faq.
