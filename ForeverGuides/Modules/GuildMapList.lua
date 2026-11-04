-- The list "Guild members on the map": one movable, resizable window with the members that share their
-- position (ns.GuildMapStore) joined with the guild list. Columns: name, class, rank, level, zone (per
-- map) and age of the report; search, the filters of the world map (online, rank, level range from the
-- settings), a click on a header sorts. Per row: set a waypoint, whisper, invite (not in combat). It is the
-- keyboard route to what the map shows: arrows move over rows and buttons, Enter runs, Tab searches,
-- Esc closes. While receiving is off the hint with its button stands in place of the rows. Rows, search,
-- sort and keys are GuildMapListLogic; no frame is built in combat. Opened by /fg gildenkarte and by
-- GuildMapList.Open() (buttons of other pages).
local _, ns = ...
local W, L, Theme, U, K = ns.W, ns.L, ns.Theme, ns.U, ns.PageKit
local GML, GLG, Store, Consent = ns.GuildMapListLogic, ns.WorldMapGuildLogic, ns.GuildMapStore, ns.Consent

local GL = {}
ns.GuildMapList = GL

ns.AddLocale("enUS", {
  ["gml.title"] = "Guild members on the map",
  ["gml.close"] = "Close list",
  ["gml.grip"] = "Drag to resize",
  ["gml.search"] = "Search name, class, rank, zone",
  ["gml.col.name"] = "Name",
  ["gml.col.class"] = "Class",
  ["gml.col.rank"] = "Rank",
  ["gml.col.level"] = "Level",
  ["gml.col.zone"] = "Zone (map)",
  ["gml.col.age"] = "Reported",
  ["gml.sort.up"] = " ^",
  ["gml.sort.down"] = " v",
  ["gml.age.s"] = "%d s",
  ["gml.age.min"] = "%d min",
  ["gml.count"] = "%d of %d members shown",
  ["gml.hint"] = "Arrows move, Enter runs, Tab searches, Esc closes",
  ["gml.empty.noGuild"] = "You are not in a guild.",
  ["gml.empty.none"] = "No positions yet. Members show up when they share.",
  ["gml.empty.filtered"] = "No member matches search and filters.",
  ["gml.combat"] = "Open the list after combat.",
})
ns.AddLocale("deDE", {
  ["gml.title"] = "Gildenmitglieder auf der Karte",
  ["gml.close"] = "Liste schließen",
  ["gml.grip"] = "Zum Ändern der Größe ziehen",
  ["gml.search"] = "Name, Klasse, Rang, Zone suchen",
  ["gml.col.name"] = "Name",
  ["gml.col.class"] = "Klasse",
  ["gml.col.rank"] = "Rang",
  ["gml.col.level"] = "Stufe",
  ["gml.col.zone"] = "Zone (Karte)",
  ["gml.col.age"] = "Gemeldet",
  ["gml.sort.up"] = " ^",
  ["gml.sort.down"] = " v",
  ["gml.age.s"] = "%d s",
  ["gml.age.min"] = "%d min",
  ["gml.count"] = "%d von %d Mitgliedern gezeigt",
  ["gml.hint"] = "Pfeile bewegen, Eingabe führt aus, Tab sucht, Esc schließt",
  ["gml.empty.noGuild"] = "Du bist in keiner Gilde.",
  ["gml.empty.none"] = "Noch keine Positionen. Mitglieder erscheinen, sobald sie teilen.",
  ["gml.empty.filtered"] = "Kein Mitglied passt zu Suche und Filtern.",
  ["gml.combat"] = "Öffne die Liste nach dem Kampf.",
})

