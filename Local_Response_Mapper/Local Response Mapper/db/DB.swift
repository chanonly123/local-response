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
    @MainActor func getRecordsList(filter: String) throws -> Results<URLTaskObject>
    @MainActor func getMapList() throws -> Results<MapLocalObject>
    @MainActor func getItemTask(taskId: String?) throws -> URLTaskObject?
    @MainActor func getItemMapLocal(id: String?) throws -> MapLocalObject?
    @MainActor func clearAllRecords()
    @MainActor func clearAllMapRecords()
    @MainActor func createDummyForPreview()
    @MainActor func write(block: (Realm) throws -> Void)
    @MainActor func deleteLocalMap(id: String) throws

    func recordBegin(task: URLTaskModelBegin) throws
    func recordEnd(task: URLTaskModelEnd) throws
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> String?
    func getLocalMap(id: String) throws -> MapLocalObject?
}

class DB: DBProtocol {

    func write(block: (Realm) throws -> Void) {
        do {
            try realm.write {
                try block(try realm)
            }
        } catch let e {
            Logger.debugPrint("Error: \(e)")
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

    func clearAllMapRecords() {
        write { r in
            let items = r.objects(MapLocalObject.self)
            r.delete(items)
        }
    }

    func getItemTask(taskId: String?) throws -> URLTaskObject? {
        guard let taskId else { return nil }
        return try realm.object(ofType: URLTaskObject.self, forPrimaryKey: taskId)
    }

    func getItemMapLocal(id: String?) throws -> MapLocalObject? {
        guard let id else { return nil }
        return try realm.object(ofType: MapLocalObject.self, forPrimaryKey: id)
    }

    func getRecordsList(filter: String = "") throws -> Results<URLTaskObject> {
        var items = try realm.objects(URLTaskObject.self).sorted(by: \.date, ascending: true)
        if !filter.isEmpty {
            items = items.where {
                $0.url.contains(filter, options: .caseInsensitive) || $0.bundleID.contains(filter, options: .caseInsensitive)
            }
        }
        return items
    }

    func getMapList() throws -> Results<MapLocalObject> {
        return try realm.objects(MapLocalObject.self).sorted(by: \.date, ascending: true)
    }

    func createDummyForPreview() {

        let item = URLTaskObject(taskId: UUID().uuidString)
        item.bundleID = "com.some.bundle"
        item.url = "https://gist.githubusercontent.com/qb-mithuns/4160386/raw?json=true"
        item.method = "POST"
        item.reqHeaders["req_header"] = "Some value"
        item.statusCode = (200...500).randomElement()!
        item.responseString = #"{"id":0,"name":"Mitzi Fields"}"#
        item.resHeaders["Content-Type"] = "application/json"
        item.body = #"{"glossary":{"title":"example glossary","GlossDiv":{"title":"S","GlossList":{"GlossEntry":{"ID":"SGML","SortAs":"SGML","GlossTerm":"Standard Generalized Markup Language","Acronym":"SGML","Abbrev":"ISO 8879:1986","GlossDef":{"para":"A meta-markup language, used to create markup languages such as DocBook.","GlossSeeAlso":["GML","XML"]},"GlossSee":"markup"}}}}}"#
        write { r in
            r.add(item)
        }

        // insert dummy MAP LOCAL responses
        let code = "\((200...500).randomElement()!)"
        let map1 = MapLocalObject(subUrl: "qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response", method: "GET", statusCode: code, resHeaders: Map<String, String>(), resString: #"{"status":{"code":201,"status":"NOT"}}"#)
        write { r in
            r.add(map1)
        }

    }

    func recordBegin(task: URLTaskModelBegin) throws {
        let r = try realm
        try r.write {
            if let item = r.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
                item.updateFrom(task: task)
                if item.url != task.url {
                    Logger.debugPrint("🔴 error: \(task.url) 🔷 \(item.url)")
                }
            } else {
                let item = URLTaskObject(taskId: task.taskId)
                item.updateFrom(task: task)
                r.add(item)
            }
        }
    }

    func recordEnd(task: URLTaskModelEnd) throws {
        let r = try realm
        try r.write {
            if let item = r.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
                let new = item.createCopy()
                new.updateFrom(task: task)
                r.add(new)
                r.delete(item)
            }
        }
    }

    /// checs if a map response found, returns id
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> String? {
        let r = try realm
        let items: [MapLocalObject] = r.objects(MapLocalObject.self)
            .where { $0.enable }
            .sorted(by: \.date, ascending: true)
            .filter({ ($0.method.contains("*") || $0.method == req.method) && req.url.contains($0.subUrl) })
            .map { $0 }
        return items.first?.id
    }

    /// returns id
    func getLocalMap(id: String) throws -> MapLocalObject? {
        let r = try realm
        let item = r.object(ofType: MapLocalObject.self, forPrimaryKey: id)
        return item
    }

    func deleteLocalMap(id: String) throws {
        let r = try realm
        try r.write {
            if let item = r.object(ofType: MapLocalObject.self, forPrimaryKey: id) {
                r.delete(item)
            }
        }
    }
}
