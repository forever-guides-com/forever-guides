-- Level brackets of the instance overview: which bracket an instance belongs to, the bracket filter ("my
-- level" included), the sections of the list (bracket headers, raids apart), the order inside them and the
-- difficulty color of a level range against the player. Pure logic: the only game access is UnitLevel, read
-- through pcall, and every rule takes the player level as a parameter so a test can fix it.
local _, ns = ...

ns.AddLocale("enUS", {
  ["instances.bracket.label"] = "Level range",
  ["instances.bracket.all"] = "All",
  ["instances.bracket.mine"] = "My level",
  ["instances.bracket.b10"] = "Level 10-19",
  ["instances.bracket.b20"] = "Level 20-29",
  ["instances.bracket.b30"] = "Level 30-39",
  ["instances.bracket.b40"] = "Level 40-49",
  ["instances.bracket.b50"] = "Level 50-60",
  ["instances.bracket.none"] = "Level unknown",
  ["instances.group.raid"] = "Raids",
  ["instances.group.fav"] = "Favorites",
  ["instances.group.all.one"] = "1 instance",
  ["instances.group.all.other"] = "%d instances",
  ["instances.group.dungeons.one"] = "1 dungeon",
  ["instances.group.dungeons.other"] = "%d dungeons",
  ["instances.group.raids.one"] = "1 raid",
  ["instances.group.raids.other"] = "%d raids",
  ["instances.group.open"] = "Collapse",
  ["instances.group.closed"] = "Expand",
  ["instances.order.desc"] = "Highest level first",
  ["instances.diff.grey"] = "Too easy for your level",
  ["instances.diff.green"] = "Easy for your level",
  ["instances.diff.yellow"] = "Fits your level",
  ["instances.diff.orange"] = "Hard for your level",
  ["instances.diff.red"] = "Much too hard for your level",
})

ns.AddLocale("deDE", {
  ["instances.bracket.label"] = "Stufenbereich",
  ["instances.bracket.all"] = "Alle",
  ["instances.bracket.mine"] = "Meine Stufe",
  ["instances.bracket.b10"] = "Stufe 10-19",
  ["instances.bracket.b20"] = "Stufe 20-29",
  ["instances.bracket.b30"] = "Stufe 30-39",
  ["instances.bracket.b40"] = "Stufe 40-49",
  ["instances.bracket.b50"] = "Stufe 50-60",
  ["instances.bracket.none"] = "Stufe unbekannt",
  ["instances.group.raid"] = "Raids",
  ["instances.group.fav"] = "Favoriten",
  ["instances.group.all.one"] = "1 Instanz",
  ["instances.group.all.other"] = "%d Instanzen",
  ["instances.group.dungeons.one"] = "1 Dungeon",
  ["instances.group.dungeons.other"] = "%d Dungeons",
  ["instances.group.raids.one"] = "1 Raid",
  ["instances.group.raids.other"] = "%d Raids",
  ["instances.group.open"] = "Einklappen",
  ["instances.group.closed"] = "Ausklappen",
  ["instances.order.desc"] = "Höchste Stufe zuerst",
  ["instances.diff.grey"] = "Zu leicht für deine Stufe",
  ["instances.diff.green"] = "Leicht für deine Stufe",
  ["instances.diff.yellow"] = "Passt zu deiner Stufe",
  ["instances.diff.orange"] = "Schwer für deine Stufe",
  ["instances.diff.red"] = "Viel zu schwer für deine Stufe",
})

local B = {}
ns.InstanceBracketLogic = B

local LL = ns.InstanceLevelLogic

-- The five brackets by their first level; a bracket ends at the next start minus one (the last at LEVEL_CAP).
B.STARTS = { 10, 20, 30, 40, 50 }
B.LEVEL_CAP = 60
-- Choices of the filter in the order of the control: "all", "mine" (the level of the player) or a bracket start.
B.CHOICES = { "all", "mine", "10", "20", "30", "40", "50" }
local VALID = {}
for _, id in ipairs(B.CHOICES) do
  VALID[id] = true
end

-- Sections that are no bracket: the favorites (first, when asked for), raids (last) and dungeons without any level.
B.RAID, B.NONE, B.FAV = "raid", "none", "fav"

-- Quest-like difficulty: the colors are the theme tokens of the list, the levels a bracket of five or more
-- levels above the player is red, three or four orange, a level beyond the green range below grey.
B.GREEN_RANGE = 8
B.COLORS = { grey = "textMuted", green = "success", yellow = "accent2", orange = "warning", red = "danger" }

local function whole(value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return math.floor(value)
end

-- The level of the player, a whole number from 1 up, else nil (the call fails or answers nonsense).
function B.PlayerLevel()
  local fn = rawget(_G, "UnitLevel")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, level = pcall(fn, "player")
  level = ok and whole(level) or nil
  return level and level >= 1 and level or nil
end

-- A saved or typed choice as a valid one, anything unknown is "all".
function B.Normalize(choice)
  choice = tostring(choice or "")
  return VALID[choice] and choice or "all"
end

-- Bracket of an instance as its start (10 to 50): the level it starts at (the end when only that is known),
-- levels below the first bracket count for it, levels above the last for the last. nil without any level.
function B.Of(inst)
  local from, to = LL.SortKey(inst)
  local level = from or to
  if not level then
    return nil
  end
  local start = B.STARTS[1]
  for _, s in ipairs(B.STARTS) do
    if level >= s then
      start = s
    end
  end
  return start
end

-- Section of an instance: "raid", the start of its bracket as text ("10") or "none".
function B.SectionOf(inst)
  if inst and inst.t == "raid" then
    return B.RAID
  end
  local start = B.Of(inst)
  return start and tostring(start) or B.NONE
end

-- True when the instance passes the bracket choice. "mine" needs the level of the player; without it
-- nothing is cut, so a client that cannot tell the level does not show an empty list.
function B.Matches(inst, choice, playerLevel)
  choice = B.Normalize(choice)
  if choice == "all" then
    return true
  elseif choice == "mine" then
    local level = whole(playerLevel)
    return level == nil or LL.Covers(inst, level)
  end
  return B.Of(inst) == tonumber(choice)
end

-- Difficulty of an instance for a player level: "grey", "green", "yellow", "orange" or "red"; nil when the
-- level of the player or the instance is not known.
function B.Difficulty(inst, playerLevel)
  local level = whole(playerLevel)
  local from, to = LL.SortKey(inst)
  from = from or to
  to = to or from
  if not (level and from) then
    return nil
  end
  if level < from then
    local diff = from - level
    return diff >= 5 and "red" or diff >= 3 and "orange" or "yellow"
  elseif level <= to then
    return "yellow"
  end
  return level - to <= B.GREEN_RANGE and "green" or "grey"
end

-- Theme token and the tooltip line of a difficulty (nil without one).
function B.DifficultyColor(difficulty)
  return difficulty and B.COLORS[difficulty] or nil
end

function B.DifficultyText(difficulty, L)
  L = L or ns.L
  return difficulty and L["instances.diff." .. difficulty] or nil
end

-- Order -------------------------------------------------------------------------------------------

local function nameKey(inst)
  return (ns.T(inst.n) or ""):lower()
end

-- Sort keys of the columns. A nil key (no level, no zone, no quest count) sorts last in both directions.
local KEYS = {
  name = function(inst)
    return nameKey(inst)
  end,
  zone = function(inst)
    local zone = ns.RefLogic.Names(inst.loc)
    return zone and zone ~= "" and zone:lower() or nil
  end,
}

-- Orders a copy of `list` by a column. sort: "name", "level", "zone" or "quests"; desc reverses the column, the
-- name stays the tie break in the other direction. questCount(inst) -> number or nil for the quest column.
function B.SortList(list, sort, desc, questCount)
  local ranked = {}
  for i, inst in ipairs(list) do
    local key, second
    if sort == "level" then
      key, second = LL.SortKey(inst)
    elseif sort == "quests" then
      key = questCount and questCount(inst) or nil
    else
      key = (KEYS[sort] or KEYS.name)(inst)
    end
    ranked[i] = { inst = inst, key = key, second = second, index = i, name = nameKey(inst) }
  end
  table.sort(ranked, function(a, b)
    if (a.key == nil) ~= (b.key == nil) then
      return a.key ~= nil
    end
    if a.key ~= b.key then
      if desc then
        return a.key > b.key
      end
      return a.key < b.key
    end
    if a.second ~= b.second then
      if (a.second == nil) ~= (b.second == nil) then
        return a.second ~= nil
      end
      if desc then
        return a.second > b.second
      end
      return a.second < b.second
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.index < b.index
  end)
  local out = {}
  for i, r in ipairs(ranked) do
    out[i] = r.inst
  end
  return out
end

-- Sections ----------------------------------------------------------------------------------------

-- The non-empty sections of an ordered list: { { key, kind, start, items, closed } }. With isFavorite(inst) the
-- favorites form the first section. Then the brackets in ascending or, with desc, descending order, the dungeons
-- without a level and the raids. The order inside a section is the order of `list`. closed is a set
-- { [key] = true } of collapsed sections.
function B.Sections(list, desc, closed, isFavorite)
  closed = type(closed) == "table" and closed or {}
  local by = {}
  for _, inst in ipairs(list) do
    local key = isFavorite and isFavorite(inst) and B.FAV or B.SectionOf(inst)
    by[key] = by[key] or {}
    table.insert(by[key], inst)
  end
  local keys = { B.FAV }
  for i = 1, #B.STARTS do
    keys[#keys + 1] = tostring(B.STARTS[desc and (#B.STARTS + 1 - i) or i])
  end
  keys[#keys + 1], keys[#keys + 2] = B.NONE, B.RAID
  local out = {}
  for _, key in ipairs(keys) do
    if by[key] then
      out[#out + 1] = {
        key = key,
        kind = key == B.RAID and "raid" or key == B.FAV and "mixed" or "dungeon",
        start = tonumber(key),
        items = by[key],
        closed = closed[key] == true,
      }
    end
  end
  return out
end

-- Title of a section ("Stufe 10-19", "Schlachtzüge", "Stufe unbekannt") and the count on its right.
function B.SectionTitle(section, L)
  L = L or ns.L
  if section.key == B.RAID then
    return L["instances.group.raid"]
  elseif section.key == B.FAV then
    return L["instances.group.fav"]
  elseif section.key == B.NONE then
    return L["instances.bracket.none"]
  end
  return L["instances.bracket.b" .. section.key]
end

function B.CountText(section, L)
  L = L or ns.L
  local n = #section.items
  local word = section.kind == "raid" and "raids" or section.kind == "mixed" and "all" or "dungeons"
  return string.format(L["instances.group." .. word .. "." .. (n == 1 and "one" or "other")], n)
end

-- A new set of collapsed sections with one section changed; the old table stays as it was.
function B.WithClosed(closed, key, on)
  local out = {}
  for k, v in pairs(type(closed) == "table" and closed or {}) do
    if v == true then
      out[k] = true
    end
  end
  out[key] = on and true or nil
  return out
end
