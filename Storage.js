// Storage.js - Pure data model, validation, CRUD, filtering, and default seed data for Omarchy Megamenu

// Strip markup so Qt Text (default AutoText) never treats saved titles as rich HTML.
function plainTextLabel(value) {
  var s = String(value || "")
  s = s.replace(/&nbsp;/gi, " ")
  s = s.replace(/&lt;/gi, "<")
  s = s.replace(/&gt;/gi, ">")
  s = s.replace(/&quot;/gi, "\"")
  s = s.replace(/&#39;/g, "'")
  s = s.replace(/&amp;/gi, "&")
  s = s.replace(/&#(\d+);/g, function(_, n) {
    var code = parseInt(n, 10)
    return (isFinite(code) && code > 0) ? String.fromCharCode(code) : ""
  })
  s = s.replace(/<[^>]*>/g, " ")
  s = s.replace(/\s+/g, " ").trim()
  return s
}

function sanitizeLiveFeedsMap(feeds) {
  if (!feeds || typeof feeds !== "object") return {}
  var out = {}
  var keys = Object.keys(feeds)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var feed = feeds[key]
    if (!feed || typeof feed !== "object") {
      out[key] = feed
      continue
    }
    var items = Array.isArray(feed.items) ? feed.items : []
    var cleanItems = []
    for (var j = 0; j < items.length; j++) {
      var it = items[j]
      if (!it || typeof it !== "object") continue
      var copy = {}
      for (var prop in it) {
        if (Object.prototype.hasOwnProperty.call(it, prop)) copy[prop] = it[prop]
      }
      copy.title = plainTextLabel(copy.title)
      copy.subtitle = plainTextLabel(copy.subtitle)
      copy.badgeText = plainTextLabel(copy.badgeText)
      cleanItems.push(copy)
    }
    out[key] = {
      items: cleanItems,
      updatedAt: feed.updatedAt,
      error: feed.error
    }
  }
  return out
}

