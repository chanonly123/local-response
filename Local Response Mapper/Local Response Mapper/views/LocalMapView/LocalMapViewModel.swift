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
    @Published var list: Results<MapLocalObject>?
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
            let list = try db.getMapList()
            self.list = list
            self.selected = list.first?.id
            notificationToken = list.observe { [weak self] _ in
                do {
                    self?.list = try self?.db.getMapList()
                } catch let e {
                    self?.appendError(e)
                }
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
            do {
                getSelectedItem()?.resString = try Utils.prettyPrintJSON(from: getSelectedItem()?.resString ?? "")
            } catch let err {
                self.appendError(err)
            }
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
        db.write { r in
            if let item = getSelectedItem() {
                let index = list?.firstIndex(of: item)
                r.delete(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.selectNearby(index: index)
                }
            }
        }
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
}

protocol InitProvider {
    init()
}

extension String: InitProvider {}
extension Bool: InitProvider {}
