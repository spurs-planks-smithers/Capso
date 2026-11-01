# m4max test of the notarized DMG with the summary name

Date: 2026-11-01. Drew named the m4max as the approved Mac for this check. The m5pro rule bars production Nextshot there, so no one has run the notarized build with the model. This run closes that gap before 0.6.0.

Run it on the m4max after the release session builds the 0.6.0 DMG. Do each step and note the result.

## Before

1. Copy the DMG to the m4max. Check `shasum -a 256` against the `.dmg.sha256` file.
2. Quit any Nextshot copy that runs on the m4max.
3. In System Settings > Apple Intelligence & Siri, note whether Apple Intelligence is on and the language.

## Run A: Apple Intelligence on

1. Double-click the app on the image. Accept "Install Nextshot". Grant screen recording once.
2. Press Option+Shift+F. Capture an area, put two red dots, press Command+S.
3. Type a note with at least three words for each dot, for example "Make this button bigger" and "Change this label to Save".
4. Wait 3 seconds. Press Option+Shift+C. Paste into any text field. The first line must read `Session Name: <app> - <name>`.
5. Press Option+Shift+C again and paste. Record whether the name is a short summary now.
6. Record: summary shown (yes or no), any crash, any permission prompt that names the model or the network.

## Run B: Apple Intelligence off

1. Turn Apple Intelligence off in System Settings. Quit and reopen Nextshot.
2. Repeat steps 2 to 4 of Run A.
3. The name must be the start of the first note. No crash, no prompt.

## After

1. Read the counts: `NEXTSHOT_FLAGS_DOMAIN=com.drewschulz.nextshot scripts/nextshot-summary-use.sh`. Expect `copy.summary` after Run A, and `copy.unavailable.appleIntelligenceNotEnabled` after Run B.
2. Check the log has no model error: `/usr/bin/log show --last 15m --predicate 'subsystem == "com.drewschulz.nextshot"' | grep -i "session summary"`.
3. Turn Apple Intelligence back on if it was on before.

## Pass

Run A shows a summary name on the second copy. Run B shows the cut name. No crash, no network prompt, and the counts match.
