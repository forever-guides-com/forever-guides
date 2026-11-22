-- One-time question after the update that made the sidebar groups start collapsed: an existing install keeps
-- its open groups (Store.migrateNavCollapse) and is asked once whether to keep them or collapse all.
local _, ns = ...

ns.AddLocale("enUS", {
  ["nav.collapse.title"] = "Menu view",
  ["nav.collapse.text"] = "Fresh installs now start with the menu collapsed, only the overview stays open. Keep your menu as it is, or collapse all sections? Afterwards the addon always remembers what you open and close yourself.",
  ["nav.collapse.keep"] = "Keep as is",
  ["nav.collapse.all"] = "Collapse all",
})
ns.AddLocale("deDE", {
  ["nav.collapse.title"] = "Menü-Ansicht",
  ["nav.collapse.text"] = "Neu installiert ist das Menü ab jetzt zugeklappt, nur die Übersicht ist offen. Willst du dein Menü so lassen, wie es gerade ist, oder alle Bereiche zuklappen? Danach merkt sich das Addon immer, was du selbst auf- und zuklappst.",
  ["nav.collapse.keep"] = "So lassen",
  ["nav.collapse.all"] = "Alle zuklappen",
})

local NC = {}
ns.NavCollapse = NC

function NC.CollapseAll()
  for _, group in ipairs(ns.Sidebar.GROUPS) do
    if group ~= "main" then
      ns.Store.set("settings.sidebarOpen." .. group, false)
    end
  end
  local sb = ns.Anchors["FG.Sidebar"]
  if sb and sb.Layout then
    sb:Layout(sb.collapsed)
  end
end

-- Another window on top of the main window (setup, news, tour, any open confirmation such as the tour offer, which
-- shares this dialog): the question waits for the next opening. Loaded after UI/Tutorial.lua so the offer is
-- already up when this runs.
local function busy()
  local dialog = rawget(_G, "ForeverGuidesConfirmDialog")
  if dialog and dialog:IsShown() then
    return true
  end
  local wizard, tour, news = ns.SetupWizardUI, ns.TutorialUI, ns.ChangelogNews
  local newsFrame = news and news.Frame and news.Frame()
  return (wizard and wizard.IsOpen() or (tour and tour.IsActive()) or (newsFrame and newsFrame:IsShown())) and true
    or false
end

-- The flag is cleared as the question appears: Esc or a click elsewhere counts as "keep", so it never returns.
function NC.Offer()
  if not ns.db.settings.navCollapsePrompt or busy() then
    return
  end
  ns.db.settings.navCollapsePrompt = nil
  ns.Dialogs.Confirm("nav.collapse.title", "nav.collapse.text", function() end, NC.CollapseAll, {
    yesKey = "nav.collapse.keep",
    noKey = "nav.collapse.all",
  })
end

ns.On("FG_MAIN_SHOWN", NC.Offer)
