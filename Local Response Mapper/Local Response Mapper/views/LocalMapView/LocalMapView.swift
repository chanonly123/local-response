//
//  LocalMapView.swift
//  Local Response Mapper
//
//  Created by Chandan on 17/08/24.
//

import SwiftUI

struct LocalMapView: View {

    @StateObject private var viewm = LocalMapViewModel()

    var body: some View {
        GeometryReader { geo in

            HSplitView {
                leftView
                    .frame(minWidth: geo.size.width/3)
                    .frame(height: geo.size.height)

                rightView
                    .frame(minWidth: geo.size.width/3)
                    .frame(height: geo.size.height)
                    .navigationTitle("Map Local")
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .monospaced()
    }

    var leftView: some View {
        VStack(spacing: 0) {
            if let items = viewm.list {
                Table(items, selection: $viewm.selected) {
                    TableColumn("Enable", content: { val in
                        Toggle("", isOn: viewm.getSetValue(val, keyPath: \.enable))
                    })
                    .width(min: 50, ideal: 50, max: 80)

                    TableColumn("Method (match)", content: { val in
                        Picker("", selection: viewm.getSetValue(val, keyPath: \.method)) {
                            ForEach(viewm.httpMethods, id: \.self) {
                                Text($0)
                            }
                        }
                    })
                    .width(min: 100, ideal: 100, max: 150)

                    TableColumn("URL (contains)", content: { val in
                        TextField("", text: viewm.getSetValue(val, keyPath: \.subUrl))
                            .truncationMode(.head)
                    })
                    .width(min: 50, ideal: 200)
                }
                .frame(minWidth: 300)

                HStack(spacing: 4) {
                    Button {
                        viewm.addNew()
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        viewm.deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(viewm.selected == nil)

                    Spacer()
                }
                .padding(.leading, 4)

            } else {
                Image(systemName: "tray")
            }
        }
    }

    var rightView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = viewm.getSelectedItem() {
                VStack(alignment: .leading, spacing: 4) {

                    HStack {
                        Text("Status")
                        (viewm.isValidStatus(item) ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .clipShape(Circle())
                    }
                    TextField("", text: viewm.getSetValue(item, keyPath: \.statusCode))

                    Text("Response Headers")
                    TextEditor(text: viewm.getSetResponseHeaders(item))
                        .frame(maxHeight: 100)

                    HStack {
                        Text("Response String")
                        (viewm.isValidResponseJSON(item) ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .clipShape(Circle())
                        Button {
                            viewm.formatJsonBody()
                        } label: {
                            Text("Format JSON")
                        }
                    }
                    TextEditor(text: viewm.getSetValue(item, keyPath: \.resString))
                        .frame(maxHeight: .infinity)
                }
                .padding(4)
            } else {
                Image(systemName: "tray")
            }
        }
    }

}

#Preview {
    LocalMapView()
}
