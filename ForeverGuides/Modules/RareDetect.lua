-- Finds rare enemies (Data/Rares.lua) while the player plays and raises an alert. Sources: the creature GUID
-- of a nameplate, the mouseover and the target (the npc id is a field of it, see RareLogic.lua), the sender of
-- a monster yell or emote matched against the rares of the current map, the vignettes of the client where it
-- has them, and a once-a-second look at the visible nameplates outside of instances for a plate event that did
-- not arrive. A dead rare is skipped when a unit tells, the same rare alerts once per RareLogic.ALERT_INTERVAL.
-- The alert is the find window (Modules/RareFound.lua), a line in the screen center and one in chat, or the
-- short toast when the window is off. Every alert is remembered as a sighting (Modules/RareFoundLogic.lua).
-- Every client call is checked, an API the client lacks is skipped.
--
-- Hook for diagnostics: RD.OnAttempt = function(source, npcId, result) is called for every attempt on a known
-- rare (result "alerted", "throttled", "dead" or "off") and for a unit without a readable GUID (npcId nil,
-- result "unreadable"). Nothing runs while it is nil.
local _, ns = ...
local L, RL, RFL = ns.L, ns.RareLogic, ns.RareFoundLogic

local RD = {}
ns.RareDetect = RD

ns.AddLocale("enUS", {
  ["rare.alert"] = "Rare enemy found: %s",
  ["rare.center"] = "%s found!",
  ["rare.tip.level"] = "Level %d",
  ["rare.tip.elite"] = "Elite",
  ["rare.tip.loot"] = "Loot",
  ["rare.set.heading"] = "Rare enemies",
  ["rare.set.enabled"] = "Rare enemy scanner",
  ["rare.set.enabledTip"] = "Main switch: symbols on the maps, recognition nearby and the alerts. The settings below control the single parts.",
  ["rare.set.map"] = "Rare enemies on the world map",
  ["rare.set.minimap"] = "Rare enemies on the minimap",
  ["rare.set.alert"] = "Alert when a rare enemy is found",
  ["rare.set.alertTip"] = "Shows a short message with the name when you see a known rare enemy, at most once every 5 minutes for the same one.",
  ["rare.set.sound"] = "Sound with the rare alert",
  ["rare.set.window"] = "Find window with model and loot",
  ["rare.set.windowTip"] = "Shows the creature, its loot and a click to target. Drag with {mod:rareFoundMove} to move the window.",
  ["rare.set.windowReset"] = "Reset the position of the find window",
  ["rare.set.center"] = "Big message in the screen center",
  ["rare.set.chat"] = "Message in chat",
  ["rare.set.mode"] = "Show rare enemies",
  ["rare.set.mode.map"] = "On the maps with alert",
  ["rare.set.mode.alert"] = "Only the alert in the screen center",
  ["rare.set.mode.off"] = "Off",
  ["rare.set.modeHint"] = "On the maps: symbols on the world map and the minimap, plus an alert when one is near. Only the alert: no symbols, only the message in the screen center.",
})
ns.AddLocale("deDE", {
  ["rare.alert"] = "Seltener Gegner gefunden: %s",
  ["rare.center"] = "%s gefunden!",
  ["rare.tip.level"] = "Stufe %d",
  ["rare.tip.elite"] = "Elite",
  ["rare.tip.loot"] = "Beute",
  ["rare.set.heading"] = "Seltene Gegner",
  ["rare.set.enabled"] = "Scanner für seltene Gegner",
  ["rare.set.enabledTip"] = "Hauptschalter: Symbole auf den Karten, Erkennung in der Nähe und die Hinweise. Die Einstellungen darunter steuern die einzelnen Teile.",
  ["rare.set.map"] = "Seltene Gegner auf der Weltkarte",
  ["rare.set.minimap"] = "Seltene Gegner auf der Minikarte",
  ["rare.set.alert"] = "Hinweis, wenn ein seltener Gegner gefunden wird",
  ["rare.set.alertTip"] = "Zeigt eine kurze Meldung mit dem Namen, wenn du einen bekannten seltenen Gegner siehst, für denselben höchstens alle 5 Minuten.",
  ["rare.set.sound"] = "Ton beim Hinweis auf seltene Gegner",
  ["rare.set.window"] = "Fundfenster mit Modell und Beute",
  ["rare.set.windowTip"] = "Zeigt die Kreatur, ihre Beute und einen Klick zum Anvisieren. Ziehen mit {mod:rareFoundMove} verschiebt das Fenster.",
  ["rare.set.windowReset"] = "Position des Fundfensters zurücksetzen",
  ["rare.set.center"] = "Große Meldung in der Bildschirmmitte",
  ["rare.set.chat"] = "Meldung im Chat",
  ["rare.set.mode"] = "Seltene Gegner anzeigen",
  ["rare.set.mode.map"] = "Auf den Karten mit Hinweis",
  ["rare.set.mode.alert"] = "Nur Hinweis in der Bildschirmmitte",
  ["rare.set.mode.off"] = "Aus",
  ["rare.set.modeHint"] = "Auf den Karten: Symbole auf Weltkarte und Minikarte, dazu ein Hinweis, wenn einer in der Nähe ist. Nur Hinweis: keine Symbole, nur die Meldung in der Bildschirmmitte.",
})

