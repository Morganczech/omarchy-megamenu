const assert = require("assert")
const S = require("../Storage.js")

assert.strictEqual(S.noteListTitle("# Nadpis\n\ntext", "file"), "Nadpis")
assert.strictEqual(S.noteListTitle("##  Druhy\n", "file"), "Druhy")
assert.strictEqual(
  S.noteListTitle("---\ntitle: Old\n---\n# Real\n", "file"),
  "Real"
)
assert.strictEqual(S.noteListTitle("plain line\n", "file"), "file")
assert.strictEqual(S.noteListTitle("", "file"), "file")

assert.strictEqual(S.noteFilename("Nadpis", []), "Nadpis.md")
assert.strictEqual(S.noteFilename("# Nadpis", []), "Nadpis.md")
assert.strictEqual(S.noteFilename("a/b", []), "a-b.md")
assert.strictEqual(S.noteFilename("...", []), "note.md")
assert.strictEqual(S.noteFilename("Nadpis", ["Nadpis.md"]), "Nadpis-2.md")
assert.strictEqual(S.noteFilename("Nadpis", ["Nadpis.md", "Nadpis-2.md"]), "Nadpis-3.md")

assert.strictEqual(S.notePathAllowed("/notes/a.md", ["/notes"]), true)
assert.strictEqual(S.notePathAllowed("/notes/sub/a.md", ["/notes"]), true)
assert.strictEqual(S.notePathAllowed("/other/a.md", ["/notes"]), false)
assert.strictEqual(S.notePathAllowed("/notes/../etc/passwd", ["/notes"]), false)

const notes = {
  writeRoot: "/notes",
  roots: ["/extra"],
  cards: [
    { path: "/notes/keep.md", categoryId: "cat-work", colorRole: "green", badgeText: "Pin", pinnedSlot: 2 },
    { path: "/gone.md", categoryId: "cat-notes-inbox", colorRole: "", badgeText: "", pinnedSlot: 0 }
  ]
}
const merged = S.mergeNoteScan(notes, [
  { path: "/notes/keep.md", title: "Keep", mtime: 1, size: 10, tooLarge: false },
  { path: "/extra/new.md", title: "New", mtime: 2, size: 20, tooLarge: false }
], "cat-notes-inbox", false)
assert.strictEqual(merged.cards.length, 2)
assert.strictEqual(merged.cards[0].colorRole, "green")
assert.strictEqual(merged.cards[0].pinnedSlot, 2)
assert.strictEqual(merged.cards[1].path, "/extra/new.md")
assert.strictEqual(merged.cards[1].categoryId, "cat-notes-inbox")

const truncated = S.mergeNoteScan(notes, [
  { path: "/notes/keep.md", title: "Keep", mtime: 1, size: 10, tooLarge: false }
], "cat-notes-inbox", true)
assert.ok(truncated.cards.some(function (c) { return c.path === "/gone.md" }))

const hiddenCards = [
  { path: "/notes/keep.md", categoryId: "cat-work", colorRole: "green", badgeText: "Pin", pinnedSlot: 2 },
  { path: "/notes/folder/later-note.md", categoryId: "cat-notes-inbox", colorRole: "blue", badgeText: "H", pinnedSlot: 1 }
]
const visibleRows = S.notesModelRows(hiddenCards, [
  { path: "/notes/keep.md", title: "Keep", mtime: 9, size: 10, tooLarge: false }
])
assert.strictEqual(visibleRows.length, 2)
const hiddenRow = visibleRows.find(function (row) { return row.path === "/notes/folder/later-note.md" })
assert.ok(hiddenRow)
assert.strictEqual(hiddenRow.title, S.noteListTitle("", "later-note"))
assert.strictEqual(hiddenRow.title, "later-note")
assert.strictEqual(hiddenRow.badgeText, "H")
assert.strictEqual(hiddenRow.colorRole, "blue")
assert.strictEqual(hiddenRow.categoryId, "cat-notes-inbox")
assert.strictEqual(hiddenRow.pinnedSlot, 1)
assert.strictEqual(hiddenRow.mtime, 0)
assert.strictEqual(hiddenRow.tooLarge, false)
const keepRow = visibleRows.find(function (row) { return row.path === "/notes/keep.md" })
assert.strictEqual(keepRow.title, "Keep")
assert.strictEqual(keepRow.mtime, 9)
assert.strictEqual(keepRow.tooLarge, false)
assert.strictEqual(hiddenCards.length, 2)

