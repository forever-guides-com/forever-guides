-- Forever Guides: Fishing helper. Core: the join with the main add-on and the check of the hook version.
-- The add-on has no window of its own: it adds a card to the settings of Forever Guides, a key in the key
-- bindings window and the command "/fg angeln". Every function is off until the player switches it on.
local ADDON_NAME, fish = ...

local FG = _G.ForeverGuides
local launcher = FG and FG.FishingLauncher
-- A hook version this build does not know: stay silent, the main add-on explains the state.
if not (launcher and launcher.version == 1) then
  return
end
-- Not ours to run (switched off, built for another version): register nothing.
if not (FG.SubAddons and FG.SubAddons.Join("fishing", ADDON_NAME)) then
  return
end
fish.FG, fish.name = FG, ADDON_NAME
