# ADR-001 :: Native document editor

Last updated: `2026.08.30`

> Paper uses the native macOS document lifecycle with an AppKit editing
> surface because trustworthy file and text behavior matter more than
> cross-platform reach for this product.

---

## 1. Decision

- Build Paper as a macOS-native Swift application.
- Use SwiftUI for scene composition and AppKit `NSTextView` for editing.
- Store ordinary UTF-8 Markdown as the sole document representation.
- Use visual source attributes before attempting character concealment.
- Keep the initial application free of web runtimes and editing engines.

## 2. Rationale

The product is a small Mac document editor, so native frameworks provide the
highest-leverage path to correct undo, spelling, substitutions, accessibility,
selection, input methods, autosave, and window behavior. `SwiftUI.TextEditor`
does not expose enough control for the intended typography and Markdown-aware
editing. Electron and Tauri add a second platform layer without advancing the
Mac-only product. ProseMirror would accelerate true WYSIWYG behavior but would
make Markdown serialization and native text behavior a cross-runtime concern.

The accepted tradeoff is that sophisticated inline rendering will take longer
than it would with a mature web editor engine.

## 3. Design Implications

- Source correctness has priority over visual concealment.
- AppKit is isolated behind a SwiftUI representable boundary.
- File I/O stays in the document model, never in the editor view.
- Styling must not alter Markdown characters or normalize whitespace.
- Features that require a database or proprietary document graph are outside
  the core architecture.

## 4. When to Revisit

Reconsider the editing engine if contextual Markdown concealment cannot remain
cursor-correct, if tables or embedded block editing become core requirements,
or if Paper must support non-Apple platforms.

