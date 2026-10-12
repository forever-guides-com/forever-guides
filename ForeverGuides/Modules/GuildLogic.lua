-- Rules of the guild overview, no game calls: roster rows from GetGuildRosterInfo, sorting,
-- filters, "last online" text, note rights, statistics and the capped list of recently seen
-- players. Everything that touches the game lives in GuildData.lua and SeenPlayers.lua.
local _, ns = ...
local PN, U = ns.PlayerName, ns.U

local GL = {}
ns.GuildLogic = GL

-- Position of every value GetGuildRosterInfo returns (Retail order, not yet verified with a
-- guild member in the Forever client). The only place that knows the order.
GL.FIELD = {
  name = 1,
  rankName = 2,
  rankIndex = 3,
  level = 4,
  className = 5,
  zone = 6,
  note = 7,
  officerNote = 8,
  online = 9,
  status = 10,
  classFile = 11,
  guid = 17,
}

GL.MAX_SEEN = 300
GL.MAX_PEERS = 500
GL.PAGE_SIZE = 25
GL.SEEN_SORTS = { "name", "recent", "level", "class" }
-- Columns the page can show per tab; the name is always shown.
GL.COLUMNS = {
  guild = { "rank", "level", "zone", "ilvl", "jobs", "note", "last" },
  social = { "race", "class", "level", "zone", "ilvl", "jobs", "guild", "seen", "source" },
}
GL.SORTS = { "rank", "name", "level", "class", "zone", "online" }
GL.MOTD_LENGTH = 120
-- Rank index of a member whose rank the client did not report: sorts last.
local NO_RANK = 99

local function text(v)
  return type(v) == "string" and v or ""
end

local function num(v)
  v = tonumber(v)
  return v and v == v and v or nil
end

-- Roster ----------------------------------------------------------------------------------------

-- raw: the values of GetGuildRosterInfo(index) as a table; last: { years, months, days, hours } of
-- GetGuildRosterLastOnline(index) or nil. nil for a row without a name.
function GL.Normalize(index, raw, last)
  local F = GL.FIELD
  raw = type(raw) == "table" and raw or {}
  local name = PN.Normalize(text(raw[F.name]))
  if name == "" then
    return nil
  end
  local online = raw[F.online]
  local m = {
    index = index,
    name = name,
    key = PN.Lower(name),
    rankName = text(raw[F.rankName]),
    rank = num(raw[F.rankIndex]) or NO_RANK,
    level = num(raw[F.level]) or 0,
    className = text(raw[F.className]),
    class = text(raw[F.classFile]):upper(),
    zone = text(raw[F.zone]),
    note = text(raw[F.note]),
    officerNote = text(raw[F.officerNote]),
    online = online == true or online == 1,
    status = num(raw[F.status]) or 0,
    guid = type(raw[F.guid]) == "string" and raw[F.guid] or nil,
  }
  if not m.online and type(last) == "table" and (last[1] or last[2] or last[3] or last[4]) then
    local y, mo, d, h = num(last[1]) or 0, num(last[2]) or 0, num(last[3]) or 0, num(last[4]) or 0
    m.last = { years = y, months = mo, days = d, hours = h }
    m.ago = ((y * 365 + mo * 30 + d) * 24) + h
  end
  return m
end

-- "Online", "2 days ago", "unknown": `L` is the locale table.
function GL.LastOnlineText(m, L)
  if m.online then
    return L["guild.last.online"]
  end
  local t = m.last
  if not t then
    return L["guild.last.unknown"]
  end
  if t.years > 0 then
    return string.format(L["guild.last.years"], t.years)
  elseif t.months > 0 then
    return string.format(L["guild.last.months"], t.months)
  elseif t.days == 1 then
    return L["guild.last.day"]
  elseif t.days > 1 then
    return string.format(L["guild.last.days"], t.days)
  elseif t.hours >= 1 then
    return string.format(L["guild.last.hours"], t.hours)
  end
  return L["guild.last.lt1"]
end

