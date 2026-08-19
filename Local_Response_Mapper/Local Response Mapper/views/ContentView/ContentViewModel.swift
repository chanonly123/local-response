//
//  ContentViewModel.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import AppKit
import Factory

@MainActor
class ContentViewModel: ObservableObject, ObservableObjectErrors {

    enum TabType: String, CaseIterable {
        case req = "Components", resString = "Response"
    }

    @Published var errors: [Error] = []
    @Published var list: [URLTaskObject]?
    var listCount: Int = 0
    @Published var filter: String = UserDefaults.standard.string(forKey: Constants.filterKey) ?? "" {
        didSet {
            UserDefaults.standard.set(filter, forKey: Constants.filterKey)
            fetch()
        }
    }
    @Published var selected = Set<String>() {
        didSet { updateFocused(oldValue: oldValue) }
    }

    /// The row the right pane follows.
    ///
    /// `Table` and `List` only report the selection as a `Set`, whose element
    /// order is hash order rather than click order — reading `selected.first`
    /// shows an arbitrary member as soon as more than one row is selected, and
    /// that is usually the row that was already on screen. The focus stays on
    /// one row and only moves once that row leaves the selection.
    @Published private(set) var focusedTaskId: String?

    private func updateFocused(oldValue: Set<String>) {
        if let focusedTaskId, selected.contains(focusedTaskId) { return }
        focusedTaskId = selected.subtracting(oldValue).first ?? selected.first
    }

    @Published var selectedTab: TabType = .req

    @Published var tree: [EndpointNode] = []
    @Published var expandedNodes: Set<String> = []
    /// hosts are expanded the first time they show up, later collapses are kept
    private var seenNodes: Set<String> = []

    @Published var newVersion: String?
    @Published var newVersionDesc: String?
    @Published var newVersionAlert: Bool = false

    var notificationToken: (any DBObservationToken)?
    @Injected(\.db) var db

