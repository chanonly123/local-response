//
//  Template.swift
//  Local Response Mapper
//

import Foundation

/// Placeholders a rule can carry — `{{uuid}}`, `{{timestamp}}`, `{{date:HH:mm}}`
/// — resolved fresh every time a rule fires, so a rule can send something that
/// has to differ per request instead of one frozen value.
///
/// Substitution happens here, in the mapper, not in the app being recorded: the
/// injected library only applies what the mapper hands back.
///
/// A token that names nothing is left exactly as written. Bodies and headers
/// legitimately contain braces, and a rule written before a variable existed
/// must keep sending the text it always sent.
struct TemplateResolver {

    /// Every builtin, in the order the help sheet lists them.
    enum Builtin: String, CaseIterable, Identifiable {
        case uuid
        case timestamp
        case timestampMs = "timestamp_ms"
        case iso8601
        case date
        case randomInt = "random_int"

        var id: String { rawValue }

        /// How the token is written, argument included.
        var token: String {
            switch self {
            case .date: "{{date:yyyy-MM-dd HH:mm:ss}}"
            case .randomInt: "{{random_int:1-100}}"
            default: "{{\(rawValue)}}"
            }
        }

        var detail: String {
            switch self {
            case .uuid: "A new UUID."
            case .timestamp: "Seconds since 1970."
            case .timestampMs: "Milliseconds since 1970."
            case .iso8601: "UTC, internet date-time."
            case .date: "The time now, in the format after the colon."
            case .randomInt: "A whole number in the range after the colon."
            }
        }
    }

    private let date: Date
    private let globals: [String: String]
    private let randomInt: (ClosedRange<Int>) -> Int
    private let makeUUID: () -> String

    /// Resolved tokens, so one request that uses `{{uuid}}` in two places sends
    /// the same id in both — a request id split across a header and the body is
    /// the point of having it.
    private var cache: [String: String] = [:]

    init(
        date: Date = Date(),
        globals: [String: String] = TemplateGlobals.dictionary,
        randomInt: @escaping (ClosedRange<Int>) -> Int = { Int.random(in: $0) },
        makeUUID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.date = date
        self.globals = globals
        self.randomInt = randomInt
        self.makeUUID = makeUUID
    }

    mutating func resolve(_ text: String) -> String {
        guard text.contains("{{") else { return text }

        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else {
                // Unclosed: the rest is text, not a token.
                out += rest[open.lowerBound...]
                return out
            }
            let token = String(after[..<close.lowerBound])
            out += value(for: token) ?? "{{\(token)}}"
            rest = after[close.upperBound...]
        }
        return out + rest
    }

    private mutating func value(for token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let cached = cache[trimmed] { return cached }
        guard let value = compute(trimmed) else { return nil }
        cache[trimmed] = value
        return value
    }

    private func compute(_ token: String) -> String? {
        let name: String
        let argument: String?
        if let colon = token.firstIndex(of: ":") {
            name = String(token[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            argument = String(token[token.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = token.lowercased()
            argument = nil
        }

        switch Builtin(rawValue: name) {
        case .uuid:
            return makeUUID()
        case .timestamp:
            return String(Int(date.timeIntervalSince1970))
        case .timestampMs:
            return String(Int(date.timeIntervalSince1970 * 1000))
        case .iso8601:
            return Self.iso8601String(date)
        case .date:
            guard let format = argument, !format.isEmpty else { return nil }
            return Self.string(from: date, format: format)
        case .randomInt:
            guard let range = argument.flatMap(Self.range(from:)) else { return nil }
            return String(randomInt(range))
        case .none:
            // Builtins win over a user variable of the same name, so a rule
            // written against `{{uuid}}` cannot be quietly repointed.
            return globals[token]
        }
    }

    /// `1-100`. A malformed range resolves to nothing, leaving the token
    /// visible in the request rather than sending a silent zero.
    private static func range(from argument: String) -> ClosedRange<Int>? {
        let parts = argument.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lower = Int(parts[0]), let upper = Int(parts[1]), lower <= upper else {
            return nil
        }
        return lower...upper
    }

    /// UTC and a fixed locale on both formatters: a rule has to send the same
    /// text whatever the machine running the mapper is set to.
    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

/// Variables the user defines once and reuses across rules — a token, a build
/// number, a base url.
///
/// Kept in `UserDefaults` rather than the database: a schema change there
/// recreates the file rather than migrating it, and these are meant to outlive
/// the recorded traffic they are used against.
enum TemplateGlobals {

    struct Variable: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String = ""
        var value: String = ""
    }

    static let storageKey = "template.globals"

    static var variables: [Variable] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode([Variable].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Lookup table for the resolver. Unnamed rows are the ones being typed —
    /// they are kept in the editor but name nothing yet.
    static var dictionary: [String: String] {
        var out = [String: String]()
        for variable in variables {
            let name = variable.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            out[name] = variable.value
        }
        return out
    }
}
