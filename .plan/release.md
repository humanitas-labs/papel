# Release gate

Status: open — Paper is public on GitHub but not announced.

Do not announce (Twitter or otherwise) until these three ship:

1. ~~**List continuation on newline**~~ — shipped `a1dd635`, #8 closed.
   Return inside a list item starts the next item (`-`/`*`/`+` repeat
   their marker; `3.`, `3)`, `1a)` increment); return on an empty item
   leaves the list; shift-return hard-wraps.
2. **Inline images** —
   [#6](https://github.com/humanitas-labs/paper/issues/6). `![alt](src)`
   drawn in the flow, syntax concealed, source untouched.
3. **Fenced code blocks** —
   [#5](https://github.com/humanitas-labs/paper/issues/5). Mono font and a
   quiet background; fences concealed; no highlighting required.

Nice-to-have but not gating: pipe tables
([#7](https://github.com/humanitas-labs/paper/issues/7)), formatting-era
polish already shipped (concealment, links, ⌘B/I/U/E/K, themes, presets,
typed →, eased wheel scrolling).

When the three close: re-render the README shot if the page changed, tag
`v0.2.0`, then announce.
