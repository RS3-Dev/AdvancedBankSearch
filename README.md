# Advanced Bank Search

Advanced Bank Search finds bank items by name, quantity, or GE price and lets you save searches for later. It adds a **Search** sidebar; the bank's normal search remains available.

## Before you start

Enable **PrettyUI**, **Bank Core**, **RuneQL**, **GE Prices**, and **Advanced Bank Search** in the client's plugin manager. All four supporting plugins are required dependencies.

GE Prices supplies price searches; name, quantity, and catalog matching do not use its price data.

Open a bank and click **Search** on the left rail. There is no separate ribbon panel.

## Search now

1. Type at least two characters in the sidebar field.
2. Matching bank stacks appear in the item area.
3. Clear the field to return to the normal bank view.

Matches use RuneQL's search rules, not simple partial-name matching. Whole words matter: `bone` does not match `bones`.

Results close when you leave All Items, use the bank's native search or filter, open presets, or close the bank. The sidebar explains what needs to change. After clearing the restriction, type again or select a saved search to reopen results.

## Settings

Open Advanced Bank Search's settings cog in **Plugin Hub → Manage**. Changes save immediately.

- **Default editor for new searches:** Visual (default) or Advanced. Existing saved searches retain their mode.
- **Quick-search placeholders:** Include (default) or hide empty bank placeholders. Saved searches always exclude them.
- **Search delay:** Fast (100 ms), Normal (200 ms, default), or Relaxed (400 ms) after you stop typing.

## Save a search without writing a query

1. Click **New**.
2. Give the search a name.
3. In **Visual**, choose a field, comparison, and value.
4. Use **Add condition** for another rule.
5. Choose whether **all** conditions must match or **any one** may match.
6. Review the generated query and save.

For example, select **Quantity**, **is at least**, and **100** to find stacks with at least 100 items. Numeric comparisons include the entered boundary; **is between** has separate Low and High values.

Visual offers Item name, Quantity, GE price, Category, Skills, Types, Combat style, Slot, Tier, Tradeable, and Augmented. Catalog field labels and types still come from RuneQL. Existing saved searches keep access to any other catalog fields they already use; Advanced supports all RuneQL fields. For example, choose **Category**, **is**, and **food**, or **Skills**, **includes**, and **archaeology**. Selecting a catalog text field opens a grid of values supplied by RuneQL. Pick one to fill the value and collapse the grid; clear the value to reopen it. Type in that field to filter the choices. Arrow buttons page through larger lists. Display labels are shown in the grid; the underlying catalog value is saved. Category uses **is / is not**; Skills, Types, Combat style, and Slot use **includes / does not include**. These compare complete values in any case. Negative comparisons exclude items with unknown or empty values. Item name keeps **has phrase / has all words**. Older catalog phrase/word searches keep their query text and open in Advanced.

Flags such as **Augmented**, **Tradeable**, and **Members** offer **is true** and **is false**, with no value to type. An unknown flag matches neither choice. Catalog classifications can be incomplete. **Base value** is a configured item value, separate from current GE prices, and needs no GE Prices plugin.

Click a saved search to open it; click it again to return to the normal bank. **Edit** changes it. **Delete** asks you to press it again to confirm.

## Prices and quantities

Quantity refers to the number in a bank stack. GE prices are **per item**, not the whole stack. Numeric values accept commas and suffixes such as `25k` or `1.5m`.

An item without the requested price does not match a price condition. If GE Prices is still loading, the page waits instead of treating missing prices as zero. Prices are estimates, not guaranteed sale proceeds.

Saved searches exclude bank placeholders; the temporary search field can include them. An item that matches in several stacks is listed once per matching stack, and the bank shows that item's stocked stacks first, then its placeholders, so the stacks shown are not always the ones that matched.

## Organize saved searches

Right-click a search to move it into a folder, create a folder, or remove it from its folder. Click a folder to expand or collapse it. Ungrouping a folder keeps its searches.

Click the Sort icon beside the search field, use the row arrows, then click Sort again to finish.

## Advanced queries

**Advanced** lets experienced users type RuneQL directly. Switching a typed query to Visual asks before starting new conditions; keep a copy of important query text first.

## If something is missing

- **Search field or Save disabled:** enable RuneQL.
- **No Search icon:** check Bank Core and PrettyUI.
- **Price search waiting:** check GE Prices and allow its data to load.
- **Page refuses to open:** the line under the search field says why. Usually switch to the bank's native All Items tab or close the preset selector, then search again.
- **Old saved searches missing:** the older integrated Bank Utilities plugin uses separate saved data. Copy its query text into a new search here; migration is not automatic.

## For reviewers and developers

[Build, saved data, architecture, and validation limits](docs/DEVELOPMENT.md) · [dependency contracts](CONTRACT.md) · [code style](STYLE_GUIDE.md).

Automated tests use a stand-in client. Check input focus, menus, query editing, and price readiness in the submitted build before release.
