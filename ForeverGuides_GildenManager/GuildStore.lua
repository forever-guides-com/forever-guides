-- The store of the add-on in the game: reads SavedVariables, names the guild of this character and
-- hands the record of that guild to the other files (GuildStoreLogic.lua holds the rules). Without
-- a guild, or with a store of a newer schema, gm.Guild() answers a record that is never saved.
local ADDON_NAME, gm = ...
if not gm.ext then
  return
end
local FG, GS = gm.FG, gm.GuildStore

-- The status of the store: "ok", or "future" (saved by a newer version, left untouched).
gm.status = "ok"
-- Usable before SavedVariables are read.
gm.db = GS.NewDb()

local scratch = GS.NewGuild("", "")
local identity, forced, opened

local function call(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok and FG.ItemInfo.accessible(a) and FG.ItemInfo.accessible(d) then
    return a, b, c, d
  end
end

-- Key, name and realm of the guild of this character; nil without a guild or while the client does not
-- say. The realm is the one GetGuildInfo names for a guild of another realm, else the own one.
local function resolve()
  if call("IsInGuild") == false then
    return nil
  end
  local name, _, _, realm = call("GetGuildInfo", "player")
  if type(name) ~= "string" then
    return nil
  end
  if type(realm) ~= "string" or realm == "" then
    realm = call("GetNormalizedRealmName") or call("GetRealmName")
  end
  local key = GS.Key(name, realm)
  return key and { key = key, name = name, realm = type(realm) == "string" and realm or "" } or nil
end

-- Cleaning of a record that was just opened or loaded.
function gm.CleanGuild(guild)
  gm.MembersLogic.Clean(guild)
  gm.InactivityLogic.Clean(guild)
  gm.ActionsLogic.Clean(guild)
  if gm.HistoryLogic then
    gm.HistoryLogic.Clean(guild)
  end
  if gm.BansLogic then
    gm.BansLogic.Clean(guild)
  end
end

-- Why nothing may be saved right now: "noGuild", "newer", or nil when saving is fine.
function gm.WriteBlock()
  if gm.status ~= "ok" then
    return "newer"
  end
  if forced or identity or resolve() then
    return nil
  end
  return "noGuild"
end

-- The record of the guild of this character (members, actions, settings). Always a table; a record
-- that belongs to no guild stays in memory and is never saved.
function gm.Guild()
  if gm.status ~= "ok" then
    return scratch
  end
  if forced then
    return gm.db.guilds[forced] or scratch
  end
  identity = identity or resolve()
  if not identity then
    return scratch
  end
  if not (opened and opened.db == gm.db and opened.key == identity.key) then
    local guild = GS.Open(gm.db, identity.key, identity.name, identity.realm)
    gm.CleanGuild(guild)
    opened = { db = gm.db, key = identity.key, guild = guild }
  end
  return opened.guild
end

FG.On("PLAYER_GUILD_UPDATE", function()
  identity = nil
end)

-- What a companion add-on may use to run this add-on on a copy of its data in memory (see
-- GuildExt.Share): the store and the member rules. SetDb(db, key) swaps the store; with a key the
-- guild of that record counts, whatever guild the character is in.
gm.ext.Share("gildenmanager", {
  Db = function()
    return gm.db
  end,
  SetDb = function(db, key)
    gm.db, forced, opened = db, key, nil
  end,
  Store = function()
    return GS
  end,
  Members = function()
    return gm.MembersLogic
  end,
  Bans = function()
    return gm.BansLogic
  end,
  Export = function()
    return gm.ExportLogic
  end,
  History = function()
    return gm.HistoryLogic
  end,
  Dates = function()
    return gm.DatesLogic
  end,
  Reminders = function()
    return gm.RemindersLogic
  end,
  Share = function()
    return gm.ShareLogic
  end,
  RulesUi = function()
    return gm.RulesUiLogic
  end,
  Shift = function(seconds)
    gm.History.SetShift(seconds)
  end,
})

FG.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then
    return
  end
  local db, status = GS.Load(ForeverGuidesGMDB)
  for _, guild in pairs(db.guilds) do
    gm.CleanGuild(guild)
  end
  gm.db, gm.status, opened = db, status, nil
  if status == "ok" then
    ForeverGuidesGMDB = db
  end
end)
