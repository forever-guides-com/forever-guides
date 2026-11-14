-- Quests tab of the instances page: the quest list on the left like the quest log (level in the difficulty color,
-- name, faction mark, dungeon or raid label, the objectives below and a hint to the prequests) and the detail
-- panel of the chosen quest on the right (Modules/InstanceQuestPanel.lua). Under PANEL_MIN px the panel sits under
-- the list. Only the direct quests of the instance are rows, a chain link is reached through the prequest hint
-- of its quest and the chain window. The row model is in Modules/QuestListLogic.lua, the chains in
-- Modules/QuestChainLogic.lua.
-- All rows come from one pool in display order, so the keyboard order of the pooled frames always follows the
-- page. Up and down move the focus through the list (the page does that), a focused quest is the chosen one,
-- Enter moves the focus to the panel.
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
  ["questlist.start.in"] = "Start: inside",
  ["questlist.start.out"] = "Start: outside",
})

ns.AddLocale("deDE", {
  ["questchain.filter.all"] = "Alle",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Vorquests (%d)",
  ["questchain.pre.hint"] = "Quests, die nur zu einer anderen Quest dieser Liste führen.",
  ["questchain.chainLen"] = "Kette mit %d Schritten",
  ["questchain.empty"] = "Keine Quest passt zu diesem Filter.",
  ["questchain.openTip"] = "Öffnet die Reihe der Vorquests mit Marker und Karte.",
  ["questchain.selectTip"] = "Zeigt die Details dieser Quest.",
  ["questchain.selected"] = "Ausgewählt",
  ["questlist.pre.one"] = "1 Vorquest",
  ["questlist.pre.other"] = "%d Vorquests",
  ["questlist.group.sparklematic"] = "%d Maschinen",
  ["questlist.group.other"] = "%d Varianten",
  ["questlist.kind.dungeon"] = "Dungeon",
  ["questlist.kind.raid"] = "Schlachtzug",
  ["questlist.start.in"] = "Start: drinnen",
  ["questlist.start.out"] = "Start: draußen",
})

local QV = {}
ns.QuestChainView = QV

local PAD = 8
-- The faction switch is shared with the instance page (one choice for both).
local FILTER_PATH = "settings.instancesQuestFilter"
local GAP = 12
local PANEL_MIN = 560
local LIST_MIN, LIST_MAX = 220, 340
local LEVEL_W = 26

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

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

