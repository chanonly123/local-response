//
//  ContentView.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import RealmSwift
import CodeEditor

struct ContentView: View {

    @StateObject private var localMapsViewm = LocalMapViewModel()
    @StateObject private var myColorScheme = ColorSchemeViewModel.shared
    @StateObject private var viewm = ContentViewModel()
    @StateObject private var server = LocalServer()
    @State private var autoScroll: Bool = true
    @State private var scrollToId: String?
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in

                HSplitView {
                    leftView
                        .frame(minWidth: geo.size.width/3)
                        .frame(height: geo.size.height)

                    rightView
                        .frame(minWidth: geo.size.width/3)
                        .frame(height: geo.size.height)
                        .navigationTitle("Local Response Mapper (\(viewm.getCurrentVersion() ?? ""))")
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            HStack {
                Button {
                    autoScroll.toggle()
                } label: {
                    HStack {
                        Circle().fill(autoScroll ? Color.green : Color.gray)
                            .frame(width: 10)
                        Text("Auto scroll")
                    }
                }

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
        }
        .font(.system(size: fontSize - 2))
        .monospaced()
        .showErrors(errors: viewm.errors)
        .onAppear {
            server.startServer()
            server.reloadLocalAddress()
            viewm.checkForNewVersion()
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
                Text("Map Local\(enabledCount == 0 ? "" : " (\(enabledCount))")")
            }

            Button {
                viewm.clearAll()
            } label: {
                Text("Clear All")
            }
        }
        .alert("New version available\n\(viewm.newVersion ?? "")", isPresented: $viewm.newVersionAlert) {
            viewm.getUpdateLink()
            Button("Cancel") { }
        }

    }

    var leftView: some View {
        VStack(spacing: 0) {
            if let items = viewm.list {

                ScrollViewReader { proxy in
                    Table(of: URLTaskObject.self, selection: $viewm.selected) {
                        TableColumn("BundleID", content: { val in
                            Text(val.bundleID)
                                .truncationMode(.head)
                                .help(val.bundleID)
                                .id(val.id)
                        })
                        .width(min: 50, ideal: 50, max: 200)

                        TableColumn("Method", content: { val in
                            Text("\(val.method)")
                                .help(val.method)
                        })
                        .width(min: 50, ideal: 50, max: 60)

                        TableColumn("Edited", content: { val in
                            Text("\(val.isEdited ? "Yes" : "-")")
                        })
                        .width(min: 45, ideal: 45, max: 60)

                        TableColumn("Status", content: { val in
                            HStack {
                                Circle().fill(Utils.getStatusColor(val.statusCode))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 1)
                                Text("\(val.statusCode > 0 ? "\(val.statusCode)" : "")")
                            }
                        })
                        .width(min: 50, ideal: 50, max: 60)

                        TableColumn("URL", content: { val in
                            Text("\(val.getPathString)")
                                .truncationMode(.head)
                                .help(val.url)
                        })
                        .width(min: 50, ideal: 200)

                    } rows: {
                        ForEach(items) { val in
                            TableRow(val)
                                .contextMenu {
                                    Button("Map local") {
                                        viewm.addNewMapLocal(obj: val)
                                        openLocalMapWindow()
                                    }
                                    Button("Copy URL") {
                                        viewm.copyValue(obj: val, keyPath: \.url)
                                    }
                                    Button("Copy Request Body") {
                                        viewm.copyValue(obj: val, keyPath: \.body)
                                    }
                                    Button("Copy Response String") {
                                        viewm.copyValue(obj: val, keyPath: \.responseString)
                                    }
                                    Button("Copy All") {
                                        viewm.copyAll(obj: val)
                                    }
                                    Button("Copy CURL") {
                                        viewm.toCurlCommand(obj: val)
                                    }
                                }
                        }
                    }
                    .frame(minWidth: 300)
                    .onChange(of: viewm.listCount) { val in
                        if autoScroll, let last = viewm.list?.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                TextField("Filter", text: $viewm.filter)
                    .textFieldStyle(.roundedBorder)
            } else {
                Image(systemName: "tray")
            }
        }
    }

    var rightView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = viewm.fetch(taskId: viewm.selected) {

                HStack {
                    Spacer()
                    HStack {
                        ForEach(ContentViewModel.TabType.allCases, id: \.self) { item in
                            Button {
                                viewm.selectedTab = item
                            } label: {
                                Text(item.rawValue)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                    .foregroundColor(viewm.getTabButtonTextColor(tab: item))
                            }
                            .setSelectedButtonStyle(selected: viewm.selectedTab == item)
                        }
                    }
                    Spacer()
                }
                .padding(2)

                switch viewm.selectedTab {
                case .req:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BundleID")
                                .underline()
                            Text(Utils.highlightYaml(item.bundleID))

                            Divider()

                            Text("Host")
                                .underline()
                            Text(item.getHost)

                            Divider()

                            Text("Path")
                                .underline()
                            Text(item.getPath)

                            Divider()

                            Text("Method")
                                .underline()
                            Text(Utils.highlightYaml(item.method))

                            Divider()

                            Text("Query Params")
                                .underline()
                            Text(item.getQuery)

                            Divider()

                            Text("Request headers")
                                .underline()
                            Text(item.getReqHeaders)

                            Divider()

                            Text("Request Body")
                                .underline()
                            Text(item.getReqBody)

                            Divider()

                            Text("Status")
                                .underline()
                            Text(Utils.highlightYaml("\(item.statusCode)")) + Text("    ") +
                            Text("\(Utils.getCommonDescription(httpStatusCode: item.statusCode) ?? "")")
                                .foregroundColor(.gray)

                            Divider()

                            Text("Response headers")
                                .underline()
                            Text(item.getResHeaders)
                        }
                        .padding()
                    }
                    .textSelection(.enabled)
                case .resString:
                    MyTextEditor(
                        source: .constant(item.responseString),
                        language: .json,
                        theme: theme,
                        flags: [.selectable]
                    )
                    .frame(maxHeight: .infinity)
                    .id(item.id)
                }
            } else {
                Image(systemName: "tray")
            }
        }
    }

    func openLocalMapWindow() {
        openWindow(id: "map-local-view")
    }

    var theme: CodeEditor.ThemeName {
        let theme = CodeEditor.ThemeName(rawValue: Utils.getThemeName(colorScheme: myColorScheme.value))

        return theme
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
