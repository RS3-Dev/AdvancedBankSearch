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

Results close when you leave All Items, use the bank's native search or filter, open presets, or close the bank. After clearing the restriction, type again or select a saved search to reopen results.

## Settings

Open Advanced Bank Search's settings cog in **Plugin Hub â†’ Manage**. Changes save immediately.

- **Query builder:** Visual (default) or Advanced. This chooses the editor for new and existing queries, and changes the open builder immediately. Saved queries without visual conditions open in Advanced to preserve their RuneQL.
- **Quick-search placeholders:** Include (default) or hide empty bank placeholders. Saved searches always exclude them.
- **Search delay:** Fast (100 ms), Normal (200 ms, default), or Relaxed (400 ms) after you stop typing.

## Save a search without writing a query

1. Click **New** to open the builder in the bank’s item area.
2. Give the search a name.
3. In **Visual**, choose a field, comparison, and value.
4. Use **Add condition** for another rule, or **Add group** for a nested set of rules.
5. Choose whether **all** conditions must match or **any one** may match, separately for the whole query and each group.
6. Review the generated query and save.

For example, select **Quantity**, **is at least**, and **100** to find stacks with at least 100 items. Numeric comparisons include the entered boundary; **is between** has separate Low and High values.

Visual offers Item name, Quantity, GE price, Category, Skills, Types, Combat style, Slot, Tier, Dose, Tradeable, and Augmented. Catalog field labels and types still come from RuneQL. Existing saved searches keep access to any other catalog fields they already use; Advanced supports all RuneQL fields. For example, choose **Category**, **is**, and **food**, or **Skills**, **includes**, and **archaeology**. Selecting a catalog text field opens a grid of values supplied by RuneQL. Pick one to fill the value and collapse the grid; clear the value to reopen it. Type in that field to filter the choices. Arrow buttons page through larger lists. Display labels are shown in the grid; the underlying catalog value is saved. Category uses **is**; Skills, Types, Combat style, and Slot use **includes**. Toggle **!** between the comparison and value to exclude a condition, for example **Dose**, **is between**, **!**, **1** and **3**. These compare complete values in any case. Exclusions leave out items with unknown or empty values. Item name keeps **has phrase / has all words**. Older catalog phrase/word searches keep their query text and open in Advanced.

Flags such as **Augmented**, **Tradeable**, and **Members** offer **is true** and **is false**, with no value to type. An unknown flag matches neither choice. Catalog classifications can be incomplete. **Base value** is a configured item value, separate from current GE prices, and needs no GE Prices plugin.

Visual supports up to six conditions across the query, six groups, and three nested group levels. Each outlined group has its own all/any choice, a plus icon to add a condition, a circled plus to add a subgroup, and a trash button beside those two actions to remove the whole group. Condition trash buttons stay at the far right. The add buttons beside the top **Match** control add to the query outside existing groups. For example, use a group for **Category is food OR Dose is 4**, then add **Quantity is at least 10** outside it with the whole query set to all. Trash buttons remove individual conditions too. Choose Visual or Advanced in the plugin settings menu; there are no mode tabs inside the editor. Save and Cancel stay at the bottom. Both return to the results that were open before editing.

Click a saved search to open it; click it again to return to the normal bank. The footer shows **Share**, **New Query**, and a pencil **Edit** button when a query is selected. To delete a query, right-click it, choose **Remove**, and confirm.

## Prices and quantities

Quantity refers to the number in a bank stack. GE prices are **per item**, not the whole stack. Numeric values accept commas and suffixes such as `25k` or `1.5m`.

An item without the requested price does not match a price condition. If GE Prices is still loading, the page waits instead of treating missing prices as zero. Prices are estimates, not guaranteed sale proceeds.

Saved searches exclude bank placeholders; the temporary search field can include them. An item that matches in several stacks is listed once per matching stack, and the bank shows that item's stocked stacks first, then its placeholders, so the stacks shown are not always the ones that matched.

Results keep their slots while the page is loaded. Quantities update as you withdraw or deposit, and withdrawing the last item leaves a placeholder in its slot. Reopening the query or running a new search recalculates the results from the current bank.

If you try to open results while a numbered bank tab, native search, active filter, or preset selector prevents it, a Bank Tags-style warning appears over the bank title. Entering those states alone closes results silently. Clear the restriction and open your search again. The banner never displays match counts.

## Organize saved searches

Right-click a query and choose **Rename** to change its name and item icon without editing its conditions. Click the item slot to open the same item-search icon picker used by Bank Tags. New and edited queries also have this icon slot beside their name.

The folder menu offers existing folders and **Create new folder**. On older PrettyUI versions without submenus, **Move to folder...** opens the folder chooser instead. Right-click a folder and choose **Rename folder** to change its name and icon. Click a folder to expand or collapse it. Ungrouping a folder keeps its queries. Empty folders are retained in storage and available as destinations, and disappear from the sidebar until they have a query again.

Drag rows to reorder them, just as in Bank Tags. Queries inside a folder reorder among that folder’s queries; queries outside folders and whole folder blocks reorder at the top level. Use the row menu to change folder membership. The sidebar has no reorder mode or sort button. All four sides of the search/list spacing use the same eight-unit inset, and the area under Search never shows status text.

## Import and share queries

Click the Share icon at the bottom left of the sidebar. Its **Import** and **Share** tabs use the same layout as Bank Tags.

- **Share:** copy a query code, or the **All queries (backup)** code, with Ctrl+A and Ctrl+C in its field. Codes include RuneQL, saved visual conditions, the item icon, and folder information.
- **Import:** paste a query code to preview it. A single query lets you adjust its name, icon, and destination folder, including creating a new folder. A backup keeps its individual names, icons, and folder structure. Nothing is saved until you click **Import queries**.
- A matching name replaces that query while retaining its local ID. Other queries stay intact. Imports validate every expression and publish the save once, so a rejected import changes nothing.

Query codes have their own format; Bank Tags item-layout codes are not query codes. The game text fields accept 9,999 characters. If a full backup is too large for its field, share individual queries instead.

## Advanced queries

**Advanced** in the plugin settings lets experienced users type RuneQL directly. Switching an open typed query to Visual keeps its Advanced text until you save visual conditions. Switching back without changing those conditions restores the original text.

## If something is missing

- **Search field or Save disabled:** enable RuneQL.
- **No Search icon:** check Bank Core and PrettyUI.
- **Price search waiting:** check GE Prices and allow its data to load.
- **Page refuses to open:** switch to the bank's native All Items tab or close the preset selector, then search again.
- **Old saved searches missing:** the older integrated Bank Utilities plugin uses separate saved data. Copy its query text into a new search here; migration is not automatic.

## For reviewers and developers

[Build, saved data, architecture, and validation limits](docs/DEVELOPMENT.md) Â· [dependency contracts](CONTRACT.md) Â· [code style](STYLE_GUIDE.md).

Automated tests use a stand-in client. Check input focus, menus, query editing, and price readiness in the submitted build before release.
