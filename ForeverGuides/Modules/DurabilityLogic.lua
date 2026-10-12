-- Durability window, pure part (no game access): the slots in the order of the character window,
-- percent and condition levels, the summary line, and the "newly below the limit" rule of the chat
-- warning. Modules/DurabilityView.lua reads the game and feeds this file, tests run it alone.
local _, ns = ...
local U = ns.U

local DL = {}
ns.DurabilityLogic = DL

-- Slots in the order of the character window. optional = shown only while the worn item has a
-- durability (necks, cloaks, rings and trinkets have none in Classic). Shirt and tabard never have one.
DL.SLOTS = {
  { id = 1, token = "HeadSlot", key = "head" },
  { id = 2, token = "NeckSlot", key = "neck", optional = true },
  { id = 3, token = "ShoulderSlot", key = "shoulder" },
  { id = 15, token = "BackSlot", key = "back", optional = true },
  { id = 5, token = "ChestSlot", key = "chest" },
  { id = 9, token = "WristSlot", key = "wrist" },
  { id = 10, token = "HandsSlot", key = "hands" },
  { id = 6, token = "WaistSlot", key = "waist" },
  { id = 7, token = "LegsSlot", key = "legs" },
  { id = 8, token = "FeetSlot", key = "feet" },
  { id = 16, token = "MainHandSlot", key = "mainhand" },
  { id = 17, token = "SecondaryHandSlot", key = "offhand" },
  { id = 18, token = "RangedSlot", key = "ranged" },
  { id = 11, token = "Finger0Slot", key = "finger1", optional = true },
  { id = 12, token = "Finger1Slot", key = "finger2", optional = true },
  { id = 13, token = "Trinket0Slot", key = "trinket1", optional = true },
  { id = 14, token = "Trinket1Slot", key = "trinket2", optional = true },
}

-- Defaults of the settings (Core/Store.lua keeps the same numbers).
DL.DEFAULTS = { yellow = 50, orange = 25, red = 10, onlyBelow = 50, warn = 25 }

-- Level names from best to worst, base colors on a dark window. The view lifts a color further
-- when the window background asks for it (4.5:1, WCAG 2.1 AA).
DL.LEVELS = { "good", "warn", "low", "critical" }
DL.COLORS = { good = "#4fd16a", warn = "#f0d44a", low = "#ff9a3c", critical = "#ff6b5e" }

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- A whole percent between 1 and 99, `default` for anything else.
function DL.CleanLimit(v, default)
  if not finite(v) then
    return default
  end
  return U.clamp(math.floor(v + 0.5), 1, 99)
end

-- Condition in percent (0 to 100, not rounded), nil without a usable pair of numbers.
function DL.Percent(cur, max)
  if not (finite(cur) and finite(max)) or max <= 0 then
    return nil
  end
  return U.clamp(cur / max * 100, 0, 100)
end

-- The whole percent shown next to the bar. Rounded down, so the text never reads better than the level.
function DL.Display(pct)
  return math.floor(pct + 1e-9)
end

-- The three limits (below `yellow` the condition is "warn", below `orange` "low", below `red`
-- "critical") as three whole percents in strictly falling order. `prefer` names the limit that
-- just changed ("yellow", "orange", "red"): the others give way to it.
function DL.Thresholds(yellow, orange, red, prefer)
  local d = DL.DEFAULTS
  yellow, orange, red = DL.CleanLimit(yellow, d.yellow), DL.CleanLimit(orange, d.orange), DL.CleanLimit(red, d.red)
  if prefer == "red" then
    red = math.min(red, 97)
    orange = math.min(math.max(orange, red + 1), 98)
    yellow = math.max(yellow, orange + 1)
  elseif prefer == "orange" then
    orange = U.clamp(orange, 2, 98)
    red = math.max(1, math.min(red, orange - 1))
    yellow = math.max(yellow, orange + 1)
  else
    yellow = math.max(yellow, 3)
    orange = math.max(2, math.min(orange, yellow - 1))
    red = math.max(1, math.min(red, orange - 1))
  end
  return yellow, orange, red
end

-- Level name of a percent, nil for nil.
function DL.Level(pct, yellow, orange, red)
  if not finite(pct) then
    return nil
  end
  if pct < red then
    return "critical"
  elseif pct < orange then
    return "low"
  elseif pct < yellow then
    return "warn"
  end
  return "good"
end

-- One entry per row of the window. read(slot) answers { cur, max, icon, placeholder, link, worn } for a
-- slot of DL.SLOTS (nothing is fine). Worn parts with a durability become rows with a percent, an empty
-- slot that could carry armor or a weapon becomes a row without one, everything else is left out.
function DL.Entries(read)
  local out = {}
  for _, slot in ipairs(DL.SLOTS) do
    local info = read(slot)
    info = type(info) == "table" and info or {}
    local pct = DL.Percent(info.cur, info.max)
    if pct then
      out[#out + 1] = {
        id = slot.id,
        key = slot.key,
        token = slot.token,
        cur = info.cur,
        max = info.max,
        pct = pct,
        icon = info.icon or info.placeholder,
        link = info.link,
      }
    elseif not slot.optional and not info.worn then
      out[#out + 1] = { id = slot.id, key = slot.key, token = slot.token, empty = true, icon = info.placeholder }
    end
  end
  return out
end

-- { count, average (percent, nil without parts), worst (the entry with the lowest percent, the first one on a tie) }.
function DL.Summary(entries)
  local count, sum, worst = 0, 0, nil
  for _, e in ipairs(entries) do
    if e.pct then
      count = count + 1
      sum = sum + e.pct
      if not worst or e.pct < worst.pct then
        worst = e
      end
    end
  end
  return { count = count, average = count > 0 and sum / count or nil, worst = worst }
end

-- True while a part is below `limit` percent.
function DL.AnyBelow(entries, limit)
  for _, e in ipairs(entries) do
    if e.pct and e.pct < limit then
      return true
    end
  end
  return false
end

-- The chat warning fires once per part and drop: state[slotId] is true after the part was reported and
-- clears when it is back at `limit` or above (repaired) or empty. Returns the entries to report now.
-- hold = true (combat) keeps back what is new, so the next call after the fight reports it.
function DL.Crossings(state, entries, limit, hold)
  local out = {}
  for _, e in ipairs(entries) do
    if not e.pct or e.pct >= limit then
      state[e.id] = nil
    elseif not state[e.id] and not hold then
      state[e.id] = true
      out[#out + 1] = e
    end
  end
  return out
end
