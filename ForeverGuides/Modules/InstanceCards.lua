-- Card grid of the instances: filter bar, one card per instance (picture with plaques, foot with name and
-- facts), the states of an empty grid and the keyboard cursor. The page that owns it (InstancesPage) opens an
-- instance through opts.onOpen / cards.onOpen. Texts and order come from Modules/InstanceListLogic.lua, the
-- picture from Modules/InstanceArt.lua. A card keeps no text on the picture: every label sits on a plaque.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit
local IL, Art, D = ns.InstanceListLogic, ns.InstanceArt, ns.InstanceDisplay
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
  ["instances.card.reset"] = "Reset filters",
  ["instances.card.count"] = "%d of %d",
  ["instances.card.fav"] = "Favorite",
  ["instances.card.fav.tip"] = "Marks or unmarks this instance. Key F on a focused card.",
  ["instances.card.empty"] = "No instance matches.",
  ["instances.card.noFavorites"] = "No favorites yet.",
  ["instances.card.noFavorites.hint"] = "The star on a card remembers it.",
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
  ["instances.card.reset"] = "Filter zurücksetzen",
  ["instances.card.count"] = "%d von %d",
  ["instances.card.fav"] = "Favorit",
  ["instances.card.fav.tip"] = "Markiert die Instanz oder nimmt die Marke weg. Taste F auf einer fokussierten Karte.",
  ["instances.card.empty"] = "Keine Instanz passt.",
  ["instances.card.noFavorites"] = "Noch keine Favoriten.",
  ["instances.card.noFavorites.hint"] = "Der Stern auf einer Karte merkt sie.",
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
    if not p.icon then
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
  ns.ShowTooltip(card, name, nil, { lines = IL.TipLines(inst, L, card.questText), anchor = "ANCHOR_RIGHT" })
end

local function setHighlight(card, on)
  card.ring.show(on)
  card.rim.show(not on)
end

