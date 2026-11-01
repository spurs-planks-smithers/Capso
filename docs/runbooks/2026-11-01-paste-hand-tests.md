# Paste hand tests

One paste can carry text, one image, and a file. Each chat app handles that paste in its own way. These three tests show what each app does with the paste that Nextshot plans to copy. T1 pastes a prompt with one image. T4 pastes long text and checks that the app keeps the last line. T6 pastes a prompt with a zip file. You fill the result tables by hand. The Part C plan starts from your results.

## Before you start

1. Open Terminal in the repository folder. This is the folder that holds `project.yml`. Run every command in this file from there.
2. Build the prompt tool once. The scripts call it to render the prompts and the zip.

```
swift build --package-path Packages/FeedbackKit --product nextshot-prompt
```

3. Know what the scripts change. Each script overwrites your clipboard (the place where macOS holds what you copy). Copy anything you need before you start. The test paste stays on the clipboard until you copy something else. After the last test, copy any word to replace it.
4. Plan your time. T1 and T6 take about 15 minutes together. T4 adds about 45 minutes because it has 64 rows. Run T4 last. Stop early if the first lengths show a clear pattern.
5. Know what leaves your Mac. Each paste goes to the cloud service of the app you test. T1 and T4 send a screenshot of the nextshot.dev page and a prompt about it. T6 sends five screenshots of a Settings window. None of these hold private data. Deny any request from an app to read, edit, or run files. The tests need no file access.

### The apps

Test every app in this table. The last column tells you how to open a new chat.

| App | How to open a new chat |
| --- | --- |
| Claude desktop, Chat | Open the Claude app. Click Chat. Click New chat. |
| Claude desktop, Code tab | Open the Claude app. Click the Code tab. Start a new session in any folder. |
| Claude Code in Terminal | In a second Terminal window, run `cd /tmp`. Then run `claude`. |
| ChatGPT desktop | Open the ChatGPT app. Click New chat. |
| claude.ai in Chrome | In Chrome, open https://claude.ai/new. |
| chatgpt.com in Chrome | In Chrome, open https://chatgpt.com/. Click New chat if a chat is open. |
| Cursor | Open Cursor in any folder. Open the chat panel. Click the button that starts a new chat. |
| Codex app | Open the Codex app. Start a new thread in any folder. |

### Two words used in this file

- **Turn:** one message in a chat. Your message is one turn. The reply is the next turn.
- **Long chat:** a chat with 20 or more earlier turns. Make one for each app before T4. Send `Reply with one word: OK` ten times in a chat. That gives 20 turns. Use the same long chat for all four T4 lengths.

### About Claude Code in Terminal

Command+V pastes text in Terminal. Claude Code takes an image with Control+V. In T1 and T4, press Command+V first. If no image attaches, press Control+V on a new line and write "Control+V" in Notes.

### If Shift+Return does not start a new line

Some apps send the message when you press Shift+Return. In that app, paste first and press Return. Then send the fixed question as a second message. Write "second message" in Notes. In T4, a second message still tests the paste, because the question asks about "my message".

---

## T1: one paste with text and one image

**What it tests.** The app takes the prompt text and the image from one paste.

**Run the mode.**

```
swift scripts/paste-test/paste-test.swift t1
```

The script prints this on 2026-11-01. Check that item 1 lists text and a PNG.

```
pasteboard items: 1
  item 1: public.utf8-plain-text, public.png
text: 3462 characters
image: 2124-nextshot-show-ai-what-you-mean.png, 2354706 bytes
```

The text is the capture prompt of the round `2026-10-31-2125-feedback`. The image is its annotated screenshot of the nextshot.dev page. To see badge 1 yourself, run this:

```
open "/Users/drewschulz/Library/Application Support/Nextshot/2026-10-31-2125-feedback/2124-nextshot-show-ai-what-you-mean.png"
```

**Fixed question.**

```
What does badge 1.1 point at?
```

**Steps for each app.**

1. Run the mode above once. Run it again if you copy anything else.
2. Open the app and open a new chat. Use the table in "The apps".
3. Click the message box. Type the fixed question. Press Shift+Return to start a new line. Press Command+V.
4. Before you send, look at the message box. Note what appeared: text, an image, or both.
5. Press Return to send. Wait for the whole answer.
6. Fill one row of the table below.
7. Go to the next app. Do not copy anything else.

**Pass.** All three are true:

- The text appears in the message, inline or as an attachment.
- One image attaches.
- The answer names the download buttons.

