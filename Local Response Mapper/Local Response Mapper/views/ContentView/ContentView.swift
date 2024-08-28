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
    
    @StateObject var viewm = ContentViewModel()
    @StateObject private var server = LocalServer()
    @Environment(\.openWindow) var openWindow
    
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
                        .navigationTitle("Local Response Mapper")
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            
            HStack {
                Spacer()
                
                Button {
                    if server.isListening == true {
                        Utils.copyToClipboard("\(server.getFullListeningAddress)")
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
                            Text("Listening \(server.getFullListeningAddress)")
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
        }
        .toolbar {
            
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
        
    }
    
    var leftView: some View {
        VStack(spacing: 0) {
            if let items = viewm.list {
                
                Table(of: URLTaskObject.self, selection: $viewm.selected) {
                    TableColumn("Method", content: { val in
                        Text("\(val.method)")
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
                            }
                    }
                }
                .frame(minWidth: 300)
                
                
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
                        Button {
                            viewm.selectedTab = .req
                        } label: {
                            Text("Request")
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .background(viewm.getTabButtonBackground(tab: .req))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            viewm.selectedTab = .res
                        } label: {
                            Text("Response")
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .background(viewm.getTabButtonBackground(tab: .res))
                            
                        }
                        .buttonStyle(.plain)
                        
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                .padding(2)
                
                
                List {
                    if viewm.selectedTab == .req {
                        Section("Host") {
                            Text(Utils.getHost(item.url) ?? "")
                        }
                        
                        Section("Path") {
                            Text(Utils.getPath(item.url) ?? "")
                        }
                        
                        Section("Method") {
                            Text(item.method)
                        }

                        Section("Query Params") {
                            Text(Utils.dictToString(item: Utils.getQueryParams(item.url)))
                        }

                        Section("Request headers") {
                            Text(Utils.dictToString(item: item.reqHeaders))
                        }
                        
                        Section("Request Body") {
                            Text(item.body)
                        }
                    } else if viewm.selectedTab == .res {
                        
                        Section("Status") {
                            Text("\(item.statusCode)")
                        }
                        
                        Section("Response headers") {
                            Text(Utils.dictToString(item: item.resHeaders))
                        }
                        
                        Section("Response String") {
                            CodeEditor(source: item.responseString, language: .json, theme: .pojoaque, disableScroll: true)
                        }
                    }
                }
                .textSelection(.enabled)
                
                
            } else {
                Image(systemName: "tray")
            }
        }
    }
    
    func openLocalMapWindow() {
        openWindow(id: "map-local-view")
    }
}

#Preview {
    ContentView()
}
