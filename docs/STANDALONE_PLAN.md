# Advanced Bank Search standalone plan

This records the plan agreed before implementation for making Advanced Bank Search a standalone plugin on Bank Core's public API, with the review refinements adopted, and the stages it is built in. Bank Core is used only through its `HOST_CONTRACT.md` and Bank Tags only through its `CONTRACT.md`; nothing in either changes.

## Starting point

- Search and saved RuneQL queries were preserved from Bank Utilities `beba274` at `3ef2125`. They were not runnable: the search parked native bank components and drew its field on the native bottom panel, and its pages, query actions, menus, and price wait lived in the mixed integration code and Core's removed private page state.
- Bank Core (`bankcore`, worktree `fix/pseudo-page-resize` at `2e4941e`) offers owners with pages, mounted tabs, listeners, and bank item snapshots. Bank Tags (`banktags`, `d6fb1cd`) offers import sources.

## Identity

- Plugin `advancedbanksearch`, Core owner `RegisterExtension("advancedbanksearch", "Advanced Bank Search")`. PrettyUI `6398181` is required; `bankcore`, `runeql`, `geprices`, and `banktags` are optional, so the host reports their changes through `PluginDependencyUpdate`.
- Runtime modules live under `advancedbanksearch/`: `app`, `search/{ranking,item_fields,search_tab,query_store,query_editor,tag_source}`, `core/{json,chunked_string_store,object_config}`.
- Events `advancedbanksearch_price_wait` and `advancedbanksearch_content`; the reload global `__advancedbanksearch_session`. The plugin publishes no API.

## Search tab and pages

- One mounted tab `search` ("Search", icon `SEARCH`): the search field, a status line, the saved queries with their last-known counts, and New, Edit, and Delete (with a confirmation). Native bank search is never parked, hidden, or read.
- Page `search`: `{ title = "Search", key = "search:<serial>", layout = { { slots = ranked } } }`. The serial changes when the text changes, so a new search starts at the top; re-ranking after a bank change keeps the key and the scroll. Placeholders are included, as in the legacy name search. Text under 2 characters leaves the page.
- Page `query`: `{ title = <name>, key = "query:<id>", ... }`, placeholders left out.
- Ranking is the legacy one: score descending, ties by View All order. `ranked` is one `{ item, copy }` per stack from the same `GetBankItems` generation.
- An empty result is one label row, "No items match"; text RuneQL cannot read is "RuneQL could not read this search", with RuneQL's reason in the status line.

## Dependencies

- **RuneQL absent:** the tab says the search needs RuneQL, the field and Save are disabled, and saved queries stay listed. There is no fallback engine. Once the host reports RuneQL unloaded, neither its injected global nor `__runeql_api` is read until it is reported loaded again.
- **GE Prices:** only a query whose `Requirements()` name `price`, `gehigh`, or `gelow` needs it. RuneQL defines no partial semantics for a missing field (a missing field matches nothing, and `NOT price:[...]` would then match every item), so such a query is never ranked without prices: its page shows a label row saying it needs GE Prices, or that prices are loading, and the query is kept. While prices load, the plugin checks every 30 ticks for up to 1,800 ticks, then re-ranks or reports that prices did not load. The wait ends on a query or text change, a page change, disconnect, replacement, or GE Prices being reported unloaded.
- **Bank Tags:** optional; see conversion below.

## Saved queries

- New keys `advancedbanksearch:queries:v1:manifest` and its `a|b` chunks, written through the preserved chunked store. The old `bankutils:runesql:*` data belongs to the old plugin's own saved data, which this plugin cannot read; nothing migrates and nothing reads the old structured fallback.
- Names up to 40 characters and queries up to 9,999, as before. A query RuneQL cannot compile is refused before anything is written, as the integrated editor did. A failed save is reported in the editor and nothing changes in memory.

## Converting a query to a tag

- Through Bank Tags' published import-source contract: one source, "Saved bank search", whose text input is a saved query's name. It is `unavailable` with a reason while it cannot run (Bank Core not connected, RuneQL missing).
- The draft is one tag named after the query with one row of the matching stacks' object IDs. Bank Tags gives a repeated object its next copy in the order listed, so the draft names exactly the matched stacks only when each object's matched copies are 1 to k. Then the object's k entries are listed and Bank Tags assigns copies 1 to k; otherwise (for example only copy 2 matched) the request fails, saying so, rather than tagging another copy. More than 1,999 stacks (Bank Tags' 2,000-entry draft, less the row) fails rather than truncating; so do no results, not All Items, an unknown name, an unreadable query, and missing prices.

## Lifecycle

