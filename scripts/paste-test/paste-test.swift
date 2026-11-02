// scripts/paste-test/paste-test.swift
import AppKit
import Foundation

// Puts a test paste on the macOS clipboard, so Drew can paste it by hand into
// AI chat apps and see what one paste carries (text, one image, a zip file).
// The runbook is docs/runbooks/2026-11-01-paste-hand-tests.md.
//
//     swift scripts/paste-test/paste-test.swift t1
//     swift scripts/paste-test/paste-test.swift t4-2000     (also 5000, 10000, 15000)
//     swift scripts/paste-test/paste-test.swift t6 2026-10-22-1609-feedback
//
// Each mode clears the pasteboard, writes the items, and prints the item types.
// This script overwrites your clipboard. It reads saved rounds and runs the
// `nextshot-prompt` tool (build it first, see the runbook). It opens no connection.
//
// Exit status: 0 on success, 1 when a step fails, 64 for a command line it cannot read.

/// The round that t1 and t4-N paste: the nextshot.dev page, no private data.
let fixedRound = "2026-10-31-2125-feedback"
/// The capture of that round whose prompt and image t1 and t4-N paste.
let fixedCaptureIndex = 1
/// The round that the runbook gives to t6: two captures. Capture 1 is an app window, capture 2 is the Settings window.
/// Capture 2 has badge 1, so item 2.1 exists. t6 takes any round with two or more captures.
let t6Round = "2026-10-22-1609-feedback"
/// The last line of every t4-N text. The T4 question asks the app to quote it.
let lastLine = "LAST LINE: blue heron 47"
let t4Lengths: Set<Int> = [2000, 5000, 10000, 15000]

let usage = """
usage:
  swift scripts/paste-test/paste-test.swift t1 [folder]
  swift scripts/paste-test/paste-test.swift t4-2000|t4-5000|t4-10000|t4-15000 [folder]
  swift scripts/paste-test/paste-test.swift t6 <folder>
The folder is a round folder name in ~/Library/Application Support/Nextshot.
t1 and t4-N use \(fixedRound) when no folder is given.
t6 takes a round with two or more captures. The runbook uses \(t6Round).
"""

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

func usageError(_ message: String) -> Never {
    fail("\(message)\n\(usage)", status: 64)
}

// MARK: - Paths

let roundsRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Nextshot", isDirectory: true)

/// The repository root: this file sits in `scripts/paste-test/`.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let promptTool: URL = {
    if let override = ProcessInfo.processInfo.environment["NEXTSHOT_PROMPT_BIN"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    return repositoryRoot.appendingPathComponent("Packages/FeedbackKit/.build/debug/nextshot-prompt")
}()

/// Where t6 writes the zip. This folder holds only files that this script wrote.
let zipFolder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("nextshot-paste-test", isDirectory: true)

// MARK: - The prompt tool

/// Runs `nextshot-prompt` and returns what it printed. Exits 1 when it fails.
func runPromptTool(_ arguments: [String]) -> String {
    guard FileManager.default.isExecutableFile(atPath: promptTool.path) else {
        fail("""
        nextshot-prompt is not built: \(promptTool.path)
        Build it from the repository root:
          swift build --package-path Packages/FeedbackKit --product nextshot-prompt
        """, status: 1)
    }
    let process = Process()
    process.executableURL = promptTool
    process.arguments = arguments
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    do {
        try process.run()
    } catch {
        fail("could not run nextshot-prompt: \(error)", status: 1)
    }
    // Read both pipes before waiting, so a full pipe cannot block the tool.
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        fail("nextshot-prompt \(arguments.first ?? "") failed (exit \(process.terminationStatus)): \(message)", status: 1)
    }
    return String(decoding: outputData, as: UTF8.self)
}

// MARK: - Round files

/// The annotated PNG of one capture, named by `captures[].imageFile` in feedback.json.
func annotatedImage(folder: String, captureIndex: Int) -> (name: String, data: Data) {
    let folderURL = roundsRoot.appendingPathComponent(folder, isDirectory: true)
    let jsonURL = folderURL.appendingPathComponent("feedback.json")
    guard let json = try? Data(contentsOf: jsonURL),
          let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
          let captures = root["captures"] as? [[String: Any]]
    else { fail("cannot read \(jsonURL.path)", status: 1) }
    guard let capture = captures.first(where: { ($0["index"] as? Int) == captureIndex }),
          let imageFile = capture["imageFile"] as? String
    else { fail("capture \(captureIndex) has no imageFile in \(jsonURL.path)", status: 1) }
    let imageURL = folderURL.appendingPathComponent(imageFile)
    guard let data = try? Data(contentsOf: imageURL), !data.isEmpty else {
        fail("cannot read \(imageURL.path)", status: 1)
    }
    return (imageFile, data)
}

// MARK: - The T4 text

