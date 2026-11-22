-- Hunter pets: the tameable families with diet, role and abilities, every pet ability with its ranks and the
-- beasts that teach it, and the rare tames. Three tabs, each a list on the left and the chosen entry on the right
-- (narrow pages show one of the two with a back button); the detail is a hero with attribute lines and section cards. Data: Data/HunterPets.lua, logic: PetsLogic.
local _, ns = ...
local Theme = ns.Theme
local W, L, K = ns.W, ns.L, ns.PageKit
local P = ns.PetsLogic

ns.AddLocale("enUS", {
  ["page.pets"] = "Hunter Pets",
  ["page.pets.sub"] = "Pet families, abilities and where to tame them",
  ["pets.intro"] = "Which beasts a hunter can tame, what each family can do and where to find the beasts, including the rare tames",
  ["pets.tab.families"] = "Families",
  ["pets.tab.abilities"] = "Abilities",
  ["pets.tab.rares"] = "Rare tames",
  ["pets.search"] = "Search",
  ["pets.searchPh"] = "Family, ability or beast",
  ["pets.total.families"] = "Families: %d",
  ["pets.total.abilities"] = "Abilities: %d",
  ["pets.total.rares"] = "Rare tames: %d",
  ["pets.empty"] = "Nothing matches your search.",
  ["pets.diet.meat"] = "Meat",
  ["pets.diet.fish"] = "Fish",
  ["pets.diet.cheese"] = "Cheese",
  ["pets.diet.bread"] = "Bread",
  ["pets.diet.fungus"] = "Fungus",
  ["pets.diet.fruit"] = "Fruit",
  ["pets.diet.none"] = "none",
  ["pets.role.damage"] = "Damage",
  ["pets.role.tank"] = "Tank",
  ["pets.role.balanced"] = "All-rounder",
  ["pets.zonePh"] = "Filter by zone",
  ["pets.card.tames"] = "Beasts: %d, level %s",
  ["pets.card.open"] = "Open family",
  ["pets.rareBadge"] = "Rare",
  ["pets.zoneNone"] = "No beast in this zone.",
  ["pets.where"] = "Where to tame",
  ["pets.whereNone"] = "No known beasts of this family.",
  ["pets.whereAll"] = "Every family can learn this ability.",
  ["pets.abilitySub"] = "%d ranks, level %d to %d",
  ["pets.abilitySub1"] = "1 rank, level %d",
  ["pets.learn"] = "Tame a beast of one of these families to learn the ability. A beast of the level of a rank teaches that rank. Teach it to your pet with Beast Training.",
  ["pets.new"] = "New in Forever",
  ["pets.newNote"] = "This ability is new in Forever and not part of Classic 1.12.",
  ["pets.elite"] = "Elite",
  ["pets.mapTip"] = "Show the zone of the beast on the map",
  ["pets.markerTip"] = "Set a waypoint at the beast",
  ["pets.attr.diet"] = "Diet",
  ["pets.attr.role"] = "Role",
  ["pets.attr.special"] = "Special trait",
  ["pets.attr.family"] = "Family",
  ["pets.attr.level"] = "Level",
  ["pets.attr.zone"] = "Zone",
  ["pets.attr.pos"] = "Position",
  ["pets.diet.tip"] = "Food your pet eats",
  ["pets.mod.health"] = "Health",
  ["pets.mod.armor"] = "Armor",
  ["pets.mod.damage"] = "Damage",
  ["pets.card.modifiers"] = "Modifiers",
  ["pets.card.abilities"] = "Family abilities",
  ["pets.card.ranks"] = "Ranks",
  ["pets.card.families"] = "Families",
  ["pets.card.facts"] = "Details",
  ["pets.card.family"] = "Family",
  ["pets.showAll"] = "Show all (%d)",
  ["pets.showLess"] = "Show fewer",
  ["pets.levelValue"] = "Level %s",
  ["pets.rankLabel"] = "Rank %d",
})

