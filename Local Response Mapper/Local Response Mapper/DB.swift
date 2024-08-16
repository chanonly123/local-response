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

protocol DBProtocol {
    @MainActor
    func getRecordsList() throws -> Results<URLTaskObject>?
    func getItem(taskId: String?) throws -> URLTaskObject?
    func recordBegin(task: URLTaskModel) throws
    func recordEnd(task: URLTaskModel) throws
    func clearAllRecords()
    func createDummyForPreview()
}

class DB: DBProtocol {
    
    func write(block: (Realm) throws -> Void) {
        do {
            try realm.write {
                try block(try realm)
            }
        } catch let e {
            print("\(e)")
        }
    }
    
    var realm: Realm {
        get throws {
            let config = Realm.Configuration(
                schemaVersion: Constants.schemaVersion)
            return try Realm(configuration: config)
        }
    }
    
    func clearAllRecords() {
        write { r in
            let items = r.objects(URLTaskObject.self)
            r.delete(items)
        }
    }
    
    func getItem(taskId: String?) throws -> URLTaskObject? {
        guard let taskId else { return nil }
        return try realm.object(ofType: URLTaskObject.self, forPrimaryKey: taskId)
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
        
        let map1 = MapLocalObject(subUrl: "qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response", method: "GET", body: #"{"status":{"code":201,"status":"NOT"}}"#)
        write { r in
            r.add(map1)
        }
        
        let map2 = MapLocalObject(subUrl: "qb-mithuns/4160386/raw", method: "GET", body: #"{"status":{"code":201,"status":"NOT"}}"#)
        write { r in
            r.add(map2)
        }
    }
    
    func recordBegin(task: URLTaskModel) throws {
        let item = URLTaskObject(taskId: task.taskId)
        item.updateFrom(task: task)
        if let found = try realm.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
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
        write { r in
            if let item = r.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
                item.updateFrom(task: task)
            }
        }
    }
    
    func getRecordsList() throws -> Results<URLTaskObject>? {
        return try realm.objects(URLTaskObject.self).sorted(by: \.date, ascending: true)
    }

    func getMapList() throws -> Results<MapLocalObject>? {
        return try realm.objects(MapLocalObject.self).sorted(by: \.date, ascending: true)
    }
}
