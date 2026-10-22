# Session History Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nshot menu read session files only when they change, and repair old bundles whose `manifest.md` and `prompt.md` still name the pre-rename `CapsoFeedback` folder.

**Architecture:** FeedbackKit gets a value-type session cache keyed by each `feedback.json` file's modification date and size, a stale-files check, and a store method that rewrites a bundle's files from its `feedback.json`. The app keeps one cache in `FeedbackController`, passes the basket straight to the status item, and repairs a bundle before it copies a prompt that points into it.

**Tech Stack:** Swift 6 (strict concurrency), Foundation, AppKit, Swift Testing. macOS 15.0.

**Spec:** `docs/superpowers/specs/2026-10-22-session-history-design.md` (the feature) and the follow-up list from the final review of PR spurs-planks-smithers/Capso#3.

## Global Constraints

- No network code. No upstream file edits. Code goes only in `App/Feedback/` and `Packages/FeedbackKit/`.
- FeedbackKit stays Foundation only. App UI types are `@MainActor`.
- `feedback.json` schema stays at `schemaVersion` 1. Add no fields.
- The Recent list keeps its rules: ended sessions with at least one capture, newest `endedAt` first, folder name breaks a tie, at most 5, unreadable folder names sorted.
- A repair rewrites `feedback.json`, `manifest.md`, `prompt.md`, and each capture prompt with the current folder path. It changes no session field except `folderName`, which becomes the directory name.
- Branch `feature/session-history-followups`, cut from `feature/session-history` at `95bb514`. PR against `feature/session-history`.
- Stage by explicit path. `docs/` and `AGENTS.md` need `git add -f`. Conventional commit prefixes. No AI attribution. Do not push.
- Before each commit, run `git -C /Users/drewschulz/Developer/capso log --oneline 95bb514..HEAD` and `git diff --stat`. Another session sometimes commits in this checkout. Stage only your own changes.
- Package tests: `swift test --package-path Packages/FeedbackKit`. App build: `xcodegen generate`, then `xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`.

## Review Focus

1. A `feedback.json` rewritten within the same second as the last read: the cache must still see the change (modification date with sub-second precision, plus size). Test in Task 1.
2. A bundle folder deleted in Finder while it is cached: it leaves the Recent list on the next read. Test in Task 1.
3. A repair on the active session's folder: it writes the store's in-memory session, never an older copy from disk. Test in Task 1.
4. A repair that fails (disk error, missing folder): the copy still happens, from `feedback.json`, and the failure is logged. Covered by reading Task 2.
5. A folder name with `/` or `..` passed to the repair: refused with `sessionNotFound`. Test in Task 1.

---

### Task 1: Session cache, stale-file check, repair, tag pattern

**Files:**
- Create: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionCache.swift`
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift` (`recent` uses a throwaway cache; add `bundleFilesNeedRepair`)
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift` (add `repairBundleFiles`)
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/ScreenText.swift:31` (pattern)
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionCacheTests.swift`, `Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionStoreTests.swift`

**Interfaces:**
- Consumes: `FeedbackLibrary.Listing`, `FeedbackSessionStore.decoder()`, `FeedbackSessionStore.sessionFileName`, the store's private `write(_:)`.
- Produces:
  - `public struct FeedbackSessionCache: Sendable` with `public init()` and `public mutating func recent(in rootURL: URL, limit: Int = 5) -> FeedbackLibrary.Listing`.
  - `FeedbackLibrary.recent(in:limit:)` keeps its signature and output. It becomes `var cache = FeedbackSessionCache(); return cache.recent(in: rootURL, limit: limit)`, so the filter, sort, and limit rule lives in one place.
  - `public static func bundleFilesNeedRepair(folderName: String, in rootURL: URL) -> Bool` on `FeedbackLibrary`.
  - `public func repairBundleFiles(folderName: String) throws` on `FeedbackSessionStore`.

- [ ] **Step 1: Write the failing tests**

```swift
// FeedbackSessionCacheTests.swift (temp root and write(_:) helper as in FeedbackLibraryTests)
@Test("A fresh cache lists the same sessions as FeedbackLibrary.recent")
@Test("Reuses a decoded session while feedback.json is unchanged")
// After one read: overwrite feedback.json with "{" padded with spaces to the same byte count,
// then set its modification date back to the original (FileManager.setAttributes).
// Expect the second read to still list the session, and unreadable == [].
@Test("Decodes again when feedback.json changes")
// Rewrite with a new endedAt and set the modification date 1 second later. Expect the new endedAt.
@Test("Sees a change within the same second when the size differs")
// Rewrite with a longer valid JSON and set the same modification date. Expect the new content.
@Test("Drops a folder deleted after it was cached")
@Test("Keeps an unreadable folder listed until its file changes")
// "{not json" -> unreadable == [name]; then write valid JSON with a new date -> listed, unreadable == [].

