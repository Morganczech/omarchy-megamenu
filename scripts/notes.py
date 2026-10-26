#!/usr/bin/env python3
import ctypes
import errno
import json
import os
import secrets
import stat
import subprocess
import sys

BODY_CAP = 1048576
TITLE_CAP = 65536
SCAN_CAP = 2000
RENAME_NOREPLACE = 1


def _roots(request):
    return [os.path.abspath(r) for r in request.get("roots") or [] if r]


def _normalize_root(root):
    root_abs = os.path.abspath(root)
    if root_abs == os.sep:
        return os.sep
    return root_abs.rstrip(os.sep)


def _contains(root, path):
    if root == os.sep:
        return path == os.sep or path.startswith(os.sep)
    return path == root or path.startswith(root + os.sep)


def _symlink_between(root, path):
    if path == root:
        return os.path.islink(path)
    relative = path[1:] if root == os.sep else path[len(root) + 1 :]
    current = root
    for part in relative.split(os.sep):
        if part in ("", "."):
            continue
        if part == "..":
            return True
        current = os.path.join(current, part)
        if os.path.islink(current):
            return True
    return False


def _allowed(path, roots):
    """Early path validation only; callers must still pin or protect ancestry."""
    if not path or "\0" in path or ".." in path.split(os.sep):
        return False
    abs_path = os.path.abspath(path)
    try:
        real_path = os.path.realpath(abs_path)
    except OSError:
        return False
    for root in roots:
        root_abs = _normalize_root(root)
        if not _contains(root_abs, abs_path):
            continue
        if _symlink_between(root_abs, abs_path):
            continue
        if _contains(_normalize_root(os.path.realpath(root_abs)), real_path):
            return True
    return False


class UnsafeTrashPath(OSError):
    pass


def _check_trusted_directory(fd):
    st = os.fstat(fd)
    # POSIX ACL write grants are also bounded by the group mode's ACL mask.
    # Sticky directories (e.g. /tmp) are safe only because every child we
    # traverse, including the final note, must also have a trusted owner.
    if st.st_uid not in (0, os.geteuid()) or (
        st.st_mode & 0o022 and not st.st_mode & stat.S_ISVTX
    ):
        raise UnsafeTrashPath("unsafe trash path")


