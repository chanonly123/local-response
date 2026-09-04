# CodeEditor (vendored)

Copied from [ZeeZide/CodeEditor](https://github.com/ZeeZide/CodeEditor) 1.2.6
(MIT — see `LICENSE`), rather than taken as a package, so the update path below
can be fixed. Everything else is upstream as it was.

## Local changes

- `UXCodeTextView.applyNewTheme(_:andFontSize:)` returns early when the theme
  and font size it is asked for are the ones already applied.

  Upstream ran the whole body on every `updateNSView`: it re-read the theme's
  css file from disk, parsed it, rebuilt three fonts from it and assigned one to
  the text view — which applies a font attribute across the entire text storage
  and relays out the document. With an editor showing a large response body,
  that made selecting text and scrolling visibly stutter.

  The upstream guard in the sibling `applyNewTheme(_:)` does not help either:
  it compares against `themeName`, which nothing ever assigns.
