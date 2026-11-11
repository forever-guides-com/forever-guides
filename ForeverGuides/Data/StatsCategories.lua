-- Item class and subclass to a statistics category, plus the locale keys of the category names. Pure data.
-- PROVISIONAL: the numbers follow the retail item enums. The subclass numbers of the Classic client differ in
-- places and are measured in game with known items, then corrected in BY_CLASS only.
local _, ns = ...

local C = {}
ns.StatsCategories = C

C.PROVISIONAL = true

C.POTIONS, C.FOOD, C.BANDAGES, C.REAGENTS, C.AMMO, C.OTHER = 1, 2, 3, 4, 5, 6

-- Display order of the categories.
C.ORDER = { C.POTIONS, C.FOOD, C.BANDAGES, C.REAGENTS, C.AMMO, C.OTHER }

C.KEYS = {
  [C.POTIONS] = "stats.cat.potions",
  [C.FOOD] = "stats.cat.food",
  [C.BANDAGES] = "stats.cat.bandages",
  [C.REAGENTS] = "stats.cat.reagents",
  [C.AMMO] = "stats.cat.ammo",
  [C.OTHER] = "stats.cat.other",
}

-- [class] = { [subclass] = category, all = category for every subclass of the class }.
-- Class 0 consumables: potions, elixirs and flasks share one category, scrolls, item enhancements, poisons and the
-- rest are not listed and fall to "other".
C.BY_CLASS = {
  [0] = {
    [1] = C.POTIONS,
    [2] = C.POTIONS,
    [3] = C.POTIONS,
    [5] = C.FOOD,
    [7] = C.BANDAGES,
  },
  [5] = { all = C.REAGENTS },
  [6] = { all = C.AMMO },
}

-- The category of an item class and subclass. An unknown pair is "other".
function C.Of(class, subclass)
  local map = C.BY_CLASS[class]
  return map and (map[subclass] or map.all) or C.OTHER
end

-- The locale key of a category, nil for an id that is not one.
function C.Key(category)
  return C.KEYS[category]
end
