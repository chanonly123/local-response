//
//  TemplateHelpView.swift
//  Local Response Mapper
//

import SwiftUI

/// Reference for the `{{...}}` placeholders a rule can carry, and the editor for
/// the user's own variables — the two belong together: the list of what can be
/// written is only complete once it includes the names this user defined.
struct TemplateHelpView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = TemplateGlobalsStore()
    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    /// Sampled once, when the sheet opens: a preview recomputed on every redraw
    /// flickers through values nobody asked to see.
    @State private var samples: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    builtins
                    userVariables
                    notes
                }
                .padding(12)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .font(.system(size: fontSize - 2))
        .monospaced()
        .frame(width: 580, height: 560)
        .onAppear(perform: sample)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("VARIABLES")
                .fontWeight(.bold)
            Text(verbatim: "Write {{name}} in a rule's query parameters, headers or body. It is replaced every time the rule fires, so each request gets a fresh value.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.14))
    }

    private var builtins: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Built in")
                .foregroundStyle(.secondary)

            ForEach(TemplateResolver.Builtin.allCases) { builtin in
                HStack(alignment: .top, spacing: 8) {
                    Text(builtin.token)
                        .textSelection(.enabled)
                        .frame(width: 210, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(builtin.detail)
                        if let sample = samples[builtin.token] {
                            Text(sample)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 4)

                    Button("Copy") {
                        Utils.copyToClipboard(builtin.token)
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var userVariables: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your variables")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.add()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a variable")
            }

            if store.variables.isEmpty {
                Text(verbatim: "None yet. Add one to reuse a token or a build number across rules — it is written {{name}}, the same as the built-in ones.")
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($store.variables) { $variable in
                HStack(spacing: 6) {
                    TextField("name", text: $variable.name)
                        .frame(width: 160)
                    TextField("value", text: $variable.value)
                    Button {
                        store.remove(id: variable.id)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this variable")
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .foregroundStyle(.secondary)
            bullet("A name nothing defines is left in the text as written, so a body that happens to contain braces is sent untouched.")
            bullet("The same placeholder used twice in one request resolves to one value — a request id can be sent in a header and in the body.")
            bullet("Times are UTC.")
            bullet("A built-in name wins over a variable of the same name.")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sample() {
        var resolver = TemplateResolver()
        var out = [String: String]()
        for builtin in TemplateResolver.Builtin.allCases {
            out[builtin.token] = resolver.resolve(builtin.token)
        }
        samples = out
    }
}

/// The user's variables, loaded once and written back on every edit — the sheet
/// has no save button, and a variable typed here has to be usable by the next
/// request that fires.
@MainActor
final class TemplateGlobalsStore: ObservableObject {

    @Published var variables: [TemplateGlobals.Variable] {
        didSet { TemplateGlobals.variables = variables }
    }

    init() {
        variables = TemplateGlobals.variables
    }

    func add() {
        variables.append(TemplateGlobals.Variable())
    }

    func remove(id: UUID) {
        variables.removeAll { $0.id == id }
    }
}

#Preview {
    TemplateHelpView()
}
