-- Small helpers shared by the data pages (map, classes, trainers, weapons,
-- instances, search): player info, a two-line list, tour button.
local _, ns = ...
local W, Theme, L, R = ns.W, ns.Theme, ns.L, ns.RefLogic

local K = {}
ns.PageKit = K

ns.AddLocale("enUS", {
  ["kit.tourTip"] = "Shows a short tour of this page. Esc skips it.",
  ["kit.noData"] = "The data package is not loaded. Check /fg diag.",
  ["kit.empty"] = "Nothing found.",
  ["kit.gap"] = "Data gap",
  ["kit.faction.A"] = "Alliance",
  ["kit.faction.H"] = "Horde",
  ["kit.faction.all"] = "Both factions",
  ["kit.filterFaction"] = "Faction",
  ["kit.filters.active"] = "%d filters active",
  ["kit.filters.active1"] = "1 filter active",
  ["kit.filterClass"] = "Class",
  ["kit.conf.3"] = "reliable",
  ["kit.conf.2"] = "likely",
  ["kit.conf.1"] = "estimated",
  ["kit.coords"] = "Position %s (percent of zone map)",
  ["kit.view.list"] = "List",
  ["kit.view.cards"] = "Cards",
  ["kit.placeMap"] = "Map",
  ["kit.placeMapTip"] = "Shows the place on the map.",
  ["kit.placeMarker"] = "Waypoint",
  ["kit.placeMarkerTip"] = "Sets a waypoint at the place.",
  ["kit.mapSet"] = "Waypoint set for %s, world map opened.",
  ["kit.mapFallbackTitle"] = "Position",
  ["kit.mapFallbackHint"] = "Not shown on the map. Look near these coordinates in the world map.",
})

ns.AddLocale("deDE", {
  ["kit.tourTip"] = "Zeigt eine kurze Führung durch die Seite. Esc überspringt sie.",
  ["kit.noData"] = "Das Datenpaket ist nicht geladen. Prüfe /fg diag.",
  ["kit.empty"] = "Nichts gefunden.",
  ["kit.gap"] = "Datenlücke",
  ["kit.faction.A"] = "Allianz",
  ["kit.faction.H"] = "Horde",
  ["kit.faction.all"] = "Beide Fraktionen",
  ["kit.filterFaction"] = "Fraktion",
  ["kit.filters.active"] = "%d Filter aktiv",
  ["kit.filters.active1"] = "1 Filter aktiv",
  ["kit.filterClass"] = "Klasse",
  ["kit.conf.3"] = "verlässlich",
  ["kit.conf.2"] = "wahrscheinlich",
  ["kit.conf.1"] = "geschätzt",
  ["kit.coords"] = "Position %s (Prozent der Zonenkarte)",
  ["kit.view.list"] = "Liste",
  ["kit.view.cards"] = "Karten",
  ["kit.placeMap"] = "Karte",
  ["kit.placeMapTip"] = "Zeigt den Ort auf der Karte.",
  ["kit.placeMarker"] = "Wegpunkt",
  ["kit.placeMarkerTip"] = "Setzt einen Wegpunkt am Ort.",
  ["kit.mapSet"] = "Wegpunkt für %s gesetzt, Weltkarte geöffnet.",
  ["kit.mapFallbackTitle"] = "Position",
  ["kit.mapFallbackHint"] = "Nicht auf der Karte angezeigt. Suche in der Weltkarte bei diesen Koordinaten.",
})

-- "A", "H" or nil.
function K.PlayerFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- Data.Races slug of the player's race, nil when unknown. The faction is needed because
-- both Skyborne races share one UnitRace token.
function K.PlayerRaceSlug()
  if not UnitRace or not ns.CharRoster then
    return nil
  end
  local ok, name, token = pcall(UnitRace, "player")
  if not ok then
    return nil
  end
  return ns.CharRoster.RaceSlug(token, name, K.PlayerFaction())
end

function K.PlayerClass()
  local _, class = UnitClass("player")
  return class
end

function K.Coord(x, y)
  if not (x and y) then
    return nil
  end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- Marks a point on the world map for the player. Never errors: the UiMapIDs in
-- the data come from Classic, so any step can be unavailable on this client and
-- the position is then offered as copyable text instead.
-- C_SuperTrack.SetSuperTrackedUserWaypoint is not called here: whether the client allows it is checked
-- at runtime (pcall) by Modules/WaypointNav.lua behind the screen navigation switch, and /fg navprobe
-- reports what this client does.
function K.ShowOnMap(mapId, x, y, label)
  label = label or ""
  local function fallback()
    local pos = K.Coord(x, y)
    ns.Dialogs.Copy("kit.mapFallbackTitle", pos and (label .. " " .. pos) or label, "kit.mapFallbackHint")
  end
  -- Neither the pin nor Blizzard's map is touched in combat: from addon code the map's pin and quest providers
  -- would run tainted. The map page of the add-on shows the place instead; without a map the position is
  -- offered as text.
  if ns.InCombat() then
    ns.MapOps.Record("show on map: own page", mapId)
    if type(mapId) == "number" and ns.MapRequest then
      ns.MapRequest.Open({ map = mapId, x = x, y = y, label = label ~= "" and label or nil })
      return
    end
    return fallback()
  end
  local hasInfo, info = false, nil
  if mapId and C_Map and C_Map.GetMapInfo then
    hasInfo, info = pcall(C_Map.GetMapInfo, mapId)
  end
  if
    not (hasInfo and info and x and y)
    or not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates)
  then
    return fallback()
  end
  if C_Map.CanSetUserWaypointOnMap then
    local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, mapId)
    if not (okCan and can) then
      return fallback()
    end
  end
  local set = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapId, x, y))
  end)
  if not set then
    return fallback()
  end
  if OpenWorldMap then
    ns.MapOps.Record("OpenWorldMap", mapId)
    pcall(OpenWorldMap, mapId)
  elseif WorldMapFrame then
    ns.MapOps.Record("WorldMapFrame:SetMapID", mapId)
    pcall(function()
      WorldMapFrame:Show()
      if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapId)
      end
    end)
  end
  ns.Notify(string.format(L["kit.mapSet"], label), "success")
end

-- Actions of W.MapActionButtons. A place is { map = UiMapID, x, y, label, zone } (x, y optional
-- fractions of the zone map, zone only names the place in the warning) or a function returning
-- one, so a costly zone lookup only runs on click. Without a map nothing is guessed, the player
-- gets a warning naming the zone.
local function resolvePlace(place)
  if type(place) == "function" then
    place = place()
  end
  if not place then
    return nil
  end
  if not place.map then
    ns.Notify(ns.Waypoints.ErrorText("unknownZone", place.zone or place.label or "?"), "warning")
    return nil
  end
  return place
end

-- UIMapType.Dungeon: instance maps, which Blizzard's world map has no zone for.
local MAP_TYPE_DUNGEON = 4

-- True when Blizzard's world map can show the zone of `mapId`: the window exists and the map is no instance map.
local function blizzardHasZone(mapId)
  if not (rawget(_G, "OpenWorldMap") or rawget(_G, "WorldMapFrame")) then
    return false
  end
  local api = rawget(_G, "C_Map")
  if not (api and api.GetMapInfo) then
    return false
  end
  local ok, info = pcall(api.GetMapInfo, mapId)
  return ok and type(info) == "table" and info.mapType ~= nil and info.mapType ~= MAP_TYPE_DUNGEON
end
K.BlizzardHasZone = blizzardHasZone

local function openBlizzardMap(mapId)
  if rawget(_G, "OpenWorldMap") then
    ns.MapOps.Record("OpenWorldMap", mapId)
    pcall(OpenWorldMap, mapId)
  else
    ns.MapOps.Record("WorldMapFrame:SetMapID", mapId)
    pcall(function()
      WorldMapFrame:Show()
      if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapId)
      end
    end)
  end
end

-- "Map": marks the place as the focus mark (one at a time, pin on Blizzard's world map and minimap, saved per
-- character) and opens Blizzard's world map at its zone. Instance maps have no zone there, the map page of
-- the addon shows them as before. Blizzard's map is not opened in combat (docs/TAINT-AUDIT.md).
function K.PlaceOnMap(place)
  place = resolvePlace(place)
  if not place then
    return
  end
  if not blizzardHasZone(place.map) then
    ns.MapRequest.Open({ map = place.map, x = place.x, y = place.y, label = place.label })
    return
  end
  if ns.InCombat() then
    ns.CombatBlocked("worldmap")
    return
  end
  if place.x and place.y then
    ns.Waypoints.Focus({ map = place.map, x = place.x, y = place.y, title = place.label })
  end
  openBlizzardMap(place.map)
end

-- "Marker": the same focus mark without opening a map.
function K.PlaceMarker(place)
  place = resolvePlace(place)
  if place then
    ns.Waypoints.Command({ map = place.map, x = place.x, y = place.y, title = place.label }, { focus = true })
  end
end

-- Hover frame of a list row: a faint background and a border inside the row, lit while the pointer
-- is over the row or one of opts.extraFrames (its buttons), so moving onto a button keeps it lit.
-- Hooks the scripts, an OnEnter tooltip of the row keeps working. opts.isActive() (default: always)
-- tells whether the row hovers at all; call row.paintHover() after rebinding a row.
function K.RowHover(row, opts)
  opts = opts or {}
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(ns.Theme.fillColor())
  row.border = W.Border(row, "accentDim", 1, 1)
  row.border.show(false)
  local function paintHover()
    local on = (not opts.isActive or opts.isActive()) and row:IsMouseOver() == true
    row.bg:SetColorTexture(Theme.fillColor(on and "hover" or nil))
    row.border.show(on)
  end
  row:HookScript("OnEnter", paintHover)
  row:HookScript("OnLeave", paintHover)
  for _, f in ipairs(opts.extraFrames or {}) do
    f:HookScript("OnEnter", paintHover)
    f:HookScript("OnLeave", paintHover)
  end
  row.paintHover = paintHover
  return paintHover
