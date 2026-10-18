-- Design tokens mirrored from the website (colors and class colors). The color
-- tables may be replaced by generated ones later; keep the shape stable.
local _, ns = ...
local U = ns.U

local Theme = {}
ns.Theme = Theme

Theme.colors = {
  bg = "#0a0a0a",
  surface = "#111111",
  surface2 = "#1a1a1a",
  surface3 = "#222222",
  text = "#f3eee2",
  textSecondary = "#c7d3dd",
  textMuted = "#9db3c4",
  accent = "#e2c2ab",
  accent2 = "#c9a670",
  accentDim = "#8a6d40",
  action = "#0f6064",
  actionHi = "#5fd3d8",
  success = "#6fae7c",
  warning = "#e0954a",
  danger = "#e05c4a",
  info = "#4a8fe0",
  alliance = "#4a8fe0",
  horde = "#e05c4a",
  -- The fixed purple of the author's channel link (title bar, start page): the same in every theme, white text
  -- on both fills passes AA (4.6:1 and 6.3:1).
  stream = "#9146ff",
  streamHi = "#772ce8",
  streamText = "#ffffff",
  -- Learn list area headers: light backgrounds that carry one black text color.
  sectionLearned = "#bdbdbd",
  sectionAvailable = "#7bc98c",
  sectionLocked = "#ee8f88",
  sectionText = "#000000",
  -- Text on WoW's own spellbook parchment (about #d8c39a, shows through our panel).
  parchment = "#d8c39a",
  parchmentText = "#2a1a0a",
  parchmentTextSecondary = "#4a3418",
  parchmentAccent = "#5f3607",
  parchmentSuccess = "#17501f",
}

-- Overrides when colorblind mode is on: red/green pair swapped for blue/orange.
Theme.colorblindColors = {
  sectionAvailable = "#6fb4f0",
  sectionLocked = "#f0b24f",
}

-- Overrides when high contrast is on.
Theme.contrast = {
  bg = "#000000",
  surface = "#000000",
  surface2 = "#141414",
  surface3 = "#262626",
  text = "#ffffff",
  textSecondary = "#ffffff",
  textMuted = "#e0e0e0",
  parchmentText = "#000000",
  parchmentTextSecondary = "#000000",
  parchmentAccent = "#000000",
  parchmentSuccess = "#000000",
}

-- Selectable color themes (settings.theme). Only dark surfaces, so the text colors stay valid
-- on them (checked in tests/test_appearance.lua). "default" changes nothing. accent2 also
-- derives accent and accentDim. Red, "class" and the class themes are added below Theme.readable.
Theme.PRESET_ORDER = { "default", "dark", "blue", "green", "warm" }
Theme.presets = {
  default = {},
  dark = { bg = "#000000", surface = "#0b0b0b", surface2 = "#141414", surface3 = "#1e1e1e" },
  blue = {
    bg = "#080d1a",
    surface = "#0e1628",
    surface2 = "#162139",
    surface3 = "#1e2c4a",
    action = "#1d4f8f",
    actionHi = "#8fbaf0",
    accent2 = "#8fb8e8",
  },
  green = {
    bg = "#08120c",
    surface = "#0e1b13",
    surface2 = "#14271b",
    surface3 = "#1b3326",
    action = "#1f6b3a",
    actionHi = "#86dca0",
    accent2 = "#8fcf9e",
  },
  warm = {
    bg = "#1a130b",
    surface = "#241a0f",
    surface2 = "#2e2214",
    surface3 = "#3a2b19",
    action = "#7a4a14",
    actionHi = "#e8b878",
    accent2 = "#dba86a",
  },
}

-- WCAG 2.1 AA for normal text.
Theme.MIN_CONTRAST = 4.5
-- Main window background opacity in percent (settings.mainAlpha).
Theme.ALPHA_MIN, Theme.ALPHA_MAX = 0, 100
-- Store loads first, so the default lives there and is read back here.
Theme.ALPHA_DEFAULT = ns.Store.defaults.settings.mainAlpha