ns.AddLocale("deDE", {
  ["page.pets"] = "Jäger-Begleiter",
  ["page.pets.sub"] = "Begleiterfamilien, Fähigkeiten und wo du sie zähmst",
  ["pets.intro"] = "Welche Tiere ein Jäger zähmen kann, was jede Familie kann und wo du die Tiere findest, auch die seltenen",
  ["pets.tab.families"] = "Familien",
  ["pets.tab.abilities"] = "Fähigkeiten",
  ["pets.tab.rares"] = "Seltene Tiere",
  ["pets.search"] = "Suchen",
  ["pets.searchPh"] = "Familie, Fähigkeit oder Tier",
  ["pets.total.families"] = "Familien: %d",
  ["pets.total.abilities"] = "Fähigkeiten: %d",
  ["pets.total.rares"] = "Seltene Tiere: %d",
  ["pets.empty"] = "Zu deiner Suche gibt es keinen Treffer.",
  ["pets.diet.meat"] = "Fleisch",
  ["pets.diet.fish"] = "Fisch",
  ["pets.diet.cheese"] = "Käse",
  ["pets.diet.bread"] = "Brot",
  ["pets.diet.fungus"] = "Pilze",
  ["pets.diet.fruit"] = "Obst",
  ["pets.diet.none"] = "keine",
  ["pets.role.damage"] = "Schaden",
  ["pets.role.tank"] = "Tank",
  ["pets.role.balanced"] = "Allrounder",
  ["pets.zonePh"] = "Gebiet filtern",
  ["pets.card.tames"] = "Tiere: %d, Stufe %s",
  ["pets.card.open"] = "Familie öffnen",
  ["pets.rareBadge"] = "Selten",
  ["pets.zoneNone"] = "Kein Tier in diesem Gebiet.",
  ["pets.where"] = "Wo zähmen",
  ["pets.whereNone"] = "Keine bekannten Tiere dieser Familie.",
  ["pets.whereAll"] = "Jede Familie kann diese Fähigkeit lernen.",
  ["pets.abilitySub"] = "%d Ränge, Stufe %d bis %d",
  ["pets.abilitySub1"] = "1 Rang, Stufe %d",
  ["pets.learn"] = "Zähme ein Tier einer dieser Familien, um die Fähigkeit zu lernen. Ein Tier mit der Stufe eines Rangs bringt dir diesen Rang bei. Dem Begleiter bringst du sie mit Tier-Training bei.",
  ["pets.new"] = "Neu in Forever",
  ["pets.newNote"] = "Diese Fähigkeit ist neu in Forever und kein Teil von Classic 1.12.",
  ["pets.elite"] = "Elite",
  ["pets.mapTip"] = "Zone des Tiers auf der Karte zeigen",
  ["pets.markerTip"] = "Wegpunkt am Tier setzen",
  ["pets.attr.diet"] = "Futter",
  ["pets.attr.role"] = "Rolle",
  ["pets.attr.special"] = "Besonderheit",
  ["pets.attr.family"] = "Familie",
  ["pets.attr.level"] = "Stufe",
  ["pets.attr.zone"] = "Gebiet",
  ["pets.attr.pos"] = "Position",
  ["pets.diet.tip"] = "Futter, das dein Begleiter frisst",
  ["pets.mod.health"] = "Gesundheit",
  ["pets.mod.armor"] = "Rüstung",
  ["pets.mod.damage"] = "Schaden",
  ["pets.card.modifiers"] = "Modifikatoren",
  ["pets.card.abilities"] = "Familienfähigkeiten",
  ["pets.card.ranks"] = "Ränge",
  ["pets.card.families"] = "Familien",
  ["pets.card.facts"] = "Details",
  ["pets.card.family"] = "Familie",
  ["pets.showAll"] = "Alle anzeigen (%d)",
  ["pets.showLess"] = "Weniger anzeigen",
  ["pets.levelValue"] = "Stufe %s",
  ["pets.rankLabel"] = "Rang %d",
})


local WHERE_LIMIT = 6
local STATE_KEY = { families = "family", abilities = "ability", rares = "rare" }