**Fail.** Any one of the three is missing.

**What to write in "What you saw".** Three short facts: text in the message (yes or no), images attached (a number), answer names the download buttons (yes or no).

| App | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- |
| Claude desktop, Chat |  |  |  |
| Claude desktop, Code tab |  |  |  |
| Claude Code in Terminal |  |  |  |
| ChatGPT desktop |  |  |  |
| claude.ai in Chrome |  |  |  |
| chatgpt.com in Chrome |  |  |  |
| Cursor |  |  |  |
| Codex app |  |  |  |

---

## T4: long text, and the last line

**What it tests.** The app keeps the whole paste, including the last line, at four lengths and in two kinds of chat.

**What the text is.** It is the capture prompt of the round `2026-10-31-2125-feedback`, with the same screenshot. The prompt is 3462 characters long, so `t4-2000` cuts it to fit. The longer modes add the item lines of the prompt again and again after the prompt, until the text is the full length. Every text ends with this line:

```
LAST LINE: blue heron 47
```

**Run the modes.** You run one mode at a time. Finish all 16 rows of one length before you run the next mode.

```
swift scripts/paste-test/paste-test.swift t4-2000
swift scripts/paste-test/paste-test.swift t4-5000
swift scripts/paste-test/paste-test.swift t4-10000
swift scripts/paste-test/paste-test.swift t4-15000
```

Each script prints the same lines as T1, with the new character count. Check that the count matches the mode, and that item 1 lists text and a PNG. The `t4-2000` line also says that the prompt was cut to fit.

**Fixed question.**

```
Quote the last line of my message.
```

**Steps for each app and chat kind.**

1. Run the mode for the length you test. Run it again if you copy anything else.
2. Open the app. For the new chat row, open a new chat. For the long chat row, open the long chat you made for that app.
3. Click the message box. Type the fixed question. Press Shift+Return to start a new line. Press Command+V.
4. Before you send, look at the message box. Note the shape of the paste: inline text, a "Pasted text" tile, or a file attachment.
5. Press Return to send. Wait for the whole answer.
6. Fill one row of the table for that length.
7. Go to the next row. Do not copy anything else.

**Pass.** The answer contains `blue heron 47`.

**Fail.** The answer quotes a different line, says it cannot see the end, or says the text was cut.

**What to write in "What you saw".** The shape of the paste (inline, tile, or file), whether one image attached, and the line the answer quoted.

### T4 at 2000 characters

| App | Chat kind | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- | --- |
| Claude desktop, Chat | New chat |  |  |  |
| Claude desktop, Chat | Long chat |  |  |  |
| Claude desktop, Code tab | New chat |  |  |  |
| Claude desktop, Code tab | Long chat |  |  |  |
| Claude Code in Terminal | New chat |  |  |  |
| Claude Code in Terminal | Long chat |  |  |  |
| ChatGPT desktop | New chat |  |  |  |
| ChatGPT desktop | Long chat |  |  |  |
| claude.ai in Chrome | New chat |  |  |  |
| claude.ai in Chrome | Long chat |  |  |  |
| chatgpt.com in Chrome | New chat |  |  |  |
| chatgpt.com in Chrome | Long chat |  |  |  |
| Cursor | New chat |  |  |  |
| Cursor | Long chat |  |  |  |
| Codex app | New chat |  |  |  |
| Codex app | Long chat |  |  |  |

### T4 at 5000 characters

| App | Chat kind | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- | --- |
| Claude desktop, Chat | New chat |  |  |  |
| Claude desktop, Chat | Long chat |  |  |  |
| Claude desktop, Code tab | New chat |  |  |  |
| Claude desktop, Code tab | Long chat |  |  |  |
| Claude Code in Terminal | New chat |  |  |  |
| Claude Code in Terminal | Long chat |  |  |  |
| ChatGPT desktop | New chat |  |  |  |
| ChatGPT desktop | Long chat |  |  |  |
| claude.ai in Chrome | New chat |  |  |  |
| claude.ai in Chrome | Long chat |  |  |  |
| chatgpt.com in Chrome | New chat |  |  |  |
| chatgpt.com in Chrome | Long chat |  |  |  |
| Cursor | New chat |  |  |  |
| Cursor | Long chat |  |  |  |
| Codex app | New chat |  |  |  |
| Codex app | Long chat |  |  |  |

### T4 at 10000 characters

