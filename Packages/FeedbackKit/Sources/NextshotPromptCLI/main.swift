// Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift
import FeedbackKit
import Foundation

/// `nextshot-prompt`: renders the prompts and zips that the app copies, from
/// saved rounds, so a script outside the app can test them. It reads rounds
/// and writes only the zip and the subset folder. It opens no connection
/// (`NetworkSourceScanTests` scans this folder).
///
///     nextshot-prompt round <rounds-root> <folder> [--redo] [--linked]
///     nextshot-prompt capture <rounds-root> <folder> <index> [--redo] [--linked]
///     nextshot-prompt zip <rounds-root> <folder> <out-dir>
///     nextshot-prompt subset <rounds-root> <folder> <captures> <out-root>
///
/// `subset` copies a round to `<out-root>/<folder>` with only the captures in
/// `<captures>` (a comma list of capture indexes, or `all`). It holds a new
/// `feedback.json`, a `manifest.md` rendered again from that round, and the
/// annotated and clean PNG of each chosen capture. It copies no other file,
/// because the original `manifest.md` holds the screen text of every capture.
/// It stops when `<out-root>/<folder>` exists, and it prints the new folder.
///
/// Exit status: 0 on success, 1 when a round, capture, zip, or subset fails,
/// 2 for `--linked`, and 64 for a command line it cannot read.

let usage = """
usage:
  nextshot-prompt round <rounds-root> <folder> [--redo] [--linked]
  nextshot-prompt capture <rounds-root> <folder> <index> [--redo] [--linked]
  nextshot-prompt zip <rounds-root> <folder> <out-dir>
  nextshot-prompt subset <rounds-root> <folder> <captures> <out-root>
"""

/// Printed for `--linked` until the linked plan is wired in.
let linkedNotBuilt = "linkedPlan is not built yet"

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

func usageError(_ message: String) -> Never {
    fail("\(message)\n\(usage)", status: 64)
}

/// Splits the arguments after the command into positional words and flags.
/// Only the flags in `allowed` are accepted.
func parse(_ arguments: ArraySlice<String>, allowed: Set<String>) -> (words: [String], flags: Set<String>) {
    var words: [String] = []
    var flags: Set<String> = []
    for argument in arguments {
        if argument.hasPrefix("--") {
            guard allowed.contains(argument) else { usageError("unknown option: \(argument)") }
            flags.insert(argument)
        } else {
            words.append(argument)
        }
    }
    return (words, flags)
}

/// Reads a round, or exits 1 with `notFound` when it is missing or unreadable.
func loadRound(root: URL, folder: String, notFound: String) -> FeedbackRound {
    guard let round = FeedbackLibrary.round(named: folder, in: root) else {
        fail(notFound, status: 1)
    }
    return round
}

/// The capture indexes in `list`: `all`, or numbers split by commas.
func chosenIndexes(_ list: String, in round: FeedbackRound) -> Set<Int> {
    if list == "all" { return Set(round.captures.map(\.index)) }
    var indexes: Set<Int> = []
    for part in list.split(separator: ",", omittingEmptySubsequences: false) {
        guard let index = Int(part) else { usageError("captures is not a list of numbers or all: \(list)") }
        indexes.insert(index)
    }
    return indexes
}

/// Writes `feedback.json` as the app does (`FeedbackRoundStore.encoder()`).
func encodeRound(_ round: FeedbackRound) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(round)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { usageError("missing command") }

