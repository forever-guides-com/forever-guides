-- The right side of the window "My catches": a column of figure tiles, fish lines with icon, name, count and a bar for
-- the share, place lines the same way, and the recipe lines. It draws blocks that JournalView hands over, it
-- knows no ledger. The same helpers give the rows of the list their item tooltip and their click.
--
-- Blocks: { kind = "title", name, id, quality, info = { title, text } }, { kind = "tiles", tiles = { { label,
-- value, long, tip, share, span } } }, { kind = "heading", text }, { kind = "rows", rows = { { id | key, name,
-- quality, n, pct, share, line, tip } } }, { kind = "uses", rows = { { text, result } } }, { kind = "text", text }.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local W, L, Theme = FG.W, FG.L, FG.Theme
local Logic, Game = fish.JournalLogic, fish.Game

local D = {}
fish.JournalDetail = D

local TILE_H, TILE_GAP = 40, 4
local ROW_H, ICON, TITLE_H, USE_H = 40, 28, 40, 32
local COUNT_W, PCT_W = 38, 58

-- Item helpers ------------------------------------------------------------------------------------------------------

-- The colour code of a quality around a name; the name itself stays the text for the quality (no colour alone).
function D.ColorName(name, quality)
  local info = FG.ItemInfo
  if info and info.ColorName and type(quality) == "number" then
    local ok, text = pcall(info.ColorName, name, quality)
    if ok and type(text) == "string" then
      return text
    end
  end
  return name
end

-- The item tooltip of the game for an item, with extra lines under it. Without an item link the name is the
-- title. The first ask for an uncached item makes the client load it (Game.ItemLink).
function D.ShowItem(owner, id, name, lines, hint)
  local title = name or L["fishing.fish.unknown"]
  local link = type(id) == "number" and Game.ItemLink(id) or nil
  FG.ShowTooltip(owner, title, nil, { link = link, lines = lines, hint = hint })
end

-- Shift+click on an item: its link goes into the chat edit box when one is open. Returns true when it did.
function D.LinkItem(id, name)
  if type(id) ~= "number" then
    return false
  end
  local link = Game.ChatLink(id, name)
  return link ~= nil and Game.InsertLink(link) == true
end

-- A click on something that stands for an item: with Shift the link, else the given action.
function D.Click(id, name, action)
  if Game.ShiftDown() then
    return D.LinkItem(id, name)
  end
  if action then
    action()
  end
  return false
end

-- Bars --------------------------------------------------------------------------------------------------------------

-- A bar for a share in percent: a track and a fill whose width follows the width of the bar. The share is also
-- written next to it by the caller, `alt` is the sentence for it (tooltip of the row, plain detail text).
-- The bar sits above everything its parent draws itself (selection, mark, outline) and takes no mouse, so the
-- tooltip of the parent stays in charge. The track is always drawn, a share of 0 or nil leaves it empty.
function D.NewBar(parent, height)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(height or 6)
  bar:SetFrameLevel(parent:GetFrameLevel() + 2)
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetAllPoints()
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  FG.Bind(bar, function(self)
    self.track:SetColorTexture(Theme.color("surface3", 1))
    self.fill:SetColorTexture(Theme.color("accent", 1))
  end)
  -- The client resolves the width of an anchored frame late: right after a re-anchor it can read 0 and fires no size
  -- event when the width ends up unchanged. The last known width carries the fill over that gap, and a frame that
  -- still reads 0 asks again on the next frame until the width is there.
  function bar:Apply()
    local full = self:GetWidth() or 0
    if full > 0 then
      self.fullWidth = full
      if self:GetScript("OnUpdate") then
        self:SetScript("OnUpdate", nil)
      end
    else
      full = self.fullWidth or 0
      if not self:GetScript("OnUpdate") then
        self:SetScript("OnUpdate", function(frame)
          frame:Apply()
        end)
      end
    end
    local width = Logic.BarWidth(self.share, full)
    if width > 0 then
      self.fill:SetWidth(width)
      self.fill:Show()
    else
      self.fill:Hide()
    end
  end
  function bar:SetShare(share, alt)
    self.share, self.alt = share, alt
    self:Apply()
  end
  bar:SetScript("OnSizeChanged", function(self)
    self:Apply()
  end)
  bar:SetScript("OnShow", function(self)
    self:Apply()
  end)
  return bar
