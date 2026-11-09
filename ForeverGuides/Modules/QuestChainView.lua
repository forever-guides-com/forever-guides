-- Quests tab of the instances page: the quests of the instance grouped by faction (Alliance, Horde, both) with a
-- faction filter. Per group the dungeon quests come first (the quests that start, end or lead on inside the
-- instance), the quests that only lead on to another quest follow under a toggle. A click on a quest opens its
-- chain in Modules/QuestChainWindow.lua. The rules are in Modules/QuestChainLogic.lua.
-- All frames of the list (group heads, toggles, quests) come from one pool in display order, so the keyboard
-- order of the pooled frames always follows the page. A head is disabled and no stop of the keyboard.
local _, ns = ...
local W, L, Theme, R, QC, QW = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.QuestChainLogic, ns.QuestChainWindow

ns.AddLocale("enUS", {
  ["questchain.filter.label"] = "Faction",
  ["questchain.filter.all"] = "All",
  ["questchain.filter.tip"] = "Shows only the quests of this faction.",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Prerequisite quests (%d)",
  ["questchain.pre.hint"] = "Quests that only lead on to another quest of this list.",
  ["questchain.chainLen"] = "chain of %d steps",
  ["questchain.empty"] = "No quest matches this filter.",
  ["questchain.openTip"] = "Opens the chain of prequests with waypoints and map.",
  ["questchain.reward"] = "Reward: %s",
})

ns.AddLocale("deDE", {
  ["questchain.filter.label"] = "Fraktion",
  ["questchain.filter.all"] = "Alle",
  ["questchain.filter.tip"] = "Zeigt nur die Quests dieser Fraktion.",
  ["questchain.group.count"] = "%s (%d)",
  ["questchain.pre.toggle"] = "Vorquests (%d)",
  ["questchain.pre.hint"] = "Quests, die nur zu einer anderen Quest dieser Liste führen.",
  ["questchain.chainLen"] = "Reihe mit %d Schritten",
  ["questchain.empty"] = "Keine Quest passt zu diesem Filter.",
  ["questchain.openTip"] = "Öffnet die Reihe der Vorquests mit Marker und Karte.",
  ["questchain.reward"] = "Belohnung: %s",
})

local QV = {}
ns.QuestChainView = QV

local PAD = 8
local INDENT = 14

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

