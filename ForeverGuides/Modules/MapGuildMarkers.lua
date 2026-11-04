-- Guild members on the map page (the add-on's own map): the symbols of the world map pins (hexagon in the
-- class color, ring for an old or unconfirmed report, diamond for an approximate place, a number for
-- several members close together) at the position a member reported, placed with
-- MapPlayerMarkerLogic.Locate on the view the canvas shows. A zone-only report sits in the middle of its
-- zone. Members on a map the view does not show stay off. The frames lie above the canvas without mouse
-- (clicks go to the map), hover is polled like the player marker's. Shown while the option "world map"
-- (guildMapShowWorld) is on and receiving is on; the data are ns.GuildMapStore joined with the guild list.
-- Pool of at most MAX pins, no frame is built in combat. The keyboard route is the member list.
local _, ns = ...
local L, Theme, ML, GLG, GML = ns.L, ns.Theme, ns.MapPlayerMarkerLogic, ns.WorldMapGuildLogic, ns.GuildMapListLogic

local MGM = {}
ns.MapGuildMarkers = MGM

MGM.MAX = 100 -- pins, like the world map
MGM.INTERVAL = 0.25 -- seconds between two checks for a change and a hover
-- Above the places and the spots and under the player marker (level 100).
local LEVEL = 90

local controllers = setmetatable({}, { __mode = "k" })

local function receiving()
  return ns.Consent.Allows("guildMap", "receive", "guild")
end

-- Are guild markers wanted on the map page now?
function MGM.Enabled()
  return GLG.Current().showWorld and receiving()
end

local function paintLine(kind, text)
  return Theme.hexText(kind == "warning" and "warning" or "textMuted", text)
end

local function rosterOf()
  local snap = ns.GuildData.Get()
  return snap and snap.members
end

