-- Loot of an instance as list and detail, like the quest board: the bosses (and the groups of loot no boss
-- owns) on the left, the loot of the chosen one on the right (Modules/InstanceLootRow.lua). Under PANEL_MIN px
-- the loot sits under the list, from COLUMNS_MIN px of detail width the rows run in two columns. Up and down move
-- the focus through the list (the page does that), a focused boss is the chosen one, Enter moves the focus to
-- the first loot row. The groups come from Modules/InstanceItemsLogic.lua.
local _, ns = ...
local W, L, Theme, IV, LR = ns.W, ns.L, ns.Theme, ns.InstanceView, ns.InstanceLootRow

ns.AddLocale("enUS", {
  ["instances.items.selectTip"] = "Shows the loot of this boss.",
  ["instances.items.selectTipGroup"] = "Shows this loot.",
  ["instances.items.selected"] = "Selected",
})

ns.AddLocale("deDE", {
  ["instances.items.selectTip"] = "Zeigt die Beute dieses Bosses.",
  ["instances.items.selectTipGroup"] = "Zeigt diese Beute.",
  ["instances.items.selected"] = "Ausgewählt",
})

local BV = {}
ns.InstanceBossView = BV

local PAD = 8
local GAP = 12
local PORTRAIT = 32
local PANEL_MIN = 560
local COLUMNS_MIN = 560
local LIST_MIN, LIST_MAX = 220, 340
local COLUMN_GAP = 8

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

local function countText(group)
  local n = #group.items
  return n == 0 and L["instances.items.bossNone"]
    or string.format(L["instances.items.count." .. (n == 1 and "one" or "other")], n)
end

-- Title of a group: "1. Name" with the words optional and heroic for a boss. Returns the colored text and the plain one.
local function titleOf(group)
  local boss = group.boss
  if not boss then
    local text = L["instances.items.group." .. group.kind]
    return text, text
  end
  local text = string.format("%d. %s", group.index, IV.Dual(boss.n) or "?")
  local plain = text
  if boss.opt then
    text = text .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
    plain = plain .. ", " .. L["instances.bosses.optional"]
  end
  if boss.hc then
    text = text .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
    plain = plain .. ", " .. L["instances.bosses.heroic"]
  end
  return text, plain
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

-- List entries: boss picture, name and the number of items.
local function makeEntry(view, register)
  local e = CreateFrame("Button", nil, view)
  e.bg = e:CreateTexture(nil, "BACKGROUND")
  e.bg:SetAllPoints()
  local hover = e:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
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
  e.portrait = CreateFrame("Frame", nil, e)
  e.portrait:SetSize(PORTRAIT, PORTRAIT)
  e.pic = e.portrait:CreateTexture(nil, "ARTWORK")
  e.pic:SetAllPoints()
  e.title = W.Text(e, { role = "ui", color = "text", wrap = true })
  e.count = W.Text(e, { role = "micro", color = "textSecondary", wrap = true })

  e:SetScript(
    "OnClick",
    ns.Wrap("instance-boss-entry", function(self)
      view:Select(self.group)
    end)
  )
  local function tip()
    ns.ShowTooltip(
      e,
      e.label or "",
      e.group and e.group.boss and L["instances.items.selectTip"] or L["instances.items.selectTipGroup"]
    )
  end
  e:HookScript("OnEnter", tip)
  e:HookScript("OnLeave", ns.HideTooltip)
  e.fgOnFocus = function()
    view:Select(e.group)
    tip()
  end
  e.fgOnBlur = ns.HideTooltip
  e.fgName = function()
    return e.label
  end
  e.fgDescription = function()
    return e.fgSelected and L["instances.items.selected"] or nil
  end
  register(e, function(self)
    view:Select(self.group)
    view:FocusDetail()
  end)

  function e:fgLayout(width)
    local withPortrait = self.portrait:IsShown()
    local textX = PAD + (withPortrait and PORTRAIT + 8 or 0)
    local textW = math.max(40, width - textX - PAD)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.title:SetWidth(textW)
    local y = PAD + ceil(self.title) + 2
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
    self.count:SetWidth(textW)
    y = y + ceil(self.count)
    return math.max(y + PAD, withPortrait and PORTRAIT + 2 * PAD or 0)
  end
  return e
end

local function paintEntry(e, group, view)
  e.group = group
  e.fgSelected = view.selected == group.id or nil
  local text, plain = titleOf(group)
  local count = countText(group)
  e.label = plain .. ", " .. count
  e.title:SetText(text)
  e.count:SetText(count)
  if group.boss then
    IV.PaintBossImage(e.portrait, e.pic, view.inst, group.boss)
  else
    ns.BossPortrait.Unbind(e.portrait)
  end
  e.portrait:SetShown(group.boss ~= nil)
  paintBackground(e)
end

