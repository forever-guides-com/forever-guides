-- Items tab of the instances page: the loot of an instance by boss (list and detail, Modules/InstanceBossView.lua,
-- the first boss chosen at the start) or as one list with the boss beside each item. Rules and data
-- merging are in Modules/InstanceItemsLogic.lua. The rows of the list come from a pool and a page Stack holds
-- the view through fgGridLayout(width).
local _, ns = ...
local W, L, Theme, R, IV, IL = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.InstanceView, ns.InstanceItemsLogic
local LR, BV = ns.InstanceLootRow, ns.InstanceBossView

ns.AddLocale("enUS", {
  ["instances.items.view.boss"] = "By boss",
  ["instances.items.view.all"] = "All items",
  ["instances.items.col.item"] = "Item",
  ["instances.items.col.boss"] = "Boss",
  ["instances.items.sort.item"] = "Sort by item",
  ["instances.items.sort.boss"] = "Sort by boss",
  ["instances.items.count.one"] = "1 item",
  ["instances.items.count.other"] = "%d items",
  ["instances.items.bossNone"] = "Loot not recorded yet",
  ["instances.items.bossHint"] = "Loot is added when you record or export it.",
  ["instances.items.group.instance"] = "More loot of the instance",
  ["instances.items.group.extra"] = "More recorded loot",
  ["instances.items.group.quests"] = "Quests",
  ["instances.items.sourceQuest"] = "Quest",
  ["instances.items.unknownSource"] = "Unknown source",
  ["instances.items.bossLine"] = "Boss: %s",
  ["instances.items.captured"] = "Recorded",
  ["instances.items.capturedTip"] = "Recorded by you: %d drops in %d kills",
  ["instances.items.rateOwn"] = "Drop chance %s%% (from your own kills, %d kills)",
  ["instances.items.rateEstimate"] = "Drop chance about %s%% (estimated, may differ from the Forever state)",
})

ns.AddLocale("deDE", {
  ["instances.items.view.boss"] = "Nach Boss",
  ["instances.items.view.all"] = "Alle Items",
  ["instances.items.col.item"] = "Item",
  ["instances.items.col.boss"] = "Boss",
  ["instances.items.sort.item"] = "Nach Item sortieren",
  ["instances.items.sort.boss"] = "Nach Boss sortieren",
  ["instances.items.count.one"] = "1 Item",
  ["instances.items.count.other"] = "%d Items",
  ["instances.items.bossNone"] = "Beute noch nicht erfasst",
  ["instances.items.bossHint"] = "Beute kommt beim eigenen Erfassen oder Export dazu.",
  ["instances.items.group.instance"] = "Weitere Beute der Instanz",
  ["instances.items.group.extra"] = "Weitere erfasste Beute",
  ["instances.items.group.quests"] = "Quests",
  ["instances.items.sourceQuest"] = "Quest",
  ["instances.items.unknownSource"] = "Unbekannte Quelle",
  ["instances.items.bossLine"] = "Boss: %s",
  ["instances.items.captured"] = "Erfasst",
  ["instances.items.capturedTip"] = "Von dir erfasst: %d Drops bei %d Kills",
  ["instances.items.rateOwn"] = "Droprate %s %% (aus eigenen Kills, %d Kills)",
  ["instances.items.rateEstimate"] = "Droprate etwa %s %% (geschätzt, kann vom Forever-Stand abweichen)",
})

local IIV = {}
ns.InstanceItemsView = IIV

local PAD = 8
local ICON = IV.ICON
local BOSS_ICON = 24 -- the boss mark beside the boss name of an item row
local BOSS_GAP = 6
local NAME_DELAY = 0.2 -- seconds: item names that arrive together paint the list once
local COLUMN_MIN = 440 -- the boss column starts from this width on
local COLUMN_SHARE = 0.6
local COLUMN_H = 26

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