// FeedbackSessionStoreTests.swift (existing makeStore(), input(), text(_:))
@Test("Repair rewrites manifest and prompt with the current folder path")
// start, addCapture, end; overwrite manifest.md with "Folder: /old/CapsoFeedback/x\n" and
// prompt.md with #"<feedback_bundle path="/old/CapsoFeedback/x">"#.
#expect(FeedbackLibrary.bundleFilesNeedRepair(folderName: ended.folderName, in: root))
try await store.repairBundleFiles(folderName: ended.folderName)
#expect(try text("\(ended.folderName)/manifest.md").contains("Folder: \(root.appendingPathComponent(ended.folderName).path)"))
#expect(try !text("\(ended.folderName)/prompt.md").contains("CapsoFeedback"))
#expect(!FeedbackLibrary.bundleFilesNeedRepair(folderName: ended.folderName, in: root))
// The session keeps endedAt and its captures:
#expect(FeedbackLibrary.session(named: ended.folderName, in: root) == ended)
@Test("Repair on the active session writes the in-memory session")
// start, addCapture, setNote(...) ; overwrite feedback.json on disk with an older copy (no note);
// repairBundleFiles(folderName: active) -> feedback.json on disk has the note again.
@Test("Repair refuses a missing folder or a path name")
await #expect(throws: FeedbackSessionStore.StoreError.sessionNotFound("2026-01-01-0000-missing")) { ... }
await #expect(throws: FeedbackSessionStore.StoreError.sessionNotFound("../x")) { ... }
@Test("A missing folder needs no repair")
#expect(!FeedbackLibrary.bundleFilesNeedRepair(folderName: "2026-01-01-0000-missing", in: root))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter "FeedbackSessionCache|FeedbackSessionStore"`
Expected: build failure, `cannot find 'FeedbackSessionCache' in scope`.

- [ ] **Step 3: Implement**

