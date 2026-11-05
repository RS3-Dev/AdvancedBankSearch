# Advanced Bank Search tests

Run every test, the build, and the compile and globals check from the repository root:

```text
set BANKCORE_ROOT=C:\path\to\bank-utilities
set RUNEQL_ROOT=C:\path\to\plugins\runeql
set PRETTYUI_ROOT=C:\path\to\prettyui-checkout
lua54 tools/check.lua
```

Tests that load Bank Core read it, unchanged, from the checkout `BANKCORE_ROOT` names; there is no default, so a stale sibling checkout is never tested against by accident. They use Bank Core's own stand-in host (`tools/test_support/fake_bank_host.lua` and `fake_plugin_host.lua` in that checkout) and load Bank Core's `plugins/bankcore/main.lua` with its own module cache, beside the Advanced Bank Search folder the build writes under `dist/test/`. Nothing from Bank Core is copied into Advanced Bank Search or its package.

Tests that rank load the installed RuneQL plugin, read-only, from `RUNEQL_ROOT`, so ranking runs on RuneQL's real `Compile`, `Score`, and `Requirements`. Sprite buttons and tooltips are PrettyUI's real `src/sprite_button.lua` and `src/tooltip.lua`, read-only, from the checkout `PRETTYUI_ROOT` names, over Bank Core's stand-in components, so the column can call only methods PrettyUI defines and its tooltip layers are really made and destroyed. The sprite table is Bank Core's stand-in, tooltips have no frame sprites, and the cursor sets nothing. The stand-in components keep each named subscription beside the unnamed one, as the client does, so a test can fire a button's own hover and its tooltip's together. The host log keeps each line, so a test that finds the column unmounted names the error Bank Core logged. A test that needs a bank item's right-click menu gives it the item's component data and marks the stand-in item layer as the bank's interface, as the client reports it.

GE Prices is a stand-in that follows its README (`isReady()`, and `getPrice(id)` raising for an item without a price), because the real plugin fetches prices over HTTP.

Core must expose `GetBankState()` and `onBankStateChanged(state)`, including `filterActive`. The bank-state test covers quick and saved searches, all native restrictions, cancellation of search/price waits, live state checks before opening, actual Core notifications, and leaving another extension's page alone. Run new untracked tests explicitly: `lua54 tests/bank_state_test.lua`.


The query builder test checks the RuneQL text visual conditions give, then compiles and evaluates it with the installed RuneQL: phrases and words, escaped quotes and syntax, all and any, number bounds and refusals, and price conditions on stacks without prices, ranked through the real price wait. The editor test also covers discovery-driven field labels, paged value grids, label/canonical-value separation, filtering, choosing/clearing values, late dependency loading, and a newly discovered field without local definitions. The editor test drives the editor in the mounted column: adding and removing conditions, number and name comparisons, switching between Visual and Advanced, saving, reopening, a typed query left alone, and cleanup on close and unload. It also checks that the controls the editor calls exist in PrettyUI's own source. Bank Core's stand-in `SimpleButton` gets PrettyUI's `SetActive`. Combo boxes use PrettyUI's real native `ComboBox`, over a stand-in native field that sorts labels and reads IDs as sorted positions. The editor supplies IDs in that same order. The harness rejects layers parented to text inputs. Editor lifecycle checks use PrettyUI's real SimpleButton components, inject early callbacks and constructor failures, and check that repeated open/filter/close cycles return to the baseline live-component count.

The folders test drives the mounted column's folders, sorting, row menus, and compact layout, with a stand-in right-click menu whose subscribers answer in either order; a bank item's menu, which `GetMenuItem` describes, gets no row actions.

A combined test loads the built Bank Cleaner beside Advanced Bank Search when `BANKCLEANER_DIST` names a built `bankcleaner` folder, to show their module paths, events, globals, and saved data do not collide; without it, that test says it was skipped.

The stand-in host is not the game client: these tests show Advanced Bank Search's behavior against Bank Core's public API under that model, not how the live client draws, scrolls, or delivers input.

The former tag-source test now verifies that Bank Tags is absent from the manifest and receives no import registration, while quick and saved searches still work.

The harness adapts older Core test loaders to read `requiredDependencies`. Dependency unload/reload scenarios explicitly inject failures even for required plugins; the real host prevents independent unloading of required dependencies.
