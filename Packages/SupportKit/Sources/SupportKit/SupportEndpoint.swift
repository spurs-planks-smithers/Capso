import Foundation

/// This is the only first-party host that accepts an explicit support upload.
public enum SupportEndpoint {
    public static func url(path: String) throws -> URL {
        guard path.hasPrefix("/v1/"), !path.contains(".."), !path.contains("%"), !path.contains("?"), !path.contains("#"), !path.contains("\\"),
              path.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "/-_").contains($0) || CharacterSet.alphanumerics.contains($0) && $0.isASCII }),
              let url = URL(string: "https://feedback.nextshot.dev" + path), url.host == "feedback.nextshot.dev" else { throw SupportError.invalidInput }
        return url
    }
}