- Cache entry key: the folder name. Entry value: the file's modification date (from `FileManager.attributesOfItem(atPath:)`, `.modificationDate`), its size (`.size`), and the decode result (`FeedbackSession?`, nil for a failed decode). On each `recent` call, list the root, read each `feedback.json`'s date and size, decode only when the date or size differs from the entry, and remove entries for folders that are gone. A folder with no `feedback.json` stays ignored.
- `bundleFilesNeedRepair`: false when the name is refused or the session does not load. Otherwise true when `manifest.md` or `prompt.md` is missing, or does not contain the bundle's current absolute folder path (`rootURL/<folderName>`).
- `repairBundleFiles`: throw `sessionNotFound(folderName)` when the name is refused or the session does not load (reuse `FeedbackLibrary.session(named:in:)`). When `activeSession?.folderName == folderName`, call `write(activeSession)`. Otherwise set `session.folderName = folderName` and call `write(session)`. It never changes `activeSession` or `.active.json`.
- `ScreenText.swift:31`: change the pattern to `#"</?\s*feedback_[^>]*>"#`. The matches stay the same; the overlapping `[a-z_]*` goes away.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionCache.swift Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift Packages/FeedbackKit/Sources/FeedbackKit/ScreenText.swift Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionCacheTests.swift Packages/FeedbackKit/Tests/FeedbackKitTests/FeedbackSessionStoreTests.swift
git -C /Users/drewschulz/Developer/capso commit -m "feat(FeedbackKit): cache sessions by file date and repair stale bundle files"
```

---

### Task 2: App wiring, small cleanups, docs

**Files:**
- Modify: `App/Feedback/FeedbackController.swift` (cache, unreadable log, repair before copy)
- Modify: `App/Feedback/FeedbackStatusItem.swift` (`basketDidChange(_:)`, Start Session item kept)
- Modify: `App/Feedback/FeedbackThumbnails.swift:20` (modification date)
- Modify: `AGENTS.md`, `docs/superpowers/specs/2026-10-22-session-history-design.md`, `docs/superpowers/plans/2026-10-22-session-history.md`

**Interfaces:**
- Consumes: `FeedbackSessionCache`, `FeedbackLibrary.bundleFilesNeedRepair(folderName:in:)`, `FeedbackSessionStore.repairBundleFiles(folderName:)` (Task 1).
- Produces: `func basketDidChange(_ basket: FeedbackBasket)` on `FeedbackStatusItem`, replacing `basketDidChange()`.

- [ ] **Step 1: Controller**

- Replace `recentCache`, `recentCacheLifetime`, and the `recentCache = nil` lines with `private var sessionCache = FeedbackSessionCache()`. The state provider calls `sessionCache.recent(in: store.rootURL)` on every call.
- Log unreadable folders only when the sorted list differs from the last one logged (keep `private var loggedUnreadable: [String] = []`). Keep today's log format and privacy.
- `onToggleCapture` calls `statusItem.basketDidChange(basket)`.
- Before Copy Session Prompt from Recent, Copy N Selected, and the one-capture copy, repair each distinct bundle folder the prompt points into when `bundleFilesNeedRepair` says so: `try await store.repairBundleFiles(folderName:)`. Then copy. On a repair error, log it with `FeedbackLog.logger.error` and copy anyway. Log `bundle repaired: <folderName>` (folder name private) on success. Wrap the copy functions in `Task { @MainActor in ... }` as the controller already does for store calls. Read the basket into a local before the `await`, and clear it before the `await`, so a click during the repair cannot double-copy.

- [ ] **Step 2: Status item and thumbnails**

- `basketDidChange(_ basket: FeedbackBasket)` uses the given basket and never calls `stateProvider`.
- Keep one Start Session item for the status item's lifetime. Call `setShortcut(for: .feedbackCapture)` on it once. Each rebuild adds that same item again (remove it from its old menu first if `item.menu != nil`).
- `FeedbackThumbnails.swift:20`: read the modification date with `FileManager.default.attributesOfItem(atPath:)[.modificationDate]`, which never returns a stale cached value.

- [ ] **Step 3: Docs**

- Spec, section "Menu during a session": move the basket-lines bullet after the bullet "Then come the Recent section and the bottom lines, the same as in the idle menu."
- Plan `docs/superpowers/plans/2026-10-22-session-history.md` lines 361 and 421: replace "at the top" with "below the Recent rows".
- `AGENTS.md`, section "Use a feedback session": after the redo-line bullet, add `- A copy from Recent first rewrites a bundle's \`manifest.md\` and \`prompt.md\` when they name an old folder, as bundles from before the 2026-10-21 rename do.`

- [ ] **Step 4: Build and relaunch**

Run: `swift test --package-path Packages/FeedbackKit`, then the app build. Expected: all suites pass; `** BUILD SUCCEEDED **` with no new warnings in `App/Feedback`. If `~/Library/Application Support/Nextshot/.active.json` is absent, run `scripts/build-local.sh`, quit and reopen `~/Applications/Nextshot.app`, and confirm with `pgrep -fl Nextshot`. Never run `scripts/release-notarized.sh`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/drewschulz/Developer/capso add App/Feedback/FeedbackController.swift App/Feedback/FeedbackStatusItem.swift App/Feedback/FeedbackThumbnails.swift
git -C /Users/drewschulz/Developer/capso add -f AGENTS.md docs/superpowers/specs/2026-10-22-session-history-design.md docs/superpowers/plans/2026-10-22-session-history.md docs/superpowers/plans/2026-10-22-session-history-followups.md
git -C /Users/drewschulz/Developer/capso commit -m "fix: read sessions only when they change and repair old bundles before a copy"
```

- [ ] **Step 6: Hand check (Drew)**

1. Open the Nshot menu twice. It opens with no pause.
2. Hover "Oct 20, 9:59 PM" (or another pre-rename session) and click Copy Session Prompt. Then `grep -c CapsoFeedback "$HOME/Library/Application Support/Nextshot/2026-10-20-2159-feedback/manifest.md"` prints 0.