-- ctx = {
--   canvas                the map canvas the markers sit on
--   view()                the view the canvas shows (see MapPlayerMarker), nil on the flat canvas
--   window()              left, top, width, height of the visible part of the canvas in canvas px
--   cursor()              the cursor as fractions (0..1) of the visible part, nil when it is off the map
-- }
-- Returns the controller: Update(force), layer, pins, groups, shown, hover.
function MGM.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { pins = {}, groups = {}, shown = 0, dirty = true, since = 0 }
  controllers[ctl] = true

  local layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + LEVEL)
  layer:EnableMouse(false)
  ctl.layer = layer

  local function hideFrom(from)
    for i = from, #ctl.pins do
      ctl.pins[i].group = nil
      ctl.pins[i]:Hide()
    end
    for i = #ctl.groups, from, -1 do
      ctl.groups[i] = nil
    end
    ctl.shown = math.min(ctl.shown, from - 1)
  end

  -- Tooltip ------------------------------------------------------------------------------------------
  local function hideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip and tip:GetOwner() == layer then
      tip:Hide()
    end
  end

  local function showTip(group)
    local items = group.items
    if #items == 1 then
      local row = items[1].row
      ns.ShowTooltip(
        layer,
        ns.GuildKit.ColoredName(row.short, row.class),
        table.concat(GML.TipLines(row, L, paintLine), "\n"),
        { anchor = "ANCHOR_CURSOR" }
      )
      return
    end
    local lines = {}
    for i = 1, math.min(#items, ns.WorldMapGuildPins.LIST_LINES) do
      local row = items[i].row
      lines[#lines + 1] = ns.GuildKit.ColoredName(row.short, row.class) .. (row.level > 0 and (" " .. row.level) or "")
    end
    if #items > ns.WorldMapGuildPins.LIST_LINES then
      lines[#lines + 1] = string.format(L["wm.guild.tip.more"], #items - ns.WorldMapGuildPins.LIST_LINES)
    end
    ns.ShowTooltip(
      layer,
      string.format(L["wm.guild.tip.cluster"], #items),
      table.concat(lines, "\n"),
      { anchor = "ANCHOR_CURSOR" }
    )
  end

  -- Same test as the player marker: only the map itself under the cursor counts.
  local function mouseOnMap()
    local foci, legacy = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
    local target
    if foci then
      target = foci()[1]
    elseif legacy then
      target = legacy()
    end
    return target == nil or target == canvas or target == layer
  end

  local function setHover(group)
    if group == ctl.hover then
      return
    end
    ctl.hover = group
    if group then
      showTip(group)
    else
      hideTip()
    end
  end

  local function pollHover()
    local found
    local fx, fy = ctx.cursor()
    if fx and ctl.shown > 0 and mouseOnMap() then
      local l, t, w, h = ctx.window()
      local cx, cy = l + fx * w, t + fy * h
      for i = 1, ctl.shown do
        local group = ctl.groups[i]
        if ML.Hit(cx, cy, group.px, group.py, math.max(ML.HIT, (ctl.pins[i].fgSize or 0) / 2 + 2)) then
          found = group
          break
        end
      end
    end
    setHover(found)
  end

  -- Pins ---------------------------------------------------------------------------------------------

  -- The members the view shows, as { key, row, px, py } in canvas px.
  local function items(opts, view, cw, ch)
    local rows = GML.Rows(ns.GuildMapStore.All(), rosterOf(), opts, {
      me = ns.PlayerName.Self(),
      className = ns.GuildKit.ClassName,
    })
    local out = {}
    for _, row in ipairs(rows) do
      local nx, ny = ML.Locate(view, row.map, row.x or 0.5, row.y or 0.5)
      local px, py
      if nx then
        px, py = ML.CanvasPoint(nx, ny, cw, ch)
      end
      if px then
        out[#out + 1] = { key = row.key, row = row, px = px, py = py }
      end
    end
    return out
  end

  local function pinFor(index)
    local pin = ctl.pins[index]
    if not pin then
      -- Never build a frame in combat: the groups that find no pin wait for the next update.
      if ns.InCombat() then
        return nil
      end
      pin = ns.WorldMapGuildPins.NewSymbol(layer)
      pin:EnableMouse(false)
      ctl.pins[index] = pin
    end
    return pin
  end

  local function paint(opts, groups)
    local size = GLG.Size(ns.WorldMapGuildPins.BASE, opts.worldSize)
    local shown = 0
    for _, group in ipairs(groups) do
      if shown >= MGM.MAX then
        break
      end
      local pin = pinFor(shown + 1)
      if not pin then
        break
      end
      shown = shown + 1
      local first = group.items[1]
      local single = #group.items == 1 and first.row or nil
      local style = GLG.Style(single and single.approx, single and single.state, single and single.check)
      local edge = ns.WorldMapGuildPins.PaintSymbol(pin, {
        size = size,
        shape = style.shape,
        hollow = style.hollow,
        color = ns.WorldMapGuildPins.ClassColor(single and { class = single.class }, opts),
        cluster = not single and #group.items or nil,
        ticks = single and opts.showRank and single.rank and GLG.RankTicks(single.rank) or 0,
        text = single and GLG.Label(opts, single.name, single.level) or "",
      })
      pin.fgSize = edge
      pin:SetSize(edge + 6, edge + 6)
      pin:SetAlpha(single and style.hollow and 0.7 or 1)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", group.px, -group.py)
      pin.group = group
      pin:Show()
      ctl.groups[shown] = group
    end
    hideFrom(shown + 1)
    ctl.shown = shown
  end

  local function rebuild()
    local opts = GLG.Current()
    local view = ctx.view()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not (opts.showWorld and receiving() and view) then
      hideFrom(1)
      return
    end
    local list = items(opts, view, cw, ch)
    local size = GLG.Size(ns.WorldMapGuildPins.BASE, opts.worldSize)
    paint(opts, GLG.Group(list, size * ns.WorldMapGuildPins.GROUP_FACTOR, opts.group))
  end

  -- Draws the markers again when the data, an option or the canvas changed (force: the canvas was laid out),
  -- else only when a report may have aged (every WorldMapGuildPins.TICK seconds).
  function ctl.Update(force)
    if force or ctl.dirty or ctl.since >= ns.WorldMapGuildPins.TICK then
      ctl.dirty, ctl.since = false, 0
      setHover(nil)
      rebuild()
    end
    pollHover()
  end

  layer:SetScript("OnUpdate", function(_, dt)
    ctl.elapsed = (ctl.elapsed or 0) + (tonumber(dt) or 0)
    if ctl.elapsed >= MGM.INTERVAL then
      ctl.since = ctl.since + ctl.elapsed
      ctl.elapsed = 0
      ns.Safe("map-guild-markers", ctl.Update, false)
    end
  end)
  layer:SetScript("OnHide", function()
    ctl.hover = nil
    hideTip()
  end)
  return ctl
end

-- New, changed, removed or expired positions, a new guild list, a changed option or consent.
local function mark()
  for ctl in pairs(controllers) do
    ctl.dirty = true
  end
end

ns.On("FG_GUILDMAP_UPDATE", mark)
ns.On("FG_GUILD_UPDATE", mark)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.guildMap") then
    mark()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == "guildMap" then
    mark()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == "guildMap" then
    mark()
  end
end)