-- Texts of one list row: { level (colored), title, meta (faction, kind and where it starts), label (plain, for the keyboard and
-- readers) }.
function QV.Describe(row)
  local entry = row.entry
  local title = entry.name ~= "" and entry.name or (entry.quest and ns.T(entry.quest.n)) or "?"
  local number = row.level and tostring(row.level) or "-"
  local meta = {}
  if row.faction then
    meta[#meta + 1] = QW.FactionText(row.faction)
  end
  meta[#meta + 1] = L["questlist.kind." .. row.kind]
  if row.start then
    meta[#meta + 1] = L["questlist.start." .. row.start]
  end
  if row.repeatable then
    meta[#meta + 1] = QW.RepeatText()
  end
  local class, classPlain = QW.ClassText(row.class), QW.ClassPlain(row.class)
  if class then
    meta[#meta + 1] = class
  end
  local plain = { title, row.level and string.format(L["questchain.level"], row.level) or nil }
  if row.faction then
    plain[#plain + 1] = L["kit.faction." .. row.faction]
  end
  plain[#plain + 1] = L["questlist.kind." .. row.kind]
  if row.start then
    plain[#plain + 1] = L["questlist.start." .. row.start]
  end
  if row.repeatable then
    plain[#plain + 1] = L["questchain.repeatable"]
  end
  if classPlain then
    plain[#plain + 1] = classPlain
  end
  local hint = QV.HintText(row)
  if hint then
    plain[#plain + 1] = hint
  end
  return {
    hint = hint,
    level = row.level and string.format("|cff%s%s|r", QV.LevelHex(row.level, row.bucket):sub(2), number) or number,
    title = title,
    meta = table.concat(meta, " · "),
    label = table.concat(plain, ", "),
  }
end

-- Registers a pooled frame for Tab and the arrow keys and keeps it behind the frames of the view that came
-- before it (the pool is in display order), not at the end of the page.
local function register(view, frame, activate)
  local items = ns.Focus.items
  ns.Focus.register(frame, activate)
  table.remove(items)
  local at = #items + 1
  for i = #items, 1, -1 do
    if items[i] == view.lastFocus then
      at = i + 1
      break
    end
  end
  table.insert(items, at, frame)
  view.lastFocus = frame
end

local function paintBackground(e)
  if e.fgSelected then
    local r, g, b = Theme.color("accent2")
    e.bg:SetColorTexture(r, g, b, 0.2)
  else
    e.bg:SetColorTexture(Theme.color("surface", 0))
  end
  e.mark:SetShown(e.fgSelected == true)
end

local function makeEntry(view)
  local e = CreateFrame("Button", nil, view)
  e.bg = e:CreateTexture(nil, "BACKGROUND")
  e.bg:SetAllPoints()
  e.hover = e:CreateTexture(nil, "HIGHLIGHT")
  e.hover:SetAllPoints()
  e.hover:SetColorTexture(1, 1, 1, 0.06)
  e.line = e:CreateTexture(nil, "ARTWORK")
  e.line:SetPoint("BOTTOMLEFT")
  e.line:SetPoint("BOTTOMRIGHT")
  e.line:SetHeight(1)
  e.mark = e:CreateTexture(nil, "OVERLAY")
  e.mark:SetPoint("TOPLEFT")
  e.mark:SetPoint("BOTTOMLEFT")
  e.mark:SetWidth(3)
  ns.Bind(e, function()
    e.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
    e.mark:SetColorTexture(Theme.color("accent2"))
    paintBackground(e)
  end)
  e.level = W.Text(e, { role = "ui", color = "text" })
  e.title = W.Text(e, { role = "ui", color = "accent2", wrap = true })
  e.meta = W.Text(e, { role = "ui", color = "textSecondary", wrap = true })
  e.objectives = W.Text(e, { role = "ui", color = "textSecondary", wrap = true })
  -- The prequest hint is a button of its own inside the row (the keyboard reaches the chain through the panel).
  e.hint = CreateFrame("Button", nil, e)
  e.hint.text = W.Text(e.hint, { role = "ui", color = "accent2" })
  e.hint.text:SetPoint("LEFT", e.hint, "LEFT", 0, 0)
  e.hint:SetScript(
    "OnClick",
    ns.Wrap("questchain-prehint", function()
      if e.fgEntry and view.inst then
        QW.Open(view.inst, e.fgEntry.quest, { byId = view.byId })
      end
    end)
  )
  e.hint:SetScript("OnEnter", function()
    ns.ShowTooltip(e.hint, e.hint.text:GetText() or "", L["questchain.openTip"])
  end)
  e.hint:SetScript("OnLeave", ns.HideTooltip)

  e:SetScript(
    "OnClick",
    ns.Wrap("questchain-entry", function(self)
      view:Activate(self)
    end)
  )
  local function show()
    view:Select(e.fgEntry)
    ns.ShowTooltip(e, e.label or "", L["questchain.selectTip"])
  end
  e:HookScript("OnEnter", function()
    ns.ShowTooltip(e, e.label or "", L["questchain.selectTip"])
  end)
  e:HookScript("OnLeave", ns.HideTooltip)
  e.fgOnFocus, e.fgOnBlur = show, ns.HideTooltip
  e.fgName = function()
    return e.label
  end
  e.fgDescription = function()
    return e.fgSelected and L["questchain.selected"] or nil
  end
  -- Enter on a quest moves on to its panel.
  register(view, e, function(self)
    view:Select(self.fgEntry)
    view.panel:FocusFirst()
  end)

  function e:fgLayout(width)
    local textX = PAD + LEVEL_W
    local textW = math.max(40, width - textX - PAD)
    self.level:ClearAllPoints()
    self.level:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    local y = PAD
    local first = true
    for _, fs in ipairs({ self.title, self.meta, self.objectives }) do
      if fs:IsShown() then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        fs:SetWidth(textW)
        y = y + math.max(ceil(fs), first and ceil(self.level) or 0) + 2
        first = false
      end
    end
    if self.hint:IsShown() then
      self.hint:ClearAllPoints()
      self.hint:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      local h = ceil(self.hint.text) + 4
      self.hint:SetSize(math.min(textW, math.ceil(self.hint.text:GetStringWidth()) + 4), h)
      y = y + h
    end
    return y + PAD - 2
  end
  return e
end

local function paintEntry(e, row, view)
  e.fgItem, e.fgMode = row, "quest"
  e.fgEntry = row.entry
  e.fgSelected = view:Owns(row.entry) or nil
  local text = QV.Describe(row)
  e.label = text.label
  e.level:SetText(text.level)
  e.title:SetText(text.title)
  e.meta:SetText(text.meta)
  local lines = row.objectives
  e.objectives:SetText(table.concat(lines, "\n"))
  e.objectives:SetShown(#lines > 0)
  e.hint:SetShown(text.hint ~= nil)
  if text.hint then
    e.hint.text:SetText(text.hint)
  end
  paintBackground(e)
end

-- The list and the panel. :SetInstance(inst, faction) takes the instance (the faction sets the start value of the
-- faction switch once), .count is the number of quests of the instance (before the filter of the list),
-- .onChange(): asks the page for a layout.
function QV.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.fgQuestView = true
  f.count = 0
  f.pool, f.used = {}, 0
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
  -- The list rows follow the last button of the switch in the keyboard order.
  f.lastFocus = ns.Focus.items[#ns.Focus.items]
  f.empty = W.Text(f, { key = "questchain.empty", role = "ui", color = "textSecondary", wrap = true })
  f.panel = ns.InstanceQuestPanel.Create(f)
  f.panel.onChange = function()
    if f.onChange then
      f.onChange()
    end
  end

  local function take()
    f.used = f.used + 1
    local frame = f.pool[f.used]
    if not frame then
      frame = makeEntry(f)
      f.pool[f.used] = frame
    end
    frame:Show()
    return frame
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

  local function objectiveText(entry)
    local live = ns.InstanceQuestPanel.Goal(entry.id)
    if live then
      return live
    end
    local _, goal = ns.QuestText.Get(entry.id)
    return goal
  end

  local function sync()
    f.used = 0
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
    local rows = QL.Rows(f.all, f.filter, { player = playerLevel(), pre = pre, chain = chain, text = objectiveText })
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
    f.entries = {}
    for _, row in ipairs(rows) do
      local frame = take()
      paintEntry(frame, row, f)
      f.entries[#f.entries + 1] = { frame = frame }
    end
    for i = f.used + 1, #f.pool do
      f.pool[i]:Hide()
    end
    f.empty:SetShown(#f.all > 0 and #rows == 0)
    f.toolbar:SetShown(#f.all > 0)
    f.panel:SetShown(#f.all > 0)
    f.toolbar.Refresh()
    f.shown = #rows
    f.panel:SetQuest(f.selectedEntry, context())
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

  -- A click on a row makes its quest the chosen one.
  function f:Activate(frame)
    self:Select(frame.fgEntry)
  end

  -- Chooses a quest and shows it in the panel.
  function f:Select(entry)
    if not entry or self.selected == entry.quest then
      return
    end
    self.selected, self.selectedEntry = entry.quest, entry
    for _, e in ipairs(self.entries) do
      local frame = e.frame
      frame.fgSelected = self:Owns(frame.fgEntry) or nil
      paintBackground(frame)
    end
    self.panel:SetQuest(entry, context())
    changed()
  end

  -- A link of the panel: a row of this instance is chosen (the filter opens for it), a chain link or a quest of
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
    sync()
    changed()
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
    end
    self.inst = inst
    self.byId = inst and QC.Index(inst) or nil
    local quests = inst and R.Quests(inst, nil) or {}
    self.all = inst and QC.Entries(inst, quests) or {}
    self.chains = {}
    self.count = #self.all
    sync()
  end

  function f:fgGridLayout(width)
    local y = 0
    if self.toolbar:IsShown() then
      self.toolbar:ClearAllPoints()
      self.toolbar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.toolbar:SetWidth(width)
      y = self.toolbar:fgGridLayout(width) + 10
    end
    local wide = width >= PANEL_MIN
    local listW = wide and math.min(LIST_MAX, math.max(LIST_MIN, math.floor(width * 0.38))) or width
    local top = y
    if self.empty:IsShown() then
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.empty:SetWidth(math.max(40, listW))
      y = y + ceil(self.empty) + 8
    end
    for _, e in ipairs(self.entries) do
      local frame = e.frame
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      frame:SetWidth(listW)
      local h = frame:fgLayout(listW)
      frame:SetHeight(h)
      y = y + h
    end
    if self.panel:IsShown() then
      local panelW = wide and (width - listW - GAP) or width
      local px, py = wide and (listW + GAP) or 0, wide and top or (y + GAP)
      self.panel:ClearAllPoints()
      self.panel:SetPoint("TOPLEFT", self, "TOPLEFT", px, -py)
      self.panel:SetWidth(panelW)
      local ph = self.panel:fgGridLayout(panelW)
      y = wide and math.max(y, py + ph) or (py + ph)
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  f.all, f.chains = {}, {}
  return f
end
