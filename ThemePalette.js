// ThemePalette.js - Parses semantic colors from Omarchy's active theme colors.toml

var COLOR_ROLES = [
  { id: "blue", label: "Modrá (Blue)" },
  { id: "cyan", label: "Azurová (Cyan)" },
  { id: "magenta", label: "Fialová (Magenta)" },
  { id: "green", label: "Zelená (Green)" },
  { id: "yellow", label: "Žlutá (Yellow)" },
  { id: "orange", label: "Oranžová (Orange)" },
  { id: "red", label: "Červená (Red)" }
]

function defaultPalette() {
  return {
    blue: "#7aa2f7",
    cyan: "#449dab",
    magenta: "#ad8ee6",
    green: "#9ece6a",
    yellow: "#e0af68",
    orange: "#eb927b",
    red: "#f7768e",
    accent: "#7aa2f7",
    foreground: "#a9b1d6",
    background: "#1a1b26",
    muted: "#565f89"
  }
}

function parseColorsToml(raw) {
  var palette = defaultPalette()
  if (!raw || !String(raw).trim()) return palette

  var lines = String(raw).split("\n")
  var map = {}
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (!m) continue
    map[m[1]] = m[2]
  }

  palette.blue = map.blue || map.bright_blue || map.color4 || map.accent || palette.blue
  palette.cyan = map.cyan || map.bright_cyan || map.color6 || palette.cyan
  palette.magenta = map.magenta || map.bright_magenta || map.color5 || palette.magenta
  palette.green = map.green || map.bright_green || map.color2 || palette.green
  palette.yellow = map.yellow || map.bright_yellow || map.color3 || palette.yellow
  palette.orange = map.orange || map.bright_yellow || palette.yellow
  palette.red = map.red || map.bright_red || map.color1 || palette.red
  palette.accent = map.accent || palette.blue
  palette.foreground = map.foreground || map.color7 || palette.foreground
  palette.background = map.background || map.color0 || palette.background
  palette.muted = map.muted || map.dark_foreground || map.color8 || palette.muted

  return palette
}

function resolveRoleColor(palette, role, fallbackAccent) {
  var p = palette || defaultPalette()
  var r = String(role || "blue").toLowerCase()
  if (p[r]) return p[r]
  return fallbackAccent || p.accent || p.blue
}

if (typeof module !== "undefined") {
  module.exports = {
    COLOR_ROLES: COLOR_ROLES,
    defaultPalette: defaultPalette,
    parseColorsToml: parseColorsToml,
    resolveRoleColor: resolveRoleColor
  }
}
