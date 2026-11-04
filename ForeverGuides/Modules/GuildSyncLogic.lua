-- Rules of the guild sync functions, no game calls and no access to saved data: send grid, intake
-- gate, the adaptive pace of position messages, plausibility of received positions, expiry rules and
-- the checks on recipe sets. Clock and random source are passed in; every number is in CONFIG.
-- Receiving never sends anything. The pace only depends on how many senders were heard lately.
local _, ns = ...

local L = {}
ns.GuildSyncLogic = L

local DAY = 86400

L.CONFIG = {
  -- gap = clamp(base * heardSenders / perSenders, min, max) seconds between two position messages.
  gap = { base = 5, perSenders = 15, min = 5, max = 30, window = 120, tracked = 600 },
  -- Heartbeat while standing still: scales with the gap, at most max seconds, spread by +-jitter.
  beat = { base = 60, max = 120, jitter = 0.2 },
  move = {
    -- Smallest move worth a message: yards, or this share of the map where yards are unknown.
    yards = 40,
    fraction = 0.015,
    -- Seconds between two messages when the map changes.
    zoneGap = 2,
    -- Seconds of silence after a pause ends.
    resume = 3,
    -- Faster than this between two reports is a jump (teleport, wrong data).
    maxSpeed = 120,
  },
  store = {
    -- A received position is current up to `fresh` seconds, older up to `old`, then gone.
    fresh = 60,
    old = 240,
    positions = 300,
    craftTtl = 14 * DAY,
    directory = 500,
    spells = 400,
    perSpell = 30,
  },
  -- Send windows per function and type: every window must have a token. `total` covers the function.
  send = {
    guildMap = {
      total = { burst = 5, refill = 0.6 },
      types = {
        P = { { burst = 4, refill = 0.5 } },
        X = { { burst = 2, refill = 0.2 } },
      },
    },
    crafting = {
      total = { burst = 6, refill = 1 },
      types = {
        J = { { burst = 2, refill = 1 / 60 } },
        -- One question per 10 seconds, at most 20 per hour.
        W = { { burst = 2, refill = 0.1 }, { burst = 20, refill = 20 / 3600 } },
        -- At most 20 answers per minute.
        K = { { burst = 5, refill = 1 / 3 } },
        R = { { burst = 3, refill = 0.8 } },
        -- Blocks of one answer, about 1.1 seconds apart.
        C = { { burst = 6, refill = 0.9 } },
        X = { { burst = 2, refill = 0.2 } },
      },
    },
  },
  receive = {
    total = { burst = 60, refill = 60 },
    -- Seconds everything is dropped after the total limit was hit.
    penalty = 5,
    tracked = 600,
    -- Seconds between two messages of one type from one sender.
    spacing = { P = 2, J = 60, W = 10, R = 10 },
  },
}
local C = L.CONFIG

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function whole(v, lo, hi)
  return finite(v) and v == math.floor(v) and v >= lo and v <= hi
end

local function now(clock)
  local ok, t = pcall(clock)
  return ok and finite(t) and t or 0
end

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

-- Pace --------------------------------------------------------------------------------------------

-- Seconds between two position messages for `heard` distinct senders in the last window.
function L.Gap(heard)
  local g = C.gap
  if not finite(heard) and heard ~= math.huge then
    heard = 0
  end
  return clamp(g.base * math.max(0, heard) / g.perSenders, g.min, g.max)
end

-- Seconds of standing still until the next "still here" message, before the spread.
function L.Heartbeat(heard)
  return math.min(C.beat.max, C.beat.base * L.Gap(heard) / C.gap.min)
end

-- `value` spread by +-fraction. `random()` returns 0 to 1 (default math.random).
function L.Jitter(value, fraction, random)
  local r = tonumber(try(random or math.random))
  if not r or r ~= r then
    r = 0.5
  end
  return value * (1 + (2 * clamp(r, 0, 1) - 1) * fraction)
end

-- Seconds until the heartbeat after a message, drawn once per message.
function L.NextBeat(heard, random)
  return L.Jitter(L.Heartbeat(heard), C.beat.jitter, random)
end

-- Distinct senders heard in the last window. Note(sender) after every accepted position message.
function L.NewHeard(clock)
  local seen, count = {}, 0
  local H = {}

  local function sweep(t)
    for sender, at in pairs(seen) do
      if t - at >= C.gap.window then
        seen[sender] = nil
        count = count - 1
      end
    end
  end

  function H.Note(sender)
    if type(sender) ~= "string" or sender == "" then
      return
    end
    local t = now(clock)
    if seen[sender] == nil then
      if count >= C.gap.tracked then
        sweep(t)
      end
      if count >= C.gap.tracked then
        return
      end
      count = count + 1
    end
    seen[sender] = t
  end

  function H.Count()
    sweep(now(clock))
    return count
  end

  function H.Clear()
    seen, count = {}, 0
  end

  return H
