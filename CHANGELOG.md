# Changelog

## 0.2.0 — 2026.08.30

- Rename the app from Serein to Paper: target, bundle identifier
  (`org.humanitas.paper`), types, attribute and notification keys, and the
  configuration directory. An existing `~/.config/serein/` (config and
  presets) is moved to `~/.config/paper/` on first launch.
- Conceal heading markers (`#`…`######` and the following whitespace) on
  every paragraph the selection does not touch, so heading text sits on the
  margin; the paragraph under the cursor shows its full source. Concealment
  is a glyph-generation decision in the layout manager (`.null` glyph
  properties on a `.concealable` attribute) and never edits the text, so
  saving, undo, find, copy, and select-all see the unchanged source.
- Restore the block-quote rule, which the opaque canvas had been painting
  over, by drawing it in `drawBackground(in:)`; quoted text is set in a
  softer ink (62 %).
- Conceal block-quote markers (`>`, nested `> >`, and their spaces) off the
  active paragraph; quote text is inset by the list indent with the rule
  standing on the text margin as the only cue, and consecutive quote lines
  keep only line spacing between them so a hard-wrapped quote reads as one
  block.
- Conceal inline delimiters (`**`, `*`, `` ` ``) the same way; bold, italic,
  and code faces stay while the punctuation hides off the active paragraph.
- Align hard-wrapped list items: non-blank lines following an item without
  a marker of their own are styled as continuations, flush under the item's
  text with no spacing between. Leading spaces or tabs on such a line (source
  that indents the wrap under the marker) are concealed off the active
  paragraph, so the continuation starts exactly where the item's text does.
- Add inline formatting to the Format menu: ⌘B bold (`**`), ⌘I italic (`*`),
  ⌘U underline (`<u>`), ⌘E code (`` ` ``). Each toggles the delimiters
  around the selection or the word under the caret and unwraps when they are
  already there; a caret in whitespace inserts an empty pair to type into.
  Edits are plain source changes with undo.
- Treat ordered markers with a letter suffix (`1a)`, `1b.`) as list items, with
  the same indent, gap, and hanging wrap as `1.`.
- Render unordered list markers as Apple Notes' two list kinds off the
  active paragraph: `-` as a dashed list (`–`), `*` and `+` as a bulleted one
  (`•`), by glyph substitution in the layout manager; the source characters
  are untouched. Items are inset from the margin (1.4 × body size), the
  marker is kerned half a body size clear of the text (after its last
  character only, so `1.` is not spread apart), and wrapped lines hang under
  the item's text.
- Draw the quote rule from the whole quote run on every redraw; a partial
  redraw of one wrapped line used to leave a slit in the rule at that line's
  leading until the next full redraw.
- Remove the file-name label from the top-left corner; the deeper title
  area put it under the traffic lights.
- Give the window Spatial's chrome: an empty unified toolbar deepens the
  title area so the traffic lights sit further in and down, and the content
  is masked with a continuous 16 pt corner over a clear window so the shadow
  follows the rounder edge.
- Add `window.width` and `window.height` for the size of new windows
  (default 1400 × 900, Settings → Window); each window keeps its own size
  afterwards.
- Add `letter.spacing` (points of tracking, negative tightens) to the config
  and Settings.
- Add themes: `theme = paper | sepia | slate | mono | spatial-dark |
  apple-dark`, each with light and dark canvas and ink (the two dark themes
  are dark in both), plus `color.canvas`, `color.ink`, `color.canvas.dark`,
  and `color.ink.dark` hex overrides. Settings gets a theme picker and colour
  wells; presets capture the theme with the type settings. Muted punctuation,
  selection, and the quote rule derive from the ink.
- Add concealment tests (attribute ranges, glyph properties, arrow-key,
  multi-paragraph, undo, typing paths) and a concealment render probe; the
  restyle probe now measures the concealment overhead against the same view
  (within noise at 10K, 100K, and 1M characters).
- Keep line and document height identical whether a heading's markers are
  shown or hidden: layout is invalidated through to the end of the document,
  since a partial invalidation double-counted paragraph spacing and shifted
  everything below.
- Add presets: named copies of the settings saved as files in
  `~/.config/paper/presets/`, with a picker in Settings to apply one, Save
  as New Preset, and Delete. Applying writes the preset's values into the
  config file; the preset stays active across launches, and edits made while
  it is active are written into it, so there is no separate update step.
- Highlight selected text in a warm grey drawn from the ink instead of the
  system accent blue.
- Draw the canvas in the text view again so it is opaque and scrolling blits
  instead of redrawing every visible line.
- Set `#` at body + 10 pt (was + 8); `##` and below are unchanged.

## 0.1.0 — 2026.08.30

- Establish the native macOS document application.
- Add the minimal full-window editorial writing surface.
- Preserve ordinary UTF-8 Markdown through native open and save behavior,
  including byte-order marks and CRLF line endings.
- Import `net.daringfireball.markdown` as the Markdown document type.
- Skip restyling during input-method composition.
- Set body type at 14 pt on a 640 pt measure after live review; prefer the
  installed Test Family with the system serif as fallback.
- Draw the insertion point as a 2 pt rounded bar sized to the glyph box.
- Read settings from `~/.config/paper/config` (`key = value`, commented
  template written on first launch, `$XDG_CONFIG_HOME` honoured) and apply
  them live to open windows on save: `font.family`, `font.size`,
  `line.height`, `paragraph.spacing`, `measure`, `heading.weight`. Settings (`⌘,`) edits the same keys with
  sliders and writes them back into the file, preserving comments, and opens
  over a full-screen document.
- Set headings at the family's Medium weight by default (nearest installed
  face otherwise).
- Style block quotes: muted marker, italic content, hanging indent, and a
  vertical rule in the margin.
- Size the insertion point from the tallest font on its paragraph so it
  matches headings.
- Pad and pixel-align redraw rects so fractional line metrics leave no
  selection streaks.
- Show the file name in a quiet system-sans label inset from the top-left
  corner.
- Keep ⌃⌘F full screen working after the View menu's toolbar items are removed.
- Add document, styler, and selection tests plus an opt-in render and restyle
  timing probe.

