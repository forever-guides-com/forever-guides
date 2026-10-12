-- Top-level commands /way and /tway. They are registered at login only for names that no
-- other addon owns, so nothing registered elsewhere is ever replaced.
local _, ns = ...
local WP = ns.Waypoints

local S = {}
ns.WaypointSlash = S

local KEY = "FOREVERGUIDES_WAY"
local COMMANDS = { "/way", "/tway" }

S.status = "not checked"

-- Names of the SLASH_ entries that own `command` (without ours), from the globals
-- SLASH_NAME1 ...; plus the entry of hash_SlashCmdList when the game already knows it.
function S.SlashOwners(command)
  local owners = {}
  local wanted = command:lower()
  for key, value in pairs(_G) do
    if type(key) == "string" and type(value) == "string" and value:lower() == wanted then
      local name = key:match("^SLASH_(.+)%d+$")
      if name and name ~= KEY then
        owners[#owners + 1] = name
      end
    end
  end
  table.sort(owners)
  local hash = rawget(_G, "hash_SlashCmdList")
  local hashed = type(hash) == "table" and hash[command:upper()] or nil
  if hashed ~= nil and hashed ~= KEY and #owners == 0 then
    owners[1] = tostring(hashed)
  end
  return owners
end

-- Registers /way and /tway where they are free. Returns the list of registered names.
function S.RegisterSlash()
  local free, taken = {}, {}
  for _, command in ipairs(COMMANDS) do
    local owners = S.SlashOwners(command)
    if #owners == 0 then
      free[#free + 1] = command
    else
      taken[#taken + 1] = command .. " by " .. owners[1]
    end
  end
  if #free > 0 then
    SlashCmdList[KEY] = function(msg)
      ns.Safe("slash:way", WP.Slash, msg)
    end
    for i, command in ipairs(free) do
      rawset(_G, "SLASH_" .. KEY .. i, command)
    end
    -- The chat frame keeps its own lookup table of commands; refresh it when the game offers
    -- the function so a late registration is found.
    local refresh = rawget(_G, "ChatFrame_ImportAllListsToHash")
    if type(refresh) == "function" then
      pcall(refresh)
    end
  end
  S.status = string.format(
    "registered: %s; taken: %s",
    #free > 0 and table.concat(free, " ") or "none",
    #taken > 0 and table.concat(taken, ", ") or "none"
  )
  return free
end

function S.StatusText()
  return "/way " .. S.status
end

-- Late: other addons have registered their commands by then.
ns.On("PLAYER_LOGIN", function()
  if ns.db then
    C_Timer.After(0, function()
      ns.Safe("waypoint-slash", S.RegisterSlash)
    end)
  end
end)
