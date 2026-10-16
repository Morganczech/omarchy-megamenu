#!/usr/bin/env python3
"""Fetch and cache RSS/Atom feeds and GitHub Issues/PRs/Releases for Omarchy Megamenu."""
import concurrent.futures
from datetime import datetime, timezone
import email.utils
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

USER_AGENT = "Omarchy-Megamenu/1.1 (+https://github.com/Morganczech/omarchy-megamenu)"
DEFAULT_TTL_SECONDS = 600  # 10 minutes
MAX_ITEMS_PER_FEED = 12


def ensure_private_dir(path: Path) -> None:
    """Create (or harden) a user-only directory for local caches that may hold private titles."""
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def write_private_text(path: Path, text: str) -> None:
    """Atomically write text as a user-only (0600) regular file."""
    ensure_private_dir(path.parent)
    fd, tmp_name = tempfile.mkstemp(prefix=".feeds-cache-", suffix=".tmp", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp_path, path)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    finally:
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def clean_text(val):
    if not val:
        return ""
    text = html.unescape(str(val))
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def format_relative_time(dt_str):
    if not dt_str:
        return ""
    s = str(dt_str).strip()
    dt = None
    # Try RFC 2822 (RSS pubDate)
    try:
        dt = email.utils.parsedate_to_datetime(s)
    except Exception:
        pass
    # Try ISO 8601 (Atom / GitHub API)
    if dt is None:
        try:
            iso = s.replace("Z", "+00:00")
            dt = datetime.fromisoformat(iso)
        except Exception:
            pass
    if dt is None:
        return ""
    try:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        diff = int((now - dt).total_seconds())
        if diff < 60:
            return "now"
        if diff < 3600:
            return f"{diff // 60}m ago"
        if diff < 86400:
            return f"{diff // 3600}h ago"
        days = diff // 86400
        if days < 30:
            return f"{days}d ago"
        return dt.strftime("%Y-%m-%d")
    except Exception:
        return ""


def extract_domain(url):
    try:
        parsed = urllib.parse.urlparse(str(url or ""))
        host = (parsed.netloc or "").lower()
        if host.startswith("www."):
            host = host[4:]
        return host
    except Exception:
        return ""


def http_get(url, accept="application/xml, text/xml, application/atom+xml, application/rss+xml, */*"):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": accept,
        },
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        return resp.read().decode("utf-8", errors="replace")


def local_tag(tag):
    if "}" in tag:
        return tag.split("}", 1)[1].lower()
    return tag.lower()


def parse_rss_or_atom(xml_text, feed_url, cat_id, space_id, color_role):
    root = ET.fromstring(xml_text)
    rtag = local_tag(root.tag)
    items = []
    feed_domain = extract_domain(feed_url)

    if rtag == "rss" or rtag == "rdf":
        # RSS 2.0 / 1.0
        for elem in root.iter():
            if local_tag(elem.tag) != "item":
                continue
            title = ""
            link = ""
            pub_date = ""
            comments_info = ""
            for child in elem:
                ctag = local_tag(child.tag)
                if ctag == "title" and not title:
                    title = clean_text(child.text)
                elif ctag == "link" and not link:
                    link = clean_text(child.text)
                elif ctag in ("pubdate", "date", "published", "updated") and not pub_date:
                    pub_date = clean_text(child.text)
                elif ctag == "description" and not comments_info:
                    desc = clean_text(child.text)
                    if desc and len(desc) <= 90:
                        comments_info = desc
            if not title or not link:
                continue
            domain = extract_domain(link) or feed_domain
            rel = format_relative_time(pub_date)
            sub_parts = [p for p in (domain, rel) if p]
            items.append(
                {
                    "id": f"live-{cat_id}-{len(items)}",
                    "spaceId": space_id,
                    "categoryId": cat_id,
                    "type": "url",
                    "title": title,
                    "subtitle": " • ".join(sub_parts) if sub_parts else link,
                    "url": link,
                    "desktopId": "",
                    "iconType": "favicon",
                    "iconValue": "󰑫",
                    "favorite": False,
                    "pinnedSlot": 0,
                    "badgeText": "",
                    "colorRole": color_role,
                    "isLiveItem": True,
                }
            )
            if len(items) >= MAX_ITEMS_PER_FEED:
                break
    else:
        # Atom feed
        for elem in root.iter():
            if local_tag(elem.tag) != "entry":
                continue
            title = ""
            link = ""
            pub_date = ""
            for child in elem:
                ctag = local_tag(child.tag)
                if ctag == "title" and not title:
                    title = clean_text("".join(child.itertext()))
                elif ctag == "link":
                    href = child.attrib.get("href", "").strip()
                    rel_attr = child.attrib.get("rel", "alternate").strip()
                    if href and (not link or rel_attr == "alternate"):
                        link = href
                elif ctag in ("updated", "published") and not pub_date:
                    pub_date = clean_text(child.text)
            if not title or not link:
                continue
            domain = extract_domain(link) or feed_domain
            rel = format_relative_time(pub_date)
            sub_parts = [p for p in (domain, rel) if p]
            items.append(
                {
                    "id": f"live-{cat_id}-{len(items)}",
                    "spaceId": space_id,
                    "categoryId": cat_id,
                    "type": "url",
                    "title": title,
                    "subtitle": " • ".join(sub_parts) if sub_parts else link,
                    "url": link,
                    "desktopId": "",
                    "iconType": "favicon",
                    "iconValue": "󰑫",
                    "favorite": False,
                    "pinnedSlot": 0,
                    "badgeText": "",
                    "colorRole": color_role,
                    "isLiveItem": True,
                }
            )
            if len(items) >= MAX_ITEMS_PER_FEED:
                break

    return items