local HEAD_H, PAD, GAP = 22, 8, 6
local MIN_W, MIN_H, MAX_W, MAX_H = 520, 320, 1100, 900
local DEFAULT_W, DEFAULT_H = 700, 420
local ACTION, ACTION_GAP, LIST_RESERVE = 22, 4, 12
local ACTIONS_W = #GML.ACTIONS * ACTION + (#GML.ACTIONS - 1) * ACTION_GAP + GAP
local ONLINE_W, RANK_W, SEARCH_MIN = 130, 150, 120
local ICON = { waypoint = "marker", whisper = "share", invite = "plus" }
-- The list is redrawn this often while it shows (a report ages without an event).
GL.TICK = 5
GL.MIN_W, GL.MIN_H, GL.MAX_W, GL.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H
GL.ACTIONS_W = ACTIONS_W

local frame
local state = { sort = "name", desc = false, text = "", built = 0, pending = false, rows = {} }
local ticking, depth = false, 0

local function g(name)
  return rawget(_G, name)
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.guildMapList) ~= "table" then
    frames.guildMapList = {}
  end
  return frames.guildMapList
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function receiving()
  return Consent.Allows("guildMap", "receive", "guild")
end

-- Data ---------------------------------------------------------------------------------------------

local function mapName(id)
  local api = g("C_Map")
  if type(api) == "table" and type(api.GetMapInfo) == "function" then
    local ok, info = pcall(api.GetMapInfo, id)
    if ok and type(info) == "table" and type(info.name) == "string" then
      return info.name
    end
  end
end

-- rows (searched and sorted), entries (all received positions), inGuild.
function GL.Collect()
  local snap = ns.GuildData.Get()
  local entries = Store.All()
  local rows = GML.Rows(entries, snap and snap.members, GLG.Current(), {
    me = ns.PlayerName.Self(),
    className = ns.GuildKit.ClassName,
    mapName = mapName,
  })
  rows = GML.Search(rows, state.text)
  GML.Sort(rows, state.sort, state.desc)
  return rows, #entries, snap ~= nil and snap.inGuild == true
end

-- Actions ------------------------------------------------------------------------------------------

local function inviteBlock(row)
  return ns.Invites.GroupInviteBlock(row.name, row.guid, row.online == false)
end

function GL.RunAction(row, id)
  if id == "waypoint" then
    local map, x, y, title = GML.Target(row)
    local wp = ns.Waypoints.Set({ map = map, x = x, y = y, title = title, source = "map" })
    if wp then
      ns.Notify(string.format(L["wp.activated"], wp.title), "info")
    end
  elseif id == "whisper" then
    ns.GuildKit.Whisper(row.name)
  elseif id == "invite" then
    ns.Invites.InviteToGroup(row.name, row.guid, row.online == false)
  end
end

-- Rows ---------------------------------------------------------------------------------------------

local function showRowTip(row)
  local data = row.data
  if not data then
    return
  end
  local lines = GML.TipLines(data, L, function(kind, text)
    return Theme.hexText(kind == "warning" and "warning" or "textMuted", text)
  end)
  ns.ShowTooltip(row, ns.GuildKit.ColoredName(data.short, data.class), table.concat(lines, "\n"))
end

local function showInviteTip(button, row)
  local reason = row.data and inviteBlock(row.data)
  if reason then
    ns.ShowTooltip(button, L["wm.guild.menu.invite"], L["invite.why." .. reason] or reason)
  else
    ns.ShowTooltip(button, L["wm.guild.menu.invite"])
  end
end

