-- Fishing helper, the page "Fishing" of the main window: the catch journal inside the page, built from the
-- same view as the floating window (JournalView.lua). The page exists while this add-on runs, so it is
-- registered here and the menu is rebuilt for the entry.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG

local PAGE_H = 520

FG.AddLocale("enUS", {
  ["page.fishing"] = "Fishing",
  ["page.fishing.sub"] = "Your catches and where you made them",
  ["fishj.page.intro"] = "The catch journal lists every fish you caught with its count and places, and every place with the fish from there. Recording is switched on under Settings > Fishing.",
})
FG.AddLocale("deDE", {
  ["page.fishing"] = "Angeln",
  ["page.fishing.sub"] = "Deine Fänge und wo du sie gemacht hast",
  ["fishj.page.intro"] = "Das Fangjournal listet jeden gefangenen Fisch mit Anzahl und Fundorten und jeden Fundort mit den Fischen von dort. Das Aufzeichnen schaltest du unter Einstellungen > Angeln ein.",
})

FG.RegisterPage({
  id = "fishing",
  order = 445,
  group = "professions",
  title = "page.fishing",
  subtitle = "page.fishing.sub",
  icon = FG.ICONS.fishing,
  aliases = { "angeln", "fishing", "fang", "fänge", "faenge", "fangjournal", "fischen", "catches" },
  build = function(container)
    local view = FG.NewPageView(container)
    FG.AddIntro(view, "fishj.page.intro")
    local host = CreateFrame("Frame", nil, view.content)
    view.stack:Add(host, { height = PAGE_H })
    fish.JournalView.Embed(host)
    return view
  end,
})

FG.Commands.PAGE_AREA.fishing = "professions"

-- A menu that is already built does not know the page yet.
FG.Emit("FG_NAV_CHANGED")