    init() {
        do {
            let list = try db.getRecordsList(filter: filter)
            self.listCount = list.count
            self.list = list
            // `didSet` does not run during initialization, so the focus is
            // seeded alongside the selection here.
            self.selected = Set([list.first?.taskId].compactMap { $0 })
            self.focusedTaskId = list.first?.taskId
            self.rebuildTree(list)
            // Any committed write to the table re-runs the read, filter and
            // all — the same refetch the live query used to trigger.
            notificationToken = db.observe(table: URLTaskObject.databaseTableName) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    do {
                        let newList = try self.db.getRecordsList(filter: self.filter)
                        self.listCount = newList.count
                        self.list = newList
                        self.rebuildTree(newList)
                    } catch let e {
                        self.appendError(e)
                    }
                }
            }
        } catch let e {
            appendError(e)
        }
    }

    func fetch() {
        do {
            let newList = try db.getRecordsList(filter: filter)
            list = newList
            rebuildTree(newList)
        } catch let e {
            appendError(e)
        }
    }

    private func rebuildTree(_ items: [URLTaskObject]?) {
        let nodes = items.map { EndpointTree.build(from: $0) } ?? []
        for node in nodes where !seenNodes.contains(node.id) {
            seenNodes.insert(node.id)
            expandedNodes.insert(node.id)
        }
        tree = nodes
    }

    func generateDummyData() {
        db.createDummyForPreview()
    }

    func clearAll() {
        db.clearAllRecords()
        seenNodes.removeAll()
        expandedNodes.removeAll()
        fetch()
        if let first = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("cache") {
            try? FileManager.default.removeItem(atPath: first.path)
        }
    }

    /// Deletes the given requests and moves the selection to the nearest
    /// surviving row, so deleting doesn't drop the right pane back to the empty
    /// state on every use.
    func delete(taskIds: Set<String>) {
        guard !taskIds.isEmpty else { return }

        let ids = list?.map(\.taskId) ?? []
        let nextSelected = ids.drop(while: { !taskIds.contains($0) })
            .first(where: { !taskIds.contains($0) })
            ?? ids.last(where: { !taskIds.contains($0) })

        // Non-text responses are kept as files next to the record; read the
        // paths while the records still exist.
        let files = taskIds.compactMap { fetch(taskId: $0)?.fileURL }

        do {
            try db.deleteRecords(taskIds: Array(taskIds))
        } catch let e {
            appendError(e)
            return
        }

        files.forEach { try? FileManager.default.removeItem(at: $0) }
        selected = Set([nextSelected].compactMap { $0 })
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
        db.addMapRule(
            MapLocalObject(
                subUrl: obj.url,
                method: obj.method,
                statusCode: String(obj.statusCode),
                resHeaders: obj.resHeaders,
                resString: obj.responseString
            )
        )
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
        arr.append(Utils.dictToPlainString(item: obj.reqHeaders))

        arr.append("== STATUS ==")
        arr.append("\(obj.statusCode)")

        arr.append("== RESPONSE_HEADERS ==")
        arr.append(Utils.dictToPlainString(item: obj.resHeaders))

        arr.append("== RESPONSE_BODY ==")
        arr.append(obj.responseString)

        Utils.copyToClipboard(arr.joined(separator: "\n"))
    }

    func copy(options: Set<CopyOptions>) {
        var arr = [String]()

        for taskId in selected {
            guard let obj = fetch(taskId: taskId) else {
                continue
            }

            // Add method
            if options.contains(.method) {
                arr.append(obj.method.uppercased())
            }

            // Add URL
            if options.contains(.url) {
                arr.append("url: \(obj.url)")
            }

            // Add request body
            if options.contains(.body) && !obj.body.isEmpty {
                arr.append("body: \(obj.body)")
            }

            // Add request headers
            if options.contains(.reqHeaders) {
                arr.append("reqh: " + Utils.dictToPlainString(item: obj.reqHeaders))
            }

            // Add status code
            if options.contains(.statusCode) {
                arr.append("status: \(obj.statusCode)")
            }

            // Add response headers
            if options.contains(.resHeaders) {
                arr.append("resh: " + Utils.dictToPlainString(item: obj.resHeaders))
            }

            // Add response body
            if options.contains(.response) && !obj.responseString.isEmpty {
                arr.append("res: " + obj.responseString)
            }

            arr.append("-------------")
        }

        Utils.copyToClipboard(arr.joined(separator: "\n"))
    }

    static let releasesURL = URL(string: "https://github.com/chanonly123/local-response/releases")!

    func getUpdateButton() -> some View {
        Button("Update") { [weak self] in
            self?.runUpdate()
        }
    }

    /// Launches `update.sh` in a new Terminal window and quits the app.
    ///
    /// A running process can't replace its own binary, so `update.sh` waits for
    /// this instance to quit before it pulls `main`, rebuilds, and relaunches.
    /// The build/pull happens in Terminal (unsandboxed), so it works even though
    /// this app is sandboxed and can't touch the repo itself.
    func runUpdate() {
        guard let scriptURL = locateUpdateScript() else {
            // Couldn't find the source checkout (e.g. a downloaded release
            // binary) — fall back to the releases page.
            NSWorkspace.shared.open(Self.releasesURL)
            return
        }

        // Hand off to Terminal via AppleScript rather than writing a `.command`
        // launcher. A file written by this sandboxed app gets stamped with the
        // quarantine attribute, which makes Gatekeeper report it as "damaged".
        // `osascript` telling Terminal to `do script` avoids the file entirely.
        //
        // Single-quote the script path for the shell; no double quotes inside,
        // so the command embeds cleanly in the AppleScript string.
        let shellCommand = "bash '\(scriptURL.path)'"
        let appleScript = """
        tell application "Terminal"
            do script "\(shellCommand)"
            activate
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        do {
            try process.run()
            // Give Terminal a moment to launch before we quit so update.sh can
            // detect our exit and safely rebuild.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApplication.shared.terminate(nil)
            }
        } catch let e {
            appendError(e)
        }
    }

    /// Locates the repo's `update.sh` by walking up from the app bundle
    /// location one directory at a time until a directory containing
    /// `update.sh` is found, or the filesystem root is reached.
    /// Returns `nil` for layouts with no `update.sh` in any ancestor (Xcode's
    /// shared DerivedData, a downloaded release binary), so those fall back
    /// to the releases page.
    private func locateUpdateScript() -> URL? {
        let fileManager = FileManager.default
        var dir = Bundle.main.bundleURL
        while dir.pathComponents.count > 1 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("update.sh")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    func getCurrentVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func checkForNewVersion() {
        struct Root: Codable {
            let tag_name: String?
            let body: String?
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

            if AppVersion.isNewer(new, than: current) {
                newVersion = new
                newVersionDesc = root.body
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
