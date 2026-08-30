# Changelog

## 0.2.0 — 2026.08.30

- Conceal heading markers (`#`…`######` and the following whitespace) on
  every paragraph the selection does not touch, so heading text sits on the
  margin; the paragraph under the cursor shows its full source. Concealment
  is a glyph-generation decision in the layout manager (`.null` glyph
  properties on a `.concealable` attribute) and never edits the text, so
  saving, undo, find, copy, and select-all see the unchanged source.
- Add concealment tests (attribute ranges, glyph properties, arrow-key,
  multi-paragraph, undo, typing paths) and a concealment render probe; the
  restyle probe now measures the concealment overhead against the same view
  (within noise at 10K, 100K, and 1M characters).
- Keep line and document height identical whether a heading's markers are
  shown or hidden: layout is invalidated through to the end of the document,
  since a partial invalidation double-counted paragraph spacing and shifted
  everything below.
- Add presets: named copies of the settings saved as files in
  `~/.config/serein/presets/`, with a picker in Settings to apply one, plus
  Save Current as Preset and Delete Preset. Applying writes the preset's values
  into the config file; later edits leave the preset untouched.
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
- Read settings from `~/.config/serein/config` (`key = value`, commented
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

