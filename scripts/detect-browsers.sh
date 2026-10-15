#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import configparser
import glob
import json
import os
import re
import subprocess

default_desktop = ""
try:
    out = subprocess.check_output(
        ["xdg-settings", "get", "default-web-browser"],
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=2,
    ).strip()
    default_desktop = out
except Exception:
    pass

search_dirs = [
    os.path.expanduser("~/.local/share/applications"),
    "/usr/local/share/applications",
    "/usr/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]

seen_ids = set()
seen_execs = set()
browsers = []

for d in search_dirs:
    if not os.path.isdir(d):
        continue
    for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
        desktop_file = os.path.basename(path)
        if desktop_file in seen_ids:
            continue

        cp = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            cp.read(path, encoding="utf-8")
        except Exception:
            continue

        if "Desktop Entry" not in cp:
            continue
        entry = cp["Desktop Entry"]

        if entry.get("NoDisplay", "false").lower() == "true":
            continue
        if entry.get("Hidden", "false").lower() == "true":
            continue

        cats = entry.get("Categories", "")
        mime = entry.get("MimeType", "")
        if "WebBrowser" not in cats and "x-scheme-handler/https" not in mime:
            continue

        name = entry.get("Name", "").strip()
        exec_raw = entry.get("Exec", "").strip()
        icon = entry.get("Icon", "web-browser").strip()
        if not name or not exec_raw:
            continue

        # Strip %u, %U, %f, %F etc. from Exec
        exec_clean = re.sub(r"\s+%[a-zA-Z]", "", exec_raw).strip()
        if not exec_clean:
            continue

        # Avoid duplicate entries for the same binary
        exec_key = exec_clean.split()[0]
        seen_ids.add(desktop_file)
        if exec_key in seen_execs and desktop_file != default_desktop:
            continue
        seen_execs.add(exec_key)

        desktop_id = desktop_file[:-8] if desktop_file.endswith(".desktop") else desktop_file
        is_default = (desktop_file == default_desktop)

        browsers.append({
            "id": desktop_id,
            "desktopFile": desktop_file,
            "name": name,
            "exec": exec_clean,
            "icon": icon,
            "isDefault": is_default,
        })

browsers.sort(key=lambda b: (0 if b["isDefault"] else 1, b["name"].lower()))
print(json.dumps(browsers))
PY