-- Scrolls every scroll area around the frame so that the frame is in view (keyboard focus).
local function reveal(frame)
  local node = frame:GetParent()
  while node do
    if node.ScrollTo and node.content then
      local top, bottom, areaTop, areaBottom = frame:GetTop(), frame:GetBottom(), node:GetTop(), node:GetBottom()
      if top and bottom and areaTop and areaBottom then
        local scroll = node:GetVerticalScroll()
        if top > areaTop then
          node:ScrollTo(scroll - (top - areaTop))
        elseif bottom < areaBottom then
          node:ScrollTo(scroll + (areaBottom - bottom))
        end
      end
    end
    node = node:GetParent()
  end
end

-- Registers a pooled frame for Tab and the arrow keys and keeps it next to the other frames of the
-- view, so the keyboard order follows the page and not the moment the frame was made.
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
  view.pooled[frame] = true
  frame.fgScrollIntoView = reveal
end

local function newLine(row)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
end

-- Item rows: icon, name in the quality color, boss (beside the name or under it) and a small note.
local function makeItemRow(view)
  local row = CreateFrame("Button", nil, view)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.boss = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  -- Boss mark: the symbol of the boss, else its small 3D portrait, else the placeholder symbol (IV.PaintBossImage).
  row.bossHost = CreateFrame("Frame", nil, row)
  row.bossHost:SetSize(BOSS_ICON, BOSS_ICON)
  row.bossPic = row.bossHost:CreateTexture(nil, "ARTWORK")
  row.bossPic:SetAllPoints()
  row.meta = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  local function show()
    local entry = row.entry
    if entry then
      W.Tooltip.Show(row, { link = entry.id and ("item:" .. entry.id) or nil, title = row.label, text = row.tip })
    end
  end
  row:SetScript("OnEnter", show)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.fgOnFocus, row.fgOnBlur = show, ns.HideTooltip
  register(view, row, function() end)
  newLine(row)

  -- colX: left edge of the boss column (all-items list on a wide page), nil = boss under the name.
  function row:fgLayout(width)
    local textX = ICON + 10
    local nameW = math.max(40, (self.colX and self.colX - 8 or width) - textX)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -PAD)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.name:SetWidth(nameW)
    local y, side = PAD + ceil(self.name), 0
    local marked = self.boss:IsShown() and self.bossMarked
    self.bossHost:SetShown(marked == true)
    if self.boss:IsShown() then
      self.boss:SetText(self.colX and self.source or string.format(L["instances.items.bossLine"], self.source))
      self.boss:ClearAllPoints()
      local shift = marked and BOSS_ICON + BOSS_GAP or 0
      self.bossHost:ClearAllPoints()
      if self.colX then
        self.bossHost:SetPoint("TOPLEFT", self, "TOPLEFT", self.colX, -PAD)
        self.boss:SetPoint("TOPLEFT", self, "TOPLEFT", self.colX + shift, -PAD)
        self.boss:SetWidth(math.max(40, width - self.colX - shift))
        side = PAD + math.max(marked and BOSS_ICON or 0, ceil(self.boss))
      else
        self.bossHost:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
        self.boss:SetPoint("TOPLEFT", self, "TOPLEFT", textX + shift, -(y + 2))
        self.boss:SetWidth(math.max(40, nameW - shift))
        y = y + 2 + math.max(marked and BOSS_ICON or 0, ceil(self.boss))
      end
    end
    if self.meta:IsShown() then
      self.meta:ClearAllPoints()
      self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
      self.meta:SetWidth(nameW)
      y = y + 2 + ceil(self.meta)
    end
    return math.max(ICON + PAD * 2, y + PAD, side + PAD)
  end
  return row
end

local function sourceLabel(item)
  local group = item.group
  if group.kind == "boss" then
    return (R.Names(group.boss.n)) or "?"
  elseif group.kind == "quests" then
    return L["instances.items.sourceQuest"]
  elseif group.kind == "instance" then
    return L["instances.items.group.instance"]
  end
  return item.source or L["instances.items.unknownSource"]
