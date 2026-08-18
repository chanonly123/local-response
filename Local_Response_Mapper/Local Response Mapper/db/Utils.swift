//
//  DbObjectMethods.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import Foundation
import RealmSwift
import SwiftUI
import UniformTypeIdentifiers

/// Token colors lifted from the Highlightr stylesheets the app uses — `xcode`
/// for light, `tomorrow-night-bright` for dark — so text styled here matches
/// text that still goes through the highlighting engine.
struct SyntaxStyle {

    let base: Color
    let key: Color
    let string: Color
    let number: Color
    let keyword: Color

    static let light = SyntaxStyle(
        base: Color(hex: 0x000000),
        key: Color(hex: 0x836C28),
        string: Color(hex: 0xC41A16),
        number: Color(hex: 0x1C00CF),
        keyword: Color(hex: 0xAA0D91)
    )

    /// tomorrow-night-bright defines no `.hljs-attr`, so keys fall back to base.
    static let dark = SyntaxStyle(
        base: Color(hex: 0xEAEAEA),
        key: Color(hex: 0xEAEAEA),
        string: Color(hex: 0xB9CA4A),
        number: Color(hex: 0xE78C45),
        keyword: Color(hex: 0xE78C45)
    )

    static var current: SyntaxStyle {
        return switch ColorSchemeViewModel.shared.value {
        case .light: light
        case .dark: dark
        @unknown default: light
        }
    }

    func run(_ text: String, _ color: Color) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = color
        out.font = .system(size: Constants.fontSize)
        return out
    }

    /// A bare scalar — an HTTP method, a host, a status code. Nothing to parse,
    /// so the whole value takes one color based on its type.
    func scalar(_ text: String) -> AttributedString {
        return run(text, color(for: text))
    }

    /// One `key: value` line.
    func pair(key keyText: String, value: String) -> AttributedString {
        return run("\(keyText):", key) + run(" ", base) + run(value, color(for: value))
    }

    private func color(for scalar: String) -> Color {
        switch scalar {
        case "true", "false", "null": return keyword
        default: return isNumber(scalar) ? number : string
        }
    }

    private func isNumber(_ text: String) -> Bool {
        // The leading-character check keeps "inf"/"nan", which Double(_:)
        // happily parses, from being colored as numbers.
        guard let first = text.first,
              first.isNumber || first == "-" || first == "+" || first == "." else {
            return false
        }
        return Double(text) != nil
    }
}

/// One header or query parameter, kept as its own row so a long value can be
/// collapsed without hiding the ones around it.
struct KeyValuePair: Identifiable, Hashable {
    let key: String
    let value: String
    var id: String { key }
}

struct Utils {

    /// Theme names for `CodeEditor`, which still runs its own Highlightr.
    static func getThemeName(colorScheme: ColorScheme) -> String {
        return switch colorScheme {
        case .light: Constants.higlightThemeLight
        case .dark: Constants.higlightThemeDark
        @unknown default: Constants.higlightThemeDark
        }
    }

    static func getHost(_ from: String) -> AttributedString {
        return styledScalar(URL(string: from)?.host() ?? "")
    }

    static func getPath(_ from: String) -> AttributedString {
        return styledScalar(URL(string: from)?.path() ?? "")
    }

    static func getQueryParams(_ from: String) -> [String: String] {
        let comps = URLComponents(string: from)
        var params = [String: String]()
        comps?.queryItems?.forEach { params[$0.name] = $0.value }
        return params
    }

    /// Colors a single value the way the themes would, without running the
    /// syntax engine — these have no structure for a grammar to find.
    static func styledScalar(_ str: String) -> AttributedString {
        return SyntaxStyle.current.scalar(str)
    }

    static func dictToPairs(item: Map<String, String>) -> [KeyValuePair] {
        return item.map { KeyValuePair(key: $0.key, value: $0.value) }
    }

    static func dictToPairs(item: [String: String]) -> [KeyValuePair] {
        return item.keys.sorted().map { KeyValuePair(key: $0, value: item[$0]!) }
    }

