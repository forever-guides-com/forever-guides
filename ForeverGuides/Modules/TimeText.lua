-- Weekday names and time stamps in the addon language. The client's date("%a") follows the
-- client locale only loosely (often English), so the names come from the locale table.
local _, ns = ...
local L = ns.L

ns.AddLocale("enUS", {
  ["time.day.1"] = "Sun",
  ["time.day.2"] = "Mon",
  ["time.day.3"] = "Tue",
  ["time.day.4"] = "Wed",
  ["time.day.5"] = "Thu",
  ["time.day.6"] = "Fri",
  ["time.day.7"] = "Sat",
})

ns.AddLocale("deDE", {
  ["time.day.1"] = "So",
  ["time.day.2"] = "Mo",
  ["time.day.3"] = "Di",
  ["time.day.4"] = "Mi",
  ["time.day.5"] = "Do",
  ["time.day.6"] = "Fr",
  ["time.day.7"] = "Sa",
})

local TT = {}
ns.TimeText = TT

-- Short weekday of `wday` (1 = Sunday, as in date("*t").wday), "?" for anything else.
function TT.DayName(wday)
  if type(wday) ~= "number" or wday < 1 or wday > 7 or wday % 1 ~= 0 then
    return "?"
  end
  return L["time.day." .. wday]
end

-- Short weekday of the local date of `t` (seconds), "?" when `t` is no valid time.
function TT.Weekday(t)
  local ok, parts = pcall(date, "*t", t)
  return ok and type(parts) == "table" and TT.DayName(parts.wday) or "?"
end

-- "Mon 07:30": localized weekday and 24 hour time of `t`.
function TT.Stamp(t)
  local ok, clock = pcall(date, "%H:%M", t)
  if not ok then
    return "?"
  end
  return TT.Weekday(t) .. " " .. clock
end
