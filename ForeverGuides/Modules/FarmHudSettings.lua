-- Settings card "Farm HUD" on the map tab: the switch (this session only, nothing is stored for it) and the
-- options of Modules/FarmHud.lua in settings.farmhud. A change of an option while the HUD is on reaches it
-- through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.FarmHudSettings = S

ns.AddLocale("enUS", {
  ["farmhud.set.heading"] = "Farm HUD",
  ["farmhud.set.hint"] = "Enlarges the real minimap over the middle of the screen, behind the interface, so you can see the ore and herb blips of the game with your pins on top. It starts only when you ask for it (/fg farmhud or a key binding) and the minimap moves back when you switch it off, in instances and at logout. It never changes in combat; a switch during combat waits for the end of it.",
  ["farmhud.set.enabled"] = "Farm HUD",
  ["farmhud.set.enabledHint"] = "On or off for this session. Also /fg farmhud and the key binding in the game's key bindings.",
  ["farmhud.set.scale"] = "Size",
  ["farmhud.set.scaleHint"] = "Share of the smaller screen side the minimap takes.",
  ["farmhud.set.strata"] = "Layer",
  ["farmhud.set.strataHint"] = "Background lies behind the whole interface and in front of the 3D world. Low and Medium lie in front of more windows.",
  ["farmhud.set.strata.BACKGROUND"] = "Background",
  ["farmhud.set.strata.LOW"] = "Low",
  ["farmhud.set.strata.MEDIUM"] = "Medium",
  ["farmhud.set.terrain"] = "Terrain on the minimap",
  ["farmhud.set.terrainHint"] = "How the map ground is hidden so only the blips and pins stay. Automatic takes the ground variant when the game offers it.",
  ["farmhud.set.terrain.auto"] = "Automatic",
  ["farmhud.set.terrain.ground"] = "Switch the ground off",
  ["farmhud.set.terrain.alpha"] = "Fade the minimap",
  ["farmhud.set.terrain.none"] = "Leave it as it is",
  ["farmhud.set.alpha"] = "Opacity of the faded minimap",
  ["farmhud.set.alphaHint"] = "Only for the variant that fades the minimap. 0 hides it completely.",
  ["farmhud.set.zoom"] = "Zoom while on",
  ["farmhud.set.zoomHint"] = "Zoom step the minimap takes while the HUD is on (0 shows the most). The old zoom comes back afterwards.",
  ["farmhud.set.zoomKeep"] = "Unchanged",
  ["farmhud.set.hideInCombat"] = "Hide in combat",
  ["farmhud.set.hideInCombatHint"] = "Hides the HUD during a fight and shows it afterwards. The minimap is gone while it is hidden.",
  ["farmhud.set.hideInInstance"] = "Hide in instances",
  ["farmhud.set.hideInInstanceHint"] = "Inside instances the game gives no position. The minimap goes back to its place there and returns outside.",
  ["farmhud.set.compass"] = "Compass",
  ["farmhud.set.compassHint"] = "The four directions at the edge. North is up unless the minimap turns with you.",
  ["farmhud.set.compassSize"] = "Compass size",
  ["farmhud.set.compassSizeHint"] = "Height of the letters in pixels.",
  ["farmhud.set.compassColor"] = "Compass color",
  ["farmhud.set.color.white"] = "White",
  ["farmhud.set.color.yellow"] = "Yellow",
  ["farmhud.set.color.green"] = "Green",
  ["farmhud.set.color.red"] = "Red",
  ["farmhud.set.color.blue"] = "Blue",
  ["farmhud.set.ring"] = "Gather ring",
  ["farmhud.set.ringHint"] = "A circle around you that shows how far you reach.",
  ["farmhud.set.ringYards"] = "Gather ring radius",
  ["farmhud.set.ringYardsHint"] = "Radius of the ring in yards.",
  ["farmhud.set.pinScale"] = "Pin size on the HUD",
  ["farmhud.set.pinScaleHint"] = "Factor on the pin size. 100 % keeps the size the pins have on the small minimap.",
  ["farmhud.set.yards"] = "%d yd",
})
ns.AddLocale("deDE", {
  ["farmhud.set.heading"] = "Farm-HUD",
  ["farmhud.set.hint"] = "Vergrößert die echte Minimap über die Bildschirmmitte, hinter die Oberfläche, damit du die Erz- und Kraut-Blips des Spiels mit deinen Pins darauf siehst. Es startet nur auf Wunsch (/fg farmhud oder eine Tastenbelegung) und die Minimap geht beim Ausschalten, in Instanzen und beim Ausloggen an ihren Platz zurück. Im Kampf ändert sich nichts, ein Schalter im Kampf wartet auf dessen Ende.",
  ["farmhud.set.enabled"] = "Farm-HUD",
  ["farmhud.set.enabledHint"] = "An oder aus für diese Sitzung. Auch /fg farmhud und die Tastenbelegung in den Tastaturbelegungen des Spiels.",
  ["farmhud.set.scale"] = "Größe",
  ["farmhud.set.scaleHint"] = "Anteil der kleineren Bildschirmseite, den die Minimap einnimmt.",
  ["farmhud.set.strata"] = "Ebene",
  ["farmhud.set.strataHint"] = "Hintergrund liegt hinter der ganzen Oberfläche und vor der 3D-Welt. Niedrig und Mittel liegen vor mehr Fenstern.",
  ["farmhud.set.strata.BACKGROUND"] = "Hintergrund",
  ["farmhud.set.strata.LOW"] = "Niedrig",
  ["farmhud.set.strata.MEDIUM"] = "Mittel",
  ["farmhud.set.terrain"] = "Gelände auf der Minimap",
  ["farmhud.set.terrainHint"] = "Wie der Kartenboden ausgeblendet wird, damit nur Blips und Pins bleiben. Automatisch nimmt die Boden-Variante, wenn das Spiel sie anbietet.",
  ["farmhud.set.terrain.auto"] = "Automatisch",
  ["farmhud.set.terrain.ground"] = "Boden ausschalten",
  ["farmhud.set.terrain.alpha"] = "Minimap abblenden",
  ["farmhud.set.terrain.none"] = "Unverändert lassen",
  ["farmhud.set.alpha"] = "Deckkraft der abgeblendeten Minimap",
  ["farmhud.set.alphaHint"] = "Nur für die Variante, die die Minimap abblendet. 0 blendet sie ganz aus.",
  ["farmhud.set.zoom"] = "Zoom im Betrieb",
  ["farmhud.set.zoomHint"] = "Zoomstufe der Minimap, solange das HUD an ist (0 zeigt am meisten). Danach kommt der alte Zoom zurück.",
  ["farmhud.set.zoomKeep"] = "Unverändert",
  ["farmhud.set.hideInCombat"] = "Im Kampf ausblenden",
  ["farmhud.set.hideInCombatHint"] = "Blendet das HUD während eines Kampfs aus und danach wieder ein. Solange es ausgeblendet ist, fehlt die Minimap.",
  ["farmhud.set.hideInInstance"] = "In Instanzen ausblenden",
  ["farmhud.set.hideInInstanceHint"] = "In Instanzen gibt das Spiel keine Position. Die Minimap geht dort an ihren Platz zurück und kommt draußen wieder.",
  ["farmhud.set.compass"] = "Kompass",
  ["farmhud.set.compassHint"] = "Die vier Himmelsrichtungen am Rand. Norden ist oben, solange sich die Minimap nicht mit dir dreht.",
  ["farmhud.set.compassSize"] = "Kompassgröße",
  ["farmhud.set.compassSizeHint"] = "Höhe der Buchstaben in Pixeln.",
  ["farmhud.set.compassColor"] = "Kompassfarbe",
  ["farmhud.set.color.white"] = "Weiß",
  ["farmhud.set.color.yellow"] = "Gelb",
  ["farmhud.set.color.green"] = "Grün",
  ["farmhud.set.color.red"] = "Rot",
  ["farmhud.set.color.blue"] = "Blau",
  ["farmhud.set.ring"] = "Sammelring",
  ["farmhud.set.ringHint"] = "Ein Kreis um dich, der zeigt, wie weit du reichst.",
  ["farmhud.set.ringYards"] = "Radius des Sammelrings",
  ["farmhud.set.ringYardsHint"] = "Radius des Rings in Yards.",
  ["farmhud.set.pinScale"] = "Pin-Größe auf dem HUD",
  ["farmhud.set.pinScaleHint"] = "Faktor auf die Pin-Größe. 100 % behält die Größe, die die Pins auf der kleinen Minimap haben.",
  ["farmhud.set.yards"] = "%d Yards",
})

