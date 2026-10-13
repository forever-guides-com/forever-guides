-- Map & route page: places, connections, faction/transport filters, route
-- planning and a canvas view. Data: ns.Data.Travel (canvas of the website,
-- no UiMapID), logic: ns.TravelLogic.
local _, ns = ...
local W, L, Theme, TL, K, MW, MM, MZ =
  ns.W, ns.L, ns.Theme, ns.TravelLogic, ns.PageKit, ns.MapWorld, ns.MapMarkers, ns.MapZoom
local MP, PL, ML, MI = ns.MapPins, ns.MapPlaceList, ns.MapLegend, ns.MapIcons
local MR, MRL, MG = ns.MapRoute, ns.MapRouteList, ns.MapMagnify
local RV = ns.MapReveal

ns.AddLocale("enUS", {
  ["map.intro"] = "Pick start and goal to see the fastest connection.",
  ["map.canvasNote"] = "Places sit on the travel canvas, not on game coordinates.\n%d of %d places have estimated positions.",
  ["map.world.note"] = "World map: %d of %d places in their real zone.\n%d estimated, %d on the schematic island.",
  ["map.world.island"] = "%s (schematic)",
  ["map.art.label"] = "Map image",
  ["map.display"] = "Display",
  ["map.symbols"] = "Show symbols",
  ["map.names"] = "Show names",
  ["map.symbolSize"] = "Symbol size",
  ["map.symbolSmaller"] = "Smaller",
  ["map.symbolBigger"] = "Bigger",
  ["map.symbolSizeTip"] = "Click: %d %%",
  ["map.dim"] = "Dim filtered places",
  ["map.dimTip"] = "Filtered places stay faded and not clickable.\nOff: hidden.",
  ["map.rb.open"] = "Open route window",
  ["map.filters"] = "Filters",
  ["map.useLevel"] = "Respect my level",
  ["map.skyborne"] = "Skyborne race",
  ["map.preferFlight"] = "Prefer flying",
  ["map.preferFlight.tip"] = "Walking legs count as longer when routes are compared, so a flight wins when the times are close.\nWalking stays allowed, the times shown are the real ones.",
  ["map.mount"] = "With mount",
  ["map.mount.tip"] = "Off: walking takes 1.6 times as long.",
  ["map.mode.flight"] = "Flight",
  ["map.mode.boat"] = "Boat",
  ["map.mode.zeppelin"] = "Zeppelin",
  ["map.mode.tram"] = "Tram",
  ["map.mode.portal"] = "Portal",
  ["map.mode.walk"] = "Walking",
  ["map.mode.spell"] = "Spell",
  ["map.mode.teleport"] = "Teleport",
  ["map.rq.classMage"] = "mage only",
  ["map.rq.classDruid"] = "druid only",
  ["map.rq.skyborne"] = "Skyborne only",
  ["map.rq.quest"] = "quest needed",
  ["map.rq.reputation"] = "reputation needed",
  ["map.rq.item"] = "item needed",
  ["map.cf.reported"] = "reported",
  ["map.cf.estimate"] = "estimated",
  ["map.places"] = "Places",
  ["map.placeSearch"] = "Filter places",
  ["map.start"] = "Start: %s",
  ["map.dest"] = "Destination: %s",
  ["map.none"] = "not set",
  ["map.tagStart"] = "Start",
  ["map.tagDest"] = "Destination",
  ["map.setStart"] = "Set as start",
  ["map.setDest"] = "Set as destination",
  ["map.swap"] = "Swap",
  ["map.route"] = "Route",
  ["map.route.pick"] = "Choose a start and a destination to see the route.",
  ["map.route.same"] = "Start and destination are the same place.",
  ["map.route.none"] = "No connection, change filters or faction.",
  ["map.route.total"] = "Total %s in %d leg(s)",
  ["map.route.alt"] = "Without %s: %s in %d leg(s)",
  ["map.route.cost"] = "cost %s",
  ["map.route.waitNote"] = "Times include the average wait.",
  ["map.canvas"] = "Map",
  ["map.details"] = "Details",
  ["map.tab.azeroth"] = "Azeroth",
  ["map.tab.island"] = "New Forever regions",
  ["map.tab.islandHint"] = "New Forever regions: schematic, one box per region.\nPositions are approximations.",
  ["map.place.tip"] = "%s · %s",
  ["map.kind.city"] = "City",
  ["map.kind.flightMaster"] = "Flight master",
  ["map.kind.harbor"] = "Harbor",
  ["map.kind.zeppelinTower"] = "Zeppelin tower",
  ["map.kind.tram"] = "Tram",
  ["map.kind.portal"] = "Portal",
  ["map.kind.instanceEntrance"] = "Instance entrance",
  ["map.kind.landmark"] = "Landmark",
  ["map.placeholderZone"] = "Zone location unconfirmed",
  ["tour.map.title"] = "Map & route",
  ["tour.map.intro.title"] = "Route planning",
  ["tour.map.intro.text"] = "Finds the fastest connection (Enter next, Esc ends the tour).",
  ["tour.map.filters.title"] = "Filters",
  ["tour.map.filters.text"] = "Choose faction and allowed transport types (Tab, Enter).",
  ["tour.map.places.title"] = "Places",
  ["tour.map.places.text"] = "Type to filter, Tab to a place, Enter selects, then set start or goal.",
  ["tour.map.route.title"] = "Route",
  ["tour.map.route.text"] = "Legs of the fastest route and alternatives.",
  ["tour.map.canvas.title"] = "Map view",
  ["tour.map.canvas.text"] = "Places and route on the world map, click selects a place.",
})

