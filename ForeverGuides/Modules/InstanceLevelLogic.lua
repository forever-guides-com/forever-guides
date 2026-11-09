-- Level display of instances: the range from to, the entry level and the named gap. Pure logic, no game access.
-- The sources are an instance of Data.Instances or a map marker built from one (fields lv, ml, rl). lv is
-- "a-b" (both sides), "a" (the start only) or "-b" (the end only); a missing lv is a gap, never an empty spot.
local _, ns = ...

ns.AddLocale("enUS", {
  ["instances.level.range"] = "Level %d to %d",
  ["instances.level.fromOnly"] = "Level %d to ?",
  ["instances.level.toOnly"] = "Level ? to %d",
  ["instances.level.unknown"] = "Level not recorded",
  ["instances.level.entry"] = "Entry from level %d",
  ["instances.level.recommended"] = "recommended from level %d",
  ["instances.announced"] = "announced",
  ["instances.announced.tip"] = "Announced, not reachable in the game yet.",
  ["instances.level.gap.to"] = "Upper level not recorded.",
  ["instances.level.gap.from"] = "Lower level not recorded.",
  ["instances.level.gap.both"] = "Level range not recorded.",
  ["instances.level.gap.estimated"] = "Only the recommended level is known, the upper level is not recorded.",
})

ns.AddLocale("deDE", {
  ["instances.level.range"] = "Stufe %d bis %d",
  ["instances.level.fromOnly"] = "Stufe %d bis ?",
  ["instances.level.toOnly"] = "Stufe ? bis %d",
  ["instances.level.unknown"] = "Stufe nicht erfasst",
  ["instances.level.entry"] = "Eintritt ab Stufe %d",
  ["instances.level.recommended"] = "empfohlen ab Stufe %d",
  ["instances.announced"] = "angekündigt",
  ["instances.announced.tip"] = "Angekündigt, im Spiel noch nicht erreichbar.",
  ["instances.level.gap.to"] = "Obergrenze der Stufe nicht erfasst.",
  ["instances.level.gap.from"] = "Untergrenze der Stufe nicht erfasst.",
  ["instances.level.gap.both"] = "Stufenbereich nicht erfasst.",
  ["instances.level.gap.estimated"] = "Nur die empfohlene Stufe ist bekannt, die Obergrenze ist nicht erfasst.",
})

local LL = {}
ns.InstanceLevelLogic = LL

-- Order of the faction groups: Alliance, Horde, both.
LL.FACTIONS = { "A", "H", "B" }
local RANK = { A = 1, H = 2, B = 3 }

-- Instances announced without any confirmed number: independent of what the generated data holds.
local ANNOUNCED = { ["Barrow Deeps"] = true }

-- True for an instance the data lists but nobody can reach yet and whose numbers are not confirmed: the flag
-- `announced` of the data or the list above. Such an instance has no level range and no map pin.
function LL.Unconfirmed(src)
  if type(src) ~= "table" then
    return false
  end
  local name = src.n and src.n.en or type(src.name) == "table" and src.name.en
  return src.announced == true or (name ~= nil and ANNOUNCED[name] == true)
end

-- True for an instance that is announced only (status "announced", or unconfirmed): it gets the mark and no
-- entry level.
function LL.Announced(src)
  return type(src) == "table" and (src.st == "announced" or LL.Unconfirmed(src))
end

local function whole(value)
  local n = tonumber(value)
  if n and n >= 0 and n == math.floor(n) then
    return n
  end
end

-- from, to of a level text or number. Either side is nil when the data does not hold it; nothing readable gives
-- nil, nil (so does a range whose start lies above its end).
function LL.Parse(value)
  if type(value) == "number" then
    return whole(value), nil
  end
  if type(value) ~= "string" then
    return nil, nil
  end
  local text = value:gsub("\226\128[\147\148]", "-"):gsub("%s+", "")
  local a, b = text:match("^(%d+)%-(%d+)$")
  if a then
    a, b = tonumber(a), tonumber(b)
    if a > b then
      return nil, nil
    end
    return a, b
  end
  a = text:match("^(%d+)[%-+]?$")
  if a then
    return tonumber(a), nil
  end
  b = text:match("^%-(%d+)$")
  if b then
    return nil, tonumber(b)
  end
  return nil, nil
end

