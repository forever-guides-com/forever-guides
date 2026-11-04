-- Whisper invite: a whisper that is a keyword invites the sender to the group and/or the
-- guild, depending on the settings (Store: inviteGroup*, inviteGuild*). The rules live in
-- InviteLogic; this file asks the game for the facts and does the invite. Every game call is
-- wrapped in pcall. The sender name goes to the game exactly as the whisper delivered it
-- ("first surname", never cut at a blank). Off until a keyword is set.
-- The group invite is automatic. The guild invite is not: the game only takes it from a click, so a
-- whisper opens a request window or bar (InvitePrompt) and the guild call runs in the click handler of its button only.
-- Every whisper with a keyword ends in one chat line that says what happened, also for a "no".
local addonName, ns = ...
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
  ["invite.fb.line"] = "%s whispered %s: %s",
  ["invite.fb.invited"] = "invited to the group",
  ["invite.fb.guild-ready"] = "guild invite is ready, click the button on screen",
  ["invite.fb.guild-waiting"] = "in combat, the guild invite waits until it ends",
  ["invite.fb.guild-sent"] = "invited to the guild",
  ["invite.fb.guild-blocked"] = "the game blocked the direct call, click the button once more",
  ["invite.fb.guild-secure"] = "guild invite command sent, the game reports the result",
  ["invite.fb.guild-combat"] = "in combat, the guild invite waits",
  ["invite.fb.failed"] = "invite failed (%s)",
  ["invite.fb.off"] = "the automatic invite is off",
  ["invite.fb.no-sender"] = "the sender is unknown",
  ["invite.fb.blocked"] = "the player is on your block list",
  ["invite.fb.no-permission"] = "you may not invite to the guild (no right)",
  ["invite.fb.mode-unavailable"] = "the selected sender group is not available here",
  ["invite.fb.mode"] = "the player is not in your allowed group",
  ["invite.fb.away"] = "you are away or busy",
  ["invite.fb.level-unknown"] = "the level of the player is unknown",
  ["invite.fb.level"] = "the level is too low",
  ["invite.fb.faction"] = "the player belongs to the other faction",
  ["invite.fb.in-guild"] = "the player is already in the guild",
  ["invite.fb.in-group"] = "the player is already in your group",
  ["invite.fb.group-full"] = "your group is full",
  ["invite.fb.not-leader"] = "only the group leader can invite",
  ["invite.fb.rate-sender"] = "already handled a moment ago",
  ["invite.fb.rate-global"] = "too many invites in a short time",
  ["invite.fb.not-in-game"] = "no character found for this Battle.net contact (not in the game)",
  ["invite.fb.other-client"] = "the Battle.net contact plays another WoW version",
  ["invite.fb.no-api"] = "not available in this client",
  ["invite.fb.error"] = "the game refused the invite",
  ["invite.fb.unsafe-name"] = "the name cannot be used",
  ["invite.fb.not-from-click"] = "the guild invite needs a click",
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
  ["invite.fb.line"] = "%s hat %s geflüstert: %s",
  ["invite.fb.invited"] = "in die Gruppe eingeladen",
  ["invite.fb.guild-ready"] = "Gildeneinladung bereit, klicke den Knopf auf dem Bildschirm",
  ["invite.fb.guild-waiting"] = "im Kampf, die Gildeneinladung wartet bis zum Kampfende",
  ["invite.fb.guild-sent"] = "in die Gilde eingeladen",
  ["invite.fb.guild-blocked"] = "das Spiel hat den direkten Aufruf blockiert, klicke den Knopf noch einmal",
  ["invite.fb.guild-secure"] = "Gilden-Einladungsbefehl gesendet, das Spiel meldet das Ergebnis",
  ["invite.fb.guild-combat"] = "im Kampf, die Gildeneinladung wartet",
  ["invite.fb.failed"] = "Einladung fehlgeschlagen (%s)",
  ["invite.fb.off"] = "die automatische Einladung ist aus",
  ["invite.fb.no-sender"] = "der Absender ist unbekannt",
  ["invite.fb.blocked"] = "der Spieler steht auf deiner Sperrliste",
  ["invite.fb.no-permission"] = "du darfst nicht in die Gilde einladen (kein Recht)",
  ["invite.fb.mode-unavailable"] = "die gewählte Absendergruppe ist hier nicht verfügbar",
  ["invite.fb.mode"] = "der Spieler gehört nicht zu deiner erlaubten Gruppe",
  ["invite.fb.away"] = "du bist abwesend oder beschäftigt",
  ["invite.fb.level-unknown"] = "die Stufe des Spielers ist unbekannt",
  ["invite.fb.level"] = "die Stufe ist zu niedrig",
  ["invite.fb.faction"] = "der Spieler gehört zur anderen Fraktion",
  ["invite.fb.in-guild"] = "der Spieler ist schon in der Gilde",
  ["invite.fb.in-group"] = "der Spieler ist schon in deiner Gruppe",
  ["invite.fb.group-full"] = "deine Gruppe ist voll",
  ["invite.fb.not-leader"] = "nur der Gruppenleiter kann einladen",
  ["invite.fb.rate-sender"] = "gerade schon bearbeitet",
  ["invite.fb.rate-global"] = "zu viele Einladungen in kurzer Zeit",
  ["invite.fb.not-in-game"] = "kein Charakter zu diesem Battle.net-Kontakt gefunden (nicht im Spiel)",
  ["invite.fb.other-client"] = "der Battle.net-Kontakt spielt eine andere WoW-Version",
  ["invite.fb.no-api"] = "in diesem Client nicht verfügbar",
  ["invite.fb.error"] = "das Spiel hat die Einladung abgelehnt",
  ["invite.fb.unsafe-name"] = "der Name kann nicht verwendet werden",
  ["invite.fb.not-from-click"] = "die Gildeneinladung braucht einen Klick",
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

