# Papel — Architecture

Last updated: `2026.09.03`

> Papel is a native macOS editor for ordinary UTF-8 Markdown files. The file is the only persistent document state. Rendering, configuration, and window state remain outside it.

## 1. System boundaries

| Component | Responsibility |
|---|---|
| `MarkdownDocument` | Decode and encode the source without transforming it |
| `PapelApp` | Own scenes, commands, and the native document lifecycle |
| `MarkdownEditor` | Bridge the SwiftUI document binding into AppKit |
| `PapelTextView` | Provide editing behavior and draw page decorations |
| `MarkdownSyntaxStyler` | Add temporary presentation attributes to the source |
| `PapelLayoutManager` | Conceal or substitute glyphs without changing storage |
| `ConfigurationStore` | Load, write, and watch user settings and presets |
| `Appearance` | Resolve configuration into fonts, spacing, and colours |

SwiftUI owns application composition. AppKit and TextKit 1 own the writing surface. The boundary between them is `MarkdownEditor`, an `NSViewRepresentable` that synchronizes plain text and the document URL.

## 2. Editor pipeline

```text
Markdown file
    ↕
MarkdownDocument
    ↕ SwiftUI binding
MarkdownEditor
    ↕
PapelTextView + MarkdownSyntaxStyler + PapelLayoutManager
```

The styler replaces presentation attributes across the in-memory text storage, then annotates recognized Markdown constructs. It does not replace source characters. Restyling waits while an input method holds marked text.

`PapelLayoutManager` turns concealed punctuation into zero-advance control glyphs outside the selected paragraphs and draws inline-code chips. Glyph substitution renders list markers and arrows without editing their source characters. `PapelTextView` draws block quotes, code blocks, thematic breaks, placeholders, and images around the laid-out text.

Block images use paragraph spacing to reserve a stable drawing band below the source line. The source remains present for selection, undo, copy, find, and saving. `ImageStore` decodes and downsamples local images off the main actor according to visible and prefetched demand. Its cache evicts least-recently-used unpinned entries under byte and entry budgets; visible images remain pinned and can exceed the byte budget. Image changes on disk invalidate cached content.

## 3. Invariants and configuration

- Saving must preserve the Markdown source exactly.
- Styling, concealment, substitution, and image rendering must not mutate the source string.
- Revealing syntax may change horizontal positions but must not change line or document height.
- Relative resources resolve from the saved Markdown file. Unsaved documents have no relative filesystem base.
- Opening a document must not fetch remote media automatically.
- The configuration file is the source of truth for user-tunable appearance values. The view zoom is the one exception: `Zoom` keeps a scale in `UserDefaults` per machine and `Appearance` multiplies the body size, measure, and margins by it, so the config and presets stay portable.

`ConfigurationStore` reads `key = value` settings from `$XDG_CONFIG_HOME/papel/config` or `~/.config/papel/config`. It preserves comments and unknown keys when writing, watches in-place and atomic saves, and posts a notification when effective values change. Presets use the same format in the adjacent `presets/` directory.

## 4. Decisions

| ID | Decision | Status |
|---|---|---|
| [ADR-001](decisions/001-native-editor.md) | Native document lifecycle and AppKit editing surface | Accepted |
| [ADR-002](decisions/002-contextual-syntax-concealment.md) | Contextual syntax concealment without source mutation | Accepted; mechanism revised by ADR-004 |
| [ADR-003](decisions/003-markdown-resource-resolution.md) | File-relative Markdown resource resolution | Accepted |
| [ADR-004](decisions/004-zero-advance-control-glyphs.md) | Zero-advance control glyphs for concealed syntax | Accepted |
