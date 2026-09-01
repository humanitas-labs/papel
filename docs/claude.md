# Using Paper with Claude (and other agents)

Paper works well as the reading surface for Markdown an agent writes: the agent edits the file, Paper renders it live (documents reload from disk whenever the window has no unsaved edits).

To wire it up, ask your agent to add a note to its instruction file (`~/.claude/CLAUDE.md` for Claude Code, or your project's `AGENTS.md`). You can paste this prompt:

> Add the following to my global instructions: Markdown files are read in Paper (a native macOS editor). To show me a document, open it with `paper <file.md>` (or `open -a Paper <file.md>`). Paper reloads clean documents from disk automatically, so after the first open just keep editing the file. Never hard-wrap prose in Markdown — a paragraph is one source line; fixed-width wrapping renders as broken mid-paragraph lines.

The pieces, individually:

- *Opening documents* — `paper file.md` once the [CLI](../README.md#command-line) is installed, or `open -a Paper file.md` without it.
- *Live reload* — Paper watches the open file and reloads it when it changes on disk, as long as the document has no unsaved edits in the window. An agent editing the file is enough; no re-open needed.
- *No hard-wrapped prose* — Paper renders Markdown, so a source line break inside a paragraph shows as a break. Agents that wrap prose at 80 columns ruin the reading flow; tell yours to keep each paragraph on one line.