function extractDomain(url) {
  var s = String(url || "").trim()
  if (!s) return ""
  var m = s.match(/^(?:https?:\/\/)?(?:www\.)?([^\/:?#]+)/i)
  return m && m[1] ? m[1].toLowerCase() : ""
}

function monogramFor(title, url) {
  var domain = extractDomain(url)
  if (domain) {
    var base = domain.split(".")[0]
    if (base && base.length >= 2) return base.slice(0, 1).toUpperCase()
  }
  var t = String(title || "").trim()
  if (!t) return "•"
  return t.charAt(0).toUpperCase()
}

function normalizeUrl(url) {
  var s = String(url || "").trim()
  if (!s) return ""
  if (!s.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//)) {
    return "https://" + s
  }
  return s
}

function uid(prefix) {
  return (prefix || "id") + "-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 100000).toString(36)
}

function defaultData() {
  return {
    version: 1,
    language: "auto",
    activeSpaceId: "dev-matrix",
    spaces: [
      { id: "personal", name: "Personal Space", icon: "󰋜" },
      { id: "dev-matrix", name: "Dev Matrix", icon: "󰆍" },
      { id: "work-core", name: "Work Core", icon: "󰒍" },
      { id: "live-pulse", name: "Live Pulse", icon: "󰑫" },
      { id: "reading-list", name: "Seznam čtení", icon: "󰂺" }
    ],
    categories: [
      // Dev Matrix categories
      { id: "cat-dev", spaceId: "dev-matrix", name: "Dev & Engineering", icon: "󰆍", colorRole: "green", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-cloud", spaceId: "dev-matrix", name: "Cloud & Infra", icon: "󰅟", colorRole: "blue", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-design", spaceId: "dev-matrix", name: "Product & Design", icon: "󰏘", colorRole: "magenta", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-ops", spaceId: "dev-matrix", name: "Workspace & Ops", icon: "󰒍", colorRole: "cyan", type: "static", feedUrl: "", feedMode: "all" },
      // Personal Space categories
      { id: "cat-media", spaceId: "personal", name: "Media & Stream", icon: "󰕧", colorRole: "red", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-social", spaceId: "personal", name: "Community & News", icon: "󰭹", colorRole: "yellow", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-local", spaceId: "personal", name: "Local Tools", icon: "󰀻", colorRole: "cyan", type: "static", feedUrl: "", feedMode: "all" },
      // Work Core categories
      { id: "cat-work-docs", spaceId: "work-core", name: "Docs & Specs", icon: "󰈙", colorRole: "blue", type: "static", feedUrl: "", feedMode: "all" },
      { id: "cat-work-comm", spaceId: "work-core", name: "Communication", icon: "󰇮", colorRole: "green", type: "static", feedUrl: "", feedMode: "all" },
      // Live Pulse categories (RSS + GitHub Feeds) - 2 wide columns by default for full title readability
      { id: "cat-live-omarchy", spaceId: "live-pulse", name: "Omarchy PRs & Issues", icon: "󰊤", colorRole: "green", type: "github", feedUrl: "basecamp/omarchy", feedMode: "all" },
      { id: "cat-live-hn", spaceId: "live-pulse", name: "Hacker News", icon: "󰑫", colorRole: "orange", type: "rss", feedUrl: "https://hnrss.org/frontpage?count=48", feedMode: "all" },
      // Reading list — stable ids shared with scripts/native-host.py
      { id: "cat-reading", spaceId: "reading-list", name: "K přečtení", icon: "󰈙", colorRole: "yellow", type: "static", feedUrl: "", feedMode: "all" }
    ],
    items: [
      // Dev Matrix - Quick Orbit [1-6] + Categories
      {
        id: "item-github",
        spaceId: "dev-matrix",
        categoryId: "cat-dev",
        type: "url",
        title: "GitHub",
        subtitle: "github.com • PRs & Repos",
        url: "https://github.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰊤",
        favorite: true,
        pinnedSlot: 1,
        badgeText: "Active",
        colorRole: "green"
      },
      {
        id: "item-vercel",
        spaceId: "dev-matrix",
        categoryId: "cat-cloud",
        type: "url",
        title: "Vercel",
        subtitle: "vercel.com • Deployments",
        url: "https://vercel.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "▲",
        favorite: true,
        pinnedSlot: 2,
        badgeText: "Live",
        colorRole: "green"
      },
      {
        id: "item-linear",
        spaceId: "dev-matrix",
        categoryId: "cat-ops",
        type: "url",
        title: "Linear",
        subtitle: "linear.app • Issue Tracker",
        url: "https://linear.app",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰓾",
        favorite: true,
        pinnedSlot: 3,
        badgeText: "Work",
        colorRole: "blue"
      },
      {
        id: "item-figma",
        spaceId: "dev-matrix",
        categoryId: "cat-design",
        type: "url",
        title: "Figma",
        subtitle: "figma.com • Design System",
        url: "https://figma.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰏘",
        favorite: false,
        pinnedSlot: 4,
        badgeText: "Design",
        colorRole: "magenta"
      },
      {
        id: "item-cloudflare",
        spaceId: "dev-matrix",
        categoryId: "cat-cloud",
        type: "url",
        title: "Cloudflare Dashboard",
        subtitle: "dash.cloudflare.com • DNS & Workers",
        url: "https://dash.cloudflare.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰅟",
        favorite: true,
        pinnedSlot: 5,
        badgeText: "Edge",
        colorRole: "orange"
      },
      {
        id: "item-supabase",
        spaceId: "dev-matrix",
        categoryId: "cat-cloud",
        type: "url",
        title: "Supabase",
        subtitle: "supabase.com • Postgres & Auth",
        url: "https://supabase.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󱐋",
        favorite: false,
        pinnedSlot: 6,
        badgeText: "Online",
        colorRole: "green"
      },
      // Dev & Engineering additional items
      {
        id: "item-claude",
        spaceId: "dev-matrix",
        categoryId: "cat-dev",
        type: "url",
        title: "Claude AI / Anthropic",
        subtitle: "claude.ai • Next-gen LLM chat",
        url: "https://claude.ai",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰚩",
        favorite: true,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "orange"
      },
      {
        id: "item-nextjs",
        spaceId: "dev-matrix",
        categoryId: "cat-dev",
        type: "url",
        title: "Next.js Documentation",
        subtitle: "nextjs.org • App Router Specs",
        url: "https://nextjs.org/docs",
        desktopId: "",
        iconType: "favicon",
        iconValue: "N",
        favorite: true,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "blue"
      },
      {
        id: "item-tailwind",
        spaceId: "dev-matrix",
        categoryId: "cat-dev",
        type: "url",
        title: "Tailwind CSS",
        subtitle: "tailwindcss.com • v4 Guide",
        url: "https://tailwindcss.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󱏿",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "cyan"
      },
      {
        id: "item-npm",
        spaceId: "dev-matrix",
        categoryId: "cat-dev",
        type: "url",
        title: "NPM Registry",
        subtitle: "npmjs.com • Packages & Metrics",
        url: "https://www.npmjs.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰎙",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "red"
      },
      // Cloud & Infra additional
      {
        id: "item-aws",
        spaceId: "dev-matrix",
        categoryId: "cat-cloud",
        type: "url",
        title: "AWS Management Console",
        subtitle: "aws.amazon.com • Console",
        url: "https://console.aws.amazon.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰸏",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "yellow"
      },
      {
        id: "item-netlify",
        spaceId: "dev-matrix",
        categoryId: "cat-cloud",
        type: "url",
        title: "Netlify Dashboard",
        subtitle: "app.netlify.com • Deployments",
        url: "https://app.netlify.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰅟",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "cyan"
      },
      // Product & Design
      {
        id: "item-lucide",
        spaceId: "dev-matrix",
        categoryId: "cat-design",
        type: "url",
        title: "Lucide Icons",
        subtitle: "lucide.dev • Vector specs",
        url: "https://lucide.dev",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰀻",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "magenta"
      },
      {
        id: "item-dribbble",
        spaceId: "dev-matrix",
        categoryId: "cat-design",
        type: "url",
        title: "Dribbble Feed",
        subtitle: "dribbble.com • UI Inspirations",
        url: "https://dribbble.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰏘",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "red"
      },
      // Workspace & Ops
      {
        id: "item-notion",
        spaceId: "dev-matrix",
        categoryId: "cat-ops",
        type: "url",
        title: "Notion Workspace",
        subtitle: "notion.so • Wiki & RFCs",
        url: "https://www.notion.so",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰈙",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "cyan"
      },
      {
        id: "item-calendar",
        spaceId: "dev-matrix",
        categoryId: "cat-ops",
        type: "url",
        title: "Google Calendar",
        subtitle: "calendar.google.com • Schedule",
        url: "https://calendar.google.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰃭",
        favorite: false,
        pinnedSlot: 0,
        badgeText: "",
        colorRole: "blue"
      },
      // Personal Space items
      {
        id: "item-youtube",
        spaceId: "personal",
        categoryId: "cat-media",
        type: "url",
        title: "YouTube",
        subtitle: "youtube.com • Videos",
        url: "https://www.youtube.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰗃",
        favorite: true,
        pinnedSlot: 1,
        badgeText: "Stream",
        colorRole: "red"
      },
      {
        id: "item-hn",
        spaceId: "personal",
        categoryId: "cat-social",
        type: "url",
        title: "Hacker News",
        subtitle: "news.ycombinator.com • Tech News",
        url: "https://news.ycombinator.com",
        desktopId: "",
        iconType: "favicon",
        iconValue: "Y",
        favorite: true,
        pinnedSlot: 2,
        badgeText: "News",
        colorRole: "orange"
      },
      // Work Core items
      {
        id: "item-work-gh",
        spaceId: "work-core",
        categoryId: "cat-work-docs",
        type: "url",
        title: "Omarchy Docs",
        subtitle: "omarchy.org • System Manual",
        url: "https://omarchy.org",
        desktopId: "",
        iconType: "favicon",
        iconValue: "󰈙",
        favorite: true,
        pinnedSlot: 1,
        badgeText: "Core",
        colorRole: "blue"
      }
    ],
    notes: { writeRoot: "", roots: [], cards: [] }
  }
}

function sanitizeItem(raw, fallbackSpaceId, fallbackCategoryId) {
  if (!raw || typeof raw !== "object") return null
  var type = raw.type === "app" ? "app" : (raw.type === "command" ? "command" : "url")
  var title = plainTextLabel(raw.title)
  if (!title) return null
  var url = type === "url" ? normalizeUrl(raw.url || "") : ""
  var desktopId = type === "app" ? String(raw.desktopId || "").trim() : ""
  var command = type === "command" ? String(raw.command || "").trim() : ""
  if (type === "command" && !command) return null
  var cwd = type === "command" ? String(raw.cwd || "").trim() : ""
  var runMode = ""
  if (type === "command") {
    runMode = String(raw.runMode || "").toLowerCase() === "background" ? "background" : "terminal"
  }
  var domain = extractDomain(url)
  var subtitle = plainTextLabel(raw.subtitle)
  if (!subtitle) {
    if (type === "url") subtitle = domain
    else if (type === "command") subtitle = command
    else subtitle = desktopId
  }
  var pinned = Number(raw.pinnedSlot || 0)
  if (!isFinite(pinned) || pinned < 0 || pinned > 6) pinned = 0

  var launchCount = Number(raw.launchCount || 0)
  if (!isFinite(launchCount) || launchCount < 0) launchCount = 0
  launchCount = Math.round(launchCount)

  var lastLaunchedAt = Number(raw.lastLaunchedAt || 0)
  if (!isFinite(lastLaunchedAt) || lastLaunchedAt < 0) lastLaunchedAt = 0
  lastLaunchedAt = Math.round(lastLaunchedAt)

  var iconType = String(raw.iconType || "")
  if (!iconType) {
    iconType = type === "app" ? "system" : (type === "command" ? "glyph" : "favicon")
  }
  var iconValue = String(raw.iconValue || "")
  if (type === "command") {
    if (iconType === "system" || iconType === "favicon") iconType = "glyph"
    if (!iconValue) iconValue = "󰆍"
  }

  return {
    id: String(raw.id || uid("item")),
    spaceId: String(raw.spaceId || fallbackSpaceId || "dev-matrix"),
    categoryId: String(raw.categoryId || fallbackCategoryId || ""),
    type: type,
    title: title,
    subtitle: subtitle,
    url: url,
    desktopId: desktopId,
    command: command,
    cwd: cwd,
    runMode: runMode,
    iconType: iconType,
    iconValue: iconValue,
    favorite: raw.favorite === true,
    pinnedSlot: Math.round(pinned),
    badgeText: plainTextLabel(raw.badgeText),
    colorRole: String(raw.colorRole !== undefined && raw.colorRole !== null ? raw.colorRole : ""),
    launchCount: launchCount,
    lastLaunchedAt: lastLaunchedAt
  }
}

function parse(rawText) {
  if (!rawText || !String(rawText).trim()) return defaultData()
  var parsed
  try {
    parsed = JSON.parse(rawText)
  } catch (e) {
    return defaultData()
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.spaces) || parsed.spaces.length === 0) {
    return defaultData()
  }

  var spaces = []
  var spaceIds = {}
  for (var i = 0; i < parsed.spaces.length; i++) {
    var sp = parsed.spaces[i]
    if (!sp || !sp.id || !sp.name) continue
    var sid = String(sp.id)
    var spName = plainTextLabel(sp.name)
    if (!spName) continue
    spaces.push({
      id: sid,
      name: spName,
      icon: String(sp.icon || "󰀻"),
      type: String(sp.type || "") === "notes" ? "notes" : ""
    })
    spaceIds[sid] = true
  }
  if (spaces.length === 0) return defaultData()

  var activeSpaceId = String(parsed.activeSpaceId || spaces[0].id)
  if (!spaceIds[activeSpaceId]) activeSpaceId = spaces[0].id

  var categories = []
  var catIds = {}
  var rawCats = Array.isArray(parsed.categories) ? parsed.categories : []
  for (var j = 0; j < rawCats.length; j++) {
    var c = rawCats[j]
    if (!c || !c.id || !c.name) continue
    var cid = String(c.id)
    var cSpace = spaceIds[c.spaceId] ? String(c.spaceId) : spaces[0].id
    var rawType = String(c.type || "static").toLowerCase()
    var catType = (rawType === "rss" || rawType === "github") ? rawType : "static"
    var rawMode = String(c.feedMode || "all").toLowerCase()
    var feedMode = (rawMode === "issues" || rawMode === "prs" || rawMode === "releases") ? rawMode : "all"
    var catName = plainTextLabel(c.name)
    if (!catName) continue
    categories.push({
      id: cid,
      spaceId: cSpace,
      name: catName,
      icon: String(c.icon || "󰉋"),
      colorRole: String(c.colorRole || "blue"),
      type: catType,
      feedUrl: String(c.feedUrl || "").trim(),
      feedMode: feedMode
    })
    catIds[cid] = cSpace
  }

  var items = []
  var rawItems = Array.isArray(parsed.items) ? parsed.items : []
  for (var k = 0; k < rawItems.length; k++) {
    var it = sanitizeItem(rawItems[k], activeSpaceId, "")
    if (!it) continue
    if (!spaceIds[it.spaceId]) it.spaceId = activeSpaceId
    items.push(it)
  }

  var rawLang = String(parsed.language || "auto").toLowerCase()
  var language = (rawLang === "en" || rawLang === "cs") ? rawLang : "auto"

  return {
    version: 1,
    language: language,
    activeSpaceId: activeSpaceId,
    spaces: spaces,
    categories: categories,
    items: items,
    notes: sanitizeNotes(parsed.notes)
  }
}

function sanitizeNotes(raw) {
  var base = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {}
  var roots = []
  var rawRoots = Array.isArray(base.roots) ? base.roots : []
  for (var i = 0; i < rawRoots.length; i++) {
    if (rawRoots[i] === undefined || rawRoots[i] === null) continue
    var root = String(rawRoots[i])
    if (!root) continue
    roots.push(root)
  }
  var cards = []
  var rawCards = Array.isArray(base.cards) ? base.cards : []
  for (var c = 0; c < rawCards.length; c++) {
    var card = rawCards[c]
    if (!card || typeof card !== "object") continue
    var path = String(card.path || "")
    if (!path) continue
    var pinned = Number(card.pinnedSlot)
    if (!isFinite(pinned)) pinned = 0
    pinned = Math.round(pinned)
    if (pinned < 0) pinned = 0
    if (pinned > 6) pinned = 6
    cards.push({
      path: path,
      categoryId: String(card.categoryId || ""),
      colorRole: String(card.colorRole || ""),
      badgeText: String(card.badgeText || ""),
      pinnedSlot: pinned
    })
  }
  return {
    writeRoot: String(base.writeRoot || ""),
    roots: roots,
    cards: cards
  }
}

function ensureNotesModel(data, inboxName) {
  var src = (data && typeof data === "object") ? data : {}
  var next = {}
  for (var key in src) {
    if (Object.prototype.hasOwnProperty.call(src, key)) next[key] = src[key]
  }
  next.spaces = Array.isArray(src.spaces) ? src.spaces.slice() : []
  next.categories = Array.isArray(src.categories) ? src.categories.slice() : []

  var hasNotesSpace = false
  for (var i = 0; i < next.spaces.length; i++) {
    if (next.spaces[i] && String(next.spaces[i].id) === "notes") {
      hasNotesSpace = true
      break
    }
  }
  if (!hasNotesSpace) {
    next.spaces.push({
      id: "notes",
      name: "Note",
      icon: "󰈙",
      type: "notes"
    })
  }

  var hasInbox = false
  for (var j = 0; j < next.categories.length; j++) {
    if (next.categories[j] && String(next.categories[j].id) === "cat-notes-inbox") {
      hasInbox = true
      break
    }
  }
  if (!hasInbox) {
    var inbox = String(inboxName || "").trim()
    if (!inbox) inbox = "Unsorted"
    next.categories.push({
      id: "cat-notes-inbox",
      spaceId: "notes",
      name: inbox,
      icon: "󰈙",
      colorRole: "yellow",
      type: "static",
      feedUrl: "",
      feedMode: "all"
    })
  }

  if (!next.notes || typeof next.notes !== "object" || Array.isArray(next.notes)) {
    next.notes = { writeRoot: "", roots: [], cards: [] }
  }
  return next
}

function serialize(data) {
  return JSON.stringify(data || defaultData(), null, 2) + "\n"
}

function cloneData(data) {
  return parse(JSON.stringify(data || defaultData()))
}

function categoriesForSpace(data, spaceId) {
  var list = (data && Array.isArray(data.categories)) ? data.categories : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].spaceId === spaceId) out.push(list[i])
  }
  return out
}

