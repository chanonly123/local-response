//
//  LocalMapViewModel.swift
//  Local Response Mapper
//
//  Created by Chandan on 19/08/24.
//

import Foundation
import RealmSwift
import Factory
import SwiftUI

@MainActor
class LocalMapViewModel: ObservableObject, ObservableObjectErrors {

    @Published var errors: [any Error] = []
    /// Frozen snapshot, not the live `Results`. A live `Results` shrinks the moment a write
    /// commits, while the `@Published` notification only arrives afterwards — during that gap
    /// SwiftUI's table can still ask a deleted row for its values and Realm throws. Frozen
    /// objects never invalidate, so the table always renders a consistent state.
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

    var notificationToken: NotificationToken?
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
            let results = try db.getMapList()
            let snapshot = Array(results.freeze())
            self.list = snapshot
            self.shadowedBy = Self.computeShadowing(snapshot)
            self.selected = snapshot.first?.id
            notificationToken = results.observe { [weak self] _ in
                self?.refreshList()
            }
        } catch let e {
            appendError(e)
        }
    }

    private func refreshList() {
        do {
            let snapshot = Array(try db.getMapList().freeze())
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
    /// shadowed, since matching skips it entirely.
    private static func computeShadowing(_ items: [MapLocalObject]) -> [String: String] {
        let enabled = items.filter(\.enable)
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

    func getSelectedItem() -> MapLocalObject? {
        do {
            // Live object, not a frozen one: reading any property of it after
            // Realm deleted it throws from Objective-C and takes the app down,
            // so an invalidated object is treated as no selection.
            let item = try db.getItemMapLocal(id: selected)
            return item?.isInvalidated == true ? nil : item
        } catch let e {
            appendError(e)
            return nil
        }
    }

    func getSetValue<T: InitProvider>(_ id: String, keyPath: WritableKeyPath<MapLocalObject, T>) -> Binding<T> {
        return Binding(get: { [weak self] in
            if let itemVar = try? self?.db.getItemMapLocal(id: id) {
                return itemVar.isInvalidated ? T() : itemVar[keyPath: keyPath]
            } else {
                return T()
            }
        }, set: { [weak self] new in
            if var itemVar = try? self?.db.getItemMapLocal(id: id) {
                self?.db.write { r in
                    itemVar[keyPath: keyPath] = new
                }
            }
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
    func removeHeader(named name: String, from id: String) {
        guard let item = try? db.getItemMapLocal(id: id) else { return }
        let kept = item.resHeaders
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                guard let colon = line.firstIndex(of: ":") else { return true }
                return line[..<colon].trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(name) != .orderedSame
            }
        db.write { _ in
            item.resHeaders = kept.joined(separator: "\n")
        }
    }

    func formatJsonBody() {
        db.write { _ in
            let str = try? Utils.prettyPrintJSON(from: getSelectedItem()?.resString ?? "")
            getSelectedItem()?.resString = str ?? getSelectedItem()?.resString ?? ""
        }
    }

    func addNew() {
        db.write { r in
            let new = MapLocalObject(subUrl: "", method: httpMethods.first ?? "", statusCode: "200", resHeaders: Map<String, String>(), resString: "")
            r.addMapRule(new)
            selectedAnimated = new.id
        }
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
        // Drop the selection and the row before the write, so nothing is pointing at the
        // deleted object while Realm commits.
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
        let result = try? JSONSerialization.jsonObject(with: item.resString.data(using: .utf8) ?? Data())
        return result != nil
    }

    var getEnabledCount: Int {
        list?.filter({ $0.enable }).count ?? 0
    }

    func clearAll() {
        // Empty the table before the delete commits, otherwise SwiftUI can render rows
        // backed by objects Realm has already invalidated.
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
