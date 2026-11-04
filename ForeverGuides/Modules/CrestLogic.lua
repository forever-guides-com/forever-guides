-- Rules of the guild and community logos, no game calls: the directory of logos (ns.CrestData), the payload of
-- the message that says "these are my logos", the register of players heard (memory only) and the text a chat
-- line gets. Nothing here asks whether something may be sent or shown, that is Consent's business (CrestMark).
-- Payload (printable ASCII), inside the envelope of ns.Comm (function CM, prefix FGCOMM):
--   C  <version>|<guild id>|<community id>,<community id>   ids of the directory only, the guild id or the
--                                                            list may be empty, never both
--   R  (empty)                                              withdrawal: forget me; carries no data
-- Only ids go out, never a name and never a picture: a receiver knows a logo only when its own directory has it.
-- The same ids can ride in the presence mark (PM) as an optional tail, see PresenceLogic: Body and DecodeBody are
-- the part after the version, "<guild id>|<community id>,<community id>".
local _, ns = ...

local CRL = {}
ns.CrestLogic = CRL

CRL.LIMITS = {
  VERSION = 1,
  MAX_LENGTH = 128,
  MIN_ID = 2,
  MAX_ID = 8,
  MAX_NAME = 48,
  MAX_ALIASES = 6,
  MAX_STEM = 40,
  MAX_COMMUNITIES = 8,
  -- Seconds a player stays in the register after the last message.
  TTL = 3600,
  MAX_ENTRIES = 1000,
  -- Messages taken into the register per second, the rest is dropped.
  INPUT_PER_SECOND = 10,
  MAX_KEY = 64,
  -- Logos after the add-on logo in a chat line: default and range of the setting.
  DEFAULT_COUNT = 3,
  MAX_COUNT = 8,
}
local L = CRL.LIMITS

-- Value of GetCurrentRegion: 1 US, 2 KR, 3 EU, 4 TW, 5 CN.
CRL.REGIONS = { "US", "KR", "EU", "TW", "CN" }
local REGION_SET = {}
for _, name in ipairs(CRL.REGIONS) do
  REGION_SET[name] = true
end

CRL.KINDS = { guild = true, community = true }
CRL.MEDIA_DIR = "Interface\\AddOns\\ForeverGuides\\Media\\Crests\\"
CRL.LINK = "ForeverGuides:crest"

-- "EU" for 3 or "eu", nil for anything else.
function CRL.RegionName(value)
  if type(value) == "number" then
    return CRL.REGIONS[value]
  end
  if type(value) == "string" then
    local name = value:upper()
    return REGION_SET[name] and name or nil
  end
  return nil
end

-- Comparison key of a guild name: lower case, no outer spaces, runs of spaces as one.
function CRL.NormalizeName(name)
  if type(name) ~= "string" then
    return ""
  end
  name = ns.PlayerName.Lower(name):gsub("%s+", " ")
  return (name:gsub("^ ", ""):gsub(" $", ""))
end

local function validId(id)
  return type(id) == "string" and #id >= L.MIN_ID and #id <= L.MAX_ID and not id:find("[^0-9a-z]")
end

local function isWhole(value, lo, hi)
  return type(value) == "number" and value == math.floor(value) and value >= lo and value <= hi
end

local function validText(text, max)
  return type(text) == "string" and text ~= "" and #text <= max and not text:find("[%c|]")
end

-- Directory ---------------------------------------------------------------------------------------------

