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
}
