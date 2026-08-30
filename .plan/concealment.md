# Plan — contextual syntax concealment

Status: Phase 1 (headings) and Phase 2 (inline delimiters) done
`2026.08.30`; Phase 3 (block-quote marker) is open as
[humanitas-labs/paper#3](https://github.com/humanitas-labs/paper/issues/3). Follows the scaffold plan
([scaffold.md](scaffold.md), Risk 7 and §3.4), which deliberately kept
punctuation visible until cursor behaviour was proven.

## 1. Decision

Hide Markdown markers on every paragraph the cursor is not on. The paragraph
holding the insertion point (or any part of the selection) shows its full
source. Nothing else changes: the file, the text storage, undo, find, copy,
and paste all keep working on the unmodified source string.

Phase 1 covers heading markers only (`#`…`######` plus the following
whitespace). Phases 2 and 3 extend the same mechanism to inline delimiters
and block-quote markers once the heading behaviour feels right.

## 2. Mechanism

Concealment is a layout decision, not a storage edit.

1. **Styler marks.** `MarkdownSyntaxStyler` adds a custom attribute,
   `.concealable`, to each marker range it already dims. The attribute is a
   pure annotation; the character data is untouched.
2. **Layout manager hides.** `SereinLayoutManager` becomes its own
   `NSLayoutManagerDelegate` and implements
   `layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)`.
   For every character that carries `.concealable` and lies outside the
   active range, it substitutes `NSGlyphProperty.null`, which makes the glyph
   unlaid: zero advance, nothing drawn. All other glyphs pass through.
3. **Text view sets the active range.** `SereinTextView` overrides
   `setSelectedRanges(_:affinity:stillSelecting:)`. It computes
   `paragraphRange(for: selectedRange)` and, when it differs from the current
   active range, stores it on the layout manager and invalidates glyphs and
   layout for the old and new ranges only. Nothing is restyled; the document
   is not rescanned.

Why this and not the alternatives:

- **Tiny/clear font on markers** (0.01 pt, transparent). Works in an
  afternoon, but leaves sub-pixel glyphs that still receive clicks and a
  visible seam at the margin. Kept as the fallback if `.null` glyphs
  misbehave.
- **Replacing text in storage** (Typora-style rendering). Breaks the
  source-of-truth invariant in §4.2 of the scaffold plan, complicates undo
  and find, and is the case the scaffold explicitly rejected.
- **TextKit 2 rendering attributes.** Cleaner API, but the editor is TextKit 1
  by decision, and moving is a rewrite of the layout-dependent code (quote
  rules, caret).

## 3. Interaction model

| Situation | Behaviour |
|---|---|
| Cursor elsewhere | `# Humanitas` renders as `Humanitas` at the margin in heading type. |
| Cursor enters the line (click, arrow, find, undo) | Markers reappear in muted ink; text shifts right by the marker width. |
| Cursor leaves the line | Markers vanish again on the same layout pass. |
| Selection spans several paragraphs | Every touched paragraph shows its source. |
| Select all / copy | Source, including markers, as today. |
| Click on a concealed heading | Hit-testing sees no marker glyphs, so the caret lands in the visible text; the line reveals and the caret keeps its character index. |
| Empty heading `# ` | Not matched as a heading today; stays visible. No change. |
| IME composition | Concealment state is frozen while `hasMarkedText()`; the styler already skips restyle. |

The text shift on reveal is inherent to the approach and is what every
contextual-concealment editor does. It is acceptable for headings because the
marker is short. It is the main reason inline delimiters are a later phase:
`**` inside a sentence reflows the whole line on every cursor pass, which is
where this model starts to feel restless. Phase 2 must be evaluated in the
running app, not assumed.

## 4. Work packages

### WP1 — Attribute and layout delegate

- `NSAttributedString.Key.concealable` in `SereinLayoutManager.swift`.
- `SereinLayoutManager`: `activeRange: NSRange` (default empty), delegate
  method producing `.null` properties, helper `setActiveRange(_:)` that
  invalidates glyphs + layout for the symmetric difference of old and new.
- Styler: apply `.concealable` to heading marker ranges (`#…` and the
  whitespace up to the content).
- Text view: selection override feeding the active range; freeze while
  `hasMarkedText()`.

### WP2 — Caret and margin decorations

- `caretFont()` already reads the paragraph's tallest font, so the caret is
  unaffected.
- Quote rules use `usedRect`, so hidden glyphs do not move them. Verify with
  the render probe.
- Confirm `setNeedsDisplay` widening still erases the caret after a reveal
  shift.

### WP3 — Tests (before calling WP1 done)

- Source string identical before and after concealment and reveal (existing
  `stylingLeavesSourceUnchanged` extended with a selection move).
- `.concealable` ranges equal the marker ranges for each heading level.
- Layout: with the cursor on another paragraph, `propertyForGlyph(at:)` is
  `.null` for marker glyphs and the heading content's first glyph has
  `location(forGlyphAt:).x == 0`; with the cursor on the paragraph, the
  property is `.null` for none and `x > 0`.
- Selection navigation: moving down into a heading from the line above lands
  in that paragraph and reveals it; moving out conceals it.
- Multi-paragraph selection reveals every paragraph it touches.
- Restyle after edit keeps `.concealable` in sync (typing a `#` at line start
  conceals nothing while the cursor is there, conceals after leaving).
- Render probe: sample document, cursor on line 1 and on line 5, light and
  dark, compared by eye.

### WP4 — Docs

- `docs/architecture.md`: the concealment layer, the active-range rule, the
  invariant that concealment never edits storage.
- `README.md`, `CHANGELOG.md` (0.2.0 entry), scaffold plan §3.4 scope line
  and Risk 7 closed.

### Phase 2 (later, separate decision) — inline delimiters

`**`, `*`, `` ` `` via the same attribute. Evaluate line reflow feel in the
app before merging. Consider revealing only the delimiters of the span under
the cursor rather than the whole paragraph if the reflow is distracting.

### Phase 3 (later) — block-quote marker

Hide `>` and keep the margin rule as the only quote cue. The hanging indent
must then be recomputed for the concealed width, or the rule loses its
alignment with the text.

## 4a. Phase 1 outcome

- Implemented as designed; `.null` glyph properties behaved on every path
  tested (arrow keys, click, select-all, undo, typing, restyle). The fallback
  font approach was not needed.
- Nine tests plus a render probe (cursor on line 1 and line 5, light and
  dark).
- Overhead: the first delegate used `longestEffectiveRange`, which merges
  every unmarked run and scanned to the next heading per glyph batch (+60–75 %
  on restyle). `effectiveRange` plus an early exit for batches inside one
  unmarked run brought it within measurement noise (10K 4.8 vs 4.7 ms, 100K
  49 vs 48 ms, 1M 744 vs 747 ms).
- Partial layout invalidation (paragraph only) made a revealed mid-document
  heading 1 × `paragraph.spacing` taller and left the lines below stale.
  Glyph invalidation stays per paragraph; layout invalidation runs from the
  paragraph to the end of the document, which is what contiguous TextKit 1
  layout expects.
- Content glyphs sit at `lineFragmentPadding` (5 pt) when concealed, which is
  the container's normal margin, not a seam.

## 5. Acceptance criteria

- Heading markers are invisible on every paragraph the selection does not
  touch and visible on every paragraph it does.
- Saved bytes are unchanged by any concealment state.
- Undo, find, copy, paste, and select-all operate on source text.
- Caret is never trapped on an invisible character: the caret's paragraph is
  always fully revealed.
- 18 existing tests still pass; new tests from WP3 pass; zero warnings.
- Full-document restyle timings from the scaffold profile are not worse than
  10 % (concealment adds no per-keystroke document scan).

## 6. Risks

- **`.null` glyphs ignored or reset by AppKit** on some paths (e.g. after
  `invalidateGlyphs` without `invalidateLayout`). Control: WP3 layout test;
  fallback to the tiny/clear font approach behind the same attribute.
- **Reveal reflow feels jumpy** on arrow-key traversal. Control: evaluate in
  the app before Phase 2; headings alone are short enough.
- **Selection override misses a path** (programmatic selection from find or
  undo). Control: override the `setSelectedRanges` primitive, which every
  other selection setter funnels through, and test find + undo explicitly.

## 7. Estimate

WP1–WP4 for headings: one focused session. Phase 2 and 3: a second session
each, gated on how Phase 1 feels.
