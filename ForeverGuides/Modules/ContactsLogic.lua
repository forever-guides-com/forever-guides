-- Rules of the contact list (the recently seen players), no game calls: cleaning of a stored list,
-- the capped add and update, filter, sort and paging, and the texts about one contact. Everything that
-- touches the game lives in SeenPlayers.lua; the page that shows the list is ContactsView.lua.
local _, ns = ...
local PN, U = ns.PlayerName, ns.U

local CL = {}
ns.ContactsLogic = CL

CL.MAX_SEEN = 300
CL.PAGE_SIZE = 25
CL.SEEN_SORTS = { "name", "recent", "level", "class" }
-- Columns the contacts page can show; the name is always shown.
CL.COLUMNS = { "race", "class", "level", "zone", "ilvl", "jobs", "guild", "seen", "source" }

local function text(v)
  return type(v) == "string" and v or ""
end

local function num(v)
  v = tonumber(v)
  return v and v == v and v or nil
end

local function compare(a, b)
  if a < b then
    return -1
  elseif a > b then
    return 1
  end
  return 0
end

-- Recently seen players ---------------------------------------------------------------------------

-- Drops entries that SavedVariables or an older version left malformed, in place. Returns the list.
function CL.CleanSeen(list)
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
  while #list > CL.MAX_SEEN do
    CL.SeenDropOldest(list)
  end
  return list
end

-- key -> entry lookup of a seen list.
function CL.SeenIndex(list)
  local index = {}
  for _, e in ipairs(list) do
    index[PN.Key(e.name)] = e
  end
  return index
end

-- guid -> entry lookup of a seen list (entries without a guid are not in it).
function CL.SeenGuidIndex(list)
  local guids = {}
  for _, e in ipairs(list) do
    if type(e.guid) == "string" then
      guids[e.guid] = e
    end
  end
  return guids
end

function CL.SeenDropOldest(list, index, guids)
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
function CL.SeenUpdate(e, info, now)
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
-- place. The list never grows beyond CL.MAX_SEEN, the oldest entry leaves first. guids is the optional
-- guid index that is kept in step. Returns the entry or nil for an empty name.
function CL.SeenAdd(list, index, info, now, guids)
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
  CL.SeenUpdate(e, info, now)
  if guids and type(e.guid) == "string" then
    guids[e.guid] = e
  end
  while #list > CL.MAX_SEEN do
    CL.SeenDropOldest(list, index, guids)
  end
  return e
end

-- f: race (token), class (token), search (part of the name). Returns a new list.
function CL.SeenFilter(list, f)
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
function CL.SeenSort(list, mode)
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
function CL.SeenChoices(list, field)
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
function CL.Page(list, page, size)
  size = size or CL.PAGE_SIZE
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
function CL.FirstContactText(first, L, sourceText, dateText)
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

-- Passive facts of a seen player ---------------------------------------------------------------------

-- The title part of UnitPVPName ("Private Anna", "Anna the Insane") without the player's name, ""
-- without a title. The names to cut out are tried in order (full name, first name).
function CL.TitleOf(pvpName, ...)
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
function CL.GuildText(e)
  local name, rank = text(e.guildName), text(e.guildRank)
  if name == "" then
    return ""
  end
  return rank ~= "" and string.format("<%s> (%s)", name, rank) or string.format("<%s>", name)
end
