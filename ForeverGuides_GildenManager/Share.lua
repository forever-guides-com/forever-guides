-- Sharing with other officers in the game (rules in ShareLogic.lua): the function gmShare of the message
-- line (Modules/Comm.lua) is the only way out and in. Nothing is registered, sent or read until the player
-- has agreed in the main add-on (Consent: gmShare, send and receive are separate, audience guild).
--   Sending    consent, a guild, a channel the rank can use, no fight, and a low pace: one message every
--              SEND_GAP seconds, a new round every ROUND_GAP seconds, only what changed since the last one.
--   Receiving  consent, the chosen channel, a sender on the roster whose rank is good enough, the category
--              on, no fight and a bucket per sender. What passes goes into the inbox, never into the record.
--   Leaving    taking back the send consent says goodbye (type R) to the channel that was told something,
--              taking back the receive consent empties the inbox.
local ADDON_NAME, gm = ...
if not gm.ext then
  return
end
local FG, SH, SL = gm.FG, gm.ShareLogic, gm.SettingsLogic
local Comm, CL, Consent, GD, PN = FG.Comm, FG.CommLogic, FG.Consent, FG.GuildData, FG.PlayerName
local LIM, FN = SH.LIMITS, SH.FN

local Share = {}
gm.Share = Share

-- Seconds before the first round after the add-on loaded or the send consent came.
Share.START_DELAY = 60
Share.MAX_BUCKETS = 100

local registered = false
local queue, lastRound, armed = {}, nil, false
-- Kinds this session really sent into (only those hear a goodbye).
local told = {}
-- peers[key] = { at, cats } of senders that said hello this session, memory only.
local peers, peerCount = {}, 0
local buckets, bucketCount = {}, 0
local roster

local function settings()
  return { guild = gm.Guild(), prefs = gm.db.prefs }
end

local function changed()
  FG.Emit("FG_GM_SHARE_CHANGED")
end

local function inGuild()
  local ok, value = pcall(rawget(_G, "IsInGuild") or function() end)
  return ok and value == true
end

-- The categories and limits the player chose.
function Share.Settings()
  local ctx = settings()
  return {
    cats = { J = SL.Get(ctx, "shareJoins"), M = SL.Get(ctx, "shareMarks"), N = SL.Get(ctx, "shareNotes") },
    channel = SL.Get(ctx, "shareChannel"),
    maxRank = SL.Get(ctx, "shareMinRank"),
  }
end

-- Whether the rank of this character can use the officer chat. The client has no plain question for it:
-- the right to see officer notes stands in (measured with a second officer, see TESTPLAN-IM-SPIEL.md).
function Share.OfficerChat()
  return GD.Can("CanViewOfficerNote") == true or GD.Can("CanEditOfficerNote") == true
end

function Share.ChannelAvailable(channel)
  return channel == "guild" or Share.OfficerChat()
end

-- True while this direction may work right now: consent, a guild that can be saved, no demo roster.
function Share.Active(dir)
  return Consent.Allows(FN, dir, "guild") and inGuild() and gm.WriteBlock() == nil and GD.Source() == nil
end

local function anyOn(cats)
  return cats.J == true or cats.M == true or cats.N == true
end

-- Receiving ---------------------------------------------------------------------------------------------

local function rosterIndex()
  local snap = GD.Get()
  if roster and roster.snap == snap then
    return roster
  end
  local keys, rows = {}, {}
  for _, m in ipairs(snap.members or {}) do
    keys[m.key], rows[m.key] = true, m
  end
  roster = { snap = snap, keys = keys, rows = rows }
  return roster
end

local function within(key)
  local b = buckets[key]
  if not b then
    if bucketCount >= Share.MAX_BUCKETS then
      buckets, bucketCount = {}, 0
    end
    b = CL.NewBucket(LIM.RECEIVE_BURST, LIM.RECEIVE_REFILL, function()
      return Comm.clock()
    end)
    buckets[key], bucketCount = b, bucketCount + 1
  end
  return b.Take()
end

-- The checks every incoming message passes after the line did its own. Returns the roster row of the
-- sender and the index, or nil.
local function admitted(sender, info, needRank)
  if not Share.Active("receive") or FG.InCombat() then
    return nil
  end
  local cfg = Share.Settings()
  if (info.channel == "OFFICER") ~= (cfg.channel == "officer") then
    return nil
  end
  local idx = rosterIndex()
  local row = idx.rows[PN.Key(sender)]
  if not row or (needRank and not SH.RankAllowed(row.rank, cfg.maxRank)) or not within(row.key) then
    return nil
  end
  return row, idx, cfg
end

local function onData(sender, value, info)
  if type(value) ~= "table" or value.kind ~= "data" then
    return
  end
  local row, idx, cfg = admitted(sender, info, true)
  local today, now = gm.History.Clock()
  if not row or not cfg.cats[value.cat] or not today then
    return
  end
  local added = SH.Accept(gm.Guild(), value.cat, value.rows, {
    name = row.name,
    key = row.key,
    rank = row.rankName,
    rankIndex = row.rank,
  }, { now = now, today = today, roster = idx.keys })
  if added > 0 then
    SH.Count(gm.Guild(), "received", added)
    changed()
  end
end

local function onHello(sender, value, info)
  if type(value) ~= "table" or value.kind ~= "hello" then
    return
  end
  local row = admitted(sender, info, true)
  if row then
    if not peers[row.key] then
      peerCount = peerCount + 1
    end
    peers[row.key] = { at = Comm.clock(), cats = value.cats }
    changed()
  end
end

