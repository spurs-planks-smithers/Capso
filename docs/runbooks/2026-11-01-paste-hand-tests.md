# Paste hand tests

One paste can carry text, one image, and a file. Each chat app handles that paste in its own way. These three tests show what each app does with the paste that Nextshot plans to copy. T1 pastes a prompt with one image. T4 pastes long text and checks that the app keeps the last line. T6 pastes a prompt with a zip file. You fill the result tables by hand. The Part C plan starts from your results.

## Before you start

1. Open Terminal in the repository folder. This is the folder that holds `project.yml`. Run every command in this file from there.
2. Build the prompt tool once. The scripts call it to render the prompts and the zip.

```
swift build --package-path Packages/FeedbackKit --product nextshot-prompt
```

3. Know what the scripts change. Each script overwrites your clipboard (the place where macOS holds what you copy). Copy anything you need before you start. The test paste stays on the clipboard until you copy something else. After the last test, copy any word to replace it.
4. Plan your time. T1 and T6 take about 15 minutes in all. T4 takes about 20 more minutes if every app passes at 15000 characters. It takes longer if some apps fail, because each failure adds another try at a shorter length. The 20 minutes does not include the time to make the eight long chats. Run T4 last.
5. Know what leaves your Mac. Each paste goes to the cloud service of the app you test. T1 and T4 send a screenshot of the nextshot.dev page and a prompt about it. T6 sends a zip file with two captures: the Settings window, and a Claude desktop session window. None of these hold private data. Deny any request from an app to read, edit, or run files. The tests need no file access.

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

### Long chat

A long chat is a chat with 20 or more earlier messages. Your messages and the replies both count. Make one for each app before T4. Send `Reply with one word: OK` ten times in one chat. That gives 20 messages, 10 sent and 10 replies. Use the same long chat for every T4 try in that app.

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

**What it tests.** How long a paste each app keeps. The text ends with a fixed last line. The question asks the app to quote that line.

**What the text is.** It is the capture prompt of the round `2026-10-31-2125-feedback`, with the same screenshot. The prompt is 3462 characters long, so `t4-2000` cuts it to fit. The longer modes add the item lines of the prompt again and again after the prompt, until the text is the full length. Every text ends with this line:

```
LAST LINE: blue heron 47
```

**The modes.** There are four. Each script prints the same lines as T1, with the new character count. Check that the count matches the mode, and that item 1 lists text and a PNG. The `t4-2000` line also says that the prompt was cut to fit.

```
swift scripts/paste-test/paste-test.swift t4-15000
swift scripts/paste-test/paste-test.swift t4-10000
swift scripts/paste-test/paste-test.swift t4-5000
swift scripts/paste-test/paste-test.swift t4-2000
```

**Fixed question.**

```
Quote the last line of my message.
```

**The step-down method.** The table has one row for each app and chat kind. There are two chat kinds: a new chat, and a long chat (see "Long chat" above). Test each row like this:

1. Run `t4-15000`. Paste it and send the question. If the answer contains `blue heron 47`, stop. Write `15000` in the row.
2. If it does not, run `t4-10000` and try again.
3. If it still does not, run `t4-5000`. Then, if needed, run `t4-2000`.
4. Stop at the first length that passes. Write that length in the row. If no length passes, write `none`.

For a new chat row, open a new chat for every try. For a long chat row, use the long chat of that app for every try.

**A faster order.** The clipboard keeps the paste while you copy nothing else. So run each mode once and use it for all the rows that still need that length. Run `t4-15000` and test all 16 rows. Then run `t4-10000` and test only the rows that failed. Then `t4-5000`, then `t4-2000`. The result is the same as the step-down method for each row.

**Steps for each try.**

1. Run the mode. Run it again if you copy anything else.
2. Open the app. Open a new chat or the long chat, as the row says.
3. Click the message box. Type the fixed question. Press Shift+Return to start a new line. Press Command+V. The paste goes after the question, so the last line of the message is `LAST LINE: blue heron 47`.
4. Before you send, look at the message box. Note the shape of the paste: inline text, a "Pasted text" tile, or a file attachment.
5. Press Return to send. Wait for the whole answer.
6. Check the answer. Go to the next row, or to the next length for this row.

**Pass.** The answer contains `blue heron 47`.

**Fail.** The answer does not contain `blue heron 47`.

**What to write in the table.**

- **Longest length that passed:** `15000`, `10000`, `5000`, `2000`, or `none`.
- **What you saw at the first failure:** the failure at the first length that failed. Write one of these: `empty attachment` (the paste became an attachment, and the app or the answer shows it empty), `text cut` (the answer quotes a line from the middle, or says the end is missing), or `other` (explain in Notes). Write `n/a` if `15000` passed.
- **Notes:** the shape of the paste (inline, tile, or file), and whether one image attached.

| App | Chat kind | Longest length that passed | What you saw at the first failure | Notes |
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

**Run the mode.** The round is `2026-10-22-1609-feedback`. It has two captures. Capture 1 shows a Claude desktop session window. Capture 2 shows the Settings window of the app, on its Permissions page.

```
swift scripts/paste-test/paste-test.swift t6 2026-10-22-1609-feedback
```

The script prints this on 2026-11-01. Check that it lists two items, a text item and a file URL item.

```
pasteboard items: 2
  item 1: public.utf8-plain-text
  item 2: public.file-url
text: 3092 characters
zip: /var/folders/.../nextshot-paste-test/nextshot-round-2026-10-22-1609-2-captures.zip, 483552 bytes
```

The command `osascript -e 'clipboard info'` lists only the first item, so it shows no file URL for this mode. To see both items, run this:

```
osascript -l JavaScript -e 'ObjC.import("AppKit"); var items = $.NSPasteboard.generalPasteboard.pasteboardItems; var out = []; for (var i = 0; i < items.count; i++) { var t = items.objectAtIndex(i).types; var names = []; for (var j = 0; j < t.count; j++) { names.push(ObjC.unwrap(t.objectAtIndex(j))); } out.push("item " + (i+1) + ": " + names.join(", ")); } out.join("\n")'
```

It prints `item 1: public.utf8-plain-text` and `item 2: public.file-url`.

**The badge.** The items in this round are 1.1, 1.2, and 2.1. Badge 2.1 is badge 1 in capture 2. To see it yourself, run this:

```
open "/Users/drewschulz/Library/Application Support/Nextshot/2026-10-22-1609-feedback/1616-claude.png"
```

**What the answer should say.** The image is a screenshot of the Settings window of the app, on its Permissions page. Badge 2.1 sits at the top left of that window, on the title bar, next to the three round window buttons (close, minimize, and zoom). A good answer names the Settings window and that top left corner. An answer about the list of permissions in the middle of the window is about the wrong region.

**Fixed question.**

```
What does the image show at badge 2.1?
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
- The answer describes the Settings window region under badge 2.1.

**Fail.** The zip does not attach, or the answer does not describe that region.

**What to write in "What you saw".** Three short facts: text in the message (yes or no), zip attached (yes or no), answer describes the Settings window region under badge 2.1 (yes or no).

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
