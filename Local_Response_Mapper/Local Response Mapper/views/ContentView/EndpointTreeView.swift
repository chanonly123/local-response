//
//  EndpointTreeView.swift
//  Local Response Mapper
//
//  Created by Chandan on 08/08/26.
//

import SwiftUI

enum LeftViewMode: String, CaseIterable, Identifiable {
    case structure = "Structure", sequence = "Sequence"

    var id: String { rawValue }
}

/// Plain snapshot of a recorded call, so tree nodes never hold on to a realm
/// object that may get invalidated while the tree is on screen.
struct EndpointRequest {
    let taskId: String
    let method: String
    let statusCode: Int
    let date: Double
    let isEdited: Bool
    let isRequestEdited: Bool
    /// last path component plus the query, e.g. `raw?json=true`
    let pathLabel: String

    init(_ obj: URLTaskObject) {
        taskId = obj.taskId
        method = obj.method
        statusCode = obj.statusCode
        date = obj.date
        isEdited = obj.isEdited
        isRequestEdited = obj.isRequestEdited
        pathLabel = EndpointRequest.pathLabel(obj.url)
    }

    var timeString: String {
        EndpointRequest.timeFormatter.string(from: Date(timeIntervalSince1970: date))
    }

    /// `URLComponents` hands back both parts already percent-decoded.
    private static func pathLabel(_ url: String) -> String {
        guard let comps = URLComponents(string: url) else { return url }
        let name = comps.path.split(separator: "/").last.map(String.init) ?? "/"
        guard let query = comps.query, !query.isEmpty else { return name }
        return "\(name)?\(query)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

final class EndpointNode: Identifiable {

    enum Kind { case host, folder, endpoint, request }

    let id: String
    let name: String
    let kind: Kind
    /// `nil` for rows that cannot be expanded
    let children: [EndpointNode]?
    /// set on `endpoint` (single call) and `request` rows
    let request: EndpointRequest?
    let requestCount: Int

    init(id: String, name: String, kind: Kind, children: [EndpointNode]?, request: EndpointRequest?, requestCount: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.children = children
        self.request = request
        self.requestCount = requestCount
    }
}

enum EndpointTree {

    /// Groups the recorded calls into `host -> path component -> ... -> endpoint`.
    /// An endpoint hit more than once becomes a folder holding one row per call.
    static func build<C: Sequence>(from items: C) -> [EndpointNode] where C.Element == URLTaskObject {
        var hosts = [String: Builder]()
        for item in items {
            let host = hostLabel(item.url)
            let builder = hosts[host] ?? {
                let new = Builder(name: host)
                hosts[host] = new
                return new
            }()
            var node = builder
            for component in pathComponents(item.url) {
                node = node.child(component)
            }
            if node === builder {
                node = builder.child("/")
            }
            node.requests.append(EndpointRequest(item))
        }
        return hosts.keys.sorted().map { makeNode(hosts[$0]!, parentId: "", kind: .host) }
    }

    // MARK: -

    private final class Builder {
        let name: String
        var children = [String: Builder]()
        var requests = [EndpointRequest]()

        init(name: String) {
            self.name = name
        }

        func child(_ name: String) -> Builder {
            if let existing = children[name] { return existing }
            let new = Builder(name: name)
            children[name] = new
            return new
        }
    }

    private static func makeNode(_ builder: Builder, parentId: String, kind: EndpointNode.Kind) -> EndpointNode {
        let id = parentId.isEmpty ? builder.name : "\(parentId)/\(builder.name)"
        let folders = builder.children.keys.sorted().map {
            makeNode(builder.children[$0]!, parentId: id, kind: .folder)
        }
        let requests = builder.requests.sorted { $0.date < $1.date }
        let count = folders.reduce(requests.count) { $0 + $1.requestCount }
        let name = builder.name.removingPercentEncoding ?? builder.name

        // a single call with nothing below it is shown as one selectable row
        if folders.isEmpty, requests.count == 1 {
            return EndpointNode(id: requests[0].taskId, name: requests[0].pathLabel, kind: .endpoint, children: nil, request: requests[0], requestCount: 1)
        }

        let callRows = requests.map {
            EndpointNode(id: $0.taskId, name: $0.pathLabel, kind: .request, children: nil, request: $0, requestCount: 1)
        }
        return EndpointNode(
            id: id,
            name: name,
            kind: kind,
            children: folders + callRows,
            request: nil,
            requestCount: count
        )
    }

    private static func hostLabel(_ url: String) -> String {
        guard let comps = URLComponents(string: url), let host = comps.host else {
            return url
        }
        var label = comps.scheme.map { "\($0)://" } ?? ""
        label += host
        if let port = comps.port {
            label += ":\(port)"
        }
        return label
    }

    private static func pathComponents(_ url: String) -> [String] {
        guard let path = URL(string: url)?.path() else { return [] }
        return path.split(separator: "/").map(String.init)
    }
}

// MARK: - Views

struct EndpointTreeView<Menu: View>: View {

    let nodes: [EndpointNode]
    @Binding var selection: Set<String>
    @Binding var expanded: Set<String>
    /// built by the owner from a taskId, so the tree shares the table's menu
    @ViewBuilder let contextMenu: (String) -> Menu

    var body: some View {
        List(selection: $selection) {
            ForEach(nodes) { node in
                EndpointNodeView(node: node, expanded: $expanded, contextMenu: contextMenu)
            }
        }
        .listStyle(.plain)
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, EndpointRowView.rowHeight)
    }
}

private struct EndpointNodeView<Menu: View>: View {

