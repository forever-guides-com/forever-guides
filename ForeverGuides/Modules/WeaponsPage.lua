-- Weapon skills per class with weapon masters (location, level), modeled on
-- the website page "Waffenmeister": faction and race filter, variable-height
-- table rows, map and waypoint buttons per trainer.
-- Data: ns.Data.Weapons, ns.Data.WeaponRaces. Logic: ns.RefLogic.
local _, ns = ...
local W, L, Theme, R, K, U, CL = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.U, ns.CostLogic

ns.AddLocale("enUS", {
  ["weapons.intro"] = "Weapon skills: trainer and level per class",
  ["weapons.hint"] = "Some races start with a skill, no trainer needed",
  ["weapons.count"] = "%d skills for %s",
  ["weapons.raceLabel"] = "Faction and race (optional)",
  ["weapons.noTeacher"] = "No teacher needed.",
  ["weapons.fromStart"] = "From the start",
  ["weapons.levelUnknown"] = "Level unknown",
  ["weapons.unconfirmed"] = "not confirmed",
  ["weapons.col.skill"] = "Skill",
  ["weapons.col.level"] = "From level",
  ["weapons.col.trainer"] = "Teacher (faction)",
  ["weapons.col.place"] = "Location",
  ["weapons.col.map"] = "Map",
  ["weapons.acq.start"] = "known from the start",
  ["weapons.acq.weaponMaster"] = "weapon master",
  ["weapons.acq.classTrainer"] = "class trainer",
  ["weapons.level"] = "Level %d",
  ["weapons.master"] = "Weapon master: %s, %s (position %s)",
  ["weapons.masterNoPos"] = "Weapon master: %s, %s",
  ["weapons.trainerPage"] = "Class trainers are listed on the Class trainers page.",
  ["weapons.hidden"] = "%d weapon master(s) of the other faction hidden.",
  ["weapons.onlyOther"] = "Only weapon masters of the other faction in the data.",
  ["weapons.empty"] = "No weapon skills in the data for this class.",
  ["weapons.basis"] = "Capitals, Classic positions, unconfirmed marked",
  ["tour.weapons.title"] = "Weapon skills",
  ["tour.weapons.intro.title"] = "Weapon skills",
  ["tour.weapons.intro.text"] = "See which weapons your class uses and where to learn them (Enter: next, Esc: end)",
  ["tour.weapons.filters.title"] = "Class, faction and race",
  ["tour.weapons.filters.text"] = "Pick class, faction, race: a race shows its start skills",
  ["tour.weapons.list.title"] = "Skills",
  ["tour.weapons.list.text"] = "Per skill: weapon masters with zone, position, map and waypoint buttons",
})

ns.AddLocale("deDE", {
  ["weapons.intro"] = "Waffenfertigkeiten: Lehrer und Stufe je Klasse",
  ["weapons.hint"] = "Manche Rassen starten mit einer Fertigkeit, ohne Lehrer",
  ["weapons.count"] = "%d Fertigkeiten für %s",
  ["weapons.raceLabel"] = "Fraktion und Rasse (optional)",
  ["weapons.noTeacher"] = "Kein Lehrer nötig.",
  ["weapons.fromStart"] = "Von Anfang an",
  ["weapons.levelUnknown"] = "Stufe unbekannt",
  ["weapons.unconfirmed"] = "nicht bestätigt",
  ["weapons.col.skill"] = "Fertigkeit",
  ["weapons.col.level"] = "Ab Stufe",
  ["weapons.col.trainer"] = "Lehrer (Fraktion)",
  ["weapons.col.place"] = "Ort",
  ["weapons.col.map"] = "Karte",
  ["weapons.acq.start"] = "von Anfang an bekannt",
  ["weapons.acq.weaponMaster"] = "Waffenmeister",
  ["weapons.acq.classTrainer"] = "Klassenlehrer",
  ["weapons.level"] = "Stufe %d",
  ["weapons.master"] = "Waffenmeister: %s, %s (Position %s)",
  ["weapons.masterNoPos"] = "Waffenmeister: %s, %s",
  ["weapons.trainerPage"] = "Klassenlehrer stehen auf der Seite Klassenlehrer.",
  ["weapons.hidden"] = "%d Waffenmeister der anderen Fraktion ausgeblendet.",
  ["weapons.onlyOther"] = "In den Daten nur Waffenmeister der anderen Fraktion.",
  ["weapons.empty"] = "Keine Waffenfertigkeiten für diese Klasse in den Daten.",
  ["weapons.basis"] = "Hauptstädte, Classic-Positionen, Unbestätigtes markiert",
  ["tour.weapons.title"] = "Waffenfertigkeiten",
  ["tour.weapons.intro.title"] = "Waffenfertigkeiten",
  ["tour.weapons.intro.text"] = "Sieh, welche Waffen deine Klasse nutzt und wo man sie lernt (Enter: weiter, Esc: Ende)",
  ["tour.weapons.filters.title"] = "Klasse, Fraktion und Rasse",
  ["tour.weapons.filters.text"] = "Klasse, Fraktion, Rasse wählen: die Rasse zeigt Startfertigkeiten",
  ["tour.weapons.list.title"] = "Fertigkeiten",
  ["tour.weapons.list.text"] = "Je Fertigkeit: Waffenmeister mit Zone, Position, Karten- und Markerknopf",
})

