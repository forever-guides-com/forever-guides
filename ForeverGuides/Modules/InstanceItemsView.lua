-- Items tab of the instances page: the loot of an instance by boss (one accordion group open at a
-- time, the first one at the start) or as one list with the boss beside each item. Rules and data
-- merging are in Modules/InstanceItemsLogic.lua. Headers and rows come from pools, the height follows
-- the open group, and a page Stack holds the view through fgGridLayout(width).
local _, ns = ...
local W, L, Theme, R, IV, IL = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.InstanceView, ns.InstanceItemsLogic

ns.AddLocale("enUS", {
  ["instances.items.view.boss"] = "By boss",
  ["instances.items.view.all"] = "All items",
  ["instances.items.col.item"] = "Item",
  ["instances.items.col.boss"] = "Boss",
  ["instances.items.sort.item"] = "Sort by item",
  ["instances.items.sort.boss"] = "Sort by boss",
  ["instances.items.count.one"] = "1 item",
  ["instances.items.count.other"] = "%d items",
  ["instances.items.bossNone"] = "No loot known",
  ["instances.items.bossHint"] = "Loot is added when you record or export it.",
  ["instances.items.group.extra"] = "More recorded loot",
  ["instances.items.group.quests"] = "Quests",
  ["instances.items.sourceQuest"] = "Quest",
  ["instances.items.unknownSource"] = "Unknown source",
  ["instances.items.bossLine"] = "Boss: %s",
  ["instances.items.captured"] = "Recorded",
  ["instances.items.capturedTip"] = "Recorded by you: %d drops in %d kills",
  ["instances.items.rate"] = "Drop chance %s%%",
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
  ["instances.items.bossNone"] = "Keine Beute bekannt",
  ["instances.items.bossHint"] = "Beute kommt beim eigenen Erfassen oder Export dazu.",
  ["instances.items.group.extra"] = "Weitere erfasste Beute",
  ["instances.items.group.quests"] = "Quests",
  ["instances.items.sourceQuest"] = "Quest",
  ["instances.items.unknownSource"] = "Unbekannte Quelle",
  ["instances.items.bossLine"] = "Boss: %s",
  ["instances.items.captured"] = "Erfasst",
  ["instances.items.capturedTip"] = "Von dir erfasst: %d Drops bei %d Kills",
  ["instances.items.rate"] = "Droprate %s %%",
})

local IIV = {}
ns.InstanceItemsView = IIV

local PAD = 8
local ICON = IV.ICON
local HEAD_PORTRAIT = 40
local INDENT = 14
local COLUMN_MIN = 440 -- the boss column starts from this width on
local COLUMN_SHARE = 0.6
local COLUMN_H = 26

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

local function percent(value)
  return value >= 10 and tostring(math.floor(value + 0.5)) or tostring(math.floor(value * 10 + 0.5) / 10)
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
    if self.boss:IsShown() then
      self.boss:SetText(self.colX and self.source or string.format(L["instances.items.bossLine"], self.source))
      self.boss:ClearAllPoints()
      if self.colX then
        self.boss:SetPoint("TOPLEFT", self, "TOPLEFT", self.colX, -PAD)
        self.boss:SetWidth(math.max(40, width - self.colX))
        side = PAD + ceil(self.boss)
      else
        self.boss:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
        self.boss:SetWidth(nameW)
        y = y + 2 + ceil(self.boss)
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
  end
  return item.source or L["instances.items.unknownSource"]
end

local function paintItemRow(row, item, flat)
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
    local rate = item.rate or (own and ns.LootCapture.Rate(own.kills, own.drops))
    meta = rate and string.format(L["instances.items.rate"], percent(rate)) or nil
  end
  row.meta:SetText(meta or "")
  row.meta:SetShown(meta ~= nil)
  row.tip = own and string.format(L["instances.items.capturedTip"], own.drops, own.kills) or nil
  row.source = sourceLabel(item)
  row.boss:SetShown(flat)
end

-- Group headers: chevron, boss portrait (boss groups), name with tags and the item count.
local function makeHeader(view)
  local h = CreateFrame("Button", nil, view)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetAllPoints()
  ns.Bind(h, function()
    h.bg:SetColorTexture(Theme.color("surface"))
  end)
  local hover = h:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  h.chevron = ns.IconDraw.new(h, 12)
  h.portrait = CreateFrame("Frame", nil, h)
  h.portrait:SetSize(HEAD_PORTRAIT, HEAD_PORTRAIT)
  h.pic = h.portrait:CreateTexture(nil, "ARTWORK")
  h.pic:SetAllPoints()
  h.letter = W.Text(h.portrait, { role = "h3", family = "heading", color = "accent2", justify = "CENTER" })
  h.letter:SetPoint("CENTER")
  h.name = W.Text(h, { role = "text", color = "text", wrap = true })
  h.count = W.Text(h, { role = "micro", color = "textMuted", wrap = true })
  h:SetScript(
    "OnClick",
    ns.Wrap("instance-items", function(self)
      view:Toggle(self.group)
    end)
  )
  register(view, h, function(self)
    self:Click()
  end)
  newLine(h)

  function h:fgLayout(width)
    local withPortrait = self.portrait:IsShown()
    local x = PAD + 12 + 10
    self.chevron:ClearAllPoints()
    self.chevron:SetPoint("LEFT", self, "LEFT", PAD, 0)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("LEFT", self, "LEFT", x, 0)
    local textX = x + (withPortrait and HEAD_PORTRAIT + 10 or 0)
    local textW = math.max(40, width - textX - PAD)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.name:SetWidth(textW)
    local y = PAD + ceil(self.name) + 2
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
    self.count:SetWidth(textW)
    y = y + ceil(self.count)
    return math.max(y + PAD, withPortrait and HEAD_PORTRAIT + PAD * 2 or 0)
  end
  return h
