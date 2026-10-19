# Move Between Spaces & Reorder Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users reorder static bookmarks/apps within a category via up/down arrows, and move them to another space+category from the edit modal and the context menu.

**Architecture:** Pure helpers in `Storage.js` rearrange the `items` array (no new schema fields). `Megamenu.qml` wires hover ▲/▼ in category columns, a Space pill selector in the edit modal, and a two-step Space→category picker in the context menu. Orbit pin clears only when `spaceId` actually changes.

**Tech Stack:** QML (Omarchy shell), `Storage.js` / `I18n.js` (plain JS with existing `module.exports` for Node), Node.js `assert` for unit tests.

**Spec:** `docs/superpowers/specs/2026-10-19-move-reorder-items-design.md`

## Global Constraints

- No `sortOrder` field — order = position in `data.items`
- No drag & drop; no category/space reordering; no extension changes
- Clear `pinnedSlot` only when `spaceId` changes; keep pin on same-space category change
- Keep `favorite` and all other item fields unchanged on move/reorder
- Up/down arrows only in category column lists (not search / `>` apps view)
- Hide move/reorder UI for `isLiveItem` and `isSystemResult`
- EN + CS strings for every new user-visible label
- Follow existing CRUD pattern: clone → mutate → return next data → `commitData`

## File map

| File | Responsibility |
| --- | --- |
| `Storage.js` | `moveItemInCategory`, `moveItemToSpace`, pin-clear in `upsertItem`, export both |
| `tests/storage-move-reorder.test.js` | Node unit tests for the new helpers + upsert pin behavior |
| `I18n.js` | New EN/CS keys |
| `Megamenu.qml` | `formItemSpaceId`, modal Space pills, context move UI, row ▲/▼, handler functions |

---

### Task 1: Storage — `moveItemInCategory` + pin clear on space change in `upsertItem`

**Files:**
- Modify: `Storage.js` (after `deleteItem`, ~line 884; also `upsertItem` ~845–874; `module.exports` ~1061–1091)
- Create: `tests/storage-move-reorder.test.js`

**Interfaces:**
- Consumes: `cloneData`, existing `items` / `categories` shape
- Produces:
  - `moveItemInCategory(data, itemId, direction)` → next data  
    `direction` is `"up"` | `"down"`
  - `upsertItem` forces `pinnedSlot = 0` when updating an item whose `spaceId` changes

- [ ] **Step 1: Write the failing tests**

Create `tests/storage-move-reorder.test.js`:

```javascript
const assert = require("assert")
const S = require("../Storage.js")

function fixture() {
  return {
    version: 1,
    activeSpaceId: "s1",
    spaces: [
      { id: "s1", name: "One", icon: "A" },
      { id: "s2", name: "Two", icon: "B" }
    ],
    categories: [
      { id: "c1", spaceId: "s1", name: "Cat1", icon: "X", colorRole: "blue", type: "static", feedUrl: "", feedMode: "all" },
      { id: "c2", spaceId: "s1", name: "Cat2", icon: "Y", colorRole: "green", type: "static", feedUrl: "", feedMode: "all" },
      { id: "c3", spaceId: "s2", name: "Other", icon: "Z", colorRole: "red", type: "static", feedUrl: "", feedMode: "all" }
    ],
    items: [
      { id: "i1", spaceId: "s1", categoryId: "c1", type: "url", title: "A", subtitle: "", url: "https://a.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "" },
      { id: "i2", spaceId: "s1", categoryId: "c1", type: "url", title: "B", subtitle: "", url: "https://b.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: true, pinnedSlot: 2, badgeText: "", colorRole: "" },
      { id: "i3", spaceId: "s1", categoryId: "c1", type: "url", title: "C", subtitle: "", url: "https://c.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "" },
      { id: "ix", spaceId: "s1", categoryId: "c2", type: "url", title: "OtherCat", subtitle: "", url: "https://x.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "" }
    ],
    settings: { locale: "auto" }
  }
}

function idsInCat(data, spaceId, categoryId) {
  return data.items
    .filter(function(it) { return it.spaceId === spaceId && it.categoryId === categoryId })
    .map(function(it) { return it.id })
}

// --- moveItemInCategory ---
assert.strictEqual(typeof S.moveItemInCategory, "function", "moveItemInCategory export missing")

{
  const data = fixture()
  const next = S.moveItemInCategory(data, "i2", "up")
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i2", "i1", "i3"])
  assert.strictEqual(next.items.find(function(i) { return i.id === "i2" }).favorite, true)
  assert.strictEqual(next.items.find(function(i) { return i.id === "i2" }).pinnedSlot, 2)
}

{
  const data = fixture()
  const next = S.moveItemInCategory(data, "i2", "down")
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i1", "i3", "i2"])
}

{
  const data = fixture()
  const up = S.moveItemInCategory(data, "i1", "up")
  assert.deepStrictEqual(idsInCat(up, "s1", "c1"), ["i1", "i2", "i3"])
  const down = S.moveItemInCategory(data, "i3", "down")
  assert.deepStrictEqual(idsInCat(down, "s1", "c1"), ["i1", "i2", "i3"])
}

{
  const data = fixture()
  const next = S.moveItemInCategory(data, "missing", "up")
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i1", "i2", "i3"])
}

// --- upsertItem clears pin on space change ---
{
  const data = fixture()
  const next = S.upsertItem(data, {
    id: "i2",
    spaceId: "s2",
    categoryId: "c3",
    type: "url",
    title: "B",
    subtitle: "",
    url: "https://b.example",
    desktopId: "",
    iconType: "favicon",
    iconValue: "",
    favorite: true,
    pinnedSlot: 2,
    badgeText: "",
    colorRole: ""
  })
  const item = next.items.find(function(i) { return i.id === "i2" })
  assert.strictEqual(item.spaceId, "s2")
  assert.strictEqual(item.categoryId, "c3")
  assert.strictEqual(item.pinnedSlot, 0, "pin must clear when space changes")
  assert.strictEqual(item.favorite, true)
}

{
  const data = fixture()
  const next = S.upsertItem(data, {
    id: "i2",
    spaceId: "s1",
    categoryId: "c2",
    type: "url",
    title: "B",
    subtitle: "",
    url: "https://b.example",
    desktopId: "",
    iconType: "favicon",
    iconValue: "",
    favorite: true,
    pinnedSlot: 2,
    badgeText: "",
    colorRole: ""
  })
  assert.strictEqual(next.items.find(function(i) { return i.id === "i2" }).pinnedSlot, 2, "pin kept on same-space category change")
}

console.log("storage-move-reorder: task1 assertions ok (partial until Task 2)")
```

- [ ] **Step 2: Run tests — expect fail**

```bash
node tests/storage-move-reorder.test.js
```

Expected: `AssertionError` / `TypeError: S.moveItemInCategory is not a function` (or similar).

- [ ] **Step 3: Implement `moveItemInCategory` and upsert pin-clear**

Insert after `deleteItem` in `Storage.js`:

```javascript
function moveItemInCategory(data, itemId, direction) {
  var next = cloneData(data)
  var id = String(itemId || "")
  var dir = direction === "down" ? "down" : "up"
  var idx = -1
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === id) {
      idx = i
      break
    }
  }
  if (idx < 0) return next

  var spaceId = next.items[idx].spaceId
  var categoryId = next.items[idx].categoryId
  var group = []
  for (var g = 0; g < next.items.length; g++) {
    if (next.items[g].spaceId === spaceId && next.items[g].categoryId === categoryId) {
      group.push(g)
    }
  }
  var pos = -1
  for (var p = 0; p < group.length; p++) {
    if (group[p] === idx) {
      pos = p
      break
    }
  }
  if (pos < 0) return next
  var swapPos = dir === "up" ? pos - 1 : pos + 1
  if (swapPos < 0 || swapPos >= group.length) return next

  var a = group[pos]
  var b = group[swapPos]
  var tmp = next.items[a]
  next.items[a] = next.items[b]
  next.items[b] = tmp
  return next
}
```

