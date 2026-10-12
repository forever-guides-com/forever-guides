-- Level overview page: per class, which abilities and ranks the class trainer
-- teaches at which level, one card per level with icon chips (same idea as the
-- website's "Stufenliste" view, without talents and weapon skills).
-- Data: ns.Data.Abilities, LevelSources. Logic: ns.LevelLogic.
local _, ns = ...
local R, K = ns.RefLogic, ns.PageKit

ns.AddLocale("enUS", {
  ["levels.intro"] = "What your class gets at which level: new abilities and ranks you can learn at your class trainer. Talents and weapon skills are not listed here, weapon skills have their own page. Abilities marked as quest abilities are taught by the trainer too, you just need a quest first.",
  ["levels.basis"] = "Levels from website data (Classic values, not all confirmed for Forever)\nNo trainer costs in the data",
  ["levels.search"] = "Search (ability)",
  ["levels.fromMe"] = "From level",
  ["levels.fromHint"] = "1 to 60",
  ["levels.fromPlaceholder"] = "1",
  ["levels.mine"] = "My level",
  ["levels.count"] = "Level list: %d entries on %d levels for %s",
  ["levels.hint"] = "Hover an entry for its tooltip",
  ["levels.level"] = "Level %d",
  ["levels.rank"] = "rank %d",
  ["levels.viaQuest"] = "via quest",
  ["levels.learned"] = "learned",
  ["levels.empty"] = "Nothing matches.",
  ["tour.levels.title"] = "Level overview",
  ["tour.levels.intro.title"] = "Level overview",
  ["tour.levels.intro.text"] = "See what you get at which level (Enter: next, Esc: end)",
  ["tour.levels.filters.title"] = "Class and filter",
  ["tour.levels.filters.text"] = "Pick class, search an ability, set the start level, reset filters",
  ["tour.levels.list.title"] = "Levels",
  ["tour.levels.list.text"] = "One card per level with chips for the abilities at the class trainer",
})

ns.AddLocale("deDE", {
  ["levels.intro"] = 'Was deine Klasse bei welcher Stufe bekommt: neue Fähigkeiten und Ränge, die du beim Klassenlehrer lernen kannst. Talente und Waffenfertigkeiten stehen hier nicht, Waffenfertigkeiten haben eine eigene Seite. Fähigkeiten mit dem Hinweis "über Quest" lehrt der Lehrer ebenfalls, dafür brauchst du vorher eine Quest.',
  ["levels.basis"] = "Stufen aus Website-Daten (Classic-Werte, nicht alle für Forever bestätigt)\nKeine Lehrerkosten in den Daten",
  ["levels.search"] = "Suchen (Fähigkeit)",
  ["levels.fromMe"] = "Ab Stufe",
  ["levels.fromHint"] = "1 bis 60",
  ["levels.fromPlaceholder"] = "1",
  ["levels.mine"] = "Meine Stufe",
  ["levels.count"] = "Stufenliste: %d Einträge auf %d Stufen für %s",
  ["levels.hint"] = "Maus über einen Eintrag zeigt den Tooltip",
  ["levels.level"] = "Stufe %d",
  ["levels.rank"] = "Rang %d",
  ["levels.viaQuest"] = "über Quest",
  ["levels.learned"] = "gelernt",
  ["levels.empty"] = "Nichts passt.",
  ["tour.levels.title"] = "Stufen-Übersicht",
  ["tour.levels.intro.title"] = "Stufen-Übersicht",
  ["tour.levels.intro.text"] = "Sieh, was du bei welcher Stufe bekommst (Enter: weiter, Esc: Ende)",
  ["tour.levels.filters.title"] = "Klasse und Filter",
  ["tour.levels.filters.text"] = "Klasse wählen, Fähigkeit suchen, Startstufe setzen, Filter zurücksetzen",
  ["tour.levels.list.title"] = "Stufen",
  ["tour.levels.list.text"] = "Eine Karte je Stufe mit Chips für die Fähigkeiten beim Klassenlehrer",
})

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { class = K.PlayerClass() or "WARRIOR" }
  local learnList

  ns.AddParagraph(view, "levels.intro")
  ns.AddParagraph(view, "levels.basis", { role = "micro", color = "textMuted" })

  local classFrame
  classFrame = K.ClassButtons(view.content, {
    get = function()
      return state.class
    end,
    set = function(v)
      state.class = v
      learnList.Refresh()
      classFrame.Refresh()
    end,
  })
  K.Anchor("FG.Levels.Class", classFrame)
  s:Add(classFrame, { gap = 12 })

  learnList = ns.LevelView.Create(view, {
    anchor = "FG.Levels",
    getClass = function()
      return state.class
    end,
  })

  function view:Show(params)
    local p1 = params and params[1]
    if p1 and R.className(p1) ~= p1 then
      state.class = p1
    end
    learnList.Refresh()
    classFrame.Refresh()
  end
  return view
end

ns.RegisterPage({
  id = "levels",
  order = 52,
  group = "character",
  title = "page.levels",
  icon = ns.ICONS.levels,
  aliases = { "levels", "stufen", "level", "stufe", "lernliste" },
  crumbLabel = function(param)
    local name = R.className(param)
    return name ~= param and name or param
  end,
  build = build,
})
