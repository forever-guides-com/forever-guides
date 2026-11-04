-- Pure logic of the guild member display on the maps: the clamped display settings, the filter, the climb
-- up the map parents when a member stands on a map the shown one has no rectangle for, grouping of
-- members that lie close together and the look of a symbol. No frames, no game calls except the settings
-- read in GLG.Current. The world map pins (WorldMapGuildPins.lua) and the minimap source use it.
local _, ns = ...

local GLG = {}
ns.WorldMapGuildLogic = GLG

-- Option name -> { settings key, default, low, high }. A boolean has no range. Store.defaults holds the
-- same defaults (a test compares them).
GLG.SPEC = {
  showWorld = { "guildMapShowWorld", true },
  showMini = { "guildMapShowMini", true },
  worldSize = { "guildMapWorldSize", 100, 50, 200 },
  miniSize = { "guildMapMiniSize", 100, 50, 200 },
  showClass = { "guildMapShowClass", true },
  showRank = { "guildMapShowRank", false },
  showLevel = { "guildMapShowLevel", false },
  showName = { "guildMapShowName", false },
  group = { "guildMapGroup", true },
  minLevel = { "guildMapMinLevel", 1, 1, 100 },
  maxLevel = { "guildMapMaxLevel", 100, 1, 100 },
  rankFilter = { "guildMapRankFilter", -1, -1, 9 },
  onlineOnly = { "guildMapOnlineOnly", true },
}

GLG.MAX_CLIMB = 4
GLG.MAX_RANK = 9

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- One option from the raw settings value: a missing or damaged value is the default, a number is rounded
-- and held inside its range.
function GLG.Clamp(name, raw)
  local spec = GLG.SPEC[name]
  if not spec then
    return nil
  end
  local default, low, high = spec[2], spec[3], spec[4]
  if type(default) == "boolean" then
    if type(raw) == "boolean" then
      return raw
    end
    return default
  end
  if not finite(raw) then
    return default
  end
  return math.max(low, math.min(high, math.floor(raw + 0.5)))
end

-- All options from a settings table (nil reads the defaults). The highest level never lies under the lowest.
function GLG.Options(settings)
  settings = type(settings) == "table" and settings or {}
  local out = {}
  for name, spec in pairs(GLG.SPEC) do
    out[name] = GLG.Clamp(name, settings[spec[1]])
  end
  out.maxLevel = math.max(out.maxLevel, out.minLevel)
  return out
end

-- The other end of the level range after `name` (minLevel or maxLevel) was set to `value`: the value it
-- has to take so the range does not turn around, nil when it can stay. `other` is its stored value.
function GLG.Partner(name, value, other)
  if not finite(other) then
    return nil
  end
  if name == "minLevel" and other < value then
    return value
  end
  if name == "maxLevel" and other > value then
    return value
  end
  return nil
end

-- The options of the player's settings, clamped.
function GLG.Current()
  return GLG.Options(ns.db and ns.db.settings)
end

-- Symbol edge in pixels for a base size and a percent value of the size option.
function GLG.Size(base, percent)
  return math.max(1, math.floor(base * GLG.Clamp("worldSize", percent) / 100 + 0.5))
end

-- Marks above a symbol for the rank: the guild master three, the next rank two, the one after that one.
function GLG.RankTicks(rank)
  if not finite(rank) or rank < 0 or rank > 2 then
    return 0
  end
  return 3 - rank
end

-- Does a member pass the filter? `member`: known (the guild list has the member), level, rank, online.
-- What the guild list does not tell passes: a member of the list that is not known yet is not hidden
-- by a filter on facts nobody has.
function GLG.Passes(opts, member)
  if not member.known then
    return true
  end
  if opts.onlineOnly and member.online ~= true then
    return false
  end
  local level = member.level
  if finite(level) and level > 0 and (level < opts.minLevel or level > opts.maxLevel) then
    return false
  end
  if opts.rankFilter >= 0 and finite(member.rank) and member.rank > opts.rankFilter then
    return false
  end
  return true
end

-- Place of a point on the shown map (`shown`, map type `kind`): nx, ny (0..1) and whether it is only
-- approximate. The point of map `from` itself when `project(from, x, y, shown, kind)` can place it. Else the
-- climb: the middle of the first map up the parent chain (at most MAX_CLIMB steps, `parentOf(id)`) that
-- can be placed, approximate. A position of "zone only" (x nil) starts the climb at its own map. nil
-- when nothing in the chain fits (a map without parents or rectangle: the pin falls away).
function GLG.Resolve(from, x, y, shown, kind, project, parentOf)
  if x ~= nil and y ~= nil then
    local px, py = project(from, x, y, shown, kind)
    if px then
      return px, py, false
    end
  end
  local id = from
  for step = 0, GLG.MAX_CLIMB do
    if step > 0 then
      id = parentOf(id)
      if not finite(id) or id <= 0 then
        return nil
      end
    end
    if step > 0 or x == nil or y == nil then
      local px, py = project(id, 0.5, 0.5, shown, kind)
      if px then
        return px, py, true
      end
    end
  end
  return nil
end

-- Symbol shape and fill: a diamond for an approximate place, a hexagon for an exact one; hollow (a ring)
-- for a position that is older than the current window or did not match the last one.
function GLG.Style(approx, state, check)
  return { shape = approx and "diamond" or "hexagon", hollow = state ~= "current" or check == "jump" }
end

-- Seconds as a number and unit ("s" or "min") for "n s ago".
function GLG.AgeParts(age)
  if not finite(age) or age < 0 then
    age = 0
  end
  age = math.floor(age)
  if age < 120 then
    return age, "s"
  end
  return math.floor(age / 60), "min"
end

-- The short name of a member (without the realm).
function GLG.ShortName(name)
  return (tostring(name or ""):match("^([^%-]+)")) or ""
end

-- The label beside a symbol: name and level as the options ask, "" for none.
function GLG.Label(opts, name, level)
  local parts = {}
  if opts.showName then
    parts[#parts + 1] = GLG.ShortName(name)
  end
  if opts.showLevel and finite(level) and level > 0 then
    parts[#parts + 1] = tostring(level)
  end
  return table.concat(parts, " ")
end

-- Groups items { key, px, py } (pixels on the screen) whose symbols would touch: an item joins the first
-- group whose centre lies within `radius`, else it starts one. Sorted by key first, so the result does not
-- depend on the order of the input. Without grouping every item is a group of its own. Returns a list of
-- { px, py (centre), items }.
function GLG.Group(items, radius, grouping)
  local sorted = {}
  for i, item in ipairs(items) do
    sorted[i] = item
  end
  table.sort(sorted, function(a, b)
    return a.key < b.key
  end)
  local groups = {}
  for _, item in ipairs(sorted) do
    local target
    if grouping then
      for _, g in ipairs(groups) do
        local dx, dy = g.px - item.px, g.py - item.py
        if dx * dx + dy * dy <= radius * radius then
          target = g
          break
        end
      end
    end
    if target then
      local n = #target.items
      target.items[n + 1] = item
      target.px = (target.px * n + item.px) / (n + 1)
      target.py = (target.py * n + item.py) / (n + 1)
    else
      groups[#groups + 1] = { px = item.px, py = item.py, items = { item } }
    end
  end
  return groups
end
