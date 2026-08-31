# Paper Architecture

Last updated: `2026.08.30`

## 1. Objective

Paper is a native macOS document editor. Ordinary Markdown text is the only
persistent state. The application owns presentation and editing behavior, not a
document library or storage system.

## 2. Runtime

```text
Markdown file
    ↕ native document lifecycle
MarkdownDocument
    ↕ SwiftUI binding
MarkdownEditor
    ↕ NSViewRepresentable
PaperTextView / PaperLayoutManager / TextKit
    → temporary source styling, contextual concealment, margin decorations
```

`MarkdownDocument` reads and writes UTF-8 without transforming the source; its
codec is exposed as `init(data:)` and `data` so the byte-exact invariant is
tested directly. Markdown is imported as `net.daringfireball.markdown` because
the SDK ships no `UTType.markdown`. `MarkdownEditor` synchronizes the document
binding with AppKit and skips restyling while an input method holds marked
text. `WindowConfigurator` applies window behavior whenever its host view
attaches to a window. Styling changes attributes in the in-memory text storage
but never changes the persisted string. `Appearance` is the single source of
visual tokens; the user-tunable ones read the live `Configuration`. Colour
is four values — canvas and ink for light and dark — from a built-in `Theme`
with optional hex overrides; every other tone is the ink at an opacity, and
the resolved `NSColor`s are cached per palette so attribute runs merge.

Concealment is layered on styling without touching storage. The styler
annotates heading, block-quote, and inline markers with a `.concealable` attribute; `PaperLayoutManager`
is its own `NSLayoutManagerDelegate` and, while generating glyphs, gives every
concealable character outside its `activeRange` a `.null` glyph property
(zero advance, nothing drawn). `PaperTextView` overrides the
`setSelectedRanges` primitive, which every selection path funnels through,
and sets the active range to the union of the paragraphs the selection
touches; only ranges that carry markers are invalidated, so moving through
plain paragraphs costs nothing. The revealed range is frozen while an input
method holds marked text. List markers use the same
delegate the other way round: a `.glyphSubstitute` attribute names the character
to draw (`–` for `-`, `•` for `*`/`+`) and the delegate substitutes that
glyph off the active paragraph. Invariant: neither concealment nor
substitution edits the text, so saving, undo, find, copy, and select-all
operate on the unchanged source.

`ConfigurationStore` owns that configuration. It reads `key = value` lines
from `~/.config/paper/config` (honouring `$XDG_CONFIG_HOME`), writes the
commented template when the file is missing, and watches both the file and its
directory with `DispatchSource` so in-place and atomic saves alike reload it.
Parsing never fails: unknown keys are ignored and invalid or out-of-range
values fall back to their defaults. A changed configuration posts
`Configuration.didChangeNotification`; every text view refonts, re-insets, and
restyles.
The Settings scene (`⌘,`) edits the same keys with controls and writes
through `ConfigurationStore.write`, which merges values into the existing
file text so comments, order, and unknown keys survive; the file and the
window can never disagree. Presets are whole-configuration files in
`presets/` beside the config, in the same format; applying one writes its
values through the same path. The store remembers the active preset (per
config file, in `UserDefaults`) and writes every later edit into it as well,
so the active preset and the live settings never drift.

## 3. Application boundaries

- SwiftUI owns scenes, commands, document composition, and the settings panel.
- The configuration file owns every user-tunable value.
- AppKit owns the writing surface and Mac text behavior.
- The document model owns exact Markdown source serialization.
- Styling may annotate source but may not silently rewrite it.

## 4. Visual system

The full window is the canvas. A transparent titlebar retains standard Mac
traffic lights while removing app-owned chrome. The editor maintains a maximum
measure with responsive margins and uses the system serif design so typography
tracks platform rendering and accessibility behavior.

## 5. Decisions

| ID | Decision | Status |
|---|---|---|
| [ADR-001](decisions/001-native-editor.md) | Native document lifecycle and AppKit editing surface | Accepted |

