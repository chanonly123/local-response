import SwiftUI

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeEditor.Language
    let theme: CodeEditor.ThemeName
    let flags: CodeEditor.Flags
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    /// A caret this view is asking for — a find hit — and the only reason it
    /// ever pushes one.
    ///
    /// Cleared as soon as the text view reports back, or the text changes under
    /// it. While it is `nil` the editor is handed no selection binding at all,
    /// so nothing of ours can move a caret the user is typing with.
    ///
    /// Character offsets, not `String.Index`: an index belongs to the string it
    /// was made from, and converting a kept one against a later string traps
    /// inside `NSRange(_:in:)`.
    @State private var pending: Range<Int>?

    /// The language actually handed to the editor — see `HighlightBudget`.
    @State private var effectiveLanguage: CodeEditor.Language?

    @State private var matches: [FindHit] = []

    /// UTF-16 length of the text the hits were found in — the scale the ruler
    /// places its ticks on.
    @State private var matchesDocumentLength: Int = 0

    /// The search in flight, cancelled the moment another is asked for — a
    /// query is retyped a character at a time, and only the last one matters.
    @State private var searchTask: Task<Void, Never>?
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
            EditorBox(
                source: $source,
                // Attached only while this view is asking for a caret — a find
                // hit to jump to. Attached at any other time, the editor
                // compares what it holds against what this view last saw and
                // pushes the difference back, which lands on the caret of
                // somebody typing; and reporting the caret means a `@State`
                // write, and a view rebuild, for every character selected.
                selection: pending != nil ? selectionBinding : nil,
                language: effectiveLanguage,
                theme: theme,
                fontSize: fontSize,
                flags: flags
            )
            .equatable()
            // Only while the bar is up: the decorations paint into the text
            // view itself, so they have to come back off when find is done.
            .overlay(alignment: .trailing) {
                if showingFind {
                    FindMatchDecorations(
                        hits: matches,
                        documentLength: matchesDocumentLength,
                        selected: selectedFindIndex - 1
                    )
                    .frame(width: 10)
                    .allowsHitTesting(false)
                }
            }

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
            }
            // ⌘= and ⌘- are not handled here any more: they are menu commands,
            // so they fire wherever focus is rather than only in this editor —
            // see `FontSizeCommands`. A menu key equivalent is matched before
            // the responder chain, so this would never have seen them anyway.
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
        .onChange(of: source, initial: true) { _, newValue in
            effectiveLanguage = HighlightBudget.language(language, for: newValue)
            // The text moved, so a hit measured against the text before it is
            // no longer a position worth pushing — and pushing one into an
            // editor being typed in is what takes the caret away.
            pending = nil
            refreshMatches()
        }
        .onChange(of: showingFind) { _, newValue in
            if !newValue {
                searchTask?.cancel()
                searchTask = nil
                matches = []
                pending = nil
            }
        }
    }

    /// Carries the hit being jumped to, and nothing else.
    ///
    /// Only read while `pending` is set — see where it is attached above.
    private var selectionBinding: Binding<Range<String.Index>> {
        Binding {
            guard let pending else {
                return source.startIndex..<source.startIndex
            }
            return Self.range(of: pending, in: source)
        } set: { _ in
            // The text view has moved its caret of its own accord; whatever
            // this view was asking for is answered or overtaken.
            pending = nil
        }
    }

    private static func range(of offsets: Range<Int>, in text: String) -> Range<String.Index> {
        let count = text.count
        let lower = min(max(0, offsets.lowerBound), count)
        let upper = min(max(lower, offsets.upperBound), count)
        let start = text.index(text.startIndex, offsetBy: lower)
        return start..<text.index(text.startIndex, offsetBy: upper)
    }

    private func onChangeFindString() {
        search(jumpToFirstHit: true)
    }

    /// The text moved under an open find bar, so the hits moved with it. The
    /// caret is the user's here — unlike a new search, this never jumps it.
    private func refreshMatches() {
        guard showingFind else { return }
        search(jumpToFirstHit: false)
    }

    /// Runs the search and puts the result on screen.
    ///
    /// A large body is searched off the main thread: the query is retyped a
    /// character at a time and each keystroke searches again, so a pass that
    /// takes long enough to be felt is a field that stutters as it is typed in.
    /// Small bodies are searched in place — the hop off the main thread and
    /// back costs more than the search does, and going through it would leave
    /// the count a frame behind the typing.
    private func search(jumpToFirstHit: Bool) {
        searchTask?.cancel()
        searchTask = nil

        let text = source
        let query = findString.trimmingCharacters(in: .whitespacesAndNewlines)
        let caseSensitive = findCaseSensitive

        guard !query.isEmpty else {
            apply(.empty, jumpToFirstHit: jumpToFirstHit)
            return
        }

        guard text.utf8.count > Self.inlineSearchLimit else {
            apply(
                Self.matches(of: query, in: text, caseSensitive: caseSensitive),
                jumpToFirstHit: jumpToFirstHit
            )
            return
        }

        searchTask = Task {
            let found = await Task.detached(priority: .medium) {
                await Self.matches(of: query, in: text, caseSensitive: caseSensitive)
            }.value
            guard !Task.isCancelled else { return }
            // The text or the query may have moved on while this ran — a
            // cancelled task is not the only way to be out of date.
            guard query == findString.trimmingCharacters(in: .whitespacesAndNewlines),
                  caseSensitive == findCaseSensitive,
                  text == source
            else { return }
            apply(found, jumpToFirstHit: jumpToFirstHit)
        }
    }

    /// Bodies at or under this are searched on the main thread — see `search`.
    private static let inlineSearchLimit = 64 * 1024

    private func apply(_ result: FindResult, jumpToFirstHit: Bool) {
        matches = result.hits
        matchesDocumentLength = result.documentLength
        if jumpToFirstHit {
            pending = result.hits.first?.characters
            selectedFindIndex = result.hits.isEmpty ? 0 : 1
        } else if selectedFindIndex > result.hits.count {
            selectedFindIndex = result.hits.isEmpty ? 0 : 1
        }
    }

    /// Every hit for `query`, in document order.
    ///
    /// Both offset kinds are counted in this one pass, and each is counted on
    /// from the hit before it rather than from the start of the document:
    /// `distance(from:to:)` walks, so measuring every hit against `startIndex`
    /// would cost a pass over the whole text per hit. Doing the utf16 side here
    /// as well is what lets the ruler and the shading work off plain numbers —
    /// converting them on the main thread was the reason hits had to be capped.
    ///
    /// Takes everything it needs as arguments so it can run off the main
    /// thread — see `search(jumpToFirstHit:)`.
    private static func matches(
        of query: String,
        in text: String,
        caseSensitive: Bool
    ) -> FindResult {
        // Searched with `.caseInsensitive` rather than over `text.lowercased()`:
        // that is a separate string, and its ranges do not address this one.
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var found = [FindHit]()
        var start = text.startIndex

        var counted = text.startIndex
        var characterOffset = 0
        var utf16Offset = 0

        while start < text.endIndex,
              let match = text.range(of: query, options: options, range: start..<text.endIndex) {
            // Off the main thread this is a search nobody is waiting for any
            // more; on it, this is false and the check costs nothing.
            if Task.isCancelled { return .empty }

            characterOffset += text.distance(from: counted, to: match.lowerBound)
            utf16Offset += text.utf16.distance(from: counted, to: match.lowerBound)
            counted = match.lowerBound

            let characters = text.distance(from: match.lowerBound, to: match.upperBound)
            let units = text.utf16.distance(from: match.lowerBound, to: match.upperBound)
            found.append(
                FindHit(
                    characters: characterOffset..<(characterOffset + characters),
                    utf16: NSRange(location: utf16Offset, length: units)
                )
            )

            start = match.upperBound > match.lowerBound
                ? match.upperBound
                : text.index(after: match.lowerBound)
        }
        return FindResult(hits: found, documentLength: text.utf16.count)
    }

    /// Steps to the next hit, or the previous one.
    ///
    /// Counted from the hit the bar is showing rather than from where the caret
    /// is: the caret is the user's, and asking the editor where it is means
    /// keeping a binding attached that can push one back.
    private func jumpToTextPressEnter(next: Bool) {
        guard !matches.isEmpty else { return }

        let current = selectedFindIndex - 1
        let index: Int
        if current < 0 || current >= matches.count {
            index = next ? 0 : matches.count - 1
        } else {
            index = (current + (next ? 1 : -1) + matches.count) % matches.count
        }

        pending = matches[index].characters
        selectedFindIndex = index + 1
    }
}

