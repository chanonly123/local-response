//
//  JSONHighlighter.swift
//  Local Response Mapper
//
//  Created by Chandan on 07/08/26.
//

import SwiftUI

/// Single-pass JSON colorizer, replacing a highlight.js round trip through
/// JavaScriptCore. JSON carries no context a grammar has to resolve — every
/// token is identifiable from its first character — so one walk over the
/// string places all of them.
enum JSONHighlighter {

    /// Bodies past this size render unstyled. Coloring them produces tens of
    /// thousands of attribute runs, and both building those runs and laying
    /// them out cost far more than the tokenizing ever did.
    static let maxLength = 64 * 1024

    private enum Token {
        case key, string, number, keyword
    }

    static func highlight(_ str: String, style: SyntaxStyle = .current) -> AttributedString {
        guard str.utf8.count <= maxLength, looksLikeJSON(str) else {
            return plain(str, style: style)
        }
        return apply(scan(str), to: str, style: style)
    }

    /// highlight.js judges the document as a whole and leaves non-JSON bodies
    /// — form encoded, XML, multipart — entirely unstyled. Matching that keeps
    /// stray quotes and colons in those bodies from being colored as JSON.
    private static func looksLikeJSON(_ str: String) -> Bool {
        guard let first = str.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    private static func plain(_ str: String, style: SyntaxStyle) -> AttributedString {
        var out = AttributedString(str)
        out.foregroundColor = style.base
        out.font = .system(size: Constants.fontSize)
        return out
    }

    private static func scan(_ str: String) -> [(range: Range<String.Index>, token: Token)] {
        var tokens = [(range: Range<String.Index>, token: Token)]()
        var i = str.startIndex
        // Numbers and literals may only begin where a value is allowed, which
        // stops digits inside unquoted junk being picked up as numbers.
        var valueAllowed = true

        while i < str.endIndex {
            let c = str[i]

            if c == "\"" {
                let start = i
                i = str.index(after: i)
                while i < str.endIndex, str[i] != "\"" {
                    if str[i] == "\\", str.index(after: i) < str.endIndex {
                        i = str.index(after: i)
                    }
                    i = str.index(after: i)
                }
                if i < str.endIndex { i = str.index(after: i) }
                tokens.append((start..<i, isKey(str, after: i) ? .key : .string))
                valueAllowed = false

            } else if valueAllowed, c.isNumber || c == "-" {
                let start = i
                while i < str.endIndex, isNumberCharacter(str[i]) {
                    i = str.index(after: i)
                }
                tokens.append((start..<i, .number))
                valueAllowed = false

            } else if valueAllowed, let end = literalEnd(str, from: i) {
                tokens.append((i..<end, .keyword))
                i = end
                valueAllowed = false

            } else {
                if c == ":" || c == "," || c == "[" || c == "{" { valueAllowed = true }
                i = str.index(after: i)
            }
        }
        return tokens
    }

    /// A string is a key when the next significant character is a colon.
    private static func isKey(_ str: String, after index: String.Index) -> Bool {
        var j = index
        while j < str.endIndex, str[j].isWhitespace { j = str.index(after: j) }
        return j < str.endIndex && str[j] == ":"
    }

    private static func isNumberCharacter(_ c: Character) -> Bool {
        return c.isNumber || c == "." || c == "e" || c == "E" || c == "+" || c == "-"
    }

    private static func literalEnd(_ str: String, from index: String.Index) -> String.Index? {
        for literal in ["true", "false", "null"] where str[index...].hasPrefix(literal) {
            return str.index(index, offsetBy: literal.count)
        }
        return nil
    }

    private static func apply(
        _ tokens: [(range: Range<String.Index>, token: Token)],
        to str: String,
        style: SyntaxStyle
    ) -> AttributedString {
        var out = AttributedString(str)
        out.foregroundColor = style.base
        out.font = .system(size: Constants.fontSize)

        // Both indices walk forward together — re-seeking from the start for
        // every token would make this quadratic on large bodies.
        var strIndex = str.startIndex
        var attrIndex = out.startIndex

        for (range, token) in tokens {
            let lead = str.distance(from: strIndex, to: range.lowerBound)
            let lower = out.index(attrIndex, offsetByCharacters: lead)
            let length = str.distance(from: range.lowerBound, to: range.upperBound)
            let upper = out.index(lower, offsetByCharacters: length)

            out[lower..<upper].foregroundColor = color(for: token, style: style)

            strIndex = range.upperBound
            attrIndex = upper
        }
        return out
    }

    private static func color(for token: Token, style: SyntaxStyle) -> Color {
        return switch token {
        case .key: style.key
        case .string: style.string
        case .number: style.number
        case .keyword: style.keyword
        }
    }
}
