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

    @State private var resHeaderSelection: Range<String.Index> = "".startIndex..<"".endIndex
    @State private var resHeaderAllMatches: [Range<String.Index>] = []
    @State private var resHeaderFilter: String = ""
    @FocusState private var resHeaderFocused: Bool

    @State private var resStringSelection: Range<String.Index> = "".startIndex..<"".endIndex
    @State private var resStringAllMatches: [Range<String.Index>] = []
    @State private var resStringFilter: String = ""
    @FocusState private var resStringFocused: Bool

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
        .font(.system(size: Constants.fontSize - 1))
        .monospaced()
        .toolbar {
            Button {
                viewm.clearAll()
            } label: {
                Text("Clear All")
            }
        }
    }

    var leftView: some View {
        VStack(spacing: 0) {
            if let items = viewm.list {
                Table(items, selection: $viewm.selected) {
                    TableColumn("Enable", content: { val in
                        Toggle("", isOn: viewm.getSetValue(val.id, keyPath: \.enable))
                    })
                    .width(min: 45, ideal: 45, max: 45)

                    TableColumn("Method (match)", content: { val in
                        Picker("", selection: viewm.getSetValue(val.id, keyPath: \.method)) {
                            ForEach(viewm.httpMethods, id: \.self) {
                                Text($0)
                                    .font(.system(size: Constants.fontSize - 1))
                            }
                        }
                    })
                    .width(min: 95, ideal: 95, max: 95)

                    TableColumn("URL (contains)", content: { val in
                        TextField("", text: viewm.getSetValue(val.id, keyPath: \.subUrl))
                            .truncationMode(.head)
                            .help(val.subUrl)
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

                        Spacer()

                        if viewm.isValidStatus(item) {
                            Text("Valid Status")
                                .foregroundStyle(.green)
                        } else {
                            Text("Invalid Status")
                                .foregroundStyle(.red)
                        }
                    }
                    TextField("", text: viewm.getSetValue(item.id, keyPath: \.statusCode))
                        .overlay(alignment: .trailing) {
                            Text(Utils.getCommonDescription(httpStatusCode: Int(item.status)) ?? "")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }

                    HStack {
                        Text("Response Headers")
                        Spacer()
                        if (item.resHeadersMap[Constants.contentEncodingKey] ?? "").isEmpty == false {
                            Text("Warning")
                                .foregroundStyle(.orange)
                                .help("Response header contains '\(Constants.contentEncodingKey)', mapping may not work.")
                        }
                    }

                    MyTextEditor(
                        source: viewm.getSetValue(item.id, keyPath: \.resHeaders),
                        language: .yaml,
                        theme: theme,
                        flags: [.editable, .selectable]
                    )
                    .frame(maxHeight: 100)
                    .id(item.id)

                    HStack {
                        Text("Response String")

                        Spacer()

                        Button {
                            viewm.formatJsonBody()
                        } label: {
                            Image(systemName: "list.bullet.indent")
                        }

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