local FH_PATH = "settings.farmhud."

local function option()
  return ns.FarmHudLogic
end

local function stored(key)
  return option().Settings(Store.get("settings.farmhud"))[key]
end

local function hint(view, id)
  ns.AddParagraph(view, "farmhud.set." .. id .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
end

local function toggle(view, id, get, set)
  local t = W.Toggle(view.content, {
    key = "farmhud.set." .. id,
    tooltip = "farmhud.set." .. id,
    tooltipText = "farmhud.set." .. id .. "Hint",
    get = get,
    set = set,
  })
  t.fgId = "farmhud-set-" .. id
  view.stack:Add(t, { height = 24, gap = 2 })
  hint(view, id)
  return t
end

local function stateToggle(view, key)
  return toggle(view, key, function()
    return stored(key) == true
  end, function(v)
    Store.set(FH_PATH .. key, v and true or false)
  end)
end

-- A slider; value (the shown number) maps to the stored one through to(value).
local function slider(view, id, min, max, step, get, format, to)
  local control = W.Slider(view.content, {
    key = "farmhud.set." .. id,
    min = min,
    max = max,
    step = step,
    get = get,
    set = function(value)
      Store.set(FH_PATH .. id, to(value))
    end,
    format = format,
  })
  control.fgId = "farmhud-set-" .. id
  control.slider:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, ns.L["farmhud.set." .. id], ns.L["farmhud.set." .. id .. "Hint"])
  end)
  control.slider:HookScript("OnLeave", ns.HideTooltip)
  view.stack:Add(control, { height = 42, width = 320, gap = 2 })
  hint(view, id)
