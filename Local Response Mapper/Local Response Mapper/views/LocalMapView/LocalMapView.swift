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
                        Toggle("", isOn: viewm.getSetValue(val.id, keyPath: \.enable))
                    })
                    .width(min: 50, ideal: 50, max: 80)

                    TableColumn("Method (match)", content: { val in
                        Picker("", selection: viewm.getSetValue(val.id, keyPath: \.method)) {
                            ForEach(viewm.httpMethods, id: \.self) {
                                Text($0)
                            }
                        }
                    })
                    .width(min: 100, ideal: 100, max: 150)

                    TableColumn("URL (contains)", content: { val in
                        TextField("", text: viewm.getSetValue(val.id, keyPath: \.subUrl))
                            .truncationMode(.head)
                            .help(val.subUrl)
                    })
                    .width(min: 50, ideal: 200)
                }
                .frame(minWidth: 300)
                .font(.system(size: Constants.tableFontSize))

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
                Text("id: \(item.id)")
                VStack(alignment: .leading, spacing: 4) {

                    HStack {
                        Text("Status")

                        Spacer()

                        if viewm.isValidStatus(item) {
                            Text("(valid Status)")
                                .foregroundStyle(.green)
                        } else {
                            Text("(invalid Status)")
                                .foregroundStyle(.red)
                        }
                    }
                    TextField("", text: viewm.getSetValue(item.id, keyPath: \.statusCode))
                        .overlay(alignment: .trailing) {
                            Text(Utils.getCommonDescription(httpStatusCode: Int(item.status)) ?? "")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }

                    Text("Response Headers")
                    CodeEditor(
                        source: viewm.getSetValue(item.id, keyPath: \.resHeaders),
                        language: .yaml,
                        theme: theme,
                        flags: [.editable, .selectable]
                    )
                    .frame(maxHeight: 100)
                    .id(item.id)

                    HStack {
                        Text("Response String")

                        Button {
                            viewm.formatJsonBody()
                        } label: {
                            Text("Format JSON")
                        }

                        Spacer()

                        if viewm.isValidResponseJSON(item) {
                            Text("(valid JSON)")
                                .foregroundStyle(.green)
                        } else {
                            Text("(invalid JSON)")
                                .foregroundStyle(.red)
                        }
                    }
                    CodeEditor(
                        source: viewm.getSetValue(item.id, keyPath: \.resString),
                        language: .json,
                        theme: theme,
                        flags: [.editable, .selectable]
                    )
                    .frame(maxHeight: .infinity)
                    .id(item.id)
                }
                .padding(4)
            } else {
                Image(systemName: "tray")
            }
        }
    }

    var theme: CodeEditor.ThemeName {
        .init(rawValue: Utils.getThemeName(colorScheme: myColorScheme.value))
    }
}

#Preview {
    LocalMapView()
}