end

function K.HasData(name)
  return ns.Data and ns.Data[name] ~= nil
end

function K.Anchor(name, frame)
  ns.Anchors[name] = frame
  return frame
end

local ACTION_SIZE = 20
local CURSOR_WIDTH = 3

-- Title of a list row with highlighted spans (byte ranges { from, to } of the title): accent
-- color plus a one pixel underline, so the hit never relies on color alone.
local function paintTitle(row, text, spans, hex)
  row.marks = row.marks or {}
  for _, m in ipairs(row.marks) do
    m:Hide()
  end
  -- hex ("rrggbb"): color of the plain parts of the title, e.g. the quality color of an item name.
  local function tint(part)
    return hex and part ~= "" and ("|cff" .. hex .. part .. "|r") or part
  end
  if not spans or #spans == 0 then
    row.title:SetText(tint(text))
    return
  end
  local parts, at = {}, 1
  for _, r in ipairs(spans) do
    parts[#parts + 1] = tint(text:sub(at, r.from - 1))
    parts[#parts + 1] = Theme.hexText("accent2", text:sub(r.from, r.to))
    at = r.to + 1
  end
  parts[#parts + 1] = tint(text:sub(at))
  row.title:SetText(table.concat(parts))
  if not row.measure then
    row.measure = W.Text(row, { role = "ui" })
    row.measure:Hide()
  end
  local room, height = row.title:GetWidth() or 0, row.title:GetStringHeight()
  for i, r in ipairs(spans) do
    row.measure:SetText(text:sub(1, r.from - 1))
    local x = row.measure:GetStringWidth()
    row.measure:SetText(text:sub(r.from, r.to))
    local w = row.measure:GetStringWidth()
    if room > 0 then
      w = math.min(w, room - x)
    end
    if w > 0 then
      local mark = row.marks[i]
      if not mark then
        mark = row:CreateTexture(nil, "OVERLAY")
        ns.Bind(mark, function(t)
          t:SetColorTexture(Theme.color("accent2"))
        end)
        row.marks[i] = mark
      end
      mark:ClearAllPoints()
      mark:SetPoint("TOPLEFT", row.title, "TOPLEFT", x, -height)
      mark:SetSize(w, 1)
      mark:Show()
    end
  end
end

-- Bar at the left edge of the row that has the keyboard cursor (a second cue besides the tint).
local function paintCursor(row, on)
  if not row.cursor then
    if not on then
      return
    end
    row.cursor = row:CreateTexture(nil, "OVERLAY")
    row.cursor:SetPoint("TOPLEFT")
    row.cursor:SetPoint("BOTTOMLEFT")
    row.cursor:SetWidth(CURSOR_WIDTH)
    ns.Bind(row.cursor, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
  end
  row.cursor:SetShown(on)
end

local function scaledHeight(base)
  return Theme.lineHeight(base)
end
K.scaledHeight = scaledHeight

-- Boxed look of K.NewList (opts.look = "boxed"): the row is a box inset by BOX_INSET with a one pixel edge.
local BOX_INSET, BOX_PAD, BAR_WIDTH = 2, 8, 3
local META_SHARE, META_LINES = 0.35, 2
local TITLE_MIN = 80

-- Four textures along the inside of the box; e.color(r, g, b, a), e.show(on).
local function boxEdges(row, size)
  local e, i = {}, BOX_INSET
  local function edge(p1, x1, y1, p2, x2, y2, horizontal)
    local t = row:CreateTexture(nil, "OVERLAY")
    t:SetPoint(p1, x1, y1)
    t:SetPoint(p2, x2, y2)
    if horizontal then
      t:SetHeight(size)
    else
      t:SetWidth(size)
    end
    e[#e + 1] = t
  end
  edge("TOPLEFT", i, -i, "TOPRIGHT", -i, -i, true)
  edge("BOTTOMLEFT", i, i, "BOTTOMRIGHT", -i, i, true)
  edge("TOPLEFT", i, -i, "BOTTOMLEFT", i, i, false)
  edge("TOPRIGHT", -i, -i, "BOTTOMRIGHT", -i, i, false)
  function e.color(r, g, b, a)
    for _, t in ipairs(e) do
      t:SetColorTexture(r, g, b, a)
    end
  end
  function e.show(on)
    for _, t in ipairs(e) do
      t:SetShown(on)
    end
  end
  return e
end

-- Chrome and extra regions of one boxed row (created with the row).
local function createBoxed(row)
  row.bg:ClearAllPoints()
  row.bg:SetPoint("TOPLEFT", BOX_INSET, -BOX_INSET)
  row.bg:SetPoint("BOTTOMRIGHT", -BOX_INSET, BOX_INSET)
  row.edge = boxEdges(row, 1)
  row.ring = boxEdges(row, 2)
  row.ring.show(false)
  row.leftBar = row:CreateTexture(nil, "OVERLAY")
  row.leftBar:SetPoint("TOPLEFT", BOX_INSET, -BOX_INSET)
  row.leftBar:SetPoint("BOTTOMLEFT", BOX_INSET, BOX_INSET)
  row.leftBar:SetWidth(BAR_WIDTH)
  row.leftBar:Hide()
  row.meta = W.Text(row, { role = "small", color = "textMuted", justify = "RIGHT" })
  if row.meta.SetWordWrap then
    row.meta:SetWordWrap(true)
  end
  if row.meta.SetMaxLines then
    row.meta:SetMaxLines(META_LINES)
  end
  row.chevron = W.Glyph(row, "chevron-right", 14, "textMuted")
  row.chevron:Hide()
  row.right:Hide()
  row.fgOnFocus = function()
    row.focused = true
    row.paint()
  end
  row.fgOnBlur = function()
    row.focused = false
    row.paint()
  end
end

-- Paints the state of a boxed row: fill, edge, focus ring, left bar, meta color.
local function paintBoxed(row)
  local hover = row.hover and not row.fgInert
  row.bg:SetColorTexture(Theme.fillColor(row.selected and "selectedStrong" or (hover and "hover" or "rowRest")))
  if row.selected then
    row.edge.color(Theme.color("selected"))
  elseif hover then
    row.edge.color(Theme.color("accentDim"))
  else
    local r, g, b = Theme.rgb("lineStrong")
    row.edge.color(r, g, b, Theme.highContrast() and 1 or Theme.fillAlpha.lineStrong)
  end
  row.ring.color(Theme.color("accent2"))
  row.ring.show(row.focused == true)
  row.line:Hide()
  local bx = row.bx or {}
  if bx.leftBar then
    row.leftBar:SetColorTexture(Theme.color(bx.leftBar))
  end
  W.SetColor(row.meta, Theme.readable(Theme.hex(bx.metaColor or "textMuted"), Theme.hex("surface2")))
end

-- Bind-time pieces made on first use.
local function boxedPart(row, name, make)
  local part = row[name]
  if not part then
    part = make()
    row[name] = part
  end
  return part
end

-- Lays out a boxed row from its last bind (row.bx). From the left: level tag, framed icon, dot, then the title
-- block; from the right: chevron, trailing widget, actions, badge, meta. The title takes what is left, so
-- nothing overlaps at any width or text size.
local function layoutBoxed(row)
  local t = row.bx
  if not t then
    return
  end
  local width = row:GetWidth() or 0
  if width <= 0 then
    local parent = row:GetParent()
    width = math.max(0, (parent and parent:GetWidth() or 0) - 10)
  end
  local left = BOX_INSET + (t.leftBar and BAR_WIDTH or 0) + BOX_PAD
  local function place(frame, w)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", row, "LEFT", left, 0)
    left = left + w + BOX_PAD - 2
  end
  if row.levelTag then
    row.levelTag:SetShown(t.level ~= nil)
  end
  if t.level ~= nil then
    local tag = row.levelTag
    tag:SetTag({ text = type(t.level) == "number" and ("L" .. t.level) or tostring(t.level), color = t.levelColor })
    place(tag, tag:Fit())
  end
  if row.iconFrame then
    row.iconFrame:SetShown(t.iconFrame ~= nil and t.iconFrame ~= false)
  end
  if t.iconFrame then
    place(row.iconFrame, row.iconFrame.size)
  elseif row.icon:IsShown() then
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", left, 0)
    left = left + 20 + BOX_PAD - 2
  end
  if row.dot then
    row.dot:SetShown(t.dot ~= nil)
  end
  if t.dot then
    place(row.dot, 10)
  end

  local right = BOX_INSET + BOX_PAD
  local function stack(frame, w)
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    right = right + w + BOX_PAD - 2
  end
  row.chevron:SetShown(t.chevron == true)
  if t.chevron then
    stack(row.chevron, 14)
  end
  if row.trailing then
    stack(row.trailing, row.trailing:GetWidth() or 0)
  end
  local shown = 0
  for _, b in ipairs(row.actions) do
    if b:IsShown() then
      shown = shown + 1
    end
  end
  if shown > 0 then
    row.actions[1]:ClearAllPoints()
    row.actions[1]:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    right = right + shown * (ACTION_SIZE + 4) + BOX_PAD - 6
  end
  if t.badge then
    stack(row.badge, row.badge:GetWidth() or 0)
  end

  local text = t.meta or t.right
  row.meta:SetText(text or "")
  row.meta:SetShown(text ~= nil and text ~= "")
  if row.meta:IsShown() then
    local room = math.max(0, width - left - right - TITLE_MIN)
    row.meta:SetWidth(math.max(40, math.min(math.floor(width * META_SHARE), room)))
    row.meta:SetHeight(META_LINES * Theme.lineHeight(14, "small"))
    row.meta:ClearAllPoints()
    row.meta:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    right = right + row.meta:GetWidth() + BOX_PAD
  end

  local tagsShown = row.tagRow ~= nil and t.tags ~= nil
  if row.tagRow then
    row.tagRow:SetShown(tagsShown)
  end
  row.title:ClearAllPoints()
  row.sub:ClearAllPoints()
  local hasSub = tagsShown or (t.sub or "") ~= ""
  if hasSub then
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -(BOX_INSET + 4))
  else
    row.title:SetPoint("LEFT", row, "LEFT", left, 0)
  end
  row.title:SetPoint("RIGHT", row, "RIGHT", -right, 0)
  row.sub:SetShown(not tagsShown)
  if hasSub and not tagsShown then
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -right, 0)
  end
  if tagsShown then
    row.tagRow:ClearAllPoints()
    row.tagRow:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.tagRow:fgLayout(math.max(TITLE_MIN, width - left - right))
  end
end

-- Binds the boxed fields of one row (level, iconFrame, dot, tags) before it is laid out.
local function bindBoxed(row, t)
  row.bx, row.trailing = t, t.trailing
  if t.level ~= nil then
    boxedPart(row, "levelTag", function()
      return K.Tag(row)
    end)
  end
  if t.iconFrame then
    local spec = type(t.iconFrame) == "table" and t.iconFrame or {}
    local frame = boxedPart(row, "iconFrame", function()
      return K.IconFrame(row, { size = spec.size or Theme.size.iconFrame.md, shape = spec.shape })
    end)
    local size = spec.size or ((t.sub or t.tags) and Theme.size.iconFrame.md or Theme.size.iconFrame.sm)
    if frame.size ~= size then
      frame:Resize(size)
    end
    if spec.spec then
      frame:SetSpec(spec.spec)
    else
      frame:SetTexture(spec.texture or t.icon)
    end
    frame:SetEdge(spec.edge)
    frame:SetDesaturated(spec.desaturate == true)
    row.icon:Hide()
  end
  if t.dot then
    local dot = boxedPart(row, "dot", function()
      local d = K.StatusDot(row, {})
      -- The dot has a tooltip of its own and must not swallow the row's hover and click.
      if d.SetPropagateMouseClicks then
        d:SetPropagateMouseClicks(true)
      end
      if d.SetPropagateMouseMotion then
        d:SetPropagateMouseMotion(true)
      end
      return d
    end)
    local spec = type(t.dot) == "table" and t.dot or { state = t.dot }
    dot:SetState(spec.state, spec.tip or spec.word, spec.shape)
  end
  if t.tags then
    local tagRow = boxedPart(row, "tagRow", function()
      return K.TagRow(row)
    end)
    local list = {}
    for i = 1, math.min(3, #t.tags) do
      list[i] = t.tags[i]
    end
    tagRow:SetTags(list)
  end
  row.leftBar:SetShown(t.leftBar ~= nil)
  layoutBoxed(row)
end

-- Virtual two-line list. opts: rowHeight, subRole (font role of the second line, default small),
-- bind(item) -> { title, sub, right,
-- selected, icon, iconPaint, wrapSub, actions, tooltip }, onClick(item).
-- tooltip: literal string shown while the row is hovered. tooltipSpec: a W.Tooltip spec instead
-- (link = "item:ID" shows the client's item tooltip, title is the fallback while it is not cached; such a
-- row also takes Shift+click, chat link, and Ctrl+click, preview, see ns.ItemActions).
-- marks: byte ranges { from, to } of the title to highlight (accent color and underline).
-- titleHex: "rrggbb" color of the title text (an item name in its quality color).
-- cursor: bar at the left edge for the row of the keyboard cursor. inert: the row is a heading,
-- not clickable and skipped by Tab.
-- icon: full texture path, shown ~20x20 at the row's left with the default
-- icon crop, white tint. iconPaint(texture): for icons that need a custom
-- crop/tint (e.g. the class-circle icon), paints the row's icon texture
-- directly instead, takes precedence over icon when both are set. Neither
-- field reserves left space when absent, so rows without an icon look and
-- lay out exactly as before. wrapSub: word-wraps the sub line for callers
-- whose text can span multiple lines (row height still comes from
-- rowHeight and does not grow, so very long sub text is truncated).
-- actions: up to 4 small icon buttons (W.Action, 20 px) bottom-right of the row (icon: a texture path
-- or the name of an icon of ns.UI_ICONS), each
-- { icon = texture, tooltip = literal string, onClick = fn }; clicking one
-- does not also trigger the row's own onClick (child button consumes the
-- click). Absent/empty reserves no space, same discipline as icon above.
-- An action may also carry boxed (surface and edge, reads as a button), selected (a toggle that
-- is on), opens (the action opens a window of its own: "Opens a new window" joins the tooltip),
-- tooltipText (second tooltip line) and dim (dimmed and inert, the tooltip says
-- why; it stays focusable so the keyboard user can read the reason).
-- badge: { text, color = Theme token } a small framed label at the top right instead of `right`
-- (text and frame carry the same token, the text names the state so color is never the only cue).
-- onRightClick(item, row): optional context menu of a row (registers the right button).
-- onReorder(item, anchor, after) / canReorder(): drag and drop, see W.ScrollList.
-- onBindRow(row, item): runs after every bind, for owners that wire the pooled row further (item actions).
-- opts.look = "boxed" (default) or "flat" (the plain two-line row above, for dense utility lists).
-- Boxed: every row is a box inset 2 px with a 1 px edge
-- (gold edge and fill while selected, hover fill, accent2 focus ring), default rowHeight Theme.size.rowBoxed
-- (52 for rows with tags). Extra bind fields, boxed only:
-- meta (right text, wraps to 2 lines and reserves them; right is used when meta is nil), metaColor (token),
-- iconFrame (true or { size, edge, shape, desaturate, texture, spec }: a K.IconFrame fed by icon),
-- leftBar (token or "#rrggbb": 3 px bar at the left edge), dot ({ state, tip } or a state: K.StatusDot before the
-- title), tags (up to 3 K.Tag opts on the second line instead of sub), level (number or text: "L10" tag at the
-- left, levelColor token), chevron (true), trailing (a widget of the owner, such as a W.MapActionButtons bar with
-- its share slot: the row anchors it at the right edge and keeps the actions and meta left of it; onBindRow may
-- also set row.trailing, the row is laid out again after it).
function K.NewList(parent, opts)
  local boxed = opts.look ~= "flat"
  return W.ScrollList(parent, {
    rowHeight = scaledHeight(opts.rowHeight or (boxed and Theme.size.rowBoxed or 40)),
    onReorder = opts.onReorder,
    canReorder = opts.canReorder,
    createRow = function(p)
      local row = CreateFrame("Button", nil, p)
      -- Sibling frames don't clip each other in WoW, only a frame clips its
      -- own children. Without this, a row whose wrapSub text runs to more
      -- lines than rowHeight allows bleeds visually into the row below it
      -- instead of just being cropped at its own bottom edge.
      row:SetClipsChildren(true)
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      row.right = W.Meta(row, { justify = "RIGHT" })
      row.right:SetPoint("TOPRIGHT", -8, -6)
      row.badge = CreateFrame("Frame", nil, row)
      row.badge:SetPoint("TOPRIGHT", -8, -5)
      row.badge.tint = row.badge:CreateTexture(nil, "BACKGROUND")
      row.badge.tint:SetAllPoints()
      row.badge.ring = W.Border(row.badge, "accent2", 0.9, 1)
      row.badge.text = W.Text(row.badge, { role = "small", color = "accent2", justify = "CENTER" })
      row.badge.text:SetPoint("CENTER")
      ns.Bind(row.badge, function(b)
        local r, g, bl = Theme.rgb(b.color or "accent2")
        b.tint:SetColorTexture(r, g, bl, 0.16)
      end)
      row.badge:Hide()
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(20, 20)
      row.icon:SetPoint("TOPLEFT", 8, -8)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.icon:Hide()
      row.title = W.Text(row, { role = "ui" })
      row.title:SetPoint("TOPLEFT", 8, -5)
      row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
      row.sub = W.Text(row, { role = opts.subRole or "small", color = "textSecondary" })
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
      -- opts.vendorLinks: bind fields titleNpc / subNpc turn the title or the sub text into a link to that vendor.
      if opts.vendorLinks then
        row.titleLink = ns.VendorsPage.Link(row, row.title)
        row.subLink = ns.VendorsPage.Link(row, row.sub)
      end
      row.actions = {}
      if boxed then
        createBoxed(row)
        row:HookScript("OnSizeChanged", function()
          layoutBoxed(row)
        end)
      end
      local prevAction
      for i = 1, 4 do
        -- A pooled W.Action: the icon, variant and tooltip change with every bind.
        local b = W.Action(row, { icon = "close", variant = "icon", size = ACTION_SIZE, manual = true })
        if prevAction then
          b:SetPoint("RIGHT", prevAction, "LEFT", -4, 0)
        else
          b:SetPoint("BOTTOMRIGHT", -6, 4)
        end
        -- A raw texture (item or spell icon) instead of an icon of the set.
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 3, -3)
        b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.tex:Hide()
        local function showTip()
          if b.tip then
            ns.ShowTooltip(b, b.tip, b.tipText, b.opens and { hint = L["action.opensWindow"] } or nil)
          end
        end
        b.fgName = function()
          return b.tip
        end
        b.fgDescription = function()
          return b.opens and L["action.opensWindow"] or nil
        end
        b:HookScript("OnEnter", showTip)
        b:HookScript("OnLeave", ns.HideTooltip)
        b.fgOnFocus, b.fgOnBlur = showTip, ns.HideTooltip
        b:SetScript(
          "OnClick",
          ns.Wrap("list-row-action", function()
            if b.fn then
              b.fn()
            end
          end)
        )
        b:Hide()
        row.actions[i] = b
        prevAction = b
      end
      row.line = row:CreateTexture(nil, "ARTWORK")
      row.line:SetPoint("BOTTOMLEFT")
      row.line:SetPoint("BOTTOMRIGHT")
      row.line:SetHeight(1)
      -- A progress bar along the bottom edge (bind field bar = 0 to 1), for rows that stand for a standing.
      row.barTrack = row:CreateTexture(nil, "ARTWORK")
      row.barTrack:SetPoint("BOTTOMLEFT", 8, 6)
      row.barTrack:SetPoint("BOTTOMRIGHT", -8, 6)
      row.barTrack:SetHeight(3)
      row.barFill = row:CreateTexture(nil, "OVERLAY")
      row.barFill:SetPoint("BOTTOMLEFT", 8, 6)
      row.barFill:SetHeight(3)
      row.barTrack:Hide()
      row.barFill:Hide()
      local function paintBar()
        local value = row.barValue
        row.barTrack:SetShown(value ~= nil)
        row.barFill:SetShown(value ~= nil and value > 0)
        if value then
          row.barFill:SetWidth(math.max(1, (row:GetWidth() - 16) * value))
        end
      end
      row.paintBar = paintBar
      row:HookScript("OnSizeChanged", paintBar)
      local function paint()
        local selected = row.selected
        row.barTrack:SetColorTexture(Theme.fillColor("lineStrong"))
        row.barFill:SetColorTexture(Theme.color("accent2"))
        if boxed then
          paintBoxed(row)
          return
        end
        row.bg:SetColorTexture(Theme.fillColor(selected and "selected" or (row.hover and "hover" or nil)))
        row.line:SetColorTexture(Theme.fillColor("line"))
      end
      row.paint = paint
      ns.Bind(row, paint)
      -- tipSpec (a W.Tooltip spec, e.g. an item link) wins over the plain tip string.
      local function showTip()
        if row.tipSpec then
          local spec = row.tipSpec
          -- An item row names its Ctrl+click gesture.
          if spec.link and ns.ItemActions and ns.ItemActions.CanPreview(spec.link) then
            local hint = ns.L["itemaction.preview"]
            spec = setmetatable({ hint = spec.hint and (spec.hint .. "\n" .. hint) or hint }, { __index = spec })
          end
          W.Tooltip.Show(row, spec)
        elseif row.tip then
          ns.ShowTooltip(row, row.tip)
        end
      end
      row:SetScript("OnEnter", function()
        row.hover = true
        paint()
        showTip()
      end)
      row:SetScript("OnLeave", function()
        row.hover = false
        paint()
        if row.tip or row.tipSpec then
          ns.HideTooltip()
        end
      end)
      row:SetScript(
        "OnClick",
        ns.Wrap("list-row", function(_, button)
          if button == "RightButton" then
            if opts.onRightClick and row.item then
              opts.onRightClick(row.item, row)
            end
            return
          end
          -- A row with an item tooltip takes Shift+click (chat link) and Ctrl+click (preview) like the game.
          local spec = row.tipSpec
          if spec and spec.link and ns.ItemActions and ns.ItemActions.Click(spec.link, button) then
            return
          end
          if opts.onClick and row.item and not row.fgDragged then
            opts.onClick(row.item)
          end
        end)
      )
      if opts.onRightClick then
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      end
      ns.Focus.register(row, function(self)
        self:Click()
      end)
      row.fgName = function()
        return row.title:GetText()
      end
      return row
    end,
    bindRow = function(row, item)
      local t = opts.bind(item)
      row.item = item
      if row.titleLink then
        local vs = ns.VendorSource
        row.titleLink:SetNpc(vs and t.titleNpc and vs.Known(t.titleNpc) or nil)
        row.subLink:SetNpc(vs and t.subNpc and vs.Known(t.subNpc) or nil)
      end
      row.tip, row.tipSpec = t.tooltip, t.tooltipSpec
      row.selected = t.selected
      row.barValue = t.bar and math.max(0, math.min(1, t.bar)) or nil
      row.paintBar()
      if t.iconPaint then
        t.iconPaint(row.icon)
        row.icon:Show()
      elseif t.icon then
        row.icon:SetTexture(t.icon)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetVertexColor(1, 1, 1)
        row.icon:Show()
      else
        row.icon:Hide()
      end
      row.title:ClearAllPoints()
      row.title:SetPoint("TOPLEFT", (t.iconPaint or t.icon) and 36 or 8, -5)
      local badge = t.badge
      if badge then
        local b = row.badge
        b.color = badge.color or "accent2"
        b.ring.set(b.color, 0.9)
        W.SetColor(b.text, b.color)
        b.text:SetText(badge.text or "")
        b:SetSize(math.ceil(b.text:GetStringWidth()) + 12, math.ceil(b.text:GetStringHeight()) + 4)
        local r, g, bl = Theme.rgb(b.color)
        b.tint:SetColorTexture(r, g, bl, 0.16)
        b:Show()
      else
        row.badge:Hide()
      end
      row.title:SetPoint("RIGHT", badge and row.badge or row.right, "LEFT", -8, 0)
      local actions = t.actions or {}
      local shown, reserve = 0, 4
      for i, b in ipairs(row.actions) do
        local a = actions[i]
        if a then
          local size = ACTION_SIZE
          b:SetVariant(a.boxed and "boxed" or "icon")
          b:SetSelected(a.selected)
          if a.icon and ns.UI_ICONS[a.icon] then
            b.tex:Hide()
            b.icon:Show()
            b:SetIcon(a.icon)
          else
            b.icon:Hide()
            b.tex:SetTexture(a.icon)
            b.tex:Show()
          end
          b:SetSize(size, size)
          b:SetAlpha(a.dim and 0.45 or 1)
          b.tip, b.tipText, b.opens = a.tooltip, a.tooltipText, a.opens
          b.fn = not a.dim and a.onClick or nil
          b:Show()
          shown = shown + 1
          reserve = reserve + size + 4
        else
          b:Hide()
          b.tip, b.tipText, b.opens, b.fn = nil, nil, nil, nil
        end
      end
      row.sub:ClearAllPoints()
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
      row.sub:SetPoint("RIGHT", -8 - (shown > 0 and reserve or 0), 0)
      if row.sub.SetWordWrap then
        row.sub:SetWordWrap(t.wrapSub == true)
      end
      paintTitle(row, t.title or "", t.marks, t.titleHex)
      paintCursor(row, t.cursor == true)
      if (row.fgInert == true) ~= (t.inert == true) then
        row.fgInert = t.inert == true
        row:SetEnabled(not row.fgInert)
      end
      row.sub:SetText(t.sub or "")
      row.right:SetText(t.right or "")
      if boxed then
        bindBoxed(row, t)
      end
      row.paint()
      if opts.onBindRow then
        opts.onBindRow(row, item)
        if boxed then
          layoutBoxed(row)
        end
      end
    end,
  })
end

-- Small List/Cards view toggle shared by pages that offer both a compact
-- K.NewList and a K.GridPool card grid for the same data. opts: get() ->
-- "list"|"cards", set(view). Same segment look as W.Tabs: the chosen view has
-- a gold edge, gold tint and bright text. Other two-way switches
-- pass views = { a, b } and keyPrefix (label key = keyPrefix .. view).
function K.ViewToggle(parent, opts)
  local gap = Theme.space.xs
  local width = 76
  local views = opts.views or { "list", "cards" }
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize((width + gap) * #views - gap, 28)
  local buttons, byView = {}, {}
  local prev
  for _, view in ipairs(views) do
    local btn = W.Button(f, {
      key = (opts.keyPrefix or "kit.view.") .. view,
      variant = "tab",
      width = width,
      height = 28,
      onClick = function()
        opts.set(view)
      end,
    })
    btn:SetPoint("LEFT", prev or f, prev and "RIGHT" or "LEFT", prev and gap or 0, 0)
    byView[view] = btn
    buttons[#buttons + 1] = btn
    prev = btn
  end
  -- A label wider than the button (large font, German words) widens it.
  local function fit()
    local total = 0
    for _, btn in ipairs(buttons) do
      local w = math.max(width, math.ceil(btn.label:GetStringWidth()) + 16)
      btn:SetWidth(w)
      total = total + w
    end
    f:SetWidth(total + gap * (#buttons - 1))
  end
  function f.Refresh()
    fit()
    local current = opts.get()
    for view, btn in pairs(byView) do
      btn:SetSelected(view == current)
    end
  end
  f.Refresh()
  return f
end

-- Choice buttons ---------------------------------------------------------------
-- One look for every class, race and faction choice in the addon: compact
-- buttons that keep their content width and wrap into rows (never stretch).
-- Content is a check slot, the icon and the name. The selected button carries a
-- colored 2 px border, the check mark and a light tint of the same color, so the
-- state never relies on color alone. Hover and keyboard focus (ns.Focus) as for
-- every other button. Builders: K.ChoiceButton (one button), K.ChoiceGroup (a
-- wrapping row of them) and on top of it K.ClassButtons, K.FactionButtons,
-- K.RaceButtons and the combined K.FactionRaceSelector.

-- Faction crest icons. The names are taken from the website's own faction
-- icon assets and are not verified in this client yet, spot-check in game.
K.FACTION_CREST = {
  A = "Interface\\Icons\\INV_Misc_Tournaments_symbol_human",
  H = "Interface\\Icons\\INV_Misc_Tournaments_symbol_orc",
}

K.SKYBORNE_ICON = "Interface\\AddOns\\ForeverGuides\\Media\\race_skyborne.png"
K.CLASS_ICON_SHEET = "Interface\\TargetingFrame\\UI-Classes-Circles"
K.RACE_ICON_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"

-- Race slug (Data.Races, WeaponRaces, RaceClasses) to its icon source:
-- atlas = name part of the client atlas "raceicon-<atlas>-<gender>" (see
-- GetRaceAtlas in the client's SharedUtils), sheet = row key of the
-- UI-CharacterCreate-Races texture sheet, file = icon shipped with the addon.
-- The two Skyborne races are new in Forever and have no race icon in any
-- classic or retail asset, they share the icon of the website (Media folder).
K.RACE_ICONS = {
  ["human"] = { atlas = "human", sheet = "HUMAN" },
  ["dwarf"] = { atlas = "dwarf", sheet = "DWARF" },
  ["night-elf"] = { atlas = "nightelf", sheet = "NIGHTELF" },
  ["gnome"] = { atlas = "gnome", sheet = "GNOME" },
  ["orc"] = { atlas = "orc", sheet = "ORC" },
  ["undead"] = { atlas = "undead", sheet = "SCOURGE" },
  ["tauren"] = { atlas = "tauren", sheet = "TAUREN" },
  ["troll"] = { atlas = "troll", sheet = "TROLL" },
  ["high-order-skyborne"] = { file = K.SKYBORNE_ICON },
  ["windshaper-skyborne"] = { file = K.SKYBORNE_ICON },
}

-- Standard 4x4 layout of the race sheet: male in the left half, female in the
-- right half, four races per column.
local RACE_SHEET_COORDS = {}
for column, races in ipairs({ { "HUMAN", "DWARF", "GNOME", "NIGHTELF" }, { "TAUREN", "SCOURGE", "TROLL", "ORC" } }) do
  for row, race in ipairs(races) do
    for half, gender in ipairs({ "MALE", "FEMALE" }) do
      local left = (column - 1 + (half - 1) * 2) * 0.25
      RACE_SHEET_COORDS[race .. "_" .. gender] = { left, left + 0.25, (row - 1) * 0.25, row * 0.25 }
    end
  end
end

-- Button anatomy: padding, icon slot (always 20 px wide, whatever the icon is),
-- 4 px, label, padding. The 2 px selected border is drawn inside the button, so
-- the padding is wider than the border. One gap for both directions between
-- the buttons of a group.
local CHOICE_ICON = 20
local CHOICE_PAD = 6
local CHOICE_ICON_GAP = 4
local CHOICE_CHECK = 12
local CHOICE_CHROME = CHOICE_PAD * 2 + CHOICE_ICON + CHOICE_ICON_GAP
local CHOICE_GAP = 6
local CREST_CROP = { 0.08, 0.92, 0.08, 0.92 }

local function luminance(r, g, b)
  local function lin(c)
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

-- The color moved towards white (dark background) or black (light background)
-- until it reaches minRatio against the Theme color `background`.
function K.ContrastColor(r, g, b, background, minRatio)
  local bl = luminance(Theme.rgb(background or "surface"))
  local target = bl < 0.5 and 1 or 0
  for step = 0, 10 do
    local t = step / 10
    local cr, cg, cb = r + (target - r) * t, g + (target - g) * t, b + (target - b) * t
    local l = luminance(cr, cg, cb)
    if (math.max(l, bl) + 0.05) / (math.min(l, bl) + 0.05) >= (minRatio or 3) then
      return cr, cg, cb
    end
  end
  return target, target, target
end

local function toHex(r, g, b)
  return string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Class color as "#rrggbb": the client's own class color, the theme's table
-- when the client has none, moved to at least 3:1 (non-text contrast) against
-- the button surface.
function K.ClassColorHex(class)
  local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
  color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  local r, g, b
  if
    type(color) == "table"
    and type(color.r) == "number"
    and type(color.g) == "number"
    and type(color.b) == "number"
  then
    r, g, b = color.r, color.g, color.b
  else
    r, g, b = Theme.rgb(class)
  end
  return toHex(K.ContrastColor(r, g, b, "surface", 3))
end

-- `sex` as UnitSex returns it (2 male, 3 female); without it the logged-in character's.
local function genderOf(sex)
  if sex == nil then
    sex = UnitSex and UnitSex("player")
  end
  return sex == 3 and "female" or "male"
end

local function atlasKnown(name)
  local get = C_Texture and C_Texture.GetAtlasInfo
  if not get then
    return false
  end
  local ok, info = pcall(get, name)
  return ok and info ~= nil
end

-- Without a file lookup in the client the sheet cannot be told from a missing
-- file (which renders as a green square), so it is not used then.
local function fileKnown(path)
  local get = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
  if not get then
    return false
  end
  local ok, id = pcall(get, path)
  return ok and id ~= nil
end

local function firstLetter(text)
  return (tostring(text or "?"):match("[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
end

local function badgeSpec(text, color)
  return { kind = "badge", letter = firstLetter(text), color = color }
end

-- Icon specs: { kind = "sheet", texture, coords } | { kind = "atlas", atlas } |
-- { kind = "texture", texture } | { kind = "split", left, right } |
-- { kind = "badge", letter, color }. The badge is the last resort, so a button
-- never ends up with an empty icon.
function K.ClassIconSpec(class)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then
    return { kind = "sheet", texture = K.CLASS_ICON_SHEET, coords = coords }
  end
  return badgeSpec(R.className(class), K.ClassColorHex(class))
end

local function crestSpec(side)
  return { kind = "texture", texture = K.FACTION_CREST[side] }
end

-- "A" or "H": the crest. "all": both crests, half each.
function K.FactionIconSpec(value)
  if value == "all" then
    return { kind = "split", left = crestSpec("A"), right = crestSpec("H") }
  end
  return crestSpec(value)
end

-- Order of resolution: client atlas (only when the client has it), the race
-- sheet (only when the client can tell the file exists), the shipped icon for
-- races without a client icon, the letter badge. `sex` (optional, UnitSex values) is the
-- gender of the icon; lists of other characters pass the stored one.
function K.RaceIconSpec(slug, side, name, sex)
  local info = K.RACE_ICONS[slug]
  if info and info.atlas then
    local gender = genderOf(sex)
    local atlas = "raceicon-" .. info.atlas .. "-" .. gender
    if atlasKnown(atlas) then
      return { kind = "atlas", atlas = atlas }
    end
    local key = info.sheet .. "_" .. gender:upper()
    local coords = (RACE_ICON_TCOORDS and RACE_ICON_TCOORDS[key]) or RACE_SHEET_COORDS[key]
    if coords and fileKnown(K.RACE_ICON_SHEET) then
      return { kind = "sheet", texture = K.RACE_ICON_SHEET, coords = coords }
    end
  elseif info and info.file then
    return { kind = "texture", texture = info.file }
  end
  return badgeSpec(name or slug, side == "H" and "horde" or side == "A" and "alliance" or "accent2")
end

local function paintIcon(btn, spec)
  btn.iconSpec = spec
  local size = btn.iconSize or CHOICE_ICON
  local icon, icon2 = btn.icon, btn.icon2
  icon:ClearAllPoints()
  icon:SetPoint("LEFT", btn.slot, "LEFT")
  icon:SetSize(size, size)
  icon:SetVertexColor(1, 1, 1)
  icon:Show()
  icon2:Hide()
  btn.badge:Hide()
  btn.badgeText:Hide()
  btn.outline:Hide()
  local kind = spec.kind
  if kind == "atlas" then
    icon:SetAtlas(spec.atlas)
  elseif kind == "sheet" then
    icon:SetTexture(spec.texture)
    icon:SetTexCoord(unpack(spec.coords))
  elseif kind == "texture" then
    icon:SetTexture(spec.texture)
    icon:SetTexCoord(unpack(CREST_CROP))
    btn.outline:Show()
  elseif kind == "split" then
    local half = size / 2
    icon:SetSize(half, size)
    icon:SetTexture(spec.left.texture)
    icon:SetTexCoord(0.08, 0.5, 0.08, 0.92)
    icon2:ClearAllPoints()
    icon2:SetPoint("LEFT", icon, "RIGHT", 0, 0)
    icon2:SetSize(half, size)
    icon2:SetTexture(spec.right.texture)
    icon2:SetTexCoord(0.5, 0.92, 0.08, 0.92)
    icon2:Show()
    btn.outline:Show()
  else
    icon:Hide()
    local r, g, b = Theme.rgb(spec.color or "accent2")
    btn.badge:SetColorTexture(r, g, b, 1)
    btn.badge:Show()
    btn.badgeText:SetText(spec.letter or "?")
    W.SetColor(btn.badgeText, luminance(r, g, b) > 0.35 and "bg" or "text")
    btn.badgeText:Show()
  end
end

-- The parts of an icon on `owner`: a fixed-size slot (the caller anchors it),
-- icon, second icon (split crest), letter badge and the thin dark outline.
-- Everything sits inside the slot, so a label next to the slot never overlaps.
local function newIconSlot(owner, size)
  size = size or CHOICE_ICON
  owner.iconSize = size
  owner.slot = owner:CreateTexture(nil, "ARTWORK")
  owner.slot:SetSize(size, size)
  -- Thin dark outline for square icons (crests), the class circles and race
  -- atlases are shaped already.
  owner.outline = owner:CreateTexture(nil, "BORDER")
  owner.outline:SetColorTexture(ns.Theme.scrim(0.6))
  owner.outline:SetPoint("TOPLEFT", owner.slot, "TOPLEFT", -1, 1)
  owner.outline:SetPoint("BOTTOMRIGHT", owner.slot, "BOTTOMRIGHT", 1, -1)
  owner.icon = owner:CreateTexture(nil, "ARTWORK")
  owner.icon2 = owner:CreateTexture(nil, "ARTWORK")
  owner.badge = owner:CreateTexture(nil, "ARTWORK")
  owner.badge:SetPoint("TOPLEFT", owner.slot, "TOPLEFT")
  owner.badge:SetSize(size, size)
  owner.badgeText = W.Text(owner, { role = "micro", color = "bg", justify = "CENTER" })
  owner.badgeText:SetPoint("CENTER", owner.badge, "CENTER")
end

-- A plain icon (class, faction or race, see the icon spec functions) for places that are not choice
-- buttons, e.g. the headers of the class cards. `size` defaults to 20 px (K.IconFrame passes its own).
function K.IconSlot(parent, spec, size)
  size = size or CHOICE_ICON
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  newIconSlot(holder, size)
  holder.slot:SetPoint("TOPLEFT")
  paintIcon(holder, spec)
  -- Repaint for a reused frame; leftovers of the old spec must not stay.
  function holder:SetSpec(newSpec)
    paintIcon(self, newSpec)
  end
  return holder
end

-- One choice button. o: label (text), labelColor (Theme token, default "text"),
-- ring (Theme token or "#rrggbb" of the selected border), idleRing (same for the
-- thin idle border, default accentDim), icon (icon spec),
-- onClick, tooltip (optional text). Methods: SetSelected(bool), Measure(width)
-- -> width, height at the button's natural size (never above width; a name
-- wider than the page wraps).
function K.ChoiceButton(parent, o)
  local btn = CreateFrame("Button", nil, parent)
  W.Fill(btn, "surface", 1)
  btn.tint = btn:CreateTexture(nil, "BACKGROUND")
  btn.tint:SetAllPoints()
  btn.tint:Hide()
  ns.Bind(btn, function()
    local r, g, b = Theme.rgb(o.ring or "accent2")
    btn.tint:SetColorTexture(r, g, b, 0.22)
  end)
  local hover = btn:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  -- Class buttons keep a thin border in their class color while idle.
  local idleName, idleAlpha = o.idleRing or "accentDim", 0.7
  btn.ringOff = W.Border(btn, idleName, idleAlpha, 1)
  -- Selected reads as tint, check mark and a bottom bar; a thick outline hugged the label too tightly.
  local bar = btn:CreateTexture(nil, "OVERLAY")
  bar:SetPoint("BOTTOMLEFT")
  bar:SetPoint("BOTTOMRIGHT")
  bar:SetHeight(2)
  bar:Hide()
  ns.Bind(bar, function(t)
    t:SetColorTexture(Theme.rgb(o.ring or "accent2"))
  end)
  btn.ringOn = {
    colorName = o.ring or "accent2",
    edges = { bar },
    show = function(on)
      bar:SetShown(on)
    end,
  }
  newIconSlot(btn)
  btn.slot:SetPoint("LEFT", btn, "LEFT", CHOICE_PAD, 0)
  -- Check mark over the lower right corner of the icon slot (on a dark chip,
  -- so it reads on every icon), it takes no room of its own.
  btn.checkBack = btn:CreateTexture(nil, "OVERLAY")
  btn.checkBack:SetColorTexture(ns.Theme.scrim(0.7))
  btn.checkBack:SetSize(CHOICE_CHECK, CHOICE_CHECK)
  btn.checkBack:SetPoint("BOTTOMRIGHT", btn.slot, "BOTTOMRIGHT", 3, -3)
  btn.checkBack:Hide()
  btn.check = W.CheckMark(btn, CHOICE_CHECK, "text")
  btn.check:SetPoint("CENTER", btn.checkBack, "CENTER")
  btn.check:Hide()
  btn.label = W.Text(btn, { text = o.label, role = "ui", color = o.labelColor or "text", wrap = true })
  btn.label:SetPoint("LEFT", btn.slot, "RIGHT", CHOICE_ICON_GAP, 0)
  paintIcon(btn, o.icon)
  btn:SetScript("OnClick", ns.Wrap("choice-button", o.onClick))
  if o.tooltip then
    btn:SetScript("OnEnter", function()
      ns.ShowTooltip(btn, o.tooltip)
    end)
    btn:SetScript("OnLeave", ns.HideTooltip)
  end
  ns.Focus.register(btn, function(self)
    self:Click()
  end)

  function btn:SetSelected(selected)
    self.selected = selected
    self.ringOff.show(true)
    self.ringOff.set(selected and (o.ring or "accent2") or idleName, selected and 1 or idleAlpha)
    self.ringOn.show(selected)
    self.check:SetShown(selected)
    self.checkBack:SetShown(selected)
    self.tint:SetShown(selected)
  end

  function btn:Measure(width)
    self.label:SetWidth(0)
    local w = math.min(width, CHOICE_CHROME + math.ceil(self.label:GetStringWidth()))
    self.label:SetWidth(math.max(1, w - CHOICE_CHROME))
    self.contentWidth = w
    return w, math.max(scaledHeight(28), math.ceil(self.label:GetStringHeight()) + 10)
  end
  return btn
end

-- Wrapping row of choice buttons. o: items (list of { value, label, labelColor,
-- ring, icon, tooltip, group }), get() -> current value, click(value) (what a
-- click does), labelKey (optional caption above the buttons), isShown(item)
-- (optional, hides single buttons), a button whose item has another `group` than
-- the previous shown one starts a new line. Lays itself out through
-- fgGridLayout(width), so it works inside a page Stack and reflows on window
-- resize; every child hangs off the group's own frame.
function K.ChoiceGroup(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  local caption = o.labelKey and W.Text(f, { key = o.labelKey, role = "ui" }) or nil
  if caption then
    caption:SetPoint("TOPLEFT")
  end
  local buttons = {}
  for _, item in ipairs(o.items) do
    local btn = K.ChoiceButton(f, {
      label = item.label,
      labelColor = item.labelColor,
      ring = item.ring,
      idleRing = item.idleRing,
      icon = item.icon,
      tooltip = item.tooltip,
      onClick = function()
        o.click(item.value)
      end,
    })
    btn.value, btn.item, btn.slug, btn.side = item.value, item, item.slug, item.side
    buttons[#buttons + 1] = btn
  end

  function f.Refresh()
    local current = o.get()
    for _, btn in ipairs(buttons) do
      btn:SetShown(not o.isShown or o.isShown(btn.item))
      btn:SetSelected(btn.value == current)
    end
  end

  function f:fgGridLayout(width)
    local y = 0
    if caption then
      y = math.ceil(caption:GetStringHeight()) + 4
    end
    local cx, rowH, lastGroup = 0, 0, nil
    for _, btn in ipairs(buttons) do
      local item = btn.item
      local show = not o.isShown or o.isShown(item)
      btn:SetShown(show)
      if show then
        local w, h = btn:Measure(width)
        if cx > 0 and (cx + w > width or item.group ~= lastGroup) then
          cx, y, rowH = 0, y + rowH + CHOICE_GAP, 0
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, -y)
        btn:SetSize(w, h)
        cx = cx + w + CHOICE_GAP
        rowH = math.max(rowH, h)
        lastGroup = item.group
      end
    end
    local height = y + rowH
    f:SetHeight(math.max(1, height))
    return height
  end

  -- Width of the whole group on one line (caption included), so a bar can keep it beside other controls.
  function f.NaturalWidth()
    local total, count = 0, 0
    for _, btn in ipairs(buttons) do
      if not o.isShown or o.isShown(btn.item) then
        total = total + (btn:Measure(math.huge)) + (count > 0 and CHOICE_GAP or 0)
        count = count + 1
      end
    end
    return math.max(total, caption and math.ceil(caption:GetStringWidth()) or 0)
  end

  f.buttons = buttons
  f.Refresh()
  return f
end

-- Class choice, one button per class with the class icon and the class color as
-- selected border. opts: get() -> class token, set(token), labelKey (default
-- "kit.filterClass", false = no caption).
function K.ClassButtons(parent, opts)
  local items = {}
  for _, class in ipairs(R.CLASSES) do
    items[#items + 1] = {
      value = class,
      label = R.className(class),
      ring = K.ClassColorHex(class),
      idleRing = K.ClassColorHex(class),
      icon = K.ClassIconSpec(class),
    }
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    click = opts.set,
    labelKey = opts.labelKey == nil and "kit.filterClass" or opts.labelKey or nil,
  })
end

local FACTION_RING = { A = "alliance", H = "horde", all = "accent2" }
local FACTION_VALUES = { "A", "H", "all" }

-- Faction choice (Alliance, Horde, optionally both) with the crest as icon, the
-- faction color as label and as selected border. opts: get() -> "A"|"H"|"all",
-- set(value), withAll (bool, adds "both factions"), allKey (locale key for the label of that choice, default
-- "kit.faction.all"), labelKey (default
-- "kit.filterFaction", false = no caption).
function K.FactionButtons(parent, opts)
  local items = {}
  for _, value in ipairs(FACTION_VALUES) do
    if value ~= "all" or opts.withAll then
      items[#items + 1] = {
        value = value,
        label = value == "all" and L[opts.allKey or "kit.faction.all"] or L["kit.faction." .. value],
        labelColor = value == "all" and "text" or FACTION_RING[value],
        ring = FACTION_RING[value],
        icon = K.FactionIconSpec(value),
      }
    end
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    click = opts.set,
    labelKey = opts.labelKey == nil and "kit.filterFaction" or opts.labelKey or nil,
  })
end

-- Race choice with the race icon (see K.RaceIconSpec), the races of one faction
-- on their own line. opts: races (list of { f = "A"|"H", n = { de, en }, s =
-- slug } as in WeaponRaces, or { f, n, slug } as in Data.Races), get() -> slug,
-- set(slug|nil), clearable (a second click on the selected race clears it),
-- isShown(race) (optional filter).
function K.RaceButtons(parent, opts)
  local items = {}
  for _, race in ipairs(opts.races or {}) do
    local slug = race.s or race.slug
    local name = ns.T(race.n)
    items[#items + 1] = {
      value = slug,
      label = name,
      ring = "accent2",
      icon = K.RaceIconSpec(slug, race.f, name),
      group = race.f,
      side = race.f,
      slug = slug,
    }
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    isShown = opts.isShown,
    click = function(slug)
      if opts.clearable and opts.get() == slug then
        opts.set(nil)
      else
        opts.set(slug)
      end
    end,
  })
end

-- Stacks the shown children of `host` under each other, each at the full width,
-- and returns the total height. Children are frames with fgGridLayout(width).
function K.StackLayout(host, children, width, gap)
  local y = 0
  for _, child in ipairs(children) do
    if child:IsShown() then
      child:ClearAllPoints()
      child:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
      child:SetWidth(width)
      y = y + child:fgGridLayout(width) + gap
    end
  end
  local height = math.max(1, y - gap)
  host:SetHeight(height)
  return height
end

-- Faction and race picker of the weapon masters page: the faction buttons
-- (Alliance, Horde, Both factions) with the race buttons of the selected faction
-- wrapped below. opts: races, getFaction()/setFaction("A"|"H"|"all"),
-- getRace()/setRace(slug|nil), optional raceAllowed(slug) to hide races the page
-- cannot use (nil = all). Clicking the selected race again clears it.
function K.FactionRaceSelector(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  local heads = K.FactionButtons(f, {
    withAll = true,
    labelKey = false,
    get = opts.getFaction,
    set = opts.setFaction,
  })
  local races = K.RaceButtons(f, {
    races = opts.races,
    clearable = true,
    get = opts.getRace,
    set = opts.setRace,
    -- Only the allowed races of the selected faction are shown.
    isShown = function(item)
      local faction = opts.getFaction()
      return (faction == "all" or faction == item.side) and (not opts.raceAllowed or opts.raceAllowed(item.slug))
    end,
  })
  function f.Refresh()
    heads.Refresh()
    races.Refresh()
  end
  function f:fgGridLayout(width)
    return K.StackLayout(f, { heads, races }, width, CHOICE_GAP)
  end
  f.heads, f.races = heads.buttons, races.buttons
  return f
end

-- Small confidence marker (data reliability: 3=reliable, 2=likely, else
-- estimated), replacing the old inline "kit.conf.*" text. The word itself
-- lives in the tooltip so the information never depends on color alone.
function K.ConfidenceDot(parent, cf)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(12, 12)
  f.cf = cf
  local dot = f:CreateTexture(nil, "ARTWORK")
  dot:SetPoint("TOPLEFT", 1, -1)
  dot:SetPoint("BOTTOMRIGHT", -1, 1)
  W.Border(f, "white", 0.4)
  local function paint()
    local colorName = f.cf == 3 and "success" or f.cf == 2 and "warning" or "textMuted"
    dot:SetColorTexture(Theme.color(colorName))
  end
  ns.Bind(f, paint)
  f:SetScript("OnEnter", function()
    ns.ShowTooltip(f, L["kit.conf." .. tostring(f.cf or 2)])
  end)
  f:SetScript("OnLeave", ns.HideTooltip)
  function f:SetCf(newCf)
    f.cf = newCf
    paint()
  end
  return f
end

-- W.Grid with pooled card frames: :Sync(list, paint) reuses one card per
-- list index across refreshes instead of leaking a fresh set of frames
-- every time a filter changes the result count. makeCard(parent) -> card.
-- Cards are parented to the grid frame itself (not the caller's outer
-- container): WoW only cascades Hide()/SetShown(false) down the real
-- frame parent chain, so cards parented to the outer container would
-- stay visible and float over whatever is shown next to a hidden grid.
function K.GridPool(parent, cardHeight, makeCard, gap)
  local pool, active = {}, {}
  local grid = W.Grid(parent, active, cardHeight, gap)
  function grid:Sync(list, paint)
    for i, item in ipairs(list) do
      local card = pool[i]
      if not card then
        card = makeCard(grid)
        pool[i] = card
      end
      paint(card, item)
      card:Show()
      active[i] = card
    end
    for i = #list + 1, #pool do
      pool[i]:Hide()
    end
    for i = #active, #list + 1, -1 do
      active[i] = nil
    end
  end
  return grid
end

-- Pooled list of rows whose height depends on their content, the variable-height
-- sibling of K.GridPool. makeRow(parent) -> row frame that defines
-- row:fgLayout(width) -> height: it positions its children, sets the width of
-- wrapped FontStrings before reading GetStringHeight (anchor-derived widths are
-- not resolved in the same frame) and returns its own height.
-- :Sync(list, paint) reuses one row per list index and calls paint(row, item).
-- Rows hang off the pool's own frame, so hiding the pool hides them too.
-- fgGridLayout(width) stacks the active rows and returns the total height. A row may carry fgGap, empty
-- space above it (not part of the row frame, a rule may be drawn in it) that counts in the total height.
-- opts.cards = { minWidth, gap } flows the rows as cards in 1 to 3 columns (ns.CardFlow); every row
-- then needs fgLayout(width) for its own card width. Rows are only re-anchored on a width change.
function K.RowPool(parent, makeRow, opts)
  local pool, active = {}, {}
  local cards = opts and opts.cards
  local list = CreateFrame("Frame", nil, parent)
  function list:Sync(items, paint)
    for i, item in ipairs(items) do
      local row = pool[i]
      if not row then
        row = makeRow(list)
        pool[i] = row
      end
      paint(row, item)
      row:Show()
      active[i] = row
    end
    for i = #items + 1, #pool do
      pool[i]:Hide()
    end
    for i = #active, #items + 1, -1 do
      active[i] = nil
    end
  end
  local function flow(width)
    local cols, cw = ns.CardFlow.Columns(width, cards.minWidth, cards.gap)
    local heights = {}
    for i, row in ipairs(active) do
      row:SetWidth(cw)
      heights[i] = row:fgLayout(cw)
      row:SetHeight(heights[i])
    end
    local spots, total = ns.CardFlow.Place(heights, cols, cw, cards.gap)
    for i, row in ipairs(active) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", spots[i].x, -spots[i].y)
    end
    list:SetHeight(total)
    return total
  end
  function list:fgGridLayout(width)
    if cards then
      return flow(width)
    end
    local y = 0
    for _, row in ipairs(active) do
      y = y + (row.fgGap or 0)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      row:SetWidth(width)
      local h = row:fgLayout(width)
      row:SetHeight(h)
      y = y + h
    end
    list:SetHeight(y)
    return y
  end
  return list
end

-- Wrapping row of small icon chips (icon, name, muted meta text) for compact
-- overviews. :SetChips(list) takes { icon, name, meta, sid } entries and reuses
-- pooled Button frames; :Layout(width) places them left to right, breaks to a
-- new line when the next chip does not fit and returns the total height.
-- FontStrings here do not wrap, so chip widths come from GetStringWidth.
-- Hovering shows the spell tooltip when a spell id is set, else name and meta;
-- an optional tip is added as a last line.
-- Chips are parented to the row frame itself so hiding the row hides them.
local CHIP_ICON = 20
local CHIP_PAD = 6
local CHIP_GAP_X = 14
local CHIP_GAP_Y = 6

local function showChipTooltip(chip)
  local d = chip.data
  if not d then
    return
  end
  -- An item chip shows the full item tooltip (icon, prices, vendors), tip as its first line, hint last.
  local shop = ns.ProfessionShop
  if d.itemId and shop and shop.ShowItemTooltip(chip, d.itemId, d.tip and { d.tip } or nil, d.hint) then
    return
  end
  -- The spell tooltip heads it and the tip follows; without a spell, name and meta take over.
  if d.sid and W.Tooltip.Show(chip, { spell = d.sid, text = d.tip }) then
    return
  end
  ns.ShowTooltip(chip, d.name, d.tip and (d.meta .. "\n" .. d.tip) or d.meta)
end

local DEFAULT_CHIP_COLORS = { name = "text", meta = "textSecondary" }

local function newChip(parent, colors)
  local chip = CreateFrame("Button", nil, parent)
  local hover = chip:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(unpack(colors.hover or { Theme.fillColor("hover") }))
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
  chip.icon:SetPoint("LEFT", CHIP_PAD, 0)
  chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  chip.name = W.Text(chip, { role = "ui", color = colors.name })
  chip.name:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
  chip.meta = W.Meta(chip, { color = colors.meta })
  chip.meta:SetPoint("LEFT", chip.name, "RIGHT", 6, 0)
  chip:SetScript("OnEnter", showChipTooltip)
  chip:SetScript("OnLeave", ns.HideTooltip)
  -- A chip with data.onClick acts on click (waypoint at a vendor), the others only show their tooltip.
  ns.Focus.register(chip, function(self)
    local d = self.data
    if d and d.onClick then
      d.onClick()
    end
  end)
  return chip
end

-- colors: optional { name, meta (Theme tokens), hover = { r, g, b, a } } for chips on a light background.
function K.ChipRow(parent, colors)
  local row = CreateFrame("Frame", nil, parent)
  local pool, shown = {}, 0
  colors = colors or DEFAULT_CHIP_COLORS

  function row:SetChips(list)
    for i, d in ipairs(list) do
      local chip = pool[i]
      if not chip then
        chip = newChip(row, colors)
        pool[i] = chip
      end
      chip.data = d
      chip:SetScript("OnClick", d.onClick and function()
        d.onClick()
      end or nil)
      chip.icon:SetTexture(d.icon)
      -- iconOnly: the icon alone shows, name and meta stay in the tooltip.
      chip.name:SetText(d.iconOnly and "" or d.name or "")
      chip.meta:SetText(d.iconOnly and "" or d.meta or "")
      chip:Show()
    end
    for i = #list + 1, #pool do
      pool[i].data = nil
      pool[i]:SetScript("OnClick", nil)
      pool[i]:Hide()
    end
    shown = #list
  end

  -- Every chip made so far (hidden ones too), for an owner that keeps them in its keyboard order.
  function row:Frames()
    local out = {}
    for i, chip in ipairs(pool) do
      out[i] = chip
    end
    return out
  end

  function row:Layout(width)
    local chipH = scaledHeight(CHIP_ICON + 4)
    local x, y = 0, 0
    for i = 1, shown do
      local chip = pool[i]
      -- Measure unconstrained, then cap the name so one long chip cannot
      -- overflow the row.
      chip.name:SetWidth(0)
      local nameW = math.ceil(chip.name:GetStringWidth())
      chip.meta:SetWidth(0)
      local metaW = 0
      if not chip.data.iconOnly and (chip.data.meta or "") ~= "" then
        -- Inline textures (coin icons) get a little slack in case a measure misses them.
        metaW = math.ceil(chip.meta:GetStringWidth()) + 2 * select(2, chip.data.meta:gsub("|T", ""))
      end
      local fixed = CHIP_PAD + CHIP_ICON + 6 + CHIP_PAD
      local w = fixed + nameW + (metaW > 0 and metaW + 6 or 0)
      if w > width then
        w = math.max(fixed + 20, width)
        local nameRoom = math.max(20, math.min(nameW, w - fixed - (metaW > 0 and metaW + 6 or 0)))
        chip.name:SetWidth(nameRoom)
        if metaW > 0 then
          -- Too narrow even alone: the meta text shrinks instead of leaving the row.
          chip.meta:SetWidth(math.max(20, math.min(metaW, w - fixed - nameRoom - 6)))
        end
      end
      if x > 0 and x + w > width then
        x, y = 0, y + chipH + CHIP_GAP_Y
      end
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
      chip:SetSize(w, chipH)
      x = x + w + CHIP_GAP_X
    end
    local height = shown > 0 and (y + chipH) or 0
    row:SetHeight(height)
    return height
  end

  return row
end

-- Filter bar -------------------------------------------------------------------------------------------
-- One filter row for a list page: the controls flow left to right and wrap into another row only when
-- the width demands it, bottom aligned. At the end sit the number of active filters and the link button
-- "Reset filters", both only while a filter is active. The bar lays itself out through fgGridLayout(width)
-- (a W.Stack item). o: count() -> number of active filters, reset() (the owner puts its state and its
-- widgets back and repaints), resetTip (optional locale key: what the reset clears). The owner calls bar:Refresh() whenever the state changed, before its
-- layout pass. Methods: bar:Add(frame, { w, h, measure, after }), bar:AddSearch, bar:AddDropdown,
-- bar:AddToggle, bar:AddGroup (a K.ChoiceGroup), bar:Reset(), bar:IsFiltered().

function K.FilterBar(parent, o)
  local bar = CreateFrame("Frame", nil, parent)
  local items = {}
  local tail

  -- Items: frame, w (number, default the frame width), h (default the frame height), measure(width) -> w, h
  -- (items whose size depends on text or room), after (a control to the right of frame, the pair wraps as one).
  function bar:Add(frame, io)
    io = io or {}
    items[#items + 1] = { frame = frame, w = io.w, h = io.h, measure = io.measure, after = io.after }
    return frame
  end

  -- A captioned search field. so: key (caption), placeholder, onChange(text), width (default 220).
  function bar:AddSearch(so)
    local width = so.width or 220
    local box = CreateFrame("Frame", nil, bar)
    box:SetSize(width, Theme.size.control)
    W.Text(box, { key = so.key, role = "ui", color = "textMuted" }):SetPoint("TOPLEFT")
    local search = W.EditBox(box, { placeholder = so.placeholder, clear = true, onChange = so.onChange })
    search:SetPoint("TOPLEFT", 0, -W.DROPDOWN_FIELD_Y)
    search:SetWidth(width)
    search.box = box
    if so.text and so.text ~= "" then
      search.edit:SetText(so.text)
    end
    self:Add(box)
    return search
  end

  -- A captioned dropdown (opts of W.Dropdown, width default 200).
  function bar:AddDropdown(d)
    d.width = d.width or 200
    local dd = W.Dropdown(bar, d)
    dd:SetWidth(d.width)
    self:Add(dd)
    return dd
  end

  -- A checkbox level with the fields (opts of W.Checkbox).
  function bar:AddToggle(t)
    local box = W.Checkbox(bar, t)
    self:Add(box, {
      measure = function(width)
        local w = math.min(width, 16 + 8 + math.ceil(box.label:GetStringWidth()) + 4)
        box:SetWidth(w)
        return w, 22
      end,
    })
    return box
  end

  -- A K.ChoiceGroup (faction, class): beside the other controls while it fits on one line, else a row of its own.
  function bar:AddGroup(group)
    self:Add(group, {
      measure = function(width)
        local w = math.min(group.NaturalWidth(), width)
        group:SetWidth(w)
        return w, group:fgGridLayout(w)
      end,
    })
    return group
  end

  local function ensureTail()
    if tail then
      return
    end
    local count = W.Meta(bar, { color = "textMuted" })
    local reset = W.Action(bar, {
      key = W.EMPTY_RESET,
      variant = "ghost",
      size = 24,
      tooltip = o.resetTip and W.EMPTY_RESET or nil,
      tooltipText = o.resetTip,
      onClick = function()
        bar:Reset()
      end,
    })
    tail = { count = count, reset = reset }
    bar.resetButton, bar.countText = reset, count
    bar:Add(count, {
      measure = function()
        return math.ceil(count:GetStringWidth()) + 2, math.ceil(count:GetStringHeight())
      end,
    })
    bar:Add(reset, {
      measure = function(width)
        local w = reset:Fit(width)
        reset:SetWidth(w)
        return w, 24
      end,
    })
    bar:Refresh()
  end

  function bar:IsFiltered()
    return (o.count and o.count() or 0) > 0
  end

  function bar:Refresh()
    local n = o.count and o.count() or 0
    if not tail then
      return ensureTail()
    end
    tail.count:SetText(n == 1 and L["kit.filters.active1"] or string.format(L["kit.filters.active"], n))
    tail.count:SetShown(n > 0)
    tail.reset:SetShown(n > 0)
  end

  function bar:Reset()
    o.reset()
    self:Refresh()
  end

  function bar:fgGridLayout(width)
    ensureTail()
    local y, x, rowH = 0, 0, 0
    local row = {}
    local function flush()
      for _, p in ipairs(row) do
        p.frame:ClearAllPoints()
        p.frame:SetPoint("TOPLEFT", bar, "TOPLEFT", p.x, -(y + rowH - p.h))
        if p.after then
          p.after:ClearAllPoints()
          p.after:SetPoint("LEFT", p.frame, "RIGHT", Theme.space.sm, 0)
        end
      end
      y, x, rowH, row = y + rowH + Theme.space.sm, 0, 0, {}
    end
    for _, it in ipairs(items) do
      if it.frame:IsShown() then
        local w, h
        if it.measure then
          w, h = it.measure(width)
        else
          w, h = it.w or it.frame:GetWidth(), it.h or it.frame:GetHeight()
        end
        local total = w + (it.after and Theme.space.sm + it.after:GetWidth() or 0)
        if x > 0 and x + total > width then
          flush()
        end
        row[#row + 1] = { frame = it.frame, after = it.after, x = x, h = h }
        x = x + total + Theme.space.md
        rowH = math.max(rowH, h)
      end
    end
    if #row > 0 then
      flush()
    end
    local height = math.max(0, y - Theme.space.sm)
    bar:SetHeight(math.max(1, height))
    return height
  end

  return bar
end

-- Quick DE | EN toggle (main bar, news window). The setting is global; the active language is the one source.
function K.LanguageToggle(bar)
  -- Shows the resolved language (ns.GetActiveLocale) and switches it with one click. The active side is a
  -- selected toggle: accent text, dark fill and the accent bar (not color-only).
  local function setLocale(loc)
    ns.Store.set("settings.locale", loc)
    ns.SetLocale(loc)
    ns.RefreshUI()
    ns.Main.InvalidateViews()
  end
  local langToggle = CreateFrame("Frame", nil, bar)
  langToggle:SetSize(64, 22)
  local langDE = W.Button(langToggle, {
    text = "DE",
    variant = "ghost",
    width = 32,
    height = 22,
    tooltip = "settings.languageLabel",
    onClick = function()
      setLocale("deDE")
    end,
  })
  langDE:SetPoint("LEFT")
  local langEN = W.Button(langToggle, {
    text = "EN",
    variant = "ghost",
    width = 32,
    height = 22,
    tooltip = "settings.languageLabel",
    onClick = function()
      setLocale("enUS")
    end,
  })
  langEN:SetPoint("LEFT", langDE, "RIGHT", 4, 0)
  -- The default 8 px label padding leaves 12 px in a 28 px button, too little
  -- for two letters, so the text was cut to "...". Size to the widest label.
  -- Bound on the label so it runs after the label's own font refresh.
  local function fitLangButtons()
    local width = 32
    for _, b in ipairs({ langDE, langEN }) do
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", 3, 0)
      b.label:SetPoint("RIGHT", -3, 0)
      width = math.max(width, math.ceil(b.label:GetStringWidth()) + 10)
    end
    langDE:SetWidth(width)
    langEN:SetWidth(width)
    langToggle:SetWidth(2 * width + 4)
  end
  ns.Bind(langEN.label, fitLangButtons)
  local function refreshLangToggle()
    local active = ns.GetActiveLocale()
    langDE:SetSelected(active == "deDE")
    langEN:SetSelected(active == "enUS")
  end
  -- The active language is the one source: the setting is stored before ns.SetLocale resolves it, so the mark
  -- follows FG_LOCALE_CHANGED, and every repaint (style, size, font) reads it again through the bind.
  ns.Bind(langToggle, refreshLangToggle)
  ns.On("FG_LOCALE_CHANGED", refreshLangToggle)
  return langToggle, langDE, langEN
end
