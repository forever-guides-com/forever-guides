-- Side tab at the right edge of the inspect window (InspectFrame, load on demand with
-- Blizzard_InspectUI): same look and tooltip as the tabs of the other windows (B.CreateSideTab).
-- It sits outside the window at the lower right corner, clear of the title bar, the portrait, the
-- slots and the short view (InspectPage) that hangs at the upper right; both are anchored to the
-- window itself, never to each other. The click opens the page Target() names.
local _, ns = ...

local K = {}
ns.InspectLink = K

ns.AddLocale("enUS", {
  ["inspect.tab"] = "Forever Guides: Inspect",
  ["inspect.tab.tip"] = "Opens the inspect page of the addon.",
})
ns.AddLocale("deDE", {
  ["inspect.tab"] = "Forever Guides: Betrachten",
  ["inspect.tab.tip"] = "Öffnet die Betrachten-Seite des Addons.",
})

local TAB_INSET, TAB_RISE = 4, 48 -- outside the right edge, lifted over the bottom edge
local TAB_SIZE = 52 -- as every side tab (BlizzardLinks)
local tab

K.TAB_INSET = TAB_INSET
-- Height the tab claims above the bottom edge of the window; the short view stays above it.
K.REACH = TAB_RISE + TAB_SIZE

-- Page id the tab opens.
function K.Target()
  return "inspect"
end

function K.Open()
  ns.Main.Show(K.Target())
end

-- Test seam.
function K.Tab()
  return tab
end

-- Builds the tab once the window exists; in combat it waits for PLAYER_REGEN_ENABLED.
function K.Install()
  local parent = rawget(_G, "InspectFrame")
  if tab or type(parent) ~= "table" or type(ns.BlizzardLinks) ~= "table" then
    return
  end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    return
  end
  tab = ns.BlizzardLinks.CreateSideTab(parent, {
    key = "inspect.tab",
    tip = "inspect.tab.tip",
    onClick = K.Open,
    point = "BOTTOMLEFT",
    rel = parent,
    relPoint = "BOTTOMRIGHT",
    x = TAB_INSET,
    y = TAB_RISE,
  })
end

ns.On("PLAYER_LOGIN", K.Install)
ns.On("ADDON_LOADED", K.Install)
ns.On("PLAYER_REGEN_ENABLED", K.Install)
