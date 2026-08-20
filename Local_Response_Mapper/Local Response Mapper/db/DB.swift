//
//  DB.swift
//  Local Response Mapper
//
//  Created by Chandan on 15/08/24.
//

import Foundation
import GRDB
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

/// Cancels its observation when the object holding it goes away, so a view
/// model only has to keep the token alive for as long as it wants updates.
protocol DBObservationToken: AnyObject {}

private final class GRDBObservationToken: DBObservationToken {

    private let cancellable: AnyDatabaseCancellable

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    deinit {
        cancellable.cancel()
    }
}

protocol DBProtocol {
    @MainActor func getRecordsList(filter: String) throws -> [URLTaskRow]
    @MainActor func getMapList() throws -> [MapLocalObject]
    @MainActor func getItemTask(taskId: String?) throws -> URLTaskObject?
    @MainActor func getItemMapLocal(id: String?) throws -> MapLocalObject?
    @MainActor func clearAllRecords()
    @MainActor func deleteRecords(taskIds: [String]) throws
    @MainActor func clearAllMapRecords()
    @MainActor func createDummyForPreview()
    @MainActor func deleteLocalMap(id: String) throws
    @MainActor func reorderMap(ids: [String])
    @MainActor func duplicateLocalMap(id: String) throws -> String?
    @MainActor func addMapRule(_ rule: MapLocalObject)
    @MainActor func updateMapRule(id: String, _ change: (MapLocalObject) -> Void)

    /// Calls `onChange` on the main queue after every committed write that
    /// touched `table`. The caller re-reads whatever it needs — the same shape
    /// as observing a query and refetching from it.
    func observe(table: String, onChange: @escaping @Sendable () -> Void) -> (any DBObservationToken)?

    func recordBegin(task: URLTaskModelBegin) throws
    func recordUpdate(task: URLTaskModelUpdate) throws
    func recordEnd(task: URLTaskModelEnd) throws
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> MapCheckResponse?
    func getLocalMap(id: String) throws -> MapLocalObject?
}

class DB: DBProtocol {

    // MARK: - Opening the file

    private var pool: DatabasePool?
    private let poolLock = NSLock()

    /// The open database, created on first use.
    ///
    /// There is no migration path: a build whose schema differs from the one on
    /// disk throws the file away and starts again. Recorded calls are a session
    /// log and rules are cheap to rewrite, so carrying old files forward is not
    /// worth a migration to maintain — see `Constants.schemaVersion`.
    var database: DatabasePool {
        get throws {
            poolLock.lock()
            defer { poolLock.unlock() }
            if let pool { return pool }
            let new = try Self.open()
            pool = new
            return new
        }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LocalResponseMapper/db.sqlite")
    }

    private static func open() throws -> DatabasePool {
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        removeLegacyRealmFiles()

        if FileManager.default.fileExists(atPath: url.path) {
            if let existing = try? DatabasePool(path: url.path),
               let version = try? existing.read({ try Int.fetchOne($0, sql: "PRAGMA user_version") }),
               version == Int(Constants.schemaVersion) {
                return existing
            }
            Logger.debugPrint("Database schema is not version \(Constants.schemaVersion), recreating file")
            try removeFile(at: url)
        }

        let pool = try DatabasePool(path: url.path)
        try pool.write { db in
            try createSchema(db)
            // Interpolated rather than bound: PRAGMA takes no parameters. The
            // value is a constant in this build, never user input.
            try db.execute(sql: "PRAGMA user_version = \(Constants.schemaVersion)")
        }
        return pool
    }

