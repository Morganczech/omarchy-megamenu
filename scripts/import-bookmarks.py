#!/usr/bin/env python3
"""
Bookmark discovery & parser for Omarchy Megamenu.
Supports:
  1. Chromium-family JSON Bookmarks (Brave, Chromium, Chrome, Vivaldi, Edge, Thorium)
  2. Firefox / Zen / LibreWolf places.sqlite (copied to temp file for lock-free read)
  3. Exported HTML bookmark files (Netscape Bookmark format in ~/Downloads, ~, Documents)

Usage:
  import-bookmarks.py --scan
      Outputs JSON array of discovered sources and their folders + bookmarks.
"""

import glob
import html.parser
import json
import os
import shutil
import sqlite3
import sys
import tempfile


def parse_chromium_bookmarks(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []

    roots = data.get("roots", {})
    folders = []

    def walk_folder(node, folder_name):
        if not isinstance(node, dict):
            return
        children = node.get("children", [])
        direct_bookmarks = []
        for child in children:
            ctype = child.get("type")
            if ctype == "url":
                url = (child.get("url") or "").strip()
                title = (child.get("name") or "").strip()
                if url and url.startswith(("http://", "https://")):
                    direct_bookmarks.append({"title": title or url, "url": url})
            elif ctype == "folder":
                sub_name = (child.get("name") or "Folder").strip()
                walk_folder(child, sub_name)

        if direct_bookmarks:
            folders.append({
                "name": folder_name or "Bookmarks",
                "count": len(direct_bookmarks),
                "bookmarks": direct_bookmarks,
            })

    for root_key, default_label in [
        ("bookmark_bar", "Bookmarks Bar"),
        ("other", "Other Bookmarks"),
        ("synced", "Mobile Bookmarks"),
    ]:
        root_node = roots.get(root_key)
        if isinstance(root_node, dict):
            walk_folder(root_node, root_node.get("name") or default_label)

    return folders


def parse_firefox_places(sqlite_path):
    if not os.path.isfile(sqlite_path):
        return []
    tmp_dir = tempfile.mkdtemp(prefix="omarchy-bm-")
    tmp_db = os.path.join(tmp_dir, "places.sqlite")
    try:
        shutil.copy2(sqlite_path, tmp_db)
        conn = sqlite3.connect(tmp_db)
        cur = conn.cursor()

        cur.execute("SELECT id, title FROM moz_bookmarks WHERE type = 2")
        folder_titles = {row[0]: (row[1] or "Bookmarks") for row in cur.fetchall()}

        cur.execute(
            """
            SELECT b.parent, b.title, p.url
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            WHERE b.type = 1 AND p.url LIKE 'http%'
            ORDER BY b.parent, b.position
            """
        )
        grouped = {}
        for parent_id, title, url in cur.fetchall():
            fname = folder_titles.get(parent_id, "Bookmarks")
            if fname in ("", "menu", "toolbar", "unfiled", "mobile"):
                fname = {
                    "menu": "Bookmarks Menu",
                    "toolbar": "Bookmarks Toolbar",
                    "unfiled": "Other Bookmarks",
                    "mobile": "Mobile Bookmarks",
                }.get(fname, "Bookmarks")
            grouped.setdefault(fname, []).append({
                "title": (title or url).strip(),
                "url": url.strip(),
            })
        conn.close()

        folders = []
        for fname, bms in grouped.items():
            if bms:
                folders.append({
                    "name": fname,
                    "count": len(bms),
                    "bookmarks": bms,
                })
        return folders
    except Exception:
        return []
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


class NetscapeBookmarkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.folder_stack = ["Imported Bookmarks"]
        self.in_h3 = False
        self.in_a = False
        self.current_href = ""
        self.text_buf = []
        self.folders_map = {}
        self.last_h3 = "Imported Bookmarks"

    def handle_starttag(self, tag, attrs):
        t = tag.lower()
        attr_dict = dict(attrs)
        if t == "h3":
            self.in_h3 = True
            self.text_buf = []
        elif t == "dl":
            if self.last_h3:
                self.folder_stack.append(self.last_h3)
                self.last_h3 = None
        elif t == "a":
            href = (attr_dict.get("href") or "").strip()
            if href.startswith(("http://", "https://")):
                self.in_a = True
                self.current_href = href
                self.text_buf = []

    def handle_endtag(self, tag):
        t = tag.lower()
        if t == "h3" and self.in_h3:
            self.in_h3 = False
            name = "".join(self.text_buf).strip() or "Bookmarks"
            self.last_h3 = name
        elif t == "dl":
            if len(self.folder_stack) > 1:
                self.folder_stack.pop()
        elif t == "a" and self.in_a:
            self.in_a = False
            title = "".join(self.text_buf).strip() or self.current_href
            folder = self.folder_stack[-1] if self.folder_stack else "Imported Bookmarks"
            self.folders_map.setdefault(folder, []).append({
                "title": title,
                "url": self.current_href,
            })

    def handle_data(self, data):
        if self.in_h3 or self.in_a:
            self.text_buf.append(data)


def parse_html_bookmarks(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            raw = f.read()
        parser = NetscapeBookmarkParser()
        parser.feed(raw)
        folders = []
        for fname, bms in parser.folders_map.items():
            if bms:
                folders.append({
                    "name": fname,
                    "count": len(bms),
                    "bookmarks": bms,
                })
        return folders
    except Exception:
        return []


def discover_sources():
    home = os.path.expanduser("~")
    sources = []

    chromium_Candidates = [
        ("Brave", os.path.join(home, ".config/BraveSoftware/Brave-Browser/*/Bookmarks")),
        ("Chromium", os.path.join(home, ".config/chromium/*/Bookmarks")),
        ("Google Chrome", os.path.join(home, ".config/google-chrome/*/Bookmarks")),
        ("Vivaldi", os.path.join(home, ".config/vivaldi/*/Bookmarks")),
        ("Thorium", os.path.join(home, ".config/thorium/*/Bookmarks")),
        ("Microsoft Edge", os.path.join(home, ".config/microsoft-edge/*/Bookmarks")),
    ]

    for browser_name, pattern in chromium_Candidates:
        for path in sorted(glob.glob(pattern)):
            profile = os.path.basename(os.path.dirname(path))
            folders = parse_chromium_bookmarks(path)
            total = sum(f["count"] for f in folders)
            if total > 0:
                sources.append({
                    "id": f"chromium:{path}",
                    "name": f"{browser_name} ({profile})",
                    "type": "chromium",
                    "path": path,
                    "totalBookmarks": total,
                    "folders": folders,
                })

    ff_candidates = [
        ("Firefox", os.path.join(home, ".mozilla/firefox/*/places.sqlite")),
        ("Firefox", os.path.join(home, ".config/mozilla/firefox/*/places.sqlite")),
        ("Zen Browser", os.path.join(home, ".zen/*/places.sqlite")),
        ("Zen Browser", os.path.join(home, ".config/zen/*/places.sqlite")),
        ("LibreWolf", os.path.join(home, ".librewolf/*/places.sqlite")),
        ("LibreWolf", os.path.join(home, ".config/librewolf/*/places.sqlite")),
    ]

    for browser_name, pattern in ff_candidates:
        for path in sorted(glob.glob(pattern)):
            profile = os.path.basename(os.path.dirname(path))
            folders = parse_firefox_places(path)
            total = sum(f["count"] for f in folders)
            if total > 0:
                sources.append({
                    "id": f"firefox:{path}",
                    "name": f"{browser_name} ({profile})",
                    "type": "firefox",
                    "path": path,
                    "totalBookmarks": total,
                    "folders": folders,
                })

    html_patterns = [
        os.path.join(home, "Downloads", "*bookmark*.html"),
        os.path.join(home, "Downloads", "*Bookmark*.html"),
        os.path.join(home, "*bookmark*.html"),
        os.path.join(home, "Documents", "*bookmark*.html"),
    ]
    seen_html = set()
    for pattern in html_patterns:
        for path in sorted(glob.glob(pattern)):
            if path in seen_html:
                continue
            seen_html.add(path)
            folders = parse_html_bookmarks(path)
            total = sum(f["count"] for f in folders)
            if total > 0:
                sources.append({
                    "id": f"html:{path}",
                    "name": f"HTML: {os.path.basename(path)}",
                    "type": "html",
                    "path": path,
                    "totalBookmarks": total,
                    "folders": folders,
                })

    return sources


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--file":
        fpath = os.path.expanduser(sys.argv[2])
        if fpath.endswith(".html") or fpath.endswith(".htm"):
            folders = parse_html_bookmarks(fpath)
        elif fpath.endswith(".sqlite"):
            folders = parse_firefox_places(fpath)
        else:
            folders = parse_chromium_bookmarks(fpath)
        total = sum(f["count"] for f in folders)
        print(json.dumps([{
            "id": f"custom:{fpath}",
            "name": os.path.basename(fpath),
            "type": "custom",
            "path": fpath,
            "totalBookmarks": total,
            "folders": folders,
        }]))
        return

    print(json.dumps(discover_sources()))


if __name__ == "__main__":
    main()
