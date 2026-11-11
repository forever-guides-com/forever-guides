-- Local recognition of guild and community logos: players who do not use the add-on get a logo for the guild
-- and the communities the game itself tells this player they belong to. Reading only, nothing is sent and
-- nobody is asked; the switch settings.crestLocal is off until the player turns it on.
--   guild roster     the own guild (GuildData, its own request throttle), every member gets the guild logo
--   seen players     the guild last seen on a player (SeenPlayers, filled from target, mouseover and group)
--   communities      the members of the subscribed communities (C_Club)
-- Where the logo comes from, in this order: the directory of the add-on (CrestLogic: region plus name of the
-- guild, name or alias of the community), else the emblem of the own guild when the client gives it, else a
-- neutral symbol (a shield for a guild, two figures for a community) whose tooltip names the guild or community
-- as the game reports it (roster, C_Club.GetSubscribedClubs). The game gives no icon of a community or of
-- somebody else's guild that an add-on may read (C_Club.SetAvatarTexture and GetClubInfo are protected and never
-- called), so the neutral symbol is the answer for them and a directory logo replaces it where one exists.
-- The index lives in memory only, with caps on every list, and is rebuilt out of the chat line on roster and
-- community events; a chat line only does table lookups. Switching off empties it and every handler returns at
-- once. The one place that decides what a line shows is CL.Shown: logos a player sends win, everybody else gets the
-- local result.
local _, ns = ...
local CLL, CRL, PN = ns.CrestLocalLogic, ns.CrestLogic, ns.PlayerName

local CL = {}
ns.CrestLocal = CL

-- Seconds a burst of roster and community events is collected before the index is rebuilt.
CL.REFRESH_DELAY = 3
-- Seconds between two reads of the member lists of the communities (they are the expensive part).
CL.CLUB_INTERVAL = 60

