-- Card "Navigation" in the settings tab Appearance: opens the window that customizes the left menu
-- (UI/NavEditor.lua) and resets the layout of the chosen scope.
local _, ns = ...
local W, NE = ns.W, ns.NavEditor

local NS = {}
ns.NavSettings = NS

ns.AddLocale("enUS", {
  ["nav.set.heading"] = "Navigation",
  ["nav.set.intro"] = "Hide, rename, recolor or reorder the entries of the left menu. Hidden pages stay reachable through search and commands.",
})
ns.AddLocale("deDE", {
  ["nav.set.heading"] = "Navigation",
  ["nav.set.intro"] = "Einträge des linken Menüs ausblenden, umbenennen, einfärben oder neu ordnen. Ausgeblendete Seiten bleiben über Suche und Befehle erreichbar.",
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
      return NE.Scope() == "char"
    end,
    set = function(on)
      NE.SetScope(on and "char" or "account")
    end,
  })
  box.fgId = "nav-scope"
  scopeBox = box
  s:Add(box, { height = 22, gap = 8 })
  local function button(key, icon, id, onClick, opens)
    local b = W.Action(
      view.content,
      { key = key, icon = icon, tooltip = key, width = BUTTON_WIDTH, height = 28, onClick = onClick, opens = opens }
    )
    b.fgId = id
    s:Add(b, { height = 28, width = BUTTON_WIDTH, gap = 6 })
  end
  button("nav.edit.toggle", "pencil", "nav-edit", function()
    NE.Open()
  end, true)
  button("nav.reset.title", "reset", "nav-reset", function()
    NE.RequestReset()
  end)
end

-- The scope was changed in the editor window: the check box here follows.
ns.On("FG_NAV_SCOPE", function()
  if scopeBox then
    scopeBox.Refresh()
  end
end)

ns.SettingsPage.Add(NS.AddSettings, "window", "menu.main")