end

-- inst is the instance of the view, it finds the boss mark of an item that belongs to a boss.
local function paintItemRow(row, item, flat, inst)
  row.entry = item
  row.colX = nil
  local name = IV.ItemName(item)
  row.label = name
  if item.count and item.count > 1 then
    name = item.count .. "x " .. name
  end
  name = ns.ItemInfo.ColorName(name, item.q or IV.ItemQuality(item.id))
  if item.choice then
    name = name .. "  " .. Theme.hexText("textMuted", "(" .. L["instances.quest.choice"] .. ")")
  end
  if item.src == "captured" then
    name = name .. "  " .. Theme.hexText("textMuted", "(" .. L["instances.items.captured"] .. ")")
  end
  row.name:SetText(name)
  row.icon:SetTexture(IV.ItemIcon(item.id))
  local own = item.captured
  local meta
  if item.src == "quest" then
    meta = string.format(L["instances.items.from"], table.concat(item.quests or {}, ", "))
  else
    -- A rate the player recorded is a measurement. A rate of the data is an estimate from an older state of the game.
    local measured = own and ns.LootCapture.Rate(own.kills, own.drops)
    if measured then
      meta = string.format(L["instances.items.rateOwn"], LR.Percent(measured), own.kills)
    elseif item.rate then
      meta = string.format(L["instances.items.rateEstimate"], LR.Percent(item.rate))
    end
  end
  row.meta:SetText(meta or "")
  row.meta:SetShown(meta ~= nil)
  row.tip = own and string.format(L["instances.items.capturedTip"], own.drops, own.kills) or nil
  row.source = sourceLabel(item)
  row.boss:SetShown(flat)
  local boss = flat and item.group.kind == "boss" and item.group.boss or nil
  row.bossMarked = boss ~= nil
  if boss then
    IV.PaintBossImage(row.bossHost, row.bossPic, inst, boss)
  else
    ns.BossPortrait.Unbind(row.bossHost)
  end
end

-- Column heads of the all-items list: two sort buttons, the active one with a chevron and a bar.
local function makeColumns(view)
  local f = CreateFrame("Frame", nil, view)
  f.buttons = {}
  for _, sort in ipairs({ "item", "boss" }) do
    local b = W.Button(f, {
      key = "instances.items.col." .. sort,
      variant = "ghost",
      width = 60,
      height = COLUMN_H,
      tooltip = "instances.items.sort." .. sort,
      onClick = function()
        view:SetSort(sort)
      end,
    })
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetJustifyH("LEFT")
    b.chevron = ns.IconDraw.new(b, 10)
    b.chevron:Draw("chevron-down")
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT", 4, 0)
    b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function()
      b.bar:SetColorTexture(Theme.color("accent2"))
    end)
    f.buttons[sort] = b
  end

  -- Item head over the names, boss head over the boss column (or behind the item head when narrow).
  function f:fgLayout(width)
    local colX = width >= COLUMN_MIN and math.floor(width * COLUMN_SHARE) or nil
    local x = ICON + 10 - 8
    for _, sort in ipairs({ "item", "boss" }) do
      local b = self.buttons[sort]
      local on = view.sort == sort
      b.chevron:SetShown(on)
      b.bar:SetShown(on)
      local w = math.ceil(b.label:GetStringWidth()) + 16 + (on and 16 or 0)
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
      b.chevron:ClearAllPoints()
      b.chevron:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
      if sort == "boss" then
        x = colX and (colX - 8) or x
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
      b:SetSize(w, COLUMN_H)
      x = x + w + 4
    end
    return COLUMN_H
  end
  return f
end

local function openLoot()
  ns.Main.Show("loot")
end

