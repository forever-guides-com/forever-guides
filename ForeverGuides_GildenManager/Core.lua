-- Forever Guides: GildenManager. Core: the join with the main add-on and the check of the hook
-- version. The add-on has no window of its own, it extends the guild page of Forever Guides through
-- ForeverGuides.GuildExt. Only Actions.lua changes the guild, all data stays on this PC.
local ADDON_NAME, gm = ...

local FG = _G.ForeverGuides
local ext = FG and FG.GuildExt
-- A hook version this build does not know: stay silent, the guild page still works.
if not (ext and ext.version == 1) then
  return
end
-- Not ours to run (switched off, built for another version): register nothing.
if not (FG.SubAddons and FG.SubAddons.Join("guildmanager", ADDON_NAME)) then
  return
end
gm.FG, gm.ext, gm.name = FG, ext, ADDON_NAME
