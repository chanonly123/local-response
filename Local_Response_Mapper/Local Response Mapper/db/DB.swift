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

extension MapLocalObject {
    /// `date` breaks ties, so rules created before `order` existed keep a stable
    /// sequence instead of jumping around at every write.
    static let priorityOrder = [
        SortDescriptor(keyPath: "order", ascending: true),
        SortDescriptor(keyPath: "date", ascending: true)
    ]
}

extension Realm {
    /// New rules go last: the first match wins, so appending can never take
    /// traffic away from a rule that already exists.
    func addMapRule(_ rule: MapLocalObject) {
        rule.order = (objects(MapLocalObject.self).max(ofProperty: "order") as Int? ?? -1) + 1
        add(rule)
    }
}

protocol DBProtocol {
    @MainActor func getRecordsList(filter: String) throws -> Results<URLTaskObject>
    @MainActor func getMapList() throws -> Results<MapLocalObject>
    @MainActor func getItemTask(taskId: String?) throws -> URLTaskObject?
    @MainActor func getItemMapLocal(id: String?) throws -> MapLocalObject?
    @MainActor func clearAllRecords()
    @MainActor func deleteRecords(taskIds: [String]) throws
    @MainActor func clearAllMapRecords()
    @MainActor func createDummyForPreview()
    @MainActor func write(block: (Realm) throws -> Void)
    @MainActor func deleteLocalMap(id: String) throws
    @MainActor func reorderMap(ids: [String])
    @MainActor func duplicateLocalMap(id: String) throws -> String?

    func recordBegin(task: URLTaskModelBegin) throws
    func recordUpdate(task: URLTaskModelUpdate) throws
    func recordEnd(task: URLTaskModelEnd) throws
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> MapCheckResponse?
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
                schemaVersion: Constants.schemaVersion,
                deleteRealmIfMigrationNeeded: true)
            return try Realm(configuration: config)
        }
    }

    func clearAllRecords() {
        write { r in
            let items = r.objects(URLTaskObject.self)
            r.delete(items)
        }
    }

    func deleteRecords(taskIds: [String]) throws {
        let r = try realm
        let items = r.objects(URLTaskObject.self).filter("taskId IN %@", taskIds)
        try r.write {
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
        if let expr = FilterExpression.parse(filter) {
            items = items.filter(expr.toPredicate())
        }
        return items
    }

    /// Rules are listed in the same order they are matched in, so the list
    /// itself reads as the priority order.
    func getMapList() throws -> Results<MapLocalObject> {
        return try realm.objects(MapLocalObject.self).sorted(by: MapLocalObject.priorityOrder)
    }

    /// Renumbers `order` to the given sequence, after a drag in the rule list.
    func reorderMap(ids: [String]) {
        write { r in
            for (index, id) in ids.enumerated() {
                r.object(ofType: MapLocalObject.self, forPrimaryKey: id)?.order = index
            }
        }
    }

    /// Copies a rule and drops the copy directly below the original, so the two
    /// stay next to each other and the copy — being later — cannot steal the
    /// original's traffic.
    func duplicateLocalMap(id: String) throws -> String? {
        let r = try realm
        guard let source = r.object(ofType: MapLocalObject.self, forPrimaryKey: id) else {
            return nil
        }
        let copy = MapLocalObject()
        copy.enable = source.enable
        copy.subUrl = source.subUrl
        copy.method = source.method
        copy.resString = source.resString
        copy.statusCode = source.statusCode
        copy.resHeaders = source.resHeaders
        copy.kind = source.kind
        copy.reqHeaders = source.reqHeaders
        copy.reqQuery = source.reqQuery
        copy.reqString = source.reqString
        copy.order = source.order + 1
        // Materialized first: the query is live, and shifting `order` inside the
        // loop would re-evaluate it mid-iteration.
        let below = Array(r.objects(MapLocalObject.self).where { $0.order > source.order })
        try r.write {
            below.forEach { $0.order += 1 }
            r.add(copy)
        }
        return copy.id
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
            r.addMapRule(map1)
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

    /// Rewrites the request side of a recorded call after a `modifyRequest`
    /// rule changed it. The row is created when missing: this and `recordBegin`
    /// race, and either can arrive first.
    func recordUpdate(task: URLTaskModelUpdate) throws {
        let r = try realm
        try r.write {
            if let item = r.object(ofType: URLTaskObject.self, forPrimaryKey: task.taskId) {
                item.updateFrom(task: task)
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

    /// Walks the rules in priority order and collects everything that applies to
    /// one outgoing request: the edits of every matching `modifyRequest` rule,
    /// and the first matching `mapResponse` rule — which ends the walk, since
    /// that request never leaves the device.
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> MapCheckResponse? {
        let r = try realm
        let rules = r.objects(MapLocalObject.self)
            .where { $0.enable }
            .sorted(by: MapLocalObject.priorityOrder)

        var applied = [MapLocalObject]()
        var headers = [String: String]()
        var query = [String: String]()
        var body: String?
        var overrideId: String?

        for rule in rules where rule.matches(url: req.url, method: req.method) {
            switch rule.kind {
            case .modifyRequest:
                guard rule.changesRequest else { continue }
                // Later rules win on a header or parameter both set, the same
                // way the list reads: the rule nearer the bottom is the last
                // word.
                rule.reqHeadersMap.forEach { headers[$0.key] = $0.value }
                rule.reqQueryMap.forEach { query[$0.key] = $0.value }
                if !rule.reqString.isEmpty { body = rule.reqString }
                applied.append(rule)
            case .mapResponse:
                overrideId = rule.id
                applied.append(rule)
            }
            if overrideId != nil { break }
        }

        guard !applied.isEmpty else { return nil }
        // Counted here rather than in `getLocalMap`, so a rule that matched is
        // credited even if serving the response later fails.
        try r.write {
            applied.forEach { $0.hitCount += 1 }
        }
        return MapCheckResponse(overrideId: overrideId, reqHeaders: headers, reqQuery: query, reqBody: body)
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
