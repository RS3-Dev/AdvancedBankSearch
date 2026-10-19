# Advanced Bank Search

Advanced Bank Search (`advancedbanksearch`) is a standalone plugin for searching the bank with RuneQL queries and keeping saved searches. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) and reaches the bank only through Bank Core's public extension API: no private Core module or native bank component is used, and the bank's own search is left alone. What it uses from Bank Core and Bank Tags is in [CONTRACT.md](CONTRACT.md); the plan it was built from is in [docs/STANDALONE_PLAN.md](docs/STANDALONE_PLAN.md).

Everything here is checked against Bank Core's stand-in host and the installed RuneQL only. Nothing in this repository has been verified in the live client yet; see [Not yet verified live](#not-yet-verified-live).

## Features

- **Search tab.** A sidebar tab with a RuneQL search field, a status line, your saved searches with how many stacks each matched last, and New, Edit, and Delete.
- **Search page.** Typing two or more characters ranks the bank's stacks against the text, best match first and ties in bank order, and shows them in the bank, placeholders included. Each new search starts at the top; a bank change ranks the same search again and keeps your place. Clearing the text returns to the bank.
- **Saved searches.** Choosing one shows its page, placeholders left out; choosing it again returns to the bank. New and Edit open an editor for the name (up to 40 characters) and the query (up to 9,999). Delete asks you to press it again.
- **Prices.** A search that uses `price`, `gehigh`, or `gelow` needs GE Prices. Until prices load, its page says it is waiting, and it is ranked once they arrive (checked every 30 ticks, for up to 1,800); it is never ranked on missing prices. Without GE Prices its page says it is needed. Other searches never need GE Prices.
- **Convert to a tag.** With Bank Tags loaded, its Import window lists "Saved bank search": type a saved search's name and Bank Tags previews a tag holding exactly the stacks the search matches now.
- **Plugin panel.** Says whether the plugin is in the bank, and whether Bank Core or RuneQL is needed.

## Requirements and load order

- **PrettyUI** is a required dependency.
- **Bank Core** (`bankcore`) is needed for anything in the bank.
- **RuneQL** (`runeql`) is needed to search and to save. Without it the field and Save are disabled, saved searches stay listed, and the tab says RuneQL is needed; there is no fallback search.
- **GE Prices** (`geprices`) is needed only for searches that use price fields.
- **Bank Tags** (`banktags`) is needed only to convert a saved search to a tag.

All four are declared as optional dependencies because the host reports changes only for optional dependencies. Any load order works: the plugin connects when Bank Core loads, reconnects when it reloads, and lets go when it unloads. Once the host reports RuneQL, GE Prices, or Bank Tags unloaded, the plugin stops using it, even if its global remains, until it is reported loaded again. Reloading the plugin shuts down the previous copy in the same Lua state first; a copy whose owner ID a newer load took stays idle.

**Old installs.** The old integrated `bankutils` plugin (and the older `bankutilities`) also replaced the bank search and had a Queries tab. They are not expected to work against this Bank Core; disable them so search is not loaded twice.

## Saved data

- Saved searches are kept under `advancedbanksearch:queries:v1:*` in this plugin's own saved data.
- **A new install starts with no saved searches.** Each plugin's saved data is separate, so this plugin cannot read the old Bank Utilities plugin's `bankutils:runesql:*` searches, and it never changes or deletes them. To keep an old search, copy its query text from the old plugin, if you can still open it, into New here.
- A save that cannot be written is reported in the editor and nothing changes. A save that cannot be read is reported in the tab and never overwritten; nothing is saved until it is fixed.

## Changes from the old integrated plugin

- The search field is in the Search tab, not in place of the bank's own search box, which is no longer hidden or moved. The `enableAdvancedSearch` and `enableRuneSQL` preferences are gone: enabling the plugin is the switch. There is no settings section.
- Delete and Convert to tag left the right-click menu: Delete is a button in the tab, and conversion starts from Bank Tags' Import window.
- A price search waiting for GE prices shows that it is waiting instead of ranking without prices, which could match the wrong items.
- Converting matches exactly the stacks found. A search that matches a later stack of an item without its first (for example by quantity) cannot be converted, because Bank Tags numbers an item's stacks in the order listed; the source says so instead of tagging another stack. A search of more than 1,999 stacks is refused rather than cut short.
- Saved searches start empty in the new plugin's own saved data (see above).

## Layout

- `plugins/advancedbanksearch/`: the entry (`main.lua`) and manifest.
- `advancedbanksearch/`: every runtime module, under `search/` and `core/`.
- `tools/`: the build and check tools adapted from Bank Tags', the harness that loads Bank Core beside the plugin, a loader for the installed RuneQL, and a stand-in for Bank Tags' import API.
- `tests/`: the tests; see [tests/README.md](tests/README.md).
- `reference/`: the preserved source from Bank Utilities `beba274`; see [reference/README.md](reference/README.md). `EXTRACTION_MANIFEST.json` records where each preserved file came from.

## Build and check

```text
lua54 tools/build.lua
lua54 tools/check.lua
```

The build writes only `dist/release/advancedbanksearch/`: `main.lua`, `plugin.json`, and the modules the entry's require graph loads, with the module eviction list generated from that graph. The check builds into `dist/check`, runs every test, compiles every built file, and fails on unexpected globals, a runtime source the entry never loads, or anything from `reference/`, `tests/`, or `tools/` in the package. Tests read Bank Core from `BANKCORE_ROOT` and RuneQL from `RUNEQL_ROOT`, and the combined test reads Bank Cleaner's build from `BANKCLEANER_DIST`.

To install, copy `dist/release/advancedbanksearch/` into the client's plugins folder as `advancedbanksearch`.

## Not yet verified live

- Keyboard focus and typing in the search field inside Bank Core's mounted column, and PrettyUI's list and buttons there.
- That GE Prices is reported to dependents as `geprices`: its folder is `geprices`, but its manifest names it "Ge Price Library" and its README says `gepl`. If the host uses another identifier, price searches will say GE Prices is needed.
- Whether saved data is scoped per plugin, when the host calls `PluginDependencyUpdate` on reloads, whether it re-injects globals, and how it clones exports.
- How the editor window draws over the bank.
