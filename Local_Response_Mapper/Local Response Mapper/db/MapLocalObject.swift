//
//  MapLocalObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import GRDB

/// One mapping rule. A reference type so a rule handed to the editor can be
/// mutated field by field and written back as a whole row — see
/// `DB.updateMapRule(id:_:)`.
final class MapLocalObject: Codable, Identifiable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "mapRule"


    /// What a rule does once its matcher fires. A `mapResponse` rule answers the
    /// request itself and it never reaches the network; a `modifyRequest` rule
    /// edits the request and lets it go out, so several of them can apply to the
    /// same request.
    enum RuleKind: String, Codable, CaseIterable {
        case mapResponse
        case modifyRequest

        var title: String {
            switch self {
            case .mapResponse: "Map Response"
            case .modifyRequest: "Modify Request"
            }
        }

        /// what the rule changes, for the card header
        var caption: String {
            switch self {
            case .mapResponse: "what the app receives instead"
            case .modifyRequest: "what goes out, before sending"
            }
        }

        /// short tag for the rule list
        var badge: String {
            switch self {
            case .mapResponse: "RES"
            case .modifyRequest: "REQ"
            }
        }
    }

    var id: String = UUID().uuidString
    var date: Double = Date().timeIntervalSince1970

    var enable: Bool = false
    var subUrl: String = ""
    var method: String = ""
    var resString: String = ""
    var statusCode: String = ""
    var resHeaders: String = ""

    var kind: RuleKind = .mapResponse

    /// `modifyRequest` only: headers set on the outgoing request, one
    /// `name: value` per line. An existing header of the same name is replaced.
    var reqHeaders: String = ""

    /// `modifyRequest` only: query parameters set on the outgoing url, one
    /// `name: value` per line. A parameter the url already carries is replaced,
    /// the rest are kept.
    var reqQuery: String = ""

    /// `modifyRequest` only: replacement request body. Empty leaves the body
    /// the app sent untouched.
    var reqString: String = ""

    /// Position in the rule list. Only the first matching rule serves a
    /// response, so this is the rule's priority — see `DB.getLocalMapIfAvailable`.
    var order: Int = 0

    /// Times this rule has served a response. `0` on an enabled rule is the
    /// usual sign that its url substring doesn't match what the app requests.
    var hitCount: Int = 0

    /// `order` is a reserved word in SQL, so the column carries a different
    /// name than the property it fills.
    enum CodingKeys: String, CodingKey {
        case id, date, enable, subUrl, method, resString, statusCode, resHeaders
        case kind, reqHeaders, reqQuery, reqString, hitCount
        case order = "sortOrder"
    }

    init() {}

    init(subUrl: String, method: String, statusCode: String, resHeaders: [String: String], resString: String) {
        self.method = method
        self.statusCode = statusCode
        self.subUrl = subUrl
        let keys = resHeaders.keys.sorted()
        self.resHeaders = keys.map { "\($0): \(resHeaders[$0] ?? "")"  }.joined(separator: "\n")
        self.resString = resString
    }

    var status: Int { Int(statusCode) ?? 0 }

    var isValidStatus: Bool { Int(statusCode) != nil }

    /// `* (any)` in the picker stands for "every method".
    var matchesAnyMethod: Bool { method.contains("*") }

    /// `*` on its own stands for "every url", the same way the method picker
    /// spells it.
    var matchesAnyUrl: Bool { trimmedSubUrl == "*" }

    /// An empty url matches nothing rather than everything: a blank field is a
    /// rule that hasn't been written yet, and having it swallow all traffic the
    /// moment it is enabled is never what was meant. `*` is the way to ask for
    /// every url.
    var matchesNoUrl: Bool { trimmedSubUrl.isEmpty }

    var trimmedSubUrl: String { subUrl.trimmingCharacters(in: .whitespaces) }

    var headerCount: Int { Self.headerCount(in: resHeaders) }

    var reqHeaderCount: Int { Self.headerCount(in: reqHeaders) }

    var reqQueryCount: Int { Self.headerCount(in: reqQuery) }

    var bodyByteCount: Int { resString.utf8.count }

    var reqBodyByteCount: Int { reqString.utf8.count }

    /// A `modifyRequest` rule that sets no query parameter, no header and no
    /// body is a no-op — worth saying out loud in the editor rather than
    /// leaving it to silently do nothing.
    var changesRequest: Bool { reqQueryCount > 0 || reqHeaderCount > 0 || !reqString.isEmpty }

    private static func headerCount(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// True when this rule's matcher is a superset of `other`'s: every request
    /// `other` could serve, this one already catches. Since matching walks the
    /// list in `order` and stops at the first `mapResponse` hit, a covered rule
    /// that sits later can never fire.
    ///
    /// Url matching is `request.url.contains(subUrl)`, so a url reaching
    /// `other` contains `other.subUrl`, which — when that in turn contains this
    /// rule's `subUrl` — means it reaches this rule too.
    ///
    /// Only rules of the same kind can shadow each other, and only
    /// `mapResponse` ones actually do: every matching `modifyRequest` rule is
    /// applied, so none of them takes traffic from another.
    func covers(_ other: MapLocalObject) -> Bool {
        guard kind == .mapResponse, other.kind == .mapResponse else { return false }
        guard matchesAnyMethod || method == other.method else { return false }
        // A rule that fires for nothing takes no traffic and has none to lose.
        guard !matchesNoUrl, !other.matchesNoUrl else { return false }
        if matchesAnyUrl { return true }
        guard !other.matchesAnyUrl else { return false }
        return other.trimmedSubUrl.contains(trimmedSubUrl)
    }

    /// Same match test the server runs — see `DB.getLocalMapIfAvailable`.
    func matches(url: String, method: String) -> Bool {
        guard matchesAnyMethod || self.method == method else { return false }
        guard !matchesNoUrl else { return false }
        return matchesAnyUrl || url.contains(trimmedSubUrl)
    }

    /// Header names are case-insensitive on the wire, so a rule that spells one
    /// `content-encoding` behaves the same as `Content-Encoding` and has to be
    /// found the same way.
    func header(_ name: String) -> String? {
        resHeadersMap.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var resHeadersMap: [String: String] { Self.headersMap(from: resHeaders) }

    var reqHeadersMap: [String: String] { Self.headersMap(from: reqHeaders) }

    /// Query parameters are written the same way as headers, `name: value` per
    /// line — but `name=value` is what a url itself looks like, so a line
    /// without a colon is split on the first `=` instead of being read as a
    /// name with no value.
    var reqQueryMap: [String: String] { Self.headersMap(from: reqQuery, orSplitOn: "=") }

    private static func headersMap(from text: String, orSplitOn fallback: Character? = nil) -> [String: String] {
        var map = [String: String]()
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .forEach {
                // Only the first colon separates the name from the value —
                // values such as `Location: https://host/path` carry their own.
                guard let separator = $0.firstIndex(of: ":") ?? fallback.flatMap($0.firstIndex(of:)) else {
                    let key = $0.trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty { map[key] = "" }
                    return
                }
                let key = $0[..<separator].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    map[key] = $0[$0.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                }
            }
        return map
    }
}