In `upsertItem`, after `var clean = sanitizeItem(...)` and the `if (!clean) return next` check, **before** the pinnedSlot collision loop, add:

```javascript
  var previousSpaceId = ""
  for (var findPrev = 0; findPrev < next.items.length; findPrev++) {
    if (next.items[findPrev].id === clean.id) {
      previousSpaceId = next.items[findPrev].spaceId
      break
    }
  }
  if (previousSpaceId && previousSpaceId !== clean.spaceId) {
    clean.pinnedSlot = 0
  }
```

Add to `module.exports`:

```javascript
    moveItemInCategory: moveItemInCategory,
```

- [ ] **Step 4: Run tests again**

```bash
node tests/storage-move-reorder.test.js
```

Expected: prints `storage-move-reorder: task1 assertions ok (partial until Task 2)` with exit code 0.  
(If Task 2 tests are already in the file and fail on missing `moveItemToSpace`, keep Task 1 assertions in this file first and add Task 2 tests in Task 2 — do not leave failing unrelated asserts.)

- [ ] **Step 5: Commit**

```bash
git add Storage.js tests/storage-move-reorder.test.js
git commit -m "$(cat <<'EOF'
feat: reorder items within category via Storage helper

Add moveItemInCategory and clear Orbit pin when upsertItem
changes an item's spaceId.
EOF
)"
```

---

### Task 2: Storage — `moveItemToSpace`

**Files:**
- Modify: `Storage.js` (after `moveItemInCategory`; `module.exports`)
- Modify: `tests/storage-move-reorder.test.js`

**Interfaces:**
- Consumes: `cloneData`, `categoriesForSpace` (or inline category lookup)
- Produces: `moveItemToSpace(data, itemId, targetSpaceId, targetCategoryId)` → next data  
  - Invalid space/category/item → unchanged logical state (cloned no-op)  
  - Same space + same category → no-op  
  - Same space + different category → update `categoryId`, **keep** `pinnedSlot`, append to end of target category order  
  - Different space → update `spaceId` + `categoryId`, set `pinnedSlot = 0`, append to end of target category order  
  - Preserve `favorite` and other fields

- [ ] **Step 1: Append failing tests** to `tests/storage-move-reorder.test.js` (replace the final `console.log` with these asserts + a new log):

```javascript
assert.strictEqual(typeof S.moveItemToSpace, "function", "moveItemToSpace export missing")

{
  const data = fixture()
  const next = S.moveItemToSpace(data, "i2", "s2", "c3")
  const item = next.items.find(function(i) { return i.id === "i2" })
  assert.strictEqual(item.spaceId, "s2")
  assert.strictEqual(item.categoryId, "c3")
  assert.strictEqual(item.pinnedSlot, 0)
  assert.strictEqual(item.favorite, true)
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i1", "i3"])
  assert.deepStrictEqual(idsInCat(next, "s2", "c3"), ["i2"])
}

{
  const data = fixture()
  const next = S.moveItemToSpace(data, "i1", "s1", "c2")
  const item = next.items.find(function(i) { return i.id === "i1" })
  assert.strictEqual(item.spaceId, "s1")
  assert.strictEqual(item.categoryId, "c2")
  assert.strictEqual(item.pinnedSlot, 0)
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i2", "i3"])
  assert.deepStrictEqual(idsInCat(next, "s1", "c2"), ["ix", "i1"])
}

{
  const data = fixture()
  data.items.find(function(i) { return i.id === "i2" }).pinnedSlot = 3
  const next = S.moveItemToSpace(data, "i2", "s1", "c1")
  assert.strictEqual(next.items.find(function(i) { return i.id === "i2" }).pinnedSlot, 3)
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i1", "i2", "i3"])
}

{
  const data = fixture()
  const badSpace = S.moveItemToSpace(data, "i1", "nope", "c3")
  assert.deepStrictEqual(idsInCat(badSpace, "s1", "c1"), ["i1", "i2", "i3"])
  const badCat = S.moveItemToSpace(data, "i1", "s2", "c1")
  assert.strictEqual(badCat.items.find(function(i) { return i.id === "i1" }).spaceId, "s1")
}

console.log("storage-move-reorder: all assertions ok")
```

