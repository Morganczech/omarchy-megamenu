#!/usr/bin/env python3
"""Add or update a Megamenu command item.

The script file itself is created separately. This only writes the menu entry
in ~/.local/share/omarchy-megamenu/data.json. Close Megamenu first. It reads
that file the next time it opens.

Example:
  add-command.py --title "Restic Backup" --command restic-backup \\
    --space "Home Lab" --category General --run terminal --slot 3
"""

import argparse
import fcntl
import json
import os
import random
import re
import sys
import tempfile
import time
from pathlib import Path

DATA_PATH = Path.home() / ".local/share/omarchy-megamenu/data.json"
TAG_RE = re.compile(r"<[^>]*>")


def plain_label(value):
    text = str(value or "")
    text = TAG_RE.sub(" ", text)
    return re.sub(r"\s+", " ", text).strip()


def base36(value):
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    if value <= 0:
        return "0"
    out = []
    while value:
        value, rem = divmod(value, 36)
        out.append(alphabet[rem])
    return "".join(reversed(out))


def new_id():
    return "item-%s-%s" % (base36(int(time.time() * 1000)), base36(random.randrange(100000)))


def load_data(path):
    if not path.is_file():
        raise SystemExit("Megamenu data was not found at %s. Open Megamenu once, then try again." % path)
    with path.open("r", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_SH)
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise SystemExit("Megamenu data is not valid JSON: %s" % exc)
    if not isinstance(data, dict) or not isinstance(data.get("spaces"), list) or not isinstance(data.get("items"), list):
        raise SystemExit("Megamenu data is missing spaces or items.")
    data.setdefault("categories", [])
    return data


def find_named(rows, query, kind):
    needle = plain_label(query)
    if not needle:
        return None
    exact_id = [row for row in rows if str(row.get("id") or "") == needle]
    if len(exact_id) == 1:
        return exact_id[0]
    folded = needle.casefold()
    named = [row for row in rows if plain_label(row.get("name")).casefold() == folded]
    if len(named) == 1:
        return named[0]
    if len(named) > 1:
        raise SystemExit("More than one %s is named %r. Pass its id instead." % (kind, needle))
    raise SystemExit("No %s named %r." % (kind, needle))


def resolve_space(data, query):
    spaces = [row for row in data["spaces"] if isinstance(row, dict) and row.get("id")]
    if not query:
        active = str(data.get("activeSpaceId") or "")
        for row in spaces:
            if row["id"] == active:
                return row
        if spaces:
            return spaces[0]
        raise SystemExit("Megamenu has no spaces yet.")
    return find_named(spaces, query, "space")


def resolve_category(data, space_id, query):
    cats = [
        row for row in data["categories"]
        if isinstance(row, dict) and row.get("id") and row.get("spaceId") == space_id
    ]
    if not query:
        if not cats:
            raise SystemExit("That space has no category. Create one in Megamenu first.")
        return cats[0]
    return find_named(cats, query, "category")


def same_command(item, space_id, command):
    return (
        isinstance(item, dict)
        and item.get("type") == "command"
        and item.get("spaceId") == space_id
        and str(item.get("command") or "").strip() == command
    )


def write_data(path, data):
    mode = 0o600
    try:
        mode = path.stat().st_mode & 0o777
    except OSError:
        pass
    payload = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=".data-", suffix=".tmp")
    try:
        os.write(fd, payload)
        os.fchmod(fd, mode)
        os.close(fd)
        fd = None
        os.replace(tmp_name, path)
    finally:
        if fd is not None:
            os.close(fd)
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def build_item(args, space, category, previous):
    command = str(args.command or "").strip()
    title = plain_label(args.title)
    if not title or not command:
        raise SystemExit("Both --title and --command are required.")
    slot = args.slot
    if slot < 0 or slot > 6:
        raise SystemExit("--slot must be from 0 to 6.")
    run_mode = "background" if args.run == "background" else "terminal"
    icon = str(args.icon or "").strip() or str((previous or {}).get("iconValue") or "").strip() or "󰆍"
    subtitle = plain_label(args.subtitle) if args.subtitle is not None else str((previous or {}).get("subtitle") or "")
    if not subtitle:
        subtitle = command
    return {
        "id": str((previous or {}).get("id") or new_id()),
        "spaceId": space["id"],
        "categoryId": category["id"],
        "type": "command",
        "title": title,
        "subtitle": subtitle,
        "url": "",
        "desktopId": "",
        "command": command,
        "cwd": str(args.cwd or "").strip(),
        "runMode": run_mode,
        "iconType": "glyph",
        "iconValue": icon,
        "favorite": bool((previous or {}).get("favorite") is True),
        "pinnedSlot": slot,
        "badgeText": plain_label(args.badge) if args.badge is not None else plain_label((previous or {}).get("badgeText")),
        "colorRole": str(args.color if args.color is not None else (previous or {}).get("colorRole") or ""),
    }


def apply_command(data, args):
    space = resolve_space(data, args.space)
    category = resolve_category(data, space["id"], args.category)
    command = str(args.command).strip()
    previous = next((item for item in data["items"] if same_command(item, space["id"], command)), None)
    item = build_item(args, space, category, previous)

    if item["pinnedSlot"] >= 1:
        for other in data["items"]:
            if not isinstance(other, dict) or other.get("id") == item["id"]:
                continue
            if other.get("spaceId") == space["id"] and other.get("pinnedSlot") == item["pinnedSlot"]:
                other["pinnedSlot"] = 0

    if previous:
        data["items"][data["items"].index(previous)] = item
        action = "updated"
    else:
        data["items"].append(item)
        action = "added"
    return action, item, space, category


def main():
    parser = argparse.ArgumentParser(description="Add or update a Megamenu command item.")
    parser.add_argument("--title", required=True)
    parser.add_argument("--command", required=True, help="Command text Megamenu runs, usually a program name")
    parser.add_argument("--space", default="", help="Space name or id. Default: the active space")
    parser.add_argument("--category", default="", help="Category name or id. Default: the first category in the space")
    parser.add_argument("--cwd", default="", help="Optional working directory")
    parser.add_argument("--run", choices=("terminal", "background"), default="terminal")
    parser.add_argument("--slot", type=int, default=0, help="Orbit slot 1-6, or 0 for none")
    parser.add_argument("--subtitle", default=None)
    parser.add_argument("--icon", default="", help="Icon glyph. Default: a terminal glyph")
    parser.add_argument("--badge", default=None)
    parser.add_argument("--color", default=None, help="Color role such as blue, green, or yellow")
    parser.add_argument("--data", default=str(DATA_PATH), help="Path to data.json")
    parser.add_argument("--dry-run", action="store_true", help="Print the item and do not write")
    args = parser.parse_args()

    path = Path(args.data).expanduser()
    if not path.is_file():
        raise SystemExit("Megamenu data was not found at %s. Open Megamenu once, then try again." % path)
    if args.dry_run:
        action, item, space, category = apply_command(load_data(path), args)
        json.dump({"action": action, "item": item, "space": space.get("name"), "category": category.get("name")}, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return

    with path.open("r+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        handle.seek(0)
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise SystemExit("Megamenu data is not valid JSON: %s" % exc)
        if not isinstance(data, dict) or not isinstance(data.get("spaces"), list) or not isinstance(data.get("items"), list):
            raise SystemExit("Megamenu data is missing spaces or items.")
        data.setdefault("categories", [])
        action, item, space, category = apply_command(data, args)
        write_data(path, data)
    print("%s %s in %s / %s" % (action, item["title"], space.get("name") or space["id"], category.get("name") or category["id"]))


if __name__ == "__main__":
    main()