local function dietText(family)
  local parts = {}
  for _, diet in ipairs(family.diet) do
    parts[#parts + 1] = L["pets.diet." .. diet]
  end
  return #parts > 0 and table.concat(parts, ", ") or L["pets.diet.none"]
end

local function abilityName(id)
  local a = P.Ability(id)
  return a and ns.T(a.n) or id
end

local function abilitySub(a)
  local count, from, to = P.RankSpan(a)
  return count == 1 and string.format(L["pets.abilitySub1"], from)
    or string.format(L["pets.abilitySub"], count, from, to)
end

-- The client's icon of a spell or an item; our fallback icon while the client does not know it.
local function clientIcon(fn, id)
  local ok, texture = pcall(fn or function() end, id)
  return ok and texture or ns.ICON_FALLBACK
end

local function spellIcon(id)
  local api = rawget(_G, "C_Spell")
  return clientIcon(type(api) == "table" and api.GetSpellTexture or rawget(_G, "GetSpellTexture"), id)
end

local function itemIcon(id)
  local api = rawget(_G, "C_Item")
  return clientIcon(type(api) == "table" and api.GetItemIconByID or rawget(_G, "GetItemIcon"), id)
end

-- The spell tooltip of the client; name, ranks and description are the fallback while it does not know the spell.
local function spellTip(frame, a)
  local desc = a.d and ns.T(a.d) or nil
  if not W.Tooltip.Show(frame, { spell = a.ranks[1].s, text = desc }) then
    local sub = abilitySub(a)
    ns.ShowTooltip(frame, ns.T(a.n), desc and (sub .. "\n" .. desc) or sub)
  end
end

-- Attribute lines of a family: food as a strip of item icons (the tooltip names the food), role, special trait.
local function familyAttrs(f)
  local icons = {}
  for _, d in ipairs(P.DietIcons(f)) do
    icons[#icons + 1] = { icon = itemIcon(d.item), tip = { title = L["pets.diet." .. d.diet], text = L["pets.diet.tip"] } }
  end
  local attrs = {
    { labelKey = "pets.attr.diet", values = icons, value = #icons == 0 and L["pets.diet.none"] or nil },
    { labelKey = "pets.attr.role", value = L["pets.role." .. f.role] },
  }
  local special = {}
  for _, id in ipairs(P.SpecialAbilities(f)) do
    special[#special + 1] = abilityName(id)
  end
  if #special > 0 then
    attrs[#attrs + 1] = { labelKey = "pets.attr.special", value = table.concat(special, ", ") }
  end
  return attrs
end

-- Rows ----------------------------------------------------------------------------------------------

-- Lays the items out one under the other from y = top; every item answers fgLayout(width) -> height.
local function stack(items, width, gap, top)
  local y = top or 0
  for i, item in ipairs(items) do
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", item:GetParent(), "TOPLEFT", 0, -y)
    y = y + item:fgLayout(width) + (i < #items and gap or 0)
  end
  return y
end

-- Shows the first n frames of a pool (made on demand), hides the rest, returns the shown ones.
local function fill(pool, parent, make, n, set)
  local out = {}
  for i = 1, n do
    pool[i] = pool[i] or make(parent)
    pool[i]:Show()
    set(pool[i], i)
    out[i] = pool[i]
  end
  for i = n + 1, #pool do
    pool[i]:Hide()
  end
  return out
end

-- One ability of a family: spell icon, name and rank span, the spell tooltip on hover and focus, a click
-- opens the ability.
local function makeAbilityRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:Hide()
  ns.Bind(row, function()
    row.hover:SetColorTexture(Theme.fillColor("hover"))
  end)
  row.icon = K.IconFrame(row, { size = Theme.size.iconFrame.sm })
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.sub = W.Meta(row, { color = "textMuted", wrap = true })
  row:SetScript("OnEnter", function(self)
    self.hover:Show()
    spellTip(self, self.ability)
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:Hide()
    ns.HideTooltip()
  end)
  row:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.onClick then
      self.onClick(self.ability)
    end
  end)
  function row:Set(a, onClick)
    self.ability, self.onClick = a, onClick
    local name = ns.T(a.n)
    W.SetText(self.name, nil, name)
    W.SetText(self.sub, nil, abilitySub(a))
    self.icon:SetTexture(spellIcon(a.ranks[1].s))
    self.icon:SetTip(name, function()
      onClick(a)
    end, name)
    local function tip(frame)
      spellTip(frame, a)
    end
    self.icon:SetScript("OnEnter", tip)
    self.icon.fgOnFocus = tip
  end
  function row:fgLayout(width)
    local sm, px = Theme.space.sm, Theme.size.iconFrame.sm
    local textW = math.max(20, width - px - sm)
    local nameH = W.FitLabel(self.name, textW)
    local subH = W.FitLabel(self.sub, textW)
    local h = math.max(K.scaledHeight(Theme.size.iconFrame.md), nameH + subH + 6)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("LEFT", self, "LEFT", 0, 0)
    local top = math.floor((h - nameH - subH) / 2)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", px + sm, -top)
    self.sub:ClearAllPoints()
    self.sub:SetPoint("TOPLEFT", self, "TOPLEFT", px + sm, -(top + nameH))
    self:SetSize(width, h)
    return h
  end
  return row
end

-- One beast to tame: name with level range, zone, map and waypoint buttons. Wide rows put the zone in a
-- column of its own, narrow rows under the name.
local function makeTameRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.zone = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.map = W.MapActionButtons(row, { mapTip = "pets.mapTip", markerTip = "pets.markerTip" })
  row.rule = row:CreateTexture(nil, "ARTWORK")
  row.rule:SetHeight(1)
  ns.Bind(row, function()
    row.rule:SetColorTexture(Theme.fillColor("line"))
  end)
  function row:Set(b)
    self.beast = b
    local extra = { P.LevelText(b) }
    if P.IsRare(b) then
      extra[#extra + 1] = L["pets.rareBadge"]
    end
    if b.e then
      extra[#extra + 1] = L["pets.elite"]
    end
    local name = ns.T(b.n)
    W.SetText(self.name, nil, name .. " " .. Theme.hexText("textSecondary", "(" .. table.concat(extra, ", ") .. ")"))
    W.SetText(self.zone, nil, P.ZoneName(b))
    self.map:SetPlace(P.Place(b))
    -- The same two buttons repeat on every row: the name of the beast tells them apart.
    self.map.map.fgName = function()
      return L["kit.placeMap"] .. ": " .. name
    end
    self.map.marker.fgName = function()
      return L["kit.placeMarker"] .. ": " .. name
    end
  end
  function row:fgLayout(width)
    local sm = Theme.space.sm
    local mapW = self.map:GetWidth()
    local pad = 4
    local textW = math.max(40, width - mapW - sm)
    local h
    self.name:ClearAllPoints()
    self.zone:ClearAllPoints()
    if width >= 420 then
      local nameW = math.floor(textW * 0.55)
      local zoneW = textW - nameW - sm
      local nh, zh = W.FitLabel(self.name, nameW), W.FitLabel(self.zone, zoneW)
      h = math.max(K.scaledHeight(Theme.size.row), nh + 2 * pad, zh + 2 * pad, self.map:GetHeight() + 2 * pad)
      self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -math.floor((h - nh) / 2))
      self.zone:SetPoint("TOPLEFT", self, "TOPLEFT", nameW + sm, -math.floor((h - zh) / 2))
    else
      local nh, zh = W.FitLabel(self.name, textW), W.FitLabel(self.zone, textW)
      h = math.max(K.scaledHeight(Theme.size.row), nh + zh + 2 * pad, self.map:GetHeight() + 2 * pad)
      local top = math.floor((h - nh - zh) / 2)
      self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
      self.zone:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(top + nh))
    end
    self.map:ClearAllPoints()
    self.map:SetPoint("RIGHT", self, "RIGHT", 0, 0)
    self.rule:ClearAllPoints()
    self.rule:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
    self.rule:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    self:SetSize(width, h)
    return h
  end
  return row
end

local function makeAttr(parent)
  return K.AttrLine(parent)
end

local function makeStat(parent)
  return K.StatRow(parent)
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { tab = "families", query = "", zone = "", family = "", ability = "", rare = "", detail = false }
  ns.PageState.Bind(view, state, { "tab", "query", "zone", "family", "ability", "rare" })
  local refresh

  ns.AddIntro(view, "pets.intro")
  local basis = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = Theme.space.sm })

  local tabs = W.Tabs(view.content, {
    wrap = true,
    tabs = {
      { id = "families", key = "pets.tab.families" },
      { id = "abilities", key = "pets.tab.abilities" },
      { id = "rares", key = "pets.tab.rares" },
    },
    onSelect = function(id)
      state.tab, state.detail = id, false
      refresh()
    end,
  })
  K.Anchor("FG.Pets.Tabs", tabs)
  s:Add(tabs, { gap = Theme.space.md })

  local search
  local filters = K.FilterBar(view.content, {
    count = function()
      return state.query ~= "" and 1 or 0
    end,
    reset = function()
      state.query = ""
      search.edit:SetText("")
      refresh()
    end,
  })
  search = filters:AddSearch({
    key = "pets.search",
    text = state.query,
    placeholder = "pets.searchPh",
    width = 260,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  s:Add(filters, { gap = Theme.space.md })
  K.Anchor("FG.Pets.Controls", filters)

  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })

  local shown, selected = {}, nil
  local paintDetail, openFamily, openAbility
  local syncing, showAll, painted = false, false, nil

  -- The list is made before the master/detail shell so the keyboard reaches it before the detail.
  local list, split
  list = K.NewList(view.content, {
    look = "boxed",
    bind = function(entry)
      local mine = selected ~= nil and selected.id == entry.id
      if state.tab == "families" then
        return {
          title = ns.T(entry.n),
          icon = entry.icon,
          iconFrame = true,
          meta = dietText(entry),
          selected = mine,
          cursor = mine,
        }
      elseif state.tab == "abilities" then
        return {
          title = ns.T(entry.n),
          sub = abilitySub(entry),
          icon = spellIcon(entry.ranks[1].s),
          iconFrame = true,
          meta = entry.new and L["pets.new"] or nil,
          selected = mine,
          cursor = mine,
        }
      end
      local family = P.Family(entry.fam)
      return {
        title = ns.T(entry.n),
        sub = P.ZoneName(entry),
        icon = family and family.icon or nil,
        iconFrame = true,
        meta = string.format(L["pets.levelValue"], P.LevelText(entry)),
        selected = mine,
        cursor = mine,
      }
    end,
    onClick = function(entry)
      state[STATE_KEY[state.tab]], state.detail = entry.id, true
      selected = entry
      list:SetData(shown)
      paintDetail()
      split:SetSelected(entry)
      view:Layout()
    end,
  })
  K.Anchor("FG.Pets.List", list)

  local content, hero, actions, cardRow, whereCard, layoutDetail
  split = K.MasterDetail(view.content, {
    list = list,
    onToggle = function(on)
      if not syncing then
        state.detail = on
      end
    end,
    detail = function(width, _, _, md)
      return layoutDetail(width, md)
    end,
  })
  K.Anchor("FG.Pets.Detail", split.detail)
  content = split.content

  -- Hero: portrait, name, attribute lines, tags and the share icon (map and waypoint too for a rare tame).
  hero = K.Hero(content, {})
  actions = W.MapActionButtons(hero, { mapTip = "pets.mapTip", markerTip = "pets.markerTip", share = true })
  hero:SetActions(actions)

  local pools = { mods = {}, abil = {}, ranks = {}, fams = {}, facts = {}, rfam = {}, tames = {} }
  local vis = { mods = {}, abil = {}, ranks = {}, fams = {}, facts = {}, rfam = {}, tames = {} }
  local gapSmall = function()
    return Theme.space.xs + 2
  end

  local famMods = K.SectionCard(content, {
    key = "pets.card.modifiers",
    body = function(w)
      return stack(vis.mods, w, gapSmall())
    end,
  })
  local famAbil = K.SectionCard(content, {
    key = "pets.card.abilities",
    body = function(w)
      return stack(vis.abil, w, Theme.space.xs)
    end,
  })
  local abilRanks = K.SectionCard(content, {
    key = "pets.card.ranks",
    body = function(w)
      return stack(vis.ranks, w, gapSmall())
    end,
  })
  local abilFams, famNote
  abilFams = K.SectionCard(content, {
    key = "pets.card.families",
    body = function(w)
      local y = stack(vis.fams, w, Theme.space.xs)
      famNote:ClearAllPoints()
      famNote:SetPoint("TOPLEFT", abilFams.body, "TOPLEFT", 0, -(y > 0 and y + Theme.space.md or 0))
      return (y > 0 and y + Theme.space.md or 0) + W.FitLabel(famNote, w)
    end,
  })
  famNote = W.Text(abilFams.body, { role = "ui", color = "textMuted", wrap = true })
  local rareFacts = K.SectionCard(content, {
    key = "pets.card.facts",
    body = function(w)
      return stack(vis.facts, w, gapSmall())
    end,
  })
  local rareFam = K.SectionCard(content, {
    key = "pets.card.family",
    body = function(w)
      return stack(vis.rfam, w, gapSmall())
    end,
  })
  cardRow = K.CardRow(content, { cards = { famMods, famAbil, abilRanks, abilFams, rareFacts, rareFam }, minWidth = 240 })

  -- Where to tame: zone filter (more than a few beasts), the rows, "Show all".
  local where = { filterBox = false, more = false, note = nil }
  local whereNote, zoneSearch, moreBtn
  whereCard = K.SectionCard(content, {
    key = "pets.where",
    body = function(w)
      local sm = Theme.space.sm
      local y = 0
      zoneSearch:SetShown(where.filterBox)
      if where.filterBox then
        zoneSearch:ClearAllPoints()
        zoneSearch:SetPoint("TOPLEFT", whereCard.body, "TOPLEFT", 0, 0)
        zoneSearch:SetWidth(math.min(w, 260))
        y = zoneSearch:GetHeight() + sm
      end
      whereNote:SetShown(where.note ~= nil)
      if where.note then
        whereNote:ClearAllPoints()
        whereNote:SetPoint("TOPLEFT", whereCard.body, "TOPLEFT", 0, -y)
        y = y + W.FitLabel(whereNote, w)
      end
      y = stack(vis.tames, w, 0, y)
      moreBtn:SetShown(where.more)
      if where.more then
        moreBtn:ClearAllPoints()
        moreBtn:SetPoint("TOPLEFT", whereCard.body, "TOPLEFT", 0, -(y + sm))
        moreBtn:SetWidth(moreBtn:Fit(w))
        y = y + sm + moreBtn:GetHeight()
      end
      return y
    end,
  })
  whereNote = W.Text(whereCard.body, { role = "ui", color = "textMuted", wrap = true })
  zoneSearch = W.EditBox(whereCard.body, {
    placeholder = "pets.zonePh",
    clear = true,
    onChange = function(text)
      if text ~= state.zone then
        state.zone = text
        paintDetail()
        view:Layout()
      end
    end,
  })
  if state.zone ~= "" then
    zoneSearch.edit:SetText(state.zone)
  end
  moreBtn = W.Button(whereCard.body, {
    text = " ",
    variant = "ghost",
    height = 24,
    onClick = function()
      showAll = not showAll
      paintDetail()
      view:Layout()
    end,
  })
  moreBtn.fgName = function()
    return moreBtn.label:GetText()
  end

  -- The where card stays shown across repaints: hiding it would drop the focus of the zone filter while typing.
  local whereShown = false

  local function paintWhere(rows, noneKey)
    local all = #rows
    local filtered = P.FilterBeastsByZone(rows, state.zone, ns.SearchLogic.match)
    local limited = P.Limit(filtered, WHERE_LIMIT, showAll)
    where.filterBox = all > WHERE_LIMIT or state.zone ~= ""
    where.note = #filtered == 0 and L[all > 0 and "pets.zoneNone" or noneKey] or nil
    whereNote:SetText(where.note or "")
    vis.tames = fill(pools.tames, whereCard.body, makeTameRow, #limited, function(row, i)
      row:Set(limited[i])
    end)
    where.more = #filtered > WHERE_LIMIT
    moreBtn.label:SetText(showAll and L["pets.showLess"] or string.format(L["pets.showAll"], #filtered))
    whereCard:SetCount(#filtered > 0 and #filtered or nil)
    whereCard:Show()
    whereShown = true
  end

  local function paintFamily(f)
    hero:SetPortrait({ texture = f.icon, name = ns.T(f.n) })
    hero:SetTitle(ns.T(f.n))
    hero:SetSubtitle("")
    hero:SetAttrs(familyAttrs(f))
    local count, lo, hi = P.TameSpan(f.id)
    hero:SetTags(count > 0 and {
      { text = string.format(L["pets.card.tames"], count, lo == hi and lo or (lo .. "-" .. hi)), color = "accent2" },
    } or nil)
    actions:SetPlace(nil)
    actions:SetShare("pets/" .. f.id)
    vis.mods = fill(pools.mods, famMods.body, makeStat, 3, function(row, i)
      local m = P.Modifiers(f)[i]
      row:Set({ key = "pets.mod." .. m.id, value = m.value })
    end)
    local abilities = {}
    for _, id in ipairs(f.ab) do
      local a = P.Ability(id)
      if a and a.ranks[1] then
        abilities[#abilities + 1] = a
      end
    end
    vis.abil = fill(pools.abil, famAbil.body, makeAbilityRow, #abilities, function(row, i)
      row:Set(abilities[i], openAbility)
    end)
    famMods:Show()
    famAbil:Show()
    famAbil:SetCount(#abilities)
    paintWhere(P.TamesOfFamily(f.id), "pets.whereNone")
  end

  local function paintAbility(a)
    hero:SetPortrait({ texture = spellIcon(a.ranks[1].s), name = ns.T(a.n) })
    hero:SetTitle(ns.T(a.n))
    hero:SetSubtitle(a.d and ns.T(a.d) or "")
    hero:SetAttrs(nil)
    local tags = { { text = abilitySub(a) } }
    if a.new then
      tags[#tags + 1] = { key = "pets.new", color = "accent2", tip = L["pets.newNote"] }
    end
    hero:SetTags(tags)
    actions:SetPlace(nil)
    actions:SetShare("pets/" .. a.id)
    vis.ranks = fill(pools.ranks, abilRanks.body, makeAttr, #a.ranks, function(row, i)
      row:Set({
        label = string.format(L["pets.rankLabel"], i),
        value = string.format(L["pets.levelValue"], a.ranks[i].l),
      })
    end)
    abilRanks:Show()
    local families = {}
    for _, id in ipairs(a.all and {} or a.fam) do
      families[#families + 1] = P.Family(id)
    end
    vis.fams = fill(pools.fams, abilFams.body, makeAttr, #families, function(row, i)
      local f = families[i]
      row:Set({
        icon = f.icon,
        label = ns.T(f.n),
        value = L["pets.role." .. f.role],
        tip = { title = ns.T(f.n), text = L["pets.card.open"] },
        onClick = function()
          openFamily(f)
        end,
      })
    end)
    famNote:SetText(a.all and L["pets.whereAll"] or L["pets.learn"])
    abilFams:Show()
    if a.all then
      whereCard:Hide()
    else
      paintWhere(P.BeastsOfAbility(a), "pets.whereNone")
    end
  end

  local function paintRare(b)
    local f = P.Family(b.fam)
    hero:SetPortrait({ texture = f and f.icon or nil, name = ns.T(b.n) })
    hero:SetTitle(ns.T(b.n))
    hero:SetSubtitle(f and ns.T(f.n) or "")
    hero:SetAttrs(nil)
    local tags = { { key = "pets.rareBadge", color = "accent2" } }
    if b.e then
      tags[#tags + 1] = { key = "pets.elite", color = "warning" }
    end
    hero:SetTags(tags)
    actions:SetPlace(P.Place(b))
    actions:SetShare("pets/rares")
    local facts = {
      { labelKey = "pets.attr.level", value = P.LevelText(b) },
      { labelKey = "pets.attr.zone", value = P.ZoneName(b) },
      { labelKey = "pets.attr.pos", value = K.Coord(b.x, b.y) or "?" },
    }
    if f then
      table.insert(facts, 1, {
        labelKey = "pets.attr.family",
        value = ns.T(f.n),
        tip = { title = ns.T(f.n), text = L["pets.card.open"] },
        onClick = function()
          openFamily(f)
        end,
      })
    end
    vis.facts = fill(pools.facts, rareFacts.body, makeAttr, #facts, function(row, i)
      row:Set(facts[i])
    end)
    rareFacts:Show()
    local attrs = f and familyAttrs(f) or {}
    vis.rfam = fill(pools.rfam, rareFam.body, makeAttr, #attrs, function(row, i)
      row:Set(attrs[i])
    end)
    if f then
      rareFam:Show()
    end
  end

  function paintDetail()
    for _, card in ipairs({ famMods, famAbil, abilRanks, abilFams, rareFacts, rareFam }) do
      card:Hide()
    end
    whereShown = false
    hero:SetShown(selected ~= nil)
    if not selected then
      whereCard:Hide()
      return
    end
    local key = state.tab .. ":" .. selected.id
    if painted ~= key then
      showAll, painted = false, key
    end
    if state.tab == "families" then
      paintFamily(selected)
    elseif state.tab == "abilities" then
      paintAbility(selected)
    else
      paintRare(selected)
    end
    if not whereShown then
      whereCard:Hide()
    end
  end

  function layoutDetail(width)
    if not selected then
      return 0
    end
    local gap = Theme.space.lg
    hero:ClearAllPoints()
    hero:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local y = hero:fgLayout(width) + gap
    cardRow:ClearAllPoints()
    cardRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    local h = cardRow:fgLayout(width)
    if h > 0 then
      y = y + h + gap
    end
    if whereCard:IsShown() then
      whereCard:ClearAllPoints()
      whereCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      y = y + whereCard:fgLayout(width) + gap
    end
    return y - gap
  end

  s:Add(split, { gap = Theme.space.lg })
  local emptyList = view.stack:Add(W.EmptyState(view.content, { text = "pets.empty", icon = "search", compact = true }))

  function openFamily(f)
    state.tab, state.family, state.detail = "families", f.id, true
    refresh()
  end

  function openAbility(a)
    state.tab, state.ability, state.detail = "abilities", a.id, true
    refresh()
  end

  function refresh()
    local tab = state.tab
    local match = ns.SearchLogic.match
    basis:SetText(ns.T(P.Basis()) or "")
    tabs:SetSelected(tab)
    filters:Refresh()
    if tab == "families" then
      shown = P.FilterFamilies(state.query, match)
    elseif tab == "abilities" then
      shown = P.FilterAbilities(state.query, match)
    else
      shown = P.FilterRares(state.query, match)
    end
    total:SetText(string.format(L["pets.total." .. tab], #shown))
    emptyList:SetAction(filters:IsFiltered() and W.EMPTY_RESET or nil, function()
      filters:Reset()
    end)
    emptyList:SetShown(#shown == 0)
    split:SetShown(#shown > 0)
    -- The chosen entry stays while the search still lists it, else the first one.
    selected = nil
    local wanted = state[STATE_KEY[tab]]
    for _, entry in ipairs(shown) do
      if entry.id == wanted then
        selected = entry
      end
    end
    selected = selected or shown[1]
    state[STATE_KEY[tab]] = selected and selected.id or ""
    state.detail = state.detail and selected ~= nil
    list:SetData(shown)
    paintDetail()
    -- Narrow pages open on the list; only a chosen entry shows its detail.
    syncing = true
    split:SetSelected(selected)
    split:ShowDetail(state.detail)
    syncing = false
    view:Layout()
  end

  -- Page link: the chosen family or ability, else the tab.
  function view:ShareState()
    if selected and state.detail and state.tab ~= "rares" then
      return { selected.id }
    end
    return { state.tab }
  end

  -- params[1] = a tab name, a family id or an ability id (deep link, /fg pets wolf); unknown ones are ignored.
  function view:Show(params)
    local first = params and params[1]
    if first == "abilities" or first == "rares" or first == "families" then
      state.tab = first
    elseif first and P.Family(first) then
      state.tab, state.family, state.detail = "families", first, true
    elseif first and P.Ability(first) then
      state.tab, state.ability, state.detail = "abilities", first, true
    end
    refresh()
  end
  ns.On("FG_UI_REFRESHED", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  return view
end

ns.RegisterPage({
  id = "pets",
  order = 350,
  group = "learn",
  title = "page.pets",
  subtitle = "page.pets.sub",
  icon = ns.ICONS.pets,
  aliases = { "begleiter", "pets", "pet", "haustiere", "jaegerbegleiter" },
  crumbLabel = function(param)
    local f = P.Family(param)
    local a = P.Ability(param)
    return f and ns.T(f.n) or a and ns.T(a.n) or param
  end,
  build = build,
})
