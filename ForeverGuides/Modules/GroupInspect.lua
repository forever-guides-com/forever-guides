-- Item level of group and raid members, read through the inspect function without any action of the
-- player (it is public information, the same data the inspect window shows). Members are tracked
-- from GROUP_ROSTER_UPDATE on: when you join a group every other member is new, later joiners come
-- one by one. One NotifyInspect at most every G.INTERVAL seconds, never in combat, never while the
-- inspect window is open or another add-on or the player inspects. A member out of reach is tried
-- again every G.RETRY seconds (G.MAX_TRIES times), then in the next sweep or roster event. The
-- result goes to Peers (source "inspect"), at most one reading per member and G.REMEASURE seconds.
-- A contact of the seen list that shows up outside the group (NearbyContacts) is queued the same way
-- through G.RequestContact: at most once per G.CONTACT_EVERY seconds and contact, only while its unit
-- is visible, and through the same gate (global interval, never in combat, never with the window open).
-- Off with settings.groupInspect. Every game call is protected, a missing function means "nothing".
local _, ns = ...
local PN, Guard = ns.PlayerName, ns.AutoGuard

local G = {}
ns.GroupInspect = G

G.INTERVAL = 2
G.RETRY = 10
G.MAX_TRIES = 6
G.SWEEP = 30
G.REMEASURE = 600
G.TIMEOUT = 8
G.FOREIGN_PAUSE = 10
G.CONTACT_EVERY = 600
G.CONTACT_TTL = 60
G.MAX_CONTACTS = 8
local BLOCK_POLL = 5
local MAX_UNITS = 40
local MAX_DEPTH = 20
-- Order classes of the queue: the leader, then friends and guild members, then everybody else.
local FIRST, RELATED, OTHER = 0, 1, 2
local ORDER_STEP = 100
local CONTACT_ORDER = 3 * ORDER_STEP

local tracked = {} -- guid -> { guid, name, order, tries, nextAt, measuredAt, contact, unit, expires }
local contactAt = {} -- guid -> clock of the last request for a contact outside the group
local current -- { entry, guid, at, ready } while a request is open
local lastAsk, lastGuid = -1e9, nil
local sweepAt = 0
local foreignAt = -1e9
local asking = false
local armedAt
local depth = 0

local function g(name)
  return rawget(_G, name)
end

-- First value of a protected call, nil when the function is missing or raises an error.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

local function clock()
  return tonumber(try(g("GetTime"))) or 0
end

-- The switch itself, and the switch together with the saving of seen players (Peers is part of it).
function G.Switch()
  return ns.db ~= nil and ns.db.settings.groupInspect ~= false
end

function G.Enabled()
  return G.Switch() and ns.SeenPlayers.Enabled()
end

-- The client has what a reading needs.
function G.Available()
  return type(g("NotifyInspect")) == "function" and type(g("CanInspect")) == "function"
end

