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

// --- non-static target rejected ---
{
  const data = fixture()
  data.categories.push({ id: "c4", spaceId: "s2", name: "Feed", icon: "R", colorRole: "red", type: "rss", feedUrl: "https://f.example", feedMode: "all" })
  const next = S.moveItemToSpace(data, "i1", "s2", "c4")
  assert.strictEqual(next.items.find(function(i) { return i.id === "i1" }).spaceId, "s1", "must not move into rss category")
  assert.deepStrictEqual(S.staticCategoriesForSpace(data, "s2").map(function(c) { return c.id }), ["c3"])
}

// --- upsertItem appends on category/space change, keeps position otherwise ---
function payloadFor(data, id, over) {
  const it = data.items.find(function(i) { return i.id === id })
  return Object.assign({}, it, over)
}

{
  const data = fixture()
  const next = S.upsertItem(data, payloadFor(data, "i1", { categoryId: "c2" }))
  assert.deepStrictEqual(idsInCat(next, "s1", "c2"), ["ix", "i1"], "appended to end of target category")
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i2", "i3"])
}

{
  const data = fixture()
  const next = S.upsertItem(data, payloadFor(data, "i1", { title: "A2" }))
  assert.deepStrictEqual(idsInCat(next, "s1", "c1"), ["i1", "i2", "i3"], "position kept on in-place update")
  assert.strictEqual(next.items.find(function(i) { return i.id === "i1" }).title, "A2")
}

{
  const data = fixture()
  const next = S.upsertItem(data, payloadFor(data, "i2", { spaceId: "s2", categoryId: "c3" }))
  assert.deepStrictEqual(idsInCat(next, "s2", "c3"), ["i2"])
  assert.strictEqual(next.items.length, data.items.length)
}

console.log("storage-move-reorder: all assertions ok")
