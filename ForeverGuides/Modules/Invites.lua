-- Whisper invite: a whisper that is a keyword invites the sender to the group and/or the
-- guild, depending on the settings (Store: inviteGroup*, inviteGuild*). The rules live in
-- InviteLogic; this file asks the game for the facts and does the invite. Every game call is
-- wrapped in pcall. The sender name goes to the game exactly as the whisper delivered it
-- ("first surname", never cut at a blank). Off until a keyword is set.
local _, ns = ...
local IL, PN = ns.InviteLogic, ns.PlayerName

local I = {}
ns.Invites = I

ns.AddLocale("enUS", {
  ["invite.kind.group"] = "Group",
  ["invite.kind.guild"] = "Guild",
  ["invite.chat.invited"] = "Invited: %s (%s)",
  ["invite.chat.failed"] = "Invite failed: %s (%s)",
  ["invite.reply.group"] = "Inviting you, %s.",
  ["invite.reply.guild"] = "Guild invite for you, %s.",
  ["invite.why.no-api"] = "Not available in this client.",
  ["invite.why.combat"] = "Not possible in combat.",
  ["invite.why.offline"] = "The player is offline.",
  ["invite.why.faction"] = "The player belongs to the other faction.",
  ["invite.why.in-group"] = "The player is already in your group.",
  ["invite.why.group-full"] = "Your group is full.",
  ["invite.why.not-leader"] = "Only the group leader can invite.",
  ["invite.why.error"] = "The game refused the invite.",
})
ns.AddLocale("deDE", {
  ["invite.kind.group"] = "Gruppe",
  ["invite.kind.guild"] = "Gilde",
  ["invite.chat.invited"] = "Eingeladen: %s (%s)",
  ["invite.chat.failed"] = "Einladung fehlgeschlagen: %s (%s)",
  ["invite.reply.group"] = "Ich lade dich ein, %s.",
  ["invite.reply.guild"] = "Gildeneinladung für dich, %s.",
  ["invite.why.no-api"] = "In diesem Client nicht verfügbar.",
  ["invite.why.combat"] = "Im Kampf nicht möglich.",
  ["invite.why.offline"] = "Der Spieler ist offline.",
  ["invite.why.faction"] = "Der Spieler gehört zur anderen Fraktion.",
  ["invite.why.in-group"] = "Der Spieler ist schon in deiner Gruppe.",
  ["invite.why.group-full"] = "Deine Gruppe ist voll.",
  ["invite.why.not-leader"] = "Nur der Gruppenleiter kann einladen.",
  ["invite.why.error"] = "Das Spiel hat die Einladung abgelehnt.",
})

local PREFIX = { group = "inviteGroup", guild = "inviteGuild" }
local MAX_SCAN = 3000
local MAX_CLUBS = 20
local ROSTER_ASK = 30
-- Race tokens of the factions the client knows; anything else counts as unknown.
local RACE_FACTION = {
  Human = "Alliance",
  Dwarf = "Alliance",
  NightElf = "Alliance",
  Gnome = "Alliance",
  Draenei = "Alliance",
  Orc = "Horde",
  Scourge = "Horde",
  Tauren = "Horde",
  Troll = "Horde",
  BloodElf = "Horde",
}

local rate = IL.NewRate()
local cache = { names = {}, dirty = true, asked = -1e9 }

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

-- Protected call by global name: ok, then the values.
local function protected(name, ...)
  local fn = g(name)
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end

local function clock()
  return tonumber(try(g("GetTime"))) or 0
end

local function inCombat()
  return try(g("InCombatLockdown")) == true
end

function I.ResetRate()
  rate = IL.NewRate()
end

-- Settings -------------------------------------------------------------------------------------

function I.Config(kind)
  local s, p = ns.db.settings, PREFIX[kind]
  return {
    enabled = s[p] == true,
    words = IL.ParseWords(s[p .. "Words"]),
    mode = IL.CleanMode(s[p .. "Mode"]),
    minLevel = IL.CleanLevel(s[p .. "MinLevel"]),
    skipAway = s.inviteSkipAway == true,
    replyOn = s[p .. "ReplyOn"] == true,
    reply = type(s[p .. "Reply"]) == "string" and s[p .. "Reply"] or "",
    notify = s[p .. "Notify"] ~= false,
  }