def normalize_github_repo(source):
    s = str(source or "").strip()
    s = re.sub(r"^https?://github\.com/", "", s, flags=re.I)
    s = s.strip("/")
    parts = [p for p in s.split("/") if p]
    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"
    return s


def fetch_github_via_gh_cli(repo, mode):
    gh_bin = shutil.which("gh")
    if not gh_bin:
        return None
    try:
        if repo.lower() in ("@me", "me", "my"):
            target_flag = "-- PRs" if mode == "prs" else "-- Issues"
            cmd = [
                gh_bin,
                "search",
                "prs" if mode == "prs" else "issues",
                "--author=@me",
                "--state=open",
                "--limit",
                str(MAX_ITEMS_PER_FEED),
                "--json",
                "title,url,number,updatedAt,repository",
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=6)
            if res.returncode == 0 and res.stdout.strip():
                return json.loads(res.stdout)
        return None
    except Exception:
        return None


def fetch_github_category(cat):
    cat_id = str(cat.get("id") or "")
    space_id = str(cat.get("spaceId") or "")
    color_role = str(cat.get("colorRole") or "blue")
    repo = normalize_github_repo(cat.get("feedUrl") or "")
    mode = str(cat.get("feedMode") or "all").lower()
    if not repo:
        return []

    # Optional @me support via authenticated gh CLI if user enters "@me"
    if repo.lower() in ("@me", "me"):
        gh_data = fetch_github_via_gh_cli(repo, mode)
        if isinstance(gh_data, list):
            out = []
            for entry in gh_data[:MAX_ITEMS_PER_FEED]:
                num = entry.get("number", "")
                rname = (entry.get("repository") or {}).get("nameWithOwner", "github.com")
                rel = format_relative_time(entry.get("updatedAt", ""))
                badge = f"#{num}" if num else "GH"
                out.append(
                    {
                        "id": f"live-{cat_id}-{len(out)}",
                        "spaceId": space_id,
                        "categoryId": cat_id,
                        "type": "url",
                        "title": clean_text(entry.get("title") or ""),
                        "subtitle": " • ".join([p for p in (rname, rel) if p]),
                        "url": str(entry.get("url") or "https://github.com"),
                        "desktopId": "",
                        "iconType": "favicon",
                        "iconValue": "󰊤",
                        "favorite": False,
                        "pinnedSlot": 0,
                        "badgeText": badge,
                        "colorRole": color_role,
                        "isLiveItem": True,
                    }
                )
            return out

    if mode == "releases":
        api_url = f"https://api.github.com/repos/{repo}/releases?per_page={MAX_ITEMS_PER_FEED}"
        raw_json = http_get(api_url, accept="application/vnd.github+json")
        data = json.loads(raw_json)
        out = []
        if isinstance(data, list):
            for rel_obj in data[:MAX_ITEMS_PER_FEED]:
                tag = str(rel_obj.get("tag_name") or "")
                name = clean_text(rel_obj.get("name") or tag or "Release")
                html_url = str(rel_obj.get("html_url") or f"https://github.com/{repo}/releases")
                rel_time = format_relative_time(rel_obj.get("published_at") or rel_obj.get("created_at") or "")
                out.append(
                    {
                        "id": f"live-{cat_id}-{len(out)}",
                        "spaceId": space_id,
                        "categoryId": cat_id,
                        "type": "url",
                        "title": name,
                        "subtitle": " • ".join([p for p in (repo, rel_time) if p]),
                        "url": html_url,
                        "desktopId": "",
                        "iconType": "favicon",
                        "iconValue": "󰊤",
                        "favorite": False,
                        "pinnedSlot": 0,
                        "badgeText": tag or "Release",
                        "colorRole": color_role,
                        "isLiveItem": True,
                    }
                )
        return out

    # Issues & PRs via /repos/{owner}/{repo}/issues
    api_url = f"https://api.github.com/repos/{repo}/issues?state=open&per_page=25"
    raw_json = http_get(api_url, accept="application/vnd.github+json")
    data = json.loads(raw_json)
    out = []
    if isinstance(data, list):
        for issue in data:
            is_pr = "pull_request" in issue
            if mode == "issues" and is_pr:
                continue
            if mode == "prs" and not is_pr:
                continue
            num = issue.get("number", "")
            title = clean_text(issue.get("title") or f"#{num}")
            html_url = str(issue.get("html_url") or f"https://github.com/{repo}")
            user_login = str((issue.get("user") or {}).get("login") or "")
            rel_time = format_relative_time(issue.get("updated_at") or issue.get("created_at") or "")
            kind_prefix = "PR" if is_pr else "Issue"
            badge = f"{kind_prefix} #{num}" if num else kind_prefix
            sub_parts = [p for p in (f"@{user_login}" if user_login else repo, rel_time) if p]
            out.append(
                {
                    "id": f"live-{cat_id}-{len(out)}",
                    "spaceId": space_id,
                    "categoryId": cat_id,
                    "type": "url",
                    "title": title,
                    "subtitle": " • ".join(sub_parts),
                    "url": html_url,
                    "desktopId": "",
                    "iconType": "favicon",
                    "iconValue": "󰊤",
                    "favorite": False,
                    "pinnedSlot": 0,
                    "badgeText": badge,
                    "colorRole": "magenta" if is_pr else color_role,
                    "isLiveItem": True,
                }
            )
            if len(out) >= MAX_ITEMS_PER_FEED:
                break
    return out


