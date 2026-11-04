-- Texts of the tab "Inactive" (Inactivity.lua).
local _, gm = ...
if not gm.ext then
  return
end

gm.FG.AddLocale("enUS", {
  ["gm.tab.inactive"] = "Inactive",
  ["gm.inactive.days"] = "Offline for at least",
  ["gm.inactive.daysValue"] = "%d days",
  ["gm.inactive.count"] = "Inactive: %d of %d",
  ["gm.inactive.empty"] = "Nobody is offline that long.",
})
gm.FG.AddLocale("deDE", {
  ["gm.tab.inactive"] = "Inaktiv",
  ["gm.inactive.days"] = "Offline seit mindestens",
  ["gm.inactive.daysValue"] = "%d Tage",
  ["gm.inactive.count"] = "Inaktiv: %d von %d",
  ["gm.inactive.empty"] = "Niemand ist so lange offline.",
})
