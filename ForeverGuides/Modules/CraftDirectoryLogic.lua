-- Rules of the guild craft directory (receiving side of the function crafting), no game calls: the shape and
-- repair of the saved table, expiry, the size limits and the questions "who has recipe X". Time is passed in
-- (epoch seconds), names and keys are strings the caller already normalized.
--   root   = { v, guilds = { [guildKey] = guild } }, at most CONFIG.guilds guilds side by side (alts)
--   guild  = { at, dir = { [memberKey] = entry }, answers = { [spell] = { [memberKey] = answer } } }
--   entry  = { n = name, t = last message, j = { [jobId] = job } }                  from J and C
--   job    = { s skill, m max, c count, h checksum of the set (J), and when a set is stored:
--              a "B" mask or "I" id list, d its data, u universe checksum, k checksum of the stored set }
--   answer = { j jobId, s skill, m max, t time }                                    from K
-- Short field names keep the saved file small: a member with four jobs takes about 300 bytes (EntryBytes).
-- A set is current while job.k == job.h; an older one stays usable (recipes are never unlearned) and is
-- reported as stale. Nothing here raises on damaged data: Clean returns a valid root for any input.
local _, ns = ...
local L, G = ns.GuildSyncLogic, ns.GuildSyncCodec

local D = {}
ns.CraftDirectoryLogic = D

local DAY = 86400
local STORE = L.CONFIG.store

D.CONFIG = {
  version = 1,
  guilds = 3,
  members = STORE.directory,
  -- Most bytes (EntryBytes) of one member; a set that would exceed it is not stored.
  memberBytes = 1500,
  spells = STORE.spells,
  perSpell = STORE.perSpell,
  -- Most answers over all spells.
  answers = 2000,
  dirTtl = STORE.craftTtl,
  -- A single answer (K) is worth less than a summary of the whole profession.
  answerTtl = 3 * DAY,
  -- Seconds an answer counts as live.
  live = 300,
  maxData = G.LIMITS.MAX_C_PAYLOAD,
  maxName = 64,
  maxKey = 80,
}
local C = D.CONFIG

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function whole(v, lo, hi)
  return finite(v) and v == math.floor(v) and v >= lo and v <= hi
end

local function validKey(key)
  return type(key) == "string" and key ~= "" and #key <= C.maxKey
end

local function validName(name)
  return type(name) == "string" and name ~= "" and #name <= C.maxName and not name:find("[%c|]")
end

-- Time of a stored record: a value from the future (damaged file) counts as now.
local function stamp(v, now)
  if not finite(v) or v < 0 then
    return nil
  end
  return math.min(v, now)
end

function D.NewRoot()
  return { v = C.version, guilds = {} }
end

function D.NewGuild(now)
  return { at = now or 0, dir = {}, answers = {} }
end

-- Size ----------------------------------------------------------------------------------------------------

