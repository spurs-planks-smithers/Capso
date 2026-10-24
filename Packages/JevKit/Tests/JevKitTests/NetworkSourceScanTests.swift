import Foundation
import Testing

/// The local-only rule as a test: only JevKit's transport opens a network
/// connection, and only JevKit's client builds a request. It scans every
/// Swift file of the fork's own code. Upstream code (Sparkle, translation,
/// Cloud Share) is outside the scan: the security baseline lists it.
@Suite("Network source scan")
struct NetworkSourceScanTests {
    /// The fork's own code. Paths are relative to the repository root.
    static let scannedFolders = ["App/Feedback", "Packages/FeedbackKit/Sources", "Packages/JevKit/Sources"]
    static let transportFile = "Packages/JevKit/Sources/JevKit/Client/URLSessionTransport.swift"
    static let clientFolder = "Packages/JevKit/Sources/JevKit/Client/"
    static let endpointFile = "Packages/JevKit/Sources/JevKit/Client/JevEndpoint.swift"

    struct Rule: Sendable {
        var name: String
        var pattern: String
        /// Files where the pattern may appear.
        var allowed: @Sendable (String) -> Bool
    }

    static let rules: [Rule] = [
        Rule(name: "URLSession", pattern: #"\bURLSession\b"#) { $0 == transportFile },
        Rule(name: "URLRequest", pattern: #"\bURLRequest\b"#) { $0.hasPrefix(clientFolder) },
        Rule(name: "a URL literal", pattern: #"https?://"#) { $0 == endpointFile },
        Rule(name: "Network framework, sockets, streams, or web views",
             pattern: #"import Network|\bNW(Connection|Listener|Browser|Endpoint|PathMonitor)\b|CFSocket|CFStream|NSURLConnection|\bsocket\(|WKWebView"#) { _ in false },
        Rule(name: "a child process", pattern: #"\bProcess\(|NSTask|\bcurl\b"#) { _ in false },
    ]

    static var repositoryRoot: URL {
        // .../Packages/JevKit/Tests/JevKitTests/NetworkSourceScanTests.swift
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    /// Every Swift file in the scanned folders, as a path from the root.
    static func swiftFiles() -> [String] {
        let root = repositoryRoot
        var files: [String] = []
        for folder in scannedFolders {
            let url = root.appendingPathComponent(folder, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                files.append(String(file.path.dropFirst(root.path.count + 1)))
            }
        }
        return files.sorted()
    }

    @Test("No fork code outside JevKit's client opens a connection or builds a request")
    func onlyJevKitTalksToTheNetwork() throws {
        let files = Self.swiftFiles()
        // A scan that finds no files must fail, not pass.
        try #require(files.count > 40, "the scan found only \(files.count) Swift files")
        try #require(files.contains(Self.transportFile), "the scan missed the transport file")

        var findings: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.repositoryRoot.appendingPathComponent(file), encoding: .utf8)
            for (number, line) in text.components(separatedBy: .newlines).enumerated() {
                // Comments may name the rule's words.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                for rule in Self.rules where !rule.allowed(file) && line.range(of: rule.pattern, options: .regularExpression) != nil {
                    findings.append("\(file):\(number + 1): \(rule.name)")
                }
            }
        }
        #expect(findings.isEmpty, "network code outside JevKit's client:\n\(findings.joined(separator: "\n"))")
    }

    @Test("No job builds code text from a String, so screen text cannot skip consent")
    func jobsUseLiteralCodeText() throws {
        let folder = "Packages/JevKit/Sources/JevKit/Jobs"
        let base: Set<String> = ["\(folder)/JevJob.swift", "\(folder)/JevJobRegistry.swift"]
        let files = Self.swiftFiles().filter { $0.hasPrefix(folder + "/") && !base.contains($0) }
        try #require(!files.isEmpty, "the scan found no job files")

        // These would turn any String into code text, which needs no consent.
        let pattern = #"stringLiteral:|stringInterpolation:|JevCodeText\(|\.code\(JevCodeText"#
        var findings: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.repositoryRoot.appendingPathComponent(file), encoding: .utf8)
            for (number, line) in text.components(separatedBy: .newlines).enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && line.range(of: pattern, options: .regularExpression) != nil {
                findings.append("\(file):\(number + 1)")
            }
        }
        #expect(findings.isEmpty, "a job builds code text from a String:\n\(findings.joined(separator: "\n"))")
    }

    @Test("The rules catch what they guard")
    func rulesMatch() {
        func matches(_ line: String) -> [String] {
            Self.rules.filter { line.range(of: $0.pattern, options: .regularExpression) != nil }.map(\.name)
        }
        #expect(matches("let session = URLSession.shared") == ["URLSession"])
        #expect(matches("var request = URLRequest(url: url)") == ["URLRequest"])
        #expect(matches(#"let url = URL(string: "https://example.com")"#) == ["a URL literal"])
        #expect(matches("let connection = NWConnection(host: host, port: 443, using: .tls)").count == 1)
        #expect(matches(#"let task = Process()"#) == ["a child process"])
        #expect(matches("let transport = URLSessionTransport()").isEmpty)
    }
}
