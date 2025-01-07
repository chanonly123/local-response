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

struct Utils {

    static var highlightrLight: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: Constants.higlightThemeLight)
        return h
    }()

    static var highlightrDark: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: Constants.higlightThemeDark)
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

    static func getIPAddress() -> String? {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

                // Check interface name:
                // wifi = ["en0"]
                // wired = ["en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

                let name = String(cString: interface.ifa_name)
                if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {

                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
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
}