function isStaticCategory(cat) {
  if (!cat) return false
  var t = String(cat.type || "").toLowerCase()
  return t === "" || t === "static"
}

function staticCategoriesForSpace(data, spaceId) {
  var all = categoriesForSpace(data, spaceId)
  var out = []
  for (var i = 0; i < all.length; i++) {
    if (isStaticCategory(all[i])) out.push(all[i])
  }
  return out
}

function itemsForSpace(data, spaceId) {
  var list = (data && Array.isArray(data.items)) ? data.items : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].spaceId === spaceId) out.push(list[i])
  }
  return out
}

function pinnedOrbitForSpace(data, spaceId) {
  var items = itemsForSpace(data, spaceId)
  var slots = [null, null, null, null, null, null]
  for (var i = 0; i < items.length; i++) {
    var s = items[i].pinnedSlot
    if (s >= 1 && s <= 6 && !slots[s - 1]) {
      slots[s - 1] = items[i]
    }
  }
  return slots
}

function matchesItemQuery(item, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  if (String(item.title || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.subtitle || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.url || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.desktopId || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.command || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.cwd || "").toLowerCase().indexOf(q) !== -1) return true
  if (String(item.badgeText || "").toLowerCase().indexOf(q) !== -1) return true
  return false
}

