// I18n.js - Localization dictionary and helper functions for Omarchy Megamenu (English & Czech)

var SUPPORTED_LANGUAGES = [
  { id: "auto", label: "Auto" },
  { id: "en", label: "EN" },
  { id: "cs", label: "CS" }
]

var STRINGS = {
  en: {
    // Top Header
    addItemBtn: "+ Item",
    addItemTooltip: "Add web bookmark, command, or local application (Ctrl+N)",
    addCategoryBtn: "+ Category",
    addCategoryTooltip: "Create a new colored category",
    importBtn: "󰋺 Import",
    importTooltip: "Import bookmarks from browser or HTML file",
    closeTooltip: "Close (Esc)",
    langTooltip: "Switch interface language (Auto / EN / CS)",
    shortcutSetBtnLabel: "Set shortcut",
    shortcutBtnTooltip: "Global hotkey to toggle Megamenu (click to configure)",
    browserHostBtn: "Page save",
    browserHostBtnOn: "Page save on",
    browserHostTooltip: "Registers the local helper so Firefox/Zen can write into Megamenu. You still need the Omarchy Megamenu add-on from Mozilla Add-ons (or Zen).",
    browserHostTooltipOn: "Local helper is on. Install Omarchy Megamenu from Mozilla Add-ons in Firefox or Zen to save the current page from the toolbar.",
    statusBrowserHostSaved: "Firefox and Zen can save pages into Megamenu",
    statusBrowserHostError: "Could not register the browser helper: ",
    spacesMoreBtn: "More",
    spacesDropdownHeader: "ALL SPACES",
    spacesAddAction: "+ Create new Space",
    spaceEditTooltip: "Edit Space",
    modalShortcutTitle: "Global Keyboard Shortcut (Opt-in)",
    modalShortcutSubtitle: "Choose or enter a Hyprland shortcut to open Megamenu from anywhere like Spotlight. Saving explicitly adds an Omaplug-compatible binding block to ~/.config/hypr/bindings.lua.",
    fieldShortcutCombo: "Key combination",
    shortcutPresetsLabel: "Quick presets:",
    shortcutNoneBtn: "Disable shortcut",
    shortcutSaveBtn: "Save shortcut",
    statusShortcutSaved: "Global shortcut set to: ",
    statusShortcutRemoved: "Global shortcut disabled",
    statusShortcutError: "Shortcut error: ",

    // Search & Filters
    searchPlaceholder: "Search all spaces, commands, Omarchy actions, or '>' for apps...",
    filterAll: "All",
    filterFavorites: "★ Favorites",
    omarchyColumnName: "Omarchy & Apps",
    otherSpaceBadge: "SPACE",
    frequentHeader: "★ FREQUENT",

    // Orbit Section
    orbitHeader: "󱐋 QUICK ACCESS / PRIMARY ORBIT",
    orbitSubheader: "/  Press key [ 1 – 6 ]",
    localStorageBadge: "LOCAL STORAGE",
    slotPrefix: "+ Slot",
    clickToPin: "Click to pin",

    // Category Grid & System Apps
    itemsCountOne: "1 link",
    itemsCountFew: "{count} links",
    itemsCountMany: "{count} links",
    systemAppsHeader: "󱓞 Omarchy System Actions, Applications & Commands (Enter to run, '+' to pin into Megamenu)",
    pinToCategoryBtn: "+ Pin to category",
    noAppsMatchedText: "No matching Omarchy actions, applications, or commands found.",

    // Footer & Status Messages
    footerActiveSpace: "ACTIVE SPACE",
    footerItems: "ITEMS",
    footerBrowsers: "BROWSERS",
    footerShortcuts: "↑↓←→ Navigate   •   Tab Space   •   1-6 Orbit   •   Enter Launch   •   Right-click / Alt+M Actions   •   Alt+E Edit   •   Esc Close",
    statusCopied: "Copied to clipboard: ",
    statusEnterItemTitle: "Please enter an item title",
    statusEnterCommand: "Enter a command",
    statusItemSaved: "Item saved: ",
    statusItemDeleted: "Item deleted: ",
    statusAppPinned: "App added to Megamenu: ",
    statusEnterCategoryName: "Please enter a category name",
    statusCategorySaved: "Category saved: ",
    statusCategoryDeleted: "Category deleted",
    statusEnterSpaceName: "Please enter a space name",
    statusSpaceSaved: "Space saved: ",
    statusSpaceDeleted: "Space deleted",
    statusNoFolderSelected: "No folder selected for import",
    statusBookmarksImported: "Bookmarks imported into active space",

    // Context Menu
    ctxLaunchInTarget: "LAUNCH IN TARGET...",
    ctxOpenIn: "Open in ",
    ctxDefaultBadge: "Default",
    ctxLaunchApp: "󰀻  Launch application",
    ctxCopyDesktopId: "󰆏  Copy Desktop ID",
    ctxCopyUrl: "󰆏  Copy URL",
    ctxCopyCommand: "󰆏  Copy command",
    ctxEditItem: "󰏫  Edit bookmark",
    ctxMoveTo: "󰀻  Move to…",
    ctxMoveBack: "← Spaces",
    statusItemMoved: "Moved: ",
    statusMoveFailed: "Could not move item (missing space or category)",
    ctxDelete: "󰩺  Delete",

    // Modal A: Add / Edit Item
    modalEditItemTitle: "Edit bookmark / item",
    modalAddItemTitle: "Add new item",
    typeWebLink: "󰖟 Web Bookmark",
    typeLocalApp: "󰀻 Local Application",
    typeCommand: "󰆍 Command",
    fieldCommand: "Command",
    fieldCommandPlaceholder: "e.g. restic-backup",
    fieldCwd: "Working directory (optional)",
    fieldCwdPlaceholder: "e.g. ~/Work/project",
    runModeTerminal: "Terminal",
    runModeBackground: "Background",
    commandDonePrompt: "Done (exit %1) — press any key",
    pickInstalledAppLabel: "Choose installed application:",
    searchAppPlaceholder: "Search application (e.g. Ghostty, Cursor, Spotify)...",
    fieldTitle: "Title",
    fieldTitlePlaceholder: "e.g. Cloudflare Dashboard",
    fieldSubtitle: "Subtitle / Description",
    fieldSubtitlePlaceholder: "e.g. dash.cloudflare.com • DNS",
    fieldUrl: "URL address",
    fieldCategory: "Category",
    fieldSpace: "Space",
    fieldPinOrbit: "Pin to Quick Orbit [1-6]",
    pinNone: "None",
    fieldBadge: "Badge",
    fieldCustomIcon: "Icon (empty = web)",
    fieldBadgeAndIcon: "Badge / Icon",
    fieldColorAccent: "Color accent (optional — click again to unselect)",
    colorNone: "✕ None",
    btnCancel: "Cancel",
    btnSaveItem: "Save item",

    // Modal B: Add / Edit Category
    modalEditCategoryTitle: "Edit category",
    modalAddCategoryTitle: "New category",
    fieldCategoryName: "Category name",
    fieldCategoryPlaceholder: "e.g. Cloud & Infra",
    fieldIcon: "Icon",
    fieldCategoryColor: "Category color (theme role)",
    fieldCategoryType: "Column source type",
    catTypeStatic: "󰉋 Static Bookmarks",
    catTypeRss: "󰑫 RSS / Atom Feed",
    catTypeGithub: "󰊤 GitHub Repo",
    fieldFeedUrlRss: "RSS / Atom Feed URL",
    fieldFeedUrlRssPlaceholder: "https://hnrss.org/frontpage?count=48",
    fieldFeedUrlGithub: "GitHub Repository (owner/repo)",
    fieldFeedUrlGithubPlaceholder: "e.g. basecamp/omarchy",
    fieldGithubMode: "GitHub Feed Filter",
    ghModeAll: "Issues & PRs",
    ghModeIssues: "Issues only",
    ghModePrs: "PRs only",
    ghModeReleases: "Releases",
    feedPresetsLabel: "Quick feed presets:",
    liveRefreshTooltip: "Refresh live feed",
    liveFetchingText: "Fetching live feed...",
    liveEmptyText: "No live entries yet. Click 󰑐 to refresh.",
    liveLoadMore: "Load more",
    ctxPinLiveItem: "󰐃  Save as permanent bookmark",
    statusLivePinned: "Saved to space bookmarks: ",
    statusFeedsRefreshed: "Live feeds refreshed",
    btnDeleteCategory: "󰩺 Delete category",
    btnSaveCategory: "Save category",

    // Modal C: Add / Edit Space
    modalEditSpaceTitle: "Edit Space",
    modalAddSpaceTitle: "New Space",
    fieldSpaceName: "Space name",
    fieldSpacePlaceholder: "e.g. Homelab & Infra",
    btnDeleteSpace: "󰩺 Delete space",
    btnSaveSpace: "Save space",

    // Modal D: Import Bookmarks
    modalImportTitle: "Import bookmarks into space: ",
    modalImportSubtitle: "Select a detected browser profile or exported HTML file. Each checked folder will be created as a category in the active space.",
    scanningBookmarksText: "Scanning installed browsers for bookmarks...",
    noBookmarksFoundText: "No browser bookmarks or ~/Downloads/bookmarks.html found.",
    linksCountSuffix: "links",
    btnImportSelected: "Import selected folders",

    // Notes
    notesInboxName: "Unsorted",
    notesScanFailed: "Could not refresh notes",
    notesRootSkipped: "A notes folder was skipped",
    notesTooLarge: "This note is too large to edit here",
    notesSaveFailed: "Could not save the note",
    notesFoldersBtn: "Folders",
    notesFoldersTitle: "Note folders",
    notesWriteRootField: "Folder for new notes",
    notesExtraRootField: "Also read these folders",
    notesAddRootPlaceholder: "/path/to/folder",
    notesEditAction: "Edit details",
    notesTrashAction: "Move to trash",
    notesFilenameField: "Filename",
    notesRenameFailed: "Could not rename the note",
    notesTrashFailed: "Could not move the note to the trash",
    notesTrashConfirm: "Move this note to the trash?",
    notesExternalChange: "This note changed on disk",
    notesFileGone: "This note is no longer on disk",
    notesOpenOmawrite: "Open in Omawrite",
    notesRenameAction: "Rename"
  },

  cs: {
    // Top Header
    addItemBtn: "+ Položka",
    addItemTooltip: "Přidat odkaz, příkaz nebo lokální aplikaci (Ctrl+N)",
    addCategoryBtn: "+ Kategorie",
    addCategoryTooltip: "Vytvořit novou barevnou kategorii",
    importBtn: "󰋺 Import",
    importTooltip: "Importovat záložky z prohlížeče nebo HTML",
    closeTooltip: "Zavřít (Esc)",
    langTooltip: "Přepnout jazyk rozhraní (Auto / EN / CS)",
    shortcutSetBtnLabel: "Nastavit zkratku",
    shortcutBtnTooltip: "Globální klávesová zkratka pro otevření Megamenu (klikni pro změnu)",
    browserHostBtn: "Ukládání stránek",
    browserHostBtnOn: "Ukládání zapnuto",
    browserHostTooltip: "Zaregistruje místního pomocníka, aby Firefox/Zen mohly zapisovat do Megamenu. Rozšíření Omarchy Megamenu si musíš zvlášť nainstalovat z Mozilla Add-ons (Firefox nebo Zen).",
    browserHostTooltipOn: "Místní pomocník je zapnutý. Ve Firefoxu nebo Zenu si ještě nainstaluj Omarchy Megamenu z Mozilla Add-ons, ať můžeš ukládat stránku z lišty.",
    statusBrowserHostSaved: "Firefox a Zen můžou ukládat stránky do Megamenu",
    statusBrowserHostError: "Pomocníka pro prohlížeč se nepodařilo zaregistrovat: ",
    spacesMoreBtn: "Více",
    spacesDropdownHeader: "VŠECHNY PROSTORY",
    spacesAddAction: "+ Vytvořit nový prostor",
    spaceEditTooltip: "Upravit prostor",
    modalShortcutTitle: "Globální klávesová zkratka (Opt-in)",
    modalShortcutSubtitle: "Vyber nebo zadej zkratku v Hyprlandu, kterou otevřeš Megamenu odkudkoliv jako Spotlight. Uložením výslovně zapíšeš blok zkratky do ~/.config/hypr/bindings.lua.",
    fieldShortcutCombo: "Klávesová kombinace",
    shortcutPresetsLabel: "Rychlé předvolby:",
    shortcutNoneBtn: "Vypnout zkratku",
    shortcutSaveBtn: "Uložit zkratku",
    statusShortcutSaved: "Globální zkratka nastavena na: ",
    statusShortcutRemoved: "Globální zkratka vypnuta",
    statusShortcutError: "Chyba zkratky: ",

    // Search & Filters
    searchPlaceholder: "Hledat ve všech prostorech, příkazy, Omarchy akce, nebo '>' pro apps...",
    filterAll: "Vše",
    filterFavorites: "★ Oblíbené",
    omarchyColumnName: "Omarchy & Aplikace",
    otherSpaceBadge: "PROSTOR",
    frequentHeader: "★ NEJČASTĚJŠÍ",

    // Orbit Section
    orbitHeader: "󱐋 QUICK ACCESS / PRIMARY ORBIT",
    orbitSubheader: "/  Stiskni klávesu [ 1 – 6 ]",
    localStorageBadge: "LOCAL STORAGE",
    slotPrefix: "+ Slot",
    clickToPin: "Klikni pro připnutí",

    // Category Grid & System Apps
    itemsCountOne: "1 položka",
    itemsCountFew: "{count} položky",
    itemsCountMany: "{count} položek",
    systemAppsHeader: "󱓞 Systémové akce Omarchy, aplikace a příkazy (Enter pro spuštění, '+' pro připnutí)",
    pinToCategoryBtn: "+ Připnout do kategorie",
    noAppsMatchedText: "Žádné odpovídající akce Omarchy, aplikace ani příkazy nebyly nalezeny.",

    // Footer & Status Messages
    footerActiveSpace: "AKTIVNÍ PROSTOR",
    footerItems: "POLOŽEK",
    footerBrowsers: "PROHLÍŽEČŮ",
    footerShortcuts: "↑↓←→ Navigace   •   Tab Prostor   •   1-6 Orbit   •   Enter Spustit   •   Pravý klik / Alt+M Akce   •   Alt+E Upravit   •   Esc Zavřít",
    statusCopied: "Zkopírováno do schránky: ",
    statusEnterItemTitle: "Zadej název položky",
    statusEnterCommand: "Zadej příkaz",
    statusItemSaved: "Položka uložena: ",
    statusItemDeleted: "Položka smazána: ",
    statusAppPinned: "Aplikace přidána do Megamenu: ",
    statusEnterCategoryName: "Zadej název kategorie",
    statusCategorySaved: "Kategorie uložena: ",
    statusCategoryDeleted: "Kategorie smazána",
    statusEnterSpaceName: "Zadej název prostoru",
    statusSpaceSaved: "Prostor uložen: ",
    statusSpaceDeleted: "Prostor smazán",
    statusNoFolderSelected: "Nevybrána žádná složka k importu",
    statusBookmarksImported: "Záložky byly naimportovány do prostoru",

    // Context Menu
    ctxLaunchInTarget: "OTEVŘÍT V PROHLÍŽEČI...",
    ctxOpenIn: "Otevřít v ",
    ctxDefaultBadge: "Default",
    ctxLaunchApp: "󰀻  Spustit aplikaci",
    ctxCopyDesktopId: "󰆏  Kopírovat Desktop ID",
    ctxCopyUrl: "󰆏  Kopírovat URL",
    ctxCopyCommand: "󰆏  Kopírovat příkaz",
    ctxEditItem: "󰏫  Upravit položku",
    ctxMoveTo: "󰀻  Přesunout do…",
    ctxMoveBack: "← Prostory",
    statusItemMoved: "Přesunuto: ",
    statusMoveFailed: "Položku nelze přesunout (chybí prostor nebo kategorie)",
    ctxDelete: "󰩺  Smazat",

    // Modal A: Add / Edit Item
    modalEditItemTitle: "Upravit položku",
    modalAddItemTitle: "Přidat novou položku",
    typeWebLink: "󰖟 Webový odkaz",
    typeLocalApp: "󰀻 Lokální aplikace",
    typeCommand: "󰆍 Příkaz",
    fieldCommand: "Příkaz",
    fieldCommandPlaceholder: "např. restic-backup",
    fieldCwd: "Pracovní adresář (volitelné)",
    fieldCwdPlaceholder: "např. ~/Work/projekt",
    runModeTerminal: "Terminál",
    runModeBackground: "Na pozadí",
    commandDonePrompt: "Hotovo (kód %1) — stiskni libovolnou klávesu",
    pickInstalledAppLabel: "Vybrat nainstalovanou aplikaci:",
    searchAppPlaceholder: "Hledat aplikaci (např. Ghostty, Cursor, Spotify)...",
    fieldTitle: "Název",
    fieldTitlePlaceholder: "Např. Cloudflare Dashboard",
    fieldSubtitle: "Podtitulek / Popis",
    fieldSubtitlePlaceholder: "Např. dash.cloudflare.com • DNS",
    fieldUrl: "URL adresa",
    fieldCategory: "Kategorie",
    fieldSpace: "Prostor",
    fieldPinOrbit: "Připnout do Quick Orbitu [1-6]",
    pinNone: "Nic",
    fieldBadge: "Štítek (Badge)",
    fieldCustomIcon: "Ikona (prázdné = web)",
    fieldBadgeAndIcon: "Štítek / Ikona",
    fieldColorAccent: "Barevný akcent (volitelné — kliknutím lze i odznačit)",
    colorNone: "✕ Žádná",
    btnCancel: "Zrušit",
    btnSaveItem: "Uložit položku",

    // Modal B: Add / Edit Category
    modalEditCategoryTitle: "Upravit kategorii",
    modalAddCategoryTitle: "Nová kategorie",
    fieldCategoryName: "Název kategorie",
    fieldCategoryPlaceholder: "Např. Cloud & Infra",
    fieldIcon: "Ikona",
    fieldCategoryColor: "Barva kategorie (podle tématu)",
    fieldCategoryType: "Typ zdroje sloupce",
    catTypeStatic: "󰉋 Statické záložky",
    catTypeRss: "󰑫 RSS / Atom Feed",
    catTypeGithub: "󰊤 GitHub Repo",
    fieldFeedUrlRss: "URL adresa RSS / Atom feedu",
    fieldFeedUrlRssPlaceholder: "https://hnrss.org/frontpage?count=48",
    fieldFeedUrlGithub: "GitHub repozitář (owner/repo)",
    fieldFeedUrlGithubPlaceholder: "Např. basecamp/omarchy",
    fieldGithubMode: "Filtr GitHub přehledu",
    ghModeAll: "Issues i PRs",
    ghModeIssues: "Jen Issues",
    ghModePrs: "Jen Pull Requesty",
    ghModeReleases: "Vydání (Releases)",
    feedPresetsLabel: "Rychlé předvolby živých zdrojů:",
    liveRefreshTooltip: "Obnovit živý feed",
    liveFetchingText: "Stahuji živý feed...",
    liveEmptyText: "Zatím žádné položky. Klikni na 󰑐 pro obnovení.",
    liveLoadMore: "Načíst další",
    ctxPinLiveItem: "󰐃  Uložit jako trvalou záložku",
    statusLivePinned: "Uloženo mezi záložky prostoru: ",
    statusFeedsRefreshed: "Živé feedy aktualizovány",
    btnDeleteCategory: "󰩺 Smazat kategorii",
    btnSaveCategory: "Uložit kategorii",

    // Modal C: Add / Edit Space
    modalEditSpaceTitle: "Upravit prostor (Space)",
    modalAddSpaceTitle: "Nový prostor (Space)",
    fieldSpaceName: "Název prostoru",
    fieldSpacePlaceholder: "Např. Homelab & Infra",
    btnDeleteSpace: "󰩺 Smazat prostor",
    btnSaveSpace: "Uložit prostor",

    // Modal D: Import Bookmarks
    modalImportTitle: "Importovat záložky do prostoru: ",
    modalImportSubtitle: "Vyber nalezený profil prohlížeče nebo exportovaný HTML soubor. Každá vybraná složka se vytvoří jako kategorie v aktivním prostoru.",
    scanningBookmarksText: "Hledám záložky v nainstalovaných prohlížečích...",
    noBookmarksFoundText: "Nebyly nalezeny žádné záložky v prohlížečích ani soubor bookmarks.html v ~/Downloads.",
    linksCountSuffix: "odkazů",
    btnImportSelected: "Naimportovat vybrané složky",

    // Notes
    notesInboxName: "Nezařazené",
    notesScanFailed: "Poznámky se nepodařilo obnovit",
    notesRootSkipped: "Složka s poznámkami byla přeskočena",
    notesTooLarge: "Tato poznámka je na úpravu tady příliš velká",
    notesSaveFailed: "Poznámku se nepodařilo uložit",
    notesFoldersBtn: "Složky",
    notesFoldersTitle: "Složky poznámek",
    notesWriteRootField: "Složka pro nové poznámky",
    notesExtraRootField: "Číst také z těchto složek",
    notesAddRootPlaceholder: "/cesta/ke/složce",
    notesEditAction: "Upravit údaje",
    notesTrashAction: "Přesunout do koše",
    notesFilenameField: "Název souboru",
    notesRenameFailed: "Poznámku se nepodařilo přejmenovat",
    notesTrashFailed: "Poznámku se nepodařilo přesunout do koše",
    notesTrashConfirm: "Přesunout tuhle poznámku do koše?",
    notesExternalChange: "Tahle poznámka se změnila na disku",
    notesFileGone: "Tahle poznámka už na disku není",
    notesOpenOmawrite: "Otevřít v Omawrite",
    notesRenameAction: "Přejmenovat"
  }
}

