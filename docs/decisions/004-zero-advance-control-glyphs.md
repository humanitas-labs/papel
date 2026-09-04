# ADR-004 :: Zero-advance control glyphs

Status: Accepted

Date recorded: `2026.09.03`

Revises: [ADR-002](002-contextual-syntax-concealment.md), glyph suppression mechanism only.

## Decision

This record documents the existing implementation. `PaperLayoutManager` represents concealed punctuation as `.controlCharacter` glyphs and returns `.zeroAdvancement` from its control-character action delegate. It does not use the `.null` mechanism described in ADR-002.

## Rationale and consequences

The layout manager's implementation notes record why `.null` was replaced: a null glyph at a paragraph start could attach to the preceding line fragment and remove its paragraph spacing. A zero-advance control glyph stays in its own fragment without drawing or occupying width.

Concealed syntax occupies no horizontal advance while retaining the source characters and their text attributes. Contextual reveal, source preservation, and geometry requirements remain as recorded in ADR-002. This revision changes neither the Markdown file format nor resource resolution.

The current implementation lives in `Paper/Editor/PaperLayoutManager.swift`; the [architecture overview](../architecture.md) describes the active editor pipeline.
