-- Item count logic without WoW API (ns.ItemCountLogic), the base of the item count element of the mouse cursor
-- ring and the HUD windows: the repair of the saved props, the show rule, the low and goal thresholds, the number
-- text, the choice of a count from a read that may fail, the short cache of counts and what a game event means for
-- one element. The code that talks to the game reads every value protected and passes only what it could read; a
-- value the game keeps secret arrives as nil.
local _, ns = ...
local U, XB, CU = ns.U, ns.XpBarLayout, ns.CursorLogic

local I = {}
ns.ItemCountLogic = I

I.SHOW_WHEN = { "always", "some", "low", "empty" }
I.STYLES = { "ring", "bar" }
I.FORMS = { "circle", "square" }
I.TEXT_MODES = { "count", "ofGoal" }
I.NAME_POSITIONS = { "off", "below", "above" }
I.ITEM_ID_MAX = 9999999
I.LOW_MAX = 99999
I.GOAL_MAX = 999999
I.BAR_W_MIN, I.BAR_W_MAX, I.BAR_H_MIN, I.BAR_H_MAX = 20, 400, 4, 64
-- Counts are cached this many seconds per item, events clear the cache at once.
I.CACHE_SECONDS = 0.25
-- From this count on a number is written short (12k).
I.SHORT_FROM = 10000

I.DEFAULTS = {
  itemId = 0,
  includeBank = false,
  includeReagentBank = false,
  includeUses = false,
  showWhen = "always",
  low = 0,
  goal = 0,
  abbreviate = false,
  textMode = "count",
  dimEmpty = true,
  style = "ring",
  shape = "circle",
  thickness = 3,
  color = "4aa8ff",
  lowColor = "ff5a5a",
  textColor = "ffffff",
  alpha = 0.9,
  barWidth = 120,
  barHeight = 16,
  barBackColor = "1a1a1a",
  namePos = "off",
  countFont = "frizqt",
  countFontSize = 16,
  countOutline = "outline",
  countShadow = true,
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function flag(v, default)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function whole(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v + 0.5), lo, hi) or default
end

-- Props ---------------------------------------------------------------------------------------------------------

-- The saved props of an element with every field valid, `d` holding the defaults.
function I.Clean(raw, d)
  local font = raw.countFont
  return {
    itemId = whole(raw.itemId, d.itemId, 0, I.ITEM_ID_MAX),
    includeBank = flag(raw.includeBank, d.includeBank),
    includeReagentBank = flag(raw.includeReagentBank, d.includeReagentBank),
    includeUses = flag(raw.includeUses, d.includeUses),
    showWhen = oneOf(raw.showWhen, I.SHOW_WHEN, d.showWhen),
    low = whole(raw.low, d.low, 0, I.LOW_MAX),
    goal = whole(raw.goal, d.goal, 0, I.GOAL_MAX),
    abbreviate = flag(raw.abbreviate, d.abbreviate),
    textMode = oneOf(raw.textMode, I.TEXT_MODES, d.textMode),
    dimEmpty = flag(raw.dimEmpty, d.dimEmpty),
    style = oneOf(raw.style, I.STYLES, d.style),
    shape = oneOf(raw.shape, I.FORMS, d.shape),
    thickness = whole(raw.thickness, d.thickness, CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX),
    color = hex(raw.color, d.color),
    lowColor = hex(raw.lowColor, d.lowColor),
    textColor = hex(raw.textColor, d.textColor),
    alpha = finite(raw.alpha) and U.clamp(raw.alpha, 0, 1) or d.alpha,
    barWidth = whole(raw.barWidth, d.barWidth, I.BAR_W_MIN, I.BAR_W_MAX),
    barHeight = whole(raw.barHeight, d.barHeight, I.BAR_H_MIN, I.BAR_H_MAX),
    barBackColor = hex(raw.barBackColor, d.barBackColor),
    namePos = oneOf(raw.namePos, I.NAME_POSITIONS, d.namePos),
    countFont = type(font) == "string" and #font <= 44 and font or d.countFont,
    countFontSize = whole(raw.countFontSize, d.countFontSize, XB.SIZE_MIN, XB.SIZE_MAX),
    countOutline = oneOf(raw.countOutline, XB.OUTLINES, d.countOutline),
    countShadow = flag(raw.countShadow, d.countShadow),
  }
end

-- Whether the element counts what the bank holds, so it listens to the bank events.
function I.CountsBank(p)
  return p.includeBank == true or p.includeReagentBank == true
end

-- The key of one count in the cache: the item and the three switches that change the number.
function I.Key(p)
  return table.concat({
    p.itemId,
    p.includeBank and 1 or 0,
    p.includeUses and 1 or 0,
    p.includeReagentBank and 1 or 0,
  }, "|")
end

-- The size of the name text next to the count: a little smaller, never below the smallest font size.
function I.NameSize(p)
  return math.max(XB.SIZE_MIN, p.countFontSize - 4)
end

-- Reading ------------------------------------------------------------------------------------------------------

-- The count a game answer stands for: a whole number from 0 up, nil for anything else (a missing function, a
-- secret value, text, a negative or infinite number).
function I.ReadCount(v)
  if not finite(v) or v < 0 then
    return nil
  end
  return math.floor(v)
end

