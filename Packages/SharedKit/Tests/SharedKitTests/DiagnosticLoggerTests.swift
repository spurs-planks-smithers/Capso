import Foundation
import Testing
@testable import SharedKit

@Suite("DiagnosticLogger", .serialized)
struct DiagnosticLoggerTests {
    @Test("append writes timestamped diagnostic lines")
    func appendWritesLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-diagnostic-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("capso.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        DiagnosticLogger.append("blocked by default", category: "Test", fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        DiagnosticLogger.append(error: NSError(domain: "Test", code: 1), context: "blocked error", fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        defer { DiagnosticLogger.configure(capabilityEnabled: false, loggingEnabled: false) }
        DiagnosticLogger.configure(capabilityEnabled: false, loggingEnabled: true)
        DiagnosticLogger.append("saved preference cannot bypass capability", fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        DiagnosticLogger.configure(capabilityEnabled: true, loggingEnabled: false)
        DiagnosticLogger.append("capability alone cannot enable logging", fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        DiagnosticLogger.configure(capabilityEnabled: true, loggingEnabled: true)
        DiagnosticLogger.append("hello diagnostics", category: "Test", fileURL: fileURL)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("[Test] hello diagnostics"))
        DiagnosticLogger.configure(capabilityEnabled: false, loggingEnabled: true)
        DiagnosticLogger.append("must not append after disabling", fileURL: fileURL)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == contents)
    }

    @Test("prepare log file creates an empty selectable file")
    func prepareLogFileCreatesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-diagnostic-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("capso.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        let preparedURL = DiagnosticLogger.prepareLogFile(at: fileURL)

        #expect(preparedURL == fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        defer { DiagnosticLogger.configure(capabilityEnabled: false, loggingEnabled: false) }
        DiagnosticLogger.configure(capabilityEnabled: false, loggingEnabled: true)
        DiagnosticLogger.prepareLogFile(at: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        DiagnosticLogger.configure(capabilityEnabled: true, loggingEnabled: false)
        DiagnosticLogger.prepareLogFile(at: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        DiagnosticLogger.configure(capabilityEnabled: true, loggingEnabled: true)
        DiagnosticLogger.prepareLogFile(at: fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8).isEmpty)
        #expect(DiagnosticLogger.logDirectory.lastPathComponent == "logs")
        #expect(DiagnosticLogger.logDirectory.deletingLastPathComponent().lastPathComponent == "Nextshot")
        #expect(DiagnosticLogger.logFileURL.lastPathComponent == "nextshot.log")
    }
}