-- Estimate of the bytes one member takes in the saved file.
function D.EntryBytes(key, entry)
  local bytes = #key + #entry.n + 16
  for _, job in pairs(entry.j) do
    bytes = bytes + 24 + (job.d and #job.d or 0)
  end
  return bytes
end

-- Estimate of the bytes of one guild: members and answers.
function D.Bytes(g)
  local bytes = 0
  for key, entry in pairs(g.dir) do
    bytes = bytes + D.EntryBytes(key, entry)
  end
  for _, list in pairs(g.answers) do
    bytes = bytes + 8
    for key in pairs(list) do
      bytes = bytes + #key + 24
    end
  end
  return bytes
end

function D.Counts(g)
  local members, spells, answers = 0, 0, 0
  for _ in pairs(g.dir) do
    members = members + 1
  end
  for _, list in pairs(g.answers) do
    spells = spells + 1
    for _ in pairs(list) do
      answers = answers + 1
    end
  end
  return { members = members, spells = spells, answers = answers }
end

-- Repair ---------------------------------------------------------------------------------------------------

local function cleanJob(raw)
  local lim = G.LIMITS
  if
    type(raw) ~= "table"
    or not (whole(raw.s, 0, lim.MAX_SKILL) and whole(raw.m, 0, lim.MAX_SKILL))
    or not (whole(raw.c, 0, lim.MAX_KNOWN) and whole(raw.h, 0, lim.MAX_SUM))
  then
    return nil
  end
  local job = { s = raw.s, m = raw.m, c = raw.c, h = raw.h }
  if
    (raw.a == "B" or raw.a == "I")
    and type(raw.d) == "string"
    and raw.d ~= ""
    and #raw.d <= C.maxData
    and not raw.d:find("[^0-9A-Za-z_%-]")
    and whole(raw.u, 0, lim.MAX_SUM)
    and whole(raw.k, 0, lim.MAX_SUM)
  then
    job.a, job.d, job.u, job.k = raw.a, raw.d, raw.u, raw.k
  end
  return job
end

-- Takes the data of the largest sets away until the member fits its limit.
local function trim(key, entry)
  while D.EntryBytes(key, entry) > C.memberBytes do
    local big, size = nil, 0
    for _, job in pairs(entry.j) do
      if job.d and #job.d > size then
        big, size = job, #job.d
      end
    end
    if not big then
      return false
    end
    big.a, big.d, big.u, big.k = nil, nil, nil, nil
  end
  return true
end

local function cleanEntry(key, raw, now)
  if type(raw) ~= "table" or not validKey(key) or not validName(raw.n) or type(raw.j) ~= "table" then
    return nil
  end
  local t = stamp(raw.t, now)
  if not t or not L.CraftValid(t, now) then
    return nil
  end
  local entry, count = { n = raw.n, t = t, j = {} }, 0
  for id, rawJob in pairs(raw.j) do
    local job = whole(id, 1, G.LIMITS.MAX_JOB_ID) and count < G.LIMITS.MAX_JOBS and cleanJob(rawJob) or nil
    if job then
      entry.j[id], count = job, count + 1
    end
  end
  if count == 0 or not trim(key, entry) then
    return nil
  end
  return entry
end

-- The newest `limit` keys of a map { [key] = record with .t }; the rest is removed.
local function keepNewest(map, limit)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  if #keys <= limit then
    return
  end
  table.sort(keys, function(a, b)
    if map[a].t ~= map[b].t then
      return map[a].t > map[b].t
    end
    return a < b
  end)
  for i = limit + 1, #keys do
    map[keys[i]] = nil
  end
end

local function cleanAnswer(raw, now)
  local lim = G.LIMITS
  if
    type(raw) ~= "table"
    or not (whole(raw.j, 1, lim.MAX_JOB_ID) and whole(raw.s, 0, lim.MAX_SKILL) and whole(raw.m, 0, lim.MAX_SKILL))
  then
    return nil
  end
  local t = stamp(raw.t, now)
  if not t or now - t > C.answerTtl then
    return nil
  end
  return { j = raw.j, s = raw.s, m = raw.m, t = t }
end

-- Newest time of the answers of one spell.
local function newest(list)
  local top = 0
  for _, a in pairs(list) do
    top = math.max(top, a.t)
  end
  return top
end

-- Removes answers above the total limit, oldest first.
local function capAnswers(answers)
  local flat = {}
  for spell, list in pairs(answers) do
    for key, a in pairs(list) do
      flat[#flat + 1] = { spell = spell, key = key, t = a.t }
    end
  end
  if #flat <= C.answers then
    return
  end
  table.sort(flat, function(a, b)
    if a.t ~= b.t then
      return a.t > b.t
    end
    if a.spell ~= b.spell then
      return a.spell < b.spell
    end
    return a.key < b.key
  end)
  for i = C.answers + 1, #flat do
    local list = answers[flat[i].spell]
    list[flat[i].key] = nil
    if next(list) == nil then
      answers[flat[i].spell] = nil
    end
  end
end

local function cleanGuild(raw, now)
  local g = D.NewGuild(stamp(type(raw) == "table" and raw.at or nil, now) or 0)
  if type(raw) ~= "table" then
    return g
  end
  if type(raw.dir) == "table" then
    for key, e in pairs(raw.dir) do
      g.dir[key] = cleanEntry(key, e, now)
    end
    keepNewest(g.dir, C.members)
  end
  if type(raw.answers) == "table" then
    local tops = {}
    for spell, list in pairs(raw.answers) do
      if whole(spell, 1, G.LIMITS.MAX_SPELL) and type(list) == "table" then
        local clean = {}
        for key, a in pairs(list) do
          clean[key] = validKey(key) and cleanAnswer(a, now) or nil
        end
        keepNewest(clean, C.perSpell)
        if next(clean) then
          g.answers[spell] = clean
          tops[spell] = { t = newest(clean) }
        end
      end
    end
    keepNewest(tops, C.spells)
    for spell in pairs(g.answers) do
      if not tops[spell] then
        g.answers[spell] = nil
      end
    end
    capAnswers(g.answers)
  end
  return g
end

-- A valid root for any saved value: damaged parts are dropped, what has expired goes, the limits hold.
function D.Clean(raw, now)
  now = finite(now) and now or 0
  local root = D.NewRoot()
  if type(raw) ~= "table" or type(raw.guilds) ~= "table" then
    return root
  end
  for key, g in pairs(raw.guilds) do
    if type(key) == "string" and key ~= "" and #key <= 100 and type(g) == "table" then
      root.guilds[key] = cleanGuild(g, now)
    end
  end
  D.CapGuilds(root)
  return root
end

-- Keeps the newest CONFIG.guilds guilds (by `at`); returns the keys that went.
function D.CapGuilds(root)
  local view, gone = {}, {}
  for key, g in pairs(root.guilds) do
    view[key] = { t = g.at }
  end
  keepNewest(view, C.guilds)
  for key in pairs(root.guilds) do
    if not view[key] then
      root.guilds[key] = nil
      gone[#gone + 1] = key
    end
  end
  return gone
end

-- Expiry ---------------------------------------------------------------------------------------------------

-- Removes what has expired. Returns how many members and answers went.
function D.Sweep(g, now)
  local members, answers = 0, 0
  for key, e in pairs(g.dir) do
    if not L.CraftValid(e.t, now) then
      g.dir[key] = nil
      members = members + 1
    end
  end
  for spell, list in pairs(g.answers) do
    for key, a in pairs(list) do
      if now - a.t > C.answerTtl then
        list[key] = nil
        answers = answers + 1
      end
    end
    if next(list) == nil then
      g.answers[spell] = nil
    end
  end
  return members, answers
end

-- Removes one member everywhere. Returns whether anything was there.
function D.Forget(g, key)
  local had = g.dir[key] ~= nil
  g.dir[key] = nil
  for spell, list in pairs(g.answers) do
    if list[key] ~= nil then
      had = true
      list[key] = nil
      if next(list) == nil then
        g.answers[spell] = nil
      end
    end
  end
  return had
end

-- Removes every member for whom isMember(key) is not true (left the guild). Returns how many went.
function D.Prune(g, isMember)
  local gone = {}
  for key in pairs(g.dir) do
    if not isMember(key) then
      gone[key] = true
    end
  end
  for _, list in pairs(g.answers) do
    for key in pairs(list) do
      if not isMember(key) then
        gone[key] = true
      end
    end
  end
  local count = 0
  for key in pairs(gone) do
    D.Forget(g, key)
    count = count + 1
  end
  return count
end

-- Writing --------------------------------------------------------------------------------------------------

local function removeOldest(map)
  local oldKey, oldT
  for key, record in pairs(map) do
    if oldT == nil or record.t < oldT or (record.t == oldT and key < oldKey) then
      oldKey, oldT = key, record.t
    end
  end
  if oldKey then
    map[oldKey] = nil
  end
end

local function countOf(map)
  local n = 0
  for _ in pairs(map) do
    n = n + 1
  end
  return n
end

-- The summary J of a member (jobs as decoded by the codec). Stored sets of a job stay. A count above the
-- universe of the receiver is no error: the sender may have newer recipe data. Returns true, or false and
-- the reason (args, range).
function D.PutSummary(g, key, name, jobs, now)
  if not validKey(key) or not validName(name) or type(jobs) ~= "table" or #jobs < 1 then
    return false, "args"
  end
  local old = g.dir[key]
  local entry = { n = name, t = now, j = {} }
  for i = 1, #jobs do
    local job = jobs[i]
    local lim = G.LIMITS
    if
      type(job) ~= "table"
      or i > lim.MAX_JOBS
      or not (whole(job.id, 1, lim.MAX_JOB_ID) and whole(job.skill, 0, lim.MAX_SKILL))
      or not (whole(job.max, 0, lim.MAX_SKILL) and whole(job.n, 0, lim.MAX_KNOWN) and whole(job.h, 0, lim.MAX_SUM))
      or job.skill > job.max
    then
      return false, "range"
    end
    local kept = old and old.j[job.id]
    local stored = { s = job.skill, m = job.max, c = job.n, h = job.h }
    if kept and kept.a then
      stored.a, stored.d, stored.u, stored.k = kept.a, kept.d, kept.u, kept.k
    end
    entry.j[job.id] = stored
  end
  if not old and countOf(g.dir) >= C.members then
    removeOldest(g.dir)
  end
  g.dir[key] = entry
  return true
end

-- A verified recipe set of one job of a member: set = { art "B" or "I", data, u, n, h }. Replaces the stored
-- one and makes it the current state of the job. Returns true, or false and the reason (unknown, args, size).
function D.PutSet(g, key, jobId, set, now)
  local entry = g.dir[key]
  local job = entry and entry.j[jobId]
  if not job then
    return false, "unknown"
  end
  local lim = G.LIMITS
  if
    type(set) ~= "table"
    or (set.art ~= "B" and set.art ~= "I")
    or type(set.data) ~= "string"
    or set.data == ""
    or #set.data > C.maxData
    or not (whole(set.u, 0, lim.MAX_SUM) and whole(set.h, 0, lim.MAX_SUM) and whole(set.n, 0, lim.MAX_KNOWN))
  then
    return false, "args"
  end
  -- A new table, so that decoded id lists of the old one are not reused.
  local fresh = { s = job.s, m = job.m, c = set.n, h = set.h, a = set.art, d = set.data, u = set.u, k = set.h }
  entry.j[jobId] = fresh
  if D.EntryBytes(key, entry) > C.memberBytes then
    entry.j[jobId] = job
    return false, "size"
  end
  entry.t = now
  return true
end

-- The answer "unchanged" (art =) to a fetch: the stored set is current when its checksum is the one sent.
function D.Confirm(g, key, jobId, h, n, now)
  local entry = g.dir[key]
  local job = entry and entry.j[jobId]
  if not job or not job.k or job.k ~= h then
    return false
  end
  job.h, job.c = h, n
  entry.t = now
  return true
end

-- One live answer K: the member makes spell. Returns true, or false and the reason (args).
function D.PutAnswer(g, spell, key, jobId, skill, max, now)
  local lim = G.LIMITS
  if
    not whole(spell, 1, lim.MAX_SPELL)
    or not validKey(key)
    or not (whole(jobId, 1, lim.MAX_JOB_ID) and whole(skill, 0, lim.MAX_SKILL) and whole(max, 0, lim.MAX_SKILL))
  then
    return false, "args"
  end
  local list = g.answers[spell]
  if not list then
    if countOf(g.answers) >= C.spells then
      local oldSpell, oldT
      for s, other in pairs(g.answers) do
        local top = newest(other)
        if oldT == nil or top < oldT or (top == oldT and s < oldSpell) then
          oldSpell, oldT = s, top
        end
      end
      g.answers[oldSpell] = nil
    end
    list = {}
    g.answers[spell] = list
  end
  if list[key] == nil and countOf(list) >= C.perSpell then
    removeOldest(list)
  end
  list[key] = { j = jobId, s = skill, m = max, t = now }
  capAnswers(g.answers)
  return true
end

-- True while a live answer for the spell is younger than CONFIG.live seconds.
function D.HasLive(g, spell, now)
  for _, a in pairs(g.answers[spell] or {}) do
    if now - a.t <= C.live then
      return true
    end
  end
  return false
end

-- Reading --------------------------------------------------------------------------------------------------

-- Ids of a stored id list as a set, nil when the data does not read. Memoized per job table.
local decoded = setmetatable({}, { __mode = "k" })

local function idSet(job)
  local set = decoded[job]
  if set == nil then
    local ids = G.DecodeIdList(job.d)
    set = false
    if ids then
      set = {}
      for _, id in ipairs(ids) do
        set[id] = true
      end
    end
    decoded[job] = set
  end
  return set or nil
end

-- The members of one guild store that can make `spell`. jobId and universe belong to the spell (nil when the
-- recipe data does not know it: then only live answers count). Returns a list sorted by key
-- { key, job, skill, max, seen, source = "live" or "cache", stale }
-- and the number of members whose set for the job is missing or cannot be read (unknown).
function D.Match(g, spell, jobId, universe, now)
  local found, unknown = {}, 0
  local masks, byKey = {}, {}
  if jobId then
    for key, entry in pairs(g.dir) do
      local job = entry.j[jobId]
      if job and job.a == "B" then
        masks[key] = { u = job.u, mask = job.d }
      elseif job and job.a == "I" then
        local set = idSet(job)
        if set == nil then
          unknown = unknown + 1
        elseif set[spell] then
          byKey[key] = true
        end
      elseif job then
        unknown = unknown + 1
      end
    end
    local yes, other = L.Holders(universe, masks, spell)
    unknown = unknown + other
    for _, key in ipairs(yes) do
      byKey[key] = true
    end
  end
  local answers = g.answers[spell] or {}
  for key in pairs(answers) do
    byKey[key] = true
  end
  for key in pairs(byKey) do
    local entry, answer = g.dir[key], answers[key]
    local job = entry and jobId and entry.j[jobId] or nil
    local item = { key = key, source = "cache", stale = false }
    -- The newer of the two statements gives skill and maximum.
    if answer and (not job or not entry or answer.t >= entry.t) then
      item.job, item.skill, item.max, item.seen = answer.j, answer.s, answer.m, answer.t
    else
      item.job, item.skill, item.max, item.seen = jobId, job.s, job.m, entry.t
    end
    if answer then
      item.seen = math.max(item.seen, answer.t)
      item.source = now - answer.t <= C.live and "live" or "cache"
    end
    item.stale = answer == nil and job ~= nil and job.k ~= job.h
    found[#found + 1] = item
  end
  table.sort(found, function(a, b)
    return a.key < b.key
  end)
  return found, unknown
end