const cleanA = { path: "/notes/a.md", text: "A", frontmatter: "", mtime: 1, dirty: false }
const typedA = { path: "/notes/a.md", text: "typed", frontmatter: "fm", mtime: 1, dirty: true }
const readB = { ok: true, body: "B", frontmatter: "---\nx\n---", mtime: 4 }
const openedB = S.noteReadSettlement(1, cleanA, "/notes/b.md", readB)
assert.strictEqual(openedB.action, "replace")
assert.strictEqual(openedB.token, 2)
assert.strictEqual(openedB.readOnly, false)
assert.strictEqual(openedB.draft.path, "/notes/b.md")
assert.strictEqual(openedB.draft.text, "B")
assert.strictEqual(openedB.draft.frontmatter, "---\nx\n---")
assert.strictEqual(openedB.draft.mtime, 4)
assert.strictEqual(openedB.draft.dirty, false)
assert.notStrictEqual(1, openedB.token)

const keptTyped = S.noteReadSettlement(1, typedA, "/notes/b.md", readB)
assert.strictEqual(keptTyped.action, "keep")
assert.strictEqual(keptTyped.token, 1)

const tooBig = S.noteReadSettlement(1, cleanA, "/notes/big.md", { ok: true, tooLarge: true, mtime: 7 })
assert.strictEqual(tooBig.action, "replace")
assert.strictEqual(tooBig.token, 2)
assert.strictEqual(tooBig.readOnly, true)
assert.strictEqual(tooBig.draft.text, "")
assert.strictEqual(tooBig.draft.frontmatter, "")
assert.strictEqual(tooBig.draft.path, "/notes/big.md")
assert.strictEqual(tooBig.draft.mtime, 7)
assert.strictEqual(tooBig.draft.dirty, false)

const typedTooBig = S.noteReadSettlement(1, typedA, "/notes/big.md", { ok: true, tooLarge: true, mtime: 7 })
assert.strictEqual(typedTooBig.action, "keep")
assert.strictEqual(typedTooBig.token, 1)

const missingClean = S.noteReadSettlement(1, cleanA, "/gone.md", { ok: false, error: "missing" })
assert.strictEqual(missingClean.action, "drop")
assert.strictEqual(missingClean.token, 2)

const missingTyped = S.noteReadSettlement(1, typedA, "/gone.md", { ok: false, error: "missing" })
assert.strictEqual(missingTyped.action, "fail")
assert.strictEqual(missingTyped.token, 1)

const unreadable = S.noteReadSettlement(1, cleanA, "/notes/a.md", { ok: false, error: "unreadable" })
assert.strictEqual(unreadable.action, "fail")
assert.strictEqual(unreadable.token, 1)

const crashed = S.noteReadSettlement(1, cleanA, "/notes/a.md", null)
assert.strictEqual(crashed.action, "fail")
assert.strictEqual(crashed.token, 1)

const staleWrite = S.noteWriteDraft(1, openedB.token, openedB.draft, "/notes/a.md", 9, "A", "")
assert.strictEqual(staleWrite, null)
const liveWrite = S.noteWriteDraft(1, 1, typedA, "/notes/a.md", 9, "A", "")
assert.strictEqual(liveWrite.draft.path, "/notes/a.md")
assert.strictEqual(liveWrite.draft.text, "typed")
assert.strictEqual(liveWrite.draft.frontmatter, "fm")
assert.strictEqual(liveWrite.draft.mtime, 9)
assert.strictEqual(liveWrite.draft.dirty, true)
assert.strictEqual(liveWrite.doneOk, false)
assert.strictEqual(liveWrite.readOnly, false)
const sameWrite = S.noteWriteDraft(4, 4, { path: "/notes/a.md", text: "A", frontmatter: "", mtime: 1, dirty: true }, "/notes/a.md", 3, "A", "")
assert.strictEqual(sameWrite.doneOk, true)
assert.strictEqual(sameWrite.draft.dirty, false)
assert.strictEqual(sameWrite.draft.text, "A")

const fresh = S.ensureNotesModel(S.defaultData(), "Unsorted")
assert.ok(fresh.spaces.some(function (s) { return s.id === "notes" && s.type === "notes" }))
assert.ok(fresh.categories.some(function (c) { return c.id === "cat-notes-inbox" && c.name === "Unsorted" }))
assert.deepStrictEqual(fresh.notes.cards, [])