local function layoutRow(row, width)
  local cols = GML.Layout(width - PAD, ACTIONS_W, Theme.fontScale())
  local shown = {}
  for _, c in ipairs(cols) do
    local cell = row.cells[c.id]
    shown[c.id] = true
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", row, "LEFT", PAD / 2 + c.x, 0)
    cell:SetWidth(c.w)
    cell:Show()
  end
  for id, cell in pairs(row.cells) do
    if not shown[id] then
      cell:Hide()
    end
  end
  for i, b in ipairs(row.buttons) do
    b:ClearAllPoints()
    b:SetPoint("RIGHT", row, "RIGHT", -(PAD / 2) - (#row.buttons - i) * (ACTION + ACTION_GAP), 0)
  end
  return K.scaledHeight(ACTION + 4)
end

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  state.built = state.built + 1
  state.rows[state.built] = row
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.cells = {}
  for _, id in ipairs(GML.COLUMNS) do
    local cell = W.Text(row, { role = "ui", color = "text", justify = id == "level" and "RIGHT" or "LEFT" })
    cell:SetWordWrap(false)
    row.cells[id] = cell
  end
  row.buttons = {}
  for i, id in ipairs(GML.ACTIONS) do
    local b = W.Action(row, {
      icon = ICON[id],
      size = ACTION,
      tooltip = "wm.guild.menu." .. id,
      wrap = "gml-action",
      onClick = function()
        if row.data then
          GL.RunAction(row.data, id)
        end
      end,
    })
    b.fgId = "gml-" .. id
    row.buttons[i] = b
  end
  local invite = row.buttons[3]
  invite:HookScript("OnEnter", function(self)
    showInviteTip(self, row)
  end)
  invite.fgOnFocus = function(self)
    showInviteTip(self, row)
  end
  invite.fgOnBlur = ns.HideTooltip
  -- Enter on the row itself sets the waypoint; a click only selects it.
  ns.Focus.register(row, function()
    if row.data then
      GL.RunAction(row.data, "waypoint")
    end
  end)
  row.fgOnFocus = function()
    showRowTip(row)
  end
  row.fgOnBlur = ns.HideTooltip
  row:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(Theme.color("surface2", 0.6))
    showRowTip(self)
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0, 0, 0, 0)
    ns.HideTooltip()
  end)
  row:SetScript("OnClick", function(self)
    ns.Focus.set(self)
  end)
  row.fgLayout = layoutRow
  return row
end

local function paintRow(row, data)
  row.data = data
  for _, id in ipairs(GML.COLUMNS) do
    local text = GML.Cell(data, id, L)
    if id == "name" then
      text = ns.GuildKit.ColoredName(text, data.class)
    end
    row.cells[id]:SetText(text)
  end
  local block = inviteBlock(data)
  for i, a in ipairs(GML.ActionState(data, block)) do
    row.buttons[i]:SetEnabled(a.enabled)
  end
  row.bg:SetColorTexture(0, 0, 0, 0)
  row:SetAlpha(data.state == "current" and 1 or 0.75)
end

-- Header --------------------------------------------------------------------------------------------

local function headerLabel(id)
  local text = L["gml.col." .. id]
  if id == state.sort then
    text = text .. L[state.desc and "gml.sort.down" or "gml.sort.up"]
  end
  return text
end

local function sortBy(id)
  state.sort, state.desc = GML.NextSort(state.sort, state.desc, id)
  GL.Refresh()
end

local function newHeader(parent)
  local header = CreateFrame("Frame", nil, parent)
  header.buttons = {}
  for _, id in ipairs(GML.COLUMNS) do
    local b = W.Button(header, {
      text = "",
      variant = "ghost",
      height = K.scaledHeight(24),
      wrap = "gml-sort",
      onClick = function()
        sortBy(id)
      end,
    })
    b.label:SetJustifyH(id == "level" and "RIGHT" or "LEFT")
    b.fgId = "gml-sort-" .. id
    header.buttons[id] = b
  end
  function header:Layout(width)
    local cols = GML.Layout(width - PAD, ACTIONS_W, Theme.fontScale())
    local shown = {}
    for _, c in ipairs(cols) do
      local b = self.buttons[c.id]
      shown[c.id] = true
      b:ClearAllPoints()
      b:SetPoint("LEFT", self, "LEFT", PAD / 2 + c.x - 4, 0)
      b:SetWidth(c.w + 4)
      b:Show()
    end
    for id, b in pairs(self.buttons) do
      if not shown[id] then
        b:Hide()
      end
      W.SetText(b.label, nil, headerLabel(id))
    end
    self.cols = cols
  end
  return header
