-- Pure logic of the reputation guide page (ReputationPage.lua): standings and their ranges, the ladder
-- of a faction, best ways and rewards per standing, the faction filter and the reading of the client.
-- Data shape: docs/RUF-FORMAT.md. Reputation values are absolute, like in the client.
local _, ns = ...

local RL = {}
ns.ReputationLogic = RL

local DEFAULT_MAX = 42999
local NEUTRAL = 4

-- Standing table entry by id (1 to 8), nil when unknown.
function RL.Standing(data, id)
  for _, s in ipairs(type(data) == "table" and data.standings or {}) do
    if s.id == id then
      return s
    end
  end
end

-- Standing that holds an absolute value and the points inside it: standing, offset (0 at its start).
-- Values beyond the table count to its first or last standing.
function RL.StandingAt(data, value)
  local list = type(data) == "table" and data.standings or {}
  if type(value) ~= "number" or #list == 0 then
    return nil
  end
  local pick = list[1]
  for _, s in ipairs(list) do
    if value >= s.min then
      pick = s
    end
  end
  return pick, math.max(0, math.min(value, pick.max) - pick.min)
end

-- Points a standing spans ("Friendly 0 to 6000").
function RL.Span(standing)
  return standing.max - standing.min + 1
end

-- Absolute value at the start of the character: the race entry of startBy, else start, else neutral.
function RL.StartValue(section, raceId)
  local by = type(section.startBy) == "table" and raceId and section.startBy[raceId]
  return type(by) == "number" and by or type(section.start) == "number" and section.start or 0
end

function RL.MaxValue(section)
  return type(section.max) == "number" and section.max or DEFAULT_MAX
end

