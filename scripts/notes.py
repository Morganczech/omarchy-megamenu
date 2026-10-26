#!/usr/bin/env python3
import errno
import json
import os
import stat
import subprocess
import sys
import secrets

BODY_CAP = 1048576
TITLE_CAP = 65536
SCAN_CAP = 2000


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


def _open_write_parent(path):
    """Pin every directory, including root ancestry, without following symlinks."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    parent = os.path.dirname(os.path.abspath(path))
    fd = os.open(os.sep, flags)
    try:
        for part in parent.split(os.sep):
            if not part:
                continue
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


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

    def onerror(err):
        nonlocal truncated
        errors.append({"path": getattr(err, "filename", None) or "", "error": str(err)})
        truncated = True

    for root in _roots(request):
        if os.path.islink(root) or not os.path.isdir(root):
            errors.append({"path": root, "error": "unreadable"})
            if not os.path.islink(root):
                truncated = True
            continue
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False, onerror=onerror):
            dirnames[:] = [name for name in dirnames if not name.startswith(".") and not os.path.islink(os.path.join(dirpath, name))]
            for name in sorted(filenames):
                if name.startswith(".") or not name.endswith(".md"):
                    continue
                path = os.path.join(dirpath, name)
                if os.path.islink(path):
                    continue
                try:
                    st = os.lstat(path)
                    if not stat.S_ISREG(st.st_mode):
                        errors.append({"path": path, "error": "unreadable"})
                        continue
                    with open(path, "rb") as handle:
                        prefix = handle.read(TITLE_CAP).decode("utf-8", "replace")
                except OSError as exc:
                    errors.append({"path": path, "error": str(exc)})
                    truncated = True
                    continue
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
                    break
            if capped:
                break
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
    try:
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode):
            return denied
        if st.st_size > BODY_CAP:
            return {"ok": True, "frontmatter": "", "body": "", "mtime": int(st.st_mtime), "tooLarge": True}
        with open(path, encoding="utf-8") as handle:
            frontmatter, body = _split(handle.read())
    except OSError as exc:
        if exc.errno == errno.ENOENT:
            return {"ok": False, "error": "missing", "frontmatter": "", "body": "", "mtime": 0, "tooLarge": False}
        return denied
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
        parent_fd = _open_write_parent(path)
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
                    os.unlink(tmp, dir_fd=parent_fd)
            finally:
                os.close(parent_fd)
    return {"ok": True, "path": path, "mtime": mtime}


def _rename(request):
    path = request.get("path") or ""
    roots = _roots(request)
    filename = request.get("filename") or ""
    if not _allowed(path, roots):
        return {"ok": False, "error": "outside roots"}
    if not filename or filename.startswith(".") or "/" in filename or "\\" in filename:
        return {"ok": False, "error": "bad name"}
    dest = os.path.join(os.path.dirname(path), filename)
    if not _allowed(dest, roots):
        return {"ok": False, "error": "outside roots"}
    if os.path.lexists(dest):
        return {"ok": False, "error": "exists"}
    os.rename(path, dest)
    return {"ok": True, "path": dest}


def _trash(request):
    path = request.get("path") or ""
    roots = _roots(request)
    if not _allowed(path, roots) or not os.path.isfile(path):
        return {"ok": False, "error": "unreadable"}
    gio = request.get("gio") or "gio"
    try:
        result = subprocess.run([gio, "trash", "--", path], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "error": str(exc)}
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