    let node: EndpointNode
    @Binding var expanded: Set<String>
    @ViewBuilder let contextMenu: (String) -> Menu

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children) { child in
                    EndpointNodeView(node: child, expanded: $expanded, contextMenu: contextMenu)
                }
            } label: {
                EndpointRowView(node: node)
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded.wrappedValue.toggle() }
            }
        } else {
            EndpointRowView(node: node)
                .tag(node.id)
                .contextMenu {
                    if let taskId = node.request?.taskId {
                        contextMenu(taskId)
                    }
                }
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(node.id) },
            set: { open in
                if open {
                    expanded.insert(node.id)
                } else {
                    expanded.remove(node.id)
                }
            }
        )
    }
}

private struct EndpointRowView: View {

    static let rowHeight: CGFloat = 16

    let node: EndpointNode

    var body: some View {
        HStack(spacing: 3) {
            icon
                .frame(width: 11)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(helpText)

            if let request = node.request {
                Text(request.method)
                    .foregroundColor(.gray)
                if request.isRequestEdited {
                    // Same badge treatment as `edited`, in the colour the rule
                    // list gives request rules, so the two are told apart at a
                    // glance: this one changed what went out, not what came
                    // back.
                    badge("req edited", background: .purple, foreground: .white)
                }
                if request.isEdited {
                    // A plain tint has four backgrounds to stay legible on —
                    // light, dark, and the selection highlight in each — so
                    // this carries its own: black on yellow reads on all of
                    // them, and reads as a warning badge rather than a label.
                    badge("edited", background: .yellow, foreground: .black)
                }
            } else if node.requestCount > 1 {
                Text("(\(node.requestCount))")
                    .foregroundColor(.gray)
            }
        }
        .frame(height: EndpointRowView.rowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private func badge(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .foregroundStyle(foreground)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(background)
            )
    }

    /// repeat calls to one endpoint share a label, so the time tells them apart
    private var helpText: String {
        guard let request = node.request else { return node.name }
        return "\(node.name)\n\(request.timeString)"
    }

    @ViewBuilder
    private var icon: some View {
        switch node.kind {
        case .host:
            Image(systemName: "bolt.circle.fill")
                .imageScale(.small)
                .foregroundColor(.blue)
        case .folder:
            Image(systemName: "folder.fill")
                .imageScale(.small)
                .foregroundColor(.blue)
        case .endpoint, .request:
            Circle()
                .fill(Utils.getStatusColor(node.request?.statusCode ?? 0))
                .frame(width: 7, height: 7)
        }
    }
}