Theme.classColors = {
  WARRIOR = "#c79c6e",
  PALADIN = "#f58cba",
  HUNTER = "#abd473",
  ROGUE = "#fff569",
  PRIEST = "#ffffff",
  SHAMAN = "#4fa8ff", -- text variant; border #0070de
  MAGE = "#69ccf0",
  WARLOCK = "#9482c9",
  DRUID = "#ff7d0a",
}

Theme.rarity = {
  poor = "#9d9d9d",
  common = "#ffffff",
  uncommon = "#1eff00",
  rare = "#4da3ff",
  epic = "#c67bff",
  legendary = "#ff8000",
}

Theme.space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Theme.size = { titleBar = 40, footer = 22, contentHeader = 44, row = 28, rowCompact = 22, icon = 20 }

-- Web font sizes: micro 11, ui 12, text 13, h3 15, h2 18, title 22. display is the
-- heading size of WoW's own book pages. small and body are the roles of the typography
-- settings; their base sizes equal micro and text.
Theme.fontSizes = { micro = 11, small = 11, ui = 12, text = 13, body = 13, h3 = 15, h2 = 18, title = 22, display = 28 }

-- The six roles with a user factor (settings.fontScales). ui and text keep their own base size
-- and borrow the factor of body until the roles are merged; display has no factor.
Theme.FONT_ROLES = { "title", "h2", "h3", "body", "small", "micro" }
Theme.fontAlias = { ui = "body", text = "body" }
local FACTOR_ROLE = {}
for _, role in ipairs(Theme.FONT_ROLES) do
  FACTOR_ROLE[role] = true
end

-- Smallest size in px. Below 100 percent window zoom the floor grows so the size on screen holds.
Theme.FONT_FLOOR = 11
-- Overall factor (settings.fontScale) and factor of one role (settings.fontScales[role]).
Theme.FONT_SCALE_MIN, Theme.FONT_SCALE_MAX = 0.85, 2
Theme.ROLE_SCALE_MIN, Theme.ROLE_SCALE_MAX = 0.8, 1.6

-- Body text uses the game font (all glyphs, best legibility). Headings use
-- the game's display serif. The client refuses font files from addon folders,
-- so only paths under "Fonts\" belong in these lists.
Theme.fontFiles = {
  body = { "Fonts\\FRIZQT__.TTF" },
  heading = { "Fonts\\FRIZQT__.TTF" },
  display = { "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF" },
}

local function settings()
  return (ns.db and ns.db.settings) or {}
end

-- Saved window scale for secondary frames; damaged SavedVariables (the client's SetScale
-- raises on a non-number) fall back to 1.
function Theme.windowScale()
  local v = tonumber(settings().scale)
  if not v or v ~= v then
    return 1
  end
  return U.clamp(v, 0.7, 1.5)
end

function Theme.highContrast()
  return settings().contrast == true
end

function Theme.colorblind()
  return settings().colorblind == true or ns.GetCVar("colorblindMode") == "1"
end

function Theme.reduceMotion()
  return settings().reduceMotion == true
end

-- Color math ---------------------------------------------------------------------------------

local function channel(c)
  return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(hex)
  local r, g, b = U.hex(hex)
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