-- The sender took the consent back: what it offered goes with it.
local function onBye(sender, value, info)
  if type(value) ~= "table" or value.kind ~= "bye" then
    return
  end
  local row = admitted(sender, info, false)
  if row then
    if peers[row.key] then
      peers[row.key], peerCount = nil, peerCount - 1
    end
    SH.DiscardAll(gm.Guild(), row.key)
    changed()
  end
end

local function decode(payload)
  local today = gm.History.Clock()
  return today and SH.Decode(payload, today) or nil
end

-- Number of officers that said hello in this session.
function Share.Peers()
  return peerCount
end

-- Sending ------------------------------------------------------------------------------------------------

local function canSend()
  return registered and Share.Active("send") and Share.ChannelAvailable(Share.Settings().channel) and not FG.InCombat()
end

local function buildRound()
  local guild, cfg = gm.Guild(), Share.Settings()
  local today = gm.History.Clock()
  local idx = rosterIndex()
  queue = {}
  if not today or not anyOn(cfg.cats) or not idx.snap.loaded then
    return
  end
  local share = guild.share
  if not share.full or today - share.full >= LIM.FULL_DAYS then
    share.sent, share.full = {}, today
  end
  local batches = SH.Batches(SH.Collect(guild, idx.keys, cfg.cats, share.sent))
  if #batches == 0 then
    return
  end
  queue[1] = { typ = "H", payload = SH.Hello(cfg.cats) }
  for i = 1, math.min(#batches, LIM.ROUND_MESSAGES) do
    queue[#queue + 1] = { typ = "D", payload = batches[i].payload, batch = batches[i] }
  end
end

-- One message of the round, when it is time. Returns true when something was queued for the line.
function Share.Tick()
  if not canSend() then
    queue = {}
    return false
  end
  local now = Comm.clock()
  if #queue == 0 and (lastRound == nil or now - lastRound >= LIM.ROUND_GAP) then
    lastRound = now
    buildRound()
  end
  local item = queue[1]
  while item and item.batch and not Share.Settings().cats[item.batch.cat] do
    table.remove(queue, 1)
    item = queue[1]
  end
  if not item or Comm.Queued() > 0 then
    return false
  end
  table.remove(queue, 1)
  local channel = Share.Settings().channel
  if not Comm.Send(FN, item.typ, item.payload, channel, nil, { priority = "background" }) then
    queue = {}
    return false
  end
  told[channel] = true
  if item.batch then
    local guild = gm.Guild()
    SH.NoteSent(guild.share.sent, item.batch)
    SH.Count(guild, "sent", #item.batch.records)
    changed()
  end
  return true
end

-- One timer at a time, as long as sending is agreed to. A timer that fires at once (tests) must not loop.
local depth = 0

local function arm(delay)
  local timer = rawget(_G, "C_Timer")
  if armed or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  armed = true
  timer.After(delay, function()
    armed = false
    depth = depth + 1
    if depth <= 1 then
      FG.Safe("gm-share", Share.Tick)
      if registered and Consent.Allows(FN, "send", "guild") then
        arm(LIM.SEND_GAP)
      end
    end
    depth = depth - 1
  end)
end

-- Goodbye to every channel this session told something. The line allows it after the consent went off.
local function farewell()
  for kind in pairs(told) do
    Comm.Send(FN, "R", "", kind)
  end
  told = {}
end

-- Registration and events ---------------------------------------------------------------------------------

-- Registers the function with the line. Only called once a consent is on: without one the line does not
-- know the function at all.
function Share.Register()
  if not registered then
    registered = Comm.Register(FN, {
      version = 1,
      audiences = { "guild", "officer" },
      on = { H = onHello, D = onData, R = onBye },
      decode = decode,
      farewell = "R",
    }) == true
  end
  return registered
end

function Share.Registered()
  return registered
end

function Share.Status()
  return { queued = #queue, peers = peerCount, registered = registered, lastRound = lastRound }
end

-- Actions of the page.
function Share.Adopt(offer)
  local today = gm.History.Clock()
  if not today then
    return false, "gone"
  end
  local ok, why = SH.Adopt(gm.Guild(), offer, today)
  changed()
  return ok, why
end

function Share.Discard(offer)
  local ok = SH.Discard(gm.Guild(), offer)
  changed()
  return ok
end

function Share.DiscardAll()
  local n = SH.DiscardAll(gm.Guild())
  changed()
  return n
end

-- Deletes the inbox, the counters and the record of what was sent.
function Share.Wipe()
  SH.Wipe(gm.Guild())
  SH.Clean(gm.Guild())
  queue, lastRound = {}, nil
  changed()
end

FG.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= FN or aud ~= "guild" then
    return
  end
  if value == true then
    Share.Register()
    if dir == "send" then
      -- A new agreement starts from scratch: what an earlier goodbye wiped at the others goes out again.
      local share = gm.Guild().share
      share.sent, share.full = {}, nil
      lastRound = nil
      arm(Share.START_DELAY)
    end
  elseif dir == "send" then
    queue = {}
    farewell()
  else
    SH.DiscardAll(gm.Guild())
    peers, peerCount = {}, 0
  end
  changed()
end)
FG.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == FN then
    queue = {}
    farewell()
    SH.DiscardAll(gm.Guild())
    peers, peerCount = {}, 0
    changed()
  end
end)
FG.On("PLAYER_GUILD_UPDATE", function()
  queue, lastRound, roster = {}, nil, nil
end)

FG.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then
    return
  end
  Consent.MarkAvailable(FN)
  if Consent.Allows(FN, "send", "guild") or Consent.Allows(FN, "receive", "guild") then
    Share.Register()
    arm(Share.START_DELAY)
  end
end)
