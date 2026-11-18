# Contributing

Keep Advanced Bank Search small, readable and focused on searching bank items,
building RuneQL queries and organizing saved searches. Shared bank integration belongs in Bank Core.

- Open an issue before adding or changing a public API so we can discuss the need
  and how other plugins would use it.
- Keep pull requests focused. Avoid unrelated rewrites, new dependencies and
  abstractions that make a simple change harder to follow.
- Use clear names and short comments that a new junior developer can follow.
  Explain necessary technical terms in plain language; avoid repeating the code.
- AI assistance is welcome, but you must understand and review everything you
  submit. Do not submit code you cannot explain or maintain.
- Do not use AI to generate your PR body. The PR body must be handwritten.
  Pull requests with AI-generated bodies will be closed.
- Run `lua54 tests/check.lua` with Lua 5.4 from the repository root. Set `BANKCORE_ROOT`,
  `RUNEQL_ROOT` and `PRETTYUI_ROOT` to the dependencies used by the suite. See
  the [test instructions](tests/README.md) for details.
- Try your changes in RuneScape. For input or layout changes, check bank opening
  and closing, reloads, typing searches, saving and editing queries, dragging,
  scrolling and different interface scales.
- Explain what changed, why, how you checked it and any problems still known.
  Update the docs or examples when their behavior changes.

Contributions use the project's [BSD-2-Clause license](LICENSE).