-- Sound kit names tried in order, the first one the client has plays.
local SOUNDS = { "RAID_WARNING", "UI_MAP_WAYPOINT_SUPER_TRACK_ON" }

local throttle = RL.NewThrottle()
local nameIndex, indexMap, indexLocale
local ticker

local function on(key)
  return RL.Active() and ns.Store.get("settings." .. key) ~= false
end

local function global(name)
  return rawget(_G, name)
end

-- Secret values are never compared.
local function readable(value)
  local secret = global("issecretvalue")
  if type(secret) == "function" and secret(value) then
    return nil
  end
  return value
end

local function ask(name, ...)
  local fn = global(name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return readable(value)
  end
end

local function locale()
  return ns.GetActiveLocale()
end

local function now()
  return ask("GetTime") or 0
end

function RD.MapId()
  local api = global("C_Map")
  local fn = type(api) == "table" and api.GetBestMapForUnit
  if type(fn) ~= "function" then
    return nil
  end
  local ok, id = pcall(fn, "player")
  id = ok and readable(id) or nil
  return type(id) == "number" and id or nil
end

local function playSound()
  local play, kit = global("PlaySound"), global("SOUNDKIT")
  if type(play) ~= "function" or type(kit) ~= "table" then
    return
  end
  for _, name in ipairs(SOUNDS) do
    if kit[name] then
      pcall(play, kit[name])
      return
    end
  end
end

local function attempt(source, id, result)
  local hook = RD.OnAttempt
  if hook then
    pcall(hook, source, id, result)
  end
end

-- Big line in the middle of the screen, in the raid warning style of the game.
local function centerText(text)
  local add, frame = global("RaidNotice_AddMessage"), global("RaidWarningFrame")
  if type(add) ~= "function" or type(frame) ~= "table" then
    return
  end
  local info = global("ChatTypeInfo")
  info = type(info) == "table" and info.RAID_WARNING or { r = 1, g = 0.82, b = 0 }
  pcall(add, frame, text, info)
end

-- Where the player stands as percent of the map, nil without a readable position.
local function playerPosition(map)
  local api = global("C_Map")
  local fn = type(api) == "table" and api.GetPlayerMapPosition
  if type(fn) ~= "function" then
    return nil
  end
  local ok, point = pcall(fn, map, "player")
  if not (ok and type(point) == "table" and type(point.GetXY) == "function") then
    return nil
  end
  local okXY, x, y = pcall(point.GetXY, point)
  x, y = readable(x), readable(y)
  if okXY and type(x) == "number" and type(y) == "number" then
    return RFL.Percent(x), RFL.Percent(y)
  end
end

local function remember(id)
  local map = RD.MapId()
  if not (ns.db and map) then
    return
  end
  local x, y = playerPosition(map)
  local t = ask("GetServerTime") or ns.U.now()
  if RFL.AddSighting(RFL.Section(ns.db).items, { npc = id, map = map, x = x, y = y, t = t }) then
    ns.Emit("FG_RARE_STATUS", id)
  end
end

-- A known rare died: remembered per account, the pins and the card take the new state from the message.
function RD.Kill(id)
  if not (ns.db and ns.DataApi.Rare(id)) then
    return
  end
  local t = ask("GetServerTime") or ns.U.now()
  if RL.RecordKill(RL.KillsSection(ns.db).items, id, t) then
    ns.Emit("FG_RARE_STATUS", id)
  end
end

-- The loot window: a source that is the creature of a known rare counts as its kill (no combat log needed).
function RD.OnLoot()
  local slots = ask("GetNumLootItems")
  for slot = 1, type(slots) == "number" and math.min(slots, 40) or 0 do
    local fn = global("GetLootSourceInfo")
    local ok, res = pcall(function()
      return { fn(slot) }
    end)
    for i = 1, ok and type(fn) == "function" and #res or 0, 2 do
      local id = RL.NpcId(readable(res[i]))
      if id then
        RD.Kill(id)
      end
    end
  end
end

local function announce(id, rare, unit)
  local name = RL.Name(rare, locale()) or tostring(id)
  if on("rareWindow") and ns.RareFound then
    ns.RareFound.Show(id, rare, unit and ask("UnitName", unit) or nil)
  else
    ns.Notify(string.format(L["rare.alert"], name), "info", { force = true })
  end
  if on("rareChat") then
    ns.Notify.chat(string.format(L["rare.alert"], name))
  end
  if on("rareCenterText") then
    centerText(string.format(L["rare.center"], name))
  end
  if on("rareSound") then
    playSound()
  end
  remember(id)
end

-- A rare was seen: npc id, optionally the unit it was read from, and the source for the diagnostics. Returns
-- true when the alert was raised.
function RD.Found(id, unit, source)
  local rare = ns.DataApi.Rare(id)
  if not rare then
    return false
  end
  if unit and ask("UnitIsDead", unit) == true then
    RD.Kill(id)
  end
  local result = "alerted"
  if not on("rareAlert") then
    result = "off"
  elseif unit and ask("UnitIsDead", unit) == true then
    result = "dead"
  elseif not throttle:Allow(id, now()) then
    result = "throttled"
  end
  attempt(source or "unknown", id, result)
  if result ~= "alerted" then
    return false
  end
  announce(id, rare, unit)
  return true
end

-- The creature of a unit. A player controlled unit is skipped; a GUID the client keeps secret or does not
-- give is only reported to the diagnostics.
local function onUnit(unit, source)
  if type(unit) ~= "string" or ask("UnitPlayerControlled", unit) == true then
    return
  end
  local guid = ask("UnitGUID", unit)
  local id = RL.NpcId(guid)
  if id then
    RD.Found(id, unit, source)
  elseif RD.OnAttempt and guid == nil then
    attempt(source, nil, "unreadable")
  end
end

-- The visible plates outside of instances: the plate event can be missed (a plate that was up before the
-- add-on looked). The throttle keeps it at one alert per rare.
function RD.Poll()
  if not on("rareAlert") or ask("IsInInstance") == true then
    return
  end
  local api = global("C_NamePlate")
  local list = type(api) == "table" and api.GetNamePlates
  if type(list) ~= "function" then
    return
  end
  local ok, plates = pcall(list)
  for _, unit in ipairs(RL.PlateUnits(ok and plates or nil, readable)) do
    onUnit(unit, "plate-poll")
  end
end

-- The ticker runs only while the alert is on.
function RD.SyncPoll()
  local api = global("C_Timer")
  if not (type(api) == "table" and type(api.NewTicker) == "function") then
    return
  end
  if on("rareAlert") and not ticker then
    ticker = api.NewTicker(RL.POLL_INTERVAL, function()
      ns.Safe("rare-poll", RD.Poll)
    end)
  elseif not on("rareAlert") and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

function RD.PollRunning()
  return ticker ~= nil
end

-- The names of the rares of the current map, rebuilt when the map or the language changes.
local function index()
  local map, lang = RD.MapId(), locale()
  if map ~= indexMap or lang ~= indexLocale then
    indexMap, indexLocale = map, lang
    nameIndex = map and RL.NameIndex(ns.DataApi.RaresForMap(map)) or {}
  end
  return nameIndex
end

local function onChat(source)
  return function(_, _, sender)
    local id = RL.MatchSender(index(), readable(sender))
    if id then
      RD.Found(id, nil, source)
    end
  end
end

-- Vignettes: the info carries the GUID of the creature, the GUID of the vignette itself is the fallback.
local function onVignette(guid)
  local api = global("C_VignetteInfo")
  local fn = type(api) == "table" and api.GetVignetteInfo
  if type(fn) ~= "function" or type(guid) ~= "string" then
    return
  end
  local ok, info = pcall(fn, guid)
  if not ok or type(info) ~= "table" or info.isDead == true then
    return
  end
  local id = RL.NpcId(info.objectGUID) or RL.VignetteNpcId(guid)
  if id then
    RD.Found(id, nil, "vignette")
  end
end

local function onVignettes()
  local api = global("C_VignetteInfo")
  local fn = type(api) == "table" and api.GetVignettes
  if type(fn) ~= "function" then
    return
  end
  local ok, list = pcall(fn)
  RD.lastVignettes = ok and type(list) == "table" and #list or nil
  for _, guid in ipairs(ok and type(list) == "table" and list or {}) do
    onVignette(guid)
  end
end

function RD.Reset()
  throttle = RL.NewThrottle()
  nameIndex, indexMap, indexLocale = nil, nil, nil
end

-- With the scanner off (settings.rares) no event asks the game anything: no unit, no loot, no vignette.
local function live(fn)
  return function(...)
    if RL.Active() then
      return fn(...)
    end
  end
end

ns.On("NAME_PLATE_UNIT_ADDED", live(function(_, unit)
  onUnit(unit, "plate")
end))
ns.On("UPDATE_MOUSEOVER_UNIT", live(function()
  onUnit("mouseover", "mouseover")
end))
ns.On("PLAYER_TARGET_CHANGED", live(function()
  onUnit("target", "target")
end))
ns.On("LOOT_OPENED", live(function()
  ns.Safe("rare-loot", RD.OnLoot)
end))
ns.On("CHAT_MSG_MONSTER_YELL", live(onChat("yell")))
ns.On("CHAT_MSG_MONSTER_EMOTE", live(onChat("emote")))
ns.On("VIGNETTES_UPDATED", live(onVignettes))
ns.On("VIGNETTE_MINIMAP_UPDATED", live(function(_, guid)
  onVignette(guid)
end))
ns.On("PLAYER_LOGIN", RD.SyncPoll)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.rareAlert" or path == "settings.rares" then
    RD.SyncPoll()
  end
  if path == "settings.rares" and not RL.Active() and ns.RareFound then
    ns.RareFound.Close()
  end
end)