end

local function paintPortrait(h, inst, boss)
  local fid = IV.Portrait(inst, boss)
  h.pic:SetTexture(fid)
  h.pic:SetShown(fid ~= nil)
  if fid == nil and not h.disc then
    h.disc = ns.IconDraw.new(h.portrait, HEAD_PORTRAIT)
    h.disc:SetPoint("TOPLEFT")
    h.disc:Draw(IV.DrawDisc, "?")
  end
  if h.disc then
    h.disc:SetShown(fid == nil)
  end
  h.letter:SetText(IV.FirstLetter(R.Names(boss.n)))
  h.letter:SetShown(fid == nil)
end

local function paintHeader(h, view, group)
  h.group = group
  local open = view.open == group.id
  h.fgExpanded = open
  h.chevron:Draw(open and "chevron-down" or "chevron-right")
  local boss = group.boss
  local text
  if boss then
    text = string.format("%d. %s", group.index, IV.Dual(boss.n) or "?")
    if boss.opt then
      text = text .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
    end
    if boss.hc then
      text = text .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
    end
    paintPortrait(h, view.inst, boss)
  else
    text = L["instances.items.group." .. group.kind]
  end
  h.portrait:SetShown(boss ~= nil)
  h.name:SetText(text)
  local n = #group.items
  h.count:SetText(
    n == 0 and L["instances.items.bossNone"]
      or string.format(L["instances.items.count." .. (n == 1 and "one" or "other")], n)
  )
end

-- Note under an open boss without loot.
local function makeHint(view)
  local f = CreateFrame("Frame", nil, view)
  f.title = W.Text(f, { key = "instances.items.bossNone", role = "ui", color = "textSecondary", wrap = true })
  f.text = W.Text(f, { key = "instances.items.bossHint", role = "micro", color = "textMuted", wrap = true })
  function f:fgLayout(width)
    local w = math.max(40, width - 2 * PAD)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    self.title:SetWidth(w)
    local y = PAD + ceil(self.title) + 2
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
    self.text:SetWidth(w)
    return y + ceil(self.text) + PAD
  end
  return f
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
    header = { make = makeHeader, list = {}, used = 0 },
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
    { id = "loot", label = "act.open", icon = "open", tooltip = "instances.items.open", onClick = openLoot },
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
    onClick = openLoot,
  })
  f.hint = makeHint(f)

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

  -- Pools are taken in display order, so a header keeps its frame (and its keyboard focus) when
  -- another group opens. The keyboard order of the pooled frames follows the display order.
  local function sync()
    for _, p in pairs(pools) do
      p.used = 0
    end
    f.hint:Hide()
    local entries, ordered = {}, {}
    local model = f.model
    local empty = model == nil or model.total == 0
    f.empty:SetShown(empty and f.inst ~= nil)
    f.toolbar:SetShown(not empty)
    f.columns:SetShown(not empty and f.view == "all")
    if not empty then
      if f.view == "all" then
        for _, row in ipairs(IL.Flat(model, f.sort, nameOf)) do
          local frame = take("item")
          entries[#entries + 1] = { frame = frame, flat = true }
          paintItemRow(frame, row.item, true)
          ordered[#ordered + 1] = frame
        end
      else
        for _, group in ipairs(model.groups) do
          local frame = take("header")
          paintHeader(frame, f, group)
          entries[#entries + 1] = { frame = frame }
          ordered[#ordered + 1] = frame
          if f.open == group.id then
            for _, item in ipairs(group.items) do
              local row = take("item")
              paintItemRow(row, item, false)
              entries[#entries + 1] = { frame = row, indent = INDENT }
              ordered[#ordered + 1] = row
            end
            if #group.items == 0 then
              f.hint:Show()
              entries[#entries + 1] = { frame = f.hint, indent = INDENT }
            end
          end
        end
      end
      for _, id in ipairs(IL.VIEWS) do
        rings[id].show(id == f.view)
      end
    end
    for _, p in pairs(pools) do
      for i = p.used + 1, #p.list do
        p.list[i]:Hide()
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

  function f:Toggle(group)
    self.open = self.open ~= group.id and group.id or nil
    sync()
    if self.onChange then
      self.onChange()
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
    local changed = self.inst ~= inst
    self.inst = inst
    self.model = inst
      and IL.Build(inst, {
        rewards = IV.Rewards(inst, faction),
        captured = LC.Bosses(),
        encounterNames = LC.EncounterNames,
      })
    self.count = self.model and self.model.total or 0
    if self.model and (changed or (self.open and not IL.Find(self.model, self.open))) then
      self.open = self.model.first
    end
    sync()
  end

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
      for _, e in ipairs(self.entries) do
        local frame, indent = e.frame, e.indent or 0
        frame.colX = e.flat and colX or nil
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self, "TOPLEFT", indent, -y)
        frame:SetWidth(width - indent)
        local h = frame:fgLayout(width - indent)
        frame:SetHeight(h)
        y = y + h
      end
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  return f
end
