import errno
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest import mock
from urllib.parse import unquote


spec = importlib.util.spec_from_file_location(
    "notes", Path(__file__).resolve().parents[1] / "scripts" / "notes.py"
)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class NotesSecurityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "ancestor" / "notes"
        self.parent = self.root / "sub"
        self.parent.mkdir(parents=True)
        self.note = self.parent / "finance.md"
        self.note.write_text("# Original\n", encoding="utf-8")

    def request(self, cmd, **kwargs):
        return notes.handle({"cmd": cmd, "path": str(self.note),
                             "roots": [str(self.root)], **kwargs})

    def test_directory_swaps_cannot_redirect_read_write_or_rename(self):
        for command in ("read", "write", "rename"):
            for component in ("ancestor", "root", "parent"):
                for stage in ("before_open", "during_open", "after_open"):
                    with self.subTest(command=command, component=component, stage=stage):
                        with tempfile.TemporaryDirectory(dir=self.base) as folder:
                            base = Path(folder)
                            root = base / "ancestor" / "notes"
                            parent = root / "sub"
                            parent.mkdir(parents=True)
                            source = parent / "finance.md"
                            source.write_text("original")
                            target = {"ancestor": root.parent, "root": root, "parent": parent}[component]
                            relative_parent = parent.relative_to(target)
                            outside = base / "outside"
                            victim_parent = outside / relative_parent
                            victim_parent.mkdir(parents=True)
                            victim = victim_parent / "finance.md"
                            victim.write_text("outside secret")
                            moved = base / "moved"
                            real_open = os.open
                            real_parent = notes._open_parent

                            def swap():
                                target.rename(moved)
                                target.symlink_to(outside, target_is_directory=True)

                            def open_component(name, flags, *args, **kwargs):
                                fd = real_open(name, flags, *args, **kwargs)
                                if stage == "during_open" and name == target.name and flags & os.O_DIRECTORY:
                                    swap()
                                return fd

                            def open_parent(path, **kwargs):
                                if stage == "before_open":
                                    swap()
                                fd = real_parent(path, **kwargs)
                                if stage == "after_open":
                                    swap()
                                return fd

                            with mock.patch.object(notes, "_open_parent", side_effect=open_parent), \
                                    mock.patch.object(notes.os, "open", side_effect=open_component):
                                result = notes.handle({"cmd": command, "path": str(source),
                                                       "roots": [str(root)], "body": "saved",
                                                       "filename": "renamed.md"})
                            self.assertEqual(result["ok"], stage != "before_open", result)
                            self.assertEqual(victim.read_text(), "outside secret")
                            self.assertFalse((victim_parent / "renamed.md").exists())
                            if result["ok"]:
                                actual_parent = moved / relative_parent
                                if command == "read":
                                    self.assertEqual(result["body"], "original")
                                elif command == "write":
                                    self.assertEqual((actual_parent / "finance.md").read_text(), "saved")
                                else:
                                    self.assertFalse((actual_parent / "finance.md").exists())
                                    self.assertEqual((actual_parent / "renamed.md").read_text(), "original")
                            self.assertFalse(list(base.rglob(".meganote-*")))

    def test_rename_refuses_existing_and_concurrently_created_destination(self):
        dest = self.parent / "renamed.md"
        rename = notes._rename_noreplace

        def create_then_rename(fd, source, name):
            dest.write_text("keep destination")
            return rename(fd, source, name)

        with mock.patch.object(notes, "_rename_noreplace", side_effect=create_then_rename):
            result = self.request("rename", filename=dest.name)
        self.assertEqual(result, {"ok": False, "error": "exists"})
        self.assertEqual(dest.read_text(), "keep destination")
        self.assertEqual(self.note.read_text(), "# Original\n")
        self.assertEqual(self.request("rename", filename=dest.name)["error"], "exists")
        dest.unlink()
        dest.symlink_to(self.base / "missing")
        self.assertEqual(self.request("rename", filename=dest.name)["error"], "exists")
        self.assertTrue(dest.is_symlink())

    def test_rename_failure_keeps_source_and_returns_json_error(self):
        for error in (errno.EACCES, errno.ENOSYS, errno.EINVAL):
            with self.subTest(error=error), mock.patch.object(
                notes, "_rename_noreplace", side_effect=OSError(error, "injected failure")
            ):
                result = self.request("rename", filename="renamed.md")
            self.assertFalse(result["ok"])
            self.assertTrue(self.note.exists())
            self.assertFalse((self.parent / "renamed.md").exists())

    def test_rename_validates_filename_and_regular_source(self):
        for filename in ("", ".", "..", "../escape.md", "/tmp/escape.md", "a/b", "a\\b", "a\0b"):
            with self.subTest(filename=filename):
                self.assertFalse(self.request("rename", filename=filename)["ok"])
        self.note.unlink()
        self.note.mkdir()
        self.assertFalse(self.request("rename", filename="renamed.md")["ok"])
        self.note.rmdir()
        self.assertFalse(self.request("rename", filename="renamed.md")["ok"])

    def test_scan_pins_root_and_nested_directory(self):
        original_open = notes._open_note
        outside = self.base / "outside"
        outside.mkdir()
        (outside / self.note.name).write_text("# Outside secret\n")
        moved = self.base / "moved"

        def open_note(fd, name):
            self.parent.rename(moved)
            self.parent.symlink_to(outside, target_is_directory=True)
            return original_open(fd, name)

        with mock.patch.object(notes, "_open_note", side_effect=open_note):
            result = self.request("scan")
        self.assertEqual([item["title"] for item in result["files"]], ["Original"])

    def test_scan_does_not_follow_replaced_root(self):
        original_open = notes._open_directory
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "secret.md").write_text("# Outside secret\n")

        def open_root(path):
            fd = original_open(path)
            self.root.rename(self.base / "moved")
            self.root.symlink_to(outside, target_is_directory=True)
            return fd

        with mock.patch.object(notes, "_open_directory", side_effect=open_root):
            result = self.request("scan")
        self.assertEqual([item["title"] for item in result["files"]], ["Original"])

    def test_read_and_scan_refuse_leaf_swapped_for_symlink_or_fifo(self):
        original_open = notes._open_note
        outside = self.base / "secret.md"
        outside.write_text("# Outside secret\n")
        for command in ("read", "scan"):
            for kind in ("symlink", "fifo"):
                with self.subTest(command=command, kind=kind):
                    self.note.unlink()
                    self.note.write_text("# Original\n")

                    def swap_leaf(fd, name):
                        self.note.unlink()
                        if kind == "symlink":
                            self.note.symlink_to(outside)
                        else:
                            os.mkfifo(self.note)
                        return original_open(fd, name)

                    with mock.patch.object(notes, "_open_note", side_effect=swap_leaf):
                        result = self.request(command)
                    if command == "read":
                        self.assertFalse(result["ok"])
                        self.assertEqual(result["body"], "")
                    else:
                        self.assertEqual(result["files"], [])
                    self.assertEqual(outside.read_text(), "# Outside secret\n")

    def test_read_caps_file_growth_after_stat_and_handles_invalid_utf8(self):
        original_open = notes._open_note

        def grow_after_stat(fd, name):
            handle, st = original_open(fd, name)
            with self.note.open("ab") as writer:
                writer.write(b"x" * (notes.BODY_CAP + 1))
            return handle, st

        with mock.patch.object(notes, "_open_note", side_effect=grow_after_stat):
            result = self.request("read")
        self.assertTrue(result["tooLarge"])
        self.assertEqual(result["body"], "")
        self.note.write_bytes(b"\xff\xfe")
        self.assertFalse(self.request("read")["ok"])
        self.note.write_bytes(b"---\r\ntitle: Old\r\n---\r\n# Original\r\n")
        read = self.request("read")
        self.assertEqual(read["frontmatter"], "---\ntitle: Old\n---")
        self.assertEqual(read["body"], "# Original\n")

    def test_scan_refuses_directory_swap_before_descent(self):
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "secret.md").write_text("# Outside secret\n")
        real_open = os.open

        def swap_before_open(name, flags, *args, **kwargs):
            if name == "sub" and flags & os.O_DIRECTORY:
                self.parent.rename(self.base / "moved")
                self.parent.symlink_to(outside, target_is_directory=True)
            return real_open(name, flags, *args, **kwargs)

        with mock.patch.object(notes.os, "open", side_effect=swap_before_open):
            result = self.request("scan")
        self.assertEqual(result["files"], [])
        self.assertTrue(result["truncated"])

    def test_scan_reports_nested_errors_and_closes_capped_walk(self):
        if os.geteuid() == 0:
            self.skipTest("permissions are not enforced for root")
        locked = self.parent / "locked"
        locked.mkdir()
        locked.chmod(0)
        try:
            result = self.request("scan")
            self.assertIn(str(locked), [error["path"] for error in result["errors"]])
            self.assertTrue(result["truncated"])
        finally:
            locked.chmod(0o700)
        before = len(os.listdir("/proc/self/fd"))
        with mock.patch.object(notes, "SCAN_CAP", 1):
            result = self.request("scan")
        self.assertEqual(len(result["files"]), 1)
        self.assertTrue(result["truncated"])
        self.assertEqual(len(os.listdir("/proc/self/fd")), before)

    def test_write_handles_temporary_file_removed_concurrently(self):
        replace = os.replace

        def remove_then_replace(src, dest, **kwargs):
            os.unlink(src, dir_fd=kwargs["src_dir_fd"])
            return replace(src, dest, **kwargs)

        with mock.patch.object(notes.os, "replace", side_effect=remove_then_replace):
            result = self.request("write", body="new")
        self.assertFalse(result["ok"])
        self.assertEqual(self.note.read_text(), "# Original\n")
        self.assertFalse(list(self.parent.glob(".meganote-*")))

    def test_trash_refuses_shared_writable_ancestry_before_launching_gio(self):
        for folder in (self.root.parent, self.root, self.parent):
            for mode in (0o770, 0o777):
                with self.subTest(folder=folder, mode=mode):
                    previous = folder.stat().st_mode
                    folder.chmod(mode)
                    try:
                        with mock.patch.object(notes.subprocess, "run") as run:
                            result = self.request("trash")
                        self.assertEqual(result, {"ok": False, "error": "unsafe trash path"})
                        run.assert_not_called()
                        self.assertTrue(self.note.exists())
                    finally:
                        folder.chmod(stat.S_IMODE(previous))

    def test_trash_refuses_untrusted_owner_even_without_write_mode(self):
        fstat = os.fstat
        for target in (self.root.parent, self.root, self.parent):
            inode = target.stat().st_ino

            def untrusted_owner(fd):
                st = fstat(fd)
                if st.st_ino == inode:
                    values = list(st)
                    values[4] = os.geteuid() + 10000
                    return os.stat_result(values)
                return st

            with self.subTest(target=target), mock.patch.object(notes.os, "fstat", side_effect=untrusted_owner), \
                    mock.patch.object(notes.subprocess, "run") as run:
                self.assertEqual(self.request("trash")["error"], "unsafe trash path")
                run.assert_not_called()

    def test_trash_private_path_preserves_original_argument_and_errors(self):
        with mock.patch.object(notes.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(self.request("trash")["ok"])
            self.assertEqual(run.call_args.args[0], ["gio", "trash", "--", str(self.note)])
        for outcome in (subprocess.CompletedProcess([], 1, "", "trash unavailable"),
                        subprocess.TimeoutExpired("gio", 10)):
            kwargs = {"side_effect": outcome} if isinstance(outcome, Exception) else {"return_value": outcome}
            with mock.patch.object(notes.subprocess, "run", **kwargs):
                self.assertFalse(self.request("trash")["ok"])
            self.assertTrue(self.note.exists())

    def test_trash_sticky_parent_requires_trusted_leaf_owner(self):
        self.parent.chmod(0o1777)
        real_stat = os.stat

        def untrusted_note(path, *args, **kwargs):
            st = real_stat(path, *args, **kwargs)
            if path == self.note.name and kwargs.get("dir_fd") is not None:
                values = list(st)
                values[4] = os.geteuid() + 10000
                return os.stat_result(values)
            return st

        with mock.patch.object(notes.os, "stat", side_effect=untrusted_note), \
                mock.patch.object(notes.subprocess, "run") as run:
            self.assertEqual(self.request("trash")["error"], "unsafe trash path")
            run.assert_not_called()
        with mock.patch.object(notes.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertTrue(self.request("trash")["ok"])

    @unittest.skipUnless(shutil.which("gio"), "GIO is not installed")
    def test_real_gio_trash_preserves_restore_metadata_in_isolated_data_home(self):
        # Keep source on the home filesystem so GIO uses this isolated home
        # trash rather than a mount-wide .Trash directory. Never use real trash.
        repo = Path(__file__).resolve().parents[1]
        if repo.stat().st_dev != Path.home().stat().st_dev:
            self.skipTest("checkout is not on the home filesystem")
        with tempfile.TemporaryDirectory(prefix=".notes-trash-test-", dir=repo) as folder:
            base = Path(folder)
            source = base / "poznámka.md"
            source.write_text("keep in trash", encoding="utf-8")
            data_home = base / "data"
            data_home.mkdir(mode=0o700)
            with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(data_home)}):
                result = notes.handle({"cmd": "trash", "path": str(source), "roots": [str(base)]})
            self.assertTrue(result["ok"], result)
            self.assertFalse(source.exists())
            trash = data_home / "Trash"
            trashed = list((trash / "files").iterdir())
            self.assertEqual(len(trashed), 1)
            self.assertEqual(trashed[0].read_text(), "keep in trash")
            info = list((trash / "info").glob("*.trashinfo"))
            self.assertEqual(len(info), 1)
            metadata = info[0].read_text()
            original = next(line[5:] for line in metadata.splitlines() if line.startswith("Path="))
            self.assertEqual(unquote(original), str(source))

    def test_trash_refuses_symlink_swap_after_validation(self):
        original_parent = notes._open_parent
        outside = self.base / "outside"
        outside.mkdir()
        victim = outside / self.note.name
        victim.write_text("keep")

        def swap_then_open(path, **kwargs):
            self.parent.rename(self.base / "moved")
            self.parent.symlink_to(outside, target_is_directory=True)
            return original_parent(path, **kwargs)

        with mock.patch.object(notes, "_open_parent", side_effect=swap_then_open), \
                mock.patch.object(notes.subprocess, "run") as run:
            self.assertFalse(self.request("trash")["ok"])
            run.assert_not_called()
        self.assertEqual(victim.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
