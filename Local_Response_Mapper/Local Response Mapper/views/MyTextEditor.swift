import SwiftUI
import CodeEditor

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeEditor.Language
    let theme: CodeEditor.ThemeName
    let flags: CodeEditor.Flags
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    /// The caret exactly as the text view last reported it, handed straight back
    /// on the next update.
    ///
    /// The text view reports a moved caret *before* it reports the edit that
    /// moved it, so during that gap the caret addresses one more character than
    /// `source` has. Measuring it against `source` there put it out of range —
    /// and the editor then pushed that measurement back, which is what sent the
    /// cursor to the top of the field on every keypress. Held as the range it
    /// came as, it is only ever compared, never converted, so the round trip
    /// leaves it where the user put it.
    @State private var caret: Range<String.Index>?

    /// A caret this view is asking for — a find hit. Cleared as soon as the text
    /// view reports back, so typing is never fighting a position from before.
    ///
    /// Character offsets, not `String.Index`: an index belongs to the string it
    /// was made from, and converting a kept one against a later string traps
    /// inside `NSRange(_:in:)`.
    @State private var pending: Range<Int>?

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

    /// Reports the caret the text view already has, so nothing is pushed into it
    /// unless this view is the one moving it.
    private var selectionBinding: Binding<Range<String.Index>> {
        Binding {
            if let pending {
                return Self.range(of: pending, in: source)
            }
            if let caret, Self.isValid(caret, in: source) {
                return caret
            }
            // No caret yet, or the text was replaced under it — the end is the
            // one position that exists in every string.
            let start = caret == nil ? source.startIndex : source.endIndex
            return start..<start
        } set: { new in
            caret = new
            pending = nil
        }
    }

    /// Bounds check only: comparing indices compares their offsets, which is
    /// safe even for indices made from another string — walking to them is not.
    private static func isValid(_ range: Range<String.Index>, in text: String) -> Bool {
        range.lowerBound >= text.startIndex && range.upperBound <= text.endIndex
    }

    /// Where the caret is in `source`, when that can be answered without
    /// walking past its end.
    private var caretOffsets: Range<Int>? {
        guard let caret, Self.isValid(caret, in: source) else { return nil }
        return Self.offsets(of: caret, in: source)
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
            pending = nil
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
        pending = found.first
        selectedFindIndex = found.isEmpty ? 0 : 1
    }

    private func jumpToTextPressEnter(next: Bool) {
        guard let first = matches.first else { return }

        // The hit the caret is sitting on — the one this steps off from. After
        // a jump the caret is reported back, so this is where it lands even
        // once `pending` has cleared.
        let current = pending ?? caretOffsets

        if let current, let index = matches.firstIndex(of: current) {
            var new = (index + (next ? 1 : -1))
            if new < 0 { new = matches.count - 1 }
            let i = new % matches.count
            pending = matches[i]
            selectedFindIndex = i + 1
        } else {
            pending = first
            selectedFindIndex = 1
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