end

-- Window --------------------------------------------------------------------------------------------

local function setBounds(f)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetSize(
    U.clamp(finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W),
    U.clamp(finite(db.h) and db.h or DEFAULT_H, MIN_H, MAX_H)
  )
  f:ClearAllPoints()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
  end
end

local function save(f)
  local db = frameDb()
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    db.x, db.y = left, top
  end
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

-- Frame of the cursor { row, col } of GuildMapListLogic.Navigate, nil when there is none.
local function cursorFrame(f, row, col)
  if row == 0 then
    return f.header.buttons[GML.COLUMNS[col]]
  end
  local r = row <= (f.shownRows or 0) and state.rows[row] or nil
  if not r then
    return nil
  end
  return col == 0 and r or r.buttons[col]
end

local function focusCursor(f, row, col)
  local target = cursorFrame(f, row, col)
  if target then
    f.cursor = { row = row, col = col }
    ns.Focus.set(target)
  end
end

-- True while the cursor frame still has the focus ring (a click or Tab elsewhere ends it).
local function cursorActive(f)
  local c = f.cursor
  return c ~= nil and cursorFrame(f, c.row, c.col) == ns.Focus.current and ns.Focus.current ~= nil
end

local function handleKey(f, key)
  if key == "ESCAPE" then
    return ns.EscStack.Close(f)
  end
  if not (cursorActive(f) or f:IsMouseOver()) then
    return false
  end
  if key == "TAB" then
    f.search.edit:SetFocus()
    return true
  end
  local count = f.shownRows or 0
  if key == "ENTER" or key == "NUMPADENTER" or key == "SPACE" then
    if not cursorActive(f) then
      return false
    end
    local action, id = GML.Activate(f.cursor.row, f.cursor.col)
    if action == "sort" then
      sortBy(id)
      focusCursor(f, 0, f.cursor.col)
    else
      ns.Focus.activate()
    end
    return true
  end
  local row, col
  if cursorActive(f) then
    row, col = GML.Navigate(f.cursor.row, f.cursor.col, key, count)
  elseif GML.Navigate(0, 1, key, count) then
    row, col = count > 0 and 1 or 0, count > 0 and 0 or 1
  end
  if not row then
    return false
  end
  focusCursor(f, row, col)
  return true
end

-- Places the parts for the window size and lays the rows out.
local function layout(f)
  local width = f.content:GetWidth()
  if not finite(width) or width <= 0 then
    width = (f:GetWidth() or MIN_W) - 2 * PAD
  end
  local y = 0
  local banner = f.banner:Update(true)
  f.banner:ClearAllPoints()
  f.banner:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
  f.banner:SetWidth(width)
  if banner then
    y = f.banner:Fit(width) + GAP
  end
  local rowY = y
  f.search:ClearAllPoints()
  f.search:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -rowY)
  f.search:SetWidth(math.max(SEARCH_MIN, width - ONLINE_W - RANK_W - 2 * GAP))
  f.online:ClearAllPoints()
  f.online:SetPoint("LEFT", f.search, "RIGHT", GAP, 0)
  f.online:SetWidth(ONLINE_W)
  f.rank:ClearAllPoints()
  f.rank:SetPoint("LEFT", f.online, "RIGHT", GAP, 0)
  f.rank.button:SetWidth(RANK_W)
  f.rank:SetWidth(RANK_W)
  y = y + f.search:GetHeight() + GAP
  f.header:ClearAllPoints()
  f.header:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
  f.header:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -LIST_RESERVE, -y)
  f.header:SetHeight(K.scaledHeight(24))
  f.header:Layout(width - LIST_RESERVE)
  f.hint:SetWidth(width)
  f.footer:SetWidth(width)
  f.host:ClearAllPoints()
  f.host:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(y + f.header:GetHeight() + 2))
  f.host:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", 0, GAP)
  f.stack:Layout()