const raw = JSON.stringify({
  version: 1,
  activeSpaceId: "personal",
  language: "en",
  spaces: [{ id: "personal", name: "Personal", icon: "X" }, { id: "notes", name: "Note", icon: "Y", type: "notes" }],
  categories: [{ id: "cat-notes-inbox", spaceId: "notes", name: "Unsorted", icon: "Y", colorRole: "yellow", type: "static", feedUrl: "", feedMode: "all" }],
  items: [],
  notes: {
    writeRoot: "/notes",
    roots: ["/extra"],
    cards: [{ path: "/notes/a.md", categoryId: "cat-notes-inbox", colorRole: "blue", badgeText: "A", pinnedSlot: 1 }]
  }
})
const parsed = S.parse(raw)
assert.strictEqual(parsed.spaces.find(function (s) { return s.id === "notes" }).type, "notes")
assert.strictEqual(parsed.notes.writeRoot, "/notes")
assert.strictEqual(parsed.notes.cards[0].badgeText, "A")
assert.strictEqual(parsed.notes.cards[0].pinnedSlot, 1)
const cloned = S.cloneData(parsed)
assert.strictEqual(cloned.notes.cards[0].path, "/notes/a.md")

const legacyRaw = JSON.stringify({
  version: 1,
  activeSpaceId: "personal",
  language: "en",
  spaces: [{ id: "personal", name: "Personal", icon: "X" }],
  categories: [],
  items: []
})
const legacyParsed = S.parse(legacyRaw)
assert.ok(!legacyParsed.spaces.some(function (s) { return s.id === "notes" }))
assert.ok(!legacyParsed.categories.some(function (c) { return c.id === "cat-notes-inbox" }))
assert.ok(Array.isArray(legacyParsed.notes.cards))

const ensured = S.ensureNotesModel(legacyParsed, "Nezařazené")
assert.ok(ensured.categories.some(function (c) {
  return c.id === "cat-notes-inbox" && c.name === "Nezařazené"
}))
const ensuredAgain = S.ensureNotesModel(ensured, "Unsorted")
assert.ok(ensuredAgain.categories.some(function (c) {
  return c.id === "cat-notes-inbox" && c.name === "Nezařazené"
}))

const found = S.searchNotes(
  { cards: [{ path: "/notes/a.md", badgeText: "Trip", categoryId: "cat-notes-inbox", colorRole: "", pinnedSlot: 0 }] },
  [{ path: "/notes/a.md", title: "Nadpis" }],
  "nad"
)
assert.strictEqual(found.length, 1)
assert.strictEqual(found[0].title, "Nadpis")
assert.strictEqual(S.searchNotes(
  { cards: [] },
  [{ path: "/notes/a.md", title: "Nadpis" }],
  "body text that is not the title"
).length, 0)

const stemHit = S.searchNotes(
  { cards: [{ path: "/notes/trip.md", badgeText: "", categoryId: "cat-notes-inbox", colorRole: "", pinnedSlot: 0 }] },
  [{ path: "/notes/trip.md", title: "Nadpis" }],
  "trip"
)
assert.strictEqual(stemHit.length, 1)
assert.strictEqual(stemHit[0].path, "/notes/trip.md")

const badgeHit = S.searchNotes(
  { cards: [{ path: "/notes/x.md", badgeText: "Pin", categoryId: "cat-notes-inbox", colorRole: "", pinnedSlot: 0 }] },
  [{ path: "/notes/x.md", title: "Nadpis" }],
  "pin"
)
assert.strictEqual(badgeHit.length, 1)
assert.strictEqual(badgeHit[0].badgeText, "Pin")

assert.deepStrictEqual(S.searchNotes(
  { cards: [{ path: "/notes/a.md", badgeText: "A", categoryId: "cat-notes-inbox", colorRole: "", pinnedSlot: 0 }] },
  [{ path: "/notes/a.md", title: "Nadpis" }],
  "   "
), [])

const scanMissing = S.searchNotes(
  {
    cards: [
      { path: "/notes/folder/later-note.md", categoryId: "cat-notes-inbox", colorRole: "blue", badgeText: "H", pinnedSlot: 1 }
    ]
  },
  [{ path: "/notes/keep.md", title: "Keep", mtime: 9, size: 10, tooLarge: false }],
  "later-note"
)
assert.strictEqual(scanMissing.length, 1)
assert.strictEqual(scanMissing[0].title, "later-note")
const scanMissingBadge = S.searchNotes(
  {
    cards: [
      { path: "/notes/folder/later-note.md", categoryId: "cat-notes-inbox", colorRole: "blue", badgeText: "H", pinnedSlot: 1 }
    ]
  },
  [{ path: "/notes/keep.md", title: "Keep", mtime: 9, size: 10, tooLarge: false }],
  "h"
)
assert.strictEqual(scanMissingBadge.length, 1)
assert.strictEqual(scanMissingBadge[0].badgeText, "H")

