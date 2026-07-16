//
//  DbObjectMethods.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import Foundation
import RealmSwift
import SwiftUI
import AppKit
import CodeEditSourceEditor
import UniformTypeIdentifiers

struct Utils {

    /// Syntax-highlighting theme for the CodeEditSourceEditor text views,
    /// picked to match the current app color scheme.
    static func editorTheme(_ colorScheme: ColorScheme) -> EditorTheme {
        colorScheme == .dark ? darkEditorTheme : lightEditorTheme
    }

    private static func ns(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Xcode-like light theme.
    private static let lightEditorTheme = EditorTheme(
        text: .init(color: ns(0, 0, 0)),
        insertionPoint: ns(0, 0, 0),
        invisibles: .init(color: ns(0.8, 0.8, 0.8)),
        background: ns(1, 1, 1),
        lineHighlight: ns(0.91, 0.95, 1.0),
        selection: ns(0.70, 0.84, 1.0),
        keywords: .init(color: ns(0.67, 0.05, 0.57)),
        commands: .init(color: ns(0.15, 0.30, 0.85)),
        types: .init(color: ns(0.16, 0.34, 0.52)),
        attributes: .init(color: ns(0.44, 0.30, 0.60)),
        variables: .init(color: ns(0.15, 0.30, 0.85)),
        values: .init(color: ns(0, 0, 0)),
        numbers: .init(color: ns(0.11, 0.0, 0.81)),
        strings: .init(color: ns(0.77, 0.10, 0.09)),
        characters: .init(color: ns(0.11, 0.0, 0.81)),
        comments: .init(color: ns(0.0, 0.45, 0.0))
    )

    /// Tomorrow-Night-Bright-like dark theme.
    private static let darkEditorTheme = EditorTheme(
        text: .init(color: ns(0.92, 0.92, 0.92)),
        insertionPoint: ns(1, 1, 1),
        invisibles: .init(color: ns(0.30, 0.30, 0.30)),
        background: ns(0, 0, 0),
        lineHighlight: ns(0.15, 0.15, 0.15),
        selection: ns(0.24, 0.28, 0.34),
        keywords: .init(color: ns(0.76, 0.59, 0.85)),
        commands: .init(color: ns(0.48, 0.65, 0.85)),
        types: .init(color: ns(0.91, 0.77, 0.28)),
        attributes: .init(color: ns(0.91, 0.55, 0.27)),
        variables: .init(color: ns(0.84, 0.31, 0.33)),
        values: .init(color: ns(0.92, 0.92, 0.92)),
        numbers: .init(color: ns(0.91, 0.55, 0.27)),
        strings: .init(color: ns(0.72, 0.79, 0.29)),
        characters: .init(color: ns(0.72, 0.79, 0.29)),
        comments: .init(color: ns(0.59, 0.60, 0.59))
    )

    /// Scheme-aware colors for the lightweight `AttributedString` highlighters below.
    private struct SyntaxColors {
        let key: Color
        let string: Color
        let number: Color
        let keyword: Color

        static var current: SyntaxColors {
            if ColorSchemeViewModel.shared.value == .dark {
                return .init(
                    key: Color(red: 0.48, green: 0.65, blue: 0.85),
                    string: Color(red: 0.72, green: 0.79, blue: 0.29),
                    number: Color(red: 0.91, green: 0.55, blue: 0.27),
                    keyword: Color(red: 0.76, green: 0.59, blue: 0.85)
                )
            } else {
                return .init(
                    key: Color(red: 0.15, green: 0.30, blue: 0.85),
                    string: Color(red: 0.77, green: 0.10, blue: 0.09),
                    number: Color(red: 0.11, green: 0.0, blue: 0.81),
                    keyword: Color(red: 0.67, green: 0.05, blue: 0.57)
                )
            }
        }
    }

    private static func colored(_ string: String, _ color: Color?) -> AttributedString {
        var a = AttributedString(string)
        if let color { a.foregroundColor = color }
        return a
    }

    static func getHost(_ from: String) -> AttributedString {
        return highlightYaml(URL(string: from)?.host() ?? "")
    }

    static func getPath(_ from: String) -> AttributedString {
        return highlightYaml(URL(string: from)?.path() ?? "")
    }

    static func getQueryParams(_ from: String) -> [String: String] {
        let comps = URLComponents(string: from)
        var params = [String: String]()
        comps?.queryItems?.forEach { params[$0.name] = $0.value }
        return params
    }

    static func dictToString(item: Map<String, String>) -> AttributedString {
        let code = item.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return highlightYaml(code)
    }

    static func dictToString(item: [String: String]) -> AttributedString {
        let keys: [String] = item.keys.sorted(by: { $0 < $1 })
        let code = keys.map { "\($0): \(item[$0]!)" }.joined(separator: "\n")
        return highlightYaml(code)
    }

    /// Lightweight, dependency-free JSON colorizer for the detail panel.
    /// Colors strings (keys vs values), numbers and `true`/`false`/`null`.
    static func highlightJson(_ str: String) -> AttributedString {
        let colors = SyntaxColors.current
        let chars = Array(str)
        var result = AttributedString()
        var i = 0

        func nextNonSpaceIsColon(from idx: Int) -> Bool {
            var j = idx
            while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
            return j < chars.count && chars[j] == ":"
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                var s = "\""
                var j = i + 1
                while j < chars.count {
                    let cc = chars[j]
                    if cc == "\\", j + 1 < chars.count {
                        s.append(cc)
                        s.append(chars[j + 1])
                        j += 2
                        continue
                    }
                    s.append(cc)
                    j += 1
                    if cc == "\"" { break }
                }
                let isKey = nextNonSpaceIsColon(from: j)
                result += colored(s, isKey ? colors.key : colors.string)
                i = j
            } else if c.isNumber || (c == "-" && i + 1 < chars.count && chars[i + 1].isNumber) {
                var s = ""
                var j = i
                while j < chars.count, chars[j].isNumber || "+-.eE".contains(chars[j]) {
                    s.append(chars[j])
                    j += 1
                }
                result += colored(s, colors.number)
                i = j
            } else if c.isLetter {
                var s = ""
                var j = i
                while j < chars.count, chars[j].isLetter { s.append(chars[j]); j += 1 }
                if s == "true" || s == "false" || s == "null" {
                    result += colored(s, colors.keyword)
                } else {
                    result += AttributedString(s)
                }
                i = j
            } else {
                result += AttributedString(String(c))
                i += 1
            }
        }
        return result
    }

    /// Lightweight, dependency-free YAML-ish colorizer for the detail panel.
    /// Colors the `key:` portion of each line.
    static func highlightYaml(_ str: String) -> AttributedString {
        let colors = SyntaxColors.current
        var result = AttributedString()
        let lines = str.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            if let colon = line.firstIndex(of: ":") {
                result += colored(String(line[..<colon]), colors.key)
                result += AttributedString(String(line[colon...]))
            } else {
                result += AttributedString(line)
            }
        }
        return result
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
