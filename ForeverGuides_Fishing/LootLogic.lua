-- Rules of the automatic looting of a catch. Pure: which slots in which order, and whether the client
-- asks to confirm a loot that binds.
local _, fish = ...
if not fish.FG then
  return
end

local Loot = {}
fish.LootLogic = Loot

-- Only a catch (the loot window of a fishing cast) and only with the option on.
function Loot.Wanted(options, isFishingLoot)
  return options.autoLoot == true and isFishingLoot == true
end

-- Slots from the last to the first: a slot that is taken does not shift the ones before it.
function Loot.Order(count)
  local out = {}
  if type(count) ~= "number" then
    return out
  end
  for slot = math.floor(count), 1, -1 do
    out[#out + 1] = slot
  end
  return out
end

-- The Forever client does not ask to confirm a loot that binds on pickup, other clients do.
function Loot.NeedsBindConfirm(flavor)
  return flavor == "retail"
end
