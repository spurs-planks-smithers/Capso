// Packages/JevKit/Sources/JevKit/Jobs/DataGuardPatterns.swift
import Foundation

/// One class of private data. Each kind has its own flag under `dataGuard`
/// (Drew, 2026-10-24).
public enum DataGuardKind: String, Sendable, CaseIterable {
    /// Email addresses and phone numbers.
    case contact
    /// Card numbers, IBANs, US Social Security numbers, and labeled account
    /// numbers.
    case numbers
    /// API keys, tokens, passwords, and private keys.
    case secrets
    /// Faces in photos and video. Found in the image, not in the text.
    case faces

    /// The kinds that local text rules find.
    public static let textKinds: Set<DataGuardKind> = [.contact, .numbers, .secrets]

    public var code: JevCodeText {
        switch self {
        case .contact: "contact"
        case .numbers: "numbers"
        case .secrets: "secrets"
        case .faces: "faces"
        }
    }
}

/// A local rule for screen text that may steer an AI agent. One strong match
/// flags the capture with no model. A weak match only makes the line a
/// candidate for the Jev check, because ordinary text matches it too.
public enum DataGuardInjectionRule: String, Sendable, CaseIterable {
    // Strong: phrases that exist to steer a model.
    case override
    case newInstructions
    case revealPrompt
    case chatTemplate
    case hideFromUser
    case addressesAgent
    // Weak: words that steering text uses, and ordinary text uses too.
    case agentName
    case systemWords
    case commandShape
    case dataRequest
    case attention

    public var isStrong: Bool {
        switch self {
        case .override, .newInstructions, .revealPrompt, .chatTemplate, .hideFromUser, .addressesAgent: true
        case .agentName, .systemWords, .commandShape, .dataRequest, .attention: false
        }
    }

    public var code: JevCodeText {
        switch self {
        case .override: "override"
        case .newInstructions: "newInstructions"
        case .revealPrompt: "revealPrompt"
        case .chatTemplate: "chatTemplate"
        case .hideFromUser: "hideFromUser"
        case .addressesAgent: "addressesAgent"
        case .agentName: "agentName"
        case .systemWords: "systemWords"
        case .commandShape: "commandShape"
        case .dataRequest: "dataRequest"
        case .attention: "attention"
        }
    }
}

/// A local rule for private data. `face` comes from the face finder, the rest
/// from screen text.
public enum DataGuardDataRule: String, Sendable, CaseIterable {
    case email
    case phone
    case card
    case iban
    case ssn
    case account
    case keyShape
    case jwt
    case privateKey
    case labeledSecret
    case face

    public var kind: DataGuardKind {
        switch self {
        case .email, .phone: .contact
        case .card, .iban, .ssn, .account: .numbers
        case .keyShape, .jwt, .privateKey, .labeledSecret: .secrets
        case .face: .faces
        }
    }

    public var code: JevCodeText {
        switch self {
        case .email: "email"
        case .phone: "phone"
        case .card: "card"
        case .iban: "iban"
        case .ssn: "ssn"
        case .account: "account"
        case .keyShape: "keyShape"
        case .jwt: "jwt"
        case .privateKey: "privateKey"
        case .labeledSecret: "labeledSecret"
        case .face: "face"
        }
    }

    /// What masking writes in place of a match.
    var placeholder: String {
        switch self {
        case .email: "[email]"
        case .phone: "[phone]"
        case .card, .iban, .ssn, .account: "[number]"
        case .keyShape, .jwt, .privateKey, .labeledSecret: "[secret]"
        case .face: "[face]"
        }
    }
}

/// One private data match inside one line of screen text.
public struct DataGuardTextHit: Equatable, Sendable {
    public var rule: DataGuardDataRule
    public var range: Range<String.Index>

    public init(rule: DataGuardDataRule, range: Range<String.Index>) {
        self.rule = rule
        self.range = range
    }
}

/// The guard's local text rules. They run on the Mac and send nothing. See
/// docs/superpowers/specs/2026-10-24-data-guard-design.md, "Injection check"
/// and "Private data check".
///
/// Every pattern is a constant, so a pattern that does not compile is a code
/// bug. `DataGuardPatternsTests` touches each one.
public enum DataGuardPatterns {
    // MARK: Injection