function resolveLang(langSetting, envLocale) {
  var pref = String(langSetting || "auto").trim().toLowerCase()
  if (pref === "cs" || pref === "cz" || pref.indexOf("cs") === 0) return "cs"
  if (pref === "en" || pref.indexOf("en") === 0) return "en"

  var env = String(envLocale || "").trim().toLowerCase()
  if (env.indexOf("cs") === 0 || env.indexOf("sk") === 0) return "cs"
  return "en"
}

function nextLanguagePref(currentPref) {
  var p = String(currentPref || "auto").toLowerCase()
  if (p === "auto") return "en"
  if (p === "en") return "cs"
  return "auto"
}

function t(lang, key) {
  var code = (lang === "cs") ? "cs" : "en"
  var table = STRINGS[code] || STRINGS.en
  if (table[key] !== undefined) return table[key]
  if (STRINGS.en[key] !== undefined) return STRINGS.en[key]
  return key
}

function formatItemsCount(lang, count) {
  var n = Number(count || 0)
  if (n === 1) return t(lang, "itemsCountOne")
  if (lang === "cs" && n >= 2 && n <= 4) {
    return t(lang, "itemsCountFew").replace("{count}", String(n))
  }
  return t(lang, "itemsCountMany").replace("{count}", String(n))
}

if (typeof module !== "undefined") {
  module.exports = {
    SUPPORTED_LANGUAGES: SUPPORTED_LANGUAGES,
    STRINGS: STRINGS,
    resolveLang: resolveLang,
    nextLanguagePref: nextLanguagePref,
    t: t,
    formatItemsCount: formatItemsCount
  }
}
