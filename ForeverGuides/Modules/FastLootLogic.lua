-- Rules of the faster looting. Pure: when the game would auto loot, which slots in which order,
-- and when a second loot event of the same window is ignored.
local _, ns = ...

local Logic = {}
ns.FastLootLogic = Logic

-- Seconds in which a second LOOT_READY/LOOT_OPENED of the same window counts as a repeat.
Logic.DEBOUNCE = 0.5

-- Auto loot applies when the game setting and the toggle modifier differ.
function Logic.AutoLootApplies(setting, modifier)
  return (setting == true) ~= (modifier == true)
end

-- Last slot first: a slot that is taken does not shift the ones before it.
function Logic.Order(count)
  local out = {}
  if type(count) ~= "number" then
    return out
  end
  for slot = math.floor(count), 1, -1 do
    out[#out + 1] = slot
  end
  return out
end

-- lastAt is when the window was last handled (nil: never).
function Logic.IsRepeat(lastAt, now)
  return type(lastAt) == "number" and type(now) == "number" and now - lastAt < Logic.DEBOUNCE and now >= lastAt
end
