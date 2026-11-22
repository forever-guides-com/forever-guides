-- Settings card "Ores and herbs" on the map tab: where the spots show (the addon map, Blizzard's world map,
-- the minimap), the explored look of the world map and the choice of materials, treasures and fishing schools
-- (ns.GatherFilterUI). The switches write through Store.set, WorldMapGather.lua listens to FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.GatheringSettings = S

ns.AddLocale("enUS", {
  ["gather.set.heading"] = "Ores and herbs",
  ["gather.set.hint"] = "Shows where ore veins and herbs grow, and where chests and fishing schools are. Everything starts switched off. Switch on below or in the setup what you want to see. The choice of materials, chests and schools below applies to both maps and is the same in every zone.",
  ["gather.set.forever"] = "Show ores and herbs on the addon map",
  ["gather.set.foreverHint"] = "The page Ores and herbs narrows the items down per zone.",
  ["gather.set.foreverObjects"] = "Show chests and fishing schools on the addon map",
  ["gather.set.foreverObjectsHint"] = "Shows chests, clams, other finds and fishing schools of the zone. You pick the kinds in the list below.",
  ["gather.set.worldmap"] = "Show on Blizzard's world map",
  ["gather.set.worldmapHint"] = "Shows the spots of the zone in the map window, in the big and the small window.",
  ["gather.set.minimap"] = "Show on the minimap",
  ["gather.set.minimapHint"] = "Shows ore and herb spots around you as pins on the minimap. They hide in instances and where the game gives no position.",
  ["gather.set.spotMarker"] = "Mark spots with several possible finds",
  ["gather.set.spotMarkerHint"] = "Draws a colored arc per possible item around the symbol and the number of possibilities at its corner. Small symbols show the number only.",
  ["gather.spots.hint.mining"] = "Symbols show possible spots. One spawn point can hold different veins, you only see which one when you are there.",
  ["gather.spots.hint.herbalism"] = "Symbols show possible spots. One spawn point can hold different plants, you only see which one when you are there.",
  ["gather.spots.hint.both"] = "Symbols show possible spots. One spawn point can hold different ores or herbs, you only see which one when you are there.",
  ["gather.set.minimapEdge"] = "Spots just beyond the minimap edge",
  ["gather.set.minimapEdgeHint"] = "Pull onto the edge shows them faint on the rim as a direction hint. Hide drops them until they come into view.",
  ["gather.set.minimapStyle"] = "Style of spot symbols on minimap/HUD",
  ["gather.set.minimapStyleHint"] = "Spots are possible places, the nodes you can really gather are the icons of the game's own tracking. Subtle draws a small faint ring in the item color so the tracking icons stay easy to see. Item symbol draws the item icon as before. The maps keep their symbols.",
  ["gather.set.style.subtle"] = "Subtle",
  ["gather.set.style.icon"] = "Item symbol",
  ["gather.set.edge.clamp"] = "Pull onto the edge",
  ["gather.set.edge.hide"] = "Hide",
  ["gather.set.minimapSize"] = "Pin size on the minimap",
  ["gather.set.minimapAlpha"] = "Pin opacity on the minimap",
  ["gather.set.minimapNear"] = "Circles up to this distance",
  ["gather.set.minimapNearHint"] = "Spots up to this distance show as a circle only, so the ore or herb the game draws itself stays visible. Farther spots show their symbol. 0 turns the circles off.",
  ["gather.set.minimapNearUnit"] = "%d yd",
  ["gather.set.minimapNearOff"] = "Off",
  ["gather.set.minimapRingSize"] = "Circle size on the minimap",
  ["gather.set.minimapRingSizeHint"] = "Sets the diameter of the circle in pixels.",
  ["gather.set.minimapRingWidth"] = "Circle line width",
  ["gather.set.minimapRingWidthHint"] = "Sets the thickness of the circle line in pixels. The addon uses the nearest ring file.",
  ["gather.set.minimapEmpty"] = "Ores and herbs are switched off in the filter, so the minimap stays empty.",
  ["gather.set.minimapEmptyButton"] = "Switch on",
  ["gather.set.reveal"] = "Show Blizzard's world map as explored",
  ["gather.set.revealHint"] = "Draws every area of a zone map as if you had explored it. Needs the data addon Map data. Works on its own, without the spots. Off puts the normal look back.",
  ["gather.set.materials"] = "Materials",
})
ns.AddLocale("deDE", {
  ["gather.set.heading"] = "Erze und Kräuter",
  ["gather.set.hint"] = "Zeigt, wo Erzadern und Kräuter wachsen und wo Truhen und Fischschwärme liegen. Zu Beginn ist alles ausgeschaltet. Schalte unten oder im Setup ein, was du sehen willst. Die Auswahl der Materialien, Truhen und Schwärme unten gilt für beide Karten und ist in jedem Gebiet gleich.",
  ["gather.set.forever"] = "Erze und Kräuter auf der Addonkarte anzeigen",
  ["gather.set.foreverHint"] = "Die Seite Erze und Kräuter schränkt die Items je Gebiet ein.",
  ["gather.set.foreverObjects"] = "Truhen und Fischschwärme auf der Addonkarte anzeigen",
  ["gather.set.foreverObjectsHint"] = "Zeigt Truhen, Muscheln, weitere Fundstücke und Fischschwärme des Gebiets. Die Arten wählst du in der Liste unten.",
  ["gather.set.worldmap"] = "Auf der Blizzard-Weltkarte anzeigen",
  ["gather.set.worldmapHint"] = "Zeigt die Fundorte des Gebiets im Kartenfenster, im großen und im kleinen Fenster.",
  ["gather.set.minimap"] = "Auf der Minimap anzeigen",
  ["gather.set.minimapHint"] = "Zeigt Erz- und Kräuterfundorte um dich herum als Pins auf der Minimap. In Instanzen und ohne Positionsangabe des Spiels sind sie ausgeblendet.",
  ["gather.set.spotMarker"] = "Fundorte mit mehreren möglichen Funden markieren",
  ["gather.set.spotMarkerHint"] = "Zeichnet pro möglichem Item einen farbigen Bogen um das Symbol und die Anzahl der Möglichkeiten an der Ecke. Kleine Symbole zeigen nur die Zahl.",
  ["gather.spots.hint.mining"] = "Symbole zeigen mögliche Fundorte. Ein Spawnpunkt kann verschiedene Adern tragen, sichtbar ist das erst vor Ort.",
  ["gather.spots.hint.herbalism"] = "Symbole zeigen mögliche Fundorte. Ein Spawnpunkt kann verschiedene Pflanzen tragen, sichtbar ist das erst vor Ort.",
  ["gather.spots.hint.both"] = "Symbole zeigen mögliche Fundorte. Ein Spawnpunkt kann verschiedene Erze oder Kräuter tragen, sichtbar ist das erst vor Ort.",
  ["gather.set.minimapEdge"] = "Fundorte knapp hinter dem Minimaprand",
  ["gather.set.minimapEdgeHint"] = "Auf den Rand ziehen zeigt sie blass am Rand als Richtungshinweis. Ausblenden lässt sie weg, bis sie ins Bild kommen.",
  ["gather.set.edge.clamp"] = "Auf den Rand ziehen",
  ["gather.set.edge.hide"] = "Ausblenden",
  ["gather.set.minimapStyle"] = "Stil der Fundort-Symbole auf Minimap/HUD",
  ["gather.set.minimapStyleHint"] = "Fundorte sind mögliche Stellen. Die Knoten, die du wirklich sammeln kannst, zeigt das eigene Aufspüren des Spiels. Dezent zeichnet einen kleinen, blassen Ring in der Itemfarbe, damit die Symbole des Aufspürens gut sichtbar bleiben. Item-Symbol zeichnet wie bisher das Itemsymbol. Die Karten behalten ihre Symbole.",
  ["gather.set.style.subtle"] = "Dezent",
  ["gather.set.style.icon"] = "Item-Symbol",
  ["gather.set.minimapSize"] = "Pingröße auf der Minimap",
  ["gather.set.minimapAlpha"] = "Pindeckkraft auf der Minimap",
  ["gather.set.minimapNear"] = "Kreise bis zu dieser Entfernung",
  ["gather.set.minimapNearHint"] = "Fundorte bis zu dieser Entfernung erscheinen nur als Kreis, damit das Erz oder Kraut, das das Spiel selbst zeichnet, sichtbar bleibt. Weiter entfernte Fundorte zeigen ihr Symbol. 0 schaltet die Kreise aus.",
  ["gather.set.minimapNearUnit"] = "%d Yards",
  ["gather.set.minimapNearOff"] = "Aus",
  ["gather.set.minimapRingSize"] = "Kreisgröße auf der Minimap",
  ["gather.set.minimapRingSizeHint"] = "Legt den Durchmesser des Kreises in Pixeln fest.",
  ["gather.set.minimapRingWidth"] = "Linienstärke des Kreises",
  ["gather.set.minimapRingWidthHint"] = "Legt die Dicke der Kreislinie in Pixeln fest. Das Addon nutzt die nächstpassende Ringdatei.",
  ["gather.set.minimapEmpty"] = "Erze und Kräuter sind im Filter ausgeschaltet, deshalb bleibt die Minimap leer.",
  ["gather.set.minimapEmptyButton"] = "Einschalten",
  ["gather.set.reveal"] = "Blizzard-Weltkarte als erkundet anzeigen",
  ["gather.set.revealHint"] = "Zeichnet jedes Gebiet einer Zonenkarte so, als hättest du es erkundet. Braucht das Datenaddon Kartendaten. Wirkt für sich allein, ohne die Fundorte. Aus stellt die normale Darstellung wieder her.",
  ["gather.set.materials"] = "Materialien",
})

