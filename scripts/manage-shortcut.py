#!/usr/bin/env python3
"""Opt-in Hyprland Lua shortcut manager for Omarchy Megamenu (compatible with Omaplug shortcut blocks)."""
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

PLUGIN_ID = "gruut.megamenu"
MODIFIERS = {"SUPER": 64, "CTRL": 4, "ALT": 8, "SHIFT": 1}


def normalize_combo(value):
    raw = str(value or "").strip()
    if not raw or raw.lower() in ("none", "off", "disabled", "false"):
        return "", 0, ""
    parts = [p.strip().upper().replace("CONTROL", "CTRL") for p in raw.split("+") if p.strip()]
    keys = [p for p in parts if p not in MODIFIERS]
    mods = [p for p in parts if p in MODIFIERS]
    if (
        len(keys) != 1
        or not mods
        or len(set(parts)) != len(parts)
        or not re.fullmatch(
            r"[A-Z0-9]|F(?:[1-9]|1[0-2])|SLASH|SPACE|RETURN|TAB|ESCAPE|HOME|END|INSERT|DELETE|PAGEUP|PAGEDOWN|UP|DOWN|LEFT|RIGHT|PERIOD|COMMA|GRAVE",
            keys[0],
        )
    ):
        raise ValueError("Use a modifier (SUPER/ALT/CTRL/SHIFT) + key (e.g. SUPER + M).")
    ordered = [m for m in MODIFIERS if m in mods]
    return " + ".join(ordered + keys), sum(MODIFIERS[m] for m in ordered), keys[0]


def run_cmd(args):
    res = subprocess.run(args, capture_output=True, text=True, timeout=10)
    if res.returncode != 0:
        raise ValueError(res.stderr.strip() or res.stdout.strip() or ("Command failed: " + args[0]))
    return res.stdout.strip()


def make_block(combo, replace=False):
    return (
        f"\n-- omaplug-shortcut-start: {PLUGIN_ID}\n"
        + (f"hl.unbind({json.dumps(combo)})\n" if replace else "")
        + "o.bind("
        + ", ".join(
            json.dumps(s)
            for s in (
                combo,
                f"Omaplug: {PLUGIN_ID}",
                f"omarchy-shell shell toggle {PLUGIN_ID}",
            )
        )
        + ")\n"
        + f"-- omaplug-shortcut-end: {PLUGIN_ID}\n"
    )


def extract_saved(raw):
    pattern = re.compile(
        r"\n?-- omaplug-shortcut-start: "
        + re.escape(PLUGIN_ID)
        + r"\n.*?-- omaplug-shortcut-end: "
        + re.escape(PLUGIN_ID)
        + r"\n?",
        re.S,
    )
    matches = pattern.findall(raw)
    if not matches:
        return "", False, raw
    block_text = matches[-1]
    match = re.search(r'o\.bind\("([^"\n]+)"', block_text)
    has_unbind = "hl.unbind(" in block_text
    cleaned = pattern.sub("", raw)
    if cleaned and not cleaned.endswith("\n"):
        cleaned += "\n"
    return (match.group(1) if match else ""), has_unbind, cleaned


def check_conflict(bindings, combo, own_combo=""):
    _, mask, key = normalize_combo(combo)
    own_ignored = False
    for b in bindings:
        if (int(b.get("modmask", 0)) & ~2) != mask:
            continue
        if b.get("mouse"):
            continue
        bound_key = str(b.get("key", "")).upper()
        if bound_key != key:
            continue
        desc = str(b.get("description") or "")
        arg = str(b.get("arg") or "")
        if not own_ignored and combo == own_combo and (
            desc == f"Omaplug: {PLUGIN_ID}" or PLUGIN_ID in arg
        ):
            own_ignored = True
            continue
        return desc or arg or b.get("dispatcher") or "another action"
    return ""


def read_bindings(path):
    if not path.exists():
        raise ValueError("This shortcut editor requires Omarchy's ~/.config/hypr/bindings.lua file.")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, encoding="utf-8") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 1024 * 1024:
            raise ValueError("Expected a user-owned regular bindings.lua file under 1 MiB.")
        return stream.read(), stat.S_IMODE(info.st_mode)


def write_bindings(path, content, mode):
    fd, tmp_path = tempfile.mkstemp(prefix=".megamenu-shortcut-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def execute(action, value="SUPER + M"):
    bindings_path = Path.home() / ".config/hypr/bindings.lua"
    if action == "status":
        if not bindings_path.exists():
            return {"ok": True, "shortcut": "", "replaced": False}
        raw, _ = read_bindings(bindings_path)
        own_combo, own_replace, _ = extract_saved(raw)
        return {"ok": True, "shortcut": own_combo, "replaced": own_replace}

    if action not in ("set", "replace", "remove"):
        raise ValueError(f"Unknown action: {action}")

    lock_path = bindings_path.parent / ".omaplug-shortcuts.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "w") as lock_stream:
        info = os.fstat(lock_stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("Unsafe shortcut lock file.")
        fcntl.flock(lock_stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        raw, mode = read_bindings(bindings_path)
        own_combo, own_replace, base = extract_saved(raw)

        if action == "remove":
            if not own_combo:
                return {"ok": True, "shortcut": ""}
            write_bindings(bindings_path, base, mode)
            run_cmd(["hyprctl", "reload"])
            return {"ok": True, "shortcut": ""}

        combo, _, _ = normalize_combo(value)
        if not combo:
            if own_combo:
                write_bindings(bindings_path, base, mode)
                run_cmd(["hyprctl", "reload"])
            return {"ok": True, "shortcut": ""}

        try:
            binds = json.loads(run_cmd(["hyprctl", "-j", "binds"]))
        except Exception:
            binds = []
        conflict_desc = check_conflict(binds, combo, own_combo)
        need_replace = bool(conflict_desc) or (action == "replace") or (combo == own_combo and own_replace)
        if conflict_desc and action != "replace":
            return {
                "ok": False,
                "shortcut": own_combo,
                "pendingShortcut": combo,
                "conflict": conflict_desc,
                "error": f"Already assigned to {conflict_desc}.",
            }

        if run_cmd(["hyprctl", "configerrors"]):
            raise ValueError("Fix existing Hyprland configuration errors before saving shortcuts.")

        updated = base + make_block(combo, need_replace)
        if updated == raw:
            return {"ok": True, "shortcut": combo, "replaced": need_replace, "unchanged": True}

        write_bindings(bindings_path, updated, mode)
        try:
            run_cmd(["hyprctl", "reload"])
            errors = run_cmd(["hyprctl", "configerrors"])
            if errors:
                raise ValueError(errors)
        except Exception as err:
            if read_bindings(bindings_path)[0] == updated:
                write_bindings(bindings_path, raw, mode)
                run_cmd(["hyprctl", "reload"])
            raise ValueError(f"Shortcut was not saved; previous bindings restored. {err}")
        return {"ok": True, "shortcut": combo, "replaced": need_replace, "conflict": conflict_desc}


if __name__ == "__main__":
    try:
        act = sys.argv[1] if len(sys.argv) > 1 else "status"
        val = sys.argv[2] if len(sys.argv) > 2 else "SUPER + M"
        res = execute(act, val)
        print(json.dumps(res))
        if not res.get("ok", True) and act != "set":
            sys.exit(1)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