-- Same wording for an age in seconds (recently seen list).
function GL.AgoText(seconds, L)
  local hours = math.floor(math.max(0, num(seconds) or 0) / 3600)
  local days = math.floor(hours / 24)
  local rest = days % 365
  return GL.LastOnlineText({
    online = false,
    last = { years = math.floor(days / 365), months = math.floor(rest / 30), days = rest % 30, hours = hours % 24 },
  }, L)
end

-- Sorting ---------------------------------------------------------------------------------------

local function compare(a, b)
  if a < b then
    return -1
  elseif a > b then
    return 1
  end
  return 0
end

local PRIMARY = {
  rank = function(a, b)
    return compare(a.rank, b.rank)
  end,
  name = function()
    return 0
  end,
  level = function(a, b)
    return compare(b.level, a.level)
  end,
  class = function(a, b)
    return compare(a.class, b.class)
  end,
  zone = function(a, b)
    return compare(PN.Lower(a.zone), PN.Lower(b.zone))
  end,
  online = function(a, b)
    if a.online ~= b.online then
      return a.online and -1 or 1
    end
    return compare(a.ago or math.huge, b.ago or math.huge)
  end,
}

-- In place; ties fall back to the name, so the order is stable between refreshes.
function GL.Sort(list, mode)
  local primary = PRIMARY[mode] or PRIMARY.rank
  table.sort(list, function(a, b)
    local c = primary(a, b)
    if c ~= 0 then
      return c < 0
    end
    return a.key < b.key
  end)
  return list
end

-- Filter ----------------------------------------------------------------------------------------

local function matches(m, needle, rights)
  for _, field in ipairs({ m.name, m.rankName, m.zone }) do
    if PN.Lower(field):find(needle, 1, true) then
      return true
    end
  end
  -- A note only counts when the player may see it.
  local note, officer = GL.VisibleNotes(m, rights)
  return (note ~= nil and PN.Lower(note):find(needle, 1, true) ~= nil)
    or (officer ~= nil and PN.Lower(officer):find(needle, 1, true) ~= nil)
end

