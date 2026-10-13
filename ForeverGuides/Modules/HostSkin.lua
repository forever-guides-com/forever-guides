-- Look of Forever Guides panels that sit on or in Blizzard windows (spellbook list and the like).
-- UI add-ons hide or dim the Blizzard art and draw a dark window, so a panel in the light Blizzard
-- palette would vanish. This module reads what the host window really shows (Detect), applies the
-- player's choice (settings.hostSkin: auto, light, dark), draws an opaque surface of our own that
-- skin sweeps leave alone (Surface) and re-checks a moment after the host shows, because skins fade
-- their art with a delay (Watch). Add-on names are only a hint for /fg diag, never the decision of
-- the host look. SheetOwner says whether an add-on draws item level and enchant text next to the
-- equipment slots (settings.slotOverlays decides what the slot overlays do with that).
local _, ns = ...

local H = {}
ns.HostSkin = H

local Scan = ns.BlizzardScan

-- A page texture counts as drawn from this effective alpha on.
local MIN_ALPHA = 0.5
-- Skins fade their art on the host's OnShow, partly delayed: look again after one frame and after this.
local LATE_DELAY = 0.5
local SURFACE_BORDER = 0.6

-- Texture keys that show the host's own page: any one of them drawn means a light window.
H.Probes = {
  spellbook = { "BookBGLeft", "BookBGRight", "BookBGHalved" },
}

-- Add-ons that restyle Blizzard windows. Listed in /fg diag only.
local SKIN_ADDONS =
  { "EllesmereUI", "EllesmereUIBlizzardSkin", "ElvUI", "Tukui", "TukUI", "Aurora", "AuroraClassic", "Skinner" }

-- Add-ons that draw item level and enchant text next to the slots of the character and the inspect
-- window themselves. Only this list counts as "draws text" (the other skins leave the slots alone).
local SHEET_ADDONS = { "EllesmereUIBlizzardSkin", "ElvUI" }

-- settings.spellbookList of earlier versions, read while settings.hostSkin is not set.
local LEGACY = { auto = "auto", parchment = "light", dark = "dark" }
local MODES = { auto = true, light = true, dark = true }

local function fmt(n)
  return string.format("%g", math.floor(n * 100 + 0.5) / 100)
end

