import importlib.util
import os
import shutil
import signal
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
        with open(os.path.join(self.root, "a.md"), "w", encoding="utf-8") as handle:
            handle.write("# Alpha\n")
        os.mkdir(os.path.join(self.root, ".secret"))
        with open(os.path.join(self.root, ".secret", "no.md"), "w", encoding="utf-8") as handle:
            handle.write("# No\n")
        os.symlink(os.path.join(self.root, "a.md"), os.path.join(self.root, "link.md"))
        result = notes.handle({"cmd": "scan", "roots": [self.root]})
        paths = [item["path"] for item in result["files"]]
        self.assertEqual(paths, [os.path.join(self.root, "a.md")])
        self.assertEqual(result["files"][0]["title"], "Alpha")
        self.assertFalse(result["truncated"])

    def test_read_splits_frontmatter_and_refuses_oversize(self):
        path = os.path.join(self.root, "a.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("---\ntitle: Old\n---\n# Alpha\n\nbody\n")
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
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("old\n")
        notes.handle({
            "cmd": "write",
            "path": path,
            "roots": [self.root],
            "frontmatter": "---\ntitle: Old\n---",
            "body": "# Alpha\n",
        })
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        self.assertTrue(text.startswith("---\ntitle: Old\n---\n# Alpha\n"))
        outside = os.path.join(self.tmp, "outside.md")
        denied = notes.handle({
            "cmd": "write", "path": outside, "roots": [self.root], "frontmatter": "", "body": "x"
        })
        self.assertFalse(denied["ok"])
        self.assertFalse(os.path.exists(outside))

    def test_trash_failure_does_not_unlink(self):
        path = os.path.join(self.root, "a.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("keep\n")
        result = notes.handle({
            "cmd": "trash", "path": path, "roots": [self.root], "gio": "gio-does-not-exist"
        })
        self.assertFalse(result["ok"])
        self.assertTrue(os.path.exists(path))

    def test_directory_symlink_cannot_leave_root(self):
        outside = os.path.join(self.tmp, "outside")
        os.mkdir(outside)
        outside_file = os.path.join(outside, "secret.md")
        with open(outside_file, "w", encoding="utf-8") as handle:
            handle.write("secret\n")
        link = os.path.join(self.root, "link")
        os.symlink(outside, link)
        via = os.path.join(link, "secret.md")
        created = os.path.join(link, "new.md")
        gio = os.path.join(self.tmp, "gio-trash")
        with open(gio, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/sh\nrm -f -- \"$3\"\n")
        os.chmod(gio, 0o755)

        result = notes.handle({"cmd": "scan", "roots": [self.root]})
        paths = [item["path"] for item in result["files"]]
        self.assertNotIn(outside_file, paths)
        self.assertFalse(any(path == link or path.startswith(link + os.sep) for path in paths))

        read = notes.handle({"cmd": "read", "path": via, "roots": [self.root]})
        self.assertFalse(read["ok"])
        write = notes.handle({
            "cmd": "write", "path": via, "roots": [self.root], "frontmatter": "", "body": "pwned\n"
        })
        self.assertFalse(write["ok"])
        write_new = notes.handle({
            "cmd": "write", "path": created, "roots": [self.root], "frontmatter": "", "body": "pwned\n"
        })
        self.assertFalse(write_new["ok"])
        rename = notes.handle({
            "cmd": "rename", "path": via, "filename": "renamed.md", "roots": [self.root]
        })
        self.assertFalse(rename["ok"])
        trash = notes.handle({"cmd": "trash", "path": via, "roots": [self.root], "gio": gio})
        self.assertFalse(trash["ok"])

        with open(outside_file, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "secret\n")
        self.assertFalse(os.path.exists(os.path.join(outside, "new.md")))
        self.assertFalse(os.path.exists(os.path.join(outside, "renamed.md")))
        self.assertFalse(any(name.startswith(".meganote-") for name in os.listdir(outside)))

    def test_dotdot_after_directory_symlink_is_refused(self):
        outside = os.path.join(self.tmp, "outside")
        os.mkdir(outside)
        link = os.path.join(self.root, "link")
        os.symlink(outside, link)
        escaped = os.path.join(link, "..", "created.md")
        lexical = os.path.abspath(escaped)
        self.assertTrue(lexical == self.root or lexical.startswith(self.root + os.sep))
        result = notes.handle({
            "cmd": "write", "path": escaped, "roots": [self.root], "frontmatter": "", "body": "pwned\n"
        })
        self.assertFalse(result["ok"])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "created.md")))
        self.assertFalse(os.path.exists(lexical))
        self.assertFalse(any(name.startswith(".meganote-") for name in os.listdir(self.tmp)))

    def test_unreadable_root_keeps_other_root(self):
        if os.geteuid() == 0:
            self.skipTest("permissions are not enforced for root")
        other = os.path.join(self.tmp, "other")
        os.mkdir(other)
        other_file = os.path.join(other, "b.md")
        with open(other_file, "w", encoding="utf-8") as handle:
            handle.write("# Beta\n")
        locked = os.path.join(self.tmp, "locked")
        os.mkdir(locked)
        os.chmod(locked, 0)
        try:
            result = notes.handle({"cmd": "scan", "roots": [locked, other]})
            self.assertTrue(result["ok"])
            self.assertIn(os.path.abspath(locked), [item["path"] for item in result["errors"]])
            self.assertIn(other_file, [item["path"] for item in result["files"]])
            self.assertTrue(result["truncated"])
        finally:
            os.chmod(locked, 0o700)

    def test_unreadable_markdown_stays_in_errors(self):
        if os.geteuid() == 0:
            self.skipTest("permissions are not enforced for root")
        good = os.path.join(self.root, "good.md")
        bad = os.path.join(self.root, "bad.md")
        with open(good, "w", encoding="utf-8") as handle:
            handle.write("# Good\n")
        with open(bad, "w", encoding="utf-8") as handle:
            handle.write("# Bad\n")
        os.chmod(bad, 0)
        try:
            result = notes.handle({"cmd": "scan", "roots": [self.root]})
            self.assertTrue(result["ok"])
            paths = [item["path"] for item in result["files"]]
            self.assertIn(good, paths)
            self.assertNotIn(bad, paths)
            self.assertIn(bad, [item["path"] for item in result["errors"]])
            self.assertTrue(result["truncated"])
            read = notes.handle({"cmd": "read", "path": bad, "roots": [self.root]})
            self.assertIsInstance(read, dict)
            self.assertFalse(read["ok"])
        finally:
            os.chmod(bad, 0o600)

    def test_unreadable_subdirectory_sets_truncated(self):
        if os.geteuid() == 0:
            self.skipTest("permissions are not enforced for root")
        kept = os.path.join(self.root, "kept.md")
        with open(kept, "w", encoding="utf-8") as handle:
            handle.write("# Kept\n")
        locked = os.path.join(self.root, "locked")
        os.mkdir(locked)
        with open(os.path.join(locked, "hidden.md"), "w", encoding="utf-8") as handle:
            handle.write("# Hidden\n")
        os.chmod(locked, 0)
        try:
            result = notes.handle({"cmd": "scan", "roots": [self.root]})
            self.assertTrue(result["ok"])
            paths = [item["path"] for item in result["files"]]
            self.assertIn(kept, paths)
            self.assertNotIn(os.path.join(locked, "hidden.md"), paths)
            self.assertIn(locked, [item["path"] for item in result["errors"]])
            self.assertTrue(result["truncated"])
        finally:
            os.chmod(locked, 0o700)

    def test_fifo_does_not_hang_scan(self):
        if not hasattr(os, "mkfifo"):
            self.skipTest("os.mkfifo is unavailable")
        fifo = os.path.join(self.root, "x.md")
        os.mkfifo(fifo)
        kept = os.path.join(self.root, "ok.md")
        with open(kept, "w", encoding="utf-8") as handle:
            handle.write("# Ok\n")

        def _timeout(signum, frame):
            raise AssertionError("scan hung")

        previous = signal.signal(signal.SIGALRM, _timeout)
        signal.alarm(2)
        try:
            result = notes.handle({"cmd": "scan", "roots": [self.root]})
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)
        paths = [item["path"] for item in result["files"]]
        self.assertNotIn(fifo, paths)
        self.assertIn(kept, paths)
        self.assertIn(fifo, [item["path"] for item in result["errors"]])
        self.assertFalse(result["truncated"])


if __name__ == "__main__":
    unittest.main()
