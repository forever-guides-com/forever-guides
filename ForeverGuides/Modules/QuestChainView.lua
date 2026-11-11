-- Quests tab of the instances page: the quest list on the left, grouped by faction (Alliance, Horde, both), and the
-- detail panel of the chosen quest on the right (Modules/InstanceQuestPanel.lua). Under PANEL_MIN px the panel
-- sits under the list. Per group the dungeon quests come first (the quests that start, end or lead on inside the
-- instance), the quests that only lead on to another quest follow under a toggle. The rules are in
-- Modules/QuestChainLogic.lua.
-- All frames of the list (group heads, toggles, quests) come from one pool in display order, so the keyboard
-- order of the pooled frames always follows the page. A head is disabled and no stop of the keyboard. Up and
-- down move the focus through the list (the page does that), a focused quest is the chosen one, Enter moves the
-- focus to the panel.
local _, ns = ...
local W, L, Theme, R, K, QC, QW =
  ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.QuestChainLogic, ns.QuestChainWindow

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
})

ns.AddLocale("deDE", {
  ["questchain.filter.all"] = "Alle",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Vorquests (%d)",
  ["questchain.pre.hint"] = "Quests, die nur zu einer anderen Quest dieser Liste führen.",
  ["questchain.chainLen"] = "Reihe mit %d Schritten",
  ["questchain.empty"] = "Keine Quest passt zu diesem Filter.",
  ["questchain.openTip"] = "Öffnet die Reihe der Vorquests mit Marker und Karte.",
  ["questchain.selectTip"] = "Zeigt die Details dieser Quest.",
  ["questchain.selected"] = "Ausgewählt",
})

local QV = {}
ns.QuestChainView = QV

local PAD = 8
-- The faction switch is shared with the instance page (one choice for both).
local FILTER_PATH = "settings.instancesQuestFilter"
local INDENT = 14
local GAP = 12
local PANEL_MIN = 560
local LIST_MIN, LIST_MAX = 220, 340

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

-- Texts of one list entry: { title, meta }. The row shows the name and the quest level, the panel the rest.
function QV.Describe(entry)
  local title = entry.name ~= "" and entry.name or (entry.quest and ns.T(entry.quest.n)) or "?"
  local meta = entry.level and string.format(L["questchain.level"], entry.level) or ""
  local inside = QC.StartsInside(entry.inst, entry)
  if inside ~= nil then
    local where = L[inside and "questchain.where.inside" or "questchain.where.outside"]
    meta = meta ~= "" and (meta .. " · " .. where) or where
  end
  return { title = title, meta = meta }
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
    e.bg:SetColorTexture(Theme.color("surface", e.fgMode == "head" and 1 or 0))
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
  e.chevron = ns.IconDraw.new(e, 12)
  e.title = W.Text(e, { role = "ui", color = "accent2", wrap = true })
  e.meta = W.Text(e, { role = "ui", color = "textSecondary", wrap = true })

  e:SetScript(
    "OnClick",
    ns.Wrap("questchain-entry", function(self)
      view:Activate(self)
    end)
  )
  local function show()
    if e.fgMode == "quest" then
      view:Select(e.fgEntry)
      ns.ShowTooltip(e, e.label or "", L["questchain.selectTip"])
    elseif e.fgMode == "toggle" then
      ns.ShowTooltip(e, e.label or "", L["questchain.pre.hint"])
    end
  end
  e:HookScript("OnEnter", function()
    if e.fgMode ~= "head" then
      ns.ShowTooltip(e, e.label or "", e.fgMode == "toggle" and L["questchain.pre.hint"] or L["questchain.selectTip"])
    end
  end)
  e:HookScript("OnLeave", ns.HideTooltip)
  e.fgOnFocus, e.fgOnBlur = show, ns.HideTooltip
  e.fgName = function()
    return e.label
  end
  e.fgDescription = function()
    return e.fgSelected and L["questchain.selected"] or nil
  end
  -- Enter on a quest moves on to its panel, on a toggle it opens or closes the group.
  register(view, e, function(self)
    if self.fgMode == "quest" then
      view:Select(self.fgEntry)
      view.panel:FocusFirst()
    else
      self:Click()
    end
  end)

  function e:fgLayout(width)
    local textX = self.fgMode == "toggle" and (PAD + 12 + 8) or PAD
    local textW = math.max(40, width - textX - PAD)
    self.chevron:ClearAllPoints()
    self.chevron:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(PAD + 2))
    local y = PAD
    for _, fs in ipairs({ self.title, self.meta }) do
      if fs:IsShown() then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        fs:SetWidth(textW)
        y = y + ceil(fs) + 2
      end
    end
    return y + PAD - 2
  end
  return e
