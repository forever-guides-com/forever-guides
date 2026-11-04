-- Forever Chat, the pace of the teams (pure, no game access, the caller passes every clock value): a bucket of bytes
-- for the add-on whispers of the function teamChat, the order of the packets, and the delivery count of own messages.
-- The numbers are assumptions of ChatThrottleLib (the game itself publishes none): a burst of 4000 bytes, then 800
-- bytes per second, about 40 bytes of overhead per message, a tenth in the first seconds after login and a loading
-- screen. This pace stays below them on purpose: burst 3000, 600 bytes per second.
--   cost of a message  length of the text + length of the prefix + OVERHEAD
--   order              messages (and the answers to a sync request) before roster and changes before sync requests,
--                      inside a class the order of arrival; the members of one message come in random order, so the
--                      same ones are not always the last.
--   delivery           per own message "to N of M delivered": M are the members that count as reachable, a member
--                      who turns out to be offline leaves M, so the message can be complete.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local PL = {}
chat.TeamsPacerLogic = PL

PL.LIMITS = {
  BURST = 3000,
  RATE = 600,
  OVERHEAD = 40,
  -- Seconds after login or a loading screen that run at a tenth.
  ZONE_SECONDS = 5,
  ZONE_FACTOR = 0.1,
  -- After the game answered "too fast": the share of the pace for a while.
  PENALTY_FACTOR = 0.5,
  PENALTY_SECONDS = 5,
  -- One member takes in 6 messages at once and then 1 per second from a sender (the receive bucket of the line, blocks
  -- counted): stay below it, 5 and 0.9 per second, so even a client of an older version loses nothing.
  TARGET_BURST = 5,
  TARGET_RATE = 0.9,
  MAX_TARGETS = 400,
  -- Delivery counts kept (newest).
  TALLY_MAX = 400,
}
local L = PL.LIMITS

-- Class of a packet by its type letter (see TeamsLogic.TYPES): 1 goes first.
PL.CLASS = {
  M = 1,
  Y = 1,
  I = 2,
  A = 2,
  D = 2,
  R = 2,
  L = 2,
  U = 2,
  X = 2,
  F = 2,
  S = 3,
}

function PL.Class(typ)
  return PL.CLASS[typ] or 2
end

-- Bytes one message of the line costs: its text, the prefix and the overhead of the game.
function PL.Cost(textLength, prefixLength)
  return textLength + prefixLength + L.OVERHEAD
end

----------------------------------------------------------------------------------------------------
-- The bucket
----------------------------------------------------------------------------------------------------

-- A pacer with its own clock: clock() gives seconds that only rise. It starts inside the slow phase of a login.
function PL.New(clock)
  local P = {}
  local start = clock()
  local at, tokens = start, L.BURST * L.ZONE_FACTOR
  local zoneUntil, penaltyUntil = start + L.ZONE_SECONDS, 0
  local targets, targetCount = {}, 0

  -- The bucket of one member (blocks), refilled to `now`.
  local function targetBucket(key, now)
    local b = targets[key]
    if not b then
      if targetCount >= L.MAX_TARGETS then
        for k, other in pairs(targets) do
          if other.tokens + (now - other.at) * L.TARGET_RATE >= L.TARGET_BURST then
            targets[k], targetCount = nil, targetCount - 1
          end
        end
      end
      b = { tokens = L.TARGET_BURST, at = now }
      targets[key], targetCount = b, targetCount + 1
    elseif now > b.at then
      b.tokens, b.at = math.min(L.TARGET_BURST, b.tokens + (now - b.at) * L.TARGET_RATE), now
    end
    return b
  end

  local function factorAt(t)
    local f = 1
    if t < zoneUntil then
      f = f * L.ZONE_FACTOR
    end
    if t < penaltyUntil then
      f = f * L.PENALTY_FACTOR
    end
    return f
  end

  -- Refills from `at` to `now`, one piece for every change of the pace in between.
  local function advance(now)
    if now <= at then
      return
    end
    local t = at
    while t < now do
      local nextT = now
      if zoneUntil > t and zoneUntil < nextT then
        nextT = zoneUntil
      end
      if penaltyUntil > t and penaltyUntil < nextT then
        nextT = penaltyUntil
      end
      local f = factorAt(t)
      tokens = math.min(L.BURST * f, tokens + (nextT - t) * L.RATE * f)
      t = nextT
    end
    at = now
  end

  -- Takes `cost` bytes. A packet bigger than the bucket of the moment is let through when the bucket is full (the
  -- slow phase holds a tenth of 3000, less than the biggest block of the line) and leaves a debt that is paid back.
  -- `target` (a name key) is the member the block goes to: one block per member and second is the most, whatever the
  -- bytes say. Returns true, or false, the seconds to wait and "item" when only this member has to wait.
  function P.Take(cost, now, target)
    now = now or clock()
    advance(now)
    local tb = target and targetBucket(target, now)
    if tb and tb.tokens < 1 - 1e-9 then
      return false, math.max(0.05, (1 - tb.tokens) / L.TARGET_RATE), "item"
    end
    local f = factorAt(now)
    local need = math.min(cost, L.BURST * f)
    if tokens + 1e-9 >= need then
      tokens = tokens - cost
      if tb then
        tb.tokens = tb.tokens - 1
      end
      return true
    end
    return false, math.max(0.05, (need - tokens) / (L.RATE * f))
  end

  -- Login or a loading screen: a tenth of the pace for ZONE_SECONDS.
  function P.Zone(now)
    now = now or clock()
    advance(now)
    zoneUntil = now + L.ZONE_SECONDS
    tokens = math.min(tokens, L.BURST * factorAt(now))
  end

  -- The game said "too fast": half the pace for a few seconds and no stock to spend at once.
  function P.Slow(now)
    now = now or clock()
    advance(now)
    penaltyUntil = now + L.PENALTY_SECONDS
    tokens = math.min(tokens, L.BURST * factorAt(now))
  end

  -- The bytes in the bucket now and the share of the pace (1 is the full pace).
  function P.Level(now)
    now = now or clock()
    advance(now)
    return tokens, factorAt(now)
  end

  return P