| App | Chat kind | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- | --- |
| Claude desktop, Chat | New chat |  |  |  |
| Claude desktop, Chat | Long chat |  |  |  |
| Claude desktop, Code tab | New chat |  |  |  |
| Claude desktop, Code tab | Long chat |  |  |  |
| Claude Code in Terminal | New chat |  |  |  |
| Claude Code in Terminal | Long chat |  |  |  |
| ChatGPT desktop | New chat |  |  |  |
| ChatGPT desktop | Long chat |  |  |  |
| claude.ai in Chrome | New chat |  |  |  |
| claude.ai in Chrome | Long chat |  |  |  |
| chatgpt.com in Chrome | New chat |  |  |  |
| chatgpt.com in Chrome | Long chat |  |  |  |
| Cursor | New chat |  |  |  |
| Cursor | Long chat |  |  |  |
| Codex app | New chat |  |  |  |
| Codex app | Long chat |  |  |  |

### T4 at 15000 characters

| App | Chat kind | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- | --- |
| Claude desktop, Chat | New chat |  |  |  |
| Claude desktop, Chat | Long chat |  |  |  |
| Claude desktop, Code tab | New chat |  |  |  |
| Claude desktop, Code tab | Long chat |  |  |  |
| Claude Code in Terminal | New chat |  |  |  |
| Claude Code in Terminal | Long chat |  |  |  |
| ChatGPT desktop | New chat |  |  |  |
| ChatGPT desktop | Long chat |  |  |  |
| claude.ai in Chrome | New chat |  |  |  |
| claude.ai in Chrome | Long chat |  |  |  |
| chatgpt.com in Chrome | New chat |  |  |  |
| chatgpt.com in Chrome | Long chat |  |  |  |
| Cursor | New chat |  |  |  |
| Cursor | Long chat |  |  |  |
| Codex app | New chat |  |  |  |
| Codex app | Long chat |  |  |  |

---

## T6: one paste with text and a zip file

**What it tests.** The app takes the round prompt as text and the zip file as an attachment from one paste.

**Run the mode.** The round is `2026-10-27-0939-feedback`. It has five captures of a Settings window, which you approved.

```
swift scripts/paste-test/paste-test.swift t6 2026-10-27-0939-feedback
```

The script prints this on 2026-11-01. Check that it lists two items, a text item and a file URL item.

```
pasteboard items: 2
  item 1: public.utf8-plain-text
  item 2: public.file-url
text: 5086 characters
zip: /var/folders/.../nextshot-paste-test/nextshot-round-2026-10-27-0939-5-captures.zip, 801697 bytes
```

The command `osascript -e 'clipboard info'` lists only the first item, so it shows no file URL for this mode. Trust the script output.

**Which badge to ask about.** The question needs a badge that exists in the round. This round has no item 2.1, because capture 2 has no badge. The items are 1.1, 1.2, 1.3, 1.4, 3.1, 4.1, and 5.1. The question below uses badge 3.1. To see what badge 3.1 marks, run this and look for badge 1:

```
open "/Users/drewschulz/Library/Application Support/Nextshot/2026-10-27-0939-feedback/0948-claude.png"
```

**Fixed question.**

```
What does the image show at badge 3.1?
```

**Steps for each app.**

1. Run the mode above once. Run it again if you copy anything else.
2. Open the app and open a new chat. Use the table in "The apps".
3. Click the message box. Type the fixed question. Press Shift+Return to start a new line. Press Command+V.
4. Before you send, look at the message box. Note what appeared: text, a zip file, or both.
5. Press Return to send. Wait for the whole answer.
6. Fill one row of the table below.
7. Go to the next app. Do not copy anything else.

**Pass.** Both are true:

- The zip attaches.
- The answer describes the region under badge 3.1.

**Fail.** The zip does not attach, or the answer does not describe that region.

**What to write in "What you saw".** Three short facts: text in the message (yes or no), zip attached (yes or no), answer describes the region under badge 3.1 (yes or no).

| App | Result (pass or fail) | What you saw | Notes |
| --- | --- | --- | --- |
| Claude desktop, Chat |  |  |  |
| Claude desktop, Code tab |  |  |  |
| Claude Code in Terminal |  |  |  |
| ChatGPT desktop |  |  |  |
| claude.ai in Chrome |  |  |  |
| chatgpt.com in Chrome |  |  |  |
| Cursor |  |  |  |
| Codex app |  |  |  |

---

## What to send back

Fill the tables. Then commit the file with the message `docs: record paste hand-test results`:

```
git add docs/runbooks/2026-11-01-paste-hand-tests.md
git commit -m "docs: record paste hand-test results"
```
