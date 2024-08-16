//
//  ContentView.swift
//  Local Response Mapper
//
//  Created by Chandan on 14/08/24.
//

import SwiftUI
import RealmSwift

struct ContentView: View {
    
    @StateObject var viewm = ContentViewModel()
    
    var body: some View {
        NavigationSplitView {
            VStack {
                if let items = viewm.list {
                    Table(items, selection: $viewm.selected) {
                        TableColumn("Method", content: { val in
                            Text("\(val.method)")
                        })
                        .width(ideal: 70)
                        
                        TableColumn("Status", content: { val in
                            Text("\(val.statusCode)")
                        })
                        .width(ideal: 50)
                        
                        TableColumn("URL", content: { val in
                            Text("\(val.url)")
                        })
                        .width(ideal: 200)
                    }
                    .frame(minWidth: 200)
                } else {
                    Text("Empty")
                }
            }
            .frame(minWidth: 200)
        } detail: {
            VStack(alignment: .leading) {
                if let item = viewm.fetch(taskId: viewm.selected) {
                    List {
                        if viewm.selectedTab == .req {
                            Section("URL") {
                                Text(item.url)
                            }
                            
                            Section("Method") {
                                Text(item.method)
                            }
                            
                            Section("Request headers") {
                                Text(viewm.dictToString(item: item.reqHeaders))
                            }
                        } else if viewm.selectedTab == .res {
                            
                            Section("Status") {
                                Text("\(item.statusCode)")
                            }
                            
                            Section("Response headers") {
                                Text(viewm.dictToString(item: item.resHeaders))
                            }
                        }
                    }
                    .monospaced()
                    
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
                            .padding(.bottom, 6)
                            .padding(.top, -2)
                            Spacer()
                        }
                    
                } else {
                    Text("Select an item")
                }
            }
            .frame(minWidth: 200)
            .navigationTitle("Details")
            .toolbar {
                Button {
                    
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