/// One find hit, in both the units that ask about it: the editor's selection
/// speaks in Characters, the layout manager counts in UTF-16.
struct FindHit: Equatable, Sendable {
    let characters: Range<Int>
    let utf16: NSRange
}

/// What one search produced, and the scale to read it against.
struct FindResult: Sendable {
    let hits: [FindHit]
    /// UTF-16 length of the text searched.
    let documentLength: Int

    static let empty = FindResult(hits: [], documentLength: 0)
}

/// When syntax coloring is worth what it costs.
///
/// Highlightr re-colors the paragraph an edit touches, and a body with no
/// newlines in it is one paragraph — so a minified megabyte is put through
/// highlight.js in full on every change, on top of TextKit laying out a single
/// enormous line. Past either limit the text is shown plain, which is still the
/// text; the alternative is an editor that does not scroll.
enum HighlightBudget {

    /// A backstop, not the real limit — the line length below is. A document of
    /// short lines is colored one paragraph at a time, so its size costs only
    /// the first pass, and that is worth paying to keep a laid-out response
    /// readable.
    static let maxBytes = 256 * 1024

    /// What actually hurts: one line this long is one paragraph, re-colored
    /// whole on every change and laid out as a single run of text.
    static let maxLineLength = 20_000


    static func language(
        _ language: CodeEditor.Language,
        for source: String
    ) -> CodeEditor.Language? {
        guard source.utf8.count <= maxBytes, !hasOverlongLine(source) else { return nil }
        return language
    }

