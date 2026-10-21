#!/usr/bin/env python3
"""Native messaging host: list Megamenu spaces and save the current page.

Chrome and Firefox talk to this script over stdio. It is the only process
allowed to translate an extension message into ~/.local/share/omarchy-megamenu/data.json.

Ids for the reading-list space match Storage.js.
"""

import fcntl
import html
import json
import os
import random
import re
import struct
import sys
import tempfile
import time

READING_SPACE_ID = "reading-list"
READING_CATEGORY_ID = "cat-reading"
READING_SPACE_NAME = "Seznam čtení"
READING_CATEGORY_NAME = "K přečtení"
READING_NAMES = ("seznam čtení", "reading list")
BOOK_ICON = "\U000f00ba"
DOC_ICON = "\U000f0219"
FOLDER_ICON = "\U000f024b"

_TAG_RE = re.compile(r"<[^>]*>")
_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*://")
_DOMAIN_RE = re.compile(r"^(?:https?://)?(?:www\.)?([^/:?#]+)", re.I)
_MAX_MESSAGE = 1024 * 1024


class HostError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def data_path():
    override = os.environ.get("MEGAMENU_DATA_FILE", "").strip()
    if override:
        return os.path.abspath(override)
    return os.path.expanduser("~/.local/share/omarchy-megamenu/data.json")


