-- Guild members on Blizzard's world map (WorldMapFrame), from ns.GuildMapStore (positions that members
-- sent through the guild map function) joined with the guild list (class, rank, level, online). A zone
-- map shows the members of that zone, a continent or world map those of its child zones. A member on a
-- map without a rectangle on the shown one (city floors, caves) is placed at the middle of the first
-- parent map that has one, as an approximate place. Pins lie on layer "guild" of WorldMapLinks.LEVELS.
-- Look: a hexagon with a dark contour in the class color. A diamond is an approximate place, a hollow
-- one (a ring) a report that is older than the current window or looks like a jump, a hexagon with a
-- number several members close together (the tooltip lists them). Optional marks: strokes above the
-- symbol for the rank (the guild master three), a label with name and level. Colour never carries the
-- state alone: shape and fill do. A pin is a button of its own, a left click opens the menu (waypoint,
-- whisper, invite). There is no right click: the map zooms out with it. Pins show only while receiving
-- the guild map is switched on, and only while the client lets us touch the map (ns.ProtectedAllowed);
-- no frame is built in combat. The keyboard route is the member list (a later package).
local _, ns = ...
local L, W, WML, GLG, Consent = ns.L, ns.W, ns.WorldMapLinks, ns.WorldMapGuildLogic, ns.Consent
local Store, PN, GD, Theme = ns.GuildMapStore, ns.PlayerName, ns.GuildData, ns.Theme

local WMG = {}
ns.WorldMapGuildPins = WMG

ns.AddLocale("enUS", {
  ["wm.guild.tip.cluster"] = "%d guild members",
  ["wm.guild.tip.level"] = "Level %d %s",
  ["wm.guild.tip.rank"] = "Rank: %s",
  ["wm.guild.tip.zone"] = "Zone (guild list): %s",
  ["wm.guild.tip.age"] = "Position reported %d s ago",
  ["wm.guild.tip.ageMin"] = "Position reported %d min ago",
  ["wm.guild.tip.approx"] = "Approximate place",
  ["wm.guild.tip.old"] = "Older report, the member may have moved",
  ["wm.guild.tip.jump"] = "Unconfirmed: the last move looks odd",
  ["wm.guild.tip.more"] = "and %d more",
  ["wm.guild.tip.hint"] = "Click for actions",
  ["wm.guild.tip.clusterHint"] = "Click sets a waypoint here",
  ["wm.guild.menu.waypoint"] = "Set waypoint",
  ["wm.guild.menu.whisper"] = "Whisper",
  ["wm.guild.menu.invite"] = "Invite to group",
})
ns.AddLocale("deDE", {
  ["wm.guild.tip.cluster"] = "%d Gildenmitglieder",
  ["wm.guild.tip.level"] = "Stufe %d %s",
  ["wm.guild.tip.rank"] = "Rang: %s",
  ["wm.guild.tip.zone"] = "Zone laut Gildenliste: %s",
  ["wm.guild.tip.age"] = "Position gemeldet vor %d s",
  ["wm.guild.tip.ageMin"] = "Position gemeldet vor %d min",
  ["wm.guild.tip.approx"] = "Ungefährer Ort",
  ["wm.guild.tip.old"] = "Ältere Meldung, das Mitglied kann weitergezogen sein",
  ["wm.guild.tip.jump"] = "Unbestätigt: der letzte Ortswechsel wirkt ungewöhnlich",
  ["wm.guild.tip.more"] = "und %d weitere",
  ["wm.guild.tip.hint"] = "Klick für Aktionen",
  ["wm.guild.tip.clusterHint"] = "Klick setzt hier einen Wegpunkt",
  ["wm.guild.menu.waypoint"] = "Wegpunkt setzen",
  ["wm.guild.menu.whisper"] = "Flüstern",
  ["wm.guild.menu.invite"] = "In die Gruppe einladen",
})

WMG.MAX_PINS = 100
WMG.BASE = 16 -- symbol edge at 100 percent, in pixels
WMG.GROUP_FACTOR = 0.9 -- grouping radius as a share of the symbol edge
WMG.CLUSTER_FACTOR = 1.35
WMG.TICK = 10 -- seconds between two redraws while members show (reports age without an event)
WMG.LIST_LINES = 12
local MEDIA = "Interface\\AddOns\\ForeverGuides\\Media\\"
local SHAPES = { hexagon = MEDIA .. "map_hexagon.png", diamond = MEDIA .. "map_diamond.png" }
local CONTOUR, TICK_W, TICK_H, TICK_GAP = 3, 4, 2, 1
local COSMIC = 0 -- Enum.UIMapType: no member stands on the map of the universe
local MENU_W, MENU_ROW = 190, 26