-- The loot of the chosen group: heading, count and the rows (or the note for a boss without loot).
local function makeDetail(view)
  local d = CreateFrame("Frame", nil, view)
  W.Fill(d, "surface", 1)
  d.title = W.Text(d, { role = "h3", color = "text", wrap = true })
  d.count = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.none = W.Text(d, { key = "instances.items.bossNone", role = "ui", color = "textSecondary", wrap = true })
  d.hint = W.Text(d, { key = "instances.items.bossHint", role = "micro", color = "textMuted", wrap = true })

  function d:fgLayout(width)
    local inner = math.max(40, width - 2 * PAD)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    self.title:SetWidth(inner)
    local y = PAD + ceil(self.title) + 2
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
    self.count:SetWidth(inner)
    y = y + ceil(self.count) + PAD
    if self.none:IsShown() then
      self.none:ClearAllPoints()
      self.none:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      self.none:SetWidth(inner)
      y = y + ceil(self.none) + 2
      self.hint:ClearAllPoints()
      self.hint:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      self.hint:SetWidth(inner)
      return y + ceil(self.hint) + PAD
    end
    local columns = width >= COLUMNS_MIN and 2 or 1
    local colW = math.floor((inner - (columns - 1) * COLUMN_GAP) / columns)
    local rows = view.rows.used
    local at = 1
    while at <= rows do
      local rowH = 0
      for c = 0, columns - 1 do
        local row = view.rows.list[at + c]
        if at + c <= rows and row then
          row:ClearAllPoints()
          row:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + c * (colW + COLUMN_GAP), -y)
          row:SetWidth(colW)
          local h = row:fgLayout(colW)
          row:SetHeight(h)
          rowH = math.max(rowH, h)
        end
      end
      y = y + rowH
      at = at + columns
    end
    return y + PAD
  end
  return d
end

-- parent: the frame the view sits in. register(frame, activate) hands a frame to the keyboard order of the owner.
-- Methods: :SetModel(inst, model) (model of IL.Build), :Select(group), :FocusDetail(), :Frames() (the used frames in
-- keyboard order), :fgGridLayout(width) -> height. .onChange(): asks the owner for a layout, .onOrder(): the frames
-- changed.
function BV.Create(parent, register)
  local f = CreateFrame("Frame", nil, parent)
  f.entries = { list = {}, used = 0 }
  f.rows = { list = {}, used = 0 }
  f.detail = makeDetail(f)

  local function take(pool, make)
    pool.used = pool.used + 1
    local frame = pool.list[pool.used]
    if not frame then
      frame = make()
      pool.list[pool.used] = frame
    end
    frame:Show()
    return frame
  end

  local function hideRest(pool)
    for i = pool.used + 1, #pool.list do
      local frame = pool.list[i]
      frame:Hide()
      if frame.portrait then
        -- A hidden entry gives its 3D portrait back to the pool.
        ns.BossPortrait.Unbind(frame.portrait)
      end
    end
  end

  local function paintDetail()
    local group = f.model and ns.InstanceItemsLogic.Find(f.model, f.selected)
    f.rows.used = 0
    if not group then
      f.detail:Hide()
      hideRest(f.rows)
      return
    end
    f.detail:Show()
    local text = titleOf(group)
    f.detail.title:SetText(text)
    f.detail.count:SetText(countText(group))
    f.detail.none:SetShown(#group.items == 0)
    f.detail.hint:SetShown(#group.items == 0)
    for _, item in ipairs(group.items) do
      local row = take(f.rows, function()
        return LR.Create(f.detail, register)
      end)
      LR.Paint(row, item)
    end
    hideRest(f.rows)
  end

  function f:Frames()
    local out = {}
    for i = 1, self.entries.used do
      out[#out + 1] = self.entries.list[i]
    end
    for i = 1, self.rows.used do
      out[#out + 1] = self.rows.list[i]
    end
    return out
  end

  local function changed()
    if f.onOrder then
      f.onOrder()
    end
    if f.onChange then
      f.onChange()
    end
  end

  -- Chooses a group and shows its loot. The chosen one stays chosen when the model is painted again.
  function f:Select(group)
    if not group or self.selected == group.id then
      return
    end
    self.selected = group.id
    for i = 1, self.entries.used do
      local e = self.entries.list[i]
      e.fgSelected = e.group.id == group.id or nil
      paintBackground(e)
    end
    paintDetail()
    changed()
  end

  function f:FocusDetail()
    for i = 1, self.rows.used do
      local row = self.rows.list[i]
      if row:IsVisible() then
        ns.Focus.set(row)
        return true
      end
    end
    return false
  end

  function f:SetModel(inst, model)
    local IL = ns.InstanceItemsLogic
    if self.inst ~= inst or not (model and self.selected and IL.Find(model, self.selected)) then
      self.selected = model and model.first or nil
    end
    self.inst, self.model = inst, model
    self.entries.used = 0
    for _, group in ipairs(model and model.groups or {}) do
      local e = take(self.entries, function()
        return makeEntry(f, register)
      end)
      paintEntry(e, group, f)
    end
    hideRest(self.entries)
    paintDetail()
  end

  function f:fgGridLayout(width)
    local wide = width >= PANEL_MIN
    local listW = wide and math.min(LIST_MAX, math.max(LIST_MIN, math.floor(width * 0.38))) or width
    local y = 0
    for i = 1, self.entries.used do
      local e = self.entries.list[i]
      e:ClearAllPoints()
      e:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      e:SetWidth(listW)
      local h = e:fgLayout(listW)
      e:SetHeight(h)
      y = y + h
    end
    if self.detail:IsShown() then
      local detailW = wide and (width - listW - GAP) or width
      local x, top = wide and (listW + GAP) or 0, wide and 0 or (y + GAP)
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", x, -top)
      self.detail:SetWidth(detailW)
      local h = self.detail:fgLayout(detailW)
      self.detail:SetHeight(h)
      y = wide and math.max(y, top + h) or (top + h)
    end
    self:SetHeight(math.max(1, y))
    return y
  end

  return f
end