-- The count to show: a fresh readable one, else the last readable one (nil when there never was one).
function I.Resolve(read, last)
  local fresh = I.ReadCount(read)
  if fresh ~= nil then
    return fresh, true
  end
  return last, false
end

-- A cache of counts with an injected clock. Get(key, read) calls read() (a count or nil) when the entry is older
-- than `ttl`; only a readable answer is kept, so a failed read is asked again at once.
function I.NewCache(clock, ttl)
  local cache, entries = {}, {}
  ttl = finite(ttl) and ttl or I.CACHE_SECONDS
  function cache.Get(key, read)
    local now = clock()
    local entry = entries[key]
    if entry and now - entry.at < ttl and now >= entry.at then
      return entry.value
    end
    local value = I.ReadCount(read())
    if value ~= nil then
      entries[key] = { value = value, at = now }
    else
      entries[key] = nil
    end
    return value
  end
  function cache.Clear()
    entries = {}
  end
  return cache
end

-- Showing ------------------------------------------------------------------------------------------------------

-- Whether the count is below the low threshold (off at 0).
function I.IsLow(p, count)
  return finite(count) and p.low > 0 and count < p.low
end

-- Whether the element shows for a count: nothing chosen or never read shows nothing, else the rule.
function I.Visible(p, count)
  if p.itemId <= 0 or not finite(count) then
    return false
  end
  local when = p.showWhen
  if when == "some" then
    return count >= 1
  elseif when == "low" then
    return I.IsLow(p, count)
  elseif when == "empty" then
    return count == 0
  end
  return true
end

-- The share of the goal reached, 0 to 1; nil without a goal.
function I.Fraction(p, count)
  if p.goal <= 0 then
    return nil
  end
  if not finite(count) then
    return 0
  end
  return U.clamp(count / p.goal, 0, 1)
end

-- A count as text: the whole number, or from SHORT_FROM on with a k or m (cut, never rounded up: 99999 is 99.9k).
function I.Format(count, abbreviate)
  if not finite(count) then
    return ""
  end
  count = math.floor(count)
  if abbreviate ~= true or count < I.SHORT_FROM then
    return tostring(count)
  end
  local unit, value = "k", math.floor(count / 100) / 10
  if count >= 1000000 then
    unit, value = "m", math.floor(count / 100000) / 10
  end
  return (string.format("%.1f", value):gsub("%.0$", "")) .. unit
end

-- The number text of the element: the count, or count over goal when the mode asks for it and a goal is set.
function I.Text(p, count)
  local text = I.Format(count, p.abbreviate)
  if p.textMode == "ofGoal" and p.goal > 0 then
    return text .. "/" .. I.Format(p.goal, p.abbreviate)
  end
  return text
end

-- The count the editor preview shows: the simulated share of a sample size that makes every threshold visible.
function I.Sample(p, fraction)
  local size = math.max(p.goal, p.low * 3, 20)
  if not finite(fraction) then
    fraction = 0.6
  end
  return math.floor(U.clamp(fraction, 0, 1) * size + 0.5)
end

-- Events ------------------------------------------------------------------------------------------------------

-- The events every drawn element listens to, and the ones only an element that counts the bank listens to.
I.EVENTS = {
  "BAG_UPDATE_DELAYED",
  "ITEM_COUNT_CHANGED",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_EQUIPMENT_CHANGED",
  "ITEM_DATA_LOAD_RESULT",
}
I.BANK_EVENTS = {
  "BANKFRAME_OPENED",
  "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED",
  "PLAYERREAGENTBANKSLOTS_CHANGED",
}

local READS = {
  BAG_UPDATE_DELAYED = true,
  PLAYER_ENTERING_WORLD = true,
  PLAYER_EQUIPMENT_CHANGED = true,
}
local BANK_READS = {
  BANKFRAME_OPENED = true,
  BANKFRAME_CLOSED = true,
  PLAYERBANKSLOTS_CHANGED = true,
  PLAYERREAGENTBANKSLOTS_CHANGED = true,
}

-- What an event means for one element: "read" (count again), "load" (the data of the item arrived, paint the icon
-- and the name and count again) or nil. `id` is the item id of the payload, nil when it is missing or secret (the
-- element then reads, instead of missing a change).
function I.Route(event, id, p)
  if READS[event] then
    return "read"
  elseif event == "ITEM_COUNT_CHANGED" then
    return (id == nil or id == p.itemId) and "read" or nil
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    return (id == nil or id == p.itemId) and "load" or nil
  elseif BANK_READS[event] then
    return I.CountsBank(p) and "read" or nil
  end
  return nil
end

-- Status ------------------------------------------------------------------------------------------------------

-- What the element does in combat, for the panel line. caps = { api = false when the client has no count function,
-- secret = true when the last read was secret }. Returns { key, color, notes }: key "readable" (the count is a plain
-- number the add-on reads live), "partial" (the last readable number stays while the game keeps it secret) or
-- "none" (nothing to show), color a theme colour name, notes the reasons as keys of the panel text.
function I.Status(p, caps)
  caps = caps or {}
  if p.itemId <= 0 then
    return { key = "none", color = "danger", notes = { "nothing" } }
  elseif caps.api == false then
    return { key = "none", color = "danger", notes = { "api" } }
  elseif caps.secret == true then
    return { key = "partial", color = "warning", notes = { "secret" } }
  end
  return { key = "readable", color = "success", notes = {} }
end
