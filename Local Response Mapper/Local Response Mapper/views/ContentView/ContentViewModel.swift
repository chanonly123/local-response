//
//  ContentViewModel.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import RealmSwift
import Factory

@MainActor
class ContentViewModel: ObservableObject, ObservableObjectErrors {

    enum TabType: String { case req, res  }

    @Published var errors: [Error] = []
    @Published var list: Results<URLTaskObject>?
    @Published var filter: String = "" {
        didSet {
            fetch()
        }
    }
    @Published var selected: String?
    @Published var selectedTab: TabType = .req

    var notificationToken: NotificationToken?
    @Injected(\.db) var db

    init() {
        do {
            let list = try db.getRecordsList(filter: filter)
            self.list = list
            self.selected = list.first?.taskId
            notificationToken = list.observe { [weak self] _ in
                do {
                    self?.list = try self?.db.getRecordsList(filter: self?.filter ?? "")
                } catch let e {
                    self?.appendError(e)
                }
            }
        } catch let e {
            appendError(e)
        }
    }

    func fetch() {
        do {
            list = try db.getRecordsList(filter: filter)
        } catch let e {
            appendError(e)
        }
    }

    func clearAll() {
        db.clearAllRecords()
        fetch()
    }

    func fetch(taskId: String?) -> URLTaskObject? {
        do {
            return try db.getItemTask(taskId: taskId)
        } catch let e {
            appendError(e)
            return nil
        }
    }

    func dictToString(item: Map<String, String>) -> String {
        item.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    func getTabButtonBackground(tab: TabType) -> Color {
        tab == selectedTab ? Color.gray.opacity(0.5) : Color.white
    }

    func addNewMapLocal(obj: URLTaskObject) {
        db.write { r in
            let new = MapLocalObject(subUrl: obj.url, method: obj.method, statusCode: String(obj.statusCode), resHeaders: obj.resHeaders, resString: obj.responseString)
            r.add(new)
        }
    }

    func copyValue(obj: URLTaskObject, keyPath: KeyPath<URLTaskObject, String>) {
        Utils.copyToClipboard(obj[keyPath: keyPath])
    }
}
