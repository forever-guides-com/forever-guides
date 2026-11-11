-- Friendly player plates with the name only: the two plate settings of the game (the friendly player plates, and the
-- one that hides the health bar of friendly players) are switched on by one click of the player, the values from
-- before are kept in settings.plateNamesSaved and one click puts them back. This is the way to give the logo of the plate
-- badge a place on other players without changing the picture much: the name stays, the bar is not drawn.
-- Nothing here runs by itself: no login, no event, never in combat. Every value is read back after it was written and
-- a difference is reported with the name of the setting.
local _, ns = ...
local Store, L = ns.Store, ns.L

local PN = {}
ns.PlateNames = PN

-- The setting of the game that shows the name without the health bar for friendly players. The names differ between
-- builds, the first one the client can read is the one that is used.
PN.ONLY_NAME_CVARS = { "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames" }
PN.FRIENDLY_CVAR = "nameplateShowFriendlyPlayers"

ns.AddLocale("enUS", {
  ["platenames.state"] = "Friendly plates: %s, health bar: %s",
  ["platenames.bar.hidden"] = "hidden (name only)",
  ["platenames.bar.shown"] = "shown",
  ["platenames.bar.unknown"] = "not readable",
  ["platenames.enable"] = "Show friendly plates with the name only",
  ["platenames.enable.tip"] = "The name stays as you know it, the logo is added. The health bar of friendly players is not drawn. Changes two game settings, only on this click.",
  ["platenames.restore"] = "Restore the plate settings",
  ["platenames.restore.tip"] = "Puts both game settings back to the values from before the click.",
  ["platenames.hint"] = "Name only: friendly players get a plate with their name and the logo, without a health bar. Your previous values are kept and can be restored with the second button.",
  ["platenames.done"] = "Friendly plates now show the name only. The previous settings are kept.",
  ["platenames.restored"] = "The plate settings are back to their previous values.",
  ["platenames.combat"] = "Not possible in combat. Try again afterwards.",
  ["platenames.unavailable"] = "This game client does not offer the setting for names only. Nothing was changed.",
  ["platenames.nothing"] = "There is nothing to restore.",
  ["platenames.mismatch"] = "The game did not keep these settings: %s.",
})
ns.AddLocale("deDE", {
  ["platenames.state"] = "Freundliche Plaketten: %s, Lebensleiste: %s",
  ["platenames.bar.hidden"] = "ausgeblendet (nur Name)",
  ["platenames.bar.shown"] = "sichtbar",
  ["platenames.bar.unknown"] = "nicht lesbar",
  ["platenames.enable"] = "Freundliche Plaketten nur mit Namen anzeigen",
  ["platenames.enable.tip"] = "Der Name bleibt wie bisher, das Logo kommt dazu. Die Lebensleiste freundlicher Spieler wird nicht gezeichnet. Ändert zwei Spieleinstellungen, nur auf diesen Klick.",
  ["platenames.restore"] = "Plaketten-Einstellungen wiederherstellen",
  ["platenames.restore.tip"] = "Stellt beide Spieleinstellungen auf die Werte vor dem Klick zurück.",
  ["platenames.hint"] = "Nur Name: Freundliche Spieler bekommen eine Plakette mit Namen und Logo, ohne Lebensleiste. Deine bisherigen Werte werden gemerkt und mit dem zweiten Knopf zurückgestellt.",
  ["platenames.done"] = "Freundliche Plaketten zeigen jetzt nur den Namen. Die bisherigen Einstellungen sind gemerkt.",
  ["platenames.restored"] = "Die Plaketten-Einstellungen sind wieder auf den früheren Werten.",
  ["platenames.combat"] = "Im Kampf nicht möglich. Versuche es danach noch einmal.",
  ["platenames.unavailable"] = "Dieser Spielclient bietet die Einstellung für nur Namen nicht an. Es wurde nichts geändert.",
  ["platenames.nothing"] = "Es gibt nichts wiederherzustellen.",
  ["platenames.mismatch"] = "Das Spiel hat diese Einstellungen nicht übernommen: %s.",
})

