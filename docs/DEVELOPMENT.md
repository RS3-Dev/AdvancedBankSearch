# Developer reference

These are implementation, build, migration, and validation notes. For first-time player instructions, read the [player guide](../README.md). Historical implementation notes are not a statement of release readiness.

# Advanced Bank Search

Advanced Bank Search (`advancedbanksearch`) is a standalone plugin for searching the bank with RuneQL queries and keeping saved searches. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) and reaches the bank only through Bank Core's public extension API: no private Core module or native bank component is used, and the bank's own search is left alone. What it uses from Bank Core is in [CONTRACT.md](../CONTRACT.md); the plan it was built from is in [docs/STANDALONE_PLAN.md](../docs/STANDALONE_PLAN.md).

Everything here is checked against Bank Core's stand-in host and the installed RuneQL only. Nothing in this repository has been verified in the live client yet; see [Not yet verified live](#not-yet-verified-live).

## Features

- **Search column.** One rail icon opens the item search field, saved query/folder tree, and native bank-style Share/New Query buttons with a pencil Edit action while a query is selected. Search is full-width with eight-unit side insets and eight units before the list. It never displays status text beneath the field. Row spacing, folder accents, selected outlines and item icons follow Bank Tags.
- **Search page.** Typing two or more characters ranks the bank's stacks against the text, best match first and ties in bank order, and shows them in the bank, placeholders included. An item matched in several stacks is listed once per matching stack, and Bank Core shows its stocked stacks first, then placeholders, so which of its stacks shows is Core's choice. Each new search starts at the top. Once resolved, bank changes update quantities without replacing the result list; withdrawn items keep their slots as placeholders until the page is reloaded. Pages still waiting for readable bank items retry on bank changes. Clearing the text returns to the bank. When the bank cannot show the page, the status line says why.
- **Saved searches.** Choosing one shows its page, placeholders left out; choosing it again returns to the bank. New and Edit open an editor in the bank item area for the name (up to 40 characters) and the query, built in Visual or typed in Advanced (up to 9,999 characters). The row menu offers Remove with a confirmation dialog.
- **Visual queries.** New searches start in Visual: up to 6 conditions total, each a field, a comparison, an exclusion toggle, and a value. Each group matches all (AND) or any (OR); Add group supports up to 6 groups and 3 nested levels. Trash buttons remove conditions and whole groups. The editor shows the RuneQL it will save, or what a condition is missing, and Save sends that RuneQL through the same check as typed text.
  - *Item name* has phrase (the words together, in order) or has all words (each anywhere). Words are whole words in any case, so "bone" does not find "bones". What you type is always quoted, so `OR`, `*`, brackets, and quotes are searched as words and never become RuneQL.
  - *Quantity*, *GE price*, *GE high price*, and *GE low price* *is*, *is at least*, *is at most*, or *is between*. Every comparison includes the number itself, so *is at least 10* matches 10. Numbers are whole, from 0 to 2,147,483,647, and can use commas or k, m, or b (`25k`, `1.5m`). GE price is the high price, or the low one when there is no high price; prices are per item, not per stack, and an item without that price never matches.
  - Catalog fields, their labels, and their types come from RuneQL's `Catalog.Fields()` API; their choices come from `Catalog.Values()` when a field is selected or edited. Category, types, subtype, skills, roles, combat style, armour role, slot, weapon type, family, set, form, container type, storage locations, and reclaim sources use scalar or list comparisons, with a selectable grid of catalog values. Selection fills the canonical value and collapses the grid; clearing the value reopens it. Typing filters the choices. The grid has 24 buttons and pages larger lists, so it never creates one control per catalog value. Catalog scalar text uses is/is not; catalog lists use includes/does not include. New conditions use exact whole-value, case-insensitive comparisons. Negatives require a known, nonempty field. Older phrase/word catalog conditions still reproduce their saved RuneQL, but reopen in Advanced to preserve those matching semantics. Tier, dose, and base value use the number comparisons. Augmentable, augmented, degradable, tradeable, GE tradeable, members, and reclaimable use *is true* or *is false* without a value input; unknown flags match neither. RuneQL resolves attributes from each bank object's stable config name. Base value needs no GE Prices dependency.
  - *Advanced* shows the conditions' RuneQL for typing expressions, fuzzy words, and the rest of RuneQL. The Plugin Hub Query builder preference selects the mode for new and saved queries and updates the open editor after persistence succeeds. Typed queries without visual metadata open in Advanced. Switching a detached Advanced draft to Visual retains its text until saving visual conditions; returning to Advanced without changing the conditions restores that text. Incomplete conditions leave Advanced text unchanged. There are no in-editor mode tabs.
