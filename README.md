# Papel

> A quiet, native markdown editor for macOS.

![Papel showing its own README: a heading, an italic quote behind a rule, and a photograph of a raked rock garden](docs/assets/papel.png)

Papel is the simplest markdown editor imaginable.

There is nothing other than the text, by design.

In most editors, every button seems to invite you to do something other than write (or read). Here, there are no controls, and only one document opens per own window so you can focus with no distractions. Every choice has been made in favor of singular focus. Feel free to [fork](https://github.com/humanitas-labs/papel/fork) if that philosophy doesn’t suit your needs.

It is a descendant of Obsidian’s file > app philosophy. Apps are ephemeral, but files last—and you should own them. Everything is just a file on your computer.

Lastly, it is free and open. We will continue our campaign to make delightful software abundant again.

## CLI

> Meant to be used as a companion to agents. Let them open the files for you while you work.

`papel notes.md` opens a document from the terminal, creating it first when it doesn't exist yet; `papel` alone opens the app. Papel installs it on first launch when a directory you own is on your shell's PATH, such as `/opt/homebrew/bin` or `~/.local/bin`, and repairs the link when the app moves. When only `/usr/local/bin` is available, install it from Settings (⌘,) under CLI, which asks for your password; the same section shows where the command lives and removes it. The launcher itself is at `Papel.app/Contents/Resources/papel`.

Give this prompt to your agent of choice (it is also in the guide Papel opens on first launch, and under Guide on the welcome window):

> Add the following to my global instructions:
>
> "Markdown files are read in Papel (a native macOS editor). To show me a document, open it with `papel <file.md>`. Papel reloads clean documents from disk automatically, so after the first open just keep editing the file. Never hard-wrap prose in Markdown — a paragraph is one source line; fixed-width wrapping renders as broken mid-paragraph lines."
>
> Then check that the `papel` command works: write a short Markdown note to a temporary file and open it with `papel`. If the command is not found, tell me; it installs from Papel's Settings (⌘,) under CLI.
>
> Finally, ask me explicitly whether I want Papel to be the default app for Markdown files, and explain what that means: double-clicking a .md file in Finder would open it in Papel instead of the current app. Do not change anything until I answer. Only if I say yes, run `papel --set-default`.

## Default app for Markdown

`papel --set-default` makes double-clicking a `.md` or `.markdown` file open Papel; so does *Make Default* in Settings (⌘,) under CLI. By hand: select any Markdown file in Finder, press ⌘I (Get Info), choose Papel under *Open with*, and click *Change All*….

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘B / ⌘I / ⌘U / ⌘⇧X / ⌘E | toggle `**bold**`, `*italic*`, `<u>underline</u>`, `~~strikethrough~~`, `` `code` `` around the selection or word |
| ⌘K | add a link, destination from the clipboard when it holds a URL |
| ⌘F / ⌘G / ⇧⌘G | find; next and previous match. Return and ⇧Return step from the field, Esc closes |
| click / ⌘-click | open a link |
| double-click an image | open it in Quick Look |
| paste or drop an image | saved beside the document, inserted as `![](…)` |
| ⌘+ / ⌘− / ⌘0 | zoom the view in and out, back to actual size; click the badge at the top right to type a percentage; per machine, never written to the config |
| ⌘, | settings |

Pasting or dropping an image into an unsaved document asks you to save first. Images go beside the document by default; set `image.paste.directory = assets` to use a relative subfolder instead. Undo removes the inserted Markdown, but keeps the image file.

## Configuration

Settings live in `$XDG_CONFIG_HOME/papel/config` when set, otherwise `~/.config/papel/config`. The file is written as a commented template on first launch and applied live to open windows whenever it is saved. Selected defaults are shown below; the generated template documents every key.

```ini
font.family = New York
font.size = 15
line.height = 1.2
paragraph.spacing = 11
letter.spacing = -0.02
font.smoothing = off
spelling = on
grammar = on
measure = 640
list.indent = 0.8
theme = enso
window.width = 1400
window.height = 876
```

## More

- [Build and test](docs/build.md)
- [Architecture](docs/architecture.md)
