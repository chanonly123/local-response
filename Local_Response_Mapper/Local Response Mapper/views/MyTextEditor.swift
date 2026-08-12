import SwiftUI
import CodeEditor

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeEditor.Language
    let theme: CodeEditor.ThemeName
    let flags: CodeEditor.Flags
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    /// Character offsets, not `String.Index`. An index belongs to the string it
    /// was made from: keeping one across an edit — or across a switch to
    /// another rule, which hands this same view a different source — and
    /// converting it against the new string traps inside `NSRange(_:in:)`.
    /// Offsets survive that, and clamp to whatever the source is now.
    @State private var selection: Range<Int> = 0..<0
    @State private var matches: [Range<Int>] = []
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
                selection: selectionBinding,
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

    /// Translates the stored offsets against whatever the source is right now,
    /// so a selection left over from a longer text can't reach past the end of
    /// a shorter one.
    private var selectionBinding: Binding<Range<String.Index>> {
        Binding {
            Self.range(of: selection, in: source)
        } set: { new in
            selection = Self.offsets(of: new, in: source)
        }
    }

    private static func range(of offsets: Range<Int>, in text: String) -> Range<String.Index> {
        let count = text.count
        let lower = min(max(0, offsets.lowerBound), count)
        let upper = min(max(lower, offsets.upperBound), count)
        let start = text.index(text.startIndex, offsetBy: lower)
        return start..<text.index(text.startIndex, offsetBy: upper)
    }

    private static func offsets(of range: Range<String.Index>, in text: String) -> Range<Int> {
        // Comparing indices only compares their offsets, so this is safe even
        // when they came from another string — walking to them would not be.
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return 0..<0
        }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        return lower..<text.distance(from: text.startIndex, to: range.upperBound)
    }

    private func onChangeFindString() {
        let final = findString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            matches = []
            selection = 0..<0
            return
        }
        // Searched with `.caseInsensitive` rather than over `source.lowercased()`:
        // that is a separate string, and its ranges do not address this one.
        let options: String.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
        var found = [Range<Int>]()
        var start = source.startIndex
        while start < source.endIndex,
              let match = source.range(of: final, options: options, range: start..<source.endIndex) {
            found.append(Self.offsets(of: match, in: source))
            start = match.upperBound > match.lowerBound
                ? match.upperBound
                : source.index(after: match.lowerBound)
        }
        matches = found
        selection = found.first ?? 0..<0
        selectedFindIndex = found.isEmpty ? 0 : 1
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