-- Look the host shows: "light" while one of the probe textures is shown and not faded out, "dark"
-- when textures exist and none is, "unknown" when no probe texture exists. Second value: the reason.
function H.Detect(host, probes)
  local found, light, parts = 0, false, {}
  for _, key in ipairs(probes or {}) do
    local tex = Scan.Field(host, key)
    if type(tex) == "table" then
      found = found + 1
      local shown = Scan.Call(tex, "IsShown") ~= false
      local alpha = Scan.Number(tex, "GetEffectiveAlpha") or Scan.Number(tex, "GetAlpha") or 1
      light = light or (shown and alpha >= MIN_ALPHA)
      parts[#parts + 1] = shown and string.format("%s alpha %s", key, fmt(alpha)) or (key .. " hidden")
    end
  end
  if found == 0 then
    return "unknown", "no texture found"
  end
  return light and "light" or "dark", table.concat(parts, ", ")
end

-- The loaded add-ons of a list, in list order.
local function loadedOf(names)
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
  local out = {}
  if type(isLoaded) ~= "function" then
    return out
  end
  for _, name in ipairs(names) do
    local ok, loaded = pcall(isLoaded, name)
    if ok and loaded then
      out[#out + 1] = name
    end
  end
  return out
end

-- The loaded add-ons that restyle Blizzard windows, in list order.
function H.ForeignSkins()
  return loadedOf(SKIN_ADDONS)
end

-- settings.hostSkin as "auto", "light" or "dark"; a damaged value counts as auto.
function H.Mode()
  local s = ns.db and ns.db.settings
  local mode = s and s.hostSkin
  if mode == nil and s then
    mode = LEGACY[s.spellbookList]
  end
  return MODES[mode] and mode or "auto"
end

-- settings.slotOverlays as "auto", "ours" or "none"; a damaged value counts as auto.
function H.SlotMode()
  local s = ns.db and ns.db.settings
  local mode = s and s.slotOverlays
  return (mode == "ours" or mode == "none") and mode or "auto"
end

-- Hosts that were resolved, for H.Report: label -> { host, probes }.
local seen, order = {}, {}

local function remember(host, probes, label)
  label = label or Scan.Call(host, "GetName") or "host"
  if not seen[label] then
    order[#order + 1] = label
  end
  seen[label] = { host = host, probes = probes }
  return label
end

-- "light" or "dark" for a host: the forced choice, else what Detect sees (unknown reads dark).
-- Also returns what Detect saw and why.
function H.Resolve(host, probes, label)
  local detected, reason = H.Detect(host, probes)
  remember(host, probes, label)
  local mode = H.Mode()
  if mode == "light" or mode == "dark" then
    return mode, detected, reason
  end
  return detected == "light" and "light" or "dark", detected, reason
end

local serial = 0
local surfaces = setmetatable({}, { __mode = "k" })

-- Frame with a global name. Skin add-ons treat anonymous frames below a Blizzard frame as Blizzard's
-- own and fade them with the rest; a named frame made by an add-on is left alone together with
-- everything below it.
function H.NamedFrame(parent, label)
  serial = serial + 1
  return CreateFrame("Frame", "ForeverGuides" .. (label or "Host") .. serial, parent)
end

-- One opaque surface (fill and border) over `parent`, made once: a second call returns the same
-- surface. opts: dark (palette, default light), level (frame level above the parent, default 0: below
-- the parent's children), label (part of the global name).
function H.Surface(parent, opts)
  opts = opts or {}
  local existing = surfaces[parent]
  if existing then
    if opts.dark ~= nil then
      existing.SetPalette(opts.dark)
    end
    return existing
  end
  local frame = H.NamedFrame(parent, opts.label or "Surface")
  frame:SetAllPoints(parent)
  frame:SetFrameLevel(math.max(0, parent:GetFrameLevel() + (opts.level or 0)))
  local surface = { frame = frame, dark = opts.dark == true }
  surface.fill = frame:CreateTexture(nil, "BACKGROUND")
  surface.fill:SetAllPoints()
  surface.border = ns.W.Border(frame, "parchmentAccent", SURFACE_BORDER)
  local function paint()
    surface.fill:SetColorTexture(ns.Theme.color(surface.dark and "surface" or "parchment"))
    surface.border.set(surface.dark and "accentDim" or "parchmentAccent", SURFACE_BORDER)
  end
  ns.Bind(frame, paint)
  function surface.SetPalette(dark)
    surface.dark = dark == true
    paint()
  end
  function surface.SetShown(on)
    surface.fill:SetShown(on)
    surface.border.show(on)
  end
  surfaces[parent] = surface
  return surface
end

-- Runs fn once now, once a frame later and once after LATE_DELAY, and again the same way whenever
-- the host shows (OnShow) or changes its size (only now). A newer burst replaces the pending ones.
-- Returns { Burst(skipNow) } for callers that change the host's look themselves.
function H.Watch(host, fn)
  local watch, generation, running = {}, 0, false
  local function run()
    if running then
      return
    end
    running = true
    ns.Safe("host-skin", fn)
    running = false
  end
  local function later(gen)
    return function()
      if gen == generation then
        run()
      end
    end
  end
  function watch.Burst(skipNow)
    generation = generation + 1
    if not skipNow then
      run()
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, later(generation))
      C_Timer.After(LATE_DELAY, later(generation))
    end
  end
  if host and host.HookScript then
    pcall(host.HookScript, host, "OnShow", function()
      watch.Burst()
    end)
    pcall(host.HookScript, host, "OnSizeChanged", run)
  end
  watch.Burst()
  return watch
end

-- Windows with equipment slots: the slot frame prefix and the frames a skin hangs its text overlay on.
local SHEETS = {
  character = { prefix = "Character", frames = { "CharacterFrame", "PaperDollItemsFrame" } },
  inspect = { prefix = "Inspect", frames = { "InspectFrame", "InspectPaperDollItemsFrame" } },
}
H.SHEETS = { "character", "inspect" }

local function objectsOf(frame, method)
  local ok, list = pcall(function()
    return { frame[method](frame) }
  end)
  return ok and list or {}
end

-- Text of a FontString without color codes, nil when it is empty or cannot be read.
local function plainText(region)
  local ok, text = pcall(function()
    local raw = region:GetText()
    if type(raw) ~= "string" then
      return nil
    end
    return (raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
  end)
  return ok and text ~= "" and text or nil
end

local function isOurs(frame)
  local name = Scan.Call(frame, "GetName")
  return type(name) == "string" and name:find("^ForeverGuides") ~= nil
end

local function anchoredTo(region, targets)
  for i = 1, 3 do
    local ok, point, rel = pcall(region.GetPoint, region, i)
    if not ok or point == nil then
      return false
    end
    if targets[rel] then
      return true
    end
  end
  return false
end

-- Counts the shown FontStrings of other add-ons that are anchored to a slot button of the window:
-- numbers (an item level) and other text. Looked at are the regions of the buttons and of the
-- frames next to them, because a skin puts one overlay frame over all slots.
local function foreignSlotTexts(sheet)
  local buttons, containers, added, parents = {}, {}, {}, {}
  local function add(frame)
    if type(frame) == "table" and not added[frame] then
      added[frame] = true
      containers[#containers + 1] = frame
    end
  end
  local function addChildrenOf(frame)
    if type(frame) == "table" and not parents[frame] then
      parents[frame] = true
      for _, child in ipairs(objectsOf(frame, "GetChildren")) do
        add(child)
      end
    end
  end
  for _, slot in ipairs(ns.ItemInfo and ns.ItemInfo.SLOTS or {}) do
    local button = rawget(_G, sheet.prefix .. slot.name)
    if type(button) == "table" then
      buttons[button] = true
      add(button)
      addChildrenOf(Scan.Call(button, "GetParent"))
    end
  end
  for _, name in ipairs(sheet.frames) do
    addChildrenOf(rawget(_G, name))
  end
  local numbers, texts = 0, 0
  for _, container in ipairs(containers) do
    if not isOurs(container) then
      for _, region in ipairs(objectsOf(container, "GetRegions")) do
        if Scan.Call(region, "GetObjectType") == "FontString" and Scan.Call(region, "IsShown") ~= false then
          local text = plainText(region)
          if text and anchoredTo(region, buttons) then
            if text:find("^%d+$") then
              numbers = numbers + 1
            else
              texts = texts + 1
            end
          end
        end
      end
    end
  end
  return numbers, texts
end

-- Whether another add-on draws the slot information of a window itself ("character" or "inspect").
-- Returns the name of that add-on (nil when none does), what it draws as { level, text } and the
-- facts behind it { skins, numbers, texts }. level: shown numbers hang on the slots (seen in the
-- frames, so it holds for any add-on and only once the add-on has built them). text: one of the
-- add-ons that are known to draw enchant text is loaded (its lines cannot be told from stat lines).
function H.SheetOwner(surface)
  local sheet = SHEETS[surface] or SHEETS.character
  local skins = loadedOf(SHEET_ADDONS)
  local numbers, texts = foreignSlotTexts(sheet)
  local owner = skins[1] or (numbers > 0 and "unknown" or nil)
  return owner, { level = numbers > 0, text = #skins > 0 }, { skins = skins, numbers = numbers, texts = texts }
end

local function yesNo(on)
  return on and "yes" or "no"
end

-- The slot part of the diag line: the choice, who draws what in each window.
local function sheetReport()
  local parts = {}
  local owners = {}
  for _, surface in ipairs(H.SHEETS) do
    local owner, draws, facts = H.SheetOwner(surface)
    owners[owner or "none"] = true
    parts[#parts + 1] = string.format(
      "%s level %s text %s (%d numbers, %d texts)",
      surface,
      yesNo(draws.level),
      yesNo(draws.text),
      facts.numbers,
      facts.texts
    )
  end
  local names = {}
  for name in pairs(owners) do
    names[#names + 1] = name
  end
  table.sort(names)
  return string.format(
    "slot texts: mode %s, drawn by %s, %s",
    H.SlotMode(),
    table.concat(names, " "),
    table.concat(parts, "; ")
  )
end

-- One /fg diag line: add-ons that restyle Blizzard windows, the choice and what each host shows now,
-- then who draws the slot texts of the character and the inspect window.
function H.Report()
  local hosts = {}
  for _, label in ipairs(order) do
    local entry = seen[label]
    local detected, reason = H.Detect(entry.host, entry.probes)
    hosts[#hosts + 1] = string.format("%s %s (%s)", label, detected, reason)
  end
  local skins = H.ForeignSkins()
  return string.format(
    "host skin: mode %s, skin add-ons %s, hosts %s, %s",
    H.Mode(),
    #skins > 0 and table.concat(skins, " ") or "none",
    #hosts > 0 and table.concat(hosts, "; ") or "none seen",
    sheetReport()
  )
end
