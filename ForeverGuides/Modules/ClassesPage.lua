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
  ["classes.tab.overview"] = "Rassen-Übersicht",
  ["classes.stats"] = "Klassenlehrer: %d\nLernbare Fähigkeiten: %d\nZauberkatalog: %d (Passive %d, Talente %d)\nWaffenfertigkeiten zu lernen: %d",
  ["classes.trainers"] = "Lehrer",
  ["classes.levels"] = "Stufen",
  ["classes.weapons"] = "Waffen",
  ["classes.races.hint"] = "Volk wählen: Klassen, Volksfähigkeiten, entfernte Fähigkeiten",
  ["tour.classes.title"] = "Klassen & Völker",
  ["tour.classes.intro.title"] = "Klassen, Völker, Fähigkeiten",
  ["tour.classes.intro.text"] = "Überblick über Klassen und Völker (Enter: weiter, Esc: Ende)",
  ["tour.classes.tabs.title"] = "Reiter",
  ["tour.classes.tabs.text"] = "Wechsle zwischen Klassen, Volksdetails und Rassen-Übersicht",
  ["tour.classes.content.title"] = "Inhalt",
  ["tour.classes.content.text"] = "Klassenkarten verlinken Lehrer, Stufenübersicht und Waffen",
})

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local groups = { classes = {}, races = {}, overview = {} }
  local state = { race = "human" }

  ns.AddParagraph(view, "classes.intro")

  local tabs
  local function showTab(id)
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
  s:Add(tabs, { height = 28, gap = 14 })

  local function add(group, item, o)
    groups[group][#groups[group] + 1] = item
    s:Add(item, o)
    return item
  end

  -- Classes ------------------------------------------------------------------
  local cards = {}
  for _, class in ipairs(R.CLASSES) do
    local card = W.Card(view.content, {})
    -- Same icon and class color border as the class buttons on the other pages.
    local color = K.ClassColorHex(class)
    card.border = W.Border(card, color, 0.7, 1)
    local icon = K.IconSlot(card, K.ClassIconSpec(class))
    icon:SetPoint("TOPLEFT", 12, -10)
    local name = W.Text(card, { role = "h3", family = "heading" })
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    local stats = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
    stats:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -38)
    stats:SetPoint("RIGHT", -12, 0)
    local b1 = W.Button(card, {
      key = "classes.trainers",
      width = 80,
      height = 22,
      onClick = function()
        ns.Router:navigate("trainers/" .. class)
      end,
    })
    b1:SetPoint("BOTTOMLEFT", 12, 10)
    local b2 = W.Button(card, {
      key = "classes.levels",
      width = 90,
      height = 22,
      onClick = function()
        ns.Router:navigate("levels/" .. class)
      end,
    })
    b2:SetPoint("LEFT", b1, "RIGHT", 6, 0)
    local b3 = W.Button(card, {
      key = "classes.weapons",
      width = 80,
      height = 22,
      onClick = function()
        ns.Router:navigate("weapons/" .. class)
      end,
    })
    b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    card.class, card.name, card.stats, card.icon, card.color = class, name, stats, icon, color
    cards[#cards + 1] = card
  end
  local grid = W.Grid(view.content, cards, 170)
  K.Anchor("FG.Classes.Content", grid)
  add("classes", grid)
  for _, c in ipairs(cards) do
    groups.classes[#groups.classes + 1] = c
  end

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
  add("races", raceButtons, { gap = 14 })
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

  function view:Show(params)
    if not K.HasData("Classes") then
      return
    end
    paintClasses()
    local tab = "classes"
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
