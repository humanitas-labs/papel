# Changelog

## Unreleased

- `papel --set-default` makes Papel the app that opens `.md` and `.markdown` files, and a Make Default button in Settings ▸ CLI does the same; Get Info's Change All is no longer the only way. The agent prompt in the guide and the README now also has the agent open a test note with `papel`, so the command is seen working, and ask whether Papel should be the default app before running the command.

- Paste an image (a screenshot, a picture copied from a browser) and it lands as a PNG beside the document, named after the document and the moment (`notes-20260903-141205.png`), with `![](notes-20260903-141205.png)` inserted on its own line at the caret. A Finder copy or drop of an image file is copied the same way, keeping its format. `image.paste.directory = assets` in the config puts them in a subfolder of the document's, created on demand. An unsaved document runs the save sheet first, since there is no folder to write into. ⌘Z removes the line; the file stays (#36).

## 0.5.1 — 2026.09.03

- A click no longer selects a character or two. The clicked paragraph revealed its concealed syntax while the mouse was still down, the text shifted under the pointer, and the tracking loop read the shift as a drag. The reveal now waits for mouse up (#42).
- `_emphasis_` and `__strong__`, the CommonMark underscore spellings, style and conceal like their asterisk twins. An underscore counts only at a word boundary, so `snake_case_name`, `a_b`, `_leading`, and `trailing_` stay literal; a pair inside a code span or an HTML comment stays literal too. ⌘I and ⌘B still write asterisks and now unwrap the underscore forms (#47).

## 0.5.0 — 2026.09.03

- Defaults: font size 15 (was 14), paragraph spacing 11 (was 12), and letter spacing −0.02 (was 0).
- Font smoothing is off by default: glyphs draw at their true weight, as Safari draws them. `font.smoothing = on` in the config, or the switch in Settings, brings macOS's smoothing back.
- A guide on first launch: a Markdown document, opened in the editor itself, with what Papel is, the shortcuts, the prompt to paste into an agent, where the `papel` command was installed (or how to install it), and how to make Papel the default app for Markdown, under the mark. It is written to `~/Library/Application Support/Papel/welcome.md`, so nothing lands in your folders, and a Guide item on the welcome window opens it again, rewriting it only when it is gone.
- A welcome window when there is nothing to open: on launch without a document, and on a Dock click with no window up. It lists New, Open, Settings, and up to five recent documents on ⌘1 to ⌘5 under the Enso mark and a greeting, and closes itself once a document window opens.
- `color.ink.label` and `color.ink.label.dark`: the ink of the welcome window's section titles and row icons. Enso sets it to #68737E in both appearances; other themes derive it from the ink like the quote tone.
- Settings' Command Line section is now CLI.
- The `papel` command installs itself: on launch, a symlink goes into the first directory you own on your shell's PATH (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/bin`), and is repaired when the app moves and the link no longer resolves. Settings ▸ CLI shows where it is, installs it into `/usr/local/bin` with your password when nothing else is writable, and removes it; a removed command stays removed (#18).
- `papel --help` and `papel --version`; `--` ends the options. Files are passed as absolute paths, so names that begin with a dash open instead of tripping `touch`, and a missing app fails with a message instead of silently doing nothing.

## 0.4.0 — 2026.09.03

- Strikethrough: `~~text~~` draws struck through, the tildes muted on the active paragraph and concealed off it like the other inline delimiters. Only the double tilde counts, so `~5 minutes` stays prose; a pair inside a code span or an HTML comment renders literal. ⌘⇧X and a Strikethrough item in the Format menu toggle it around the selection or the word under the caret (#12).

## 0.3.1 — 2026.09.02

- Rename the app from Paper to Papel: target, bundle identifier (`org.humanitas.papel`), attribute and notification keys, the `papel` command-line launcher, the DMG, and the configuration directory. The configuration directory is now `~/.config/papel/`. The site moves to papel.sh.
- Add the `enso` theme, white under the ink #2D2B29 and, in the dark appearance, Spatial's #191B1D under #F4F9FA, and ship with it, line height 1.2, and paragraph spacing 12 as the defaults.
- Weights are numbers: `font.weight` (new, default 400) and `heading.weight` (default 500) take any value from 100 to 900, or the CSS names. New York and any variable face take the exact value on the weight axis; a static family takes its nearest face. Bold runs three hundred above the body weight. Settings gets sliders for both.
- `color.selection.ink` and `color.selection.ink.dark`: an ink for selected text, for themes whose selection is a solid rather than a tint. Unset keeps the text's own colour. Enso's selection is now that solid: #353535 under #F9F9F9 in the light appearance, the inverse in the dark.
- A `font.smoothing` key, and a Font smoothing switch in Settings: on applies macOS's smoothing, which thickens every stem a little; off draws glyphs at their true weight, as Safari does. On by default.
- The block-quote rule is a pill: its ends are rounded at half its width, in the app and on the site.
- Double-click a block image to open it in the system Quick Look panel, zoomed out of its band, with ← → across the document's images and Open with Preview one click away. The pointer is the arrow over an image, and a click on one leaves the caret alone so the source line stays concealed and the band stays put (#34).
- A single click marks an image with a wash of the ink that eases in over a third of a second, as Messages does, and eases out on the next click or keystroke.
- Code never keeps a spelling underline. The checker on current macOS writes its marks straight into the layout manager rather than through the text view's result handler, so the layout manager now refuses the mark wherever the characters are code (a fenced block, an inline span, a link or image address) and keeps it for prose; a mark laid down before a span is styled still comes off on the next restyle.
- Text checking leaves the `(destination)` of a link or image alone: a path or URL is not prose, so it no longer collects spelling underlines. Link text and alt text are still checked.
- HTML comments recede: `<!-- … -->`, across lines, draws in the muted ink with its delimiters in view and nothing inside it treated as Markdown; a comment never closed runs to the end of the document, as a browser reads it, and one inside a code fence stays code (#29).
- Decode only the images the viewport asks for: the text view tells the image store which bands its real viewport shows and which lie within one viewport of it, and the store decodes those, visible first, one at a time. Drawing looks only in the cache — AppKit paints well past the viewport for responsive scrolling, and the previous draw-driven decode pulled in every image it prepared, so a forty-image document decoded most of its images on open and cycled through the cache budget. Visible images are pinned against eviction, a file no longer demanded leaves the queue, a decode that finishes after losing demand is discarded, and a file rewritten mid-decode has its stale result dropped and decodes again. Opening the forty-image fixture now decodes three files (one visible, two prefetched) and idles at 0% CPU.
- Count decoded bitmaps by their actual bytes: the store had sized entries from the image rep's pixel count, which reports the display scale, so the 256 MB budget held under three Retina-sized bitmaps instead of sixteen and evicted constantly.

## 0.3.0 — 2026.09.02

- Decode images lazily, off the main thread: styling reserves each band from the file header alone, the bitmap decodes on a serial background queue the first time its band is drawn (so images that never scroll into view never decode), and the band shows a quiet panel of the final size until it lands. A document naming forty large images opens without a freeze (#30).
- In-document anchors: clicking `[text](#fragment)` jumps to the heading whose GitHub-style slug matches (lowercase, punctuation dropped, spaces as hyphens; repeated headings count `-1`, `-2`…), placing the caret on the heading and scrolling it into view. A fragment naming no heading does nothing (#28).
- Keep a keystroke that lands while an external file change is being adopted: the deferred clean-mark now checks the buffer still matches the adopted disk content, so the unsaved-change protection survives (#25).
- Back off file-watcher re-arming while a path stays missing: each failed open doubles the wait up to 2 s instead of retrying every 50 ms forever (#26).
- Bound image resources: decoded bitmaps live in a least-recently-used cache with a byte budget and entry limit, and a document watches at most 64 image files at once (#23).
- Leave image-looking lines inside fenced code alone: they render literal as before, and now also neither resolve, decode, nor watch the file they name (#24).

- User-defined themes: a file in `~/.config/papel/themes/<name>` holding `color.*` keys is a theme, selected by `theme = <name>`, listed in Settings under the built-ins, and reloaded live when edited. A file named like a built-in replaces it; keys a file leaves out take Papel's values; the config's `color.*` overrides still layer on top. Settings gains Save as Theme…, which writes the colours in use to a file and selects it, and Delete Theme for custom ones. A `theme` name nothing resolves to falls back to Papel without being rewritten, so a file added later is picked up.
- Theme tones beyond canvas and ink: `color.ink.muted`, `color.ink.quote`, `color.selection`, `color.code.background`, and `color.rule`, each with a `.dark` form, name the tones that were only ever the ink at an opacity. A theme file or the config may set any of them; the rest keep deriving, so every existing theme is unchanged.
- Render block images: `![alt](file)` alone on a line draws the file under it, scaled to fit the measure and never up past its natural size, with the source concealed off the active paragraph and shown above the image on it. The band is the paragraph's spacing, so the source stays untouched (save, undo, find, copy see `![…](…)`) and the caret entering the line moves nothing. Relative paths resolve against the document's file, which the editor now receives explicitly and follows across Save As; links open against it too, so an untitled document no longer resolves them against the home folder. A missing file shows its alt text muted and italic. Remote images are not fetched — no request leaves the machine when a document opens — and stand as their alt text; an image rewritten on disk is decoded again on the next restyle.

## 0.2.0 — 2026.08.30

- Leave code out of text checking: spelling and grammar underlines, smart quotes, and text replacements no longer touch fenced blocks or inline `code` spans, while the rest of the document keeps them. The check results are filtered as they arrive rather than toggling checking off.
- Chip a wrapped inline code span per line fragment, each chip clamped to the glyphs it holds: TextKit's background rects are selection-shaped, so a wrapping span used to stretch its first chip to the trailing edge and start the next at the left margin.
- Repaint the area a shortening edit vacates: every TextKit display invalidation is character-based, so the strip below the new last line held no characters and kept the old one's pixels — deleting a newline could leave the final paragraph apparently duplicated until a selection sweep repainted it.
- Start the title on the first letter typed into an empty document: it lands as `# ` plus the letter, one undo step, visible in the source. Syntax starters (`#`, `-`, `*`, `>`, a backtick, a digit, whitespace) begin as typed, so lists, quotes, and hand-typed headings are untouched.
- Ghost a title placeholder on an empty document — `# Untitled` in the H1 face at the muted syntax ink, marker shown as it would be on the caret's paragraph — so a fresh page reads as a page instead of a blank canvas. The caret stands in the ghost at the title's full height, and the first keystroke clears it.
- Ship a command-line launcher at `Papel.app/Contents/Resources/papel`: `papel file.md` opens documents from the terminal (creating any that do not exist yet), `papel` alone opens the app. Installed by symlinking it onto the PATH; it resolves the app bundle from its own location. `docs/claude.md` covers pointing Claude or another agent at it.
- License Papel under the MIT License, move build and test instructions into `docs/build.md`, and remove the private Spatial reference image from the repository.
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
  `~/.config/papel/presets/`, with a picker in Settings to apply one, Save
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
- Read settings from `~/.config/papel/config` (`key = value`, commented
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