def _open_directory(path, *, trusted=False):
    """Pin directories from / down, refusing symlinks in all ancestry."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(os.sep, flags)
    try:
        if trusted:
            _check_trusted_directory(fd)
        for part in os.path.abspath(path).split(os.sep):
            if not part:
                continue
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
            if trusted:
                _check_trusted_directory(fd)
        return fd
    except BaseException:
        os.close(fd)
        raise


def _open_parent(path, *, trusted=False):
    return _open_directory(os.path.dirname(os.path.abspath(path)), trusted=trusted)


def _open_note(parent_fd, name):
    # NONBLOCK prevents a regular file swapped for a FIFO from hanging us.
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                 dir_fd=parent_fd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise OSError(errno.EINVAL, "not a regular note", name)
        return os.fdopen(fd, "rb"), st
    except BaseException:
        os.close(fd)
        raise


def _rename_noreplace(parent_fd, source, dest):
    # Linux/Omarchy: a pre-check followed by os.rename would still overwrite
    # a destination created concurrently. Fail closed if unavailable.
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameat2 = libc.renameat2
    except AttributeError:
        raise OSError(errno.ENOSYS, "atomic no-replace rename is unavailable") from None
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                         ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    if renameat2(parent_fd, os.fsencode(source), parent_fd, os.fsencode(dest), RENAME_NOREPLACE) != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), dest)


def _title(prefix, stem):
    text = prefix.lstrip("\ufeff")
    lines = text.splitlines()
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break
    for line in lines[start:]:
        stripped = line.lstrip("#")
        marks = len(line) - len(stripped)
        if 1 <= marks <= 6 and stripped.startswith(" ") and stripped.strip():
            return stripped.strip()
        if line.strip():
            break
    return stem or "note"


def _split(text):
    if not text.startswith("---\n"):
        return "", text
    end = text.find("\n---\n", 4)
    if end == -1:
        return "", text
    return text[: end + 4], text[end + 5 :]


def _scan(request):
    files = []
    errors = []
    truncated = False
    capped = False

    def error(path, exc):
        nonlocal truncated
        errors.append({"path": path, "error": str(exc)})
        truncated = True

    def visit(dir_fd, dirpath, depth=0):
        nonlocal truncated, capped
        try:
            names = sorted(os.listdir(dir_fd))
        except OSError as exc:
            error(dirpath, exc)
            return
        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(dirpath, name)
            try:
                st = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
                if stat.S_ISDIR(st.st_mode):
                    if depth >= 128:
                        error(path, "directory depth limit reached")
                        continue
                    child_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY |
                                       os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dir_fd)
                    try:
                        visit(child_fd, path, depth + 1)
                    finally:
                        os.close(child_fd)
                elif name.endswith(".md") and not stat.S_ISLNK(st.st_mode):
                    if not stat.S_ISREG(st.st_mode):
                        errors.append({"path": path, "error": "unreadable"})
                        continue
                    handle, st = _open_note(dir_fd, name)
                    with handle:
                        prefix = handle.read(TITLE_CAP).decode("utf-8", "replace")
                    files.append({
                        "path": path,
                        "title": _title(prefix, name[:-3]),
                        "mtime": int(st.st_mtime),
                        "size": st.st_size,
                        "tooLarge": st.st_size > BODY_CAP,
                    })
                    if len(files) >= SCAN_CAP:
                        truncated = True
                        capped = True
            except OSError as exc:
                error(path, exc)
            if capped:
                return

    for root in _roots(request):
        root_fd = None
        try:
            root_fd = _open_directory(root)
            visit(root_fd, root)
        except OSError as exc:
            error(root, exc)
        finally:
            if root_fd is not None:
                os.close(root_fd)
        if capped:
            break
    files.sort(key=lambda item: item["path"])
    return {"ok": True, "files": files, "truncated": truncated, "errors": errors}


def _read(request):
    path = request.get("path") or ""
    roots = _roots(request)
    denied = {"ok": False, "error": "unreadable", "frontmatter": "", "body": "", "mtime": 0, "tooLarge": False}
    if not _allowed(path, roots):
        return denied
    parent_fd = None
    try:
        parent_fd = _open_parent(path)
        handle, st = _open_note(parent_fd, os.path.basename(path))
        with handle:
            if st.st_size > BODY_CAP:
                return {"ok": True, "frontmatter": "", "body": "", "mtime": int(st.st_mtime), "tooLarge": True}
            data = handle.read(BODY_CAP + 1)
        if len(data) > BODY_CAP:
            return {"ok": True, "frontmatter": "", "body": "", "mtime": int(st.st_mtime), "tooLarge": True}
        text = data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
        frontmatter, body = _split(text)
    except OSError as exc:
        if exc.errno == errno.ENOENT:
            return {"ok": False, "error": "missing", "frontmatter": "", "body": "", "mtime": 0, "tooLarge": False}
        return denied
    except UnicodeError:
        return denied
    finally:
        if parent_fd is not None:
            os.close(parent_fd)
    return {"ok": True, "frontmatter": frontmatter, "body": body, "mtime": int(st.st_mtime), "tooLarge": False}


def _write(request):
    path = request.get("path") or ""
    roots = _roots(request)
    if not _allowed(path, roots):
        return {"ok": False, "error": "outside roots"}
    frontmatter = request.get("frontmatter") or ""
    body = request.get("body") or ""
    text = body
    if frontmatter:
        text = frontmatter + ("" if frontmatter.endswith("\n") else "\n") + body
    parent_fd = None
    tmp = None
    try:
        parent_fd = _open_parent(path)
        # All subsequent operations use this descriptor, never the mutable path.
        for attempt in range(100):
            candidate = ".meganote-" + secrets.token_hex(16)
            try:
                fd = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                             os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=parent_fd)
                tmp = candidate
                break
            except FileExistsError:
                continue
        else:
            raise OSError("could not create temporary note")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
            mtime = int(os.fstat(handle.fileno()).st_mtime)
        os.replace(tmp, os.path.basename(path), src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        tmp = None
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        if parent_fd is not None:
            try:
                if tmp is not None:
                    try:
                        os.unlink(tmp, dir_fd=parent_fd)
                    except FileNotFoundError:
                        pass
            finally:
                os.close(parent_fd)
    return {"ok": True, "path": path, "mtime": mtime}


def _rename(request):
    path = request.get("path") or ""
    roots = _roots(request)
    filename = request.get("filename") or ""
    if not _allowed(path, roots):
        return {"ok": False, "error": "outside roots"}
    if not filename or filename.startswith(".") or "/" in filename or "\\" in filename or "\0" in filename:
        return {"ok": False, "error": "bad name"}
    dest = os.path.join(os.path.dirname(path), filename)
    parent_fd = None
    try:
        parent_fd = _open_parent(path)
        source = os.path.basename(path)
        st = os.stat(source, dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISREG(st.st_mode):
            return {"ok": False, "error": "unreadable"}
        _rename_noreplace(parent_fd, source, filename)
    except FileExistsError:
        return {"ok": False, "error": "exists"}
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        if parent_fd is not None:
            os.close(parent_fd)
    return {"ok": True, "path": dest}


def _trash(request):
    path = request.get("path") or ""
    roots = _roots(request)
    if not _allowed(path, roots):
        return {"ok": False, "error": "unreadable"}
    gio = request.get("gio") or "gio"
    parent_fd = None
    try:
        # GIO takes a pathname, not a directory descriptor. Only delegate when
        # another UID cannot replace any path component. Keep the original
        # path so the trash's restore metadata points to the actual note.
        parent_fd = _open_parent(path, trusted=True)
        st = os.stat(os.path.basename(path), dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISREG(st.st_mode):
            return {"ok": False, "error": "unreadable"}
        if st.st_uid not in (0, os.geteuid()):
            raise UnsafeTrashPath("unsafe trash path")
        result = subprocess.run([gio, "trash", "--", os.path.abspath(path)], capture_output=True, text=True, timeout=10)
    except UnsafeTrashPath:
        return {"ok": False, "error": "unsafe trash path"}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        if parent_fd is not None:
            os.close(parent_fd)
    if result.returncode != 0:
        return {"ok": False, "error": (result.stderr or result.stdout or "trash failed").strip()}
    return {"ok": True}


def handle(request):
    cmd = (request or {}).get("cmd")
    if cmd == "scan":
        return _scan(request)
    if cmd == "read":
        return _read(request)
    if cmd == "write":
        return _write(request)
    if cmd == "rename":
        return _rename(request)
    if cmd == "trash":
        return _trash(request)
    return {"ok": False, "error": "unknown command"}


def main():
    request = json.load(sys.stdin)
    json.dump(handle(request), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
