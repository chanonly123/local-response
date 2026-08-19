//
//  LocalMapViewModel.swift
//  Local Response Mapper
//
//  Created by Chandan on 19/08/24.
//

import Foundation
import Factory
import SwiftUI

@MainActor
class LocalMapViewModel: ObservableObject, ObservableObjectErrors {

    @Published var errors: [any Error] = []
    /// A snapshot read at the last change, not a live query — the table renders
    /// rows that cannot change or disappear underneath it mid-draw.
    @Published var list: [MapLocalObject]?
    @Published var selected: String?
    @Published var search: String = ""
    /// Rule id -> id of the earlier enabled rule that already catches everything
    /// it would. Recomputed with the list so rows can render the warning without
    /// each one rescanning its predecessors.
    @Published private(set) var shadowedBy: [String: String] = [:]
    let httpMethods = [
        "GET",
        "POST",
        "PUT",
        "DELETE",
        "HEAD",
        "OPTIONS",
        "PATCH",
        "CONNECT",
        "TRACE",
        "* (any)"
    ]

    var notificationToken: (any DBObservationToken)?
    @Injected(\.db) var db

    var selectedAnimated: String? {
        set {
            withAnimation {
                selected = newValue
            }
        }
        get {
            selected
        }
    }

    init() {
        do {
            let snapshot = try db.getMapList()
            self.list = snapshot
            self.shadowedBy = Self.computeShadowing(snapshot)
            self.selected = snapshot.first?.id
            notificationToken = db.observe(table: MapLocalObject.databaseTableName) { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshList()
                }
            }
        } catch let e {
            appendError(e)
        }
    }

    private func refreshList() {
        do {
            let snapshot = try db.getMapList()
            list = snapshot
            shadowedBy = Self.computeShadowing(snapshot)
            // A selection pointing at a deleted row makes the table query a row that no
            // longer exists, so drop it.
            if let selected, !snapshot.contains(where: { $0.id == selected }) {
                self.selected = nil
            }
        } catch let e {
            appendError(e)
        }
    }

    /// Only enabled rules take part: a disabled rule neither shadows nor is
    /// shadowed, since matching skips it entirely. `modifyRequest` rules are
    /// left out — every one of them that matches is applied, so none of them
    /// can starve another.
    private static func computeShadowing(_ items: [MapLocalObject]) -> [String: String] {
        let enabled = items.filter { $0.enable && $0.kind == .mapResponse }
        var out = [String: String]()
        for (index, rule) in enabled.enumerated() {
            if let covering = enabled[..<index].first(where: { $0.covers(rule) }) {
                out[rule.id] = covering.id
            }
        }
        return out
    }

    // MARK: - Rule list

    var visibleRules: [MapLocalObject] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return list ?? [] }
        return (list ?? []).filter {
            $0.subUrl.lowercased().contains(query)
            || $0.method.lowercased().contains(query)
            || $0.statusCode.contains(query)
            || $0.kind.title.lowercased().contains(query)
        }
    }

    /// 1-based position in the full list — what the row shows and what
    /// "shadowed by rule 2" refers to.
    func priority(of id: String) -> Int {
        (list?.firstIndex { $0.id == id } ?? 0) + 1
    }

    func shadowingPriority(of id: String) -> Int? {
        shadowedBy[id].map { priority(of: $0) }
    }

    var ruleCountLabel: String {
        let total = list?.count ?? 0
        guard total > 0 else { return "" }
        return "\(getEnabledCount) of \(total) active"
    }

    /// Reorders the visible rows while leaving rules hidden by the search filter
    /// exactly where they are.
    func move(from source: IndexSet, to destination: Int) {
        guard let list else { return }
        var visible = visibleRules
        visible.move(fromOffsets: source, toOffset: destination)

        let movedIds = Set(visible.map(\.id))
        var reordered = visible.makeIterator()
        let merged = list.map { rule in
            movedIds.contains(rule.id) ? (reordered.next() ?? rule) : rule
        }
        self.list = merged
        db.reorderMap(ids: merged.map(\.id))
    }

    func duplicateSelected() {
        guard let id = selected else { return }
        do {
            if let new = try db.duplicateLocalMap(id: id) {
                selectedAnimated = new
            }
        } catch let e {
            appendError(e)
        }
    }

    /// The row the editor is on, read fresh so a field always shows what is
    /// stored rather than what the last snapshot held. A rule deleted while
    /// selected simply reads back as no selection.
    func getSelectedItem() -> MapLocalObject? {
        do {
            return try db.getItemMapLocal(id: selected)
        } catch let e {
            appendError(e)
            return nil
        }
    }

    /// One field of one rule as a `Binding`. The setter writes the whole row
    /// back, so every field in the editor persists through the same path.
    func getSetValue<T: InitProvider>(_ id: String, keyPath: ReferenceWritableKeyPath<MapLocalObject, T>) -> Binding<T> {
        return Binding(get: { [weak self] in
            guard let item = try? self?.db.getItemMapLocal(id: id) ?? nil else { return T() }
            return item[keyPath: keyPath]
        }, set: { [weak self] new in
            self?.db.updateMapRule(id: id) { $0[keyPath: keyPath] = new }
        })
    }

    // MARK: - Response header notes

    /// Something the rule's headers will do that isn't visible from the header
    /// text itself.
    struct HeaderNote: Identifiable {

        enum Kind { case warning, info }

        let kind: Kind
        /// the header this note is about — also its identity, one note per header
        let name: String
        let value: String
        let detail: String

        var id: String { name }
        var line: String { "\(name): \(value)" }
    }

    /// Notes on the headers a `modifyRequest` rule sets — the ones URLSession
    /// takes over itself, so setting them here changes nothing.
    func requestHeaderNotes(_ item: MapLocalObject) -> [HeaderNote] {
        let map = item.reqHeadersMap
        var notes = [HeaderNote]()
        for name in Constants.sessionManagedRequestHeaders {
            guard let entry = map.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) else {
                continue
            }
            notes.append(
                HeaderNote(
                    kind: .info,
                    name: entry.key,
                    value: entry.value,
                    detail: "Ignored — URLSession sets \(name) on the request itself."
                )
            )
        }
        return notes
    }

    /// Read straight off the rule so the editor can explain what the server will
    /// actually send, rather than leaving it to a tooltip on a warning glyph.
    func headerNotes(_ item: MapLocalObject) -> [HeaderNote] {
        var notes = [HeaderNote]()

        if let encoding = item.header(Constants.contentEncodingKey), !encoding.isEmpty {
            notes.append(
                HeaderNote(
                    kind: .warning,
                    name: Constants.contentEncodingKey,
                    value: encoding,
                    detail: "The body below is sent as plain text, so the app will try to \(encoding)-decode something that was never encoded, and the response will fail to parse."
                )
            )
        }

        for name in Constants.serverManagedHeaders {
            guard let value = item.header(name) else { continue }
            notes.append(
                HeaderNote(
                    kind: .info,
                    name: name,
                    value: value,
                    detail: "Ignored — the server computes \(name) from the body when it serves the response."
                )
            )
        }

        return notes
    }

    /// Drops every line naming `name`, matching case-insensitively the same way
    /// `MapLocalObject.header(_:)` finds it.
    func removeHeader(
        named name: String,
        from id: String,
        keyPath: ReferenceWritableKeyPath<MapLocalObject, String> = \.resHeaders
    ) {
        db.updateMapRule(id: id) { rule in
            rule[keyPath: keyPath] = rule[keyPath: keyPath]
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    guard let colon = line.firstIndex(of: ":") else { return true }
                    return line[..<colon].trimmingCharacters(in: .whitespaces)
                        .caseInsensitiveCompare(name) != .orderedSame
                }
                .joined(separator: "\n")
        }
    }

    func formatJsonBody(keyPath: ReferenceWritableKeyPath<MapLocalObject, String> = \.resString) {
        guard let id = selected else { return }
        db.updateMapRule(id: id) { rule in
            if let str = try? Utils.prettyPrintJSON(from: rule[keyPath: keyPath]) {
                rule[keyPath: keyPath] = str
            }
        }
    }

    func addNew() {
        let new = MapLocalObject(subUrl: "", method: httpMethods.first ?? "", statusCode: "200", resHeaders: [:], resString: "")
        db.addMapRule(new)
        selectedAnimated = new.id
    }

    func deleteSelected() {
        guard let id = selected else { return }
        // The delete is always asked for from inside an AppKit event — a row's
        // context menu, or a button that this very delete is about to disable.
        // Letting that event finish first means no view is torn down while
        // AppKit is still working through it.
        Task { @MainActor [weak self] in
            self?.delete(id: id)
        }
    }

    private func delete(id: String) {
        let index = list?.firstIndex(where: { $0.id == id })
        // Drop the selection and the row before the write, so nothing is
        // pointing at the deleted rule while the delete commits.
        selected = nil
        list?.removeAll { $0.id == id }
        do {
            try db.deleteLocalMap(id: id)
        } catch let e {
            appendError(e)
            return
        }
        selectNearby(index: index)
    }

    func selectNearby(index: Int?) {
        if let index, let list, !list.isEmpty {
            if index < list.count {
                selectedAnimated = list[index].id
            } else if index-1 < list.count {
                selectedAnimated = list[index-1].id
            } else {
                selected = nil
            }
        } else {
            selected = nil
        }
    }

    func isValidStatus(_ item: MapLocalObject) -> Bool {
        return item.isValidStatus
    }

    func isValidResponseJSON(_ item: MapLocalObject) -> Bool {
        isValidJSON(item.resString)
    }

    func isValidRequestJSON(_ item: MapLocalObject) -> Bool {
        isValidJSON(item.reqString)
    }

    private func isValidJSON(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    var getEnabledCount: Int {
        list?.filter({ $0.enable }).count ?? 0
    }

    func clearAll() {
        // Empty the table before the delete commits, so no row is left asking
        // for a rule that is on its way out.
        selected = nil
        list = []
        db.clearAllMapRecords()
    }
}

protocol InitProvider {
    init()
}

extension String: InitProvider {}
extension Bool: InitProvider {}
extension MapLocalObject.RuleKind: InitProvider {
    init() { self = .mapResponse }
}
