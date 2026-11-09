# Bank query editor

- Use Bank Core’s item-area custom view for query editing. The search sidebar uses the Bank Tags list: full-width search, eight-unit left/right and below-search spacing, 30-unit drawn rows on a 32-unit stride. No reorder button or status text below Search.
- Keep the existing game UI: native combos, PrettyUI framed buttons, Museo Sans 11pt content, Cinzel labels, gold headings, muted beige hints and red validation.
- Use eight-unit outer margins, 28-unit controls, 6–8-unit horizontal gaps, and 34-unit row steps. Reserve 18 units for the scrollbar on the right. Two-line condition values use the whole second line.
- Visual / Advanced are chosen in the Plugin Hub Query builder setting and switch the open editor. Do not draw mode tabs or reserve their height. Save / Cancel and validation belong in the footer. Only editor content scrolls.
- At narrow bank widths, comparison controls occupy one line and values the next. Keep condition trash at the far right. Group trash sits directly after Add subgroup in its header; use HUD_COMBAT_BTN_BIN for both.
- Put the active-state ! exclusion button after the comparison. Comparisons stay positive; ! excludes only that condition and never matches missing field values.
- Indent group descendants by 12 units per level. Enclose each group in a darker surface and thin gold frame, with six units around its header and right edge, a padded closing border, and an eight-unit gap before the next sibling. Groups own their all/any choice and additions. Query-level add buttons sit beside the top Match control, never beneath a group where their scope could be mistaken.
- Tooltips use the bank overlay. Clear picker tooltip attachments before reusing or hiding a choice. Destroy owned contexts when leaving or rebuilding the editor.
- Preserve drafts as Lua data across Core redraws; do not recover them from retired UI components.
- Keep Save/Cancel four units from the top and bottom of their footer. Reserve validation-message space only while a message is visible.
- Restricted bank states close results silently. Show the Bank Tags title banner only after an attempted opening; hide it when the restriction clears or changes. Never show match counts in the banner.

- Copy Bank Tags’ folder row accents, stripes, chevrons, indentation, item icons and selected outlines. Drag within siblings or move folder blocks; change membership via the row menu.
- Query and folder Rename uses Bank Tags’ 360x176 name-and-item-slot editor. The icon picker keeps its 8x5 item grid, name search and hover tooltips. New/edit query names include the same item slot.

- Match Bank Tags' footer exactly: 28-unit EXPORT icon at the left, eight-unit gap, wide native New Query button, and 28-unit PENCIL icon at the right only while a query is selected. No footer Delete action. Keep Share and New available with no selection.
- Import / Share is a 520x520 two-tab popup, copied from Bank Tags: paste/preview first; single-query name, 40-unit item slot and folder controls; explicit Import action; per-query code fields on Share. Controls are relabeled for queries, and query codes use their own format.
