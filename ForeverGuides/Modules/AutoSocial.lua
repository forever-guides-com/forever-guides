-- Duels and group invites, all off by default. The switch autoSocial covers:
-- * Duel requests are declined unless the challenger is a friend, guild member or in my group.
-- * Group invites of everyone else are declined (autoSocialDecline, off by default), also not while
--   queued: a Group Finder invite comes from a stranger.
-- Accepting group invites has one switch per group, independent of autoSocial: friends
-- (autoSocialAcceptFriends), guild members (autoSocialAcceptGuild) and contacts, the recently seen
-- players (autoSocialAcceptContacts). Never while queued for a dungeon, raid, group finder or
-- battleground, because joining a group would end the queue.
-- The override key leaves the decision to the player. An invite from the host of a layer switch is left to
-- LayerSwitch.lua, which accepts it (and nothing else) when the player asked that host.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local S = {}
ns.AutoSocial = S

ns.AddLocale("enUS", {
  ["auto.social.duel"] = "Duel from %s declined (%s lets it through)",
  ["auto.social.accepted"] = "Group invite from %s accepted",
  ["auto.social.declined"] = "Group invite from %s declined",
})
ns.AddLocale("deDE", {
  ["auto.social.duel"] = "Duell von %s abgelehnt (%s lässt es durch)",
  ["auto.social.accepted"] = "Gruppeneinladung von %s angenommen",
  ["auto.social.declined"] = "Gruppeneinladung von %s abgelehnt",
})

local ID = "autoSocial"
local INVITE_ID = "autoInvite"
-- LFG categories (dungeon finder, raid finder, ...) and the largest battlefield queue index.
local LFG_CATEGORIES = 5
local MAX_QUEUES = 3

local function settings()
  return ns.db.settings
end

-- Queued for anything, or the game does not say: then a group invite stays with the player.
local function queued()
  local known = false
  for category = 1, LFG_CATEGORIES do
    local found, mode = Guard.Call("GetLFGMode", category)
    known = known or found
    if found and mode then
      return true
    end
  end
  local foundEntry, listed = Guard.Call("C_LFGList.HasActiveEntryInfo")
  local foundApps, applications = Guard.Call("C_LFGList.GetApplications")
  known = known or foundEntry or foundApps
  if listed == true or (type(applications) == "table" and #applications > 0) then
    return true
  end
  local foundMax, maxQueues = Guard.Call("GetMaxBattlefieldID")
  maxQueues = foundMax and Guard.Safe(maxQueues) or MAX_QUEUES
  for index = 1, type(maxQueues) == "number" and maxQueues or MAX_QUEUES do
    local found, status = Guard.Call("GetBattlefieldStatus", index)
    known = known or found
    if found and (status == "queued" or status == "confirm") then
      return true
    end
  end
  return not known
end

-- The layer switch (LayerSwitch.lua) takes this check too: it must not end a queue either.
S.Queued = queued

local function hidePopup(which)
  if Guard.Has("StaticPopup_Hide") then
    Guard.Call("StaticPopup_Hide", which)
  end
end

function S.OnDuel(challenger)
  challenger = Guard.Safe(challenger)
  if settings().autoSocialDuel == false or Guard.Paused() or type(challenger) ~= "string" then
    return
  end
  if Guard.Trusted(challenger) then
    return
  end
  Guard.Call("CancelDuel")
  hidePopup("DUEL_REQUESTED")
  Guard.Say(ID, string.format(L["auto.social.duel"], challenger, Guard.KeyName()))
end

-- Each group (friends, guild, contacts) has its own switch, independent of autoSocial.
local function mayAccept(inviter, guid)
  local s = settings()
  return (s.autoSocialAcceptFriends == true and Guard.IsFriend(inviter, guid))
    or (s.autoSocialAcceptGuild == true and Guard.IsGuildMember(inviter, guid))
    or (s.autoSocialAcceptContacts == true and Guard.IsContact(inviter, guid))
end

-- Returns true when the invite was accepted.
function S.OnAccept(inviter, _, _, _, _, _, guid)
  inviter = Guard.Safe(inviter)
  if Guard.Paused() or type(inviter) ~= "string" or inviter == "" or queued() then
    return false
  end
  if not mayAccept(inviter, guid) then
    return false
  end
  Guard.Call("AcceptGroup")
  hidePopup("PARTY_INVITE")
  Guard.Say(INVITE_ID, string.format(L["auto.social.accepted"], inviter))
  return true
end

function S.OnDecline(inviter, _, _, _, _, _, guid)
  inviter = Guard.Safe(inviter)
  if Guard.Paused() or type(inviter) ~= "string" or inviter == "" or queued() then
    return
  end
  -- The host of a layer switch the player asked for is no stranger: that invite is the point of the switch.
  local layer = ns.LayerSwitch
  if layer and layer.Expects(inviter) then
    return
  end
  if settings().autoSocialDecline == true and not Guard.Related(inviter, guid) then
    Guard.Call("DeclineGroup")
    hidePopup("PARTY_INVITE")
    Guard.Say(ID, string.format(L["auto.social.declined"], inviter))
  end
end

ns.On("DUEL_REQUESTED", function(_, challenger)
  Guard.Run(ID, S.OnDuel, challenger)
end)

ns.On("PARTY_INVITE_REQUEST", function(_, ...)
  local _, accepted = Guard.Run(INVITE_ID, S.OnAccept, ...)
  if not accepted then
    Guard.Run(ID, S.OnDecline, ...)
  end
end)