end

local function paintEntry(e, item, view)
  e.fgItem, e.fgMode = item, item.kind
  e.fgGroup, e.fgEntry = item.group, item.entry
  e:SetEnabled(item.kind ~= "head")
  e.chevron:SetShown(item.kind == "toggle")
  e.meta:SetShown(false)
  e.fgExpanded = nil
  e.fgSelected = item.kind == "quest" and view.selected == item.entry.quest or nil
  if item.kind == "head" then
    local group = item.group
    e.label = string.format(
      L["questchain.group.count"],
      L["kit.faction." .. (group.faction == "B" and "all" or group.faction)],
      group.count
    )
    e.title:SetText(QW.FactionText(group.faction) .. Theme.hexText("textMuted", string.format("  (%d)", group.count)))
    W.SetColor(e.title, "text")
  elseif item.kind == "toggle" then
    local open = view:PreOpen(item.group)
    e.label = string.format(L["questchain.pre.toggle"], #item.group.pre)
    e.title:SetText(e.label)
    W.SetColor(e.title, "textSecondary")
    e.chevron:Draw(open and "chevron-down" or "chevron-right")
    e.fgExpanded = open
  else
    local text = QV.Describe(item.entry)
    e.label = text.meta ~= "" and (text.title .. ", " .. text.meta) or text.title
    e.title:SetText(text.title)
    W.SetColor(e.title, "accent2")
    e.meta:SetText(text.meta)
    e.meta:SetShown(text.meta ~= "")
  end
  paintBackground(e)
end

-- The list and the panel. :SetInstance(inst, faction) takes the instance (the faction sets the start value of the
-- faction switch once), .count is the number of quests of the instance (before the filter of the list),
-- .onChange(): asks the page for a layout.
function QV.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.count = 0
  f.pool, f.used = {}, 0
  f.entries = {}
  f.open = {}

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

  function f:PreOpen(group)
    local state = self.open[group.faction]
    if state == nil then
      return #group.direct == 0
    end
    return state
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

  -- The groups of the filter: a faction shows its own quests and the ones of both factions.
  local function groupsFor(filter)
    local all = QC.Groups(f.all or {}, "all")
    if filter == "all" then
      return all
    end
    local keep, shown = {}, 0
    for _, group in ipairs(all.groups) do
      if group.faction == filter or group.faction == "B" then
        keep[#keep + 1] = group
        shown = shown + group.count
      end
    end
    all.groups, all.shown = keep, shown
    return all
  end

  local function firstQuest(groups)
    for _, group in ipairs(groups.groups) do
      if group.direct[1] or group.pre[1] then
        return (group.direct[1] or group.pre[1]).quest
      end
    end
  end

  local function context()
    return {
      inst = f.inst,
      chainLength = f.selectedEntry and f.lengths[f.selectedEntry.id or 0] or 1,
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
    }
  end

  local function sync()
    f.used = 0
    local items = {}
    local groups = groupsFor(f.filter)
    f.groups = groups
    local function add(item)
      items[#items + 1] = item
    end
    for _, group in ipairs(groups.groups) do
      add({ kind = "head", group = group })
      for _, entry in ipairs(group.direct) do
        add({ kind = "quest", group = group, entry = entry, indent = 0 })
      end
      if #group.pre > 0 then
        add({ kind = "toggle", group = group, indent = 0 })
        if f:PreOpen(group) then
          for _, entry in ipairs(group.pre) do
            add({ kind = "quest", group = group, entry = entry, indent = INDENT })
          end
        end
      end
    end
    -- The chosen quest stays when it is still in the list, else the first one is chosen.
    local seen
    for _, item in ipairs(items) do
      if item.kind == "quest" and item.entry.quest == f.selected then
        seen = item.entry
      end
    end
    if not seen and f.selected then
      for _, group in ipairs(groups.groups) do
        for _, list in ipairs({ group.direct, group.pre }) do
          for _, entry in ipairs(list) do
            seen = seen or (entry.quest == f.selected and entry or nil)
          end
        end
      end
    end
    if not seen then
      f.selected = firstQuest(groups)
      for _, item in ipairs(items) do
        if item.kind == "quest" and item.entry.quest == f.selected then
          seen = item.entry
          break
        end
      end
    end
    f.selectedEntry = seen
    f.entries = {}
    for _, item in ipairs(items) do
      local frame = take()
      paintEntry(frame, item, f)
      f.entries[#f.entries + 1] = { frame = frame, indent = item.indent or 0 }
    end
    for i = f.used + 1, #f.pool do
      f.pool[i]:Hide()
    end
    f.empty:SetShown(#f.all > 0 and #items == 0)
    f.toolbar:SetShown(#f.all > 0)
    f.panel:SetShown(#f.all > 0)
    f.toolbar.Refresh()
    f.shown = groups.shown
    f.panel:SetQuest(f.selectedEntry, context())
  end

  local function changed()
    if f.onChange then
      f.onChange()
    end
  end

  -- A click on a head does nothing, a toggle opens or closes its prerequisites, a quest becomes the chosen one.
  function f:Activate(frame)
    if frame.fgMode == "toggle" then
      self.open[frame.fgGroup.faction] = not self:PreOpen(frame.fgGroup)
      sync()
      changed()
    elseif frame.fgMode == "quest" then
      self:Select(frame.fgEntry)
    end
  end

  -- Chooses a quest and shows it in the panel.
  function f:Select(entry)
    if not entry or self.selected == entry.quest then
      return
    end
    self.selected, self.selectedEntry = entry.quest, entry
    for _, e in ipairs(self.entries) do
      local frame = e.frame
      if frame.fgMode == "quest" then
        frame.fgSelected = frame.fgEntry.quest == entry.quest or nil
        paintBackground(frame)
      end
    end
    self.panel:SetQuest(entry, context())
    changed()
  end

  -- A link of the panel: a quest of this instance is chosen (the filter and the folded group open for it), a
  -- quest of another instance opens its chain window.
  function f:Go(ref)
    if ref.kind ~= "select" then
      QW.Open(ref.inst, ref.quest, { byId = self.byId })
      return
    end
    local target
    for _, entry in ipairs(self.all) do
      if entry.quest == ref.quest then
        target = entry
      end
    end
    if not target then
      return
    end
    if self.filter ~= "all" and target.faction ~= "B" and target.faction ~= self.filter then
      self.filter = "all"
      ns.Store.set(FILTER_PATH, "all")
    end
    if not target.direct then
      self.open[target.faction] = true
    end
    self.selected = target.quest
    sync()
    changed()
  end

  -- Opens or closes the prerequisite quests of every group.
  function f:ExpandPre(on)
    for _, faction in ipairs(QC.FACTIONS) do
      self.open[faction] = on == true
    end
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
    self.lengths = {}
    for _, entry in ipairs(self.all) do
      self.lengths[entry.id or 0] = #QC.Chain(inst, entry.quest, { byId = self.byId }).steps
    end
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
      local frame, indent = e.frame, e.indent
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self, "TOPLEFT", indent, -y)
      frame:SetWidth(listW - indent)
      local h = frame:fgLayout(listW - indent)
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

  f.all, f.lengths = {}, {}
  return f
end