local map, menu
local pins = {}
local hooked = {}
local ticking, depth = false, 0

local function g(name)
  return rawget(_G, name)
end

local function receiving()
  return Consent.Allows("guildMap", "receive", "guild")
end

-- Pins ---------------------------------------------------------------------------------------------

local function hidePins(from)
  for i = from, #pins do
    local pin = pins[i]
    pin.group = nil
    pin:Hide()
  end
end

local function paintTexture(tex, shape, size, r, gr, b, a)
  tex:SetTexture(SHAPES[shape])
  tex:SetSize(size, size)
  tex:SetVertexColor(r, gr, b, a or 1)
  tex:Show()
end

local function memberLines(item)
  local e, m = item.entry, item.member
  local lines = {}
  if m then
    if m.level > 0 then
      lines[#lines + 1] = string.format(L["wm.guild.tip.level"], m.level, ns.GuildKit.ClassName(m.class, m.className))
    end
    if m.rankName ~= "" then
      lines[#lines + 1] = string.format(L["wm.guild.tip.rank"], m.rankName)
    end
    if m.zone ~= "" then
      lines[#lines + 1] = string.format(L["wm.guild.tip.zone"], m.zone)
    end
  end
  local n, unit = GLG.AgeParts(e.age)
  lines[#lines + 1] = string.format(L[unit == "s" and "wm.guild.tip.age" or "wm.guild.tip.ageMin"], n)
  if item.approx then
    lines[#lines + 1] = Theme.hexText("textMuted", L["wm.guild.tip.approx"])
  end
  if e.state ~= "current" then
    lines[#lines + 1] = Theme.hexText("warning", L["wm.guild.tip.old"])
  elseif e.check == "jump" then
    lines[#lines + 1] = Theme.hexText("warning", L["wm.guild.tip.jump"])
  end
  return lines
end

local function coloredName(item)
  local m = item.member
  return ns.GuildKit.ColoredName(item.entry.name, m and m.class)
end

local function tooltip(pin)
  local group = pin.group
  if not group then
    return
  end
  local items = group.items
  if #items == 1 then
    local lines = memberLines(items[1])
    lines[#lines + 1] = Theme.hexText("textMuted", L["wm.guild.tip.hint"])
    ns.ShowTooltip(pin, coloredName(items[1]), table.concat(lines, "\n"))
    return
  end
  local lines = {}
  for i = 1, math.min(#items, WMG.LIST_LINES) do
    local m = items[i].member
    local level = m and m.level > 0 and (" " .. m.level) or ""
    lines[#lines + 1] = coloredName(items[i]) .. level
  end
  if #items > WMG.LIST_LINES then
    lines[#lines + 1] = string.format(L["wm.guild.tip.more"], #items - WMG.LIST_LINES)
  end
  lines[#lines + 1] = Theme.hexText("textMuted", L["wm.guild.tip.clusterHint"])
  ns.ShowTooltip(pin, string.format(L["wm.guild.tip.cluster"], #items), table.concat(lines, "\n"))
end

-- Actions ------------------------------------------------------------------------------------------

local function moveFocus(list, step)
  local index = 0
  for i, b in ipairs(list) do
    if ns.Focus.current == b then
      index = i
    end
  end
  if #list == 0 then
    return
  end
  index = index == 0 and (step > 0 and 1 or #list) or (index - 1 + step) % #list + 1
  ns.Focus.set(list[index])
end

local function setWaypoint(map_, x, y, title)
  local wp = ns.Waypoints.Set({ map = map_, x = x, y = y, title = title, source = "map" })
  if wp then
    ns.Notify(string.format(L["wp.activated"], wp.title), "info")
  end
end

local function inviteReason(target)
  return ns.Invites.GroupInviteBlock(target.name, target.guid, target.offline)
end

local function buildMenu()
  local layer = ns.Desktop.Layer
  local p = layer.newPopup("surface2")
  local items = {
    {
      id = "waypoint",
      run = function(t)
        setWaypoint(t.map, t.x, t.y, t.name)
      end,
    },
    {
      id = "whisper",
      run = function(t)
        ns.GuildKit.Whisper(t.name)
      end,
    },
    {
      id = "invite",
      run = function(t)
        ns.Invites.InviteToGroup(t.name, t.guid, t.offline)
      end,
    },
  }
  p.buttons, p.byId = {}, {}
  for i, item in ipairs(items) do
    local b = W.Button(p, {
      key = "wm.guild.menu." .. item.id,
      variant = "ghost",
      width = MENU_W - 4,
      height = MENU_ROW,
      onClick = function()
        local target = p.target
        layer.close("select")
        if target then
          item.run(target)
        end
      end,
    })
    b.label:SetJustifyH("LEFT")
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
    p.buttons[i], p.byId[item.id] = b, b
  end
  -- A dimmed invite says why in its tooltip.
  p.byId.invite:HookScript("OnEnter", function(self)
    local reason = p.target and inviteReason(p.target)
    if reason then
      ns.ShowTooltip(self, L["wm.guild.menu.invite"], L["invite.why." .. reason] or reason)
    end
  end)
  p.byId.invite:HookScript("OnLeave", ns.HideTooltip)
  p:SetSize(MENU_W, #items * MENU_ROW + 4)
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      layer.close("escape")
    elseif key == "UP" or key == "DOWN" then
      moveFocus(self.buttons, key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    ns.PropagateKeys(self, not handled)
  end)
  return p
end

-- The menu of one member: where to set the waypoint, whom to whisper and invite.
local function openMenu(pin, item)
  local layer = ns.Desktop and ns.Desktop.Layer
  if not layer then
    return
  end
  menu = menu or buildMenu()
  local e, m = item.entry, item.member
  menu.target = {
    name = e.name,
    guid = m and m.guid,
    offline = m and m.online == false or false,
    map = e.map,
    x = e.x or 0.5,
    y = e.y or 0.5,
  }
  local blocked = inviteReason(menu.target) ~= nil
  menu.byId.invite:SetEnabled(not blocked)
  layer.open({
    frames = { menu },
    owner = pin,
    move = function(step)
      moveFocus(menu.buttons, step)
    end,
  })
  layer.place(menu, pin, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  menu:Show()
  ns.Focus.set(menu.buttons[1])
end

local function onClick(pin)
  local group = pin.group
  if not group then
    return
  end
  if #group.items == 1 then
    openMenu(pin, group.items[1])
  else
    local id = WML.MapID()
    if id then
      setWaypoint(id, group.nx, group.ny, string.format(L["wm.guild.tip.cluster"], #group.items))
    end
  end
end

-- Frames -------------------------------------------------------------------------------------------

-- The parts of a symbol on `frame`: contour, body, the hole of the hollow look, the rank strokes, the
-- number of a group and the label. The pins and the legend of the bar share them.
local function newParts(frame)
  frame.edge = frame:CreateTexture(nil, "BACKGROUND")
  frame.body = frame:CreateTexture(nil, "BORDER")
  frame.hole = frame:CreateTexture(nil, "ARTWORK", nil, 0)
  frame.ticks = {}
  for i = 1, 3 do
    frame.ticks[i] = {
      edge = frame:CreateTexture(nil, "ARTWORK", nil, 1),
      bar = frame:CreateTexture(nil, "ARTWORK", nil, 2),
    }
  end
  frame.count = W.Text(frame, { role = "micro", color = "text", justify = "CENTER" })
  frame.count:SetPoint("CENTER")
  frame.label = W.Text(frame, { role = "micro", color = "text", justify = "LEFT" })
end

-- spec: size (edge of the symbol), shape ("hexagon" or "diamond"), hollow, color ({ r, g, b }), cluster
-- (number of members, draws the group look), ticks (0 to 3), text (label). Returns the edge that was drawn.
local function paintParts(frame, spec)
  local size, bg = spec.size, { Theme.color("bg", 0.95) }
  for _, part in ipairs({ frame.edge, frame.body, frame.hole }) do
    part:ClearAllPoints()
    part:SetPoint("CENTER")
  end
  if spec.cluster then
    -- Several members: a bigger hexagon with a gold rim and the number inside.
    size = math.floor(size * WMG.CLUSTER_FACTOR + 0.5)
    frame.edgeColor = { Theme.color("accent2") }
    paintTexture(frame.edge, "hexagon", size + 2 * CONTOUR, unpack(frame.edgeColor))
    paintTexture(frame.body, "hexagon", size, unpack(bg))
    frame.hole:Hide()
    W.SetText(frame.count, nil, tostring(spec.cluster))
    frame.count:Show()
  else
    frame.edgeColor = bg
    paintTexture(frame.edge, spec.shape, size + 2 * CONTOUR, unpack(bg))
    paintTexture(frame.body, spec.shape, size, spec.color[1], spec.color[2], spec.color[3], spec.hollow and 0.85 or 1)
    if spec.hollow then
      paintTexture(frame.hole, spec.shape, math.max(2, math.floor(size * 0.5)), unpack(bg))
    else
      frame.hole:Hide()
    end
    frame.count:Hide()
  end
  for i, tick in ipairs(frame.ticks) do
    local on = i <= (spec.ticks or 0)
    tick.edge:SetShown(on)
    tick.bar:SetShown(on)
    if on then
      local x = (i - (spec.ticks + 1) / 2) * (TICK_W + TICK_GAP)
      local y = size / 2 + CONTOUR + 1
      tick.edge:ClearAllPoints()
      tick.edge:SetPoint("BOTTOM", frame, "CENTER", x, y - 1)
      tick.edge:SetColorTexture(unpack(bg))
      tick.edge:SetSize(TICK_W + 2, TICK_H + 2)
      tick.bar:ClearAllPoints()
      tick.bar:SetPoint("BOTTOM", frame, "CENTER", x, y)
      tick.bar:SetColorTexture(Theme.color("accent2"))
      tick.bar:SetSize(TICK_W, TICK_H)
    end
  end
  local text = spec.text or ""
  frame.label:ClearAllPoints()
  frame.label:SetPoint("LEFT", frame, "CENTER", size / 2 + CONTOUR + 3, 0)
  W.SetText(frame.label, nil, text)
  frame.label:SetShown(text ~= "")
  frame.fgSize = size
  return size
end

-- A plain frame that shows one symbol (the legend of the bar). Paint it with WMG.PaintSymbol.
function WMG.NewSymbol(parent)
  local frame = CreateFrame("Frame", nil, parent)
  newParts(frame)
  return frame
end

function WMG.PaintSymbol(frame, spec)
  return paintParts(frame, spec)
end

-- The colour of a member: its class, or a neutral one without class or without the option.
local function classColor(m, opts)
  if opts.showClass and m and ns.GuildKit.KNOWN_CLASS[m.class] then
    return { ns.U.hex(ns.PageKit.ClassColorHex(m.class)) }
  end
  return { Theme.color("textSecondary") }
end
WMG.ClassColor = classColor

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:RegisterForClicks("LeftButtonUp")
  newParts(pin)
  pin:SetScript("OnEnter", function(self)
    self.edge:SetVertexColor(Theme.color("accent2"))
    tooltip(self)
  end)
  pin:SetScript("OnLeave", function(self)
    self.edge:SetVertexColor(unpack(self.edgeColor))
    ns.HideTooltip()
  end)
  pin:SetScript(
    "OnClick",
    ns.Wrap("wmg-click", function(self, mouse)
      -- Only the left button acts: the right one zooms the map out.
      if mouse == nil or mouse == "LeftButton" then
        onClick(self)
      end
    end)
  )
  return pin
end

-- Look of one pin for its group: a single member or the number of several.
local function paintPin(pin, group, opts)
  local items, size = group.items, GLG.Size(WMG.BASE, opts.worldSize)
  local single = #items == 1 and items[1] or nil
  local style = GLG.Style(single and single.approx, single and single.entry.state, single and single.entry.check)
  local member = single and single.member
  local drawn = paintParts(pin, {
    size = size,
    shape = style.shape,
    hollow = style.hollow,
    color = classColor(member, opts),
    cluster = not single and #items or nil,
    ticks = single and opts.showRank and member and GLG.RankTicks(member.rank) or 0,
    text = single and GLG.Label(opts, single.entry.name, member and member.level) or "",
  })
  local hit = math.max(ns.MapPins.HIT, drawn + 6)
  pin:SetSize(hit, hit)
  pin:SetAlpha(single and style.hollow and 0.7 or 1)
end

-- Data ---------------------------------------------------------------------------------------------

local function parentOf(id)
  local info = WML.CApi("GetMapInfo", id)
  return type(info) == "table" and info.parentMapID or nil
end

local function rosterByKey()
  local snap = GD.Get()
  local out = {}
  for _, m in ipairs(snap and snap.members or {}) do
    out[m.key] = m
  end
  return out
end

local function inGroup(name)
  for _, fn in ipairs({ g("UnitInParty"), g("UnitInRaid") }) do
    if type(fn) == "function" then
      local ok, value = pcall(fn, name)
      if ok and value == true then
        return true
      end
    end
  end
  return false
end

-- The members the shown map `id` (of map type `kind`) displays, with their place on it (0..1). Members of
-- the player's group are left out: the client's own pin shows them.
local function placements(id, kind, opts)
  local roster, me, out = rosterByKey(), ns.PlayerName.Self(), {}
  for _, e in ipairs(Store.All()) do
    local m = roster[e.key]
    local member = { known = m ~= nil, level = m and m.level, rank = m and m.rank, online = m and m.online }
    if not PN.Equal(e.name, me) and GLG.Passes(opts, member) and not inGroup(e.name) then
      local nx, ny, approx = GLG.Resolve(e.map, e.x, e.y, id, kind, WML.Project, parentOf)
      if nx and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
        out[#out + 1] = { key = e.key, entry = e, member = m, nx = nx, ny = ny, approx = approx }
      end
    end
  end
  return out
end

-- Draw ---------------------------------------------------------------------------------------------

local arm

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local opts = GLG.Current()
  local canvas = opts.showWorld and receiving() and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  if not id then
    hidePins(1)
    return
  end
  local kind = WML.MapType(id)
  if kind == COSMIC then
    hidePins(1)
    return
  end
  local items, scale = placements(id, kind, opts), WML.CanvasScale()
  local width = canvas:GetWidth() * scale
  local height = canvas:GetHeight() * scale
  for _, item in ipairs(items) do
    item.px, item.py = item.nx * width, item.ny * height
  end
  local size = GLG.Size(WMG.BASE, opts.worldSize)
  local groups = GLG.Group(items, size * WMG.GROUP_FACTOR, opts.group)
  local shown = 0
  for _, group in ipairs(groups) do
    if shown >= WMG.MAX_PINS then
      break
    end
    local pin = pins[shown + 1]
    if not pin then
      -- Never build a frame in combat: the groups that find no free pin wait for the next draw.
      if ns.InCombat() then
        break
      end
      pin = newPin(canvas)
      pins[shown + 1] = pin
    end
    shown = shown + 1
    local nx, ny = 0, 0
    for _, item in ipairs(group.items) do
      nx, ny = nx + item.nx, ny + item.ny
    end
    group.nx, group.ny = nx / #group.items, ny / #group.items
    pin.group, pin.nx, pin.ny = group, group.nx, group.ny
    paintPin(pin, group, opts)
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "guild"))
    WML.PlacePin(pin, canvas, scale)
    pin:Show()
  end
  hidePins(shown + 1)
  if shown > 0 then
    arm()
  end
end

-- While members show, a report ages from current to old without an event: draw again every TICK seconds.
-- A client that runs a timer at once must not loop.
arm = function()
  local timer = g("C_Timer")
  if ticking or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  ticking = true
  local ok = pcall(timer.After, WMG.TICK, function()
    ticking = false
    depth = depth + 1
    if depth <= 2 and map and map:IsShown() then
      ns.Safe("wmg-tick", draw)
    end
    depth = depth - 1
  end)
  if not ok then
    ticking = false
  end
end

WMG.Refresh = ns.Wrap("wmg-refresh", draw)

-- Zoom and canvas size change which members lie close together: draw again, the data is local.
local function rescale()
  WMG.Refresh()
end

-- Number of shown pins.
function WMG.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.group then
      n = n + 1
    end
  end
  return n
end

-- WML.HookMethod queues the work for the next frame, when the map already reports its new id.
local function hookMethod(name, fn)
  hooked[name] = WML.HookMethod("guild", name, fn) or hooked[name]
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WMG.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("guild", "OnShow", WMG.Refresh)
  hookMethod("OnMapChanged", draw)
  hookMethod("OnCanvasScaleChanged", rescale)
  hookMethod("OnCanvasSizeChanged", rescale)
  WMG.Refresh()
end

ns.On("PLAYER_LOGIN", WMG.Attach)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WMG.Attach()
  end
end)

-- New, changed, removed or expired positions (debounced by the store), a new guild list, a changed option.
ns.On("FG_GUILDMAP_UPDATE", WMG.Refresh)
ns.On("FG_GUILD_UPDATE", WMG.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.guildMap") then
    WMG.Refresh()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == "guildMap" then
    WMG.Refresh()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == "guildMap" then
    WMG.Refresh()
  end
end)
