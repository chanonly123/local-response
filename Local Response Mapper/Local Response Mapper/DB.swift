//
//  DB.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import Foundation
import RealmSwift
import Factory

extension Container {
    var db: Factory<DBProtocol> {
        Factory(self) {
            let db: any DBProtocol = DB()
            return db
        }
        .singleton
    }
}

class URLTaskObject: Object, Identifiable {
    var id: String { taskId }
    @Persisted var date: Double = Date().timeIntervalSince1970
    @Persisted(primaryKey: true) var taskId: String
    @Persisted var url: String = ""
    @Persisted var method: String = ""
    @Persisted var reqHeaders: Map<String, String> = .init()
    
    // after response
    @Persisted var body: String = ""
    @Persisted var resHeaders: Map<String, String> = .init()
    @Persisted var statusCode: Int = 0
    @Persisted var finished: Bool = false
    
    convenience init(taskId: String) {
        self.init()
        self.taskId = taskId
    }
    
    func updateFrom(task: URLTaskModel) {
        date = Date().timeIntervalSince1970
        url = task.url
        method = task.method
        task.reqHeaders.forEach { reqHeaders[$0.key] = $0.value }
        body = task.body ?? ""
        task.resHeaders?.forEach { resHeaders[$0.key] = $0.value }
        statusCode = task.statusCode ?? 0
        finished = task.finished
    }
    
    var requestHeaders: [String: String] { realmMapToDict(reqHeaders) }
    var responseHeaders: [String: String] { realmMapToDict(resHeaders) }
    
    private func realmMapToDict(_ map: Map<String, String>) -> [String: String] {
        var dict = [String: String]()
        map.forEach { dict[$0.key] = $0.value }
        return dict
    }
}

protocol DBProtocol {
    @MainActor
    func getList() -> Results<URLTaskObject>?
    func recordBegin(task: URLTaskModel)
    func recordEnd(task: URLTaskModel)
}

extension DBProtocol {
    
    func write(block: (Realm) -> Void) {
        guard let realm else { return }
        do {
            try realm.write {
                block(realm)
            }
        } catch let e {
            print("\(e)")
        }
    }
    
    var realm: Realm? {
        let config = Realm.Configuration(
            schemaVersion: Constants.schemaVersion)
        return try! Realm(configuration: config)
    }
    
    func clearAllRecords() {
        write { r in
            let items = r.objects(URLTaskObject.self)
            r.delete(items)
        }
    }
    
    func getItem(taskId: String?) -> URLTaskObject? {
        guard let taskId else { return nil }
        return realm?.object(ofType: URLTaskObject.self, forPrimaryKey: taskId)
    }
    
    func createDummyForPreview() {
        let item = URLTaskObject(taskId: UUID().uuidString)
        item.url = "https://gist.githubusercontent.com/qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response"
        item.method = "POST"
        item.reqHeaders["header1"] = "Some value"
        write { r in
            r.add(item)
        }
        
        let item2 = URLTaskObject(taskId: UUID().uuidString)
        item2.url = "https://gist.githubusercontent.com/qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response"
        item2.method = "POST"
        item2.reqHeaders["header1"] = "Some value"
        
        item2.resHeaders["header2"] = "Some value"
        item2.body = #"{"glossary":{"title":"example glossary","GlossDiv":{"title":"S","GlossList":{"GlossEntry":{"ID":"SGML","SortAs":"SGML","GlossTerm":"Standard Generalized Markup Language","Acronym":"SGML","Abbrev":"ISO 8879:1986","GlossDef":{"para":"A meta-markup language, used to create markup languages such as DocBook.","GlossSeeAlso":["GML","XML"]},"GlossSee":"markup"}}}}}"#
        write { r in
            r.add(item2)
        }
    }
}

class DB: DBProtocol {
    
    func recordBegin(task: URLTaskModel) {
        guard let realm else { return }
        print("🟡 recordBegin \(task.taskId)")
        let item = URLTaskObject(taskId: task.taskId)
        item.updateFrom(task: task)
        if let found = realm.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
            write { r in
                found.updateFrom(task: task)
            }
        } else {
            write { r in
                r.add(item)
            }
        }
    }
    
    func recordEnd(task: URLTaskModel) {
        print("🟡 recordEnd \(task.taskId)")
        write { r in
            if let item = r.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
                item.updateFrom(task: task)
            }
        }
    }
    
    func getList() -> Results<URLTaskObject>? {
        guard let realm else { return nil }
        return realm.objects(URLTaskObject.self).sorted(by: \.date, ascending: false)
    }

}