-- A directory of logos; the add-on has one (CRL.Directory), filled from ns.CrestData. Tests fill and empty it.
function CRL.NewDirectory()
  local byId, order = {}, {}
  -- kind -> "<region>|<normalized name or alias>" -> entry, the key of the local recognition (CrestLocal).
  local lookup = { guild = {}, community = {} }
  local D = {}

  local function regionsOf(text)
    if type(text) ~= "string" or text == "" then
      return nil
    end
    local set, list = {}, {}
    for token in text:gmatch("[^,%s]+") do
      local name = CRL.RegionName(token)
      if not name or set[name] then
        return nil
      end
      set[name] = true
      list[#list + 1] = name
    end
    return #list > 0 and set or nil
  end

  -- The optional list of other names the game may report for the entry; nil when it is malformed.
  local function aliasesOf(list)
    if list == nil then
      return {}
    end
    if type(list) ~= "table" or #list > L.MAX_ALIASES then
      return nil
    end
    local count = 0
    for _ in pairs(list) do
      count = count + 1
    end
    if count ~= #list then
      return nil
    end
    local out = {}
    for _, alias in ipairs(list) do
      if not validText(alias, L.MAX_NAME) then
        return nil
      end
      out[#out + 1] = alias
    end
    return out
  end

  -- Adds { id, kind, name, regions, stem [, aliases] }. Returns true, or false and the name of the field that is
  -- wrong. Name and aliases of one kind must be unique per region.
  function D.Add(row)
    if type(row) ~= "table" then
      return false, "row"
    end
    local id, kind, name, regions, stem = row[1], row[2], row[3], regionsOf(row[4]), row[5]
    if not validId(id) or byId[id] then
      return false, "id"
    end
    if not CRL.KINDS[kind] then
      return false, "kind"
    end
    if not validText(name, L.MAX_NAME) then
      return false, "name"
    end
    if not regions then
      return false, "regions"
    end
    if type(stem) ~= "string" or #stem > L.MAX_STEM or not stem:find("^[%w_-]+$") then
      return false, "stem"
    end
    local aliases = aliasesOf(row[6])
    if not aliases then
      return false, "aliases"
    end
    local keys, named = {}, {}
    local texts = { name }
    for _, alias in ipairs(aliases) do
      texts[#texts + 1] = alias
    end
    for _, text in ipairs(texts) do
      local normalized = CRL.NormalizeName(text)
      if not named[normalized] then
        named[normalized] = true
        for region in pairs(regions) do
          local key = region .. "|" .. normalized
          if lookup[kind][key] then
            return false, kind
          end
          keys[#keys + 1] = key
        end
      end
    end
    local entry = {
      id = id,
      kind = kind,
      name = name,
      regions = regions,
      stem = stem,
      aliases = aliases,
      path = CRL.MEDIA_DIR .. stem .. ".png",
    }
    byId[id] = entry
    order[#order + 1] = entry
    for _, key in ipairs(keys) do
      lookup[kind][key] = entry
    end
    return true
  end

  function D.Get(id)
    return type(id) == "string" and byId[id] or nil
  end

  -- Entries of one kind (nil: all) that apply in a region (nil: every region), in the order of the data.
  function D.List(kind, region)
    local out = {}
    for _, entry in ipairs(order) do
      if (kind == nil or entry.kind == kind) and (region == nil or entry.regions[region]) then
        out[#out + 1] = entry
      end
    end
    return out
  end

  local function find(kind, region, name)
    local key = CRL.NormalizeName(name)
    if key == "" or type(region) ~= "string" then
      return nil
    end
    return lookup[kind][region .. "|" .. key]
  end

  -- The guild entry for a region and the name the game reports (the name or an alias), nil without a match.
  function D.FindGuild(region, name)
    return find("guild", region, name)
  end

  -- The community entry for a region and the name of the community in the game (the name or an alias).
  function D.FindCommunity(region, name)
    return find("community", region, name)
  end

  function D.Count()
    return #order
  end

  function D.Clear()
    byId, order = {}, {}
    lookup = { guild = {}, community = {} }
  end

  return D
end

CRL.Directory = CRL.NewDirectory()
for _, row in ipairs(ns.CrestData and ns.CrestData.rows or {}) do
  CRL.Directory.Add(row)
end

-- Payload -----------------------------------------------------------------------------------------------

-- The body of the payload for a guild id (or nil) and a list of community ids, nil when nothing is to be sent:
-- both empty, an id the directory does not know or of the wrong kind, a double, or more than MAX_COMMUNITIES.
function CRL.Body(guildId, communityIds, dir)
  dir = dir or CRL.Directory
  communityIds = communityIds or {}
  if guildId ~= nil then
    local entry = dir.Get(guildId)
    if not entry or entry.kind ~= "guild" then
      return nil
    end
  end
  if #communityIds > L.MAX_COMMUNITIES then
    return nil
  end
  local seen = {}
  for _, id in ipairs(communityIds) do
    local entry = dir.Get(id)
    if not entry or entry.kind ~= "community" or seen[id] then
      return nil
    end
    seen[id] = true
  end
  if guildId == nil and #communityIds == 0 then
    return nil
  end
  return string.format("%s|%s", guildId or "", table.concat(communityIds, ","))
end

-- The payload (version and body), nil when nothing is to be sent.
function CRL.Encode(guildId, communityIds, dir)
  local body = CRL.Body(guildId, communityIds, dir)
  return body and string.format("%d|%s", L.VERSION, body) or nil
end

-- The ids of a body: { guild = id or nil, communities = { id, ... } }, nil for anything else (an empty or malformed
-- id, a double, too many ids, a guild id in the list or the other way round, nothing at all). An id the directory
-- does not know is left out, so a newer directory of the sender does not break an older one; the result may be
-- empty then.
local function readBody(guild, list, dir)
  if guild == "" and list == "" then
    return nil
  end
  local out = { communities = {} }
  if guild ~= "" then
    if not validId(guild) then
      return nil
    end
    local entry = dir.Get(guild)
    if entry then
      if entry.kind ~= "guild" then
        return nil
      end
      out.guild = guild
    end
  end
  if list ~= "" then
    local seen, n = {}, 0
    for id in (list .. ","):gmatch("([^,]*),") do
      n = n + 1
      if n > L.MAX_COMMUNITIES or not validId(id) or seen[id] then
        return nil
      end
      seen[id] = true
      local entry = dir.Get(id)
      if entry then
        if entry.kind ~= "community" then
          return nil
        end
        out.communities[#out.communities + 1] = id
      end
    end
  end
  return out
end

-- The same for the body of the tail of a presence mark ("<guild id>|<list>"), which may be followed by more
-- fields of a later version ("|..."): those are ignored. nil for a body that is not exactly that.
function CRL.DecodeBody(body, dir)
  dir = dir or CRL.Directory
  if type(body) ~= "string" or #body > L.MAX_LENGTH or body:find("[^ -~]") then
    return nil
  end
  local guild, list = body:match("^([0-9a-z]*)|([0-9a-z,]*)$")
  if not guild then
    guild, list = body:match("^([0-9a-z]*)|([0-9a-z,]*)|")
  end
  if not guild then
    return nil
  end
  return readBody(guild, list, dir)
end

-- { guild = id or nil, communities = { id, ... } } for exactly the format, nil for anything else (wrong version,
-- length, a character outside printable ASCII, and what readBody refuses).
function CRL.Decode(payload, dir)
  dir = dir or CRL.Directory
  if type(payload) ~= "string" or #payload > L.MAX_LENGTH or payload:find("[^ -~]") then
    return nil
  end
  local version, guild, list = payload:match("^(%d)|([0-9a-z]*)|([0-9a-z,]*)$")
  if not version or tonumber(version) ~= L.VERSION then
    return nil
  end
  return readBody(guild, list, dir)
end

function CRL.EncodeFarewell()
  return ""
end

function CRL.DecodeFarewell(payload)
  return payload == ""
end

-- Register ----------------------------------------------------------------------------------------------

local SOURCES = { group = true, guild = true }

-- Players heard, key -> { guild, communities, at, src }. clock() returns seconds. The caller derives the key
-- from the name (ns.PlayerName.Key), nothing here knows names.
function CRL.NewRegistry(clock)
  local entries, count = {}, 0
  local window, inWindow = nil, 0
  local R = {}

  local function drop(key)
    if entries[key] then
      entries[key], count = nil, count - 1
    end
  end

  local function expired(entry, now)
    return now - entry.at >= L.TTL
  end

  function R.Prune()
    local now, n = clock(), 0
    for key, entry in pairs(entries) do
      if expired(entry, now) then
        drop(key)
        n = n + 1
      end
    end
    return n
  end

  local function evictOldest()
    local victim
    for key, entry in pairs(entries) do
      if not victim or entry.at < entries[victim].at then
        victim = key
      end
    end
    drop(victim)
  end

  -- msg: a result of Decode. Returns "stored", "rate" (more than INPUT_PER_SECOND in this second) or "invalid".
  function R.Add(key, msg, src)
    if type(key) ~= "string" or key == "" or #key > L.MAX_KEY or type(msg) ~= "table" or not SOURCES[src] then
      return "invalid"
    end
    local now = clock()
    local second = math.floor(now)
    if second ~= window then
      window, inWindow = second, 0
    end
    if inWindow >= L.INPUT_PER_SECOND then
      return "rate"
    end
    inWindow = inWindow + 1
    if not entries[key] then
      if count >= L.MAX_ENTRIES then
        R.Prune()
      end
      if count >= L.MAX_ENTRIES then
        evictOldest()
      end
      count = count + 1
    end
    local communities = {}
    for i, id in ipairs(msg.communities or {}) do
      communities[i] = id
    end
    entries[key] = { guild = msg.guild, communities = communities, at = now, src = src }
    return "stored"
  end

  -- A copy { guild, communities, at, src }, nil when unknown or older than the TTL.
  function R.Get(key)
    local entry = entries[key]
    if not entry then
      return nil
    end
    if expired(entry, clock()) then
      drop(key)
      return nil
    end
    local communities = {}
    for i, id in ipairs(entry.communities) do
      communities[i] = id
    end
    return { guild = entry.guild, communities = communities, at = entry.at, src = entry.src }
  end

  function R.Remove(key)
    local had = entries[key] ~= nil
    drop(key)
    return had
  end

  -- Forgets everything that came from one source (a consent that went off), returns how many.
  function R.RemoveSource(src)
    local n = 0
    for key, entry in pairs(entries) do
      if entry.src == src then
        drop(key)
        n = n + 1
      end
    end
    return n
  end

  function R.Clear()
    local n = count
    entries, count = {}, 0
    return n
  end

  function R.Count()
    R.Prune()
    return count
  end

  return R
end

-- Chat line ---------------------------------------------------------------------------------------------

-- Entries of the directory for { guild, communities }: the guild first, then the communities in the order of
-- the sender. An id the directory does not know is skipped.
function CRL.Entries(info, dir)
  dir = dir or CRL.Directory
  local out = {}
  if type(info) ~= "table" then
    return out
  end
  local guild = dir.Get(info.guild)
  if guild and guild.kind == "guild" then
    out[1] = guild
  end
  for _, id in ipairs(info.communities or {}) do
    local entry = dir.Get(id)
    if entry and entry.kind == "community" then
      out[#out + 1] = entry
    end
  end
  return out
end

-- The number of logos after the add-on logo: the setting, 0 to MAX_COUNT, the default for anything else.
function CRL.CleanCount(value)
  value = tonumber(value)
  if not value or value ~= value then
    return L.DEFAULT_COUNT
  end
  return math.max(0, math.min(L.MAX_COUNT, math.floor(value + 0.5)))
end

-- The entry of a logo the game itself provides (not from the directory): { id, kind, name, icon }. icon is
-- { file = file id } and for a tinted emblem also r, g, b (0 to 255). nil for anything that is not exactly that,
-- so a half read value never becomes a logo. key makes the id unique ("guild", "club<id>").
function CRL.GameEntry(kind, key, name, icon)
  if not CRL.KINDS[kind] or not validText(key, L.MAX_NAME) or not validText(name, L.MAX_NAME) then
    return nil
  end
  if type(icon) ~= "table" or not isWhole(icon.file, 1, 4294967295) then
    return nil
  end
  local out = { file = icon.file }
  if icon.r ~= nil or icon.g ~= nil or icon.b ~= nil then
    if not (isWhole(icon.r, 0, 255) and isWhole(icon.g, 0, 255) and isWhole(icon.b, 0, 255)) then
      return nil
    end
    out.r, out.g, out.b = icon.r, icon.g, icon.b
  end
  return { id = "game:" .. key, kind = kind, name = name, icon = out }
end

-- The entry of a neutral symbol, for a guild or community the game names but the directory has no logo for:
-- { id, kind, name, path, logo }. key makes the id unique ("guild", "club<id>"). name is the one the game reports,
-- cut to MAX_NAME bytes at a character boundary. nil for anything that is not a plain name or when the picture
-- stems are missing (no CrestData).
function CRL.NeutralEntry(kind, key, name)
  local stems = ns.CrestData and ns.CrestData.neutral
  local stem = CRL.KINDS[kind] and type(stems) == "table" and stems[kind] or nil
  if not stem or type(name) ~= "string" or not validText(key, L.MAX_NAME) then
    return nil
  end
  if #name > L.MAX_NAME then
    local cut = L.MAX_NAME
    -- Back up over UTF-8 continuation bytes so a multi-byte character is never split.
    while cut > 1 and name:byte(cut + 1) and name:byte(cut + 1) >= 0x80 and name:byte(cut + 1) < 0xC0 do
      cut = cut - 1
    end
    name = name:sub(1, cut)
  end
  if not validText(name, L.MAX_NAME) then
    return nil
  end
  return {
    id = "neutral:" .. key,
    kind = kind,
    name = name,
    path = CRL.MEDIA_DIR .. stem .. ".png",
    logo = "neutral " .. kind,
  }
end

-- Texture of one logo. A directory logo is one 64 px file, a logo of the game is a file id (a tinted emblem
-- takes the whole picture and the color as 0 to 255). The chat scales it to the height.
function CRL.Texture(entry, height)
  height = math.max(1, math.floor(tonumber(height) or 14))
  local icon = entry.icon
  if not icon then
    return string.format("|T%s:%d:%d:0:0|t", entry.path, height, height)
  end
  if icon.r then
    return string.format("|T%d:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", icon.file, height, height, icon.r, icon.g, icon.b)
  end
  return string.format("|T%d:%d:%d:0:0|t", icon.file, height, height)
end

-- A hover target around some text: the player (percent-encoded) and the place of the logo in the line, 0 for the
-- add-on logo, 1 and up for the others. The game never opens anything for it, the hook of CrestLink shows a tooltip.
function CRL.Link(name, index, inner)
  return string.format("|Haddon:%s:%s:%d|h%s|h", CRL.LINK, ns.PlayerName.Encode(name), index, inner)
end

-- name and index of a link as the game hands it to the hover hooks ("addon:ForeverGuides:crest:<name>:<index>"),
-- nil for every other link.
function CRL.ParseLink(data)
  if type(data) ~= "string" or #data > 160 then
    return nil
  end
  local name, index = data:match("^addon:" .. CRL.LINK .. ":([^:|]+):(%d+)$")
  index = tonumber(index)
  if not name or not index or index > L.MAX_COUNT + 1 then
    return nil
  end
  return ns.PlayerName.Decode(name), index
end

-- What goes in front of a name: the add-on logo (forever, markup or ""), then the first `count` logos of
-- `entries`, at the pixel height `height`. The add-on logo is always the hover target: it names the add-on and
-- lists all logos of the player, also those that do not fit. "" when there is nothing to show.
function CRL.Compose(name, forever, entries, count, height)
  local parts = {}
  if forever ~= "" then
    parts[1] = CRL.Link(name, 0, forever)
  end
  for i = 1, math.min(#entries, count) do
    parts[#parts + 1] = CRL.Link(name, i, CRL.Texture(entries[i], height))
  end
  return table.concat(parts, " ")
end
