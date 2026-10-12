-- Settings section "Item level on items" (Modules/ItemLevelOverlay.lua). Every change goes
-- through Store.set, the overlay follows at once through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store
local O = ns.ItemLevelOverlay

local S = {}
ns.ItemLevelSettings = S

ns.AddLocale("enUS", {
  ["ilvl.heading"] = "Item level on items",
  ["ilvl.hint"] = "Small item level number on item icons: character window, bags, bank.\nColored by quality.",
  ["ilvl.enable"] = "Show item level on items",
  ["ilvl.character"] = "Character window",
  ["ilvl.bags"] = "Bags and bank",
  ["ilvl.inspect"] = "Also when inspecting",
  ["ilvl.corner"] = "Corner of the item icon",
  ["ilvl.corner.TOPRIGHT"] = "Top right",
  ["ilvl.corner.BOTTOMRIGHT"] = "Bottom right",
  ["ilvl.corner.TOPLEFT"] = "Top left",
  ["ilvl.minQuality"] = "Lowest quality shown",
  ["ilvl.quality.0"] = "Poor (grey)",
  ["ilvl.quality.1"] = "Common (white)",
  ["ilvl.quality.2"] = "Uncommon (green)",
  ["ilvl.quality.3"] = "Rare (blue)",
  ["ilvl.quality.4"] = "Epic (purple)",
  ["ilvl.size"] = "Font size",
})
ns.AddLocale("deDE", {
  ["ilvl.heading"] = "Itemlevel auf Items",
  ["ilvl.hint"] = "Kleine Itemlevel-Zahl auf Item-Symbolen: Charakterfenster, Taschen, Bank.\nNach Qualität gefärbt.",
  ["ilvl.enable"] = "Itemlevel auf Items anzeigen",
  ["ilvl.character"] = "Charakterfenster",
  ["ilvl.bags"] = "Taschen und Bank",
  ["ilvl.inspect"] = "Auch beim Betrachten",
  ["ilvl.corner"] = "Ecke des Item-Symbols",
  ["ilvl.corner.TOPRIGHT"] = "Oben rechts",
  ["ilvl.corner.BOTTOMRIGHT"] = "Unten rechts",
  ["ilvl.corner.TOPLEFT"] = "Oben links",
  ["ilvl.minQuality"] = "Niedrigste angezeigte Qualität",
  ["ilvl.quality.0"] = "Schlecht (grau)",
  ["ilvl.quality.1"] = "Gewöhnlich (weiß)",
  ["ilvl.quality.2"] = "Ungewöhnlich (grün)",
  ["ilvl.quality.3"] = "Selten (blau)",
  ["ilvl.quality.4"] = "Episch (lila)",
  ["ilvl.size"] = "Schriftgröße",
})

local CORNERS = { "TOPRIGHT", "BOTTOMRIGHT", "TOPLEFT" }
local QUALITIES = { 0, 1, 2, 3, 4 }

local function setting(key)
  return function()
    return O.Option(key)
  end, function(v)
    Store.set("settings." .. key, v)
  end
end

-- The button that runs the item function test (also placed by the settings page on its own). It
-- exists only when an extension registers the test.
function S.AddProbe(view)
  local tool = ns.DevTools.byId.itemprobe
  if not tool then
    return
  end
  view.stack:Add(
    W.Action(view.content, {
      label = "act.test",
      icon = "search",
      tooltip = "ilvl.probe",
      width = 220,
      onClick = tool.run,
    }),
    { height = 26, width = 220 }
  )
end

-- opts.probe == false leaves the test button out.
function S.Add(view, opts)
  local s = view.stack
  ns.AddHeading(view, "ilvl.heading")
  ns.AddParagraph(view, "ilvl.hint", { role = "micro", color = "textMuted" })
  for _, item in ipairs({
    { "itemLevel", "ilvl.enable" },
    { "itemLevelCharacter", "ilvl.character" },
    { "itemLevelBags", "ilvl.bags" },
    { "itemLevelInspect", "ilvl.inspect" },
  }) do
    local get, set = setting(item[1])
    s:Add(
      W.Toggle(view.content, {
        key = item[2],
        get = function()
          return get() ~= false
        end,
        set = set,
      }),
      { height = 24, gap = 6 }
    )
  end
  local corners, qualities = {}, {}
  for _, name in ipairs(CORNERS) do
    corners[#corners + 1] = { value = name, key = "ilvl.corner." .. name }
  end
  for _, quality in ipairs(QUALITIES) do
    qualities[#qualities + 1] = { value = quality, key = "ilvl.quality." .. quality, quality = quality }
  end
  local getCorner, setCorner = setting("itemLevelCorner")
  s:Add(
    W.Dropdown(view.content, { key = "ilvl.corner", width = 240, options = corners, get = getCorner, set = setCorner }),
    { height = 46, width = 240 }
  )
  local getQuality, setQuality = setting("itemLevelMinQuality")
  s:Add(
    W.Dropdown(
      view.content,
      { key = "ilvl.minQuality", width = 240, options = qualities, get = getQuality, set = setQuality }
    ),
    { height = 46, width = 240 }
  )
  local getSize, setSize = setting("itemLevelSize")
  s:Add(
    W.Slider(view.content, {
      key = "ilvl.size",
      min = O.SIZE_MIN,
      max = O.SIZE_MAX,
      step = 1,
      get = getSize,
      set = setSize,
      format = function(v)
        return string.format("%d px", math.floor(v + 0.5))
      end,
    }),
    { height = 42, width = 320 }
  )
  if not (opts and opts.probe == false) then
    S.AddProbe(view)
  end
  ns.ItemEnchantSettings.Add(view)
end
