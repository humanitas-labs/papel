---
title: "Serein native macOS editor implementation plan"
date: 2026-08-30
status: approved
affects: "Labs-owned minimal Markdown document editor"
---

# Serein Native macOS Editor Implementation Plan

Last updated: `2026.08.30`

> Build Serein as a native macOS document editor whose interface recedes into a
> single warm writing surface. The first release must preserve ordinary
> Markdown exactly, feel native under sustained use, and reproduce Spatial's
> restraint with the editorial typography of the supplied reference.

## Table of Contents

1. [Decision](#1-decision)
2. [Current state](#2-current-state)
3. [Product definition](#3-product-definition)
   - [3.1 — User outcome](#31--user-outcome)
   - [3.2 — Visual references](#32--visual-references)
   - [3.3 — Interaction model](#33--interaction-model)
   - [3.4 — Scope](#34--scope)
4. [Technical architecture](#4-technical-architecture)
   - [4.1 — Runtime boundaries](#41--runtime-boundaries)
   - [4.2 — Source-of-truth invariant](#42--source-of-truth-invariant)
   - [4.3 — Document lifecycle](#43--document-lifecycle)
   - [4.4 — Editing surface](#44--editing-surface)
   - [4.5 — Markdown presentation](#45--markdown-presentation)
5. [Detailed implementation sequence](#5-detailed-implementation-sequence)
6. [File-by-file specification](#6-file-by-file-specification)
7. [Test plan](#7-test-plan)
8. [Acceptance criteria](#8-acceptance-criteria)
9. [Risks and controls](#9-risks-and-controls)
10. [Commands](#10-commands)
11. [Handoff instructions](#11-handoff-instructions)

---

## 1. Decision

Build the first Serein release with Swift, SwiftUI, AppKit, and TextKit.

- SwiftUI owns the application scene and document composition.
- AppKit `NSTextView` owns text input and rendering.
- The native document lifecycle owns new, open, save, autosave, undo, file
  versions, and multiwindow behavior.
- The file's UTF-8 Markdown string is the only persistent document state.
- Text attributes may style Markdown source. They may not change or normalize
  it.
- Markdown punctuation remains visible but quiet in the scaffold. Contextual
  concealment followed once cursor correctness was proven: heading markers
  since `2026.08.30` ([concealment.md](concealment.md)).
- The app has no permanent app-owned chrome. Standard Mac traffic lights remain.

The architecture decision is recorded in
[`docs/decisions/001-native-editor.md`](../docs/decisions/001-native-editor.md).

---

## 2. Current state

Executed on `2026.08.30`. Work packages 0–6 and 8 are complete; work package 7
is complete for the flows an automated session can drive and awaits the user
for the remainder.

Verified:

- `xcodegen generate` is deterministic; `Serein.xcodeproj` is generated and
  ignored by Git.
- Debug build succeeds with zero warnings under Swift 6 strict concurrency.
- 18 tests in 5 suites pass: byte-exact UTF-8 round trips (including BOM,
  CRLF, composed characters, tabs, trailing whitespace, empty file), invalid
  UTF-8 and non-regular-file rejection, styling leaves `NSTextStorage.string`
  unchanged, selection and typing attributes survive restyling, selection
  clamping, settings-driven font and heading sizes with clamping and fallback,
  block-quote attributes and bold/italic trait composition.
- Offscreen renders at `640 × 520`, `1120 × 800`, and `1800 × 900` in light
  and dark: measure is `640 pt` at wide sizes and viewport minus `128 pt` at
  the minimum; canvas, ink, muted delimiters, heading, bold, italic, and code
  styling render as specified.
- Restyle cost per keystroke (Debug, M-series): `3 ms` at `10 KB`, `30 ms` at
  `100 KB`, `~550 ms` at `1 MB`. Full-document restyling is retained; `1 MB`
  is the recorded threshold where it would need incremental styling.
- The app launches at `1120 × 800`, opens a file from the command line, and
  autosaves typed edits to disk.
- Serein is registered in `kdb` as `serein` / `SER` in the Labs space.

Deviations from the original draft, all recorded in the tables above:

- `UTType.markdown` does not exist in the SDK; the type is imported as
  `net.daringfireball.markdown` and declared in `Info.plist`.
- SwiftUI's `FileDocumentReadConfiguration` and `WriteConfiguration` have no
  public initializers, so the codec is exposed as `init(data:)`,
  `init(fileWrapper:)`, and `data` and tested through those.
- Decoding uses `String(validating:as:)` rather than
  `String(data:encoding:)`, which strips a leading BOM.
- Restyling is skipped while an input method has marked text so composition is
  not interrupted.
- `WindowConfigurator` configures the window from `viewDidMoveToWindow`.
- Body size `14 pt`, measure `640 pt`, paragraph spacing `13 pt`, headings
  `22 pt` down to `16 pt`, after live review stepped the draft down from
  `23 pt`.
- The body family prefers the installed "Test Family" (a Klim trial font on
  this machine) and falls back to the system serif. Nothing is bundled; the
  fallback keeps the original rule intact on machines without it.
- Typeface, size, line height, paragraph spacing, measure, and heading
  weight are settings in `~/.config/serein/config`, applied live to
  open windows on save. See the configuration section below.

Remaining for the user (work package 7): the interactive flows — Save As,
Finder open, `.txt` round trip, two windows, dirty-close prompt, undo/redo,
find bar, live resize, appearance switch, external modification — and the
subjective call on font and insertion point.

No commit exists. Do not commit without user approval.

---

## 3. Product definition

### 3.1 — User outcome

The user double-clicks a Markdown file and immediately writes in a quiet,
book-like window. The editor behaves like a normal Mac document. The file stays
where it already lives. No import, vault, workspace, or account is required.

The app should feel absent during use. Text, selection, insertion point, and
scroll position are the only persistent signals inside the window.

### 3.2 — Visual references

Use the references for separate purposes:

1. [`editorial-typography.png`](../docs/references/editorial-typography.png)
   defines the paper color, serif character, generous leading, paragraph
   spacing, and long-form reading tone.
2. [`spatial-minimal-window.png`](../docs/references/spatial-minimal-window.png)
   defines the window restraint, open margins, full-size content, and absence of
   normal editor chrome.

Do not reproduce Spatial's sans-serif typography, back button, or ellipsis
button. Those controls express Spatial's document hierarchy and actions. Serein
opens filesystem documents directly, so hierarchy controls would be false
affordances.

Initial visual tokens:

| Token | Light | Dark | Purpose |
|---|---:|---:|---|
| Canvas | `#F6F3EC` | `#1B1916` | Full window background |
| Ink | `#1B1916` | `#E8E3D6` | Primary source text |
| Muted ink | Ink at `28%` opacity | Ink at `28%` opacity | Markdown punctuation |
| Body size | `14 pt` | `14 pt` | Default prose (was `23 pt`; settled during live review) |
| Maximum measure | `640 pt` | `640 pt` | Readable line length (~85 characters at `14 pt`) |
| Minimum side margin | `64 pt` | `64 pt` | Narrow-window breathing room |
| Top margin | `90 pt` | `90 pt` | Clears traffic lights and opens the page |
| Line-height multiple | `1.38` | `1.38` | Long-form readability |
| Paragraph spacing | `13 pt` | `13 pt` | Editorial rhythm |

Prefer the installed "Test Family" and fall back to the system serif design.
Do not bundle a font during the scaffold. The fallback path must inherit macOS
rendering, accessibility behavior, and font fallback.

### 3.3 — Interaction model

The window contains:

- standard red, yellow, and green traffic lights;
- a full-size content canvas beneath a transparent titlebar;
- one centered writing measure;
- an overlay vertical scrollbar that appears only during interaction; and
- native selection, insertion point, contextual menu, and find bar.

The window does not contain:

- a toolbar;
- a sidebar;
- tabs;
- a formatting bar;
- a title field inside the page;
- a status bar;
- a file browser;
- back or forward navigation; or
- an app-specific action button.

Commands belong in the macOS menu bar and standard keyboard shortcuts. The
window background may drag the window only where doing so does not interfere
with text selection.

Expected keyboard behavior:

| Command | Result |
|---|---|
| `⌘N` | Create a new untitled Markdown document |
| `⌘O` | Open a filesystem document |
| `⌘S` | Save using native document semantics |
| `⇧⌘S` | Save As |
| `⌘Z` / `⇧⌘Z` | Undo / redo text edits |
| `⌘F` | Reveal the native in-editor find bar |
| `⌘G` / `⇧⌘G` | Move between find results |
| `⌘W` | Close the current document window |

### 3.4 — Scope

The scaffold includes:

- macOS 15 or later;
- `.md`, `.markdown`, and `.txt` documents;
- new, open, save, Save As, autosave, and multiple document windows;
- UTF-8 source preservation;
- AppKit text editing with native undo, find, spelling, grammar, smart quotes,
  smart dashes, and text replacements;
- responsive centered layout;
- adaptive light and dark appearances;
- visual styling for headings, emphasis, strong text, inline code, list
  markers, and block quotes while retaining all Markdown characters;
- unit tests, architecture documentation, and reproducible Xcode generation;
  and
- a warning-free Debug build.

The scaffold excludes:

- complete WYSIWYG editing;
- concealment of inline and block-quote markers (heading markers are
  concealed contextually; see [concealment.md](concealment.md));
- CommonMark or GFM parser integration;
- tables, task controls, rendered images, footnotes, equations, or diagrams;
- colour themes (planned as further keys in the same config file);
- export to HTML, PDF, or rich text;
- a library, folder navigator, backlinks, tags, or search across files;
- iCloud or third-party sync;
- collaboration, comments, AI features, or publishing;
- sandbox entitlements and App Store packaging;
- Developer ID signing and notarization; and
- an application icon.

---

## 4. Technical architecture

### 4.1 — Runtime boundaries

```text
SereinApp
└── DocumentGroup
    └── MarkdownDocument
        └── DocumentView
            ├── WindowConfigurator
            └── MarkdownEditor (NSViewRepresentable)
                └── NSScrollView
                    └── SereinTextView (NSTextView)
                        ├── NSTextStorage
                        ├── NSLayoutManager
                        ├── NSTextContainer
                        └── MarkdownSyntaxStyler
```

Each boundary has one responsibility:

- `SereinApp` declares the document scene and commands.
- `MarkdownDocument` reads and writes the source string.
- `DocumentView` composes the window-level surface.
- `WindowConfigurator` applies Mac window behavior not exposed by SwiftUI.
- `MarkdownEditor` synchronizes SwiftUI document state with AppKit.
- `SereinTextView` configures text input, layout, and native editor behavior.
- `MarkdownSyntaxStyler` applies presentation attributes without changing text.
- `Appearance` is the single source of truth for visual tokens.

### 4.2 — Source-of-truth invariant

The plain `String` in `MarkdownDocument.text` is authoritative.

The following operations are forbidden unless the user explicitly invokes a
future formatting command:

- replacing typographic characters;
- trimming trailing whitespace;
- normalizing line endings;
- inserting or removing final newlines;
- renumbering lists;
- changing Markdown delimiters;
- rewriting links; or
- serializing from attributed text.

The source-preservation test is byte equality after UTF-8 read and write.
Styling tests must also assert that `NSTextStorage.string` is unchanged after
attributes are applied.

Smart quotes, smart dashes, and text replacements are native user-input
features. They may affect newly typed characters because the user caused the
edit. They may never retroactively transform opened source.

### 4.3 — Document lifecycle

Use a SwiftUI `DocumentGroup` with a value-type `FileDocument` unless the build
environment proves that the current SDK requires the newer document protocol.
Do not migrate APIs preemptively.

`MarkdownDocument` must:

1. declare Markdown and plain text as readable and writable content types;
2. reject file wrappers without regular file contents;
3. reject non-UTF-8 input with a Cocoa file-read error;
4. retain the decoded string exactly;
5. write `Data(text.utf8)` without intermediate attributed serialization; and
6. expose a deterministic empty-document initializer.

The document scene should inherit native menu commands. Replace or hide only
the toolbar command because Serein has no toolbar.

### 4.4 — Editing surface

Use a single AppKit `NSTextView` inside an `NSScrollView`.

Required text-view configuration:

- vertically resizable;
- horizontally fixed to the viewport;
- text container width tracks the text view;
- transparent text-view background;
- rich-text input disabled;
- graphic import disabled;
- undo enabled;
- find bar enabled;
- incremental search enabled;
- spelling and grammar enabled;
- automatic quote, dash, and text replacement enabled;
- automatic spelling correction disabled to avoid silent word replacement;
- AppKit selection colors; and
- an insertion point using the active ink color, drawn as a `2 pt` rounded
  bar sized to the glyph box rather than the full leaded line.

Responsive measure calculation:

```text
side margin = max(64, (viewport width - 640) / 2)
```

Apply this as the text container inset after every frame-size change. Keep the
top inset at `90 pt`. Verify that the text width does not become negative near
the minimum window width.

The SwiftUI/AppKit bridge must be idempotent:

- update the binding only when the text changes;
- update the text view only when external document text differs;
- preserve and clamp the selected range when external text replaces content;
- prevent attribute-only changes from producing document edits;
- avoid recursive delegate updates; and
- keep typing attributes aligned with the base appearance after restyling.

### 4.5 — Markdown presentation

The scaffold uses source styling, not rendered Markdown.

| Construct | Presentation |
|---|---|
| Paragraph | Serif body font, ink, `1.38` line height, `13 pt` spacing |
| `#` heading | `22 pt` medium serif content, marker at muted ink |
| `##` heading | `20 pt` medium serif content, marker at muted ink |
| Lower headings | Descend by `2 pt`, floor at `16 pt` |
| `**strong**` | Bold serif content, delimiters at muted ink |
| `*emphasis*` | Italic serif content, delimiters at muted ink |
| `` `code` `` | Monospaced content at `88%` body size, delimiters muted |
| List marker | Marker and following source spacing at muted ink |
| `> quote` | Marker at muted ink, content italic, wrapped lines hang under the text, `2 pt` muted rule in the margin |

Regex styling is acceptable for this narrow scaffold. It is presentation only.
Do not claim complete Markdown parsing. Add a parser only when nested constructs
or block semantics require it.

Restyling must be safe for:

- an empty document;
- Unicode and composed characters;
- unmatched delimiters;
- nested or adjacent emphasis markers;
- selection within a matched range;
- rapid typing and deletion; and
- appearance changes.

---

## 5. Detailed implementation sequence

### Work package 0 — Orient and protect existing work

1. Read the workspace and project instructions before editing.
2. Read `kernel/SOP/code.md`, `kernel/conventions/code.md`, this plan, the ADR,
   and `docs/architecture.md`.
3. Run `git status --short --branch` inside Serein.
4. Confirm the repository has no remote. If a remote exists, fetch and compare
   `master` with upstream before changing code.
5. Preserve all user changes. Do not reset or replace current files wholesale
   merely because they are unverified.

Exit condition: the executor can state which files exist, which are modified,
and whether upstream comparison applies.

### Work package 1 — Generate the Xcode project

1. Inspect `project.yml` for XcodeGen compatibility.
2. Confirm application and test targets use macOS 15 as the deployment floor.
3. Confirm the app target uses `org.humanitas.serein` and version `0.1.0`.
4. Confirm Markdown and plain-text document types appear in the generated
   `Info.plist`.
5. Run `xcodegen generate`.
6. Run it a second time and inspect Git status. Generation must be deterministic
   and should not modify unrelated source files.

Exit condition: `Serein.xcodeproj` exists and exposes the `Serein` scheme with
application and test targets.

### Work package 2 — Establish a warning-free build

1. Build with signing disabled and Derived Data outside the repository.
2. Fix compiler errors at the smallest scope.
3. Keep Swift 6 strict concurrency enabled.
4. Do not suppress warnings. Rewrite code that produces false positives.
5. Pay particular attention to:
   - global AppKit color and font values under strict concurrency;
   - static `NSRegularExpression` instances and Sendable diagnostics;
   - SwiftUI scene command placement APIs;
   - `FileDocument` SDK availability;
   - `UTType.markdown` availability;
   - test configuration initializer visibility; and
   - actor isolation in `WindowConfigurator` and representable callbacks.

Exit condition: Debug application build succeeds with zero warnings.

### Work package 3 — Prove document correctness

1. Compile the existing document tests.
2. Repair tests using public SDK APIs only.
3. Add coverage for:
   - empty documents;
   - ASCII Markdown;
   - Unicode and composed characters;
   - blank lines and trailing newline preservation;
   - tabs and trailing spaces;
   - malformed file wrappers; and
   - invalid UTF-8 rejection.
4. Add a fixture that reads and writes the same source, then compares the
   resulting bytes.

Exit condition: document tests pass and demonstrate exact UTF-8 preservation.

### Work package 4 — Stabilize SwiftUI/AppKit synchronization

1. Review `MarkdownEditor` for feedback loops.
2. Confirm user typing updates `MarkdownDocument.text` once per text change.
3. Confirm attribute-only restyling does not register as a source edit.
4. Confirm external document updates replace the visible text once.
5. Preserve and clamp the selection after external replacement.
6. Confirm undo and redo operate on typed source, not styling operations.
7. Add focused unit tests around selection clamping if it is extracted into a
   testable type.

Exit condition: text synchronization is deterministic and does not disturb the
cursor during ordinary typing.

### Work package 5 — Complete the minimal window

1. Configure a full-size content view and transparent titlebar.
2. Hide the title and titlebar separator.
3. Remove the toolbar and toolbar menu command.
4. Retain the standard traffic lights in their normal positions.
5. Set the canvas color at the window, scroll view, and SwiftUI background
   layers so resizing never flashes white.
6. Set a minimum window size of `640 × 520 pt`.
7. Choose a restrained default new-window size between `1080 × 760 pt` and
   `1200 × 840 pt`; preserve normal macOS window restoration thereafter.
8. Verify that background window dragging does not capture gestures within the
   text editor.
9. Verify that the top text inset clears the traffic lights at minimum width.

Exit condition: the window shows only traffic lights, canvas, text, and an
interaction-only overlay scrollbar.

### Work package 6 — Complete the editorial writing surface

1. Make `Appearance` the only location for visual constants.
2. Verify the system serif descriptor renders as expected on macOS 15 and 26.
3. Apply body type, ink, line height, and paragraph spacing to the full source.
4. Apply heading, emphasis, strong, inline-code, and list-marker styling.
5. Keep punctuation present and selectable.
6. Reapply dynamic colors when effective appearance changes.
7. Verify typing attributes after a heading or emphasis span so new text does
   not inherit the wrong font.
8. Profile restyling with documents at `10 KB`, `100 KB`, and `1 MB`. Full-file
   regex restyling is acceptable for the scaffold if normal typing remains
   responsive through `100 KB`. Record the observed threshold.

Exit condition: prose matches the intended warm editorial tone, Markdown
characters remain source-correct, and typing is responsive at the declared
document size.

### Work package 7 — Exercise native document flows

Run these manual flows against the built application:

1. Create an untitled document, type, save as `.md`, close, and reopen.
2. Open an existing `.markdown` file from Finder.
3. Open a `.txt` file, edit it, and save without changing its extension.
4. Open two documents in separate windows and edit both.
5. Close a dirty untitled document and confirm the native save prompt.
6. Undo and redo multiple typing operations.
7. Find text with `⌘F`, advance with `⌘G`, and dismiss the find bar.
8. Resize from minimum width to a large display and confirm the centered measure.
9. Switch between light and dark appearances while a document is open.
10. Modify an open file externally and record the native conflict behavior.

Do not invent custom conflict handling during the scaffold. If native behavior
is inadequate, document the observed gap as a follow-on issue.

Exit condition: all ordinary flows pass or have a specific recorded defect with
reproduction steps.

### Work package 8 — Finish documentation and registration

1. Update `README.md` to match behavior actually verified.
2. Update `docs/architecture.md` if implementation boundaries changed.
3. Amend ADR-001 only for factual corrections. Write a new ADR if the editing
   engine or document architecture changes.
4. Update `CHANGELOG.md` without changing version `0.1.0`.
5. Mark this plan `done` only after every acceptance criterion is met.
6. From the Humanitas root, register the project:

   ```bash
   kdb projects add serein \
     --alias SER \
     --path labs/projects/serein \
     --name Serein \
     --description "Native macOS editor for quiet, editorial Markdown writing." \
     --space labs
   ```

7. Run `kdb check` from the Humanitas root.
8. Present the diff, build result, test result, manual test checklist, and known
   limitations to the user.
9. Do not commit until the user approves the implementation.

Exit condition: project registration and workspace checks pass; the work is
ready for user review.

---

## 6. File-by-file specification

| File | Responsibility | Required outcome |
|---|---|---|
| `project.yml` | Reproducible Xcode project definition | App and test targets, macOS 15 floor, document types, version, strict concurrency |
| `Serein/App/SereinApp.swift` | Scene and document composition | Native document commands, no toolbar, minimum view size |
| `Serein/App/WindowConfigurator.swift` | AppKit window policy | Transparent hidden titlebar, full-size content, no separator or toolbar |
| `Serein/Design/Appearance.swift` | Visual source of truth | Dynamic canvas and ink, serif fonts, measure and spacing constants |
| `Serein/Documents/MarkdownDocument.swift` | Persistent document model | Exact UTF-8 read and write, explicit errors, no normalization |
| `Serein/Editor/MarkdownEditor.swift` | SwiftUI/AppKit bridge | Idempotent text synchronization, selection preservation, no feedback loop |
| `Serein/Editor/SereinTextView.swift` | TextKit configuration | Native editing services, responsive insets, transparent surface |
| `Serein/Editor/MarkdownSyntaxStyler.swift` | Source presentation | Safe attribute-only styling, no character changes |
| `SereinTests/MarkdownDocumentTests.swift` | Document correctness | Empty, Unicode, invalid input, and byte-preservation coverage |
| `SereinTests/MarkdownSyntaxStylerTests.swift` | Styling invariants | Source unchanged, empty and Unicode input safe, delimiters styled correctly |
| `docs/architecture.md` | Current architecture | Matches the verified runtime and boundaries |
| `docs/decisions/001-native-editor.md` | Decision history | Records native architecture and revisit conditions |
| `README.md` | Operator documentation | Accurate generate, build, test, and run commands |
| `CHANGELOG.md` | Version history | `0.1.0` scaffold entry aligned with delivered behavior |
| `.gitignore` | Local artifact exclusions | Derived Data, user state, build output, and OS files ignored |

Generated files:

- `Serein.xcodeproj` is generated by XcodeGen and should be checked in if that
  matches the neighboring Labs project convention. The authoritative structure
  remains `project.yml`.
- Derived Data must remain outside the repository and untracked.

---

## 7. Test plan

### 7.1 — Automated tests

Document-model assertions:

- empty initializer returns an empty string;
- Markdown and plain text are accepted types;
- valid UTF-8 decodes exactly;
- Unicode survives round-trip;
- trailing newline, blank lines, tabs, and trailing spaces survive round-trip;
- regular-file data encodes exactly as `Data(source.utf8)`;
- absent regular file contents throw;
- invalid UTF-8 throws; and
- repeated read/write cycles do not drift.

Styling assertions:

- styling an empty storage is safe;
- styling does not alter `storage.string`;
- heading content receives the expected font tier;
- heading markers receive muted ink;
- emphasis and strong content receive the expected font traits;
- inline-code content receives a monospaced font;
- unmatched delimiters do not crash or style unrelated text; and
- Unicode ranges do not produce out-of-bounds attributes.

### 7.2 — Build gates

- XcodeGen succeeds.
- Debug application build succeeds.
- Unit-test bundle builds.
- All tests pass.
- Compiler emits zero warnings under Swift 6 strict concurrency.
- A second XcodeGen run produces no unexplained project drift.

### 7.3 — Manual visual checks

At `640`, `1080`, `1440`, and `1800 pt` window widths, confirm:

- the writing measure stays centered;
- side margins never fall below `64 pt`;
- the first baseline clears the traffic lights;
- the canvas reaches every window edge;
- no title, toolbar, separator, or sidebar appears;
- overlay scrollbar behavior remains native;
- serif text and paper color match the references in character; and
- dark appearance remains readable without becoming a generic black editor.

### 7.4 — Manual source checks

Use a fixture containing:

```markdown
# Serein

A quiet place to write — with **strong text**, *emphasis*, and `inline code`.

1. Preserve list syntax.
2. Preserve trailing spaces.  

- Unicode: café, naïve, 中文, العربية, 👩🏽‍💻
- Link: [Humanitas](https://example.com/?a=1&b=2)
```

Save, close, reopen, and compare the bytes with the expected fixture.

---

## 8. Acceptance criteria

The scaffold is done only when every statement below is true.

### Build and structure

- [ ] `xcodegen generate` succeeds reproducibly.
- [ ] The Debug application builds with zero warnings.
- [ ] The unit-test target builds and all tests pass.
- [ ] Derived Data and user-specific Xcode state remain untracked.

### File correctness

- [ ] Serein creates and opens Markdown documents through native Mac commands.
- [ ] `.md`, `.markdown`, and `.txt` files remain ordinary filesystem files.
- [ ] UTF-8 Markdown survives read and write byte-for-byte.
- [ ] Styling never changes the persisted source.
- [ ] Dirty-document close behavior uses the native save prompt.

### Editing behavior

- [ ] Typing, deletion, selection, copy, paste, undo, redo, and find behave
      normally.
- [ ] Spelling, grammar, smart quotes, smart dashes, and text replacements are
      available.
- [ ] Cursor position does not jump during restyling or external binding updates.
- [ ] Two document windows can be edited independently.

### Visual behavior

- [ ] Only standard traffic lights persist as window chrome.
- [ ] No toolbar, sidebar, tab strip, status bar, or formatting controls appear.
- [ ] The canvas fills the complete window without resize flashes.
- [ ] The serif writing measure remains centered and responsive.
- [ ] Light and dark appearances use the declared warm palette.
- [ ] Headings, emphasis, strong text, inline code, and list markers are visually
      differentiated while their Markdown source remains visible.

### Workspace completion

- [ ] README, architecture, ADR, changelog, and this plan match actual behavior.
- [ ] Serein is registered as project `serein`, alias `SER`, in the Labs space.
- [ ] `kdb check` passes from the Humanitas root.
- [ ] The user receives build, test, and manual verification results.
- [ ] No commit is created before user approval.

---

## Follow-on: `ser` command-line launcher

Requested on `2026.08.30` after the first live session. Out of scope for the
`0.1.0` scaffold; record only.

- Provide a `ser` command so a file opens from the terminal in one step:
  `ser notes.md`, `ser` (new untitled document), `ser a.md b.md` (one window
  each).
- Preferred shape: a thin script or tiny binary on `PATH` that resolves paths
  and calls `open -a Serein <files>` (or `NSWorkspace` directly), so launch
  semantics stay identical to Finder and the app needs no argument parsing.
- Consider `--wait` (block until the window closes) so `ser` can serve as
  `EDITOR` and `GIT_EDITOR`; this needs the app to signal document close, which
  is the only part that touches app code.
- Install path and packaging (Homebrew formula, `make install`, or an in-app
  "Install command line tool" menu item) are open questions.

---

## Configuration file (added to scope `2026.08.30`)

Pulled into `0.1.0` at the user's request during live review. A first pass
used a `Settings` window with typeface and size sliders on `UserDefaults`;
the user then asked for every tunable value in one live-reloaded file so it
can be edited in real time and grow to colour themes. The window was replaced.

Implemented:

- `~/.config/serein/config` (`$XDG_CONFIG_HOME` honoured), `key = value`
  lines with `#` comments, no parser dependency. Written from a commented
  template on first launch; the template parses to the defaults (tested).
- Keys: `font.family`, `font.size`, `line.height`, `paragraph.spacing`,
  `measure`, `heading.weight` (regular|medium|semibold|bold). Unknown keys ignored; invalid values fall back; numbers
  clamp to sane ranges.
- `ConfigurationStore` watches file and directory via `DispatchSource`,
  coalesces event bursts, re-arms after atomic replacement, and posts
  `Configuration.didChangeNotification`. Text views refont, re-inset, and
  restyle.
- `Appearance` reads the live configuration for the tunable tokens.
- Settings scene (`⌘,`) has a slider or picker per key and writes through
  `ConfigurationStore.write`, which merges into the file text preserving
  comments (user asked to keep the controls alongside the file).
- A paperize-style edge vignette was tried (radial shading, then an
  irregular blurred frame with a wobbled outline) and removed at the user's
  request: neither felt natural. Not planned again.

Follow-on keys: colour theme (`canvas`, `ink` as hex; also stored in presets),
caret style, top margin.

---

## 9. Risks and controls

### Risk 1 — Styling changes source or undo history

`NSTextStorage` attributes can trigger layout and delegate behavior. Keep source
serialization separate from attributed state. Add explicit tests that styling
leaves the string unchanged. Confirm undo records text edits only.

### Risk 2 — Full-document regex styling becomes slow

The scaffold may restyle the complete source after each edit. Measure before
optimizing. If `100 KB` documents visibly lag, debounce styling and restrict it
to affected paragraphs. Do not add a parser solely as a performance guess.

### Risk 3 — Markdown regex ranges fail on Unicode

`NSRegularExpression` uses UTF-16 `NSRange`. Keep all attribute ranges in UTF-16
space and test composed Unicode and emoji. Do not convert through Swift string
indices unless the conversion is explicit and tested.

### Risk 4 — Window configuration races attachment

An `NSViewRepresentable` may be created before it has a window. Configuration
must be idempotent and run again after attachment. Do not depend on a single
deferred callback.

### Risk 5 — Background dragging interferes with editing

`isMovableByWindowBackground` may treat empty areas inside the text view as
window drag regions. Verify selection and insertion in blank document regions.
Disable background dragging if it harms editing.

### Risk 6 — Swift 6 flags AppKit globals as unsafe

AppKit types may not satisfy Sendable checks. Keep visual state main-actor
isolated or compute it through main-actor functions. Do not use unchecked
Sendable conformance for convenience.

### Risk 7 — Source mode does not feel sufficiently rendered

Closed `2026.08.30`. The scaffold intentionally retained punctuation until
typography was strong. Contextual concealment of heading markers then shipped
per [concealment.md](concealment.md): hidden on every paragraph the cursor is
not on, via `.null` glyph properties in the layout manager, never by editing
storage. Inline and block-quote markers remain visible pending Phases 2–3.

---

## 10. Commands

Run from the Serein project unless stated otherwise.

Inspect:

```bash
git status --short --branch
git remote -v
find . -maxdepth 4 -type f -not -path './.git/*' | sort
```

Generate:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild \
  -project Serein.xcodeproj \
  -scheme Serein \
  -configuration Debug \
  -derivedDataPath /tmp/serein-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Test:

```bash
xcodebuild \
  -project Serein.xcodeproj \
  -scheme Serein \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/serein-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Launch for manual verification:

```bash
open /tmp/serein-derived-data/Build/Products/Debug/Serein.app
```

Workspace checks from the humanitas workspace root:

```bash
kdb projects show serein --json
kdb check
```

---

## 11. Handoff instructions

Claude should execute this plan in order and retain its scope.

1. Read the workspace `AGENTS.md` and any nearer project
   instructions before acting.
2. Follow the Humanitas code SOP. The plan is already approved.
3. Begin with current-state inspection. Existing files are drafts, not validated
   implementation.
4. Use `apply_patch` for text-file edits.
5. Preserve unrelated changes and never use destructive Git commands.
6. Resolve compiler and test failures from evidence. Do not weaken strict
   concurrency or delete tests to make the build green.
7. Keep the first release Mac-only, file-based, and free of permanent chrome.
8. Do not add dependencies unless a verified requirement cannot be met with the
   platform frameworks.
9. Do not commit. Return the completed diff and verification evidence for user
   review.
10. If a requirement conflicts with source preservation or native editing
    correctness, preserve correctness and report the exact conflict.

