# Paper

> A quiet, native macOS editor for ordinary Markdown files.

![A Markdown document set as a clean serif page in Paper](docs/assets/paper.png)

Paper is an experiment in absolute simplicity.

## Goals

- *Minimalism* — there is too much noise in the existing editors that I’ve used. I find they have too many controls, and as a result are not conducive to thought.
- *Focus* — Deliberately rendering only a single document at a time.
- *Customizable* — Everyone loves a good theme, and I often want to change the vibe depending on what I’m writing.
- *Conducive to thought* — It is easy to dismiss the medium, but I believe our tools unconsciously shape our expression.

## Stylistic choices

- *Typography* — a centered measure with real margins; headings stepped
  from the body size; block quotes inset and italic behind a hairline rule.
- *Lists* — Apple Notes' two kinds: `-` draws as a dashed list (–), `*`
  as a bulleted one (•). Items hang under their text, hard-wrapped lines
  align, and ordered markers may carry a letter (`1a)`). Return continues
  the list — markers repeat, numbers count up — and Return on an empty
  item ends it.
- *Code* — fenced blocks set in mono on a quiet band, their content
  literal and their fences tucked away; inline `code` in mono too.
- *Links* — underlined text with the syntax concealed. Click opens the
  destination; relative paths resolve against the document.
- *Typed substitutions* — `->` becomes → as you type, like smart dashes;
  ⌘Z gives the pair back.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘B / ⌘I / ⌘U / ⌘E | toggle `**bold**`, `*italic*`, `<u>underline</u>`, `` `code` `` around the selection or word |
| ⌘K | add a link, destination from the clipboard when it holds a URL |
| click / ⌘-click | open a link |
| ⌘, | settings |

## Configuration

Everything lives in `~/.config/paper/config` (`$XDG_CONFIG_HOME` honoured), written as a commented template on first launch and applied live to open windows whenever it is saved:

```ini
font.family = Test Tiempos Text
font.size = 16
line.height = 1.11
letter.spacing = 0.02
measure = 655
theme = slate
window.width = 1374
window.height = 877
```

Themes:

`paper`, `slate`, `mono`, `spatial`, `apple`, each with light and dark palettes, plus per-colour hex overrides. The Settings window (⌘,) edits the same keys with controls and writes them back into the file, comments preserved. Named presets are files too, in `~/.config/paper/presets/`; edits write through to the active preset.

## Command line

The app bundles a small launcher. Put it on your PATH once:

```sh
ln -s /Applications/Paper.app/Contents/Resources/paper /usr/local/bin/paper
```

Then `paper notes.md` opens a document, creating it first when it doesn't exist yet, and `paper` alone opens the app.

## Default app for Markdown

To make double-clicking a `.md` file open Paper: select any Markdown file in Finder, press ⌘I (Get Info), choose Paper under **Open with**, and click **Change All…** — that applies to every `.md` file. Repeat once for `.markdown` if you use that extension.

## More

- [Build and test](docs/build.md)
- [Architecture](docs/architecture.md)
- [Using Paper with Claude](docs/claude.md)
