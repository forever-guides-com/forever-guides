-- Tour definitions. Bump `version` when the UI a tour points at changes,
-- so players who saw an older version get it offered again.
local _, ns = ...

ns.Tutorials.register({
  id = "addon-start",
  version = 1,
  title = "tour.addon-start.title",
  steps = {
    { id = "welcome" },
    { id = "sidebar", target = "FG.Sidebar" },
    { id = "search", target = "FG.Search" },
    { id = "data", target = "FG.Footer.Data", optional = true },
    { id = "help", target = "FG.Help" },
    { id = "resize", target = "FG.Resize" },
    { id = "title", target = "FG.Title" },
  },
})

local function pageTour(id, steps, version)
  ns.Tutorials.register({ id = id, page = id, version = version or 1, title = "tour." .. id .. ".title", steps = steps })
end

pageTour("map", {
  { id = "intro" },
  { id = "filters", target = "FG.Map.Filters" },
  { id = "places", target = "FG.Map.Places" },
  { id = "route", target = "FG.Map.Route" },
  { id = "canvas", target = "FG.Map.Canvas" },
})
pageTour("classes", {
  { id = "intro" },
  { id = "tabs", target = "FG.Classes.Tabs" },
  { id = "content", target = "FG.Classes.Content", optional = true },
})
pageTour("trainers", {
  { id = "intro" },
  { id = "filters", target = "FG.Trainers.Filters" },
  { id = "list", target = "FG.Trainers.List", optional = true },
  { id = "levels", target = "FG.Trainers.LevelsLink" },
}, 2)
pageTour("weapons", {
  { id = "intro" },
  { id = "filters", target = "FG.Weapons.Filters" },
  { id = "list", target = "FG.Weapons.List", optional = true },
})
pageTour("levels", {
  { id = "intro" },
  { id = "filters", target = "FG.Levels.Filters" },
  { id = "list", target = "FG.Levels.List", optional = true },
})
pageTour("instances", {
  { id = "intro" },
  { id = "filters", target = "FG.Instances.Filters" },
  { id = "list", target = "FG.Instances.List" },
  { id = "detail", target = "FG.Instances.Detail", optional = true },
})
pageTour("search", {
  { id = "intro" },
  { id = "box", target = "FG.Search" },
  { id = "results", target = "FG.Search.Results" },
})
pageTour("help", {
  { id = "intro" },
  { id = "feedback", target = "FG.Help.Tabs", optional = true },
})
