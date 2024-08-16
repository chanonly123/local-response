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
    
    @Published var error: Error?
    @Published var list: Results<URLTaskObject>?
    @Published var selected: String?
    var notificationToken: NotificationToken?
    @Injected(\.db) var db
    
    init() {
        let list = db.getList()
        self.list = list
        self.selected = list?.first?.taskId
        notificationToken = list?.observe { [weak self] _ in
            self?.list = self?.db.getList()
        }
    }
    
    func fetch() {
        list = db.getList()
    }
    
    func clearAll() {
        db.clearAllRecords()
        fetch()
    }
    
    func fetch(taskId: String?) -> URLTaskObject? {
        return db.getItem(taskId: taskId)
    }
    
    func dictToString(item: Map<String, String>) -> String {
        item.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
}