end

-- Pieces -------------------------------------------------------------------------------------------------------------

local function newTile(parent)
  local tile = CreateFrame("Frame", nil, parent)
  tile:SetHeight(TILE_H)
  tile:EnableMouse(true)
  tile.bg = tile:CreateTexture(nil, "BACKGROUND")
  tile.bg:SetAllPoints()
  FG.Bind(tile, function(self)
    self.bg:SetColorTexture(Theme.color("surface2", 1))
  end)
  tile.label = W.Text(tile, { role = "micro", color = "textSecondary" })
  tile.label:SetPoint("TOPLEFT", 6, -4)
  tile.label:SetPoint("TOPRIGHT", -6, -4)
  tile.value = W.Text(tile, { role = "ui", color = "text" })
  tile.value:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -2)
  tile.value:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
  tile.bar = D.NewBar(tile, 4)
  tile.bar:SetPoint("BOTTOMLEFT", 6, 4)
  tile.bar:SetPoint("BOTTOMRIGHT", -6, 4)
  tile:SetScript("OnEnter", function(self)
    local data = self.data
    if data and (data.tip or data.long) then
      FG.ShowTooltip(self, data.long or data.label, data.tip)
    end
  end)
  tile:SetScript("OnLeave", FG.HideTooltip)
  return tile
end

local function newHeading(parent)
  return W.Text(parent, { role = "ui", color = "accent2" })
end

local function newNote(parent)
  return W.Text(parent, { role = "ui", color = "textMuted", wrap = true })
end

local function newTitle(parent)
  local title = CreateFrame("Button", nil, parent)
  title:SetHeight(TITLE_H)
  title.icon = title:CreateTexture(nil, "ARTWORK")
  title.icon:SetSize(34, 34)
  title.icon:SetPoint("TOPLEFT", 0, -3)
  title.info = W.InfoButton(title, "fishj.d.openTitle", "fishj.d.open")
  title.info:SetPoint("TOPRIGHT", -2, -3)
  title.name = W.Text(title, { role = "h3", color = "text", wrap = true })
  title.name:SetPoint("TOPLEFT", title.icon, "TOPRIGHT", 6, -2)
  title.name:SetPoint("RIGHT", title, "RIGHT", -2, 0)
  if title.name.SetMaxLines then
    title.name:SetMaxLines(2)
  end
  title:SetScript("OnEnter", function(self)
    local data = self.data
    if not data then
      return
    end
    if data.id then
      D.ShowItem(self, data.id, data.name, nil, L["fishj.tip.link"])
    else
      FG.ShowTooltip(self, data.name)
    end
  end)
  title:SetScript("OnLeave", FG.HideTooltip)
  title:SetScript(
    "OnClick",
    FG.Wrap("fishj-title", function(self)
      if self.data and self.data.id then
        D.Click(self.data.id, self.data.name)
      end
    end)
  )
  return title
end

