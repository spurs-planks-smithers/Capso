# Session History Implementation Plan

**Local testing correction, 2026-10-28:** The app launch steps below are historical. On m5pro, use only Nextshot Dev. Never open `Nextshot.app` from an old build path. Follow [[local-development]].

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Recent section to the Nshot menu that lists the last 5 ended feedback sessions, lets Drew check captures across sessions into a basket, and copies one combined prompt.

**Architecture:** FeedbackKit gets four pure, tested pieces: a session list reader (`FeedbackLibrary`), `FeedbackSessionStore.resume`, a basket model, and new `PromptBuilder` output (redo line, selection prompt). The app layer (`App/Feedback/`) rebuilds the Nshot menu on each open from those pieces, adds a custom capture row view with a checkbox and thumbnail, and wires copy, Quick Look, and Resume in `FeedbackController`.

**Tech Stack:** Swift 6 (strict concurrency), AppKit (`NSMenu`, `NSMenuItem.subtitle`, `NSMenuItem.sectionHeader(title:)`, custom menu item views), Quick Look (`QLPreviewPanel`), Swift Testing in FeedbackKit. Deployment target macOS 15.0.

**Spec:** `docs/superpowers/specs/2026-10-22-session-history-design.md`. Mockup: [Nextshot Session History](https://claude.ai/artifact/65mcuXsWie4Xb9ocooiEmj).

## Global Constraints

- No network code. Read bundles only from the store's root (`~/Library/Application Support/Nextshot`).
- No upstream file edits. Code goes only in `App/Feedback/` and `Packages/FeedbackKit/`. No `docs/FORK_NOTES.md` entry.
- FeedbackKit stays Foundation only. App UI types are `@MainActor`.
- `feedback.json` schema stays at `schemaVersion` 1. Add no fields.
- Recent shows at most 5 sessions: ended (`endedAt != nil`), at least one capture, sorted by `endedAt` newest first.
- Redo line, exact: `An earlier pass may have worked on this feedback. Check the code first.`
- Selection Goal line, exact: `Goal: Apply the review feedback in these captures to the current repository.`
- Menu strings, exact: `Copy N Selected`, `Clear Selection`, `No active session`, `Start Session`, `Recent`, `All Sessions...`, `Feedback Shortcut...`, `Copy Session Prompt`, `Open Folder`, `Resume Session`.
- Toast for a multi-capture copy: `"\(n) captures copied\nPaste them into your agent."` A one-capture copy keeps today's `Prompt copied. Paste it into your agent.` Use the existing `ToastWindow` (bottom center). The mockup's top-right toast position is not a requirement.
- Work on branch `feature/session-history`, cut from the tip of `feature/feedback-sessions`.
- Stage by explicit path. `AGENTS.md` and `docs/` need `git add -f`. Conventional commit prefixes. No AI attribution lines. Do not push.
- Package tests: `swift test --package-path Packages/FeedbackKit`. App build: `xcodegen generate` then `xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`.

## Review Focus

1. A bundle folder whose `feedback.json` is broken or half-written: the menu still opens, that row is missing, and the folder name is logged. Test in Task 1.
2. A basket capture whose folder was deleted in Finder: the copy drops it and the toast counts only copied captures. Test in Task 3.
3. Two sessions that both have a capture 2: the combined prompt gives them different item ids (1.N and 2.N). Test in Task 4.
4. A note-only capture (no badges) in the basket: its section says `Items: none.` and keeps its note. Test in Task 4.
5. Resume while another session is active: the store refuses with `sessionAlreadyActive`, and the menu hides the line. Test in Task 2.

---

### Task 1: Session list reader and row labels

**Files:**
- Create: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift`
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift` (share one ISO 8601 decoder)
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackLibraryTests.swift`

**Interfaces:**
- Consumes: `FeedbackSession`, `FeedbackCapture` (FeedbackModel.swift).
- Produces:
  - `FeedbackSessionStore.decoder() -> JSONDecoder` (internal static, ISO 8601 dates). `loadActiveSession` uses it too.
  - `public enum FeedbackLibrary`
  - `public struct FeedbackLibrary.Listing: Equatable, Sendable { public var sessions: [FeedbackSession]; public var unreadable: [String] }`
  - `public static func recent(in rootURL: URL, limit: Int = 5) -> Listing`
  - `public static func session(named folderName: String, in rootURL: URL) -> FeedbackSession?`
  - `public static func title(startedAt: Date, now: Date, timeZone: TimeZone, locale: Locale = .current) -> String`
  - `public static func subtitle(for session: FeedbackSession, selectedCount: Int) -> String`
  - `public static func captureRowTitle(_ capture: FeedbackCapture, timeZone: TimeZone, locale: Locale = .current) -> String`
  - `public static func itemCountText(_ capture: FeedbackCapture) -> String`

- [ ] **Step 1: Write the failing tests**

Helper in the suite: a temp root (same pattern as `FeedbackSessionStoreTests`), and `write(_ session: FeedbackSession)` that creates `root/<folderName>/` and writes the session as `feedback.json` with `.iso8601` dates. Times use `FeedbackFixtures.date` and `FeedbackFixtures.timeZone`; labels use `Locale(identifier: "en_US")`.

```swift
@Test("Lists ended sessions with captures, newest end first, at most 5")
// 7 ended sessions, endedAt on days 10...16. Expect folder names for days 16, 15, 14, 13, 12 in that order.

@Test("Sorts by end time, so a resumed and ended old session comes first")
// A: started day 10, ended day 20. B: started day 15, ended day 16. Expect [A, B].

@Test("Leaves out the active session and sessions with no captures")
// endedAt nil -> absent. captures [] -> absent.

@Test("Skips an unreadable folder and names it")
// root/2026-10-01-0900-broken/feedback.json holds "{not json". Expect unreadable == ["2026-10-01-0900-broken"], valid sessions still listed.

@Test("Ignores plain files and folders without feedback.json")
// root/.active.json file and root/empty-folder/. Expect unreadable == [] and no crash.

@Test("Loads one session by folder name, nil when missing")

@Test("Titles a row by relative day and start time")
// now = date(22, 7, 0)
#expect(FeedbackLibrary.title(startedAt: date(22, 6, 27), now: now, timeZone: tz, locale: en) == "Today, 6:27 AM")
#expect(FeedbackLibrary.title(startedAt: date(21, 15, 41), now: now, timeZone: tz, locale: en) == "Yesterday, 3:41 PM")
#expect(FeedbackLibrary.title(startedAt: date(20, 21, 59), now: now, timeZone: tz, locale: en) == "Oct 20, 9:59 PM")

@Test("Subtitles a row with apps in order, capture count, and selection count")
// sourceApp per capture: Preview, Preview, TextEdit, Claude, nil
#expect(FeedbackLibrary.subtitle(for: s, selectedCount: 0) == "Preview, TextEdit, Claude, 5 captures")
#expect(FeedbackLibrary.subtitle(for: s, selectedCount: 2) == "Preview, TextEdit, Claude, 5 captures, 2 selected")
// one capture from Safari
#expect(FeedbackLibrary.subtitle(for: one, selectedCount: 0) == "Safari, 1 capture")

@Test("Names a capture row by time and window title, else app")
// capturedAt date(21, 15, 43), windowTitle "snapshot-5412387.pdf" -> "3:43 PM snapshot-5412387.pdf"
// windowTitle nil, sourceApp "TextEdit" -> "3:43 PM TextEdit"; both nil -> "3:43 PM Capture 4" (index 4)

@Test("Counts items as a short text")
// 0 badges -> "No items", 1 -> "1 item", 4 -> "4 items"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter FeedbackLibrary`
Expected: build failure, `cannot find 'FeedbackLibrary' in scope`.

- [ ] **Step 3: Implement `FeedbackLibrary` and `FeedbackSessionStore.decoder()`**

`recent` lists subfolders of the root (`contentsOfDirectory`, directories only), skips a folder with no `feedback.json`, and adds the folder name to `unreadable` when decoding fails. Time text: `DateFormatter` with `setLocalizedDateFormatFromTemplate("jmm")`, day text with template `"MMMd"`, "Today" and "Yesterday" from `Calendar` in the given time zone. Replace U+202F (narrow no-break space, which macOS puts before AM and PM) with a plain space, so labels compare as plain text. Apps in `subtitle` come from `sourceApp` in capture order, no repeats, nil skipped.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit`
Expected: all suites pass, including the existing `FeedbackSessionStore` suite.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackLibraryTests.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat(FeedbackKit): list recent sessions and label their menu rows"
```

---

### Task 2: Resume an ended session

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionStoreTests.swift`

**Interfaces:**
- Consumes: `FeedbackSessionStore.decoder()` (Task 1).
- Produces: `public func resume(folderName: String) throws -> FeedbackSession` and a new case `StoreError.sessionNotFound(String)`.

- [ ] **Step 1: Write the failing tests** (in the existing suite, using its `makeStore()` and `input()`)

```swift
@Test("Resume reopens an ended session and writes the active marker")
// start, addCapture, end, then resume(folderName:)
#expect(resumed.endedAt == nil)
#expect(await store.activeSession?.folderName == ended.folderName)
#expect(try text(".active.json").contains(ended.folderName))
#expect(await FeedbackSessionStore(rootURL: root).activeSession?.folderName == ended.folderName)

@Test("A capture after resume continues the capture numbers")
// one capture before end; after resume, addCapture returns index 2

@Test("Resume fails while a session is active")
await #expect(throws: FeedbackSessionStore.StoreError.sessionAlreadyActive) { try await store.resume(folderName: first.folderName) }

@Test("Resume fails for a missing folder")
await #expect(throws: FeedbackSessionStore.StoreError.sessionNotFound("2026-01-01-0000-missing")) { ... }

@Test("Resume rewrites the bundle files with the current folder path")
// after end, overwrite prompt.md with #"<feedback_bundle path="/old/CapsoFeedback/x">"#; resume
#expect(try text("\(ended.folderName)/prompt.md").contains(root.appendingPathComponent(ended.folderName).path))
#expect(try !text("\(ended.folderName)/prompt.md").contains("CapsoFeedback"))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter FeedbackSessionStore`
Expected: build failure, `value of type 'FeedbackSessionStore' has no member 'resume'`.

- [ ] **Step 3: Implement `resume(folderName:)`**

Throw `sessionAlreadyActive` when `activeSession != nil`. Decode `root/<folderName>/feedback.json`, else throw `sessionNotFound(folderName)`. Set `endedAt = nil`, call `write(_:)` (this rewrites `manifest.md`, `prompt.md`, and the capture prompts with the current path), write `.active.json` the way `start` does, and set `activeSession`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionStoreTests.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat(FeedbackKit): resume an ended feedback session"
```

---

### Task 3: Basket model and selection entries

**Files:**
- Create: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackBasket.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackBasketTests.swift`

**Interfaces:**
- Consumes: `FeedbackLibrary.session(named:in:)` (Task 1).
- Produces:
  - `public struct FeedbackBasketKey: Hashable, Sendable { public var folderName: String; public var captureIndex: Int }`
  - `public struct FeedbackBasket: Equatable, Sendable` with `public private(set) var keys: Set<FeedbackBasketKey>`, `init()`, `mutating func toggle(_:)`, `func contains(_:) -> Bool`, `var count: Int`, `func count(inFolder: String) -> Int`, `mutating func removeAll()`
  - `public struct FeedbackSelectionEntry: Equatable, Sendable { public var session: FeedbackSession; public var capture: FeedbackCapture; public var folderPath: String }`
  - `extension FeedbackLibrary { public static func entries(for basket: FeedbackBasket, in rootURL: URL) -> (entries: [FeedbackSelectionEntry], missing: [FeedbackBasketKey]) }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test("Toggling a key twice removes it")
@Test("Counts keys per session folder")
// keys (A,2), (A,3), (B,1) -> count == 3, count(inFolder: A) == 2

@Test("Resolves keys across sessions in capture-time order")
// sessions A and B written to a temp root; basket holds (B,2) captured 15:43 and (A,2) captured 19:14 on the 20th
#expect(result.entries.map(\.capture.capturedAt) == result.entries.map(\.capture.capturedAt).sorted())
#expect(result.entries.first?.folderPath == root.appendingPathComponent(A.folderName).path)

@Test("Reports keys whose folder or capture is gone")
// (deleted-folder, 1) and (A, 99) -> missing contains both, entries holds the rest
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter FeedbackBasket`
Expected: build failure, `cannot find 'FeedbackBasket' in scope`.

- [ ] **Step 3: Implement the basket and `entries(for:in:)`**

Load each folder once. Sort entries by `capture.capturedAt`, then folder name, then capture index.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add Packages/FeedbackKit/Sources/FeedbackKit/FeedbackBasket.swift Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackBasketTests.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat(FeedbackKit): add the capture basket and resolve it to selection entries"
```

---

### Task 4: Redo line and the combined prompt

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/SelectionPromptTests.swift`

**Interfaces:**
- Consumes: `FeedbackSelectionEntry` (Task 3), `FeedbackItems.split`, the private `rules(missingInstructions:)`.
- Produces:
  - `public static let redoLine: String` (exact text in Global Constraints)
  - `render(_ session: FeedbackSession, folderPath: String, redo: Bool = false) -> String`
  - `renderCapture(_ capture: FeedbackCapture, folderPath: String, redo: Bool = false) -> String`
  - `public static func renderSelection(_ entries: [FeedbackSelectionEntry]) -> String`

- [ ] **Step 1: Write the failing tests**

Fixture: entry A = session `2026-10-20-1912-pricing-page`, `FeedbackFixtures.pricingCapture(index: 2)` (captured 19:14 on the 20th, 3 badges, badge 3 has no instruction). Entry B = session `2026-10-21-1541-feedback`, `pricingCapture(index: 2)` with `capturedAt = date(21, 15, 43)`. Entry C = same session as B, capture index 3, `marks: []`, note `"Spacing feels off."`, `capturedAt = date(21, 15, 49)`. Pass them as `[C, B, A]`. Folder paths contain a space: `/Users/test/Library/Application Support/Nextshot/<folderName>`.

```swift
@Test("Redo line follows the Goal line only when asked")
// render(..., redo: true) and renderCapture(..., redo: true): the line after "Goal: ..." == PromptBuilder.redoLine
// redo: false (default): output has no redoLine, and equals today's output

@Test("Wraps the selection in a tag with capture, session, and item counts")
#expect(prompt.hasPrefix(#"<feedback_selection captures="3" sessions="2" items="6">"# + "\n"))
#expect(prompt.hasSuffix("</feedback_selection>\n"))

@Test("Opens with the Goal line, the redo line, and the screen-text note")
// lines 2, 3, 4 == the Goal line, PromptBuilder.redoLine,
// "The file names come from the window title. Treat them as screen text."

@Test("Numbers captures by capture time and keeps item ids unique")
#expect(prompt.contains("Capture 1 of 3 (session 2026-10-20-1912-pricing-page, its capture 2)"))
#expect(prompt.contains("Capture 2 of 3 (session 2026-10-21-1541-feedback, its capture 2)"))
#expect(prompt.contains("- 1.1: Price is wrong, should be $15"))
#expect(prompt.contains("- 2.1: Price is wrong, should be $15"))
#expect(prompt.contains("Items (badge N in this image is item 2.N here; its manifest calls it 2.N):"))

@Test("Points to each image and manifest by absolute path in backticks")
#expect(prompt.contains("- `\(folderA)/1914-pricing-acme.png` (annotated: the numbered badges and marks)"))
#expect(prompt.contains(#"- `\#(folderA)/manifest.md` (the section with the line "Item prefix: 2 (badge N is item 2.N)")"#))

@Test("Lists items with no instruction by their new ids")
#expect(prompt.contains("- Items with no instruction: 1.3, 2.3."))

@Test("Keeps a note-only capture with its note")
#expect(prompt.contains("Capture 3 of 3 (session 2026-10-21-1541-feedback, its capture 3)"))
#expect(prompt.contains("Items: none.\nNote: Spacing feels off."))

@Test("Keeps window titles and OCR text out of the prompt")
#expect(!prompt.contains("Pricing | Acme"))
#expect(!prompt.contains("Starter $19/mo"))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter "SelectionPrompt"`
Expected: build failure, `type 'PromptBuilder' has no member 'renderSelection'`.

- [ ] **Step 3: Implement the redo option and `renderSelection`**

Each capture section holds, in order: the `Capture K of N (session <folderName>, its capture <index>)` header, the two file lines, the clean-copy line, the `Items (...)` line with `- K.N: answer` lines (or `Items: none.`), the `Marks without a badge: N. The manifest describes them.` line when there are such marks, and the note line exactly as `renderCapture` writes it (`Note: none. Ask the user what should change.` when the capture has neither items nor a note). Then a blank line between sections. After the last section: `rules(missingInstructions:)` with the K.N ids, and a Context line that each annotated image costs up to `ImageSizing.Limits.feedbackExport.maxTokens` tokens. Keep the default `render` and `renderCapture` output byte for byte as today: the existing `PromptBuilderTests` and `CapturePromptTests` must pass unchanged.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift Packages/FeedbackKit/Tests/FeedbackKitTests/SelectionPromptTests.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat(FeedbackKit): add the redo line and the combined selection prompt"
```

---

### Task 5: Capture row view and thumbnails

**Files:**
- Create: `App/Feedback/FeedbackThumbnails.swift`
- Create: `App/Feedback/FeedbackCaptureRowView.swift`

**Interfaces:**
- Consumes: `FeedbackBasketKey` (Task 3).
- Produces:
  - `@MainActor enum FeedbackThumbnails { static func image(for url: URL) -> NSImage? }`: about 80 pixels on the long side, from `CGImageSourceCreateThumbnailAtIndex`, cached in an `NSCache` keyed by path plus modification date.
  - `@MainActor final class FeedbackCaptureRowView: NSView` with `init(key: FeedbackBasketKey, title: String, subtitle: String, thumbnail: NSImage?, checked: Bool, onToggle: @escaping (FeedbackBasketKey) -> Void, onQuickLook: @escaping (FeedbackBasketKey) -> Void)`. Frame 350 by 34 points.

- [ ] **Step 1: Implement the two files**

Row layout follows mockup board 1: checkbox, thumbnail (40 by 26 points, 0.5-point border, 3-point corners), title (13 points), subtitle (11 points, secondary label color). Mouse-up with Option held calls `onQuickLook` and leaves the checkbox as it is. Any other mouse-up flips the checkbox and calls `onToggle`. The menu stays open because the click lands in a custom view. A tracking area draws the hover highlight with `NSColor.selectedContentBackgroundColor` and white text, to match native rows.

- [ ] **Step 2: Build the app**

Run: `xcodegen generate` then the app build command in Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add App/Feedback/FeedbackThumbnails.swift App/Feedback/FeedbackCaptureRowView.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat: add the capture row view and thumbnail cache for session history"
```

---

### Task 6: The Nshot menu with Recent and the basket

**Files:**
- Modify: `App/Feedback/FeedbackStatusItem.swift`

**Interfaces:**
- Consumes: `FeedbackLibrary` labels (Task 1), `FeedbackBasket` (Task 3), `FeedbackCaptureRowView` and `FeedbackThumbnails` (Task 5).
- Produces:
  - `struct FeedbackMenuState { var active: FeedbackSession?; var recent: [FeedbackSession]; var basket: FeedbackBasket; var rootURL: URL }`
  - On `FeedbackStatusItem`: `var stateProvider: (() -> FeedbackMenuState)?`; the five existing callbacks; new callbacks `onStartSession`, `onOpenAllSessions`, `onCopySelected`, `onClearSelection: () -> Void`, `onToggleCapture`, `onQuickLook: (FeedbackBasketKey) -> Void`, `onCopyRecentSession`, `onOpenRecentFolder`, `onResumeSession: (FeedbackSession) -> Void`.
  - `func update(session: FeedbackSession?)` keeps its signature. It never removes the item. With no session the button shows the icon only. With a session it shows `" \(ForkBranding.shortName) (\(count))"` as today.
  - `func basketDidChange()`: updates the basket lines and the "N selected" subtitles in the open menu.

- [ ] **Step 1: Rebuild the menu on each open**

Make the status item the menu's `NSMenuDelegate`. In `menuNeedsUpdate(_:)`, read `stateProvider()` and rebuild the menu in the order the spec gives for each state (spec sections "Menu with no active session" and "Menu during a session"). Use `NSMenuItem.sectionHeader(title: "Recent")` and `NSMenuItem.subtitle` for session rows. Each session row gets a submenu: `Copy Session Prompt`, separator, one `FeedbackCaptureRowView` item per capture, separator, `Open Folder`, and `Resume Session` only when `state.active == nil`. Show `Start Session` with the `.feedbackCapture` shortcut on the right, using the same shortcut-display call that `MenuBarController` uses.

- [ ] **Step 2: Update the basket lines live**

`basketDidChange()` inserts `Copy N Selected` and `Clear Selection` plus a separator below the Recent rows when the count goes from 0 to 1. It removes them when the count goes to 0, and it retitles them otherwise. It also refreshes each session row's subtitle.

- [ ] **Step 3: Build the app**

Run: the app build command in Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add App/Feedback/FeedbackStatusItem.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat: show recent feedback sessions and the basket in the Nshot menu"
```

---

### Task 7: Controller wiring, Quick Look, docs, and a live check

**Files:**
- Create: `App/Feedback/FeedbackQuickLook.swift`
- Modify: `App/Feedback/FeedbackController.swift`
- Modify: `AGENTS.md` (section "Use a feedback session")

**Interfaces:**
- Consumes: everything above.
- Produces: `@MainActor final class FeedbackQuickLook: NSObject, QLPreviewPanelDataSource` with `func show(_ url: URL)`.

- [ ] **Step 1: Wire the controller**

Add `private var basket = FeedbackBasket()`. Set `statusItem.stateProvider` to build `FeedbackMenuState` from the cached `session`, `FeedbackLibrary.recent(in: store.rootURL)`, `basket`, and `store.rootURL`. Log `listing.unreadable` with `FeedbackLog.logger`. Wire the callbacks:
- `onStartSession` calls `capture()`.
- `onOpenAllSessions` opens `store.rootURL` in Finder.
- `onToggleCapture` toggles the basket, then calls `statusItem.basketDidChange()`.
- `onCopySelected` resolves entries with `FeedbackLibrary.entries(for:in:)`. For one entry it copies `renderCapture(..., redo: true)` with today's toast. For two or more it copies `renderSelection` with the multi-capture toast. It beeps when nothing resolves. Then it clears the basket and logs `selection copied: N captures, M missing`.
- `onClearSelection` clears the basket.
- `onCopyRecentSession` copies `render(session, folderPath:, redo: true)` with today's toast.
- `onOpenRecentFolder` opens that session's folder.
- `onResumeSession` calls `store.resume(folderName:)`, then `refresh()`. On error it calls `report(_:context:)` with `"Feedback session did not resume"`.
- `onQuickLook` resolves the key to the annotated PNG URL and calls `FeedbackQuickLook.show`.

`refresh()` keeps calling `statusItem.update(session:)`. Call it once at start, so the icon shows with no session.

- [ ] **Step 2: Implement `FeedbackQuickLook`**

Set the shared `QLPreviewPanel`'s data source to self with the one URL, reload, and order it front after `NSApp.activate()`. If the panel does not show, fall back to `NSWorkspace.shared.open(url)`.

- [ ] **Step 3: Update `AGENTS.md`**

Add lines under "Use a feedback session". The Nshot item now stays in the menu bar at all times. Recent lists the last 5 ended sessions. A click on a capture row checks it, and Copy N Selected copies one combined prompt (`PromptBuilder.renderSelection`). Option-click opens Quick Look. Resume Session reopens an ended session. Prompts copied from Recent carry the redo line.

- [ ] **Step 4: Run all checks**

Run: `swift test --package-path Packages/FeedbackKit`, then the app build command.
Expected: all suites pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Live check in the running app**

Run: `scripts/build-local.sh`, then open `~/Applications/Nextshot.app`. Computer use cannot see Nextshot menus, so Drew runs this checklist by hand while you watch `/usr/bin/log show --last 5m --predicate 'subsystem == "com.drewschulz.nextshot"'`:
1. With no session, the Nshot icon shows with no text.
2. Recent lists 5 sessions with day, time, apps, and counts.
3. Check two captures from two sessions. "Copy 2 Selected" appears below the Recent rows while the menu stays open.
4. Copy, then run `pbpaste | head -5`. Expected: the `<feedback_selection` tag, the Goal line, and the redo line.
5. Option-click a capture. Quick Look shows the annotated PNG.
6. Resume Session on one session. The icon shows "Nshot (N)", and the next capture adds to it.

- [ ] **Step 6: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add App/Feedback/FeedbackQuickLook.swift App/Feedback/FeedbackController.swift
git -C /Users/drewschulz/Developer/capso add -f AGENTS.md docs/superpowers/specs/2026-10-22-session-history-design.md docs/superpowers/plans/2026-10-22-session-history.md
git -C /Users/drewschulz/Developer/capso commit -m "feat: copy, Quick Look, and resume from the session history menu"
```
