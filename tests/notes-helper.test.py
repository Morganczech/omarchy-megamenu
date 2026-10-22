import importlib.util
import os
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "notes", os.path.join(os.path.dirname(__file__), "..", "scripts", "notes.py")
)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class NotesHelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.root = os.path.join(self.tmp, "notes")
        os.mkdir(self.root)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_scan_skips_hidden_and_symlinks(self):
        open(os.path.join(self.root, "a.md"), "w", encoding="utf-8").write("# Alpha\n")
        os.mkdir(os.path.join(self.root, ".secret"))
        open(os.path.join(self.root, ".secret", "no.md"), "w", encoding="utf-8").write("# No\n")
        os.symlink(os.path.join(self.root, "a.md"), os.path.join(self.root, "link.md"))
        result = notes.handle({"cmd": "scan", "roots": [self.root]})
        paths = [item["path"] for item in result["files"]]
        self.assertEqual(paths, [os.path.join(self.root, "a.md")])
        self.assertEqual(result["files"][0]["title"], "Alpha")
        self.assertFalse(result["truncated"])

    def test_read_splits_frontmatter_and_refuses_oversize(self):
        path = os.path.join(self.root, "a.md")
        open(path, "w", encoding="utf-8").write("---\ntitle: Old\n---\n# Alpha\n\nbody\n")
        read = notes.handle({"cmd": "read", "path": path, "roots": [self.root]})
        self.assertEqual(read["frontmatter"], "---\ntitle: Old\n---")
        self.assertTrue(read["body"].startswith("# Alpha"))
        big = os.path.join(self.root, "big.md")
        with open(big, "wb") as handle:
            handle.write(b"#" + b"x" * 1048576)
        refused = notes.handle({"cmd": "read", "path": big, "roots": [self.root]})
        self.assertTrue(refused["tooLarge"])
        self.assertEqual(refused["body"], "")

    def test_write_preserves_frontmatter_and_failed_replace_keeps_original(self):
        path = os.path.join(self.root, "a.md")
        open(path, "w", encoding="utf-8").write("old\n")
        notes.handle({
            "cmd": "write",
            "path": path,
            "roots": [self.root],
            "frontmatter": "---\ntitle: Old\n---",
            "body": "# Alpha\n",
        })
        text = open(path, encoding="utf-8").read()
        self.assertTrue(text.startswith("---\ntitle: Old\n---\n# Alpha\n"))
        outside = os.path.join(self.tmp, "outside.md")
        denied = notes.handle({
            "cmd": "write", "path": outside, "roots": [self.root], "frontmatter": "", "body": "x"
        })
        self.assertFalse(denied["ok"])
        self.assertFalse(os.path.exists(outside))

    def test_trash_failure_does_not_unlink(self):
        path = os.path.join(self.root, "a.md")
        open(path, "w", encoding="utf-8").write("keep\n")
        result = notes.handle({
            "cmd": "trash", "path": path, "roots": [self.root], "gio": "gio-does-not-exist"
        })
        self.assertFalse(result["ok"])
        self.assertTrue(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
