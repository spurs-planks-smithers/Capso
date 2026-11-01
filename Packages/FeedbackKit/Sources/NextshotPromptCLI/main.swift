// Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift
import FeedbackKit
import Foundation

/// `nextshot-prompt`: renders the prompts and zips that the app copies, from
/// saved rounds, so a script outside the app can test them. It reads rounds
/// and writes only the zip. It opens no connection (`NetworkSourceScanTests`
/// scans this folder).
///
///     nextshot-prompt round <rounds-root> <folder> [--redo] [--linked]
///     nextshot-prompt capture <rounds-root> <folder> <index> [--redo] [--linked]
///     nextshot-prompt zip <rounds-root> <folder> <out-dir>
///
/// Exit status: 0 on success, 1 when a round, capture, or zip fails, 2 for
/// `--linked`, and 64 for a command line it cannot read.

let usage = """
usage:
  nextshot-prompt round <rounds-root> <folder> [--redo] [--linked]
  nextshot-prompt capture <rounds-root> <folder> <index> [--redo] [--linked]
  nextshot-prompt zip <rounds-root> <folder> <out-dir>
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

default:
    usageError("unknown command: \(arguments[1])")
}
