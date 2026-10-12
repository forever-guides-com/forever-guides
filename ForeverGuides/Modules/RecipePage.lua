-- Page "Professions" (/fg berufe): the recipe database of one profession. Controls on top (profession,
-- search, source, filters, skill slider with the color bands of the chosen recipe), the recipe list
-- on the left (categories like the game's profession window, or sections per skill color), the
-- detail with source, reagents and who knows the recipe on the right. The list is a virtual
-- W.ScrollList, so 600 recipes only build the visible rows.
-- Data: Modules/RecipeData.lua, logic: RecipeLogic.lua, known recipes: RecipeKnown.lua.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local R, Data, Known = ns.RecipeLogic, ns.RecipeAccess, ns.RecipeKnown
local Route, Shop = ns.ProfessionRouteLogic, ns.ProfessionShop

local P = {}
ns.RecipePage = P

local CONTROL_GAP = 12
local ROW_GAP = 8
local DROPDOWN_W, SEARCH_W, SOURCE_W, TOGGLE_W, SKILL_W = 220, 200, 150, 190, 380
local STRIP_H = 10
local WIDE = 560
local SPLIT_GAP = 14
local MIN_ROWS = 8
local ICON = 18
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

ns.AddLocale("enUS", {
  ["recipes.intro"] = "Recipe database per profession",
  ["recipes.profession"] = "Profession",
  ["recipes.search"] = "Search",
  ["recipes.searchPh"] = "Recipe name",
  ["recipes.source"] = "Learned from",
  ["recipes.src.all"] = "All",
  ["recipes.src.t"] = "Trainer",
  ["recipes.src.i"] = "Recipe item",
  ["recipes.src.u"] = "Unknown",
  ["recipes.changed"] = "Classic changes",
  ["recipes.changedTip"] = "Only recipes changed against Classic.",
  ["recipes.learnable"] = "Learnable only",
  ["recipes.learnableTip"] = "Only recipes you can learn at the chosen skill.",
  ["recipes.unknown"] = "Unlearned only",
  ["recipes.unknownTip"] = "Hides recipes this character knows.",
  ["recipes.removed"] = "Show removed",
  ["recipes.removedTip"] = "Also lists recipes removed in Forever.",
  ["recipes.skill"] = "Skill",
  ["recipes.count"] = "%d of %d recipes",
  ["recipes.noneKnown"] = "Open the profession window to record your recipes",
  ["recipes.empty"] = "No recipes match.",
  ["recipes.pick"] = "Pick a recipe.",
  ["recipes.other"] = "Other",
  ["recipes.band.orange"] = "Orange",
  ["recipes.band.yellow"] = "Yellow",
  ["recipes.band.green"] = "Green",
  ["recipes.band.gray"] = "Gray",
  ["recipes.band.locked"] = "Not learnable yet",
  ["recipes.band.none"] = "No skill data",
  ["recipes.bandAt"] = "At skill %d: %s",
  ["recipes.bandsTip"] = "Colors of the chosen recipe",
  ["recipes.srcTrainer"] = "Trainer",
  ["recipes.srcTrainerRank"] = "Trainer (%s)",
  ["recipes.srcItem"] = "Recipe item",
  ["recipes.srcUnknown"] = "Source unknown",
  ["recipes.item"] = "Item %d",
  ["recipes.reagents"] = "Reagents",
  ["recipes.reagentCount"] = "%dx, have %d",
  ["recipes.crafts"] = "Craftable: %dx",
  ["recipes.knownBy"] = "Learned by: %s",
  ["recipes.learned"] = "Learned: %s",
  ["recipes.changedNote"] = "Changed against Classic",
  ["recipes.removedNote"] = "Removed in Forever",
  ["recipes.linkHint"] = "Shift+click: link to chat",
})
ns.AddLocale("deDE", {
  ["recipes.intro"] = "Rezeptdatenbank je Beruf",
  ["recipes.profession"] = "Beruf",
  ["recipes.search"] = "Suche",
  ["recipes.searchPh"] = "Rezeptname",
  ["recipes.source"] = "Gelehrt von",
  ["recipes.src.all"] = "Alle",
  ["recipes.src.t"] = "Lehrer",
  ["recipes.src.i"] = "Rezept-Item",
  ["recipes.src.u"] = "Unbekannt",
  ["recipes.changed"] = "Classic-Änderungen",
  ["recipes.changedTip"] = "Nur Rezepte, die sich gegenüber Classic ändern.",
  ["recipes.learnable"] = "Nur lernbare",
  ["recipes.learnableTip"] = "Nur Rezepte, die du beim gewählten Skill lernen kannst.",
  ["recipes.unknown"] = "Nur unbekannte",
  ["recipes.unknownTip"] = "Blendet Rezepte aus, die dieser Charakter kennt.",
  ["recipes.removed"] = "Entfernte zeigen",
  ["recipes.removedTip"] = "Zeigt auch Rezepte, die in Forever entfernt sind.",
  ["recipes.skill"] = "Skill",
  ["recipes.count"] = "%d von %d Rezepten",
  ["recipes.noneKnown"] = "Berufefenster öffnen erfasst deine Rezepte",
  ["recipes.empty"] = "Keine Treffer.",
  ["recipes.pick"] = "Rezept wählen.",
  ["recipes.other"] = "Sonstige",
  ["recipes.band.orange"] = "Orange",
  ["recipes.band.yellow"] = "Gelb",
  ["recipes.band.green"] = "Grün",
  ["recipes.band.gray"] = "Grau",
  ["recipes.band.locked"] = "Noch nicht lernbar",
  ["recipes.band.none"] = "Ohne Skill-Angabe",
  ["recipes.bandAt"] = "Bei Skill %d: %s",
  ["recipes.bandsTip"] = "Farben des gewählten Rezepts",
  ["recipes.srcTrainer"] = "Lehrer",
  ["recipes.srcTrainerRank"] = "Lehrer (%s)",
  ["recipes.srcItem"] = "Rezept-Item",
  ["recipes.srcUnknown"] = "Quelle unbekannt",
  ["recipes.item"] = "Item %d",
  ["recipes.reagents"] = "Reagenzien",
  ["recipes.reagentCount"] = "%dx, Besitz %d",
  ["recipes.crafts"] = "Herstellbar: %dx",
  ["recipes.knownBy"] = "Gelernt von: %s",
  ["recipes.learned"] = "Gelernt: %s",
  ["recipes.changedNote"] = "Geändert gegenüber Classic",
  ["recipes.removedNote"] = "In Forever entfernt",
  ["recipes.linkHint"] = "Umschalt+Klick: Link in den Chat",
})

-- Game helpers ---------------------------------------------------------------------------------------

-- "de" or "en" by the addon language.
local function lang()
  return ns.T({ de = "de", en = "en" })
end

local function itemApi(name)
  local c = rawget(_G, "C_Item")
  local fn = type(c) == "table" and c[name] or nil
  return type(fn) == "function" and fn or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

local requested = {}

-- Item name from the client; asks for the data once when it is not cached yet.
local function clientItemName(id)
  local get = itemApi("GetItemNameByID") or rawget(_G, "GetItemInfo")
  local name = call(get, id)
  if type(name) == "string" and name ~= "" then
    return name
  end
  if not requested[id] then
    requested[id] = true
    call(itemApi("RequestLoadItemDataByID"), id)
  end
end

local function itemIcon(id)
  local icon = call(itemApi("GetItemIconByID") or rawget(_G, "GetItemIcon"), id)
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

local function spellTexture(id)
  local api = rawget(_G, "C_Spell")
  local icon = call(type(api) == "table" and api.GetSpellTexture or rawget(_G, "GetSpellTexture"), id)
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

local function iconPath(name)
  return type(name) == "string" and name ~= "" and ("Interface\\Icons\\" .. name) or nil
end

-- The icon of a recipe: the data icon, else the item or the spell icon from the client.
local function recipeIcon(r)
  return iconPath(r.ico) or (r.i and itemIcon(r.i)) or spellTexture(r.s) or FALLBACK_ICON
end

-- A clickable link for the chat: the client's own link when it has one, else a plain hyperlink.
local function chatLink(r, name)
  if r.i then
    local _, link = call(itemApi("GetItemInfo") or rawget(_G, "GetItemInfo"), r.i)
    return type(link) == "string" and link ~= "" and link or string.format("|Hitem:%d|h[%s]|h", r.i, name)
  end
  local api = rawget(_G, "C_Spell")
  local link = call(type(api) == "table" and api.GetSpellLink or rawget(_G, "GetSpellLink"), r.s)
  return type(link) == "string" and link ~= "" and link or string.format("|Hspell:%d|h[%s]|h", r.s, name)
end

-- Into the open chat edit box, else opens the chat with the link in it.
local function insertChatLink(link)
  local util = rawget(_G, "ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
  if type(insert) ~= "function" then
    return
  end
  local ok, done = pcall(insert, link)
  local open = util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
  if not (ok and done) and type(open) == "function" then
    pcall(open, link)
  end
end

local function shiftDown()
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

local function hex(band)
  local c = R.COLORS[band] or R.COLORS.none
  return string.format(
    "|cff%02x%02x%02x",
    math.floor(c[1] * 255 + 0.5),
    math.floor(c[2] * 255 + 0.5),
    math.floor(c[3] * 255 + 0.5)
  )
end

local function bandName(band)
  return L["recipes.band." .. band]
end

-- "Orange 1  Yellow 55  Green 75  Gray 95": color and word and number, never color alone.
local function bandsText(sk)
  local parts = {}
  for i, band in ipairs(R.BANDS) do
    if (tonumber(sk[i]) or 0) > 0 then
      parts[#parts + 1] = string.format("%s%s %d|r", hex(band), bandName(band), sk[i])
    end
  end
  return table.concat(parts, "  ")
end

-- Stock of the current character { [itemId] = n }, empty without a snapshot.
local function stock()
  local Inv = ns.Inventory
  if Inv and Inv.Fresh then
    pcall(Inv.Fresh)
  end
  local inventory = type(ns.db) == "table" and ns.db.inventory or {}
  local key = ns.CharRoster.CurrentKey()
  return key and Route.Stock(inventory, { key }, false) or {}
end

-- Item lines (patterns, reagents) -----------------------------------------------------------------

local function newItemLine(parent)
  local b = CreateFrame("Button", nil, parent)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("LEFT", 0, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.right = W.Text(b, { role = "micro", color = "textSecondary", justify = "RIGHT" })
  b.right:SetPoint("RIGHT", -4, 0)
  b.name = W.Text(b, { role = "ui" })
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.name:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
  b:SetScript("OnEnter", function(self)
    if self.id then
      W.Tooltip.Show(self, { link = "item:" .. self.id, title = self.label })
    end
  end)
  b:SetScript("OnLeave", ns.HideTooltip)
  b:SetScript(
    "OnClick",
    ns.Wrap("recipes-item-line", function(self)
      if shiftDown() and self.id then
        insertChatLink(self.link or string.format("|Hitem:%d|h[%s]|h", self.id, self.label or tostring(self.id)))
      end
    end)
  )
  ns.Focus.register(b, function() end)
  return b
end

-- Detail ------------------------------------------------------------------------------------------------

local function newDetail(parent)
  local d = CreateFrame("Frame", nil, parent)
  d.pick = W.Text(d, { role = "ui", color = "textMuted", wrap = true })
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(32, 32)
  d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.name = W.Text(d, { role = "h3", family = "heading", wrap = true })
  d.nameButton = CreateFrame("Button", nil, d)
  d.nameButton:SetScript("OnEnter", function(self)
    if d.recipe then
      P.ShowTooltip(self, d.recipe)
    end
  end)
  d.nameButton:SetScript("OnLeave", ns.HideTooltip)
  d.nameButton:SetScript(
    "OnClick",
    ns.Wrap("recipes-name", function()
      if shiftDown() and d.recipe then
        insertChatLink(chatLink(d.recipe, R.Name(d.recipe, lang())))
      end
    end)
  )
  ns.Focus.register(d.nameButton, function() end)
  d.bands = W.Text(d, { role = "ui", wrap = true })
  d.bandNow = W.Text(d, { role = "ui", wrap = true })
  d.source = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.notes = W.Text(d, { role = "ui", color = "accent2", wrap = true })
  d.known = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.crafts = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.reagentHead = W.Text(d, { key = "recipes.reagents", role = "h3", family = "heading", color = "accent2" })
  d.hint = W.Text(d, { key = "recipes.linkHint", role = "micro", color = "textMuted", wrap = true })
  d.lines = {}
  return d
end

local function line(d, i)
  local b = d.lines[i]
  if not b then
    b = newItemLine(d)
    d.lines[i] = b
  end
  return b
end

-- Fills the detail for one recipe; ctx: { data, own (skill), known (set of the character), skill }.
local function paintDetail(d, r, ctx)
  d.recipe = r
  d.pick:SetShown(r == nil)
  local widgets =
    { d.icon, d.name, d.nameButton, d.bands, d.bandNow, d.source, d.notes, d.known, d.crafts, d.reagentHead, d.hint }
  for _, w in ipairs(widgets) do
    w:SetShown(r ~= nil)
  end
  d.layout = { used = 0 }
  if not r then
    for _, b in ipairs(d.lines) do
      b:Hide()
    end
    return
  end
  local name = R.Name(r, lang())
  d.icon:SetTexture(recipeIcon(r))
  d.name:SetText(name)
  d.bands:SetText(bandsText(r.sk))
  local band = R.Band(r.sk, ctx.skill)
  d.bandNow:SetText(string.format(L["recipes.bandAt"], ctx.skill, hex(band) .. bandName(band) .. "|r"))
  local used = 0
  -- Source: trainer with rank, recipe items (names from the client), or unknown.
  local kind = R.SourceKind(r)
  local sourceText = L["recipes.srcUnknown"]
  d.layout.patterns = {}
  if kind == "t" then
    local rank = r.rank and L["profroute.rank." .. r.rank]
    sourceText = rank and rank ~= "profroute.rank." .. r.rank and string.format(L["recipes.srcTrainerRank"], rank)
      or L["recipes.srcTrainer"]
  elseif kind == "i" then
    sourceText = L["recipes.srcItem"]
    for _, id in ipairs(type(r.pat) == "table" and r.pat or {}) do
      if type(id) == "number" then
        used = used + 1
        local b = line(d, used)
        local label = clientItemName(id) or string.format(L["recipes.item"], id)
        b.id, b.label, b.link = id, label, nil
        b.icon:SetTexture(itemIcon(id) or FALLBACK_ICON)
        b.name:SetText(ns.ItemInfo.ColorName(label, ns.ItemInfo.quality(id)))
        b.right:SetText("")
        b:Show()
        d.layout.patterns[#d.layout.patterns + 1] = b
      end
    end
  end
  d.source:SetText(sourceText)
  local notes = {}
  if r.ch then
    notes[#notes + 1] = L["recipes.changedNote"]
  end
  if r.rm then
    notes[#notes + 1] = L["recipes.removedNote"]
  end
  d.notes:SetText(table.concat(notes, "\n"))
  local owners = Known.Owners(r.s)
  local names = {}
  for _, o in ipairs(owners) do
    names[#names + 1] = o.name
  end
  d.known:SetText(#names > 0 and string.format(L["recipes.knownBy"], table.concat(names, ", ")) or "")
  -- Reagents with the stock of this character.
  local reagents, crafts = R.Reagents(r.mats, ctx.stock)
  d.crafts:SetText(crafts and crafts > 0 and string.format(L["recipes.crafts"], crafts) or "")
  d.layout.reagents = {}
  local items = type(ctx.data.items) == "table" and ctx.data.items or {}
  for _, m in ipairs(reagents) do
    used = used + 1
    local b = line(d, used)
    local info = items[m.id] or {}
    local label = ns.T({ de = info.de, en = info.en }) or clientItemName(m.id) or string.format(L["recipes.item"], m.id)
    b.id, b.label, b.link = m.id, label, nil
    b.icon:SetTexture(iconPath(info.ico) or itemIcon(m.id) or FALLBACK_ICON)
    b.name:SetText(ns.ItemInfo.ColorName(label, ns.ItemInfo.quality(m.id)))
    b.right:SetText(string.format(L["recipes.reagentCount"], m.need, m.have))
    b:Show()
    d.layout.reagents[#d.layout.reagents + 1] = b
  end
  d.reagentHead:SetShown(#reagents > 0)
  for i = used + 1, #d.lines do
    d.lines[i]:Hide()
  end
  d.layout.used = used
end

-- Places the detail widgets from the top and returns the height; the wrapped texts get their width
-- before their height is read.
local function layoutDetail(d, width)
  d:SetWidth(width)
  d.pick:ClearAllPoints()
  d.pick:SetPoint("TOPLEFT", 0, 0)
  d.pick:SetWidth(width)
  if not d.recipe then
    return math.max(d.pick:GetStringHeight(), 16)
  end
  local y = 0
  local function text(fs, gap)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, -y)
    fs:SetWidth(width)
    local h = fs:GetText() ~= nil and fs:GetText() ~= "" and fs:GetStringHeight() or 0
    fs:SetShown(h > 0)
    y = y + (h > 0 and h + (gap or 6) or 0)
  end
  d.icon:ClearAllPoints()
  d.icon:SetPoint("TOPLEFT", 0, 0)
  d.name:ClearAllPoints()
  d.name:SetPoint("TOPLEFT", 40, 0)
  d.name:SetWidth(math.max(40, width - 40))
  local nameH = math.max(d.name:GetStringHeight(), 32)
  d.nameButton:ClearAllPoints()
  d.nameButton:SetPoint("TOPLEFT", 0, 0)
  d.nameButton:SetSize(width, nameH)
  y = nameH + 8
  text(d.bands, 4)
  text(d.bandNow, 8)
  text(d.source, 4)
  local rowH = K.scaledHeight(22)
  for _, b in ipairs(d.layout.patterns) do
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 8, -y)
    b:SetSize(math.max(40, width - 8), rowH)
    y = y + rowH
  end
  y = y + 4
  text(d.notes, 4)
  text(d.known, 4)
  text(d.crafts, 8)
  if #d.layout.reagents > 0 then
    d.reagentHead:ClearAllPoints()
    d.reagentHead:SetPoint("TOPLEFT", 0, -y)
    y = y + 22
    for _, b in ipairs(d.layout.reagents) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -y)
      b:SetSize(width, rowH)
      y = y + rowH
    end
    y = y + 8
  end
  d.hint:ClearAllPoints()
  d.hint:SetPoint("TOPLEFT", 0, -y)
  d.hint:SetWidth(width)
  y = y + d.hint:GetStringHeight()
  return y
end

-- Tooltip of a recipe: the item (else the spell) tooltip, then who knows it and what changed.
function P.ShowTooltip(owner, r)
  local lines = {}
  local owners = Known.Owners(r.s)
  if #owners > 0 then
    local names = {}
    for _, o in ipairs(owners) do
      names[#names + 1] = o.name
    end
    lines[#lines + 1] = { text = string.format(L["recipes.learned"], table.concat(names, ", ")), color = "success" }
  end
  if r.ch then
    lines[#lines + 1] = { text = L["recipes.changedNote"], color = "accent2" }
  end
  if r.rm then
    lines[#lines + 1] = { text = L["recipes.removedNote"], color = "warning" }
  end
  W.Tooltip.Show(owner, {
    link = r.i and ("item:" .. r.i) or nil,
    spell = not r.i and r.s or nil,
    title = R.Name(r, lang()),
    lines = lines,
  })
end

-- Skill strip and list rows -----------------------------------------------------------------------------

local function newStrip(parent)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(STRIP_H)
  strip.back = strip:CreateTexture(nil, "BACKGROUND")
  strip.back:SetAllPoints()
  ns.Bind(strip, function()
    strip.back:SetColorTexture(Theme.color("surface3"))
  end)
  strip.segments = {}
  strip.marker = strip:CreateTexture(nil, "OVERLAY")
  strip.marker:SetWidth(2)
  strip.marker:SetColorTexture(1, 1, 1, 1)
  strip:EnableMouse(true)
  strip:SetScript("OnEnter", function(self)
    if self.sk then
      W.Tooltip.Show(self, { title = L["recipes.bandsTip"], text = bandsText(self.sk), anchor = "ANCHOR_TOP" })
    end
  end)
  strip:SetScript("OnLeave", ns.HideTooltip)
  -- Draws the bands of `sk` (nil: bare track) over the slider range 1..max and the skill marker.
  function strip:Draw(width)
    local max, skill = self.max or 1, self.skill or 1
    width = width or self:GetWidth()
    if not width or width < 1 then
      return
    end
    local segs = self.sk and R.Segments(self.sk, max) or {}
    for i, s in ipairs(segs) do
      local t = self.segments[i]
      if not t then
        t = self:CreateTexture(nil, "ARTWORK")
        self.segments[i] = t
      end
      local c = R.COLORS[s.band]
      t:SetColorTexture(c[1], c[2], c[3], 1)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT", math.floor((s.from - 1) / max * width), 0)
      t:SetSize(math.max(1, math.floor((s.to - s.from + 1) / max * width)), STRIP_H)
      t:Show()
    end
    for i = #segs + 1, #self.segments do
      self.segments[i]:Hide()
    end
    self.marker:ClearAllPoints()
    self.marker:SetPoint("TOPLEFT", self, "TOPLEFT", math.min(width - 2, math.floor((skill - 1) / max * width)), 2)
    self.marker:SetHeight(STRIP_H + 4)
  end
  function strip:Paint(sk, max, skill)
    self.sk, self.max, self.skill = sk, max, skill
    self:Draw()
  end
  strip:SetScript("OnSizeChanged", function(self, width)
    self:Draw(width)
  end)
  return strip
end

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.level = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
  row.level:SetPoint("RIGHT", -8, 0)
  row.level:SetWidth(34)
  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetSize(8, 8)
  row.dot:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
  row.check = W.CheckMark(row, 12, "success")
  row.check:SetPoint("RIGHT", row.dot, "LEFT", -6, 0)
  row.changed = W.Text(row, { text = "*", role = "ui", color = "accent2", justify = "CENTER" })
  row.changed:SetPoint("RIGHT", row.check, "LEFT", -4, 0)
  row.changed:SetWidth(10)
  row.arrow = W.Text(row, { role = "ui", color = "accent2" })
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.title = W.Text(row, { role = "ui" })
  row.title:SetPoint("RIGHT", row.changed, "LEFT", -6, 0)
  row.hover = false
  function row:paint()
    local selected = self.selected
    self.bg:SetColorTexture(1, 1, 1, selected and 0.1 or (self.hover and 0.05 or 0))
  end
  row:SetScript("OnEnter", function(self)
    self.hover = true
    self:paint()
    if self.recipe then
      P.ShowTooltip(self, self.recipe)
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover = false
    self:paint()
    ns.HideTooltip()
  end)
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  return row
end

-- Paints one display row (head or recipe) of R.Rows.
local function bindRow(row, item, ctx)
  row.item = item
  local indent = 6 + item.depth * 12
  local isHead = item.kind == "head"
  row.recipe = not isHead and item.recipe or nil
  row.selected = row.recipe ~= nil and row.recipe.s == ctx.selected
  row.arrow:SetShown(isHead)
  row.icon:SetShown(not isHead)
  row.check:SetShown(false)
  row.changed:SetShown(false)
  row.title:ClearAllPoints()
  row.title:SetPoint("RIGHT", row.changed, "LEFT", -6, 0)
  if isHead then
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("LEFT", indent, 0)
    row.arrow:SetText(item.open and "-" or "+")
    row.title:SetPoint("LEFT", indent + 14, 0)
    row.title:SetText(item.band and bandName(item.band) or item.name)
    W.SetColor(row.title, "accent2")
    row.level:SetText(tostring(item.count))
    if item.band then
      local c = R.COLORS[item.band]
      row.dot:SetColorTexture(c[1], c[2], c[3], 1)
    end
    row.dot:SetShown(item.band ~= nil)
  else
    local r = item.recipe
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", indent, 0)
    row.icon:SetTexture(recipeIcon(r))
    row.title:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.title:SetText(R.Name(r, lang()))
    W.SetColor(row.title, r.rm and "textMuted" or "text")
    local c = R.COLORS[R.Band(r.sk, ctx.skill)]
    row.dot:SetColorTexture(c[1], c[2], c[3], 1)
    row.dot:SetShown(true)
    local level = R.Level(r)
    row.level:SetText(level == math.huge and "-" or tostring(level))
    row.check:SetShown(ctx.known[r.s] == true)
    row.changed:SetShown(r.ch == true or r.rm == true)
  end
  row:paint()
end

-- Page --------------------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    slug = nil,
    skill = nil,
    query = "",
    source = nil,
    changed = false,
    learnable = false,
    unknown = false,
    removed = false,
    collapsed = {},
    selected = nil,
  }
  -- What refresh() worked out for the shown profession; update() reuses it while the user filters.
  local ctx = { slug = Route.SLUGS[1], skill = 1, known = {} }
  local refresh, update

  ns.AddParagraph(view, "recipes.intro")

  -- Controls -----------------------------------------------------------------------------------------
  local controls = CreateFrame("Frame", nil, view.content)
  local options = {}
  local professions = W.Dropdown(controls, {
    key = "recipes.profession",
    width = DROPDOWN_W,
    options = options,
    get = function()
      return ctx.slug
    end,
    set = function(slug)
      state.slug, state.skill, state.selected, state.collapsed = slug, nil, nil, {}
      refresh()
    end,
  })
  professions:SetWidth(DROPDOWN_W)

  local search = CreateFrame("Frame", nil, controls)
  search:SetSize(SEARCH_W, 46)
  local searchLabel = W.Text(search, { key = "recipes.search", role = "ui" })
  searchLabel:SetPoint("TOPLEFT")
  search.edit = W.EditBox(search, {
    placeholder = "recipes.searchPh",
    clear = true,
    onChange = function(text)
      state.query = text
      update()
    end,
  })
  search.edit:SetPoint("TOPLEFT", 0, -18)
  search.edit:SetWidth(SEARCH_W)

  local sourceOptions = {}
  for _, v in ipairs({ "all", "t", "i", "u" }) do
    sourceOptions[#sourceOptions + 1] = { value = v, key = "recipes.src." .. v }
  end
  local source = W.Dropdown(controls, {
    key = "recipes.source",
    width = SOURCE_W,
    options = sourceOptions,
    get = function()
      return state.source or "all"
    end,
    set = function(v)
      state.source = v ~= "all" and v or nil
      update()
    end,
  })
  source:SetWidth(SOURCE_W)

  local function toggle(field)
    local t = W.Toggle(controls, {
      key = "recipes." .. field,
      tooltip = "recipes." .. field,
      tooltipText = "recipes." .. field .. "Tip",
      get = function()
        return state[field]
      end,
      set = function(on)
        state[field] = on
        update()
      end,
    })
    t:SetWidth(TOGGLE_W)
    return t
  end
  local by = {
    changed = toggle("changed"),
    learnable = toggle("learnable"),
    unknown = toggle("unknown"),
    removed = toggle("removed"),
  }
  local toggles = { by.changed, by.learnable, by.unknown, by.removed }

  local skillBox = CreateFrame("Frame", nil, controls)
  skillBox:SetSize(SKILL_W, 42 + 6 + STRIP_H + 4)
  local sliderOpts = {
    key = "recipes.skill",
    min = 1,
    max = R.DEFAULT_MAX_SKILL,
    step = 1,
    get = function()
      return ctx.skill
    end,
    set = function(v)
      state.skill = v
      update()
    end,
  }
  local slider = W.Slider(skillBox, sliderOpts)
  slider:SetPoint("TOPLEFT")
  slider:SetPoint("TOPRIGHT")
  local strip = newStrip(skillBox)
  strip:SetPoint("TOPLEFT", 0, -48)
  strip:SetPoint("TOPRIGHT", 0, -48)
  skillBox.strip = strip

  local groups = { { professions, search, source }, toggles, { skillBox } }
  function controls:fgGridLayout(width)
    skillBox:SetWidth(math.min(SKILL_W, width))
    local y = 0
    for _, group in ipairs(groups) do
      local x, rowH = 0, 0
      for _, item in ipairs(group) do
        local w, h = item:GetWidth(), item:GetHeight()
        if x > 0 and x + w > width then
          y, x, rowH = y + rowH + ROW_GAP, 0, 0
        end
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        x = x + w + CONTROL_GAP
        rowH = math.max(rowH, h)
      end
      y = y + rowH + ROW_GAP
    end
    y = y - ROW_GAP
    self:SetHeight(y)
    return y
  end
  s:Add(controls, { gap = 12 })

  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = 8 })
  -- Instead of the hint while the recipe add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, Data.ADDON, {
    onLoaded = function()
      refresh()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = 8 })
  local note = ns.AddParagraph(view, nil, { role = "ui", color = "textMuted", gap = 8 })
  local summary = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary", gap = 8 })

  -- List and detail -------------------------------------------------------------------------------------
  local split = CreateFrame("Frame", nil, view.content)
  local rowH = K.scaledHeight(26)
  local list = W.ScrollList(split, {
    rowHeight = rowH,
    createRow = function(parent)
      local row = newRow(parent)
      row:SetScript(
        "OnClick",
        ns.Wrap("recipes-row", function(self)
          local item = self.item
          if not item then
            return
          end
          if item.kind == "head" then
            state.collapsed[item.id] = item.open or nil
            update()
          elseif shiftDown() then
            insertChatLink(chatLink(item.recipe, R.Name(item.recipe, lang())))
          else
            state.selected = item.recipe.s
            update()
          end
        end)
      )
      return row
    end,
    bindRow = function(row, item)
      bindRow(row, item, { skill = ctx.skill, known = ctx.known, selected = state.selected })
    end,
  })
  local detail = newDetail(split)
  paintDetail(detail, nil, ctx)

  local function listHeight()
    local y = s.pad
    for _, entry in ipairs(s.items) do
      if entry.item == split then
        break
      end
      if entry.item:IsShown() then
        y = y + entry.item:GetHeight() + (entry.opts.gap or 10)
      end
    end
    local free = view.area:GetHeight() - y - s.pad
    return math.max(rowH * MIN_ROWS, math.floor(free))
  end

  function split:fgGridLayout(width)
    local listH = listHeight()
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    detail:ClearAllPoints()
    local total
    if width >= WIDE then
      local leftW = math.floor(width * 0.52)
      list:SetSize(leftW, listH)
      detail:SetPoint("TOPLEFT", self, "TOPLEFT", leftW + SPLIT_GAP, 0)
      total = math.max(listH, layoutDetail(detail, width - leftW - SPLIT_GAP))
    else
      list:SetSize(width, listH)
      detail:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(listH + SPLIT_GAP))
      total = listH + SPLIT_GAP + layoutDetail(detail, width)
    end
    detail:SetHeight(total)
    self:SetHeight(total)
    return total
  end
  s:Add(split, { gap = 12 })

  -- Refresh ------------------------------------------------------------------------------------------------

  local function fillOptions(own)
    for i = #options, 1, -1 do
      options[i] = nil
    end
    local mine = {}
    for _, p in ipairs(own) do
      mine[p.slug] = true
      options[#options + 1] = { value = p.slug, text = string.format("%s (%d/%d)", Route.Name(p.slug), p.skill, p.max) }
    end
    for _, slug in ipairs(Route.SLUGS) do
      if not mine[slug] then
        options[#options + 1] = { value = slug, text = Route.Name(slug) }
      end
    end
  end

  -- Filter, rows, list, strip and detail from what refresh() collected.
  function update()
    if not ctx.data then
      return
    end
    ctx.skill = math.max(1, math.min(state.skill or ctx.ownSkill or 1, ctx.max))
    slider.Refresh()
    local filtered = R.Filter(ctx.list, {
      query = state.query,
      changed = state.changed,
      source = state.source,
      learnable = state.learnable,
      skill = ctx.skill,
      unknown = state.unknown,
      known = ctx.known,
      removed = state.removed,
    })
    local rows = R.Rows(ctx.data, filtered, {
      lang = lang(),
      skill = ctx.skill,
      collapsed = state.collapsed,
      forceOpen = state.query ~= "",
      otherName = L["recipes.other"],
      presorted = true,
    })
    list:SetData(rows)
    summary:SetText(string.format(L["recipes.count"], #filtered, #ctx.list))
    local current = ctx.byId[state.selected]
    strip:Paint(current and current.sk or nil, ctx.max, ctx.skill)
    paintDetail(detail, current, { data = ctx.data, skill = ctx.skill, stock = current and stock() or {} })
    view:Layout()
  end

  function refresh()
    local own = Shop.Own()
    fillOptions(own)
    ctx.slug = state.slug or (own[1] and own[1].slug) or Route.SLUGS[1]
    ctx.ownSkill = nil
    for _, p in ipairs(own) do
      if p.slug == ctx.slug then
        ctx.ownSkill = p.skill
      end
    end
    professions.Refresh()
    local data, recipes, status = Data.Get(ctx.slug)
    ctx.data = data
    local key = ns.CharRoster.CurrentKey()
    ctx.known = key and Known.Set(key) or {}
    local offered = banner:Update(data == nil and status == Data.STATUS.missing)
    hint:SetShown(data == nil and not offered)
    note:SetShown(false)
    split:SetShown(data ~= nil)
    summary:SetShown(data ~= nil)
    if not data then
      hint:SetText(Data.Hint(status))
      list:SetData({})
      view:Layout()
      return
    end
    ctx.list = R.Sort(recipes, lang())
    ctx.byId = {}
    for _, r in ipairs(ctx.list) do
      ctx.byId[r.s] = r
    end
    ctx.max = math.min(R.MaxSkill(ctx.list), R.MAX_SKILL)
    sliderOpts.max = ctx.max
    slider.slider:SetMinMaxValues(1, ctx.max)
    local noKnown = key == nil or #Known.Ids(key) == 0
    note:SetShown(noKnown)
    note:SetText(noKnown and L["recipes.noneKnown"] or "")
    update()
  end

  -- Deep link professions/<slug>/<spell id> (from the search): that profession with the recipe
  -- selected and the list filtered by its name, every other filter off. Without params the page
  -- stays as the user left it.
  function view:Show(params)
    local slug = params and params[1]
    if slug and Route.PROFESSIONS[slug] then
      state.slug, state.skill, state.selected, state.collapsed = slug, nil, tonumber(params[2]), {}
      state.query, state.source = "", nil
      state.changed, state.learnable, state.unknown, state.removed = false, false, false, false
      refresh()
      local found = ctx.data and ctx.byId[state.selected]
      if found then
        state.query = R.Name(found, lang())
      end
      search.edit.edit:SetText(state.query)
      source.Refresh()
      for _, t in pairs(by) do
        t.Refresh()
      end
      update()
      return
    end
    refresh()
  end
  local function whenVisible()
    if container:IsVisible() then
      refresh()
    end
  end
  ns.On("FG_RECIPES_CHANGED", whenVisible)
  ns.On("FG_ROSTER_CHANGED", whenVisible)
  ns.On("FG_UI_REFRESHED", whenVisible)
  ns.On("SKILL_LINES_CHANGED", function()
    ns.Debounce("recipes-skill", 0.5, whenVisible)
  end)
  ns.On("GET_ITEM_INFO_RECEIVED", function()
    ns.Debounce("recipes-items", 0.5, whenVisible)
  end)
  P.view, P.options, P.state, P.list, P.detail = view, options, state, list, detail
  P.controls =
    { professions = professions, search = search, source = source, toggles = by, slider = slider, strip = strip }
  return view
end

ns.RegisterPage({
  id = "professions",
  order = 80,
  group = "character",
  title = "page.professions",
  icon = ns.ICONS.professions,
  aliases = { "berufe", "professions", "rezepte", "recipes" },
  crumbLabel = function(param, index)
    if index == 1 and Route.PROFESSIONS[param] then
      return Route.Name(param)
    end
    return index == 2 and "#" .. param or param
  end,
  build = build,
})
