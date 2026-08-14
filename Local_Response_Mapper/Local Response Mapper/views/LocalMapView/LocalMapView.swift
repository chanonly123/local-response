//
//  LocalMapView.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import SwiftUI
import CodeEditor

struct LocalMapView: View {

    @StateObject private var myColorScheme = ColorSchemeViewModel.shared
    @StateObject private var viewm = LocalMapViewModel()
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize
    @State private var showVariables = false

    var body: some View {
        PersistentHSplitView(widthKey: Constants.mapLocalRightPaneWidthKey) {
            leftView
        } right: {
            rightView
                .navigationTitle("Map Local")
        }
        .font(.system(size: fontSize - 2))
        .monospaced()
        .toolbar {
            Button {
                showVariables = true
            } label: {
                Label("Variables", systemImage: "curlybraces")
            }
            .help("Placeholders a rule can send — {{uuid}}, {{timestamp}}, and your own")

            Button {
                viewm.clearAll()
            } label: {
                Text("Clear All")
            }
        }
        .sheet(isPresented: $showVariables) {
            TemplateHelpView()
        }
    }

    /// The rule list: what exists, what is on, and — through the subtitle — what
    /// each rule does, without having to select it. Editing lives in `rightView`.
    var leftView: some View {
        VStack(spacing: 0) {
            TextField("Filter rules", text: $viewm.search)
                .textFieldStyle(.roundedBorder)
                .padding(4)
                .disabled(viewm.list?.isEmpty != false)

            Divider()

            // Both of these stay mounted whatever the list holds. Deleting the
            // last rule used to swap the whole `List` out for the empty state,
            // and tearing an NSTableView out of the hierarchy from inside the
            // click that emptied it crashes AppKit — so the empty state is drawn
            // over the list instead of replacing it.
            ruleList
                .overlay {
                    if viewm.visibleRules.isEmpty {
                        emptyState
                    }
                }

            Divider()
            bottomBar
        }
        .frame(minWidth: 300)
    }