    /// Removes the database Realm used to keep, which sits in the same
    /// directory this app's own file now lives in. Nothing reads it any more,
    /// and a long recording session left it hundreds of megabytes large, so it
    /// is swept once rather than left to sit in the container forever.
    ///
    /// Only Realm's own `default.realm*` names are touched — `.management` is a
    /// directory, the rest are files.
    private static func removeLegacyRealmFiles() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Constants.legacyRealmRemovedKey) else { return }
        defaults.set(true, forKey: Constants.legacyRealmRemovedKey)

        let directory = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        for name in ["default.realm", "default.realm.lock", "default.realm.note", "default.realm.management"] {
            let file = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                Logger.debugPrint("Removed leftover \(name)")
            } catch let e {
                Logger.debugPrint("Could not remove leftover \(name): \(e)")
            }
        }
    }

    /// The write-ahead log and shared-memory files belong to the database and
    /// have to go with it — leaving them behind hands the new file the old
    /// file's uncommitted pages.
    private static func removeFile(at url: URL) throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.create(table: URLTaskObject.databaseTableName) { t in
            t.primaryKey("taskId", .text)
            t.column("liveKey", .text).notNull().defaults(to: "")
            t.column("date", .double).notNull()
            t.column("startTime", .double).notNull().defaults(to: 0)
            t.column("endTime", .double).notNull().defaults(to: 0)
            t.column("url", .text).notNull().defaults(to: "")
            t.column("body", .text).notNull().defaults(to: "")
            t.column("method", .text).notNull().defaults(to: "")
            t.column("bundleID", .text).notNull().defaults(to: "")
            t.column("mimeType", .text).notNull().defaults(to: "")
            t.column("responseString", .text).notNull().defaults(to: "")
            t.column("statusCode", .integer).notNull().defaults(to: 0)
            t.column("isEdited", .boolean).notNull().defaults(to: false)
            t.column("isRequestEdited", .boolean).notNull().defaults(to: false)
            // Stored as JSON — GRDB encodes a dictionary property that way.
            t.column("reqHeaders", .text).notNull().defaults(to: "{}")
            t.column("resHeaders", .text).notNull().defaults(to: "{}")
        }
        try db.create(index: "urlTask_date", on: URLTaskObject.databaseTableName, columns: ["date"])
        // Every record posted for a call in flight is found through this.
        try db.create(index: "urlTask_liveKey", on: URLTaskObject.databaseTableName, columns: ["liveKey"])

        try db.create(table: MapLocalObject.databaseTableName) { t in
            t.primaryKey("id", .text)
            t.column("date", .double).notNull()
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("enable", .boolean).notNull().defaults(to: false)
            t.column("kind", .text).notNull().defaults(to: MapLocalObject.RuleKind.mapResponse.rawValue)
            t.column("subUrl", .text).notNull().defaults(to: "")
            t.column("method", .text).notNull().defaults(to: "")
            t.column("statusCode", .text).notNull().defaults(to: "")
            t.column("resString", .text).notNull().defaults(to: "")
            t.column("resHeaders", .text).notNull().defaults(to: "")
            t.column("reqHeaders", .text).notNull().defaults(to: "")
            t.column("reqQuery", .text).notNull().defaults(to: "")
            t.column("reqString", .text).notNull().defaults(to: "")
            t.column("hitCount", .integer).notNull().defaults(to: 0)
        }
        try db.create(index: "mapRule_order", on: MapLocalObject.databaseTableName, columns: ["sortOrder", "date"])
    }

    // MARK: - Observation

    func observe(table: String, onChange: @escaping @Sendable () -> Void) -> (any DBObservationToken)? {
        do {
            let observation = DatabaseRegionObservation(tracking: Table(table))
            let cancellable = try observation.start(in: try database) { error in
                Logger.debugPrint("Observation error: \(error)")
            } onChange: { _ in
                // Delivered from the writer's queue the moment the transaction
                // commits; everything reading it is main-actor state.
                DispatchQueue.main.async(execute: onChange)
            }
            return GRDBObservationToken(cancellable)
        } catch let e {
            Logger.debugPrint("Error: \(e)")
            return nil
        }
    }

    // MARK: - Compiled rules

    /// A rule in the shape the request path uses it.
    ///
    /// Matching runs on every outgoing request, and it used to re-read every
    /// enabled rule from the database and re-split its header and query text
    /// each time — work that only changes when a rule is edited. This is that
    /// work, done once per edit and held until the next one.
    private struct CompiledRule {
        let id: String
        let kind: MapLocalObject.RuleKind
        let method: String
        let matchesAnyMethod: Bool
        let matchesAnyUrl: Bool
        let matchesNoUrl: Bool
        let subUrl: String
        let changesRequest: Bool
        let reqHeaders: [String: String]
        let reqQuery: [String: String]
        let reqString: String

        init(_ rule: MapLocalObject) {
            id = rule.id
            kind = rule.kind
            method = rule.method
            matchesAnyMethod = rule.matchesAnyMethod
            matchesAnyUrl = rule.matchesAnyUrl
            matchesNoUrl = rule.matchesNoUrl
            subUrl = rule.trimmedSubUrl
            changesRequest = rule.changesRequest
            reqHeaders = rule.reqHeadersMap
            reqQuery = rule.reqQueryMap
            reqString = rule.reqString
        }

        /// Same test as `MapLocalObject.matches(url:method:)`, over the values
        /// already worked out above.
        func matches(url: String, method: String) -> Bool {
            guard matchesAnyMethod || self.method == method else { return false }
            guard !matchesNoUrl else { return false }
            return matchesAnyUrl || url.contains(subUrl)
        }
    }

    /// Guards the cache only. Requests read it from the server's connection
    /// queues, and an edit arrives on whichever queue the editor is on.
    private let rulesCacheLock = NSLock()
    private var compiledRules: [CompiledRule]?

    /// Called after every write that changes what a rule matches or does —
    /// after, so a request compiling the rules while the write is still open
    /// cannot leave its pre-write copy in place behind it.
    ///
    /// Counting a hit deliberately does not invalidate: it writes to the same
    /// table on every matched request, and nothing about matching depends on
    /// the count. The rule list reads its own copy from the database, so what
    /// it shows is unaffected.
    private func invalidateRulesCache() {
        rulesCacheLock.lock()
        compiledRules = nil
        rulesCacheLock.unlock()
    }

    private func enabledRules() throws -> [CompiledRule] {
        rulesCacheLock.lock()
        if let compiledRules {
            rulesCacheLock.unlock()
            return compiledRules
        }
        rulesCacheLock.unlock()

        // Read outside the lock: a slow read must not hold every other request
        // waiting behind it, and two requests compiling the same rules at once
        // produce the same answer.
        let rules = try database.read { db in
            try Self.rulesInPriorityOrder
                .filter(Column("enable") == true)
                .fetchAll(db)
        }
        let compiled = rules.map(CompiledRule.init)

        rulesCacheLock.lock()
        compiledRules = compiled
        rulesCacheLock.unlock()
        return compiled
    }

    // MARK: - Rules

    /// New rules go last: the first match wins, so appending can never take
    /// traffic away from a rule that already exists.
    func addMapRule(_ rule: MapLocalObject) {
        write { db in
            let highest = try Int.fetchOne(
                db,
                sql: "SELECT MAX(sortOrder) FROM \(MapLocalObject.databaseTableName)"
            ) ?? -1
            rule.order = highest + 1
            try rule.insert(db)
        }
        invalidateRulesCache()
    }

    /// Reads the rule, hands it to `change`, and writes the whole row back.
    /// Rules are small and there is one editor, so a full-row write costs
    /// nothing and keeps every field going through one path.
    func updateMapRule(id: String, _ change: (MapLocalObject) -> Void) {
        write { db in
            guard let rule = try MapLocalObject.fetchOne(db, key: id) else { return }
            change(rule)
            try rule.update(db)
        }
        invalidateRulesCache()
    }

    func getItemMapLocal(id: String?) throws -> MapLocalObject? {
        guard let id else { return nil }
        return try database.read { try MapLocalObject.fetchOne($0, key: id) }
    }

    /// Rules are listed in the same order they are matched in, so the list
    /// itself reads as the priority order.
    func getMapList() throws -> [MapLocalObject] {
        try database.read { try Self.rulesInPriorityOrder.fetchAll($0) }
    }

    /// `date` breaks ties, so rules created before `sortOrder` existed keep a
    /// stable sequence instead of jumping around at every write.
    private static var rulesInPriorityOrder: QueryInterfaceRequest<MapLocalObject> {
        MapLocalObject.order(Column("sortOrder").asc, Column("date").asc)
    }

    /// Renumbers `order` to the given sequence, after a drag in the rule list.
    func reorderMap(ids: [String]) {
        defer { invalidateRulesCache() }
        write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE \(MapLocalObject.databaseTableName) SET sortOrder = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    /// Copies a rule and drops the copy directly below the original, so the two
    /// stay next to each other and the copy — being later — cannot steal the
    /// original's traffic.
    func duplicateLocalMap(id: String) throws -> String? {
        defer { invalidateRulesCache() }
        return try database.write { db in
            guard let source = try MapLocalObject.fetchOne(db, key: id) else { return nil }
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
            try db.execute(
                sql: "UPDATE \(MapLocalObject.databaseTableName) SET sortOrder = sortOrder + 1 WHERE sortOrder > ?",
                arguments: [source.order]
            )
            try copy.insert(db)
            return copy.id
        }
    }

    func deleteLocalMap(id: String) throws {
        defer { invalidateRulesCache() }
        _ = try database.write { db in
            try MapLocalObject.deleteOne(db, key: id)
        }
    }

    func clearAllMapRecords() {
        write { db in
            _ = try MapLocalObject.deleteAll(db)
        }
        invalidateRulesCache()
    }

    func getLocalMap(id: String) throws -> MapLocalObject? {
        try database.read { try MapLocalObject.fetchOne($0, key: id) }
    }

    /// Walks the rules in priority order and collects everything that applies to
    /// one outgoing request: the edits of every matching `modifyRequest` rule,
    /// and the first matching `mapResponse` rule — which ends the walk, since
    /// that request never leaves the device.
    func getLocalMapIfAvailable(req: MapCheckRequest) throws -> MapCheckResponse? {
        // The master switch is checked here rather than per rule: with it off
        // nothing matches, nothing is counted as a hit, and every request goes
        // out untouched — without having to turn each rule off and back on.
        guard Utils.mapRulesEnabled else { return nil }

        // Matched against the compiled copy, and written to only if something
        // matched: this runs on every outgoing request, and most of them match
        // no rule at all — reading the table for those, then taking the writer,
        // would put every request behind one lock.
        let rules = try enabledRules()

        var applied = [CompiledRule]()
        var headers = [String: String]()
        var query = [String: String]()
        var body: String?
        var overrideId: String?

        // One resolver for the whole request, so `{{uuid}}` written in a header
        // and in the body is the same id on the wire.
        var resolver = TemplateResolver()

        for rule in rules where rule.matches(url: req.url, method: req.method) {
            switch rule.kind {
            case .modifyRequest:
                guard rule.changesRequest else { continue }
                // Later rules win on a header or parameter both set, the same
                // way the list reads: the rule nearer the bottom is the last
                // word.
                rule.reqHeaders.forEach { headers[$0.key] = resolver.resolve($0.value) }
                rule.reqQuery.forEach { query[$0.key] = resolver.resolve($0.value) }
                if !rule.reqString.isEmpty { body = resolver.resolve(rule.reqString) }
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
        try database.write { db in
            for rule in applied {
                try db.execute(
                    sql: "UPDATE \(MapLocalObject.databaseTableName) SET hitCount = hitCount + 1 WHERE id = ?",
                    arguments: [rule.id]
                )
            }
        }
        return MapCheckResponse(overrideId: overrideId, reqHeaders: headers, reqQuery: query, reqBody: body)
    }

    // MARK: - Recorded calls

    /// Only the columns the list and the tree draw — see `URLTaskRow`. The
    /// filter still matches on `url` and `bundleID`, which a `WHERE` can do
    /// whether or not the column is in the select list.
    func getRecordsList(filter: String = "") throws -> [URLTaskRow] {
        var request = URLTaskObject
            .select(URLTaskRow.selectedColumns)
            .order(Column("date").asc)
        if let expr = FilterExpression.parse(filter) {
            let (sql, arguments) = expr.toSQL()
            request = request.filter(sql: sql, arguments: StatementArguments(arguments))
        }
        return try database.read { try request.asRequest(of: URLTaskRow.self).fetchAll($0) }
    }

    func getItemTask(taskId: String?) throws -> URLTaskObject? {
        guard let taskId else { return nil }
        return try database.read { try URLTaskObject.fetchOne($0, key: taskId) }
    }

    func clearAllRecords() {
        write { db in
            _ = try URLTaskObject.deleteAll(db)
        }
    }

    func deleteRecords(taskIds: [String]) throws {
        _ = try database.write { db in
            try URLTaskObject.deleteAll(db, keys: taskIds)
        }
    }

    /// The row a call in flight is still writing to, if it has one.
    ///
    /// Looked up by the client's key rather than by the row's own id: the two
    /// are separate so that finishing a call is an update and not a re-key —
    /// see `URLTaskObject.liveKey`.
    private static func liveTask(_ db: Database, key: String) throws -> URLTaskObject? {
        try URLTaskObject.filter(Column("liveKey") == key).fetchOne(db)
    }

    private static func newTask(key: String) -> URLTaskObject {
        let item = URLTaskObject(taskId: UUID().uuidString)
        item.liveKey = key
        return item
    }

    func recordBegin(task: URLTaskModelBegin) throws {
        try database.write { db in
            if let item = try Self.liveTask(db, key: task.taskId) {
                item.updateFrom(task: task)
                if item.url != task.url {
                    Logger.debugPrint("🔴 error: \(task.url) 🔷 \(item.url)")
                }
                try item.update(db)
            } else {
                let item = Self.newTask(key: task.taskId)
                item.updateFrom(task: task)
                try item.insert(db)
            }
        }
    }

    /// Rewrites the request side of a recorded call after a `modifyRequest`
    /// rule changed it. The row is created when missing: this and `recordBegin`
    /// race, and either can arrive first.
    func recordUpdate(task: URLTaskModelUpdate) throws {
        try database.write { db in
            if let item = try Self.liveTask(db, key: task.taskId) {
                item.updateFrom(task: task)
                try item.update(db)
            } else {
                let item = Self.newTask(key: task.taskId)
                item.updateFrom(task: task)
                try item.insert(db)
            }
        }
    }

    /// Finishes the row the call was writing to, in place.
    ///
    /// The client's key is only borrowed — it is an address, handed out again
    /// once the task that held it goes away — so it is released here rather
    /// than kept. The row itself keeps the id it was given at the start, which
    /// is what stops the list having to rebuild every finishing row.
    func recordEnd(task: URLTaskModelEnd) throws {
        try database.write { db in
            guard let item = try Self.liveTask(db, key: task.taskId) else { return }
            item.updateFrom(task: task)
            item.liveKey = ""
            try item.update(db)
        }
    }

    // MARK: - Preview data

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
        write { db in
            try item.insert(db)
        }

        // insert dummy MAP LOCAL responses
        let code = "\((200...500).randomElement()!)"
        let map1 = MapLocalObject(subUrl: "qb-mithuns/4160386/raw/13ff411a17e2cd558804d98da241d6f711c6c57a/Sample%2520Response", method: "GET", statusCode: code, resHeaders: [:], resString: #"{"status":{"code":201,"status":"NOT"}}"#)
        addMapRule(map1)
    }

    // MARK: - Writing

    /// A write whose failure is logged rather than thrown — the call sites for
    /// these are user actions with nowhere to report an error to.
    private func write(_ block: (Database) throws -> Void) {
        do {
            try database.write(block)
        } catch let e {
            Logger.debugPrint("Error: \(e)")
        }
    }
}