function searchCommandItems(data, query, maxResults) {
  var items = (data && Array.isArray(data.items)) ? data.items : []
  var limit = (maxResults && maxResults > 0) ? maxResults : 20
  var out = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item || item.type !== "command") continue
    if (!matchesItemQuery(item, query)) continue
    out.push(item)
    if (out.length >= limit) break
  }
  return out
}

function bashSingleQuote(value) {
  return "'" + String(value == null ? "" : value).replace(/'/g, "'\\''") + "'"
}

function commandHoldPrintf(holdPrompt) {
  var prompt = String(holdPrompt || "")
  var parts = prompt.split("%1")
  var before = parts.length > 0 ? parts[0] : ""
  var after = parts.length > 1 ? parts.slice(1).join("%1") : ""
  return "printf " + bashSingleQuote("%s%s%s") + " " + bashSingleQuote(before) + " \"$status\" " + bashSingleQuote(after)
}

function commandShellScript(item, holdPrompt) {
  var command = String((item && item.command) || "").trim()
  var cwd = String((item && item.cwd) || "").trim()
  var hold = String(holdPrompt || "")
  var lines = []
  if (cwd && hold) {
    lines.push("cd -- " + bashSingleQuote(cwd))
    lines.push("status=$?")
    lines.push("if [ \"$status\" -ne 0 ]; then")
    lines.push("  echo")
    lines.push("  " + commandHoldPrintf(hold))
    lines.push("  read -n 1 -s -r")
    lines.push("  printf '\\n'")
    lines.push("  exit \"$status\"")
    lines.push("fi")
  } else if (cwd) {
    lines.push("cd -- " + bashSingleQuote(cwd) + " || exit $?")
  }
  lines.push(command)
  if (hold) {
    lines.push("status=$?")
    lines.push("echo")
    lines.push(commandHoldPrintf(hold))
    lines.push("read -n 1 -s -r")
    lines.push("printf '\\n'")
    lines.push("exit \"$status\"")
  }
  return lines.join("\n")
}

function filterItems(data, spaceId, filterId, query, liveFeedsMap) {
  var q = String(query || "").trim()
  var baseSource = q.length > 0 ? ((data && data.items) || []) : itemsForSpace(data, spaceId)
  var source = baseSource.slice()

  if (liveFeedsMap && typeof liveFeedsMap === "object" && data && Array.isArray(data.categories)) {
    for (var c = 0; c < data.categories.length; c++) {
      var cat = data.categories[c]
      if (!cat || (cat.type !== "rss" && cat.type !== "github")) continue
      if (!q && cat.spaceId !== spaceId) continue
      var feedObj = liveFeedsMap[cat.id]
      var feedItems = (feedObj && Array.isArray(feedObj.items)) ? feedObj.items : []
      for (var f = 0; f < feedItems.length; f++) {
        source.push(feedItems[f])
      }
    }
  }

  var out = []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (!q && item.spaceId !== spaceId) continue
    if (filterId === "favorites" && !item.favorite) continue
    if (filterId && filterId !== "all" && filterId !== "favorites" && item.categoryId !== filterId) continue
    if (!matchesItemQuery(item, q)) continue
    out.push(item)
  }
  return out
}

function recordLaunch(data, itemId) {
  var next = cloneData(data)
  var id = String(itemId || "")
  if (!id) return next
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id !== id) continue
    var count = Number(next.items[i].launchCount || 0)
    if (!isFinite(count) || count < 0) count = 0
    next.items[i].launchCount = Math.round(count) + 1
    next.items[i].lastLaunchedAt = Date.now()
    break
  }
  return next
}

function frequentItems(data, limit) {
  var items = (data && Array.isArray(data.items)) ? data.items : []
  var max = (limit && limit > 0) ? limit : 8
  var scored = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (!it) continue
    var count = Number(it.launchCount || 0)
    if (!isFinite(count) || count <= 0) continue
    scored.push(it)
  }
  scored.sort(function(a, b) {
    var ca = Number(a.launchCount || 0)
    var cb = Number(b.launchCount || 0)
    if (cb !== ca) return cb - ca
    var ta = Number(a.lastLaunchedAt || 0)
    var tb = Number(b.lastLaunchedAt || 0)
    return tb - ta
  })
  return scored.slice(0, max)
}

function otherSpaceSearchGroups(data, activeSpaceId, filteredItems) {
  var spaces = (data && Array.isArray(data.spaces)) ? data.spaces : []
  var spaceMap = {}
  for (var s = 0; s < spaces.length; s++) {
    if (spaces[s] && spaces[s].id) spaceMap[String(spaces[s].id)] = spaces[s]
  }
  var active = String(activeSpaceId || "")
  var order = []
  var groups = {}
  var list = Array.isArray(filteredItems) ? filteredItems : []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item) continue
    if (item.isSystemResult || item.isLoadMore) continue
    var sid = String(item.spaceId || "")
    if (!sid || sid === active) continue
    if (!groups[sid]) {
      groups[sid] = []
      order.push(sid)
    }
    groups[sid].push(item)
  }
  var out = []
  for (var o = 0; o < order.length; o++) {
    var id = order[o]
    var sp = spaceMap[id]
    out.push({
      spaceId: id,
      name: sp ? String(sp.name || id) : id,
      icon: sp ? String(sp.icon || "󰀻") : "󰀻",
      items: groups[id]
    })
  }
  return out
}

