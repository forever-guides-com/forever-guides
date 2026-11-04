-- Texts of the store (GuildStore.lua): why nothing is saved right now.
local _, gm = ...
if not gm.ext then
  return
end

gm.FG.AddLocale("enUS", {
  ["gm.err.noGuild"] = "No guild: nothing is saved",
  ["gm.err.newer"] = "The saved data comes from a newer version: nothing is saved",
})
gm.FG.AddLocale("deDE", {
  ["gm.err.noGuild"] = "Keine Gilde: nichts wird gespeichert",
  ["gm.err.newer"] = "Die gespeicherten Daten stammen aus einer neueren Version: nichts wird gespeichert",
})