end

----------------------------------------------------------------------------------------------------
-- Order
----------------------------------------------------------------------------------------------------

-- The index of the packet that goes next: the lowest class, inside it the first one that arrived. `ready(p)` says
-- whether a packet may go now (nil: all). Returns nil when nothing may go.
function PL.Pick(outbox, ready)
  local best, bestClass
  for i, p in ipairs(outbox) do
    local class = PL.Class(p.typ)
    if (not best or class < bestClass) and (ready == nil or ready(p)) then
      best, bestClass = i, class
      if class == 1 then
        break
      end
    end
  end
  return best
end

-- Puts a list in random order (Fisher-Yates); random(n) gives an integer from 1 to n. Returns the list.
function PL.Shuffle(list, random)
  for i = #list, 2, -1 do
    local j = math.max(1, math.min(i, math.floor(tonumber(random(i)) or i)))
    list[i], list[j] = list[j], list[i]
  end
  return list
end

----------------------------------------------------------------------------------------------------
-- Delivery count
----------------------------------------------------------------------------------------------------

-- The count of own messages { [key] = { total, done, skipped } }, at most TALLY_MAX (the oldest leave first).
function PL.NewTally()
  local T = {}
  local map, order = {}, {}

  -- A message of `total` packets (one per reachable member).
  function T.Expect(key, total)
    if map[key] == nil then
      order[#order + 1] = key
      while #order > L.TALLY_MAX do
        map[table.remove(order, 1)] = nil
      end
    end
    map[key] = { total = total, done = 0, skipped = 0 }
  end

  function T.Done(key)
    local e = map[key]
    if e then
      e.done = math.min(e.total - e.skipped, e.done + 1)
    end
  end

  -- A member that cannot be reached leaves the count.
  function T.Skip(key)
    local e = map[key]
    if e and e.done + e.skipped < e.total then
      e.skipped = e.skipped + 1
    end
  end

  -- A packet that counted as delivered did not arrive after all (the game said "not found" late).
  function T.Undo(key)
    local e = map[key]
    if e and e.done > 0 then
      e.done = e.done - 1
      e.skipped = e.skipped + 1
    end
  end

  -- { state, done, total } with total = M, the members that count: state is "waiting" (nothing delivered yet),
  -- "partial" (some), "complete" (all of M) or "nobody" (M is 0). nil for an unknown message.
  function T.State(key)
    local e = map[key]
    if not e then
      return nil
    end
    local total = e.total - e.skipped
    local state = "waiting"
    if total <= 0 then
      state = "nobody"
    elseif e.done >= total then
      state = "complete"
    elseif e.done > 0 then
      state = "partial"
    end
    return { state = state, done = e.done, total = total }
  end

  function T.Clear()
    map, order = {}, {}
  end

  return T
end