-- A declined or closed request starts the wait of its sender again from now on, so asking again right after
-- declining waits the chosen time.
function I.Touch(kind, sender)
  IL.RateTouch(rate, IL.RateKey(kind, sender), clock())
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

-- Retail allows guilds and groups across the factions, the game answers itself when it refuses: only the
-- Classic based clients (Forever) check the faction before the invite. nil counts as unknown and never blocks.
local function sameFaction(guid)
  if not guid or (ns.Client and ns.Client.IsRetail()) then
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

-- The game reports a call it refuses (a restricted function outside a click) as an event, not as a Lua
-- error, so no pcall can see it. The flag is only set for the length of one call.
local blockedFlag = nil
local function onBlocked(_, who)
  if who == addonName and blockedFlag ~= nil then
    blockedFlag = true
  end
end
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)
ns.On("ADDON_ACTION_BLOCKED", onBlocked)

-- Runs fn(name). Answers "sent", "blocked" (the game refused it by event) or false and a reason.
local function guarded(fn, name)
  blockedFlag = false
  local ok = pcall(fn, name)
  local blocked = blockedFlag
  blockedFlag = nil
  if blocked then
    return "blocked"
  end
  if ok then
    return "sent"
  end
  return false, "error"
end

-- Returns ok, reason of the failure.
local function inviteGroup(name)
  local party = g("C_PartyInfo")
  local fn = type(party) == "table" and type(party.InviteUnit) == "function" and party.InviteUnit or g("InviteUnit")
  if type(fn) ~= "function" then
    return false, "no-api"
  end
  local status, why = guarded(fn, name)
  return status == "sent", status == "blocked" and "error" or why
end

-- Depth of the click handler of the guild bar that is running. The guild call needs a click and is
-- refused for every other caller, a chat event above all.
local clickDepth = 0