function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function scoreDesktopEntry(name, id, subtext, keywordsStr, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  var nameLower = name.toLowerCase()
  var idLower = id.toLowerCase()
  var haystack = (name + " " + subtext + " " + keywordsStr + " " + id).toLowerCase()

  var terms = q.split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    var t = terms[i]
    if (!t) continue
    if (haystack.indexOf(t) === -1) return -1
  }

  var directName = nameLower.indexOf(q)
  var directId = idLower.indexOf(q)
  if (directName === 0) return 10000 - nameLower.length
  if (directId === 0) return 9500 - idLower.length
  if (directName > 0) return 8000 - directName * 10 - nameLower.length
  if (directId > 0) return 7600 - directId * 10 - idLower.length
  var hayIdx = haystack.indexOf(q)
  if (hayIdx >= 0) return 6000 - hayIdx
  return 4000 - nameLower.length
}

function searchDesktopEntries(rawEntries, query, hiddenIdsMap, maxResults) {
  var list = rawEntries || []
  var q = String(query || "").trim()
  var hidden = hiddenIdsMap || {}
  var limit = (maxResults && maxResults > 0) ? maxResults : 40
  var matches = []

  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var entry = (item && item.entry !== undefined) ? item.entry : item
    if (!entry || entry.noDisplay === true) continue

    var id = normalizeDesktopId(entry.id || "")
    if (!id || hidden[id] === true) continue

    var name = String(entry.name || id).trim()
    if (!name) continue

    var subtext = String(entry.genericName || entry.comment || "").trim()
    var kw = ""
    try {
      if (entry.keywords && typeof entry.keywords.join === "function") {
        kw = entry.keywords.join(" ")
      }
    } catch (e) {}

    var score = scoreDesktopEntry(name, id, subtext, kw, q)
    if (score < 0) continue

    matches.push({
      id: id,
      name: name,
      subtext: subtext || id,
      icon: String(entry.icon || ""),
      score: score,
      sortKey: name.toLowerCase()
    })
  }

  matches.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.sortKey < b.sortKey) return -1
    if (a.sortKey > b.sortKey) return 1
    return 0
  })

  return matches.slice(0, limit)
}

function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function parseOmarchyMenuJsonc(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return []
  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return []
  }
  if (!parsed || typeof parsed !== "object") return []
  var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items))
    ? parsed.items
    : parsed

  var map = {}
  var ids = []
  for (var id in source) {
    var entry = source[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    var parent = entry.parent
    if (parent === undefined) {
      parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root"
    }
    if (id === "root") parent = ""
    var aliases = Array.isArray(entry.aliases)
      ? entry.aliases.filter(function(v) { return Boolean(v) })
      : (typeof entry.aliases === "string" && entry.aliases ? [entry.aliases] : [])
    var kind = entry.action ? "action" : (entry.target ? "link" : "menu")
    map[id] = {
      id: id,
      parent: parent,
      kind: kind,
      icon: String(entry.icon || "󱓞"),
      iconFont: String(entry.iconFont || ""),
      label: String(entry.label || id),
      action: String(entry.action || ""),
      provider: String(entry.provider || ""),
      aliases: aliases
    }
    ids.push(id)
  }

  var out = []
  for (var i = 0; i < ids.length; i++) {
    var cur = map[ids[i]]
    if (!cur || cur.id === "root" || cur.id === "apps") continue
    // Build breadcrumb path
    var labels = []
    var node = cur
    var guard = 0
    while (node && node.id !== "root" && guard < 16) {
      labels.unshift(node.label)
      node = node.parent ? map[node.parent] : null
      guard++
    }
    var pathStr = labels.join(" › ")
    var leafTokens = cur.id.replace(/[._-]+/g, " ")
    var aliasTokens = cur.aliases.join(" ").replace(/[._-]+/g, " ")
    out.push({
      id: cur.id,
      kind: cur.kind,
      icon: cur.icon || "󱓞",
      iconFont: cur.iconFont,
      label: cur.label,
      path: pathStr,
      action: cur.action,
      searchText: (cur.label + " " + pathStr + " " + leafTokens + " " + aliasTokens).toLowerCase()
    })
  }
  return out
}

function searchOmarchyMenuEntries(menuEntries, query, maxResults) {
  var list = Array.isArray(menuEntries) ? menuEntries : []
  var q = String(query || "").trim().toLowerCase()
  var limit = (maxResults && maxResults > 0) ? maxResults : 12
  if (!q) return []

  var terms = q.split(/\s+/)
  var matches = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry) continue
    var hay = entry.searchText || ""
    var ok = true
    for (var t = 0; t < terms.length; t++) {
      if (terms[t] && hay.indexOf(terms[t]) === -1) {
        ok = false
        break
      }
    }
    if (!ok) continue

    var labelLower = String(entry.label || "").toLowerCase()
    var score = 5000
    if (labelLower === q) score = 15000
    else if (labelLower.indexOf(q) === 0) score = 12000 - labelLower.length
    else if (labelLower.indexOf(q) > 0) score = 9500 - labelLower.indexOf(q) * 10
    else if (String(entry.path || "").toLowerCase().indexOf(q) >= 0) score = 8000
    if (entry.kind === "action") score += 250
    if (entry.id.indexOf("style.") === 0 || entry.id.indexOf("trigger.") === 0 || entry.id.indexOf("system.") === 0 || entry.id.indexOf("setup.") === 0) {
      score += 800
    } else if (entry.id.indexOf("install.") === 0 || entry.id.indexOf("remove.") === 0) {
      score -= 600
    }

    matches.push({
      id: "omarchy:" + entry.id,
      menuId: entry.id,
      entryKind: "omarchy",
      omarchyKind: entry.kind,
      name: entry.label,
      subtext: "Omarchy  •  " + (entry.path || entry.id),
      icon: entry.icon || "󱓞",
      iconFont: entry.iconFont || "",
      action: entry.action || "",
      score: score,
      sortKey: (entry.path || entry.label).toLowerCase()
    })
  }

  matches.sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score
    if (a.sortKey < b.sortKey) return -1
    if (a.sortKey > b.sortKey) return 1
    return 0
  })

  return matches.slice(0, limit)
}

// CRUD Operations returning a new state object

