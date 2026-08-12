//
//  MapLocalObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import RealmSwift

class MapLocalObject: Object, Identifiable {

    /// What a rule does once its matcher fires. A `mapResponse` rule answers the
    /// request itself and it never reaches the network; a `modifyRequest` rule
    /// edits the request and lets it go out, so several of them can apply to the
    /// same request.
    enum RuleKind: String, PersistableEnum {
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

    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var date: Double = Date().timeIntervalSince1970

    @Persisted var enable: Bool = false
    @Persisted var subUrl: String = ""
    @Persisted var method: String = ""
    @Persisted var resString: String = ""
    @Persisted var statusCode: String = ""
    @Persisted var resHeaders: String = ""

    @Persisted var kind: RuleKind = .mapResponse

    /// `modifyRequest` only: headers set on the outgoing request, one
    /// `name: value` per line. An existing header of the same name is replaced.
    @Persisted var reqHeaders: String = ""

    /// `modifyRequest` only: replacement request body. Empty leaves the body
    /// the app sent untouched.
    @Persisted var reqString: String = ""

    /// Position in the rule list. Only the first matching rule serves a
    /// response, so this is the rule's priority — see `DB.getLocalMapIfAvailable`.
    @Persisted var order: Int = 0

    /// Times this rule has served a response. `0` on an enabled rule is the
    /// usual sign that its url substring doesn't match what the app requests.
    @Persisted var hitCount: Int = 0

    convenience init(subUrl: String, method: String, statusCode: String, resHeaders: Map<String, String>, resString: String) {
        self.init()
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

    var bodyByteCount: Int { resString.utf8.count }

    var reqBodyByteCount: Int { reqString.utf8.count }

    /// A `modifyRequest` rule that sets no header and no body is a no-op — worth
    /// saying out loud in the editor rather than leaving it to silently do
    /// nothing.
    var changesRequest: Bool { reqHeaderCount > 0 || !reqString.isEmpty }

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

    var resHeadersMap: Map<String, String> { Self.headersMap(from: resHeaders) }

    var reqHeadersMap: Map<String, String> { Self.headersMap(from: reqHeaders) }

    private static func headersMap(from text: String) -> Map<String, String> {
        let map = Map<String, String>()
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .forEach {
                // Only the first colon separates the name from the value —
                // values such as `Location: https://host/path` carry their own.
                guard let colon = $0.firstIndex(of: ":") else {
                    let key = $0.trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty { map[key] = "" }
                    return
                }
                let key = $0[..<colon].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    map[key] = $0[$0.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
            }
        return map
    }
}
