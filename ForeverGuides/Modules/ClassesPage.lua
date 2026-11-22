-- Classes & races page: class overview, race details and the race overview
-- (views in RaceViews.lua). Data: ns.Data.Classes/RaceInfo/Spells/Abilities.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit
local RL, RV = ns.RaceLogic, ns.RaceViews

ns.AddLocale("enUS", {
  ["classes.intro"] = "Nine classes, ten races, racial abilities",
  ["classes.tab.classes"] = "Classes",
  ["classes.tab.races"] = "Races",
  ["classes.tab.overview"] = "Race overview",
  ["classes.stats"] = "Class trainers: %d\nLearnable abilities: %d\nSpell catalog: %d (passives %d, talents %d)\nWeapon skills to learn: %d",
  ["classes.trainers"] = "Trainers",
  ["classes.levels"] = "Levels",
  ["classes.weapons"] = "Weapons",
  ["classes.races.hint"] = "Pick a race: classes, racial and removed abilities",
  ["tour.classes.title"] = "Classes & races",
  ["tour.classes.intro.title"] = "Classes, races, abilities",
  ["tour.classes.intro.text"] = "Overview of classes and races (Enter: next, Esc: end)",
  ["tour.classes.tabs.title"] = "Tabs",
  ["tour.classes.tabs.text"] = "Switch between classes, race details and race overview",
  ["tour.classes.content.title"] = "Content",
  ["tour.classes.content.text"] = "Class cards link to trainers, levels and weapon skills",
})

ns.AddLocale("deDE", {
  ["classes.intro"] = "Neun Klassen, zehn Völker, Volksfähigkeiten",
  ["classes.tab.classes"] = "Klassen",
  ["classes.tab.races"] = "Völker",
  ["classes.tab.overview"] = "Rassenübersicht",
  ["classes.stats"] = "Klassenlehrer: %d\nLernbare Fähigkeiten: %d\nZauberkatalog: %d (Passive %d, Talente %d)\nWaffenfertigkeiten zu lernen: %d",
  ["classes.trainers"] = "Lehrer",
  ["classes.levels"] = "Stufen",
  ["classes.weapons"] = "Waffen",
  ["classes.races.hint"] = "Volk wählen: Klassen, Volksfähigkeiten, entfernte Fähigkeiten",
  ["tour.classes.title"] = "Klassen & Völker",
  ["tour.classes.intro.title"] = "Klassen, Völker, Fähigkeiten",
  ["tour.classes.intro.text"] = "Überblick über Klassen und Völker (Enter: weiter, Esc: Ende)",
  ["tour.classes.tabs.title"] = "Reiter",
  ["tour.classes.tabs.text"] = "Wechsle zwischen Klassen, Volksdetails und Rassenübersicht",
  ["tour.classes.content.title"] = "Inhalt",
  ["tour.classes.content.text"] = "Klassenkarten verlinken Lehrer, Stufenübersicht und Waffen",
})

