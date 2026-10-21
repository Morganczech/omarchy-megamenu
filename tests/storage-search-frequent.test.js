const assert = require("assert")
const S = require("../Storage.js")

function fixture() {
  return {
    version: 1,
    activeSpaceId: "s1",
    spaces: [
      { id: "s1", name: "One", icon: "A" },
      { id: "s2", name: "Two", icon: "B" },
      { id: "s3", name: "Three", icon: "C" }
    ],
    categories: [
      { id: "c1", spaceId: "s1", name: "Cat1", icon: "X", colorRole: "blue", type: "static", feedUrl: "", feedMode: "all" },
      { id: "c3", spaceId: "s2", name: "Other", icon: "Z", colorRole: "red", type: "static", feedUrl: "", feedMode: "all" },
      { id: "c4", spaceId: "s3", name: "Third", icon: "W", colorRole: "green", type: "static", feedUrl: "", feedMode: "all" }
    ],
    items: [
      { id: "i1", spaceId: "s1", categoryId: "c1", type: "url", title: "Alpha Local", subtitle: "", url: "https://a.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "" },
      { id: "i2", spaceId: "s2", categoryId: "c3", type: "url", title: "Beta Remote", subtitle: "", url: "https://b.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "", launchCount: 5, lastLaunchedAt: 100 },
      { id: "i3", spaceId: "s3", categoryId: "c4", type: "url", title: "Gamma Rare", subtitle: "", url: "https://g.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "", launchCount: 2, lastLaunchedAt: 200 },
      { id: "i4", spaceId: "s2", categoryId: "c3", type: "url", title: "Delta Hot", subtitle: "", url: "https://d.example", desktopId: "", iconType: "favicon", iconValue: "", favorite: false, pinnedSlot: 0, badgeText: "", colorRole: "", launchCount: 5, lastLaunchedAt: 300 }
    ]
  }
}

// --- filterItems searches across spaces when query is set ---
{
  const data = fixture()
  const empty = S.filterItems(data, "s1", "all", "", null)
  assert.deepStrictEqual(empty.map(function(i) { return i.id }), ["i1"])

  const cross = S.filterItems(data, "s1", "all", "Beta", null)
  assert.strictEqual(cross.length, 1)
  assert.strictEqual(cross[0].id, "i2")
  assert.strictEqual(cross[0].spaceId, "s2")

  const both = S.filterItems(data, "s1", "all", "a", null)
  const ids = both.map(function(i) { return i.id }).sort()
  assert.deepStrictEqual(ids, ["i1", "i2", "i3", "i4"])
}

// --- otherSpaceSearchGroups ---
{
  const data = fixture()
  const filtered = S.filterItems(data, "s1", "all", "a", null)
  const groups = S.otherSpaceSearchGroups(data, "s1", filtered)
  assert.strictEqual(groups.length, 2)
  assert.strictEqual(groups[0].spaceId, "s2")
  assert.strictEqual(groups[0].name, "Two")
  assert.ok(groups[0].items.some(function(i) { return i.id === "i2" }))
  assert.strictEqual(groups[1].spaceId, "s3")
  assert.strictEqual(groups[1].name, "Three")
}

{
  const data = fixture()
  const onlyLocal = S.filterItems(data, "s1", "all", "Alpha", null)
  const groups = S.otherSpaceSearchGroups(data, "s1", onlyLocal)
  assert.deepStrictEqual(groups, [])
}

// --- recordLaunch ---
{
  const data = fixture()
  const next = S.recordLaunch(data, "i1")
  const item = next.items.find(function(i) { return i.id === "i1" })
  assert.strictEqual(item.launchCount, 1)
  assert.ok(item.lastLaunchedAt > 0)

  const again = S.recordLaunch(next, "i1")
  assert.strictEqual(again.items.find(function(i) { return i.id === "i1" }).launchCount, 2)
}

{
  const data = fixture()
  const next = S.recordLaunch(data, "missing")
  assert.strictEqual(next.items.find(function(i) { return i.id === "i1" }).launchCount, 0)
}

// --- sanitizeItem preserves launch stats ---
{
  const item = S.sanitizeItem({
    id: "x",
    spaceId: "s1",
    categoryId: "c1",
    type: "url",
    title: "X",
    url: "https://x.example",
    launchCount: 9,
    lastLaunchedAt: 42
  }, "s1", "c1")
  assert.strictEqual(item.launchCount, 9)
  assert.strictEqual(item.lastLaunchedAt, 42)
}

// --- frequentItems ---
{
  const data = fixture()
  const top = S.frequentItems(data, 3)
  assert.deepStrictEqual(top.map(function(i) { return i.id }), ["i4", "i2", "i3"])
}

{
  const data = fixture()
  data.items[0].launchCount = 0
  const top = S.frequentItems(data, 10)
  assert.strictEqual(top.length, 3)
  assert.ok(!top.some(function(i) { return i.id === "i1" }))
}

console.log("storage-search-frequent: ok")