-- A line of the detail: icon (fish only), name, count, bar and the share as a number.
local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:Hide()
  FG.Bind(row, function(self)
    self.hover:SetColorTexture(Theme.color("accent", 0.14))
  end)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 2, 0)
  row.count = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.count:SetPoint("TOPRIGHT", -4, -5)
  row.count:SetWidth(COUNT_W)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("TOPRIGHT", row.count, "TOPLEFT", -4, 0)
  row.pct = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
  row.pct:SetPoint("BOTTOMRIGHT", -4, 5)
  row.pct:SetWidth(PCT_W)
  row.bar = D.NewBar(row, 6)
  row.bar:SetPoint("BOTTOMRIGHT", row.pct, "BOTTOMLEFT", -6, 2)
  row:SetScript("OnEnter", function(self)
    self.hover:Show()
    local data = self.data
    if not data then
      return
    end
    local lines = { data.line }
    if data.id then
      D.ShowItem(self, data.id, data.name, lines, L["fishj.tip.fish"])
    else
      FG.ShowTooltip(self, data.name, nil, { lines = lines, hint = L["fishj.tip.place"] })
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:Hide()
    FG.HideTooltip()
  end)
  row:SetScript(
    "OnClick",
    FG.Wrap("fishj-detail-row", function(self)
      local data, panel = self.data, self.panel
      if not (data and panel) then
        return
      end
      if data.id then
        D.Click(data.id, data.name, function()
          panel.hooks.onFish(data.id)
        end)
      elseif data.key ~= nil then
        panel.hooks.onPlace(data.key)
      end
    end)
  )
  return row
end

local function newUse(parent)
  local use = CreateFrame("Button", nil, parent)
  use:SetHeight(USE_H)
  use.hover = use:CreateTexture(nil, "BACKGROUND")
  use.hover:SetAllPoints()
  use.hover:Hide()
  FG.Bind(use, function(self)
    self.hover:SetColorTexture(Theme.color("accent", 0.14))
  end)
  use.icon = use:CreateTexture(nil, "ARTWORK")
  use.icon:SetSize(22, 22)
  use.icon:SetPoint("LEFT", 2, 0)
  use.text = W.Text(use, { role = "ui", color = "text", wrap = true })
  use.text:SetPoint("LEFT", use.icon, "RIGHT", 6, 0)
  use.text:SetPoint("RIGHT", use, "RIGHT", -2, 0)
  if use.text.SetMaxLines then
    use.text:SetMaxLines(2)
  end
  use:SetScript("OnEnter", function(self)
    self.hover:Show()
    local data = self.data
    if not data then
      return
    end
    if data.result then
      D.ShowItem(self, data.result, data.resultName, { data.text }, L["fishj.tip.link"])
    else
      FG.ShowTooltip(self, data.text)
    end
  end)
  use:SetScript("OnLeave", function(self)
    self.hover:Hide()
    FG.HideTooltip()
  end)
  use:SetScript(
    "OnClick",
    FG.Wrap("fishj-use", function(self)
      if self.data and self.data.result then
        D.Click(self.data.result, self.data.resultName)
      end
    end)
  )
  return use
end

-- The panel -----------------------------------------------------------------------------------------------------------

