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
            self.list = Array(results.freeze())
            self.selected = self.list?.first?.id
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
            // A selection pointing at a deleted row makes the table query a row that no
            // longer exists, so drop it.
            if let selected, !snapshot.contains(where: { $0.id == selected }) {
                self.selected = nil
            }
        } catch let e {
            appendError(e)
        }
    }

    func getSelectedItem() -> MapLocalObject? {
        do {
            return try db.getItemMapLocal(id: selected)
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

    func formatJsonBody() {
        db.write { _ in
            let str = try? Utils.prettyPrintJSON(from: getSelectedItem()?.resString ?? "")
            getSelectedItem()?.resString = str ?? getSelectedItem()?.resString ?? ""
        }
    }

    func addNew() {
        db.write { r in
            let new = MapLocalObject(subUrl: "", method: httpMethods.first ?? "", statusCode: "0", resHeaders: Map<String, String>(), resString: "")
            r.add(new)
            selectedAnimated = new.id
        }
    }

    func deleteSelected() {
        guard let id = selected else { return }
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
        return Int(item.statusCode) != nil
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
