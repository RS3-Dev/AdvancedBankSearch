# Advanced Bank Search

Advanced Bank Search (`advancedbanksearch`) is a standalone plugin for searching the bank with RuneQL queries and keeping saved searches. It runs on [Bank Utilities Core](https://github.com/RS3-Dev/bank-utilities) (`bankcore`) and reaches the bank only through Bank Core's public extension API: no private Core module or native bank component is used, and the bank's own search is left alone. What it uses from Bank Core and Bank Tags is in [CONTRACT.md](CONTRACT.md); the plan it was built from is in [docs/STANDALONE_PLAN.md](docs/STANDALONE_PLAN.md).

Everything here is checked against Bank Core's stand-in host and the installed RuneQL only. Nothing in this repository has been verified in the live client yet; see [Not yet verified live](#not-yet-verified-live).

## Features

- **Search tab.** A sidebar tab with a RuneQL search field and a sort button, your saved searches and folders with how many stacks each search matched last, and New, Edit, and Delete. A status line appears under the field only while there is something to say; otherwise the saved searches start right under it.
- **Search page.** Typing two or more characters ranks the bank's stacks against the text, best match first and ties in bank order, and shows them in the bank, placeholders included. Each new search starts at the top; a bank change ranks the same search again and keeps your place. Clearing the text returns to the bank.
- **Saved searches.** Choosing one shows its page, placeholders left out; choosing it again returns to the bank. New and Edit open an editor for the name (up to 40 characters) and the query, built in Visual or typed in Advanced (up to 9,999 characters). Delete asks you to press it again.
- **Visual queries.** New searches start in Visual: up to 6 conditions, each a field, a comparison, and a value, matched all together (AND) or any one (OR), with Add condition and Remove. The editor shows the RuneQL it will save, or what a condition is missing, and Save sends that RuneQL through the same check as typed text.
  - *Item name* has phrase (the words together, in order) or has all words (each anywhere). Words are whole words in any case, so "bone" does not find "bones". What you type is always quoted, so `OR`, `*`, brackets, and quotes are searched as words and never become RuneQL.
  - *Quantity*, *GE price*, *GE high price*, and *GE low price* *is*, *is greater than*, *is less than*, or *is between*. Every comparison includes the number itself, so *is greater than 10* matches 10. Numbers are whole, from 0 to 2,147,483,647, and can use commas or k, m, or b (`25k`, `1.5m`). GE price is the high price, or the low one when there is no high price; prices are per item, not per stack, and an item without that price never matches.
  - *Advanced* shows the conditions' RuneQL for typing NOT, groups, fuzzy words, and the rest of RuneQL. A search made in Visual reopens in Visual while its text is still what the conditions give; once the text is typed over and saved, it opens in Advanced. A typed search always opens in Advanced, unchanged; pressing Visual asks first, then starts a blank condition, and its text is replaced only if you save from Visual. Leaving Visual with incomplete conditions keeps the typed text as it was.
- **Folders.** As in Bank Tags, folders hold saved searches. A folder row shows how many it holds; click it to open or close it, which changes neither the chosen search nor the page shown. A closed folder is outlined when the chosen search is inside. Right-click a search for Edit, Move to folder (pick a folder, No folder, or type a new folder's name and press Create), and Remove from folder; right-click a folder for Expand or Collapse, Rename folder, and Ungroup folder, which removes the folder and keeps its searches where it was. A folder can be empty. New searches go at the bottom, outside any folder; editing a search keeps its folder and place, and deleting it takes it out of its folder.
- **Sorting.** As in Bank Tags, the swap button beside the field, a native bank button whose icon lights while hovered or sorting, turns sorting on and off. While sorting, each row has up and down arrows: folders and searches outside folders move among themselves, and searches inside a folder move within it. Folders keep whether they are open and still open and close when clicked, so a closed folder's searches can be reached; clicking a search chooses nothing. Starting a search, or leaving the bank, ends sorting; sorting keeps the search text, since the search does not hide rows. Folders, their order, and whether each is open are saved.
- **Prices.** A search that uses `price`, `gehigh`, or `gelow` needs GE Prices. Until prices load, its page says it is waiting, and it is ranked once they arrive (checked every 30 ticks, for up to 1,800); it is never ranked on missing prices. Without GE Prices its page says it is needed. Other searches never need GE Prices.
- **Convert to a tag.** With Bank Tags loaded, its Import window lists "Saved bank search": type a saved search's name and Bank Tags previews a tag holding exactly the stacks the search matches now.
- **No plugin window entry.** Advanced Bank Search has no ribbon icon or panel in the Plugins window; everything it shows is in the bank.

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
- A search made in Visual saves its conditions beside its query text, which stays what is searched. Conditions are used only while they still give exactly that text; otherwise the search opens in Advanced. Searches saved before this load and save as they were.
- Folders and the order are saved in the same keys. A save from before folders loads with every search outside any folder, in its saved order, with the same IDs; a folder change or a new order cannot be read by those earlier builds, which would save over it without folders.
- A query RuneQL cannot read is refused in the editor with RuneQL's reason, and a save that cannot be written is reported there; either way nothing changes and the editor stays open. Saving a query drops its old count; a shown query is counted again at once. A save that cannot be read is reported in the tab and never overwritten; nothing is saved until it is fixed.

## Changes from the old integrated plugin

- The search field is in the Search tab, not in place of the bank's own search box, which is no longer hidden or moved. The `enableAdvancedSearch` and `enableRuneSQL` preferences are gone: enabling the plugin is the switch. There is no settings section.
- Delete and Convert to tag left the right-click menu: Delete is a button in the tab, and conversion starts from Bank Tags' Import window. The right-click menu now holds folder actions.
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
- How the editor window and folder dialog draw over the bank, including whether the 620 by 560 editor fits small clients (it does not scroll or shrink).
- The editor's combo boxes: their dropdowns opening over the rows below, hiding a row's controls, and whether changing a row's comparison list reports a selection (the editor ignores reports while it fills rows). Combo box entry IDs are whole numbers, as the client needs.
- Whether the Visual and Advanced buttons look lit with `SetActive`, and whether the hint and preview fit in two lines of Museo Sans 11pt.
- The sort button's native panel style and its icon drawn beside it, its tooltip in Bank Core's overlay, the folder chevron's rotation, the sort arrows' positions and clicks inside list rows (including whether an arrow's click also reaches its folder row), and where the host places right-click entries over the tab.
- Whether one status line of Museo Sans 11pt fits about one character per 6 pixels, which decides when the status takes two lines.
