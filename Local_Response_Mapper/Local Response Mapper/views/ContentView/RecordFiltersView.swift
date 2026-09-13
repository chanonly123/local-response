//
//  RecordFiltersView.swift
//  Local Response Mapper
//

import SwiftUI

/// Editor for the whitelist and blacklist the server applies to incoming
/// records.
///
/// Changes are written as they are made rather than on a Save button: the
/// server reads `Utils.recordFilters` per record, so an edit takes effect on
/// the next call either way, and a Save button would only invite the
/// expectation that Cancel puts things back.
struct RecordFiltersView: View {

    @Binding var filters: RecordFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Filters").font(.headline)
                Text("Matched against the whole url, case insensitive, as plain text — no wildcards. A filtered call is never recorded, so it costs nothing and cannot be recovered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            list(
                title: "Whitelist",
                caption: "Record only urls containing one of these. An empty list does nothing.",
                isEnabled: $filters.whitelistEnabled,
                entries: $filters.whitelist
            )

            Divider()

            list(
                title: "Blacklist",
                caption: "Never record urls containing one of these. Wins over the whitelist.",
                isEnabled: $filters.blacklistEnabled,
                entries: $filters.blacklist
            )

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
        .frame(width: 540, height: 540)
        .onChange(of: filters) { _, updated in
            Utils.recordFilters = updated
        }
    }

    @ViewBuilder
    private func list(
        title: String,
        caption: String,
        isEnabled: Binding<Bool>,
        entries: Binding<[String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isEnabled) {
                Text(title).font(.subheadline).bold()
            }
            .toggleStyle(.checkbox)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(entries.wrappedValue.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            TextField("contains…", text: entries[index])
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                            Button {
                                entries.wrappedValue.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(height: 120)

            Button {
                entries.wrappedValue.append("")
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        // The switch reads as off when it is on but empty, which is exactly
        // what it does, so the rows stay editable either way and only the
        // colour says whether they are in force.
        .opacity(isEnabled.wrappedValue ? 1 : 0.55)
    }
}