-- Icon names are best-effort Classic-era references, not pixel-verified
-- against the Forever client, spot-check in game and adjust if any look wrong.
local SKILL_ICONS = {
  axe1h = "INV_Axe_01",
  axe2h = "INV_Axe_02",
  bow = "INV_Weapon_Bow_01",
  crossbow = "INV_Weapon_Crossbow_01",
  dagger = "INV_Weapon_ShortBlade_01",
  dualwield = "Ability_DualWield",
  fist = "INV_Gauntlets_04",
  gun = "INV_Weapon_Rifle_01",
  leather = "INV_Chest_Leather_01",
  mace1h = "INV_Mace_01",
  mace2h = "INV_Mace_02",
  mail = "INV_Chest_Chain_01",
  parry = "Ability_Defend",
  plate = "INV_Chest_Plate01",
  polearm = "INV_Weapon_Polearm_01",
  shield = "INV_Shield_04",
  staff = "INV_Staff_01",
  sword1h = "INV_Sword_04",
  sword2h = "INV_Sword_07",
  thrown = "INV_ThrowingAxe_01",
  wand = "INV_Wand_01",
}

-- UnitRace's second return value to the WeaponRaces slug. The Skyborne
-- tokens are unknown, those players pick their race by hand.
local RACE_TOKEN_SLUG = {
  Human = "human",
  Dwarf = "dwarf",
  NightElf = "night-elf",
  Gnome = "gnome",
  Orc = "orc",
  Scourge = "undead",
  Tauren = "tauren",
  Troll = "troll",
}

local function skillIcon(skill)
  return SKILL_ICONS[skill] and ("Interface\\Icons\\" .. SKILL_ICONS[skill]) or ns.ICONS.weapons
end

local function playerRaceSlug()
  if not UnitRace then
    return nil
  end
  local _, token = UnitRace("player")
  return RACE_TOKEN_SLUG[token]
end

-- True when the skill needs no teacher: either the selected race knows it from
-- the start or everybody does.
local function needsNoTeacher(row)
  return row.raceStart or row.a == "start"
end