- The entry shuts down a previous session in the same Lua state, evicts its module cache, and connects; a copy whose owner ID a newer load took retires. No `SetSettings` section, no `MiniMenuReady`: query actions are buttons in the tab, and Delete and Convert leave the right-click menu.
- `enableAdvancedSearch` and `enableRuneSQL` are gone: enabling the plugin is the switch.

## Repository layout and tools

- `plugins/advancedbanksearch/` holds the entry and manifest. Tools are adapted from Bank Tags, which is only read; the build writes `dist/advancedbanksearch/`.
- `reference/` keeps the preserved integration code and tests byte for byte; `bank_interface`, `config`, `catalog_objects`, `name_search_page`, `query_page`, `storage_keys`, `debug_log`, `text`, and the original `bank_name_search` move to `reference/preserved/`. `EXTRACTION_MANIFEST.json` stays unchanged.
- Tests load the real Bank Core from `BANKCORE_ROOT` in its stand-in host. Bank Tags is not built (its build writes only inside its own repository); the import source is tested against a stand-in that follows Bank Tags' `CONTRACT.md`. A combined test loads the built Bank Cleaner beside Advanced Bank Search when `BANKCLEANER_DIST` names its build.

## Stages

| Stage | Content |
| --- | --- |
| 0 | This plan |
| 1 | Restructure, tools, manifest; dead modules to `reference/preserved/` |
| 2 | Ranking, item fields, and query store, with unit tests |
| 3 | App, search tab, editor, pages, price wait, RuneQL absent, with Core harness tests |
| 4 | Bank Tags import source, tested against a contract stand-in |
| 5 | README and contract |

Each stage passes `lua54 tools/check.lua`, and Bank Core's and Bank Tags' trees are checked unchanged.

## Not verified live

Keyboard focus in the mounted search field, `geprices` as the optional dependency identifier (its manifest names itself "Ge Price Library"), per-plugin saved data, how the host clones exports and calls `PluginDependencyUpdate` on reloads.

## Results

All stages are implemented on `feature/standalone-plugin`, each in its own commit, with `tools/check.lua` passing at every stage against Bank Core `2e4941e` read from `BANKCORE_ROOT` and the installed RuneQL 0.4.0 read from `RUNEQL_ROOT`. Bank Core, Bank Tags, and RuneQL were only read; Bank Core's and Bank Tags' trees were checked unchanged after every stage. Nothing has been verified in the live client.

| | Lua files | Lines |
| --- | ---: | ---: |
| Built `dist/release/advancedbanksearch` (entry and 10 modules, plus `plugin.json`) | 11 | 1,795 |
| Tests and tools | 13 | 1,752 |

Tests: `ranking_test` (the real RuneQL: order, ties, copies, placeholders, unreadable text, and RuneQL's missing-field semantics pinned), `query_store_test` (new keys only, validation, a refused write, an unreadable save never overwritten), `search_app_test` (the real Bank Core and RuneQL: the field opening and leaving the search page, keys, re-ranking on bank changes, unchanged pages not sent, saved queries made, edited, refused, and deleted, price waits, a stale wait dropped, the give-up, GE Prices and RuneQL unloading, the bank closing), `tag_source_test` (the import source against a Bank Tags stand-in that follows its `CONTRACT.md`), `plugin_reload_test` (load orders, cloned exports, reloads mid-wait, a replaced owner staying idle, no subscription left), and `combined_plugins_test` (Bank Cleaner's own build loaded beside this plugin in shared and separate states).

Found during implementation and left for review:

- RuneQL matches a range only on a row that has the field, and a negated range on every row without it, so ranking a price query before prices load would show wrong items. Price queries are never ranked without loaded prices.
- After a price wait gave up, Bank Core's next items notice (it reports one after every page rebuild, including this plugin's own) started a new wait; the key whose wait failed now stays failed until the search or GE Prices changes.
- Saving a new query while another query's page was shown replaced the shown page; the query a page shows is now tracked apart from the list's selection.
- Later: Bank Core's launch API replaced owners, tabs, listeners, keyed pages, `ShowWarning`, and explicit copies. Advanced Bank Search registers one rail icon with the Search column, sets one `{ title, rows }` page of object IDs per search or saved query and opens it, and follows `onClose`, `onBankItems`, and `onBankClose`; a refusal goes to the column's status line. The import source no longer refuses a match that skips a stack, since a tag names objects, not stacks. [CONTRACT.md](../CONTRACT.md) describes it.
- PrettyUI's `SimpleButton` has no label setter, so Delete's confirmation is in the status line ("Press Delete again...") rather than on the button.
- The build's default `dist` output refused to build once the check had written `dist/check`; it is now `dist/release`.
- Every original file in `EXTRACTION_MANIFEST.json` has a byte-identical copy in the repository; the adapted `object_config`, `query_store`, `query_editor`, and `query_item_fields` are in `reference/preserved/`.