// Insert item right after the last item of its (space, category) group, or at the end.
function insertItemAtCategoryEnd(next, item) {
  var insertAt = next.items.length
  for (var j = next.items.length - 1; j >= 0; j--) {
    if (next.items[j].spaceId === item.spaceId && next.items[j].categoryId === item.categoryId) {
      insertAt = j + 1
      break
    }
  }
  next.items.splice(insertAt, 0, item)
}

function upsertItem(data, itemPayload) {
  var next = cloneData(data)
  var spaceId = itemPayload.spaceId || next.activeSpaceId
  var cats = categoriesForSpace(next, spaceId)
  var fallbackCat = cats.length > 0 ? cats[0].id : ""
  var clean = sanitizeItem(itemPayload, spaceId, fallbackCat)
  if (!clean) return next

  var previousSpaceId = ""
  var previousCategoryId = ""
  for (var findPrev = 0; findPrev < next.items.length; findPrev++) {
    if (next.items[findPrev].id === clean.id) {
      previousSpaceId = next.items[findPrev].spaceId
      previousCategoryId = next.items[findPrev].categoryId
      if (itemPayload.launchCount === undefined && itemPayload.lastLaunchedAt === undefined) {
        clean.launchCount = Number(next.items[findPrev].launchCount || 0) || 0
        clean.lastLaunchedAt = Number(next.items[findPrev].lastLaunchedAt || 0) || 0
      }
      break
    }
  }
  if (previousSpaceId && previousSpaceId !== clean.spaceId) {
    clean.pinnedSlot = 0
  }

  // If pinnedSlot 1..6 is chosen, clear any existing item in the same space holding that slot
  if (clean.pinnedSlot >= 1 && clean.pinnedSlot <= 6) {
    for (var p = 0; p < next.items.length; p++) {
      if (next.items[p].spaceId === clean.spaceId && next.items[p].id !== clean.id && next.items[p].pinnedSlot === clean.pinnedSlot) {
        next.items[p].pinnedSlot = 0
      }
    }
  }

  var updated = false
  var relocated = false
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === clean.id) {
      relocated = previousSpaceId !== clean.spaceId || previousCategoryId !== clean.categoryId
      if (relocated) {
        next.items.splice(i, 1)
        insertItemAtCategoryEnd(next, clean)
      } else {
        next.items[i] = clean
      }
      updated = true
      break
    }
  }
  if (!updated) {
    next.items.push(clean)
  }
  return next
}

function deleteItem(data, itemId) {
  var next = cloneData(data)
  var out = []
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id !== itemId) out.push(next.items[i])
  }
  next.items = out
  return next
}

function moveItemInCategory(data, itemId, direction) {
  var next = cloneData(data)
  var id = String(itemId || "")
  var dir = direction === "down" ? "down" : "up"
  var idx = -1
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === id) {
      idx = i
      break
    }
  }
  if (idx < 0) return next

  var spaceId = next.items[idx].spaceId
  var categoryId = next.items[idx].categoryId
  var group = []
  for (var g = 0; g < next.items.length; g++) {
    if (next.items[g].spaceId === spaceId && next.items[g].categoryId === categoryId) {
      group.push(g)
    }
  }
  var pos = -1
  for (var p = 0; p < group.length; p++) {
    if (group[p] === idx) {
      pos = p
      break
    }
  }
  if (pos < 0) return next
  var swapPos = dir === "up" ? pos - 1 : pos + 1
  if (swapPos < 0 || swapPos >= group.length) return next

  var a = group[pos]
  var b = group[swapPos]
  var tmp = next.items[a]
  next.items[a] = next.items[b]
  next.items[b] = tmp
  return next
}

function moveItemToSpace(data, itemId, targetSpaceId, targetCategoryId) {
  var next = cloneData(data)
  var id = String(itemId || "")
  var spaceId = String(targetSpaceId || "")
  var categoryId = String(targetCategoryId || "")

  var spaceOk = false
  for (var s = 0; s < next.spaces.length; s++) {
    if (next.spaces[s].id === spaceId) {
      spaceOk = true
      break
    }
  }
  if (!spaceOk) return next

  var catOk = false
  for (var c = 0; c < next.categories.length; c++) {
    if (next.categories[c].id === categoryId && next.categories[c].spaceId === spaceId && isStaticCategory(next.categories[c])) {
      catOk = true
      break
    }
  }
  if (!catOk) return next

  var idx = -1
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === id) {
      idx = i
      break
    }
  }
  if (idx < 0) return next

  var item = next.items[idx]
  if (item.spaceId === spaceId && item.categoryId === categoryId) return next

  var moved = {}
  for (var prop in item) {
    if (Object.prototype.hasOwnProperty.call(item, prop)) moved[prop] = item[prop]
  }
  var spaceChanged = moved.spaceId !== spaceId
  moved.spaceId = spaceId
  moved.categoryId = categoryId
  if (spaceChanged) moved.pinnedSlot = 0

  next.items.splice(idx, 1)
  insertItemAtCategoryEnd(next, moved)
  return next
}

function toggleFavorite(data, itemId) {
  var next = cloneData(data)
  for (var i = 0; i < next.items.length; i++) {
    if (next.items[i].id === itemId) {
      next.items[i].favorite = !next.items[i].favorite
      break
    }
  }
  return next
}

function upsertCategory(data, catPayload) {
  var next = cloneData(data)
  var name = plainTextLabel((catPayload && catPayload.name) || "")
  if (!name) return next
  var id = String((catPayload && catPayload.id) || uid("cat"))
  var spaceId = String((catPayload && catPayload.spaceId) || next.activeSpaceId)
  var icon = String((catPayload && catPayload.icon) || "󰉋")
  var colorRole = String((catPayload && catPayload.colorRole) || "blue")
  var rawType = String((catPayload && catPayload.type) || "static").toLowerCase()
  var catType = (rawType === "rss" || rawType === "github") ? rawType : "static"
  var feedUrl = String((catPayload && catPayload.feedUrl) || "").trim()
  var rawMode = String((catPayload && catPayload.feedMode) || "all").toLowerCase()
  var feedMode = (rawMode === "issues" || rawMode === "prs" || rawMode === "releases") ? rawMode : "all"

  var found = false
  for (var i = 0; i < next.categories.length; i++) {
    if (next.categories[i].id === id) {
      next.categories[i].name = name
      next.categories[i].spaceId = spaceId
      next.categories[i].icon = icon
      next.categories[i].colorRole = colorRole
      next.categories[i].type = catType
      next.categories[i].feedUrl = feedUrl
      next.categories[i].feedMode = feedMode
      found = true
      break
    }
  }
  if (!found) {
    next.categories.push({
      id: id,
      spaceId: spaceId,
      name: name,
      icon: icon,
      colorRole: colorRole,
      type: catType,
      feedUrl: feedUrl,
      feedMode: feedMode
    })
  }
  return next
}

