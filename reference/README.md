# Reference archive

Preserved source from Bank Utilities `beba274b57853d444c7017eaa9c813273f222475`, kept for history and comparison. Nothing here is built, loaded, or tested; the build refuses to ship it.

- `integration/`: the old integrated app (with query deletion and conversion), feature glue, sidebar (with the Queries tab), menus, settings, and plugin entry.
- `preserved/lib/`: preserved modules the standalone plugin no longer loads: the native bank search replacement (`bank_name_search.lua`, which parked native components and owned the price wait), the search and query page descriptors for Core's removed private page state, catalog search, the bank interface, config, storage keys, debug log, and text helpers.
- `preserved/tests/`: the catalog search test, for the preserved `catalog_objects.lua`.
- `tests/`: the old integration tests, which need the original repository's harness.
- `HOST_CONTRACT.md`: the host and API assumptions at the source revision, superseded by Bank Core's `HOST_CONTRACT.md` and this repository's `CONTRACT.md`.

`EXTRACTION_MANIFEST.json` at the repository root records each preserved file's original path and hash. Files that became runtime modules moved to `advancedbanksearch/` and were adapted there; their history is in git.
