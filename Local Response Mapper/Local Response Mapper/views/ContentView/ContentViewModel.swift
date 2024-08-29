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

    enum TabType: String, CaseIterable {
        case req = "Request", res = "Response", resString = "Response String"
    }

    @Published var errors: [Error] = []
    @Published var list: Results<URLTaskObject>?
    @Published var filter: String = "" {
        didSet {
            fetch()
        }
    }
    @Published var selected: String?
    @Published var selectedTab: TabType = .req

    @Published var newVersion: String?
    @Published var newVersionAlert: Bool = false

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

    func getTabButtonTextColor(tab: TabType) -> Color {
        tab == selectedTab ? Color.blue : Color.gray.opacity(0.5)
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

    func getUpdateLink() -> some View {
        Link("Update", destination: URL(string: "https://github.com/chanonly123/local-response/releases")!)
    }

    func checkForNewVersion() {
        struct Root: Codable {
            let tag_name: String?
        }

        Task {
            guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                return
            }

            guard let url = URL(string: "https://api.github.com/repos/chanonly123/local-response/releases/latest") else {
                return
            }

            let result = try await URLSession.shared.data(from: url)
            let root = try JSONDecoder().decode(Root.self, from: result.0)

            guard let new = root.tag_name else {
                return
            }

            if new > current {
                newVersion = new
                newVersionAlert = true
            }
        }
    }
    
}