- [ ] **Step 2: Run tests — expect fail**

```bash
node tests/storage-move-reorder.test.js
```

Expected: fail on missing `moveItemToSpace`.

- [ ] **Step 3: Implement `moveItemToSpace`**

```javascript
function moveItemToSpace(data, itemId, targetSpaceId, targetCategoryId) {
  var next = cloneData(data)
  var id = String(itemId || "")
  var spaceId = String(targetSpaceId || "")
  var categoryId = String(targetCategoryId || "")

  var spaceOk = false
  for (var s = 0; s < next.spaces.length; s++) {
    if (next.spaces[s].id === spaceId) {
      spaceOk = true
      break
    }
  }
  if (!spaceOk) return next

  var catOk = false
  for (var c = 0; c < next.categories.length; c++) {
    if (next.categories[c].id === categoryId && next.categories[c].spaceId === spaceId) {
      catOk = true
      break
    }
  }
  if (!catOk) return next

  var idx = -1
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === id) {
      idx = i
      break
    }
  }
  if (idx < 0) return next

  var item = next.items[idx]
  if (item.spaceId === spaceId && item.categoryId === categoryId) return next

  var moved = {}
  for (var prop in item) {
    if (Object.prototype.hasOwnProperty.call(item, prop)) moved[prop] = item[prop]
  }
  var spaceChanged = moved.spaceId !== spaceId
  moved.spaceId = spaceId
  moved.categoryId = categoryId
  if (spaceChanged) moved.pinnedSlot = 0

  next.items.splice(idx, 1)

  var insertAt = next.items.length
  for (var j = next.items.length - 1; j >= 0; j--) {
    if (next.items[j].spaceId === spaceId && next.items[j].categoryId === categoryId) {
      insertAt = j + 1
      break
    }
  }
  next.items.splice(insertAt, 0, moved)
  return next
}
```

Export it:

```javascript
    moveItemToSpace: moveItemToSpace,
```

- [ ] **Step 4: Run tests — expect pass**

```bash
node tests/storage-move-reorder.test.js
```

Expected: `storage-move-reorder: all assertions ok`

- [ ] **Step 5: Commit**

```bash
git add Storage.js tests/storage-move-reorder.test.js
git commit -m "$(cat <<'EOF'
feat: move items between spaces in Storage

Add moveItemToSpace with pin clearing only when spaceId changes
and append-to-category ordering.
EOF
)"
```

---

### Task 3: i18n strings + edit modal Space selector

**Files:**
- Modify: `I18n.js` (EN block ~context/modal keys; CS block matching)
- Modify: `Megamenu.qml` (form properties ~86–98; `openNewItemModal` / `openEditItemModal` / `saveItemModal` ~678–754; edit modal category section ~3677–3695)

**Interfaces:**
- Consumes: `Storage.categoriesForSpace`, `Storage.upsertItem` (pin behavior from Task 1)
- Produces: `formItemSpaceId` property; modal Space pills; `saveItemModal` uses `formItemSpaceId` instead of hard-coded `root.activeSpaceId`

- [ ] **Step 1: Add i18n keys**

In `I18n.js` **en** (near `ctxEditItem` / `fieldCategory`):

```javascript
    ctxMoveTo: "󰀻  Move to…",
    ctxMoveBack: "← Spaces",
    fieldSpace: "Space",
    statusItemMoved: "Moved: ",
    statusMoveFailed: "Could not move item (missing space or category)",
```

In **cs**:

```javascript
    ctxMoveTo: "󰀻  Přesunout do…",
    ctxMoveBack: "← Prostory",
    fieldSpace: "Prostor",
    statusItemMoved: "Přesunuto: ",
    statusMoveFailed: "Položku nelze přesunout (chybí prostor nebo kategorie)",
```

- [ ] **Step 2: Add `formItemSpaceId` and wire modal open/save**

Near other `formItem*` properties:

```qml
  property string formItemSpaceId: ""
```

In `openNewItemModal`, after setting category default:

```qml
    root.formItemSpaceId = root.activeSpaceId
```

In `openEditItemModal`:

```qml
    root.formItemSpaceId = item.spaceId || root.activeSpaceId
```

Add helper (near other form helpers):

```qml
  function formCategoriesForSelectedSpace() {
    return Storage.categoriesForSpace(root.data, root.formItemSpaceId || root.activeSpaceId)
  }

  function onFormSpaceChosen(spaceId) {
    if (!spaceId || spaceId === root.formItemSpaceId) return
    root.formItemSpaceId = spaceId
    var cats = root.formCategoriesForSelectedSpace()
    var stillValid = false
    for (var i = 0; i < cats.length; i++) {
      if (cats[i].id === root.formItemCategoryId) {
        stillValid = true
        break
      }
    }
    root.formItemCategoryId = stillValid ? root.formItemCategoryId : (cats.length ? cats[0].id : "")
    if (spaceId !== root.activeSpaceId && root.formItemPinnedSlot > 0) {
      root.formItemPinnedSlot = 0
    }
  }
```

In `saveItemModal` payload, replace `spaceId: root.activeSpaceId` with:

```qml
      spaceId: root.formItemSpaceId || root.activeSpaceId,
```

- [ ] **Step 3: Add Space pills UI above Category in the edit item modal**

Insert a Column **before** the existing Category Selector Pills block (the one with `root.tr("fieldCategory")`), mirroring category pills but bound to spaces:

```qml
            Column {
              width: parent.width
              spacing: 4
              Text {
                text: root.tr("fieldSpace")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: (root.data && root.data.spaces) ? root.data.spaces : []
                  delegate: Button {
                    required property var modelData
                    text: (modelData.icon || "󰀻") + " " + modelData.name
                    bordered: true
                    selected: root.formItemSpaceId === modelData.id
                    onClicked: root.onFormSpaceChosen(modelData.id)
                  }
                }
              }
            }
```

Change the category `Repeater` model from `root.currentCategories` to:

```qml
                  model: root.formCategoriesForSelectedSpace()
```

- [ ] **Step 4: Manual smoke check (modal)**

```bash
node tests/storage-move-reorder.test.js
```

Expected: still pass.

Then in the running Megamenu: Edit item → Space pills appear → switching space refreshes categories → Save moves the item.

- [ ] **Step 5: Commit**

```bash
git add I18n.js Megamenu.qml
git commit -m "$(cat <<'EOF'
feat: choose target space when editing an item

Add Space pills to the item modal and persist formItemSpaceId
through upsertItem.
EOF
)"
```

---

### Task 4: Context menu — Move to… (Space → category)

**Files:**
- Modify: `Megamenu.qml` (context menu state ~74–78; `openContextMenuFor` ~645; context menu Column ~3065–3297)

**Interfaces:**
- Consumes: `Storage.moveItemToSpace`, `Storage.categoriesForSpace`
- Produces: two-step context UI (`contextMoveBrowseSpaceId`) and `confirmMoveItem(spaceId, categoryId)`

- [ ] **Step 1: Add state + handlers**

Near context menu properties:

```qml
  property string contextMoveBrowseSpaceId: ""
```

In `openContextMenuFor`, reset browse state:

```qml
    root.contextMoveBrowseSpaceId = ""
```

Add:

