# Paper

Last updated: `2026.08.30`

> A quiet native macOS editor for ordinary Markdown files.

Paper is the working name. The code, bundle, and configuration path still
use the original name, Serein (`~/.config/serein/`), until the name is final.

Serein is designed around one surface: a warm, centered page with editorial
serif typography. It has no document library, account, database, toolbar,
sidebar, or proprietary format. The file remains Markdown on disk.

## Current scaffold

Version `0.1.0` proves the native document architecture:

- SwiftUI document application with an AppKit `NSTextView` editor;
- native new, open, save, autosave, undo, find, spelling, and multiwindow
  behavior;
- transparent title bar and no app-owned window chrome;
- settings in a plain-text file, `~/.config/serein/config` (or under
  `$XDG_CONFIG_HOME`), written with commented defaults on first launch and
  applied live to open windows on save: typeface, size, line height, paragraph
  spacing, measure, heading weight, theme (paper, sepia, slate, mono), and
  per-colour hex overrides; Settings (`⌘,`) edits the
  same keys with sliders and writes them back into the file, and saves,
  applies, and deletes named presets stored in `~/.config/serein/presets/`;
- typeface defaults to Test Family at 14 pt when installed and otherwise the
  system serif; no bundled font;
- responsive centered measure (`640 pt` maximum, `64 pt` minimum margins) with
  adaptive warm light and dark appearances;
- heading markers and inline delimiters (`**`, `*`, `` ` ``) hidden on every
  paragraph the cursor is not on, with the full source shown on the paragraph
  being edited; `-` items rendered as a dashed list and `*` items as a
  bulleted list, hanging under their text; block-quote markers visible but
  subdued; and
- exact UTF-8 source preservation.

Inline rendering, concealment of block-quote markers, export, and a file
library are outside the scaffold boundary.

## Generate

Serein uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so project
structure remains reviewable in `project.yml`. The generated `Serein.xcodeproj`
is ignored by Git; regenerate it after cloning or editing `project.yml`.

```bash
xcodegen generate
```

## Build and test

```bash
xcodebuild -project Serein.xcodeproj -scheme Serein \
  -configuration Debug build

xcodebuild -project Serein.xcodeproj -scheme Serein \
  -configuration Debug -destination 'platform=macOS' test
```

The build is warning-free under Swift 6 strict concurrency. Tests cover
byte-exact UTF-8 round trips, malformed input rejection, and the invariant that
styling never changes the text storage string.

Setting `TEST_RUNNER_SEREIN_PROBE_DIR=<dir>` (containing a `fixtures/`
directory with `sample.md`, `10k.md`, `100k.md`, and `1m.md`) makes the test
run also write offscreen renders and restyle timings into that directory for
visual review. Without it those probes are skipped.

## Run locally

After building, open the Debug application produced in Xcode's Derived Data, or
open `Serein.xcodeproj` and run the `Serein` scheme.

## Architecture

- [Current architecture](docs/architecture.md)
- [ADR-001 — Native document editor](docs/decisions/001-native-editor.md)
- [Scaffold plan](.plan/scaffold.md)

