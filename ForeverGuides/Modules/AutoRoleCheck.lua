-- Auto role check (settings.autoRoleCheck, off by default). Two role questions of the game:
-- * Dungeon finder role check (LFG_ROLE_CHECK_SHOW): confirmed with the roles saved in the dungeon
--   finder (GetLFGRoles), only when at least one role is saved.
-- * Group role poll (ROLE_POLL_BEGIN): the saved or current role is set and the popup closes, only
--   when that role is unambiguous and the character can take it.
-- Never in combat, the override key stops it. A client without the events or functions is left
-- alone: nothing happens and nothing is reported.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local R = {}
ns.AutoRoleCheck = R

ns.AddLocale("enUS", {
  ["auto.role.TANK"] = "Tank",
  ["auto.role.HEALER"] = "Healer",
  ["auto.role.DAMAGER"] = "Damage",
  ["auto.role.confirmed"] = "Role check confirmed: %s (%s stops it)",
  ["auto.role.none"] = "No role saved",
  ["auto.role.set"] = "Role set to %s (%s stops it)",
})
ns.AddLocale("deDE", {
  ["auto.role.TANK"] = "Tank",
  ["auto.role.HEALER"] = "Heiler",
  ["auto.role.DAMAGER"] = "Schaden",
  ["auto.role.confirmed"] = "Rollenabfrage bestätigt: %s (%s hält an)",
  ["auto.role.none"] = "Keine Rolle gespeichert",
  ["auto.role.set"] = "Rolle auf %s gesetzt (%s hält an)",
})

local ID = "autoRoleCheck"
-- Blizzard's own handler may show the popup after ours ran, so it is closed once more shortly after.
local POPUP_RETRY = 0.2
R.ROLES = { "TANK", "HEALER", "DAMAGER" }

local IS_ROLE = {}
for _, role in ipairs(R.ROLES) do
  IS_ROLE[role] = true
end

-- true, false or nil for a game value that is a boolean and readable.
local function flag(value)
  value = Guard.Safe(value)
  return type(value) == "boolean" and value or nil
end

-- Roles saved in the dungeon finder as a set and their number, nil when the game cannot tell.
function R.Saved()
  local found, _, tank, healer, damage = Guard.Call("GetLFGRoles")
  if not found then
    return nil
  end
  local set, count = {}, 0
  for role, on in pairs({ TANK = flag(tank), HEALER = flag(healer), DAMAGER = flag(damage) }) do
    if on then
      set[role], count = true, count + 1
    end
  end
  return set, count
end

-- Roles the character can take as a set, nil when the game cannot tell.
local function available()
  local found, tank, healer, damage = Guard.Call("UnitGetAvailableRoles", "player")
  if not found then
    return nil
  end
  return { TANK = flag(tank), HEALER = flag(healer), DAMAGER = flag(damage) }
end

-- The role the character has in the group right now, nil for none.
local function current()
  local found, role = Guard.Call("UnitGroupRolesAssigned", "player")
  role = found and Guard.Safe(role) or nil
  return IS_ROLE[role or ""] and role or nil
end

-- The one role to answer a group poll with, nil when it is not clear.
function R.Pick()
  local can = available()
  if not can then
    return nil
  end
  local set, count = R.Saved()
  local now = current()
  if not set or count == 0 then
    return now and can[now] and now or nil
  end
  local usable = {}
  for _, role in ipairs(R.ROLES) do
    if set[role] and can[role] then
      usable[#usable + 1] = role
    end
  end
  if #usable == 1 then
    return usable[1]
  end
  -- Several saved roles: the one the character has now settles it, else the player decides.
  for _, role in ipairs(usable) do
    if role == now then
      return role
    end
  end
  return nil
end

local function closePopup()
  local popup = rawget(_G, "RolePollPopup")
  if type(popup) ~= "table" then
    return
  end
  if Guard.Has("StaticPopupSpecial_Hide") then
    Guard.Call("StaticPopupSpecial_Hide", popup)
  elseif type(popup.Hide) == "function" then
    pcall(popup.Hide, popup)
  end
end

function R.OnLfgRoleCheck()
  if Guard.Paused() or not Guard.Has("CompleteLFGRoleCheck") then
    return
  end
  local set, count = R.Saved()
  if not set then
    return
  end
  if count == 0 then
    Guard.Say(ID, L["auto.role.none"])
    return
  end
  Guard.Call("CompleteLFGRoleCheck", true)
  local names = {}
  for _, role in ipairs(R.ROLES) do
    if set[role] then
      names[#names + 1] = L["auto.role." .. role]
    end
  end
  Guard.Say(ID, string.format(L["auto.role.confirmed"], table.concat(names, ", "), Guard.KeyName()))
end

function R.OnRolePoll()
  -- UnitSetRole is a restricted function: it raises ADDON_ACTION_FORBIDDEN while the client restricts addons.
  if
    Guard.Paused()
    or ns.AddonRestricted("Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map")
    or not Guard.Has("UnitSetRole")
  then
    return
  end
  local role = R.Pick()
  if not role then
    return
  end
  Guard.Call("UnitSetRole", "player", role)
  closePopup()
  Guard.After(ID, POPUP_RETRY, function()
    if not Guard.Paused() then
      closePopup()
    end
  end)
  Guard.Say(ID, string.format(L["auto.role.set"], L["auto.role." .. role], Guard.KeyName()))
end

ns.On("LFG_ROLE_CHECK_SHOW", function()
  Guard.Run(ID, R.OnLfgRoleCheck)
end)

ns.On("ROLE_POLL_BEGIN", function()
  Guard.Run(ID, R.OnRolePoll)
end)
