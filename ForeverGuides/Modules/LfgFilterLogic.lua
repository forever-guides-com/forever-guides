-- The CVar behind "show all dungeons" in the group finder (pure logic, no game calls and no UI;
-- Modules/LfgFilter.lua connects it). The game hides activities outside the level range of the player unless
-- the variable is "1". The variable is the only source of truth: nothing here is stored by the addon.
local _, ns = ...

local LL = {}
ns.LfgFilterLogic = LL

LL.CVAR = "disableSuggestedLevelActivityFilter"
-- The default of the game: the filter is active, so only the activities of the level range show.
LL.DEFAULT = "0"

-- "on" (all dungeons show), "off" (level filter active) or "unknown" for a missing or foreign value.
function LL.State(raw)
  if raw == "1" then
    return "on"
  end
  if raw == "0" then
    return "off"
  end
  return "unknown"
end

-- The text a switch writes: on shows everything ("1"), off is the default of the game.
function LL.Target(on)
  return on and "1" or LL.DEFAULT
end

-- True when the name of a CVAR_UPDATE event is this variable (the game compares names without case).
function LL.IsCVar(name)
  return type(name) == "string" and name:lower() == LL.CVAR:lower()
end

-- Whether the variable may be written now. facts = { combat, canSet }. Returns true, or false and the locale key
-- of the reason.
function LL.CanWrite(facts)
  if not facts.canSet then
    return false, "lfg.blocked.api"
  end
  if facts.combat then
    return false, "lfg.blocked.combat"
  end
  return true
end

-- The write counts when the value read back is the one asked for.
function LL.Confirmed(wanted, readBack)
  return readBack ~= nil and tostring(readBack) == wanted
end

-- The value for /fg diag: the raw text, "?" when the client gave none.
function LL.DiagValue(raw)
  if raw == nil then
    return "?"
  end
  return tostring(raw)
end
