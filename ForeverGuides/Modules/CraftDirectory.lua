-- Crafting, receiving side: the directory of what the guild members share and the question "who in the
-- guild can make recipe X". Data only, the windows are another package. Everything needs the consent
-- crafting.receive (audience guild): without it nothing is stored, asked or fetched.
--   J   summary of a member (jobs, skill, count, checksum): kept as a directory entry, 14 days
--   K   live answer to the own question W: kept as a single answer, 3 days
--   C   recipe set of a job after the own fetch R: mask or id list, checked against count and checksum
--   X   the member withdrew: the entry and the answers of that member go
-- K and C come as whispers, which anybody can send: they count only for a nonce this client asked with
-- in the last 30 seconds (W or R), only from a guild member, and for R only from the member asked.
-- Saved as ns.db.guildSync (CraftDirectoryLogic), one store per guild, only other members, no own recipes.
-- What clears it: switching receiving off, withdrawing the consent (all guilds), leaving the guild or
-- changing it, a member that left the roster, X, expiry (on login and while running).
--   CraftDirectory.Ask(spell)        sends W; the hits come as FG_CRAFT_UPDATE (debounced, no arguments)
--   CraftDirectory.Asking(spell)     true during the wait for answers
--   CraftDirectory.Fetch(slug)       queues the R for the online members whose set of the job is missing or old
--   CraftDirectory.Crafters(spell)   list, info: members that can make it, with data of the guild roster
--   CraftDirectory.Coverage()        { sharing, total, loaded }: "12 of 87 members share their recipes"
--   CraftDirectory.Stats()           numbers for the tab Teilen
local _, ns = ...
local Comm, Consent, PN, L, G = ns.Comm, ns.Consent, ns.PlayerName, ns.GuildSyncLogic, ns.GuildSyncCodec
local CS, CDL, RU = ns.CraftShare, ns.CraftDirectoryLogic, ns.RecipeUniverse

local CD = {}
ns.CraftDirectory = CD

CD.FN = "crafting"
-- Seconds of the debounce of FG_CRAFT_UPDATE, of the wait for answers to W, and a nonce stays valid.
CD.DEBOUNCE = 1
CD.ASK_WAIT = 6
CD.NONCE_TTL = 30
-- Fetches: at most `open` at once (one per member), `burst` in a moment and `perMinute` over time, `gap`
-- seconds between two rounds of the queue, `retry` seconds before a member is asked again for the same job,
-- `queue` entries.
CD.FETCH = { open = 3, burst = 3, perMinute = 20, gap = 1.2, retry = 300, queue = 60 }
-- Seconds between two sweeps of expired data while running (epoch seconds).
CD.SWEEP = 600

-- Replaceable in tests: epoch seconds and a random integer from 1 to n.
function CD.now()
  return ns.U.now()
end
function CD.random(n)
  return math.random(n)
end

local function clock()
  return Comm.clock()
end

local function g(name)
  return rawget(_G, name)
end

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

local function inGuild()
  return try(g("IsInGuild")) == true
end

local function inCombat()
  local guard = ns.AutoGuard
  return (guard and guard.Blocked()) or ns.InCombat()
end

local function allowed()
  return Consent.Allows(CD.FN, "receive", "guild")
end

