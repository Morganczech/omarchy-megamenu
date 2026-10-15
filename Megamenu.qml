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
  property string statusBannerText: ""

  // Context Menu state
  property bool contextMenuOpen: false
  property var contextMenuItem: null
  property real contextMenuX: 0
  property real contextMenuY: 0

  // Modals: "" | "editItem" | "editCategory" | "editSpace" | "importBookmarks"
  property string activeModal: ""

  // Edit Item Modal fields
  property string formItemId: ""
  property string formItemType: "url" // "url" | "app"
  property string formItemTitle: ""
  property string formItemSubtitle: ""
  property string formItemUrl: ""
  property string formItemDesktopId: ""
  property string formItemCategoryId: ""
  property string formItemIconType: "favicon" // "favicon" | "glyph" | "system" | "monogram"
  property string formItemIconValue: ""
  property string formItemBadgeText: ""
  property string formItemColorRole: "blue"
  property int formItemPinnedSlot: 0
  property bool formItemFavorite: false
  property string formAppSearchQuery: ""

  // Edit Category Modal fields
  property string formCategoryId: ""
  property string formCategoryName: ""
  property string formCategoryIcon: "󰉋"
  property string formCategoryColorRole: "blue"

  // Edit Space Modal fields
  property string formSpaceId: ""
  property string formSpaceName: ""
  property string formSpaceIcon: "󰀻"

  // Import Bookmarks Modal state
  property int selectedSourceIndex: 0
  property var selectedFoldersMap: ({})

  // Global Shortcut Modal state (strictly opt-in; read-only status check on startup)
  property string currentGlobalShortcut: ""
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
  readonly property var currentCategories: Storage.categoriesForSpace(root.data, root.activeSpaceId)
  readonly property var currentSpaceItems: Storage.itemsForSpace(root.data, root.activeSpaceId)
  readonly property var pinnedOrbit: Storage.pinnedOrbitForSpace(root.data, root.activeSpaceId)
  readonly property var filteredFlatItems: Storage.filterItems(root.data, root.activeSpaceId, root.activeFilter, root.searchQuery)
  readonly property bool isCommandMode: root.searchQuery.trim().indexOf(">") === 0
  readonly property var matchedSystemApps: {
    if (!root.isCommandMode) return []
    var q = root.searchQuery.trim().slice(1).trim()
    var values = (DesktopEntries && DesktopEntries.applications && DesktopEntries.applications.values)
      ? DesktopEntries.applications.values
      : []
    return Storage.searchDesktopEntries(values, q, root.hiddenDesktopIds, 40)
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
    var id = Storage.normalizeDesktopId(desktopId)
    if (!id) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // Lifecycle methods invoked by omarchy-shell
  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p && (p.language === "en" || p.language === "cs")) {
        root.payloadLanguageOverride = p.language
      }
    } catch (e) {}

    root.opened = true
    root.contextMenuOpen = false
    root.activeModal = ""
    root.searchQuery = ""
    root.selectedAppIndex = 0
    if (searchInput) searchInput.text = ""
    themeColorsFile.reload()
    if (!appIconScanProc.running) appIconScanProc.running = true
    root.refreshBrowsers()
    root.applyGlobalShortcut("", "status")
    root.ensureSelectedValid()
    Qt.callLater(function() {
      if (searchInput) searchInput.forceActiveFocus()
    })
  }

  function close() {
    root.contextMenuOpen = false
    root.activeModal = ""
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "gruut.megamenu")
    }
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

  function hydrateData(rawText) {
    var hasExisting = rawText && String(rawText).trim().length > 0
    root.data = Storage.parse(rawText)
    root.storageReady = true
    if (!hasExisting) {
      dataFile.setText(Storage.serialize(root.data))
    }
    root.ensureSelectedValid()
    root.queueMissingFavicons()
  }

  function ensureSelectedValid() {
    var items = root.filteredFlatItems
    if (!items || items.length === 0) {
      root.selectedItemId = ""
      return
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === root.selectedItemId) return
    }
    root.selectedItemId = items[0].id
  }

  function selectDelta(delta) {
    var items = root.filteredFlatItems
    if (!items || items.length === 0) return
    var idx = 0
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === root.selectedItemId) {
        idx = i
        break
      }
    }
    var nextIdx = (idx + delta + items.length) % items.length
    root.selectedItemId = items[nextIdx].id
  }

  function findItemById(itemId) {
    var list = (root.data && root.data.items) ? root.data.items : []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === itemId) return list[i]
    }
    return null
  }

  function switchSpace(spaceId) {
    if (!spaceId) return
    var next = Storage.cloneData(root.data)
    next.activeSpaceId = spaceId
    root.activeFilter = "all"
    root.contextMenuOpen = false
    root.commitData(next)
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
  function launchItemDefault(item) {
    if (!item) return
    root.dismiss()
    if (item.type === "app") {
      root.launchDesktopApp(item.desktopId, item.title)
    } else if (item.url) {
      Quickshell.execDetached(["xdg-open", item.url])
    }
  }

  function launchItemInBrowser(item, browser) {
    if (!item || !item.url || !browser || !browser.exec) return
    root.dismiss()
    Util.execDetached("uwsm-app -- " + browser.exec + " " + Util.shellQuote(item.url))
  }

  function copyItemUrl(item) {
    if (!item) return
    var target = item.type === "url" ? item.url : item.desktopId
    if (!target) return
    Quickshell.execDetached(["wl-copy", target])
    root.contextMenuOpen = false
    root.showStatus(root.tr("statusCopied") + target)
  }

  function openContextMenuFor(item, globalX, globalY) {
    if (!item) return
    root.contextMenuItem = item
    var menuW = Style.space(260)
    var menuH = Style.space(250)
    var maxX = card.width - menuW - Style.space(12)
    var maxY = card.height - menuH - Style.space(12)
    root.contextMenuX = Math.max(Style.space(12), Math.min(maxX, globalX))
    root.contextMenuY = Math.max(Style.space(12), Math.min(maxY, globalY))
    root.contextMenuOpen = true
  }

  // Modal openers
  function openAddItemModal(preselectedCategoryId, preselectedSlot) {
    root.contextMenuOpen = false
    var cats = root.currentCategories
    var defaultCat = preselectedCategoryId || (cats.length > 0 ? cats[0].id : "")
    root.formItemId = ""
    root.formItemType = "url"
    root.formItemTitle = ""
    root.formItemSubtitle = ""
    root.formItemUrl = "https://"
    root.formItemDesktopId = ""
    root.formItemCategoryId = defaultCat
    root.formItemIconType = "favicon"
    root.formItemIconValue = ""
    root.formItemBadgeText = ""
    root.formItemColorRole = "blue"
    root.formItemPinnedSlot = preselectedSlot || 0
    root.formItemFavorite = false
    root.formAppSearchQuery = ""
    root.activeModal = "editItem"
    Qt.callLater(function() { itemTitleInput.forceActiveFocus() })
  }

  function openEditItemModal(item) {
    if (!item) return
    root.contextMenuOpen = false
    root.formItemId = item.id
    root.formItemType = item.type || "url"
    root.formItemTitle = item.title || ""
    root.formItemSubtitle = item.subtitle || ""
    root.formItemUrl = item.url || ""
    root.formItemDesktopId = item.desktopId || ""
    root.formItemCategoryId = item.categoryId || ""
    root.formItemIconType = item.iconType || "favicon"
    root.formItemIconValue = item.iconValue || ""
    root.formItemBadgeText = item.badgeText || ""
    root.formItemColorRole = item.colorRole || "blue"
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
    var payload = {
      id: root.formItemId || Storage.uid("item"),
      spaceId: root.activeSpaceId,
      categoryId: root.formItemCategoryId,
      type: root.formItemType,
      title: title,
      subtitle: root.formItemSubtitle.trim(),
      url: root.formItemType === "url" ? root.formItemUrl.trim() : "",
      desktopId: root.formItemType === "app" ? root.formItemDesktopId.trim() : "",
      iconType: root.formItemIconType,
      iconValue: root.formItemIconValue.trim(),
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
    if (categoryObj && categoryObj.id) {
      root.formCategoryId = categoryObj.id
      root.formCategoryName = categoryObj.name || ""
      root.formCategoryIcon = categoryObj.icon || "󰉋"
      root.formCategoryColorRole = categoryObj.colorRole || "blue"
    } else {
      root.formCategoryId = ""
      root.formCategoryName = ""
      root.formCategoryIcon = "󰉋"
      root.formCategoryColorRole = "blue"
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
    var next = Storage.upsertCategory(root.data, {
      id: root.formCategoryId || Storage.uid("cat"),
      spaceId: root.activeSpaceId,
      name: name,
      icon: root.formCategoryIcon.trim() || "󰉋",
      colorRole: root.formCategoryColorRole
    })
    root.activeModal = ""
    root.commitData(next)
    root.showStatus(root.tr("statusCategorySaved") + name)
  }

  function openSpaceModal(spaceObj) {
    root.contextMenuOpen = false
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
    if (!root.dirReady || faviconFetchProc.running) return
    var items = (root.data && root.data.items) ? root.data.items : []
    var domains = {}
    var cmd = [root.pluginDir + "/scripts/fetch-favicon.sh", root.faviconsDir]
    var count = 0
    for (var i = 0; i < items.length; i++) {
      if (items[i].type === "url" && items[i].url) {
        var d = Storage.extractDomain(items[i].url)
        if (d && !domains[d]) {
          domains[d] = true
          cmd.push(d)
          count++
          if (count >= 25) break
        }
      }
    }
    if (count > 0) {
      faviconFetchProc.command = cmd
      faviconFetchProc.running = true
    }
  }

  // Keyboard Navigation
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (root.contextMenuOpen) {
        root.contextMenuOpen = false
      } else if (root.activeModal !== "") {
        root.activeModal = ""
        Qt.callLater(function() { searchInput.forceActiveFocus() })
      } else if (root.searchQuery.length > 0) {
        root.searchQuery = ""
        searchInput.text = ""
      } else {
        root.dismiss()
      }
      event.accepted = true
      return
    }

    if (root.activeModal !== "") return

    // Quick Orbit [1-6] with Alt+1..6 or plain 1..6 when search input is empty
    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
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
      root.openAddItemModal("", 0)
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

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.isCommandMode && root.matchedSystemApps.length > 0) {
        var idx = Math.max(0, Math.min(root.selectedAppIndex, root.matchedSystemApps.length - 1))
        var sysApp = root.matchedSystemApps[idx]
        root.dismiss()
        root.launchDesktopApp(sysApp.id, sysApp.name)
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
    command: ["mkdir", "-p", root.dataDir, root.faviconsDir]
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
    property int boxSize: Style.space(28)
    width: boxSize
    height: boxSize
    radius: Style.cornerRadius > 0 ? Math.max(4, Math.min(8, Style.cornerRadius)) : 4
    color: Util.alpha(root.roleColor(itemData ? itemData.colorRole : "blue"), 0.14)
    border.width: 1
    border.color: Util.alpha(root.roleColor(itemData ? itemData.colorRole : "blue"), 0.35)

    readonly property bool isApp: itemData && itemData.type === "app"
    readonly property bool wantsFavicon: itemData && itemData.type === "url" && itemData.iconType === "favicon"
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
      color: root.roleColor(badgeRoot.itemData ? badgeRoot.itemData.colorRole : "blue")
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
      onClicked: root.dismiss()
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

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            // Brand / Core OS indicator
            Row {
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

            // Space Switcher Tabs
            Rectangle {
              height: Style.space(36)
              width: spacesRow.implicitWidth + Style.space(8)
              radius: Style.cornerRadius > 0 ? Math.max(4, Style.cornerRadius) : 4
              color: Util.alpha(root.foreground, 0.04)
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.14)
              anchors.verticalCenter: parent.verticalCenter

              Row {
                id: spacesRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Repeater {
                  model: (root.data && root.data.spaces) ? root.data.spaces : []

                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool isCurrent: modelData.id === root.activeSpaceId
                    height: Style.space(28)
                    width: spaceTabRow.implicitWidth + Style.space(18)
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
          }

          // Top Right Actions
          Row {
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
              text: "󰗊 " + root.activeLang.toUpperCase() + (root.languagePref === "auto" ? " (A)" : "")
              bordered: true
              tooltipText: root.tr("langTooltip")
              onClicked: root.cycleLanguage()
            }

            Button {
              text: root.tr("addItemBtn")
              bordered: true
              tooltipText: root.tr("addItemTooltip")
              onClicked: root.openAddItemModal("", 0)
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
          spacing: Style.spacing.sm

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
            height: Math.min(filterPillsFlow.implicitHeight, Style.space(60))
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
                  ? root.roleColor(orbitItem.colorRole)
                  : Util.alpha(root.foreground, 0.2)
                width: (orbitRow.width - Style.space(10) * 5) / 6
                height: Style.space(76)
                radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
                color: orbitMouse.containsMouse
                  ? Util.alpha(orbitAccent, 0.14)
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
                        text: orbitItem ? orbitItem.title : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      Text {
                        width: parent.width
                        elide: Text.ElideRight
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
                  - (orbitSection.visible ? orbitSection.height + Style.spacing.md : 0)
                  - footerBar.height
                  - Style.spacing.md * 3

          // 4A. Category Columns Horizontal Flickable (Normal View)
          Flickable {
            id: categoriesFlick
            anchors.fill: parent
            visible: !root.isCommandMode
            contentWidth: categoriesRow.implicitWidth
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: categoriesRow
              height: parent.height
              spacing: Style.space(12)

              Repeater {
                model: {
                  if (root.activeFilter !== "all" && root.activeFilter !== "favorites") {
                    var filtered = []
                    for (var i = 0; i < root.currentCategories.length; i++) {
                      if (root.currentCategories[i].id === root.activeFilter) {
                        filtered.push(root.currentCategories[i])
                      }
                    }
                    return filtered
                  }
                  return root.currentCategories
                }

                delegate: Rectangle {
                  id: catColumnCard
                  required property var modelData
                  readonly property color catAccent: root.roleColor(modelData.colorRole)
                  readonly property var columnItems: {
                    var all = root.filteredFlatItems
                    var list = []
                    for (var i = 0; i < all.length; i++) {
                      if (all[i].categoryId === modelData.id) list.push(all[i])
                    }
                    return list
                  }

                  width: Math.max(Style.space(280), (gridContainer.width - Style.space(12) * 3) / Math.min(4, Math.max(1, root.currentCategories.length)))
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
                        width: catHeaderRow.implicitWidth
                        height: parent.height

                        Row {
                          id: catHeaderRow
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)

                          Text {
                            text: modelData.icon || "󰉋"
                            color: catColumnCard.catAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            text: modelData.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openCategoryModal(modelData)
                        }
                      }

                      Row {
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
                            text: I18n.formatItemsCount(root.activeLang, catColumnCard.columnItems.length)
                            color: catColumnCard.catAccent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Rectangle {
                          width: Style.space(22)
                          height: Style.space(20)
                          radius: Style.cornerRadius > 0 ? Math.max(3, Style.cornerRadius - 2) : 3
                          color: addInCatMouse.containsMouse ? Util.alpha(catColumnCard.catAccent, 0.22) : Util.alpha(root.foreground, 0.06)
                          anchors.verticalCenter: parent.verticalCenter

                          Text {
                            anchors.centerIn: parent
                            text: "+"
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
                            onClicked: root.openAddItemModal(modelData.id, 0)
                          }
                        }
                      }
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

                      delegate: Rectangle {
                        id: itemRowRect
                        required property var modelData
                        readonly property bool isSelected: root.selectedItemId === modelData.id
                        readonly property bool isHovered: rowMouse.containsMouse
                        readonly property color rowAccent: root.roleColor(modelData.colorRole || catColumnCard.modelData.colorRole)

                        width: catListView.width
                        height: Style.space(52)
                        radius: Style.cornerRadius > 0 ? Math.max(5, Style.cornerRadius - 1) : 5
                        color: (isHovered || isSelected)
                          ? Util.alpha(rowAccent, 0.14)
                          : "transparent"
                        border.width: (isHovered || isSelected) ? 1 : 0
                        border.color: (isHovered || isSelected)
                          ? Util.alpha(rowAccent, 0.55)
                          : "transparent"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(8)
                          anchors.rightMargin: Style.space(8)
                          spacing: Style.space(10)

                          ItemIconBadge {
                            itemData: modelData
                            boxSize: Style.space(32)
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Column {
                            width: parent.width - Style.space(104)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Row {
                              spacing: Style.space(6)
                              width: parent.width

                              Text {
                                width: Math.min(implicitWidth, parent.width - Style.space(20))
                                elide: Text.ElideRight
                                text: modelData.title
                                color: (itemRowRect.isHovered || itemRowRect.isSelected) ? root.selectedText : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                              }

                              Rectangle {
                                visible: modelData.type === "app"
                                height: Style.space(15)
                                width: appTagText.implicitWidth + Style.space(8)
                                radius: 3
                                color: Util.alpha(itemRowRect.rowAccent, 0.2)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                  id: appTagText
                                  anchors.centerIn: parent
                                  text: "APP"
                                  color: itemRowRect.rowAccent
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption - 2
                                  font.bold: true
                                }
                              }
                            }

                            Text {
                              width: parent.width
                              elide: Text.ElideRight
                              text: modelData.subtitle || Storage.extractDomain(modelData.url)
                              color: Color.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }
                        }

                        // Main Row Mouse Area (Left click: launch, Right click: context menu)
                        MouseArea {
                          id: rowMouse
                          anchors.fill: parent
                          anchors.rightMargin: Style.space(56)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          acceptedButtons: Qt.LeftButton | Qt.RightButton
                          onEntered: root.selectedItemId = modelData.id
                          onClicked: function(mouse) {
                            root.selectedItemId = modelData.id
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
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(4)

                          // Favorite Star Toggle
                          Rectangle {
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 4
                            color: favMouse.containsMouse ? Util.alpha(root.foreground, 0.12) : "transparent"
                            visible: itemRowRect.isHovered || itemRowRect.isSelected || modelData.favorite

                            Text {
                              anchors.centerIn: parent
                              text: modelData.favorite ? "★" : "☆"
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
                                root.commitData(Storage.toggleFavorite(root.data, modelData.id))
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
                    readonly property bool isSelected: index === root.selectedAppIndex
                    width: ListView.view.width
                    height: Style.space(46)
                    radius: 5
                    color: (sysAppMouse.containsMouse || isSelected)
                      ? Util.alpha(root.roleColor("green"), 0.16)
                      : Util.alpha(root.foreground, 0.03)
                    border.width: 1
                    border.color: (sysAppMouse.containsMouse || isSelected)
                      ? root.roleColor("green")
                      : Util.alpha(root.foreground, 0.1)

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(12)
                      anchors.rightMargin: Style.space(12)
                      spacing: Style.space(12)

                      Item {
                        width: Style.space(28)
                        height: Style.space(28)
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                          id: sysAppIconImg
                          anchors.fill: parent
                          source: root.resolveAppIconSource(modelData.icon || "")
                          smooth: true
                          visible: status === Image.Ready
                        }

                        Rectangle {
                          anchors.fill: parent
                          radius: 5
                          visible: sysAppIconImg.status !== Image.Ready
                          color: Util.alpha(root.roleColor("green"), 0.2)
                          border.width: 1
                          border.color: Util.alpha(root.roleColor("green"), 0.45)

                          Text {
                            anchors.centerIn: parent
                            text: appName.length > 0 ? appName.slice(0, 1).toUpperCase() : "A"
                            color: root.roleColor("green")
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                          }
                        }
                      }

                      Column {
                        width: parent.width - Style.space(180)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: appName
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: appSub || modelData.id
                          color: Color.muted
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Button {
                        anchors.verticalCenter: parent.verticalCenter
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
                            iconType: "system",
                            iconValue: modelData.icon || "",
                            colorRole: "green"
                          })
                          root.commitData(next)
                          root.showStatus(root.tr("statusAppPinned") + appName)
                        }
                      }
                    }

                    MouseArea {
                      id: sysAppMouse
                      anchors.fill: parent
                      anchors.rightMargin: Style.space(170)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedAppIndex = index
                      onClicked: {
                        root.dismiss()
                        root.launchDesktopApp(modelData.id, appName)
                      }
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
      // 6. FLOATING CONTEXT MENU (Right-click on any item)
      // ============================================================
      Rectangle {
        id: contextMenuPopup
        visible: root.contextMenuOpen && root.contextMenuItem !== null
        x: root.contextMenuX
        y: root.contextMenuY
        width: Style.space(264)
        height: contextMenuCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius > 0 ? Math.max(6, Style.cornerRadius) : 6
        color: Color.popups.background
        border.width: 1.5
        border.color: Color.popups.border
        z: 50

        Column {
          id: contextMenuCol
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(4)

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
              text: (root.contextMenuItem && root.contextMenuItem.type === "app") ? root.tr("ctxCopyDesktopId") : root.tr("ctxCopyUrl")
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

          // Edit Bookmark / Item
          Rectangle {
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

          // Delete Item
          Rectangle {
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

            // Type Toggle: Web Link vs Local App
            Row {
              spacing: Style.space(8)

              Button {
                text: root.tr("typeWebLink")
                bordered: true
                selected: root.formItemType === "url"
                onClicked: {
                  root.formItemType = "url"
                  root.formItemIconType = "favicon"
                }
              }

              Button {
                text: root.tr("typeLocalApp")
                bordered: true
                selected: root.formItemType === "app"
                onClicked: {
                  root.formItemType = "app"
                  root.formItemIconType = "system"
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
                  model: Storage.searchDesktopEntries(
                    (DesktopEntries && DesktopEntries.applications && DesktopEntries.applications.values)
                      ? DesktopEntries.applications.values
                      : [],
                    root.formAppSearchQuery,
                    root.hiddenDesktopIds,
                    30
                  )

                  delegate: Rectangle {
                    required property var modelData
                    readonly property string entryTitle: modelData.name || modelData.id || ""
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
                      text: entryTitle + "  (" + modelData.id + ")"
                      color: root.foreground
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
                        root.formItemIconType = "system"
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

            // Category Selector Pills
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldCategory"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

              Flow {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.currentCategories
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

            // Pinned Quick Orbit Slot [0..6] & Badge
            Row {
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: (parent.width - Style.space(10)) * 0.62
                spacing: 4
                Text { text: root.tr("fieldPinOrbit"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

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
                width: (parent.width - Style.space(10)) * 0.38
                spacing: 4
                Text { text: root.tr("fieldBadgeAndIcon"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  TextField {
                    width: parent.width * 0.58
                    placeholderText: "Live / Work"
                    text: root.formItemBadgeText
                    onTextChanged: root.formItemBadgeText = text
                  }
                  TextField {
                    width: parent.width * 0.38
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

            // Color Role Picker
            Column {
              width: parent.width
              spacing: 4
              Text { text: root.tr("fieldColorAccent"); color: Color.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

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
                    border.width: root.formItemColorRole === modelData.id ? 3 : 1
                    border.color: root.formItemColorRole === modelData.id ? root.foreground : Util.alpha(root.background, 0.5)

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.formItemColorRole = modelData.id
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
        // MODAL B: Add / Edit Category
        // ------------------------------------------------------------
        BorderSurface {
          visible: root.activeModal === "editCategory"
          width: Math.min(Style.space(440), parent.width - Style.space(40))
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
