//
//  MapLocalObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import RealmSwift

class MapLocalObject: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var date: Double = Date().timeIntervalSince1970
    
    @Persisted var enable: Bool = false
    @Persisted var subUrl: String = ""
    @Persisted var method: String = ""
    @Persisted var resString: String = ""
    @Persisted var statusCode: String = ""
    @Persisted var resHeaders: String = ""

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

    var headerCount: Int {
        resHeaders.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    var bodyByteCount: Int { resString.utf8.count }

    /// True when this rule's matcher is a superset of `other`'s: every request
    /// `other` could serve, this one already catches. Since matching walks the
    /// list in `order` and stops at the first hit, a covered rule that sits
    /// later can never fire.
    ///
    /// Url matching is `request.url.contains(subUrl)`, so a url reaching
    /// `other` contains `other.subUrl`, which — when that in turn contains this
    /// rule's `subUrl` — means it reaches this rule too.
    func covers(_ other: MapLocalObject) -> Bool {
        guard matchesAnyMethod || method == other.method else { return false }
        return other.subUrl.contains(subUrl)
    }

    /// Header names are case-insensitive on the wire, so a rule that spells one
    /// `content-encoding` behaves the same as `Content-Encoding` and has to be
    /// found the same way.
    func header(_ name: String) -> String? {
        resHeadersMap.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var resHeadersMap: Map<String, String> {
        let map = Map<String, String>()
        resHeaders.split(separator: "\n", omittingEmptySubsequences: true)
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
