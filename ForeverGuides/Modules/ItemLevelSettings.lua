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

function S.Add(view)
  ns.AddHeading(view, "ilvl.heading")
  ns.AddParagraph(view, "ilvl.hint", { role = "micro", color = "textMuted" })
  local function toggle(target, item)
    local get, set = setting(item[1])
    local control = W.Toggle(target.content, {
      key = item[2],
      get = function()
        return get() ~= false
      end,
      set = set,
    })
    control.fgId = "ilvl-" .. item[1]
    target.stack:Add(control, { height = 24, gap = 6 })
  end
  toggle(view, { "itemLevel", "ilvl.enable" })
  toggle(view, { "itemLevelCharacter", "ilvl.character" })
  toggle(view, { "itemLevelBags", "ilvl.bags" })
  -- Where else it shows, the corner, the size and the enchant overlay: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "items.itemlevel" })
  toggle(more, { "itemLevelInspect", "ilvl.inspect" })
  local corners, qualities = {}, {}
  for _, name in ipairs(CORNERS) do
    corners[#corners + 1] = { value = name, key = "ilvl.corner." .. name }
  end
  for _, quality in ipairs(QUALITIES) do
    qualities[#qualities + 1] = { value = quality, key = "ilvl.quality." .. quality, quality = quality }
  end
  local getCorner, setCorner = setting("itemLevelCorner")
  local corner =
    W.Dropdown(more.content, { key = "ilvl.corner", width = 240, options = corners, get = getCorner, set = setCorner })
  corner.fgId = "ilvl-itemLevelCorner"
  more.stack:Add(corner, { height = 46, width = 240 })
  local getQuality, setQuality = setting("itemLevelMinQuality")
  local minQuality = W.Dropdown(
    more.content,
    { key = "ilvl.minQuality", width = 240, options = qualities, get = getQuality, set = setQuality }
  )
  minQuality.fgId = "ilvl-itemLevelMinQuality"
  more.stack:Add(minQuality, { height = 46, width = 240 })
  local getSize, setSize = setting("itemLevelSize")
  local size = W.Slider(more.content, {
    key = "ilvl.size",
    min = O.SIZE_MIN,
    max = O.SIZE_MAX,
    step = 1,
    get = getSize,
    set = setSize,
    format = function(v)
      return string.format("%d px", math.floor(v + 0.5))
    end,
  })
  size.fgId = "ilvl-itemLevelSize"
  more.stack:Add(size, { height = 42, width = 320 })
  -- The overlays of the game's equipment slots: what we draw while another add-on draws there as well.
  local slotOverlays = W.Dropdown(more.content, {
    key = "settings.slotOverlays",
    width = 280,
    options = {
      { value = "auto", key = "settings.slotOverlays.auto" },
      { value = "ours", key = "settings.slotOverlays.ours" },
      { value = "none", key = "settings.slotOverlays.none" },
    },
    get = function()
      return ns.db.settings.slotOverlays
    end,
    set = function(v)
      Store.set("settings.slotOverlays", v)
      ns.RefreshUI()
    end,
  })
  slotOverlays.fgId = "slot-overlays"
  more.stack:Add(slotOverlays, { height = 46, width = 280 })
  ns.AddParagraph(more, "settings.slotOverlaysHint", { role = "micro", color = "textMuted" })
  ns.ItemEnchantSettings.Add(more)
end
