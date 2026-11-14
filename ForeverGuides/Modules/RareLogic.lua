-- Rare enemies, pure side (no frames, no client calls): the npc id of a creature GUID, the name a rare
-- goes by in the client language, the lookup of a chat sender against the rares of a map, the points a
-- map shows, the card text, item list and symbol, and the throttle of the find alert. The data is
-- Data/Rares.lua (read through ns.DataApi),
-- the events and the notice are Modules/RareDetect.lua, the pins are
-- Modules/WorldMapRarePins.lua and Modules/MinimapRareSource.lua, the hover card is Modules/RareCard.lua.
local _, ns = ...

local RL = {}
ns.RareLogic = RL

-- Seconds before the same rare raises the alert again.
RL.ALERT_INTERVAL = 300
-- Seconds between two looks at the visible nameplates.
RL.POLL_INTERVAL = 1
-- Most loot items on the card, and the seconds it stays after the mouse left pin and card.
RL.CARD_MAX_ITEMS = 12
RL.CARD_HIDE_DELAY = 0.3
-- The other spawn points of a hovered or pinned rare are drawn smaller and dimmer than its main pin.
-- Other spawn points of the open rare: big enough to tell apart on the map, drawn on a dark disc.
RL.OTHER_SCALE, RL.OTHER_ALPHA = 0.8, 1

-- Main switch (settings.rares, off by default): pins, detection and alerts only run while it is on.
function RL.Active()
  local store = ns.Store
  return store ~= nil and store.get("settings.rares") == true
end

