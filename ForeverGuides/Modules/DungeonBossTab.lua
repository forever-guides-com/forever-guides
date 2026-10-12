-- Boss tab of the dungeon map (Modules/DungeonWorldMap.lua): every boss of the instance in the order of the data,
-- with the boss portrait when the data has one and whether the boss is defeated in this run (ns.BossProgress).
-- The list is the same on every floor. A state is a symbol and a text, never the color alone: a drawn check
-- (defeated), a muted check (probably defeated) and an empty ring (open). An instance without a game ID in the data
-- shows the list without states and says so. Rows are keyboard targets (ns.Focus) that scroll into view.
local _, ns = ...
local W, L, IV, BP = ns.W, ns.L, ns.InstanceView, ns.BossProgress

ns.AddLocale("enUS", {
  ["bosstab.defeated"] = "Defeated",
  ["bosstab.likely"] = "Probably defeated",
  ["bosstab.open"] = "Open",
  ["bosstab.unavailable"] = "Progress is not available for this instance.",
})

ns.AddLocale("deDE", {
  ["bosstab.defeated"] = "Besiegt",
  ["bosstab.likely"] = "Wahrscheinlich besiegt",
  ["bosstab.open"] = "Offen",
  ["bosstab.unavailable"] = "Fortschritt für diese Instanz nicht verfügbar.",
})

local DBT = {}
ns.DungeonBossTab = DBT

DBT.PORTRAIT, DBT.MARK = 32, 14
local GAP, SCROLLBAR, ROW_PAD = 8, 12, 6

ns.IconDraw.register("boss-open", function(p)
  p:Ellipse(1, 1, 10, 10, false)
end)

-- Symbol glyph, tint and text key of a status ("confirmed", "likely" or nil for open).
local LOOK = {
  confirmed = { glyph = "check", tint = "success", key = "bosstab.defeated" },
  likely = { glyph = "check", tint = "textMuted", key = "bosstab.likely" },
  open = { glyph = "boss-open", tint = "textSecondary", key = "bosstab.open" },
}

-- Rows ----------------------------------------------------------------------------------------------

local function makeRow(parent, owner)
  local row = CreateFrame("Frame", nil, parent)
  row.portrait = row:CreateTexture(nil, "ARTWORK")
  row.portrait:SetSize(DBT.PORTRAIT, DBT.PORTRAIT)
  row.mark = ns.IconDraw.new(row, DBT.MARK)
  row.name = W.Text(row, { role = "text", color = "text", wrap = true })
  row.state = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, ns.Theme.lineAlpha())
  end)
  -- The row is a stop of the keyboard walk and brings itself into view.
  ns.Focus.register(row, nil)
  function row:fgScrollIntoView()
    owner:ScrollTo(self)
  end

  function row:fgLayout(width, hasPortrait, available)
    local x = hasPortrait and (DBT.PORTRAIT + GAP) or 0
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -ROW_PAD)
    self.portrait:SetShown(hasPortrait and self.hasPicture == true)
    local textX = x + (available and (DBT.MARK + GAP) or 0)
    local textW = math.max(40, width - textX)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -ROW_PAD)
    self.name:SetWidth(textW)
    local y = ROW_PAD + math.ceil(self.name:GetStringHeight())
    self.mark:SetShown(available)
    self.state:SetShown(available)
    if available then
      self.mark:ClearAllPoints()
      self.mark:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(ROW_PAD + 2))
      self.state:ClearAllPoints()
      self.state:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
      self.state:SetWidth(textW)
      y = y + 2 + math.ceil(self.state:GetStringHeight())
    end
    return math.max(y + ROW_PAD, hasPortrait and (DBT.PORTRAIT + ROW_PAD * 2) or 0)
  end
  return row
end

-- Widget ----------------------------------------------------------------------------------------------

function DBT.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  local state = { inst = nil, rows = {}, tops = {} }
  f.state = state
  f.head = W.Text(f, { role = "h3", color = "accent2", wrap = true })
  f.area = W.ScrollArea(f)

  -- Scrolls the list so the row shows completely.
  function f:ScrollTo(row)
    local top, height = state.tops[row], row:GetHeight()
    local view = self.area:GetHeight()
    local at = self.area:GetVerticalScroll()
    if not top or view <= 0 then
      return
    end
    if top < at then
      self.area:ScrollTo(top)
    elseif top + height > at + view then
      self.area:ScrollTo(top + height - view)
    end
  end

  -- Progress of the shown instance: the Summary result, nil without game ID or bosses in the data.
  local function summary()
    local inst = state.inst
    return inst and type(inst.id) == "number" and BP.Summary(inst.id) or nil
  end

  -- Reads the data and the progress again and paints the rows (no placing, Layout does that).
  function f:Refresh()
    local inst = state.inst
    local sum = summary()
    state.available = sum ~= nil
    local bosses = inst and inst.bo or {}
    if #bosses == 0 then
      W.SetText(self.head, "instances.bosses.none")
    elseif sum then
      W.SetText(self.head, nil, BP.SummaryText(sum))
    else
      W.SetText(self.head, "bosstab.unavailable")
    end
    state.hasPortrait = false
    local fids = {}
    for i, boss in ipairs(bosses) do
      local fid, kind = IV.Portrait(inst, boss)
      fids[i] = kind == "own" and fid or nil
      state.hasPortrait = state.hasPortrait or fids[i] ~= nil
    end
    for i, boss in ipairs(bosses) do
      local row = state.rows[i]
      if not row then
        row = makeRow(self.area.content, self)
        state.rows[i] = row
      end
      local text = string.format("%d. %s", i, ns.T(boss.n) or "?")
      if boss.opt then
        text = text .. "  " .. ns.Theme.hexText("textMuted", L["instances.bosses.optional"])
      end
      row.name:SetText(text)
      row.hasPicture = fids[i] ~= nil
      row.portrait:SetTexture(fids[i])
      row.status = state.available and (BP.Status(inst.id, i) or "open") or nil
      if row.status then
        local look = LOOK[row.status]
        row.mark:Draw(look.glyph)
        row.mark:SetTint(look.tint)
        row.state:SetText(L[look.key])
        W.SetColor(row.state, look.tint)
      end
      row:Show()
    end
    for i = #bosses + 1, #state.rows do
      state.rows[i]:Hide()
    end
    state.count = #bosses
  end

  -- Takes the shown instance (a Data.Instances entry, nil for none).
  function f:SetInstance(inst)
    state.inst = inst
    self.area:SetVerticalScroll(0)
    self:Refresh()
  end

  -- Places the parts in a box of this size (the caller anchors the frame) and returns nothing.
  function f:Layout(width, height)
    self:SetSize(width, height)
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.head:SetWidth(width)
    local y = math.ceil(self.head:GetStringHeight()) + GAP
    self.area:ClearAllPoints()
    self.area:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.area:SetSize(width, math.max(1, height - y))
    local inner = math.max(1, width - SCROLLBAR)
    local content = self.area.content
    content:SetWidth(inner)
    local at = 0
    for i = 1, state.count or 0 do
      local row = state.rows[i]
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -at)
      row:SetWidth(inner)
      local h = row:fgLayout(inner, state.hasPortrait, state.available)
      row:SetHeight(h)
      state.tops[row] = at
      at = at + h
    end
    self.area:SetContentHeight(at)
  end

  return f
end
