//
//  FilterExpression.swift
//  Local Response Mapper
//

import Foundation

/// Parses filter text like `"app" && ("profile" || "todo")` into a boolean
/// expression tree, matched against a record's url/bundleID.
indirect enum FilterExpression {
    case term(String)
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)

    private enum Token: Equatable {
        case lparen, rparen, and, or, term(String)
    }

    /// Returns `nil` for blank input. Bare words with no `&&`/`||` between
    /// them are combined with AND, so `app profile` behaves like `app && profile`.
    static func parse(_ input: String) -> FilterExpression? {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else { return nil }
        var pos = 0
        return parseOr(tokens, &pos)
    }

    /// Builds a `WHERE` fragment matching records whose `url` or `bundleID`
    /// contains each term, combined per the parsed tree. `LIKE` is
    /// case-insensitive for ASCII in SQLite, which is what the search box
    /// promises.
    func toSQL() -> (sql: String, arguments: [String]) {
        (sql, args)
    }

    private var sql: String {
        switch self {
        case .term:
            return "(url LIKE ? ESCAPE '\\' OR bundleID LIKE ? ESCAPE '\\')"
        case let .and(lhs, rhs):
            return "(\(lhs.sql) AND \(rhs.sql))"
        case let .or(lhs, rhs):
            return "(\(lhs.sql) OR \(rhs.sql))"
        }
    }

    private var args: [String] {
        switch self {
        case let .term(value):
            let pattern = Self.containsPattern(value)
            return [pattern, pattern]
        case let .and(lhs, rhs), let .or(lhs, rhs):
            return lhs.args + rhs.args
        }
    }

    /// A `LIKE` pattern matching anything containing `value`. The wildcards
    /// `%` and `_` are ordinary characters in a url, so a term carrying one
    /// has to be escaped rather than left to match everything.
    private static func containsPattern(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c == "(" {
                tokens.append(.lparen)
                i += 1
            } else if c == ")" {
                tokens.append(.rparen)
                i += 1
            } else if c == "&", i + 1 < chars.count, chars[i + 1] == "&" {
                tokens.append(.and)
                i += 2
            } else if c == "|", i + 1 < chars.count, chars[i + 1] == "|" {
                tokens.append(.or)
                i += 2
            } else if c == "\"" {
                var j = i + 1
                var term = ""
                while j < chars.count, chars[j] != "\"" {
                    term.append(chars[j])
                    j += 1
                }
                if !term.isEmpty {
                    tokens.append(.term(term))
                }
                i = j < chars.count ? j + 1 : j
            } else {
                var j = i
                var term = ""
                while j < chars.count, !chars[j].isWhitespace, chars[j] != "(", chars[j] != ")" {
                    if chars[j] == "&", j + 1 < chars.count, chars[j + 1] == "&" { break }
                    if chars[j] == "|", j + 1 < chars.count, chars[j + 1] == "|" { break }
                    term.append(chars[j])
                    j += 1
                }
                tokens.append(.term(term))
                i = j
            }
        }
        return tokens
    }

    private static func parseOr(_ tokens: [Token], _ pos: inout Int) -> FilterExpression? {
        guard var left = parseAnd(tokens, &pos) else { return nil }
        while pos < tokens.count, tokens[pos] == .or {
            pos += 1
            guard let right = parseAnd(tokens, &pos) else { break }
            left = .or(left, right)
        }
        return left
    }

    private static func parseAnd(_ tokens: [Token], _ pos: inout Int) -> FilterExpression? {
        guard var left = parsePrimary(tokens, &pos) else { return nil }
        while pos < tokens.count {
            if tokens[pos] == .and {
                pos += 1
                guard let right = parsePrimary(tokens, &pos) else { break }
                left = .and(left, right)
            } else if tokens[pos] == .lparen || isTerm(tokens[pos]) {
                // Juxtaposed primaries with no explicit operator: implicit AND.
                guard let right = parsePrimary(tokens, &pos) else { break }
                left = .and(left, right)
            } else {
                break
            }
        }
        return left
    }

    private static func parsePrimary(_ tokens: [Token], _ pos: inout Int) -> FilterExpression? {
        guard pos < tokens.count else { return nil }
        switch tokens[pos] {
        case .lparen:
            pos += 1
            let inner = parseOr(tokens, &pos)
            if pos < tokens.count, tokens[pos] == .rparen {
                pos += 1
            }
            return inner
        case let .term(value):
            pos += 1
            return .term(value)
        case .and, .or, .rparen:
            return nil
        }
    }

    private static func isTerm(_ token: Token) -> Bool {
        if case .term = token { return true }
        return false
    }
}
