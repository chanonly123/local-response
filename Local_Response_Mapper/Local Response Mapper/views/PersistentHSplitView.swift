//
//  PersistentHSplitView.swift
//  Local Response Mapper
//

import SwiftUI

/// A two-pane horizontal split whose divider position survives relaunch.
///
/// `HSplitView` keeps its divider to itself — there is nothing to read the
/// position from, and pinning a pane with `.frame(width:)` makes the divider
/// unmovable — so the split is laid out here instead: the right pane owns the
/// stored width, the left takes the rest, and the divider writes the new width
/// back while it is dragged.
struct PersistentHSplitView<Left: View, Right: View>: View {

    /// The divider line is a hairline; the gutter around it is what the pointer
    /// actually has to hit, so it gets a few points of its own.
    private static var gutterWidth: CGFloat { 6 }

    /// Smallest either pane may be, as a fraction of the whole — the limit the
    /// `HSplitView` layout used before.
    private let minPaneFraction: CGFloat
    private let left: Left
    private let right: Right

    /// Right pane width in points, or 0 before it has ever been dragged, which
    /// means "split evenly".
    @AppStorage private var storedWidth: Double

    /// Right pane width when the current drag started; nil while not dragging.
    /// The gesture reports a translation from where it began, so the width it
    /// began at has to be kept — reading the live width instead would compound
    /// every change.
    @State private var dragAnchor: CGFloat?

    init(
        widthKey: String,
        minPaneFraction: CGFloat = 1.0 / 3.0,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self._storedWidth = AppStorage(wrappedValue: 0, widthKey)
        self.minPaneFraction = minPaneFraction
        self.left = left()
        self.right = right()
    }

    var body: some View {
        GeometryReader { geo in
            let rightWidth = resolvedWidth(total: geo.size.width)

            HStack(spacing: 0) {
                left
                    .frame(width: max(geo.size.width - Self.gutterWidth - rightWidth, 0))

                divider(total: geo.size.width, current: rightWidth)

                right
                    .frame(width: rightWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func divider(total: CGFloat, current: CGFloat) -> some View {
        ZStack {
            Color.clear
            Divider()
        }
        .frame(width: Self.gutterWidth)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let anchor = dragAnchor ?? current
                    dragAnchor = anchor
                    // Moving the divider left widens the right pane.
                    storedWidth = clamped(anchor - value.translation.width, total: total)
                }
                .onEnded { _ in
                    dragAnchor = nil
                }
        )
    }

    /// The width to draw the right pane at. A stored width too wide for the
    /// current window is only clamped for this layout, never written back, so
    /// working in a narrow window doesn't lose the position the user chose.
    private func resolvedWidth(total: CGFloat) -> CGFloat {
        guard storedWidth > 0 else {
            return max(total - Self.gutterWidth, 0) / 2
        }
        return clamped(storedWidth, total: total)
    }

    private func clamped(_ width: CGFloat, total: CGFloat) -> CGFloat {
        let minimum = total * minPaneFraction
        let maximum = total - Self.gutterWidth - minimum
        guard maximum > minimum else {
            return max(total - Self.gutterWidth, 0) / 2
        }
        return min(max(width, minimum), maximum)
    }
}
