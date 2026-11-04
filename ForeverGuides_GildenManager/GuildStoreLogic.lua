-- The store of the add-on, no game calls: one record per guild inside ForeverGuidesGMDB (schema 2),
-- the guild key, the one-time migration of the schema 1 store, size limits and cleanup.
--   ForeverGuidesGMDB = { v = 2, prefs = {}, guilds = { [guildKey] = guild }, backupN = old stores }
-- A guild holds members, actions, settings and the containers later features fill (events, bans,
-- rules, ...). What cannot be assigned to a guild yet (data of schema 1 carries no guild) waits in
-- db.legacy until the first guild of this client opens it. Unknown fields are never dropped.
local _, gm = ...
if not gm.ext then
  return
end
local PN, U = gm.FG.PlayerName, gm.FG.U

local GS = {}
gm.GuildStore = GS

GS.SCHEMA = 2
GS.MAX_NOTE = 120
-- Longest guild name or realm (bytes) that still makes a key.
GS.MAX_PART = 96
-- Slots backup1 .. backupN for the stores a migration replaced.
GS.BACKUPS = 3
-- dryRun starts on: a first real run is a conscious choice after the measurement.
GS.DEFAULTS = { inactiveDays = 30, dryRun = true, maxEvents = 2000, maxActions = 500 }
-- Settings that bound a list: { min, max }, the default comes from DEFAULTS.
GS.LIMITS = { maxEvents = { 500, 5000 }, maxActions = { 100, 5000 } }
-- Lists and tables of a guild record; features of later versions fill most of them.
local CONTAINERS = {
  "members",
  "idByGuid",
  "seen",
  "events",
  "actions",
  "bans",
  "rules",
  "protect",
  "skip",
  "settings",
  "share",
  "inbox",
}
local NUMBERS = { "firstScanDay", "lastScanDay", "lastScanCount" }

local function number(v)
  return type(v) == "number" and v == v and v
end

local function part(s)
  if type(s) ~= "string" then
    return nil
  end
  s = (s:gsub("|", ""):gsub("%s+", " "))
  s = U.trim(s)
  return s ~= "" and #s <= GS.MAX_PART and s or nil
end

-- "<realm>|<guild name>", lower case. The realm loses spaces and hyphens like in a roster key, so both
-- spellings of the client give one key; a missing realm falls back to "unknown". Nil without a name.
function GS.Key(name, realm)
  name = part(name)
  if not name then
    return nil
  end
  realm = part(type(realm) == "string" and realm:gsub("[%s%-]", "") or nil)
  return PN.Lower(realm or "unknown") .. "|" .. PN.Lower(name)
end

function GS.NewGuild(name, realm)
  local guild = { name = part(name) or "", realm = part(realm) or "" }
  for _, field in ipairs(NUMBERS) do
    guild[field] = 0
  end
  for _, field in ipairs(CONTAINERS) do
    guild[field] = {}
  end
  guild.settings = U.copy(GS.DEFAULTS)
  return guild
end

function GS.NewDb()
  return { v = GS.SCHEMA, prefs = {}, guilds = {} }
end

-- A whole number inside the limit of the setting, the default for anything else.
function GS.Limit(guild, field)
  local range = GS.LIMITS[field]
  local settings = type(guild) == "table" and guild.settings
  local v = number(type(settings) == "table" and settings[field])
  if not v then
    return GS.DEFAULTS[field]
  end
  return U.clamp(math.floor(v + 0.5), range[1], range[2])
end

-- Drops the oldest entries of a list (oldest first) down to the limit, in place.
function GS.Trim(list, limit)
  local n = #list
  local extra = n - limit
  if extra <= 0 then
    return list
  end
  for i = 1, limit do
    list[i] = list[i + extra]
  end
  for i = limit + 1, n do
    list[i] = nil
  end
  return list
end

