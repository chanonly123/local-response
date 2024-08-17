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
class ContentViewModel: ObservableObject {
    
    enum TabType: String { case req, res  }
    
    @Published var error: [Error] = []
    @Published var list: Results<URLTaskObject>?
    @Published var selected: String?
    @Published var selectedTab: TabType = .req
    
    var notificationToken: NotificationToken?
    @Injected(\.db) var db
    
    init() {
        do {
            let list = try db.getRecordsList()
            self.list = list
            self.selected = list?.first?.taskId
            notificationToken = list?.observe { [weak self] _ in
                do {
                    self?.list = try self?.db.getRecordsList()
                } catch let e {
                    self?.error.append(e)
                }
            }
        } catch let e {
            error.append(e)
        }
    }
    
    func fetch() {
        do {
            list = try db.getRecordsList()
        } catch let e {
            error.append(e)
        }
    }
    
    func clearAll() {
        db.clearAllRecords()
        fetch()
    }
    
    func fetch(taskId: String?) -> URLTaskObject? {
        do {
            return try db.getItem(taskId: taskId)
        } catch let e {
            error.append(e)
            return nil
        }
    }
    
    func dictToString(item: Map<String, String>) -> String {
        item.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
    
    func getTabButtonBackground(tab: TabType) -> Color {
        tab == selectedTab ? Color.gray.opacity(0.5) : Color.white
    }
}

