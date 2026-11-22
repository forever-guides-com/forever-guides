-- Quests tab of the instances page: the quest list on the left (boxed two-line rows: the title in the color of its
-- state, a muted line with level, faction, kind, start place and chain, map, waypoint and share icons on the
-- right) and the detail of the chosen quest on the right (Modules/InstanceQuestPanel.lua), both in a
-- K.MasterDetail: side by side from 640 px, below it one of them with a back button. Only the direct quests of the
-- instance are rows, a chain link is reached through the chain card of its quest and the chain window. The row
-- model is in Modules/QuestListLogic.lua, the chains in Modules/QuestChainLogic.lua.
-- Up and down move the focus through the list (the page does that), a focused quest is the chosen one, Enter moves
-- the focus to the detail.
local _, ns = ...
local W, L, Theme, R, K, QC, QW, QL =
  ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.QuestChainLogic, ns.QuestChainWindow, ns.QuestListLogic

ns.AddLocale("enUS", {
  ["questchain.filter.all"] = "All",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Prerequisite quests (%d)",
  ["questchain.pre.hint"] = "Quests that only lead on to another quest of this list.",
  ["questchain.chainLen"] = "chain of %d steps",
  ["questchain.empty"] = "No quest matches this filter.",
  ["questchain.openTip"] = "Opens the chain of prequests with waypoints and map.",
  ["questchain.selectTip"] = "Shows the details of this quest.",
  ["questchain.selected"] = "Selected",
  ["questlist.pre.one"] = "1 prequest",
  ["questlist.pre.other"] = "%d prequests",
  ["questlist.group.sparklematic"] = "%d machines",
  ["questlist.group.other"] = "%d variants",
  ["questlist.kind.dungeon"] = "Dungeon",
  ["questlist.kind.raid"] = "Raid",
  ["questlist.level"] = "Level %s",
  ["questlist.state.log"] = "In your quest log",
  ["questlist.state.done"] = "Completed",
  ["questlist.state.locked"] = "Not available yet",
  ["questlist.state.open"] = "Available",
  ["questlist.start.in"] = "Start: inside",
  ["questlist.start.out"] = "Start: outside",
  ["questlist.start.outZone"] = "Start: outside (%s)",
  ["questlist.start.zone"] = "Start: %s",
})

ns.AddLocale("deDE", {
  ["questchain.filter.all"] = "Alle",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Vorquests (%d)",
  ["questchain.pre.hint"] = "Quests, die nur zu einer anderen Quest dieser Liste führen.",
  ["questchain.chainLen"] = "Kette mit %d Schritten",
  ["questchain.empty"] = "Keine Quest passt zu diesem Filter.",
  ["questchain.openTip"] = "Öffnet die Reihe der Vorquests mit Wegpunkten und Karte.",
  ["questchain.selectTip"] = "Zeigt die Details dieser Quest.",
  ["questchain.selected"] = "Ausgewählt",
  ["questlist.pre.one"] = "1 Vorquest",
  ["questlist.pre.other"] = "%d Vorquests",
  ["questlist.group.sparklematic"] = "%d Maschinen",
  ["questlist.group.other"] = "%d Varianten",
  ["questlist.kind.dungeon"] = "Dungeon",
  ["questlist.kind.raid"] = "Raid",
  ["questlist.level"] = "Stufe %s",
  ["questlist.state.log"] = "Im Questlog",
  ["questlist.state.done"] = "Abgeschlossen",
  ["questlist.state.locked"] = "Noch nicht verfügbar",
  ["questlist.state.open"] = "Verfügbar",
  ["questlist.start.in"] = "Start: drinnen",
  ["questlist.start.out"] = "Start: draußen",
  ["questlist.start.outZone"] = "Start: draußen (%s)",
  ["questlist.start.zone"] = "Start: %s",
})

local QV = {}
ns.QuestChainView = QV

-- The faction switch is shared with the instance page (one choice for both).
local FILTER_PATH = "settings.instancesQuestFilter"
local ROW_HEIGHT = 58
local ROW_ACTION_SIZE = 20
local WIDE_FROM = 640

local function playerLevel()
  local fn = rawget(_G, "UnitLevel")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, level = pcall(fn, "player")
  level = ok and ns.AutoGuard and ns.AutoGuard.Safe(level) or nil
  return type(level) == "number" and level or nil