end

-- Distance of two own positions in yards through `dist(a, b)`, else as a share of the map (x and y are
-- fractions 0..1 on the same map). Returns the distance and whether it is in yards.
local function distance(a, b, dist)
  local yards = try(dist, a, b)
  if finite(yards) then
    return yards, true
  end
  if not (finite(a.x) and finite(a.y) and finite(b.x) and finite(b.y)) then
    return 0, false
  end
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy), false
end

-- Why the own position should be sent now: "first", "zone", "move", "beat", or nil for nothing.
-- last = { map, x, y, at, beatIn } of the last message sent (nil before the first), cur = { map, x, y },
-- x and y as map fractions 0..1.
-- beatIn is the NextBeat drawn when `last` was sent.
function L.SendReason(last, cur, t, heard, dist)
  if not last then
    return "first"
  end
  local age = t - last.at
  local m = C.move
  if cur.map ~= last.map then
    return age >= m.zoneGap and "zone" or nil
  end
  if age >= L.Gap(heard) then
    local d, inYards = distance(last, cur, dist)
    if d >= (inYards and m.yards or m.fraction) then
      return "move"
    end
  end
  if age >= (last.beatIn or L.Heartbeat(heard)) then
    return "beat"
  end
  return nil
end

-- Plausibility of a received position against the previous one of the same sender, for display only.
-- Records are { map, x, y, at }. Returns "ok", "zone" (map changed, speed not judged) or "jump".
function L.Plausible(prev, cur, dist)
  if type(prev) ~= "table" or type(cur) ~= "table" or prev.map ~= cur.map then
    return "zone"
  end
  local dt = cur.at - prev.at
  if not finite(dt) or dt < 0 then
    return "ok"
  end
  local yards = try(dist, prev, cur)
  if not finite(yards) then
    return "ok"
  end
  return yards / math.max(dt, 1) > C.move.maxSpeed and "jump" or "ok"
end

-- Expiry --------------------------------------------------------------------------------------------

-- "current", "old" or nil (gone) for a position received at `at`.
function L.PositionState(at, t)
  if not finite(at) or not finite(t) then
    return nil
  end
  local age = math.max(0, t - at)
  if age <= C.store.fresh then
    return "current"
  end
  if age <= C.store.old then
    return "old"
  end
  return nil
end

-- True while a stored recipe answer or summary from `at` (epoch seconds) is kept.
function L.CraftValid(at, t)
  return finite(at) and finite(t) and t - at <= C.store.craftTtl
end

-- Rate limits ---------------------------------------------------------------------------------------

-- Minimum gap per key: Allow(key, seconds) is true when the key was not allowed within `seconds`.
-- Keeps at most `max` keys; when full, finished ones go first and then everything.
function L.NewSpacing(clock, max)
  local free, count = {}, 0
  local S = {}

  function S.Allow(key, seconds)
    local t = now(clock)
    local until_ = free[key]
    if until_ and t < until_ then
      return false
    end
    if until_ == nil then
      if count >= max then
        for k, v in pairs(free) do
          if v <= t then
            free[k] = nil
            count = count - 1
          end
        end
        if count >= max then
          free, count = {}, 0
        end
      end
      count = count + 1
    end
    free[key] = t + seconds
    return true
  end

  return S
end

-- Send grid of one function ("guildMap" or "crafting"): a token window per type and one for the whole
-- function. Allow(type, cost) spends from all of them or from none.
function L.NewSendGrid(clock, fn)
  local CL = ns.CommLogic
  local spec = type(fn) == "string" and C.send[fn] or nil
  if not spec or not CL or type(clock) ~= "function" then
    return nil, "args"
  end
  local total = CL.NewBucket(spec.total.burst, spec.total.refill, clock)
  local types = {}
  for typ, windows in pairs(spec.types) do
    types[typ] = {}
    for i, w in ipairs(windows) do
      types[typ][i] = CL.NewBucket(w.burst, w.refill, clock)
    end
  end
  local S = {}

  function S.Allow(typ, cost)
    cost = cost == nil and 1 or cost
    local list = type(typ) == "string" and types[typ] or nil
    if not list or not finite(cost) or cost < 0 then
      return false
    end
    local buckets = { total }
    for i = 1, #list do
      buckets[i + 1] = list[i]
    end
    for _, b in ipairs(buckets) do
      if b.Level() + 1e-9 < cost then
        return false
      end
    end
    for _, b in ipairs(buckets) do
      b.Take(cost)
    end
    return true
  end

  function S.Reset()
    total.Reset()
    for _, list in pairs(types) do
      for _, b in ipairs(list) do
        b.Reset()
      end
    end
  end

  return S
end

