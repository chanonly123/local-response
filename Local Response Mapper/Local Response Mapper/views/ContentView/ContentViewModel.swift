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
        case req = "Components", resString = "Response"
    }

    @Published var errors: [Error] = []
    @Published var list: Results<URLTaskObject>?
    var listCount: Int = 0
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
            self.listCount = list.count
            self.list = list
            self.selected = list.first?.taskId
            notificationToken = list.observe { [weak self] _ in
                do {
                    let newList = try self?.db.getRecordsList(filter: self?.filter ?? "")
                    self?.listCount = newList?.count ?? 0
                    self?.list = newList
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

    func generateDummyData() {
        db.createDummyForPreview()
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

    func copyAll(obj: URLTaskObject) {
        var arr = [String]()
        arr.append("== URL ==")
        arr.append(obj.url)
        if !obj.body.isEmpty {
            arr.append("== REQUEST_BODY ==")
            arr.append(obj.body)
        }
        arr.append("== METHOD ==")
        arr.append(obj.method)

        arr.append("== REQUEST_HEADERS ==")
        arr.append(NSAttributedString(obj.getReqHeaders).string)

        arr.append("== STATUS ==")
        arr.append("\(obj.statusCode)")

        arr.append("== RESPONSE_HEADERS ==")
        arr.append(NSAttributedString(string: obj.responseString).string)

        arr.append("== RESPONSE_BODY ==")
        arr.append(obj.responseString)

        Utils.copyToClipboard(arr.joined(separator: "\n"))
    }

    func getUpdateLink() -> some View {
        Link("Update", destination: URL(string: "https://github.com/chanonly123/local-response/releases")!)
    }

    func getCurrentVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func checkForNewVersion() {
        struct Root: Codable {
            let tag_name: String?
        }

        func versionToInt(_ ver: String) -> Int? {
            Int(ver.replacingOccurrences(of: ".", with: ""))
        }

        Task {
            guard let current = getCurrentVersion() else {
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

            if
                let newVer = versionToInt(new),
                let currentVer = versionToInt(current),
                newVer > currentVer
            {
                newVersion = new
                newVersionAlert = true
            }
        }
    }

    func toCurlCommand(obj: URLTaskObject) {
        var arr = [String]()
        let url = obj.url
        arr.append("curl")
        arr.append("    --request \(obj.method.uppercased())")
        obj.reqHeaders.forEach {
            arr.append("    --header '\($0.key): \($0.value)'")
        }
        if !obj.body.isEmpty && (obj.method.uppercased() == "POST" || obj.method.uppercased() == "PUT" || obj.method.uppercased() == "PATCH") {
            arr.append("    --data '\(obj.body)'")
        }
        arr.append("    '\(url)'")
        Utils.copyToClipboard(arr.joined(separator: " \\\n"))
    }
}