    /// Scanned over utf8, which needs no character breaking, and stops at the
    /// first line long enough to decide.
    private static func hasOverlongLine(_ source: String) -> Bool {
        var run = 0
        for byte in source.utf8 {
            if byte == 0x0A {
                run = 0
                continue
            }
            run += 1
            if run > maxLineLength { return true }
        }
        return false
    }
}

/// The editor itself, held apart from everything drawn around it.
///
/// `CodeEditor` does real work on every `updateNSView`: it reloads its theme
/// from disk, rebuilds the fonts from it and re-applies one across the whole
/// document — so an update it does not need costs a relayout of the text. Being
/// compared on its own inputs, it is only rebuilt when one of them changes; a
/// redraw of the find bar's counter, or of the pane behind it, stops here.
private struct EditorBox: View, Equatable {

    let source: Binding<String>
    let selection: Binding<Range<String.Index>>?
    let language: CodeEditor.Language?
    let theme: CodeEditor.ThemeName
    let fontSize: Double
    let flags: CodeEditor.Flags

    static func == (lhs: EditorBox, rhs: EditorBox) -> Bool {
        // Two views of the same text usually hold the same storage, which is
        // the case `String` answers by comparing pointers.
        lhs.source.wrappedValue == rhs.source.wrappedValue
            && lhs.selection?.wrappedValue == rhs.selection?.wrappedValue
            && (lhs.selection == nil) == (rhs.selection == nil)
            && lhs.language == rhs.language
            && lhs.theme.rawValue == rhs.theme.rawValue
            && lhs.fontSize == rhs.fontSize
            && lhs.flags == rhs.flags
    }

    var body: some View {
        CodeEditor(
            source: source,
            selection: selection,
            language: language,
            theme: theme,
            fontSize: .constant(fontSize),
            flags: flags
        )
    }
}

/// Marks every find hit twice: shaded in the text itself, and as a tick on a
/// slim ruler down the right edge, so hits off screen are still visible — the
/// same job Xcode's and VS Code's overview rulers do.
///
/// `CodeEditor` exposes nothing for this, so the decorations are applied to the
/// `NSTextView` it wraps. They are *temporary* attributes on the layout
/// manager, never text-storage ones: the syntax highlighter owns the storage
/// and rewrites it on every edit, which would wipe anything left there.
private struct FindMatchDecorations: NSViewRepresentable {

    let hits: [FindHit]
    /// UTF-16 length of the text the hits were found in.
    let documentLength: Int
    /// Index into `hits` of the hit the caret is on, or -1 for none.
    let selected: Int

    func makeNSView(context: Context) -> FindRulerView {
        FindRulerView()
    }

    func updateNSView(_ view: FindRulerView, context: Context) {
        view.apply(hits: hits, documentLength: documentLength, selected: selected)
    }

    static func dismantleNSView(_ view: FindRulerView, coordinator: ()) {
        view.clearHighlights()
    }
}