```qml
  function confirmMoveItem(targetSpaceId, targetCategoryId) {
    var item = root.contextMenuItem
    if (!item || item.isLiveItem === true || item.isSystemResult === true) return
    var cats = Storage.categoriesForSpace(root.data, targetSpaceId)
    if (!cats || cats.length === 0) {
      root.showStatus(root.tr("statusMoveFailed"))
      root.contextMenuOpen = false
      return
    }
    var catOk = false
    for (var i = 0; i < cats.length; i++) {
      if (cats[i].id === targetCategoryId) {
        catOk = true
        break
      }
    }
    if (!catOk) {
      root.showStatus(root.tr("statusMoveFailed"))
      root.contextMenuOpen = false
      return
    }
    var next = Storage.moveItemToSpace(root.data, item.id, targetSpaceId, targetCategoryId)
    root.contextMenuOpen = false
    root.contextMoveBrowseSpaceId = ""
    root.commitData(next)
    root.showStatus(root.tr("statusItemMoved") + (item.title || ""))
  }
```

- [ ] **Step 2: Extend context menu UI**

After the Edit row (and before Delete), insert Move UI (same visibility as Edit — static items only):

```qml
          // Move to… (two-step: spaces list, then categories)
          Rectangle {
            visible: root.contextMenuItem === null || (root.contextMenuItem.isLiveItem !== true && root.contextMenuItem.isSystemResult !== true)
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: moveCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.contextMoveBrowseSpaceId === "" ? root.tr("ctxMoveTo") : root.tr("ctxMoveBack")
              color: moveCtxMouse.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: moveCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.contextMoveBrowseSpaceId !== "") {
                  root.contextMoveBrowseSpaceId = ""
                } else {
                  root.contextMoveBrowseSpaceId = "__pick__"
                }
              }
            }
          }

          // Space list (when picking)
          Repeater {
            model: {
              if (!root.contextMenuOpen || root.contextMoveBrowseSpaceId !== "__pick__") return []
              return (root.data && root.data.spaces) ? root.data.spaces : []
            }
            delegate: Rectangle {
              required property var modelData
              width: contextMenuCol.width
              height: Style.space(30)
              radius: 4
              color: spaceMoveMouse.containsMouse ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.icon || "󰀻") + "  " + modelData.name
                color: spaceMoveMouse.containsMouse ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: spaceMoveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.contextMoveBrowseSpaceId = modelData.id
              }
            }
          }

          // Category list for chosen space
          Repeater {
            model: {
              if (!root.contextMenuOpen || root.contextMoveBrowseSpaceId === "" || root.contextMoveBrowseSpaceId === "__pick__") return []
              return Storage.categoriesForSpace(root.data, root.contextMoveBrowseSpaceId)
            }
            delegate: Rectangle {
              required property var modelData
              width: contextMenuCol.width
              height: Style.space(30)
              radius: 4
              color: catMoveMouse.containsMouse ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.icon || "󰉋") + "  " + modelData.name
                color: catMoveMouse.containsMouse ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: catMoveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmMoveItem(root.contextMoveBrowseSpaceId, modelData.id)
              }
            }
          }
```

Notes for the implementer:
- Sentinel `"__pick__"` means “show spaces”; a real space id means “show that space’s categories”.
- The top Move row toggles back to spaces when already browsing a space.
- Hide browser-launch / copy sections are unchanged; keep Move with Edit/Delete visibility rules.

- [ ] **Step 3: Manual check**

Right-click static item → Move to… → Space → Category → item leaves current space (if different) → toast. Same-space category change keeps Orbit pin.

- [ ] **Step 4: Commit**

```bash
git add Megamenu.qml I18n.js
git commit -m "$(cat <<'EOF'
feat: move bookmarks from context menu

Add a two-step Space → category picker that calls moveItemToSpace.
EOF
)"
```

---

### Task 5: Up/down arrows on category column rows

**Files:**
- Modify: `Megamenu.qml` (`rowRightActions` inside category `ListView` delegate ~2720–2780)

**Interfaces:**
- Consumes: `Storage.moveItemInCategory`, ListView `index` / `count`
- Produces: hover ▲/▼ buttons; no arrows for live entries

