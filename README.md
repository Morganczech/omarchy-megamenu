# Omarchy Megamenu (`gruut.megamenu`)

A theme-aware Spotlight-style megamenu and bar widget for [Omarchy](https://omarchy.org/) featuring workspaces (**Spaces**), a 6-slot **Quick Access Orbit**, color-coded categories, live **RSS/Atom & GitHub columns**, web bookmarks with automatic favicons, built-in **Omarchy system actions & desktop app search**, per-link browser selection, and one-click browser bookmark importing.

![Omarchy Megamenu preview](preview.png)

## Features

- **Spaces (Workspaces for Links, Feeds & Apps):**
  - Organize your links, feeds, and apps into separate spaces (e.g. *Dev Matrix*, *Homelab & Infra*, *Live Pulse*, *Personal*) and switch between them with `Tab` / `Shift+Tab` or a click.
  - Create, rename, or delete spaces directly from the top bar.
- **Quick Access / Primary Orbit (`1–6`):**
  - Pin up to 6 of your most used web apps, Omarchy actions, or local applications per space and launch them instantly with keys `1` through `6`.
- **Live Columns (RSS/Atom & GitHub Issues/PRs/Releases):**
  - Any category column can be configured as a **Static Bookmark list**, **RSS / Atom Feed**, or **GitHub Repository feed** (`owner/repo` or `@me` via `gh` CLI).
  - Includes a built-in **Live Pulse** showcase space (Hacker News, Omarchy GitHub activity, Tech News) and one-click `󰐃` pinning to save any live entry as a permanent bookmark.
- **Color-Coded Categories & Theme Integration:**
  - Automatically adapts to the active Omarchy light/dark theme (`Color`, `Style`, `Border`, and semantic ANSI colors from `colors.toml`: `blue`, `cyan`, `green`, `magenta`, `yellow`, `orange`, `red`).
  - Responsive category filter badges under the search bar that center on a single row and wrap cleanly when you have many categories.
- **Instant Search, Omarchy Spotlight Actions & Local App Launcher (`>`):**
  - Type anywhere to filter bookmarks across spaces **and** simultaneously search native Omarchy system actions (`Style › Theme`, `Style › Background`, `System › Lock`, `Trigger › Capture › Screenshot`, `Setup › Monitors`, etc.) and installed `.desktop` applications.
  - Prefix your query with **`>`** (e.g. `> theme`, `> ghostty`) to open the dedicated full-width Omarchy actions & applications view, or pin any action/app into a Megamenu category.
- **Right-Click Browser Chooser & Actions:**
  - Right-click any item (or press `Alt+M`) to open a context menu where you can launch a URL in **any installed browser** (Brave, Zen, Firefox, Chromium, Vivaldi, LibreWolf, etc.), copy the URL/Desktop ID to the clipboard (`wl-copy`), edit, or delete the item.
- **Browser Bookmark Importer:**
  - Automatically detects bookmark profiles from installed Chromium-based browsers (Brave, Chromium, Chrome, Vivaldi, Edge) and Firefox/Zen/LibreWolf (`places.sqlite`), as well as exported HTML files (`~/Downloads/bookmarks.html`).
  - Select which bookmark folders to import as color-coded categories into the active space.
- **Opt-In Global Keyboard Shortcut (Spotlight Mode):**
  - Click the **`󰌌 Set shortcut`** button in the top bar of Megamenu to optionally bind a Hyprland shortcut (such as `SUPER + M` or `ALT + SPACE`) in `~/.config/hypr/bindings.lua` using Omaplug-compatible comment blocks.
  - Strictly opt-in: no user configuration files are modified without explicit user action.
- **Multilingual UI (English & Czech):**
  - Supports automatic locale detection (`Auto`), **English (`EN`)**, and **Czech (`CS`)**, switchable live from the top bar or via bar widget settings.

## Install

```bash
omarchy plugin add https://github.com/Morganczech/omarchy-megamenu --enable
```

## Update & Remove

If you configured an optional global keyboard shortcut inside Megamenu, you can disable it first via the **`󰌌`** button (**Disable shortcut**) before removing the plugin.

```bash
# Update plugin
omarchy plugin update gruut.megamenu

# Move widget to another bar section
omarchy bar move gruut.megamenu --section left

# Remove plugin
omarchy plugin remove gruut.megamenu
```

### Manual removal

```bash
rm -rf ~/.config/omarchy/plugins/gruut.megamenu
```

Then remove `"gruut.megamenu"` from `~/.config/omarchy/shell.json` (and any optional `-- omaplug-shortcut-start: gruut.megamenu` block from `~/.config/hypr/bindings.lua`) and run `omarchy restart shell`.

## Usage

Click the **Megamenu** icon (`󰀻`) in the Omarchy bar, or toggle it from a terminal / keybinding:

```bash
omarchy-shell shell toggle gruut.megamenu
```

### Keyboard Shortcuts inside Megamenu

| Key | Action |
| --- | --- |
| **Type text** | Filter bookmarks and apps in the active space |
| **`>` + query** | Search and launch installed system applications |
| **`1` – `6`** | Launch pinned Quick Access Orbit slot `1–6` (when search is empty) |
| **`Tab` / `Shift+Tab`** | Switch to next / previous Space |
| **`↑` / `↓` / `←` / `→`** | Navigate items (or system apps in `>` mode) |
| **`Enter`** | Launch selected bookmark or application |
| **`Right-Click` / `Alt+M`** | Open context menu (choose browser, copy URL, edit, delete) |
| **`Alt+E`** | Edit selected item |
| **`Ctrl+N`** | Add new bookmark or local application |
| **`Esc`** | Close modal / context menu / Megamenu |

## Requirements & Dependencies

- **Omarchy 4.x** (`quickshell` runtime, Hyprland, and `omarchy` CLI)
- **Standard system utilities included with Omarchy:**
  - `python3` (standard library `sqlite3`, `json`, `html.parser` for bookmark importing and opt-in shortcut management)
  - `curl` (caches website favicons into `~/.local/share/omarchy-megamenu/favicons/`)
  - `wl-copy` (copies URLs and Desktop IDs to the Wayland clipboard)
  - `xdg-open` and `gtk-launch` (launches URLs and `.desktop` applications)
- **Data storage:** Stored locally in `~/.local/share/omarchy-megamenu/data.json`. No privileges (`sudo` / `pkexec`) are required or used.

## License

[MIT](LICENSE) © 2026 Morganczech
