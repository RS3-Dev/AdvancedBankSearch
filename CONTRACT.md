# Advanced Bank Search contract

This describes what Advanced Bank Search uses from Bank Core, Bank Tags, RuneQL, GE Prices, and the host. It offers no API of its own. Like Bank Core's API it has no version number: nothing has shipped, so a change updates this document and the tests.

## Plugin identity

- Plugin name `advancedbanksearch`. PrettyUI is required; `bankcore`, `runeql`, `geprices`, and `banktags` are optional dependencies.
- The entry returns nothing. The running session is `_G.__advancedbanksearch_session`; a new load shuts it down first.
- Event names start with `advancedbanksearch_`: `advancedbanksearch_price_wait` (subscribed only while a price wait runs) and `advancedbanksearch_content` (the plugin panel).
- Saved data: `advancedbanksearch:queries:v1:manifest` and `advancedbanksearch:queries:v1:<a|b>:<n>` chunks of JSON `{ schemaVersion = 1, nextId, queries = { { id, name, query } } }`. Nothing else is read or written.

## What it uses from Bank Core

Only the public owner API in Bank Core's `HOST_CONTRACT.md`:

- `RegisterExtension("advancedbanksearch", "Advanced Bank Search")`, found through the injected `bankcore` or `__bankcore_api`; a copy whose owner ID a newer load took never registers again.
- One mounted tab `search` ("Search", icon `SEARCH`) whose content is the plugin's own: a PrettyUI text field, status text, list, and buttons. No menus, drops, settings section, launchers, or highlights.
- Page `search`: `{ title = "Search", key = "search:<serial>", layout = { { slots = ranked } } }`, the serial changing with the text. Page `query`: `{ title = <name>, key = "query:<id>", layout = ... }`. A slot is `{ item = objectID, copy = n }` for a stack of the `GetBankItems` generation ranked, so each copy appears once. A page with no stacks is one label: "No items match", "RuneQL could not read this search", "This search needs GE Prices", "Waiting for GE prices...", "GE prices did not load", "This search needs RuneQL", or "The bank's items are not available yet".
- `OpenPage` through the mounted context (for Bank Core's View All guidance), or the handle when the tab is not mounted; `LeavePage`; `UpdatePage` only when a page's title, key, or rows changed.
- `SetListener`: `onState` closes the editor and drops the snapshot when the bank closes; `onPage` tracks the shown page and ends a price wait for another key; `onBankItems` reads `GetBankItems` (keeping the last snapshot while it answers `building`) and ranks the shown page again under the same key.

## Ranking

- RuneQL's `Compile(text)` gives a plan, or nil and a reason. Each stack is scored with `plan:Score({ name, configName, quantity, fields })`, the name from `config.Obj.FromID(id).name` and the config name from its `configName`. Matches are sorted by score, descending, ties in View All order.
- When `plan:Requirements()` names `price`, `gehigh`, or `gelow`, the plan is ranked only once GE Prices' `isReady()` is true, with `fields.gehigh`, `fields.gelow`, and `fields.price` from `getPrice(id)` (positive numbers only; an error is no price). RuneQL lets a negated range match a row without the field, so ranking before prices load would be wrong.
- RuneQL is read from the injected `runeql` or `__runeql_api`, and GE Prices from `geprices` or `__geprices_api`, only while the host last reported them loaded.

## What it uses from Bank Tags

Only the import-source API in Bank Tags' `CONTRACT.md`:

- `RegisterExtension("advancedbanksearch", "Advanced Bank Search")` on the injected `banktags` or `__banktags_api`, and one provider `saved-search`: label "Saved bank search", icon `SEARCH`, `input = "text"`, a prompt and placeholder, and `unavailable` while Bank Core is not connected or RuneQL is not loaded (updated with `UpdateImportProvider` when that changes). The handle is disposed when Bank Tags is reported unloaded or this plugin stops; a handle a newer copy replaced is never registered again.
- A request's input names a saved search. The answer is `Resolve({ tags = { { name = <query name without commas>, rows = { { objectID, ... } } } } })`, one entry per matched stack in rank order, placeholders left out. Bank Tags gives a repeated object its next copy, so an object appears k times only when its matched copies are exactly 1 to k; otherwise, and for more than 1,999 stacks, no matches, a closed bank, another tab than All Items, a building bank, an unreadable query, missing or loading prices, or an unknown name, the answer is `Fail` with a reason under 120 characters. Answers are given while the request runs; no cancel function is returned.

## Host behavior it relies on

Checked with Bank Core's stand-in host only: `PluginDependencyUpdate` for all four optional dependencies; `PersistentDB:GetString` and `SetString` per plugin; PrettyUI's `TextField` (with `SetDisabled`), `Text`, `List` (with `_onEntryClick`), `SimpleButton`, and `Window`; `ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)` for the editor's parent; `Event.Logic` and `Event.ContentLayerReady`.