    var ruleList: some View {
        List(selection: $viewm.selected) {
            ForEach(viewm.visibleRules) { rule in
                MapRuleRow(
                    rule: rule,
                    priority: viewm.priority(of: rule.id),
                    shadowedBy: viewm.shadowingPriority(of: rule.id),
                    enabled: viewm.getSetValue(rule.id, keyPath: \.enable)
                )
                .tag(rule.id)
                .contextMenu {
                    Button("Duplicate") {
                        viewm.selected = rule.id
                        viewm.duplicateSelected()
                    }
                    Button("Delete") {
                        viewm.selected = rule.id
                        viewm.deleteSelected()
                    }
                }
            }
            .onMove { viewm.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, MapRuleRow.minRowHeight)
        .animation(.easeInOut(duration: 0.2), value: viewm.visibleRules.map(\.id))
    }

    @ViewBuilder
    var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            if viewm.list?.isEmpty == false {
                Text("No rule matches the filter")
                    .foregroundStyle(.secondary)
            } else {
                Text("No rules yet")
                    .foregroundStyle(.secondary)
                Text("A rule matches every request whose url contains its text — or * for all of them — and either answers it with a canned response or edits it before it is sent.")
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                Button("Add Rule") {
                    viewm.addNew()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                viewm.addNew()
            } label: {
                Image(systemName: "plus")
            }
            .help("Add rule")

            Button {
                viewm.deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .disabled(viewm.selected == nil)
            .help("Delete rule")

            Spacer()

            Text(viewm.ruleCountLabel)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .font(.headline)
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    /// Two cards, because the pane answers two unrelated questions: *when does
    /// this rule fire* and *what does it send back*. Read as one flat stack they
    /// were indistinguishable.
    var rightView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = viewm.getSelectedItem() {
                matchSection(item)
                switch item.kind {
                case .mapResponse: overrideSection(item)
                case .modifyRequest: modifyRequestSection(item)
                }
            } else {
                Spacer()
                Image(systemName: "tray")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(6)
    }

    func matchSection(_ item: MapLocalObject) -> some View {
        RuleSection("Match", caption: "when this rule fires") {
            if let shadowedBy = viewm.shadowingPriority(of: item.id) {
                Label("rule \(shadowedBy) matches first", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("An earlier rule already catches every request this one would, so this rule never fires.")
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    fieldLabel("Does")

                    Picker("", selection: viewm.getSetValue(item.id, keyPath: \.kind)) {
                        ForEach(MapLocalObject.RuleKind.allCases, id: \.self) {
                            Text($0.title)
                                .font(.system(size: fontSize - 2))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .padding(.leading, -30)
                    .help("Map Response answers the request locally. Modify Request edits it and lets it go to the server.")

                    Spacer()
                }

                HStack(spacing: 6) {
                    fieldLabel("Method")

                    Picker("", selection: viewm.getSetValue(item.id, keyPath: \.method)) {
                        ForEach(viewm.httpMethods, id: \.self) {
                            Text($0)
                                .font(.system(size: fontSize - 2))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .padding(.leading, -30)

                    Toggle("Enabled", isOn: viewm.getSetValue(item.id, keyPath: \.enable))

                    Spacer()
                }

                HStack(spacing: 6) {
                    fieldLabel("URL contains")

                    TextField("* for every url", text: viewm.getSetValue(item.id, keyPath: \.subUrl))
                        .help(item.subUrl)
                }

                if item.matchesNoUrl {
                    Label("no url — this rule never fires", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("An empty url matches nothing. Type part of a url, or * to match every request.")
                }
            }
        }
    }

    func overrideSection(_ item: MapLocalObject) -> some View {
        RuleSection(item.kind.title, caption: item.kind.caption) {
            variablesLink
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    fieldLabel("Status")

                    TextField("", text: viewm.getSetValue(item.id, keyPath: \.statusCode))
                        .frame(width: 60)

                    if viewm.isValidStatus(item) {
                        Text(Utils.getCommonDescription(httpStatusCode: item.status) ?? "")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not a status code")
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }

                let notes = viewm.headerNotes(item)

                subFieldLabel("Response Headers") {
                    Text("\(item.headerCount) sent")
                        .foregroundStyle(.tertiary)
                }

                MyTextEditor(
                    source: viewm.getSetValue(item.id, keyPath: \.resHeaders),
                    language: .yaml,
                    theme: theme,
                    flags: [.editable, .selectable]
                )
                .frame(maxHeight: 100)
                // Per field, not per rule: the editors are siblings, and an id
                // they share lets SwiftUI carry one's state — its selection —
                // over to another's text.
                .id("\(item.id)-resHeaders")
                .editorFrame()

                ForEach(notes) { note in
                    HeaderNoteView(note: note) {
                        viewm.removeHeader(named: note.name, from: item.id)
                    }
                }

                subFieldLabel("Response String") {
                    Button {
                        viewm.formatJsonBody()
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .buttonStyle(.borderless)
                    .help("Format JSON")

                    if viewm.isValidResponseJSON(item) {
                        Text("Valid JSON")
                            .foregroundStyle(.green)
                    } else {
                        Text("Invalid JSON")
                            .foregroundStyle(.red)
                    }
                }

                MyTextEditor(
                    source: viewm.getSetValue(item.id, keyPath: \.resString),
                    language: .json,
                    theme: theme,
                    flags: [.editable, .selectable]
                )
                .frame(maxHeight: .infinity)
                .id("\(item.id)-resString")
                .editorFrame()
            }
        }
    }

    /// The edits a `modifyRequest` rule makes on the way out. Unlike an
    /// override, the request still goes to the server — so there is no status
    /// code here, and every matching rule of this kind gets its turn.
    func modifyRequestSection(_ item: MapLocalObject) -> some View {
        RuleSection(item.kind.title, caption: item.kind.caption) {
            if !item.changesRequest {
                Label("changes nothing yet", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .help("The rule matches, but sets no header and no body, so the request goes out unchanged.")
            }
            variablesLink
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                let notes = viewm.requestHeaderNotes(item)

                subFieldLabel("Query Parameters") {
                    Text("\(item.reqQueryCount) set")
                        .foregroundStyle(.tertiary)
                }

                MyTextEditor(
                    source: viewm.getSetValue(item.id, keyPath: \.reqQuery),
                    language: .yaml,
                    theme: theme,
                    flags: [.editable, .selectable]
                )
                .frame(maxHeight: 80)
                .id("\(item.id)-reqQuery")
                .editorFrame()

                Text(verbatim: "One \"name: value\" per line. A parameter already in the url is replaced, the rest are kept.")
                    .foregroundStyle(.tertiary)

                subFieldLabel("Request Headers") {
                    Text("\(item.reqHeaderCount) set")
                        .foregroundStyle(.tertiary)
                }

                MyTextEditor(
                    source: viewm.getSetValue(item.id, keyPath: \.reqHeaders),
                    language: .yaml,
                    theme: theme,
                    flags: [.editable, .selectable]
                )
                .frame(maxHeight: 100)
                .id("\(item.id)-reqHeaders")
                .editorFrame()

                Text(verbatim: "One \"name: value\" per line. A header the app already sends is replaced.")
                    .foregroundStyle(.tertiary)

                ForEach(notes) { note in
                    HeaderNoteView(note: note) {
                        viewm.removeHeader(named: note.name, from: item.id, keyPath: \.reqHeaders)
                    }
                }

                subFieldLabel("Request Body") {
                    Button {
                        viewm.formatJsonBody(keyPath: \.reqString)
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .buttonStyle(.borderless)
                    .help("Format JSON")

                    if item.reqString.isEmpty {
                        Text("Body unchanged")
                            .foregroundStyle(.secondary)
                    } else if viewm.isValidRequestJSON(item) {
                        Text("Valid JSON")
                            .foregroundStyle(.green)
                    } else {
                        Text("Invalid JSON")
                            .foregroundStyle(.red)
                    }
                }

                MyTextEditor(
                    source: viewm.getSetValue(item.id, keyPath: \.reqString),
                    language: .json,
                    theme: theme,
                    flags: [.editable, .selectable]
                )
                .frame(maxHeight: .infinity)
                .id("\(item.id)-reqString")
                .editorFrame()
            }
        }
    }

    /// Sits on the card whose fields accept placeholders, so the reference is
    /// found from the editor rather than only from the toolbar.
    var variablesLink: some View {
        Button {
            showVariables = true
        } label: {
            Text(verbatim: "{{variables}}")
        }
        .buttonStyle(.link)
        .help("What can be written in these fields, and your own variables")
    }

    /// Fixed-width leading label, so every control in a section lines up on one
    /// column instead of floating at its own indent.
    func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 90, alignment: .leading)
    }

    /// Header for a field that owns a whole row — an editor rather than a
    /// single control.
    func subFieldLabel<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.top, 2)
    }

    var theme: CodeEditor.ThemeName {
        .init(rawValue: Utils.getThemeName(colorScheme: myColorScheme.value))
    }
}

/// A titled card in the rule editor. The filled header bar plus the border is
/// what separates one group of settings from the next — without it the fields
/// run together into a single undifferentiated column.
private struct RuleSection<Trailing: View, Content: View>: View {

    private static var cornerRadius: CGFloat { 6 }

    let title: String
    let caption: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        _ title: String,
        caption: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .fontWeight(.bold)

                Text(caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.14))

            Divider()

            content
                .padding(8)
        }
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        }
    }
}

/// Explains one header whose effect can't be read off the header text — either
/// it breaks the mapped response, or the server replaces it — and offers the
/// one thing that resolves it.
private struct HeaderNoteView: View {

