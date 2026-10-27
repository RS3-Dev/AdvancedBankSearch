# Advanced Bank Search

Advanced Bank Search finds bank items by name, quantity, or GE price and lets you save searches for later. It adds a **Search** sidebar; the bank's normal search remains available.

## Before you start

Enable **PrettyUI**, **Bank Core**, **RuneQL**, and **Advanced Bank Search** in the client's plugin manager.

- **GE Prices** is needed only for price searches.
- **Bank Tags** is needed only to turn a saved search into a tag.

Open a bank and click **Search** on the left rail. There is no separate ribbon panel.

## Search now

1. Type at least two characters in the sidebar field.
2. Matching bank stacks appear in the item area.
3. Clear the field to return to the normal bank view.

Matches use RuneQL's search rules, not simple partial-name matching. Whole words matter: `bone` does not match `bones`.

## Save a search without writing a query

1. Click **New**.
2. Give the search a name.
3. In **Visual**, choose a field, comparison, and value.
4. Use **Add condition** for another rule.
5. Choose whether **all** conditions must match or **any one** may match.
6. Review the generated query and save.

For example, select **Quantity**, **is greater than**, and **100** to find stacks with at least 100 items. The comparisons named “greater than” and “less than” currently **include the entered boundary**.

Click a saved search to open it; click it again to return to the normal bank. **Edit** changes it. **Delete** asks you to press it again to confirm.

## Prices and quantities

Quantity refers to the number in a bank stack. GE prices are **per item**, not the whole stack. Numeric values accept commas and suffixes such as `25k` or `1.5m`.

An item without the requested price does not match a price condition. If GE Prices is still loading, the page waits instead of treating missing prices as zero. Prices are estimates, not guaranteed sale proceeds.

Saved searches exclude bank placeholders; the temporary search field can include them.

## Organize saved searches

Right-click a search to move it into a folder, create a folder, or remove it from its folder. Click a folder to expand or collapse it. Ungrouping a folder keeps its searches.

Click the Sort icon beside the search field, use the row arrows, then click Sort again to finish.

## Advanced queries and tags

**Advanced** lets experienced users type RuneQL directly. Switching a typed query to Visual asks before starting new conditions; keep a copy of important query text first.

With Bank Tags enabled, open its **Import/Share** window, choose **Saved bank search**, and enter your saved search's name. Review the tag preview before importing. This creates a tag from the current matches; it is not a live search-linked tag.

## If something is missing

- **Search field or Save disabled:** enable RuneQL.
- **No Search tab:** check Bank Core and PrettyUI. If the client log says Advanced Bank Search needs a newer Bank Core, update Bank Core.
- **Price search waiting:** check GE Prices and allow its data to load.
- **Page refuses to open:** switch to the bank's native All Items tab.
- **Old saved searches missing:** the older integrated Bank Utilities plugin uses separate saved data. Copy its query text into a new search here; migration is not automatic.

## For reviewers and developers

[Build, saved data, architecture, and validation limits](docs/DEVELOPMENT.md) · [dependency contracts](CONTRACT.md) · [code style](STYLE_GUIDE.md).

Automated tests use a stand-in client. Check input focus, menus, query editing, and price readiness in the submitted build before release.