function deleteCategory(data, categoryId) {
  var next = cloneData(data)
  var remainingCats = []
  for (var i = 0; i < next.categories.length; i++) {
    if (next.categories[i].id !== categoryId) remainingCats.push(next.categories[i])
  }
  next.categories = remainingCats

  var remainingItems = []
  for (var j = 0; j < next.items.length; j++) {
    if (next.items[j].categoryId !== categoryId) remainingItems.push(next.items[j])
  }
  next.items = remainingItems
  return next
}

function upsertSpace(data, spacePayload) {
  var next = cloneData(data)
  var name = plainTextLabel((spacePayload && spacePayload.name) || "")
  if (!name) return next
  var id = String((spacePayload && spacePayload.id) || uid("space"))
  var icon = String((spacePayload && spacePayload.icon) || "󰀻")

  var found = false
  for (var i = 0; i < next.spaces.length; i++) {
    if (next.spaces[i].id === id) {
      next.spaces[i].name = name
      next.spaces[i].icon = icon
      found = true
      break
    }
  }
  if (!found) {
    next.spaces.push({ id: id, name: name, icon: icon })
    next.categories.push({
      id: uid("cat"),
      spaceId: id,
      name: "General",
      icon: "󰉋",
      colorRole: "blue"
    })
  }
  next.activeSpaceId = id
  return next
}

function deleteSpace(data, spaceId) {
  var next = cloneData(data)
  if (next.spaces.length <= 1) return next
  var spaces = []
  for (var i = 0; i < next.spaces.length; i++) {
    if (next.spaces[i].id !== spaceId) spaces.push(next.spaces[i])
  }
  next.spaces = spaces
  if (next.activeSpaceId === spaceId) {
    next.activeSpaceId = spaces[0].id
  }
  next.categories = next.categories.filter(function(c) { return c.spaceId !== spaceId })
  next.items = next.items.filter(function(it) { return it.spaceId !== spaceId })
  return next
}

function mergeImportedFolders(data, targetSpaceId, folders) {
  var next = cloneData(data)
  var spaceId = targetSpaceId || next.activeSpaceId
  var roles = ["blue", "cyan", "magenta", "green", "yellow", "orange", "red"]
  if (!Array.isArray(folders)) return next

  var existingUrls = {}
  for (var e = 0; e < next.items.length; e++) {
    if (next.items[e].spaceId === spaceId && next.items[e].url) {
      existingUrls[next.items[e].url.toLowerCase()] = true
    }
  }

  for (var f = 0; f < folders.length; f++) {
    var folder = folders[f]
    if (!folder || !Array.isArray(folder.bookmarks) || folder.bookmarks.length === 0) continue
    var folderName = plainTextLabel(folder.name || "Imported") || "Imported"
    var catId = ""
    for (var c = 0; c < next.categories.length; c++) {
      if (next.categories[c].spaceId === spaceId && next.categories[c].name.toLowerCase() === folderName.toLowerCase()) {
        catId = next.categories[c].id
        break
      }
    }
    var role = roles[(next.categories.length + f) % roles.length]
    if (!catId) {
      catId = uid("cat")
      next.categories.push({
        id: catId,
        spaceId: spaceId,
        name: folderName,
        icon: "󰉋",
        colorRole: role
      })
    }

    for (var b = 0; b < folder.bookmarks.length; b++) {
      var bm = folder.bookmarks[b]
      if (!bm || !bm.url) continue
      var normUrl = normalizeUrl(bm.url)
      if (!normUrl || existingUrls[normUrl.toLowerCase()]) continue
      existingUrls[normUrl.toLowerCase()] = true
      var item = sanitizeItem({
        spaceId: spaceId,
        categoryId: catId,
        type: "url",
        title: plainTextLabel(bm.title) || extractDomain(normUrl) || normUrl,
        subtitle: extractDomain(normUrl),
        url: normUrl,
        iconType: "favicon",
        iconValue: "",
        colorRole: ""
      }, spaceId, catId)
      if (item) next.items.push(item)
    }
  }
  return next
}

