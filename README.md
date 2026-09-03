# Papel

> A quiet, native markdown editor for macOS.

![Papel showing its own README: a heading, an italic quote behind a rule, and a photograph of a raked rock garden](docs/assets/papel.png)

Papel is the simplest markdown editor imaginable.

There is nothing other than the text, by design.

In most editors, every button is a standing invitation to do something other than write (or read). Here, there are no controls, and only one document opens per own window so you can focus with no distractions. Every choice has been made in favor of singular focus. Feel free to [fork](https://github.com/humanitas-labs/papel/fork) if that philosophy doesn’t suit your needs.

It is a descendant of Obsidian’s file > app philosophy. Apps are ephemeral, but files last—and you should own them. Everything is just a file on your computer.

Lastly, it is free and open. We will continue our campaign to make delightful software abundant again.

## CLI

> Meant to be used as a companion to agents. Let them open the files for you while you work.

`papel notes.md` opens a document from the terminal, creating it first when it doesn't exist yet; `papel` alone opens the app. Papel installs it on first launch when a directory you own is on your shell's PATH, such as `/opt/homebrew/bin` or `~/.local/bin`, and repairs the link when the app moves. When only `/usr/local/bin` is available, install it from Settings (⌘,) under CLI, which asks for your password; the same section shows where the command lives and removes it. The launcher itself is at `Papel.app/Contents/Resources/papel`.

Give this prompt to your agent of choice (it is also in the guide Papel opens on first launch, and under Guide on the welcome window):

> Add the following to my global instructions: 
>
>Markdown files are read in Papel (a native macOS editor). To show me a document, open it with `papel <file.md>`. Papel reloads clean documents from disk automatically, so after the first open just keep editing the file. Never hard-wrap prose in Markdown — a paragraph is one source line; fixed-width wrapping renders as broken mid-paragraph lines.

## Default app for Markdown

To make double-clicking a `.md` file open Papel: select any Markdown file in Finder, press ⌘I (Get Info), choose Papel under *Open with*, and click *Change All*… — that applies to every `.md` file. Repeat once for `.markdown` if you use that extension.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘B / ⌘I / ⌘U / ⌘⇧X / ⌘E | toggle `**bold**`, `*italic*`, `<u>underline</u>`, `~~strikethrough~~`, `` `code` `` around the selection or word |
| ⌘K | add a link, destination from the clipboard when it holds a URL |
| click / ⌘-click | open a link |
| double-click an image | open it in Quick Look |
| ⌘, | settings |

## Configuration

Everything lives in `~/.config/papel/config` (`$XDG_CONFIG_HOME` honoured), written as a commented template on first launch and applied live to open windows whenever it is saved:

```ini
font.family = New York
font.size = 16
line.height = 1.11
letter.spacing = 0.02
font.smoothing = off
measure = 655
theme = slate
window.width = 1374
window.height = 877
```

## More

- [Build and test](docs/build.md)
- [Architecture](docs/architecture.md)
