# Advanced Bank Search tests

Run every test, the build, and the compile and globals check from the repository root:

```text
set BANKCORE_ROOT=C:\path\to\bank-utilities
set RUNEQL_ROOT=C:\path\to\plugins\runeql
lua54 tools/check.lua
```

Tests that load Bank Core read it, unchanged, from the checkout `BANKCORE_ROOT` names; there is no default, so a stale sibling checkout is never tested against by accident. They use Bank Core's own stand-in host (`tools/test_support/fake_bank_host.lua` and `fake_plugin_host.lua` in that checkout) and load Bank Core's `plugins/bankcore/main.lua` with its own module cache, beside the Advanced Bank Search folder the build writes under `dist/test/`. Nothing from Bank Core is copied into Advanced Bank Search or its package.

Tests that rank load the installed RuneQL plugin, read-only, from `RUNEQL_ROOT`, so ranking runs on RuneQL's real `Compile`, `Score`, and `Requirements`. GE Prices is a stand-in that follows its README (`isReady()`, and `getPrice(id)` raising for an item without a price), because the real plugin fetches prices over HTTP.

Bank Tags is not built here: its build writes only inside its own repository. The import source is tested against a stand-in import registry that follows Bank Tags' `CONTRACT.md` and reads drafts the way Bank Tags does: a repeated object takes its next copy, and a draft holds at most 2,000 entries.

The folders test drives the mounted tab's folders, sorting, row menus, and compact layout, with a stand-in right-click menu whose subscribers answer in either order.

A combined test loads the built Bank Cleaner beside Advanced Bank Search when `BANKCLEANER_DIST` names a built `bankcleaner` folder, to show their module paths, events, globals, and saved data do not collide; without it, that test says it was skipped.

The stand-in host is not the game client: these tests show Advanced Bank Search's behavior against Bank Core's public API under that model, not how the live client draws, scrolls, or delivers input.