-- Brings a guild record into shape and inside its limits, in place. Entries of members and actions
-- are checked by MembersLogic and ActionsLogic.
function GS.CleanGuild(guild)
  guild.name = part(guild.name) or ""
  guild.realm = part(guild.realm) or ""
  for _, field in ipairs(NUMBERS) do
    guild[field] = number(guild[field]) and guild[field] >= 0 and guild[field] or 0
  end
  for _, field in ipairs(CONTAINERS) do
    if type(guild[field]) ~= "table" then
      guild[field] = {}
    end
  end
  local settings = U.applyDefaults(guild.settings, GS.DEFAULTS)
  for field in pairs(GS.LIMITS) do
    settings[field] = GS.Limit(guild, field)
  end
  local events = {}
  for _, e in ipairs(guild.events) do
    if type(e) == "table" then
      events[#events + 1] = e
    end
  end
  guild.events = GS.Trim(events, settings.maxEvents)
  return guild
end

-- Takes what schema 1 kept at the top of the store (members, log, inactiveDays, dryRun) out of the
-- store as a guild-shaped table, or nil when there was none. migrating: the fields go even when
-- they are unusable (the backup has them).
local function takeLegacy(db, migrating)
  local out, any = { members = {}, actions = {}, settings = {} }, false
  local function grab(field, valid, put)
    local v = db[field]
    if valid(v) then
      put(v)
      any, db[field] = true, nil
    elseif migrating then
      db[field] = nil
    end
  end
  grab("members", function(v)
    return type(v) == "table" and next(v) ~= nil
  end, function(v)
    out.members = v
  end)
  grab("log", function(v)
    return type(v) == "table" and next(v) ~= nil
  end, function(v)
    out.actions = v
  end)
  grab("inactiveDays", number, function(v)
    out.settings.inactiveDays = v
  end)
  grab("dryRun", function(v)
    return type(v) == "boolean"
  end, function(v)
    out.settings.dryRun = v
  end)
  return any and out or nil
end

-- Adds src (a guild-shaped table) to dst without overwriting: members by key (missing fields of an
-- existing entry, nil or empty, are filled), actions appended in time order, settings only where dst has none, or
-- all of them when dst is new.
local function merge(dst, src, replaceSettings)
  for key, e in pairs(src.members) do
    local mine = dst.members[key]
    if mine == nil then
      dst.members[key] = e
    elseif type(mine) == "table" and type(e) == "table" then
      for field, value in pairs(e) do
        if mine[field] == nil or mine[field] == "" then
          mine[field] = value
        end
      end
    end
  end
  local list, order = dst.actions, {}
  for _, e in ipairs(src.actions) do
    list[#list + 1] = e
  end
  for i, e in ipairs(list) do
    order[e] = i
  end
  table.sort(list, function(a, b)
    local ta, tb = type(a) == "table" and number(a.t) or 0, type(b) == "table" and number(b.t) or 0
    if ta ~= tb then
      return ta < tb
    end
    return order[a] < order[b]
  end)
  for field, value in pairs(src.settings) do
    if replaceSettings or dst.settings[field] == nil then
      dst.settings[field] = value
    end
  end
end

local function usable(legacy)
  return type(legacy) == "table"
    and type(legacy.members) == "table"
    and type(legacy.actions) == "table"
    and type(legacy.settings) == "table"
end

-- First slot backup1 .. backupN that is free, nil when all are taken.
local function freeBackup(db)
  for i = 1, GS.BACKUPS do
    if db["backup" .. i] == nil then
      return "backup" .. i
    end
  end
end

-- Puts the db into schema 2 and answers it with the status "ok", or an empty db and "future" for a store
-- of a newer schema (it stays as it is, nothing of it is read or written). The migration runs once
-- (the schema number says so), keeps a copy of the old store in the next free backupN, and may run
-- again on its own result without a change. A value that is no table is kept in backup1 as { value = v }.
function GS.Load(raw)
  if type(raw) == "table" and number(raw.v) and raw.v > GS.SCHEMA then
    return GS.NewDb(), "future"
  end
  local db = type(raw) == "table" and raw or {}
  local migrating = db.v ~= GS.SCHEMA
  if migrating and raw ~= nil then
    local slot = freeBackup(db)
    if slot and type(raw) == "table" then
      local copy = {}
      for k, v in pairs(db) do
        if not (type(k) == "string" and k:find("^backup%d+$")) then
          copy[k] = U.copy(v)
        end
      end
      db[slot] = copy
    elseif slot then
      db[slot] = { value = raw }
    end
  end
  local legacy = takeLegacy(db, migrating)
  if legacy then
    if usable(db.legacy) then
      merge(db.legacy, legacy, false)
    else
      db.legacy = legacy
    end
  end
  db.v = GS.SCHEMA
  if type(db.prefs) ~= "table" then
    db.prefs = {}
  end
  if type(db.guilds) ~= "table" then
    db.guilds = {}
  end
  for key, guild in pairs(db.guilds) do
    if type(key) ~= "string" or key == "" or type(guild) ~= "table" then
      db.guilds[key] = nil
    else
      GS.CleanGuild(guild)
    end
  end
  return db, "ok"
end

-- The record of the guild with this key, created when new. The data that waited in db.legacy goes
-- into it (once, the first guild that opens wins). name and realm only label the record.
function GS.Open(db, key, name, realm)
  local guild = db.guilds[key]
  local fresh = type(guild) ~= "table"
  if fresh then
    guild = GS.NewGuild(name, realm)
    db.guilds[key] = guild
  else
    guild.name = part(name) or guild.name
    guild.realm = part(realm) or guild.realm
  end
  local legacy = db.legacy
  db.legacy = nil
  if usable(legacy) then
    merge(guild, legacy, fresh)
    GS.CleanGuild(guild)
  end
  return guild
end