end

local function toHex(r, g, b)
  local function byte(v)
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
  end
  return string.format("#%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Color of a quest level as "#rrggbb": the client color of the difficulty when it has one, else the bucket of the
-- logic, lifted until it reads on the list background (AA, the level number is always written out).
function QV.LevelHex(level, bucket)
  local base = QL.COLORS[bucket or "grey"]
  local api = rawget(_G, "GetQuestDifficultyColor")
  if type(api) == "function" and type(level) == "number" then
    local ok, c = pcall(api, level)
    if ok and type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
      base = toHex(c.r, c.g, c.b)
    end
  end
  return (Theme.readable(base, Theme.hex("surface3")))
end

-- The line under a row that opens the chain: the group ("3 machines"), the chain ("Chain of 4 steps") or the
-- prequests outside the list ("2 prequests"). Nil when the row has none of them.
function QV.HintText(row)
  if row.group then
    local key = "questlist.group." .. tostring(row.entry.grp)
    return string.format(L[key] ~= key and L[key] or L["questlist.group.other"], row.group)
  elseif row.chain and row.chain > 1 then
    return (string.format(L["questchain.chainLen"], row.chain):gsub("^%l", string.upper))
  elseif row.pre > 0 then
    return row.pre == 1 and L["questlist.pre.one"] or string.format(L["questlist.pre.other"], row.pre)
  end
  return nil
end

-- Where the quest starts as a short text: "inside", "outside" with the zone, or just the zone. nil when unknown.
function QV.StartText(row)
  local zone = row.entry and row.entry.zone and ns.T(row.entry.zone)
  if zone == "" then
    zone = nil
  end
  if row.start == "out" and zone then
    return string.format(L["questlist.start.outZone"], zone)
  end
  if row.start then
    return L["questlist.start." .. row.start]
  end
  return zone and string.format(L["questlist.start.zone"], zone) or nil
end

-- State of a quest for the player: "log" (in the quest log), "done", "locked" (the player is below its minimum
-- level) or "open".
function QV.State(entry)
  local id = entry and entry.id
  local P = ns.InstanceQuestPanel
  if type(id) == "number" and P then
    if P.InLog(id) then
      return "log"
    elseif P.Done(id) then
      return "done"
    end
  end
  local avail = entry and entry.avail
  local level = playerLevel()
  if avail and avail.kind ~= "hint" and type(avail.level) == "number" and level and level < avail.level then
    return "locked"
  end
  return "open"
end

-- Look of a state: the token of the title color and the status dot (a shape of its own, so the word and the
-- shape carry the state, not the color). The dot has no look for "open".
QV.STATES = {
  log = { token = "info", dot = { state = "info", shape = "ring" } },
  done = { token = "success", dot = { state = "ok", shape = "filled" } },
  locked = { token = "textMuted", dot = { state = "warn", shape = "dash" } },
  open = {},
}

-- Texts of one list row: { level (colored), title, meta (level, faction, kind, start place, chain), label (plain,
-- for the keyboard and readers), hint (the chain or prequest line, nil without one) }.
function QV.Describe(row)
  local entry = row.entry
  local title = entry.name ~= "" and entry.name or (entry.quest and ns.T(entry.quest.n)) or "?"
  local number = row.level and tostring(row.level) or "-"
  local meta = {}
  if row.level then
    meta[#meta + 1] = string.format(L["questlist.level"], row.level)
  end
  if row.faction then
    meta[#meta + 1] = L["kit.faction." .. row.faction]
  end
  meta[#meta + 1] = L["questlist.kind." .. row.kind]
  local start = QV.StartText(row)
  if start then
    meta[#meta + 1] = start
  end
  if row.repeatable then
    meta[#meta + 1] = L["questchain.repeatable"]
  end
  -- The row shows the class with icon and color, readers and the keyboard name get the plain words.
  local classPlain = QW.ClassPlain(row.class)
  local classAt
  if classPlain then
    meta[#meta + 1] = classPlain
    classAt = #meta
  end
  local hint = QV.HintText(row)
  if hint then
    meta[#meta + 1] = hint
  end
  local shown = { unpack(meta) }
  if classAt then
    shown[classAt] = QW.ClassText(row.class)
  end
  local state = QV.State(entry)
  local plain = { title, row.level and string.format(L["questchain.level"], row.level) or nil }
  for i = (row.level and 2 or 1), #meta do
    plain[#plain + 1] = meta[i]
  end
  if state ~= "open" then
    plain[#plain + 1] = L["questlist.state." .. state]
  end
  return {
    hint = hint,
    state = state,
    level = row.level and string.format("|cff%s%s|r", QV.LevelHex(row.level, row.bucket):sub(2), number) or number,
    title = title,
    meta = table.concat(shown, " · "),
    label = table.concat(plain, ", "),
  }
end

-- Page link of a quest row: instances/<slug>/quests/<questId>, nil without an id.
function QV.SharePayload(inst, entry)
  local id = entry and entry.id
  if not (inst and type(id) == "number") then
    return nil
  end
  return "instances/" .. R.InstanceSlug(inst) .. "/quests/" .. id
end

-- "rrggbb" of the title color of a state, lifted until it reads on the row background; nil leaves the default.
local function stateHex(state)
  local token = QV.STATES[state].token
  if not token then
    return nil
  end
  return (Theme.readable(Theme.hex(token), Theme.hex("surface2")):sub(2))
end

-- The list and the detail. :SetInstance(inst, faction) takes the instance (the faction sets the start value of the
-- faction switch once), .count is the number of quests of the instance (before the filter of the list),
-- .onChange(): asks the page for a layout.
function QV.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.fgQuestView = true
  f.count = 0
  f.entries = {}

  f.toolbar = K.FactionButtons(f, {
    withAll = true,
    allKey = "questchain.filter.all",
    get = function()
      return f.filter
    end,
    set = function(id)
      f:SetFilter(id)
    end,
  })
  f.empty = W.Text(f, { key = "questchain.empty", role = "ui", color = "textSecondary", wrap = true })

  -- Rows read the chosen quest from the view, so the list can repaint itself after a choice.
  local function bind(row)
    local text = QV.Describe(row)
    local look = QV.STATES[text.state]
    return {
      title = text.title,
      titleHex = stateHex(text.state),
      sub = text.meta,
      wrapSub = true,
      dot = look.dot and { state = look.dot.state, shape = look.dot.shape, tip = L["questlist.state." .. text.state] }
        or nil,
      selected = f:Owns(row.entry),
      cursor = f:Owns(row.entry),
      tooltip = text.label,
    }
  end

  -- Moves the stops of the icons right behind their row, so Tab visits a row and then its buttons.
  local function behind(row)
    local items = ns.Focus.items
    local buttons = { row.qa.map, row.qa.marker, row.qa.share }
    for _, b in ipairs(buttons) do
      for i = #items, 1, -1 do
        if items[i] == b then
          table.remove(items, i)
        end
      end
    end
    for i, item in ipairs(items) do
      if item == row then
        for n, b in ipairs(buttons) do
          table.insert(items, i + n, b)
        end
        return
      end
    end
  end

  -- Wires the pooled row once: keyboard name, the choice on focus, Enter to the detail, the icons at its right.
  local function wire(row)
    row.qa = W.MapActionButtons(row, { size = ROW_ACTION_SIZE, share = true })
    behind(row)
    row.fgName = function()
      return row.label
    end
    row.fgDescription = function()
      return row.fgSelected and L["questchain.selected"] or nil
    end
    local focused = row.fgOnFocus
    row.fgOnFocus = function(self)
      if focused then
        focused(self)
      end
      f:Select(self.fgEntry)
    end
    row.fgActivate = function(self)
      f:Select(self.fgEntry, true)
      f.panel:FocusFirst()
    end
  end

  f.list = K.NewList(f, {
    look = "boxed",
    rowHeight = ROW_HEIGHT,
    bind = bind,
    onClick = function(row)
      f:Select(row.entry, true)
    end,
    onBindRow = function(row, item)
      if not row.qa then
        wire(row)
      end
      row.fgItem, row.fgMode, row.fgEntry = item, "quest", item.entry
      row.fgSelected = f:Owns(item.entry) or nil
      row.label = QV.Describe(item).label
      row.qa:SetPlace(item.entry and QW.Place(item.entry) or nil)
      row.qa:SetShare(QV.SharePayload(f.inst, item.entry))
      row.trailing = row.qa
    end,
  })

  f.split = K.MasterDetail(f, {
    list = f.list,
    wideFrom = WIDE_FROM,
    backKey = "instances.split.back",
    backTip = "instances.split.back.tip",
    backFit = true,
    onToggle = function(on)
      if not f.syncing then
        f.detailOpen = on
      end
    end,
    detail = function(width)
      return f.panel:fgGridLayout(width)
    end,
  })
  f.panel = ns.InstanceQuestPanel.Create(f.split.content)
  f.panel.onChange = function()
    if f.onChange then
      f.onChange()
    end
  end

  local function context()
    return {
      inst = f.inst,
      chain = f.selectedEntry and f:Chain(f.selectedEntry) or nil,
      resolve = function(id)
        return QC.Reference(f.inst, f.byId, id)
      end,
      go = function(ref)
        f:Go(ref)
      end,
      openChain = function()
        if f.selectedEntry and f.inst then
          QW.Open(f.inst, f.selectedEntry.quest, { byId = f.byId })
        end
      end,
      also = QL.OtherInstances(f.inst, f.selectedEntry and f.selectedEntry.id, ns.Data and ns.Data.Instances),
    }
  end

  local function sync()
    -- A row with follow-up steps shows its chain (the prequests are part of it), any other the prequests.
    local pre, chain = {}, {}
    for _, entry in ipairs(f.all) do
      if entry.direct then
        local info = f:Chain(entry)
        if info.after > 0 then
          chain[entry.id or 0] = #info.steps
        else
          pre[entry.id or 0] = info.before
        end
      end
    end
    local rows = QL.Rows(f.all, f.filter, { player = playerLevel(), pre = pre, chain = chain })
    f.rows = rows
    -- The chosen quest stays while its row is in the list (a follow-up step sits in the row of its head) and the
    -- faction filter lets it through, else the first row is chosen.
    local seen
    for _, entry in ipairs(f.all) do
      if entry.quest == f.selected and f:Visible(entry, rows) then
        seen = entry
      end
    end
    if not seen then
      seen = rows[1] and rows[1].entry or nil
      f.selected = seen and seen.quest or nil
    end
    f.selectedEntry = seen
    f.entries = rows
    f.list:SetData(rows)
    f.empty:SetShown(#f.all > 0 and #rows == 0)
    -- The instance page shows the faction switch in its own tab row.
    f.toolbar:SetShown(#f.all > 0 and not f.hideToolbar)
    f.split:SetShown(#rows > 0)
    f.toolbar.Refresh()
    f.shown = #rows
    f.panel:SetQuest(f.selectedEntry, context())
    -- Narrow pages stay on the list until a quest is asked for.
    f.syncing = true
    f.split:SetSelected(f.selectedEntry)
    f.split:ShowDetail(f.detailOpen == true)
    f.syncing = false
  end

  local function changed()
    if f.onChange then
      f.onChange()
    end
  end

  -- The chain of an entry (QC.Chain), built once per instance.
  function f:Chain(entry)
    local info = self.chains[entry.quest]
    if not info then
      info = QC.Chain(self.inst, entry.quest, { byId = self.byId })
      self.chains[entry.quest] = info
    end
    return info
  end

  -- True when the row of `entry` (its own, the one of its chain head, the one of its group) is in `rows` and the
  -- faction filter keeps the quest itself.
  function f:Visible(entry, rows)
    if self.filter ~= "all" and entry.faction ~= "B" and entry.faction ~= self.filter then
      return false
    end
    for _, row in ipairs(rows) do
      if self:RowOwns(row.entry, entry) then
        return true
      end
    end
    return false
  end

  -- True when `rowEntry` is the row that stands for `entry`: the entry itself, the row of its chain or of its group.
  function f:RowOwns(rowEntry, entry)
    return rowEntry == entry
      or (entry.owner ~= nil and entry.owner == rowEntry.id)
      or (entry.grp ~= nil and entry.grp == rowEntry.grp)
  end

  -- Whether the row of `rowEntry` is marked as chosen.
  function f:Owns(rowEntry)
    return self.selectedEntry ~= nil and self:RowOwns(rowEntry, self.selectedEntry)
  end

  -- Chooses a quest and shows it in the detail; `open` also leaves the list in narrow mode (a click, Enter).
  function f:Select(entry, open)
    if not entry then
      return
    end
    if open then
      self.detailOpen = true
    end
    if self.selected ~= entry.quest then
      self.selected, self.selectedEntry = entry.quest, entry
      self.list:SetData(self.rows)
      self.panel:SetQuest(entry, context())
      self.split:SetSelected(entry)
      changed()
    end
    if open then
      self.split:ShowDetail(true)
    end
  end

  -- A link of the detail: a row of this instance is chosen (the filter opens for it), a chain link or a quest of
  -- another instance opens its chain window.
  function f:Go(ref)
    local target
    if ref.kind == "select" then
      for _, entry in ipairs(self.all) do
        if (entry.quest == ref.quest or (entry.id and entry.id == ref.quest.id)) and (entry.direct or entry.step) then
          target = entry
        end
      end
    end
    if not target then
      QW.Open(ref.inst, ref.quest, { byId = self.byId })
      return
    end
    if self.filter ~= "all" and target.faction ~= "B" and target.faction ~= self.filter then
      self.filter = "all"
      ns.Store.set(FILTER_PATH, "all")
    end
    self.selected = target.quest
    self.detailOpen = true
    sync()
    changed()
  end

  -- Id of the chosen quest, nil without one.
  function f:SelectedId()
    return self.selectedEntry and self.selectedEntry.id or nil
  end

  -- Chooses a quest of this instance by its id (a page link). False when the list has no such quest.
  function f:SelectId(id)
    for _, entry in ipairs(self.all or {}) do
      if entry.id == id and (entry.direct or entry.step) then
        self:Go({ kind = "select", quest = entry.quest })
        return true
      end
    end
    return false
  end

  function f:SetFilter(id)
    self.filter = id == "A" and "A" or id == "H" and "H" or "all"
    ns.Store.set(FILTER_PATH, self.filter)
    sync()
    changed()
  end

  -- The switch of the page changed the shared choice: follow at once, also while this tab is open.
  ns.On("FG_SETTING_CHANGED", function(_, path, value)
    if path == FILTER_PATH and f.filter then
      local choice = ns.InstanceListLogic.Faction(value, K.PlayerFaction())
      if choice ~= f.filter then
        f.filter = choice
        sync()
        changed()
      end
    end
  end)

  function f:SetInstance(inst, faction)
    -- One faction choice for the page and this tab: the saved value, else the start value of the caller.
    self.filter = ns.InstanceListLogic.Faction(ns.db.settings.instancesQuestFilter, faction)
    if self.inst ~= inst then
      self.selected = nil
      self.detailOpen = false
    end
    self.inst = inst
    self.byId = inst and QC.Index(inst) or nil
    local quests = inst and R.Quests(inst, nil) or {}
    self.all = inst and QC.Entries(inst, quests) or {}
    self.chains = {}
    self.count = #self.all
    sync()
  end

  -- Esc and the back key: true when a narrow detail went back to the list.
  function f:CloseDetail()
    return self.split:IsShown() and self.split:CloseDetail()
  end

  -- room: what the page tells (top, viewHeight, pad). The shell below the faction switch fills the rest.
  function f:fgGridLayout(width, room)
    local y = 0
    if self.toolbar:IsShown() then
      self.toolbar:ClearAllPoints()
      self.toolbar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.toolbar:SetWidth(width)
      y = self.toolbar:fgGridLayout(width) + 10
    end
    if self.empty:IsShown() then
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.empty:SetWidth(math.max(40, width))
      y = y + math.ceil(self.empty:GetStringHeight()) + 8
    end
    if self.split:IsShown() then
      self.split:ClearAllPoints()
      self.split:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.split:SetWidth(width)
      local below = room and { top = room.top + y, viewHeight = room.viewHeight, pad = room.pad, gap = room.gap } or nil
      if below and room.fill then
        local fill = room.fill
        below.fill = { height = math.max(1, fill.height - y), mode = fill.mode, listW = fill.listW }
      end
      y = y + self.split:fgGridLayout(width, below)
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  f.all, f.chains = {}, {}
  return f
end