/// The lines of a capture prompt that name an item, such as `- 1.2: ...`.
func itemLines(of prompt: String) -> [String] {
    prompt.split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
        .filter { $0.range(of: #"^- \d+\.\d+:"#, options: .regularExpression) != nil }
}

struct PaddedText {
    let text: String
    /// True when the prompt was longer than N and had to be cut.
    let shortened: Bool
}

/// Builds a text of exactly `length` characters that ends with `lastLine`.
///
/// The prompt keeps its closing tag. The padding goes after it: the item
/// lines of the prompt, repeated. A prompt that is already too long for
/// `length` is cut to fit instead. The last line counts inside `length`.
func paddedText(prompt: String, length: Int) -> PaddedText {
    let head = prompt.hasSuffix("\n") ? prompt : prompt + "\n"
    // head + padding + newline + last line = length
    let paddingLength = length - head.count - 1 - lastLine.count
    if paddingLength < 0 {
        let kept = String(head.prefix(length - 1 - lastLine.count))
        return PaddedText(text: kept + "\n" + lastLine, shortened: true)
    }
    let lines = itemLines(of: prompt)
    guard !lines.isEmpty else { fail("the prompt has no item lines to repeat", status: 1) }
    let unit = lines.joined(separator: "\n") + "\n"
    var padding = ""
    while padding.count < paddingLength { padding += unit }
    return PaddedText(text: head + String(padding.prefix(paddingLength)) + "\n" + lastLine, shortened: false)
}

// MARK: - Pasteboard

func describe(_ pasteboard: NSPasteboard) {
    let items = pasteboard.pasteboardItems ?? []
    print("pasteboard items: \(items.count)")
    for (number, item) in items.enumerated() {
        print("  item \(number + 1): " + item.types.map(\.rawValue).joined(separator: ", "))
    }
}

/// One item with text and one PNG, as the app would copy a capture.
func writeTextAndImage(text: String, png: Data) {
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setData(png, forType: .png)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else { fail("the pasteboard refused the item", status: 1) }
    describe(pasteboard)
}

/// Two items: the text, then a file URL.
func writeTextAndFile(text: String, file: URL) {
    let textItem = NSPasteboardItem()
    textItem.setString(text, forType: .string)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.writeObjects([textItem, file as NSURL]) else {
        fail("the pasteboard refused the items", status: 1)
    }
    describe(pasteboard)
}

// MARK: - Modes

/// t1 and t4-N. `length` is nil for t1.
func runTextAndImage(folder: String, length: Int?) {
    let prompt = runPromptTool(["capture", roundsRoot.path, folder, String(fixedCaptureIndex)])
    guard !prompt.isEmpty else { fail("nextshot-prompt printed an empty prompt", status: 1) }
    var text = prompt
    var note = ""
    if let length {
        let padded = paddedText(prompt: prompt, length: length)
        text = padded.text
        // Self-check: the text is exactly N characters and ends with the fixed line.
        guard text.count == length, text.hasSuffix("\n" + lastLine) else {
            fail("internal error: text is \(text.count) characters, wanted \(length)", status: 1)
        }
        if padded.shortened {
            note = " (the prompt is \(prompt.count) characters, so it was cut to fit)"
        }
    }
    let image = annotatedImage(folder: folder, captureIndex: fixedCaptureIndex)
    writeTextAndImage(text: text, png: image.data)
    print("text: \(text.count) characters\(note)")
    print("image: \(image.name), \(image.data.count) bytes")
}

/// t6: the round prompt and the round zip.
func runTextAndZip(folder: String) {
    let prompt = runPromptTool(["round", roundsRoot.path, folder])
    guard !prompt.isEmpty else { fail("nextshot-prompt printed an empty prompt", status: 1) }
    // Start from an empty folder, so the clipboard never points at an old zip.
    try? FileManager.default.removeItem(at: zipFolder)
    let zipPath = runPromptTool(["zip", roundsRoot.path, folder, zipFolder.path])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let zipURL = URL(fileURLWithPath: zipPath)
    let attributes = try? FileManager.default.attributesOfItem(atPath: zipURL.path)
    guard let size = (attributes?[.size] as? NSNumber)?.intValue, size > 0 else {
        fail("the zip is missing or empty: \(zipPath)", status: 1)
    }
    writeTextAndFile(text: prompt, file: zipURL)
    print("text: \(prompt.count) characters")
    print("zip: \(zipURL.path), \(size) bytes")
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { usageError("missing mode") }
let mode = arguments[1]
let folderArgument = arguments.count >= 3 ? arguments[2] : nil
guard arguments.count <= 3 else { usageError("too many arguments") }

if mode == "t1" {
    runTextAndImage(folder: folderArgument ?? fixedRound, length: nil)
} else if mode.hasPrefix("t4-") {
    guard let length = Int(mode.dropFirst(3)), t4Lengths.contains(length) else {
        usageError("unknown mode: \(mode)")
    }
    runTextAndImage(folder: folderArgument ?? fixedRound, length: length)
} else if mode == "t6" {
    guard let folderArgument else { usageError("t6 needs a round folder") }
    runTextAndZip(folder: folderArgument)
} else {
    usageError("unknown mode: \(mode)")
}
