-- The bar on Blizzard's world map (created by WorldMapLinks.lua): collapsed it is a narrow strip
-- "Forever Guides" with an arrow, opened it has five sections as tabs. It sits at the top right of
-- the canvas, the header drags it anywhere inside the canvas and four corner buttons put it in a
-- corner. The position is a corner of the canvas plus the offset from it (settings.worldMapPanelPos),
-- the bar always unfolds towards the inside: upwards in the lower half, downwards otherwise, and
-- right aligned in the right half. Markers: set a marker (mode of
-- the map click, see WorldMapLinks) and the list of the markers of the shown map. Route: start and
-- goal from the known places, the fastest route as a short step list, and the actions of the
-- addon's map page. Route planning is the page's own logic: TravelLogic computes, MapRouteList (a
-- hidden instance) takes the route as waypoints or points the arrow at the next stop. The stops are
-- places without exact map coordinates, so no lines are drawn on Blizzard's map. Flights: the nearest flight
-- points with their distance (FlightPointList), a click sets the waypoint. Like every control of the bar it
-- stays out of the Tab ring, the keyboard route is /fg flights. Gather: the spots of ores and herbs and the
-- explored look on the map (WorldMapGatherTab.lua, built when the tab is first used). Guild: the filters and the
-- legend of the guild members on the map and the own side of sharing (WorldMapGuildTab.lua, symbol tab).
local _, ns = ...
local W, L, Theme, TL = ns.W, ns.L, ns.Theme, ns.TravelLogic
local MRL, PL, MW, MM = ns.MapRouteList, ns.MapPlaceList, ns.MapWorld, ns.MapMarkers
local FP, MI = ns.FlightPointsLogic, ns.MapIcons
local WP = ns.Waypoints
local B = ns.BlizzardLinks
local BL = ns.WorldMapBarLogic

local Bar = {}
ns.WorldMapBar = Bar

