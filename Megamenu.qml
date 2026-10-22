import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Storage.js" as Storage
import "ThemePalette.js" as ThemePalette
import "I18n.js" as I18n

Item {
  id: root

  // Host-injected properties from omarchy-shell
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string envLocale: Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "en_US.UTF-8"
  readonly property string dataDir: homeDir + "/.local/share/omarchy-megamenu"
  readonly property string faviconsDir: dataDir + "/favicons"
  readonly property string pluginDir: homeDir + "/.config/omarchy/plugins/gruut.megamenu"
  readonly property string currentThemeColorsPath: homeDir + "/.local/state/omarchy/current/theme/colors.toml"

  property var noteFiles: []
  property string noteError: ""
  property bool pendingNewNote: false
  property var notesQueue: []
  property bool scanNotesOnOpen: false
  property var noteDraft: ({ path: "", text: "", frontmatter: "", mtime: 0, dirty: false })
  property int noteDraftToken: 0
  property bool noteReadOnly: false
  property bool noteEditorFocused: false

  property bool opened: false
  property bool dirReady: false
  property bool storageReady: false

  property var data: Storage.defaultData()
  property var palette: ThemePalette.defaultPalette()
  property var installedBrowsers: []
  property var bookmarkSources: []
  property bool scanningBookmarks: false
  property var cachedFaviconDomains: ({})
  property var hiddenDesktopIds: ({})
  property var appIconIndex: ({})
  property var pendingAppIconIndex: ({})
  property var omarchyMenuEntries: []
  property string payloadLanguageOverride: ""

  // Localization state
  readonly property string languagePref: {
    if (root.payloadLanguageOverride === "en" || root.payloadLanguageOverride === "cs") {
      return root.payloadLanguageOverride
    }
    return (root.data && root.data.language) ? String(root.data.language) : "auto"
  }
  readonly property string activeLang: I18n.resolveLang(root.languagePref, root.envLocale)

  function tr(key) {
    return I18n.t(root.activeLang, key)
  }

  function cycleLanguage() {
    var nextPref = I18n.nextLanguagePref(root.languagePref)
    root.payloadLanguageOverride = ""
    var next = Storage.cloneData(root.data)
    next.language = nextPref
    root.commitData(next)
  }

  // UI Filtering & Navigation state
  property string searchQuery: ""
  property string activeFilter: "all" // "all", "favorites", or categoryId
  property string selectedItemId: ""
  property int selectedAppIndex: 0
  property bool keyboardGridNavActive: false
  property string statusBannerText: ""

  // Context Menu & Spaces Dropdown state
  property bool contextMenuOpen: false
  property string contextMoveBrowseSpaceId: ""
  property var contextMenuItem: null
  property real contextMenuX: 0
  property real contextMenuY: 0
  property bool spacesDropdownOpen: false
  property real spacesDropdownX: 0
  property real spacesDropdownY: 0

  // Modals: "" | "editItem" | "editCategory" | "editSpace" | "importBookmarks"
  property string activeModal: ""

  // Edit Item Modal fields
  property string formItemId: ""
  property string formItemType: "url" // "url" | "app" | "command"
  property string formItemTitle: ""
  property string formItemSubtitle: ""
  property string formItemUrl: ""
  property string formItemDesktopId: ""
  property string formItemCommand: ""
  property string formItemCwd: ""
  property string formItemRunMode: "terminal" // "terminal" | "background"
  property string formItemCategoryId: ""
  property string formItemSpaceId: ""
  property string formItemOriginalSpaceId: ""
  property string formItemIconType: "favicon" // "favicon" | "glyph" | "system" | "monogram"
  property string formItemIconValue: ""
  property string formItemBadgeText: ""
  property string formItemColorRole: ""
  property int formItemPinnedSlot: 0
  property bool formItemFavorite: false
  property string formAppSearchQuery: ""

  // Edit Category Modal fields
  property string formCategoryId: ""
  property string formCategoryName: ""
  property string formCategoryIcon: "󰉋"
  property string formCategoryColorRole: "blue"
  property string formCategoryType: "static" // "static" | "rss" | "github"
  property string formCategoryFeedUrl: ""
  property string formCategoryFeedMode: "all" // "all" | "issues" | "prs" | "releases"

  // Live Feeds state
  property var liveFeedsMap: ({})
  property bool fetchingLiveFeeds: false
  readonly property int livePageSize: 12
  property var liveVisibleLimits: ({})

  // Edit Space Modal fields
  property string formSpaceId: ""
  property string formSpaceName: ""
  property string formSpaceIcon: "󰀻"

  // Import Bookmarks Modal state
  property int selectedSourceIndex: 0
  property var selectedFoldersMap: ({})

  // Global Shortcut Modal state (strictly opt-in; read-only status check on startup)
  property string currentGlobalShortcut: ""
  property bool browserHostRegistered: false
  property string formShortcutCombo: "SUPER + M"

  // Theme-bound surface tokens from qs.Commons
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  // Computed properties for current view
  readonly property string activeSpaceId: (root.data && root.data.activeSpaceId) ? root.data.activeSpaceId : "dev-matrix"
  readonly property var activeSpace: {
    var spaces = (root.data && root.data.spaces) ? root.data.spaces : []
    for (var i = 0; i < spaces.length; i++) {
      if (spaces[i] && spaces[i].id === root.activeSpaceId) return spaces[i]
    }
    return null
  }
  readonly property bool notesSpaceActive: !!(root.activeSpace && String(root.activeSpace.type || "") === "notes")
  readonly property var notesModel: root.buildNotesModel(root.data, root.noteFiles)
  readonly property var currentCategories: Storage.categoriesForSpace(root.data, root.activeSpaceId)
  readonly property var currentSpaceItems: Storage.itemsForSpace(root.data, root.activeSpaceId)
  readonly property var pinnedOrbit: Storage.pinnedOrbitForSpace(root.data, root.activeSpaceId)
  readonly property var filteredFlatItems: Storage.filterItems(root.data, root.activeSpaceId, root.activeFilter, root.searchQuery, root.liveFeedsMap)
  readonly property var frequentItems: Storage.frequentItems(root.data, 8)
  readonly property bool isCommandMode: root.searchQuery.trim().indexOf(">") === 0
  readonly property var matchedSystemApps: {
    if (!root.isCommandMode) return []
    var q = root.searchQuery.trim().slice(1).trim()
    var commandMatches = Storage.searchCommandItems(root.data, q, 20)
    var commandRows = []
    var spaces = (root.data && root.data.spaces) ? root.data.spaces : []
    for (var c = 0; c < commandMatches.length; c++) {
      var cmd = commandMatches[c]
      var spaceLabel = ""
      for (var s = 0; s < spaces.length; s++) {
        if (spaces[s].id === cmd.spaceId) {
          spaceLabel = spaces[s].name || ""
          break
        }
      }
      var cmdLabel = cmd.subtitle || cmd.command || ""
      commandRows.push({
        id: cmd.id,
        name: cmd.title,
        subtext: spaceLabel ? (spaceLabel + "  •  " + cmdLabel) : cmdLabel,
        entryKind: "command",
        icon: cmd.iconValue || "󰆍",
        commandItem: cmd
      })
    }
    var omarchyMatches = Storage.searchOmarchyMenuEntries(root.omarchyMenuEntries, q, 25)
    var values = (DesktopEntries && DesktopEntries.applications && DesktopEntries.applications.values)
      ? DesktopEntries.applications.values
      : []
    var appMatches = Storage.searchDesktopEntries(values, q, root.hiddenDesktopIds, 40)
    return commandRows.concat(omarchyMatches).concat(appMatches)
  }
  readonly property var searchSystemColumnItems: {
    if (root.isCommandMode) return []
    var q = root.searchQuery.trim()
    if (!q) return []
    var omarchyMatches = Storage.searchOmarchyMenuEntries(root.omarchyMenuEntries, q, 10)
    var values = (DesktopEntries && DesktopEntries.applications && DesktopEntries.applications.values)
      ? DesktopEntries.applications.values
      : []
    var appMatches = Storage.searchDesktopEntries(values, q, root.hiddenDesktopIds, 8)
    var items = []
    for (var i = 0; i < omarchyMatches.length; i++) {
      var om = omarchyMatches[i]
      items.push({
        id: "sys_omarchy_" + om.menuId,
        spaceId: root.activeSpaceId,
        categoryId: "__omarchy_system__",
        type: "app",
        title: om.name,
        subtitle: om.subtext,
        url: "",
        desktopId: om.id,
        omarchyAction: om.action || "",
        omarchyMenuId: om.menuId || "",
        iconType: "glyph",
        iconValue: om.icon || "󱓞",
        badgeText: om.omarchyKind === "menu" ? "MENU" : "OMARCHY",
        colorRole: "cyan",
        favorite: false,
        pinnedSlot: 0,
        isSystemResult: true
      })
    }
    for (var j = 0; j < appMatches.length; j++) {
      var ap = appMatches[j]
      items.push({
        id: "sys_app_" + ap.id,
        spaceId: root.activeSpaceId,
        categoryId: "__omarchy_system__",
        type: "app",
        title: ap.name,
        subtitle: ap.subtext || ap.id,
        url: "",
        desktopId: ap.id,
        iconType: "system",
        iconValue: ap.icon || "",
        badgeText: "APP",
        colorRole: "green",
        favorite: false,
        pinnedSlot: 0,
        isSystemResult: true
      })
    }
    return items
  }

  function resolveAppIconSource(icon) {
    var value = String(icon || "").trim()
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    if (root.appIconIndex && root.appIconIndex[value]) {
      return Util.fileUrl(root.appIconIndex[value])
    }
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function launchDesktopApp(desktopId, appName) {
    var raw = String(desktopId || "").trim()
    if (!raw) return
    if (raw.indexOf("omarchy:") === 0) {
      var menuId = raw.slice(8).trim()
      var entries = root.omarchyMenuEntries || []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === menuId) {
          if (entries[i].action) {
            Util.execDetached(entries[i].action)
            return
          }
          break
        }
      }
      if (root.shell && typeof root.shell.summon === "function") {
        root.shell.summon("omarchy.menu", JSON.stringify({ initialMenu: menuId }))
      } else {
        Util.execDetached("omarchy-shell shell summon omarchy.menu " + Util.shellQuote(JSON.stringify({ initialMenu: menuId })))
      }
      return
    }
    var id = Storage.normalizeDesktopId(raw)
    if (!id) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // Lifecycle methods invoked by omarchy-shell
  function open(payloadJson) {
    var action = ""
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p && (p.language === "en" || p.language === "cs")) {
        root.payloadLanguageOverride = p.language
      }
      if (p && p.action) action = String(p.action)
    } catch (e) {}
    if (action === "new-note") root.pendingNewNote = true
    // dataFile.reload() hydrates asynchronously. scanNotes() runs at the end
    // of that hydrate, including when the action is new-note.
    root.scanNotesOnOpen = true

    root.opened = true
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    root.activeModal = ""
    root.searchQuery = ""
    root.selectedAppIndex = 0
    if (searchInput) searchInput.text = ""
    themeColorsFile.reload()
    if (!appIconScanProc.running) appIconScanProc.running = true
    root.refreshBrowsers()
    root.applyGlobalShortcut("", "status")
    // Plugin stays loaded, so pick up pages saved by the browser host since the last open.
    // hydrateData() refreshes live feeds after the file loads.
    if (root.dirReady) dataFile.reload()
    else root.refreshLiveFeeds(false, "")
    root.refreshBrowserHostStatus()
    root.ensureSelectedValid()
    Qt.callLater(function() {
      if (searchInput) searchInput.forceActiveFocus()
    })
  }

  function close() {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    root.activeModal = ""
    root.opened = false
  }

  function dismiss() {
    root.finishNoteLeave(function () {
      root.close()
      if (root.shell && typeof root.shell.hide === "function") {
        root.shell.hide((root.manifest && root.manifest.id) || "gruut.megamenu")
      }
    })
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function ping() {
    return "ok"
  }

  function showStatus(msg) {
    root.statusBannerText = msg
    statusBannerTimer.restart()
  }

  function roleColor(role) {
    return ThemePalette.resolveRoleColor(root.palette, role, Color.accent)
  }

  function itemAccentColor(item, fallbackRole) {
    var explicitRole = item && item.colorRole ? String(item.colorRole).trim() : ""
    if (explicitRole.length > 0) {
      return root.roleColor(explicitRole)
    }
    if (item && item.categoryId && root.data && Array.isArray(root.data.categories)) {
      for (var i = 0; i < root.data.categories.length; i++) {
        var cat = root.data.categories[i]
        if (cat && cat.id === item.categoryId && cat.colorRole) {
          return root.roleColor(cat.colorRole)
        }
      }
    }
    if (fallbackRole) {
      return root.roleColor(fallbackRole)
    }
    return Color.accent
  }

  function faviconUrlFor(url) {
    var domain = Storage.extractDomain(url)
    if (!domain || !root.cachedFaviconDomains[domain]) return ""
    return "file://" + root.faviconsDir + "/" + domain + ".png"
  }

  function commitData(nextData) {
    root.data = nextData
    if (root.storageReady) {
      dataFile.setText(Storage.serialize(nextData))
    }
    root.ensureSelectedValid()
    root.queueMissingFavicons()
  }

  function reorderItemInCategory(itemId, direction) {
    if (!itemId) return
    var next = Storage.moveItemInCategory(root.data, itemId, direction)
    root.commitData(next)
  }

  function spaceNameKey(name) {
    return String(name || "").trim().toLowerCase()
  }

  function isReadingListSpace(space) {
    if (!space) return false
    if (space.id === "reading-list") return true
    var name = root.spaceNameKey(space.name)
    return name === "seznam čtení" || name === "reading list"
  }

  // Copy missing shipped spaces (and their categories) onto an existing data file.
  // Returns true when parsed was changed.
  function ensureSeedSpaces(parsed) {
    var def = Storage.defaultData()
    var seedIds = ["live-pulse", "reading-list"]
    var changed = false
    for (var si = 0; si < seedIds.length; si++) {
      var seedId = seedIds[si]
      var present = false
      for (var s = 0; s < parsed.spaces.length; s++) {
        var existing = parsed.spaces[s]
        if (existing.id === seedId || (seedId === "reading-list" && root.isReadingListSpace(existing))) {
          present = true
          break
        }
      }
      if (present) continue
      for (var ds = 0; ds < def.spaces.length; ds++) {
        if (def.spaces[ds].id === seedId) {
          parsed.spaces.push(def.spaces[ds])
          changed = true
        }
      }
      for (var dc = 0; dc < def.categories.length; dc++) {
        if (def.categories[dc].spaceId === seedId) {
          parsed.categories.push(def.categories[dc])
          changed = true
        }
      }
    }
    return changed
  }

  function hydrateData(rawText) {
    var hasExisting = rawText && String(rawText).trim().length > 0
    var parsed = Storage.parse(rawText)

    // Keep shipped spaces present for existing data files. A renamed reading list
    // (same id, or the name "Seznam čtení" / "Reading List") is left alone.
    if (hasExisting && root.ensureSeedSpaces(parsed)) {
      dataFile.setText(Storage.serialize(parsed))
    }

    root.data = parsed
    root.storageReady = true
    var notesMissing = !root.notesSpacePresent(root.data)
    root.data = Storage.ensureNotesModel(root.data, root.tr("notesInboxName"))
    if (notesMissing) root.commitData(root.data)
    else if (!hasExisting) dataFile.setText(Storage.serialize(root.data))
    root.ensureSelectedValid()
    root.queueMissingFavicons()
    root.refreshLiveFeeds(false, "")
    // open() sets the flag before reload(). Keep scanning while the menu is
    // open so a second load in the same open still refreshes the note list.
    if (root.opened || root.scanNotesOnOpen) {
      root.scanNotesOnOpen = false
      root.scanNotes()
    }
  }

  function notesSpacePresent(data) {
    var spaces = data && data.spaces ? data.spaces : []
    for (var i = 0; i < spaces.length; i++) {
      if (spaces[i] && String(spaces[i].id) === "notes") return true
    }
    return false
  }

  function runNotes(request, callback) {
    var queue = root.notesQueue ? root.notesQueue.slice() : []
    queue.push({ request: request, callback: callback })
    root.notesQueue = queue
    root.pumpNotes()
  }

  function pumpNotes() {
    if (notesProc.running) return
    var queue = root.notesQueue ? root.notesQueue.slice() : []
    if (!queue.length) return
    var job = queue.shift()
    root.notesQueue = queue
    notesProc.pendingCallback = job.callback
    var payload = JSON.stringify(job.request)
    notesProc.pendingStdin = payload ? payload : "{}"
    notesProc.stdinEnabled = true
    notesProc.running = true
  }

  function noteWriteRoots() {
    var notes = root.data && root.data.notes ? root.data.notes : { writeRoot: "", roots: [] }
    var roots = []
    if (notes.writeRoot) roots.push(notes.writeRoot)
    var extra = notes.roots || []
    for (var i = 0; i < extra.length; i++) {
      if (extra[i] && roots.indexOf(extra[i]) === -1) roots.push(extra[i])
    }
    return roots
  }

  function noteNamesInWriteRoot(writeRoot) {
    var rootPath = String(writeRoot || "").replace(/\/+$/, "")
    var names = []
    var seen = {}
    function consider(filePath) {
      var value = String(filePath || "")
      if (!value) return
      var slash = value.lastIndexOf("/")
      var dir = slash >= 0 ? value.slice(0, slash).replace(/\/+$/, "") : ""
      var name = slash >= 0 ? value.slice(slash + 1) : value
      if (dir !== rootPath || !name || seen[name]) return
      seen[name] = true
      names.push(name)
    }
    var files = root.noteFiles || []
    for (var i = 0; i < files.length; i++) consider(files[i] && files[i].path)
    var cards = (root.data && root.data.notes && root.data.notes.cards) ? root.data.notes.cards : []
    for (var c = 0; c < cards.length; c++) consider(cards[c] && cards[c].path)
    if (root.noteDraft && root.noteDraft.path) consider(root.noteDraft.path)
    return names
  }

  function emptyNoteDraft() {
    return { path: "", text: "", frontmatter: "", mtime: 0, dirty: false }
  }

  function clearNoteDraft() {
    root.noteReadOnly = false
    root.noteDraft = root.emptyNoteDraft()
  }

  function noteDraftNeedsSave() {
    var draft = root.noteDraft || {}
    return !!(draft.dirty && String(draft.text || "").trim())
  }

  function buildNotesModel(data, files) {
    var notes = data && data.notes ? data.notes : null
    var cards = notes && notes.cards ? notes.cards : []
    var incoming = files || []
    var byPath = {}
    for (var i = 0; i < incoming.length; i++) {
      var file = incoming[i]
      if (file && file.path) byPath[String(file.path)] = file
    }
    var out = []
    for (var c = 0; c < cards.length; c++) {
      var card = cards[c]
      if (!card || !card.path) continue
      var match = byPath[String(card.path)]
      if (!match) continue
      out.push({
        path: String(card.path),
        title: String(match.title || ""),
        badgeText: String(card.badgeText || ""),
        colorRole: String(card.colorRole || ""),
        categoryId: String(card.categoryId || ""),
        pinnedSlot: Math.round(Number(card.pinnedSlot) || 0),
        mtime: Number(match.mtime) || 0,
        tooLarge: match.tooLarge === true
      })
    }
    return out
  }

  function rememberWrittenNote(path, mtime, body) {
    var files = root.noteFiles ? root.noteFiles.slice() : []
    var title = Storage.noteListTitle(String(body || ""), "note")
    for (var i = 0; i < files.length; i++) {
      if (files[i] && String(files[i].path) === String(path)) {
        files[i] = {
          path: String(path),
          title: title,
          mtime: Number(mtime) || 0,
          size: Number(files[i].size) || 0,
          tooLarge: false
        }
        root.noteFiles = files
        return
      }
    }
    files.push({
      path: String(path),
      title: title,
      mtime: Number(mtime) || 0,
      size: 0,
      tooLarge: false
    })
    root.noteFiles = files
  }

  function applyNoteDraftText(text) {
    if (root.noteReadOnly) return
    var draft = root.noteDraft || root.emptyNoteDraft()
    if (String(draft.text || "") === String(text || "")) return
    root.noteDraft = {
      path: String(draft.path || ""),
      text: String(text || ""),
      frontmatter: String(draft.frontmatter || ""),
      mtime: Number(draft.mtime) || 0,
      dirty: true
    }
  }

  function saveCurrentNote(done) {
    var draft = root.noteDraft || root.emptyNoteDraft()
    var text = String(draft.text || "")
    if (!text.trim()) {
      if (root.noteReadOnly) {
        if (done) done(true)
        return
      }
      root.clearNoteDraft()
      if (done) done(true)
      return
    }
    var notes = root.data && root.data.notes ? root.data.notes : { writeRoot: "", roots: [] }
    var path = String(draft.path || "")
    var roots = root.noteWriteRoots()
    var frontmatter = String(draft.frontmatter || "")
    if (!path) {
      var writeRoot = String(notes.writeRoot || "")
      var filename = Storage.noteFilename(Storage.noteListTitle(text, "note"), root.noteNamesInWriteRoot(writeRoot))
      path = writeRoot.replace(/\/+$/, "") + "/" + filename
    }
    if (!path || !Storage.notePathAllowed(path, roots)) {
      root.showStatus(root.tr("notesSaveFailed"))
      if (done) done(false)
      return
    }
    var writtenText = text
    root.runNotes({
      cmd: "write",
      path: path,
      roots: roots,
      frontmatter: frontmatter,
      body: text
    }, function (res) {
      if (!res || !res.ok) {
        root.showStatus(root.tr("notesSaveFailed"))
        if (done) done(false)
        return
      }
      var current = root.noteDraft || root.emptyNoteDraft()
      var textNow = String(current.text || "")
      var sameBody = textNow === writtenText
      root.noteDraft = {
        path: String(res.path || path),
        text: textNow,
        frontmatter: String(current.frontmatter || frontmatter),
        mtime: Number(res.mtime) || 0,
        dirty: !sameBody
      }
      root.noteReadOnly = false
      root.rememberWrittenNote(root.noteDraft.path, root.noteDraft.mtime, writtenText)
      root.scanNotes()
      if (done) done(sameBody)
    })
  }

  function dropMissingNote(path) {
    var next = Storage.cloneData(root.data)
    if (!next.notes || typeof next.notes !== "object") {
      next.notes = { writeRoot: "", roots: [], cards: [] }
    }
    var cards = next.notes.cards || []
    var kept = []
    for (var i = 0; i < cards.length; i++) {
      if (cards[i] && String(cards[i].path) !== String(path)) kept.push(cards[i])
    }
    next.notes.cards = kept
    root.clearNoteDraft()
    root.commitData(next)
  }

  function selectNote(path) {
    path = String(path || "")
    if (!path) return
    function readIt() {
      var roots = root.noteWriteRoots()
      if (!Storage.notePathAllowed(path, roots)) {
        root.showStatus(root.tr("notesScanFailed"))
        return
      }
      root.noteDraftToken = root.noteDraftToken + 1
      var token = root.noteDraftToken
      root.runNotes({ cmd: "read", path: path, roots: roots }, function (res) {
        if (token !== root.noteDraftToken) return
        var draft = root.noteDraft || root.emptyNoteDraft()
        if (res && res.ok && res.tooLarge) {
          if (draft.dirty) return
          root.noteReadOnly = true
          root.noteDraft = {
            path: path,
            text: "",
            frontmatter: "",
            mtime: Number(res.mtime) || 0,
            dirty: false
          }
          return
        }
        if (!res || !res.ok) {
          var missing = !!(res && res.ok === false && String(res.error || "") === "missing")
          if (missing && !draft.dirty) {
            root.dropMissingNote(path)
            return
          }
          root.showStatus(root.tr("notesScanFailed"))
          return
        }
        if (draft.dirty) return
        root.noteReadOnly = false
        root.noteDraft = {
          path: path,
          text: String(res.body || ""),
          frontmatter: String(res.frontmatter || ""),
          mtime: Number(res.mtime) || 0,
          dirty: false
        }
      })
    }
    if (root.noteDraftNeedsSave()) {
      root.saveCurrentNote(function (ok) {
        if (!ok) return
        readIt()
      })
      return
    }
    readIt()
  }

  function beginNoteDraft() {
    var notes = root.data && root.data.notes ? root.data.notes : {}
    if (!String(notes.writeRoot || "")) {
      root.activeModal = "noteFolders"
      return
    }
    function openEmpty() {
      root.noteDraftToken = root.noteDraftToken + 1
      root.clearNoteDraft()
      Qt.callLater(function () {
        if (notePane) notePane.focusEditor()
      })
    }
    if (root.noteDraftNeedsSave()) {
      root.saveCurrentNote(function (ok) {
        if (!ok) return
        openEmpty()
      })
      return
    }
    openEmpty()
  }

  function finishNoteLeave(then) {
    if (!root.notesSpaceActive) {
      if (then) then()
      return
    }
    if (root.noteDraftNeedsSave()) {
      root.saveCurrentNote(function (ok) {
        if (ok && then) then()
      })
      return
    }
    var text = String((root.noteDraft && root.noteDraft.text) || "")
    if (!text.trim()) {
      root.noteDraftToken = root.noteDraftToken + 1
      root.clearNoteDraft()
    }
    if (then) then()
  }

  function scanNotes() {
    root.runNotes({ cmd: "scan", roots: root.noteWriteRoots() }, function (res) {
      if (!res || !res.ok) {
        root.noteError = root.tr("notesScanFailed")
        return
      }
      var merged = Storage.mergeNoteScan(root.data.notes, res.files || [], "cat-notes-inbox", res.truncated === true)
      root.data.notes = merged
      root.noteFiles = res.files || []
      root.noteError = (res.errors && res.errors.length) ? root.tr("notesRootSkipped") : ""
      root.commitData(root.data)
    })
  }

  function itemsForCategory(catOrId) {
    var catId = (catOrId && catOrId.id) ? catOrId.id : String(catOrId || "")
    var cat = (catOrId && catOrId.id) ? catOrId : null
    if ((cat && cat.type === "omarchy") || catId === "__omarchy_system__") {
      return root.searchSystemColumnItems || []
    }
    if (cat && cat.type === "other-space") {
      var sid = String(cat.spaceId || "")
      var allOther = root.filteredFlatItems || []
      var otherList = []
      for (var o = 0; o < allOther.length; o++) {
        if (allOther[o].spaceId === sid) otherList.push(allOther[o])
      }
      return otherList
    }
    var all = root.filteredFlatItems || []
    var list = []
    for (var i = 0; i < all.length; i++) {
      if (all[i].categoryId === catId) list.push(all[i])
    }
    return list
  }

  function otherSpaceCategoryEntries() {
    var q = String(root.searchQuery || "").trim()
    if (!q || root.isCommandMode) return []
    if (root.activeFilter !== "all" && root.activeFilter !== "favorites") return []
    var groups = Storage.otherSpaceSearchGroups(root.data, root.activeSpaceId, root.filteredFlatItems)
    var out = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      out.push({
        id: "__other_space__" + g.spaceId,
        spaceId: g.spaceId,
        name: g.name,
        icon: g.icon || "󰀻",
        colorRole: "magenta",
        type: "other-space"
      })
    }
    return out
  }

  function bumpLaunchStats(item) {
    if (!item || !item.id) return
    if (item.isSystemResult || item.isLiveItem || item.isLoadMore) return
    var next = Storage.recordLaunch(root.data, item.id)
    root.commitData(next)
  }

  function liveVisibleLimit(catId) {
    var limits = root.liveVisibleLimits || {}
    var n = Number(limits[catId] || 0)
    if (!isFinite(n) || n < root.livePageSize) return root.livePageSize
    return n
  }

  function loadMoreLive(catId) {
    if (!catId) return
    var full = root.itemsForCategory(catId)
    var current = root.liveVisibleLimit(catId)
    var limits = root.liveVisibleLimits || {}
    var next = {}
    var keys = Object.keys(limits)
    for (var i = 0; i < keys.length; i++) next[keys[i]] = limits[keys[i]]
    next[catId] = current + root.livePageSize
    root.liveVisibleLimits = next
    if (full.length > current && full[current] && full[current].id) {
      root.selectedItemId = full[current].id
    }
  }

  function visibleColumnItems(cat) {
    var list = root.itemsForCategory(cat)
    if (!cat) return list
    var isLive = cat.type === "rss" || cat.type === "github"
    if (!isLive || String(root.searchQuery || "").trim().length > 0) return list
    var limit = root.liveVisibleLimit(cat.id)
    if (list.length <= limit) return list
    var out = list.slice(0, limit)
    out.push({
      id: "__loadmore__" + cat.id,
      isLoadMore: true,
      categoryId: cat.id,
      title: root.tr("liveLoadMore")
    })
    return out
  }

  function buildVisibleCategoryColumns() {
    var cats = root.currentCategories || []
    var cols = []
    for (var c = 0; c < cats.length; c++) {
      var cat = cats[c]
      if (root.activeFilter !== "all" && root.activeFilter !== "favorites" && cat.id !== root.activeFilter) {
        continue
      }
      var colItems = root.visibleColumnItems(cat)
      if (colItems.length > 0) {
        cols.push({ category: cat, items: colItems })
      }
    }
    var otherCats = root.otherSpaceCategoryEntries()
    for (var o = 0; o < otherCats.length; o++) {
      var otherCat = otherCats[o]
      var otherItems = root.itemsForCategory(otherCat)
      if (otherItems.length > 0) {
        cols.push({ category: otherCat, items: otherItems })
      }
    }
    var sysItems = root.searchSystemColumnItems || []
    if (sysItems.length > 0) {
      cols.push({
        category: {
          id: "__omarchy_system__",
          name: root.tr("omarchyColumnName"),
          icon: "󱓞",
          colorRole: "cyan",
          type: "omarchy"
        },
        items: sysItems
      })
    }
    return cols
  }

  function ensureSelectedValid() {
    var cols = root.buildVisibleCategoryColumns()
    if (!cols || cols.length === 0) {
      root.selectedItemId = ""
      return
    }
    for (var c = 0; c < cols.length; c++) {
      var colItems = cols[c].items
      for (var r = 0; r < colItems.length; r++) {
        if (colItems[r].id === root.selectedItemId) return
      }
    }
    root.selectedItemId = cols[0].items[0].id
  }

  function selectDelta(delta) {
    var cols = root.buildVisibleCategoryColumns()
    if (!cols || cols.length === 0) return
    var foundCol = 0
    var foundRow = 0
    for (var c = 0; c < cols.length; c++) {
      var colItems = cols[c].items
      for (var r = 0; r < colItems.length; r++) {
        if (colItems[r].id === root.selectedItemId) {
          foundCol = c
          foundRow = r
          break
        }
      }
    }
    var targetList = cols[foundCol].items
    var nextRow = (foundRow + delta + targetList.length) % targetList.length
    root.selectedItemId = targetList[nextRow].id
  }

  function selectCategoryColumnDelta(colDelta) {
    var cats = root.currentCategories || []
    if (cats.length === 0) return

    // If a single category filter pill is active, Left/Right switches the active category filter
    if (root.activeFilter !== "all" && root.activeFilter !== "favorites") {
      var curCatIdx = 0
      for (var k = 0; k < cats.length; k++) {
        if (cats[k].id === root.activeFilter) {
          curCatIdx = k
          break
        }
      }
      var nextCatIdx = (curCatIdx + colDelta + cats.length) % cats.length
      root.activeFilter = cats[nextCatIdx].id
      root.ensureSelectedValid()
      return
    }

    var cols = root.buildVisibleCategoryColumns()
    if (!cols || cols.length === 0) return
    var foundCol = 0
    var foundRow = 0
    for (var c = 0; c < cols.length; c++) {
      var colItems = cols[c].items
      for (var r = 0; r < colItems.length; r++) {
        if (colItems[r].id === root.selectedItemId) {
          foundCol = c
          foundRow = r
          break
        }
      }
    }
    var nextCol = (foundCol + colDelta + cols.length) % cols.length
    var nextColItems = cols[nextCol].items
    var clampedRow = Math.min(foundRow, nextColItems.length - 1)
    root.selectedItemId = nextColItems[clampedRow].id
  }

  function findItemById(itemId) {
    var list = (root.data && root.data.items) ? root.data.items : []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === itemId) return list[i]
    }
    var flat = root.filteredFlatItems || []
    for (var j = 0; j < flat.length; j++) {
      if (flat[j].id === itemId) return flat[j]
    }
    var sys = root.searchSystemColumnItems || []
    for (var k = 0; k < sys.length; k++) {
      if (sys[k].id === itemId) return sys[k]
    }
    return null
  }

  function pinLiveItemAsBookmark(liveItem) {
    if (!liveItem) return
    root.contextMenuOpen = false
    var cats = root.currentCategories
    var targetCatId = ""
    for (var i = 0; i < cats.length; i++) {
      if (!cats[i].type || cats[i].type === "static") {
        targetCatId = cats[i].id
        break
      }
    }
    if (!targetCatId && cats.length > 0) targetCatId = cats[0].id
    var isApp = (liveItem.type === "app")
    var next = Storage.upsertItem(root.data, {
      id: Storage.uid("item"),
      spaceId: root.activeSpaceId,
      categoryId: targetCatId,
      type: isApp ? "app" : "url",
      title: liveItem.title || "Saved Link",
      subtitle: liveItem.subtitle || "",
      url: isApp ? "" : (liveItem.url || ""),
      desktopId: isApp ? (liveItem.desktopId || "") : "",
      iconType: isApp ? (liveItem.iconType || "system") : "favicon",
      iconValue: liveItem.iconValue || (isApp ? "󱓞" : "󰑫"),
      badgeText: liveItem.badgeText || "",
      colorRole: liveItem.colorRole || (isApp ? "cyan" : "blue"),
      pinnedSlot: 0,
      favorite: true
    })
    root.commitData(next)
    root.showStatus(root.tr("statusLivePinned") + (liveItem.title || ""))
  }

  function refreshLiveFeeds(forceRefresh, singleCategoryId) {
    if (!root.dirReady || liveFeedFetchProc.running) return
    // prlimit --as caps helper address space (128 MiB) so a hostile feed
    // cannot exhaust shell-session memory via the Python helper.
    var args = [
      "prlimit",
      "--as=134217728",
      "python3",
      root.pluginDir + "/scripts/fetch-feeds.py",
      root.dataDir + "/data.json",
      root.dataDir + "/feeds-cache.json"
    ]
    if (forceRefresh) args.push("--force")
    if (singleCategoryId) args.push("--category=" + singleCategoryId)
    root.fetchingLiveFeeds = true
    liveFeedFetchProc.wasExplicitRefresh = (forceRefresh === true)
    liveFeedFetchProc.command = args
    liveFeedFetchProc.running = true
  }

  function switchSpace(spaceId) {
    if (!spaceId) return
    function go() {
      var next = Storage.cloneData(root.data)
      next.activeSpaceId = spaceId
      root.activeFilter = "all"
      root.contextMenuOpen = false
      root.spacesDropdownOpen = false
      root.commitData(next)
    }
    if (spaceId === root.activeSpaceId) {
      go()
      return
    }
    root.finishNoteLeave(go)
  }

  function cycleSpace(delta) {
    var spaces = (root.data && root.data.spaces) ? root.data.spaces : []
    if (spaces.length <= 1) return
    var idx = 0
    for (var i = 0; i < spaces.length; i++) {
      if (spaces[i].id === root.activeSpaceId) {
        idx = i
        break
      }
    }
    var nextIdx = (idx + delta + spaces.length) % spaces.length
    root.switchSpace(spaces[nextIdx].id)
  }

  // Launch actions
  function launchCommandItem(item) {
    if (!item || item.type !== "command") return
    var command = String(item.command || "").trim()
    if (!command) return
    var background = item.runMode === "background"
    var script = Storage.commandShellScript(item, background ? "" : root.tr("commandDonePrompt"))
    var title = String(item.title || "Megamenu").replace(/[\r\n]/g, " ")
    if (background) {
      Quickshell.execDetached(["setsid", "bash", "-lc", script])
      return
    }
    Quickshell.execDetached([
      "setsid", "uwsm-app", "--",
      "xdg-terminal-exec",
      "--app-id=org.omarchy.megamenu.command",
      "--title=" + title,
      "-e", "bash", "-lc", script
    ])
  }

  function launchSystemSearchEntry(entry) {
    if (!entry) return
    if (entry.entryKind === "command" && entry.commandItem) {
      root.launchItemDefault(entry.commandItem)
      return
    }
    root.dismiss()
    root.launchDesktopApp(entry.id, entry.name)
  }

  function launchItemDefault(item) {
    if (!item) return
    root.bumpLaunchStats(item)
    root.dismiss()
    if (item.type === "app") {
      root.launchDesktopApp(item.desktopId, item.title)
    } else if (item.type === "command") {
      root.launchCommandItem(item)
    } else if (item.url) {
      Quickshell.execDetached(["xdg-open", item.url])
    }
  }

  function launchItemInBrowser(item, browser) {
    if (!item || !item.url || !browser || !browser.exec) return
    root.bumpLaunchStats(item)
    root.dismiss()
    Util.execDetached("uwsm-app -- " + browser.exec + " " + Util.shellQuote(item.url))
  }

  function copyItemUrl(item) {
    if (!item) return
    var target = item.type === "url" ? item.url : (item.type === "command" ? item.command : item.desktopId)
    if (!target) return
    Quickshell.execDetached(["wl-copy", target])
    root.contextMenuOpen = false
    root.showStatus(root.tr("statusCopied") + target)
  }

  function closeContextMenu() {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    Qt.callLater(function() {
      if (root.activeModal === "" && searchInput) searchInput.forceActiveFocus()
    })
  }

  function openContextMenuFor(item, globalX, globalY) {
    if (!item) return
    root.spacesDropdownOpen = false
    root.contextMenuItem = item
    root.contextMoveBrowseSpaceId = ""
    var menuW = Style.space(260)
    var menuH = Style.space(250)
    var maxX = card.width - menuW - Style.space(12)
    var maxY = card.height - menuH - Style.space(12)
    root.contextMenuX = Math.max(Style.space(12), Math.min(maxX, globalX))
    root.contextMenuY = Math.max(Style.space(12), Math.min(maxY, globalY))
    root.contextMenuOpen = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmMoveItem(targetSpaceId, targetCategoryId) {
    var item = root.contextMenuItem
    if (!item || item.isLiveItem === true || item.isSystemResult === true) return
    var cats = Storage.staticCategoriesForSpace(root.data, targetSpaceId)
    if (!cats || cats.length === 0) {
      root.showStatus(root.tr("statusMoveFailed"))
      root.contextMenuOpen = false
      return
    }
    var catOk = false
    for (var i = 0; i < cats.length; i++) {
      if (cats[i].id === targetCategoryId) {
        catOk = true
        break
      }
    }
    if (!catOk) {
      root.showStatus(root.tr("statusMoveFailed"))
      root.contextMenuOpen = false
      return
    }
    var unchanged = item.spaceId === targetSpaceId && item.categoryId === targetCategoryId
    var next = Storage.moveItemToSpace(root.data, item.id, targetSpaceId, targetCategoryId)
    root.contextMenuOpen = false
    root.contextMoveBrowseSpaceId = ""
    if (unchanged) return
    root.commitData(next)
    root.showStatus(root.tr("statusItemMoved") + (item.title || ""))
  }

  function toggleSpacesDropdown(anchorItem) {
    if (root.spacesDropdownOpen) {
      root.closeContextMenu()
      return
    }
    root.contextMenuOpen = false
    if (anchorItem) {
      var pos = anchorItem.mapToItem(card, 0, anchorItem.height + Style.space(6))
      var menuW = Style.space(250)
      var maxX = card.width - menuW - Style.space(12)
      root.spacesDropdownX = Math.max(Style.space(12), Math.min(maxX, pos.x))
      root.spacesDropdownY = Math.max(Style.space(44), pos.y)
    }
    root.spacesDropdownOpen = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function formCategoriesForSelectedSpace() {
    return Storage.staticCategoriesForSpace(root.data, root.formItemSpaceId || root.activeSpaceId)
  }

  function onFormSpaceChosen(spaceId) {
    if (!spaceId || spaceId === root.formItemSpaceId) return
    root.formItemSpaceId = spaceId
    var cats = root.formCategoriesForSelectedSpace()
    var stillValid = false
    for (var i = 0; i < cats.length; i++) {
      if (cats[i].id === root.formItemCategoryId) {
        stillValid = true
        break
      }
    }
    root.formItemCategoryId = stillValid ? root.formItemCategoryId : (cats.length ? cats[0].id : "")
    if (spaceId !== root.formItemOriginalSpaceId && root.formItemPinnedSlot > 0) {
      root.formItemPinnedSlot = 0
    }
  }

  // Modal openers
  function openAddItemModal(preselectedCategoryId, preselectedSlot) {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    var cats = root.currentCategories
    var defaultCat = preselectedCategoryId || (cats.length > 0 ? cats[0].id : "")
    root.formItemId = ""
    root.formItemType = "url"
    root.formItemTitle = ""
    root.formItemSubtitle = ""
    root.formItemUrl = "https://"
    root.formItemDesktopId = ""
    root.formItemCommand = ""
    root.formItemCwd = ""
    root.formItemRunMode = "terminal"
    root.formItemCategoryId = defaultCat
    root.formItemSpaceId = root.activeSpaceId
    root.formItemOriginalSpaceId = root.activeSpaceId
    root.formItemIconType = "favicon"
    root.formItemIconValue = ""
    root.formItemBadgeText = ""
    root.formItemColorRole = ""
    root.formItemPinnedSlot = preselectedSlot || 0
    root.formItemFavorite = false
    root.formAppSearchQuery = ""
    root.activeModal = "editItem"
    Qt.callLater(function() { itemTitleInput.forceActiveFocus() })
  }

  function openEditItemModal(item) {
    if (!item) return
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    var itType = item.type || "url"
    var customIcon = (itType === "url" && item.iconType !== "glyph") ? "" : String(item.iconValue || "").trim()
    root.formItemId = item.id
    root.formItemType = itType
    root.formItemTitle = item.title || ""
    root.formItemSubtitle = item.subtitle || ""
    root.formItemUrl = item.url || ""
    root.formItemDesktopId = item.desktopId || ""
    root.formItemCommand = item.command || ""
    root.formItemCwd = item.cwd || ""
    root.formItemRunMode = item.runMode === "background" ? "background" : "terminal"
    root.formItemCategoryId = item.categoryId || ""
    root.formItemSpaceId = item.spaceId || root.activeSpaceId
    root.formItemOriginalSpaceId = root.formItemSpaceId
    root.formItemIconValue = customIcon
    root.formItemIconType = (itType === "url")
      ? (customIcon.length > 0 ? "glyph" : "favicon")
      : (itType === "command" ? "glyph" : (item.iconType || "system"))
    root.formItemBadgeText = item.badgeText || ""
    root.formItemColorRole = item.colorRole || ""
    root.formItemPinnedSlot = item.pinnedSlot || 0
    root.formItemFavorite = item.favorite === true
    root.formAppSearchQuery = ""
    root.activeModal = "editItem"
    Qt.callLater(function() { itemTitleInput.forceActiveFocus() })
  }

  function saveItemModal() {
    var title = root.formItemTitle.trim()
    if (!title) {
      root.showStatus(root.tr("statusEnterItemTitle"))
      return
    }
    if (root.formItemType === "command" && !root.formItemCommand.trim()) {
      root.showStatus(root.tr("statusEnterCommand"))
      return
    }
    var formCats = root.formCategoriesForSelectedSpace()
    var catValid = false
    for (var fc = 0; fc < formCats.length; fc++) {
      if (formCats[fc].id === root.formItemCategoryId) {
        catValid = true
        break
      }
    }
    if (!catValid) {
      root.showStatus(root.tr("statusMoveFailed"))
      return
    }
    var trimmedIcon = root.formItemIconValue.trim()
    var resolvedIconType = "system"
    if (root.formItemType === "url") {
      resolvedIconType = trimmedIcon.length > 0 ? "glyph" : "favicon"
    } else if (root.formItemType === "command") {
      resolvedIconType = "glyph"
      if (!trimmedIcon) trimmedIcon = "󰆍"
    }
    var payload = {
      id: root.formItemId || Storage.uid("item"),
      spaceId: root.formItemSpaceId || root.activeSpaceId,
      categoryId: root.formItemCategoryId,
      type: root.formItemType,
      title: title,
      subtitle: root.formItemSubtitle.trim(),
      url: root.formItemType === "url" ? root.formItemUrl.trim() : "",
      desktopId: root.formItemType === "app" ? root.formItemDesktopId.trim() : "",
      command: root.formItemType === "command" ? root.formItemCommand.trim() : "",
      cwd: root.formItemType === "command" ? root.formItemCwd.trim() : "",
      runMode: root.formItemType === "command" && root.formItemRunMode === "background" ? "background" : "terminal",
      iconType: resolvedIconType,
      iconValue: trimmedIcon,
      badgeText: root.formItemBadgeText.trim(),
      colorRole: root.formItemColorRole,
      pinnedSlot: root.formItemPinnedSlot,
      favorite: root.formItemFavorite
    }
    var next = Storage.upsertItem(root.data, payload)
    root.activeModal = ""
    root.commitData(next)
    root.showStatus(root.tr("statusItemSaved") + title)
  }

  function openCategoryModal(categoryObj) {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    if (categoryObj && categoryObj.id) {
      root.formCategoryId = categoryObj.id
      root.formCategoryName = categoryObj.name || ""
      root.formCategoryIcon = categoryObj.icon || "󰉋"
      root.formCategoryColorRole = categoryObj.colorRole || "blue"
      root.formCategoryType = categoryObj.type || "static"
      root.formCategoryFeedUrl = categoryObj.feedUrl || ""
      root.formCategoryFeedMode = categoryObj.feedMode || "all"
    } else {
      root.formCategoryId = ""
      root.formCategoryName = ""
      root.formCategoryIcon = "󰉋"
      root.formCategoryColorRole = "blue"
      root.formCategoryType = "static"
      root.formCategoryFeedUrl = ""
      root.formCategoryFeedMode = "all"
    }
    root.activeModal = "editCategory"
    Qt.callLater(function() { catNameInput.forceActiveFocus() })
  }

  function saveCategoryModal() {
    var name = root.formCategoryName.trim()
    if (!name) {
      root.showStatus(root.tr("statusEnterCategoryName"))
      return
    }
    var cid = root.formCategoryId || Storage.uid("cat")
    var ctype = root.formCategoryType || "static"
    var next = Storage.upsertCategory(root.data, {
      id: cid,
      spaceId: root.activeSpaceId,
      name: name,
      icon: root.formCategoryIcon.trim() || (ctype === "rss" ? "󰑫" : (ctype === "github" ? "󰊤" : "󰉋")),
      colorRole: root.formCategoryColorRole,
      type: ctype,
      feedUrl: root.formCategoryFeedUrl.trim(),
      feedMode: root.formCategoryFeedMode || "all"
    })
    root.activeModal = ""
    root.commitData(next)
    root.showStatus(root.tr("statusCategorySaved") + name)
    if (ctype === "rss" || ctype === "github") {
      Qt.callLater(function() { root.refreshLiveFeeds(true, cid) })
    }
  }

  function openSpaceModal(spaceObj) {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    if (spaceObj && spaceObj.id) {
      root.formSpaceId = spaceObj.id
      root.formSpaceName = spaceObj.name || ""
      root.formSpaceIcon = spaceObj.icon || "󰀻"
    } else {
      root.formSpaceId = ""
      root.formSpaceName = ""
      root.formSpaceIcon = "󰀻"
    }
    root.activeModal = "editSpace"
    Qt.callLater(function() { spaceNameInput.forceActiveFocus() })
  }

  function saveSpaceModal() {
    var name = root.formSpaceName.trim()
    if (!name) {
      root.showStatus(root.tr("statusEnterSpaceName"))
      return
    }
    var next = Storage.upsertSpace(root.data, {
      id: root.formSpaceId || Storage.uid("space"),
      name: name,
      icon: root.formSpaceIcon.trim() || "󰀻"
    })
    root.activeModal = ""
    root.commitData(next)
    root.showStatus(root.tr("statusSpaceSaved") + name)
  }

  function openImportBookmarksModal() {
    root.contextMenuOpen = false
    root.spacesDropdownOpen = false
    root.activeModal = "importBookmarks"
    root.scanningBookmarks = true
    bookmarkScanProc.running = false
    bookmarkScanProc.running = true
  }

  function confirmImportBookmarks() {
    if (!root.bookmarkSources || root.bookmarkSources.length === 0) return
    var src = root.bookmarkSources[root.selectedSourceIndex]
    if (!src || !Array.isArray(src.folders)) return
    var chosen = []
    for (var i = 0; i < src.folders.length; i++) {
      var key = src.id + "::" + i
      if (root.selectedFoldersMap[key] !== false) {
        chosen.push(src.folders[i])
      }
    }
    if (chosen.length === 0) {
      root.showStatus(root.tr("statusNoFolderSelected"))
      return
    }
    var next = Storage.mergeImportedFolders(root.data, root.activeSpaceId, chosen)
    root.activeModal = ""
    root.commitData(next)
    root.showStatus(root.tr("statusBookmarksImported"))
  }

  function openShortcutModal() {
    root.closeContextMenu()
    root.formShortcutCombo = root.currentGlobalShortcut || "SUPER + M"
    root.activeModal = "shortcut"
  }

  function refreshBrowserHostStatus() {
    if (browserHostProc.running) return
    browserHostProc.pendingMode = "status"
    browserHostProc.command = [
      "python3",
      root.pluginDir + "/scripts/install-browser-host.py",
      "--status",
      "--firefox-only",
      "--json"
    ]
    browserHostProc.running = true
  }

  function registerBrowserHost() {
    if (browserHostProc.running && browserHostProc.pendingMode === "register") return
    browserHostProc.pendingMode = "register"
    browserHostProc.command = [
      "python3",
      root.pluginDir + "/scripts/install-browser-host.py",
      "--firefox-only",
      "--json"
    ]
    browserHostProc.running = true
  }

  function applyGlobalShortcut(comboValue, mode) {
    shortcutManageProc.pendingMode = mode || "replace"
    shortcutManageProc.command = [
      "python3",
      root.pluginDir + "/scripts/manage-shortcut.py",
      shortcutManageProc.pendingMode,
      String(comboValue || "")
    ]
    shortcutManageProc.running = true
  }

  // Helper script invocations
  function refreshBrowsers() {
    if (!browserDetectProc.running) {
      browserDetectProc.running = true
    }
  }

  function queueMissingFavicons() {
    if (!root.dirReady) return
    if (faviconFetchProc.running) {
      faviconFetchProc.rerunAfterExit = true
      return
    }
    var rawItems = (root.data && root.data.items) ? root.data.items : []
    var ordered = []
    for (var a = 0; a < rawItems.length; a++) {
      if (rawItems[a].spaceId === root.activeSpaceId) ordered.push(rawItems[a])
    }
    for (var b = 0; b < rawItems.length; b++) {
      if (rawItems[b].spaceId !== root.activeSpaceId) ordered.push(rawItems[b])
    }
    var feedKeys = Object.keys(root.liveFeedsMap || {})
    for (var k = 0; k < feedKeys.length; k++) {
      var fobj = root.liveFeedsMap[feedKeys[k]]
      var fitems = (fobj && Array.isArray(fobj.items)) ? fobj.items : []
      for (var m = 0; m < fitems.length; m++) ordered.push(fitems[m])
    }

    var domains = {}
    var cmd = [root.pluginDir + "/scripts/fetch-favicon.sh", root.faviconsDir, "--list-existing"]
    var missingCount = 0
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].type === "url" && ordered[i].url) {
        var d = Storage.extractDomain(ordered[i].url)
        if (d && !domains[d] && !root.cachedFaviconDomains[d]) {
          domains[d] = true
          cmd.push(d)
          missingCount++
          if (missingCount >= 40) break
        }
      }
    }
    if (missingCount > 0 || Object.keys(root.cachedFaviconDomains || {}).length === 0) {
      faviconFetchProc.rerunAfterExit = false
      faviconFetchProc.command = cmd
      faviconFetchProc.running = true
    }
  }

  // Keyboard Navigation
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (root.contextMenuOpen || root.spacesDropdownOpen) {
        root.closeContextMenu()
      } else if (root.activeModal !== "") {
        root.activeModal = ""
        Qt.callLater(function() { searchInput.forceActiveFocus() })
      } else if (root.searchQuery.length > 0) {
        root.searchQuery = ""
        searchInput.text = ""
        Qt.callLater(function() { searchInput.forceActiveFocus() })
      } else {
        root.dismiss()
      }
      event.accepted = true
      return
    }

    if (root.activeModal !== "") return

    // Quick Orbit [1-6] with Alt+1..6 or plain 1..6 when search input is empty.
    // A focused note editor keeps the digit. Orbit selection of a note is later.
    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
      if (root.noteEditorFocused) return
      var slotIdx = event.key - Qt.Key_1
      if (alt || (!searchInput.activeFocus) || (root.searchQuery.length === 0 && !ctrl)) {
        var orbitItem = root.pinnedOrbit[slotIdx]
        if (orbitItem) {
          root.launchItemDefault(orbitItem)
          event.accepted = true
          return
        }
      }
    }

    if (ctrl && event.key === Qt.Key_K) {
      searchInput.forceActiveFocus()
      searchInput.selectAll()
      event.accepted = true
      return
    }

    if (ctrl && event.key === Qt.Key_N) {
      if (root.notesSpaceActive) root.beginNoteDraft()
      else root.openAddItemModal("", 0)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Tab) {
      root.cycleSpace(1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Backtab) {
      root.cycleSpace(-1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down) {
      root.keyboardGridNavActive = true
      if (root.isCommandMode) {
        var appCountDown = root.matchedSystemApps.length
        if (appCountDown > 0) {
          root.selectedAppIndex = (root.selectedAppIndex + 1) % appCountDown
          if (sysAppsListView) sysAppsListView.positionViewAtIndex(root.selectedAppIndex, ListView.Contain)
        }
      } else {
        root.selectDelta(1)
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Up) {
      root.keyboardGridNavActive = true
      if (root.isCommandMode) {
        var appCountUp = root.matchedSystemApps.length
        if (appCountUp > 0) {
          root.selectedAppIndex = (root.selectedAppIndex - 1 + appCountUp) % appCountUp
          if (sysAppsListView) sysAppsListView.positionViewAtIndex(root.selectedAppIndex, ListView.Contain)
        }
      } else {
        root.selectDelta(-1)
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      if (!root.isCommandMode && (root.searchQuery.length === 0 || root.keyboardGridNavActive || alt || !searchInput.activeFocus)) {
        root.keyboardGridNavActive = true
        root.selectCategoryColumnDelta(event.key === Qt.Key_Right ? 1 : -1)
        event.accepted = true
        return
      }
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.isCommandMode && root.matchedSystemApps.length > 0) {
        var idx = Math.max(0, Math.min(root.selectedAppIndex, root.matchedSystemApps.length - 1))
        var sysApp = root.matchedSystemApps[idx]
        root.launchSystemSearchEntry(sysApp)
        event.accepted = true
        return
      }
      var selId = String(root.selectedItemId || "")
      if (selId.indexOf("__loadmore__") === 0) {
        root.loadMoreLive(selId.substring("__loadmore__".length))
        event.accepted = true
        return
      }
      var sel = root.findItemById(root.selectedItemId)
      if (sel) {
        root.launchItemDefault(sel)
        event.accepted = true
        return
      }
    }

    if (alt && event.key === Qt.Key_E) {
      var toEdit = root.findItemById(root.selectedItemId)
      if (toEdit) {
        root.openEditItemModal(toEdit)
        event.accepted = true
      }
      return
    }

    if (alt && event.key === Qt.Key_M) {
      var toMenu = root.findItemById(root.selectedItemId)
      if (toMenu) {
        root.openContextMenuFor(toMenu, card.width / 2 - Style.space(120), card.height / 2 - Style.space(80))
        event.accepted = true
      }
      return
    }
  }

  // Processes & File IO
  Process {
    id: mkdirProc
    // 0700 so feeds-cache.json (may contain private GitHub @me titles) is not world-traversable
    command: ["bash", "-c", "mkdir -p -- \"$1\" \"$2\" && chmod 700 -- \"$1\" \"$2\"", "megamenu-mkdir", root.dataDir, root.faviconsDir]
    running: false
    onExited: {
      root.dirReady = true
      root.refreshBrowsers()
    }
  }

  Process {
    id: browserDetectProc
    command: [root.pluginDir + "/scripts/detect-browsers.sh"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text.trim() || "[]")
          if (Array.isArray(parsed)) root.installedBrowsers = parsed
        } catch (e) {}
      }
    }
  }

  Process {
    id: faviconFetchProc
    property bool rerunAfterExit: false
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var map = {}
        for (var i = 0; i < lines.length; i++) {
          var d = lines[i].trim().toLowerCase()
          if (d) map[d] = true
        }
        root.cachedFaviconDomains = map
        if (faviconFetchProc.rerunAfterExit) {
          faviconFetchProc.rerunAfterExit = false
          Qt.callLater(function() { root.queueMissingFavicons() })
        }
      }
    }
  }

  Process {
    id: bookmarkScanProc
    command: ["python3", root.pluginDir + "/scripts/import-bookmarks.py", "--scan"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.scanningBookmarks = false
        try {
          var parsed = JSON.parse(text.trim() || "[]")
          if (Array.isArray(parsed)) {
            root.bookmarkSources = parsed
            root.selectedSourceIndex = 0
            var initialMap = {}
            for (var s = 0; s < parsed.length; s++) {
              var folders = parsed[s].folders || []
              for (var f = 0; f < folders.length; f++) {
                initialMap[parsed[s].id + "::" + f] = true
              }
            }
            root.selectedFoldersMap = initialMap
          }
        } catch (e) {
          root.bookmarkSources = []
        }
      }
    }
  }

  FileView {
    id: dataFile
    path: root.dirReady ? root.dataDir + "/data.json" : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.hydrateData(dataFile.text())
    onLoadFailed: root.hydrateData("")
  }

  FileView {
    id: feedsCacheFile
    path: root.dirReady ? root.dataDir + "/feeds-cache.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(feedsCacheFile.text() || "{}")
        if (parsed && typeof parsed.feeds === "object") {
          root.liveFeedsMap = Storage.sanitizeLiveFeedsMap(parsed.feeds)
          root.ensureSelectedValid()
          root.queueMissingFavicons()
        }
      } catch (e) {}
    }
  }

  Process {
    id: liveFeedFetchProc
    property bool wasExplicitRefresh: false
    running: false
    stdout: StdioCollector {
      id: liveFeedOut
      waitForEnd: true
    }
    onExited: {
      root.fetchingLiveFeeds = false
      var raw = String(liveFeedOut.text || "").trim()
      if (!raw) return
      try {
        var parsed = JSON.parse(raw)
        if (parsed && typeof parsed.feeds === "object") {
          root.liveFeedsMap = Storage.sanitizeLiveFeedsMap(parsed.feeds)
          root.ensureSelectedValid()
          root.queueMissingFavicons()
          if (liveFeedFetchProc.wasExplicitRefresh) {
            root.showStatus(root.tr("statusFeedsRefreshed"))
          }
        }
      } catch (e) {}
    }
  }

  Process {
    id: notesProc
    property var pendingCallback: null
    // JSON body prepared before running = true. Quickshell write() is a no-op
    // until the process exists, and notes.py's json.load needs EOF, so the
    // body is written and the channel closed once the process has started.
    property string pendingStdin: ""
    command: [
      "prlimit",
      "--as=134217728",
      "python3",
      root.pluginDir + "/scripts/notes.py"
    ]
    stdinEnabled: true
    running: false
    stdout: StdioCollector {
      id: notesOut
      waitForEnd: true
    }
    onStarted: {
      if (notesProc.pendingStdin.length > 0) {
        notesProc.write(notesProc.pendingStdin)
        notesProc.pendingStdin = ""
      }
      notesProc.stdinEnabled = false
    }
    onExited: {
      var raw = String(notesOut.text || "").trim()
      var res = null
      try {
        if (raw) res = JSON.parse(raw)
      } catch (e) {
        res = null
      }
      var cb = notesProc.pendingCallback
      notesProc.pendingCallback = null
      try {
        if (cb) cb(res)
      } finally {
        root.pumpNotes()
      }
    }
    onRunningChanged: {
      // FailedToStart never emits exited. A normal exit clears the callback first.
      if (notesProc.running || !notesProc.pendingCallback) return
      var cb = notesProc.pendingCallback
      notesProc.pendingCallback = null
      notesProc.pendingStdin = ""
      try {
        if (cb) cb(null)
      } finally {
        root.pumpNotes()
      }
    }
  }

  FileView {
    id: themeColorsFile
    path: root.currentThemeColorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.palette = ThemePalette.parseColorsToml(themeColorsFile.text())
    onFileChanged: reload()
  }

  FileView {
    id: launcherHidesFile
    path: (root.omarchyPath || "/usr/share/omarchy") + "/default/omarchy/launcher.hides"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var map = {}
      var lines = String(launcherHidesFile.text() || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var id = Storage.normalizeDesktopId(lines[i])
        if (id) map[id] = true
      }
      root.hiddenDesktopIds = map
    }
  }

  FileView {
    id: omarchyMenuFile
    path: (root.omarchyPath || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.omarchyMenuEntries = Storage.parseOmarchyMenuJsonc(omarchyMenuFile.text())
    }
  }

  Process {
    id: appIconScanProc
    command: [
      "bash", "-c",
      "dirs=\"$HOME/.icons $HOME/.local/share/icons\"; " +
      "IFS=\":\"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs=\"$dirs $d/icons\"; done; unset IFS; " +
      "for ext in svg png; do " +
      "  for base in $dirs; do " +
      "    [[ -d $base ]] && find \"$base\" \\( -path \"*/apps/*\" -o -path \"*/devices/*\" \\) -name \"*.$ext\" 2>/dev/null; " +
      "  done; " +
      "  find /usr/share/pixmaps -maxdepth 1 -name \"*.$ext\" 2>/dev/null; " +
      "done"
    ]
    running: false
    onStarted: root.pendingAppIconIndex = ({})
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!value) return
        var slash = value.lastIndexOf("/")
        var file = slash >= 0 ? value.slice(slash + 1) : value
        var dot = file.lastIndexOf(".")
        var name = dot > 0 ? file.slice(0, dot) : file
        if (name && root.pendingAppIconIndex[name] === undefined) {
          root.pendingAppIconIndex[name] = value
        }
      }
    }
    onExited: root.appIconIndex = root.pendingAppIconIndex
  }

  Timer {
    id: statusBannerTimer
    interval: 2800
    repeat: false
    onTriggered: root.statusBannerText = ""
  }

  Process {
    id: browserHostProc
    property string pendingMode: "status"
    running: false
    stdout: StdioCollector {
      id: browserHostOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: browserHostErr
      waitForEnd: true
    }
    onExited: {
      var raw = String(browserHostOut.text || "").trim()
      var res = null
      try {
        res = JSON.parse(raw)
      } catch (e) {}
      if (res && res.ok) {
        root.browserHostRegistered = res.registered === true
        if (browserHostProc.pendingMode === "register") {
          root.showStatus(root.tr("statusBrowserHostSaved"))
        }
        return
      }
      if (browserHostProc.pendingMode === "register") {
        var detail = (res && res.error) ? res.error : String(browserHostErr.text || "").trim()
        root.showStatus(root.tr("statusBrowserHostError") + (detail || "unknown error"))
      }
    }
  }

  Process {
    id: shortcutManageProc
    property string pendingMode: "status"
    running: false
    stdout: StdioCollector {
      id: shortcutManageOut
      waitForEnd: true
    }
    onExited: {
      var raw = String(shortcutManageOut.text || "").trim()
      if (!raw) return
      try {
        var res = JSON.parse(raw)
        if (res.ok) {
          root.currentGlobalShortcut = String(res.shortcut || "")
          if (shortcutManageProc.pendingMode !== "status") {
            root.activeModal = ""
            if (root.currentGlobalShortcut) {
              root.showStatus(root.tr("statusShortcutSaved") + root.currentGlobalShortcut)
            } else {
              root.showStatus(root.tr("statusShortcutRemoved"))
            }
          }
        } else if (res.error && shortcutManageProc.pendingMode !== "status") {
          root.showStatus(root.tr("statusShortcutError") + res.error)
        }
      } catch (e) {}
    }
  }

  Component.onCompleted: {
    mkdirProc.running = true
    appIconScanProc.running = true
    root.applyGlobalShortcut("", "status")
  }

  // Reusable Favicon / App / Glyph icon renderer
  component ItemIconBadge: Rectangle {
    id: badgeRoot
    property var itemData: null
    property string fallbackRole: ""
    property bool activeHighlight: false
    property int boxSize: Style.space(28)
    readonly property bool hasColorRole: Boolean(itemData && itemData.colorRole && String(itemData.colorRole).length > 0)
    readonly property color badgeAccent: root.itemAccentColor(itemData, fallbackRole)
    width: boxSize
    height: boxSize
    radius: Style.cornerRadius > 0 ? Math.max(4, Math.min(8, Style.cornerRadius)) : 4
    color: (hasColorRole || activeHighlight) ? Util.alpha(badgeAccent, 0.16) : Util.alpha(badgeAccent, 0.08)
    border.width: 1
    border.color: (hasColorRole || activeHighlight) ? Util.alpha(badgeAccent, 0.5) : Util.alpha(badgeAccent, 0.25)

    readonly property bool isApp: itemData && itemData.type === "app" && itemData.iconType !== "glyph"
    readonly property bool wantsFavicon: itemData && itemData.type === "url" && (itemData.iconType !== "glyph" || !itemData.iconValue)
    readonly property string faviconSource: wantsFavicon ? root.faviconUrlFor(itemData.url) : ""
    readonly property string appIconSource: (isApp && itemData.iconValue)
      ? root.resolveAppIconSource(itemData.iconValue)
      : ""

    Image {
      id: favImg
      anchors.centerIn: parent
      width: Math.round(badgeRoot.boxSize * 0.64)
      height: Math.round(badgeRoot.boxSize * 0.64)
      source: badgeRoot.isApp ? badgeRoot.appIconSource : badgeRoot.faviconSource
      visible: status === Image.Ready && (badgeRoot.wantsFavicon || badgeRoot.isApp)
      smooth: true
      asynchronous: true
    }

    Text {
      anchors.centerIn: parent
      visible: !favImg.visible
      text: {
        if (!badgeRoot.itemData) return "•"
        if (badgeRoot.itemData.iconValue && badgeRoot.itemData.iconType === "glyph") {
          return badgeRoot.itemData.iconValue
        }
        if (badgeRoot.itemData.iconValue && badgeRoot.itemData.iconValue.length <= 2) {
          return badgeRoot.itemData.iconValue
        }
        return Storage.monogramFor(badgeRoot.itemData.title, badgeRoot.itemData.url)
      }
      color: badgeRoot.badgeAccent
      font.family: root.fontFamily
      font.pixelSize: Math.round(badgeRoot.boxSize * 0.48)
      font.bold: true
    }
  }

  // Main Layer-Shell Window
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "gruut-megamenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: {
        if (root.contextMenuOpen || root.spacesDropdownOpen) {
          root.closeContextMenu()
        } else if (root.activeModal !== "") {
          root.activeModal = ""
          Qt.callLater(function() { searchInput.forceActiveFocus() })
        } else {
          root.dismiss()
        }
      }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1260), panel.width - Style.gapsOut * 4)
      height: Math.min(Style.space(820), panel.height - Style.gapsOut * 4)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          root.contextMenuOpen = false
          root.spacesDropdownOpen = false
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      Column {
        id: mainLayout
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ============================================================
        // 1. TOP HEADER BAR: Logo + Space Switcher + Action Controls
        // ============================================================
        Item {
          id: topHeader
          width: parent.width
          height: Style.space(40)

          // Brand / Core OS indicator
          Row {
            id: brandRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Rectangle {
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              color: root.roleColor("green")
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Omarchy"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              height: Style.space(20)
              width: coreBadgeLabel.implicitWidth + Style.space(12)
              radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius) : 3
              color: Util.alpha(root.foreground, 0.08)
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.2)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: coreBadgeLabel
                anchors.centerIn: parent
                text: "MEGAMENU"
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // Space Switcher Tabs + Overflow Dropdown ("▾ More")
          Rectangle {
            id: spaceSwitcherBar
            readonly property real maxAvailableWidth: Math.max(
              Style.space(240),
              topRightActions.x - brandRow.width - Style.spacing.md * 2
            )
            readonly property var allSpaces: (root.data && root.data.spaces) ? root.data.spaces : []
            readonly property bool hasOverflow: allSpaces.length > 4 || spacesFullRowWidth > maxAvailableWidth
            readonly property real spacesFullRowWidth: {
              var list = allSpaces
              var total = Style.space(44) // + button + padding
              for (var i = 0; i < list.length; i++) {
                var labelLen = String(list[i].name || "").length
                total += Math.min(Style.space(150), labelLen * Style.space(7.5) + Style.space(42))
              }
              return total
            }
            readonly property var visibleInlineSpaces: {
              var list = allSpaces
              if (!hasOverflow) return list
              var maxInline = 3
              var out = []
              var activeIncluded = false
              for (var i = 0; i < list.length && out.length < maxInline; i++) {
                out.push(list[i])
                if (list[i].id === root.activeSpaceId) activeIncluded = true
              }
              if (!activeIncluded && out.length > 0) {
                for (var j = 0; j < list.length; j++) {
                  if (list[j].id === root.activeSpaceId) {
                    out[out.length - 1] = list[j]
                    break
                  }
                }
              }
              return out
            }
            readonly property int hiddenSpacesCount: Math.max(0, allSpaces.length - visibleInlineSpaces.length)

            anchors.left: brandRow.right
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(36)
            width: Math.min(maxAvailableWidth, spacesRow.implicitWidth + Style.space(8))
            clip: true
            radius: Style.cornerRadius > 0 ? Math.max(4, Style.cornerRadius) : 4
            color: Util.alpha(root.foreground, 0.04)
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.14)

            Row {
              id: spacesRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              Repeater {
                model: spaceSwitcherBar.visibleInlineSpaces

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool isCurrent: modelData.id === root.activeSpaceId
                  height: Style.space(28)
                  width: spaceTabRow.implicitWidth + Style.space(16)
                  radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                  color: isCurrent
                    ? Util.alpha(root.roleColor("green"), 0.18)
                    : (spaceTabMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent")
                  border.width: isCurrent ? 1 : 0
                  border.color: Util.alpha(root.roleColor("green"), 0.55)

                  Row {
                    id: spaceTabRow
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Text {
                      text: modelData.icon || "󰀻"
                      color: isCurrent ? root.roleColor("green") : Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      width: Math.min(implicitWidth, Style.space(115))
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: isCurrent ? root.foreground : Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: isCurrent
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: spaceTabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton) {
                        root.openSpaceModal(modelData)
                      } else {
                        root.switchSpace(modelData.id)
                      }
                    }
                  }
                }
              }

              // Overflow Dropdown Trigger ("▾ +N" or "▾")
              Rectangle {
                id: spacesOverflowBtn
                visible: spaceSwitcherBar.hasOverflow || spaceSwitcherBar.allSpaces.length > 2
                height: Style.space(28)
                width: overflowBtnRow.implicitWidth + Style.space(14)
                radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                color: root.spacesDropdownOpen
                  ? Util.alpha(root.roleColor("cyan"), 0.22)
                  : (overflowBtnMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : Util.alpha(root.foreground, 0.04))
                border.width: root.spacesDropdownOpen || spaceSwitcherBar.hiddenSpacesCount > 0 ? 1 : 0
                border.color: root.spacesDropdownOpen
                  ? root.roleColor("cyan")
                  : Util.alpha(root.foreground, 0.22)

                Row {
                  id: overflowBtnRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    visible: spaceSwitcherBar.hiddenSpacesCount > 0
                    text: "+" + spaceSwitcherBar.hiddenSpacesCount
                    color: root.spacesDropdownOpen ? root.roleColor("cyan") : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: root.spacesDropdownOpen ? "▴" : "▾"
                    color: root.spacesDropdownOpen ? root.roleColor("cyan") : Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: overflowBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSpacesDropdown(spacesOverflowBtn)
                }
              }

              // + Add Space Button
              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                color: addSpaceMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "+"
                  color: Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                MouseArea {
                  id: addSpaceMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openSpaceModal(null)
                }
              }
            }
          }

          // Top Right Actions
          Row {
            id: topRightActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Button {
              text: "󰌌 " + (root.currentGlobalShortcut || root.tr("shortcutSetBtnLabel"))
              bordered: true
              tooltipText: root.tr("shortcutBtnTooltip")
              onClicked: root.openShortcutModal()
            }

            Button {
              text: root.browserHostRegistered ? root.tr("browserHostBtnOn") : root.tr("browserHostBtn")
              bordered: true
              tooltipText: root.browserHostRegistered
                ? root.tr("browserHostTooltipOn")
                : root.tr("browserHostTooltip")
              onClicked: root.registerBrowserHost()
            }

            Button {
              text: "󰗊 " + root.activeLang.toUpperCase() + (root.languagePref === "auto" ? " (A)" : "")
              bordered: true
              tooltipText: root.tr("langTooltip")
              onClicked: root.cycleLanguage()
            }

            Button {
              text: root.tr("addItemBtn")
              bordered: true
              tooltipText: root.tr("addItemTooltip")
              onClicked: {
                if (root.notesSpaceActive) root.beginNoteDraft()
                else root.openAddItemModal("", 0)
              }
            }

            Button {
              text: root.tr("addCategoryBtn")
              bordered: true
              tooltipText: root.tr("addCategoryTooltip")
              onClicked: root.openCategoryModal(null)
            }

            Button {
              text: root.tr("importBtn")
              bordered: true
              tooltipText: root.tr("importTooltip")
              onClicked: root.openImportBookmarksModal()
            }

            Button {
              text: "✕"
              bordered: true
              tooltipText: root.tr("closeTooltip")
              onClicked: root.dismiss()
            }
          }
        }

        // ============================================================
        // 2. SEARCH BAR & FILTER PILLS
        // ============================================================
        Column {
          id: searchSection
          width: parent.width
          spacing: Style.space(14)

          // Search Box Container
          Rectangle {
            width: Math.min(Style.space(760), parent.width)
            height: Style.space(44)
            anchors.horizontalCenter: parent.horizontalCenter
            radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
            color: Util.alpha(root.foreground, 0.04)
            border.width: searchInput.activeFocus ? 1.5 : 1
            border.color: searchInput.activeFocus
              ? root.roleColor("green")
              : Util.alpha(root.foreground, 0.22)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                text: "󰍉"
                color: root.roleColor("green")
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              TextInput {
                id: searchInput
                width: parent.width - Style.space(185)
                anchors.verticalCenter: parent.verticalCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                clip: true
                selectByMouse: true
                onTextChanged: {
                  root.keyboardGridNavActive = false
                  root.searchQuery = text
                  root.selectedAppIndex = 0
                  root.ensureSelectedValid()
                }
                Keys.onPressed: function(event) {
                  root.handleKey(event)
                }

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: root.tr("searchPlaceholder")
                  color: Util.alpha(root.foreground, 0.42)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  visible: !searchInput.text && !searchInput.PreeditText
                }
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Rectangle {
                  height: Style.space(24)
                  width: cmdPillLabel.implicitWidth + Style.space(12)
                  radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                  color: root.isCommandMode
                    ? Util.alpha(root.roleColor("green"), 0.22)
                    : Util.alpha(root.foreground, 0.07)
                  border.width: 1
                  border.color: root.isCommandMode
                    ? root.roleColor("green")
                    : Util.alpha(root.foreground, 0.16)

                  Text {
                    id: cmdPillLabel
                    anchors.centerIn: parent
                    text: "> apps"
                    color: root.isCommandMode ? root.roleColor("green") : Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.isCommandMode) {
                        searchInput.text = ""
                      } else {
                        searchInput.text = "> "
                        searchInput.forceActiveFocus()
                      }
                    }
                  }
                }

                Rectangle {
                  height: Style.space(24)
                  width: escLabel.implicitWidth + Style.space(12)
                  radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                  color: Util.alpha(root.foreground, 0.07)
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.16)

                  Text {
                    id: escLabel
                    anchors.centerIn: parent
                    text: "ESC"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // Filter Pills Container (Centered when fitting 1 row, wraps cleanly without horizontal overflow when many)
          Flickable {
            id: filterPillsScroll
            width: parent.width
            visible: !root.notesSpaceActive
            height: root.notesSpaceActive ? 0 : Math.min(filterPillsFlow.implicitHeight, Style.space(60))
            contentWidth: width
            contentHeight: filterPillsFlow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
              id: filterPillsFlow
              readonly property real singleRowWidth: {
                var kids = filterPillsFlow.visibleChildren
                var total = 0
                var count = 0
                for (var i = 0; i < kids.length; i++) {
                  var w = kids[i].width
                  if (w > 0) {
                    total += w
                    count++
                  }
                }
                if (count > 1) total += (count - 1) * filterPillsFlow.spacing
                return total
              }
              width: Math.min(filterPillsScroll.width, Math.max(1, singleRowWidth))
              x: Math.max(0, Math.round((filterPillsScroll.width - width) / 2))
              spacing: Style.space(8)

              // All Pill
              Rectangle {
                id: allPillRect
                readonly property bool active: root.activeFilter === "all"
                height: Style.space(26)
                width: allPillRow.implicitWidth + Style.space(18)
                radius: height / 2
                color: active ? Util.alpha(root.roleColor("green"), 0.18) : Util.alpha(root.foreground, 0.04)
                border.width: 1
                border.color: active ? root.roleColor("green") : Util.alpha(root.foreground, 0.14)

                Row {
                  id: allPillRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Rectangle {
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: root.roleColor("green")
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: root.tr("filterAll") + " (" + root.currentSpaceItems.length + ")"
                    color: allPillRect.active ? root.foreground : Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: allPillRect.active
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activeFilter = "all"
                }
              }

              // Favorites Pill
              Rectangle {
                id: favPillRect
                readonly property bool active: root.activeFilter === "favorites"
                readonly property int favCount: {
                  var c = 0
                  for (var i = 0; i < root.currentSpaceItems.length; i++) {
                    if (root.currentSpaceItems[i].favorite) c++
                  }
                  return c
                }
                height: Style.space(26)
                width: favPillText.implicitWidth + Style.space(18)
                radius: height / 2
                color: active ? Util.alpha(root.roleColor("yellow"), 0.18) : Util.alpha(root.foreground, 0.04)
                border.width: 1
                border.color: active ? root.roleColor("yellow") : Util.alpha(root.foreground, 0.14)

                Text {
                  id: favPillText
                  anchors.centerIn: parent
                  text: root.tr("filterFavorites") + " (" + favPillRect.favCount + ")"
                  color: favPillRect.active ? root.roleColor("yellow") : Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: favPillRect.active
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activeFilter = "favorites"
                }
              }

              // Category Filter Pills
              Repeater {
                model: root.currentCategories

                delegate: Rectangle {
                  id: catPillRect
                  required property var modelData
                  readonly property bool active: root.activeFilter === modelData.id
                  readonly property color catColor: root.roleColor(modelData.colorRole)
                  height: Style.space(26)
                  width: catPillRow.implicitWidth + Style.space(18)
                  radius: height / 2
                  color: active ? Util.alpha(catColor, 0.18) : Util.alpha(root.foreground, 0.04)
                  border.width: 1
                  border.color: active ? catColor : Util.alpha(root.foreground, 0.14)

                  Row {
                    id: catPillRow
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Rectangle {
                      width: Style.space(6)
                      height: Style.space(6)
                      radius: width / 2
                      color: catPillRect.catColor
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      width: Math.min(implicitWidth, Style.space(160))
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: catPillRect.active ? root.foreground : Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: catPillRect.active
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeFilter = (root.activeFilter === modelData.id ? "all" : modelData.id)
                  }
                }
              }
            }
          }
        }

        // ============================================================
        // 3a. FREQUENT (usage-ranked, empty search only)
        // ============================================================
        Column {
          id: frequentSection
          width: parent.width
          spacing: Style.space(6)
          visible: !root.isCommandMode
                   && !root.notesSpaceActive
                   && root.searchQuery.trim().length === 0
                   && root.frequentItems.length > 0

          Item {
            width: parent.width
            height: Style.space(18)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("frequentHeader")
              color: root.roleColor("yellow")
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Row {
            id: frequentRow
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.frequentItems

              delegate: Rectangle {
                required property var modelData
                readonly property color freqAccent: root.itemAccentColor(modelData, "yellow")
                width: Math.min(
                  Style.space(160),
                  Math.max(
                    Style.space(110),
                    (frequentRow.width - Style.space(8) * Math.max(0, root.frequentItems.length - 1)) / Math.max(1, root.frequentItems.length)
                  )
                )
                height: Style.space(40)
                radius: Style.cornerRadius > 0 ? Math.max(5, Style.cornerRadius - 1) : 5
                color: freqMouse.containsMouse
                  ? Util.alpha(freqAccent, 0.18)
                  : Util.alpha(root.foreground, 0.04)
                border.width: 1
                border.color: freqMouse.containsMouse
                  ? Util.alpha(freqAccent, 0.55)
                  : Util.alpha(root.foreground, 0.12)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  ItemIconBadge {
                    itemData: modelData
                    fallbackRole: "yellow"
                    activeHighlight: freqMouse.containsMouse
                    boxSize: Style.space(24)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    width: Math.max(Style.space(40), parent.width - Style.space(32))
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: modelData.title || ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                MouseArea {
                  id: freqMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      var pos = freqMouse.mapToItem(card, mouse.x, mouse.y)
                      root.openContextMenuFor(modelData, pos.x, pos.y)
                    } else {
                      root.launchItemDefault(modelData)
                    }
                  }
                }
              }
            }
          }
        }

        // ============================================================
        // 3. QUICK ACCESS / PRIMARY ORBIT [1 - 6]
        // ============================================================
        Column {
          id: orbitSection
          width: parent.width
          spacing: Style.space(6)
          visible: !root.isCommandMode && root.searchQuery.trim().length === 0

          Item {
            width: parent.width
            height: Style.space(20)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                text: root.tr("orbitHeader")
                color: root.roleColor("magenta")
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: root.tr("orbitSubheader")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                text: root.tr("localStorageBadge")
                color: root.roleColor("green")
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                width: Style.space(6)
                height: Style.space(6)
                radius: width / 2
                color: root.roleColor("green")
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          Row {
            id: orbitRow
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: 6

              delegate: Rectangle {
                required property int index
                readonly property var orbitItem: root.pinnedOrbit[index]
                readonly property color orbitAccent: orbitItem
                  ? root.itemAccentColor(orbitItem, "")
                  : Util.alpha(root.foreground, 0.2)
                width: (orbitRow.width - Style.space(10) * 5) / 6
                height: Style.space(76)
                radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
                color: orbitMouse.containsMouse
                  ? Util.alpha(orbitAccent, 0.16)
                  : Util.alpha(root.foreground, 0.035)
                border.width: orbitMouse.containsMouse ? 1.5 : 1
                border.color: orbitMouse.containsMouse
                  ? orbitAccent
                  : Util.alpha(root.foreground, 0.14)

                // Filled Orbit Card
                Item {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  visible: orbitItem !== null

                  // Top Row: Icon + Title/Domain + Shortcut badge [1..6]
                  Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Style.space(8)

                    ItemIconBadge {
                      itemData: orbitItem
                      activeHighlight: orbitMouse.containsMouse
                      boxSize: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      width: parent.width - Style.space(74)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 1

                      Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: orbitItem ? orbitItem.title : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: orbitItem ? (Storage.extractDomain(orbitItem.url) || orbitItem.subtitle) : ""
                        color: Color.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Rectangle {
                      width: Style.space(26)
                      height: Style.space(20)
                      radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                      color: Util.alpha(root.foreground, 0.08)
                      border.width: 1
                      border.color: Util.alpha(root.foreground, 0.16)
                      anchors.top: parent.top

                      Text {
                        anchors.centerIn: parent
                        text: "#" + (index + 1)
                        color: Color.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  // Bottom Row: Subtitle + Status Pill
                  Item {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Style.space(18)

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(65)
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: orbitItem ? orbitItem.subtitle : ""
                      color: Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Rectangle {
                      visible: orbitItem !== null && String(orbitItem.badgeText || "").length > 0
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      height: Style.space(18)
                      width: badgeTxt.implicitWidth + Style.space(10)
                      radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                      color: Util.alpha(orbitAccent, 0.18)
                      border.width: 1
                      border.color: Util.alpha(orbitAccent, 0.45)

                      Text {
                        id: badgeTxt
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: orbitItem ? orbitItem.badgeText : ""
                        color: orbitAccent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption - 1
                        font.bold: true
                      }
                    }
                  }
                }

                // Empty Orbit Slot placeholder
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  visible: orbitItem === null

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.tr("slotPrefix") + " [" + (index + 1) + "]"
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.tr("clickToPin")
                    color: Util.alpha(root.foreground, 0.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: orbitMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (!orbitItem) {
                      root.openAddItemModal("", index + 1)
                      return
                    }
                    if (mouse.button === Qt.RightButton) {
                      var pos = orbitMouse.mapToItem(card, mouse.x, mouse.y)
                      root.openContextMenuFor(orbitItem, pos.x, pos.y)
                    } else {
                      root.launchItemDefault(orbitItem)
                    }
                  }
                }
              }
            }
          }
        }

        // ============================================================
        // 4. MAIN BODY: Category Columns Grid OR System App Search
        // ============================================================
        Item {
          id: gridContainer
          width: parent.width
          height: parent.height
                  - topHeader.height
                  - searchSection.height
                  - (frequentSection.visible ? frequentSection.height + Style.spacing.md : 0)
                  - (orbitSection.visible ? orbitSection.height + Style.spacing.md : 0)
                  - footerBar.height
                  - Style.spacing.md * 3

          // 4A. Category Columns Horizontal Flickable (Normal View)
          Flickable {
            id: categoriesFlick
            anchors.fill: parent
            visible: !root.isCommandMode && !root.notesSpaceActive
            contentWidth: categoriesRow.implicitWidth
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: categoriesRow
              height: parent.height
              spacing: Style.space(12)

              readonly property bool hasLiveCategories: {
                for (var i = 0; i < root.currentCategories.length; i++) {
                  var t = root.currentCategories[i].type
                  if (t === "rss" || t === "github") return true
                }
                return false
              }
              readonly property int maxVisibleCols: hasLiveCategories ? 2 : 4

              readonly property var activeCategoryList: {
                var baseList = []
                var searching = String(root.searchQuery || "").trim().length > 0 && !root.isCommandMode
                if (root.activeFilter !== "all" && root.activeFilter !== "favorites") {
                  for (var i = 0; i < root.currentCategories.length; i++) {
                    if (root.currentCategories[i].id === root.activeFilter) {
                      baseList.push(root.currentCategories[i])
                    }
                  }
                } else {
                  for (var j = 0; j < root.currentCategories.length; j++) {
                    baseList.push(root.currentCategories[j])
                  }
                }
                if (searching) {
                  var nonEmpty = []
                  for (var n = 0; n < baseList.length; n++) {
                    if (root.itemsForCategory(baseList[n]).length > 0) nonEmpty.push(baseList[n])
                  }
                  baseList = nonEmpty
                  var otherCats = root.otherSpaceCategoryEntries()
                  for (var o = 0; o < otherCats.length; o++) {
                    if (root.itemsForCategory(otherCats[o]).length > 0) baseList.push(otherCats[o])
                  }
                }
                if (root.searchSystemColumnItems && root.searchSystemColumnItems.length > 0) {
                  baseList.push({
                    id: "__omarchy_system__",
                    name: root.tr("omarchyColumnName"),
                    icon: "󱓞",
                    colorRole: "cyan",
                    type: "omarchy"
                  })
                }
                return baseList
              }

              Repeater {
                model: categoriesRow.activeCategoryList

                delegate: Rectangle {
                  id: catColumnCard
                  required property var modelData
                  readonly property bool isLiveCat: modelData.type === "rss" || modelData.type === "github"
                  readonly property bool isOmarchyCat: modelData.type === "omarchy"
                  readonly property bool isOtherSpaceCat: modelData.type === "other-space"
                  readonly property color catAccent: root.roleColor(modelData.colorRole)
                  readonly property var columnSourceItems: root.itemsForCategory(modelData)
                  readonly property var columnItems: root.visibleColumnItems(modelData)

                  readonly property int visibleColCount: Math.min(
                    categoriesRow.maxVisibleCols,
                    Math.max(1, categoriesRow.activeCategoryList.length)
                  )

                  width: Math.max(
                    isLiveCat ? Style.space(420) : Style.space(280),
                    (gridContainer.width - Style.space(12) * Math.max(0, visibleColCount - 1)) / visibleColCount
                  )
                  height: parent.height
                  radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
                  color: Util.alpha(root.foreground, 0.025)
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.14)
                  clip: true

                  // Colored Top Accent Line (from active Omarchy theme)
                  Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Style.space(3)
                    color: catColumnCard.catAccent
                  }

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    anchors.topMargin: Style.space(14)
                    spacing: Style.space(10)

                    // Category Column Header
                    Item {
                      width: parent.width
                      height: Style.space(26)

                      Item {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(Style.space(80), parent.width - catRightControls.width - Style.space(10))
                        height: parent.height

                        Row {
                          id: catHeaderRow
                          width: parent.width
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)

                          Text {
                            id: catIconText
                            text: modelData.icon || "󰉋"
                            color: catColumnCard.catAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            width: Math.min(
                              implicitWidth,
                              Math.max(
                                Style.space(50),
                                parent.width - catIconText.implicitWidth - (liveTypeBadge.visible ? liveTypeBadge.width + Style.space(16) : Style.space(8))
                              )
                            )
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: modelData.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Rectangle {
                            id: liveTypeBadge
                            visible: catColumnCard.isLiveCat || catColumnCard.isOtherSpaceCat
                            height: Style.space(16)
                            width: liveTypeTag.implicitWidth + Style.space(8)
                            radius: 3
                            color: Util.alpha(catColumnCard.catAccent, 0.2)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                              id: liveTypeTag
                              anchors.centerIn: parent
                              text: catColumnCard.isOtherSpaceCat
                                ? root.tr("otherSpaceBadge")
                                : (modelData.type === "github" ? "GH" : "RSS")
                              color: catColumnCard.catAccent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption - 2
                              font.bold: true
                            }
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          enabled: !catColumnCard.isOmarchyCat && !catColumnCard.isOtherSpaceCat
                          cursorShape: (catColumnCard.isOmarchyCat || catColumnCard.isOtherSpaceCat) ? Qt.ArrowCursor : Qt.PointingHandCursor
                          onClicked: {
                            if (!catColumnCard.isOmarchyCat && !catColumnCard.isOtherSpaceCat) root.openCategoryModal(modelData)
                          }
                        }
                      }

                      Row {
                        id: catRightControls
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)

                        Rectangle {
                          height: Style.space(20)
                          width: countLabel.implicitWidth + Style.space(12)
                          radius: height / 2
                          color: Util.alpha(catColumnCard.catAccent, 0.16)
                          border.width: 1
                          border.color: Util.alpha(catColumnCard.catAccent, 0.4)
                          anchors.verticalCenter: parent.verticalCenter

                          Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: I18n.formatItemsCount(root.activeLang, catColumnCard.columnSourceItems.length)
                            color: catColumnCard.catAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Rectangle {
                          visible: !catColumnCard.isOmarchyCat && !catColumnCard.isOtherSpaceCat
                          width: Style.space(22)
                          height: Style.space(20)
                          radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                          color: addInCatMouse.containsMouse ? Util.alpha(catColumnCard.catAccent, 0.22) : Util.alpha(root.foreground, 0.06)
                          anchors.verticalCenter: parent.verticalCenter

                          Text {
                            anchors.centerIn: parent
                            text: (modelData.type === "rss" || modelData.type === "github") ? "󰑐" : "+"
                            color: catColumnCard.catAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }

                          MouseArea {
                            id: addInCatMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (modelData.type === "rss" || modelData.type === "github") {
                                root.refreshLiveFeeds(true, modelData.id)
                              } else {
                                root.openAddItemModal(modelData.id, 0)
                              }
                            }
                          }

                          ToolTip.visible: addInCatMouse.containsMouse && (modelData.type === "rss" || modelData.type === "github")
                          ToolTip.text: root.tr("liveRefreshTooltip")
                        }
                      }
                    }

                    // Empty / Loading State for Live Feed Column
                    Text {
                      visible: (modelData.type === "rss" || modelData.type === "github") && catColumnCard.columnItems.length === 0
                      width: parent.width
                      wrapMode: Text.WordWrap
                      topPadding: Style.space(16)
                      horizontalAlignment: Text.AlignHCenter
                      text: root.fetchingLiveFeeds ? root.tr("liveFetchingText") : root.tr("liveEmptyText")
                      color: Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    // Items List inside Category Column
                    ListView {
                      id: catListView
                      width: parent.width
                      height: parent.height - Style.space(36)
                      clip: true
                      spacing: Style.space(6)
                      model: catColumnCard.columnItems
                      boundsBehavior: Flickable.StopAtBounds

                      readonly property int selectedIndexInColumn: {
                        var list = catColumnCard.columnItems
                        var selId = root.selectedItemId
                        if (!selId || !list) return -1
                        for (var i = 0; i < list.length; i++) {
                          if (list[i].id === selId) return i
                        }
                        return -1
                      }

                      onSelectedIndexInColumnChanged: {
                        if (selectedIndexInColumn >= 0) {
                          catListView.positionViewAtIndex(selectedIndexInColumn, ListView.Contain)
                          var colLeft = catColumnCard.x
                          var colRight = catColumnCard.x + catColumnCard.width
                          if (colLeft < categoriesFlick.contentX) {
                            categoriesFlick.contentX = colLeft
                          } else if (colRight > categoriesFlick.contentX + categoriesFlick.width) {
                            categoriesFlick.contentX = Math.max(0, colRight - categoriesFlick.width)
                          }
                        }
                      }

                      delegate: Rectangle {
                        id: itemRowRect
                        required property var modelData
                        required property int index
                        readonly property bool isLoadMore: modelData.isLoadMore === true
                        readonly property bool isSelected: root.selectedItemId === modelData.id
                        readonly property bool isHovered: rowMouse.containsMouse
                        readonly property color rowAccent: root.itemAccentColor(modelData, catColumnCard.modelData.colorRole)
                        readonly property bool isLiveEntry: modelData.isLiveItem === true

                        width: catListView.width
                        height: isLoadMore
                          ? Style.space(40)
                          : (isLiveEntry
                            ? Math.max(Style.space(58), itemTextCol.implicitHeight + Style.space(18))
                            : Style.space(52))
                        radius: Style.cornerRadius > 0 ? Math.max(5, Style.cornerRadius - 1) : 5
                        color: (isHovered || isSelected)
                          ? Util.alpha(rowAccent, 0.16)
                          : "transparent"
                        border.width: (isHovered || isSelected) ? 1 : 0
                        border.color: (isHovered || isSelected)
                          ? Util.alpha(rowAccent, 0.6)
                          : "transparent"

                        Text {
                          visible: itemRowRect.isLoadMore
                          anchors.centerIn: parent
                          text: modelData.title || root.tr("liveLoadMore")
                          color: (itemRowRect.isHovered || itemRowRect.isSelected) ? itemRowRect.rowAccent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        Row {
                          visible: !itemRowRect.isLoadMore
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(8)
                          anchors.rightMargin: Style.space(8)
                          spacing: Style.space(10)

                          ItemIconBadge {
                            itemData: modelData
                            fallbackRole: catColumnCard.modelData.colorRole || ""
                            activeHighlight: itemRowRect.isHovered || itemRowRect.isSelected
                            boxSize: Style.space(32)
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Column {
                            id: itemTextCol
                            width: Math.max(Style.space(80), parent.width - Style.space(42) - rowRightActions.width - Style.space(8))
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                              width: parent.width
                              wrapMode: itemRowRect.isLiveEntry ? Text.Wrap : Text.NoWrap
                              maximumLineCount: itemRowRect.isLiveEntry ? 2 : 1
                              elide: Text.ElideRight
                              textFormat: Text.PlainText
                              text: modelData.title
                              color: (itemRowRect.isHovered || itemRowRect.isSelected) ? itemRowRect.rowAccent : root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.bodySmall
                              font.bold: true
                            }

                            Row {
                              width: parent.width
                              spacing: Style.space(6)

                              Rectangle {
                                id: inlineItemTag
                                visible: modelData.type === "app" || modelData.type === "command" || String(modelData.badgeText || "").length > 0
                                height: Style.space(15)
                                width: appTagText.implicitWidth + Style.space(8)
                                radius: 3
                                color: Util.alpha(itemRowRect.rowAccent, 0.2)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                  id: appTagText
                                  anchors.centerIn: parent
                                  textFormat: Text.PlainText
                                  text: String(modelData.badgeText || (modelData.type === "app" ? "APP" : (modelData.type === "command" ? "CMD" : "")))
                                  color: itemRowRect.rowAccent
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption - 2
                                  font.bold: true
                                }
                              }

                              Text {
                                width: Math.max(
                                  Style.space(40),
                                  parent.width - (inlineItemTag.visible ? inlineItemTag.width + Style.space(6) : 0)
                                )
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: modelData.subtitle || Storage.extractDomain(modelData.url)
                                color: Color.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                              }
                            }
                          }
                        }

                        // Main Row Mouse Area (Left click: launch, Right click: context menu)
                        MouseArea {
                          id: rowMouse
                          anchors.fill: parent
                          anchors.rightMargin: itemRowRect.isLoadMore ? 0 : (rowRightActions.width + Style.space(10))
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          acceptedButtons: itemRowRect.isLoadMore ? Qt.LeftButton : (Qt.LeftButton | Qt.RightButton)
                          onEntered: root.selectedItemId = modelData.id
                          onClicked: function(mouse) {
                            root.selectedItemId = modelData.id
                            if (modelData.isLoadMore === true) {
                              root.loadMoreLive(modelData.categoryId)
                              return
                            }
                            if (mouse.button === Qt.RightButton) {
                              var pos = rowMouse.mapToItem(card, mouse.x, mouse.y)
                              root.openContextMenuFor(modelData, pos.x, pos.y)
                            } else {
                              root.launchItemDefault(modelData)
                            }
                          }
                        }

                        // Right Action Icons (Favorite Star + ⋮ Context Menu button)
                        Row {
                          id: rowRightActions
                          visible: !itemRowRect.isLoadMore
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(4)

                          // Reorder up/down (static items only, category columns only)
                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            visible: !itemRowRect.isLiveEntry
                              && !(modelData.isSystemResult === true)
                              && (itemRowRect.isHovered || itemRowRect.isSelected)
                              && itemRowRect.index > 0
                              && root.searchQuery.trim().length === 0
                              && root.activeFilter !== "favorites"
                            color: moveUpMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"

                            Text {
                              anchors.centerIn: parent
                              text: "▲"
                              color: Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                              id: moveUpMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.reorderItemInCategory(modelData.id, "up")
                            }
                          }

                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            visible: !itemRowRect.isLiveEntry
                              && !(modelData.isSystemResult === true)
                              && (itemRowRect.isHovered || itemRowRect.isSelected)
                              && itemRowRect.index < (catListView.count - 1)
                              && root.searchQuery.trim().length === 0
                              && root.activeFilter !== "favorites"
                            color: moveDownMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"

                            Text {
                              anchors.centerIn: parent
                              text: "▼"
                              color: Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                              id: moveDownMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.reorderItemInCategory(modelData.id, "down")
                            }
                          }

                          // Favorite Star Toggle (or Save Bookmark for Live Items)
                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            color: favMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
                            visible: itemRowRect.isHovered || itemRowRect.isSelected || modelData.favorite

                            Text {
                              anchors.centerIn: parent
                              text: (modelData.isLiveItem || modelData.isSystemResult) ? "󰐃" : (modelData.favorite ? "★" : "☆")
                              color: modelData.favorite ? root.roleColor("yellow") : Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.bodySmall
                            }

                            MouseArea {
                              id: favMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                if (modelData.isLiveItem || modelData.isSystemResult) {
                                  root.pinLiveItemAsBookmark(modelData)
                                } else {
                                  root.commitData(Storage.toggleFavorite(root.data, modelData.id))
                                }
                              }
                            }
                          }

                          // More (⋮) Context Menu Trigger
                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            color: dotsMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : Util.alpha(root.foreground, 0.05)

                            Text {
                              anchors.centerIn: parent
                              text: "⋮"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.bodySmall
                              font.bold: true
                            }

                            MouseArea {
                              id: dotsMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: function(mouse) {
                                var pos = dotsMouse.mapToItem(card, mouse.x, mouse.y)
                                root.openContextMenuFor(modelData, pos.x, pos.y)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          NotePane {
            id: notePane
            anchors.fill: parent
            visible: root.notesSpaceActive && !root.isCommandMode
            notesModel: root.notesModel
            categories: root.currentCategories
            filter: root.activeFilter
            draftText: root.noteDraft ? String(root.noteDraft.text || "") : ""
            currentPath: root.noteDraft && root.noteDraft.path ? String(root.noteDraft.path) : ""
            readOnly: root.noteReadOnly
            readOnlyMessage: root.noteReadOnly ? root.tr("notesTooLarge") : ""
            foldersLabel: root.tr("notesFoldersBtn")
            allLabel: root.tr("filterAll")
            foreground: root.foreground
            fontFamily: root.fontFamily
            searchField: searchInput
            roleColorFor: function (role) { return root.roleColor(role) }
            onNoteChosen: function (path) { root.selectNote(path) }
            onDraftEdited: function (text) { root.applyNoteDraftText(text) }
            onSaveRequested: function () { root.saveCurrentNote() }
            onFoldersRequested: root.activeModal = "noteFolders"
            onFilterRequested: function (id) { root.activeFilter = id }
            onEditorFocusedChanged: root.noteEditorFocused = editorFocused
          }

          // 4B. System Application Search View (when typing `> query`)
          Rectangle {
            anchors.fill: parent
            visible: root.isCommandMode
            radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
            color: Util.alpha(root.foreground, 0.03)
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.15)

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(16)
              spacing: Style.space(10)

              Text {
                text: root.tr("systemAppsHeader") + " (" + root.matchedSystemApps.length + ")"
                color: root.roleColor("green")
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Item {
                width: parent.width
                height: parent.height - Style.space(34)

                Text {
                  anchors.centerIn: parent
                  visible: root.matchedSystemApps.length === 0
                  text: root.tr("noAppsMatchedText")
                  color: Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                ListView {
                  id: sysAppsListView
                  anchors.fill: parent
                  visible: root.matchedSystemApps.length > 0
                  clip: true
                  spacing: Style.space(6)
                  model: root.matchedSystemApps

                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property string appName: modelData.name || modelData.id || ""
                    readonly property string appSub: modelData.subtext || modelData.id || ""
                    readonly property bool isOmarchyEntry: modelData.entryKind === "omarchy"
                    readonly property bool isCommandEntry: modelData.entryKind === "command"
                    readonly property bool showGlyph: isOmarchyEntry || isCommandEntry
                    readonly property color entryAccent: isCommandEntry
                      ? root.roleColor("yellow")
                      : (isOmarchyEntry ? root.roleColor("cyan") : root.roleColor("green"))
                    readonly property bool isSelected: index === root.selectedAppIndex
                    width: ListView.view.width
                    height: Style.space(46)
                    radius: 5
                    color: (sysAppMouse.containsMouse || isSelected)
                      ? Util.alpha(entryAccent, 0.16)
                      : Util.alpha(root.foreground, 0.03)
                    border.width: 1
                    border.color: (sysAppMouse.containsMouse || isSelected)
                      ? entryAccent
                      : Util.alpha(root.foreground, 0.1)

                    Row {
                      id: sysAppRow
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(12)
                      anchors.rightMargin: Style.space(12)
                      spacing: Style.space(12)

                      Item {
                        id: sysAppIconBox
                        width: Style.space(28)
                        height: Style.space(28)
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                          id: sysAppIconImg
                          anchors.fill: parent
                          source: showGlyph ? "" : root.resolveAppIconSource(modelData.icon || "")
                          smooth: true
                          visible: !showGlyph && status === Image.Ready
                        }

                        Rectangle {
                          anchors.fill: parent
                          radius: 5
                          visible: showGlyph || sysAppIconImg.status !== Image.Ready
                          color: Util.alpha(entryAccent, 0.2)
                          border.width: 1
                          border.color: Util.alpha(entryAccent, 0.45)

                          Text {
                            anchors.centerIn: parent
                            text: showGlyph
                              ? (modelData.icon || (isCommandEntry ? "󰆍" : "󱓞"))
                              : (appName.length > 0 ? appName.slice(0, 1).toUpperCase() : "A")
                            color: entryAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                        }
                      }

                      Column {
                        readonly property real pinWidth: pinBtn.visible ? pinBtn.implicitWidth : 0
                        readonly property real gaps: sysAppRow.spacing * (pinBtn.visible ? 2 : 1)
                        width: Math.max(Style.space(40), sysAppRow.width - sysAppIconBox.width - pinWidth - gaps)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: appName
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                          text: appSub || modelData.id
                          color: Color.muted
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Button {
                        id: pinBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !isCommandEntry
                        text: root.tr("pinToCategoryBtn")
                        bordered: true
                        onClicked: {
                          var cats = root.currentCategories
                          var targetCat = cats.length > 0 ? cats[0].id : ""
                          var next = Storage.upsertItem(root.data, {
                            spaceId: root.activeSpaceId,
                            categoryId: targetCat,
                            type: "app",
                            title: appName,
                            subtitle: appSub || modelData.id,
                            desktopId: modelData.id,
                            iconType: isOmarchyEntry ? "glyph" : "system",
                            iconValue: modelData.icon || (isOmarchyEntry ? "󱓞" : ""),
                            badgeText: isOmarchyEntry ? "OMARCHY" : "APP",
                            colorRole: isOmarchyEntry ? "cyan" : "green"
                          })
                          root.commitData(next)
                          root.showStatus(root.tr("statusAppPinned") + appName)
                        }
                      }
                    }

                    MouseArea {
                      id: sysAppMouse
                      anchors.fill: parent
                      anchors.rightMargin: pinBtn.visible ? pinBtn.implicitWidth + Style.space(12) : 0
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedAppIndex = index
                      onClicked: root.launchSystemSearchEntry(modelData)
                    }
                  }
                }
              }
            }
          }
        }

        // ============================================================
        // 5. FOOTER STATUS & SHORTCUTS BAR
        // ============================================================
        Rectangle {
          id: footerBar
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius > 0 ? Math.max(4, Style.cornerRadius - 2) : 4
          color: Util.alpha(root.foreground, 0.035)
          border.width: 1
          border.color: Util.alpha(root.foreground, 0.12)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Row {
              spacing: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                radius: width / 2
                color: root.roleColor("green")
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.statusBannerText !== ""
                  ? root.statusBannerText
                  : (root.tr("footerActiveSpace") + ": " + root.activeSpaceId.toUpperCase()
                     + "  |  " + root.tr("footerItems") + ": " + root.currentSpaceItems.length
                     + "  |  " + root.tr("footerBrowsers") + ": " + root.installedBrowsers.length)
                color: root.statusBannerText !== "" ? root.roleColor("green") : Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Text {
              text: root.tr("footerShortcuts")
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ============================================================
      // 6. FLOATING CONTEXT MENU & DROPDOWN BACKDROP + POPUPS
      // ============================================================
      MouseArea {
        id: popupDismissBackdrop
        anchors.fill: parent
        visible: root.contextMenuOpen || root.spacesDropdownOpen
        acceptedButtons: Qt.AllButtons
        z: 48
        onPressed: function(mouse) {
          root.closeContextMenu()
          mouse.accepted = true
        }
        onWheel: function(wheel) {
          root.closeContextMenu()
          wheel.accepted = true
        }
      }

      Rectangle {
        id: contextMenuPopup
        visible: root.contextMenuOpen && root.contextMenuItem !== null
        x: root.contextMenuX
        y: root.contextMenuY
        width: Style.space(264)
        height: Math.min(contextMenuCol.implicitHeight + Style.space(16),
                         Math.max(Style.space(120), card.height - root.contextMenuY - Style.space(12)))
        radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
        color: Color.popups.background
        border.width: 1.5
        border.color: Color.popups.border
        z: 50

        // Keep the popup on-card when its content (Move browse lists) grows.
        function reclampY() {
          var wantH = Math.min(contextMenuCol.implicitHeight + Style.space(16), card.height - Style.space(24))
          root.contextMenuY = Math.max(Style.space(12), Math.min(root.contextMenuY, card.height - wantH - Style.space(12)))
        }
        onVisibleChanged: if (visible) reclampY()

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Flickable {
          id: contextMenuFlick
          anchors.fill: parent
          anchors.margins: Style.space(8)
          clip: true
          contentWidth: width
          contentHeight: contextMenuCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

        Column {
          id: contextMenuCol
          width: parent.width
          spacing: Style.space(4)
          onImplicitHeightChanged: if (contextMenuPopup.visible) contextMenuPopup.reclampY()

          // Header: LAUNCH IN TARGET...
          Text {
            visible: root.contextMenuItem && root.contextMenuItem.type === "url"
            text: root.tr("ctxLaunchInTarget")
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - 1
            font.bold: true
            leftPadding: Style.space(8)
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)
          }

          // Installed Browsers List
          Repeater {
            model: (root.contextMenuItem && root.contextMenuItem.type === "url") ? root.installedBrowsers : []

            delegate: Rectangle {
              required property var modelData
              width: contextMenuCol.width
              height: Style.space(30)
              radius: 4
              color: browserItemMouse.containsMouse ? root.selectedBackground : "transparent"

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  text: "󰖟"
                  color: modelData.isDefault ? root.roleColor("green") : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.tr("ctxOpenIn") + modelData.name
                  color: browserItemMouse.containsMouse ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.isDefault
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Rectangle {
                visible: modelData.isDefault
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(18)
                width: defTxt.implicitWidth + Style.space(10)
                radius: 3
                color: Util.alpha(root.roleColor("green"), 0.18)

                Text {
                  id: defTxt
                  anchors.centerIn: parent
                  text: root.tr("ctxDefaultBadge")
                  color: root.roleColor("green")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                }
              }

              MouseArea {
                id: browserItemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchItemInBrowser(root.contextMenuItem, modelData)
              }
            }
          }

          // Launch local app option when item is an app
          Rectangle {
            visible: root.contextMenuItem && root.contextMenuItem.type === "app"
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: appLaunchCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("ctxLaunchApp")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: appLaunchCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchItemDefault(root.contextMenuItem)
            }
          }

          // Divider
          Rectangle {
            width: contextMenuCol.width
            height: 1
            color: Util.alpha(root.foreground, 0.14)
          }

          // Copy URL
          Rectangle {
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: copyCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.contextMenuItem && root.contextMenuItem.type === "app") return root.tr("ctxCopyDesktopId")
                if (root.contextMenuItem && root.contextMenuItem.type === "command") return root.tr("ctxCopyCommand")
                return root.tr("ctxCopyUrl")
              }
              color: copyCtxMouse.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: copyCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyItemUrl(root.contextMenuItem)
            }
          }

          // Save Live Item as Permanent Bookmark (only for Live Feed or Omarchy/App search items)
          Rectangle {
            visible: root.contextMenuItem !== null && (root.contextMenuItem.isLiveItem === true || root.contextMenuItem.isSystemResult === true)
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: pinLiveCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("ctxPinLiveItem")
              color: pinLiveCtxMouse.containsMouse ? root.selectedText : root.roleColor("green")
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: pinLiveCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pinLiveItemAsBookmark(root.contextMenuItem)
            }
          }

          // Edit Bookmark / Item (only for static bookmarks)
          Rectangle {
            visible: root.contextMenuItem === null || (root.contextMenuItem.isLiveItem !== true && root.contextMenuItem.isSystemResult !== true)
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: editCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("ctxEditItem")
              color: editCtxMouse.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "Alt+E"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: editCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openEditItemModal(root.contextMenuItem)
            }
          }

          // Move to… (two-step: spaces list, then categories)
          Rectangle {
            visible: root.contextMenuItem === null || (root.contextMenuItem.isLiveItem !== true && root.contextMenuItem.isSystemResult !== true)
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: moveCtxMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.contextMoveBrowseSpaceId === "" ? root.tr("ctxMoveTo") : root.tr("ctxMoveBack")
              color: moveCtxMouse.containsMouse ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: moveCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.contextMoveBrowseSpaceId !== "") {
                  root.contextMoveBrowseSpaceId = ""
                } else {
                  root.contextMoveBrowseSpaceId = "__pick__"
                }
              }
            }
          }

          // Space list (when picking)
          Repeater {
            model: {
              if (!root.contextMenuOpen || root.contextMoveBrowseSpaceId !== "__pick__") return []
              return (root.data && root.data.spaces) ? root.data.spaces : []
            }
            delegate: Rectangle {
              required property var modelData
              width: contextMenuCol.width
              height: Style.space(30)
              radius: 4
              color: spaceMoveMouse.containsMouse ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.icon || "󰀻") + "  " + modelData.name
                color: spaceMoveMouse.containsMouse ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: spaceMoveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.contextMoveBrowseSpaceId = modelData.id
              }
            }
          }

          // Category list for chosen space
          Repeater {
            model: {
              if (!root.contextMenuOpen || root.contextMoveBrowseSpaceId === "" || root.contextMoveBrowseSpaceId === "__pick__") return []
              return Storage.staticCategoriesForSpace(root.data, root.contextMoveBrowseSpaceId)
            }
            delegate: Rectangle {
              required property var modelData
              width: contextMenuCol.width
              height: Style.space(30)
              radius: 4
              color: catMoveMouse.containsMouse ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.icon || "󰉋") + "  " + modelData.name
                color: catMoveMouse.containsMouse ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: catMoveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmMoveItem(root.contextMoveBrowseSpaceId, modelData.id)
              }
            }
          }

          // Delete Item (only for static bookmarks)
          Rectangle {
            visible: root.contextMenuItem === null || (root.contextMenuItem.isLiveItem !== true && root.contextMenuItem.isSystemResult !== true)
            width: contextMenuCol.width
            height: Style.space(30)
            radius: 4
            color: delCtxMouse.containsMouse ? Util.alpha(Color.urgent, 0.18) : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("ctxDelete")
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: delCtxMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var target = root.contextMenuItem
                root.contextMenuOpen = false
                if (target) {
                  root.commitData(Storage.deleteItem(root.data, target.id))
                  root.showStatus(root.tr("statusItemDeleted") + target.title)
                }
              }
            }
          }
        }
        }
      }

      // ============================================================
      // 6B. FLOATING SPACES DROPDOWN MENU
      // ============================================================
      Rectangle {
        id: spacesDropdownPopup
        visible: root.spacesDropdownOpen
        x: root.spacesDropdownX
        y: root.spacesDropdownY
        width: Style.space(254)
        height: spacesDropdownCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
        color: Color.popups.background
        border.width: 1.5
        border.color: Color.popups.border
        z: 55

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: spacesDropdownCol
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(4)

          Text {
            text: root.tr("spacesDropdownHeader")
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - 1
            font.bold: true
            leftPadding: Style.space(8)
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)
          }

          Repeater {
            model: (root.data && root.data.spaces) ? root.data.spaces : []

            delegate: Rectangle {
              required property var modelData
              readonly property bool isCurrent: modelData.id === root.activeSpaceId
              width: spacesDropdownCol.width
              height: Style.space(32)
              radius: 4
              color: isCurrent
                ? Util.alpha(root.roleColor("green"), 0.18)
                : (spaceDropRowMouse.containsMouse ? root.selectedBackground : "transparent")
              border.width: isCurrent ? 1 : 0
              border.color: Util.alpha(root.roleColor("green"), 0.5)

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  text: modelData.icon || "󰀻"
                  color: isCurrent
                    ? root.roleColor("green")
                    : (spaceDropRowMouse.containsMouse ? root.selectedText : Color.muted)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: Style.space(155)
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: isCurrent
                    ? root.foreground
                    : (spaceDropRowMouse.containsMouse ? root.selectedText : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: isCurrent
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: spaceDropRowMouse
                anchors.fill: parent
                anchors.rightMargin: Style.space(34)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    root.openSpaceModal(modelData)
                  } else {
                    root.switchSpace(modelData.id)
                  }
                }
              }

              // Edit Space Icon Button
              Rectangle {
                width: Style.space(24)
                height: Style.space(24)
                radius: 4
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                color: editSpaceDropMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "󰏫"
                  color: editSpaceDropMouse.containsMouse ? root.foreground : Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: editSpaceDropMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openSpaceModal(modelData)
                }
              }
            }
          }

          Rectangle {
            width: spacesDropdownCol.width
            height: 1
            color: Util.alpha(root.foreground, 0.14)
          }

          Rectangle {
            width: spacesDropdownCol.width
            height: Style.space(30)
            radius: 4
            color: addSpaceDropMouse.containsMouse ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.tr("spacesAddAction")
              color: addSpaceDropMouse.containsMouse ? root.selectedText : root.roleColor("green")
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            MouseArea {
              id: addSpaceDropMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openSpaceModal(null)
            }
          }
        }
      }

      // ============================================================
      // 7. MODALS OVERLAY (Add/Edit Item, Category, Space, Import)
      // ============================================================
      Rectangle {
        anchors.fill: parent
        visible: root.activeModal !== ""
        color: Util.alpha(root.background, 0.78)
        radius: root.cornerRadius
        z: 100

        MouseArea {
          anchors.fill: parent
          onClicked: root.activeModal = ""
        }

        // ------------------------------------------------------------
        // MODAL A: Add / Edit Item (Web Link or Local App)
        // ------------------------------------------------------------
        BorderSurface {
          visible: root.activeModal === "editItem"
          width: Math.min(Style.space(560), parent.width - Style.space(40))
          height: itemModalCol.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          radius: root.cornerRadius
          color: Color.popups.background
          borderSpec: root.borderSpec
          padding: Style.space(18)

          MouseArea { anchors.fill: parent }

          Column {
            id: itemModalCol
            width: parent.width - Style.space(36)
            anchors.centerIn: parent
            spacing: Style.space(12)

            Text {
              text: root.formItemId !== "" ? root.tr("modalEditItemTitle") : root.tr("modalAddItemTitle")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            // Type Toggle: Web Link, Local App, or Command
            Row {
              spacing: Style.space(8)

              Button {
                text: root.tr("typeWebLink")
                bordered: true
                selected: root.formItemType === "url"
                onClicked: {
                  if (root.formItemIconValue.trim() === "󰆍") root.formItemIconValue = ""
                  root.formItemType = "url"
                  root.formItemIconType = root.formItemIconValue.trim().length > 0 ? "glyph" : "favicon"
                }
              }

              Button {
                text: root.tr("typeLocalApp")
                bordered: true
                selected: root.formItemType === "app"
                onClicked: {
                  if (root.formItemIconValue.trim() === "󰆍") root.formItemIconValue = ""
                  root.formItemType = "app"
                  root.formItemIconType = "system"
                }
              }

              Button {
                text: root.tr("typeCommand")
                bordered: true
                selected: root.formItemType === "command"
                onClicked: {
                  root.formItemType = "command"
                  root.formItemIconType = "glyph"
                  if (!root.formItemIconValue.trim()) root.formItemIconValue = "󰆍"
                }
              }
            }

            // Local App Picker (shown when type === "app")
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.formItemType === "app"

              Text {
                text: root.tr("pickInstalledAppLabel")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                width: parent.width
                placeholderText: root.tr("searchAppPlaceholder")
                text: root.formAppSearchQuery
                onTextChanged: root.formAppSearchQuery = text
              }

              Rectangle {
                width: parent.width
                height: Style.space(110)
                radius: 4
                color: Util.alpha(root.foreground, 0.04)
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.14)

                ListView {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  clip: true
                  model: {
                    var om = Storage.searchOmarchyMenuEntries(root.omarchyMenuEntries, root.formAppSearchQuery, 15)
                    var apps = Storage.searchDesktopEntries(
                      (DesktopEntries && DesktopEntries.applications && DesktopEntries.applications.values)
                        ? DesktopEntries.applications.values
                        : [],
                      root.formAppSearchQuery,
                      root.hiddenDesktopIds,
                      30
                    )
                    return om.concat(apps)
                  }

                  delegate: Rectangle {
                    required property var modelData
                    readonly property string entryTitle: modelData.name || modelData.id || ""
                    readonly property bool isOmarchyEntry: modelData.entryKind === "omarchy"
                    width: ListView.view.width
                    height: Style.space(26)
                    radius: 3
                    color: root.formItemDesktopId === modelData.id
                      ? Util.alpha(root.roleColor("green"), 0.22)
                      : (pickerItemMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent")

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(8)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      text: (isOmarchyEntry ? (modelData.icon + "  ") : "") + entryTitle + "  (" + (modelData.subtext || modelData.id) + ")"
                      color: isOmarchyEntry ? root.roleColor("cyan") : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: pickerItemMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.formItemDesktopId = modelData.id
                        root.formItemTitle = entryTitle
                        root.formItemSubtitle = modelData.subtext || modelData.id
                        root.formItemIconType = isOmarchyEntry ? "glyph" : "system"
                        root.formItemIconValue = modelData.icon || ""
                      }
                    }
                  }
                }
              }
            }

            // Title & Subtitle
            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: (parent.width - Style.space(10)) / 2
                spacing: 4
                Text { text: root.tr("fieldTitle"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  id: itemTitleInput
                  width: parent.width
                  placeholderText: root.tr("fieldTitlePlaceholder")
                  text: root.formItemTitle
                  onTextChanged: root.formItemTitle = text
                }
              }

              Column {
                width: (parent.width - Style.space(10)) / 2
                spacing: 4
                Text { text: root.tr("fieldSubtitle"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  width: parent.width
                  placeholderText: root.tr("fieldSubtitlePlaceholder")
                  text: root.formItemSubtitle
                  onTextChanged: root.formItemSubtitle = text
                }
              }
            }

            // Command fields (shown when type === "command")
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.formItemType === "command"

              Column {
                width: parent.width
                spacing: 4
                Text { text: root.tr("fieldCommand"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  width: parent.width
                  placeholderText: root.tr("fieldCommandPlaceholder")
                  text: root.formItemCommand
                  onTextChanged: root.formItemCommand = text
                }
              }

              Column {
                width: parent.width
                spacing: 4
                Text { text: root.tr("fieldCwd"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  width: parent.width
                  placeholderText: root.tr("fieldCwdPlaceholder")
                  text: root.formItemCwd
                  onTextChanged: root.formItemCwd = text
                }
              }

              Row {
                spacing: Style.space(8)

                Button {
                  text: root.tr("runModeTerminal")
                  bordered: true
                  selected: root.formItemRunMode !== "background"
                  onClicked: root.formItemRunMode = "terminal"
                }

                Button {
                  text: root.tr("runModeBackground")
                  bordered: true
                  selected: root.formItemRunMode === "background"
                  onClicked: root.formItemRunMode = "background"
                }
              }
            }

            // URL or Desktop ID
            Column {
              width: parent.width
              spacing: 4
              visible: root.formItemType === "url"
              Text { text: root.tr("fieldUrl"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              TextField {
                width: parent.width
                placeholderText: "https://..."
                text: root.formItemUrl
                onTextChanged: root.formItemUrl = text
              }
            }

            // Space Selector Pills
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldSpace"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: (root.data && root.data.spaces) ? root.data.spaces : []
                  delegate: Button {
                    required property var modelData
                    text: (modelData.icon || "󰀻") + " " + modelData.name
                    bordered: true
                    selected: root.formItemSpaceId === modelData.id
                    onClicked: root.onFormSpaceChosen(modelData.id)
                  }
                }
              }
            }

            // Category Selector Pills
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldCategory"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.formCategoriesForSelectedSpace()
                  delegate: Button {
                    required property var modelData
                    text: (modelData.icon || "󰉋") + " " + modelData.name
                    bordered: true
                    selected: root.formItemCategoryId === modelData.id
                    onClicked: root.formItemCategoryId = modelData.id
                  }
                }
              }
            }

            // Pinned Quick Orbit Slot [0..6] & Badge / Custom Icon
            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: (parent.width - Style.space(10)) * 0.56
                spacing: 4
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: root.tr("fieldPinOrbit")
                  color: Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  spacing: Style.space(4)
                  Repeater {
                    model: [0, 1, 2, 3, 4, 5, 6]
                    delegate: Button {
                      required property int modelData
                      text: modelData === 0 ? root.tr("pinNone") : "#" + modelData
                      bordered: true
                      selected: root.formItemPinnedSlot === modelData
                      onClicked: root.formItemPinnedSlot = modelData
                    }
                  }
                }
              }

              Column {
                width: (parent.width - Style.space(10)) * 0.44
                spacing: 4
                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Column {
                    width: (parent.width - Style.space(6)) * 0.54
                    spacing: 4
                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: root.tr("fieldBadge")
                      color: Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    TextField {
                      width: parent.width
                      placeholderText: "Live / Work"
                      text: root.formItemBadgeText
                      onTextChanged: root.formItemBadgeText = text
                    }
                  }

                  Column {
                    width: (parent.width - Style.space(6)) * 0.46
                    spacing: 4
                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: root.tr("fieldCustomIcon")
                      color: Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    TextField {
                      width: parent.width
                      placeholderText: "󰊤"
                      text: root.formItemIconValue
                      onTextChanged: {
                        root.formItemIconValue = text
                        if (text.trim().length > 0 && root.formItemType === "url") {
                          root.formItemIconType = "glyph"
                        } else if (root.formItemType === "url") {
                          root.formItemIconType = "favicon"
                        }
                      }
                    }
                  }
                }
              }
            }

            // Color Role Picker
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldColorAccent"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Row {
                spacing: Style.space(8)

                Button {
                  text: root.tr("colorNone")
                  bordered: true
                  selected: root.formItemColorRole === ""
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.formItemColorRole = ""
                }

                Repeater {
                  model: ThemePalette.COLOR_ROLES
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: width / 2
                    color: root.roleColor(modelData.id)
                    border.width: root.formItemColorRole === modelData.id ? 3 : 1
                    border.color: root.formItemColorRole === modelData.id ? root.foreground : Util.alpha(root.background, 0.5)
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.formItemColorRole = (root.formItemColorRole === modelData.id) ? "" : modelData.id
                      }
                    }
                  }
                }
              }
            }

            // Modal Footer Actions
            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Button {
                text: root.tr("btnCancel")
                bordered: true
                onClicked: root.activeModal = ""
              }

              Button {
                text: root.tr("btnSaveItem")
                bordered: true
                selected: true
                onClicked: root.saveItemModal()
              }
            }
          }
        }

        // ------------------------------------------------------------
        // MODAL B: Add / Edit Category (Supports Static, RSS & GitHub Live Feeds)
        // ------------------------------------------------------------
        BorderSurface {
          visible: root.activeModal === "editCategory"
          width: Math.min(Style.space(520), parent.width - Style.space(40))
          height: catModalCol.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          radius: root.cornerRadius
          color: Color.popups.background
          borderSpec: root.borderSpec
          padding: Style.space(18)

          MouseArea { anchors.fill: parent }

          Column {
            id: catModalCol
            width: parent.width - Style.space(36)
            anchors.centerIn: parent
            spacing: Style.space(12)

            Text {
              text: root.formCategoryId !== "" ? root.tr("modalEditCategoryTitle") : root.tr("modalAddCategoryTitle")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            // Column Source Type Selector (Static / RSS / GitHub)
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldCategoryType"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Row {
                spacing: Style.space(6)

                Button {
                  text: root.tr("catTypeStatic")
                  bordered: true
                  selected: root.formCategoryType === "static"
                  onClicked: root.formCategoryType = "static"
                }

                Button {
                  text: root.tr("catTypeRss")
                  bordered: true
                  selected: root.formCategoryType === "rss"
                  onClicked: {
                    root.formCategoryType = "rss"
                    if (root.formCategoryIcon === "󰉋" || root.formCategoryIcon === "󰊤") root.formCategoryIcon = "󰑫"
                  }
                }

                Button {
                  text: root.tr("catTypeGithub")
                  bordered: true
                  selected: root.formCategoryType === "github"
                  onClicked: {
                    root.formCategoryType = "github"
                    if (root.formCategoryIcon === "󰉋" || root.formCategoryIcon === "󰑫") root.formCategoryIcon = "󰊤"
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: parent.width - Style.space(90)
                spacing: 4
                Text { text: root.tr("fieldCategoryName"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  id: catNameInput
                  width: parent.width
                  placeholderText: root.tr("fieldCategoryPlaceholder")
                  text: root.formCategoryName
                  onTextChanged: root.formCategoryName = text
                }
              }

              Column {
                width: Style.space(80)
                spacing: 4
                Text { text: root.tr("fieldIcon"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  width: parent.width
                  placeholderText: "󰉋"
                  text: root.formCategoryIcon
                  onTextChanged: root.formCategoryIcon = text
                }
              }
            }

            // Live Feed URL / Repo Field (shown when type is rss or github)
            Column {
              visible: root.formCategoryType === "rss" || root.formCategoryType === "github"
              width: parent.width
              spacing: 6

              Text {
                text: root.formCategoryType === "github" ? root.tr("fieldFeedUrlGithub") : root.tr("fieldFeedUrlRss")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                width: parent.width
                placeholderText: root.formCategoryType === "github" ? root.tr("fieldFeedUrlGithubPlaceholder") : root.tr("fieldFeedUrlRssPlaceholder")
                text: root.formCategoryFeedUrl
                onTextChanged: root.formCategoryFeedUrl = text
              }

              // GitHub Mode Selector (all / issues / prs / releases)
              Column {
                visible: root.formCategoryType === "github"
                width: parent.width
                spacing: 4

                Text { text: root.tr("fieldGithubMode"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Button {
                    text: root.tr("ghModeAll")
                    bordered: true
                    selected: root.formCategoryFeedMode === "all"
                    onClicked: root.formCategoryFeedMode = "all"
                  }
                  Button {
                    text: root.tr("ghModeIssues")
                    bordered: true
                    selected: root.formCategoryFeedMode === "issues"
                    onClicked: root.formCategoryFeedMode = "issues"
                  }
                  Button {
                    text: root.tr("ghModePrs")
                    bordered: true
                    selected: root.formCategoryFeedMode === "prs"
                    onClicked: root.formCategoryFeedMode = "prs"
                  }
                  Button {
                    text: root.tr("ghModeReleases")
                    bordered: true
                    selected: root.formCategoryFeedMode === "releases"
                    onClicked: root.formCategoryFeedMode = "releases"
                  }
                }
              }

              // Quick Feed Presets
              Text { text: root.tr("feedPresetsLabel"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.formCategoryType === "github"
                    ? [
                        { label: "Omarchy PRs & Issues", name: "Omarchy Activity", icon: "󰊤", url: "basecamp/omarchy", mode: "all", color: "green" },
                        { label: "Omarchy Releases", name: "Omarchy Releases", icon: "󰓾", url: "basecamp/omarchy", mode: "releases", color: "cyan" },
                        { label: "Hyprland Issues", name: "Hyprland WM", icon: "󰊤", url: "hyprwm/Hyprland", mode: "all", color: "blue" },
                        { label: "My Open PRs (@me)", name: "My GitHub PRs", icon: "󰊤", url: "@me", mode: "prs", color: "magenta" }
                      ]
                    : [
                        { label: "Hacker News", name: "Hacker News", icon: "󰑫", url: "https://hnrss.org/frontpage?count=48", mode: "all", color: "orange" },
                        { label: "Arch Linux News", name: "Arch Linux News", icon: "󰣇", url: "https://archlinux.org/feeds/news/", mode: "all", color: "blue" },
                        { label: "Root.cz", name: "Root.cz Články", icon: "󰑫", url: "https://www.root.cz/rss/clanky/", mode: "all", color: "red" },
                        { label: "Lobsters", name: "Lobste.rs", icon: "󰑫", url: "https://lobste.rs/rss", mode: "all", color: "yellow" }
                      ]

                  delegate: Button {
                    required property var modelData
                    text: modelData.label
                    bordered: true
                    selected: root.formCategoryFeedUrl === modelData.url && (root.formCategoryType !== "github" || root.formCategoryFeedMode === modelData.mode)
                    onClicked: {
                      root.formCategoryFeedUrl = modelData.url
                      root.formCategoryFeedMode = modelData.mode
                      if (!root.formCategoryName.trim()) root.formCategoryName = modelData.name
                      root.formCategoryIcon = modelData.icon
                      root.formCategoryColorRole = modelData.color
                    }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldCategoryColor"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Row {
                spacing: Style.space(8)
                Repeater {
                  model: ThemePalette.COLOR_ROLES
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: width / 2
                    color: root.roleColor(modelData.id)
                    border.width: root.formCategoryColorRole === modelData.id ? 3 : 1
                    border.color: root.formCategoryColorRole === modelData.id ? root.foreground : Util.alpha(root.background, 0.5)

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.formCategoryColorRole = modelData.id
                    }
                  }
                }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Button {
                visible: root.formCategoryId !== ""
                text: root.tr("btnDeleteCategory")
                bordered: true
                foreground: Color.urgent
                onClicked: {
                  var cid = root.formCategoryId
                  root.activeModal = ""
                  root.commitData(Storage.deleteCategory(root.data, cid))
                  root.showStatus(root.tr("statusCategoryDeleted"))
                }
              }

              Button {
                text: root.tr("btnCancel")
                bordered: true
                onClicked: root.activeModal = ""
              }

              Button {
                text: root.tr("btnSaveCategory")
                bordered: true
                selected: true
                onClicked: root.saveCategoryModal()
              }
            }
          }
        }

        // ------------------------------------------------------------
        // MODAL C: Add / Edit Space
        // ------------------------------------------------------------
        BorderSurface {
          visible: root.activeModal === "editSpace"
          width: Math.min(Style.space(420), parent.width - Style.space(40))
          height: spaceModalCol.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          radius: root.cornerRadius
          color: Color.popups.background
          borderSpec: root.borderSpec
          padding: Style.space(18)

          MouseArea { anchors.fill: parent }

          Column {
            id: spaceModalCol
            width: parent.width - Style.space(36)
            anchors.centerIn: parent
            spacing: Style.space(12)

            Text {
              text: root.formSpaceId !== "" ? root.tr("modalEditSpaceTitle") : root.tr("modalAddSpaceTitle")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: parent.width - Style.space(90)
                spacing: 4
                Text { text: root.tr("fieldSpaceName"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  id: spaceNameInput
                  width: parent.width
                  placeholderText: root.tr("fieldSpacePlaceholder")
                  text: root.formSpaceName
                  onTextChanged: root.formSpaceName = text
                }
              }

              Column {
                width: Style.space(80)
                spacing: 4
                Text { text: root.tr("fieldIcon"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                TextField {
                  width: parent.width
                  placeholderText: "󰀻"
                  text: root.formSpaceIcon
                  onTextChanged: root.formSpaceIcon = text
                }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Button {
                visible: root.formSpaceId !== "" && root.data.spaces.length > 1
                text: root.tr("btnDeleteSpace")
                bordered: true
                foreground: Color.urgent
                onClicked: {
                  var sid = root.formSpaceId
                  root.activeModal = ""
                  root.commitData(Storage.deleteSpace(root.data, sid))
                  root.showStatus(root.tr("statusSpaceDeleted"))
                }
              }

              Button {
                text: root.tr("btnCancel")
                bordered: true
                onClicked: root.activeModal = ""
              }

              Button {
                text: root.tr("btnSaveSpace")
                bordered: true
                selected: true
                onClicked: root.saveSpaceModal()
              }
            }
          }
        }

        // ------------------------------------------------------------
        // MODAL D: One-time Browser Bookmark Importer
        // ------------------------------------------------------------
        BorderSurface {
          visible: root.activeModal === "importBookmarks"
          width: Math.min(Style.space(620), parent.width - Style.space(40))
          height: importModalCol.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          radius: root.cornerRadius
          color: Color.popups.background
          borderSpec: root.borderSpec
          padding: Style.space(18)

          MouseArea { anchors.fill: parent }

          Column {
            id: importModalCol
            width: parent.width - Style.space(36)
            anchors.centerIn: parent
            spacing: Style.space(12)

            Text {
              text: root.tr("modalImportTitle") + root.activeSpaceId
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.tr("modalImportSubtitle")
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }

            // Source tabs
            Flow {
              width: parent.width
              spacing: Style.space(6)
              visible: root.bookmarkSources.length > 0

              Repeater {
                model: root.bookmarkSources
                delegate: Button {
                  required property var modelData
                  required property int index
                  text: modelData.name + " (" + modelData.totalBookmarks + ")"
                  bordered: true
                  selected: root.selectedSourceIndex === index
                  onClicked: root.selectedSourceIndex = index
                }
              }
            }

            // Folders checklist
            Rectangle {
              width: parent.width
              height: Style.space(220)
              radius: 5
              color: Util.alpha(root.foreground, 0.04)
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.14)

              Text {
                anchors.centerIn: parent
                visible: root.scanningBookmarks
                text: root.tr("scanningBookmarksText")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.centerIn: parent
                visible: !root.scanningBookmarks && root.bookmarkSources.length === 0
                text: root.tr("noBookmarksFoundText")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              ListView {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                clip: true
                spacing: Style.space(4)
                visible: !root.scanningBookmarks && root.bookmarkSources.length > 0
                model: (root.bookmarkSources[root.selectedSourceIndex] && root.bookmarkSources[root.selectedSourceIndex].folders)
                  ? root.bookmarkSources[root.selectedSourceIndex].folders
                  : []

                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  readonly property string sourceId: root.bookmarkSources[root.selectedSourceIndex]
                    ? root.bookmarkSources[root.selectedSourceIndex].id : ""
                  readonly property string folderKey: sourceId + "::" + index
                  readonly property bool isChecked: root.selectedFoldersMap[folderKey] !== false

                  width: ListView.view.width
                  height: Style.space(32)
                  radius: 4
                  color: isChecked ? Util.alpha(root.roleColor("green"), 0.14) : "transparent"

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(10)

                    Text {
                      text: isChecked ? "☑" : "☐"
                      color: isChecked ? root.roleColor("green") : Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "󰉋  " + modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: isChecked
                    }

                    Text {
                      text: "(" + modelData.count + " " + root.tr("linksCountSuffix") + ")"
                      color: Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var nextMap = Object.assign({}, root.selectedFoldersMap)
                      nextMap[folderKey] = !isChecked
                      root.selectedFoldersMap = nextMap
                    }
                  }
                }
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Button {
                text: root.tr("btnCancel")
                bordered: true
                onClicked: root.activeModal = ""
              }

              Button {
                text: root.tr("btnImportSelected")
                bordered: true
                selected: true
                onClicked: root.confirmImportBookmarks()
              }
            }
          }
        }

        // ----------------------------------------------------------
        // Modal E: Global Keyboard Shortcut (Spotlight Hotkey)
        // ----------------------------------------------------------
        BorderSurface {
          width: Style.space(520)
          height: shortcutCol.implicitHeight + Style.space(44)
          anchors.centerIn: parent
          visible: root.activeModal === "shortcut"
          radius: root.cornerRadius
          color: root.background
          borderSpec: root.borderSpec
          padding: Style.space(22)

          MouseArea { anchors.fill: parent }

          Column {
            id: shortcutCol
            width: parent.width
            spacing: Style.space(14)

            Text {
              text: root.tr("modalShortcutTitle")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.tr("modalShortcutSubtitle")
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              width: parent.width
              spacing: 4
              Text {
                text: root.tr("fieldShortcutCombo")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              TextField {
                width: parent.width
                placeholderText: "SUPER + M"
                text: root.formShortcutCombo
                onTextChanged: root.formShortcutCombo = text
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: root.tr("shortcutPresetsLabel")
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Flow {
                width: parent.width
                spacing: Style.space(8)

                Repeater {
                  model: ["SUPER + M", "ALT + SPACE", "SUPER + ALT + SPACE", "SUPER + SPACE", "SUPER + G"]

                  delegate: Button {
                    required property string modelData
                    text: modelData
                    bordered: true
                    selected: root.formShortcutCombo.trim().toUpperCase() === modelData
                    onClicked: root.formShortcutCombo = modelData
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: root.tr("shortcutNoneBtn")
                bordered: true
                visible: root.currentGlobalShortcut !== ""
                onClicked: root.applyGlobalShortcut("", "remove")
              }

              Item { width: Style.space(10); height: 1 }

              Button {
                text: root.tr("btnCancel")
                bordered: true
                onClicked: root.activeModal = ""
              }

              Button {
                text: root.tr("shortcutSaveBtn")
                bordered: true
                selected: true
                onClicked: root.applyGlobalShortcut(root.formShortcutCombo, "replace")
              }
            }
          }
        }
      }
    }
  }
}