ns.AddLocale("deDE", {
  ["map.intro"] = "Start und Ziel wählen, die schnellste Verbindung erscheint.",
  ["map.canvasNote"] = "Orte liegen auf der Reise-Leinwand, nicht auf Spielkoordinaten.\n%d von %d Orten mit geschätzter Position.",
  ["map.world.note"] = "Weltkarte: %d von %d Orten in echter Zone.\n%d geschätzt, %d auf der Schemainsel.",
  ["map.world.island"] = "%s (schematisch)",
  ["map.art.label"] = "Kartenbild",
  ["map.display"] = "Anzeige",
  ["map.symbols"] = "Symbole zeigen",
  ["map.names"] = "Namen zeigen",
  ["map.symbolSize"] = "Symbolgröße",
  ["map.symbolSmaller"] = "Kleiner",
  ["map.symbolBigger"] = "Größer",
  ["map.symbolSizeTip"] = "Klick: %d %%",
  ["map.dim"] = "Gefilterte Orte dimmen",
  ["map.dimTip"] = "Ausgefilterte Orte bleiben blass und nicht klickbar.\nAus: ausgeblendet.",
  ["map.rb.open"] = "Routen-Fenster öffnen",
  ["map.filters"] = "Filter",
  ["map.useLevel"] = "Meine Stufe beachten",
  ["map.skyborne"] = "Skyborne-Volk",
  ["map.preferFlight"] = "Fliegen bevorzugen",
  ["map.preferFlight.tip"] = "Laufstrecken zählen beim Vergleich der Routen länger, so gewinnt ein Flug bei ähnlicher Dauer.\nLaufen bleibt erlaubt, die gezeigten Zeiten sind die echten.",
  ["map.mount"] = "Mit Reittier",
  ["map.mount.tip"] = "Aus: Laufen dauert 1,6 mal so lang.",
  ["map.mode.flight"] = "Flug",
  ["map.mode.boat"] = "Boot",
  ["map.mode.zeppelin"] = "Zeppelin",
  ["map.mode.tram"] = "Tiefenbahn",
  ["map.mode.portal"] = "Portal",
  ["map.mode.walk"] = "Zu Fuß",
  ["map.mode.spell"] = "Zauber",
  ["map.mode.teleport"] = "Teleport",
  ["map.rq.classMage"] = "nur Magier",
  ["map.rq.classDruid"] = "nur Druide",
  ["map.rq.skyborne"] = "nur Skyborne",
  ["map.rq.quest"] = "Quest nötig",
  ["map.rq.reputation"] = "Ruf nötig",
  ["map.rq.item"] = "Gegenstand nötig",
  ["map.cf.reported"] = "gemeldet",
  ["map.cf.estimate"] = "geschätzt",
  ["map.places"] = "Orte",
  ["map.placeSearch"] = "Orte filtern",
  ["map.start"] = "Start: %s",
  ["map.dest"] = "Ziel: %s",
  ["map.none"] = "nicht gesetzt",
  ["map.tagStart"] = "Start",
  ["map.tagDest"] = "Ziel",
  ["map.setStart"] = "Als Start",
  ["map.setDest"] = "Als Ziel",
  ["map.swap"] = "Tauschen",
  ["map.route"] = "Route",
  ["map.route.pick"] = "Wähle Start und Ziel, um die Route zu sehen.",
  ["map.route.same"] = "Start und Ziel sind derselbe Ort.",
  ["map.route.none"] = "Keine Verbindung, ändere Filter oder Fraktion.",
  ["map.route.total"] = "Gesamt %s in %d Etappe(n)",
  ["map.route.alt"] = "Ohne %s: %s in %d Etappe(n)",
  ["map.route.cost"] = "Kosten %s",
  ["map.route.waitNote"] = "Zeiten enthalten die durchschnittliche Wartezeit.",
  ["map.canvas"] = "Karte",
  ["map.details"] = "Details",
  ["map.tab.azeroth"] = "Azeroth",
  ["map.tab.island"] = "Neue Forever-Regionen",
  ["map.tab.islandHint"] = "Neue Forever-Regionen: schematisch, ein Feld pro Region.\nPositionen sind Näherungen.",
  ["map.place.tip"] = "%s · %s",
  ["map.kind.city"] = "Stadt",
  ["map.kind.flightMaster"] = "Flugmeister",
  ["map.kind.harbor"] = "Hafen",
  ["map.kind.zeppelinTower"] = "Zeppelinturm",
  ["map.kind.tram"] = "Tiefenbahn",
  ["map.kind.portal"] = "Portal",
  ["map.kind.instanceEntrance"] = "Instanzeingang",
  ["map.kind.landmark"] = "Landmarke",
  ["map.placeholderZone"] = "Lage der Zone unbestätigt",
  ["tour.map.title"] = "Karte & Route",
  ["tour.map.intro.title"] = "Routenplanung",
  ["tour.map.intro.text"] = "Findet die schnellste Verbindung (Enter weiter, Esc beenden).",
  ["tour.map.filters.title"] = "Filter",
  ["tour.map.filters.text"] = "Fraktion und erlaubte Verkehrsmittel wählen (Tab, Enter).",
  ["tour.map.places.title"] = "Orte",
  ["tour.map.places.text"] = "Tippen filtert, Tab zum Ort, Enter wählt, dann Start oder Ziel.",
  ["tour.map.route.title"] = "Route",
  ["tour.map.route.text"] = "Etappen der schnellsten Route und Alternativen.",
  ["tour.map.canvas.title"] = "Kartenansicht",
  ["tour.map.canvas.text"] = "Orte und Route auf der Weltkarte, Klick wählt einen Ort aus.",
})

local UI_MODES = { "flight", "boat", "zeppelin", "tram", "portal", "walk", "spell" }

-- Opens the page on request of another part of the addon (the Blizzard world map): spec = { map =
-- UiMapID of the zone to show, x, y = optional position in the zone (fractions 0..1) to point at
-- with label as its name, start, dest = place slugs, faction, query = text for the place search,
-- markers = true to start in marker mode, stops = place slugs between start and dest (at most
-- TL.MAX_STOPS) }. The page takes it in Show. Request.shared is the state of the page that was built
-- last (faction, transport switches, flying and mount options): the world map bar plans with it.
local Request = {}
ns.MapRequest = Request

function Request.Open(spec)
  Request.pending = spec
  ns.Main.Show("map")
end

function Request.Take()
  local spec = Request.pending
  Request.pending = nil
  return spec
end

-- Map art -----------------------------------------------------------------------
-- The world map and the node placement come from ns.MapWorld; this file only
-- paints them. Without the needed C_Map functions the canvas stays flat.
local ART_ALPHA = 0.6
-- Brightness of the map tiles outside the explored pieces in the exploration mode.
local FOG_DIM = 0.3

-- Lays the art's tiles over the canvas, stretched to its size; art == nil hides them.
-- Edge tiles are cropped to the layer size, the rest of a tile is padding. pieces are the
-- overlay pictures on top (ns.MapReveal.Draw): all of the zone in the revealed mode, the explored
-- ones in the exploration mode (dim: the tiles go dark there); nil draws none.
local function paintArt(canvas, art, pieces, dim)
  RV.DrawBase(canvas, art, { alpha = ART_ALPHA, shade = dim and FOG_DIM or 1 })
  RV.Draw(canvas, art, pieces, ART_ALPHA)
end