-- f: online (bool), rank (rank index), class (token), minLevel, maxLevel, search (text),
-- rights (GL.Rights). Returns a new list.
function GL.Filter(list, f)
  f = f or {}
  local needle = PN.Lower(U.trim(f.search))
  local out = {}
  for _, m in ipairs(list) do
    if
      (not f.online or m.online)
      and (f.rank == nil or m.rank == f.rank)
      and (f.class == nil or f.class == "" or m.class == f.class)
      and (not f.minLevel or m.level >= f.minLevel)
      and (not f.maxLevel or m.level <= f.maxLevel)
      and (needle == "" or matches(m, needle, f.rights))
    then
      out[#out + 1] = m
    end
  end
  return out
end

-- Rights ----------------------------------------------------------------------------------------

-- read(name) answers true, false or nil (function missing). Only a clear yes shows a note.
function GL.Rights(read)
  return {
    publicNote = read("CanEditPublicNote") == true,
    officerNote = read("CanViewOfficerNote") == true,
  }
end

-- Public note, officer note: a string or nil when empty or not allowed.
function GL.VisibleNotes(m, rights)
  rights = rights or {}
  local note = rights.publicNote and m.note ~= "" and m.note or nil
  local officer = rights.officerNote and m.officerNote ~= "" and m.officerNote or nil
  return note, officer
end

-- Statistics ------------------------------------------------------------------------------------

-- { total, online, levels = { { lo, count } } ascending, classes = { { class, count } } by count }.
function GL.Stats(list)
  local s = { total = #list, online = 0, levels = {}, classes = {} }
  local byLevel, byClass = {}, {}
  for _, m in ipairs(list) do
    if m.online then
      s.online = s.online + 1
    end
    if m.level > 0 then
      local lo = math.floor(m.level / 10) * 10
      byLevel[lo] = (byLevel[lo] or 0) + 1
    end
    if m.class ~= "" then
      byClass[m.class] = (byClass[m.class] or 0) + 1
    end
  end
  for lo, count in pairs(byLevel) do
    s.levels[#s.levels + 1] = { lo = lo, count = count }
  end
  for class, count in pairs(byClass) do
    s.classes[#s.classes + 1] = { class = class, count = count }
  end
  table.sort(s.levels, function(a, b)
    return a.lo < b.lo
  end)
  table.sort(s.classes, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.class < b.class
  end)
  return s
end

-- "50-59" for a level bucket.
function GL.LevelRange(lo)
  return string.format("%d-%d", lo, lo + 9)
end

-- Cuts at `limit` characters (UTF-8 safe) and marks the cut.
function GL.Truncate(s, limit)
  s = text(s)
  local cut = PN.Cut(s, limit)
  return cut == s and s or cut .. "..."
end

-- Recently seen players ---------------------------------------------------------------------------

-- Drops entries that SavedVariables or an older version left malformed, in place. Returns the list.
function GL.CleanSeen(list)
  for i = #list, 1, -1 do
    local e = list[i]
    if type(e) ~= "table" or PN.Key(text(e.name)) == "" then
      table.remove(list, i)
    else
      e.name, e.zone, e.src = text(e.name), text(e.zone), text(e.src)
      e.class = text(e.class):upper()
      e.race, e.raceName, e.guid = text(e.race), text(e.raceName), type(e.guid) == "string" and e.guid or nil
      e.level, e.t = num(e.level) or 0, num(e.t) or 0
      e.guildName, e.guildRank, e.title = text(e.guildName), text(e.guildRank), text(e.title)
      e.pvp, e.honor = e.pvp == true, num(e.honor) or 0
      -- Entries of older versions have no first contact: what they hold is the best knowledge there is.
      local first = type(e.first) == "table" and e.first or {}
      e.first = { t = num(first.t) or e.t, src = text(first.src), zone = text(first.zone) }
      if e.first.src == "" and e.first.t == e.t then
        e.first.src, e.first.zone = e.src, e.zone
      end
      if type(e.who) == "table" then
        e.who = { t = num(e.who.t) or 0, zone = text(e.who.zone) }
      else
        e.who = nil
      end
    end
  end
  while #list > GL.MAX_SEEN do
    GL.SeenDropOldest(list)
  end
  return list
end

-- key -> entry lookup of a seen list.
function GL.SeenIndex(list)
  local index = {}
  for _, e in ipairs(list) do
    index[PN.Key(e.name)] = e
  end
  return index
end

-- guid -> entry lookup of a seen list (entries without a guid are not in it).
function GL.SeenGuidIndex(list)
  local guids = {}
  for _, e in ipairs(list) do
    if type(e.guid) == "string" then
      guids[e.guid] = e
    end
  end
  return guids
end

function GL.SeenDropOldest(list, index, guids)
  local oldest = 1
  for i, e in ipairs(list) do
    if e.t < list[oldest].t then
      oldest = i
    end
  end
  local gone = table.remove(list, oldest)
  if gone and index then
    index[PN.Key(gone.name)] = nil
  end
  if gone and guids and type(gone.guid) == "string" and guids[gone.guid] == gone then
    guids[gone.guid] = nil
  end
end

-- Refreshes an entry with what was seen now: time and place of the last sighting (e.t, e.zone) and the
-- current values. info: class, level, zone, race, raceName, guid, guildName, guildRank, title, pvp,
-- honor and src. A field that is nil or empty keeps its value, except the guild fields: a string (also
-- an empty one) is a reading, the player has no guild or title now. The first contact (e.first) and the
-- source (e.src) never change once they are set.
function GL.SeenUpdate(e, info, now)
  e.t = now
  if text(info.class) ~= "" then
    e.class = info.class:upper()
  end
  if (num(info.level) or 0) > 0 then
    e.level = num(info.level)
  end
  if text(info.zone) ~= "" then
    e.zone = info.zone
  end
  if text(info.src) ~= "" and e.src == "" then
    e.src = info.src
    e.first.src = info.src
  end
  if text(info.race) ~= "" then
    e.race = info.race
  end
  if text(info.raceName) ~= "" then
    e.raceName = info.raceName
  end
  if type(info.guid) == "string" then
    e.guid = info.guid
  end
  for _, field in ipairs({ "guildName", "guildRank", "title" }) do
    if type(info[field]) == "string" then
      e[field] = info[field]
    end
  end
  if type(info.pvp) == "boolean" then
    e.pvp = info.pvp
  end
  if num(info.honor) then
    e.honor = math.max(0, math.floor(num(info.honor)))
  end
end

-- Adds or refreshes a player (see SeenUpdate). A new entry remembers its first contact: source, time and
-- place. The list never grows beyond GL.MAX_SEEN, the oldest entry leaves first. guids is the optional
-- guid index that is kept in step. Returns the entry or nil for an empty name.
function GL.SeenAdd(list, index, info, now, guids)
  local key = PN.Key(text(info.name))
  if key == "" then
    return nil
  end
  local e = index[key]
  if not e then
    e = {
      name = PN.Normalize(info.name),
      class = "",
      level = 0,
      zone = "",
      src = "",
      race = "",
      raceName = "",
      guildName = "",
      guildRank = "",
      title = "",
      pvp = false,
      honor = 0,
      t = now,
      first = { t = now, src = text(info.src), zone = text(info.zone) },
    }
    list[#list + 1] = e
    index[key] = e
  end
  GL.SeenUpdate(e, info, now)
  if guids and type(e.guid) == "string" then
    guids[e.guid] = e
  end
  while #list > GL.MAX_SEEN do
    GL.SeenDropOldest(list, index, guids)
  end
  return e
end

-- f: race (token), class (token), search (part of the name). Returns a new list.
function GL.SeenFilter(list, f)
  f = f or {}
  local needle = PN.Lower(U.trim(f.search))
  local out = {}
  for _, e in ipairs(list) do
    if
      (f.race == nil or f.race == "" or e.race == f.race)
      and (f.class == nil or f.class == "" or e.class == f.class)
      and (needle == "" or PN.Lower(e.name):find(needle, 1, true))
    then
      out[#out + 1] = e
    end
  end
  return out
end

local SEEN_PRIMARY = {
  name = function()
    return 0
  end,
  recent = function(a, b)
    return compare(b.t, a.t)
  end,
  level = function(a, b)
    return compare(b.level, a.level)
  end,
  class = function(a, b)
    return compare(a.class, b.class)
  end,
}

-- In place; mode: name, recent (default), level, class. Ties fall back to the name.
function GL.SeenSort(list, mode)
  local primary = SEEN_PRIMARY[mode] or SEEN_PRIMARY.recent
  table.sort(list, function(a, b)
    local c = primary(a, b)
    if c ~= 0 then
      return c < 0
    end
    return PN.Lower(a.name) < PN.Lower(b.name)
  end)
  return list
end

-- Distinct values of one field of the list as { { value, label } } sorted by label, for a filter
-- dropdown. field: "race" (label from raceName) or "class" (label = token).
function GL.SeenChoices(list, field)
  local seen, out = {}, {}
  for _, e in ipairs(list) do
    local v = e[field]
    if v ~= "" and not seen[v] then
      seen[v] = true
      out[#out + 1] = { value = v, label = field == "race" and e.raceName ~= "" and e.raceName or v }
    end
  end
  table.sort(out, function(a, b)
    return a.label < b.label
  end)
  return out
end

-- One page of a list: items, the page number kept inside 1..pages, and the page count.
function GL.Page(list, page, size)
  size = size or GL.PAGE_SIZE
  local pages = math.max(1, math.ceil(#list / size))
  page = U.clamp(math.floor(num(page) or 1), 1, pages)
  local items = {}
  for i = (page - 1) * size + 1, math.min(#list, page * size) do
    items[#items + 1] = list[i]
  end
  return items, page, pages
end

-- "Trade on 10/09 in Orgrimmar" / "Handel am 09.10. in Orgrimmar": what is known about the first contact.
-- sourceText: the name of the source ("" when unknown), dateText: the date ("" when unknown).
function GL.FirstContactText(first, L, sourceText, dateText)
  local parts = {}
  if text(sourceText) ~= "" then
    parts[#parts + 1] = sourceText
  end
  if text(dateText) ~= "" then
    parts[#parts + 1] = string.format(L["guild.on"], dateText)
  end
  if type(first) == "table" and text(first.zone) ~= "" then
    parts[#parts + 1] = string.format(L["guild.in"], first.zone)
  end
  return table.concat(parts, " ")
end

-- Columns -----------------------------------------------------------------------------------------

-- cols: the stored table of one tab, id = false hides a column, everything else shows it.
function GL.ColumnOn(cols, id)
  return type(cols) ~= "table" or cols[id] ~= false
end

-- Passive facts of a seen player ---------------------------------------------------------------------

-- The title part of UnitPVPName ("Private Anna", "Anna the Insane") without the player's name, ""
-- without a title. The names to cut out are tried in order (full name, first name).
function GL.TitleOf(pvpName, ...)
  pvpName = text(pvpName)
  for i = 1, select("#", ...) do
    local name = text((select(i, ...)))
    local from, to = nil, nil
    if name ~= "" then
      from, to = pvpName:find(name, 1, true)
    end
    if from then
      local title = U.trim(pvpName:sub(1, from - 1) .. " " .. pvpName:sub(to + 1))
      return (title:gsub("^[,%s]+", ""):gsub("[,%s]+$", ""))
    end
  end
  return ""
end

-- "<Guild> (Rank)", "<Guild>" without a rank, "" without a guild.
function GL.GuildText(e)
  local name, rank = text(e.guildName), text(e.guildRank)
  if name == "" then
    return ""
  end
  return rank ~= "" and string.format("<%s> (%s)", name, rank) or string.format("<%s>", name)
end

-- Peers (item level and professions of other players) ----------------------------------------------

local PEER_SOURCES = { game = true, inspect = true, addon = true, manual = true }
GL.PEER_SOURCES = PEER_SOURCES

-- Validated profession list { { id, name, skill, max } }, at most 8, nil entries dropped.
function GL.CleanProfessions(list)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for _, p in ipairs(list) do
    local name = type(p) == "table" and text(p.name) or ""
    local skill, max = type(p) == "table" and num(p.skill or p.rank), type(p) == "table" and num(p.max)
    if name ~= "" and skill and max and skill >= 0 and max >= skill and #out < 8 then
      out[#out + 1] = { id = num(p.id), name = PN.Cut(name, 40), skill = math.floor(skill), max = math.floor(max) }
    end
  end
  return out
end

-- "-" while unknown.
function GL.IlvlText(peer)
  local v = peer and num(peer.ilvl)
  return v and v > 0 and tostring(math.floor(v + 0.5)) or "-"
end

-- "Smithing 74/150, Mining 20/150", "-" while unknown.
function GL.JobsText(peer)
  local parts = {}
  for _, p in ipairs(peer and peer.professions or {}) do
    parts[#parts + 1] = string.format("%s %d/%d", p.name, p.skill, p.max)
  end
  return #parts > 0 and table.concat(parts, ", ") or "-"
end

-- Age of peer data: "just now" and minutes first, then the wording of AgoText.
function GL.PeerAgeText(seconds, L)
  seconds = math.max(0, num(seconds) or 0)
  if seconds < 60 then
    return L["guild.peer.now"]
  elseif seconds < 3600 then
    return string.format(L["guild.peer.minutes"], math.floor(seconds / 60))
  end
  return GL.AgoText(seconds, L)
end

-- "As of 3 days ago, source: Game", nil without data.
function GL.PeerTip(peer, now, L)
  if not peer or not peer.at then
    return nil
  end
  local source = PEER_SOURCES[peer.source] and L["guild.peer.source." .. peer.source] or ""
  return string.format(L["guild.peer.tip"], GL.PeerAgeText((num(now) or 0) - peer.at, L), source)
end