-- { from, to, entry, recommended, estimated, gap, text, gapText, entryText, recommendedText, announced,
-- announcedText, announcedTip } of a source.
-- gap is nil for a full range, else "to" (end missing), "from" (start missing) or "both". Without lv the
-- recommended level (rl) stands in as the start and `estimated` is true. L defaults to ns.L.
local function read(src)
  src = src or {}
  local from, to = LL.Parse(src.lv)
  if LL.Unconfirmed(src) then
    return nil, nil, nil, nil, false
  end
  local rl = whole(src.rl)
  local estimated = false
  if from == nil and to == nil and rl then
    from, estimated = rl, true
  end
  local entry = not LL.Announced(src) and whole(src.ml) or nil
  if entry == 0 then
    entry = nil
  end
  return from, to, entry, rl, estimated
end

function LL.Of(src, L)
  L = L or ns.L
  local from, to, entry, rl, estimated = read(src)
  local out = { from = from, to = to, entry = entry, estimated = estimated }
  if LL.Announced(src) then
    out.announced = true
    out.announcedText = L["instances.announced"]
    out.announcedTip = L["instances.announced.tip"]
  end
  if from and to then
    out.text = string.format(L["instances.level.range"], from, to)
  elseif from then
    out.gap = "to"
    out.text = string.format(L["instances.level.fromOnly"], from)
    out.gapText = L[estimated and "instances.level.gap.estimated" or "instances.level.gap.to"]
  elseif to then
    out.gap = "from"
    out.text = string.format(L["instances.level.toOnly"], to)
    out.gapText = L["instances.level.gap.from"]
  else
    out.gap = "both"
    out.text = L["instances.level.unknown"]
    out.gapText = L["instances.level.gap.both"]
  end
  if entry then
    out.entryText = string.format(L["instances.level.entry"], entry)
  end
  if rl and not estimated then
    out.recommended = rl
    out.recommendedText = string.format(L["instances.level.recommended"], rl)
  end
  return out
end

-- Sort key of a source: from, to. Both nil for an unknown level.
function LL.SortKey(src)
  local from, to = read(src)
  return from, to
end

-- True when a sorts before b by level: start, then end (a missing end after a known one); a source without any
-- level sorts after every other. Equal keys are neither before nor after.
function LL.Before(a, b)
  local fa, ta = LL.SortKey(a)
  local fb, tb = LL.SortKey(b)
  if fa ~= fb then
    return (fa or math.huge) < (fb or math.huge)
  end
  if ta ~= tb then
    return (ta or math.huge) < (tb or math.huge)
  end
  return false
end

-- Faction of a source as "A", "H" or "B" (anything else counts for both).
function LL.Faction(src)
  local f = src and src.f
  return RANK[f] and f or "B"
end

-- True when the level n lies in the range or equals the entry level.
function LL.Covers(src, n)
  local from, to = LL.SortKey(src)
  if from and n >= from and n <= (to or from) then
    return true
  end
  if to and not from and n <= to then
    return true
  end
  local entry = whole(src and src.ml)
  return entry ~= nil and entry == n
end

-- A query of digits only ("40") as a number, else nil.
function LL.QueryLevel(query)
  local text = tostring(query or ""):match("^%s*(%d+)%s*$")
  return text and tonumber(text) or nil
end

-- Sorts `list` in place: by faction group (A, H, B) when byFaction, then by level, then by `tie(a, b)`.
function LL.Sort(list, byFaction, byLevel, tie)
  table.sort(list, function(a, b)
    if byFaction then
      local ra, rb = RANK[LL.Faction(a)], RANK[LL.Faction(b)]
      if ra ~= rb then
        return ra < rb
      end
    end
    if byLevel then
      if LL.Before(a, b) then
        return true
      end
      if LL.Before(b, a) then
        return false
      end
    end
    return tie(a, b)
  end)
  return list
end

-- The non-empty faction groups of a list in A, H, B order: { { faction, items } }.
function LL.Groups(list)
  local by, out = {}, {}
  for _, item in ipairs(list) do
    local f = LL.Faction(item)
    if not by[f] then
      by[f] = { faction = f, items = {} }
    end
    table.insert(by[f].items, item)
  end
  for _, f in ipairs(LL.FACTIONS) do
    if by[f] then
      out[#out + 1] = by[f]
    end
  end
  return out
end

-- { A, H, B, total, gaps } of a list: items per faction group and how many have no full level range.
function LL.Count(list)
  local count = { A = 0, H = 0, B = 0, total = 0, gaps = 0 }
  for _, item in ipairs(list) do
    local f = LL.Faction(item)
    count[f] = count[f] + 1
    count.total = count.total + 1
    local from, to = LL.SortKey(item)
    if not (from and to) then
      count.gaps = count.gaps + 1
    end
  end
  return count
end