-- The guild invite, the only place that calls the game for it. Answers "sent", "blocked" or false and a
-- reason.
function I.GuildInviteFromClick(name)
  if clickDepth == 0 then
    return false, "not-from-click"
  end
  if not I.CanGuild() then
    return false, "no-permission"
  end
  local info = g("C_GuildInfo")
  local fn = type(info) == "table" and type(info.Invite) == "function" and info.Invite or g("GuildInvite")
  if type(fn) ~= "function" then
    return false, "no-api"
  end
  return guarded(fn, name)
end

local function clickInvite(name)
  clickDepth = clickDepth + 1
  local ok, status, why = pcall(I.GuildInviteFromClick, name)
  clickDepth = clickDepth - 1
  if ok then
    return status, why
  end
  return false, "error"
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

-- Feedback ----------------------------------------------------------------------------------------------

-- Without a keyword setting the plain words still get an answer, so a whisper never vanishes silently.
local DEFAULT_WORD = { group = "inv", guild = "ginv" }
local FEEDBACK_WINDOW = 30
local told = {}

-- A hidden (secret) value of Retail 12 must not be compared, measured or shown.
local function isSecret(value)
  local check = g("issecretvalue")
  if type(check) ~= "function" then
    return false
  end
  local ok, hidden = pcall(check, value)
  return not ok or hidden == true
end

local function plainString(value)
  return type(value) == "string" and value ~= "" and not isSecret(value) and value or nil
end

-- One chat line "<who> whispered <word>: <result>". A refusal repeats at most once per window and
-- sender; what was done (invited, asked) always shows.
local function feedback(cfg, who, keyword, code, why, repeatable)
  if cfg.notify == false then
    return
  end
  if repeatable then
    local now, key = clock(), tostring(who):lower() .. "|" .. keyword .. "|" .. code
    if told[key] and now - told[key] < FEEDBACK_WINDOW then
      return
    end
    told[key] = now
  end
  local result = ns.L["invite.fb." .. code] or code
  if why then
    result = string.format(result, ns.L["invite.fb." .. why] or why)
  end
  ns.Notify.chat(string.format(ns.L["invite.fb.line"], who, keyword, result))
end

-- What the whisper line and the friend list tell about the sender (class and level), for the look of the
-- request. Missing values stay out; nothing is asked of the game beyond what it already knows.
local function senderInfo(name, guid)
  local info = {}
  if guid and not isSecret(guid) then
    local ok, className, token = protected("GetPlayerInfoByGUID", guid)
    if ok then
      info.className, info.class = plainString(className), plainString(token)
    end
  end
  info.level = levelOf(name)
  return info
end

-- The bar of a guild request; the invite itself happens on its click (see GuildInviteFromClick).
local function askGuild(cfg, name, who, keyword, battleNetId, info)
  local prompt = ns.InvitePrompt
  if not prompt then
    return false, "no-api"
  end
  local function sent(target)
    record("guild", who, "invited", "ok")
    feedback(cfg, who, keyword, "guild-sent")
    if cfg.replyOn then
      reply("guild", cfg, target, battleNetId)
    end
  end
  local state, why = prompt.Request(name, {
    invite = function(target)
      local status, reason = clickInvite(target)
      if status == "sent" then
        sent(target)
      elseif status == "blocked" then
        feedback(cfg, who, keyword, "guild-blocked")
      else
        feedback(cfg, who, keyword, "failed", reason or "error")
      end
      return status
    end,
    combat = function()
      feedback(cfg, who, keyword, "guild-combat", nil, true)
    end,
    closed = function(target)
      I.Touch("guild", target)
    end,
    sent = function(target)
      sent(target)
      feedback(cfg, who, keyword, "guild-secure")
    end,
  }, info)
  return state, why
end