local OPEN_W, CLOSED_W, HEAD_H = 240, 150, 24
local PAD, GAP, TAB_H, ROW_H, BTN_H, ACTION_H = 8, 4, 22, 22, 24, 22
local INNER = OPEN_W - 2 * PAD
local MARGIN, TOP_RESERVE = 8, 36 -- the floor dropdown of Blizzard's map sits at the top left
local CORNER_BTN, CORNER_GAP, CHEVRON_SPACE = 14, 2, 22
local CORNER_SPAN = 4 * CORNER_BTN + 3 * CORNER_GAP
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local CORNER_OK = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local POS_KEY = "settings.worldMapPanelPos"
local STEP_H, PICK_ROWS, MAX_ROWS, MAX_STEPS = 16, 5, 8, 8
local DOT, DURATION_W, ZONE_W = 12, 44, 84
local FLIGHT_ROW_H, FLIGHT_DIST_W, FLIGHT_BADGE, FLIGHT_TEXT_X, FLIGHT_TICK = 30, 74, 14, 34, 1
local TAB_IDS = { "markers", "route", "flights", "gather", "guild" }
-- The guild tab is a symbol without text, so the four labeled tabs keep their room.
local GUILD_TAB_W = 24
local TAB_W = (INNER - GUILD_TAB_W - (#TAB_IDS - 1) * GAP) / (#TAB_IDS - 1)
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local HEXAGON = "Interface\\AddOns\\ForeverGuides\\Media\\map_hexagon.png" -- the shape of the member symbols

local function setting(key, default)
  local s = ns.db and ns.db.settings
  local v = s and s[key]
  if v == nil then
    return default
  end
  return v
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Corner glyphs of the header buttons: an angle in the corner and a dot inside, drawn on the icon grid.
local function cornerGlyph(right, bottom)
  return function(p)
    p.mirror = right
    local function rect(x, y, w, h, token)
      p:Rect(x, bottom and 12 - y - h or y, w, h, token)
    end
    rect(1, 1, 7, 2)
    rect(1, 1, 2, 7)
    rect(5, 5, 3, 3, "accent2")
  end
end
ns.IconDraw.register("fg-corner-TOPLEFT", cornerGlyph(false, false))
ns.IconDraw.register("fg-corner-TOPRIGHT", cornerGlyph(true, false))
ns.IconDraw.register("fg-corner-BOTTOMLEFT", cornerGlyph(false, true))
ns.IconDraw.register("fg-corner-BOTTOMRIGHT", cornerGlyph(true, true))
ns.IconDraw.register("fg-chevron-up", function(p)
  p:Line(2, 8, 6, 4)
  p:Line(6, 4, 10, 8)
end)

-- Buttons of the bar live on a Blizzard frame: the main window's Tab ring must not reach them.
local function button(parent, opts)
  local b = W.Button(parent, opts)
  B.LeaveFocusRing(b)
  return b
end

local function listRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(INNER, ROW_H)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = row:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0)
  row:HookScript("OnEnter", function()
    hl:SetColorTexture(1, 1, 1, 0.08)
  end)
  row:HookScript("OnLeave", function()
    hl:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  return row
end

function Bar.Create(map)
  local WML = ns.WorldMapLinks
  local f = CreateFrame("Frame", "ForeverGuidesWorldMapBar", map)
  ns.Layer.Own(f)
  WML.Lift(f)
  f:EnableMouse(true)
  W.Fill(f, "bg", 0.94)
  W.Border(f, "accentDim", 1)

  local r = { picking = nil, query = "" }
  local eng

  -- Route engine: the data, the layout of the page and a hidden MapRouteList that does the work of
  -- "take as waypoints" and "next stop". Built when the route tab is first used.
  local function engine()
    if eng then
      return eng
    end
    local data = ns.Data and ns.Data.Travel
    if not (data and data.nodes) then
      return nil
    end
    local e = { data = data, byslug = {}, zoneName = {}, zoneOfMap = {}, state = { alt = 1 } }
    for _, n in ipairs(data.nodes) do
      e.byslug[n.s] = n
    end
    for _, z in ipairs(data.zones or {}) do
      e.zoneName[z.s] = ns.T(z.n)
    end
    local okWorld, world = ns.Safe("wm-world", MW.Discover, data)
    e.world = okWorld and world or nil
    for slug, id in pairs(e.world and e.world.maps or {}) do
      e.zoneOfMap[id] = slug
    end
    if e.world then
      local okLayout, layout = ns.Safe("wm-layout", MW.LayoutWorld, data, e.world)
      e.layout = okLayout and layout or nil
    end
    if e.layout then
      local okIsland, island = ns.Safe("wm-island", MW.IslandView, e.layout)
      e.island = okIsland and island or nil
    end
    function e.nameOf(slug)
      local n = e.byslug[slug]
      return n and ns.T(n.n) or tostring(slug or "?")
    end
    local host = CreateFrame("Frame", nil, f)
    host:Hide()
    e.list = MRL.Attach({
      side = { content = host },
      state = e.state,
      nameOf = e.nameOf,
      specFor = function(slug)
        local n = e.byslug[slug]
        return n and PL.ZonePoint({ e.layout, e.island }, n) or nil
      end,
      route = {
        SetRoute = function() end,
        SetHover = function() end,
        Capped = function()
          return false
        end,
      },
      showStep = function() end,
      relayout = function() end,
    })
    eng = e
    return e
  end

  -- The options of the map page (faction, transport switches, flying, mount) when it was opened this
  -- session, the defaults otherwise; start and goal are the bar's own.
  local function options(e)
    local o = MRL.Options(ns.MapRequest and ns.MapRequest.shared or {})
    o.from, o.to = e.state.start, e.state.dest
    return o
  end

  -- Header and tabs ------------------------------------------------------------------------
  local function isOpen()
    return setting("worldMapPanelOpen", false) == true
  end

  local function currentTab()
    local id = setting("worldMapPanelTab", "markers")
    for _, tabId in ipairs(TAB_IDS) do
      if tabId == id then
        return id
      end
    end
    return "markers"
  end

  local head = button(f, {
    key = "wm.bar.title",
    variant = "ghost",
    width = CLOSED_W,
    height = HEAD_H,
    tooltip = "wm.bar.title",
    tooltipText = "wm.bar.toggleTip",
    onClick = function()
      ns.Store.set("settings.worldMapPanelOpen", not isOpen())
      f:Layout()
    end,
  })
  head.label:SetJustifyH("LEFT")
  head.logo = head:CreateTexture(nil, "ARTWORK")
  head.logo:SetTexture(LOGO)
  head.logo:SetSize(16, 16)
  head.logo:SetPoint("LEFT", 6, 0)
  head.chevron = ns.IconDraw.new(head, 12)
  head.chevron:SetPoint("RIGHT", -6, 0)

  -- Position -------------------------------------------------------------------------------------
  -- Corner of the canvas (also the side the bar is anchored on) and the offsets inwards from it.
  local function position()
    if r.drag then
      return r.drag.corner, r.drag.dx, r.drag.dy
    end
    local p = setting("worldMapPanelPos", nil)
    if type(p) == "table" and CORNER_OK[p.corner] and finite(p.dx) and finite(p.dy) then
      return p.corner, math.max(0, p.dx), math.max(0, p.dy)
    end
    return "TOPRIGHT", math.max(MARGIN, WML.RightClear() + MARGIN / 2), MARGIN
  end

  -- Anchors the bar at its corner with the offsets held inside the canvas (size from the last Layout).
  local function place()
    local corner, dx, dy = position()
    local _, mapW, mapH = WML.BarSpace()
    local right, up = corner:find("RIGHT$") ~= nil, corner:find("^BOTTOM") ~= nil
    dx = clamp(dx, 0, math.max(0, mapW - (r.w or CLOSED_W)))
    dy = clamp(dy, 0, math.max(0, mapH - (r.h or HEAD_H)))
    f:ClearAllPoints()
    f:SetPoint(corner, WML.Container(), corner, right and -dx or dx, up and dy or -dy)
  end

  local function cursor()
    local x, y = GetCursorPosition()
    local s = WML.Container():GetEffectiveScale()
    if not (finite(x) and finite(y) and finite(s) and s > 0) then
      return nil
    end
    return x / s, y / s
  end

  -- The header follows the cursor: the quadrant of its center gives the corner, hence the direction.
  local function dragUpdate()
    local c, cx, cy = WML.ContainerRect(), cursor()
    if not (c and r.grab and cx) then
      return
    end
    local w, h = c.r - c.l, c.t - c.b
    local width = f:GetWidth()
    local headL, headT = cx - r.grab.x, cy + r.grab.y
    local right = headL + width / 2 > c.l + w / 2
    local up = headT - HEAD_H / 2 < c.b + h / 2
    r.drag = {
      corner = (up and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT"),
      dx = clamp(right and c.r - (headL + width) or headL - c.l, 0, math.max(0, w - width)),
      dy = clamp(up and headT - HEAD_H - c.b or c.t - headT, 0, math.max(0, h - HEAD_H)),
    }
    if up ~= r.up then
      f:Layout()
    else
      place()
    end
  end

  local function dragStop(save)
    f:SetScript("OnUpdate", nil)
    local drag = r.drag
    r.drag, r.grab = nil, nil
    if drag and save then
      ns.Store.set(POS_KEY, { corner = drag.corner, dx = drag.dx, dy = drag.dy })
    end
    f:Layout()
  end

  head:RegisterForDrag("LeftButton")
  head:SetScript(
    "OnDragStart",
    ns.Wrap("wm-bar-drag", function()
      local hl, ht = head:GetLeft(), head:GetTop()
      local cx, cy = cursor()
      if not (finite(hl) and finite(ht) and cx) then
        return
      end
      local corner, dx, dy = position()
      r.grab = { x = cx - hl, y = ht - cy }
      r.drag = { corner = corner, dx = dx, dy = dy }
      f:SetScript("OnUpdate", ns.Wrap("wm-bar-drag", dragUpdate))
    end)
  )
  head:SetScript(
    "OnDragStop",
    ns.Wrap("wm-bar-drag", function()
      dragStop(true)
    end)
  )
  f:SetScript("OnHide", function()
    if r.drag then
      dragStop(false)
    end
  end)

  -- The four buttons in the header put the bar in a corner of the canvas.
  local function setCorner(corner)
    local lift = WML.BarSpace()
    local right, up = corner:find("RIGHT$") ~= nil, corner:find("^BOTTOM") ~= nil
    local dx = right and math.max(MARGIN, WML.RightClear() + MARGIN / 2) or MARGIN
    local dy = MARGIN
    if not right then
      dy = up and lift or TOP_RESERVE
    end
    ns.Store.set(POS_KEY, { corner = corner, dx = dx, dy = dy })
    f:Layout()
  end

  head.corners = {}
  for i, corner in ipairs(CORNERS) do
    local b = CreateFrame("Button", nil, head)
    b:SetSize(CORNER_BTN, CORNER_BTN)
    b:SetPoint("RIGHT", head, "RIGHT", -(CHEVRON_SPACE + (#CORNERS - i) * (CORNER_BTN + CORNER_GAP)), 0)
    b.icon = ns.IconDraw.new(b, 12)
    b.icon:SetPoint("CENTER")
    b.icon:Draw("fg-corner-" .. corner)
    b:SetScript("OnEnter", function(self)
      self.icon:SetTint("accent")
      ns.ShowTooltip(self, L["wm.corner." .. corner])
    end)
    b:SetScript("OnLeave", function(self)
      self.icon:SetTint("textSecondary")
      ns.HideTooltip()
    end)
    b:SetScript(
      "OnClick",
      ns.Wrap("wm-corner", function()
        setCorner(corner)
      end)
    )
    B.LeaveFocusRing(b)
    b.corner = corner
    head.corners[i] = b
  end

  local tabs = {}
  local gt, gu
  local function newTab(id, key, tooltip, tooltipText)
    local b = button(f, {
      key = key,
      variant = "ghost",
      width = TAB_W,
      height = TAB_H,
      tooltip = tooltip or key,
      tooltipText = tooltipText,
      onClick = function()
        ns.Store.set("settings.worldMapPanelTab", id)
        r.picking = nil
        f:Layout()
      end,
    })
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
    tabs[id] = b
    return b
  end
  newTab("markers", "map.marker.heading", nil, "wm.tip.tab.markers")
  newTab("route", "map.route", nil, "wm.tip.tab.route")
  newTab("flights", "fp.tab", "fp.list.title", "wm.tip.tab.flights")
  newTab("gather", "wm.gather.tab", nil, "wm.tip.tab.gather")
  do
    local b = W.Action(f, {
      texture = HEXAGON,
      variant = "ghost",
      width = GUILD_TAB_W,
      height = TAB_H,
      tooltip = "wm.guild.tab.title",
      tooltipText = "wm.guild.tab.tip",
      wrap = "button",
      onClick = function()
        ns.Store.set("settings.worldMapPanelTab", "guild")
        r.picking = nil
        f:Layout()
      end,
    })
    B.LeaveFocusRing(b)
    -- A square hexagon in the middle, not stretched over the whole tab.
    local base = b.fgPlace
    b.fgPlace = function(self)
      base(self)
      self.icon:ClearAllPoints()
      self.icon:SetPoint("CENTER")
      self.icon:SetSize(GUILD_TAB_W - 10, GUILD_TAB_W - 10)
    end
    b.fgPlace(b)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
    tabs.guild = b
  end

  -- The pages sit in one scroll area: a page taller than the room down to the edge of the map window
  -- scrolls instead of reaching over the frame. The gutter at the right holds the scroll bar.
  local scroll = W.ScrollArea(f, { gutter = PAD })
  local pageParent = scroll.content

  -- Markers --------------------------------------------------------------------------------
  local mk = CreateFrame("Frame", nil, pageParent)
  mk.rows = {}
  mk.place = button(mk, {
    key = "wm.place",
    variant = "primary",
    width = INNER,
    height = 26,
    tooltip = "wm.place",
    tooltipText = "wm.place.tip",
    onClick = function()
      WML.SetPlacing(not WML.Placing())
    end,
  })
  mk.hint = W.Text(mk, { key = "wm.place.hint", role = "micro", color = "textMuted", wrap = true })
  mk.count = W.Text(mk, { role = "micro", color = "textSecondary" })

  local function markerItems()
    local id, items = WML.MapID(), {}
    local active = WP.data().active
    for _, wp in ipairs(WP.List()) do
      if id and wp.map == id then
        items[#items + 1] = { wp = wp, active = wp.id == active }
      end
    end
    MM.SortPins(items)
    return items
  end

  local function newMarkerRow()
    local row = listRow(mk)
    row.ring = row:CreateTexture(nil, "BORDER")
    row.ring:SetTexture(DISC)
    row.ring:SetSize(DOT + 4, DOT + 4)
    row.ring:SetPoint("LEFT", 2, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(DISC)
    row.dot:SetSize(DOT, DOT)
    row.dot:SetPoint("LEFT", 6, 0)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("LEFT", row, "LEFT", DOT + 14, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    ns.Bind(row.ring, function(t)
      t:SetVertexColor(Theme.color("text"))
    end)
    row:HookScript("OnEnter", function(self)
      local wp = self.wpId and WP.Get(self.wpId)
      if wp then
        ns.ShowTooltip(
          self,
          wp.title,
          string.format(L["map.marker.pos"], ns.WaypointLogic.coordText(wp.x, wp.y))
            .. "\n"
            .. Theme.hexText("textMuted", L["map.marker.hint"])
        )
      end
    end)
    row:SetScript(
      "OnClick",
      ns.Wrap("wm-row", function(self, mouse)
        local wp = self.wpId and WP.Get(self.wpId)
        if not wp then
          return
        end
        if mouse == "RightButton" then
          WML.OpenMarkerMenu(wp, self)
        else
          WML.Activate(wp)
        end
      end)
    )
    return row
  end

  -- Returns the height of the page; avail is the room the page may use.
  local function layoutMarkers(avail)
    local items = markerItems()
    local on = WML.Placing()
    W.SetText(mk.place.label, on and "wm.place.stop" or "wm.place")
    mk.place:ClearAllPoints()
    mk.place:SetPoint("TOPLEFT", mk, "TOPLEFT", 0, 0)
    local y = mk.place:GetHeight() + GAP
    mk.hint:SetShown(on)
    if on then
      mk.hint:ClearAllPoints()
      mk.hint:SetPoint("TOPLEFT", mk, "TOPLEFT", 0, -y)
      mk.hint:SetWidth(INNER)
      y = y + math.ceil(mk.hint:GetStringHeight()) + GAP
    end
    local countH = 14
    local shown = math.min(#items, clamp(math.floor((avail - y - countH - GAP) / ROW_H), 1, MAX_ROWS))
    for i = 1, shown do
      local row = mk.rows[i]
      if not row then
        row = newMarkerRow()
        mk.rows[i] = row
      end
      local wp, active = items[i].wp, items[i].active
      row.wpId = wp.id
      row.dot:SetVertexColor(Theme.color(wp.color))
      row.ring:SetShown(active)
      W.SetText(row.name, nil, wp.title)
      W.SetColor(row.name, active and "accent2" or "text")
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", mk, "TOPLEFT", 0, -y)
      row:Show()
      y = y + ROW_H
    end
    for i = shown + 1, #mk.rows do
      mk.rows[i].wpId = nil
      mk.rows[i]:Hide()
    end
    local text = L["wm.empty"]
    if #items > 0 then
      text = #items > shown and string.format(L["wm.count.part"], #items, shown) or string.format(L["wm.count"], #items)
    end
    W.SetText(mk.count, nil, text)
    mk.count:ClearAllPoints()
    mk.count:SetPoint("TOPLEFT", mk, "TOPLEFT", 0, -(y + GAP))
    mk.count:SetWidth(INNER)
    return y + GAP + countH
  end

  -- Route ----------------------------------------------------------------------------------
  local rt = CreateFrame("Frame", nil, pageParent)
  rt.picks, rt.steps = {}, {}

  local function newEndButton(which)
    local b = button(rt, {
      text = "",
      variant = "secondary",
      width = INNER,
      height = BTN_H,
      tooltip = "wm." .. which .. ".title",
      tooltipText = "wm." .. which .. ".tip",
      onClick = function()
        r.picking = r.picking ~= which and which or nil
        r.query = ""
        if rt.search then
          rt.search.edit:SetText("")
        end
        f:Layout()
        if r.picking and rt.search then
          rt.search.edit:SetFocus()
        end
      end,
    })
    b.label:SetJustifyH("LEFT")
    return b
  end
  rt.start, rt.dest = newEndButton("start"), newEndButton("dest")

  local function calculate()
    local e = engine()
    if not e then
      return
    end
    ns.TravelWalk.Ensure(e.data, calculate)
    if e.state.start and e.state.dest then
      local result = TL.Route(e.data, options(e))
      r.status = result.status
      e.list.Set(result, e.state.start .. ">" .. e.state.dest)
    else
      r.status = nil
      e.list.Set(nil, nil)
    end
    f:Layout()
  end

  local function swap()
    local e = engine()
    if not e then
      return
    end
    e.state.start, e.state.dest = e.state.dest, e.state.start
    if e.list.result then
      calculate()
    else
      f:Layout()
    end
  end

  local function reset()
    local e = engine()
    r.picking, r.status, r.query = nil, nil, ""
    if e then
      e.state.start, e.state.dest = nil, nil
      e.list.Set(nil, nil)
    end
    f:Layout()
  end

  local HALF_W = (INNER - BTN_H - 2 * GAP) / 2
  rt.swap = button(rt, {
    key = "wm.swap",
    width = HALF_W,
    height = BTN_H,
    tooltip = "wm.swap",
    tooltipText = "wm.swap.tip",
    onClick = swap,
  })
  rt.calc = button(rt, {
    key = "wm.calc",
    variant = "primary",
    width = HALF_W,
    height = BTN_H,
    tooltip = "wm.calc",
    tooltipText = "wm.calc.tip",
    onClick = calculate,
  })
  rt.reset = W.Action(rt, {
    icon = "reset",
    boxed = true,
    size = BTN_H,
    tooltip = "map.resetRoute",
    tooltipText = "map.resetRoute.tip",
    onClick = reset,
  })
  B.LeaveFocusRing(rt.reset)

  local function choose(slug)
    local e = engine()
    if not (e and r.picking and slug) then
      return
    end
    e.state[r.picking] = slug
    r.picking, r.status = nil, nil
    e.list.Set(nil, nil)
    f:Layout()
  end

  local function pickEntries()
    local e = engine()
    if not e then
      return {}
    end
    local entries = TL.Nodes(e.data, options(e), function(n)
      return ns.T(n.n)
    end, r.query, ns.SearchLogic.match)
    return PL.Sort(entries, r.query, e.zoneOfMap[WML.MapID()])
  end

  rt.search = W.EditBox(rt, {
    placeholder = "wm.search",
    tooltip = "wm.search",
    tooltipText = "wm.search.tip",
    onChange = function(text)
      r.query = text
      f:Layout()
    end,
    onEnter = function()
      local first = pickEntries()[1]
      if first then
        choose(first.node.s)
      end
    end,
  })
  rt.search.edit:HookScript("OnEscapePressed", function()
    r.picking = nil
    f:Layout()
  end)
  rt.noPlace = W.Text(rt, { key = "wm.noPlace", role = "ui", color = "textMuted" })
  rt.msg = W.Text(rt, { role = "ui", color = "textSecondary", wrap = true })
  rt.total = W.Text(rt, { role = "ui", color = "accent2" })
  rt.more = W.Text(rt, { role = "micro", color = "textMuted" })

  local function newPickRow()
    local row = listRow(rt)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(ZONE_W + 6), 0)
    row.zone = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.zone:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.zone:SetWidth(ZONE_W)
    -- The row cuts long names: the tooltip has the whole name and the zone.
    row:HookScript("OnEnter", function(self)
      if self.pickName then
        ns.ShowTooltip(self, self.pickName, (self.pickZone ~= "" and self.pickZone .. "\n" or "") .. L["wm.pick.tip"])
      end
    end)
    row:SetScript(
      "OnClick",
      ns.Wrap("wm-pick", function(self)
        choose(self.slug)
      end)
    )
    return row
  end

  local function newStepRow()
    local row = CreateFrame("Frame", nil, rt)
    row:SetSize(INNER, STEP_H)
    row.leg = W.Text(row, { role = "micro", color = "text" })
    row.leg:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.leg:SetPoint("RIGHT", row, "RIGHT", -(DURATION_W + 4), 0)
    row.dur = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
    row.dur:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.dur:SetWidth(DURATION_W)
    return row
  end

  local function action(key, tip, handler)
    return button(rt, {
      key = key,
      width = INNER,
      height = ACTION_H,
      tooltip = key,
      tooltipText = tip,
      onClick = handler,
    })
  end
  rt.show = action("wm.route.show", "wm.route.showTip", function()
    local e = engine()
    if e and ns.MapRequest then
      ns.MapRequest.Open({
        map = WML.MapID(),
        start = e.state.start,
        dest = e.state.dest,
        faction = options(e).faction,
      })
      B.RaiseMain(map)
    end
  end)
  rt.next = action("map.route.next", "map.route.next.tip", function()
    local e = engine()
    if e then
      e.list.NextStop()
    end
  end)
  rt.adopt = action("map.route.adopt", "map.route.adopt.tip", function()
    local e = engine()
    if e then
      e.list.Adopt()
    end
  end)

  local function layoutRoute(avail)
    local e = engine()
    local st = e and e.state or {}
    local function endText(which)
      local slug = st[which]
      return string.format(L["map." .. which], slug and e.nameOf(slug) or L["map.none"])
    end
    W.SetText(rt.start.label, nil, endText("start"))
    W.SetText(rt.dest.label, nil, endText("dest"))
    local y = 0
    for _, b in ipairs({ rt.start, rt.dest }) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
      y = y + BTN_H + GAP
    end
    rt.swap:ClearAllPoints()
    rt.swap:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
    rt.calc:ClearAllPoints()
    rt.calc:SetPoint("TOPLEFT", rt, "TOPLEFT", HALF_W + GAP, -y)
    rt.reset:ClearAllPoints()
    rt.reset:SetPoint("TOPRIGHT", rt, "TOPRIGHT", 0, -y)
    rt.swap:SetEnabled(e ~= nil and (st.start ~= nil or st.dest ~= nil))
    rt.calc:SetEnabled(e ~= nil and st.start ~= nil and st.dest ~= nil)
    y = y + BTN_H + GAP + 2

    local picking = r.picking ~= nil and e ~= nil
    rt.search:SetShown(picking)
    rt.noPlace:Hide()
    rt.msg:Hide()
    rt.total:Hide()
    rt.more:Hide()
    for _, b in ipairs({ rt.show, rt.next, rt.adopt }) do
      b:Hide()
    end
    local shownSteps, shownPicks = 0, 0
    if picking then
      rt.search:ClearAllPoints()
      rt.search:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
      rt.search:SetWidth(INNER)
      y = y + rt.search:GetHeight() + GAP
      local entries = pickEntries()
      shownPicks = math.min(#entries, clamp(math.floor((avail - y) / ROW_H), 1, PICK_ROWS))
      for i = 1, shownPicks do
        local row = rt.picks[i]
        if not row then
          row = newPickRow()
          rt.picks[i] = row
        end
        row.slug = entries[i].node.s
        W.SetText(row.name, nil, entries[i].name)
        W.SetText(row.zone, nil, e.zoneName[entries[i].node.z] or "")
        row.pickName, row.pickZone = entries[i].name, e.zoneName[entries[i].node.z] or ""
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_H
      end
      if #entries == 0 then
        rt.noPlace:ClearAllPoints()
        rt.noPlace:SetPoint("TOPLEFT", rt, "TOPLEFT", 4, -y)
        rt.noPlace:Show()
        y = y + ROW_H
      end
    else
      local route = e and e.list.routes[1]
      if route then
        W.SetText(rt.total, nil, string.format(L["map.route.total"], TL.FormatDuration(route.totalSec), #route.steps))
        rt.total:ClearAllPoints()
        rt.total:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
        rt.total:SetWidth(INNER)
        rt.total:Show()
        y = y + 18
        local reserved = 14 + 3 * (ACTION_H + GAP)
        shownSteps = math.min(#route.steps, clamp(math.floor((avail - y - reserved) / STEP_H), 1, MAX_STEPS))
        for i = 1, shownSteps do
          local row = rt.steps[i]
          if not row then
            row = newStepRow()
            rt.steps[i] = row
          end
          local step = route.steps[i]
          W.SetText(row.leg, nil, string.format(L["map.route.leg"], i, e.nameOf(step.from), e.nameOf(step.to)))
          W.SetText(row.dur, nil, TL.FormatDuration(step.sec))
          row:ClearAllPoints()
          row:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
          row:Show()
          y = y + STEP_H
        end
        if #route.steps > shownSteps then
          W.SetText(rt.more, nil, string.format(L["wm.route.more"], #route.steps - shownSteps))
          rt.more:ClearAllPoints()
          rt.more:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
          rt.more:Show()
        end
        y = y + 14
        for _, b in ipairs({ rt.show, rt.next, rt.adopt }) do
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
          b:Show()
          y = y + ACTION_H + GAP
        end
      else
        local key = not e and "wm.noData"
          or r.status == "same" and "map.route.same"
          or r.status == "unreachable" and "map.route.none"
          or "map.route.pick"
        W.SetText(rt.msg, nil, L[key])
        rt.msg:ClearAllPoints()
        rt.msg:SetPoint("TOPLEFT", rt, "TOPLEFT", 0, -y)
        rt.msg:SetWidth(INNER)
        rt.msg:Show()
        y = y + math.ceil(rt.msg:GetStringHeight())
      end
    end
    for i = shownSteps + 1, #rt.steps do
      rt.steps[i]:Hide()
    end
    for i = shownPicks + 1, #rt.picks do
      rt.picks[i]:Hide()
    end
    return y
  end

  -- Flights --------------------------------------------------------------------------------
  local fl = CreateFrame("Frame", nil, pageParent)
  fl.rows = {}
  fl.msg = W.Text(fl, { role = "micro", color = "textMuted", wrap = true })

  -- Two lines: name and distance, below the name "not discovered" (text, so it does not rest on the color).
  -- A check in front marks the flight point the active waypoint is on.
  local function newFlightRow()
    local row = listRow(fl)
    row:SetHeight(FLIGHT_ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row.check = ns.IconDraw.new(row, 10)
    row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.check:Draw("check")
    row.check:SetTint("accent2")
    row.badge = MI.NewBadge(row)
    row.badge.box:SetPoint("LEFT", row, "LEFT", 16, 0)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("LEFT", row, "LEFT", FLIGHT_TEXT_X, 6)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(FLIGHT_DIST_W + 8), 6)
    row.dist = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
    row.dist:SetPoint("RIGHT", row, "RIGHT", -4, 6)
    row.dist:SetWidth(FLIGHT_DIST_W)
    row.status = W.Text(row, { key = "fp.list.unknown", role = "micro", color = "textMuted" })
    row.status:SetPoint("LEFT", row, "LEFT", FLIGHT_TEXT_X, -7)
    row:HookScript("OnEnter", function(self)
      if self.point then
        ns.ShowTooltip(self, self.point.name, FP.TooltipText(self.state, self.yards, L, self.active))
      end
    end)
    row:SetScript(
      "OnClick",
      ns.Wrap("wm-flight-row", function(self)
        if self.point then
          ns.FlightPointList.SetWaypoint(self.point)
        end
      end)
    )
    return row
  end

  -- Returns the height of the page; avail is the room the page may use.
  local function layoutFlights(avail)
    local rows, positioned = ns.FlightPointList.Rows()
    local y = 0
    local note = not positioned and "fp.list.noPosition" or #rows == 0 and "fp.list.empty" or nil
    fl.msg:SetShown(note ~= nil)
    if note then
      W.SetText(fl.msg, note)
      fl.msg:ClearAllPoints()
      fl.msg:SetPoint("TOPLEFT", fl, "TOPLEFT", 0, 0)
      fl.msg:SetWidth(INNER)
      y = math.ceil(fl.msg:GetStringHeight()) + GAP
    end
    local shown = math.min(#rows, clamp(math.floor((avail - y) / FLIGHT_ROW_H), 1, FP.COUNT_MAX))
    for i = 1, shown do
      local row = fl.rows[i]
      if not row then
        row = newFlightRow()
        fl.rows[i] = row
      end
      local d = rows[i]
      row.point, row.state, row.yards, row.active = d.point, d.state, d.yards, d.active
      row.badge:Set("flightMaster", d.point.faction, FLIGHT_BADGE, false, d.undiscovered)
      row.check:SetShown(d.active)
      W.SetText(row.name, nil, d.name)
      W.SetColor(row.name, d.active and "accent2" or d.undiscovered and "textMuted" or "text")
      W.SetText(row.dist, nil, d.distance)
      row.status:SetShown(d.undiscovered)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", fl, "TOPLEFT", 0, -y)
      row:Show()
      y = y + FLIGHT_ROW_H
    end
    for i = shown + 1, #fl.rows do
      fl.rows[i].point = nil
      fl.rows[i]:Hide()
    end
    return y
  end

  -- The distances change while the player moves: one pass a second, only while the page is on screen
  -- (the client stops OnUpdate of a hidden frame, the handler is also dropped on hide) and never in combat.
  local tick = ns.Wrap("wm-flight-tick", function(page, elapsed)
    page.acc = page.acc + elapsed
    if page.acc < FLIGHT_TICK then
      return
    end
    page.acc = 0
    if not (InCombatLockdown and InCombatLockdown()) then
      f:Layout()
    end
  end)
  fl:SetScript("OnShow", function(page)
    page.acc = 0
    page:SetScript("OnUpdate", tick)
  end)
  fl:SetScript("OnHide", function(page)
    page:SetScript("OnUpdate", nil)
  end)

  -- Gather: built when the tab is first used, so the data add-on of the materials is not touched before.
  local function gatherPage()
    if not gt then
      gt = ns.WorldMapGatherTab.Create(pageParent, INNER, {
        relayout = function()
          f:Refresh()
        end,
      })
      f.parts.gather = gt
    end
    return gt
  end

  -- Guild: built when the tab is first used.
  local function guildPage()
    if not gu then
      gu = ns.WorldMapGuildTab.Create(pageParent, INNER, {
        relayout = function()
          f:Refresh()
        end,
      })
      f.parts.guild = gu
    end
    return gu
  end

  -- Layout -------------------------------------------------------------------------------------
  -- Header at the canvas edge the bar is anchored on, content on the inner side of it.
  function f:Layout()
    WML.Lift(f)
    local lift, _, mapHeight = WML.BarSpace()
    local corner, _, dy = position()
    local up = corner:find("^BOTTOM") ~= nil
    local edge = up and "BOTTOM" or "TOP"
    local open = isOpen()
    r.up = up
    head:ClearAllPoints()
    head:SetPoint(edge .. "LEFT")
    head:SetPoint(edge .. "RIGHT")
    head.label:ClearAllPoints()
    head.label:SetPoint("LEFT", 28, 0)
    head.label:SetPoint("RIGHT", open and -(CHEVRON_SPACE + CORNER_SPAN + 4) or -CHEVRON_SPACE, 0)
    head.chevron:Draw(open and (up and "fg-chevron-up" or "chevron-down") or "chevron-right")
    for _, b in ipairs(head.corners) do
      b:SetShown(open)
    end
    -- Only the pages that are not on show are hidden. A Layout runs on every typed letter of the place search,
    -- and hiding the page that holds the focused box takes the focus away (the client clears it on hide).
    local current = open and currentTab() or nil
    local pages = { markers = mk, route = rt, flights = fl, gather = gt, guild = gu }
    for tabId, page in pairs(pages) do
      if tabId ~= current then
        page:Hide()
      end
    end
    for _, tab in pairs(tabs) do
      tab:SetShown(open)
    end
    -- Shown and hidden with the bar only: a hide on every layout would take the focus from a typed box.
    scroll:SetShown(open)
    if not open then
      r.w, r.h = CLOSED_W, HEAD_H
      f:SetSize(r.w, r.h)
      place()
      return
    end
    local top = HEAD_H + PAD
    local pageTop = top + TAB_H + PAD
    -- Content keeps clear of the overlays at the far end: the bottom ones, or the floor dropdown on top.
    local reserve = up and TOP_RESERVE or lift
    local avail = BL.Space(mapHeight, dy, MARGIN, reserve, pageTop, PAD)
    local id = currentTab()
    local x = PAD
    for _, tabId in ipairs(TAB_IDS) do
      local tab = tabs[tabId]
      tab:ClearAllPoints()
      tab:SetPoint(edge .. "LEFT", f, edge .. "LEFT", x, up and top or -top)
      tab.bar:SetShown(tabId == id)
      if tab.label then
        W.SetColor(tab.label, tabId == id and "accent" or "textSecondary")
      else
        tab.icon:SetVertexColor(Theme.color(tabId == id and "accent" or "textSecondary"))
      end
      x = x + tab:GetWidth() + GAP
    end
    local lazy = id == "gather" and gatherPage or id == "guild" and guildPage or nil
    local page = lazy and lazy() or ({ markers = mk, route = rt, flights = fl })[id]
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", pageParent, "TOPLEFT")
    local height
    if lazy then
      height = page:Layout(avail)
    else
      height = ({ markers = layoutMarkers, route = layoutRoute, flights = layoutFlights })[id](avail)
    end
    page:SetSize(INNER, height)
    page:Show()
    local view, scrolls = BL.Fit(height, avail)
    scroll:ClearAllPoints()
    scroll:SetPoint(edge .. "LEFT", f, edge .. "LEFT", PAD, up and pageTop or -pageTop)
    scroll:SetSize(INNER + PAD, view)
    pageParent:SetWidth(INNER)
    scroll:SetContentHeight(height)
    scroll:EnableMouseWheel(scrolls)
    if id ~= r.pageId then
      r.pageId = id
      scroll:ScrollTo(0)
    end
    r.w, r.h = OPEN_W, pageTop + view + PAD
    f:SetSize(r.w, r.h)
    place()
  end

  f.parts = { head = head, tabs = tabs, markers = mk, route = rt, flights = fl, scroll = scroll }

  function f:Refresh()
    if f:IsShown() then
      f:Layout()
    end
  end

  ns.On("FG_WAYPOINTS_CHANGED", function()
    f:Refresh()
  end)
  ns.On("FG_WORLDMAP_PLACING", function()
    f:Refresh()
  end)
  ns.On("FG_UI_REFRESHED", function()
    f:Refresh()
  end)
  ns.On("FG_PACKAGE_CHANGED", function()
    f:Refresh()
  end)
  return f
end
