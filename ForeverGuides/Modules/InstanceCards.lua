-- Instance overview: filter bar, then the instances as a list (rows with columns, Modules/InstanceListView.lua)
-- or as cards (picture with plaques, foot with name and facts), both grouped under collapsible level brackets,
-- the states of an empty list and the keyboard cursor. The page that owns it (InstancesPage) opens an
-- instance through opts.onOpen / cards.onOpen. Texts and order come from Modules/InstanceListLogic.lua, the
-- picture from Modules/InstanceArt.lua. A card keeps no text on the picture: every label sits on a plaque.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit
local IL, Art, D = ns.InstanceListLogic, ns.InstanceArt, ns.InstanceDisplay
local B, LV = ns.InstanceBracketLogic, ns.InstanceListView
local DA = ns.InstanceDataAccess

local Cards = {}
ns.InstanceCards = Cards

ns.AddLocale("enUS", {
  ["instances.card.kind.all"] = "All",
  ["instances.card.kind.dungeon"] = "Dungeons",
  ["instances.card.kind.raid"] = "Raids",
  ["instances.card.levelBox"] = "Filter by level",
  ["instances.card.levelBox.ph"] = "e.g. 25",
  ["instances.card.levelBox.tip"] = "Shows the instances that cover this level.",
  ["instances.card.onlyFav"] = "Favorites only",
  ["instances.card.favFirst"] = "Favorites first",
  ["instances.card.count"] = "%d of %d",
  ["instances.card.fav"] = "Favorite",
  ["instances.card.fav.tip"] = "Marks this instance as a favorite or removes the mark. Press F on a focused card.",
  ["instances.card.empty"] = "No instance matches.",
  ["instances.card.noFavorites"] = "No favorites yet.",
  ["instances.card.noFavorites.hint"] = "Click the star on a card to mark it.",
})

ns.AddLocale("deDE", {
  ["instances.card.kind.all"] = "Alle",
  ["instances.card.kind.dungeon"] = "Dungeons",
  ["instances.card.kind.raid"] = "Raids",
  ["instances.card.levelBox"] = "Stufe filtern",
  ["instances.card.levelBox.ph"] = "z.B. 25",
  ["instances.card.levelBox.tip"] = "Zeigt die Instanzen, die diese Stufe abdecken.",
  ["instances.card.onlyFav"] = "Nur Favoriten",
  ["instances.card.favFirst"] = "Favoriten zuerst",
  ["instances.card.count"] = "%d von %d",
  ["instances.card.fav"] = "Favorit",
  ["instances.card.fav.tip"] = "Markiert die Instanz als Favorit oder entfernt die Markierung. Drücke auf einer fokussierten Karte die Taste F.",
  ["instances.card.empty"] = "Keine Instanz passt.",
  ["instances.card.noFavorites"] = "Noch keine Favoriten.",
  ["instances.card.noFavorites.hint"] = "Klicke den Stern auf einer Karte, um sie zu markieren.",
})

-- Pixels at 100 percent text size; the heights of text parts come from the font, these are the fixed rest.
Cards.PAD = 6
Cards.GAP = 4
Cards.STAR = 24
Cards.ICON = 20
Cards.FOOT_PAD = 8
Cards.PLAQUE_ALPHA = 0.85
Cards.BAR_GAP = 8

local function ceil(n)
  return math.ceil(n)
end

-- Plaque: a surface behind the text, so text never stands directly on the picture. ---------------------

