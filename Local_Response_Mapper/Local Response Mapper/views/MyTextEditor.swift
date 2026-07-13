import SwiftUI
import CodeEditor

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeEditor.Language
    let theme: CodeEditor.ThemeName
    let flags: CodeEditor.Flags
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    @State private var selection: Range<String.Index> = "".startIndex..<"".endIndex
    @State private var matches: [Range<String.Index>] = []
    @State private var findString: String = ""
    @State private var showingFind: Bool
    @State private var findCaseSensitive: Bool = false
    @State private var selectedFindIndex: Int = 0
    @FocusState private var findFocused: Bool

    init(
        source: Binding<String>,
        language: CodeEditor.Language,
        theme: CodeEditor.ThemeName,
        flags: CodeEditor.Flags,
        showingFind: Bool = false
    ) {
        self._source = source
        self.language = language
        self.theme = theme
        self.flags = flags
        self._showingFind = State(wrappedValue: showingFind)
        self.fontSize = fontSize
    }

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
                    Button("Aa") {
                        findCaseSensitive.toggle()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .buttonStyle(.link)
                    .foregroundStyle(findCaseSensitive ? Color.blue : Color.gray.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.background)
                    )
                    Button("Done") {
                        showingFind = false
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .buttonStyle(.link)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.background)
                    )
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
                fontSize: .constant(fontSize),
                flags: flags
            )

        }
        .onKeyPress(action: { e in
            if e.key == .return {
                if findFocused {
                    jumpToTextPressEnter(next: !e.modifiers.contains(.shift))
                    return .handled
                }
            } else if e.key == .init("f") && e.modifiers.contains(.command) {
                showingFind = true
                findFocused = true
                return .handled
            } else if e.key == .init("=") && e.modifiers.contains(.command) {
                fontSize = min(20, fontSize + 1)
                return .handled
            } else if e.key == .init("-") && e.modifiers.contains(.command) {
                fontSize = max(8, fontSize - 1)
                return .handled
            }
            return .ignored
        })
        .onChange(of: findString) { _, _ in
            onChangeFindString()
        }
        .onChange(of: findFocused) { _, newValue in
            if newValue {
                onChangeFindString()
            }
        }
        .onChange(of: findCaseSensitive) { _, newValue in
            onChangeFindString()
        }
    }

    private func onChangeFindString() {
        let final = findString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            matches = []
            selection = "".startIndex..<"".endIndex
            return
        }
        if findCaseSensitive {
            matches = source.ranges(of: final)
        } else {
            matches = source.lowercased().ranges(of: final.lowercased())
        }
        selection = matches.first ?? "".startIndex..<"".endIndex
        if !matches.isEmpty { selectedFindIndex = 1 }
    }

    private func jumpToTextPressEnter(next: Bool) {
        if let first = matches.first {
            if let index = matches.firstIndex(of: selection) {
                var new = (index + (next ? 1 : -1))
                if new < 0 { new = matches.count - 1 }
                let i = new % matches.count
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
            flags: [.editable, .selectable],
            showingFind: true
        )
    }
}

#Preview {
    MyTextEditorPreview()
}
#endif