-- Standings from the start of the faction to its maximum, as table entries.
function RL.Ladder(data, section, raceId)
  local first = RL.StandingAt(data, RL.StartValue(section, raceId))
  local last = RL.StandingAt(data, RL.MaxValue(section))
  local out = {}
  if first and last then
    for id = first.id, math.max(first.id, last.id) do
      out[#out + 1] = RL.Standing(data, id)
    end
  end
  return out
end

-- "Neutral" or "Neutral 500" for a lower bound.
local function point(data, value, name, fmt)
  local s, offset = RL.StandingAt(data, value)
  if not s then
    return nil
  end
  return offset == 0 and name(s) or string.format(fmt.point, name(s), offset)
end

-- Reputation range of a way as standing names and points, never as absolute values. min is the
-- first value with reputation, max the last one (both included). fmt: range, from, to (each with %s) and
-- point ("%s %d"); name(standing) gives the localized standing name. nil without any bound.
function RL.RangeText(data, min, max, name, fmt)
  local lo = type(min) == "number" and point(data, min, name, fmt) or nil
  local hi
  if type(max) == "number" then
    -- A maximum right before a standing starts reads as that standing without points.
    local nextS = RL.StandingAt(data, max + 1)
    local s, offset = RL.StandingAt(data, max)
    if nextS and nextS.min == max + 1 then
      hi = name(nextS)
    elseif s then
      hi = string.format(fmt.point, name(s), offset)
    end
  end
  if lo and hi then
    return string.format(fmt.range, lo, hi)
  elseif lo then
    return string.format(fmt.from, lo)
  elseif hi then
    return string.format(fmt.to, hi)
  end
  return nil
end

-- Best ways of a standing: the rows named in section.best[standing], filtered by side. Rows without a
-- confirmed flag stay in, the page marks them.
function RL.Ways(section, standingId, side, matches)
  local out = {}
  local rows = type(section.rows) == "table" and section.rows or {}
  local best = type(section.best) == "table" and section.best[standingId] or {}
  for _, index in ipairs(best) do
    local row = rows[index]
    if row and matches(row.faction, side) then
      out[#out + 1] = row
    end
  end
  return out
end

-- Rewards released at a standing. Items below the first standing of the ladder count to it.
function RL.Rewards(section, standingId, firstId)
  local out = {}
  for _, r in ipairs(type(section.rewards) == "table" and section.rewards or {}) do
    local tier = type(r.tier) == "number" and r.tier or 1
    if tier == standingId or (standingId == firstId and tier < firstId) then
      out[#out + 1] = r
    end
  end
  return out
end

-- Vendors of a reward as { id, vendor } in the order of the reward, unknown ids skipped.
function RL.Vendors(section, reward)
  local out = {}
  for _, id in ipairs(type(reward.v) == "table" and reward.v or {}) do
    local vendor = type(section.vendors) == "table" and section.vendors[id]
    if vendor then
      out[#out + 1] = { id = id, vendor = vendor }
    end
  end
  return out
end

-- Every vendor of the faction once, sorted by name.
function RL.AllVendors(section, lang)
  local out = {}
  for id, vendor in pairs(type(section.vendors) == "table" and section.vendors or {}) do
    out[#out + 1] = { id = id, vendor = vendor }
  end
  table.sort(out, function(a, b)
    local an, bn = a.vendor[lang] or a.vendor.en or "", b.vendor[lang] or b.vendor.en or ""
    return an ~= bn and an < bn or (an == bn and a.id < b.id)
  end)
  return out
end

-- Factions ----------------------------------------------------------------------------------------------

local function groupOrder(data)
  local order = {}
  for i, g in ipairs(type(data.groups) == "table" and data.groups or {}) do
    order[g.id] = i
  end
  return order
end

-- Sections in the order of the groups, then by name. title(section) gives the localized name.
function RL.Sort(data, sections, title)
  local order = groupOrder(data)
  local out = {}
  for i, s in ipairs(sections) do
    out[i] = s
  end
  table.sort(out, function(a, b)
    local ga, gb = order[a.group] or 99, order[b.group] or 99
    if ga ~= gb then
      return ga < gb
    end
    local ta, tb = title(a) or "", title(b) or ""
    if ta ~= tb then
      return ta < tb
    end
    return a.fid < b.fid
  end)
  return out
end

local function haystack(section)
  local t = section.title
  return type(t) == "table" and ((t.de or "") .. " " .. (t.en or "")) or tostring(t or "")
end

-- Filter of the faction list. f: group ("all" or an id), side ("all", "A", "H"), query, known (only
-- factions the client reports as known, readings[fid] set), readings, matches(rowSide, side),
-- words(query) and match(text, word) (default: plain, case-insensitive).
function RL.Filter(sections, f)
  local words = f.words and f.words(f.query) or {}
  local match = f.match or function(text, word)
    return text:lower():find(word:lower(), 1, true) ~= nil
  end
  local out = {}
  for _, s in ipairs(sections) do
    local ok = (f.group == nil or f.group == "all" or s.group == f.group) and f.matches(s.side, f.side)
    if ok and f.known then
      ok = f.readings ~= nil and f.readings[s.fid] ~= nil and f.readings[s.fid].known == true
    end
    if ok then
      local text = haystack(s)
      for _, word in ipairs(words) do
        if not match(text, word) then
          ok = false
          break
        end
      end
    end
    if ok then
      out[#out + 1] = s
    end
  end
  return out
end

-- Client reading ----------------------------------------------------------------------------------------

-- Reading of one faction from the client values: standing id, bar start and value. The position inside
-- the standing is value - barMin, so absolute and relative bar values give the same answer. known
-- follows the character statistics: a standing other than neutral or points inside neutral.
-- Returns { standing, offset, span, known } or nil.
function RL.Reading(data, standingId, barMin, value)
  local s = RL.Standing(data, standingId)
  if not s or type(barMin) ~= "number" or type(value) ~= "number" then
    return nil
  end
  local offset = math.max(0, math.min(value - barMin, RL.Span(s) - 1))
  return {
    standing = s,
    offset = offset,
    span = RL.Span(s),
    known = s.id ~= NEUTRAL or offset > 0,
  }
end

-- Detail ------------------------------------------------------------------------------------------------

-- Flat list of the detail view, top to bottom: per standing of the ladder a head ({ kind = "head",
-- standing, current }), its best ways ({ kind = "way", row }) and rewards ({ kind = "reward", reward,
-- vendors }), then the vendors ({ kind = "vendorHead" }, { kind = "vendor", id, vendor }). A faction
-- without ways starts with { kind = "note" } ("data follows") and lists only the standings that have
-- rewards. o: side, raceId, matches(rowSide, side), currentId (standing of the character), lang.
function RL.Items(data, section, o)
  local items = {}
  local ladder = RL.Ladder(data, section, o.raceId)
  local hasRows = type(section.rows) == "table" and #section.rows > 0
  if not hasRows then
    items[1] = { kind = "note" }
  end
  local firstId = ladder[1] and ladder[1].id
  for _, s in ipairs(ladder) do
    local ways = hasRows and RL.Ways(section, s.id, o.side, o.matches) or {}
    local rewards = RL.Rewards(section, s.id, firstId)
    if #ways > 0 or #rewards > 0 or hasRows then
      items[#items + 1] = { kind = "head", standing = s, current = o.currentId == s.id }
      for _, row in ipairs(ways) do
        items[#items + 1] = { kind = "way", row = row }
      end
      for _, r in ipairs(rewards) do
        items[#items + 1] = { kind = "reward", reward = r, vendors = RL.Vendors(section, r) }
      end
    end
  end
  local vendors = RL.AllVendors(section, o.lang or "en")
  if #vendors > 0 then
    items[#items + 1] = { kind = "vendorHead" }
    for _, v in ipairs(vendors) do
      items[#items + 1] = { kind = "vendor", id = v.id, vendor = v.vendor }
    end
  end
  return items
end