function noteListTitle(prefixText, filenameStem) {
  var text = String(prefixText || "").replace(/^\uFEFF/, "")
  var lines = text.split(/\r?\n/)
  var start = 0
  if (lines.length > 0 && lines[0].trim() === "---") {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") {
        start = i + 1
        break
      }
    }
  }
  for (var j = start; j < lines.length; j++) {
    var line = lines[j]
    var heading = line.match(/^(#{1,6})\s+(.*)$/)
    if (heading && String(heading[2]).trim()) return String(heading[2]).trim()
    if (String(line).trim()) break
  }
  var stem = String(filenameStem || "").trim()
  return stem || "note"
}

function noteFilename(title, takenNames) {
  var raw = String(title || "").replace(/^(#{1,6})\s+/, "").trim()
  raw = raw.replace(/[\/\\\u0000-\u001F]/g, "-")
  raw = raw.replace(/^[\s.]+|[\s.]+$/g, "")
  raw = raw.replace(/-+/g, "-").replace(/^-|-$/g, "")
  if (!raw) raw = "note"
  var taken = {}
  var names = Array.isArray(takenNames) ? takenNames : []
  for (var i = 0; i < names.length; i++) taken[String(names[i])] = true
  var candidate = raw + ".md"
  if (!taken[candidate]) return candidate
  var n = 2
  while (taken[raw + "-" + n + ".md"]) n++
  return raw + "-" + n + ".md"
}

function notePathAllowed(path, roots) {
  var value = String(path || "")
  if (!value || value.indexOf("\0") !== -1) return false
  if (value.split("/").indexOf("..") !== -1) return false
  var list = Array.isArray(roots) ? roots : []
  for (var i = 0; i < list.length; i++) {
    var root = String(list[i] || "").replace(/\/+$/, "")
    if (!root || root.split("/").indexOf("..") !== -1) continue
    if (value === root || value.indexOf(root + "/") === 0) return true
  }
  return false
}

function searchNotes(notes, files, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  var cards = (notes && Array.isArray(notes.cards)) ? notes.cards : []
  var rows = notesModelRows(cards, files)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var hay = [
      String(row.title || ""),
      notePathStem(row.path),
      String(row.badgeText || "")
    ]
    var hit = false
    for (var h = 0; h < hay.length; h++) {
      if (hay[h].toLowerCase().indexOf(q) !== -1) {
        hit = true
        break
      }
    }
    if (!hit) continue
    out.push({
      path: row.path,
      title: row.title,
      badgeText: row.badgeText,
      categoryId: row.categoryId
    })
  }
  return out
}

function emptyNotes() {
  return { writeRoot: "", roots: [], cards: [] }
}

function notePathStem(path) {
  var base = String(path || "").split("/").pop()
  var dot = base.lastIndexOf(".")
  if (dot > 0) return base.slice(0, dot)
  return base
}

function notesModelRows(cards, files) {
  var incoming = Array.isArray(files) ? files : []
  var byPath = {}
  for (var i = 0; i < incoming.length; i++) {
    var file = incoming[i]
    if (file && file.path) byPath[String(file.path)] = file
  }
  var list = Array.isArray(cards) ? cards : []
  var out = []
  for (var c = 0; c < list.length; c++) {
    var card = list[c]
    if (!card || !card.path) continue
    var pinned = Math.round(Number(card.pinnedSlot) || 0)
    var match = byPath[String(card.path)]
    if (!match) {
      out.push({
        path: String(card.path),
        title: noteListTitle("", notePathStem(card.path)),
        badgeText: String(card.badgeText || ""),
        colorRole: String(card.colorRole || ""),
        categoryId: String(card.categoryId || ""),
        pinnedSlot: pinned,
        mtime: 0,
        tooLarge: false
      })
      continue
    }
    out.push({
      path: String(card.path),
      title: String(match.title || ""),
      badgeText: String(card.badgeText || ""),
      colorRole: String(card.colorRole || ""),
      categoryId: String(card.categoryId || ""),
      pinnedSlot: pinned,
      mtime: Number(match.mtime) || 0,
      tooLarge: match.tooLarge === true
    })
  }
  return out
}

function noteReadSettlement(token, draft, path, res) {
  var current = draft && typeof draft === "object" ? draft : {}
  var dirty = !!current.dirty
  if (res && res.ok && res.tooLarge) {
    if (dirty) return { action: "keep", token: token }
    return {
      action: "replace",
      token: token + 1,
      readOnly: true,
      draft: {
        path: String(path || ""),
        text: "",
        frontmatter: "",
        mtime: Number(res.mtime) || 0,
        dirty: false
      }
    }
  }
  if (!res || !res.ok) {
    var missing = !!(res && res.ok === false && String(res.error || "") === "missing")
    if (missing && !dirty) return { action: "drop", token: token + 1 }
    return { action: "fail", token: token }
  }
  if (dirty) return { action: "keep", token: token }
  return {
    action: "replace",
    token: token + 1,
    readOnly: false,
    draft: {
      path: String(path || ""),
      text: String(res.body || ""),
      frontmatter: String(res.frontmatter || ""),
      mtime: Number(res.mtime) || 0,
      dirty: false
    }
  }
}

function noteWriteDraft(capturedToken, currentToken, currentDraft, savedPath, savedMtime, writtenText, frontmatter) {
  if (capturedToken !== currentToken) return null
  var current = currentDraft && typeof currentDraft === "object" ? currentDraft : {}
  var textNow = String(current.text || "")
  var sameBody = textNow === String(writtenText || "")
  return {
    readOnly: false,
    doneOk: sameBody,
    draft: {
      path: String(savedPath || ""),
      text: textNow,
      frontmatter: String(current.frontmatter || frontmatter || ""),
      mtime: Number(savedMtime) || 0,
      dirty: !sameBody
    }
  }
}

function mergeNoteScan(notes, files, inboxCategoryId, truncated) {
  var base = notes && typeof notes === "object" ? notes : emptyNotes()
  var cards = Array.isArray(base.cards) ? base.cards : []
  var byPath = {}
  for (var i = 0; i < cards.length; i++) {
    if (cards[i] && cards[i].path) byPath[String(cards[i].path)] = cards[i]
  }
  var seen = {}
  var nextCards = []
  var incoming = Array.isArray(files) ? files : []
  for (var f = 0; f < incoming.length; f++) {
    var file = incoming[f]
    if (!file || !file.path) continue
    var p = String(file.path)
    seen[p] = true
    var prev = byPath[p]
    var slot = prev ? Math.round(Number(prev.pinnedSlot) || 0) : 0
    if (slot < 0 || slot > 6) slot = 0
    nextCards.push({
      path: p,
      categoryId: prev && prev.categoryId ? String(prev.categoryId) : String(inboxCategoryId || ""),
      colorRole: prev && prev.colorRole ? String(prev.colorRole) : "",
      badgeText: prev && prev.badgeText ? String(prev.badgeText) : "",
      pinnedSlot: slot
    })
  }
  if (truncated) {
    for (var c = 0; c < cards.length; c++) {
      var oldPath = cards[c] && cards[c].path ? String(cards[c].path) : ""
      if (oldPath && !seen[oldPath]) nextCards.push(cards[c])
    }
  }
  return {
    writeRoot: String(base.writeRoot || ""),
    roots: Array.isArray(base.roots) ? base.roots.slice() : [],
    cards: nextCards
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    plainTextLabel: plainTextLabel,
    sanitizeLiveFeedsMap: sanitizeLiveFeedsMap,
    extractDomain: extractDomain,
    monogramFor: monogramFor,
    normalizeUrl: normalizeUrl,
    uid: uid,
    defaultData: defaultData,
    sanitizeItem: sanitizeItem,
    parse: parse,
    serialize: serialize,
    cloneData: cloneData,
    categoriesForSpace: categoriesForSpace,
    isStaticCategory: isStaticCategory,
    staticCategoriesForSpace: staticCategoriesForSpace,
    itemsForSpace: itemsForSpace,
    pinnedOrbitForSpace: pinnedOrbitForSpace,
    matchesItemQuery: matchesItemQuery,
    searchCommandItems: searchCommandItems,
    bashSingleQuote: bashSingleQuote,
    commandShellScript: commandShellScript,
    filterItems: filterItems,
    recordLaunch: recordLaunch,
    frequentItems: frequentItems,
    otherSpaceSearchGroups: otherSpaceSearchGroups,
    normalizeDesktopId: normalizeDesktopId,
    searchDesktopEntries: searchDesktopEntries,
    parseOmarchyMenuJsonc: parseOmarchyMenuJsonc,
    searchOmarchyMenuEntries: searchOmarchyMenuEntries,
    upsertItem: upsertItem,
    deleteItem: deleteItem,
    moveItemInCategory: moveItemInCategory,
    moveItemToSpace: moveItemToSpace,
    toggleFavorite: toggleFavorite,
    upsertCategory: upsertCategory,
    deleteCategory: deleteCategory,
    upsertSpace: upsertSpace,
    deleteSpace: deleteSpace,
    mergeImportedFolders: mergeImportedFolders,
    noteListTitle: noteListTitle,
    noteFilename: noteFilename,
    notePathAllowed: notePathAllowed,
    mergeNoteScan: mergeNoteScan,
    notesModelRows: notesModelRows,
    searchNotes: searchNotes,
    noteReadSettlement: noteReadSettlement,
    noteWriteDraft: noteWriteDraft,
    ensureNotesModel: ensureNotesModel
  }
}
