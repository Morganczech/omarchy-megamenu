#!/usr/bin/env python3
"""Register the Megamenu native messaging host for Chrome and Firefox.

Run this from the plugin directory (or a git checkout). It points the
browsers at scripts/native-host.py next to this file and allows the
extension id pinned in extension/manifest.json.
"""

import json
import os
import stat
import sys

HOST_NAME = "gruut.megamenu"
GECKO_ID = "megamenu@gruut"
DESCRIPTION = "Save the current page into Omarchy Megamenu"

CHROME_ROOTS = [
    "~/.config/google-chrome",
    "~/.config/chromium",
    "~/.config/BraveSoftware/Brave-Browser",
    "~/.config/microsoft-edge",
    "~/.config/vivaldi",
]
# Firefox always gets a manifest. The others are written when that browser
# already has a config directory, so unused browsers are left untouched.
ALWAYS_FIREFOX = ["~/.mozilla/native-messaging-hosts"]
OPTIONAL_FIREFOX = [
    "~/.librewolf/native-messaging-hosts",
    "~/.zen/native-messaging-hosts",
]


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def extension_id():
    manifest_path = os.path.join(repo_root(), "extension", "manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    key = manifest.get("key")
    if not key:
        raise SystemExit(f"Missing \"key\" in {manifest_path}")
    import base64
    import hashlib
    der = base64.b64decode(key)
    digest = hashlib.sha256(der).hexdigest()[:32]
    return "".join(chr(ord("a") + int(char, 16)) for char in digest)


def chrome_manifest(host_path, ext_id):
    return {
        "name": HOST_NAME,
        "description": DESCRIPTION,
        "path": host_path,
        "type": "stdio",
        "allowed_origins": [f"chrome-extension://{ext_id}/"],
    }


def firefox_manifest(host_path):
    return {
        "name": HOST_NAME,
        "description": DESCRIPTION,
        "path": host_path,
        "type": "stdio",
        "allowed_extensions": [GECKO_ID],
    }


def write_json(path, payload, dry_run, quiet=False):
    expanded = os.path.expanduser(path)
    if dry_run:
        if not quiet:
            print(f"would write {expanded}")
        return expanded
    os.makedirs(os.path.dirname(expanded), exist_ok=True)
    tmp = expanded + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, expanded)
    if not quiet:
        print(f"wrote {expanded}")
    return expanded


def remove_path(path, dry_run):
    expanded = os.path.expanduser(path)
    if dry_run:
        print(f"would remove {expanded}")
        return
    if os.path.isfile(expanded):
        os.remove(expanded)
        print(f"removed {expanded}")


def target_dirs():
    chrome_dirs = []
    for root in CHROME_ROOTS:
        expanded = os.path.expanduser(root)
        if os.path.isdir(expanded):
            chrome_dirs.append(os.path.join(root, "NativeMessagingHosts"))
    firefox_dirs = list(ALWAYS_FIREFOX)
    for directory in OPTIONAL_FIREFOX:
        parent = os.path.dirname(os.path.expanduser(directory))
        if os.path.isdir(parent):
            firefox_dirs.append(directory)
    return chrome_dirs, firefox_dirs


def host_manifest_paths(directories):
    filename = HOST_NAME + ".json"
    return [os.path.expanduser(os.path.join(directory, filename)) for directory in directories]


def registered_paths(directories):
    return [path for path in host_manifest_paths(directories) if os.path.isfile(path)]


def emit(payload, json_mode):
    if json_mode:
        print(json.dumps(payload, ensure_ascii=False))
        return
    if not payload.get("ok", True):
        raise SystemExit(payload.get("error") or "Registration failed")
    for path in payload.get("wrote") or []:
        print(f"wrote {path}")
    for path in payload.get("removed") or []:
        print(f"removed {path}")
    if "registered" in payload:
        state = "registered" if payload["registered"] else "not registered"
        print(f"Firefox host is {state}.")


def main():
    args = set(sys.argv[1:])
    dry_run = "--dry-run" in args
    remove = "--remove" in args
    firefox_only = "--firefox-only" in args
    json_mode = "--json" in args
    status_only = "--status" in args
    host_path = os.path.join(repo_root(), "scripts", "native-host.py")
    if not os.path.isfile(host_path):
        emit({"ok": False, "error": f"Missing host script: {host_path}"}, json_mode)
        return 1
    if not dry_run and not remove and not status_only:
        mode = os.stat(host_path).st_mode
        os.chmod(host_path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    chrome_dirs, firefox_dirs = target_dirs()
    if firefox_only:
        chrome_dirs = []
    filename = HOST_NAME + ".json"

    if status_only:
        found = registered_paths(firefox_dirs if firefox_only else chrome_dirs + firefox_dirs)
        emit({
            "ok": True,
            "registered": os.path.isfile(os.path.expanduser(
                "~/.mozilla/native-messaging-hosts/" + filename
            )),
            "paths": found,
        }, json_mode)
        return 0

    if remove:
        removed = []
        for directory in chrome_dirs + firefox_dirs:
            path = os.path.join(directory, filename)
            if dry_run:
                print(f"would remove {os.path.expanduser(path)}")
                continue
            if os.path.isfile(os.path.expanduser(path)):
                remove_path(path, False)
                removed.append(os.path.expanduser(path))
        emit({"ok": True, "removed": removed, "registered": False}, json_mode)
        return 0

    if not firefox_only and not chrome_dirs and not json_mode:
        print("No Chromium-based browser config found. Chrome, Chromium, Brave, Edge, and Vivaldi will be skipped until one of them has been started.", file=sys.stderr)

    wrote = []
    if chrome_dirs:
        ext_id = extension_id()
        for directory in chrome_dirs:
            wrote.append(write_json(
                os.path.join(directory, filename),
                chrome_manifest(host_path, ext_id),
                dry_run,
                quiet=json_mode,
            ))
    for directory in firefox_dirs:
        wrote.append(write_json(
            os.path.join(directory, filename),
            firefox_manifest(host_path),
            dry_run,
            quiet=json_mode,
        ))

    if json_mode:
        emit({
            "ok": True,
            "registered": True,
            "wrote": [] if dry_run else wrote,
            "geckoId": GECKO_ID,
        }, True)
        return 0

    extension_dir = os.path.join(repo_root(), "extension")
    print("")
    print(f"Firefox id:   {GECKO_ID}")
    print(f"Load this folder as an unpacked extension: {extension_dir}")
    print("Firefox / Zen: about:debugging  →  This Firefox  →  Load Temporary Add-on  →  extension/manifest.json")
    print("Open Megamenu once before the first save so data.json exists.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