/// The ruler itself, and the owner of the in-text shading — one view so the two
/// always describe the same set of hits.
private final class FindRulerView: NSView {

    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.35)
    private static let selectedColor = NSColor.systemOrange.withAlphaComponent(0.65)
    private static let matchTick = NSColor.systemYellow.withAlphaComponent(0.75)
    private static let selectedTick = NSColor.systemOrange

    /// Every hit, for the ticks — placing one is arithmetic, so all of them
    /// can be shown however many there are.
    private var hits: [FindHit] = []
    private var selected = -1

    /// UTF-16 length of the text the hits were found in, which is the scale the
    /// ticks are placed on.
    private var documentLength = 0

    /// How many hits are shaded in the text itself.
    ///
    /// Each one is a temporary attribute the layout manager has to keep and
    /// redraw, and unlike a tick that is not free — so the shading follows the
    /// caret through the document in a window this size, rather than trying to
    /// paint every hit of a query that matched ten thousand times.
    private static let shadingWindow = 400

    /// Held weakly, and re-found whenever it has gone: the text view belongs to
    /// `CodeEditor`, and SwiftUI may rebuild it under us.
    private weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    /// Never in the way of the text — this is a readout, not a control.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        repaint()
    }

    func apply(hits: [FindHit], documentLength: Int, selected: Int) {
        self.hits = hits
        self.documentLength = documentLength
        self.selected = selected
        repaint()
    }

    func clearHighlights() {
        guard let layoutManager = textView?.layoutManager, let textView else { return }
        layoutManager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length)
        )
    }

    /// The slice of hits shaded in the text: `shadingWindow` of them, centred on
    /// the one the caret is on.
    private var shadedSlice: Range<Int> {
        guard hits.count > Self.shadingWindow else { return 0..<hits.count }
        let centre = selected >= 0 ? selected : 0
        let lower = max(0, min(centre - Self.shadingWindow / 2, hits.count - Self.shadingWindow))
        return lower..<(lower + Self.shadingWindow)
    }

    private func repaint() {
        needsDisplay = true
        guard let textView = locateTextView(), let layoutManager = textView.layoutManager else { return }

        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: length)
        )
        for index in shadedSlice where NSMaxRange(hits[index].utf16) <= length {
            layoutManager.addTemporaryAttributes(
                [.backgroundColor: index == selected ? Self.selectedColor : Self.matchColor],
                forCharacterRange: hits[index].utf16
            )
        }
    }

    /// Ticks sit where the hit falls in the document, by character offset.
    ///
    /// Not by where the text is laid out: asking the layout manager for a hit's
    /// bounding rect forces layout up to it, which for a hit near the end of a
    /// long document is layout of the whole thing — and this redraws whenever
    /// the view scrolls or resizes. Wrapped lines make the two disagree a
    /// little; this is a slim indicator, not a map.
    override func draw(_ dirtyRect: NSRect) {
        guard !hits.isEmpty, documentLength > 0 else { return }

        for (index, hit) in hits.enumerated() where hit.utf16.location <= documentLength {
            let position = CGFloat(hit.utf16.location) / CGFloat(documentLength)
            let y = position * bounds.height
            let tick = NSRect(x: 2, y: max(0, y - 1.5), width: max(1, bounds.width - 4), height: 3)
            (index == selected ? Self.selectedTick : Self.matchTick).setFill()
            NSBezierPath(roundedRect: tick, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    /// The text view this ruler is laid over. SwiftUI gives no handle on it, so
    /// it is found by walking out to the nearest ancestor that contains one —
    /// and where a window holds several editors, by taking the one this ruler
    /// actually sits on top of.
    private func locateTextView() -> NSTextView? {
        if let textView, textView.window != nil { return textView }

        var ancestor = superview
        var hops = 0
        while let current = ancestor, hops < 8 {
            var found = [NSTextView]()
            Self.collectTextViews(in: current, into: &found)
            if let best = nearest(of: found) {
                textView = best
                return best
            }
            ancestor = current.superview
            hops += 1
        }
        return nil
    }

    /// The candidate whose frame overlaps this ruler's — the ruler is drawn on
    /// top of its own editor, so that is the one it describes.
    private func nearest(of candidates: [NSTextView]) -> NSTextView? {
        guard candidates.count > 1 else { return candidates.first }
        let mine = convert(bounds, to: nil)
        return candidates.max { first, second in
            overlap(mine, first) < overlap(mine, second)
        }
    }

    private func overlap(_ rect: NSRect, _ view: NSView) -> CGFloat {
        rect.intersection(view.convert(view.bounds, to: nil)).height
    }

    private static func collectTextViews(in view: NSView, into found: inout [NSTextView]) {
        if let textView = view as? NSTextView {
            found.append(textView)
            return
        }
        for subview in view.subviews {
            collectTextViews(in: subview, into: &found)
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