-- Draws the schematic panel for regions that are not part of the world art (the whole canvas
-- on the island tab, see MW.IslandView); panel == nil hides it. It sits below the dots.
local function paintPanel(canvas, panel, title, zoneOf)
  local p = canvas.panel
  if not p then
    p = { fill = canvas:CreateTexture(nil, "BACKGROUND", nil, 2), edges = {}, cells = {} }
    for i = 1, 4 do
      p.edges[i] = canvas:CreateTexture(nil, "BORDER")
    end
    p.title = W.Text(canvas, { role = "micro", color = "textSecondary" })
    canvas.panel = p
  end
  local shown = panel ~= nil
  p.fill:SetShown(shown)
  p.title:SetShown(shown)
  for _, edge in ipairs(p.edges) do
    edge:SetShown(shown)
  end
  for _, label in ipairs(p.cells) do
    label:Hide()
  end
  if not panel then
    return
  end
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  local x, y, w, h = panel.l * cw, panel.t * ch, panel.w * cw, panel.h * ch
  p.fill:ClearAllPoints()
  p.fill:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
  p.fill:SetSize(w, h)
  p.fill:SetColorTexture(Theme.color("surface", 0.92))
  local bounds = { { x, y, w, 1 }, { x, y + h - 1, w, 1 }, { x, y, 1, h }, { x + w - 1, y, 1, h } }
  for i, edge in ipairs(p.edges) do
    local b = bounds[i]
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", canvas, "TOPLEFT", b[1], -b[2])
    edge:SetSize(b[3], b[4])
    edge:SetColorTexture(Theme.color("accent2", 0.8))
  end
  p.title:ClearAllPoints()
  p.title:SetPoint("TOPLEFT", canvas, "TOPLEFT", x + 6, -(y + 4))
  p.title:SetWidth(w - 12)
  W.SetText(p.title, nil, title)
  for i, cell in ipairs(panel.cells) do
    local label = p.cells[i]
    if not label then
      label = W.Text(canvas, { role = "micro", color = "textMuted", justify = "CENTER" })
      p.cells[i] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", canvas, "TOPLEFT", cell.l * cw, -(cell.labelT * ch))
    label:SetWidth(cell.w * cw)
    local zone = zoneOf[cell.zone]
    W.SetText(label, nil, zone and ns.T(zone.n) or cell.zone)
    label:Show()
  end
end

local MIN_CANVAS = 260 -- the height cap never squeezes the map below this
local SIDE_MAX = 520 -- width cap of the side column, the map takes the rest
local GAP = 6
local TOOLBAR_H = 26
local DIM_W = 230 -- width of the "dim filtered places" switch
local HEADER_H = 24

