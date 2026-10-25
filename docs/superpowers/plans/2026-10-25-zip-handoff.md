# Zip Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package a round, or the captures checked in Recent Rounds, as one zip whose prompts name files inside the zip.

**Architecture:** FeedbackKit builds a portable text model and a file list. The app encodes JPEG, writes the zip with Foundation, copies it to Downloads, and puts the file on the clipboard. The live bundle stays absolute and stays PNG.

**Tech Stack:** Swift 6, Foundation, ImageIO in the app target only, Swift Testing, AppKit for the menu, clipboard, and Share picker.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-10-25-zip-handoff-design.md`. Issue: #85. Flag: `zipHandoff`, states off and on, both defaults off, `devOnly` false, `releasedInBuild` nil.
- Local only. No `Process(`, `NSTask`, `curl`, `URLSession`, or sockets in `App/Feedback`, `Packages/FeedbackKit`, or `Packages/JevKit`. Do not call `/usr/bin/ditto`.
- The zip has no `__MACOSX/` entry and no path component that starts with `._`.
- No prompt or manifest inside a zip holds an absolute path or the source Mac's home folder.
- The live bundle is never rewritten. Screen text stays untrusted. Authority rules stay in every prompt.
- New logic in FeedbackKit. New app files under `App/Feedback/`. Log any upstream edit in `docs/FORK_NOTES.md`. Never edit `.gitignore`.
- Do not touch `scripts/release-notarized.sh`, the DMG layout, or `scripts/build-local.sh`.
- Stage by explicit path. Conventional commit prefix. `Part of #85`. No AI attribution line.
- Work on `feature/zip-handoff` in `/Users/drewschulz/Developer/capso/.claude/worktrees/zip-handoff-85`.

---

### Task 1: Portable path mode

**Files:**
- Modify: `[AWS_SECRET_KEY]/PromptBuilder.swift`
- Modify: `[AWS_SECRET_KEY]/ManifestWriter.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/PromptBuilderTests.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/ManifestWriterTests.swift`

**Interfaces:**
- Consumes: existing `render`, `renderCapture`, `renderSelection`, `ManifestWriter.render`.
- Produces: `PromptBuilder.portableFolder = "."`, `PromptBuilder.portablePathSentence`, and `portable: Bool = false` on `render`, `renderCapture`, and `renderSelection`. `ManifestWriter.render(_:folderPath:timeZone:portable:)`.

- [ ] **Step 1: Write the failing test**

Add to `PromptBuilderTests.swift`:

```swift
@Test("A portable prompt names files relative to its own folder")
func portableRoundPrompt() {
    let prompt = PromptBuilder.render(
        FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()]),
        folderPath: folder,
        portable: true
    )
    #expect(prompt.contains(#"<feedback_bundle path="." "#))
    #expect(prompt.contains(PromptBuilder.portablePathSentence))
    #expect(prompt.contains("Open `./manifest.md`."))
    #expect(!prompt.contains(folder))
    #expect(!prompt.contains("/Users/"))
}
```

Add the same assertion shape for `renderCapture` and `renderSelection`: each backtick path starts with `./`, and the source `folderPath` is absent.

Add to `ManifestWriterTests.swift`:

```swift
@Test("A portable manifest uses a relative Folder line and Codex command")
func portableManifest() {
    let text = ManifestWriter.render(round, folderPath: "/Users/drewschulz/Library/Application Support/Nextshot/round", timeZone: TimeZone(secondsFromGMT: 0)!, portable: true)
    #expect(text.contains("Folder: . (paths are relative to the folder that holds this file)"))
    #expect(text.contains(#"codex --image "./"#))
    #expect(!text.contains("/Users/drewschulz"))
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `swift test --package-path Packages/FeedbackKit --filter 'portableRoundPrompt|portableManifest'`

Expected: FAIL. The compiler reports `portable` is not a parameter.

- [ ] **Step 3: Add the path mode**

In `PromptBuilder`:

```swift
public static let portableFolder = "."
public static let portablePathSentence = "Paths are relative to the folder that holds this file. Open that folder before you read a file."
```

Add `portable: Bool = false` to `render`, `renderCapture`, and `renderSelection`. When `portable` is true, use `portableFolder` instead of the caller's `folderPath`, and insert `portablePathSentence` on the line after `Goal:`. When it is false, keep today's text.

In `ManifestWriter.render`, add `portable: Bool = false`. When true, the Folder line is `Folder: . (paths are relative to the folder that holds this file)` and `codexCommand` receives `portableFolder`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/FeedbackKit --filter 'PromptBuilder|ManifestWriter'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -f \
  "[AWS_SECRET_KEY]/PromptBuilder.swift" \
  "[AWS_SECRET_KEY]/ManifestWriter.swift" \
  Packages/FeedbackKit/Tests/FeedbackKitTests/PromptBuilderTests.swift \
  Packages/FeedbackKit/Tests/FeedbackKitTests/ManifestWriterTests.swift
git commit -m "$(cat <<'EOF'
feat: add a portable path mode to prompts and manifests

Part of #85.
EOF
)"
```

### Task 2: Zip file list and name

**Files:**
- Create: `[AWS_SECRET_KEY]/ZipHandoff.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/ZipHandoffTests.swift`

**Interfaces:**
- Consumes: `FeedbackRound`, `FeedbackCapture`, `FeedbackSelectionEntry`, `PromptBuilder.portableFolder`.
- Produces:

```swift
public struct ZipFilePlan: Equatable, Sendable {
    public var folderName: String
    public var zipFileName: String
    public var files: [ZipPlannedFile]
    public var prompt: String
    public var manifest: String
    public var capturePrompts: [String: String]
}

public struct ZipPlannedFile: Equatable, Sendable {
    public var sourceRelativePath: String
    public var zipRelativePath: String
    public var role: ZipFileRole
}

public enum ZipFileRole: String, Sendable {
    case annotated, clean, crop, refined, prompt, manifest, feedbackJSON
}

public enum ZipHandoff {
    public static let byteTarget = 5_000_000
    public static func roundPlan(round: FeedbackRound, folderName: String, includeClean: Bool, includeCrops: Bool, includeRefined: Bool) -> ZipFilePlan
    public static func selectionPlan(entries: [FeedbackSelectionEntry], stamped stem: String, includeClean: Bool, includeCrops: Bool, includeRefined: Bool) -> ZipFilePlan
    public static func uniqueDownloadName(_ name: String, existing: Set<String>) -> String
}
```

- [ ] **Step 1: Write the failing test**

```swift
@Test("A round plan excludes jev files and uses the Nextshot prefix")
func roundPlanExcludesJev() {
    let plan = ZipHandoff.roundPlan(
        round: FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()]),
        folderName: "2026-10-25-0637-feedback",
        includeClean: true,
        includeCrops: true,
        includeRefined: true
    )
    #expect(plan.zipFileName == "Nextshot-2026-10-25-0637-feedback.zip")
    #expect(plan.folderName == "Nextshot-2026-10-25-0637-feedback")
    #expect(plan.files.allSatisfy { !$0.zipRelativePath.contains("jev.json") && !$0.zipRelativePath.contains("jev-review") })
    #expect(plan.prompt.contains(PromptBuilder.portablePathSentence))
    #expect(!plan.prompt.contains("/Users/"))
}

@Test("A taken Downloads name gets a numeric suffix")
func uniqueName() {
    let taken: Set<String> = ["Nextshot-round.zip", "Nextshot-round-2.zip"]
    #expect(ZipHandoff.uniqueDownloadName("Nextshot-round.zip", existing: taken) == "Nextshot-round-3.zip")
}
```

Add a selection test: two entries become one folder, item ids `1.N` and `2.N`, and a stem clash gets `-2` on the second file.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `swift test --package-path Packages/FeedbackKit --filter ZipHandoffTests`

Expected: FAIL. `ZipHandoff` is not defined.

- [ ] **Step 3: Implement the planner**

`roundPlan` lists annotated PNG, clean PNG, each `*-prompt.md`, `prompt.md`, `manifest.md`, and `feedback.json`. It adds `refined.md`, `<stem>-refined.md`, and `<stem>-item-<N>.png` only when `includeRefined` or `includeCrops` is true and the caller says the source file exists. It never lists `jev.json` or `jev-review/`. Image zip names use `.jpg` when the app will encode JPEG. The planner itself only names files.

`selectionPlan` sorts like `FeedbackLibrary.entries`: capture time, then folder path, then capture index. It calls `PromptBuilder.renderSelection` with `portable: true` after rewriting each entry's `folderPath` to `PromptBuilder.portableFolder`. It writes one manifest with `ManifestWriter` path mode, and one section note that the prompt's K.N wins over the capture's own prefix.

`uniqueDownloadName` returns `name` when it is not in `existing`. Otherwise it inserts `-2`, `-3`, and so on before the extension.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `swift test --package-path Packages/FeedbackKit --filter ZipHandoffTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -f \
  "[AWS_SECRET_KEY]/ZipHandoff.swift" \
  Packages/FeedbackKit/Tests/FeedbackKitTests/ZipHandoffTests.swift
git commit -m "$(cat <<'EOF'
feat: plan a portable zip file list for a round or a basket

Part of #85.
EOF
)"
```

### Task 3: Flag

**Files:**
- Modify: `[AWS_SECRET_KEY]/FeatureFlags.swift`
- Modify: `scripts/nextshot-flags.sh`
- Modify: `Packages/FeedbackKit/[AWS_SECRET_KEY].swift`

**Interfaces:**
- Consumes: `FlagSpec`.
- Produces: `FeatureFlag.zipHandoff`.

- [ ] **Step 1: Write the failing expectation**

In `registryContents`, change the seven-flag list to eight. Add `"zipHandoff"` and issue `85`.

```swift
#expect(FeatureFlag.allCases.map(\.rawValue) == [
    "jevBase", "noteCoach", "cropsAnchors", "dupesConflicts", "oneBreath",
    "jevSendImages", "jevSendScreenText", "zipHandoff",
])
#expect(FeatureFlag.zipHandoff.spec.issue == 85)
#expect(FeatureFlag.zipHandoff.spec.devOnly == false)
#expect(FeatureFlag.zipHandoff.spec.allowedStates == [.off, .on])
```

Update the test name from "seven flags" to "eight flags".

- [ ] **Step 2: Run the test and confirm it fails**

Run: `swift test --package-path Packages/FeedbackKit --filter FeatureFlagsTests`

Expected: FAIL. `zipHandoff` is missing.

- [ ] **Step 3: Add the flag**

```swift
case zipHandoff
```

In `spec`:

```swift
case .zipHandoff:
    FlagSpec(issue: 85, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: false)
```

In `scripts/nextshot-flags.sh`, append `zipHandoff:off,on` to the `FLAGS=` line.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `swift test --package-path Packages/FeedbackKit --filter FeatureFlagsTests`

Expected: PASS. The script line matches the registry.

- [ ] **Step 5: Commit**

```bash
git add -f \
  "[AWS_SECRET_KEY]/FeatureFlags.swift" \
  scripts/nextshot-flags.sh \
  "Packages/FeedbackKit/[AWS_SECRET_KEY].swift"
git commit -m "$(cat <<'EOF'
feat: add the zipHandoff flag, off in both channels

Part of #85.
EOF
)"
```

### Task 4: Foundation zip writer

**Files:**
- Create: `App/Feedback/FeedbackZipArchive.swift`
- Test: `App/Tests/FeedbackZipArchiveTests.swift`

**Interfaces:**
- Consumes: a staging directory URL.
- Produces: `enum FeedbackZipArchive { static func write(stagingParent: URL, to zipURL: URL) throws }`.

- [ ] **Step 1: Probe `NSFileCoordinator`**

Write a throwaway test that stages one PNG and one markdown file, calls `NSFileCoordinator` with `.forUploading`, and lists the zip with `ArchiveByteStream` or by reading the central directory. If any entry contains `__MACOSX` or a component that starts with `._`, do not use the coordinator. Use the Foundation writer in Step 3 either way if the probe is unclean.

This probe is a test, not a script that calls `ditto`.

- [ ] **Step 2: Write the failing archive test**

```swift
func testZipHasNoAppleDoubleEntries() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folder = parent.appendingPathComponent("Nextshot-round", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: folder.appendingPathComponent("prompt.md"))
    let zip = parent.appendingPathComponent("out.zip")
    try FeedbackZipArchive.write(stagingParent: parent, to: zip)
    let names = try FeedbackZipArchive.entryNames(in: zip)
    XCTAssertTrue(names.contains("Nextshot-round/prompt.md"))
    XCTAssertTrue(names.allSatisfy { !$0.contains("__MACOSX") && !$0.split(separator: "/").contains { $0.hasPrefix("._") } })
}
```

- [ ] **Step 3: Implement the writer**

Prefer the coordinator only if Step 1 is clean. Otherwise write a stored-or-deflated zip with `FileManager` file bytes and a small central-directory writer in `FeedbackZipArchive`. Set no extra-field AppleDouble records. Skip any source file whose name starts with `._` or is `__MACOSX`.

`entryNames(in:)` reads the central directory and returns the entry paths. The test uses it so the assertion does not shell out.

- [ ] **Step 4: Run the app test**

Run: `xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests/FeedbackZipArchiveTests`

Expected: PASS. Generate the project first with `xcodegen generate` if `Capso.xcodeproj` is missing. Do not pass `PRODUCT_NAME`.

- [ ] **Step 5: Commit**

```bash
git add -f App/Feedback/FeedbackZipArchive.swift App/Tests/FeedbackZipArchiveTests.swift
git commit -m "$(cat <<'EOF'
feat: write a zip with no AppleDouble entries

Part of #85.
EOF
)"
```

### Task 5: Stage, encode, and cap the size

**Files:**
- Create: `App/Feedback/FeedbackZipBuilder.swift`
- Test: `App/Tests/FeedbackZipBuilderTests.swift`

**Interfaces:**
- Consumes: `ZipFilePlan`, `FeedbackZipArchive.write`.
- Produces:

```swift
struct ZipBuildResult: Equatable {
    var zipURL: URL
    var byteCount: Int
    var leftOut: [String]
}

enum FeedbackZipBuilder {
    static let jpegQuality = 0.7
    static func build(plan: ZipFilePlan, sourceRoot: URL, downloadsDirectory: URL) throws -> ZipBuildResult
}
```

`leftOut` uses only these tokens: `clean images`, `crops`, `refined file`, `PNG kept`.

- [ ] **Step 1: Write the failing test**

Build a source folder with one small PNG and one `prompt.md`. Call `build`. Unzip to a temp folder. Assert:

- the prompt in the zip contains `Paths are relative to the folder that holds this file`
- the prompt does not contain the source root path
- the image name ends in `.jpg`
- `leftOut` is empty when the zip is under 5 MB

Add a second test with a plan that includes a missing refined file. Assert `leftOut` contains `refined file` and the prompt does not name that file.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests/FeedbackZipBuilderTests`

Expected: FAIL. `FeedbackZipBuilder` is not defined.

- [ ] **Step 3: Implement the builder**

1. Create a temp staging parent and the plan's folder inside it.
2. Copy text files from the plan (`prompt`, `manifest`, `capturePrompts`, `feedback.json`).
3. Encode each PNG with ImageIO (`kCGImageDestinationLossyCompressionQuality` = 0.7) to the `.jpg` name. On encode failure, copy the PNG, rename the prompt references for that file back to `.png`, and append `PNG kept`.
4. If a refined source still contains an absolute path after replacing the source folder prefix with `.`, omit it and append `refined file`.
5. Write the zip. If `byteCount` is over `ZipHandoff.byteTarget`, drop clean images, rewrite prompts so they do not name them, append `clean images`, and zip again.
6. If still over, drop crops the same way and append `crops`.
7. Return the zip URL in the downloads directory, using `ZipHandoff.uniqueDownloadName`. Delete the staging parent in `defer`.

Do not read or copy `jev.json` or `jev-review/`.

- [ ] **Step 4: Run the test and confirm it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -f App/Feedback/FeedbackZipBuilder.swift App/Tests/FeedbackZipBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat: stage a portable zip and keep it near 5 MB

Part of #85.
EOF
)"
```

### Task 6: Menu, hotkey, clipboard, and Share

**Files:**
- Create: `App/Feedback/FeedbackZip.swift`
- Modify: `App/Feedback/FeedbackStatusItem.swift`
- Modify: `App/Feedback/FeedbackController.swift`
- Modify: `App/Feedback/FeedbackShortcuts.swift`
- Modify: `App/[AWS_SECRET_KEY].swift`
- Modify: `docs/agents/bundle-guide.md`
- Modify: `docs/FORK_NOTES.md` only if an upstream file changes. These files are fork files, so a note is not required unless the edit touches an upstream hook.

**Interfaces:**
- Consumes: `Flags.isOn(.zipHandoff)`, `FeedbackZipBuilder.build`, `ZipHandoff.roundPlan`, `ZipHandoff.selectionPlan`.
- Produces: menu rows `Zip Round` and `Zip N Selected`, hotkey `KeyboardShortcuts.Name.feedbackZipRound`.

- [ ] **Step 1: Add the shortcut**

In `FeedbackShortcuts.swift`:

```swift
static let feedbackZipRound = Self("feedbackZipRound", default: .init(.z, modifiers: [.option, .shift]))
```

Add it to `feedbackRoundKeys` and `nextshotKeys`. Add a Settings row in `FeedbackShortcutSettingsSection` titled `Zip Round`.

- [ ] **Step 2: Gate the rows**

In `fillSubmenu`, under Copy Round Prompt, add Zip Round only when `Flags.isOn(.zipHandoff)`. In the active-round block, add a shortcut item titled `Zip Round` with `.feedbackZipRound`. In `insertBasketItems`, add `Zip N Selected` under Copy N Selected, same flag check.

The help box in `FeedbackHelpOverlay` does not gain a line.

- [ ] **Step 3: Wire the actions**

`zipRound` reads the round, builds `ZipHandoff.roundPlan`, calls `FeedbackZipBuilder.build`, then `FeedbackZip.deliver`. It does not call `end()`.

`zipSelected` copies the basket, clears it, resolves entries, and builds `selectionPlan` with stem `selection-<yyyy-MM-dd-HHmm>`.

Option+Shift+Z calls `zipRound` for the active round. If `roundEndKeyAllowed()` is false, beep and return. That helper already treats an open selection, editor, or note panel as busy.

- [ ] **Step 4: Deliver the file**

```swift
enum FeedbackZip {
    static func deliver(zipURL: URL, leftOut: [String], byteCount: Int)
    static func toast(leftOut: [String], byteCount: Int) -> String
}
```

`deliver` writes the file URL with `pasteboard.writeObjects([zipURL as NSURL])`. It does not set a string. Then it shows the toast and an `NSSharingServicePicker` from the status item button.

Toast text, exact:

- no left out, size at or under 5 MB: `Zip copied. It is in Downloads.`
- left out: `Zip copied. It is in Downloads. Left out: clean images.`
- over 5 MB: `Zip copied. It is in Downloads. It is over 5 MB (6.2 MB).`

A failed build beeps and shows `Zip was not written.` The clipboard is unchanged.

- [ ] **Step 5: Update the agent guide**

Add a section to `docs/agents/bundle-guide.md`:

```markdown
## A zip from another Mac

A zip names files relative to the folder that holds `prompt.md`. Unzip it, then open that folder. The prompt says `Paths are relative to the folder that holds this file.` The zip holds no `jev.json` and no `jev-review/`. Images in the zip are JPEG. The live bundle on the source Mac stays PNG and keeps absolute paths.
```

- [ ] **Step 6: Run the package tests and the new app tests**

Run: `swift test --package-path Packages/FeedbackKit`

Run: `xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests/FeedbackZipArchiveTests -only-testing:CapsoTests/FeedbackZipBuilderTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -f \
  App/Feedback/FeedbackZip.swift \
  App/Feedback/FeedbackStatusItem.swift \
  App/Feedback/FeedbackController.swift \
  App/Feedback/FeedbackShortcuts.swift \
  App/[AWS_SECRET_KEY].swift \
  docs/agents/bundle-guide.md
git commit -m "$(cat <<'EOF'
feat: zip a round or checked captures from the Nshot menu

Part of #85.
EOF
)"
```

## Self-review

- Spec decisions 1 through 9 each have a task: destination and Share in Task 6, contents and multi-round layout in Task 2, relative paths in Task 1, menu and hotkey in Task 6, flag in Task 3, names in Task 2, size cap in Task 5.
- The AppleDouble test is Task 4. The absolute-path test is Task 1 and Task 5.
- No step says TBD. The coordinator probe in Task 4 has a fail-closed rule: an unclean probe uses the Foundation writer.
- `portable` is defined in Task 1 and used in Task 2. `ZipFilePlan` is defined in Task 2 and used in Task 5 and Task 6.

## Stop

Do not implement this plan until Drew approves it. Do not run `scripts/build-local.sh` or `scripts/release-notarized.sh`.