end

local function percent(value)
  return string.format("%d %%", math.floor(value + 0.5))
end

local function dropdown(view, id, values, labelKey, get)
  local options = {}
  for i, value in ipairs(values) do
    options[i] = { value = value, key = labelKey .. value }
  end
  local hasHint = ns.Locales.enUS["farmhud.set." .. id .. "Hint"] ~= nil
  local control = W.Dropdown(view.content, {
    key = "farmhud.set." .. id,
    tooltip = "farmhud.set." .. id,
    tooltipText = hasHint and "farmhud.set." .. id .. "Hint" or nil,
    width = 240,
    options = options,
    get = get,
    set = function(value)
      Store.set(FH_PATH .. id, value)
    end,
  })
  control.fgId = "farmhud-set-" .. id
  view.stack:Add(control, { height = 46, width = 240, gap = 4 })
  if hasHint then
    hint(view, id)
  end
end

function S.Add(view)
  local FH, H = option(), ns.FarmHud
  ns.AddHeading(view, "farmhud.set.heading")
  ns.AddParagraph(view, "farmhud.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "enabled", function()
    return H.IsWanted()
  end, function(v)
    H.SetWanted(v)
  end)
  slider(
    view,
    "scale",
    FH.SCALE_MIN * 100,
    FH.SCALE_MAX * 100,
    5,
    function()
      return stored("scale") * 100
    end,
    percent,
    function(value)
      return math.floor(value + 0.5) / 100
    end
  )
  dropdown(view, "strata", FH.STRATA, "farmhud.set.strata.", function()
    return stored("strata")
  end)
  dropdown(view, "terrain", FH.TERRAINS, "farmhud.set.terrain.", function()
    return stored("terrain")
  end)
  slider(
    view,
    "alpha",
    0,
    100,
    5,
    function()
      return stored("alpha") * 100
    end,
    percent,
    function(value)
      return math.floor(value + 0.5) / 100
    end
  )
  slider(view, "zoom", FH.ZOOM_KEEP, FH.ZOOM_MAX, 1, function()
    return stored("zoom")
  end, function(value)
    value = math.floor(value + 0.5)
    return value < FH.ZOOM_MIN and ns.L["farmhud.set.zoomKeep"] or tostring(value)
  end, function(value)
    return math.floor(value + 0.5)
  end)
  stateToggle(view, "hideInCombat")
  stateToggle(view, "hideInInstance")
  stateToggle(view, "compass")
  slider(view, "compassSize", FH.COMPASS_SIZE_MIN, FH.COMPASS_SIZE_MAX, 1, function()
    return stored("compassSize")
  end, function(value)
    return string.format("%d px", math.floor(value + 0.5))
  end, function(value)
    return math.floor(value + 0.5)
  end)
  dropdown(view, "compassColor", FH.COMPASS_ORDER, "farmhud.set.color.", function()
    return stored("compassColor")
  end)
  stateToggle(view, "ring")
  slider(view, "ringYards", FH.RING_YARDS_MIN, FH.RING_YARDS_MAX, FH.RING_YARDS_STEP, function()
    return stored("ringYards")
  end, function(value)
    return string.format(ns.L["farmhud.set.yards"], math.floor(value + 0.5))
  end, function(value)
    return math.floor(value + 0.5)
  end)
  slider(
    view,
    "pinScale",
    FH.PIN_SCALE_MIN * 100,
    FH.PIN_SCALE_MAX * 100,
    5,
    function()
      return stored("pinScale") * 100
    end,
    percent,
    function(value)
      return math.floor(value + 0.5) / 100
    end
  )
end
