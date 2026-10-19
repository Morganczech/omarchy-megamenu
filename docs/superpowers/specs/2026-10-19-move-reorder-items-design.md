# Design: Move items between spaces & reorder within category

**Date:** 2026-10-19  
**Status:** Approved  
**Scope:** Omarchy Megamenu static bookmarks/apps (`items` in `data.json`)

## Problem

Users can edit, delete, and change an item’s category within the **active** space, but cannot:

1. Move a link/app to another space
2. Manually reorder items within a category list

Order today is whatever order entries have in the `items` array (insert/import order). There is no drag-and-drop and no “move to space” UI.

## Goals

- Move an item to another space + category (edit modal **and** context menu)
- Reorder items within a category via up/down controls
- Clear Orbit pin (`pinnedSlot`) when the item’s space changes
- No schema migration; keep existing `data.json` compatible

## Non-goals

- Drag & drop reordering
- Reordering categories or spaces
- Moving an entire category between spaces
- Changes to the browser extension popup (it already picks space + category on save)

## Decisions (from brainstorming)

| Topic | Choice |
| --- | --- |
| Reorder UX | Up/down arrows (not drag) |
| Move UX | Both edit modal and context menu |
| Pin on space change | Always clear (`pinnedSlot = 0`) |
| Context menu target | Two-level: Space → category |
| Order storage | Rearrange the `items` array (no `sortOrder` field) |

## Architecture

### Storage (`Storage.js`)

Two new pure helpers that clone state and return the next `data` object (same pattern as `upsertItem` / `deleteItem`):

#### `moveItemInCategory(data, itemId, direction)`

- `direction`: `"up"` | `"down"`
- Locate the item by `id`
- Build the ordered list of indices in `items` that share the same `spaceId` + `categoryId`
- Swap with the previous/next neighbor in that filtered order
- If already first/last in the category, no-op (return unchanged clone or same logical state)
- Live/system items are not stored as normal static items for this path; callers only invoke for editable static items

#### `moveItemToSpace(data, itemId, targetSpaceId, targetCategoryId)`

- Validate target space exists
- Validate target category exists and belongs to `targetSpaceId`
- Set `spaceId`, `categoryId`, force `pinnedSlot = 0`
- Preserve `favorite` and other fields
- Place the item at the **end** of the target category’s relative order (remove from current array position, re-insert after the last item that already has that space+category, or append to `items` if none)

#### `upsertItem` adjustment

When updating an existing item, if `spaceId` changes compared to the stored item, set `pinnedSlot = 0` before applying the rest of the payload (or ignore an incoming non-zero pin when space changed). Category lists in the modal must only offer categories for the chosen space.

### UI (`Megamenu.qml` + `I18n.js`)

#### Row up/down controls

- Visible for static bookmarks/apps only (not live feed rows, not Omarchy/system search results)
- Shown on hover and/or keyboard focus of the row
- ▲ / ▼ call `moveItemInCategory` then `commitData`
- Disable or hide the arrow that would be a no-op (first → no up; last → no down)

#### Edit item modal

- Add a **Space** selector (same pill/`Button` pattern as category)
- Changing space refreshes the category pills to `categoriesForSpace(target)`
- If the previous `categoryId` is not in the new space, select the first category of that space
- Save continues via `upsertItem` with the selected `spaceId` (not hard-coded `root.activeSpaceId`)

#### Context menu

- New entry: “Move to…” / “Přesunout do…”
- Submenu: each space → its categories
- Prefer listing all spaces; selecting a category in the **current** space still moves within space (category change only) and does **not** clear the pin unless `spaceId` actually changes
- On pick: `moveItemToSpace` + close menu + status toast
- Hidden for live/system items (same visibility rules as Edit/Delete)

#### i18n

Add EN + CS strings for:

- Move menu label
- Space field label in modal (if not already present)
- Status messages (moved / cannot move / reorder edge — only if user-visible)

### Data flow

```
UI action → Storage.moveItem* / upsertItem → commitData(next) → persist data.json → UI rebinds from root.data
```

Column rendering already walks `items` filtered by category; preserving array order for that filter is enough for display order.

## Edge cases

| Case | Behavior |
| --- | --- |
| Up on first / down on last in category | No-op |
| Target space has zero categories | No-op + status message |
| Invalid category for target space | No-op + status message |
| Move to same space + same category | No-op |
| Move to same space + different category | Update category; keep pin |
| Move to different space | Update space+category; clear pin |
| Favorite flag | Unchanged on move/reorder |
| Filter / search active | Up/down arrows appear **only** in the category column lists (normal browsing). They are hidden in global search results and in the `>` apps view so reorder always matches the visible category order. |

## Testing (manual)

1. Reorder middle item up and down; verify persistence after reopen
2. First/last item: arrows disabled/hidden; no crash
3. Edit modal: change space → categories refresh → save → item appears in target space; Orbit pin cleared if it had one
4. Context menu: Space → category move; toast; pin cleared on space change
5. Same-space category change via menu: pin kept
6. Live feed / system result: no move, no arrows
7. EN and CS labels for new strings

## Implementation notes

- Keep helpers unit-testable as pure JS if the repo later adds tests; for now manual QA is enough
- Avoid large refactors of `Megamenu.qml`; localize changes to item delegate, context menu, and edit modal
- Do not change extension native host or import scripts for this feature
