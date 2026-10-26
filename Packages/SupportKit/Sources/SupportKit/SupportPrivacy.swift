import Foundation
import Vision
import ImageIO

/// These local checks add protection before upload. Server checks remain required.
public enum SupportPrivacy {
    public enum Finding: String, Sendable { case credential, governmentIdentifier, paymentNumber }
    private static let credentials = [
        #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
        #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{20,})\b"#,
        #"(?i)\b(?:password|passwd|api[_ -]?key|access[_ -]?token|authorization)\s*[:=]\s*[\"']?(?:bearer\s+)?[^\s\"']{6,}"#,
    ]

    public static func findings(in text: String) -> Set<Finding> {
        var result: Set<Finding> = []
        if credentials.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { result.insert(.credential) }
        if text.range(of: #"\b(?!000|666|9\d\d)\d{3}[- ](?!00)\d{2}[- ](?!0000)\d{4}\b"#, options: .regularExpression) != nil { result.insert(.governmentIdentifier) }
        if let pattern = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#) {
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let r = Range(match.range, in: text) else { continue }
                let digits = text[r].compactMap(\.wholeNumberValue)
                if (13...19).contains(digits.count), Set(digits).count > 1, luhn(digits) { result.insert(.paymentNumber) }
            }
        }
        return result
    }

    private static func luhn(_ digits: [Int]) -> Bool {
        digits.reversed().enumerated().reduce(0) { sum, value in
            let number = value.offset.isMultiple(of: 2) ? value.element : value.element * 2
            return sum + (number > 9 ? number - 9 : number)
        }.isMultiple(of: 10)
    }

    static func checkImage(_ image: CGImage) throws {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { throw SupportError.incompleteOCR }
        var bytes = 0
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let line = observation.topCandidates(1).first else { throw SupportError.incompleteOCR }
            bytes += line.string.utf8.count
            guard bytes <= SupportLimits.textBytes else { throw SupportError.tooLarge }
            guard findings(in: line.string).isEmpty else { throw SupportError.sensitiveContent }
        }
    }
}