local function skillBodyText(row)
  local lines = {}
  if row.raceStart then
    return L["weapons.noTeacher"]
  end
  if row.h then
    lines[#lines + 1] = ns.T(row.h) or ""
  end
  for _, t in ipairs(row.trainers) do
    local zone = ns.T(t.z) or "?"
    local pos = K.Coord(t.x, t.y)
    local name = ns.T(t.n) or t.id
    local line = pos and string.format(L["weapons.master"], name, zone, pos)
      or string.format(L["weapons.masterNoPos"], name, zone)
    if t.unconfirmed then
      line = line .. " " .. Theme.hexText("textMuted", L["weapons.unconfirmed"])
    end
    lines[#lines + 1] = line
  end
  if row.a == "classTrainer" then
    lines[#lines + 1] = L["weapons.trainerPage"]
  end
  if row.hidden > 0 then
    lines[#lines + 1] = Theme.hexText(
      "textMuted",
      #row.trainers == 0 and L["weapons.onlyOther"] or string.format(L["weapons.hidden"], row.hidden)
    )
  end
  return table.concat(lines, "\n")
end

-- Price of a table row, or nil: skills known from the start (for everybody or
-- the chosen race) cost nothing and show no price.
local function rowPrice(row, class)
  if needsNoTeacher(row) then
    return nil
  end
  local price = CL.ItemPrice({ kind = "weapon", skill = row.skill, a = row.a }, class)
  return price.cost and price or nil
end

-- Invisible button over a price text that explains where the price comes from.
local function priceTip(parent, fs)
  local b = CreateFrame("Button", nil, parent)
  b:SetAllPoints(fs)
  b:SetScript("OnEnter", function(self)
    if self.tip then
      ns.ShowTooltip(self, self.tip)
    end
  end)
  b:SetScript("OnLeave", ns.HideTooltip)
  return b
end

local function paintPrice(fs, tipButton, price)
  local text = CL.Text(price)
  fs:SetText(text or "")
  fs:SetShown(text ~= nil)
  tipButton.tip = text and CL.Tip(price) or nil
  tipButton:SetShown(text ~= nil)
  return text ~= nil
end

local ACQ_BADGE_COLOR = { start = "success", weaponMaster = "accent2", classTrainer = "textMuted" }

-- Table rows ---------------------------------------------------------------------

local ROW_PAD = 8
local SKILL_ICON_SIZE = 24
local CREST_SIZE = 16
local ACTIONS_W = W.MAP_ACTION_SIZE * 2 + W.MAP_ACTION_GAP
local ACTIONS_H = W.MAP_ACTION_SIZE
local LINE_GAP = 4

-- Left block (skill + level) and right block (trainers) of a table row, shared
-- by the header and the rows so both line up.
local function columns(width)
  local leftW = U.clamp(math.floor(width * 0.34), 150, 240)
  local rightX = leftW + 12
  return leftW, rightX, math.max(120, width - rightX)
end

local function newTrainerLine(row)
  local line = {}
  line.crest = row:CreateTexture(nil, "ARTWORK")
  line.crest:SetSize(CREST_SIZE, CREST_SIZE)
  line.crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  line.text = W.Text(row, { role = "ui", wrap = true })
  line.actions = W.MapActionButtons(row, { mapTip = "trainers.mapTip", markerTip = "trainers.markerTip" })
  return line
end

local function paintTrainerLine(line, t)
  local crest = K.FACTION_CREST[t.f]
  if crest then
    line.crest:SetTexture(crest)
  end
  line.crest:SetShown(crest ~= nil)
  local zone = ns.T(t.z)
  local where
  if zone then
    local pos = K.Coord(t.x, t.y)
    where = pos and (zone .. " · " .. pos) or zone
  else
    where = L["weapons.trainerPage"]
  end
  local text = (ns.T(t.n) or t.id) .. "  " .. Theme.hexText("textSecondary", where)
  if t.unconfirmed then
    text = text .. "  " .. Theme.hexText("textMuted", L["weapons.unconfirmed"])
  end
  line.text:SetText(text)
  line.text:Show()
  local hasMap = t.m ~= nil and t.x ~= nil and t.y ~= nil
  line.trainer = hasMap and t or nil
  line.actions:SetPlace(hasMap and {
    map = t.m,
    x = t.x,
    y = t.y,
    label = ns.T(t.n) or t.id,
    zone = ns.T(t.z),
  } or nil)
end

local function hideTrainerLine(line)
  line.crest:Hide()
  line.text:Hide()
  line.actions:SetPlace(nil)
  line.trainer = nil
end

local function layoutRow(row, width)
  local leftW, rightX, rightW = columns(width)
  local textX = ROW_PAD + SKILL_ICON_SIZE + 8
  local textW = math.max(40, leftW - textX)

  row.icon:ClearAllPoints()
  row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD, -ROW_PAD)
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -ROW_PAD)
  row.name:SetWidth(textW)
  local nameH = row.name:GetStringHeight()
  row.level:ClearAllPoints()
  row.level:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -(ROW_PAD + nameH + 2))
  row.level:SetWidth(textW)
  local leftBottom = ROW_PAD + nameH + 2 + row.level:GetStringHeight()
  row.price:ClearAllPoints()
  if row.priceShown then
    row.price:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -(leftBottom + 2))
    row.price:SetWidth(textW)
    leftBottom = leftBottom + 2 + row.price:GetStringHeight()
  end
  local leftH = math.max(ROW_PAD * 2 + SKILL_ICON_SIZE, leftBottom + ROW_PAD)

  local y = ROW_PAD
  if row.noTeacherMode then
    row.noTeacher:ClearAllPoints()
    row.noTeacher:SetPoint("TOPLEFT", row, "TOPLEFT", rightX, -y)
    row.noTeacher:SetWidth(rightW)
    y = y + row.noTeacher:GetStringHeight() + LINE_GAP
  else
    local lineTextX = rightX + CREST_SIZE + 6
    -- Measured against the real row width: the right block has a minimum width the row may not have.
    local lineTextW = math.max(24, width - lineTextX - ACTIONS_W - 6 - ROW_PAD)
    for i = 1, row.lineCount do
      local line = row.lines[i]
      line.text:ClearAllPoints()
      line.text:SetPoint("TOPLEFT", row, "TOPLEFT", lineTextX, -(y + 2))
      line.text:SetWidth(lineTextW)
      local lineH = line.text:GetStringHeight() + 4
      line.crest:ClearAllPoints()
      line.crest:SetPoint("TOPLEFT", row, "TOPLEFT", rightX, -(y + 2))
      if line.trainer then
        line.actions:ClearAllPoints()
        line.actions:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD, -y)
        lineH = math.max(lineH, ACTIONS_H)
      end
      y = y + lineH + LINE_GAP
    end
    if row.showHidden then
      row.hiddenNote:ClearAllPoints()
      row.hiddenNote:SetPoint("TOPLEFT", row, "TOPLEFT", rightX, -y)
      row.hiddenNote:SetWidth(rightW)
      y = y + row.hiddenNote:GetStringHeight() + LINE_GAP
    end
  end
  return math.max(leftH, y - LINE_GAP + ROW_PAD)
