//
//  MapLocalObject.swift
//  Local Response Mapper
//
//  Created by Chandan on 16/08/24.
//

import Foundation
import RealmSwift

class MapLocalObject: Object, Identifiable {
    @Persisted var id: String = UUID().uuidString
    @Persisted var date: Double = Date().timeIntervalSince1970
    
    @Persisted var subUrl: String = ""
    @Persisted var method: String = ""
    @Persisted var body: String = ""
    
    convenience init(subUrl: String, method: String, body: String) {
        self.init()
        self.method = method
        self.subUrl = subUrl
        self.body = body
    }
}
