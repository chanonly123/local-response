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
class LocalMapViewModel: ObservableObject {
    
    @Published var error: [Error] = []
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
    
    init() {
        do {
            let list = try db.getMapList()
            self.list = list
            self.selected = list.first?.id
            notificationToken = list.observe { [weak self] _ in
                do {
                    self?.list = try self?.db.getMapList()
                } catch let e {
                    self?.error.append(e)
                }
            }
        } catch let e {
            error.append(e)
        }
    }
    
    func getSelectedItem() -> MapLocalObject? {
        do {
            return try db.getItemMapLocal(id: selected)
        } catch let e {
            error.append(e)
            return nil
        }
    }
    
    func getSetValue<T>(_ item: MapLocalObject, keyPath: WritableKeyPath<MapLocalObject, T>) -> Binding<T> {
        var item = item
        return Binding(get: {
            item[keyPath: keyPath]
        }, set: { [weak self] new in
            self?.db.write { r in
                item[keyPath: keyPath] = new
            }
        })
    }
    
    func formatJsonBody() {
        db.write { _ in
            do {
                getSelectedItem()?.resString = try Utils.prettyPrintJSON(from: getSelectedItem()?.resString ?? "")
            } catch let err {
                self.error.append(err)
            }
        }
    }
    
    func addNew() {
        db.write { r in
            let new = MapLocalObject(subUrl: "", method: httpMethods.first ?? "", statusCode: 0, resString: "")
            r.add(new)
        }
    }
    
    func deleteSelected() {
        db.write { r in
            if let item = getSelectedItem() {
                r.delete(item)
            }
        }
    }
}