function Theme.contrastRatio(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- Blend of `hex` toward `toward` by t (0..1), as "#rrggbb".
function Theme.mix(hex, toward, t)
  local r1, g1, b1 = U.hex(hex)
  local r2, g2, b2 = U.hex(toward)
  return string.format(
    "#%02x%02x%02x",
    (r1 + (r2 - r1) * t) * 255 + 0.5,
    (g1 + (g2 - g1) * t) * 255 + 0.5,
    (b1 + (b2 - b1) * t) * 255 + 0.5
  )
end

-- Lightens `hex` until it reads on `bg` (all themes are dark). Returns hex, adjusted.
function Theme.readable(hex, bg, min)
  min = min or Theme.MIN_CONTRAST
  local out, adjusted = hex, false
  for step = 1, 20 do
    if Theme.contrastRatio(out, bg) >= min then
      break
    end
    out, adjusted = Theme.mix(hex, "#ffffff", step * 0.05), true
  end
  return out, adjusted
end

-- Dark surfaces tinted by one color: "red" and the nine class colors. The accent is lightened
-- for contrast in overrides(); the action color stays dark enough for the text on it.
local function tinted(accent)
  local dark = "#000000"
  local top = Theme.mix(dark, accent, 0.16)
  return {
    bg = Theme.mix(dark, accent, 0.05),
    surface = Theme.mix(dark, accent, 0.08),
    surface2 = Theme.mix(dark, accent, 0.12),
    surface3 = top,
    action = Theme.mix(accent, dark, 0.65),
    actionHi = (Theme.readable(Theme.mix(accent, "#ffffff", 0.35), top)),
    accent2 = accent,
  }
end

-- "class" follows the class of the character that is logged in (see Theme.playerClassId).
Theme.presets.red = tinted(Theme.colors.danger)
Theme.presets.class = {}
table.insert(Theme.PRESET_ORDER, "red")
table.insert(Theme.PRESET_ORDER, "class")
for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
  local id = token:lower()
  Theme.presets[id] = tinted(Theme.classColors[token])
  table.insert(Theme.PRESET_ORDER, id)
end

-- Preset id of the current character's class, nil while the client does not know it yet.
function Theme.playerClassId()
  if type(UnitClass) ~= "function" then
    return nil
  end
  local ok, _, token = pcall(UnitClass, "player")
  token = ok and type(token) == "string" and token:lower() or nil
  return token and token ~= "class" and Theme.presets[token] and token or nil
end

function Theme.cleanAccent(v)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and "#" .. raw:lower() or nil
end

-- Theme and accent overrides, rebuilt only when theme, accent or contrast mode change.
local resolved = { key = nil, map = {}, adjusted = false }

-- Color of the window style in force (UI/Skins.lua, loads after this file): below the theme,
-- above the base colors.
local function skinColor(name)
  local skins = ns.Skins
  return skins and skins.palette(name)
end

local function overrides()
  local s = settings()
  local id = s.theme == "class" and Theme.playerClassId() or s.theme
  local skin = ns.Skins and ns.Skins.activeId() or "flat"
  local key = tostring(id) .. "|" .. tostring(s.accent) .. "|" .. tostring(Theme.highContrast()) .. "|" .. skin
  if resolved.key == key then
    return resolved.map
  end
  local map = {}
  for k, v in pairs(Theme.presets[id] or {}) do
    map[k] = v
  end
  local accent = Theme.cleanAccent(s.accent) or map.accent2
  local adjusted = false
  if accent then
    local floor = (Theme.highContrast() and Theme.contrast.surface3)
      or map.surface3
      or skinColor("surface3")
      or Theme.colors.surface3
    accent, adjusted = Theme.readable(accent, floor)
    map.accent2, map.accent = accent, Theme.mix(accent, "#ffffff", 0.3)
    map.accentDim = Theme.mix(accent, "#000000", 0.31)
  end
  resolved = { key = key, map = map, adjusted = adjusted and Theme.cleanAccent(s.accent) ~= nil }
  return map
end

-- True while the chosen accent color had to be lightened to stay readable.
function Theme.accentAdjusted()
  overrides()
  return resolved.adjusted
end

function Theme.mainAlpha()
  local v = tonumber(settings().mainAlpha)
  if not v or v ~= v then
    return Theme.ALPHA_DEFAULT / 100
  end
  return U.clamp(v, Theme.ALPHA_MIN, Theme.ALPHA_MAX) / 100
end

function Theme.rgb(name)
  local hex = (Theme.highContrast() and Theme.contrast[name])
    or (Theme.colorblindColors[name] and Theme.colorblind() and Theme.colorblindColors[name])
    or overrides()[name]
    or skinColor(name)
    or Theme.colors[name]
    or Theme.classColors[name]
    or name
  return U.hex(hex)
end

function Theme.color(name, alpha)
  local r, g, b = Theme.rgb(name)
  return r, g, b, alpha or 1
end

function Theme.hexText(name, text)
  local r, g, b = Theme.rgb(name)
  return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

function Theme.lineAlpha()
  return Theme.highContrast() and 0.3 or 0.1
end

-- A saved factor: damaged values (not a number, NaN, infinite) count as 1, the rest is clamped.
local function factor(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then
    return 1
  end
  return U.clamp(v, lo, hi)
end

function Theme.fontScale()
  return factor(settings().fontScale, Theme.FONT_SCALE_MIN, Theme.FONT_SCALE_MAX)
end

-- Factor of the role; aliases and unknown roles use the one of body, display has none.
function Theme.roleScale(role)
  if role == "display" then
    return 1
  end
  role = Theme.fontAlias[role] or role
  if not FACTOR_ROLE[role] then
    role = "body"
  end
  local scales = settings().fontScales
  return factor(type(scales) == "table" and scales[role], Theme.ROLE_SCALE_MIN, Theme.ROLE_SCALE_MAX)
end

function Theme.fontFloor()
  local zoom = Theme.windowScale()
  return zoom < 1 and math.ceil(Theme.FONT_FLOOR / zoom) or Theme.FONT_FLOOR
end

function Theme.fontSize(role)
  local base = Theme.fontSizes[role] or Theme.fontSizes.ui
  return math.max(Theme.fontFloor(), U.round(base * Theme.fontScale() * Theme.roleScale(role)))
end

-- Actual size over base size of the role (default ui); below 1 when the font shrank.
function Theme.fontRatio(role)
  return Theme.fontSize(role or "ui") / (Theme.fontSizes[role] or Theme.fontSizes.ui)
end

-- Height of a fixed-size element designed for `base` px of the role's text at 100 percent.
-- Follows the real size of the font, so it shrinks with it as well.
function Theme.lineHeight(base, role)
  return math.ceil(base * Theme.fontRatio(role))
end

-- role: title|h2|h3|body|small|micro|display or the aliases ui|text; family: body|heading|display
function Theme.applyFont(fs, role, family, flags)
  local size = Theme.fontSize(role)
  for _, file in ipairs(Theme.fontFiles[family or "body"]) do
    if fs:SetFont(file, size, flags or "") then
      break
    end
  end
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
end

-- Sets a fixed size on a font string of a foreign frame (a line of the GameTooltip) and returns the
-- function that puts the old font back; nil when the font cannot be read or set.
function Theme.shrinkFont(fs, size)
  if type(fs) ~= "table" or type(fs.GetFont) ~= "function" or type(fs.SetFont) ~= "function" then
    return nil
  end
  local font, oldSize, flags = fs:GetFont()
  if not (font and pcall(fs.SetFont, fs, font, size, flags)) then
    return nil
  end
  return function()
    pcall(fs.SetFont, fs, font, oldSize, flags)
  end
end

-- Elements bind an apply-function that runs now and again whenever theme,
-- font scale or locale change. Weak keys: hidden/unused owners are fine.
local bound = setmetatable({}, { __mode = "k" })

function ns.Bind(owner, fn)
  local list = bound[owner]
  if not list then
    list = {}
    bound[owner] = list
  end
  list[#list + 1] = fn
  ns.Safe("bind", fn, owner)
end

function ns.RefreshUI()
  for owner, list in pairs(bound) do
    for _, fn in ipairs(list) do
      ns.Safe("refresh", fn, owner)
    end
  end
  ns.Emit("FG_UI_REFRESHED")
end
