-- Computed aura timer without WoW API (ns.AuraTrack): in combat the game keeps aura fields secret, so the aura
-- element can count the time itself. A cast of the trigger spell starts a timer (now plus a known duration), an aura
-- that was readable before the fight is carried on from its end time, death and a removal the game names end it, and
-- readable values outside combat correct it. Every number here is the add-on's own, never a secret one, so ring,
-- text and threshold can use it freely. This file holds the state machine, the choice of the duration, the repair of
-- the track props and the learned durations (ns.db.auraDurations, repaired and capped here).
local _, ns = ...

local T = {}
ns.AuraTrack = T

-- auto: the native container in combat when the client has it, else read the aura out of combat and count it in
-- combat. native: the same choice made by hand (without the container the element counts as in auto). cast: only
-- the cast events start and end the timer. live: only read (no tracking). The order is the one of the panel.
T.MODES = { "auto", "native", "cast", "live" }
T.MARKS = { "none", "dot" }
T.SOURCES = { "manual", "learned", "base" }
T.DEFAULTS = { trackMode = "auto", trackSpell = 0, trackDuration = 0, trackStacks = false, trackMark = "none" }
T.SPELL_ID_MAX = 4000000
T.DURATION_MAX = 86400
T.STACK_MAX = 99
-- Two signals for one cast (the cast event and the cooldown change) count once within this many seconds.
T.DEDUPE = 0.5
T.MAX_ENTRIES = 200
T.STORE_VERSION = 1

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function clampInt(v, hi, default)
  if not finite(v) then
    return default
  end
  return math.min(math.max(math.floor(v + 0.5), 0), hi)
end

-- Props ---------------------------------------------------------------------------------------------------

-- The track props of a saved element, repaired.
function T.Clean(raw, d)
  return {
    trackMode = oneOf(raw.trackMode, T.MODES, d.trackMode),
    trackMark = oneOf(raw.trackMark, T.MARKS, d.trackMark),
    trackStacks = type(raw.trackStacks) == "boolean" and raw.trackStacks or d.trackStacks,
    trackSpell = clampInt(raw.trackSpell, T.SPELL_ID_MAX, d.trackSpell),
    trackDuration = clampInt(raw.trackDuration, T.DURATION_MAX, d.trackDuration),
  }
end

-- Whether the element counts at all: only the player's own auras (a target changes under the timer) and not a proc.
function T.Applies(p)
  return p.trackMode ~= "live" and p.source == "aura" and p.unit == "player"
end

-- Whether the computed timer takes over a readable aura at the start of a fight and is corrected by readings
-- outside it (every mode but cast, where the cast events alone decide).
function T.Reads(p)
  return p.trackMode ~= "cast"
end

-- Duration -----------------------------------------------------------------------------------------------

-- The duration to count with and where it comes from: the typed one, the one learned from the last reading, the
-- base duration the game gave then. A value of 0 or less is no duration.
function T.PickDuration(manual, learned, base)
  if finite(manual) and manual > 0 then
    return manual, "manual"
  elseif finite(learned) and learned > 0 then
    return learned, "learned"
  elseif finite(base) and base > 0 then
    return base, "base"
  end
  return nil, nil
end

-- State ----------------------------------------------------------------------------------------------------

function T.New()
  return { combat = false, stacks = 0 }
end

local function clearRun(state)
  state.startAt, state.endAt, state.duration = nil, nil, nil
  state.permanent, state.unknown, state.source = nil, nil, nil
  state.stacks = 0
end

-- Remembers what a readable reading said about the aura: f = { duration, expirationTime } (nil, none when the
-- aura is confirmed missing). A duration of 0 is an aura without end.
function T.Seen(state, f, now)
  if type(f) ~= "table" then
    state.seen = nil
  elseif finite(f.duration) and f.duration <= 0 then
    state.seen = { permanent = true, at = now }
  elseif finite(f.duration) and finite(f.expirationTime) and f.duration > 0 then
    state.seen = { duration = f.duration, expiration = f.expirationTime, at = now }
  end
end

-- A cast of the trigger spell: start (or restart) the timer. duration nil means no duration is known: the aura
-- counts as active without a timer. Returns false when the same cast was counted already (DEDUPE).
function T.Activate(state, duration, now, source, countStacks)
  if finite(state.activatedAt) and now - state.activatedAt >= 0 and now - state.activatedAt < T.DEDUPE then
    return false
  end
  local running = T.Status(state, now).present == true
  local stacks = running and state.stacks or 0
  clearRun(state)
  state.activatedAt = now
  state.stacks = countStacks and math.min(stacks + 1, T.STACK_MAX) or 0
  if finite(duration) and duration > 0 then
    state.startAt, state.endAt, state.duration, state.source = now, now + duration, duration, source
  else
    state.unknown = true
  end
  return true
end

-- The fight begins: an aura read before it carries on from its known end time (an own run keeps going), unless
-- `adopt` is false (mode cast starts from casts only).
function T.CombatStart(state, now, adopt)
  state.combat = true
  if adopt == false or state.endAt or state.permanent or state.unknown then
    return
  end
  local seen = state.seen
  if not seen then
    return
  end
  if seen.permanent then
    state.permanent, state.source = true, "seen"
  elseif seen.expiration > now then
    state.startAt, state.endAt, state.duration = seen.expiration - seen.duration, seen.expiration, seen.duration
    state.source = "seen"
  end