local function whole(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

-- Memory state: open requests by nonce, who is asked, the fetch queue, counters of what was refused.
local pending, openBy, askOpen = {}, {}, {}
local queue, queued, cooldown = {}, {}, {}
local drops = {}
local pumpGen, pumpArmed, depth = 0, false, 0
local curGuild, lastSweep, checked = nil, nil, nil
local scratch = CDL.NewRoot()
local fetchBucket
local noteGuild
local intake = assert(L.NewIntake(clock))

local function drop(reason)
  drops[reason] = (drops[reason] or 0) + 1
end

local function changed()
  ns.Debounce("craft-update", CD.DEBOUNCE, function()
    ns.Emit("FG_CRAFT_UPDATE")
  end)
end

-- Storage ---------------------------------------------------------------------------------------------------

-- The saved root, repaired once per saved table.
local function root()
  local db = ns.db
  if type(db) ~= "table" then
    return scratch
  end
  if db.guildSync ~= checked or type(db.guildSync) ~= "table" then
    local ok, clean = pcall(CDL.Clean, db.guildSync, CD.now())
    db.guildSync = ok and clean or CDL.NewRoot()
    checked = db.guildSync
  end
  return db.guildSync
end

-- Key of the own guild: name and realm, nil when the game does not tell (yet).
local function guildKey()
  if not inGuild() then
    return nil
  end
  local ok, name, _, _, realm = pcall(g("GetGuildInfo") or function() end, "player")
  if not ok or type(name) ~= "string" or name == "" then
    local data = ns.GuildData
    local snap = data and data.Get()
    name = type(snap) == "table" and snap.inGuild and snap.name or nil
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(realm) ~= "string" or realm == "" then
    realm = try(g("GetNormalizedRealmName"))
  end
  return PN.Lower(name) .. "-" .. PN.Lower(type(realm) == "string" and realm or "")
end

local function sweepAll(r)
  local gone = 0
  for _, guild in pairs(r.guilds) do
    local members, answers = CDL.Sweep(guild, CD.now())
    gone = gone + members + answers
  end
  if gone > 0 then
    changed()
  end
end

-- The store of the own guild. create: make it when missing. nil without a guild or a readable guild name.
local function store(create)
  local key = guildKey()
  if not key then
    return nil
  end
  noteGuild(key)
  local r = root()
  local t = CD.now()
  if not lastSweep or t - lastSweep >= CD.SWEEP or t < lastSweep then
    lastSweep = t
    sweepAll(r)
  end
  local guild = r.guilds[key]
  if not guild and create then
    guild = CDL.NewGuild(t)
    r.guilds[key] = guild
    CDL.CapGuilds(r)
  end
  if guild and create then
    guild.at = t
  end
  return guild, key
end

-- Roster ---------------------------------------------------------------------------------------------------

local rosterSnap, rosterIndex
-- The guild roster of GuildData and its members by key, nil without a guild.
local function roster()
  local data = ns.GuildData
  local snap = data and data.Get()
  if type(snap) ~= "table" or snap.inGuild ~= true then
    return nil
  end
  if snap ~= rosterSnap then
    rosterSnap, rosterIndex = snap, {}
    for _, m in ipairs(snap.members) do
      rosterIndex[m.key] = m
    end
  end
  return snap, rosterIndex
end

-- Only the roster is believed: a whisper can come from anybody.
local function member(sender)
  if type(sender) ~= "string" or sender == "" or #sender > 64 then
    return nil
  end
  local name = PN.Normalize(sender)
  if name == "" or PN.Equal(name, PN.Self()) then
    return nil
  end
  local inv = ns.Invites
  if not (inv and inv.IsGuildMember(name, nil) == true) then
    return nil
  end
  return name, PN.Key(name)
end

-- Clearing ---------------------------------------------------------------------------------------------------

local function resetRequests()
  for nonce, p in pairs(pending) do
    if p.kind == "R" then
      Comm.Close(CD.FN, p.name, nonce)
    end
  end
  pending, openBy, askOpen = {}, {}, {}
  queue, queued, cooldown = {}, {}, {}
  pumpGen = pumpGen + 1
  pumpArmed = false
end

-- Removes everything saved (all guilds) and everything that waits.
function CD.Clear()
  local db = ns.db
  if type(db) == "table" then
    db.guildSync = CDL.NewRoot()
    checked = db.guildSync
  end
  scratch = CDL.NewRoot()
  resetRequests()
  changed()
end

-- Removes the store of one guild (left, changed).
local function forgetGuild(key)
  local r = root()
  if r.guilds[key] ~= nil then
    r.guilds[key] = nil
    changed()
  end
end

-- Notes the guild this client is in. A store of a guild that is not the own any more goes (left, changed).
noteGuild = function(key)
  if curGuild and key ~= curGuild then
    forgetGuild(curGuild)
    resetRequests()
  end
  curGuild = key
end

-- Notices a change of the guild; keeps nothing while receiving is off.
local function syncGuild()
  if not allowed() and not curGuild and next(root().guilds) == nil then
    return
  end
  local inside = inGuild()
  local key = inside and guildKey() or nil
  if inside and not key then
    return
  end
  noteGuild(key)
  if key and not allowed() then
    forgetGuild(key)
  end
end

-- Members that left the roster. Only a complete roster counts: the "online only" view lists fewer rows.
local function prune()
  if not allowed() then
    return
  end
  local snap, index = roster()
  if not snap or not snap.loaded or #snap.members < (tonumber(snap.total) or 0) then
    return
  end
  local guild = allowed() and store(false)
  if not guild then
    return
  end
  local function inRoster(key)
    return index[key] ~= nil
  end
  if CDL.Prune(guild, inRoster) > 0 then
    changed()
  end
end

-- Expiry on login, then the state of the guild.
function CD.Load()
  checked, lastSweep = nil, nil
  sweepAll(root())
  syncGuild()
end

-- Requests -------------------------------------------------------------------------------------------------

local function newNonce()
  for _ = 1, 8 do
    local nonce = G.NewNonce(CD.random)
    if not pending[nonce] then
      return nonce
    end
  end
end

local function finish(nonce)
  local p = pending[nonce]
  if not p then
    return
  end
  pending[nonce] = nil
  if p.kind == "R" then
    openBy[p.key] = nil
    Comm.Close(CD.FN, p.name, nonce)
  elseif askOpen[p.spell] == nonce then
    askOpen[p.spell] = nil
  end
end

-- Requests older than the nonce memory are over.
local function expire()
  local t = clock()
  for nonce, p in pairs(pending) do
    if t - p.at > CD.NONCE_TTL then
      finish(nonce)
    end
  end
end

-- The open request of a kind for this nonce, nil for anything else (unknown, too old, other transfer id).
local function openRequest(nonce, kind, ctx)
  local p = type(nonce) == "string" and pending[nonce] or nil
  if not p or p.kind ~= kind then
    return nil
  end
  if clock() - p.at > CD.NONCE_TTL then
    finish(nonce)
    return nil
  end
  if type(ctx) == "table" and ctx.id ~= nil and ctx.id ~= nonce then
    return nil
  end
  return p
end

-- Asking the guild (W) -------------------------------------------------------------------------------------

function CD.Asking(spell)
  expire()
  return askOpen[spell] ~= nil
end

local function timer(delay, fn)
  local t = g("C_Timer")
  if type(t) ~= "table" or type(t.After) ~= "function" then
    return false
  end
  return pcall(t.After, delay, function()
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("craftdirectory", fn)
    end
    depth = depth - 1
  end)
end

-- Asks the guild who can make the spell. Returns true and the nonce, or false and why: consent, guild,
-- spell, unregistered, combat, pending (the same question is open), cached (a live answer is younger than
-- 5 minutes: nothing to ask), throttle (one question per 10 s, 20 per hour), or the reason of the line.
function CD.Ask(spell)
  if not allowed() then
    return false, "consent"
  end
  if not inGuild() or not guildKey() then
    return false, "guild"
  end
  if not whole(spell, 1, G.LIMITS.MAX_SPELL) then
    return false, "spell"
  end
  if not CS.Register() then
    return false, "unregistered"
  end
  if inCombat() then
    return false, "combat"
  end
  expire()
  if askOpen[spell] then
    return false, "pending", askOpen[spell]
  end
  local guild = store(false)
  if guild and CDL.HasLive(guild, spell, CD.now()) then
    changed()
    return false, "cached"
  end
  if not CS.Allow("W") then
    return false, "throttle"
  end
  local nonce = newNonce()
  local payload = nonce and G.Encode(CD.FN, { typ = "W", nonce = nonce, spell = spell })
  if not payload then
    return false, "payload"
  end
  local ok, why = Comm.Send(CD.FN, "W", payload, "guild", nil, { id = nonce, priority = "click" })
  if not ok then
    return false, why
  end
  pending[nonce] = { kind = "W", at = clock(), spell = spell }
  askOpen[spell] = nonce
  timer(CD.ASK_WAIT, function()
    if askOpen[spell] == nonce then
      askOpen[spell] = nil
    end
    changed()
  end)
  return true, nonce
end

-- Fetching sets (R) ----------------------------------------------------------------------------------------

local pump

local function arm()
  if pumpArmed or #queue == 0 then
    return
  end
  pumpArmed = true
  local mine = pumpGen
  local ok = timer(CD.FETCH.gap, function()
    if mine ~= pumpGen then
      return
    end
    pumpArmed = false
    pump()
  end)
  if not ok then
    pumpArmed = false
  end
end

local function sendFetch(item)
  local universe = RU.Get(item.slug)
  local guild = store(false)
  local entry = guild and guild.dir[item.key]
  local job = entry and entry.j[item.job]
  local nonce = newNonce()
  local payload = nonce
    and G.Encode(CD.FN, {
      typ = "R",
      nonce = nonce,
      job = item.job,
      u = universe and universe.sum or 0,
      h = job and job.k or 0,
    })
  if not payload then
    return false
  end
  local ok = Comm.Send(CD.FN, "R", payload, "whisper", item.name, { id = nonce, priority = "reply" })
  if ok then
    pending[nonce] = { kind = "R", at = clock(), key = item.key, name = item.name, job = item.job, slug = item.slug }
    openBy[item.key] = nonce
  end
  return ok
end

local function openCount()
  local n = 0
  for _ in pairs(openBy) do
    n = n + 1
  end
  return n
end

-- One round of the queue: as many fetches as the limits allow.
pump = function()
  expire()
  if #queue == 0 then
    return
  end
  if not allowed() or inCombat() then
    return arm()
  end
  local f = CD.FETCH
  fetchBucket = fetchBucket or ns.CommLogic.NewBucket(f.burst, f.perMinute / 60, clock)
  for _ = 1, #queue do
    if #queue == 0 or openCount() >= f.open or fetchBucket.Level() < 1 then
      break
    end
    local item = table.remove(queue, 1)
    local id = item.key .. "\n" .. item.job
    if openBy[item.key] then
      -- One open request per member: this one waits for the next round.
      queue[#queue + 1] = item
    elseif CS.Allow("R") then
      fetchBucket.Take(1)
      queued[id] = nil
      cooldown[id] = clock() + f.retry
      sendFetch(item)
    else
      table.insert(queue, 1, item)
      break
    end
  end
  arm()
end

-- Queues the fetch of the recipe sets of a profession (slug) from the online members whose set is missing
-- or old. Returns how many were queued, or false and why (consent, job, guild).
function CD.Fetch(slug)
  if not allowed() then
    return false, "consent"
  end
  local jobId = type(slug) == "string" and RU.JobId(slug) or nil
  if not jobId then
    return false, "job"
  end
  local guild = store(false)
  local snap, index = roster()
  if not guild or not snap then
    return false, "guild"
  end
  expire()
  local keys = {}
  for key in pairs(guild.dir) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local added, t = 0, clock()
  for _, key in ipairs(keys) do
    local job = guild.dir[key].j[jobId]
    local m = index[key]
    local id = key .. "\n" .. jobId
    if
      job
      and job.k ~= job.h
      and m
      and m.online
      and not queued[id]
      and not openBy[key]
      and (cooldown[id] or 0) <= t
      and #queue < CD.FETCH.queue
    then
      queue[#queue + 1] = { key = key, name = m.name, slug = slug, job = jobId }
      queued[id] = true
      added = added + 1
    end
  end
  pump()
  return added
end

-- Receiving ------------------------------------------------------------------------------------------------

-- The common gate of a message: consent, a readable guild, a roster member. Returns the store, the key and
-- the name, or nil and the reason.
local function accept(sender, create)
  if not allowed() then
    return nil, "consent"
  end
  local name, key = member(sender)
  if not name then
    return nil, "member"
  end
  local guild = store(create)
  if not guild then
    return nil, "guild"
  end
  return guild, key, name
end

local function onSummary(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "J" or not allowed() then
    return
  end
  local key = type(sender) == "string" and PN.Key(sender) or ""
  if key == "" or not intake.Allow("J", key) then
    return drop("rate")
  end
  local guild, memberKey, name = accept(sender, true)
  if not guild then
    return drop(memberKey)
  end
  if CDL.PutSummary(guild, memberKey, name, msg.jobs, CD.now()) then
    changed()
  else
    drop("summary")
  end
end

local function onAnswer(sender, msg, ctx)
  if type(msg) ~= "table" or msg.typ ~= "K" or not allowed() then
    return
  end
  if type(ctx) == "table" and ctx.aud ~= "whisper" then
    return drop("channel")
  end
  local ask = openRequest(msg.nonce, "W", ctx)
  if not ask or ask.spell ~= msg.spell then
    return drop("nonce")
  end
  local guild, key = accept(sender, true)
  if not guild then
    return drop(key)
  end
  -- The profession must be the one of the recipe, and the skill cannot be above the maximum.
  local slug = RU.JobOf(msg.spell)
  if (slug and RU.JobId(slug) ~= msg.job) or msg.skill > msg.max then
    return drop("answer")
  end
  if CDL.PutAnswer(guild, msg.spell, key, msg.job, msg.skill, msg.max, CD.now()) then
    changed()
  end
end

local function onSet(sender, msg, ctx)
  if type(msg) ~= "table" or msg.typ ~= "C" or not allowed() then
    return
  end
  if type(ctx) == "table" and ctx.aud ~= "whisper" then
    return drop("channel")
  end
  local req = openRequest(msg.nonce, "R", ctx)
  if not req then
    return drop("nonce")
  end
  local guild, key = accept(sender, false)
  if not guild then
    return drop(key)
  end
  -- Only the member asked answers, for the job asked. Anything else leaves the request open.
  if key ~= req.key or msg.job ~= req.job then
    return drop("answer")
  end
  finish(msg.nonce)
  local verdict, detail = L.VerifyAnswer(msg, RU.Get(req.slug))
  local stored = false
  if verdict == "ok" then
    stored =
      CDL.PutSet(guild, key, msg.job, { art = msg.art, data = msg.data, u = msg.u, n = msg.n, h = msg.h }, CD.now())
  elseif verdict == "same" then
    stored = CDL.Confirm(guild, key, msg.job, msg.h, msg.n, CD.now())
  else
    drop("set-" .. tostring(detail))
  end
  if stored then
    changed()
  end
end

local function onWithdraw(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "X" or not allowed() then
    return
  end
  local guild = store(false)
  local key = type(sender) == "string" and PN.Key(sender) or ""
  if guild and key ~= "" and CDL.Forget(guild, key) then
    changed()
  end
end

-- An error in a handler goes to the error list, not into the line.
local function guarded(fn)
  return function(...)
    ns.Safe("craftdirectory", fn, ...)
  end
end

CS.SetReceiver("J", guarded(onSummary))
CS.SetReceiver("K", guarded(onAnswer))
CS.SetReceiver("C", guarded(onSet))
CS.SetReceiver("X", guarded(onWithdraw))

-- Reading --------------------------------------------------------------------------------------------------

-- How many roster members share their recipes (a directory entry or a live answer), and the roster size.
function CD.Coverage()
  local info = { sharing = 0, total = 0, loaded = false }
  if not allowed() then
    return info
  end
  local snap, index = roster()
  if snap then
    info.loaded = snap.loaded == true
    info.total = math.max(tonumber(snap.total) or 0, #snap.members)
  end
  local guild = store(false)
  if not guild then
    return info
  end
  local seen = {}
  local function count(key)
    if not seen[key] and (not info.loaded or index[key]) then
      seen[key] = true
      info.sharing = info.sharing + 1
    end
  end
  for key in pairs(guild.dir) do
    count(key)
  end
  for _, list in pairs(guild.answers) do
    for key in pairs(list) do
      count(key)
    end
  end
  return info
end

local function better(a, b)
  if a.online ~= b.online then
    return a.online == true
  end
  if a.skill ~= b.skill then
    return a.skill > b.skill
  end
  return PN.Lower(a.name) < PN.Lower(b.name)
end

-- Members that can make the spell: { key, name, job, slug, skill, max, online, zone, agoMin, seen, source,
-- stale } sorted online first, then by skill. online, zone and agoMin come from the guild roster (and can be
-- minutes old), seen is the epoch of the last message of the member, source "live" (answer to a question of
-- the last 5 minutes) or "cache", stale a set that is older than the last summary. The second value is
-- { sharing, total, loaded, unknown (members whose set of the job is not fetched yet), asking }.
function CD.Crafters(spell)
  local info = CD.Coverage()
  info.unknown, info.asking = 0, CD.Asking(spell)
  local guild = allowed() and store(false)
  if not guild or not whole(spell, 1, G.LIMITS.MAX_SPELL) then
    return {}, info
  end
  local slug = RU.JobOf(spell)
  local jobId = slug and RU.JobId(slug) or nil
  local found, unknown = CDL.Match(guild, spell, jobId, slug and RU.Get(slug) or nil, CD.now())
  info.unknown = unknown
  local _, index = roster()
  local list = {}
  for _, item in ipairs(found) do
    local m = index and index[item.key]
    -- A loaded roster is the truth about who is in the guild.
    if m or not info.loaded then
      local entry = guild.dir[item.key]
      local online
      if m then
        online = m.online == true
      end
      list[#list + 1] = {
        key = item.key,
        name = m and m.name or entry and entry.n or item.key,
        job = item.job,
        slug = RU.SlugOfJob(item.job),
        skill = item.skill,
        max = item.max,
        online = online,
        zone = m and m.zone ~= "" and m.zone or nil,
        agoMin = m and not m.online and m.agoMin or nil,
        seen = item.seen,
        source = item.source,
        stale = item.stale,
      }
    end
  end
  table.sort(list, better)
  return list, info
end

-- Numbers for the tab Teilen: members and answers in the cache of the own guild, the coverage, the size of
-- the saved data of all guilds (estimate in bytes), the open work.
function CD.Stats()
  expire()
  local out = { members = 0, answers = 0, spells = 0, bytes = 0, guilds = 0, queued = #queue, open = openCount() }
  local cover = CD.Coverage()
  out.sharing, out.total, out.loaded = cover.sharing, cover.total, cover.loaded
  local guild = allowed() and store(false)
  if guild then
    local counts = CDL.Counts(guild)
    out.members, out.answers, out.spells = counts.members, counts.answers, counts.spells
  end
  for _, other in pairs(root().guilds) do
    out.guilds = out.guilds + 1
    out.bytes = out.bytes + CDL.Bytes(other)
  end
  out.dropped = {}
  for reason, n in pairs(drops) do
    out.dropped[reason] = n
  end
  return out
end

-- Forgets the memory state (tests); saved data stays.
function CD.Reset()
  resetRequests()
  drops, curGuild, lastSweep, checked = {}, nil, nil, nil
  rosterSnap, rosterIndex, fetchBucket = nil, nil, nil
end

-- Events ---------------------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", CD.Load)
ns.On("PLAYER_ENTERING_WORLD", syncGuild)
ns.On("PLAYER_GUILD_UPDATE", syncGuild)
ns.On("FG_GUILD_UPDATE", function()
  syncGuild()
  prune()
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn == CD.FN and dir == "receive" and aud == "guild" and value ~= true then
    CD.Clear()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == CD.FN then
    CD.Clear()
  end
end)