- [ ] **Step 1: Add reorder handler**

```qml
  function reorderItemInCategory(itemId, direction) {
    if (!itemId) return
    var next = Storage.moveItemInCategory(root.data, itemId, direction)
    root.commitData(next)
  }
```

- [ ] **Step 2: Add ▲/▼ into `rowRightActions`**

Inside the category column item delegate’s `rowRightActions` Row, **before** the favorite star, only for non-live static items. Use ListView’s `index` (Qt provides it on delegates):

```qml
                          // Reorder up/down (static items only, category columns only)
                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            visible: !itemRowRect.isLiveEntry
                              && !(modelData.isSystemResult === true)
                              && (itemRowRect.isHovered || itemRowRect.isSelected)
                              && index > 0
                            color: moveUpMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"

                            Text {
                              anchors.centerIn: parent
                              text: "▲"
                              color: Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                              id: moveUpMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.reorderItemInCategory(modelData.id, "up")
                            }
                          }

                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            visible: !itemRowRect.isLiveEntry
                              && !(modelData.isSystemResult === true)
                              && (itemRowRect.isHovered || itemRowRect.isSelected)
                              && index < (catListView.count - 1)
                            color: moveDownMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"

                            Text {
                              anchors.centerIn: parent
                              text: "▼"
                              color: Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                              id: moveDownMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.reorderItemInCategory(modelData.id, "down")
                            }
                          }
```

Also update `rowMouse.anchors.rightMargin` if needed so clicks on arrows are not eaten — arrows live in `rowRightActions`, and `rowMouse` already uses `anchors.rightMargin: rowRightActions.width + Style.space(10)`, so width growth is fine.

Do **not** add these arrows to search-result lists or the `>` apps view.

- [ ] **Step 3: Manual verification checklist**

1. Hover middle item → ▲ and ▼ → order persists after reopen  
2. First item: no ▲; last item: no ▼  
3. Live RSS/GitHub rows: no arrows  
4. Search results: no arrows  
5. EN/CS: Move / Space / status strings  

```bash
node tests/storage-move-reorder.test.js
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Megamenu.qml
git commit -m "$(cat <<'EOF'
feat: reorder category items with up/down controls

Show hover arrows on static bookmark rows in category columns.
EOF
)"
```

---

### Task 6: Final verification pass

**Files:**
- None required (docs optional)

- [ ] **Step 1: Re-run unit tests**

```bash
node tests/storage-move-reorder.test.js
```

Expected: `storage-move-reorder: all assertions ok`

- [ ] **Step 2: Walk the spec test plan**

From `docs/superpowers/specs/2026-10-19-move-reorder-items-design.md` § Testing (manual):

1. Reorder middle item; reopen Megamenu — order kept  
2. First/last arrows hidden; no crash  
3. Edit modal space change → pin cleared if it had one  
4. Context menu cross-space move → toast; pin cleared  
5. Same-space category via menu → pin kept  
6. Live/system → no move, no arrows  
7. Switch UI to CS and confirm new strings  

- [ ] **Step 3: Commit only if Step 2 found fixes**

If fixes were needed, commit them with a focused message (e.g. `fix: hide reorder arrows on live rows`). If nothing changed, skip commit.

---

## Self-review (plan vs spec)

| Spec requirement | Task |
| --- | --- |
| `moveItemInCategory` array swap | Task 1 |
| `moveItemToSpace` + pin clear on space change | Task 2 |
| `upsertItem` pin clear on space change | Task 1 |
| Edit modal Space + category refresh | Task 3 |
| Context menu Space → category | Task 4 |
| Up/down arrows in category columns only | Task 5 |
| No arrows in search / `>` view | Task 5 (explicit non-add) |
| Hide for live/system | Tasks 4–5 |
| EN/CS strings | Task 3 |
| No schema / no extension / no DnD | Global constraints |
| Manual QA list | Task 6 |
| Unit-testable Storage helpers | Tasks 1–2 (`tests/storage-move-reorder.test.js`) |