- **Folders.** As in Bank Tags, folders hold saved searches. A folder row shows how many it holds; click it to open or close it, which changes neither the chosen search nor the page shown. A closed folder is outlined when the chosen search is inside. Right-click a search for Edit, Move to folder (pick a folder, No folder, or type a new folder's name and press Create), and Remove from folder; right-click a folder for Expand or Collapse, Rename folder, and Ungroup folder, which removes the folder and keeps its searches where it was. A folder can be empty. New searches go at the bottom, outside any folder; editing a search keeps its folder and place, and deleting it takes it out of its folder.
- **Reordering.** The Bank Tags drag implementation is ported into the query list: a six-unit threshold, held-row cover, ghost, insertion line, edge scrolling and cancellation on refresh, resize or unmount. Queries move among their siblings; expanded and collapsed folders move as whole blocks. Name/icon editing and the 8-by-5 item picker also follow Bank Tags, with plugin-specific paths and callbacks. Icons use stable config names or #id references and survive renames, folders, condition edits and reloads.
- **Prices.** A search that uses `price`, `gehigh`, or `gelow` needs GE Prices. Until prices load, its page says it is waiting, and it is ranked once they arrive (checked every 30 ticks, for up to 1,800); it is never ranked on missing prices. Without GE Prices its page says it is needed. Other searches never need GE Prices.
- **No plugin window entry.** Advanced Bank Search has no ribbon icon or panel in the Plugins window; everything it shows is in the bank.

## Requirements and load order

- **PrettyUI** is a required dependency.
- **Bank Core** (`bankcore`) is needed for anything in the bank.
- **RuneQL** (`runeql`) is needed to search and to save. Without it the field and Save are disabled, saved searches stay listed, and the column says RuneQL is needed; there is no fallback search.
- **GE Prices** (injected as `gepl`) is needed only for searches that use price fields.

PrettyUI, Bank Core, RuneQL, and GE Prices are declared in `requiredDependencies`. The local manifest uses `"bankcore": "bankcore"`, `"runeql": "runeql"`, and `"gepl": "geprices"`; PrettyUI retains its mod.io ID. The host injects their exports before startup. Defensive dependency-change handling remains for reload recovery and fault-injection tests; the real host reports `PluginDependencyUpdate` for optional dependencies. Reloading the plugin shuts down the previous copy in the same Lua state first.

**Old installs.** The old integrated `bankutils` plugin (and the older `bankutilities`) also replaced the bank search and had a Queries tab. They are not expected to work against this Bank Core; disable them so search is not loaded twice.

## Settings

The manifest enables `hasSettingsIcon`. `resources/settings.lua` subscribes to `Event.SettingsLayerReady` and mounts a PrettyUI SimpleView in `event.component`. Remounting destroys the previous view; shutdown unsubscribes and destroys the current view. Stale control callbacks are ignored. Settings do not create a ribbon panel or subscribe to ContentLayerReady.

Validated preferences are stored as one JSON string at `advancedbanksearch:settings:v1`. Defaults are Visual for new editors, placeholders included for quick searches, and 10 logic ticks (200 ms) of debounce. Choices are Visual/Advanced, include/hide placeholders, and 5/10/20 ticks. A preference is applied only after persistence succeeds; a failed write rolls back the selection and shows an error. Missing or malformed persisted values use defaults without rewriting the stored data during load.

Changing placeholder visibility refreshes the active quick search. Changing the delay restarts any pending search wait. Saved queries always exclude placeholders, and the Query builder preference applies to existing searches with saved visual conditions too.

## Saved data

- Saved searches are kept under `advancedbanksearch:queries:v1:*` in this plugin's own saved data.
- **A new install starts with no saved searches.** Each plugin's saved data is separate, so this plugin cannot read the old Bank Utilities plugin's `bankutils:runesql:*` searches, and it never changes or deletes them. To keep an old search, copy its query text from the old plugin, if you can still open it, into New here.
- A search made in Visual saves its conditions beside its query text, which stays what is searched. Conditions are used only while they still give exactly that text; otherwise the search opens in Advanced. Conditions for unavailable catalog fields are retained until RuneQL loads, then checked against its current metadata. Searches saved before this load and save as they were.
- Folders and the order are saved in the same keys. A save from before folders loads with every search outside any folder, in its saved order, with the same IDs; a folder change or a new order cannot be read by those earlier builds, which would save over it without folders.
- A query RuneQL cannot read is refused in the editor with RuneQL's reason, and a save that cannot be written is reported there; either way nothing changes and the editor stays open. Saving a query drops its old count; a shown query is counted again at once. A save that cannot be read is reported in the column and never overwritten; nothing is saved until it is fixed.

## Changes from the old integrated plugin

- The search field is in the Search column, not in place of the bank's own search box, which is no longer hidden or moved. The `enableAdvancedSearch` and `enableRuneSQL` preferences are gone: enabling the plugin is the switch. Preferences are available through the Plugin Hub settings cog, using SettingsLayerReady rather than ContentLayerReady.
- Delete is a button in the column. The right-click menu holds folder actions.
- A price search waiting for GE prices shows that it is waiting instead of ranking without prices, which could match the wrong items.
- Results name items, not particular stacks: an item matched in some of its stacks shows that many of its stacks, stocked ones first.
- Saved searches start empty in the new plugin's own saved data (see above).

## Layout

- `plugins/advancedbanksearch/`: the entry (`main.lua`) and manifest.
- `resources/`: every runtime module, under `search/` and `core/`.
- `tools/`: the build and check tools adapted from Bank Tags', the harness that loads Bank Core beside the plugin, a loader for the installed RuneQL.
- `tests/`: the tests; see [tests/README.md](../tests/README.md).
- `reference/`: the preserved source from Bank Utilities `beba274`; see [reference/README.md](../reference/README.md). `EXTRACTION_MANIFEST.json` records where each preserved file came from.

## Build and check

```text
lua54 tools/build.lua
lua54 tools/check.lua
```

The build writes only `dist/release/advancedbanksearch/`: `main.lua`, `plugin.json`, and the modules the entry's require graph loads, with the module eviction list generated from that graph. The check builds into `dist/check`, runs every test, compiles every built file, and fails on unexpected globals, a runtime source the entry never loads, or anything from `reference/`, `tests/`, or `tools/` in the package. Tests read Bank Core from `BANKCORE_ROOT` and RuneQL from `RUNEQL_ROOT`, and the combined test reads Bank Cleaner's build from `BANKCLEANER_DIST`.

To install, copy `dist/release/advancedbanksearch/` into the client's plugins folder as `advancedbanksearch`.

Release ZIPs contain one top-level `advancedbanksearch/` folder. Inside it are `main.lua`, `plugin.json`, and `resources/`; the latter holds `app.lua`, `settings.lua`, `core/`, and `search/`. Package the built folder itself, rather than its contents.

## Not yet verified live

- Keyboard focus and typing in the search field inside Bank Core's mounted column, and PrettyUI's list and buttons there.
- The local manifest binds the `geprices` plugin directory to the `gepl` variable used by this plugin. That alias is controlled by our manifest, independently of the library's name. Live price fetching still needs client verification.
- Whether saved data is scoped per plugin, when the host calls `PluginDependencyUpdate` on reloads, whether it re-injects globals, and how it clones exports.
- How the embedded editor fits the bank item area at different sizes. The body starts at the top with no mode-tab strip. Footer actions stay outside the inner scroll. Eight-unit outer margins and the scrollbar reserve use the available width; narrow layouts give values the full second line. Groups have six-unit header/right padding and a gap after their closing border. Unsaved edits survive custom-view redraws and resizes. The folder dialog remains a separate window.
- The editor's native combo boxes, including opening their menus over rows below. Labels and integer IDs share alphabetical order. The editor ignores callbacks during construction, synchronization, and after destruction. The clear icon overlays the input as a sibling layer, rather than parenting a component to a native input.
- Whether the Plugin Hub Query builder choice switches the open editor, preserves detached Advanced drafts, and keeps hints and previews readable in Museo Sans 11pt.
- Native row press/hold/release ordering, pointer capture and scaling during a drag; row-menu defaults and folder submenu placement. PrettyUI builds without MiniMenu use the existing folder chooser fallback. Rename/icon windows and picker tooltips must retire on close and reload.
- Whether one status line of Museo Sans 11pt fits about one character per 6 pixels, which decides when the status takes two lines.

## Query sharing

The footer button and tabbed Import/Share window are ported from Bank Tags. Module paths and data callbacks are query-specific. Import previews never write; a single-query preview can override name, icon and destination folder, while backups retain their metadata. Share rows contain per-query codes and a full-backup row when there is more than one query. Fields are capped at 9,999 characters; oversized exports show a reason rather than truncated code.

`advancedbanksearch-queries` version 1 is a JSON envelope with `queries`, `folders` and portable `order` entries by name. Queries hold `name`, `query`, optional bounded `builder`, `icon` references, and a folder name. Folder records hold name, icon and collapse state. Local IDs are never exported. Import validates the entire envelope and compiles every query with current RuneQL, then stages a copy and commits once. Case-insensitive query name matches reuse local IDs; existing folder names reuse their IDs without overwriting their settings. Unrelated queries and folders are preserved. Invalid optional visual metadata opens in Advanced while keeping the authoritative expression.

The popup retains Bank Tags' lifetime across bank close, and is destroyed with its owned icon picker on disconnect, plugin reload or explicit close. Icon callbacks are revision-guarded so a result cannot change a newer pasted draft. Footer visibility changes hide old tooltips. Preview and copy UI still need a game-client check for tab rendering, focus and Ctrl+A/Ctrl+C.