const diskDuringScan = {
  version: 1,
  activeSpaceId: "personal",
  language: "cs",
  spaces: [{ id: "personal", name: "Personal", icon: "X" }, { id: "notes", name: "Note", icon: "Y", type: "notes" }],
  categories: [],
  items: [{ id: "saved-during-scan", spaceId: "personal", type: "url", title: "Saved during scan", url: "https://example.com/saved" }],
  notes: {
    writeRoot: "/old",
    roots: [],
    cards: [{ path: "/old/stale.md", categoryId: "cat-notes-inbox", colorRole: "", badgeText: "", pinnedSlot: 0 }]
  }
}
const scannedNotes = {
  writeRoot: "/notes",
  roots: ["/extra"],
  cards: [
    { path: "/notes/a.md", categoryId: "cat-notes-inbox", colorRole: "blue", badgeText: "A", pinnedSlot: 1 },
    { path: "", categoryId: "cat-notes-inbox", colorRole: "", badgeText: "", pinnedSlot: 9 }
  ]
}
const applied = S.applyScannedNotes(diskDuringScan, scannedNotes)
assert.strictEqual(applied.activeSpaceId, "personal")
assert.strictEqual(applied.language, "cs")
assert.strictEqual(applied.items.length, 1)
assert.strictEqual(applied.items[0].id, "saved-during-scan")
assert.strictEqual(applied.items[0].title, "Saved during scan")
assert.strictEqual(applied.notes.writeRoot, "/notes")
assert.deepStrictEqual(applied.notes.roots, ["/extra"])
assert.strictEqual(applied.notes.cards.length, 1)
assert.strictEqual(applied.notes.cards[0].path, "/notes/a.md")
assert.strictEqual(applied.notes.cards[0].badgeText, "A")
assert.strictEqual(applied.notes.cards[0].pinnedSlot, 1)
assert.ok(!applied.notes.cards.some(function (c) { return c.path === "/old/stale.md" }))

const legacyPins = S.parse(JSON.stringify({
  version: 1,
  activeSpaceId: "notes",
  language: "en",
  spaces: [{ id: "notes", name: "Note", icon: "Y", type: "notes" }],
  categories: [],
  items: [],
  notes: {
    writeRoot: "/notes",
    roots: [],
    cards: [
      { path: "/notes/slot-one.md", categoryId: "", colorRole: "", badgeText: "", pinnedSlot: 1 },
      { path: "/notes/slot-six.md", categoryId: "", colorRole: "", badgeText: "", pinnedSlot: 6 },
      { path: "/notes/explicit.md", categoryId: "", colorRole: "", badgeText: "", pinnedSlot: 1, pinOrder: 9 }
    ]
  }
}))
assert.strictEqual(legacyPins.notes.cards[0].pinOrder, 6)
assert.strictEqual(legacyPins.notes.cards[1].pinOrder, 1)
assert.strictEqual(legacyPins.notes.cards[2].pinOrder, 9)

const unpinned = S.toggleNotePin(legacyPins.notes, "/notes/slot-six.md")
const unpinnedSix = unpinned.cards.find(function (c) { return c.path === "/notes/slot-six.md" })
assert.strictEqual(unpinnedSix.pinOrder, 0)
assert.strictEqual(unpinnedSix.pinnedSlot, 0)
const repinned = S.toggleNotePin(unpinned, "/notes/slot-six.md")
const six = repinned.cards.find(function (c) { return c.path === "/notes/slot-six.md" })
const one = repinned.cards.find(function (c) { return c.path === "/notes/slot-one.md" })
assert.ok(six.pinOrder > one.pinOrder)
assert.strictEqual(six.pinnedSlot, 0)

const rankedRows = S.notesModelRows(repinned.cards, [
  { path: "/notes/slot-one.md", title: "One", mtime: 100, size: 1, tooLarge: false },
  { path: "/notes/slot-six.md", title: "Six", mtime: 1, size: 1, tooLarge: false },
  { path: "/notes/explicit.md", title: "Explicit", mtime: 5, size: 1, tooLarge: false }
])
assert.deepStrictEqual(rankedRows.map(function (row) { return row.path }), [
  "/notes/slot-six.md",
  "/notes/explicit.md",
  "/notes/slot-one.md"
])

const keptPin = S.mergeNoteScan({
  writeRoot: "/notes",
  roots: [],
  cards: [{ path: "/notes/a.md", categoryId: "cat-notes-inbox", colorRole: "", badgeText: "", pinnedSlot: 0, pinOrder: 4 }]
}, [{ path: "/notes/a.md", title: "A", mtime: 1, size: 1, tooLarge: false }], "cat-notes-inbox", false)
assert.strictEqual(keptPin.cards[0].pinOrder, 4)

console.log("storage-notes: all assertions ok")
