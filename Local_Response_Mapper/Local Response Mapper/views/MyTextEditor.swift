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
            EditorBox(
                source: $source,
                // Attached only while the find bar is up. Reporting the caret
                // means writing it to `@State`, and every one of those writes
                // rebuilds this view — which drags the whole editor through an
                // update it does not need. Selecting text reports continuously,
                // so with the bar closed nothing is listening.
                selection: showingFind ? selectionBinding : nil,
                language: language,
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
                        source: source,
                        matches: matches,
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
        .onChange(of: source) { _, _ in
            refreshMatches()
        }
        .onChange(of: showingFind) { _, newValue in
            if !newValue {
                matches = []
                // Nothing reports the caret while the bar is closed, so what is
                // held here is only as current as the last time it was open.
                caret = nil
                pending = nil
            }
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
        let found = currentMatches()
        matches = found
        pending = found.first
        selectedFindIndex = found.isEmpty ? 0 : 1
    }

    /// The text moved under an open find bar, so the hits moved with it. The
    /// caret is the user's here — unlike a new search, this never jumps it.
    private func refreshMatches() {
        guard showingFind else { return }
        matches = currentMatches()
        if selectedFindIndex > matches.count {
            selectedFindIndex = matches.isEmpty ? 0 : 1
        }
    }

    /// Every hit for the current query, in document order.
    private func currentMatches() -> [Range<Int>] {
        let final = findString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else { return [] }
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
        return found
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
    let language: CodeEditor.Language
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

    let source: String
    /// Character offsets, in document order — the same ranges the find bar counts.
    let matches: [Range<Int>]
    /// Index into `matches` of the hit the caret is on, or -1 for none.
    let selected: Int

    func makeNSView(context: Context) -> FindRulerView {
        FindRulerView()
    }

    func updateNSView(_ view: FindRulerView, context: Context) {
        view.apply(source: source, matches: matches, selected: selected)
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

    /// UTF-16 ranges, which is what the layout manager counts in.
    private var ranges: [NSRange] = []
    private var selected = -1
    /// Held weakly, and re-found whenever it has gone: the text view belongs to
    /// `CodeEditor`, and SwiftUI may rebuild it under us.
    private weak var textView: NSTextView?
    private var frameObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    /// Never in the way of the text — this is a readout, not a control.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        repaint()
    }

    func apply(source: String, matches: [Range<Int>], selected: Int) {
        ranges = Self.utf16Ranges(of: matches, in: source)
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

    private func repaint() {
        needsDisplay = true
        guard let textView = locateTextView(), let layoutManager = textView.layoutManager else { return }

        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: length)
        )
        for (index, range) in ranges.enumerated() where NSMaxRange(range) <= length {
            layoutManager.addTemporaryAttributes(
                [.backgroundColor: index == selected ? Self.selectedColor : Self.matchColor],
                forCharacterRange: range
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !ranges.isEmpty,
              let textView = locateTextView(),
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        // The text view is sized to the whole document inside its scroll view,
        // so its height is the scale the ticks are placed on — and reading it
        // costs nothing, where measuring the laid-out text would force layout
        // of the entire document.
        let documentHeight = textView.frame.height
        guard documentHeight > 0 else { return }

        let length = (textView.string as NSString).length
        for (index, range) in ranges.enumerated() where NSMaxRange(range) <= length {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let box = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            let y = (box.midY / documentHeight) * bounds.height
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
                observe(best)
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

    /// Reflow moves every hit, and the text view is the only thing that knows
    /// it happened — the ranges themselves have not changed.
    private func observe(_ textView: NSTextView) {
        self.textView = textView
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        textView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    /// Character offsets to UTF-16 ranges in one pass: `String` counts
    /// Characters and the layout manager counts UTF-16 units, and converting
    /// each hit on its own would walk the document once per hit.
    ///
    /// Relies on `offsets` being in ascending, non-overlapping document order,
    /// which is how the search produces them.
    private static func utf16Ranges(of offsets: [Range<Int>], in text: String) -> [NSRange] {
        var index = text.startIndex
        var characters = 0
        var units = 0

        func advance(to target: Int) {
            while characters < target, index < text.endIndex {
                units += text[index].utf16.count
                index = text.index(after: index)
                characters += 1
            }
        }

        return offsets.map { offset in
            advance(to: offset.lowerBound)
            let start = units
            advance(to: offset.upperBound)
            return NSRange(location: start, length: units - start)
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