end

-- The fight is over: the reading of the game is trusted again, so the run goes, unless `keep` (mode cast).
function T.CombatEnd(state, keep)
  state.combat = false
  if not keep then
    clearRun(state)
  end
end

-- The aura ended by a sign the game gave (a named removal): the run stops.
function T.End(state)
  clearRun(state)
end

-- Death, resurrection and release: nothing is known after them.
function T.Reset(state)
  clearRun(state)
  state.seen, state.activatedAt = nil, nil
end

-- What the state says at `now`: present (true running or without end or unknown duration, false ended, nil nothing
-- known), remaining (seconds), duration, startAt, permanent, unknown, stacks, source. A timer that reaches its end
-- exactly now is over.
function T.Status(state, now)
  local out = { stacks = state.stacks > 0 and state.stacks or nil, source = state.source }
  if state.endAt then
    out.duration, out.startAt = state.duration, state.startAt
    if now < state.endAt then
      out.present, out.remaining = true, state.endAt - now
    else
      out.present, out.remaining = false, 0
    end
  elseif state.permanent then
    out.present, out.permanent = true, true
  elseif state.unknown then
    out.present, out.unknown = true, true
  end
  return out
end

-- Signals --------------------------------------------------------------------------------------------------

-- Whether a readable spell id of a cast event belongs to the trigger ids; a secret id (nil) never does.
function T.IsTrigger(ids, spellId)
  return finite(spellId) and ids[spellId] == true
end

-- The cooldown route for a client whose cast event gives no readable id: the trigger spell's cooldown going from
-- not active to active is a cast. A cooldown event that names the trigger readably (idMatches) is enough with
-- the global cooldown too (a spell without a cooldown of its own only has that one); without a readable id the
-- change must come outside the global cooldown, an unreadable flag guesses nothing. prev is the last known
-- isActive (nil when not known yet), active and onGcd the readable answers now. Returns started and the isActive
-- to remember.
function T.Fallback(prev, active, onGcd, idMatches)
  local nextPrev = prev
  if type(active) == "boolean" then
    nextPrev = active
  end
  if idMatches == true then
    return active == true and prev ~= true, nextPrev
  end
  return prev == false and active == true and onGcd == false, nextPrev
end

-- Learned durations ----------------------------------------------------------------------------------------

-- The store { v, seq, items = { [spellId] = { duration, base, seen } } }, repaired: bad entries dropped, at most
-- MAX_ENTRIES kept (the ones seen last).
function T.CleanStore(raw)
  local out = { v = T.STORE_VERSION, seq = 0, items = {} }
  if type(raw) ~= "table" or type(raw.items) ~= "table" then
    return out
  end
  local list = {}
  for id, entry in pairs(raw.items) do
    if
      finite(id)
      and id > 0
      and id <= T.SPELL_ID_MAX
      and id == math.floor(id)
      and type(entry) == "table"
      and finite(entry.duration)
      and entry.duration > 0
      and entry.duration <= T.DURATION_MAX
    then
      local base = finite(entry.base) and entry.base > 0 and entry.base <= T.DURATION_MAX and entry.base or nil
      list[#list + 1] =
        { id = id, duration = entry.duration, base = base, seen = finite(entry.seen) and entry.seen or 0 }
    end
  end
  table.sort(list, function(a, b)
    if a.seen ~= b.seen then
      return a.seen > b.seen
    end
    return a.id < b.id
  end)
  for i = 1, math.min(#list, T.MAX_ENTRIES) do
    local e = list[i]
    out.items[e.id] = { duration = e.duration, base = e.base, seen = e.seen }
    out.seq = math.max(out.seq, e.seen)
  end
  return out
end

-- Notes the duration seen on a readable aura (and its base duration when the game gave one). Returns whether the
-- store changed; an unchanged value writes nothing. A full store drops the entry seen longest ago.
function T.Learn(store, id, duration, base)
  if not (finite(id) and id > 0 and finite(duration) and duration > 0 and duration <= T.DURATION_MAX) then
    return false
  end
  base = finite(base) and base > 0 and base <= T.DURATION_MAX and base or nil
  local entry = store.items[id]
  if entry and entry.duration == duration and (base == nil or entry.base == base) then
    return false
  end
  if not entry then
    local count, oldest, oldestSeen = 0, nil, math.huge
    for key, e in pairs(store.items) do
      count = count + 1
      if e.seen < oldestSeen or (e.seen == oldestSeen and key < (oldest or math.huge)) then
        oldest, oldestSeen = key, e.seen
      end
    end
    if count >= T.MAX_ENTRIES and oldest then
      store.items[oldest] = nil
    end
  end
  store.seq = store.seq + 1
  store.items[id] = { duration = duration, base = base or (entry and entry.base) or nil, seen = store.seq }
  return true
end

-- The learned entry of a spell, nil when none.
function T.Lookup(store, id)
  return store.items[id]
end
