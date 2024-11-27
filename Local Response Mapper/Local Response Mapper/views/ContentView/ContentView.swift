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

    @StateObject private var myColorScheme = ColorSchemeViewModel.shared
    @StateObject private var viewm = ContentViewModel()
    @StateObject private var server = LocalServer()
    @Environment(\.openWindow) private var openWindow

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

            Button {
                openLocalMapWindow()
            } label: {
                Text("Map Local")
            }

            Button {
                viewm.clearAll()
            } label: {
                Text("Clear")
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

                Table(of: URLTaskObject.self, selection: $viewm.selected) {
                    TableColumn("BundleID", content: { val in
                        Text(val.bundleID)
                            .truncationMode(.head)
                            .help(val.bundleID)
                    })
                    .width(min: 50, ideal: 50, max: 200)

                    TableColumn("Method", content: { val in
                        Text("\(val.method)")
                            .help(val.method)
                    })
                    .width(min: 50, ideal: 50, max: 100)

                    TableColumn("Status", content: { val in
                        HStack {
                            Circle().fill(Utils.getStatusColor(val.statusCode))
                                .frame(width: 10, height: 10)
                                .padding(.top, 1)
                            Text("\(val.statusCode > 0 ? "\(val.statusCode)" : "")")
                        }
                    })
                    .width(min: 50, ideal: 50, max: 100)

                    TableColumn("URL", content: { val in
                        Text("\(val.url)")
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
                .font(.system(size: Constants.tableFontSize))


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
                    List {
                        Section("BundleID") {
                            Text(item.bundleID)
                        }

                        Section("Host") {
                            Text(item.getHost)
                        }

                        Section("Path") {
                            Text(item.getPath)
                        }

                        Section("Method") {
                            Text(Utils.highlightYaml(item.method))
                        }

                        Section("Query Params") {
                            Text(item.getQuery)
                        }

                        Section("Request headers") {
                            Text(item.getReqHeaders)
                        }

                        Section("Request Body") {
                            Text(item.getResBody)
                        }
                    }
                    .textSelection(.enabled)
                case .res:
                    List {
                        Section("Status") {
                            HStack {
                                Text(Utils.highlightYaml("\(item.statusCode)"))
                                Spacer()
                                Text("\(Utils.getCommonDescription(httpStatusCode: item.statusCode) ?? "")")
                                    .foregroundColor(.gray)
                            }
                        }

                        Section("Response headers") {
                            Text(item.getResHeaders)
                        }
                    }
                    .textSelection(.enabled)
                case .resString:
                    CodeEditor(source: item.responseString, language: .json, theme: theme, flags: [.selectable])
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
        return .init(rawValue: Utils.getThemeName(colorScheme: myColorScheme.value))
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