end

-- The rows for the data now. In combat only the rows that exist are drawn (no frame is built); the rest
-- follows after the fight.
function GL.Refresh()
  local f = frame
  if not (f and f:IsShown()) then
    return
  end
  local rows, total, inGuild = GL.Collect()
  local recv = receiving()
  if ns.InCombat() and #rows > state.built then
    for i = #rows, state.built + 1, -1 do
      rows[i] = nil
    end
    state.pending = true
  end
  f.shownRows = #rows
  f.pool:Sync(rows, paintRow)
  local reason = GML.EmptyReason(recv, inGuild, total, #rows)
  f.empty:SetText(reason and reason ~= "off" and L["gml.empty." .. reason] or "")
  f.empty:SetShown(reason ~= nil and reason ~= "off")
  f.pool:SetShown(#rows > 0)
  f.footer:SetText(recv and string.format(L["gml.count"], #rows, total) or "")
  f.online:Refresh()
  ns.WorldMapGuildTab.FillRanks(f.rankOptions)
  f.rank:Refresh()
  layout(f)
  if f.cursor and not cursorFrame(f, f.cursor.row, f.cursor.col) then
    f.cursor = nil
  end
end

local function create()
  local f = CreateFrame("Frame", "FGGuildMapList", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  ns.Bind(f, function()
    f.bg:SetColorTexture(Theme.color("bg", 0.96))
  end)
  f.shell = ns.WindowShell.Attach(f, { title = "gml.title", titleHeight = HEAD_H, shadow = true })
  f.bar, f.title = f.shell.titleBar, f.shell.titleText
  f.bar:HookScript(
    "OnDragStop",
    ns.Wrap("gml-move", function()
      f:StopMovingOrSizing()
      save(f)
    end)
  )
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "gml.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("gml-close", function()
      f:Hide()
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.close, "LEFT", -4, 0)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", PAD, -(HEAD_H + 6))
  content:SetPoint("BOTTOMRIGHT", -PAD, 16)
  f.content = content

  f.banner = ns.OptInNotice.Banner(content, {
    fn = "guildMap",
    dir = "receive",
    aud = "guild",
    textKey = "wm.guild.needRecv",
    onChanged = function()
      GL.Refresh()
    end,
  })
  f.search = W.EditBox(content, { placeholder = "gml.search", clear = true, height = 26 })
  local edit = f.search.edit
  edit:HookScript(
    "OnTextChanged",
    ns.Wrap("gml-search", function()
      local text = edit:GetText() or ""
      if text ~= state.text then
        state.text = text
        GL.Refresh()
      end
    end)
  )
  edit:HookScript("OnEscapePressed", function()
    edit:SetText("")
  end)
  local function leaveSearch()
    edit:ClearFocus()
    focusCursor(f, (f.shownRows or 0) > 0 and 1 or 0, (f.shownRows or 0) > 0 and 0 or 1)
  end
  edit:HookScript("OnEnterPressed", leaveSearch)
  edit:HookScript("OnTabPressed", leaveSearch)

  f.online = W.Checkbox(content, {
    key = "wm.guild.online",
    tooltip = "wm.guild.online",
    tooltipText = "wm.guild.onlineTip",
    get = function()
      return GLG.Current().onlineOnly
    end,
    set = function(v)
      ns.Store.set("settings." .. GLG.SPEC.onlineOnly[1], v and true or false)
    end,
  })
  f.online.fgId = "gml-online"
  f.rankOptions = {}
  ns.WorldMapGuildTab.FillRanks(f.rankOptions)
  f.rank = W.Dropdown(content, {
    key = "wm.guild.rank",
    compact = true,
    width = RANK_W,
    options = f.rankOptions,
    get = function()
      return GLG.Current().rankFilter
    end,
    set = function(v)
      ns.Store.set("settings." .. GLG.SPEC.rankFilter[1], v)
    end,
  })
  f.rank.fgId = "gml-rank"

  f.header = newHeader(content)
  f.hint = W.Text(content, { key = "gml.hint", role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("BOTTOMLEFT", 0, 0)
  f.footer = W.Text(content, { role = "ui", color = "textSecondary", wrap = true })
  f.footer:SetPoint("BOTTOMLEFT", f.hint, "TOPLEFT", 0, 2)

  f.host = CreateFrame("Frame", nil, content)
  local area = W.ScrollArea(f.host)
  area:SetAllPoints()
  f.stack = W.Stack(area, 0)
  f.pool = K.RowPool(area.content, newRow)
  f.stack:Add(f.pool, { gap = 0 })
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(f.stack, 0.05, function()
      f.stack:Layout()
    end)
  end)
  f.empty = W.Text(f.host, { role = "ui", color = "textMuted", justify = "CENTER", wrap = true })
  f.empty:SetPoint("TOPLEFT", 0, -12)
  f.empty:SetPoint("TOPRIGHT", 0, -12)
  f.empty:Hide()
  content:SetScript("OnSizeChanged", function()
    if f:IsShown() then
      layout(f)
    end
  end)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("gml-size", function()
      f:StopMovingOrSizing()
      save(f)
      GL.Refresh()
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["gml.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)
  f.grip = grip

  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = ns.Safe("gml-key", handleKey, self, key)
    ns.PropagateKeys(self, not handled)
  end)
  f:SetScript(
    "OnShow",
    ns.Wrap("gml-show", function()
      ns.WindowShell.SetEsc(f, true)
      GL.Refresh()
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("gml-hide", function()
      ns.WindowShell.SetEsc(f, false)
      f.search.edit:ClearFocus()
      f.cursor = nil
    end)
  )
  f:Hide()
  return f
end

-- Redraw while the list shows: a report ages without an event. A client that runs a timer at once must
-- not loop.
local function arm()
  local timer = g("C_Timer")
  if ticking or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  ticking = true
  local ok = pcall(timer.After, GL.TICK, function()
    ticking = false
    depth = depth + 1
    if depth <= 2 and frame and frame:IsShown() then
      ns.Safe("gml-tick", GL.Refresh)
      arm()
    end
    depth = depth - 1
  end)
  if not ok then
    ticking = false
  end
end

function GL.IsShown()
  return frame ~= nil and frame:IsShown()
end

function GL.Frame()
  return frame
end

-- Opens the list (builds it once, not in combat) and brings it to the front.
function GL.Open()
  if not ns.db then
    return false
  end
  if not frame then
    if ns.InCombat() then
      ns.Notify(L["gml.combat"], "warning")
      return false
    end
    frame = create()
  end
  place(frame)
  if frame:IsShown() then
    GL.Refresh()
  else
    frame:Show()
    -- The keyboard works at once: the ring starts on the first row.
    local count = frame.shownRows or 0
    focusCursor(frame, count > 0 and 1 or 0, count > 0 and 0 or 1)
  end
  frame:Raise()
  arm()
  return true
end

function GL.Hide()
  if frame then
    frame:Hide()
  end
end

function GL.Toggle()
  if GL.IsShown() then
    GL.Hide()
  else
    GL.Open()
  end
end

-- /fg gildenkarte: opens or closes the list.
function GL.Slash()
  GL.Toggle()
end

local function follow()
  if frame and frame:IsShown() then
    GL.Refresh()
  end
end

ns.On("FG_GUILDMAP_UPDATE", follow)
ns.On("FG_GUILD_UPDATE", follow)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.guildMap") then
    follow()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == "guildMap" then
    follow()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == "guildMap" then
    follow()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if state.pending then
    state.pending = false
    follow()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    save(frame)
  end
end)
