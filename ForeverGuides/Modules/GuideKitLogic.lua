-- Shared logic of the guide pages (group "guides"), pure and free of game API. Every guide keeps its
-- content in a load-on-demand data add-on that fills ns.GuideData[<guide id>] (docs/ARCHITEKTUR.md,
-- "Guides"). Shape of that table:
--   { v = 1, sections = { { id, title = {de, en}, note = {de, en}, confirmed = bool,
--       rows = { { min, max, faction = "A"|"H"|nil, target, zone (each {de, en} or text),
--                  map, x, y, confirmed = bool, objects = { gathering object ids },
--                  item = item id, quest = quest id (collection status, see GL.CollectionStatus) } } } }
-- A section without rows is shown as "data follows". A row counts as confirmed for Forever only
-- when it (or else its section) says confirmed = true.
local _, ns = ...

local GL = { SCHEMA = 1 }
ns.GuideKitLogic = GL

-- Guide id -> data add-on. The add-ons are optional: a missing one is the "data follows" state.
GL.GUIDES = {
  lockpicking = { addon = "ForeverGuides_Lockpicking" },
  comprehension = { addon = "ForeverGuides_Comprehension" },
  reputation = { addon = "ForeverGuides_Reputation" },
  itemsets = { addon = "ForeverGuides_Itemsets" },
}

GL.STATUS = { loaded = "loaded", missing = "missing", disabled = "disabled", empty = "empty" }

-- Data of an add-on that loaded but does not match the schema counts as no data at all.
function GL.IsValid(data)
  return type(data) == "table" and data.v == GL.SCHEMA and type(data.sections) == "table"
end

-- pkgState is the state from ns.PackageUI.State ("missing", "off", "idle", "ready"). Usable data wins
-- over everything, so a stale state never hides a guide that is there.
function GL.Status(pkgState, data)
  if GL.IsValid(data) then
    return GL.STATUS.loaded
  elseif pkgState == "missing" then
    return GL.STATUS.missing
  elseif pkgState == "off" then
    return GL.STATUS.disabled
  end
  return GL.STATUS.empty
end

-- Filter value for the faction of the player ("A", "H", anything else when unknown): the own
-- faction, else all.
function GL.DefaultFaction(playerFaction)
  return (playerFaction == "A" or playerFaction == "H") and playerFaction or "all"
end

-- A row without faction (or "both") is valid for both sides.
function GL.MatchesFaction(rowFaction, filter)
  if filter == nil or filter == "all" or rowFaction == nil or rowFaction == "both" then
    return true
  end
  return rowFaction == filter
end

function GL.FilterRows(rows, filter)
  local out = {}
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if GL.MatchesFaction(row.faction, filter) then
      out[#out + 1] = row
    end
  end
  return out
end

function GL.HasRows(section)
  return type(section) == "table" and type(section.rows) == "table" and #section.rows > 0
end

-- Unconfirmed is the default: nothing is shown as verified unless the data says so.
function GL.IsConfirmed(row, section)
  if type(row) == "table" and type(row.confirmed) == "boolean" then
    return row.confirmed
  end
  return type(section) == "table" and section.confirmed == true
end

-- "75", "1-75" or "300+" (no upper end); nil without a lower end.
function GL.RangeText(min, max)
  if type(min) ~= "number" then
    return nil
  elseif type(max) ~= "number" then
    return min .. "+"
  elseif max == min then
    return tostring(min)
  end
  return min .. "-" .. max
end

-- Waypoint place for the map buttons, nil without a usable map and position.
function GL.Place(row, label)
  if type(row) ~= "table" or type(row.map) ~= "number" then
    return nil
  end
  local x, y = row.x, row.y
  if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then
    return nil
  end
  return { map = row.map, x = x, y = y, label = label }
end

-- Ids of the chest kinds of a row (gathering object ids, ForeverGuides_Gathering), nil without any.
function GL.ObjectIds(row)
  local out, seen = {}, {}
  for _, id in ipairs(type(row) == "table" and type(row.objects) == "table" and row.objects or {}) do
    if type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return #out > 0 and out or nil
end

-- Map to open for the chests of a row: the map of the row, else the one the player stands in.
function GL.TargetMap(row, playerMap)
  if type(row) == "table" and type(row.map) == "number" then
    return row.map
  end
  return type(playerMap) == "number" and playerMap or nil
end

-- Skill and maximum of the skill line called one of names (any language, case blind) in lines
-- { name, skill, max }; nil when the character does not have it.
function GL.FindSkill(lines, names)
  local wanted = {}
  for _, name in ipairs(names) do
    wanted[string.lower(name)] = true
  end
  for _, line in ipairs(type(lines) == "table" and lines or {}) do
    if type(line.name) == "string" and wanted[string.lower(line.name)] and type(line.skill) == "number" then
      return line.skill, type(line.max) == "number" and line.max or nil
    end
  end
  return nil
end

-- State of a bracket against the value of the player (skill or level): "done" at or above the upper end,
-- "current" inside, "upcoming" below the lower end. A bracket without upper end is "open" once reached.
function GL.RowState(value, min, max)
  if type(value) ~= "number" or type(min) ~= "number" then
    return nil
  elseif value < min then
    return "upcoming"
  elseif type(max) ~= "number" then
    return "open"
  end
  return value >= max and "done" or "current"
end

-- Share of a bracket already passed (0 to 1); nil for a bracket without a usable span.
function GL.Progress(value, min, max)
  if type(value) ~= "number" or type(min) ~= "number" or type(max) ~= "number" or max <= min then
    return nil
  end
  return math.min(1, math.max(0, (value - min) / (max - min)))
end

-- The step to do next: the first current bracket of the sections in order, one with a position before
-- one without. kindOf(section) names what the range of a section measures ("skill", "level" or nil),
-- values holds the player's value per kind. Returns the section index and the row, nil without one.
function GL.NextStep(sections, kindOf, values, filter)
  for i, section in ipairs(sections) do
    local kind = kindOf(section)
    local first
    for _, row in ipairs(GL.FilterRows(section.rows, filter)) do
      if kind and GL.RowState(values[kind], row.min, row.max) == "current" then
        if GL.Place(row) then
          return i, row
        end
        first = first or row
      end
    end
    if first then
      return i, first
    end
  end
  return nil
end

-- Row state per collection status: a handed in entry is done, one the player carries is the one to act on.
GL.COLLECT_STATE = { handed = "done", read = "done", bag = "current", bank = "current", missing = "open", open = "open" }

-- Status of a row that tracks an item and/or a quest, nil for any other row. probe = { quest = function(id) -> bool,
-- count = function(id, withBank) -> number, marked = optional function(row) -> bool }. "handed" (quest done),
-- "read" (the player marked the row), "bag", "bank" (item only in the bank), "missing", or "open" for a row with
-- a quest but no item. A marked row counts as done in the list and stays out of the handed in totals.
function GL.CollectionStatus(row, probe)
  if type(row) ~= "table" or type(probe) ~= "table" then
    return nil
  end
  local quest, item = row.quest, row.item
  if type(quest) ~= "number" and type(item) ~= "number" then
    return nil
  elseif type(quest) == "number" and probe.quest(quest) then
    return "handed"
  elseif type(probe.marked) == "function" and probe.marked(row) then
    return "read"
  elseif type(item) ~= "number" then
    return "open"
  elseif (probe.count(item, false) or 0) > 0 then
    return "bag"
  end
  return (probe.count(item, true) or 0) > 0 and "bank" or "missing"
end

-- Handed in and total of the collection entries of a row list. Only rows with an item count; a row with just a
-- quest shows its status and stays out of the totals.
function GL.CollectionTotals(rows, probe)
  local handed, total = 0, 0
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if type(row.item) == "number" then
      total = total + 1
      if GL.CollectionStatus(row, probe) == "handed" then
        handed = handed + 1
      end
    end
  end
  return handed, total
end
