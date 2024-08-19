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
    @Persisted var body: String = ""
    @Persisted var resHeaders: Map<String, String> = .init()
    
    convenience init(subUrl: String, method: String, body: String) {
        self.init()
        self.method = method
        self.subUrl = subUrl
        self.body = body
    }
}