end

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(SKILL_ICON_SIZE, SKILL_ICON_SIZE)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.level = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.price = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.priceTip = priceTip(row, row.price)
  row.noTeacher = W.Text(row, { key = "weapons.noTeacher", role = "ui", color = "textMuted", wrap = true })
  row.hiddenNote = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetPoint("BOTTOMLEFT")
  row.divider:SetPoint("BOTTOMRIGHT")
  row.divider:SetHeight(1)
  ns.Bind(row, function()
    row.divider:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  row.lines = {}
  row.lineCount = 0
  row.fgLayout = layoutRow
  return row
end

local function paintRow(row, item)
  row.icon:SetTexture(skillIcon(item.skill))
  row.name:SetText(item.name)

  local noTeacher = needsNoTeacher(item)
  row.noTeacherMode = noTeacher
  local levelText, levelColor
  if noTeacher then
    levelText, levelColor = L["weapons.fromStart"], "success"
  elseif item.l then
    levelText, levelColor = string.format(L["weapons.level"], item.l), "textSecondary"
  else
    levelText, levelColor = L["weapons.levelUnknown"], "textSecondary"
  end
  if item.unconfirmed then
    levelText = levelText .. "  " .. Theme.hexText("textMuted", L["weapons.unconfirmed"])
  end
  row.level:SetText(levelText)
  W.SetColor(row.level, levelColor)
  row.priceShown = paintPrice(row.price, row.priceTip, item.price)
  row.noTeacher:SetShown(noTeacher)

  local count = 0
  if not noTeacher then
    for i, t in ipairs(item.trainers) do
      local line = row.lines[i]
      if not line then
        line = newTrainerLine(row)
        row.lines[i] = line
      end
      paintTrainerLine(line, t)
      count = i
    end
  end
  for i = count + 1, #row.lines do
    hideTrainerLine(row.lines[i])
  end
  row.lineCount = count

  row.showHidden = not noTeacher and item.hidden > 0
  if row.showHidden then
    row.hiddenNote:SetText(
      #item.trainers == 0 and L["weapons.onlyOther"] or string.format(L["weapons.hidden"], item.hidden)
    )
  end
  row.hiddenNote:SetShown(row.showHidden)
end

-- Page ---------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local races = (ns.Data and ns.Data.WeaponRaces and ns.Data.WeaponRaces.races) or {}
  local state = {
    class = K.PlayerClass() or "WARRIOR",
    faction = K.PlayerFaction() or "A",
    race = playerRaceSlug(),
    view = ns.db.settings.weaponsView or "list",
  }
  local function raceAllowed(slug, faction)
    for _, race in ipairs(R.RacesForClass(state.class, faction)) do
      if race.s == slug then
        return true
      end
    end
    return false
  end
  -- A race that is hidden (other faction) or cannot be the chosen class would
  -- act invisibly, so the selection falls back to "all races".
  local function dropInvalidRace()
    if state.race and not raceAllowed(state.race, state.faction ~= "all" and state.faction or nil) then
      state.race = nil
    end
  end
  dropInvalidRace()
  local refresh

  ns.AddParagraph(view, "weapons.intro")
  ns.AddParagraph(view, "weapons.basis", { role = "micro", color = "textMuted" })

  local classButtons = K.ClassButtons(view.content, {
    get = function()
      return state.class
    end,
    set = function(v)
      state.class = v
      dropInvalidRace()
      refresh()
    end,
  })
  K.Anchor("FG.Weapons.Filters", classButtons)
  s:Add(classButtons, { gap = 12 })

  s:Add(W.Text(view.content, { key = "weapons.raceLabel", role = "ui" }), { gap = 4 })
  local selector = K.FactionRaceSelector(view.content, {
    races = races,
    raceAllowed = raceAllowed,
    getFaction = function()
      return state.faction
    end,
    setFaction = function(v)
      state.faction = v
      dropInvalidRace()
      refresh()
    end,
    getRace = function()
      return state.race
    end,
    setRace = function(slug)
      state.race = slug
      refresh()
    end,
  })
  s:Add(selector, { gap = 12 })

  ns.AddParagraph(view, "weapons.hint", { role = "micro", color = "textMuted" })
  local message = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })
  local count = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })
  local total = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })
  ns.AddParagraph(view, "cost.legend", { role = "micro", color = "textMuted" })

  local viewToggle = K.ViewToggle(view.content, {
    get = function()
      return state.view
    end,
    set = function(v)
      state.view = v
      ns.Store.set("settings.weaponsView", v)
      refresh()
    end,
  })
  K.Anchor("FG.Weapons.ViewToggle", viewToggle)
  s:Add(viewToggle, { height = 22, gap = 10 })

  local header = CreateFrame("Frame", nil, view.content)
  W.Fill(header, "surface", 1)
  local headLeft = W.Text(header, {
    text = string.format("%s / %s", L["weapons.col.skill"], L["weapons.col.level"]),
    role = "micro",
    color = "textSecondary",
    wrap = true,
  })
  local headRight = W.Text(header, {
    text = string.format("%s / %s / %s", L["weapons.col.trainer"], L["weapons.col.place"], L["weapons.col.map"]),
    role = "micro",
    color = "textSecondary",
    wrap = true,
  })
  function header:fgGridLayout(width)
    local leftW, rightX, rightW = columns(width)
    headLeft:ClearAllPoints()
    headLeft:SetPoint("TOPLEFT", header, "TOPLEFT", ROW_PAD, -6)
    headLeft:SetWidth(leftW - ROW_PAD)
    headRight:ClearAllPoints()
    headRight:SetPoint("TOPLEFT", header, "TOPLEFT", rightX, -6)
    headRight:SetWidth(rightW)
    local h = math.max(headLeft:GetStringHeight(), headRight:GetStringHeight()) + 12
    header:SetHeight(h)
    return h
  end
  s:Add(header, { gap = 0 })

  local rowList = K.RowPool(view.content, makeRow)
  K.Anchor("FG.Weapons.List", rowList)
  s:Add(rowList, { gap = 14 })

  local weaponGrid = K.GridPool(view.content, 190, function(parent)
    local card = W.Card(parent, {})
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 12, -12)
    card.icon:SetSize(40, 40)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.name = W.Text(card, { role = "ui", color = "accent2", wrap = true })
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
    card.name:SetPoint("RIGHT", -24, 0)
    card.badge = W.Badge(card, "weapons.acq.start", "success")
    card.badge:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -24)
    card.level = W.Text(card, { role = "micro", color = "textMuted" })
    card.level:SetPoint("LEFT", card.badge, "RIGHT", 8, 0)
    card.dot = K.ConfidenceDot(card, 2)
    card.dot:SetPoint("TOPRIGHT", -10, -10)
    card.price = W.Text(card, { role = "micro", color = "textSecondary" })
    card.price:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -6)
    card.priceTip = priceTip(card, card.price)
    card.body = W.Text(card, { role = "micro", color = "textSecondary", wrap = true })
    card.body:SetPoint("TOPLEFT", card.price, "BOTTOMLEFT", 0, -6)
    card.body:SetPoint("RIGHT", -12, 0)
    return card
  end)
  s:Add(weaponGrid, { gap = 14 })

  local function paintWeaponCard(card, row)
    card.icon:SetTexture(skillIcon(row.skill))
    card.name:SetText(row.name)
    if row.raceStart then
      card.badge:SetKey("weapons.fromStart", "success")
      card.level:SetText("")
    else
      card.badge:SetKey("weapons.acq." .. tostring(row.a), ACQ_BADGE_COLOR[row.a] or "textMuted")
      card.level:SetText(row.l and string.format(L["weapons.level"], row.l) or "")
    end
    card.dot:SetCf(row.unconfirmed and 1 or row.cf)
    paintPrice(card.price, card.priceTip, row.price)
    card.body:SetText(skillBodyText(row))
  end

  function refresh()
    local rows = {}
    if K.HasData("Weapons") then
      rows = R.Weapons(state.class, state.faction ~= "all" and state.faction or nil, state.race)
      message:SetText(#rows == 0 and L["weapons.empty"] or "")
    else
      message:SetText(L["kit.noData"])
    end
    count:SetText(#rows > 0 and string.format(L["weapons.count"], #rows, R.className(state.class)) or "")
    local prices = {}
    for _, r in ipairs(rows) do
      r.price = rowPrice(r, state.class)
      if not needsNoTeacher(r) then
        prices[#prices + 1] = r.price or {}
      end
    end
    total:SetText(CL.SumText(CL.Sum(prices), { key = "cost.weaponsTotal" }) or "")
    local asList = state.view == "list"
    header:SetShown(asList)
    rowList:SetShown(asList)
    weaponGrid:SetShown(not asList)
    if asList then
      rowList:Sync(rows, paintRow)
    else
      weaponGrid:Sync(rows, paintWeaponCard)
    end
    classButtons.Refresh()
    selector.Refresh()
    viewToggle.Refresh()
    view:Layout()
  end

  function view:Show(params)
    local c = params and params[1]
    if c and R.className(c) ~= c then
      state.class = c
      dropInvalidRace()
    end
    refresh()
  end
  return view
end

ns.RegisterPage({
  id = "weapons",
  order = 340,
  group = "learn",
  title = "page.weapons",
  icon = ns.ICONS.weapons,
  aliases = { "waffen", "weapons" },
  crumbLabel = function(param)
    return R.className(param)
  end,
  build = build,
})