local CARD_MIN_W = 260

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local groups = { classes = {}, races = {}, overview = {} }
  local state = { race = "human", tab = "classes" }
  ns.PageState.Bind(view, state, { "race", "tab" })
  if not RL.Info(state.race) then
    state.race = "human"
  end

  ns.AddIntro(view, "classes.intro")

  local tabs
  local function showTab(id)
    state.tab = id
    for name, items in pairs(groups) do
      for _, item in ipairs(items) do
        item:SetShown(name == id)
      end
    end
    view:Layout()
  end
  tabs = W.Tabs(view.content, {
    tabs = {
      { id = "classes", key = "classes.tab.classes" },
      { id = "races", key = "classes.tab.races" },
      { id = "overview", key = "classes.tab.overview" },
    },
    onSelect = showTab,
  })
  K.Anchor("FG.Classes.Tabs", tabs)
  s:Add(tabs, { height = 28, gap = Theme.space.lg })

  local function add(group, item, o)
    groups[group][#groups[group] + 1] = item
    s:Add(item, o)
    return item
  end

  -- Classes ------------------------------------------------------------------
  local cards = {}
  local grid = CreateFrame("Frame", nil, view.content)
  for _, class in ipairs(R.CLASSES) do
    -- Same icon and class color border as the class buttons on the other pages.
    local color = K.ClassColorHex(class)
    local card = W.Panel(grid, { edge = color, edgeAlpha = 0.7 })
    card.border = card.rim
    local icon = K.IconSlot(card, K.ClassIconSpec(class))
    local name = W.Text(card, { role = "h3", family = "heading" })
    local stats = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
    local function goTo(page)
      return function()
        ns.Router:navigate(page .. "/" .. class)
      end
    end
    local buttons = {
      { W.Button(card, { key = "classes.trainers", width = 80, height = 22, opens = true, onClick = goTo("trainers") }), 80 },
      { W.Button(card, { key = "classes.levels", width = 90, height = 22, opens = true, onClick = goTo("levels") }), 90 },
      { W.Button(card, { key = "classes.weapons", width = 80, height = 22, opens = true, onClick = goTo("weapons") }), 80 },
    }
    -- The card is as high as its content: head, the wrapped stats and the buttons, which are as wide as their
    -- labels (at least the base width) and wrap into rows.
    function card:fgLayout(width)
      local pad, gap = self.pad, Theme.space.sm
      local avail = math.max(40, width - pad * 2)
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", pad, -pad)
      name:ClearAllPoints()
      name:SetPoint("LEFT", icon, "RIGHT", Theme.space.sm, 0)
      name:SetPoint("RIGHT", self, "RIGHT", -pad, 0)
      local y = pad + icon:GetHeight() + gap
      stats:ClearAllPoints()
      stats:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
      stats:SetWidth(avail)
      y = y + math.ceil(stats:GetStringHeight()) + gap
      local rows, rowW = { {} }, 0
      for _, entry in ipairs(buttons) do
        local b = entry[1]
        local w = math.min(avail, math.max(entry[2], b:Fit(avail)))
        b:SetWidth(w)
        if rowW > 0 and rowW + gap + w > avail then
          rows[#rows + 1], rowW = {}, 0
        end
        local row = rows[#rows]
        row[#row + 1] = { b, rowW }
        rowW = rowW + w + gap
      end
      local bh = buttons[1][1]:GetHeight()
      for r, row in ipairs(rows) do
        for _, item in ipairs(row) do
          item[1]:ClearAllPoints()
          item[1]:SetPoint("TOPLEFT", self, "TOPLEFT", pad + item[2], -(y + (r - 1) * (bh + gap)))
        end
      end
      return y + #rows * bh + (#rows - 1) * gap + pad
    end
    card.class, card.name, card.stats, card.icon, card.color = class, name, stats, icon, color
    cards[#cards + 1] = card
  end
  -- The class cards flow into one to three columns (ns.CardFlow); every card has the height of its content.
  function grid:fgGridLayout(width)
    local gap = Theme.space.md
    local cols, cw = ns.CardFlow.Columns(width, CARD_MIN_W, gap)
    local heights = {}
    for i, card in ipairs(cards) do
      card:SetWidth(cw)
      heights[i] = card:fgLayout(cw)
      card:SetHeight(heights[i])
    end
    local spots, total = ns.CardFlow.Place(heights, cols, cw, gap)
    for i, card in ipairs(cards) do
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", self, "TOPLEFT", spots[i].x, -spots[i].y)
    end
    self:SetHeight(total)
    return total
  end
  K.Anchor("FG.Classes.Content", grid)
  add("classes", grid)

  local function paintClasses()
    for _, card in ipairs(cards) do
      local st = R.ClassStats(card.class)
      card.name:SetText(
        Theme.hexText(R.classColor(card.class) and ("#" .. R.classColor(card.class)) or "text", R.className(card.class))
      )
      card.stats:SetText(
        string.format(L["classes.stats"], st.trainers, st.abilities, st.spells, st.passives, st.talents, st.weapons)
      )
    end
  end

  -- Races --------------------------------------------------------------------
  local function openRace(slug)
    view:Show({ "races", slug })
  end
  add("races", W.Text(view.content, { key = "classes.races.hint", role = "ui", color = "textSecondary", wrap = true }))
  local raceButtons = K.RaceButtons(view.content, {
    races = RL.Races(),
    get = function()
      return state.race
    end,
    set = openRace,
  })
  add("races", raceButtons, { gap = Theme.space.lg })
  local raceDetail = RV.Detail(view.content)
  add("races", raceDetail)

  -- Overview -------------------------------------------------------------------
  local overview = RV.Overview(view.content, {
    onSelect = openRace,
    relayout = function()
      view:Layout()
    end,
  })
  add("overview", overview)

  -- Names and texts come from the data, so a language change repaints them.
  ns.On("FG_UI_REFRESHED", function()
    if raceDetail:IsVisible() or overview:IsVisible() then
      raceDetail:SetRace(state.race)
      overview:Paint()
      view:Layout()
    end
  end)

  -- Page link: the tab and, on the race tab, the race.
  function view:ShareState()
    local tab = tabs.selected
    if tab == "races" then
      return { tab, state.race }
    end
    return tab == "overview" and { tab } or {}
  end

  function view:Show(params)
    if not K.HasData("Classes") then
      return
    end
    paintClasses()
    -- No link: the tab the page was left on. Any other link (a class id, the list) shows the classes.
    local tab = (not params or #params == 0) and groups[state.tab] and state.tab or "classes"
    if params and params[1] == "races" then
      tab = "races"
      if RL.Info(params[2]) then
        state.race = params[2]
      end
    elseif params and params[1] == "overview" then
      tab = "overview"
    end
    raceButtons.Refresh()
    raceDetail:SetRace(state.race)
    overview:Paint()
    tabs:Select(tab)
  end
  return view
end

ns.RegisterPage({
  id = "classes",
  order = 310,
  group = "learn",
  title = "page.classes",
  icon = ns.ICONS.classes,
  aliases = { "klassen", "rassen", "voelker", "classes", "races" },
  crumbLabel = function(param)
    return L["classes.tab." .. param] ~= "classes.tab." .. param and L["classes.tab." .. param] or R.className(param)
  end,
  build = build,
})
