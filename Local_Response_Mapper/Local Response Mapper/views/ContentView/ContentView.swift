//
//  ContentView.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var localMapsViewm = LocalMapViewModel()
    @StateObject private var myColorScheme = ColorSchemeViewModel.shared
    @StateObject private var viewm = ContentViewModel()
    @StateObject private var server = LocalServer()
    @AppStorage(Constants.autoScrollOffKey) private var autoScrollOff = false
    @State private var scrollToId: String?
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize
    @AppStorage(Constants.leftViewModeKey) private var leftMode: LeftViewMode = .sequence
    @AppStorage(Constants.mapRulesOffKey) private var rulesOff = false
    @AppStorage(Constants.mapDelayMsKey) private var delayMs = 0

    /// Which columns are shown, and in what order.
    ///
    /// Kept in `UserDefaults` rather than scene storage: scene storage belongs
    /// to a window's restored state, so a window opened fresh — or opened after
    /// the app was relaunched without restoration — came up with every column
    /// back. Columns are a preference, and this is where preferences live.
    @State private var customization: TableColumnCustomization<URLTaskRow>

    @AppStorage(Constants.hideUrlQueryKey) private var hideUrlQuery = false

    /// Both settings are stored as their opposite — see `Constants` — so each
    /// switch reads and writes through the sense the user sees.
    private var autoScroll: Binding<Bool> {
        Binding { !autoScrollOff } set: { autoScrollOff = !$0 }
    }

    private var showUrlQuery: Binding<Bool> {
        Binding { !hideUrlQuery } set: { hideUrlQuery = !$0 }
    }

    init() {
        _customization = State(initialValue: Self.loadColumns())
    }

    private static func loadColumns() -> TableColumnCustomization<URLTaskRow> {
        guard let data = UserDefaults.standard.data(forKey: Constants.tableColumnsKey),
              let stored = try? JSONDecoder().decode(
                TableColumnCustomization<URLTaskRow>.self,
                from: data
              )
        else {
            return TableColumnCustomization<URLTaskRow>()
        }
        return stored
    }

    private static func saveColumns(_ columns: TableColumnCustomization<URLTaskRow>) {
        guard let data = try? JSONEncoder().encode(columns) else { return }
        UserDefaults.standard.set(data, forKey: Constants.tableColumnsKey)
    }

    @State private var showMultiCopyPopover = false
    @State private var multiCopySelectedItems: Set<CopyOptions> = [.method, .url, .body, .statusCode]

    var body: some View {
        VStack(spacing: 0) {
            PersistentHSplitView(widthKey: Constants.contentRightPaneWidthKey) {
                leftView
            } right: {
                rightView
                    .navigationTitle("Local Response Mapper (\(viewm.getCurrentVersion() ?? ""))")
            }

            HStack {
                Toggle("Auto scroll", isOn: autoScroll)
                    .help("Follow the newest recorded call")

                Toggle("Query params", isOn: showUrlQuery)
                    .help("Show the query string after the path in the URL column")

                MapRuleControls()

                Spacer()

                Button {
                    if server.isListening == true {
                        Utils.copyToClipboard("\(server.listeningAddress)")
                    }
                } label: {
                    Circle().fill(server.isListening == true ? Color.green : Color.gray)
                        .frame(width: 10)
                    switch server.isListening {
                    case false:
                        Text("Start Server")
                    case nil:
                        Text("Connecting...")
                    case true:
                        HStack {
                            Text("Listening \(server.listeningAddress)")
                            Image(systemName: "doc.on.doc")
                        }
                    case .some(_):
                        EmptyView()
                    }
                }
            }
            .padding(2)
            .padding(.leading, 6)
        }
        .font(.system(size: fontSize - 2))
        .monospaced()
        .background(ToolbarLock())
        .showErrors(errors: viewm.errors)
        .onAppear {
            server.startServer()
            server.reloadLocalAddress()
            viewm.checkForNewVersion()
        }
        .onChange(of: customization) { _, columns in
            Self.saveColumns(columns)
        }
        .toolbar {

#if DEBUG
            Button {
                viewm.generateDummyData()
            } label: {
                Text("Add Dummy data")
            }
#endif

            Button {
                myColorScheme.rotateScheme()
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.striped.horizontal.inverse")
            }

            let enabledCount = localMapsViewm.getEnabledCount

            Button {
                openLocalMapWindow()
            } label: {
                // With the master switch off the count would read as "3 rules
                // are working", which is the opposite of what is happening. The
                // delay rides along because a held request looks like a slow
                // server, and this window is where that is noticed.
                Text("Override Rules\(overrideRulesSuffix(enabledCount: enabledCount))")
            }

            Button {
                viewm.clearAll()
            } label: {
                Text("Clear All")
            }
        }
        .alert(
            "New version available\n\(viewm.newVersion ?? "")",
            isPresented: $viewm.newVersionAlert,
            actions: {
                viewm.getUpdateButton()
                Button("Cancel") { }
            },
            message: {
                Text(viewm.newVersionDesc ?? "")
            }
        )
        .popover(
            isPresented: $showMultiCopyPopover,
            attachmentAnchor: .point(.center),
            arrowEdge: .bottom
        ) {
            SelectionPopoverView(
                items: CopyOptions.allCases,
                viewm: viewm,
                selectedItems: $multiCopySelectedItems,
                isPresented: $showMultiCopyPopover
            )
        }
    }

    private func overrideRulesSuffix(enabledCount: Int) -> String {
        if rulesOff { return " (off)" }
        var parts = [String]()
        if enabledCount > 0 { parts.append("\(enabledCount)") }
        if delayMs > 0 { parts.append(Utils.delayLabel(delayMs)) }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: " · ")))"
    }

    @State var selectedOptions: String = "0"

    var leftView: some View {
        VStack(spacing: 0) {
            Picker("", selection: $leftMode) {
                ForEach(LeftViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(2)

            switch leftMode {
            case .structure:
                structureView
            case .sequence:
                sequenceView
            }

            TextField("Matches url/bundleID. Combine with && / ||, e.g. app && (profile || todo). Quote terms with spaces: \"my todo\"", text: $viewm.filter)
                .textFieldStyle(.roundedBorder)
        }
        // The tree costs a walk over every recorded call to build, so it is
        // only kept up to date while it is the tab on screen.
        .onAppear { viewm.setTreeVisible(leftMode == .structure) }
        .onChange(of: leftMode) { _, mode in
            viewm.setTreeVisible(mode == .structure)
        }
    }

    var structureView: some View {
        EndpointTreeView(
            nodes: viewm.tree,
            selection: $viewm.selected,
            expanded: $viewm.expandedNodes,
            contextMenu: { taskId in
                if let val = viewm.fetch(taskId: taskId) {
                    getContextMenuForSingleRow(val: val)
                }
            }
        )
        .frame(minWidth: 300, maxHeight: .infinity)
    }

    var sequenceView: some View {
        VStack(spacing: 0) {
            if let items = viewm.list {

                ScrollViewReader { proxy in
                    Table(
                        of: URLTaskRow.self,
                        selection: $viewm.selected,
                        columnCustomization: $customization,
                        columns: {
                            TableColumn(
                                "BundleID",
                                content: { val in
                                Text(val.bundleID)
                                    .truncationMode(.head)
                                    .help(val.bundleID)
                                    .id(val.id)
                                }
                            )
                            .width(min: 50, ideal: 50, max: 200)
                            .customizationID("BundleID")

                            TableColumn("MimeType", content: { val in
                                Text("\(val.mimeType)")
                                    .help(val.mimeType)
                            })
                            .width(min: 50, ideal: 50, max: 110)
                            .customizationID("MimeType")


                            TableColumn("Method", content: { val in
                                Text("\(val.method)")
                                    .help(val.method)
                            })
                            .width(min: 50, ideal: 50, max: 60)
                            .customizationID("Method")

                            // One column for both directions: up is what the
                            // app sent, down is what it received. Arrows keep
                            // the two apart without a colour that a selected
                            // row would swallow.
                            TableColumn("Modified", content: { val in
                                HStack(spacing: 3) {
                                    if val.isRequestEdited {
                                        Image(systemName: "arrowshape.up.fill")
                                        Text("REQ")
                                    }
                                    if val.isEdited {
                                        Image(systemName: "arrowshape.down.fill")
                                        Text("RES")
                                    }
                                    if !val.isRequestEdited && !val.isEdited {
                                        Text("-")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .help(Self.modifiedHelp(val))
                            })
                            .width(min: 55, ideal: 60, max: 85)
                            .customizationID("Modified")

                            TableColumn("Time", content: { val in
                                Text(val.timeDelay)
                            })
                            .width(min: 45, ideal: 45, max: 60)
                            .customizationID("Time")

                            TableColumn("Status", content: { val in
                                HStack {
                                    Circle().fill(Utils.getStatusColor(val.statusCode))
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 1)
                                    Text("\(val.statusCode > 0 ? "\(val.statusCode)" : "")")
                                }
                            })
                            .width(min: 50, ideal: 50, max: 60)
                            .customizationID("Status")

                            TableColumn("URL", content: { val in
                                Text(urlDisplay(val))
                                    .truncationMode(.head)
                                    .help(val.url)
                            })
                            .width(min: 50, ideal: 200)
                            .customizationID("URL")

                        },
                        rows: {
                            ForEach(items) { val in
                                TableRow(val)
                                    .contextMenu {
                                        // The row itself carries no bodies —
                                        // the menu copies them, so it reads the
                                        // whole record, and only when opened.
                                        if let full = viewm.fetch(taskId: val.taskId) {
                                            getContextMenuForSingleRow(val: full)
                                        }
                                    }
                            }
                        }
                    )
                    .frame(minWidth: 300)
                    .onChange(of: viewm.listCount) { _, _ in
                        if autoScroll.wrappedValue, let last = viewm.list?.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            } else {
                Image(systemName: "tray")
            }
        }
    }

    var rightView: some View {
        VStack(alignment: .center, spacing: 0) {
            if let item = viewm.fetch(taskId: viewm.focusedTaskId) {
                // Keyed on the request, so the pane is rebuilt rather than
                // reused when the selection moves and nothing inside it can
                // carry state over from the row that was on screen before. The
                // token is part of the key so a reload rebuilds it too.
                detailView(item: item)
                    .id("\(item.id)-\(viewm.detailReloadToken)")
            } else {
                Image(systemName: "tray")
            }
        }
    }

    @ViewBuilder
    func detailView(item: URLTaskObject) -> some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Spacer()
                HStack {
                    ForEach(ContentViewModel.TabType.allCases, id: \.self) { tab in
                        Button {
                            viewm.selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .foregroundColor(viewm.getTabButtonTextColor(tab: tab))
                        }
                        .setSelectedButtonStyle(selected: viewm.selectedTab == tab)
                    }
                }
                Spacer()
            }
            .overlay(alignment: .trailing) {
                // A non-text body is written to its file after the row is
                // recorded, so a pane opened in that moment can find nothing
                // there — and what it found is kept until the record is read
                // again. This reads it again.
                Button {
                    viewm.reloadDetail()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload this response from disk")
                .padding(.trailing, 8)
            }
            .padding(2)

            switch viewm.selectedTab {
            case .req:
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BundleID")
                            .underline()
                        Text(Utils.styledScalar(item.bundleID))

                        Divider()

                        Text("Host")
                            .underline()
                        Text(item.getHost)

                        Divider()

                        Text("Method")
                            .underline()
                        Text(Utils.styledScalar(item.method))

                        Divider()

                        Text("Path")
                            .underline()
                        Text(item.getPath)

                        Divider()

                        Text("Query Params")
                            .underline()
                        KeyValueList(pairs: item.getQuery)

                        Divider()

                        Text("Request headers")
                            .underline()
                        KeyValueList(pairs: item.getReqHeaders)

                        Divider()

                        Text("Request Body")
                            .underline()
                        JSONBodyText(raw: item.prettyBody)

                        Divider()

                        Text("Status")
                            .underline()
                        Text(Utils.styledScalar("\(item.statusCode)")) + Text("    ") +
                        Text("\(Utils.getCommonDescription(httpStatusCode: item.statusCode) ?? "")")
                            .foregroundColor(.gray)

                        Divider()

                        Text("Response headers")
                            .underline()
                        KeyValueList(pairs: item.getResHeaders)
                    }
                    .padding()
                }
                .textSelection(.enabled)
            case .resString:
                ResponseView(item: item, theme: theme)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// The url column's text, with the query parameters told apart from the
    /// path and from each other.
    ///
    /// A selected row is left plain: the table paints the selection and draws
    /// that row's text to sit on it, which colors of ours would not survive —
    /// dark text on the selection fill reads as a smudge.
    private func urlDisplay(_ row: URLTaskRow) -> AttributedString {
        let text = hideUrlQuery ? row.getPathString : row.getPathWithQuery
        guard !viewm.selected.contains(row.taskId) else {
            return AttributedString(text)
        }
        return SyntaxStyle.current.url(text)
    }

    /// Says which arrow is which — the column is two glyphs wide, so the
    /// direction they stand for has to be readable from the row itself.
    static func modifiedHelp(_ val: URLTaskRow) -> String {
        switch (val.isRequestEdited, val.isEdited) {
        case (false, false):
            return "Sent and received unchanged"
        case (true, false):
            return "↑ A Modify Request rule rewrote this request before it was sent"
        case (false, true):
            return "↓ A Map Response rule answered this request instead of the server"
        case (true, true):
            return "↑ The request was rewritten before it was sent, ↓ and a Map Response rule answered it instead of the server"
        }
    }

    func openLocalMapWindow() {
        openWindow(id: "map-local-view")
    }

    var theme: CodeEditor.ThemeName {
        let theme = CodeEditor.ThemeName(rawValue: Utils.getThemeName(colorScheme: myColorScheme.value))

        return theme
    }

    func getContextMenuForSingleRow(val: URLTaskObject) -> some View {
        VStack {
            if viewm.selected.count > 1 {
                Button("Copy Requests") {
                    showMultiCopyPopover.toggle()
                }
                Divider()
                Button("Delete \(viewm.selected.count) Requests") {
                    viewm.delete(taskIds: viewm.selected)
                }
            } else {
                if val.contentType == .text {
                    Button("Map local") {
                        viewm.addNewMapLocal(obj: val)
                        openLocalMapWindow()
                    }
                    Button("Copy Request Body") {
                        viewm.copyValue(val.prettyBody)
                    }
                    Button("Copy Response String") {
                        viewm.copyValue(val.prettyResponseString)
                    }
                    Button("Copy All") {
                        viewm.copyAll(obj: val)
                    }
                }
                Button("Copy URL") {
                    viewm.copyValue(val.url)
                }
                Button("Copy CURL") {
                    viewm.toCurlCommand(obj: val)
                }
                Divider()
                Button("Delete Request") {
                    viewm.delete(taskIds: [val.taskId])
                }
            }
        }
    }

}


enum CopyOptions: String, CaseIterable, Hashable, Identifiable {
    case method, url, body, statusCode, reqHeaders, resHeaders, response
    var id: Self { self }
}

struct SelectionPopoverView: View {
    private let items: [CopyOptions]
    private let viewm: ContentViewModel
    @Binding private var selectedItems: Set<CopyOptions>
    @Binding private var isPresented: Bool

    init(
        items: [CopyOptions],
        viewm: ContentViewModel,
        selectedItems: Binding<Set<CopyOptions>>,
        isPresented: Binding<Bool>
    ) {
        self.items = items
        self.viewm = viewm
        self._selectedItems = selectedItems
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select items to Copy")
                .font(.headline)
                .padding(.top)

            List {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item.rawValue)
                        Spacer()
                        if selectedItems.contains(item) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedItems.contains(item) {
                            selectedItems.remove(item)
                        } else {
                            selectedItems.insert(item)
                        }
                    }
                }
            }
            .frame(height: 200)

            Button("Copy") {
                viewm.copy(options: selectedItems)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .frame(width: 200)
    }
}

/// Renders headers or query parameters, one `key: value` per line.
///
/// Values past `Constants.collapseLimit` are cut and expanded on demand.
struct KeyValueList: View {

    let pairs: [KeyValuePair]

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pairs) { pair in
                let isLong = pair.value.count > Constants.collapseLimit
                let isExpanded = expanded.contains(pair.key)
                // `prefix` counts Characters, so a cut never lands inside a
                // grapheme cluster.
                let shown = isLong && !isExpanded
                    ? String(pair.value.prefix(Constants.collapseLimit)) + "…"
                    : pair.value

                HStack(alignment: .top, spacing: 6) {
                    Text(SyntaxStyle.current.pair(key: pair.key, value: shown))
                        .fixedSize(horizontal: false, vertical: true)

                    if isLong {
                        Button(isExpanded ? "less" : "more") {
                            if isExpanded {
                                expanded.remove(pair.key)
                            } else {
                                expanded.insert(pair.key)
                            }
                        }
                        .buttonStyle(.link)
                        // The button is a control, not part of the value: let a
                        // drag through this row select the text instead.
                        .textSelection(.disabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a request body with JSON coloring. Small bodies are colored up
/// front so they appear styled on the first frame; larger ones are handed to a
/// background task so a big body can't stall the selection changing.
struct JSONBodyText: View {

    /// Coloring this much takes well under a frame — see JSONHighlighter for
    /// the cost curve. Past it, the work moves off the main thread.
    private static let inlineLimit = 4 * 1024

    private let raw: String

    /// The cached coloring is kept together with the body it was made from, so
    /// a coloring can only ever be shown for the body it was made for — the
    /// body can change under this view whenever it is reused rather than
    /// rebuilt (an in-flight request completing, say).
    @State private var highlighted: (source: String, text: AttributedString)?

    init(raw: String) {
        self.raw = raw
    }

    private var display: AttributedString {
        if let highlighted, highlighted.source == raw {
            return highlighted.text
        }
        if raw.utf8.count <= Self.inlineLimit {
            return Utils.highlightJson(raw)
        }
        return AttributedString(raw)
    }

    var body: some View {
        Text(display)
            .task(id: raw) {
                guard raw.utf8.count > Self.inlineLimit else { return }
                // The color scheme is main-actor state, so it is resolved
                // before handing the work off.
                let style = SyntaxStyle.current
                let body = raw
                let text = await Task.detached {
                    JSONHighlighter.highlight(body, style: style)
                }.value
                highlighted = (source: body, text: text)
            }
    }
}

fileprivate extension View {

    @ViewBuilder
    func setSelectedButtonStyle(selected: Bool) -> some View {
        if selected {
            self.buttonStyle(.bordered)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

#Preview {
    ContentView()
}
