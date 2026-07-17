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

    // Request-mapping fields (used when mode == .modifyRequest)
    @Persisted var mode: String = MapMode.mockResponse.rawValue
    @Persisted var reqHeaders: String = ""
    @Persisted var urlRewrite: String = ""
    @Persisted var methodOverride: String = ""

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

    var resHeadersMap: Map<String, String> {
        let map = Map<String, String>()
        resHeaders.split(separator: "\n", omittingEmptySubsequences: true)
            .forEach {
                let comps = $0.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if comps.count > 0 {
                    map[comps[0]] = comps.count > 1 ? comps[1] : ""
                }
            }
        return map
    }

    var mapMode: MapMode { MapMode(rawValue: mode) ?? .mockResponse }

    /// Parses `reqHeaders` (one `key: value` per line) into a `RequestOverride`.
    /// Conventions: `key: value` sets/overrides, `key:` (empty) removes that key,
    /// `*:` (empty) drops all original headers first.
    var requestOverride: RequestOverride {
        var clearAll = false
        var setHeaders = [String: String]()
        var removeHeaders = [String]()

        reqHeaders.split(separator: "\n", omittingEmptySubsequences: true).forEach { line in
            let raw = String(line)
            // Split on the first colon only, so header values may contain colons.
            let key: String
            let value: String
            if let colon = raw.firstIndex(of: ":") {
                key = raw[..<colon].trimmingCharacters(in: .whitespaces)
                value = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            } else {
                key = raw.trimmingCharacters(in: .whitespaces)
                value = ""
            }

            if key == "*" {
                clearAll = true
            } else if key.isEmpty {
                return
            } else if value.isEmpty {
                removeHeaders.append(key)
            } else {
                setHeaders[key] = value
            }
        }

        let trimmedUrl = urlRewrite.trimmingCharacters(in: .whitespaces)
        let trimmedMethod = methodOverride.trimmingCharacters(in: .whitespaces)
        return RequestOverride(
            url: trimmedUrl.isEmpty ? nil : trimmedUrl,
            method: trimmedMethod.isEmpty ? nil : trimmedMethod,
            clearAllHeaders: clearAll,
            setHeaders: setHeaders,
            removeHeaders: removeHeaders
        )
    }
}
