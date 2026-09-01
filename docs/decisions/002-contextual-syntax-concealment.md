# ADR-002 :: Contextual syntax concealment

Date: `2026.08.31`

> Paper conceals Markdown syntax during layout while preserving the source text exactly.

---

## 1. Decision

Paper marks eligible Markdown punctuation with a `.concealable` text attribute. `PaperLayoutManager` suppresses those characters with `.null` glyph properties outside the paragraphs touched by the current selection. The selected paragraphs reveal their complete source.

Concealment changes glyph generation only. It never replaces, removes, or normalizes characters in text storage.

## 2. Rationale

Paper must read like a typeset page without sacrificing ordinary Markdown as the source of truth. Layout-time concealment satisfies both requirements: inactive syntax recedes, while saving, undo, find, copy, paste, and select-all continue to operate on the original text.

The selection range controls disclosure because a person editing a paragraph must be able to see and manipulate its complete syntax. The revealed range is frozen while an input method holds marked text so composition remains stable.

## 3. Alternatives rejected

- Replacing source characters with rendered content would introduce a second document representation and make exact Markdown serialization harder to guarantee.
- Drawing markers with a transparent or extremely small font would leave geometry and hit-testing artifacts.
- Migrating to TextKit 2 solely for rendering attributes would require replacing working layout-dependent behavior without improving the source-preservation invariant.

## 4. Consequences

- Persisted Markdown remains byte-exact regardless of what is visible.
- Concealment and reveal may change horizontal glyph positions, but must not change line height or document height.
- Selection changes require targeted glyph and layout invalidation.
- Every new concealed construct must prove cursor, selection, input-method, undo, and round-trip correctness in tests.

## 5. When to revisit

Reconsider this mechanism if TextKit no longer supports reliable glyph suppression, if embedded block editing becomes a core requirement, or if concealment cannot remain correct for selections and input methods.
