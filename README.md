# Omarchy Megamenu (`gruut.megamenu`)

A theme-aware Spotlight-style megamenu and bar widget for [Omarchy](https://omarchy.org/) featuring workspaces (**Spaces**), a 6-slot **Quick Access Orbit**, color-coded categories, live **RSS/Atom & GitHub columns**, web bookmarks with automatic favicons, built-in **Omarchy system actions & desktop app search**, saved **shell commands**, per-link browser selection, and one-click browser bookmark importing.

![Omarchy Megamenu preview](preview.png)

## Features

- **Spaces (Workspaces for Links, Feeds & Apps):**
  - Organize your links, feeds, and apps into separate spaces (e.g. *Dev Matrix*, *Homelab & Infra*, *Live Pulse*, *Personal*) and switch between them with `Tab` / `Shift+Tab` or a click.
  - Create, rename, or delete spaces directly from the top bar.
- **Quick Access / Primary Orbit (`1–6`):**
  - Pin up to 6 of your most used web apps, Omarchy actions, local applications, or shell commands per space and launch them instantly with keys `1` through `6`.
- **Live Columns (RSS/Atom & GitHub Issues/PRs/Releases):**
  - Any category column can be configured as a **Static Bookmark list**, **RSS / Atom Feed**, or **GitHub Repository feed** (`owner/repo` or `@me` via `gh` CLI).
  - Includes a built-in **Live Pulse** showcase space (Hacker News, Omarchy GitHub activity, Tech News) and one-click `󰐃` pinning to save any live entry as a permanent bookmark.
- **Color-Coded Categories & Theme Integration:**
  - Automatically adapts to the active Omarchy light/dark theme (`Color`, `Style`, `Border`, and semantic ANSI colors from `colors.toml`: `blue`, `cyan`, `green`, `magenta`, `yellow`, `orange`, `red`).
  - Responsive category filter badges under the search bar that center on a single row and wrap cleanly when you have many categories.
- **Instant Search, Omarchy Spotlight Actions & Local App Launcher (`>`):**
  - Type anywhere to filter bookmarks and commands across **all Spaces** (matches from other spaces appear in dedicated columns) **and** simultaneously search native Omarchy system actions (`Style › Theme`, `Style › Background`, `System › Lock`, `Trigger › Capture › Screenshot`, `Setup › Monitors`, etc.) and installed `.desktop` applications.
  - Prefix your query with **`>`** (e.g. `> theme`, `> ghostty`, `> restic`) to open the dedicated full-width Omarchy actions, applications, and saved-commands view, or pin any action/app into a Megamenu category.
- **Frequent launches:**
  - Opening Megamenu with an empty search shows a **Frequent** strip of your most-used bookmarks, apps, and commands (ranked by launch count).
- **Shell commands:**
  - Add a command from the item dialog (`Ctrl+N`, then **Command**) into any category. Optional working directory, Orbit pin, and glyph icon work the same way as other items.
  - **Terminal** (default) opens the default Omarchy terminal via `xdg-terminal-exec`, runs the command with `bash -lc`, and waits for a key after it finishes. **Background** runs the same script with no window.
  - Find a saved command by its title or command text, including from `>`.
- **Reorder & Move Between Spaces:**
  - Hover ▲ / ▼ on a static bookmark to reorder it within its category (hidden while searching or filtering Favorites).
  - Move an item to another space and category from the edit modal or the context menu (**Move to…** → Space → category). Orbit pins clear when the space changes.
- **Right-Click Browser Chooser & Actions:**
  - Right-click any item (or press `Alt+M`) to open a context menu where you can launch a URL in **any installed browser** (Brave, Zen, Firefox, Chromium, Vivaldi, LibreWolf, etc.), copy the URL, Desktop ID, or command to the clipboard (`wl-copy`), edit, move, or delete the item.
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
| **Type text** | Filter bookmarks and commands across all Spaces (plus Omarchy actions / apps) |
| **`>` + query** | Search and launch Omarchy actions, installed applications, and saved commands |
| **`1` – `6`** | Launch pinned Quick Access Orbit slot `1–6` (when search is empty) |
| **`Tab` / `Shift+Tab`** | Switch to next / previous Space |
| **`↑` / `↓` / `←` / `→`** | Navigate items (or system apps in `>` mode) |
| **`Enter`** | Launch selected bookmark, command, or application |
| **`Right-Click` / `Alt+M`** | Open context menu (choose browser, copy URL, edit, delete) |
| **`Alt+E`** | Edit selected item |
| **`Ctrl+N`** | Add new bookmark, command, or local application |
| **`Esc`** | Close modal / context menu / Megamenu |

### Add a shell command

Megamenu stores the command text in your menu data. It does not create or keep a script file for you. Type a short command directly, or point at a script you have already saved.

1. Open Megamenu and press **`Ctrl+N`** (or **+ Item**).
2. Choose **Command**. In the Czech interface the button is **Příkaz**.
3. **Title** is the label shown in the menu, for example `Restic Backup`.
4. **Command** is what actually runs:
   - the name of a program already available in the terminal, such as `restic-backup`
   - or a single line, such as `notify-send "Backup finished"`
5. **Working directory** is optional. Set it when the command has to start inside a project, for example `pnpm dev` in `~/Work/my-app`.
6. Choose how it runs:
   - **Terminal** opens your usual terminal, runs the command, and keeps the window open until you press a key. Use this when you want to read the output.
   - **Background** runs the command with no window. Use this when there is nothing to read, such as a notification.
7. Pick a category. You can also pin an Orbit slot (`1`–`6`) and set an icon.
8. Save the item.

Click the item, press **Enter**, or press its Orbit key. You can also type **`>`** and part of the name, for example `> restic`. Right-click the item to copy the command text, edit it, or delete it.

A longer script is an ordinary file you save yourself, usually under `~/.local/bin/`, with the executable bit set. Megamenu then only needs that file's name in the **Command** field. `~/.local/bin` is on the terminal `PATH` in Omarchy, so the name alone is enough.

You can also ask an assistant in Omarchy to prepare the script and add the menu item. For a backup, the script file should contain the backup itself. Megamenu already keeps the terminal window open when **Terminal** is selected, so the script does not need its own "press a key" ending.

The assistant saves the file, marks it executable, then adds the menu entry. Close Megamenu before that write. Open it again afterwards.

```bash
install -m 755 ./restic-backup ~/.local/bin/restic-backup

python3 ~/.config/omarchy/plugins/gruut.megamenu/scripts/add-command.py \
  --title "Restic Backup" \
  --command restic-backup \
  --space "Home Lab" \
  --category General \
  --run terminal \
  --slot 3
```

`--space` and `--category` match the names you see in Megamenu. The same command and space are updated instead of added twice. `--run background` is the no-window choice. `--slot 0` leaves the Orbit pin unset.

## Requirements & Dependencies

- **Omarchy 4.x** (`quickshell` runtime, Hyprland, and `omarchy` CLI)
- **Standard system utilities included with Omarchy:**
  - `python3` (standard library `sqlite3`, `json`, `html.parser` for bookmark importing and opt-in shortcut management)
  - `curl` (caches website favicons into `~/.local/share/omarchy-megamenu/favicons/`)
  - `wl-copy` (copies URLs and Desktop IDs to the Wayland clipboard)
  - `xdg-open` and `gtk-launch` (launches URLs and `.desktop` applications)
  - `xdg-terminal-exec` (opens the default terminal for saved commands)
- **Data storage:** Bookmarks, categories, and saved commands stay on this computer in `~/.local/share/omarchy-megamenu/data.json`.

## License

[MIT](LICENSE) © 2026 Morganczech
