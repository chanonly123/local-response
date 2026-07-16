import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct MyTextEditor: View {

    @Binding var source: String
    let language: CodeLanguage
    let theme: EditorTheme
    let isEditable: Bool
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    /// Drives the native find/replace panel (⌘F), cursor and scroll position.
    @State private var editorState = SourceEditorState()

    init(
        source: Binding<String>,
        language: CodeLanguage,
        theme: EditorTheme,
        isEditable: Bool
    ) {
        self._source = source
        self.language = language
        self.theme = theme
        self.isEditable = isEditable
    }

    var body: some View {
        SourceEditor(
            $source,
            language: language,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme,
                    font: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
                    wrapLines: true,
                    tabWidth: 4
                ),
                behavior: .init(isEditable: isEditable)
            ),
            state: $editorState
        )
        .onKeyPress { e in
            if e.key == .init("=") && e.modifiers.contains(.command) {
                fontSize = min(20, fontSize + 1)
                return .handled
            } else if e.key == .init("-") && e.modifiers.contains(.command) {
                fontSize = max(8, fontSize - 1)
                return .handled
            }
            return .ignored
        }
    }
}

#if DEBUG
struct MyTextEditorPreview: View {

    @State private var source = "{\n  \"message\": \"Lorem Ipsum\",\n  \"count\": 1500,\n  \"ok\": true\n}"

    var body: some View {
        MyTextEditor(
            source: $source,
            language: .json,
            theme: Utils.editorTheme(.dark),
            isEditable: true
        )
    }
}

#Preview {
    MyTextEditorPreview()
}
#endif
