//
//  DbObjectMethods.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import Foundation
import RealmSwift
import SwiftUI
import Highlightr
import UniformTypeIdentifiers

struct Utils {

    static var highlightrLight: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: Constants.higlightThemeLight)
        h?.theme.setCodeFont(RPFont.systemFont(ofSize: Constants.fontSize))
        return h
    }()

    static var highlightrDark: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: Constants.higlightThemeDark)
        h?.theme.setCodeFont(RPFont.systemFont(ofSize: Constants.fontSize))
        return h
    }()

    static var highlightr: Highlightr? {
        return switch ColorSchemeViewModel.shared.value {
        case .light: highlightrLight
        case .dark: highlightrDark
        @unknown default: highlightrLight
        }
    }

    static func getThemeName(colorScheme: ColorScheme) -> String {
        return switch colorScheme {
        case .light: Constants.higlightThemeLight
        case .dark: Constants.higlightThemeDark
        @unknown default: Constants.higlightThemeDark
        }
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

    static func highlightJson(_ str: String) -> AttributedString {
        guard let attr = highlightr?.highlight(str, as: "json") else {
            return AttributedString(str)
        }
        return AttributedString(attr)
    }

    static func highlightYaml(_ str: String) -> AttributedString {
        guard let attr = highlightr?.highlight(str, as: "yaml") else {
            return AttributedString(str)
        }
        return AttributedString(attr)
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