def plain_text(value, limit=300):
    text = html.unescape(str(value or ""))
    text = _TAG_RE.sub(" ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if limit and len(text) > limit:
        text = text[:limit].rstrip()
    return text


def normalize_url(url):
    text = str(url or "").strip()
    if not text:
        return ""
    if not _SCHEME_RE.match(text):
        text = "https://" + text
    return text


def extract_domain(url):
    match = _DOMAIN_RE.match(str(url or "").strip())
    return match.group(1).lower() if match else ""


def uid(prefix):
    return f"{prefix}-{int(time.time() * 1000):x}-{random.randrange(100000):x}"


def is_reading_space(space):
    if not isinstance(space, dict):
        return False
    if space.get("id") == READING_SPACE_ID:
        return True
    return plain_text(space.get("name"), limit=0).lower() in READING_NAMES


def ensure_reading_list(data):
    spaces = data.get("spaces")
    if any(is_reading_space(space) for space in spaces):
        return False
    spaces.append({
        "id": READING_SPACE_ID,
        "name": READING_SPACE_NAME,
        "icon": BOOK_ICON,
    })
    categories = data.get("categories")
    if not isinstance(categories, list):
        categories = []
        data["categories"] = categories
    categories.append({
        "id": READING_CATEGORY_ID,
        "spaceId": READING_SPACE_ID,
        "name": READING_CATEGORY_NAME,
        "icon": DOC_ICON,
        "colorRole": "yellow",
        "type": "static",
        "feedUrl": "",
        "feedMode": "all",
    })
    return True


def public_spaces(data):
    categories = data.get("categories") if isinstance(data.get("categories"), list) else []
    listed = []
    for space in data.get("spaces") or []:
        if not isinstance(space, dict) or not space.get("id") or not space.get("name"):
            continue
        space_categories = []
        for category in categories:
            if not isinstance(category, dict):
                continue
            if category.get("spaceId") != space.get("id") or not category.get("id") or not category.get("name"):
                continue
            space_categories.append({
                "id": str(category["id"]),
                "name": plain_text(category.get("name")) or str(category["id"]),
            })
        listed.append({
            "id": str(space["id"]),
            "name": plain_text(space.get("name")) or str(space["id"]),
            "reading": is_reading_space(space),
            "categories": space_categories,
        })
    listed.sort(key=lambda item: (0 if item["reading"] else 1, item["name"].lower()))
    return listed


def find_space(data, space_id):
    for space in data.get("spaces") or []:
        if isinstance(space, dict) and str(space.get("id") or "") == space_id:
            return space
    return None


def pick_category(data, space, category_id):
    categories = data.get("categories")
    if not isinstance(categories, list):
        categories = []
        data["categories"] = categories
    owned = [
        category for category in categories
        if isinstance(category, dict) and category.get("spaceId") == space.get("id")
    ]
    if category_id:
        for category in owned:
            if str(category.get("id") or "") == category_id:
                return category, False
        raise HostError("bad-category", "That category is not in the selected space.")
    for category in owned:
        if str(category.get("type") or "static").lower() == "static":
            return category, False
    if owned:
        return owned[0], False
    created = {
        "id": uid("cat"),
        "spaceId": space["id"],
        "name": "General",
        "icon": FOLDER_ICON,
        "colorRole": "blue",
        "type": "static",
        "feedUrl": "",
        "feedMode": "all",
    }
    categories.append(created)
    return created, True


def write_atomic(path, data):
    directory = os.path.dirname(path) or "."
    payload = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    fd, tmp = tempfile.mkstemp(prefix=".data-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def with_data(mutate):
    path = data_path()
    if not os.path.isfile(path):
        raise HostError(
            "no-data",
            "Open Megamenu once so it can create its data file, then try again.",
        )
    lock_path = path + ".lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read()
        try:
            data = json.loads(raw) if raw.strip() else None
        except json.JSONDecodeError as exc:
            raise HostError("bad-data", "Megamenu data file is not valid JSON.") from exc
        if not isinstance(data, dict) or not isinstance(data.get("spaces"), list) or not data["spaces"]:
            raise HostError("bad-data", "Megamenu data file has no spaces.")
        result, changed = mutate(data)
        if changed:
            write_atomic(path, data)
        return result
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)


def list_spaces():
    def mutate(data):
        changed = ensure_reading_list(data)
        return {"ok": True, "spaces": public_spaces(data)}, changed
    return with_data(mutate)


def save_page(message):
    url = normalize_url(message.get("url"))
    scheme = url.split(":", 1)[0].lower() if "://" in url else ""
    if scheme not in ("http", "https"):
        raise HostError("bad-url", "Only http and https pages can be saved.")
    title = plain_text(message.get("title")) or extract_domain(url) or url
    space_id = str(message.get("spaceId") or "").strip()
    category_id = str(message.get("categoryId") or "").strip()
    if not space_id:
        raise HostError("bad-space", "Choose a space.")

    def mutate(data):
        changed = ensure_reading_list(data)
        space = find_space(data, space_id)
        if space is None:
            raise HostError("bad-space", "That space no longer exists.")
        category, created = pick_category(data, space, category_id)
        changed = changed or created
        needle = url.lower()
        items = data.get("items")
        if not isinstance(items, list):
            items = []
            data["items"] = items
        for item in items:
            if not isinstance(item, dict):
                continue
            if item.get("spaceId") != space.get("id"):
                continue
            if str(item.get("url") or "").strip().lower() == needle:
                return {
                    "ok": True,
                    "status": "duplicate",
                    "title": plain_text(item.get("title")) or title,
                    "spaceName": plain_text(space.get("name")),
                    "categoryName": plain_text(category.get("name")),
                }, changed
        items.append({
            "id": uid("item"),
            "spaceId": space["id"],
            "categoryId": category["id"],
            "type": "url",
            "title": title,
            "subtitle": extract_domain(url),
            "url": url,
            "desktopId": "",
            "iconType": "favicon",
            "iconValue": "",
            "favorite": False,
            "pinnedSlot": 0,
            "badgeText": "",
            "colorRole": "",
        })
        return {
            "ok": True,
            "status": "saved",
            "title": title,
            "spaceName": plain_text(space.get("name")),
            "categoryName": plain_text(category.get("name")),
        }, True

    return with_data(mutate)


def handle(message):
    if not isinstance(message, dict):
        raise HostError("bad-request", "Expected a JSON object.")
    action = message.get("action")
    if action == "list":
        return list_spaces()
    if action == "save":
        return save_page(message)
    raise HostError("bad-request", "Unknown action.")


def error_payload(exc):
    if isinstance(exc, HostError):
        return {"ok": False, "error": exc.code, "message": exc.message}
    return {"ok": False, "error": "internal", "message": "Could not update Megamenu."}


def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len:
        return None
    if len(raw_len) < 4:
        raise HostError("bad-request", "Truncated message header.")
    length = struct.unpack("<I", raw_len)[0]
    if length > _MAX_MESSAGE:
        raise HostError("bad-request", "Message is too large.")
    payload = sys.stdin.buffer.read(length)
    if len(payload) < length:
        raise HostError("bad-request", "Truncated message.")
    return json.loads(payload.decode("utf-8"))


def send_message(obj):
    data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def serve():
    while True:
        try:
            message = read_message()
        except Exception as exc:
            send_message(error_payload(exc))
            return
        if message is None:
            return
        try:
            send_message(handle(message))
        except Exception as exc:
            send_message(error_payload(exc))


def _frame(obj):
    data = json.dumps(obj).encode("utf-8")
    return struct.pack("<I", len(data)) + data


def _read_frame(buffer):
    if len(buffer) < 4:
        raise AssertionError("short frame")
    length = struct.unpack("<I", buffer[:4])[0]
    payload = buffer[4:4 + length]
    if len(payload) != length:
        raise AssertionError("short payload")
    return json.loads(payload.decode("utf-8")), buffer[4 + length:]


def call(message):
    try:
        return handle(message)
    except HostError as exc:
        return error_payload(exc)


def run_self_test():
    import subprocess

    tmp = tempfile.mkdtemp(prefix="megamenu-host-")
    path = os.path.join(tmp, "data.json")
    env = os.environ.copy()
    env["MEGAMENU_DATA_FILE"] = path
    os.environ["MEGAMENU_DATA_FILE"] = path

    missing = call({"action": "list"})
    assert missing["ok"] is False and missing["error"] == "no-data", missing
    assert not os.path.exists(path)

    seed = {
        "version": 1,
        "language": "cs",
        "activeSpaceId": "personal",
        "customFlag": True,
        "spaces": [{"id": "personal", "name": "Personal Space", "icon": "x"}],
        "categories": [{
            "id": "cat-media",
            "spaceId": "personal",
            "name": "Media",
            "icon": "x",
            "colorRole": "red",
            "type": "static",
            "feedUrl": "",
            "feedMode": "all",
        }],
        "items": [],
    }
    with open(path, "w", encoding="utf-8") as handle_file:
        json.dump(seed, handle_file)

    listed = call({"action": "list"})
    assert listed["ok"] is True, listed
    assert listed["spaces"][0]["id"] == READING_SPACE_ID, listed
    stored = json.load(open(path, encoding="utf-8"))
    assert stored["customFlag"] is True
    assert stored["activeSpaceId"] == "personal"
    assert any(space["id"] == READING_SPACE_ID for space in stored["spaces"])

    saved = call({
        "action": "save",
        "url": "https://Example.com/article",
        "title": "<b>Hello</b>  world",
        "spaceId": READING_SPACE_ID,
        "categoryId": READING_CATEGORY_ID,
    })
    assert saved["status"] == "saved", saved
    assert saved["title"] == "Hello world"
    again = call({
        "action": "save",
        "url": "https://example.com/article",
        "title": "Hello world",
        "spaceId": READING_SPACE_ID,
    })
    assert again["status"] == "duplicate", again

    bad = call({"action": "save", "url": "chrome://newtab", "title": "New", "spaceId": "personal"})
    assert bad["ok"] is False and bad["error"] == "bad-url", bad

    wrong_cat = call({
        "action": "save",
        "url": "https://example.com/other",
        "title": "Other",
        "spaceId": "personal",
        "categoryId": READING_CATEGORY_ID,
    })
    assert wrong_cat["error"] == "bad-category", wrong_cat

    other = call({
        "action": "save",
        "url": "example.org/notes",
        "title": "Notes",
        "spaceId": "personal",
    })
    assert other["status"] == "saved", other
    assert other["categoryName"] == "Media"

    renamed_path = os.path.join(tmp, "renamed.json")
    os.environ["MEGAMENU_DATA_FILE"] = renamed_path
    renamed = {
        "version": 1,
        "spaces": [{"id": "mine", "name": "Reading List", "icon": "x"}],
        "categories": [],
        "items": [],
    }
    with open(renamed_path, "w", encoding="utf-8") as handle_file:
        json.dump(renamed, handle_file)
    renamed_list = call({"action": "list"})
    assert len(renamed_list["spaces"]) == 1, renamed_list
    assert renamed_list["spaces"][0]["reading"] is True
    created_general = call({
        "action": "save",
        "url": "https://example.com/later",
        "title": "Later",
        "spaceId": "mine",
    })
    assert created_general["status"] == "saved", created_general
    assert created_general["categoryName"] == "General"

    os.environ["MEGAMENU_DATA_FILE"] = path
    proc = subprocess.run(
        [sys.executable, os.path.abspath(__file__)],
        input=_frame({"action": "list"}) + _frame({
            "action": "save",
            "url": "https://example.com/from-stdio",
            "title": "Stdio",
            "spaceId": "personal",
        }),
        capture_output=True,
        env=env,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    first, rest = _read_frame(proc.stdout)
    second, rest = _read_frame(rest)
    assert rest == b"", rest
    assert first["ok"] is True and first["spaces"], first
    assert second["status"] == "saved", second
    print("native-host self-test ok")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        run_self_test()
        return 0
    serve()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