-- Places chips ({ w, h }, sets x and y) left to right, wrapped at width and centered on their line.
-- Returns the height of all lines.
local function flowChips(chips, width)
  local lines, line, x = {}, nil, 0
  for _, chip in ipairs(chips) do
    if not line or x + chip.w > width then
      line, x = { h = 0 }, 0
      lines[#lines + 1] = line
    end
    line[#line + 1] = chip
    chip.x = x
    x = x + chip.w + GAP
    line.h = math.max(line.h, chip.h)
  end
  local y = 0
  for _, l in ipairs(lines) do
    for _, chip in ipairs(l) do
      chip.y = y + math.floor((l.h - chip.h) / 2)
    end
    y = y + l.h + GAP
  end
  return #lines > 0 and y - GAP or 0
end

local function savedTab()
  return ns.Store.get("settings.mapTab") == "island" and "island" or "azeroth"
end

local function build(container)
  local FL = ns.FlowLayout
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    faction = K.PlayerFaction() or "A",
    useLevel = true,
    skyborne = false,
    mount = true,
    preferFlight = true,
    stops = {},
    artOn = true,
    modes = {},
    query = "",
    tab = savedTab(),
    introOpen = false,
  }
  for _, m in ipairs(UI_MODES) do
    state.modes[m] = true
  end
  Request.shared = state
  local byslug, zoneOf = {}, {}
  local data, world, layout, island, estimated
  local refresh, layoutPanes, followTab, intro
  local markers, zoom, pins, places, legend, route, routeList, showStep, mag, stopsList
  local exploredCache = {}
  -- True while the map pane is laid out: a banner that changes its height then must not start another layout.
  local laying = false

  -- Header: one-line hint and the fold-out intro --------------------------
  local header = CreateFrame("Frame", nil, view.content)
  local paintDetails
  local detailsButton = W.Button(header, {
    key = "map.details",
    variant = "ghost",
    width = 100,
    height = HEADER_H,
    onClick = function()
      state.introOpen = not state.introOpen
      intro:SetShown(state.introOpen)
      paintDetails()
      view:Layout()
    end,
  })
  local hint = W.Text(header, { key = "map.route.pick", role = "ui", color = "textSecondary" })
  function header:fgGridLayout()
    detailsButton:ClearAllPoints()
    detailsButton:SetPoint("TOPRIGHT", self, "TOPRIGHT")
    hint:ClearAllPoints()
    hint:SetPoint("LEFT", self, "LEFT", 0, 0)
    hint:SetPoint("RIGHT", detailsButton, "LEFT", -10, 0)
    self:SetHeight(HEADER_H)
    return HEADER_H
  end
  s:Add(header, { gap = GAP })
  intro = ns.AddParagraph(view, "map.intro", { gap = GAP })
  intro:SetShown(false)
  function paintDetails()
    W.SetText(detailsButton.label, nil, (state.introOpen and "v " or "> ") .. L["map.details"])
  end
  paintDetails()
  ns.On("FG_UI_REFRESHED", paintDetails)
  K.Anchor("FG.Map.Details", detailsButton)
  K.Anchor("FG.Map.Intro", intro)

  local function nodeName(slug)
    local n = byslug[slug]
    return n and ns.T(n.n) or tostring(slug or "?")
  end

  local function zoneLabel(slug)
    local z = zoneOf[slug]
    return z and ns.T(z.n) or nil
  end

  local function dimFiltered()
    return ns.Store.get("settings.mapDimFiltered") == true
  end

  -- Display settings: symbols and names default on, the map image defaults to fully revealed.
  local function symbolsOn()
    return ns.Store.get("settings.mapSymbols") ~= false
  end

  local function namesOn()
    return ns.Store.get("settings.mapNames") ~= false
  end

  local function revealOn()
    return RV.Revealed()
  end

  local function symbolScale()
    return MP.ClampScale(ns.Store.get("settings.mapSymbolScale"))
  end

  -- Hover is shared between a pin and its card: one slug, both sides repaint.
  local function setHover(slug)
    if state.hover == slug then
      return
    end
    state.hover = slug
    pins.Paint()
    places.PaintHover()
  end

  local function unhover(slug)
    if state.hover == slug then
      setHover(nil)
    end
  end

  local function opts()
    return MRL.Options(state)
  end

  -- Two panes under the header: the map on the left, the side column (filters, places,
  -- start/destination, route) with its own scroll on the right. Stacked on narrow pages, map first.
  local function visibleHeight()
    local above = HEADER_H + GAP + (state.introOpen and intro:GetStringHeight() + GAP or 0)
    return view.area:GetHeight() - 2 * s.pad - above
  end
  local split = FL.TwoPane(view.content, {
    ratio = 0.62,
    leftMax = 100000,
    rightMin = 240,
    rightMax = SIDE_MAX,
    stackedShare = 0,
    minHeight = 400,
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = visibleHeight,
    onLayout = function(info)
      return layoutPanes(info)
    end,
  })
  s:Add(split, { gap = 0 })
  local leftPane, rightPane = split.left, split.right
  local sideArea = W.ScrollArea(rightPane)
  sideArea:SetFrameLevel(rightPane:GetFrameLevel() + 1)
  sideArea:SetAllPoints()
  local side = { area = sideArea, content = sideArea.content, stack = W.Stack(sideArea, GAP) }

  -- Filters ----------------------------------------------------------------
  ns.AddHeading(side, "map.filters")
  local filterBox = CreateFrame("Frame", nil, side.content)
  K.Anchor("FG.Map.Filters", filterBox)
  local faction = K.FactionButtons(filterBox, {
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  })
  local checks = {}
  for _, m in ipairs(UI_MODES) do
    checks[#checks + 1] = W.Checkbox(filterBox, {
      key = "map.mode." .. m,
      get = function()
        return state.modes[m]
      end,
      set = function(v)
        state.modes[m] = v
        refresh()
      end,
    })
  end
  local function option(key, field)
    return W.Checkbox(filterBox, {
      key = key,
      tooltip = key,
      tooltipText = key .. ".tip",
      get = function()
        return state[field]
      end,
      set = function(v)
        state[field] = v
        refresh()
      end,
    })
  end
  checks[#checks + 1] = option("map.preferFlight", "preferFlight")
  checks[#checks + 1] = option("map.mount", "mount")
  checks[#checks + 1] = W.Checkbox(filterBox, {
    key = "map.useLevel",
    get = function()
      return state.useLevel
    end,
    set = function(v)
      state.useLevel = v
      refresh()
    end,
  })
  checks[#checks + 1] = W.Checkbox(filterBox, {
    key = "map.skyborne",
    get = function()
      return state.skyborne
    end,
    set = function(v)
      state.skyborne = v
      refresh()
    end,
  })
  function filterBox:fgGridLayout(width)
    faction:ClearAllPoints()
    faction:SetPoint("TOPLEFT", self, "TOPLEFT")
    faction:SetWidth(width)
    local top = faction:fgGridLayout(width) + 12
    local cols = math.max(1, math.min(4, math.floor(width / 150)))
    local cw = width / cols
    for i, c in ipairs(checks) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", self, "TOPLEFT", col * cw, -top - row * 26)
      c:SetSize(cw - 8, 24)
    end
    local h = top + math.ceil(#checks / cols) * 26
    self:SetHeight(h)
    return h
  end
  side.stack:Add(filterBox)

  -- Display: symbols, names, symbol size ------------------------------------------------------
  ns.AddHeading(side, "map.display")
  local displayBox = CreateFrame("Frame", nil, side.content)
  K.Anchor("FG.Map.Display", displayBox)
  local function switch(key, setting, on, tip)
    return W.Checkbox(displayBox, {
      key = key,
      tooltip = tip and key,
      tooltipText = tip,
      get = on,
      set = function(v)
        ns.Store.set(setting, v)
        refresh()
      end,
    })
  end
  local switches = {
    switch("map.symbols", "settings.mapSymbols", symbolsOn),
    switch("map.names", "settings.mapNames", namesOn),
  }
  local sizeLabel = W.Text(displayBox, { key = "map.symbolSize", role = "ui" })
  local sizeValue
  local function paintSize()
    sizeValue.text:SetText(string.format("%d %%", symbolScale()))
  end
  local function setScale(percent)
    ns.Store.set("settings.mapSymbolScale", MP.ClampScale(percent))
    paintSize()
    refresh()
  end
  local smaller = W.Action(displayBox, {
    icon = "minus",
    size = 24,
    tooltip = "map.symbolSmaller",
    onClick = function()
      setScale(symbolScale() - MP.SCALE_STEP)
    end,
  })
  sizeValue = W.ValueButton(displayBox, {
    width = 48,
    height = 24,
    tooltip = "map.symbolSize",
    tooltipText = function()
      return string.format(L["map.symbolSizeTip"], MP.SCALE_DEFAULT)
    end,
    onClick = function()
      setScale(MP.SCALE_DEFAULT)
    end,
  })
  local bigger = W.Action(displayBox, {
    icon = "plus",
    size = 24,
    tooltip = "map.symbolBigger",
    onClick = function()
      setScale(symbolScale() + MP.SCALE_STEP)
    end,
  })
  paintSize()
  displayBox.switches, displayBox.smaller = switches, smaller
  displayBox.sizeValue, displayBox.bigger = sizeValue, bigger
  function displayBox:fgGridLayout(width)
    local cols = math.max(1, math.min(3, math.floor(width / 170)))
    local cw = width / cols
    for i, c in ipairs(switches) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", self, "TOPLEFT", col * cw, -row * 26)
      c:SetSize(cw - 8, 24)
    end
    local top = math.ceil(#switches / cols) * 26 + 4
    bigger:ClearAllPoints()
    bigger:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -top)
    sizeValue:ClearAllPoints()
    sizeValue:SetPoint("RIGHT", bigger, "LEFT")
    smaller:ClearAllPoints()
    smaller:SetPoint("RIGHT", sizeValue, "LEFT")
    sizeLabel:ClearAllPoints()
    sizeLabel:SetPoint("LEFT", self, "TOPLEFT", 0, -(top + 12))
    sizeLabel:SetPoint("RIGHT", smaller, "LEFT", -6, 0)
    self:SetHeight(top + 24)
    return top + 24
  end
  side.stack:Add(displayBox)

  -- Places -----------------------------------------------------------------
  ns.AddHeading(side, "map.places")
  local placeBox = CreateFrame("Frame", nil, side.content)
  K.Anchor("FG.Map.Places", placeBox)
  local search = W.EditBox(placeBox, {
    placeholder = "map.placeSearch",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT")
  search:SetPoint("TOPRIGHT")
  places = PL.Attach({
    parent = placeBox,
    search = search,
    data = function()
      return data
    end,
    opts = opts,
    query = function()
      return state.query
    end,
    zone = function()
      return zoom and zoom.Zone()
    end,
    nameOf = function(n)
      return ns.T(n.n)
    end,
    zoneName = zoneLabel,
    state = state,
    onSelect = function(slug)
      state.selected = slug
      followTab(slug)
      refresh()
    end,
    hover = setHover,
    unhover = unhover,
    setRoute = function(which, slug)
      state[which] = slug
      refresh()
    end,
    spec = function(n)
      return PL.ZonePoint({ layout, island }, n)
    end,
    show = function(slug)
      state.selected = slug
      followTab(slug)
      refresh()
      local n = byslug[slug]
      if n and zoom.Zone() ~= n.z then
        zoom.Enter(n.z)
      end
    end,
  })
  function placeBox:fgGridLayout()
    local h = places.Height()
    self:SetHeight(h)
    return h
  end
  side.stack:Add(placeBox)

  -- Start, stops and goal ---------------------------------------------------------------
  local function resetRoute()
    state.start, state.dest, state.selected, state.pickNext = nil, nil, nil, nil
    state.stops = {}
    refresh()
  end
  local planHead = CreateFrame("Frame", nil, side.content)
  local planTitle = W.Text(planHead, { key = "map.plan", role = "h3", family = "heading", color = "accent2" })
  local resetButton = W.Action(planHead, {
    icon = "reset",
    size = 28,
    boxed = true,
    tooltip = "map.resetRoute",
    tooltipText = "map.resetRoute.tip",
    onClick = resetRoute,
  })
  K.Anchor("FG.Map.Reset", resetButton)
  function planHead:fgGridLayout()
    resetButton:ClearAllPoints()
    resetButton:SetPoint("TOPRIGHT", self, "TOPRIGHT")
    planTitle:ClearAllPoints()
    planTitle:SetPoint("LEFT", self, "LEFT")
    planTitle:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    self:SetHeight(resetButton:GetHeight())
    return resetButton:GetHeight()
  end
  side.stack:Add(planHead, { gap = 6 })
  stopsList = MRL.AttachStops({
    side = side,
    state = state,
    nameOf = nodeName,
    changed = function()
      refresh()
    end,
  })
  local startText, destText = stopsList.startText, stopsList.destText
  K.Anchor("FG.Map.StartText", startText)
  K.Anchor("FG.Map.DestText", destText)
  K.Anchor("FG.Map.Stops", stopsList.box)
  side.stack:Add(stopsList.box, { gap = 6 })
  local function useSelected(which)
    return function()
      if state.selected then
        state[which] = state.selected
        refresh()
      end
    end
  end
  local buttons = FL.ButtonRow(side.content, {
    {
      id = "start",
      label = "act.start",
      icon = "play",
      tooltip = "map.setStart",
      variant = "primary",
      width = 110,
      onClick = useSelected("start"),
    },
    {
      id = "dest",
      label = "act.goal",
      icon = "marker",
      tooltip = "map.setDest",
      variant = "primary",
      width = 110,
      onClick = useSelected("dest"),
    },
    {
      id = "stop",
      label = "act.stop",
      icon = "plus",
      width = 150,
      tooltip = "map.addStop",
      tooltipText = "map.addStop.tip",
      onClick = function()
        if MRL.AddStop(state, state.selected) then
          refresh()
        end
      end,
    },
    {
      id = "swap",
      label = "act.swap",
      icon = "refresh",
      tooltip = "map.swap",
      width = 80,
      onClick = function()
        state.start, state.dest = state.dest, state.start
        local reversed = {}
        for i = #state.stops, 1, -1 do
          reversed[#reversed + 1] = state.stops[i]
        end
        state.stops = reversed
        refresh()
      end,
    },
  })
  K.Anchor("FG.Map.RouteButtons", buttons)
  side.stack:Add(buttons)

  -- Takes over a route text (MRL.Encode): faction, start, stops and goal, all places known for it.
  local paste
  local function takeRoute(text)
    local spec = MRL.Decode(text)
    if not spec then
      ns.Notify(L["map.route.paste.bad"], "warning")
      return
    end
    local o = opts()
    o.faction = spec.faction
    for _, slug in ipairs(MRL.Chain(spec)) do
      local n = byslug[slug]
      if not (n and TL.NodeVisible(n, o)) then
        ns.Notify(string.format(L["map.route.paste.unknown"], slug), "warning")
        return
      end
    end
    state.faction, state.start, state.stops, state.dest = spec.faction, spec.start, spec.stops, spec.dest
    paste.edit:SetText("")
    ns.Notify(L["map.route.paste.done"], "success")
    refresh()
  end
  paste = W.EditBox(side.content, {
    placeholder = "map.route.paste",
    clear = true,
    onChange = function(text)
      if MRL.Decode(text) then
        takeRoute(text)
      end
    end,
    onEnter = function(text)
      if ns.U.trim(text) ~= "" then
        takeRoute(text)
      end
    end,
  })
  K.Anchor("FG.Map.Paste", paste)
  side.stack:Add(paste, { height = 26 })
  legend = ML.Attach({
    side = side,
    relayout = function()
      view:Layout()
    end,
  })

  -- Route ------------------------------------------------------------------
  ns.AddHeading(side, "map.route")
  local routeCtx = {
    side = side,
    state = state,
    nameOf = nodeName,
    specFor = function(slug)
      local n = byslug[slug]
      return n and PL.ZonePoint({ layout, island }, n) or nil
    end,
    showStep = function(step)
      return showStep(step)
    end,
    relayout = function()
      view:Layout()
    end,
    share = function()
      return MRL.Encode(state.faction, MRL.Chain(state))
    end,
  }
  routeList = MRL.Attach(routeCtx)
  K.Anchor("FG.Map.Route", routeList.box)
  side.stack:Add(routeList.box)
  side.stack:Add(FL.ButtonRow(side.content, {
    {
      id = "routeWindow",
      label = "act.open",
      icon = "open",
      tooltip = "map.rb.open",
      width = 200,
      onClick = function()
        if ns.RouteBuilder then
          ns.RouteBuilder.Show()
        end
      end,
    },
  }))

  -- Map pane: tabs, island hint, canvas, toolbar, note -----------------------------------
  local silentTab = false
  local tabs = W.Tabs(leftPane, {
    tabs = { { id = "azeroth", key = "map.tab.azeroth" }, { id = "island", key = "map.tab.island" } },
    onSelect = function(id)
      state.tab = id
      if zoom then
        zoom.Reset()
        mag.Reset()
      end
      if silentTab then
        return
      end
      if ns.Store.get("settings.mapTab") ~= id then
        ns.Store.set("settings.mapTab", id)
      end
      refresh()
    end,
  })
  -- Shows a tab without remembering it as the player's choice.
  local function showTab(id)
    silentTab = true
    tabs:Select(id)
    silentTab = false
  end
  K.Anchor("FG.Map.Tabs", tabs)
  showTab(state.tab)
  local islandHint = W.Text(leftPane, { key = "map.tab.islandHint", role = "ui", color = "textSecondary", wrap = true })
  local note = W.Text(leftPane, { role = "ui", color = "textMuted", wrap = true })

  local toolbar = CreateFrame("Frame", nil, leftPane)
  local artToggle = W.Checkbox(toolbar, {
    key = "map.art.label",
    get = function()
      return state.artOn
    end,
    set = function(v)
      state.artOn = v
      zoom.Reset()
      mag.Reset()
      refresh()
    end,
  })
  artToggle:SetSize(200, 24)
  local dimToggle = W.Checkbox(toolbar, {
    key = "map.dim",
    tooltip = "map.dim",
    tooltipText = "map.dimTip",
    get = dimFiltered,
    set = function(v)
      ns.Store.set("settings.mapDimFiltered", v)
      refresh()
    end,
  })
  dimToggle:SetSize(DIM_W, 24)
  K.Anchor("FG.Map.DimToggle", dimToggle)
  -- Map image mode (Revealed / Exploration) and the banner of the data add-on.
  local reveal = RV.Attach({
    toolbar = toolbar,
    changed = function()
      refresh()
    end,
    resized = function()
      if not laying then
        view:Layout()
      end
    end,
  })
  K.Anchor("FG.Map.RevealRow", reveal.row)
  K.Anchor("FG.Map.RevealBanner", reveal.banner)

  -- True while the world map with its own node positions is shown.
  local function worldActive()
    return state.artOn and layout ~= nil
  end

  -- True while the schematic view of the new regions fills the map.
  local function islandMode()
    return state.tab == "island" and island ~= nil
  end

  -- A place that sits on the other tab switches to it, so a selection never vanishes.
  function followTab(slug)
    local n = slug and byslug[slug]
    if n and zoom and zoom.Zone() and zoom.Zone() ~= n.z then
      zoom.Reset()
    end
    local p = island and slug and layout.pos[slug]
    if p then
      local want = p.kind == "island" and "island" or "azeroth"
      if want ~= state.tab then
        showTab(want)
      end
    end
  end

  local function panelTitle()
    for _, entry in ipairs(data.continents or {}) do
      if world and world.panel[entry.s] then
        return string.format(L["map.world.island"], ns.T(entry.n) or entry.s)
      end
    end
  end

  local function noteText()
    if worldActive() then
      local st = layout.stats
      return string.format(L["map.world.note"], st.real, st.total, st.estimate, st.island)
    end
    return string.format(L["map.canvasNote"], estimated or 0, #data.nodes)
  end

  -- The viewport clips the canvas, which grows inside it while the world view is magnified. The
  -- rim is the map's frame, above the canvas, so it stays at the viewport edge.
  local viewport = CreateFrame("Frame", nil, leftPane)
  K.Anchor("FG.Map.Viewport", viewport)
  local canvas = CreateFrame("Frame", nil, viewport)
  K.Anchor("FG.Map.Canvas", canvas)
  W.Fill(canvas, "surface", 1)
  local rim = CreateFrame("Frame", nil, viewport)
  rim:SetAllPoints()
  rim:SetFrameLevel(viewport:GetFrameLevel() + 250)
  W.Border(rim, "white")
  canvas.dots, canvas.artTiles = {}, {}

  local function nodePos(n)
    local fx, fy
    local zv = zoom and zoom.View()
    if zv then
      local p = zv.pos[n.s]
      fx, fy = p and p.x, p and p.y
    elseif islandMode() then
      local p = island.pos[n.s]
      fx, fy = p and p.x, p and p.y
    elseif worldActive() then
      local p = layout.pos[n.s]
      if p and p.kind ~= "island" then
        fx, fy = p.x, p.y
      end
    else
      fx, fy = TL.CanvasFraction(data, n)
    end
    if not fx then
      return nil
    end
    return fx * canvas:GetWidth(), -fy * canvas:GetHeight()
  end

  -- The view a click on the canvas is read against: nil on the flat canvas (no zone rectangles).
  local function baseView()
    if islandMode() then
      return island
    end
    if worldActive() then
      return layout
    end
  end

  local function activeView()
    return zoom and zoom.View() or baseView()
  end

  -- The visible place of the marker's zone that lies closest to it on the current view.
  local function placeFor(wp, zone)
    local v = data and zone and activeView()
    local mx, my = MW.ZoneToPoint(v, zone, wp.x, wp.y)
    if not mx then
      return nil
    end
    local o, best, bestD = opts(), nil, nil
    for _, n in ipairs(data.nodes) do
      local p = n.z == zone and v.pos[n.s]
      if p and (v == island or p.kind ~= "island") and TL.NodeVisible(n, o) then
        local d = (p.x - mx) ^ 2 + (p.y - my) ^ 2
        if not bestD or d < bestD then
          best, bestD = n.s, d
        end
      end
    end
    return best
  end

  markers = MM.Attach({
    canvas = canvas,
    toolbar = toolbar,
    side = side,
    view = activeView,
    maps = function()
      return layout and layout.maps
    end,
    zoneName = function(slug)
      local z = zoneOf[slug]
      return z and ns.T(z.n) or nil
    end,
    placeFor = placeFor,
    setRoute = function(which, slug)
      if slug then
        state[which] = slug
        refresh()
      end
    end,
    relayout = function()
      view:Layout()
    end,
    onClick = function(button)
      -- The release that ends a drag of the magnified map is no click on the map.
      if not mag.WasDrag() then
        zoom.Click(button)
      end
    end,
    hintText = function()
      return L[MRL.NextWhich(state) == "dest" and "map.route.pickDest" or "map.route.pickStart"]
    end,
    routeModeChanged = function()
      state.pickNext = nil
    end,
  })
  canvas.markers = markers

  mag = MG.Attach({
    viewport = viewport,
    canvas = canvas,
    active = function()
      return data ~= nil and zoom ~= nil and zoom.View() == nil and worldActive() and not islandMode()
    end,
    dragAllowed = function()
      return not markers.mode and not ns.Keys.Matches("mapMarker")
    end,
    changed = function()
      view:Layout()
    end,
    moved = function()
      pins.Paint()
    end,
  })
  canvas.mag = mag

  local placesIn = {}
  zoom = MZ.Attach({
    canvas = canvas,
    over = function()
      local fx, fy = MM.CursorFraction(viewport)
      return canvas:IsMouseOver() and fx ~= nil and fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1
    end,
    base = baseView,
    data = function()
      return data
    end,
    zoneName = function(slug)
      local z = zoneOf[slug]
      return z and ns.T(z.n) or nil
    end,
    placeCount = function(slug)
      return placesIn[slug] or 0
    end,
    markerCount = function(mapId)
      local count = 0
      for _, wp in ipairs(ns.Waypoints.List()) do
        if wp.map == mapId then
          count = count + 1
        end
      end
      return count
    end,
    markers = markers,
    changed = function()
      places.Update()
      view:Layout()
    end,
  })
  canvas.zoom = zoom
  canvas:HookScript("OnHide", zoom.Reset)
  container:HookScript("OnHide", zoom.Reset)

  pins = MP.Attach({
    canvas = canvas,
    data = function()
      return data
    end,
    state = state,
    filter = function()
      local o = opts()
      return function(n)
        return TL.NodeVisible(n, o)
      end
    end,
    pos = nodePos,
    name = nodeName,
    tip = function(n)
      local factionText = (n.f == "A" and L["faction.alliance"])
        or (n.f == "H" and L["faction.horde"])
        or L["map.pin.neutral"]
      local lines = {
        string.format(L["map.place.tip"], MI.KindName(n.k), zoneLabel(n.z) or tostring(n.z)),
        Theme.hexText("textSecondary", factionText),
      }
      if n.est and zoom.View() then
        lines[#lines + 1] = Theme.hexText("textMuted", L["map.zoom.estimated"])
      end
      return table.concat(lines, "\n")
    end,
    dim = dimFiltered,
    symbols = symbolsOn,
    names = namesOn,
    scale = symbolScale,
    window = function()
      return mag.Window()
    end,
    percent = function()
      return mag.Percent()
    end,
    zoomed = function()
      return zoom.View() ~= nil
    end,
    markers = markers,
    onClick = function(slug, button)
      -- The marker key and marker mode: the click sets a marker instead of selecting the place.
      if markers.Click(button) then
        return
      end
      -- Start/Goal mode: the click sets an end of the route, nothing else changes.
      if markers.routeMode then
        if button == "LeftButton" then
          MRL.Pick(state, slug)
          refresh()
        end
        return
      end
      state.selected = slug
      followTab(slug)
      refresh()
    end,
    hover = setHover,
    unhover = unhover,
  })

  canvas.pins, canvas.places, canvas.legend = pins, places, legend

  -- Positions of a place on the current view as canvas px, y down.
  local function routePoint(slug)
    local n = byslug[slug]
    if not n then
      return nil
    end
    local x, y = nodePos(n)
    if x then
      return x, -y
    end
  end

  route = MR.Attach({
    canvas = canvas,
    point = routePoint,
    zone = function()
      return zoom.Zone()
    end,
    inZone = function(slug)
      local n = byslug[slug]
      return n ~= nil and n.z == zoom.Zone()
    end,
    -- A place of another zone as the zone's map would see it: the world position of the place
    -- inside the rectangle of the open zone, beyond the canvas when it lies outside.
    outside = function(slug)
      local base, zone = baseView(), zoom.Zone()
      local p = base and base.pos[slug]
      local r = base and zone and base.zones[zone]
      if not (p and r and r.right > r.left and r.bottom > r.top) then
        return nil
      end
      return (p.x - r.left) / (r.right - r.left) * canvas:GetWidth(),
        (p.y - r.top) / (r.bottom - r.top) * canvas:GetHeight()
    end,
    name = nodeName,
    viewKey = function()
      return table.concat({
        zoom.Zone() or "-",
        state.tab,
        tostring(worldActive()),
        tostring(islandMode()),
        tostring(layout),
        tostring(island),
      }, ":")
    end,
    picking = function()
      return markers.routeMode == true
    end,
    legTip = function(i)
      return routeList.LegTip(i)
    end,
    hoverChanged = function()
      routeList.PaintHover()
    end,
  })
  routeCtx.route = route
  canvas.route, canvas.routeList, canvas.stopsList = route, routeList, stopsList
  canvas:HookScript("OnHide", route.Release)
  container:HookScript("OnHide", route.Release)

  -- A click on a step zooms into the zone of the step (the first of its two places that has a map).
  function showStep(step)
    for _, slug in ipairs({ step.from, step.to }) do
      local n = byslug[slug]
      if n then
        followTab(slug)
        if zoom.Zone() == n.z or zoom.Enter(n.z) then
          return
        end
      end
    end
  end

  -- The explored pieces of a zone map, asked once per page visit; nil when the client has no such
  -- call (the plain tiles stay).
  local function exploredFor(mapId)
    local cached = exploredCache[mapId]
    if cached == nil then
      local list = MW.LoadExplored(mapId)
      cached = list and MW.ExploredTiles(list) or false
      exploredCache[mapId] = cached
    end
    return cached or nil
  end

  local function paintCanvas()
    if not data then
      return
    end
    local onIsland = islandMode()
    local zv = zoom.View()
    local zoomed = zv ~= nil
    local art = (worldActive() and not onIsland) and world.art or nil
    local mapId = art and world.mapID
    if zoomed then
      art, mapId = zoom.Art(), zv.mapId
    end
    local pieces, dim
    if art and mapId then
      if revealOn() then
        -- A zone map loads the data add-on, the world view only uses it when it is there already.
        pieces = (zoomed or RV.Available()) and RV.Pieces(MW.ArtId(mapId)) or nil
      elseif zoomed then
        pieces = exploredFor(mapId)
        dim = pieces ~= nil
      end
    end
    ns.Safe("map-art", paintArt, canvas, art, pieces, dim)
    ns.Safe("map-island", paintPanel, canvas, (onIsland and not zoomed) and island.panel or nil, panelTitle(), zoneOf)
    zoom.Paint()
    pins.Paint()
    markers.Paint()
    route.Paint()
  end
  ns.Bind(canvas, paintCanvas)

  -- Places the map pane top to bottom and returns the height it needs. The canvas keeps its
  -- aspect: its height is capped by the visible page height (never below MIN_CANVAS) and it
  -- gets narrower instead of distorted and sits in the middle of the pane.
  local function layoutLeft(info)
    local w = info.leftWidth
    laying = true
    local y = 0
    tabs:SetShown(island ~= nil)
    if island then
      tabs:ClearAllPoints()
      tabs:SetPoint("TOPLEFT", leftPane, "TOPLEFT")
      tabs:SetPoint("TOPRIGHT", leftPane, "TOPRIGHT")
      y = tabs:GetHeight() + GAP
    end
    local onIsland = islandMode()
    islandHint:SetShown(onIsland)
    if onIsland then
      islandHint:ClearAllPoints()
      islandHint:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -y)
      islandHint:SetWidth(w)
      y = y + math.ceil(islandHint:GetStringHeight()) + GAP
    end
    note:SetWidth(w)
    local noteH = math.ceil(note:GetStringHeight())
    -- Mode group and diagnostics share the first row. Below it (and below the hint of the
    -- Start/Goal mode) the image mode switch, the art switch and the dim switch flow side by side
    -- and wrap, then the banner of the map data comes last.
    local rowH = math.max(TOOLBAR_H, markers.modeRow:SetWidthAvailable(MM.MODE_WIDTH))
    local artShown = layout ~= nil and not onIsland
    local revealShown = artShown and state.artOn
    local zoomed = zoom.View() ~= nil
    local revealing = revealShown and revealOn()
    if revealing and zoomed then
      RV.Ensure()
    end
    local needData = revealing and RV.BannerWanted(zoomed)
    local hintH = markers.LayoutHint(w, rowH + GAP)
    local extra = hintH > 0 and hintH + GAP or 0
    local chips = {}
    if revealShown then
      local rw = math.min(RV.ROW_W, w)
      chips[#chips + 1] = { frame = reveal.row, w = rw, h = reveal.row:SetWidthAvailable(rw) }
    end
    if artShown then
      chips[#chips + 1] = { frame = artToggle, w = math.min(200, w), h = 24 }
    end
    chips[#chips + 1] = { frame = dimToggle, w = math.min(DIM_W, w), h = 24 }
    local chipsH = flowChips(chips, w)
    local bannerH = needData and reveal.banner:Update(true) and reveal.banner:Fit(w) or 0
    if not needData then
      reveal.banner:Update(false)
    end
    local toolbarH = rowH + extra + GAP + chipsH + (bannerH > 0 and GAP + bannerH or 0)
    local aspect = onIsland and island.aspect or (worldActive() and layout.aspect or 0.6)
    local natural = math.floor(w * aspect)
    local cap = math.max(MIN_CANVAS, visibleHeight() - y - GAP - toolbarH - GAP - noteH)
    local h = math.min(natural, cap)
    local cw = h < natural and math.min(w, math.floor(h / aspect)) or w
    viewport:ClearAllPoints()
    viewport:SetPoint("TOPLEFT", leftPane, "TOPLEFT", math.floor((w - cw) / 2), -y)
    viewport:SetSize(cw, h)
    mag.Place(cw, h)
    paintCanvas()
    y = y + h + GAP
    toolbar:ClearAllPoints()
    toolbar:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -y)
    toolbar:SetSize(w, toolbarH)
    markers.modeRow:ClearAllPoints()
    markers.modeRow:SetPoint("TOPLEFT", toolbar, "TOPLEFT")
    markers.modeRow:SetWidth(MM.MODE_WIDTH)
    artToggle:SetShown(artShown)
    reveal.row:SetShown(revealShown)
    local chipsTop = rowH + extra + GAP
    for _, chip in ipairs(chips) do
      chip.frame:ClearAllPoints()
      chip.frame:SetPoint("TOPLEFT", toolbar, "TOPLEFT", chip.x, -(chipsTop + chip.y))
      chip.frame:SetSize(chip.w, chip.h)
    end
    if bannerH > 0 then
      reveal.banner:ClearAllPoints()
      reveal.banner:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, -(chipsTop + chipsH + GAP))
      reveal.banner:SetWidth(w)
    end
    y = y + toolbarH + GAP
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -y)
    laying = false
    return y + noteH
  end

  function layoutPanes(info)
    -- The scroll child gets its width from the pane, the client reports it one frame late.
    sideArea.content:SetWidth(math.max(1, info.rightWidth - 12))
    -- The map first: whether the route fits on it decides a note in the side column.
    local height = layoutLeft(info)
    side.stack:Layout()
    return height
  end

  -- State -> screen ----------------------------------------------------------
  local function paintRoute()
    if not (state.start and state.dest) then
      routeList.Set(nil, nil)
      return
    end
    local chain = MRL.Chain(state)
    routeList.Set(TL.RouteVia(data, opts(), chain), table.concat(chain, ">"))
  end

  function refresh()
    if not data then
      return
    end
    local o = opts()
    for _, which in ipairs({ "start", "dest", "selected" }) do
      local n = state[which] and byslug[state[which]]
      if n and not TL.NodeVisible(n, o) then
        state[which] = nil
      end
    end
    for i = #state.stops, 1, -1 do
      local n = byslug[state.stops[i]]
      if not (n and TL.NodeVisible(n, o)) then
        table.remove(state.stops, i)
      end
    end
    places.Update()
    stopsList.Update()
    faction.Refresh()
    note:SetText(noteText())
    startText:SetText(string.format(L["map.start"], state.start and nodeName(state.start) or L["map.none"]))
    destText:SetText(string.format(L["map.dest"], state.dest and nodeName(state.dest) or L["map.none"]))
    buttons:SetItemEnabled("start", state.selected ~= nil)
    buttons:SetItemEnabled("dest", state.selected ~= nil)
    buttons:SetItemEnabled("stop", state.selected ~= nil and #state.stops < TL.MAX_STOPS)
    paintRoute()
    view:Layout()
  end

  function view:Show(params)
    local request = Request.Take()
    zoom.Reset()
    mag.Reset()
    exploredCache = {}
    reveal.Paint()
    markers.SetRouteMode(false)
    state.hover = nil
    data = ns.Data and ns.Data.Travel
    if not data then
      routeList.Message(L["kit.noData"])
      view:Layout()
      return
    end
    byslug, zoneOf, placesIn = {}, {}, {}
    for _, z in ipairs(data.zones or {}) do
      zoneOf[z.s] = z
    end
    local est = 0
    for _, n in ipairs(data.nodes) do
      byslug[n.s] = n
      placesIn[n.z] = (placesIn[n.z] or 0) + 1
      if n.est then
        est = est + 1
      end
    end
    estimated = est
    ns.TravelWalk.Ensure(data, function()
      if container:IsShown() then
        paintRoute()
      end
    end)
    local okWorld, found = ns.Safe("map-world", MW.Discover, data)
    world = okWorld and found or nil
    local okLayout, laid = ns.Safe("map-layout", MW.LayoutWorld, data, world)
    layout = okLayout and laid or nil
    local okIsland, islandView = ns.Safe("map-island-view", MW.IslandView, layout)
    island = okIsland and islandView or nil
    local slug = params and params[1]
    if slug and byslug[slug] then
      local n = byslug[slug]
      if n.f == "A" or n.f == "H" then
        state.faction = n.f
      end
      state.selected = slug
      followTab(slug)
      state.query = ns.T(n.n) or ""
      search.edit:SetText(state.query)
    end
    local zone
    if request then
      if request.query then
        state.query = request.query
        search.edit:SetText(request.query)
      end
      for _, which in ipairs({ "start", "dest" }) do
        if request[which] and byslug[request[which]] then
          state[which] = request[which]
        end
      end
      if request.start or request.dest or request.stops then
        state.stops = {}
        for _, stopSlug in ipairs(request.stops or {}) do
          if byslug[stopSlug] and #state.stops < TL.MAX_STOPS then
            state.stops[#state.stops + 1] = stopSlug
          end
        end
      end
      if request.faction == "A" or request.faction == "H" then
        state.faction = request.faction
      end
      for zoneSlug, id in pairs(layout and layout.maps or {}) do
        if id == request.map then
          zone = zoneSlug
        end
      end
    end
    refresh()
    if zone and zoom.Enter(zone) and request.x and request.y then
      zoom.Focus(request.x, request.y, request.label)
    end
    if request and request.markers then
      markers.SetMode(true)
    end
  end
  return view
end

ns.RegisterPage({
  id = "map",
  order = 110,
  group = "world",
  title = "page.map",
  icon = ns.ICONS.map,
  aliases = { "karte", "route", "map" },
  crumbLabel = function(param)
    local n = ns.DataApi.TravelNode(param)
    return n and ns.T(n.n) or param
  end,
  build = build,
})