    let note: LocalMapViewModel.HeaderNote
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(note.line)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(note.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button("Remove", action: remove)
                .buttonStyle(.link)
                .help("Delete this header from the rule")
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var icon: String {
        switch note.kind {
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch note.kind {
        case .warning: .orange
        case .info: .secondary
        }
    }
}

private extension View {
    /// Marks a code editor as an input: without a border it bleeds into the
    /// card it sits on.
    func editorFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            }
    }
}

/// One rule in the left pane. The top line identifies the rule the way the
/// matcher sees it — priority, method, url — and the bottom line says what it
/// would serve, so the list answers "which rule is doing this?" on its own.
private struct MapRuleRow: View {

    static let minRowHeight: CGFloat = 36
    /// Enough for a long url with a query string; past this the tail is elided
    /// and the tooltip carries the rest.
    private static let maxUrlLines = 3
    private static let badgeWidth: CGFloat = 34
    /// badge and method columns plus their spacing, so the summary line starts
    /// under the url
    private static let urlIndent: CGFloat = badgeWidth + 6 + 46 + 6

    let rule: MapLocalObject
    let priority: Int
    /// priority of the earlier rule that swallows this one's traffic, if any
    let shadowedBy: Int?
    @Binding var enabled: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .controlSize(.mini)
                .help(enabled ? "Rule is active" : "Rule is off")

