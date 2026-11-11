-- Which loot is a catch. Pure: the loot window arrives as a snapshot, the rule answers with the items to
-- count. Two ways in, in this order:
--   1. The game says the loot is a fishing loot (IsFishingLoot is true): every item with a readable id counts.
--      It says no (false): nothing counts.
--   2. The game does not say (the function is missing or its answer is hidden): the loot counts when the
--      fishing channel runs or ended a moment ago, and its source is not a creature, a vehicle, a pet or a
--      player (a source we cannot read is accepted, the channel is the evidence then).
-- The same loot is reported more than once (ready and opened, slots that move while it is taken), so only the
-- growth of the amount of an item within one cast counts.
local _, fish = ...
if not fish.FG then
  return
end

local R = {}
fish.CatchRules = R

-- Seconds after the end of the channel in which loot still belongs to the cast (second way in only).
R.WINDOW = 2

-- Source kinds that are never a fishing catch.
local FOREIGN = { Creature = true, Vehicle = true, Pet = true, Player = true, Corpse = true }

-- The kind of a source guid ("Creature-0-1-2..." gives "Creature"), nil for anything else.
function R.SourceKind(guid)
  if type(guid) ~= "string" then
    return nil
  end
  return guid:match("^(%a+)%-")
end

-- A new record of what one cast already counted.
function R.NewCast()
  return { counted = {} }
end

local function grouped(slots)
  local order, total = {}, {}
  for _, slot in ipairs(slots) do
    local item = slot.item
    if type(item) == "number" and item > 0 then
      local qty = type(slot.qty) == "number" and slot.qty >= 1 and math.floor(slot.qty) or 1
      if total[item] == nil then
        order[#order + 1] = item
        total[item] = 0
      end
      total[item] = total[item] + qty
    end
  end
  return order, total
end

-- Is this loot ours to count? Returns true and the way ("fishing" or "channel"), or false and the reason.
function R.Accepts(snap, ctx)
  if snap.fishing == true then
    return true, "fishing"
  elseif snap.fishing == false then
    return false, "not-fishing"
  end
  local recent = ctx.channeling == true
    or (type(ctx.sinceStop) == "number" and ctx.sinceStop >= 0 and ctx.sinceStop <= R.WINDOW)
  if not recent then
    return false, "no-channel"
  end
  return true, "channel"
end

-- The items to count from a loot snapshot. snap: { fishing = true | false | nil, slots = { { item, qty,
-- source } } }. ctx: { channeling = bool, sinceStop = seconds | nil }. cast: R.NewCast() of the cast the loot
-- belongs to (updated). Returns a list of { item, qty } (growth only, in slot order) and the way.
function R.Catches(snap, ctx, cast)
  local out = {}
  if type(snap) ~= "table" or type(snap.slots) ~= "table" then
    return out, "no-loot"
  end
  local ok, way = R.Accepts(snap, ctx or {})
  if not ok then
    return out, way
  end
  local slots = {}
  for _, slot in ipairs(snap.slots) do
    local kind = R.SourceKind(slot.source)
    if way == "fishing" or not (kind and FOREIGN[kind]) then
      slots[#slots + 1] = slot
    end
  end
  local order, total = grouped(slots)
  for _, item in ipairs(order) do
    local seen = cast.counted[item] or 0
    if total[item] > seen then
      out[#out + 1] = { item = item, qty = total[item] - seen }
      cast.counted[item] = total[item]
    end
  end
  return out, way
end