local function process(kind, text, sender, guid, label, battleNetId, missing)
  local cfg = I.Config(kind)
  local keyword = IL.Match(text, #cfg.words > 0 and cfg.words or { DEFAULT_WORD[kind] })
  if not keyword then
    return nil
  end
  local who = plainString(sender) or plainString(label) or "?"
  if not cfg.enabled or #cfg.words == 0 then
    feedback(cfg, who, keyword, "off", nil, true)
    return nil
  end
  local s = ns.db.settings
  local now = clock()
  local decision
  if plainString(sender) == nil then
    decision = { action = "ignore", reason = missing or "no-sender", keyword = keyword }
  else
    decision = IL.Decide({
      kind = kind,
      cfg = cfg,
      message = text,
      sender = sender,
      self = PN.Self(),
      allow = IL.ParseNames(s.inviteAllow),
      block = IL.ParseNames(s.inviteBlock),
      now = now,
      rate = rate,
      cooldown = IL.CleanCooldown(s.inviteSenderCooldown),
      globalLimit = IL.CleanGlobalLimit(s.inviteGlobalLimit),
      get = facts(sender, guid, battleNetId ~= nil),
    })
  end
  local result, reason = "ignored", decision.reason
  if decision.action == "invite" then
    IL.RateRecord(rate, IL.RateKey(kind, sender), now)
    if kind == "guild" then
      local state, why = askGuild(cfg, PN.Clean(sender), who, keyword, battleNetId, senderInfo(sender, guid))
      if state then
        result, reason = "asked", state
        -- A request in line is not worth a chat line each: 200 of them would fill the chat.
        if state ~= "queued" then
          feedback(cfg, who, keyword, state == "ready" and "guild-ready" or "guild-waiting")
        end
      else
        result, reason = "failed", why
        feedback(cfg, who, keyword, "failed", why)
      end
    else
      local ok, why = inviteGroup(sender)
      result, reason = ok and "invited" or "failed", ok and "ok" or why
      if ok and cfg.replyOn then
        reply(kind, cfg, sender, battleNetId)
      end
      if ok then
        feedback(cfg, who, keyword, "invited")
      else
        feedback(cfg, who, keyword, "failed", why)
      end
    end
  elseif reason ~= "self" then
    feedback(cfg, who, keyword, reason, nil, true)
  end
  -- A repeat inside the sender window is not worth a log line.
  if reason ~= "rate-sender" then
    record(kind, who, result, reason)
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
  if not ns.db or type(text) ~= "string" or isSecret(text) or isSecret(sender) then
    return
  end
  for _, kind in ipairs({ "group", "guild" }) do
    process(kind, text, sender, guid)
  end
end

-- The character of a Battle.net contact: name (Retail "Name-Realm", Forever "First Surname") or nil and
-- the reason code ("not-in-game", "other-client").
local function resolveBattleNet(id)
  local api = g("C_BattleNet")
  local info = type(api) == "table" and type(id) == "number" and not isSecret(id) and try(api.GetAccountInfoByID, id)
  local game = type(info) == "table" and info.gameAccountInfo
  if type(game) ~= "table" or game.clientProgram ~= "WoW" then
    return nil, "not-in-game"
  end
  local mine, theirs = g("WOW_PROJECT_ID"), game.wowProjectID
  if type(mine) == "number" and type(theirs) == "number" and mine ~= theirs then
    return nil, "other-client"
  end
  local character = plainString(game.characterName)
  if not character then
    return nil, "not-in-game"
  end
  local full
  if PN.MultiWord() then
    full = PN.Clean(character)
  else
    full = PN.ForWhisper(character, nil, plainString(game.realmName))
  end
  return full ~= "" and full or nil, "not-in-game"
end

-- Battle.net whisper: the invite goes to the WoW character of that friend.
function I.OnBattleNetWhisper(text, label, id)
  if not ns.db or type(text) ~= "string" or isSecret(text) then
    return
  end
  local name, code = resolveBattleNet(id)
  for _, kind in ipairs({ "group", "guild" }) do
    process(kind, text, name, nil, label, id, code)
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
