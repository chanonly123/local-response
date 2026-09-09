//
//  ContentViewModel.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import AppKit
import QuartzCore
import Factory

@MainActor
class ContentViewModel: ObservableObject, ObservableObjectErrors {

    enum TabType: String, CaseIterable {
        case req = "Components", resString = "Response"
    }

    @Published var errors: [Error] = []
    @Published var list: [URLTaskRow]?
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
            // all — the same refetch the live query used to trigger, coalesced
            // so a flood of writes cannot outrun what the screen can show.
            notificationToken = db.observe(table: URLTaskObject.databaseTableName) { [weak self] in
                MainActor.assumeIsolated {
                    self?.scheduleRefresh()
                }
            }
        } catch let e {
            appendError(e)
        }
    }

    // MARK: - Refreshing

    /// The shortest gap between two refetches of the list.
    ///
    /// One recorded call commits up to three times, and a flood commits far
    /// faster than the list can usefully redraw — every one of those commits
    /// used to re-read and re-draw the whole table. A row can therefore appear
    /// up to this late; nothing is dropped, since the refetch that does run
    /// reads whatever the database holds at that moment.
    private static let refreshInterval: CFTimeInterval = 0.15

    private var refreshDirty = false
    private var refreshScheduled = false
    private var lastRefresh: CFTimeInterval = 0

    /// Refreshes now if the last refresh is far enough behind, and otherwise
    /// once at the end of the current window. The first change after a quiet
    /// spell is never held back, so a single request still shows up at once.
    private func scheduleRefresh() {
        let now = CACurrentMediaTime()
        let since = now - lastRefresh
        if since >= Self.refreshInterval && !refreshScheduled {
            lastRefresh = now
            fetch()
            return
        }
        refreshDirty = true
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.refreshInterval - since)) { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            guard self.refreshDirty else { return }
            self.refreshDirty = false
            self.lastRefresh = CACurrentMediaTime()
            self.fetch()
        }
    }

    /// The read in flight. Cancelled when another is asked for: a refresh
    /// started before this one finished would land out of order.
    private var fetchTask: Task<Void, Never>?

    /// Re-reads the list off the main thread and publishes the result.
    ///
    /// Reading it decodes every recorded row, and that used to happen on the
    /// main thread on every tick — the list grows all session, so the cost of a
    /// refresh grew with it while the window was trying to stay responsive.
    func fetch() {
        let filter = self.filter
        let db = self.db
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            do {
                let newList = try await Task.detached(priority: .userInitiated) {
                    try db.getRecordsList(filter: filter)
                }.value
                guard !Task.isCancelled, let self else { return }
                self.apply(newList)
            } catch {
                self?.appendError(error)
            }
        }
    }

    private func apply(_ newList: [URLTaskRow]) {
        // A recorded call the filter hides still commits, and the refresh it
        // triggers still reads the list — but publishing the identical result
        // would have SwiftUI diff and redraw the table for a row nobody can
        // see. Comparing the rows costs a pass; publishing them costs a frame.
        guard hasChanged(newList) else { return }

        listCount = newList.count
        list = newList
        rebuildTree(newList)
        pruneDetailCache(against: newList)
    }

    private func hasChanged(_ newList: [URLTaskRow]) -> Bool {
        guard let current = list else { return true }
        guard current.count == newList.count else { return true }
        return !zip(current, newList).allSatisfy { $0.sameContent(as: $1) }
    }

    // MARK: - Endpoint tree

    /// Whether the Structure tab is the one on screen.
    ///
    /// Building the tree walks every recorded call, and the Sequence tab does
    /// not show it — under a flood that is a whole tree thrown away several
    /// times a second for nobody. It is built when the tab comes back instead.
    private var treeVisible = false

    /// Set while the tree is not being built, so switching to it rebuilds
    /// rather than showing whatever it held when it was last on screen.
    private var treeStale = true

    /// The snapshots the last build made, reused by the next one for every row
    /// that has not changed since — see `EndpointTree.build`.
    private var endpointCache: [String: EndpointRequest] = [:]

    func setTreeVisible(_ visible: Bool) {
        guard treeVisible != visible else { return }
        treeVisible = visible
        if visible && treeStale {
            rebuildTree(list)
        }
    }

    private func rebuildTree(_ items: [URLTaskRow]?) {
        guard treeVisible else {
            treeStale = true
            return
        }
        treeStale = false
        let nodes = items.map { EndpointTree.build(from: $0, cache: &endpointCache) } ?? []
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
        endpointCache.removeAll()
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

    /// The full record for one row — bodies included — kept until the next
    /// refresh.
    ///
    /// The right pane asks for its record every time it is laid out, and the
    /// record it gets carries the laid-out copy of the body, so re-reading it
    /// per redraw means re-reading and re-formatting the same body. Cleared in
    /// `fetch()`, so a record can never outlive a write that touched it.
    private var detailCache: [String: URLTaskObject] = [:]

    /// Far more than the panes need at once — the cache exists to survive
    /// redraws, not to hold the table.
    private static let detailCacheLimit = 64

    /// Bumped to rebuild the detail pane — see `reloadDetail()`.
    @Published private(set) var detailReloadToken = 0

    /// Re-reads the focused record from scratch.
    ///
    /// A non-text response body is kept in a file written after the row is
    /// committed, so a pane opened in that moment finds nothing there — and
    /// what it found is cached, on the record's own lazy properties, until the
    /// record itself is replaced. This drops it and makes the pane build again.
    func reloadDetail() {
        guard let taskId = focusedTaskId else { return }
        detailCache.removeValue(forKey: taskId)
        detailReloadToken += 1
    }

    /// Drops the cached records the refresh actually changed, and keeps the
    /// rest.
    ///
    /// Clearing the whole cache meant the focused record was read again — with
    /// its bodies — and laid out again on every tick, which with a large
    /// response selected was the most expensive thing the main thread did.
    private func pruneDetailCache(against rows: [URLTaskRow]) {
        guard !detailCache.isEmpty else { return }

        var stillListed = Set<String>(minimumCapacity: detailCache.count)
        var stale = [String]()
        for row in rows {
            guard let cached = detailCache[row.taskId] else { continue }
            stillListed.insert(row.taskId)
            if !cached.matches(row) {
                stale.append(row.taskId)
            }
        }
        // A record the list no longer carries has been deleted, or filtered out
        // of view — either way this is not the copy to answer with next time.
        stale.append(contentsOf: detailCache.keys.filter { !stillListed.contains($0) })
        stale.forEach { detailCache.removeValue(forKey: $0) }
    }

    func fetch(taskId: String?) -> URLTaskObject? {
        guard let taskId else { return nil }
        if let cached = detailCache[taskId] { return cached }
        do {
            guard let item = try db.getItemTask(taskId: taskId) else { return nil }
            if detailCache.count >= Self.detailCacheLimit {
                detailCache.removeAll()
            }
            detailCache[taskId] = item
            return item
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
                resString: obj.prettyResponseString
            )
        )
    }

    func copyValue(_ value: String) {
        Utils.copyToClipboard(value)
    }

    func copyAll(obj: URLTaskObject) {
        var arr = [String]()
        arr.append("== URL ==")
        arr.append(obj.url)
        if !obj.body.isEmpty {
            arr.append("== REQUEST_BODY ==")
            arr.append(obj.prettyBody)
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
        arr.append(obj.prettyResponseString)

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
                arr.append("body: \(obj.prettyBody)")
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
                arr.append("res: " + obj.prettyResponseString)
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