local LIST_H = 320

local function on(path)
  return Store.get(path) ~= false
end

local function toggle(view, id, path, after)
  local t = W.Toggle(view.content, {
    key = "gather.set." .. id,
    tooltip = "gather.set." .. id,
    tooltipText = "gather.set." .. id .. "Hint",
    get = function()
      return on(path)
    end,
    set = function(v)
      Store.set(path, v and true or false)
      if after then
        after()
      end
    end,
  })
  t.fgId = "gather-set-" .. id
  view.stack:Add(t, { height = 24, gap = 2 })
  ns.AddParagraph(view, "gather.set." .. id .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
  return t
end

-- The options of the minimap pins (Modules/MinimapLayer.lua); each change reaches the layer through
-- FG_SETTING_CHANGED and shows at once.
local function minimapOptions(view)
  local Layer, ML = ns.MinimapLayer, ns.MinimapPinLogic
  local edge = W.Dropdown(view.content, {
    key = "gather.set.minimapEdge",
    tooltip = "gather.set.minimapEdge",
    tooltipText = "gather.set.minimapEdgeHint",
    width = 240,
    options = {
      { value = "clamp", key = "gather.set.edge.clamp" },
      { value = "hide", key = "gather.set.edge.hide" },
    },
    get = Layer.EdgeMode,
    set = function(value)
      Store.set("settings.gather.minimapEdge", value)
    end,
  })
  edge.fgId = "gather-set-minimapEdge"
  view.stack:Add(edge, { height = 46, width = 240, gap = 4 })
  local style = W.Dropdown(view.content, {
    key = "gather.set.minimapStyle",
    tooltip = "gather.set.minimapStyle",
    tooltipText = "gather.set.minimapStyleHint",
    width = 240,
    options = {
      { value = "subtle", key = "gather.set.style.subtle" },
      { value = "icon", key = "gather.set.style.icon" },
    },
    get = Layer.SpotStyle,
    set = function(value)
      Store.set("settings.gather.minimapStyle", value)
    end,
  })
  style.fgId = "gather-set-minimapStyle"
  view.stack:Add(style, { height = 46, width = 240, gap = 4 })
  -- format: a pattern with one %d, or a function (value) -> text; tip: the hint is the tooltip and a line below.
  local function slider(id, min, max, step, get, format, tip)
    local control = W.Slider(view.content, {
      key = "gather.set." .. id,
      min = min,
      max = max,
      step = step,
      get = get,
      set = function(value)
        Store.set("settings.gather." .. id, math.floor(value + 0.5))
      end,
      format = function(value)
        value = math.floor(value + 0.5)
        if type(format) == "function" then
          return format(value)
        end
        return string.format(format, value)
      end,
    })
    control.fgId = "gather-set-" .. id
    if tip then
      control.slider:HookScript("OnEnter", function(self)
        ns.ShowTooltip(self, ns.L["gather.set." .. id], ns.L["gather.set." .. id .. "Hint"])
      end)
      control.slider:HookScript("OnLeave", ns.HideTooltip)
    end
    view.stack:Add(control, { height = 42, width = 320, gap = tip and 2 or 4 })
    if tip then
      ns.AddParagraph(view, "gather.set." .. id .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
    end
  end
  slider("minimapSize", Layer.SIZE_MIN, Layer.SIZE_MAX, 1, Layer.PinSize, "%d px")
  slider("minimapAlpha", Layer.ALPHA_MIN, Layer.ALPHA_MAX, 5, function()
    return Layer.PinAlpha() * 100
  end, "%d %%")
  slider("minimapNear", ML.NEAR_MIN, ML.NEAR_MAX, ML.NEAR_STEP, Layer.NearRange, function(value)
    if value <= 0 then
      return ns.L["gather.set.minimapNearOff"]
    end
    return string.format(ns.L["gather.set.minimapNearUnit"], value)
  end, true)
  slider("minimapRingSize", ML.RING_SIZE_MIN, ML.RING_SIZE_MAX, 1, Layer.RingSize, "%d px", true)
  slider("minimapRingWidth", ML.RING_WIDTH_MIN, ML.RING_WIDTH_MAX, 1, Layer.RingWidth, "%d px", true)
end

-- Both profession filters off leave the minimap empty without a word: a line with a button that switches
-- both on, shown only in that case.
local function emptyNotice(view)
  local F = ns.GatherFilter
  local notice = CreateFrame("Frame", nil, view.content)
  notice.text = W.Text(notice, { key = "gather.set.minimapEmpty", role = "ui", color = "warning", wrap = true })
  notice.button = W.Button(notice, {
    key = "gather.set.minimapEmptyButton",
    width = 120,
    height = 24,
    onClick = function()
      F.SetProfession("mining", true)
      F.SetProfession("herbalism", true)
    end,
  })
  notice.button.fgId = "gather-set-minimapEmptyButton"
  notice.fgId = "gather-set-minimapEmpty"
  notice.fgGridLayout = function(self, width)
    self.text:ClearAllPoints()
    self.text:SetWidth(math.max(1, width))
    self.text:SetPoint("TOPLEFT", 0, 0)
    local textHeight = self.text:GetStringHeight()
    self.button:ClearAllPoints()
    self.button:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", 0, -6)
    local height = textHeight + 6 + 24
    self:SetHeight(height)
    return height
  end
  notice:SetHeight(24)
  local function update()
    notice:SetShown(not (F.ProfessionOn("mining") or F.ProfessionOn("herbalism")))
    view.stack:Layout()
  end
  ns.On("FG_GATHER_FILTER_CHANGED", update)
  view.stack:Add(notice, { gap = 8 })
  notice:SetShown(not (F.ProfessionOn("mining") or F.ProfessionOn("herbalism")))
end

function S.Add(view)
  ns.AddHeading(view, "gather.set.heading")
  ns.AddParagraph(view, "gather.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "forever", "settings.gather.forever")
  toggle(view, "foreverObjects", "settings.gather.foreverObjects")
  toggle(view, "worldmap", "settings.gather.worldmap")
  toggle(view, "minimap", "settings.gather.minimap")
  toggle(view, "spotMarker", "settings.gather.spotMarker")
  ns.AddParagraph(view, "gather.spots.hint.both", { role = "micro", color = "textMuted", gap = 6 })
  emptyNotice(view)
  ns.AddHeading(view, "gather.set.materials")
  local filter = ns.GatherFilterUI.Build(view.content)
  filter:SetListHeight(LIST_H)
  view.stack:Add(filter, { gap = 8 })

  -- The look of the minimap pins and the revealed world map are set once and then left alone.
  local more = W.Accordion(view, { id = view.id or "gathering.pins" })
  minimapOptions(more)
  local RV = ns.MapReveal
  local banner
  local function wanted()
    return on("settings.worldMapReveal") and RV.BannerWanted(false)
  end
  toggle(more, "reveal", "settings.worldMapReveal", function()
    banner:Update(wanted())
    view:Layout()
  end)
  banner = ns.PackageUI.Banner(more.content, RV.ADDON, {
    labelKey = "map.reveal.pkg",
    onLoaded = function()
      ns.WorldMapGather.Refresh()
      view:Layout()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  banner:Update(wanted())
  more.stack:Add(banner, { gap = 8 })
end
