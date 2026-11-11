-- Rules of the local logo recognition, no game calls: which logo a guild or a community of the game gets (the
-- directory first, for the own guild then the emblem of the game, else a neutral symbol with the name the game
-- reports: a shield for a guild, two figures for a community), and the index "player key -> guild logo and
-- community logos" built from lists the game already shows the player (guild roster, members of the subscribed
-- communities). Keys come from ns.PlayerName.Key, nothing here knows names. Memory only, with caps on every
-- list; whether the recognition is on is the business of CrestLocal.
-- A logo is an entry of the form of CrestLogic.Entries: { id, kind, name, path } of the directory or
-- { id, kind, name, icon } of the game (CrestLogic.GameEntry, the emblem of the own guild only).
local _, ns = ...
local CRL = ns.CrestLogic

local CLL = {}
ns.CrestLocalLogic = CLL

CLL.LIMITS = {
  -- Players in the index.
  MAX_ENTRIES = 5000,
  -- Members read from the guild roster and from each community.
  MAX_GUILD_MEMBERS = 2000,
  MAX_COMMUNITY_MEMBERS = 1000,
  -- Members read from all communities together (each one is a call of the game).
  MAX_COMMUNITY_READS = 4000,
  -- Subscribed communities looked at.
  MAX_CLUBS = 20,
}
local L = CLL.LIMITS

-- The logo of the own guild: the directory one (region plus name), else `game` (the emblem of the game, an entry
-- or nil), else nil.
function CLL.GuildEntry(region, name, game, dir)
  dir = dir or CRL.Directory
  local entry = region and dir.FindGuild(region, name) or nil
  return entry or game
end

-- Which source the logo of a guild entry came from, for the status report.
function CLL.Source(entry)
  if not entry then
    return nil
  elseif entry.logo then
    return "neutral"
  end
  return entry.path and "directory" or "game"
end

-- The logos of `entries` (what a player sends: guild first, then communities) that the viewer shares with him: his
-- guild only when it is the guild of the viewer, only those of his communities the viewer is in as well. mine is
-- { guildIds = { id = true }, guildKey = normalized guild name, communityIds = { id = true } } of the viewer (directory
-- logos only, a neutral symbol names no guild by its id), nil or empty when that is not known: then nothing is shown,
-- never a guess. Entries that are not tables or carry no id are dropped.
function CLL.Shared(entries, mine)
  local out = {}
  if type(entries) ~= "table" or type(mine) ~= "table" then
    return out
  end
  local guilds, clubs = mine.guildIds or {}, mine.communityIds or {}
  local key = type(mine.guildKey) == "string" and mine.guildKey or ""
  local hasGuild = false
  for _, entry in ipairs(entries) do
    if type(entry) == "table" and entry.id ~= nil then
      if entry.kind == "guild" and not hasGuild then
        local sameName = key ~= "" and type(entry.name) == "string" and CRL.NormalizeName(entry.name) == key
        if guilds[entry.id] or sameName then
          hasGuild = true
          out[#out + 1] = entry
        end
      elseif entry.kind == "community" and clubs[entry.id] then
        out[#out + 1] = entry
      end
    end
  end
  return out
end

-- The neutral shield for the guild the game names, nil for a name that is no plain text.
function CLL.NeutralGuild(name)
  return CRL.NeutralEntry("guild", "guild", name)
end

-- The communities to read, as { entry, clubId } in the order they are shown: those with a directory logo first, in
-- the order of the directory, then the others in the order of the game with a neutral symbol and the name the
-- game reports. clubs are { name, clubId } each. Without a region only neutral symbols are possible. The game has
-- no icon for a community that an add-on may read (C_Club.SetAvatarTexture is protected), so a directory logo
-- or the neutral symbol is all there is.
function CLL.Clubs(clubs, region, dir)
  dir = dir or CRL.Directory
  local rank = {}
  for i, entry in ipairs(region and dir.List("community", region) or {}) do
    rank[entry.id] = i
  end
  local listed, seen = {}, {}
  for i, club in ipairs(type(clubs) == "table" and clubs or {}) do
    if i > L.MAX_CLUBS then
      break
    end
    if type(club) == "table" and club.clubId ~= nil then
      local entry = region and dir.FindCommunity(region, club.name) or nil
      entry = entry or CRL.NeutralEntry("community", "club" .. tostring(club.clubId), club.name)
      if entry and not seen[entry.id] then
        seen[entry.id] = true
        listed[#listed + 1] = {
          entry = entry,
          clubId = club.clubId,
          -- Directory logos before neutral ones, each group in its own order.
          rank = entry.logo and math.huge or rank[entry.id] or 0,
          pos = i,
        }
      end
    end
  end
  table.sort(listed, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.pos < b.pos
  end)
  local out = {}
  for _, match in ipairs(listed) do
    out[#out + 1] = { entry = match.entry, clubId = match.clubId }
  end
  return out
end

-- The index of the players: guild = { entry, keys = { key, ... } } or nil, communities = { { entry, keys }, ... }
-- in the order they are shown. Returns key -> { guild = entry or nil, communities = { entry, ... } } and the
-- number of players. Caps: MAX_ENTRIES players (guild members first), MAX_GUILD_MEMBERS and MAX_COMMUNITY_MEMBERS
-- keys per list, at most CRL.LIMITS.MAX_COMMUNITIES communities per player, none twice.
function CLL.Build(guild, communities)
  local map, count = {}, 0
  local function slot(key)
    if type(key) ~= "string" or key == "" then
      return nil
    end
    local info = map[key]
    if not info and count < L.MAX_ENTRIES then
      info = { communities = {} }
      map[key], count = info, count + 1
    end
    return info
  end
  if type(guild) == "table" and type(guild.entry) == "table" then
    for i, key in ipairs(guild.keys or {}) do
      if i > L.MAX_GUILD_MEMBERS then
        break
      end
      local info = slot(key)
      if info then
        info.guild = guild.entry
      end
    end
  end
  for _, community in ipairs(type(communities) == "table" and communities or {}) do
    local entry = community.entry
    for i, key in ipairs(type(entry) == "table" and community.keys or {}) do
      if i > L.MAX_COMMUNITY_MEMBERS then
        break
      end
      local info = slot(key)
      if info and #info.communities < CRL.LIMITS.MAX_COMMUNITIES then
        local twice = false
        for _, have in ipairs(info.communities) do
          twice = twice or have.id == entry.id
        end
        if not twice then
          info.communities[#info.communities + 1] = entry
        end
      end
    end
  end
  return map, count
end

-- The logos of one player as a new list: the guild of the index (else `seen`, the directory logo of the guild he
-- was last seen in) first, then his communities. info is an entry of the index or nil.
function CLL.Entries(info, seen)
  local out = {}
  local guild = info and info.guild or seen
  if guild then
    out[1] = guild
  end
  for _, entry in ipairs(info and info.communities or {}) do
    out[#out + 1] = entry
  end
  return out
end