-- Number of spawn points besides the main point of each map.
function RL.OtherCount(rare)
  local n = 0
  for _, list in pairs(type(rare) == "table" and type(rare.p) == "table" and rare.p or {}) do
    n = n + math.max(0, math.floor(#list / 2) - 1)
  end
  return n
end
-- Kills kept per account, and seconds before a dead unit that stays in view counts as a new kill.
RL.KILLS_MAX = 500
RL.KILL_WINDOW = 600
-- Pin symbols: atlases of the game's rare vignettes, and the fallback texture.
RL.ATLAS_NORMAL, RL.ATLAS_ELITE = "VignetteKill", "VignetteKillElite"
RL.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local GUID_TYPES = { Creature = true, Vehicle = true }

local function parseId(guid, types)
  if type(guid) ~= "string" then
    return nil
  end
  local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
  if not types[kind] then
    return nil
  end
  id = tonumber(id)
  return id and id > 0 and id or nil
end

-- Creature-0-server-instance-zone-npcId-spawnUID: the npc id is the sixth field. Players, pets of players
-- and objects have other types and give nil.
function RL.NpcId(guid)
  return parseId(guid, GUID_TYPES)
end

-- A vignette GUID carries the object id of its creature in the same place.
function RL.VignetteNpcId(guid)
  return parseId(guid, { Vignette = true })
end

-- The name of a rare: German on a German client when the data has it, else English.
function RL.Name(rare, locale)
  local n = type(rare) == "table" and rare.n
  if type(n) ~= "table" then
    return nil
  end
  if locale == "deDE" and n.de then
    return n.de
  end
  return n.en or n.de
end

-- Lower-case name -> npc id for the rares of a map list (DataApi.RaresForMap), both languages, so a chat
-- line matches whatever language the data was written in.
function RL.NameIndex(list)
  local index = {}
  for _, entry in ipairs(list or {}) do
    local n = entry.rare.n
    for _, name in pairs(n) do
      index[name:lower()] = entry.id
    end
  end
  return index
end

-- The npc id for the sender of a monster yell or emote, nil when it is no rare of the index.
function RL.MatchSender(index, sender)
  if type(sender) ~= "string" or sender == "" then
    return nil
  end
  return index[sender:lower()]
end

-- One pin per rare: its main point, the first x,y pair of the points of the map. x and y are fractions of
-- the map (the data is percent).
function RL.MainPins(list)
  local pins = {}
  for _, entry in ipairs(list or {}) do
    local p = entry.points
    if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
      pins[#pins + 1] = { id = entry.id, rare = entry.rare, x = p[1] / 100, y = p[2] / 100 }
    end
  end
  return pins
end

-- The other spawn points of a rare on a map (every pair after the first) as { { x, y }, ... } fractions.
function RL.OtherPoints(rare, map)
  local out = {}
  local p = type(rare) == "table" and type(rare.p) == "table" and rare.p[map]
  for i = 3, type(p) == "table" and #p - 1 or 0, 2 do
    if type(p[i]) == "number" and type(p[i + 1]) == "number" then
      out[#out + 1] = { x = p[i] / 100, y = p[i + 1] / 100 }
    end
  end
  return out
end

-- npc id -> newest time of a list of sightings { npc, t }.
function RL.SeenIndex(items)
  local index = {}
  for _, o in ipairs(items or {}) do
    if type(o) == "table" and type(o.npc) == "number" and type(o.t) == "number" then
      if not index[o.npc] or o.t > index[o.npc] then
        index[o.npc] = o.t
      end
    end
  end
  return index
end

-- The personal state of a rare: "killed" (kills[id] is a time), "seen" (seen[id] is a time) or "new".
function RL.Status(id, seen, kills)
  if kills and kills[id] then
    return "killed"
  end
  if seen and seen[id] then
    return "seen"
  end
  return "new"
end

local function prune(items)
  local count = 0
  for _ in pairs(items) do
    count = count + 1
  end
  while count > RL.KILLS_MAX do
    local oldestId, oldest
    for k, v in pairs(items) do
      if not oldest or v < oldest then
        oldestId, oldest = k, v
      end
    end
    items[oldestId] = nil
    count = count - 1
  end
end

-- Writes a kill of npc `id` at time t into items (npc id -> time). A kill within KILL_WINDOW of the last one is
-- the same corpse. The oldest entries drop beyond KILLS_MAX. Returns true when something was written.
function RL.RecordKill(items, id, t)
  local last = items[id]
  if type(id) ~= "number" or type(t) ~= "number" or (last and t >= last and t - last < RL.KILL_WINDOW) then
    return false
  end
  items[id] = t
  prune(items)
  return true
end

-- The saved kills of the account, created or repaired: wrong entries drop, the cap holds.
function RL.KillsSection(db)
  local s = db.rareKills
  if type(s) ~= "table" then
    s = {}
    db.rareKills = s
  end
  s.v = 1
  local clean = {}
  if type(s.items) == "table" then
    for id, t in pairs(s.items) do
      if type(id) == "number" and type(t) == "number" then
        clean[id] = t
      end
    end
  end
  s.items = clean
  prune(clean)
  return s
end

-- The info line of the card: "Not seen yet", else the last kill, else the last sighting. age(seconds) gives
-- the relative time text, now and the times are server seconds.
function RL.StatusLine(status, seenAt, killAt, now, age, L)
  if status == "new" then
    return L["rare.card.new"]
  end
  local key, at = "rare.card.seen", seenAt
  if status == "killed" then
    key, at = "rare.card.killed", killAt
  end
  return string.format(L[key], at and age(now - at) or "?")
end

-- Chance of a loot item as text: one decimal, a trailing ".0" dropped.
function RL.Percent(chance)
  local text = string.format("%.1f", chance)
  return (text:gsub("%.0$", ""))
end

-- Drop chance for the item tooltip: up to two decimals, no trailing zeros, the decimal comma and a space
-- before the percent sign on a German client ("0,71 %"), else "0.71%".
function RL.ChanceText(chance, locale)
  local text = string.format("%.2f", chance):gsub("0+$", ""):gsub("%.$", "")
  if locale == "deDE" then
    return text:gsub("%.", ",") .. " %"
  end
  return text .. "%"
end

-- First line of the card: level, plus the elite word for an elite. L carries rare.tip.level and
-- rare.tip.elite.
function RL.CardHead(rare, L)
  -- Unknown level reads "??" as the game shows it, never "0".
  local level = tonumber(rare.l)
  local head = level and level > 0 and string.format(L["rare.tip.level"], level)
    or (L["rare.tip.level"]:gsub("%%d", "??"))
  if rare.e then
    head = head .. ", " .. L["rare.tip.elite"]
  end
  return head
end

-- The known loot of a rare as { { id, chance }, ... } in data order, at most CARD_MAX_ITEMS. The data
-- lists flat pairs (item id, chance in percent); a pair with an unusable id is skipped, a missing chance
-- stays nil.
function RL.CardItems(rare)
  local out = {}
  local items = type(rare) == "table" and rare.i
  if type(items) ~= "table" then
    return out
  end
  for i = 1, #items, 2 do
    local id = items[i]
    if type(id) == "number" and id > 0 then
      out[#out + 1] = { id = id, chance = type(items[i + 1]) == "number" and items[i + 1] or nil }
      if #out >= RL.CARD_MAX_ITEMS then
        break
      end
    end
  end
  return out
end

-- Pin symbol: the game's rare vignette (skull on silver, with a dragon border for an elite) when the
-- client has the atlas, else the raid skull. hasAtlas(name) says whether the client knows an atlas.
-- Returns "atlas", name or "texture", path.
function RL.Icon(rare, hasAtlas)
  local name = rare and rare.e and RL.ATLAS_ELITE or RL.ATLAS_NORMAL
  if type(hasAtlas) == "function" and hasAtlas(name) == true then
    return "atlas", name
  end
  return "texture", RL.SKULL
end

-- Hover keep-alive of the card: over = the mouse is on the pin or the card. Returns hide, idleSince; the
-- card hides once the mouse has been on neither for `delay` seconds. A clock that went back restarts the wait.
function RL.CardHold(over, idleSince, now, delay)
  if over then
    return false, nil
  end
  if not idleSince or now < idleSince then
    return false, now
  end
  return now - idleSince >= delay, idleSince
end

-- The unit tokens of a nameplate list (C_NamePlate.GetNamePlates), each once. read(value) returns the value
-- or nil for one the client keeps secret; a plate without a readable token is skipped.
function RL.PlateUnits(plates, read)
  local units, seen = {}, {}
  for _, plate in ipairs(type(plates) == "table" and plates or {}) do
    local unit = type(plate) == "table" and read(plate.namePlateUnitToken) or nil
    if type(unit) == "string" and unit ~= "" and not seen[unit] then
      seen[unit] = true
      units[#units + 1] = unit
    end
  end
  return units
end

-- Throttle of the alert: Allow(id, now) is true at most once per interval for each id.
local Throttle = {}
Throttle.__index = Throttle

function RL.NewThrottle(interval)
  return setmetatable({ interval = interval or RL.ALERT_INTERVAL, last = {} }, Throttle)
end

function Throttle:Allow(id, now)
  local last = self.last[id]
  if last and now >= last and now - last < self.interval then
    return false
  end
  self.last[id] = now
  return true
end
