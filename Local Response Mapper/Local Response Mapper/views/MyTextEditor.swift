import SwiftUI
import CodeEditor

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeEditor.Language
    let theme: CodeEditor.ThemeName
    let flags: CodeEditor.Flags

    @State private var selection: Range<String.Index> = "".startIndex..<"".endIndex
    @State private var matches: [Range<String.Index>] = []
    @State private var findString: String = ""
    @State private var showingFind: Bool = false
    @State private var findCaseSensitive: Bool = true
    @State private var selectedFindIndex: Int = 0
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showingFind {
                HStack {
                    TextField("Find", text: $findString)
                        .textFieldStyle(.plain)
                        .focusable()
                        .focused($findFocused)
                    Spacer()
                    if !matches.isEmpty {
                        Text("\(selectedFindIndex) of \(matches.count)")
                            .foregroundStyle(.placeholder)
                    }
                    Button("Done") {
                        showingFind = false
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(lineWidth: 0.2)
                }
            }
            CodeEditor(
                source: $source,
                selection: $selection,
                language: language,
                theme: theme,
                fontSize: .constant(Constants.fontSize),
                flags: flags
            )

        }
        .onKeyPress(action: { e in
            if e.key == .init("f") && e.modifiers.contains(.command) {
                showingFind = true
                findFocused = true
                return .handled
            }
            return .ignored
        })
        .onChange(of: findString) { oldValue, newValue in
            onChangeFindString()
        }
        .onKeyPress(.return, action: {
            if findFocused {
                selectNextFindText()
                return .handled
            }
            return .ignored
        })
    }

    private func onChangeFindString() {
        let final = findString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            matches = []
            selection = "".startIndex..<"".endIndex
            return
        }
        matches = source.ranges(of: final)
        selection = matches.first ?? "".startIndex..<"".endIndex
        if !matches.isEmpty { selectedFindIndex = 1 }
    }

    private func selectNextFindText() {
        if let first = matches.first {
            if let index = matches.firstIndex(of: selection) {
                let i = (index + 1) % matches.count
                selection = matches[i]
                selectedFindIndex = i + 1
            } else {
                selection = first
            }
        }
    }
}

#if DEBUG
struct MyTextEditorPreview: View {

    @State private var source = "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book."

    var body: some View {
        MyTextEditor(
            source: $source,
            language: .json,
            theme: .default,
            flags: [.editable, .selectable]
        )
    }
}

#Preview {
    MyTextEditorPreview()
}
#endif
