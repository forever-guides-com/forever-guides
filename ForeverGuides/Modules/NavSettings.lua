-- Card "Navigation" in the settings tab Appearance: starts the edit mode of the left menu
-- (UI/SidebarEdit.lua) and resets the layout of the chosen scope.
local _, ns = ...
local W, SE = ns.W, ns.SidebarEdit

local NS = {}
ns.NavSettings = NS

ns.AddLocale("enUS", {
  ["nav.set.heading"] = "Navigation",
  ["nav.set.intro"] = "Hide, rename or reorder the entries of the left menu. Hidden pages stay reachable through search and commands.",
})
ns.AddLocale("deDE", {
  ["nav.set.heading"] = "Navigation",
  ["nav.set.intro"] = "Einträge des linken Menüs ausblenden, umbenennen oder neu ordnen. Ausgeblendete Seiten bleiben über Suche und Befehle erreichbar.",
})

local BUTTON_WIDTH = 220
local scopeBox

function NS.AddSettings(view)
  local s = view.stack
  ns.AddHeading(view, "nav.set.heading")
  ns.AddParagraph(view, "nav.set.intro", { role = "micro", color = "textMuted" })
  local box = W.Checkbox(view.content, {
    key = "nav.edit.scope",
    tooltip = "nav.edit.scope",
    tooltipText = "nav.edit.scopeHint",
    get = function()
      return SE.Scope() == "char"
    end,
    set = function(on)
      SE.SetScope(on and "char" or "account")
    end,
  })
  box.fgId = "nav-scope"
  scopeBox = box
  s:Add(box, { height = 22, gap = 8 })
  local function button(key, icon, id, onClick)
    local b = W.Action(
      view.content,
      { key = key, icon = icon, tooltip = key, width = BUTTON_WIDTH, height = 28, onClick = onClick }
    )
    b.fgId = id
    s:Add(b, { height = 28, width = BUTTON_WIDTH, gap = 6 })
  end
  button("nav.edit.toggle", "pencil", "nav-edit", SE.Enter)
  button("nav.reset.title", "reset", "nav-reset", function()
    SE.RequestReset()
  end)
end

-- The scope was changed in the edit mode: the check box here follows.
ns.On("FG_NAV_SCOPE", function()
  if scopeBox then
    scopeBox.Refresh()
  end
end)

ns.SettingsPage.Add(NS.AddSettings, "window")