local function newPlaque(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  ns.Bind(p, function(self)
    local r, g, b = Theme.rgb("surface")
    self.bg:SetColorTexture(r, g, b, Theme.highContrast() and 1 or Cards.PLAQUE_ALPHA)
  end)
  p.text = W.Text(p, { role = "small", color = "text" })
  p.icon = nil
  p.full, p.short = "", nil
  return p
end

-- spec: faction icon spec (optional). The text may be shortened to `short` (a letter) when the width runs out.
local function setPlaque(p, full, short, iconSpec)
  p.full, p.short, p.shortOn = full, short, false
  p.text:SetText(full)
  if iconSpec then
    if p.icon then
      p.icon:SetSpec(iconSpec)
    else
      p.icon = K.IconSlot(p, iconSpec)
    end
    p.icon:Show()
  elseif p.icon then
    p.icon:Hide()
  end
  p.hasIcon = iconSpec ~= nil
end

-- Width of the plaque with the word (full) or without it (short text, or the icon alone).
local function plaqueWidth(p, short)
  local padX = Cards.PAD
  local textW
  if short then
    if p.hasIcon then
      textW = 0
    else
      p.text:SetText(p.short or p.full)
      textW = ceil(p.text:GetStringWidth())
      p.text:SetText(p.full)
    end
  else
    textW = ceil(p.text:GetStringWidth())
  end
  local iconW = p.hasIcon and (Cards.ICON + (textW > 0 and Cards.GAP or 0)) or 0
  return textW + iconW + 2 * padX
end

local function plaqueHeight(p)
  return math.max(ceil(p.text:GetStringHeight()) + 4, p.hasIcon and (Cards.ICON + 2) or 0)
end

-- Lays the plaque out in its final width and mode.
local function sizePlaque(p, short, height)
  local w = plaqueWidth(p, short)
  p.shortOn = short
  p.text:SetText(short and (p.hasIcon and "" or p.short or p.full) or p.full)
  p.text:ClearAllPoints()
  if p.hasIcon then
    p.icon:ClearAllPoints()
    p.icon:SetPoint("LEFT", p, "LEFT", Cards.PAD, 0)
    p.text:SetPoint("LEFT", p, "LEFT", Cards.PAD + Cards.ICON + Cards.GAP, 0)
  else
    p.text:SetPoint("LEFT", p, "LEFT", Cards.PAD, 0)
  end
  p:SetSize(w, height)
end

-- Card -----------------------------------------------------------------------------------------------

local function isFavorite(inst)
  return D.IsFavorite(R.InstanceSlug(inst))
end

local function showTip(card)
  local inst = card.inst
  if not inst then
    return
  end
  local name = R.Names(inst.n)
  local lines = IL.TipLines(inst, L, card.questText)
  for _, extra in ipairs(card.extraTip or {}) do
    lines[#lines + 1] = extra
  end
  ns.ShowTooltip(card, name, nil, { lines = lines, anchor = "ANCHOR_RIGHT" })
end

local function setHighlight(card, on)
  card:SetHover(on)
end

-- Hover, tooltip and click of a card or a row (the keyboard cursor of the owner shares the rim).
local function wire(item)
  item:SetScript("OnEnter", function(self)
    setHighlight(self, true)
    showTip(self)
  end)
  item:SetScript("OnLeave", function(self)
    if not (self.owner and self.owner.cursorShown and self.owner.cursorCard == self) then
      setHighlight(self, false)
    end
    ns.HideTooltip()
  end)
  item:SetScript(
    "OnClick",
    ns.Wrap("instance-card", function(self)
      if self.owner and self.owner.cursorCard ~= self then
        self.owner:SetCursor(self.index)
      end
      if self.owner then
        self.owner:Open(self.inst)
      end
    end)
  )
end

local function newRow(parent)
  local row = LV.NewRow(parent)
  wire(row)
  return row
end

local function newCard(grid)
  local card = W.Panel(grid, { frameType = "Button", edgeAlpha = 0.3 })
  card.art = Art.Create(card)
  card.art:SetPoint("TOPLEFT")
  card.top = CreateFrame("Frame", nil, card)
  card.top:SetAllPoints(card.art)
  card.top:SetFrameLevel(card:GetFrameLevel() + 3)
  card.typeP = newPlaque(card.top)
  card.facP = newPlaque(card.top)
  card.annP = newPlaque(card.top)
  card.questP = newPlaque(card.top)
  card.levelP = newPlaque(card.top)
  card.star = W.Action(card.top, {
    icon = "star-outline",
    size = Cards.STAR,
    boxed = true,
    tooltip = "instances.card.fav",
    tooltipText = "instances.card.fav.tip",
    onClick = function()
      if card.inst then
        D.ToggleFavorite(R.InstanceSlug(card.inst))
        card.owner:Refresh()
      end
    end,
  })
  card.name = W.Text(card, { role = "h3", family = "heading", color = "text", wrap = true })
  card.meta = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  wire(card)
  return card
end

-- Fills a card with an instance (texts only; the sizes follow in layoutCard).
local function paintCard(card, inst, owner, index, quests)
  card.owner, card.inst, card.index = owner, inst, index
  card.questText = IL.QuestText(quests.status, quests.count, L)
  card.art:SetInstance(inst)
  local plaques = IL.Plaques(inst, L)
  setPlaque(card.typeP, plaques.type.word, plaques.type.word:sub(1, 1))
  if plaques.faction then
    setPlaque(card.facP, plaques.faction.word, nil, K.FactionIconSpec(plaques.faction.value))
    card.facP:Show()
  else
    card.facP:Hide()
  end
  if plaques.announced then
    setPlaque(card.annP, plaques.announced)
    card.annP:Show()
  else
    card.annP:Hide()
  end
  setPlaque(card.questP, card.questText)
  setPlaque(card.levelP, plaques.level)
  card.name:SetText(R.Names(inst.n) or "")
  card.fav = isFavorite(inst)
  card.star:SetSelected(card.fav)
  card.star:SetIcon(card.fav and "star" or "star-outline")
  card.facPlaque, card.footExtra = plaques.faction, nil
end

-- Places picture, plaques and foot for a card width; returns the card height. The cut of the plaques is
-- decided by IL.FitPlaques (faction word, then type word, then the quest count leaves the top row).
local function layoutCard(card, width)
  local pad, gap = Cards.PAD, Cards.GAP
  local imageH = math.floor(width * 5 / 16)
  card.art:Layout(width, imageH)
  local ph = math.max(plaqueHeight(card.typeP), plaqueHeight(card.levelP), plaqueHeight(card.questP))
  local rowH = math.max(Cards.STAR, ph)
  local m = {
    gap = gap,
    pad = pad,
    imageH = imageH,
    plaqueH = ph,
    starW = Cards.STAR,
    starH = Cards.STAR,
    typeWord = plaqueWidth(card.typeP, false),
    typeIcon = plaqueWidth(card.typeP, true),
    quest = plaqueWidth(card.questP, false),
    level = plaqueWidth(card.levelP, false),
  }
  if card.facP:IsShown() then
    m.factionWord = plaqueWidth(card.facP, false)
    m.factionIcon = plaqueWidth(card.facP, true)
  end
  if card.annP:IsShown() then
    m.announced = plaqueWidth(card.annP, false)
  end
  local fit = IL.FitPlaques(width - 2 * pad, m)

  sizePlaque(card.typeP, not fit.typeWord, ph)
  card.typeP:ClearAllPoints()
  card.typeP:SetPoint("TOPLEFT", card.top, "TOPLEFT", pad, -pad - (rowH - ph) / 2)
  local prev = card.typeP
  if card.facP:IsShown() then
    sizePlaque(card.facP, not fit.factionWord, ph)
    card.facP:ClearAllPoints()
    card.facP:SetPoint("LEFT", prev, "RIGHT", gap, 0)
    prev = card.facP
  end
  if card.annP:IsShown() then
    sizePlaque(card.annP, false, ph)
    card.annP:ClearAllPoints()
    card.annP:SetPoint("LEFT", prev, "RIGHT", gap, 0)
  end
  card.star:ClearAllPoints()
  card.star:SetPoint("TOPRIGHT", card.top, "TOPRIGHT", -pad, -pad - (rowH - Cards.STAR) / 2)
  sizePlaque(card.questP, false, ph)
  card.questP:ClearAllPoints()
  card.questP:SetShown(fit.quest ~= "foot" and fit.quest ~= "none")
  if fit.quest == "top" then
    card.questP:SetPoint("RIGHT", card.star, "LEFT", -gap, 0)
  elseif fit.quest == "below" then
    card.questP:SetPoint("TOPRIGHT", card.top, "TOPRIGHT", -pad, -pad - rowH - gap)
  end
  sizePlaque(card.levelP, false, ph)
  card.levelP:ClearAllPoints()
  card.levelP:SetPoint("BOTTOMLEFT", card.top, "BOTTOMLEFT", pad, pad)

  -- Foot: name and facts on the card surface; the quest count joins them when the picture had no room.
  local inner = math.max(1, width - 2 * Cards.FOOT_PAD)
  local parts = IL.FootParts(card.inst, L, fit.quest == "foot" and card.questText or nil)
  card.name:ClearAllPoints()
  card.name:SetPoint("TOPLEFT", card, "TOPLEFT", Cards.FOOT_PAD, -(imageH + Cards.FOOT_PAD))
  card.name:SetWidth(inner)
  local nameH = ceil(card.name:GetStringHeight())
  card.meta:SetText(table.concat(parts, " · "))
  card.meta:ClearAllPoints()
  card.meta:SetPoint("TOPLEFT", card.name, "TOPLEFT", 0, -(nameH + 2))
  card.meta:SetWidth(inner)
  return imageH + Cards.FOOT_PAD + nameH + 2 + ceil(card.meta:GetStringHeight()) + Cards.FOOT_PAD
end

-- Grid -------------------------------------------------------------------------------------------------

-- Gap below a section header and between two sections, rows of a list.
local SECTION_GAP, ROW_GAP = 4, 2

local function sectionFrame(self, i)
  local f = self.sectionFrames[i]
  if not f then
    f = LV.NewSection(self.grid, function(section)
      self:ToggleSection(section.key)
    end)
    self.sectionFrames[i] = f
  end
  return f
end

-- Places the section headers and, in the open sections, the cards or the rows; returns the height.
local function layoutGrid(self, width)
  local grid = self.grid
  local list = self.cards
  local isList = self.view == "list"
  local columns = IL.Columns(width)
  local cw = IL.CardWidth(width, columns)
  local y, index = 0, 0
  local cols, rowH
  self.header:SetShown(isList)
  if isList then
    cols = IL.ListColumns(width, LV.Scale())
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", grid, "TOPLEFT")
    self.header:SetWidth(width)
    y = LV.LayoutHeader(self.header, cols) + SECTION_GAP
    rowH = list[1] and LV.RowHeight(list[1]) or LV.ROW_MIN
  end
  for i, section in ipairs(self.sections) do
    local frame = sectionFrame(self, i)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
    frame:SetWidth(width)
    y = y + LV.LayoutSection(frame, width) + SECTION_GAP
    local count = section.closed and 0 or #section.items
    if isList then
      for _ = 1, count do
        index = index + 1
        local row = list[index]
        LV.LayoutRow(row, cols, rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
        row:SetSize(width, rowH)
        y = y + rowH + ROW_GAP
      end
    else
      for first = index + 1, index + count, columns do
        local last = math.min(index + count, first + columns - 1)
        local rowTop = 0
        for i2 = first, last do
          rowTop = math.max(rowTop, layoutCard(list[i2], cw))
        end
        for i2 = first, last do
          list[i2]:ClearAllPoints()
          list[i2]:SetPoint("TOPLEFT", grid, "TOPLEFT", (i2 - first) * (cw + IL.GAP), -y)
          list[i2]:SetSize(cw, rowTop)
        end
        y = y + rowTop + IL.GAP
      end
      index = index + count
    end
    y = y + SECTION_GAP
  end
  for i = #self.sections + 1, #self.sectionFrames do
    self.sectionFrames[i]:Hide()
  end
  local height = math.max(0, y - SECTION_GAP)
  grid:SetSize(math.max(1, width), math.max(1, height))
  self.rowGrid:SetSize(math.max(1, width), math.max(1, height))
  self.columns = isList and 1 or columns
  return height
end

-- Filter bar -----------------------------------------------------------------------------------------

local function buildBar(self)
  local f = self.filter
  local bar = K.FilterBar(self, {
    count = function()
      return (f.kind ~= "all" and 1 or 0)
        + (f.faction ~= IL.NewFilter(self.defaultFaction).faction and 1 or 0)
        + (f.level and 1 or 0)
        + ((f.query or "") ~= "" and 1 or 0)
        + (f.favorites and 1 or 0)
        + (B.Normalize(f.bracket) ~= "all" and 1 or 0)
    end,
    reset = function()
      self:ResetFilter()
    end,
  })
  local function changed()
    self:Refresh()
  end
  local boxH = 26
  -- Controls are created in reading order (the keyboard focus follows creation order): search, corner button,
  -- view switch, type, level range, level, faction, checkboxes, sort. The placement is in bar:fgGridLayout.
  self.search = W.EditBox(bar, {
    placeholder = "instances.search",
    clear = true,
    onChange = function(text)
      f.query = text
      changed()
    end,
  })
  self.cornerButton = self.cornerFactory and self.cornerFactory(bar) or nil
  self.viewToggle = K.ViewToggle(bar, {
    views = IL.VIEWS,
    get = function()
      return self.view
    end,
    set = function(v)
      self.view = v
      self:Persist("view", v)
      changed()
    end,
  })
  self.kindToggle = K.ViewToggle(bar, {
    views = IL.KINDS,
    keyPrefix = "instances.card.kind.",
    get = function()
      return f.kind
    end,
    set = function(v)
      f.kind = v
      changed()
    end,
  })
  local options = {}
  for _, id in ipairs(B.CHOICES) do
    options[#options + 1] = { value = id, key = "instances.bracket." .. (tonumber(id) and "b" .. id or id) }
  end
  self.bracket = W.Dropdown(bar, {
    key = "instances.bracket.label",
    width = 150,
    options = options,
    get = function()
      return B.Normalize(f.bracket)
    end,
    set = function(v)
      f.bracket = v
      self:Persist("bracket", v)
      changed()
    end,
  })
  self.bracket:SetWidth(150)
  self.levelLabel = W.Text(bar, { key = "instances.card.levelBox", role = "ui", color = "textMuted" })
  self.levelBox = W.EditBox(bar, {
    placeholder = "instances.card.levelBox.ph",
    tooltip = "instances.card.levelBox",
    tooltipText = "instances.card.levelBox.tip",
    maxLetters = 2,
    clear = true,
    onChange = function(text)
      f.level = IL.ParseLevel(text)
      changed()
    end,
  })
  self.levelBox.fgName = function()
    return L["instances.card.levelBox.tip"]
  end
  if self.levelBox.edit.SetNumeric then
    self.levelBox.edit:SetNumeric(true)
  end
  self.levelBox:SetWidth(84)
  self.faction = bar:AddGroup(K.FactionButtons(bar, {
    withAll = true,
    get = function()
      return f.faction
    end,
    set = function(v)
      f.faction = v
      if self.onFaction then
        self.onFaction(v)
      end
      changed()
    end,
  }))
  self.onlyFav = bar:AddToggle({
    key = "instances.card.onlyFav",
    get = function()
      return f.favorites
    end,
    set = function(on)
      f.favorites = on
      changed()
    end,
  })
  self.favFirst = bar:AddToggle({
    key = "instances.card.favFirst",
    get = function()
      return f.favoritesFirst
    end,
    set = function(on)
      f.favoritesFirst = on
      changed()
    end,
  })
  self.orderToggle = bar:AddToggle({
    key = "instances.order.desc",
    get = function()
      return f.desc == true
    end,
    set = function(on)
      f.desc = on
      self:Persist("desc", on)
      changed()
    end,
  })
  self.sortLabel = W.Text(bar, { key = "instances.sort.label", role = "ui", color = "textSecondary" })
  self.sortToggle = K.ViewToggle(bar, {
    views = IL.SORTS,
    keyPrefix = "instances.sort.",
    get = function()
      return f.sort
    end,
    set = function(v)
      f.sort = v
      self:Persist("sort", v)
      changed()
    end,
  })
  self.countText = W.Text(bar, { role = "ui", color = "textMuted", justify = "RIGHT" })
  bar:Refresh()
  self.resetBtn = bar.resetButton

  -- Three rows, every item centered on the line of its row. A row keeps its left and right items on one line
  -- while they fit and wraps the right items under the left ones (still right aligned) when they do not.
  local owner = self
  local GAP, LINE_GAP = Theme.space.md, Theme.space.md
  -- Item: w, h, cy (center of the control, default h / 2), place(x, top).
  local function item(w, h, cy, place)
    return { w = w, h = h, cy = cy or h / 2, place = place }
  end
  local function at(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
  end
  local function plain(frame, w, h, cy)
    return item(w, h, cy, function(x, top)
      at(frame, x, top)
    end)
  end
  local function span(items)
    local w = 0
    for i, it in ipairs(items) do
      w = w + it.w + (i > 1 and GAP or 0)
    end
    return w
  end
  local function wrap(items, width)
    local lines, line, x = {}, {}, 0
    for _, it in ipairs(items) do
      if #line > 0 and x + GAP + it.w > width then
        lines[#lines + 1], line, x = line, {}, 0
      end
      x = x + (#line > 0 and GAP or 0) + it.w
      line[#line + 1] = it
    end
    if #line > 0 then
      lines[#lines + 1] = line
    end
    return lines
  end
  -- Extent of sets of items above and below their common center line.
  local function extent(...)
    local above, below = 0, 0
    for _, items in ipairs({ ... }) do
      for _, it in ipairs(items) do
        above, below = math.max(above, it.cy), math.max(below, it.h - it.cy)
      end
    end
    return above, below
  end
  local function put(items, x, y, above)
    for _, it in ipairs(items) do
      it.place(x, y + above - it.cy)
      x = x + it.w + GAP
    end
  end
  local function placeRow(left, right, width, y)
    if #left == 0 and #right == 0 then
      return y
    end
    local both = #left > 0 and #right > 0
    if span(left) + (both and GAP or 0) + span(right) <= width then
      local above, below = extent(left, right)
      put(left, 0, y, above)
      put(right, width - span(right), y, above)
      return y + above + below
    end
    for _, items in ipairs({ left, right }) do
      for _, line in ipairs(wrap(items, width)) do
        local above, below = extent(line)
        put(line, items == right and (width - span(line)) or 0, y, above)
        y = y + above + below + Theme.space.sm
      end
    end
    return y - Theme.space.sm
  end

  function bar.fgGridLayout(_, width)
    local function checkbox(box)
      local w = math.min(width, 16 + 8 + math.ceil(box.label:GetStringWidth()) + 4)
      box:SetWidth(w)
      return plain(box, w, 22)
    end

    -- Row 1: search left, corner button and view switch right.
    local right = {}
    local cb = owner.cornerButton
    if cb then
      cb:SetWidth(cb:Fit(width))
      right[#right + 1] = plain(cb, cb:GetWidth(), cb:GetHeight())
    end
    local view = owner.viewToggle
    right[#right + 1] = plain(view, view:GetWidth(), view:GetHeight())
    local room = width - span(right) - GAP
    local searchW = room >= 140 and math.min(room, 480) or math.min(width, 480)
    owner.search:SetWidth(searchW)
    local y = placeRow({ plain(owner.search, searchW, boxH) }, right, width, 0)

    -- Row 2: type, level range, level, faction. Captions sit above their field, all fields on one line.
    local fieldY = W.DROPDOWN_FIELD_Y
    local kind = owner.kindToggle
    local row2 = {
      plain(kind, kind:GetWidth(), kind:GetHeight()),
      plain(owner.bracket, 150, owner.bracket:GetHeight(), fieldY + 12),
      item(84, fieldY + boxH, fieldY + boxH / 2, function(x, top)
        at(owner.levelLabel, x, top)
        at(owner.levelBox, x, top + fieldY)
      end),
    }
    local group = owner.faction
    local gw = math.min(group.NaturalWidth(), width)
    group:SetWidth(gw)
    local gh = group:fgGridLayout(gw)
    local bh = group.buttons[1] and group.buttons[1]:GetHeight() or 28
    row2[#row2 + 1] = plain(group, gw, gh, gh - bh / 2)
    y = placeRow(row2, {}, width, y + LINE_GAP)

    -- Row 3: checkboxes left; filter count and reset, sort and the counter right.
    local left, tail = {}, {}
    for _, box in ipairs({ owner.onlyFav, owner.favFirst, owner.orderToggle }) do
      left[#left + 1] = checkbox(box)
    end
    local count, reset = bar.countText, owner.resetBtn
    if count and count:IsShown() then
      tail[#tail + 1] = plain(count, math.ceil(count:GetStringWidth()) + 2, math.ceil(count:GetStringHeight()))
    end
    if reset and reset:IsShown() then
      reset:SetWidth(reset:Fit(width))
      tail[#tail + 1] = plain(reset, reset:GetWidth(), 24)
    end
    local label, sort = owner.sortLabel, owner.sortToggle
    local lw, sh = math.ceil(label:GetStringWidth()), sort:GetHeight()
    tail[#tail + 1] = item(lw + Theme.space.sm + sort:GetWidth(), sh, sh / 2, function(x, top)
      at(label, x, top + (sh - math.ceil(label:GetStringHeight())) / 2)
      at(sort, x + lw + Theme.space.sm, top)
    end)
    local total = owner.countText
    local tw = math.ceil(total:GetStringWidth()) + 2
    total:SetWidth(tw)
    tail[#tail + 1] = plain(total, tw, math.ceil(total:GetStringHeight()))
    y = placeRow(left, tail, width, y + LINE_GAP)

    bar:SetHeight(math.max(1, y))
    return y
  end
  return bar
end

-- Public -----------------------------------------------------------------------------------------------

-- :SetFilter(partial) merges known fields (kind, faction, level, query, favorites, favoritesFirst, sort, desc,
-- bracket).
function Cards.SetFilter(self, partial)
  for _, key in ipairs({
    "kind",
    "faction",
    "level",
    "query",
    "favorites",
    "favoritesFirst",
    "sort",
    "desc",
    "bracket",
  }) do
    if partial[key] ~= nil then
      self.filter[key] = partial[key]
    end
  end
  if partial.level == false then
    self.filter.level = nil
  end
  self:Refresh()
end

function Cards.ResetFilter(self)
  local f = IL.NewFilter(self.defaultFaction)
  f.sort, f.desc, f.favoritesFirst = self.filter.sort, self.filter.desc, self.filter.favoritesFirst
  -- In place: the controls of the bar hold this table.
  for key in pairs(self.filter) do
    self.filter[key] = nil
  end
  for key, value in pairs(f) do
    self.filter[key] = value
  end
  if self.onFaction then
    self.onFaction(self.filter.faction)
  end
  self:Persist("bracket", self.filter.bracket)
  self.search.edit:SetText("")
  self.levelBox.edit:SetText("")
  self:Refresh()
end

-- tab: the tab of the instance to open ("map" for the map button of a row).
function Cards.Open(self, inst, tab)
  if inst and self.onOpen then
    self.onOpen(inst, tab)
  end
end

-- Tells the owner a choice that is worth keeping: view, sort, desc, bracket, closed (the set of collapsed
-- sections).
function Cards.Persist(self, key, value)
  if self.onPersist then
    self.onPersist(key, value)
  end
end

-- Collapses or expands a section of the list; the choice is kept.
function Cards.ToggleSection(self, key)
  self.closed = B.WithClosed(self.closed, key, not self.closed[key])
  self:Persist("closed", self.closed)
  self:Refresh()
end

-- Moves the keyboard cursor to card `index` (clamped) and shows its rim and tooltip while the grid has focus.
function Cards.SetCursor(self, index)
  local old = self.cursorCard
  if #self.cards == 0 then
    self.cursor, self.cursorCard = 1, nil
    return
  end
  self.cursor = math.max(1, math.min(#self.cards, index or 1))
  local card = self.cards[self.cursor]
  self.cursorCard = card
  if old and old ~= card then
    setHighlight(old, false)
  end
  self.proxy:ClearAllPoints()
  self.proxy:SetAllPoints(card)
  if self.cursorShown then
    setHighlight(card, true)
    ns.Focus.set(self.proxy)
  end
end

local KEY_MOVES = { LEFT = "left", RIGHT = "right", UP = "up", DOWN = "down", HOME = "home", END = "end" }

-- Up and down inside a section follow the rows of its cards; at the top or the bottom edge the cursor goes to the
-- neighbour section (same column where it exists).
local function moveVertical(self, move)
  local columns = self.columns or 1
  for i, spot in ipairs(self.spots) do
    if self.cursor >= spot.first and self.cursor < spot.first + spot.count then
      local at = self.cursor - spot.first + 1
      local to = IL.Move(at, spot.count, columns, move)
      if to ~= at then
        return spot.first + to - 1
      end
      local other = self.spots[i + (move == "up" and -1 or 1)]
      if not other then
        return self.cursor
      end
      local column = (at - 1) % columns
      if move == "up" then
        local lastRowStart = other.first + (math.ceil(other.count / columns) - 1) * columns
        return math.min(other.first + other.count - 1, lastRowStart + column)
      end
      return other.first + math.min(column, other.count - 1)
    end
  end
  return self.cursor
end

-- Keys of a focused grid. Returns true when the key was used.
function Cards.HandleKey(self, key)
  local move = KEY_MOVES[key]
  if move then
    if move == "up" or move == "down" then
      self:SetCursor(moveVertical(self, move))
    else
      self:SetCursor(IL.Move(self.cursor, #self.cards, self.columns or 1, move))
    end
    return true
  end
  local card = self.cursorCard
  if not card or not ns.Focus.recent() then
    return false
  end
  if key == "ENTER" or key == "SPACE" then
    self:Open(card.inst)
    return true
  elseif key == "F" and not (IsControlKeyDown and IsControlKeyDown()) then
    D.ToggleFavorite(R.InstanceSlug(card.inst))
    self:Refresh()
    return true
  end
  return false
end

local function questInfo(inst, faction)
  local status = DA.Ensure()
  if status ~= "ok" then
    return { status = status }
  end
  return { status = status, count = #R.Quests(inst, faction) }
end

-- Recomputes the list of the filter and repaints cards or rows in their sections; keeps the cursor on the same
-- instance.
function Cards.Refresh(self)
  local hasData = K.HasData("Instances")
  local faction = (self.filter.faction == "A" or self.filter.faction == "H") and self.filter.faction or nil
  local player = B.PlayerLevel()
  local list = hasData
      and IL.Apply(self.filter, nil, nil, {
        playerLevel = player,
        questCount = function(inst)
          return questInfo(inst, faction).count
        end,
      })
    or {}
  local keep = self.cursorCard and self.cursorCard.inst
  self.shown = list
  self.sections = B.Sections(list, self.filter.desc, self.closed, self.filter.favoritesFirst and isFavorite or nil)
  local visible, spots = {}, {}
  for _, section in ipairs(self.sections) do
    if not section.closed then
      spots[#spots + 1] = { first = #visible + 1, count = #section.items }
      for _, inst in ipairs(section.items) do
        visible[#visible + 1] = inst
      end
    end
  end
  self.spots = spots
  self.cards = {}
  local isList = self.view == "list"
  local on, off = isList and self.rowGrid or self.grid, isList and self.grid or self.rowGrid
  off:Sync({}, function() end)
  self.rowGrid:SetShown(isList)
  on:Sync(visible, function(card, inst)
    self.cards[#self.cards + 1] = card
    local quests = questInfo(inst, faction)
    if isList then
      LV.PaintRow(card, inst, self, #self.cards, quests, player)
    else
      paintCard(card, inst, self, #self.cards, quests)
    end
  end)
  for i, section in ipairs(self.sections) do
    local frame = sectionFrame(self, i)
    LV.PaintSection(frame, section)
    frame:Show()
  end
  LV.SetHeader(self.header, self.filter.sort, self.filter.desc)
  self.countText:SetText(string.format(L["instances.card.count"], #list, IL.Total()))
  self.bar:Refresh()
  for _, ctl in ipairs({
    self.kindToggle,
    self.sortToggle,
    self.orderToggle,
    self.viewToggle,
    self.bracket,
    self.faction,
    self.onlyFav,
    self.favFirst,
  }) do
    if ctl.Refresh then
      ctl.Refresh()
    end
  end
  local favorites = D.FavoriteCount()
  self.state = IL.State(hasData, #list, self.filter, favorites)
  self:ShowState()
  local cursor = 1
  if keep then
    for i, inst in ipairs(visible) do
      if inst == keep then
        cursor = i
        break
      end
    end
  end
  self:SetCursor(cursor)
  if self.width then
    self:Layout(self.width)
  end
end

local STATE_TEXT = {
  noData = { "kit.noData" },
  empty = { "instances.card.empty" },
  noFavorites = { "instances.card.noFavorites", "instances.card.noFavorites.hint" },
}

function Cards.ShowState(self)
  local text = STATE_TEXT[self.state]
  self.empty:SetShown(text ~= nil)
  self.grid:SetShown(text == nil)
  self.proxy:SetShown(text == nil)
  if text then
    self.empty:SetTexts(L[text[1]], text[2] and L[text[2]] or "")
    -- Only a filter can empty the list; the other states have nothing to reset.
    self.empty:SetAction(self.state == "empty" and W.EMPTY_RESET or nil, function()
      self:ResetFilter()
    end)
  end
end

-- Lays the whole widget out for a width and sets .height (bar, gap, grid or the state).
function Cards.Layout(self, width)
  width = math.max(1, math.floor(width or self:GetWidth()))
  self.width = width
  self.bar:ClearAllPoints()
  self.bar:SetPoint("TOPLEFT", self, "TOPLEFT")
  self.bar:SetWidth(width)
  local y = self.bar:fgGridLayout(width) + Cards.BAR_GAP
  self.grid:ClearAllPoints()
  self.grid:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
  local body
  if self.state == "ok" then
    body = layoutGrid(self, width)
  else
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.empty:Relayout(width)
    body = math.max(160, self.empty.minHeight)
    self.empty:SetSize(width, body)
  end
  self.height = y + body
  self:SetSize(width, math.max(1, self.height))
  return self.height
end

-- Gives every picture back (texture memory); the pictures come again with the next Refresh or show.
function Cards.Release(self)
  for _, card in ipairs(self.cards) do
    card.art:Release()
  end
end

-- opts: onOpen(inst, tab), onFaction(value) after the faction choice or a reset, onPersist(key, value) after a choice
-- worth keeping (view, sort, desc, bracket, closed), faction (default of the faction filter: "A", "H"; nil = the
-- player's own), filter (start values, see SetFilter), view ("list" or "cards", default "cards"), closed (set of
-- collapsed section keys), corner (function(parent) -> button for the first bar row, beside the view switch).
function Cards.Create(parent, opts)
  opts = opts or {}
  local self = CreateFrame("Frame", nil, parent)
  self.onOpen = opts.onOpen
  self.onFaction = opts.onFaction
  self.onPersist = opts.onPersist
  self.view = opts.view == "list" and "list" or "cards"
  self.closed = B.WithClosed(opts.closed, "", false)
  self.sections, self.spots, self.sectionFrames = {}, {}, {}
  self.defaultFaction = opts.faction or K.PlayerFaction()
  self.filter = IL.NewFilter(self.defaultFaction)
  for key, value in pairs(opts.filter or {}) do
    self.filter[key] = value
  end
  self.filter.bracket = B.Normalize(self.filter.bracket)
  self.cards, self.cursor, self.height, self.columns = {}, 1, 0, 1
  self.cornerFactory = opts.corner
  self.bar = buildBar(self)
  self.grid = K.GridPool(self, 1, newCard, IL.GAP)
  self.rowGrid = K.GridPool(self.grid, 1, newRow, ROW_GAP)
  self.rowGrid:SetPoint("TOPLEFT", self.grid, "TOPLEFT")
  self.header = LV.NewHeader(self.grid, function(id)
    local f = self.filter
    f.desc = f.sort == id and not f.desc or false
    f.sort = id
    self:Persist("sort", f.sort)
    self:Persist("desc", f.desc)
    self:Refresh()
  end)
  self.empty = W.EmptyState(self, { text = "instances.card.empty", icon = "search" })
  self.empty:Hide()
  for name, fn in pairs(Cards) do
    if type(fn) == "function" and name ~= "Create" then
      self[name] = fn
    end
  end

  -- One tab stop for the grid: the proxy follows the card under the cursor, so the focus ring sits on it.
  self.proxy = CreateFrame("Frame", nil, self.grid)
  self.proxy:EnableMouse(false)
  ns.Focus.register(self.proxy, function()
    self:Open(self.cursorCard and self.cursorCard.inst)
  end)
  self.proxy.fgName = function()
    local card = self.cursorCard
    return card and card.inst and ns.T(card.inst.n) or nil
  end
  self.proxy.fgOnFocus = function(proxy)
    self.cursorShown = true
    if self.cursorCard then
      setHighlight(self.cursorCard, true)
      showTip(self.cursorCard)
    end
    if proxy.EnableKeyboard then
      proxy:EnableKeyboard(true)
    end
  end
  self.proxy.fgOnBlur = function(proxy)
    self.cursorShown = false
    if self.cursorCard then
      setHighlight(self.cursorCard, false)
    end
    ns.HideTooltip()
    if proxy.EnableKeyboard then
      proxy:EnableKeyboard(false)
    end
  end
  self.proxy:SetScript("OnKeyDown", function(proxy, key)
    local _, handled = ns.Safe("instance-cards-key", self.HandleKey, self, key)
    ns.PropagateKeys(proxy, not handled)
  end)

  self:SetScript("OnHide", self.Release)
  ns.On("FG_INSTANCE_DATA", function()
    if self:IsShown() then
      self:Refresh()
    end
  end)
  self:Refresh()
  return self
end