-- Units of the other group members that exist right now: { unit, index }.
local function groupUnits()
  local members = tonumber(try(g("GetNumGroupMembers"))) or 0
  local out = {}
  if members < 2 then
    return out
  end
  local raid = try(g("IsInRaid")) == true
  local prefix, last = raid and "raid" or "party", raid and members or members - 1
  for i = 1, math.min(last, MAX_UNITS) do
    out[#out + 1] = { unit = prefix .. i, index = i }
  end
  return out
end

-- Player and guid of a unit, nil for pets, yourself and units the client does not answer for yet.
local function describe(u)
  if try(g("UnitIsPlayer"), u.unit) ~= true then
    return nil
  end
  local name = Guard.Safe(PN.Display(u.unit))
  local guid = Guard.Safe(try(g("UnitGUID"), u.unit))
  if type(name) ~= "string" or type(guid) ~= "string" or guid == "" or PN.Equal(name, PN.Self()) then
    return nil
  end
  return { guid = guid, name = name, index = u.index, unit = u.unit }
end

local function orderOf(info)
  local class = OTHER
  if try(g("UnitIsGroupLeader"), info.unit) == true then
    class = FIRST
  elseif Guard.Related(info.name, info.guid) then
    class = RELATED
  end
  return class * ORDER_STEP + info.index
end

-- Seconds since the stored reading of a player when it is still fresh, else nil.
local function freshAge(info)
  local peer = ns.Peers.Get(info.name, info.guid)
  if not (peer and peer.ilvl and peer.at) then
    return nil
  end
  local age = ns.U.now() - peer.at
  return age >= 0 and age < G.REMEASURE and age or nil
end

local function reset()
  tracked, current = {}, nil
end

-- Brings the tracked members in line with the roster: new members join the queue, members that left
-- go, an exhausted member gets a fresh set of tries.
local function sync()
  if not (G.Enabled() and G.Available()) then
    reset()
    return
  end
  local now = clock()
  local present = {}
  for _, u in ipairs(groupUnits()) do
    local info = describe(u)
    if info then
      present[info.guid] = true
      local entry = tracked[info.guid]
      if entry then
        entry.contact = nil
        if entry.tries >= G.MAX_TRIES and not entry.measuredAt then
          entry.tries, entry.nextAt = 0, now
        end
      else
        local age = freshAge(info)
        tracked[info.guid] = {
          guid = info.guid,
          name = info.name,
          order = orderOf(info),
          tries = 0,
          nextAt = age and now - age + G.REMEASURE or now,
          measuredAt = age and now - age or nil,
        }
      end
    end
  end
  -- Group entries go with the member; a contact goes once it is read, given up or too old.
  for guid, entry in pairs(tracked) do
    if entry.contact then
      if entry.measuredAt or entry.tries >= G.MAX_TRIES or now > entry.expires then
        tracked[guid] = nil
      end
    elseif not present[guid] then
      tracked[guid] = nil
    end
  end
  if current and not tracked[current.guid] then
    current = nil
  end
end

function G.OnRoster()
  sync()
  G.Pump()
end

-- The unit that carries a guid now, the roster may have shifted since the member was queued.
local function locate(guid)
  for _, u in ipairs(groupUnits()) do
    if Guard.Safe(try(g("UnitGUID"), u.unit)) == guid then
      return u.unit
    end
  end
  -- A contact outside the group: the unit of the sighting, as long as it still carries that guid.
  local entry = tracked[guid]
  local unit = entry and entry.contact and entry.unit
  if unit and Guard.Safe(try(g("UnitGUID"), unit)) == guid then
    return unit
  end
end

local function windowShown()
  local frame = g("InspectFrame")
  return type(frame) == "table" and try(frame.IsShown, frame) == true
end

local function blocked(now)
  return Guard.Blocked() or windowShown() or now - foreignAt < G.FOREIGN_PAUSE
end

-- In reach of the inspect function: allowed by the game, close enough and visible.
local function reachable(unit)
  if try(g("CanInspect"), unit) ~= true or try(g("CheckInteractDistance"), unit, 1) ~= true then
    return false
  end
  return try(g("UnitIsVisible"), unit) ~= false
end

-- Wakes the pump at an absolute time; a timer that is already due earlier stays.
local function wake(at)
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" or (armedAt and armedAt <= at) then
    return
  end
  armedAt = at
  pcall(timer.After, math.max(0.05, at - clock()), function()
    if armedAt == at then
      armedAt = nil
    end
    G.Pump()
  end)
end

-- giveUp: no more tries (a contact is asked once per G.CONTACT_EVERY, whatever the answer was).
local function miss(entry, now, giveUp)
  entry.tries = giveUp and G.MAX_TRIES or entry.tries + 1
  if entry.tries >= G.MAX_TRIES then
    entry.nextAt = math.huge
    ns.Emit("FG_SEEN_UPDATE") -- the page stops saying "reading"
  else
    entry.nextAt = now + G.RETRY
  end
end

-- Ends the open request. Clearing the inspect data is skipped when somebody else inspects now, so
-- the window of the player never loses its data.
local function finish(ok)
  local c = current
  current = nil
  if not c then
    return
  end
  if not windowShown() and clock() - foreignAt >= G.FOREIGN_PAUSE then
    try(g("ClearInspectPlayer"))
  end
  if ok then
    c.entry.measuredAt, c.entry.tries, c.entry.nextAt = clock(), 0, clock() + G.REMEASURE
  else
    miss(c.entry, clock(), c.entry.contact)
  end
end

-- Stores the item level once the request is ready and the gear is cached.
local function read()
  local c = current
  if not (c and c.ready) then
    return
  end
  local unit = locate(c.guid)
  if not unit then
    finish(false)
    G.Pump()
    return
  end
  local overlay = ns.InspectOverlay
  local ok, facts = pcall(overlay.Collect, unit)
  local average = ok and type(facts) == "table" and facts.average
  if not average then
    return -- items arrive late, GET_ITEM_INFO_RECEIVED or the timeout decides
  end
  ns.Peers.Set({ name = c.entry.name, guid = c.guid, ilvl = average, source = "inspect" })
  finish(true)
  ns.Emit("FG_SEEN_UPDATE")
  G.Pump()
end

local function ask(entry, unit, now)
  lastAsk, lastGuid = now, entry.guid
  current = { entry = entry, guid = entry.guid, at = now }
  asking = true
  local ok = pcall(g("NotifyInspect"), unit)
  asking = false
  if not ok then
    current = nil
    miss(entry, now, entry.contact)
  end
end

local function sortedEntries()
  local list = {}
  for _, entry in pairs(tracked) do
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.guid < b.guid
  end)
  return list