end

-- Guild rights: only CanGuildInvite() decides, nothing is tried without it.
function I.CanGuild()
  return try(g("CanGuildInvite")) == true
end

function I.CommunitiesAvailable()
  local club = g("C_Club")
  return type(club) == "table"
    and type(club.GetSubscribedClubs) == "function"
    and type(club.GetClubMembers) == "function"
    and type(club.GetMemberInfo) == "function"
end

-- Log ---------------------------------------------------------------------------------------------

function I.Log()
  if type(ns.db.inviteLog) ~= "table" then
    ns.db.inviteLog = {}
  end
  return ns.db.inviteLog
end

local function record(kind, name, result, reason)
  IL.PushLog(I.Log(), { t = ns.U.now(), name = name, kind = kind, result = result, reason = reason })
  ns.Emit("FG_INVITE_LOG")
end

-- Facts from the game -------------------------------------------------------------------------

local function scanGuild()
  local names = {}
  if try(g("IsInGuild")) == true then
    local count = tonumber(try(g("GetNumGuildMembers"))) or 0
    if count == 0 then
      -- The roster is not loaded yet; ask once in a while, the update event marks it dirty again.
      local now = clock()
      if now - cache.asked >= ROSTER_ASK then
        cache.asked = now
        local info = g("C_GuildInfo")
        try(type(info) == "table" and info.GuildRoster or g("GuildRoster"))
      end
      return
    end
    for i = 1, math.min(count, MAX_SCAN) do
      local ok, name, _, _, level = protected("GetGuildRosterInfo", i)
      if ok and type(name) == "string" then
        names[PN.Key(name)] = { level = tonumber(level) }
      end
    end
  end
  cache.names, cache.dirty = names, false
end

-- Cached roster entry of a player, nil when not in the guild. Not scanned in combat.
local function guildEntry(name)
  if cache.dirty and not inCombat() then
    scanGuild()
  end
  return cache.names[PN.Key(name)]
end

local function isGuildMember(name, guid)
  if guid and try(g("IsGuildMember"), guid) == true then
    return true
  end
  return guildEntry(name) ~= nil
end

local function isFriend(name, guid)
  local list = g("C_FriendList")
  if guid and type(list) == "table" and try(list.IsFriend, guid) == true then
    return true
  end
  local battle = g("C_BattleNet")
  if guid and type(battle) == "table" and try(battle.GetAccountInfoByGUID, guid) ~= nil then
    return true
  end
  if type(list) == "table" then
    for i = 1, tonumber(try(list.GetNumFriends)) or 0 do
      local info = try(list.GetFriendInfoByIndex, i)
      if type(info) == "table" and type(info.name) == "string" and PN.Equal(info.name, name) then
        return true
      end
    end
  end
  return false
end

-- Shared with the automatic helpers (Modules/AutoGuard.lua).
I.IsGuildMember, I.IsFriend = isGuildMember, isFriend