switch arguments[1] {
case "round":
    let (words, flags) = parse(arguments.dropFirst(2), allowed: ["--redo", "--linked"])
    guard words.count == 2 else { usageError("round takes <rounds-root> <folder>") }
    if flags.contains("--linked") { fail(linkedNotBuilt, status: 2) }
    let root = URL(fileURLWithPath: words[0], isDirectory: true)
    let round = loadRound(root: root, folder: words[1], notFound: "round not found: \(words[1])")
    let folderPath = root.appendingPathComponent(words[1], isDirectory: true).path
    print(PromptBuilder.render(round, folderPath: folderPath, redo: flags.contains("--redo"), sessionTitle: true), terminator: "")

case "capture":
    let (words, flags) = parse(arguments.dropFirst(2), allowed: ["--redo", "--linked"])
    guard words.count == 3 else { usageError("capture takes <rounds-root> <folder> <index>") }
    guard let index = Int(words[2]) else { usageError("index is not a number: \(words[2])") }
    if flags.contains("--linked") { fail(linkedNotBuilt, status: 2) }
    let root = URL(fileURLWithPath: words[0], isDirectory: true)
    let missingCapture = "capture not found: \(words[1]) \(index)"
    let round = loadRound(root: root, folder: words[1], notFound: missingCapture)
    guard let capture = round.captures.first(where: { $0.index == index }) else {
        fail(missingCapture, status: 1)
    }
    let folderPath = root.appendingPathComponent(words[1], isDirectory: true).path
    print(PromptBuilder.renderCapture(capture, folderPath: folderPath, redo: flags.contains("--redo"), sessionTitle: true), terminator: "")

case "zip":
    let (words, _) = parse(arguments.dropFirst(2), allowed: [])
    guard words.count == 3 else { usageError("zip takes <rounds-root> <folder> <out-dir>") }
    let root = URL(fileURLWithPath: words[0], isDirectory: true)
    let round = loadRound(root: root, folder: words[1], notFound: "round not found: \(words[1])")
    let folderPath = root.appendingPathComponent(words[1], isDirectory: true).path
    let entries = round.captures.map { FeedbackSelectionEntry(round: round, capture: $0, folderPath: folderPath) }
    let outDirectory = URL(fileURLWithPath: words[2], isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        let result = try ZipWriter.write(
            kind: .round,
            entries: entries,
            into: outDirectory,
            now: Date(),
            timeZone: .current,
            sessionTitle: true
        )
        print(result.url.path)
    } catch {
        fail("zip failed: \(error)", status: 1)
    }

case "subset":
    let (words, _) = parse(arguments.dropFirst(2), allowed: [])
    guard words.count == 4 else { usageError("subset takes <rounds-root> <folder> <captures> <out-root>") }
    let root = URL(fileURLWithPath: words[0], isDirectory: true)
    let round = loadRound(root: root, folder: words[1], notFound: "round not found: \(words[1])")
    let indexes = chosenIndexes(words[2], in: round)
    for index in indexes.sorted() where !round.captures.contains(where: { $0.index == index }) {
        fail("capture not found: \(words[1]) \(index)", status: 1)
    }
    guard !indexes.isEmpty else { usageError("captures names no capture: \(words[2])") }

    var subset = round
    subset.captures = round.captures.filter { indexes.contains($0.index) }
    let source = root.appendingPathComponent(words[1], isDirectory: true)
    let target = URL(fileURLWithPath: words[3], isDirectory: true).appendingPathComponent(words[1], isDirectory: true)
    guard target.standardizedFileURL.path != source.standardizedFileURL.path else {
        fail("the output folder is the round folder: \(target.path)", status: 1)
    }
    guard !FileManager.default.fileExists(atPath: target.path) else {
        fail("output folder exists: \(target.path)", status: 1)
    }
    do {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for capture in subset.captures {
            for name in [capture.imageFile, capture.cleanImageFile] {
                guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: target.appendingPathComponent(name))
            }
        }
        // The manifest is rendered again from the subset, never copied: the
        // original lists the screen text of the captures left out.
        let manifest = ManifestWriter.render(subset, paths: .absolute(folderPath: target.path), timeZone: .current)
        try Data(manifest.utf8).write(to: target.appendingPathComponent("manifest.md"))
        try encodeRound(subset).write(to: target.appendingPathComponent("feedback.json"))
        print(target.path)
    } catch {
        try? FileManager.default.removeItem(at: target)
        fail("subset failed: \(error)", status: 1)
    }

default:
    usageError("unknown command: \(arguments[1])")
}
