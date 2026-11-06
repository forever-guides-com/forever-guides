-- What this client lets an add-on do to the guild, as measured by the player (/fg dev gmprobe) and kept in
-- the account preferences of the store. A value is true (works), false (blocked) or nil (not measured).
--   setNote    C_GuildInfo.SetNote
--   rankOrder  C_GuildInfo.SetGuildRankOrder (without it ranks change by promote and demote)
--   remove     C_GuildInfo.RemoveFromGuild
--   macro      the secure button with a slash command
--   direct     the plain promote, demote and invite calls
-- A measurement can only forbid ("false" stops the way) or, for rankOrder, allow a more exact call.
-- On a client that reserves the guild calls (Locked) every name answers false without any call: the
-- result of the measurement there is known and trying it again would only show the game's warning.
-- Nothing is asked from the game here.
local _, gm = ...
if not gm.ext then
  return
end

local C = {}
gm.Caps = C

C.NAMES = { "setNote", "rankOrder", "remove", "macro", "direct" }

local VALID = {}
for _, name in ipairs(C.NAMES) do
  VALID[name] = true
end

local function store(create)
  local prefs = gm.db and gm.db.prefs
  if type(prefs) ~= "table" then
    return nil
  end
  if type(prefs.caps) ~= "table" and create then
    prefs.caps = {}
  end
  return type(prefs.caps) == "table" and prefs.caps or nil
end

-- True on a client that blocks guild changes from add-on code (WoW Forever, whose project id differs
-- from the mainline one); the same rule as I.GuildCallReserved of the main add-on.
function C.Locked()
  local project, mainline = rawget(_G, "WOW_PROJECT_ID"), rawget(_G, "WOW_PROJECT_MAINLINE")
  return project ~= nil and mainline ~= nil and project ~= mainline
end

-- true, false or nil for a name that is unknown, not measured or has no store yet.
function C.Get(name)
  if VALID[name] and C.Locked() then
    return false
  end
  local caps = VALID[name] and store(false)
  local value = caps and caps[name]
  if type(value) == "boolean" then
    return value
  end
end

-- Stores a measurement: true, false, or nil to forget it. False for an unknown name or other value.
function C.Set(name, value)
  if not VALID[name] or (value ~= nil and type(value) ~= "boolean") then
    return false
  end
  local caps = store(true)
  if not caps then
    return false
  end
  caps[name] = value
  return true
end

-- The stored measurements as a copy, only known names.
function C.All()
  local out = {}
  for _, name in ipairs(C.NAMES) do
    out[name] = C.Get(name)
  end
  return out
end