            handle

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    kindBadge

                    Text(rule.matchesAnyMethod ? "ANY" : rule.method)
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)

                    urlLabel
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if rule.kind == .mapResponse {
                        statusPill
                    }
                }

                subtitle
                    .padding(.leading, Self.urlIndent)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: Self.minRowHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(enabled ? 1 : 0.5)
    }

    /// The grip takes over the priority number's slot on hover: it appears
    /// exactly where the number it changes is, and the row never reflows.
    private var handle: some View {
        ZStack {
            Text("\(priority)")
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 0 : 1)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .opacity(isHovering ? 1 : 0)
        }
        .frame(width: 16)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .help("Rule \(priority) — drag to change which rule matches first")
    }

    /// Which of the two things the rule does, on every row — the rest of the
    /// row (status pill, summary) means something different per kind, so this
    /// has to be readable first. It carries its own fill and white text, so it
    /// keeps its contrast on a selected row in either appearance.
    private var kindBadge: some View {
        Text(rule.kind.badge)
            .foregroundStyle(.white)
            .frame(width: Self.badgeWidth)
            .padding(.vertical, 1)
            .background(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(rule.kind.title)
    }

    private var badgeColor: Color {
        switch rule.kind {
        case .mapResponse: .blue
        case .modifyRequest: .purple
        }
    }

    @ViewBuilder
    private var urlLabel: some View {
        if rule.matchesNoUrl {
            Text("no url")
                .italic()
                .foregroundStyle(.orange)
                .help("An empty url matches nothing — use * for every url")
        } else if rule.matchesAnyUrl {
            Text("every url")
                .italic()
                .foregroundStyle(.tertiary)
        } else {
            Text(rule.subUrl)
                .lineLimit(1...Self.maxUrlLines)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .help(rule.subUrl)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Utils.getStatusColor(rule.status))
                .frame(width: 7, height: 7)
            Text(rule.isValidStatus ? rule.statusCode : "—")
        }
        .help(Utils.getCommonDescription(httpStatusCode: rule.status) ?? "Not a status code")
    }

    @ViewBuilder
    private var subtitle: some View {
        if rule.matchesNoUrl {
            Label("never fires — no url to match on", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let shadowedBy {
            Label("never fires — rule \(shadowedBy) matches first", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var summary: String {
        var parts = [String]()

        switch rule.kind {
        case .mapResponse:
            switch rule.headerCount {
            case 0: parts.append("no headers")
            case 1: parts.append("1 header")
            case let count: parts.append("\(count) headers")
            }

            parts.append(
                rule.bodyByteCount == 0
                ? "empty body"
                : ByteCountFormatter.string(fromByteCount: Int64(rule.bodyByteCount), countStyle: .file)
            )

        case .modifyRequest:
            switch (rule.reqQueryCount, rule.reqHeaderCount) {
            case (0, 0): parts.append("nothing set")
            case let (params, 0): parts.append("sets \(params) param\(params == 1 ? "" : "s")")
            case let (0, headers): parts.append("sets \(headers) header\(headers == 1 ? "" : "s")")
            case let (params, headers): parts.append("sets \(params) param\(params == 1 ? "" : "s"), \(headers) header\(headers == 1 ? "" : "s")")
            }

            parts.append(
                rule.reqBodyByteCount == 0
                ? "body unchanged"
                : "body \(ByteCountFormatter.string(fromByteCount: Int64(rule.reqBodyByteCount), countStyle: .file))"
            )
        }

        switch (rule.hitCount, enabled) {
        case (0, true): parts.append("never matched")
        case (0, false): break
        case (1, _): parts.append("1 hit")
        case let (count, _): parts.append("\(count) hits")
        }

        return parts.joined(separator: " · ")
    }
}

#Preview {
    LocalMapView()
}