    /// Same text as `dictToString`, without building throwaway attributes.
    static func dictToPlainString(item: Map<String, String>) -> String {
        return item.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    static func highlightJson(_ str: String, style: SyntaxStyle = .current) -> AttributedString {
        return JSONHighlighter.highlight(str, style: style)
    }

    static func getStatusColor(_ status: Int) -> Color {
        switch status {
        case 100...199: // Informational
            return Color.blue
        case 200...299: // Success
            return Color.green
        case 300...399: // Redirection
            return Color.orange
        case 400...499: // Client Error
            return Color.yellow
        case 500...599: // Server Error
            return Color.red
        default: // Unknown status
            return Color.gray
        }
    }

    static func prettyPrintJSON(from jsonString: String) throws -> String? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return jsonString
        }
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])

        return String(data: prettyData, encoding: .utf8)
    }

    static func copyToClipboard(_ string: String) {
        let gen = NSPasteboard.general
        gen.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func getCommonDescription(httpStatusCode: Int) -> String? {
        switch httpStatusCode {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 103: return "Early Hints"

        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"

        case 300: return "Multiple Choice"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 306: return "unused"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"

        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 418: return "I'm a teapot"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Content"
        case 423: return "Locked"
        case 424: return "Failed Dependency"
        case 425: return "Too Early"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"

        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 506: return "Variant Also Negotiates"
        case 510: return "Not Extended"
        case 511: return "Network Authentication Required"

        default: return nil
        }
    }

    /// The master switch, read straight from `UserDefaults` so the server can
    /// ask it on a background thread — the toggle that writes it lives in the
    /// toolbar as `@AppStorage`.
    static var mapRulesEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: Constants.mapRulesOffKey) }
        set { UserDefaults.standard.set(!newValue, forKey: Constants.mapRulesOffKey) }
    }

    /// Milliseconds the mapper waits before answering a request a rule matched.
    /// Read the same way as the master switch, so the server can ask for it off
    /// the main thread. Clamped on the way in — a negative wait means nothing,
    /// and one past the cap would outlast the lookup that is waiting on it.
    static var mapDelayMs: Int {
        get { min(max(UserDefaults.standard.integer(forKey: Constants.mapDelayMsKey), 0), Constants.maxMapDelayMs) }
        set { UserDefaults.standard.set(min(max(newValue, 0), Constants.maxMapDelayMs), forKey: Constants.mapDelayMsKey) }
    }

    /// The delay as the controls say it — one decimal, always seconds, so the
    /// label and the field never disagree about what `1500` is.
    static func delayLabel(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }

    static var isPreview: Bool {
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Determines the best file extension from response headers or URL.
    static func determineFileExtensionAndType(
        from: URLTaskObject
    ) -> (ext: String, type: ContentType) {

        func extractFilename(from contentDisposition: String) -> String? {
            let pattern = "filename=\"?([^\";]+)\"?"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: contentDisposition, range: NSRange(contentDisposition.startIndex..., in: contentDisposition)),
                  let range = Range(match.range(at: 1), in: contentDisposition) else {
                return nil
            }
            return String(contentDisposition[range])
        }

        var ext: String?

        // 1. Try filename from Content-Disposition
        if
            let contentDisposition = from.resHeaders["Content-Disposition"],
            let filename = extractFilename(from: contentDisposition)
        {
            ext = URL(fileURLWithPath: filename).pathExtension
        }

        // 2. If not found, try MIME → UTType → extension
        if ext?.isEmpty ?? true,
           let utType = UTType(mimeType: from.mimeType),
           let utExt = utType.preferredFilenameExtension
        {
            ext = utExt
        }

        // 3. If still not found, use URL path extension
        if ext?.isEmpty ?? true,
           let urlExt = URL(string: from.url)?.pathExtension,
           !urlExt.isEmpty
        {
            ext = urlExt
        }

        let finalExt = ext?.lowercased() ?? "bin"

        // Determine ContentType:
        let mimeType = from.resHeaders["Content-Type"] ?? from.mimeType
        var contentType = ContentType(fromMimeType: mimeType)

        // If MIME type was unhelpful, guess from extension
        if contentType == .unknown || contentType == .binary {
            let extBasedType = ContentType(fromExtension: finalExt)
            if extBasedType != .unknown {
                contentType = extBasedType
            }
        }

        return (finalExt, contentType)
    }
}