    /// Unicode NFKC form, lowercase, curly apostrophes made straight, zero
    /// width characters removed, and white space runs joined into one space.
    /// NFKC turns look-alike forms, such as full-width letters, into plain
    /// letters, so "ｉｇｎｏｒｅ" matches "ignore".
    public static func normalized(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in folded.unicodeScalars where !zeroWidth.contains(scalar.value) {
            if scalar.properties.isWhitespace {
                if !lastWasSpace { scalars.append(" ") }
                lastWasSpace = true
            } else {
                scalars.append(curlyApostrophes.contains(scalar.value) ? "'" : scalar)
                lastWasSpace = false
            }
        }
        if scalars.last == " " { scalars.removeLast() }
        return String(scalars)
    }

    /// The injection rules that match the line, each once, in rule order.
    public static func injectionRules(in line: String) -> [DataGuardInjectionRule] {
        let text = normalized(line)
        guard !text.isEmpty else { return [] }
        return injectionPatterns.compactMap { rule, regex in
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil ? nil : rule
        }
    }

    // Zero-width space, non-joiner, joiner, word joiner, byte order mark, soft hyphen.
    private static let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD]
    private static let curlyApostrophes: Set<UInt32> = [0x2018, 0x2019, 0x02BC]

    /// Names that only an AI system answers to. No bare "agent" or
    /// "assistant": Nextiva's contact center screens use both for people.
    private static let aiNames = #"(?:ai|llm|ai agent|ai assistant|coding agent|language model|large language model|claude|chatgpt|gpt|codex|copilot|gemini)"#

    private static let injectionPatterns: [(DataGuardInjectionRule, NSRegularExpression)] = [
        (.override, regex(#"\b(?:ignore|disregard|forget|override|bypass)\s+(?:(?:all|any|the|your|of|these|those)\s+)*(?:previous|prior|above|earlier|preceding|original|initial|existing|system|developer)\s+(?:instructions?|prompts?|rules|directions|guidelines|directives|context)\b|\b(?:ignore|disregard|forget)\s+(?:(?:all|any|the|your)\s+)*(?:instructions?|prompts?|everything)\s+(?:above|before|so far)\b"#)),
        (.newInstructions, regex(#"\b(?:new|updated|revised|real|actual|true)\s+(?:instructions?|task|directives?)\s*:"#)),
        (.revealPrompt, regex(#"\b(?:reveal|print|show|repeat|output|leak|dump)\s+(?:me\s+)?(?:your|the)\s+(?:system|developer|hidden|initial|original)\s+(?:prompt|message|instructions)\b"#)),
        (.chatTemplate, regex(#"<\|(?:im_start|im_end|system|user|assistant|endoftext)\|>|\[/?inst\]|<</?sys>>|</?system>|^#{2,}\s*(?:instruction|system)\b"#)),
        (.hideFromUser, regex(#"\b(?:do not|don't|never)\s+(?:tell|inform|alert|notify|show)\s+(?:this\s+to\s+)?(?:the\s+)?(?:user|reviewer|human|developer|operator)\b|\bwithout\s+(?:telling|informing|alerting|notifying)\s+(?:the\s+)?(?:user|reviewer|human|developer|operator)\b"#)),
        (.addressesAgent, regex(#"\b"# + aiNames + #"\s*[,:]\s*(?:please\s+)?(?:ignore|run|execute|delete|remove|send|upload|download|open|commit|push|install|email|forward|exfiltrate|copy|paste|write|modify|change|print|reveal)\b|\bif\s+you\s+are\s+(?:an?\s+)?(?:ai|llm|language model|large language model|ai agent|ai assistant|chatbot|bot)\b|\b(?:note|message|attention)\s+(?:to|for)\s+(?:the\s+|any\s+|all\s+)?"# + aiNames + #"s?\b"#)),
        (.agentName, regex(#"\b(?:ai agents?|ai assistants?|coding agents?|language models?|llms?|claude|chatgpt|codex|copilot|gemini|assistant)\b"#)),
        (.systemWords, regex(#"\b(?:system|developer)\s+(?:prompts?|messages?)\b|\bprompt\s+injection\b|\bjailbreak"#)),
        (.commandShape, regex(#"\bcurl\s|\bwget\s|\|\s*(?:sh|bash|zsh)\b|\brm\s+-rf\b|\bsudo\s|\bchmod\s+\+x\b|\bgit\s+push\b|\bbase64\s+(?:-d|--decode)\b|\bpowershell\b|\bnc\s+-e\b"#)),
        (.dataRequest, regex(#"\bexfiltrat\w*|\b(?:send|upload|post|forward|leak)\s+(?:(?:the|your|all|any|my)\s+)?(?:api keys?|keys?|secrets?|tokens?|credentials|passwords?|environment variables|\.env|files?|code|repo|repository|data)\s+(?:to|into)\b|\b(?:api keys?|ssh keys?|access tokens?|credentials)\b"#)),
        (.attention, regex(#"^(?:important|attention|urgent|warning)\s*[:!]"#)),
    ]

    // MARK: Private data

    /// The private data matches in one line, by start, for the given text
    /// kinds. Overlapping matches of different rules all appear.
    public static func dataHits(in line: String, kinds: Set<DataGuardKind> = DataGuardKind.textKinds) -> [DataGuardTextHit] {
        guard !line.isEmpty, !kinds.isDisjoint(with: DataGuardKind.textKinds) else { return [] }
        let whole = NSRange(line.startIndex..., in: line)
        var hits: [DataGuardTextHit] = []

        func add(_ rule: DataGuardDataRule, _ range: NSRange) {
            if let range = Range(range, in: line) {
                hits.append(DataGuardTextHit(rule: rule, range: range))
            }
        }

        if kinds.contains(.contact) {
            for match in email.matches(in: line, range: whole) {
                add(.email, match.range)
            }
            for match in phoneDetector?.matches(in: line, range: whole) ?? [] {
                // E.164 allows at most 15 digits. A longer run is a card or an id.
                if let range = Range(match.range, in: line), (7...15).contains(line[range].filter(\.isNumber).count) {
                    add(.phone, match.range)
                }
            }
        }
        if kinds.contains(.numbers) {
            for match in cardCandidate.matches(in: line, range: whole) {
                guard let range = Range(match.range, in: line) else { continue }
                let digits = line[range].compactMap(\.wholeNumberValue)
                if isCardNumber(digits) { add(.card, match.range) }
            }
            for match in ibanCandidate.matches(in: line, range: whole) {
                guard let range = Range(match.range, in: line) else { continue }
                if passesIBAN(line[range].filter { !$0.isWhitespace }) { add(.iban, match.range) }
            }
            for match in ssnCandidate.matches(in: line, range: whole) {
                guard let range = Range(match.range, in: line) else { continue }
                let parts = line[range].split(separator: "-").map(String.init)
                if parts.count == 3, isIssuableSSN(area: parts[0], group: parts[1], serial: parts[2]) { add(.ssn, match.range) }
            }
            for match in labeledAccount.matches(in: line, range: whole) {
                let value = match.range(at: 1)
                guard let range = Range(value, in: line), line[range].filter(\.isNumber).count >= 4 else { continue }
                add(.account, value)
            }
        }
        if kinds.contains(.secrets) {
            for (rule, regex) in secretPatterns {
                for match in regex.matches(in: line, range: whole) {
                    add(rule, match.range)
                }
            }
        }
        return hits.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The line with every private data match of every text kind replaced by
    /// its placeholder, for example `[email]`. It runs whatever the kind flags
    /// say: masking only removes data from a request.
    public static func masked(_ line: String) -> String {
        let hits = dataHits(in: line)
        guard !hits.isEmpty else { return line }
        // Merge overlapping matches, so each character is replaced once.
        var merged: [(range: Range<String.Index>, placeholder: String)] = []
        for hit in hits {
            if let last = merged.last, hit.range.lowerBound < last.range.upperBound {
                merged[merged.count - 1].range = last.range.lowerBound..<max(last.range.upperBound, hit.range.upperBound)
            } else {
                merged.append((hit.range, hit.rule.placeholder))
            }
        }
        var result = line
        for entry in merged.reversed() {
            result.replaceSubrange(entry.range, with: entry.placeholder)
        }
        return result
    }

    /// The Luhn checksum, used by every payment card number.
    static func passesLuhn(_ digits: [Int]) -> Bool {
        guard !digits.isEmpty else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    /// 13 to 19 digits, a known card prefix, the Luhn checksum, and not all
    /// one digit. The prefix rule keeps most timestamps and order numbers out.
    static func isCardNumber(_ digits: [Int]) -> Bool {
        guard (13...19).contains(digits.count), Set(digits).count > 1, passesLuhn(digits) else { return false }
        let first2 = digits[0] * 10 + digits[1]
        let first4 = first2 * 100 + digits[2] * 10 + digits[3]
        switch digits[0] {
        case 4: return true // Visa
        case 3: return [34, 37, 35, 36, 38, 30].contains(first2) // American Express, JCB, Diners
        case 5: return (51...55).contains(first2) // Mastercard
        case 2: return (2221...2720).contains(first4) // Mastercard 2-series
        case 6: return first4 == 6011 || first2 == 65 || (644...649).contains(first4 / 10) || first2 == 62 // Discover, UnionPay
        default: return false
        }
    }

    /// ISO 13616: move the first four characters to the end, turn letters
    /// into numbers (A is 10), and the remainder mod 97 must be 1.
    static func passesIBAN(_ text: String) -> Bool {
        let chars = Array(text.uppercased())
        guard (15...34).contains(chars.count), chars.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        var remainder = 0
        for char in chars[4...] + chars[..<4] {
            let value: Int
            if let digit = char.wholeNumberValue {
                value = digit
            } else if let ascii = char.asciiValue {
                value = Int(ascii) - 55
            } else {
                return false
            }
            remainder = (value < 10 ? remainder * 10 + value : remainder * 100 + value) % 97
        }
        return remainder == 1
    }

    /// The SSA never issues area 000, 666, or 900 to 999, group 00, or
    /// serial 0000.
    static func isIssuableSSN(area: String, group: String, serial: String) -> Bool {
        guard let areaNumber = Int(area), let groupNumber = Int(group), let serialNumber = Int(serial) else { return false }
        return areaNumber != 0 && areaNumber != 666 && areaNumber < 900 && groupNumber != 0 && serialNumber != 0
    }

    // File extensions that look like a top-level domain in "icon@2x.png".
    private static let email = regex(#"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?!(?:png|jpe?g|gif|svg|webp|heic|pdf|swift|js|ts|py|md|json)\b)[A-Za-z]{2,}\b"#)
    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    private static let cardCandidate = regex(#"(?<![\d-])\d(?:[ -]?\d){12,18}(?![\d-])"#)
    private static let ibanCandidate = regex(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b"#, caseInsensitive: false)
    private static let ssnCandidate = regex(#"(?<![\d-])\d{3}-\d{2}-\d{4}(?![\d-])"#)
    private static let labeledAccount = regex(#"\b(?:account|acct|a/c|routing|member\s*id|policy|customer\s*id)\b\.?\s*(?:no\.?|number|num|#|id)?\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9-]{5,})"#)
    private static let secretPatterns: [(DataGuardDataRule, NSRegularExpression)] = [
        (.keyShape, regex(#"\bsk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_-]{20,}|\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|\bgh[pousr]_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{22,}|\b(?:AKIA|ASIA)[0-9A-Z]{16}\b|\bxox[abprs]-[A-Za-z0-9-]{10,}|\bAIza[0-9A-Za-z_-]{35}|\bglpat-[A-Za-z0-9_-]{20,}|\bnpm_[A-Za-z0-9]{36}\b"#, caseInsensitive: false)),
        (.jwt, regex(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, caseInsensitive: false)),
        (.privateKey, regex(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, caseInsensitive: false)),
        (.labeledSecret, regex(#"\b(?:api[_ -]?key|secret|token|password|passwd|pwd|client[_ -]?secret|access[_ -]?key)\b\s*[:=]\s*["']?[^\s"']{8,}"#)),
    ]

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines])
        } catch {
            preconditionFailure("DataGuardPatterns: a constant pattern does not compile")
        }
    }
}
