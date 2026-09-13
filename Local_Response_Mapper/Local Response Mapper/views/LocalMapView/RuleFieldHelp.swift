//
//  RuleFieldHelp.swift
//  Local Response Mapper
//

import SwiftUI

/// The three "what is this field for" explainers, behind one alert.
///
/// Kept next to the view that shows them rather than on the model: every word
/// below describes what the editor does with a field, not what a rule is.
enum HelpTopic: String, Identifiable {

    case does, method, url

    var id: String { rawValue }

    var title: String {
        switch self {
        case .does: "What the rule does"
        case .method: "Which methods it fires on"
        case .url: "Which urls it fires on"
        }
    }

    var message: String {
        switch self {
        case .does:
            """
            Map Response answers the request here. It never reaches the \
            network, and only the first matching rule answers — the one \
            highest in the list.

            Modify Request edits the request and lets it go to the server. \
            Every matching rule applies, top to bottom, so several can change \
            the same request.

            Example: Map Response with status 500 to see how the app handles \
            a server error. Modify Request to add an auth header to every \
            call without touching the app.
            """

        case .method:
            """
            Fires only on calls made with this method. "* (any)" fires on \
            every method.

            The method has to match as well as the url — a POST rule stays \
            quiet on the GET the app makes to the same address.
            """

        case .url:
            """
            Tested against the whole url, query string included. Matching is \
            case-sensitive. Type * on its own to fire on every url; an empty \
            field fires on nothing.

            For https://api.example.com/v2/users/42/profile.json?full=1

            contains — /users/ fires. Anywhere in the url.

            equals — the whole url, character for character, ?full=1 and all.

            starts with — https://api.example.com/v2/ fires.

            ends with — .json does NOT fire here: the url ends with the query, \
            not the path. .json?full=1 does.

            matches — */users/*/profile* fires. * stands for any run of \
            characters, ? for exactly one. Use it when the part you care \
            about sits between parts that change.
            """
        }
    }
}

/// The button that opens one, and the popover it opens.
///
/// A popover rather than an alert. An alert's message closure is not rendered
/// as a view tree — the platform pulls the string out and draws it in the
/// system font — so `.monospaced()`, and every other font or color modifier,
/// is silently dropped there. The url examples below are patterns, and a
/// pattern that reads as prose is worth less than no example at all.
///
/// Still one presentation for all of them: which topic is showing lives in the
/// `selection` the caller owns, so opening one closes any other, and adding a
/// topic stays a `HelpTopic` case and a `help:` argument.
///
/// The padding and the hit shape are inside the label, under `.plain`. A
/// bordered or borderless style would hit-test the glyph alone, which at this
/// size is a target barely worth aiming at.
struct HelpButton: View {

    let topic: HelpTopic
    @Binding var selection: HelpTopic?

    var body: some View {
        Button {
            selection = topic
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What this does, with an example")
        .popover(
            isPresented: Binding(
                get: { selection == topic },
                set: { if !$0 { selection = nil } }
            ),
            arrowEdge: .bottom
        ) {
            HelpCard(topic: topic)
        }
    }
}

/// One explainer, laid out.
private struct HelpCard: View {

    let topic: HelpTopic

    @AppStorage(Constants.fontSizeKey) private var fontSize: Double = Constants.fontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(topic.title)
                .font(.system(size: fontSize, weight: .semibold))

            // A popover is its own presentation, so it inherits nothing from
            // the editor behind it — the font the rest of the window carries
            // has to be set again here.
            Text(topic.message)
                .font(.system(size: fontSize - 2))
                .monospaced()
                .textSelection(.enabled)
                // Without this the text is measured on one line and the
                // popover grows sideways instead of wrapping.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 430, alignment: .leading)
    }
}
