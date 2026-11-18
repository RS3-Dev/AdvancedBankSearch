# Advanced Bank Search

Search your RuneScape bank with RuneQL, build visual queries, and organize saved searches into folders. The search interface lives in Bank Core’s bank sidebar.

## Install from source

Install and enable PrettyUI, Bank Core, RuneQL, and GE Prices in your client first. Copy `main.lua`, `plugin.json`, and the entire `resources/` directory into your client’s `plugins/advancedbanksearch/` folder, then load the plugin (or run `prl advancedbanksearch` to reload it). No build step is needed. The manifest keeps the published plugin name, Advanced Bank Search, and version 1.0.2.

The repository root is the runtime root. `resources/app.lua` connects the plugin, `resources/settings.lua` handles settings, `resources/core/` contains shared helpers, and `resources/search/` contains search, saved queries, and their interface. Keep those paths intact.

## Tests

See [tests/README.md](tests/README.md) for Lua 5.4, dependency paths, and test coverage. Run `lua54 tests/check.lua` from this directory. `tests/` contains the test suite and its tooling, which are not needed by the client.

For a runtime ZIP, archive only `main.lua`, `plugin.json`, and `resources/`, directly at the ZIP root. Tests and this README stay outside the runtime package.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

[BSD 2-Clause](LICENSE), copyright 2026 Advanced Bank Search contributors.
The license notice is also included in `main.lua` so runtime packages retain it.
