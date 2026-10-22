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

console.log("storage-notes: all assertions ok")
