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
    @State private var selected: String?
    
    var body: some View {
        NavigationSplitView {
            if let items = viewm.list {
                Table(items, selection: $selected) {
                    TableColumn("Method", content: { val in
                        Text("\(val.method)")
                    })
                    
                    TableColumn("Status", content: { val in
                        Text("\(val.statusCode)")
                    })
                    
                    TableColumn("URL", content: { val in
                        Text("\(val.url)")
                    })
                }
            } else {
                Text("Empty")
            }
        } detail: {
            VStack(alignment: .leading) {
                if let item = viewm.fetch(taskId: selected) {
                    List {
                        Section("URL") {
                            Text(item.url)
                        }
                        
                        Section("Method") {
                            Text(item.method)
                        }
                        
                        Section("Request headers") {
                            let keys = item.reqHeaders.keys
                            ForEach(keys.indices) { i in
                                Text("\(keys[i]): \(item.reqHeaders[keys[i]] ?? "")")
                            }
                        }
                        
                        Section("Status") {
                            Text("\(item.statusCode)")
                        }
                        
                        Section("Response headers") {
                            let keys = item.resHeaders.keys
                            ForEach(keys.indices) { i in
                                Text("\(keys[i]): \(item.resHeaders[keys[i]] ?? "")")
                            }
                        }
                    }
                    .monospaced()
                } else {
                    Text("Select an item")
                }
            }
            .navigationTitle("Details")
        }
    }
}

#Preview {
    ContentView()
}
