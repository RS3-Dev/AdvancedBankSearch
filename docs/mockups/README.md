# Query builder mockup

Open `query-builder.html` in a browser. It is self-contained.

The screen contains only the search name, all/any selection, conditions, Add condition, read-only generated query, and Cancel/Save. There are no results, match counts, copy/edit-query actions, helper captions, or confirmation messages.

Catalog text fields open an alphabetical visual picker when empty. Selection fills the existing input and collapses the picker. The inline clear button or deleting the value reopens it. A filled selection stays collapsed. Typing in that same input filters the list. Skills show all 24 catalog values; larger lists scroll. Tab completes the active input without moving focus.

Numeric ranges have separate Low/High inputs. Invalid numbers and reversed bounds receive an error border. Incomplete conditions hide the generated query and disable Save. The query is displayed as plain text.

Save records a value only in the page's JavaScript memory. Cancel resets the example. Neither changes the plugin. The embedded catalog supplies 727 values and 50 sample names for suggestions; it is not used to show search results.

This is still an HTML mockup. The Lua runtime is unchanged.