-- The view: toolbar (By boss, All items, open loot capture), then either the accordion or the list,
-- or an empty state when the instance has no items at all.
function IIV.Create(parent)
  local FL = ns.FlowLayout
  local f = CreateFrame("Frame", nil, parent)
  f.view = IL.View(ns.db.settings.instancesItemsView)
  f.sort = "boss"
  f.count = 0
  f.pooled = {}
  f.entries = {}
  local pools = {
    item = { make = makeItemRow, list = {}, used = 0 },
  }

  local rings = {}
  f.toolbar = FL.ButtonRow(f, {
    {
      id = "boss",
      key = "instances.items.view.boss",
      onClick = function()
        f:SetView("boss")
      end,
    },
    {
      id = "all",
      key = "instances.items.view.all",
      onClick = function()
        f:SetView("all")
      end,
    },
    {
      id = "loot",
      label = "act.open",
      icon = "open",
      tooltip = "instances.items.open",
      opens = true,
      onClick = openLoot,
    },
  })
  for _, id in ipairs(IL.VIEWS) do
    rings[id] = W.Border(f.toolbar:GetButton(id), "accent2", 1, 2)
  end
  f.columns = makeColumns(f)
  f.lastFocus = f.columns.buttons.boss

  f.empty = CreateFrame("Frame", nil, f)
  f.empty.title =
    W.Text(f.empty, { key = "instances.items.none", role = "h3", color = "text", justify = "CENTER", wrap = true })
  f.empty.text = W.Text(
    f.empty,
    { key = "instances.items.loot", role = "ui", color = "textSecondary", justify = "CENTER", wrap = true }
  )
  f.empty.button = W.Action(f.empty, {
    label = "act.open",
    icon = "open",
    tooltip = "instances.items.open",
    width = 120,
    height = 26,
    opens = true,
    onClick = openLoot,
  })
  f.bossView = BV.Create(f, function(frame, activate)
    register(f, frame, activate)
  end)
  f.bossView.onChange = function()
    if f.onChange then
      f.onChange()
    end
  end
  f.bossView.onOrder = function()
    f:SyncFocusOrder(f.bossView:Frames())
  end

  local function take(kind)
    local p = pools[kind]
    p.used = p.used + 1
    local frame = p.list[p.used]
    if not frame then
      frame = p.make(f)
      p.list[p.used] = frame
    end
    frame:Show()
    return frame
  end

  local function nameOf(item)
    return IV.ItemName(item)
  end

  -- Pools are taken in display order. The keyboard order of the pooled frames follows the display order.
  local function sync()
    for _, p in pairs(pools) do
      p.used = 0
    end
    local entries, ordered = {}, {}
    local model = f.model
    local empty = model == nil or model.total == 0
    f.empty:SetShown(empty and f.inst ~= nil)
    f.bossView:SetShown(not empty and f.view == "boss")
    if not empty and f.view == "boss" then
      f.bossView:SetModel(f.inst, model)
    end
    f.toolbar:SetShown(not empty)
    f.columns:SetShown(not empty and f.view == "all")
    if not empty then
      if f.view == "all" then
        for _, row in ipairs(IL.Flat(model, f.sort, nameOf)) do
          local frame = take("item")
          entries[#entries + 1] = { frame = frame }
          paintItemRow(frame, row.item, true, f.inst)
          ordered[#ordered + 1] = frame
        end
      else
        ordered = f.bossView:Frames()
      end
      for _, id in ipairs(IL.VIEWS) do
        rings[id].show(id == f.view)
      end
    end
    for _, p in pairs(pools) do
      for i = p.used + 1, #p.list do
        local frame = p.list[i]
        frame:Hide()
        -- A hidden row gives its 3D portrait back to the pool.
        ns.BossPortrait.Unbind(frame.bossHost or frame.portrait)
      end
    end
    f.entries = entries
    f:SyncFocusOrder(ordered)
  end

  -- The pooled frames sit in one block of the focus list: shown ones first, in display order.
  function f:SyncFocusOrder(ordered)
    local items = ns.Focus.items
    local start
    for i, item in ipairs(items) do
      if item == self.columns.buttons.boss then
        start = i + 1
        break
      end
    end
    local count = 0
    for _ in pairs(self.pooled) do
      count = count + 1
    end
    if not start then
      return
    end
    for i = start, start + count - 1 do
      if not self.pooled[items[i]] then
        return
      end
    end
    local seen, at = {}, start
    for _, frame in ipairs(ordered) do
      items[at], seen[frame], at = frame, true, at + 1
    end
    for frame in pairs(self.pooled) do
      if not seen[frame] then
        items[at], at = frame, at + 1
      end
    end
  end

  function f:SetView(view)
    self.view = IL.View(view)
    ns.Store.set("settings.instancesItemsView", self.view)
    sync()
    if self.onChange then
      self.onChange()
    end
  end

  function f:SetSort(sort)
    self.sort = IL.Sort(sort)
    sync()
    if self.onChange then
      self.onChange()
    end
  end

  -- inst, faction ("A", "H" or nil) like the other lists of the page.
  function f:SetInstance(inst, faction)
    local LC = ns.LootCapture
    self.inst = inst
    self.model = inst
      and IL.Build(inst, {
        rewards = IV.Rewards(inst, faction),
        captured = LC.Bosses(),
        encounterNames = LC.EncounterNames,
      })
    self.count = self.model and self.model.total or 0
    sync()
  end

  -- Item names arrive late from the client. The list paints again (names, sort order, heights) once per burst,
  -- and only when the instance shown holds the item.
  local function onItemData(_, id)
    if not f:IsVisible() or (id ~= nil and not IL.HasItem(f.model, id)) then
      return
    end
    ns.Debounce("instance-items-names", NAME_DELAY, function()
      if f:IsVisible() then
        sync()
        if f.onChange then
          f.onChange()
        end
      end
    end)
  end
  ns.On("GET_ITEM_INFO_RECEIVED", onItemData)
  ns.On("ITEM_DATA_LOAD_RESULT", onItemData)

  function f:fgGridLayout(width)
    local y = 0
    if self.empty:IsShown() then
      local textW = math.max(40, width - 2 * PAD)
      self.empty.title:ClearAllPoints()
      self.empty.title:SetPoint("TOP", self.empty, "TOP", 0, -24)
      self.empty.title:SetWidth(textW)
      y = 24 + ceil(self.empty.title) + 8
      self.empty.text:ClearAllPoints()
      self.empty.text:SetPoint("TOP", self.empty, "TOP", 0, -y)
      self.empty.text:SetWidth(textW)
      y = y + ceil(self.empty.text) + 14
      local button = self.empty.button
      button:SetSize(math.min(textW, math.ceil(button.label:GetStringWidth()) + 32), 26)
      button:ClearAllPoints()
      button:SetPoint("TOP", self.empty, "TOP", 0, -y)
      y = y + 26 + 24
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.empty:SetSize(width, y)
    elseif self.toolbar:IsShown() then
      self.toolbar:ClearAllPoints()
      self.toolbar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.toolbar:SetWidth(width)
      y = self.toolbar:fgGridLayout(width) + 10
      local colX = self.view == "all" and width >= COLUMN_MIN and math.floor(width * COLUMN_SHARE) or nil
      if self.columns:IsShown() then
        self.columns:ClearAllPoints()
        self.columns:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        self.columns:SetSize(width, COLUMN_H)
        y = y + self.columns:fgLayout(width) + 2
      end
      if self.bossView:IsShown() then
        self.bossView:ClearAllPoints()
        self.bossView:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        self.bossView:SetWidth(width)
        y = y + self.bossView:fgGridLayout(width)
      end
      for _, e in ipairs(self.entries) do
        local frame = e.frame
        frame.colX = colX
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        frame:SetWidth(width)
        local h = frame:fgLayout(width)
        frame:SetHeight(h)
        y = y + h
      end
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  return f
end