local function newCard(grid)
  local card = CreateFrame("Button", nil, grid)
  W.Fill(card, "surface", 1)
  card.rim = W.Border(card, "white", 0.3)
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
  card.ring = W.Border(card, "accent2", 1, 2)
  card.ring.show(false)
  card:SetScript("OnEnter", function(self)
    setHighlight(self, true)
    showTip(self)
  end)
  card:SetScript("OnLeave", function(self)
    if not (self.owner and self.owner.cursorShown and self.owner.cursorCard == self) then
      setHighlight(self, false)
    end
    ns.HideTooltip()
  end)
  card:SetScript(
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

local function layoutGrid(self, width)
  local grid = self.grid
  local columns = IL.Columns(width)
  local cw = IL.CardWidth(width, columns)
  local list = self.cards
  local y, rows = 0, 0
  for first = 1, #list, columns do
    local rowH = 0
    for i = first, math.min(#list, first + columns - 1) do
      rowH = math.max(rowH, layoutCard(list[i], cw))
    end
    for i = first, math.min(#list, first + columns - 1) do
      local col = i - first
      list[i]:ClearAllPoints()
      list[i]:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (cw + IL.GAP), -y)
      list[i]:SetSize(cw, rowH)
    end
    y = y + rowH + IL.GAP
    rows = rows + 1
  end
  local height = math.max(0, y - IL.GAP)
  grid:SetSize(math.max(1, width), math.max(1, height))
  self.columns = columns
  return height
end

-- Filter bar -----------------------------------------------------------------------------------------

local function buildBar(self)
  local bar = CreateFrame("Frame", nil, self)
  local f = self.filter
  local function changed()
    self:Refresh()
  end
  self.search = W.EditBox(bar, {
    placeholder = "instances.search",
    clear = true,
    onChange = function(text)
      f.query = text
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
  self.levelLabel = W.Text(bar, { key = "instances.card.levelBox", role = "ui", color = "textSecondary" })
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
  -- The clear button sets the text from code, which does not report a change.
  self.levelBox.clearButton:HookScript("OnClick", function()
    f.level = nil
    changed()
  end)
  self.faction = K.FactionButtons(bar, {
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
  })
  self.onlyFav = W.Checkbox(bar, {
    key = "instances.card.onlyFav",
    get = function()
      return f.favorites
    end,
    set = function(on)
      f.favorites = on
      changed()
    end,
  })
  self.favFirst = W.Checkbox(bar, {
    key = "instances.card.favFirst",
    get = function()
      return f.favoritesFirst
    end,
    set = function(on)
      f.favoritesFirst = on
      changed()
    end,
  })
  self.resetBtn = W.Button(bar, {
    key = "instances.card.reset",
    variant = "ghost",
    onClick = function()
      self:ResetFilter()
    end,
  })
  self.countText = W.Text(bar, { role = "ui", color = "textMuted", justify = "RIGHT" })
  return bar
end

-- Flows the controls of the bar into rows; returns the bar height.
local function layoutBar(self, width)
  local bar, gap = self.bar, Cards.BAR_GAP
  local y, x, rowH = 0, 0, 0
  local function put(widget, w, h)
    if x > 0 and x + w > width then
      y, x, rowH = y + rowH + gap, 0, 0
    end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
    x = x + w + gap
    rowH = math.max(rowH, h)
  end
  local function newRow()
    if x > 0 then
      y, x, rowH = y + rowH + gap, 0, 0
    end
  end
  local boxH = 26
  self.search:SetWidth(math.min(width, 360))
  put(self.search, math.min(width, 360), boxH)
  -- A label with its control stays together: the pair wraps as one.
  local function pair(label, control, controlW, controlH)
    local labelW = ceil(label:GetStringWidth())
    put(label, labelW + 6 + controlW, math.max(controlH, ceil(label:GetStringHeight())))
    control:ClearAllPoints()
    control:SetPoint("LEFT", label, "RIGHT", 6, 0)
  end
  pair(self.sortLabel, self.sortToggle, self.sortToggle:GetWidth(), self.sortToggle:GetHeight())
  newRow()
  put(self.kindToggle, self.kindToggle:GetWidth(), self.kindToggle:GetHeight())
  local levelW = 84
  self.levelBox:SetWidth(levelW)
  pair(self.levelLabel, self.levelBox, levelW, boxH)
  newRow()
  self.faction:SetWidth(width)
  local fh = self.faction:fgGridLayout(width)
  self.faction:ClearAllPoints()
  self.faction:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -y)
  y = y + fh + gap
  x, rowH = 0, 0
  for _, box in ipairs({ self.onlyFav, self.favFirst }) do
    local w = math.min(width, 16 + 8 + ceil(box.label:GetStringWidth()) + 4)
    box:SetWidth(w)
    put(box, w, math.max(22, ceil(box.label:GetStringHeight())))
  end
  local rw = self.resetBtn:Fit(width)
  self.resetBtn:SetWidth(rw)
  put(self.resetBtn, rw, self.resetBtn:GetHeight())
  local cw = ceil(self.countText:GetStringWidth()) + 2
  self.countText:SetWidth(cw)
  put(self.countText, cw, ceil(self.countText:GetStringHeight()))
  y = y + rowH
  bar:SetSize(math.max(1, width), math.max(1, y))
  return y
end

-- Public -----------------------------------------------------------------------------------------------

-- :SetFilter(partial) merges known fields (kind, faction, level, query, favorites, favoritesFirst, sort).
function Cards.SetFilter(self, partial)
  for _, key in ipairs({ "kind", "faction", "level", "query", "favorites", "favoritesFirst", "sort" }) do
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
  f.sort, f.favoritesFirst = self.filter.sort, self.filter.favoritesFirst
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
  self.search.edit:SetText("")
  self.levelBox.edit:SetText("")
  self:Refresh()
end

function Cards.Open(self, inst)
  if inst and self.onOpen then
    self.onOpen(inst)
  end
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

-- Keys of a focused grid. Returns true when the key was used.
function Cards.HandleKey(self, key)
  local move = KEY_MOVES[key]
  if move then
    self:SetCursor(IL.Move(self.cursor, #self.cards, self.columns or 1, move))
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

-- Recomputes the list of the filter and repaints the cards; keeps the cursor on the same instance.
function Cards.Refresh(self)
  local hasData = K.HasData("Instances")
  local list = hasData and IL.Apply(self.filter) or {}
  local keep = self.cursorCard and self.cursorCard.inst
  local faction = (self.filter.faction == "A" or self.filter.faction == "H") and self.filter.faction or nil
  self.shown = list
  self.cards = {}
  self.grid:Sync(list, function(card, inst)
    self.cards[#self.cards + 1] = card
    paintCard(card, inst, self, #self.cards, questInfo(inst, faction))
  end)
  self.countText:SetText(string.format(L["instances.card.count"], #list, IL.Total()))
  self.resetBtn:SetShown(not IL.IsDefault(self.filter, self.defaultFaction))
  for _, ctl in ipairs({ self.kindToggle, self.sortToggle, self.faction, self.onlyFav, self.favFirst }) do
    ctl.Refresh()
  end
  local favorites = D.FavoriteCount()
  self.state = IL.State(hasData, #list, self.filter, favorites)
  self:ShowState()
  local cursor = 1
  if keep then
    for i, inst in ipairs(list) do
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
  end
end

-- Lays the whole widget out for a width and sets .height (bar, gap, grid or the state).
function Cards.Layout(self, width)
  width = math.max(1, math.floor(width or self:GetWidth()))
  self.width = width
  self.bar:ClearAllPoints()
  self.bar:SetPoint("TOPLEFT", self, "TOPLEFT")
  local y = layoutBar(self, width) + Cards.BAR_GAP
  self.grid:ClearAllPoints()
  self.grid:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
  local body
  if self.state == "ok" then
    body = layoutGrid(self, width)
  else
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.empty:SetSize(width, 160)
    self.empty:Relayout(width)
    body = 160
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

-- opts: onOpen(inst), onFaction(value) after the faction choice or a reset, faction (default of the faction filter: "A", "H"; nil = the player's own), filter (start
-- values, see SetFilter).
function Cards.Create(parent, opts)
  opts = opts or {}
  local self = CreateFrame("Frame", nil, parent)
  self.onOpen = opts.onOpen
  self.onFaction = opts.onFaction
  self.defaultFaction = opts.faction or K.PlayerFaction()
  self.filter = IL.NewFilter(self.defaultFaction)
  for key, value in pairs(opts.filter or {}) do
    self.filter[key] = value
  end
  self.cards, self.cursor, self.height, self.columns = {}, 1, 0, 1
  self.bar = buildBar(self)
  self.grid = K.GridPool(self, 1, newCard, IL.GAP)
  self.empty = W.EmptyState(self, { text = "instances.card.empty" })
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