local LIMITS = CLL.LIMITS
-- Enum.ClubType.Guild when the client has the enum.
local CLUB_TYPE_GUILD = 2
local CLUB_EVENTS = { "CLUB_ADDED", "CLUB_REMOVED", "CLUB_UPDATED", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED" }

-- What the viewer belongs to (CL.Mine), kept for MINE_TTL seconds.
local mineCache
local byKey, count, region = {}, 0, nil
-- The parts of the index and what has to be read again.
local parts = { guild = nil, guildKey = "", communities = {} }
local dirty = {}
-- What the last read found per source, for the status report: nil until the first read.
local report
local lastClubRead = -1e9
local armed = false

local function g(name)
  return rawget(_G, name)
end

-- First value of a protected call, nil when the function is missing or raises an error.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

-- The value, or nil when the client calls it secret.
local function safe(value)
  local guard = ns.AutoGuard
  if guard then
    return guard.Safe(value)
  end
  return value
end

local function settings()
  return ns.db and ns.db.settings or {}
end

local function now()
  return tonumber(try(g("GetTime"))) or 0
end

-- The switch. Nothing below reads anything while it is off.
function CL.On()
  return settings().crestLocal == true
end

-- Reading the game ---------------------------------------------------------------------------------------

-- The emblem of the own guild as an icon of the game: the file of the emblem and its color (0 to 255). nil plus
-- the reason when the client does not give both. The color is a table of three fractions from 0 to 1.
local function guildIcon(name)
  local info = g("C_GuildInfo")
  if type(info) ~= "table" or type(info.GetGuildTabardInfo) ~= "function" then
    return nil, "no emblem function in this client"
  end
  local ok, tabard = pcall(info.GetGuildTabardInfo, "player")
  if not ok then
    return nil, "emblem call failed"
  end
  if type(tabard) ~= "table" then
    return nil, "client returned no emblem"
  end
  local color = safe(tabard.emblemColor)
  local file = safe(tabard.emblemFileID)
  if type(color) ~= "table" then
    return nil, "emblem color missing or secret"
  end
  local rgb = {}
  for i, field in ipairs({ "r", "g", "b" }) do
    local value = safe(color[field])
    if type(value) ~= "number" or value < 0 or value > 1 then
      return nil, "emblem color not usable"
    end
    rgb[i] = math.floor(value * 255 + 0.5)
  end
  local entry = CRL.GameEntry("guild", "guild", name, { file = file, r = rgb[1], g = rgb[2], b = rgb[3] })
  if not entry then
    return nil, "emblem file missing or secret"
  end
  return entry
end

-- Own guild: { entry, keys } with the logo (directory, else the emblem of the game, else the neutral shield), nil
-- without a guild or a usable name; second value the comparison key of its name. A roster that is not loaded yet
-- keeps what was read before and asks once (GuildData keeps its own throttle). Notes in report.guild where the
-- logo comes from or why there is none.
local function readGuild()
  local data = ns.GuildData
  report.guildState = "noGuild"
  if not data or data.Source() ~= nil then
    report.guild = "guild data unavailable in this client"
    return nil
  end
  local snap = data.Get()
  if type(snap) ~= "table" or snap.inGuild ~= true then
    report.guild = "not in a guild"
    return nil
  end
  if snap.loaded ~= true then
    data.Request()
    report.guild = report.guild or "roster not loaded yet"
    report.guildState = parts.guild == nil and "unread" or nil
    return parts.guild, parts.guildKey
  end
  local name = safe(snap.name)
  if type(name) ~= "string" or name == "" then
    report.guild = "guild name missing or secret"
    return nil
  end
  report.guildState = nil
  local entry, why = CLL.GuildEntry(region, name), nil
  if not entry then
    entry, why = guildIcon(name)
  end
  entry = entry or CLL.NeutralGuild(name)
  if not entry then
    report.guild = "no directory logo, " .. tostring(why)
    return nil
  end
  local source = CLL.Source(entry)
  report.guild = source == "neutral" and ("neutral symbol, no directory logo, " .. tostring(why))
    or (source == "directory" and "directory logo" or "game emblem")
  local keys = {}
  for i, member in ipairs(snap.members) do
    if i > LIMITS.MAX_GUILD_MEMBERS then
      break
    end
    keys[i] = member.key
  end
  return { entry = entry, keys = keys }, CRL.NormalizeName(name)
end

local function clubApi()
  local club = g("C_Club")
  if
    type(club) == "table"
    and type(club.GetSubscribedClubs) == "function"
    and type(club.GetClubMembers) == "function"
    and type(club.GetMemberInfo) == "function"
  then
    return club
  end
  return nil
end

-- The communities of the game (no guild) as { name, clubId, clubType }.
local function subscribedClubs(club)
  local list = try(club.GetSubscribedClubs)
  if type(list) ~= "table" then
    return {}
  end
  local enum = g("Enum")
  local guildType = type(enum) == "table" and type(enum.ClubType) == "table" and enum.ClubType.Guild or CLUB_TYPE_GUILD
  local out = {}
  for i = 1, math.min(#list, LIMITS.MAX_CLUBS) do
    local entry = list[i]
    if type(entry) == "table" then
      local name, id, kind = safe(entry.name), safe(entry.clubId), safe(entry.clubType)
      if type(name) == "string" and id ~= nil and kind ~= guildType then
        out[#out + 1] = { name = name, clubId = id, clubType = kind }
      end
    end
  end
  return out
end

-- { entry, keys } for each subscribed community (a directory logo, else a neutral symbol with the name of the
-- community). Without the API (Forever, Classic) nothing. Notes in report.communities how many there are, how many
-- have a directory logo and how many a neutral symbol.
local function readCommunities()
  local club = clubApi()
  if not club then
    report.communities = { api = false, total = 0, logo = 0, neutral = 0 }
    return {}
  end
  local clubs = subscribedClubs(club)
  local matches = CLL.Clubs(clubs, region)
  local neutral = 0
  for _, match in ipairs(matches) do
    neutral = neutral + (match.entry.logo and 1 or 0)
  end
  report.communities = { api = true, total = #clubs, logo = #matches - neutral, neutral = neutral }
  local out, reads = {}, 0
  for _, match in ipairs(matches) do
    local members, keys = try(club.GetClubMembers, match.clubId), {}
    if type(members) == "table" then
      for i = 1, math.min(#members, LIMITS.MAX_COMMUNITY_MEMBERS) do
        if reads >= LIMITS.MAX_COMMUNITY_READS then
          break
        end
        reads = reads + 1
        local info = try(club.GetMemberInfo, match.clubId, members[i])
        local name = type(info) == "table" and safe(info.name) or nil
        local key = type(name) == "string" and PN.Key(name) or ""
        if key ~= "" then
          keys[#keys + 1] = key
        end
      end
    end
    out[#out + 1] = { entry = match.entry, keys = keys }
  end
  return out
end

-- The index ------------------------------------------------------------------------------------------------

local function rebuild()
  byKey, count = CLL.Build(parts.guild, parts.communities)
end

-- Not in combat: the marks stay and the end of combat schedules the read again.
local function ready()
  local guard = ns.AutoGuard
  return CL.On() and not (guard and guard.Blocked())
end

local function refreshGuild()
  if not ready() or not dirty.guild then
    return
  end
  dirty.guild = nil
  region = ns.CrestMark.Region()
  report = report or {}
  local key
  parts.guild, key = readGuild()
  parts.guildKey = key or ""
  rebuild()
end

local function refreshClubs()
  if not ready() or not dirty.communities then
    return
  end
  dirty.communities = nil
  region = ns.CrestMark.Region()
  lastClubRead = now()
  report = report or {}
  parts.communities = readCommunities()
  rebuild()
end

local function schedule(part)
  if not CL.On() then
    return
  end
  dirty[part] = true
  if part == "guild" then
    ns.Debounce("crest-local-guild", CL.REFRESH_DELAY, refreshGuild)
  else
    local wait = math.max(CL.REFRESH_DELAY, CL.CLUB_INTERVAL - (now() - lastClubRead))
    ns.Debounce("crest-local-clubs", wait, refreshClubs)
  end
end

-- Empties the index and forgets what was marked.
function CL.Clear()
  byKey, count, region, report = {}, 0, nil, nil
  mineCache = nil
  parts = { guild = nil, guildKey = "", communities = {} }
  dirty, lastClubRead = {}, -1e9
end

-- What the last read found, for the status report: nil while the switch is off or before the first read.
-- { guild = "where the logo comes from or why there is none", guildState = "unread" (roster not read yet) or
-- "noGuild" (no guild found) or nil (a guild is in the index), communities = { api, total, logo, neutral } or nil }.
function CL.Report()
  if not CL.On() or not report then
    return nil
  end
  return { guild = report.guild, guildState = report.guildState, communities = report.communities }
end

-- Players in the index.
function CL.Count()
  return count
end

-- What the game is listened to for is only registered once the switch has been on.
local function arm()
  if armed then
    return
  end
  armed = true
  for _, event in ipairs(CLUB_EVENTS) do
    ns.On(event, function()
      schedule("communities")
    end)
  end
  ns.On("FG_GUILD_UPDATE", function()
    schedule("guild")
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    for part in pairs(dirty) do
      schedule(part)
    end
  end)
end

local function enable()
  arm()
  region = ns.CrestMark.Region()
  dirty = { guild = true, communities = true }
  lastClubRead = -1e9
  ns.Safe("crestlocal", refreshGuild)
  ns.Safe("crestlocal", refreshClubs)
end

-- Reading a line -------------------------------------------------------------------------------------------

-- The logo of the guild a player was last seen in: the directory one, or the one of the own guild when it is
-- that guild. Reads the contact list of this computer (SeenPlayers), nothing from the game.
local function seenGuild(name)
  local seen = ns.SeenPlayers
  if not seen or not seen.Enabled() then
    return nil
  end
  local contact = seen.FindName(name)
  local guild = contact and contact.guildName
  if type(guild) ~= "string" or guild == "" then
    return nil
  end
  -- Only the guild of the viewer: a guild the viewer is not in is no logo here.
  if parts.guild and CRL.NormalizeName(guild) == parts.guildKey then
    return parts.guild.entry
  end
  return nil
end

local function entriesOf(name, key)
  local info = byKey[key]
  return CLL.Entries(info, not (info and info.guild) and seenGuild(name) or nil)
end

-- Logos the local sources know for a player: guild first, then communities. Empty while the switch is off.
function CL.Entries(name)
  name = safe(name)
  if type(name) ~= "string" or not CL.On() then
    return {}
  end
  local key = PN.Key(name)
  return key ~= "" and entriesOf(name, key) or {}
end

-- What the viewer belongs to, for CLL.Shared: the directory ids of the own guild and of the own communities, the
-- comparison key of the guild name. Read from the game (GetGuildInfo of the player, the subscribed communities), also
-- while the local recognition is off, and kept for a few seconds. Secret or missing values leave the part empty.
local MINE_TTL = 10

function CL.Mine()
  local t = now()
  if mineCache and t >= mineCache.at and t - mineCache.at < MINE_TTL then
    return mineCache.value
  end
  local at = region or ns.CrestMark.Region()
  local mine = { guildIds = {}, guildKey = "", communityIds = {} }
  local guild = safe(try(g("GetGuildInfo"), "player"))
  if type(guild) == "string" and guild ~= "" then
    mine.guildKey = CRL.NormalizeName(guild)
    local entry = CLL.GuildEntry(at, guild)
    if entry and not entry.logo then
      mine.guildIds[entry.id] = true
    end
  end
  local club = clubApi()
  if club then
    for _, match in ipairs(CLL.Clubs(subscribedClubs(club), at)) do
      if not match.entry.logo then
        mine.communityIds[match.entry.id] = true
      end
    end
  end
  mineCache = { at = t, value = mine }
  return mine
end

-- What a chat line and the tooltip show for a player, and where it came from (for the "why" trace of the chat
-- badge): "off" (switch off, exactly what the logo register says), "sent" (logos the player sends himself, he
-- decides for himself), "local" (the local result), "no hit" (the index has no logo for him) or "guild unknown"
-- (no guild in the index at all). A player who sends no logo is not told from one without the add-on: the
-- directory is empty at times and nobody sends anything then, so the local result has to apply to everybody who
-- sent nothing, the own name included.
function CL.Shown(name)
  name = safe(name)
  if type(name) ~= "string" then
    return {}, "no hit"
  end
  local raw = ns.CrestMark.Entries(name)
  -- Only what the viewer shares with the player: his own logos always, the logos he sends only for the guild and the
  -- communities the viewer is in as well (the local index below is built from the lists of the viewer's own guild and
  -- communities, so it is shared by construction).
  local sent = PN.Equal(name, PN.Self()) and raw or CLL.Shared(raw, CL.Mine())
  if not CL.On() then
    return sent, "off"
  elseif #raw > 0 then
    return sent, "sent"
  end
  local key = PN.Key(name)
  local found = key ~= "" and entriesOf(name, key) or {}
  if found[1] then
    return found, "local"
  end
  return found, parts.guild == nil and "guild unknown" or "no hit"
end

-- Like CL.Shown, for a player who is on the screen as a unit (a nameplate): when the local recognition is on and the
-- logos so far name no guild, the guild the game reports for the unit (GetGuildInfo, readable values only) adds the logo
-- of the own guild when it is that guild. Nothing is read when the switch is off.
function CL.ShownUnit(name, unit)
  local entries, tag = CL.Shown(name)
  if not CL.On() or (entries[1] and entries[1].kind == "guild") or type(unit) ~= "string" or not parts.guild then
    return entries, tag
  end
  -- The guild the game names for the unit counts only when it is the guild of the viewer.
  local guild = safe(try(g("GetGuildInfo"), unit))
  if type(guild) ~= "string" or guild == "" or CRL.NormalizeName(guild) ~= parts.guildKey then
    return entries, tag
  end
  local out = { parts.guild.entry }
  for _, item in ipairs(entries) do
    out[#out + 1] = item
  end
  return out, "unit"
end

-- Events ---------------------------------------------------------------------------------------------------

ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path ~= "settings.crestLocal" then
    return
  end
  if value == true then
    enable()
  else
    CL.Clear()
  end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
  if CL.On() then
    arm()
    schedule("guild")
    schedule("communities")
  end
end)