end

local function pump()
  if next(tracked) == nil then
    return
  end
  local now = clock()
  if current then
    if now - current.at < G.TIMEOUT then
      wake(current.at + G.TIMEOUT)
      return
    end
    finish(false)
  end
  if now >= sweepAt then
    sweepAt = now + G.SWEEP
    sync() -- members whose data was not there at the roster event, members out of reach for long
    if next(tracked) == nil then
      return
    end
  end
  if blocked(now) then
    wake(now + BLOCK_POLL)
    return
  end
  local nextWake = sweepAt
  local ready = lastAsk + G.INTERVAL
  for _, entry in ipairs(sortedEntries()) do
    if entry.nextAt > now then
      nextWake = math.min(nextWake, entry.nextAt)
    elseif now < ready then
      nextWake = math.min(nextWake, ready)
    else
      local unit = locate(entry.guid)
      if unit and reachable(unit) then
        ask(entry, unit, now)
        nextWake = math.min(nextWake, current and current.at + G.TIMEOUT or ready)
        break
      end
      miss(entry, now)
      nextWake = math.min(nextWake, entry.nextAt)
    end
  end
  wake(nextWake)
end

-- Queues a contact that is visible as `unit` (a plate or the target) outside the group. false when
-- nothing was queued: switched off, in combat, queued or read lately, a stored reading is fresh, or
-- too many contacts wait already.
function G.RequestContact(guid, name, unit)
  if not (G.Enabled() and G.Available()) or Guard.Blocked() then
    return false
  end
  if type(guid) ~= "string" or type(name) ~= "string" or type(unit) ~= "string" or tracked[guid] then
    return false
  end
  local now = clock()
  local last = contactAt[guid]
  if (last and now >= last and now - last < G.CONTACT_EVERY) or freshAge({ name = name, guid = guid }) then
    return false
  end
  local waiting = 0
  for _, entry in pairs(tracked) do
    if entry.contact then
      waiting = waiting + 1
    end
  end
  if waiting >= G.MAX_CONTACTS then
    return false
  end
  contactAt[guid] = now
  tracked[guid] = {
    guid = guid,
    name = name,
    order = CONTACT_ORDER,
    tries = 0,
    nextAt = now,
    contact = true,
    unit = unit,
    expires = now + G.CONTACT_TTL,
  }
  G.Pump()
  return true
end

function G.Pump()
  if depth >= MAX_DEPTH or not G.Enabled() or not G.Available() then
    return
  end
  depth = depth + 1
  ns.Safe("groupinspect", pump)
  depth = depth - 1
end

-- true while INSPECT_READY of this guid belongs to a request of ours, not to the inspect window.
function G.Owns(guid)
  if type(guid) ~= "string" then
    return false
  end
  return (current ~= nil and current.guid == guid) or (guid == lastGuid and clock() - lastAsk < G.TIMEOUT + G.INTERVAL)
end

-- A member that is queued or being read and has no item level yet, for the "reading" text.
function G.Loading(name)
  if not (G.Enabled() and G.Available()) then
    return false
  end
  for _, entry in pairs(tracked) do
    if not entry.measuredAt and entry.tries < G.MAX_TRIES and PN.Equal(entry.name, name) then
      return true
    end
  end
  return false
end

-- Somebody else called NotifyInspect (the window of the player, another add-on): stay out of the way.
function G.NoteForeign()
  if not asking then
    foreignAt = clock()
  end
end

if type(g("hooksecurefunc")) == "function" and type(g("NotifyInspect")) == "function" then
  pcall(g("hooksecurefunc"), "NotifyInspect", G.NoteForeign)
end

ns.On("PLAYER_LOGIN", G.OnRoster)
ns.On("PLAYER_ENTERING_WORLD", G.OnRoster)
ns.On("GROUP_ROSTER_UPDATE", G.OnRoster)
ns.On("PLAYER_REGEN_ENABLED", G.Pump)
ns.On("INSPECT_READY", function(_, guid)
  if current and Guard.Safe(guid) == current.guid then
    current.ready = true
    read()
  end
end)
ns.On("GET_ITEM_INFO_RECEIVED", read)
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path == "settings.groupInspect" then
    if value == true then
      G.OnRoster()
    else
      reset()
    end
  end
end)