-- One-line reward text of a quest (experience is in the numbers line).
local function rewardText(q)
  local names = {}
  for _, r in ipairs(q.rw or {}) do
    local label = r.n or ("#" .. tostring(r.id))
    if r.c and r.c > 1 then
      label = r.c .. "x " .. label
    end
    if r.ch then
      label = label .. " (" .. L["instances.quest.choice"] .. ")"
    end
    names[#names + 1] = label
  end
  return #names > 0 and string.format(L["questchain.reward"], table.concat(names, ", ")) or nil
end

-- Texts of one list entry: { title, meta, giver, extra }.
function QV.Describe(entry, inst, chainLength)
  local text = QW.Describe(entry, inst, { listRow = true })
  local meta = text.meta
  if chainLength and chainLength > 1 then
    meta = meta .. " · " .. string.format(L["questchain.chainLen"], chainLength)
  end
  local extra = {}
  local reward = rewardText(entry.quest)
  if reward then
    extra[#extra + 1] = reward
  end
  if ns.InstanceGaps and ns.InstanceGaps.QuestWeak(entry.quest) then
    extra[#extra + 1] = Theme.hexText("warning", L["instances.quest.weak"])
  end
  return { title = text.title, meta = meta, giver = text.giver, extra = table.concat(extra, "\n") }
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
  ns.Bind(e, function()
    e.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
    e.bg:SetColorTexture(Theme.color("surface", e.fgMode == "head" and 1 or 0))
  end)
  e.chevron = ns.IconDraw.new(e, 12)
  e.title = W.Text(e, { role = "ui", color = "accent2", wrap = true })
  e.meta = W.Text(e, { role = "ui", color = "textSecondary", wrap = true })
  e.giver = W.Text(e, { role = "ui", color = "textSecondary", wrap = true })
  e.extra = W.Text(e, { role = "micro", color = "textMuted", wrap = true })
  e.actions = W.MapActionButtons(e)

  e:SetScript(
    "OnClick",
    ns.Wrap("questchain-entry", function(self)
      view:Activate(self)
    end)
  )
  local function show()
    if e.fgMode == "quest" then
      ns.ShowTooltip(e, e.label or "", L["questchain.openTip"], { hint = L["action.opensWindow"] })
    elseif e.fgMode == "toggle" then
      ns.ShowTooltip(e, e.label or "", L["questchain.pre.hint"])
    end
  end
  e:HookScript("OnEnter", show)
  e:HookScript("OnLeave", ns.HideTooltip)
  e.fgOnFocus, e.fgOnBlur = show, ns.HideTooltip
  e.fgName = function()
    return e.label
  end
  e.fgDescription = function()
    return e.fgMode == "quest" and L["action.opensWindow"] or nil
  end
  register(view, e, function(self)
    self:Click()
  end)

  function e:fgLayout(width)
    local textX = self.fgMode == "toggle" and (PAD + 12 + 8) or PAD
    local right = (self.actions:IsShown() and (self.actions:GetWidth() + 8) or 0)
    local textW = math.max(40, width - textX - PAD - right)
    self.chevron:ClearAllPoints()
    self.chevron:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(PAD + 2))
    local y = PAD
    for _, fs in ipairs({ self.title, self.meta, self.giver, self.extra }) do
      if fs:IsShown() then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        fs:SetWidth(textW)
        y = y + ceil(fs) + 2
      end
    end
    self.actions:ClearAllPoints()
    self.actions:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -PAD)
    return math.max(y + PAD - 2, self.actions:IsShown() and (PAD * 2 + self.actions:GetHeight()) or 0)
  end
  return e
end

local function paintEntry(e, item, view)
  e.fgItem, e.fgMode = item, item.kind
  e.fgGroup, e.fgEntry = item.group, item.entry
  e:SetEnabled(item.kind ~= "head")
  e.chevron:SetShown(item.kind == "toggle")
  e.actions:SetPlace(nil)
  e.meta:SetShown(false)
  e.giver:SetShown(false)
  e.extra:SetShown(false)
  e.fgExpanded = nil
  if item.kind == "head" then
    local group = item.group
    e.label = string.format(
      L["questchain.group.count"],
      L["kit.faction." .. (group.faction == "B" and "all" or group.faction)],
      group.count
    )
    e.title:SetText(QW.FactionText(group.faction) .. Theme.hexText("textMuted", string.format("  (%d)", group.count)))
    W.SetColor(e.title, "text")
    e.bg:SetColorTexture(Theme.color("surface", 1))
  elseif item.kind == "toggle" then
    local open = view:PreOpen(item.group)
    e.label = string.format(L["questchain.pre.toggle"], #item.group.pre)
    e.title:SetText(e.label)
    W.SetColor(e.title, "textSecondary")
    e.chevron:Draw(open and "chevron-down" or "chevron-right")
    e.fgExpanded = open
    e.bg:SetColorTexture(Theme.color("surface", 0))
  else
    local entry = item.entry
    local text = QV.Describe(entry, view.inst, item.chainLength)
    e.label = text.title
    e.title:SetText(text.title)
    W.SetColor(e.title, "accent2")
    e.meta:SetText(text.meta)
    e.meta:SetShown(text.meta ~= "")
    e.giver:SetText(text.giver)
    e.giver:SetShown(text.giver ~= "")
    e.extra:SetText(text.extra)
    e.extra:SetShown(text.extra ~= "")
    e.actions:SetPlace(QW.Place(entry))
    e.bg:SetColorTexture(Theme.color("surface", 0))
  end
end

-- The list. :SetInstance(inst) takes the instance (a second argument, the faction of the page, is not used: the
-- list shows every faction in its groups), .count is the number of quests of the instance (before the filter of the
-- list), .onChange(): asks the page for a layout.
function QV.Create(parent)
  local FL = ns.FlowLayout
  local f = CreateFrame("Frame", nil, parent)
  f.filter = QC.Filter(ns.db.settings.instancesQuestFilter)
  f.count = 0
  f.pool, f.used = {}, 0
  f.entries = {}
  f.open = {}

  f.label = W.Text(f, { key = "questchain.filter.label", role = "micro", color = "textMuted" })
  local defs = {}
  for _, id in ipairs(QC.FILTERS) do
    defs[#defs + 1] = {
      id = id,
      key = id == "all" and "questchain.filter.all" or ("kit.faction." .. (id == "B" and "all" or id)),
      tooltip = "questchain.filter.tip",
      width = 70,
      onClick = function()
        f:SetFilter(id)
      end,
    }
  end
  f.toolbar = FL.ButtonRow(f, defs)
  f.lastFocus = f.toolbar:GetButton("B")
  f.empty = W.Text(f, { key = "questchain.empty", role = "ui", color = "textSecondary", wrap = true })

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

  local function sync()
    f.used = 0
    local items = {}
    local groups = QC.Groups(f.all or {}, f.filter)
    f.groups = groups
    local function add(item)
      items[#items + 1] = item
    end
    for _, group in ipairs(groups.groups) do
      add({ kind = "head", group = group })
      for _, entry in ipairs(group.direct) do
        add({ kind = "quest", group = group, entry = entry, chainLength = f.lengths[entry.id], indent = 0 })
      end
      if #group.pre > 0 then
        add({ kind = "toggle", group = group, indent = 0 })
        if f:PreOpen(group) then
          for _, entry in ipairs(group.pre) do
            add({
              kind = "quest",
              group = group,
              entry = entry,
              chainLength = f.lengths[entry.id],
              indent = INDENT,
            })
          end
        end
      end
    end
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
    f.label:SetShown(#f.all > 0)
    for _, id in ipairs(QC.FILTERS) do
      f.toolbar:GetButton(id):SetSelected(id == f.filter)
    end
    f.shown = groups.shown
  end

  -- A click on a head does nothing, a toggle opens or closes its prerequisites, a quest opens its window.
  function f:Activate(frame)
    if frame.fgMode == "toggle" then
      self.open[frame.fgGroup.faction] = not self:PreOpen(frame.fgGroup)
      sync()
      if self.onChange then
        self.onChange()
      end
    elseif frame.fgMode == "quest" and self.inst then
      QW.Open(self.inst, frame.fgEntry.quest, { byId = self.byId })
    end
  end

  -- Opens or closes the prerequisite quests of every group.
  function f:ExpandPre(on)
    for _, faction in ipairs(QC.FACTIONS) do
      self.open[faction] = on == true
    end
    sync()
    if self.onChange then
      self.onChange()
    end
  end

  function f:SetFilter(id)
    self.filter = QC.Filter(id)
    ns.Store.set("settings.instancesQuestFilter", self.filter)
    sync()
    if self.onChange then
      self.onChange()
    end
  end

  function f:SetInstance(inst)
    self.inst = inst
    self.byId = inst and QC.Index(inst) or nil
    -- The list has its own faction groups and filter, so the faction of the page does not cut the list.
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
      self.label:ClearAllPoints()
      self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      y = ceil(self.label) + 4
      self.toolbar:ClearAllPoints()
      self.toolbar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.toolbar:SetWidth(width)
      y = y + self.toolbar:fgGridLayout(width) + 10
    end
    if self.empty:IsShown() then
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.empty:SetWidth(math.max(40, width))
      y = y + ceil(self.empty) + 8
    end
    for _, e in ipairs(self.entries) do
      local frame, indent = e.frame, e.indent
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self, "TOPLEFT", indent, -y)
      frame:SetWidth(width - indent)
      local h = frame:fgLayout(width - indent)
      frame:SetHeight(h)
      y = y + h
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  f.all, f.lengths = {}, {}
  return f
end