local function g(name)
  return rawget(_G, name)
end

local function cvarFunction(kind)
  local api = g("C_CVar")
  local fn = type(api) == "table" and api[kind .. "CVar"] or g(kind .. "CVar")
  return type(fn) == "function" and fn or nil
end

-- The value of a setting as text, nil when it cannot be read.
function PN.Read(name)
  local get = cvarFunction("Get")
  if not get then
    return nil
  end
  local ok, value = pcall(get, name)
  if not ok or value == nil then
    return nil
  end
  return tostring(value)
end

local function write(name, value)
  local set = cvarFunction("Set")
  return set ~= nil and pcall(set, name, value)
end

-- Name of the "name only" setting this client can read, nil when it has none.
function PN.OnlyNameCVar()
  for _, name in ipairs(PN.ONLY_NAME_CVARS) do
    if PN.Read(name) ~= nil then
      return name
    end
  end
  return nil
end

local function isOn(value)
  return value == "1" or value == "true"
end

-- "shown", "hidden" or "unknown": the health bar of friendly player plates.
function PN.BarState()
  local name = PN.OnlyNameCVar()
  local value = name and PN.Read(name)
  if value == nil then
    return "unknown"
  end
  return isOn(value) and "hidden" or "shown"
end

-- True while values from before the click are kept.
function PN.HasSaved()
  local saved = ns.db and ns.db.settings.plateNamesSaved
  return type(saved) == "table" and saved.friendly ~= nil
end

local function inCombat()
  local fn = g("InCombatLockdown")
  return type(fn) == "function" and fn() == true
end

-- Writes the pairs { name, value } and reads each back; returns the list of names that did not keep the value.
local function setAll(pairsList)
  local wrong = {}
  for _, item in ipairs(pairsList) do
    write(item[1], item[2])
    if PN.Read(item[1]) ~= item[2] then
      wrong[#wrong + 1] = item[1]
    end
  end
  return wrong
end

-- Switches the friendly plates on and the health bar off. Returns true, or false and the reason: "combat",
-- "unavailable" (a setting is missing or cannot be read, nothing was changed) or "mismatch" and the names the game
-- did not keep.
function PN.Enable()
  if inCombat() then
    return false, "combat"
  end
  local only = PN.OnlyNameCVar()
  local friendly = PN.Read(PN.FRIENDLY_CVAR)
  if not only or friendly == nil or not cvarFunction("Set") then
    return false, "unavailable"
  end
  -- The first values are kept; a second click does not overwrite them with the values it set itself.
  if not PN.HasSaved() then
    Store.set("settings.plateNamesSaved", { friendly = friendly, only = PN.Read(only), name = only })
  end
  local wrong = setAll({ { PN.FRIENDLY_CVAR, "1" }, { only, "1" } })
  if #wrong > 0 then
    return false, "mismatch", wrong
  end
  return true
end

-- Puts the kept values back. Returns true, or false and the reason ("combat", "nothing", "mismatch" and the names).
function PN.Restore()
  if inCombat() then
    return false, "combat"
  end
  if not PN.HasSaved() then
    return false, "nothing"
  end
  local saved = ns.db.settings.plateNamesSaved
  local list = { { PN.FRIENDLY_CVAR, saved.friendly } }
  if saved.name and saved.only ~= nil then
    list[#list + 1] = { saved.name, saved.only }
  end
  local wrong = setAll(list)
  if #wrong > 0 then
    return false, "mismatch", wrong
  end
  Store.set("settings.plateNamesSaved", {})
  return true
end

-- The text for a result of Enable or Restore, and its level for ns.Notify.
function PN.Message(ok, reason, wrong, done)
  if ok then
    return L[done], "success"
  elseif reason == "mismatch" then
    return string.format(L["platenames.mismatch"], table.concat(wrong or {}, ", ")), "warning"
  end
  return L["platenames." .. tostring(reason)], "warning"
end