-- Intake gate in front of any processing: a total limit (a flood is dropped for `penalty` seconds), then
-- one message per type and sender within the spacing. Allow(type, sender) -> true, or false and the
-- reason "flood", "sender" or "rate".
function L.NewIntake(clock)
  local CL = ns.CommLogic
  local r = C.receive
  if not CL or type(clock) ~= "function" then
    return nil, "args"
  end
  local bucket = CL.NewBucket(r.total.burst, r.total.refill, clock)
  local spacing = L.NewSpacing(clock, r.tracked)
  local blocked, dropped = -math.huge, 0
  local I = {}

  local function refuse(reason)
    dropped = dropped + 1
    return false, reason
  end

  function I.Allow(typ, sender)
    local t = now(clock)
    if t < blocked then
      return refuse("flood")
    end
    if not bucket.Take(1) then
      blocked = t + r.penalty
      return refuse("flood")
    end
    local seconds = type(typ) == "string" and r.spacing[typ] or nil
    if not seconds then
      return true
    end
    if type(sender) ~= "string" or sender == "" then
      return refuse("sender")
    end
    if not spacing.Allow(typ .. ":" .. sender, seconds) then
      return refuse("rate")
    end
    return true
  end

  function I.Dropped()
    return dropped
  end

  return I
end

-- Recipe sets ---------------------------------------------------------------------------------------

-- Answer to a fetch (R) for a set of known spell ids. `request` is { u, h } of the asker (0 = none).
-- Returns { art, u, n, h, data } for C, or nil and a reason. "=" when the asker's copy is current, "B"
-- when both sides share the universe, else "I".
function L.PlanAnswer(universe, known, request)
  local G = ns.GuildSyncCodec
  if type(universe) ~= "table" or not universe.size or universe.size < 1 then
    return nil, "universe"
  end
  if
    type(request) ~= "table"
    or not whole(request.u, 0, G.LIMITS.MAX_SUM)
    or not whole(request.h, 0, G.LIMITS.MAX_SUM)
  then
    return nil, "request"
  end
  local mask, n, h, ids = G.EncodeMask(universe, known)
  if not mask then
    return nil, n
  end
  local answer = { u = universe.sum, n = n, h = h }
  if request.h ~= 0 and request.h == h then
    answer.art = "="
  elseif request.u ~= 0 and request.u == universe.sum then
    answer.art, answer.data = "B", mask
  else
    answer.art, answer.data = "I", G.EncodeIdList(ids)
  end
  return answer
end

-- Checks a decoded C against what the receiver can know. Returns "ok" and the ascending ids of the set,
-- "same" (nothing to replace), or "rejected" and the reason. Count and checksum of the set must fit the
-- head, otherwise the old copy stays.
function L.VerifyAnswer(msg, universe)
  local G = ns.GuildSyncCodec
  if type(msg) ~= "table" or msg.typ ~= "C" then
    return "rejected", "message"
  end
  if msg.art == "=" then
    return "same"
  end
  local ids
  if msg.art == "B" then
    if type(universe) ~= "table" or not universe.size or universe.size < 1 or universe.sum ~= msg.u then
      return "rejected", "universe"
    end
    local ranks, why = G.DecodeMask(msg.data, universe.size)
    if not ranks then
      return "rejected", why
    end
    ids = {}
    for i, k in ipairs(ranks) do
      ids[i] = universe.ids[k]
    end
  elseif msg.art == "I" then
    ids = msg.ids or G.DecodeIdList(msg.data)
    if not ids then
      return "rejected", "data"
    end
  else
    return "rejected", "art"
  end
  if #ids ~= msg.n then
    return "rejected", "count"
  end
  if G.Checksum(ids) ~= msg.h then
    return "rejected", "checksum"
  end
  return "ok", ids
end

-- True, false, or nil (cannot tell) whether the mask of a job holds the spell. The mask must belong to
-- the universe `universe` (same checksum `u`).
function L.Holds(universe, u, mask, spell)
  local G = ns.GuildSyncCodec
  if type(universe) ~= "table" or universe.sum ~= u or not universe.size or universe.size < 1 then
    return nil
  end
  local rank = universe.rank[spell]
  if not rank then
    return nil
  end
  return G.MaskHas(mask, universe.size, rank)
end

-- Who can make a spell: entries = { [key] = { u, mask } } of one job. Returns the sorted keys that hold
-- it and the number of entries that could not be judged.
function L.Holders(universe, entries, spell)
  local yes, unknown = {}, 0
  for key, e in pairs(entries) do
    local has
    if type(e) == "table" then
      has = L.Holds(universe, e.u, e.mask, spell)
    end
    if has then
      yes[#yes + 1] = key
    elseif has == nil then
      unknown = unknown + 1
    end
  end
  table.sort(yes)
  return yes, unknown
end