def fetch_single_category(cat):
    cat_id = str(cat.get("id") or "")
    space_id = str(cat.get("spaceId") or "")
    color_role = str(cat.get("colorRole") or "blue")
    cat_type = str(cat.get("type") or "static").lower()
    feed_url = str(cat.get("feedUrl") or "").strip()

    if cat_type == "rss" and feed_url:
        if not re.match(r"^https?://", feed_url, flags=re.I):
            feed_url = "https://" + feed_url
        xml_text = http_get(feed_url)
        items = parse_rss_or_atom(xml_text, feed_url, cat_id, space_id, color_role)
        return cat_id, {"items": items, "updatedAt": int(time.time()), "error": ""}

    if cat_type == "github" and feed_url:
        items = fetch_github_category(cat)
        return cat_id, {"items": items, "updatedAt": int(time.time()), "error": ""}

    return cat_id, None


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"feeds": {}}))
        return

    data_path = Path(sys.argv[1])
    cache_path = Path(sys.argv[2])
    force = "--force" in sys.argv[3:]
    only_cat_id = ""
    for arg in sys.argv[3:]:
        if arg.startswith("--category="):
            only_cat_id = arg.split("=", 1)[1].strip()

    # Harden layout even when cache is only read (existing installs may be 0755/0644).
    ensure_private_dir(cache_path.parent)
    if cache_path.exists():
        try:
            os.chmod(cache_path, 0o600)
        except OSError:
            pass

    cache = {"feeds": {}}
    if cache_path.exists():
        try:
            loaded = json.loads(cache_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict) and isinstance(loaded.get("feeds"), dict):
                cache = loaded
        except Exception:
            cache = {"feeds": {}}

    if not data_path.exists():
        print(json.dumps(cache))
        return

    try:
        user_data = json.loads(data_path.read_text(encoding="utf-8"))
    except Exception:
        print(json.dumps(cache))
        return

    categories = user_data.get("categories") if isinstance(user_data, dict) else []
    if not isinstance(categories, list):
        categories = []

    now = int(time.time())
    to_fetch = []
    for c in categories:
        if not isinstance(c, dict):
            continue
        cid = str(c.get("id") or "")
        ctype = str(c.get("type") or "static").lower()
        furl = str(c.get("feedUrl") or "").strip()
        if ctype not in ("rss", "github") or not furl or not cid:
            continue
        if only_cat_id and cid != only_cat_id:
            continue
        existing = cache["feeds"].get(cid)
        if (
            not force
            and isinstance(existing, dict)
            and isinstance(existing.get("items"), list)
            and len(existing.get("items")) > 0
            and (now - int(existing.get("updatedAt") or 0)) < DEFAULT_TTL_SECONDS
        ):
            continue
        to_fetch.append(c)

    if to_fetch:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = {pool.submit(fetch_single_category, c): c for c in to_fetch}
            for fut in concurrent.futures.as_completed(futures):
                cat_obj = futures[fut]
                cid = str(cat_obj.get("id") or "")
                try:
                    _, result = fut.result()
                    if result is not None:
                        cache["feeds"][cid] = result
                except Exception as exc:
                    prev = cache["feeds"].get(cid, {})
                    cache["feeds"][cid] = {
                        "items": prev.get("items", []) if isinstance(prev, dict) else [],
                        "updatedAt": now,
                        "error": str(exc),
                    }

        try:
            write_private_text(
                cache_path,
                json.dumps(cache, ensure_ascii=False, indent=2) + "\n",
            )
        except Exception:
            pass

    print(json.dumps(cache, ensure_ascii=False))


if __name__ == "__main__":
    main()
