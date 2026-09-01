# Changelog

## Unreleased

- Render block images: `![alt](file)` alone on a line draws the file under it, scaled to fit the measure and never up past its natural size, with the source concealed off the active paragraph and shown above the image on it. The band is the paragraph's spacing, so the source stays untouched (save, undo, find, copy see `![…](…)`) and the caret entering the line moves nothing. Relative paths resolve against the document's file, which the editor now receives explicitly and follows across Save As; links open against it too, so an untitled document no longer resolves them against the home folder. A missing file shows its alt text muted and italic. Remote images are not fetched — no request leaves the machine when a document opens — and stand as their alt text; an image rewritten on disk is decoded again on the next restyle.

## 0.2.0 — 2026.08.30

- Leave code out of text checking: spelling and grammar underlines, smart quotes, and text replacements no longer touch fenced blocks or inline `code` spans, while the rest of the document keeps them. The check results are filtered as they arrive rather than toggling checking off.
- Chip a wrapped inline code span per line fragment, each chip clamped to the glyphs it holds: TextKit's background rects are selection-shaped, so a wrapping span used to stretch its first chip to the trailing edge and start the next at the left margin.
- Repaint the area a shortening edit vacates: every TextKit display invalidation is character-based, so the strip below the new last line held no characters and kept the old one's pixels — deleting a newline could leave the final paragraph apparently duplicated until a selection sweep repainted it.
- Start the title on the first letter typed into an empty document: it lands as `# ` plus the letter, one undo step, visible in the source. Syntax starters (`#`, `-`, `*`, `>`, a backtick, a digit, whitespace) begin as typed, so lists, quotes, and hand-typed headings are untouched.
- Ghost a title placeholder on an empty document — `# Untitled` in the H1 face at the muted syntax ink, marker shown as it would be on the caret's paragraph — so a fresh page reads as a page instead of a blank canvas. The caret stands in the ghost at the title's full height, and the first keystroke clears it.
- Ship a command-line launcher at `Paper.app/Contents/Resources/paper`: `paper file.md` opens documents from the terminal (creating any that do not exist yet), `paper` alone opens the app. Installed by symlinking it onto the PATH; it resolves the app bundle from its own location. `docs/claude.md` covers pointing Claude or another agent at it.
- License Paper under the MIT License, move build and test instructions into `docs/build.md`, and remove the private Spatial reference image from the repository.
- Reload documents edited by other programs: each window watches its file
  (vnode events, atomic-save rename handled) and a clean buffer adopts the
  disk content in place, selection preserved, without marking the document
  edited. A buffer with unsaved changes keeps them and surfaces the
  conflict on save, as before.
- Open links on a plain click (drag still selects; ⌘-click still works)
  and show a pointing-hand cursor over link text.
- Native mouse-wheel scrolling: the custom notch-easing animation is
  removed — it fought the system's acceleration and launched the viewport
  on physical mice.
- Render fenced code blocks: backtick or tilde fences set their lines in
  the code font on a quiet rounded band (the theme's ink at 5.5 % over the
  canvas). Content is literal — emphasis, lists, links, and arrows inside
  a fence stay as typed — and the fence lines conceal off the active
  paragraph, reading as the band's padding. An unterminated fence stays
  prose. No syntax highlighting yet.
- Continue lists on Return: pressing Return in a list item's text starts
  the next item with the same indent, block-quote prefix, and marker gap —
  unordered markers repeat, numbers count up, and a letter suffix advances
  (`1a)` → `1b)`). Return on an empty item removes its marker instead,
  ending the list. Splitting an item mid-line hands the tail to the new
  item. The continuation is one undo step.
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
- Ease mouse-wheel scrolling: each notch moves the viewport 60 pt toward an
  accumulated target over 180 ms with an ease-out, the way browsers scroll,
  instead of jumping. Trackpad scrolling (pixel-precise deltas with the
  system's own momentum) is untouched.
- Replace `->` with `→` in the source as it is typed, like smart dashes;
  ⌘Z restores the pair. `-->`, `<->`, and code spans are left as typed.
- Draw `->` as `→` off the active paragraph (the `-` concealed, the `>`
  drawn with the arrow glyph); code spans and `-->` are left alone. The
  glyph-substitution attribute is renamed from `listMarker` to
  `glyphSubstitute` now that it serves more than list markers.
- Style Markdown links: `[text](destination)` shows the text underlined
  with `[` and `](destination)` concealed off the active paragraph. ⌘-click
  opens the destination (absolute URLs as they are, paths relative to the
  document); a plain click places the caret as usual. Format → Add Link (⌘K)
  wraps the selection or the word under the caret, filling the destination
  from the clipboard when it holds a URL.
- Add inline formatting to the Format menu: ⌘B bold (`**`), ⌘I italic (`*`),
  ⌘U underline (`<u>`), ⌘E code (`` ` ``). Each toggles the delimiters
  around the selection or the word under the caret and unwraps when they are
  already there; a caret in whitespace inserts an empty pair to type into.
  Edits are plain source changes with undo. `<u>…</u>` renders underlined,
  with the tags muted and concealed off the active paragraph.
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