local function inCommunity(name, guid)
  if inCombat() or not I.CommunitiesAvailable() then
    return false
  end
  local club = g("C_Club")
  local clubs = try(club.GetSubscribedClubs)
  local guildType = type(g("Enum")) == "table" and g("Enum").ClubType and g("Enum").ClubType.Guild or 1
  local seen = 0
  for i = 1, math.min(#(clubs or {}), MAX_CLUBS) do
    local entry = clubs[i]
    if type(entry) == "table" and entry.clubType ~= guildType and entry.clubId then
      for _, member in ipairs(try(club.GetClubMembers, entry.clubId) or {}) do
        seen = seen + 1
        if seen > MAX_SCAN then
          return false
        end
        local info = try(club.GetMemberInfo, entry.clubId, member)
        if type(info) == "table" then
          if (guid and info.guid == guid) or (type(info.name) == "string" and PN.Equal(info.name, name)) then
            return true
          end
        end
      end
    end
  end
  return false
end

local function isOwn(name)
  local roster = ns.CharRoster
  for _, e in ipairs(roster and roster.List() or {}) do
    if PN.Equal(PN.Join(e.name, e.surname), name) or PN.Equal(PN.ForWhisper(e.name, e.surname, e.realm), name) then
      return true
    end
  end
  return false
end

local function levelOf(name)
  local entry = guildEntry(name)
  if entry and entry.level then
    return entry.level
  end
  local list = g("C_FriendList")
  local info = type(list) == "table" and try(list.GetFriendInfo, name)
  return type(info) == "table" and tonumber(info.level) or nil
end

local function sameFaction(guid)
  if not guid then
    return nil
  end
  local ok, _, _, _, race = protected("GetPlayerInfoByGUID", guid)
  local theirs = ok and RACE_FACTION[race]
  local ours = try(g("UnitFactionGroup"), "player")
  if not theirs or type(ours) ~= "string" then
    return nil
  end
  return theirs == ours
end

local function groupState(name)
  local members = tonumber(try(g("GetNumGroupMembers"))) or 0
  return {
    hasGroup = try(g("IsInGroup")) == true,
    members = members,
    isRaid = try(g("IsInRaid")) == true,
    isLeader = try(g("UnitIsGroupLeader"), "player") == true or try(g("UnitIsGroupAssistant"), "player") == true,
    senderInGroup = try(g("UnitInParty"), name) == true or try(g("UnitInRaid"), name) ~= nil,
  }
end

local function facts(sender, guid, viaBattleNet)
  return {
    relation = function(mode)
      if mode == "friends" then
        return viaBattleNet or isFriend(sender, guid)
      elseif mode == "guild" then
        return isGuildMember(sender, guid)
      elseif mode == "communities" then
        return inCommunity(sender, guid)
      elseif mode == "own" then
        return isOwn(sender)
      end
      return false
    end,
    available = function(mode)
      return mode ~= "communities" or I.CommunitiesAvailable()
    end,
    level = function()
      return levelOf(sender)
    end,
    sameFaction = function()
      return sameFaction(guid)
    end,
    away = function()
      return try(g("UnitIsAFK"), "player") == true or try(g("UnitIsDND"), "player") == true
    end,
    group = function()
      return groupState(sender)
    end,
    canGuildInvite = I.CanGuild,
    senderInGuild = function()
      return isGuildMember(sender, guid)
    end,
  }
end

-- Actions ----------------------------------------------------------------------------------------------

-- Returns ok, reason of the failure.
local function inviteGroup(name)
  local party = g("C_PartyInfo")
  local fn = type(party) == "table" and type(party.InviteUnit) == "function" and party.InviteUnit or g("InviteUnit")
  if type(fn) ~= "function" then
    return false, "no-api"
  end
  local ok = pcall(fn, name)
  return ok, not ok and "error" or nil
end

local function inviteGuild(name)
  if not I.CanGuild() then
    return false, "no-permission"
  end
  local info = g("C_GuildInfo")
  local fn = g("GuildInvite") or (type(info) == "table" and info.Invite)
  if type(fn) ~= "function" then
    return false, "no-api"
  end
  local ok = pcall(fn, name)
  return ok, not ok and "error" or nil
end

local function reply(kind, cfg, name, battleNetId)
  -- The client refuses addon chat messages while the chat restriction is active.
  if ns.AddonRestricted("Chat") then
    return
  end
  local template = cfg.reply ~= "" and cfg.reply or ns.L["invite.reply." .. kind]
  local text = IL.Reply(template, name)
  if not text then
    return
  end
  if battleNetId then
    protected("BNSendWhisper", battleNetId, text)
  else
    protected("SendChatMessage", text, "WHISPER", nil, name)
  end
end

local function process(kind, text, sender, guid, label, battleNetId)
  local cfg = I.Config(kind)
  if not cfg.enabled or not IL.Match(text, cfg.words) then
    return nil
  end
  local s = ns.db.settings
  local now = clock()
  local decision = IL.Decide({
    kind = kind,
    cfg = cfg,
    message = text,
    sender = sender,
    self = PN.Self(),
    allow = IL.ParseNames(s.inviteAllow),
    block = IL.ParseNames(s.inviteBlock),
    now = now,
    rate = rate,
    get = facts(sender, guid, battleNetId ~= nil),
  })
  local name = type(sender) == "string" and sender or tostring(label or "?")
  local result, reason = "ignored", decision.reason
  if decision.action == "invite" then
    local ok, why = (kind == "guild" and inviteGuild or inviteGroup)(sender)
    IL.RateRecord(rate, IL.RateKey(kind, sender), now)
    result, reason = ok and "invited" or "failed", ok and "ok" or why
    if ok and cfg.replyOn then
      reply(kind, cfg, sender, battleNetId)
    end
    if cfg.notify then
      local line = ns.L[ok and "invite.chat.invited" or "invite.chat.failed"]
      ns.Notify.chat(string.format(line, name, ns.L["invite.kind." .. kind]))
    end
  end
  -- A repeat inside the sender window is not worth a log line.
  if reason ~= "rate-sender" then
    record(kind, name, result, reason)
  end
  return decision, result
end

-- Manual invite (the "Invite" button of a contact row) ---------------------------------------------------

-- Why the button cannot invite now (key suffix of "invite.why.*"), nil when it can.
-- offline: the caller knows the player is offline.
function I.GroupInviteBlock(name, guid, offline)
  local party = g("C_PartyInfo")
  if not ((type(party) == "table" and type(party.InviteUnit) == "function") or type(g("InviteUnit")) == "function") then
    return "no-api"
  end
  if inCombat() then
    return "combat"
  end
  if offline then
    return "offline"
  end
  if sameFaction(guid) == false then
    return "faction"
  end
  return IL.GroupBlock(groupState(name))
end

-- The click is the consent: it invites once, after the same checks that dim the button.
function I.InviteToGroup(name, guid, offline)
  name = PN.Clean(name)
  local reason = name == "" and "error" or I.GroupInviteBlock(name, guid, offline)
  local ok
  if not reason then
    ok, reason = inviteGroup(name)
  end
  if ok then
    ns.Notify(string.format(ns.L["invite.chat.invited"], name, ns.L["invite.kind.group"]), "success")
    return true
  end
  ns.Notify(string.format(ns.L["invite.chat.failed"], name, ns.L["invite.why." .. reason] or reason), "warning")
  return false, reason
end

-- Entry points -------------------------------------------------------------------------------------

function I.OnWhisper(text, sender, guid)
  if not ns.db or type(text) ~= "string" then
    return
  end
  for _, kind in ipairs({ "group", "guild" }) do
    process(kind, text, sender, guid)
  end
end

-- Battle.net whisper: the invite goes to the WoW character of that friend.
function I.OnBattleNetWhisper(text, label, id)
  if not ns.db or type(text) ~= "string" then
    return
  end
  local name
  local api = g("C_BattleNet")
  local info = type(api) == "table" and try(api.GetAccountInfoByID, id)
  local game = type(info) == "table" and info.gameAccountInfo
  if type(game) == "table" and game.clientProgram == "WoW" and type(game.characterName) == "string" then
    name = PN.Normalize(PN.ForWhisper(game.characterName, nil, game.realmName))
  end
  for _, kind in ipairs({ "group", "guild" }) do
    process(kind, text, name ~= "" and name or nil, nil, label, id)
  end
end

ns.On("CHAT_MSG_WHISPER", function(_, text, sender, ...)
  I.OnWhisper(text, sender, (select(10, ...)))
end)
ns.On("CHAT_MSG_BN_WHISPER", function(_, text, label, ...)
  I.OnBattleNetWhisper(text, label, (select(11, ...)))
end)
local function dirty()
  cache.dirty = true
end
ns.On("GUILD_ROSTER_UPDATE", dirty)
ns.On("PLAYER_GUILD_UPDATE", dirty)