-- hooks: onFish(id) and onPlace(key) for a click on a line.
function D.Create(parent, hooks)
  local panel = { hooks = hooks, pools = {} }
  local area = W.ScrollArea(parent)
  local content = area.content
  panel.area = area

  local function take(kind, make)
    local pool = panel.pools[kind]
    if not pool then
      pool = { n = 0 }
      panel.pools[kind] = pool
    end
    pool.n = pool.n + 1
    local item = pool[pool.n]
    if not item then
      item = make(content)
      item.panel = panel
      pool[pool.n] = item
    end
    item:Show()
    return item
  end

  local function place(item, y, height)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    item:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    if height then
      item:SetHeight(height)
    end
  end

  local builders = {}

  function builders.title(block, y)
    local title = take("title", newTitle)
    place(title, y)
    title.data = block
    if block.id then
      title.icon:SetTexture(Game.ItemIcon(block.id))
      title.icon:Show()
      title.name:SetText(D.ColorName(block.name, block.quality))
    else
      title.icon:Hide()
      title.name:SetText(block.name)
    end
    title.name:ClearAllPoints()
    title.name:SetPoint(
      "TOPLEFT",
      block.id and title.icon or title,
      block.id and "TOPRIGHT" or "TOPLEFT",
      block.id and 6 or 2,
      -2
    )
    title.name:SetPoint("RIGHT", block.info and title.info or title, block.info and "LEFT" or "RIGHT", -4, 0)
    title.info:SetShown(block.info ~= nil)
    return TITLE_H + 4
  end

  -- Tiles go two to a row, a tile with span 2 takes a whole row.
  function builders.tiles(block, y)
    local top, tiles, index = y, block.tiles, 1
    while index <= #tiles do
      local pair = { tiles[index] }
      if pair[1].span ~= 2 and tiles[index + 1] and tiles[index + 1].span ~= 2 then
        pair[2] = tiles[index + 1]
      end
      index = index + #pair
      for slot, data in ipairs(pair) do
        local tile = take("tile", newTile)
        tile.data = data
        tile:ClearAllPoints()
        if #pair == 1 then
          tile:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
          tile:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -top)
        elseif slot == 1 then
          tile:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
          tile:SetPoint("TOPRIGHT", content, "TOP", -TILE_GAP / 2, -top)
        else
          tile:SetPoint("TOPLEFT", content, "TOP", TILE_GAP / 2, -top)
          tile:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -top)
        end
        tile.label:SetText(data.label)
        tile.value:SetText(data.value)
        if data.share ~= nil then
          tile.bar:SetShare(data.share, data.plain)
          tile.bar:Show()
        else
          tile.bar:Hide()
        end
      end
      top = top + TILE_H + TILE_GAP
    end
    return top - y + 4
  end

  function builders.heading(block, y)
    local heading = take("heading", newHeading)
    heading:ClearAllPoints()
    heading:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(y + 2))
    heading:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + 2))
    heading:SetText(block.text)
    return 22
  end

  function builders.rows(block, y)
    local top = y
    for _, data in ipairs(block.rows) do
      local row = take("row", newRow)
      place(row, top)
      row.data = data
      row.count:SetText(tostring(data.n))
      row.pct:SetText(data.pct or "")
      row.bar:SetShare(data.share, data.line)
      row.name:ClearAllPoints()
      if data.id then
        row.icon:SetTexture(Game.ItemIcon(data.id))
        row.icon:Show()
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
        row.name:SetText(D.ColorName(data.name, data.quality))
      else
        row.icon:Hide()
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
        row.name:SetText(data.name)
      end
      row.name:SetPoint("TOPRIGHT", row.count, "TOPLEFT", -4, 0)
      row.bar:ClearAllPoints()
      row.bar:SetPoint("BOTTOMLEFT", data.id and ICON + 10 or 4, 7)
      row.bar:SetPoint("BOTTOMRIGHT", row.pct, "BOTTOMLEFT", -6, 2)
      top = top + ROW_H
    end
    return top - y + 2
  end

  function builders.uses(block, y)
    local top = y
    for _, data in ipairs(block.rows) do
      local use = take("use", newUse)
      place(use, top)
      use.data = data
      use.text:SetText(data.text)
      if data.result then
        use.icon:SetTexture(Game.ItemIcon(data.result))
        use.icon:Show()
      else
        use.icon:Hide()
      end
      top = top + USE_H
    end
    return top - y + 2
  end

  function builders.text(block, y)
    local note = take("note", newNote)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(y + 2))
    note:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -(y + 2))
    note:SetText(block.text)
    return math.max(16, (note:GetStringHeight() or 14)) + 8
  end

  -- Draws the blocks, in order, from the top. An empty list leaves the panel empty.
  function panel:Render(blocks)
    self.blocks = blocks
    for _, pool in pairs(self.pools) do
      for index = 1, #pool do
        pool[index]:Hide()
      end
      pool.n = 0
    end
    local y = 2
    for _, block in ipairs(blocks or {}) do
      local build = builders[block.kind]
      if build then
        y = y + (build(block, y))
      end
    end
    area:SetContentHeight(y + 4)
    area:ScrollTo(0)
  end

  -- Wrapped notes need the final width: draw again when it changed.
  local width = 0
  area:HookScript("OnSizeChanged", function(_, w)
    if w and math.abs(w - width) > 1 and panel.blocks then
      width = w
      local scroll = area:GetVerticalScroll()
      panel:Render(panel.blocks)
      area:ScrollTo(scroll)
    end
  end)
  return panel
end
