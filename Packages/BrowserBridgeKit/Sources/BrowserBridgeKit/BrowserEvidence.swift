import Foundation

/// Only these page-evidence fields enter a native bundle. Unknown fields are dropped.
enum BrowserEvidence {
    static func text(_ value: Any?, limit: Int, redact: Bool = true) -> String {
        let raw = value as? String ?? ""
        var result = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 && $0.value != 127 }).prefix(limit))
        if redact {
            for pattern in [#"\bBearer\s+[A-Za-z0-9._~+/-]{8,}"#, #"\b(?:sk|pk|api)[_-][A-Za-z0-9_-]{16,}"#, #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, #"\b(password|secret|token|authorization|api[_-]?key)\s*[:=]\s*[^\s,;]+"#] {
                result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: [.regularExpression, .caseInsensitive])
            }
        }
        return result
    }
    static func url(_ value: Any?) -> String? {
        guard let raw = value as? String, raw.count <= 8192, var c = URLComponents(string: raw),
              ["https", "http"].contains(c.scheme), c.host != nil else { return nil }
        c.user = nil; c.password = nil; c.query = nil; c.fragment = nil
        c.path = c.path.components(separatedBy: "/").map { $0.count > 48 || $0.hasPrefix("sk_") || $0.hasPrefix("eyJ") ? "[redacted]" : $0 }.joined(separator: "/")
        return c.string
    }
    static func number(_ object: [String: Any], _ key: String, min: Double = 0, max: Double = 86400000) throws -> Double {
        guard let n = object[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
              (min...max).contains(n.doubleValue) else { throw BrowserBridgeError.invalid }
        return n.doubleValue
    }
    static func array(_ object: [String: Any], _ key: String, max: Int) throws -> [[String: Any]] {
        guard let values = object[key] as? [[String: Any]], values.count <= max else { throw BrowserBridgeError.invalid }; return values
    }
    static func action(_ input: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = ["at": try number(input, "at"), "kind": text(input["kind"], limit: 40), "label": text(input["label"], limit: 200)]
        if let id = input["elementId"] { result["elementId"] = text(id, limit: 100) }; return result
    }
    static func capture(_ input: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in ["id", "kind", "createdAt", "imageFile", "cleanImageFile"] { result[key] = input[key] }
        result["width"] = try number(input, "width", min: 1, max: 16000)
        result["height"] = try number(input, "height", min: 1, max: 16000)
        result["title"] = text(input["title"], limit: 200)
        result["note"] = text(input["note"], limit: 20000, redact: false)
        result["url"] = url(input["url"])
        let elements = try array(input, "elements", max: 2000).map { e -> [String: Any] in
            guard let bounds = e["bounds"] as? [String: Any] else { throw BrowserBridgeError.invalid }
            var r: [String: Any] = ["id": text(e["id"], limit: 100), "selector": text(e["selector"], limit: 500), "tag": text(e["tag"], limit: 30), "role": text(e["role"], limit: 60), "text": text(e["text"], limit: 300),
                "bounds": ["x": try number(bounds, "x", min: -100000, max: 100000), "y": try number(bounds, "y", min: -100000, max: 100000), "width": try number(bounds, "width", max: 100000), "height": try number(bounds, "height", max: 100000)]]
            r["frameURL"] = url(e["frameURL"]); return r
        }
        let ids = elements.compactMap { $0["id"] as? String }
        guard Set(ids).count == ids.count else { throw BrowserBridgeError.invalid }
        result["elements"] = elements
        result["marks"] = try array(input, "marks", max: 100).map { m -> [String: Any] in
            var r: [String: Any] = ["id": try number(m, "id", min: 1, max: 100), "kind": text(m["kind"], limit: 10), "x": try number(m, "x", max: result["width"] as! Double), "y": try number(m, "y", max: result["height"] as! Double), "note": text(m["note"], limit: 10000, redact: false)]
            if m["endX"] != nil { r["endX"] = try number(m, "endX", max: result["width"] as! Double) }
            if m["endY"] != nil { r["endY"] = try number(m, "endY", max: result["height"] as! Double) }
            if let id = m["elementId"] as? String { guard ids.contains(id) else { throw BrowserBridgeError.invalid }; r["elementId"] = id }
            return r
        }
        var actions = try array(input, "actions", max: 2000).map(action)
        var diagnostics = try array(input, "diagnostics", max: 1000).map { d -> [String: Any] in
            guard let kind = d["kind"] as? String, ["error", "request", "coverage", "gap"].contains(kind) else { throw BrowserBridgeError.invalid }
            var r: [String: Any] = ["at": try number(d, "at"), "kind": kind, "text": text(d["text"], limit: 1000)]
            r["url"] = url(d["url"])
            if let method = d["method"] { r["method"] = text(method, limit: 12) }
            if d["status"] != nil { r["status"] = try number(d, "status", max: 999) }
            if d["duration"] != nil { r["duration"] = try number(d, "duration") }; return r
        }
        if let clip = input["clip"] as? [String: Any] {
            let start = try number(clip, "start"), end = try number(clip, "end", min: start), issue = try number(clip, "issue", min: start, max: end)
            func selected(_ event: [String: Any]) -> Bool { let at = event["at"] as! Double; return at >= start && at <= end }
            var c: [String: Any] = ["start": start, "end": end, "issue": issue, "steps": try array(clip, "steps", max: 100).map(action).filter(selected)]
            if let media = clip["mediaFile"] as? String {
                guard BrowserPayload.safeName(media), ["webm", "mp4", "gif"].contains((media as NSString).pathExtension) else { throw BrowserBridgeError.invalid }
                c["mediaFile"] = media; c["mime"] = text(clip["mime"], limit: 80)
            }
            result["clip"] = c; actions = actions.filter(selected); diagnostics = diagnostics.filter(selected)
        }
        if input["keyFrames"] != nil {
            guard let clip = input["clip"] as? [String: Any], let id = input["id"] as? String else { throw BrowserBridgeError.invalid }
            let start = try number(clip, "start"), end = try number(clip, "end", min: start)
            result["keyFrames"] = try array(input, "keyFrames", max: 12).map { frame -> [String: Any] in
                guard let file = frame["file"] as? String, BrowserPayload.safeName(file), file.hasPrefix(id + "-"),
                      ["jpg", "jpeg", "png", "webp"].contains((file as NSString).pathExtension) else { throw BrowserBridgeError.invalid }
                return ["at": try number(frame, "at", min: start, max: end), "file": file,
                        "width": try number(frame, "width", min: 1, max: 16000), "height": try number(frame, "height", min: 1, max: 16000)]
            }
        }
        result["actions"] = actions; result["diagnostics"] = diagnostics
        return result
    }
}
