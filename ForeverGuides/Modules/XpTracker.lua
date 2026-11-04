-- The game side of the experience bar: reads XP, rested XP and the quest log, keeps the session
-- (gain, active time, pause, sources), the played time per level and the learned level sizes, and hands
-- the window one Snapshot(). Every game value goes through rawget and pcall and has to be a plain
-- number, so a missing API or a secret value leaves the old reading in place and never raises. The
-- arithmetic lives in Modules/XpLogic.lua.
-- The gain is the difference between two readings of UnitXP. The events that carry an amount (kill and
-- discovery lines, quest turn-ins) fill the source sums and, while no reading can confirm them, count
-- the gain themselves (see hold and settle).
-- Per character (ForeverGuidesCharDB.xp): session, last (the reading the gain is measured from) and
-- levelStart[level] (played seconds when the level began). Account wide (ForeverGuidesDB.xpLearned
-- [build][level]): XP per level the client reported. SavedVariables are written on reload and logout
-- only, so the session is saved at every change.
local addonName, ns = ...
local XL, U = ns.XpLogic, ns.U

local XT = {}
ns.XpTracker = XT

local QUEST_DELAY = 0.5
local PLAYED_EVERY = 600
local LEVEL_UP_TIMEOUT = 5
-- Seconds an event amount waits for a reading that confirms it before it counts on its own.
local SETTLE_DELAY = 5
local PAYLOAD_LETTERS = 60
-- Seconds after a level-up event in which a reading from before it is dropped.
local LEVEL_UP_WINDOW = 3
-- Seconds after the last save from which a login starts a new session (setting sessionResetOnLogin): a
-- reload or a short disconnect keeps the session, a normal new login does not.
local STALE_SESSION = 600
-- Longest a played answer may be older than the level-up it is taken for, in seconds.
local ANSWER_SLACK = 30
local MAX_QUESTS = 200

local st = {
  ready = false,
  rested = 0,
  doneXp = 0,
  todoXp = 0,
  atMax = false,
  questToken = 0,
  levelUpSeq = 0,
  -- Event XP no reading has confirmed yet, one episode at a time (the id tells a timer which one it is for).
  pending = { sum = 0, id = 0 },
  -- XP counted from events while the base reading lagged: the next difference includes it again.
  direct = 0,
  -- XP a difference proved beyond the pending amounts, which late event lines may still claim.
  budget = nil,
  -- For XT.Debug: how often each event came, how each update ended.
  events = {},
  outcomes = {},
}
local listeners = {}
local spare = { levelStart = {}, session = {} }

-- Game access -----------------------------------------------------------------------------------------

local function global(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn or nil
end

local function readable(value)
  local secret = global("issecretvalue")
  if secret then
    local ok, hidden = pcall(secret, value)
    if not ok or hidden then
      return nil
    end
  end
  return value
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function numberOf(ok, value)
  value = ok and readable(value) or nil
  return finite(value) and value or nil
end

-- A number from a game function, nil for anything else.
local function read(name, ...)
  local fn = global(name)
  return fn and numberOf(pcall(fn, ...)) or nil
end

local function flag(name, ...)
  local fn = global(name)
  if not fn then
    return nil
  end
  local ok, value = pcall(fn, ...)
  value = ok and readable(value) or nil
  return value == true or value == 1
end

local function now()
  return read("GetTime") or 0
end

local function after(delay, fn)
  local timer = rawget(_G, "C_Timer")
  return type(timer) == "table" and type(timer.After) == "function" and pcall(timer.After, delay, fn)
end

local function setting(key)
  local cfg = ns.db and ns.db.settings and ns.db.settings.xpBar
  return type(cfg) == "table" and cfg[key] == true
end

-- Storage ---------------------------------------------------------------------------------------------------

local function charStore()
  local char = ns.charDB
  if type(char) ~= "table" then
    return spare
  end
  if type(char.xp) ~= "table" then
    char.xp = {}
  end
  if type(char.xp.levelStart) ~= "table" then
    char.xp.levelStart = {}
  end
  return char.xp
end

local function buildKey()
  local fn = global("GetBuildInfo")
  if fn then
    local ok, _, build = pcall(fn)
    if ok and (type(build) == "string" or type(build) == "number") then
      return tostring(build)
    end
  end
  return ns.XpTable.build
end

local function learnedTable()
  local db = ns.db
  if type(db) ~= "table" then
    return nil
  end
  if type(db.xpLearned) ~= "table" then
    db.xpLearned = {}
  end
  local key = buildKey()
  if type(db.xpLearned[key]) ~= "table" then
    db.xpLearned[key] = {}
  end
  return db.xpLearned[key]
end

-- Highest level the client lets a character reach, never above the table: the table runs to 100
-- while the game stops lower.
local function levelCap()
  local cap = ns.XpTable.maxLevel
  for _, name in ipairs({ "GetMaxPlayerLevel", "GetMaxLevelForPlayerExpansion" }) do
    local value = read(name)
    if value and value >= 1 then
      return math.min(cap, math.floor(value))
    end
  end
  return cap
end

local function sizesOf(learned, level, max)
  local ctx = XL.Sizes(learned, level, max)
  ctx.maxLevel = levelCap()
  return ctx
end

local function sizes()
  local last = st.last
  return sizesOf(learnedTable(), last and last.level, last and last.max)
end

local function persist()
  local store = charStore()
  if st.session then
    store.session = XL.SessionSave(st.session, now(), U.now())
  end
  -- A base that lags behind counted events would count them twice after a reload: none is saved then.
  store.last = st.direct == 0 and XL.BaseSave(st.last, U.now()) or nil
end

local function fire()
  for _, fn in ipairs(listeners) do
    ns.Safe("xptracker.change", fn)
  end
end

-- XP and level ---------------------------------------------------------------------------------------------------

-- Why a game value is not usable, for the counters of XT.Debug.
local function why(name, ...)
  local fn = global(name)
  if not fn then
    return "missing"
  end
  local ok, value = pcall(fn, ...)
  if not ok then
    return "error"
  end
  if value ~= nil and readable(value) == nil then
    return "secret"
  end
  return type(value) == "number" and "invalid" or type(value)
end

local function tally(name)
  st.outcomes[name] = (st.outcomes[name] or 0) + 1
end

-- Counts a difference two readings proved. What the events already counted while the base lagged is
-- left out, the event amounts waiting for a reading are covered by it (a `partial` reading, the
-- level-up with its XP not yet known, covers no more than it holds). Returns the name of the outcome.
local function creditGain(gain, partial)
  if gain <= 0 then
    return "zero"
  end
  local owed = math.min(st.direct, gain)
  st.direct = st.direct - owed
  XL.Record(st.session, gain - owed)
  local pending = st.pending
  local covered = partial and math.min(pending.sum, gain) or pending.sum
  pending.sum = pending.sum - covered
  st.budget = { xp = math.max(0, gain - owed - covered), at = now() }
  return st.session.running and "gain" or "paused"
end

-- Reads level, XP and rested XP, counts the gain while the session runs and learns the level size.
-- `forced` is the level a PLAYER_LEVEL_UP announced, for a client whose UnitLevel is late. Returns the
-- name of the outcome.
local function reading(forced)
  local level = read("UnitLevel", "player")
  local xp, max = read("UnitXP", "player"), read("UnitXPMax", "player")
  local last = st.last
  st.atMax = flag("IsPlayerAtEffectiveMaxLevel") == true
  st.rested = read("GetXPExhaustion") or 0
  -- Shortly after a level-up event the client may still report the level and XP from before it: such a
  -- reading is dropped. Later on a lower value is a resync and counts no gain.
  if not forced and last and st.levelUpAt and now() - st.levelUpAt <= LEVEL_UP_WINDOW then
    if level and (level < last.level or (level == last.level and xp and xp < last.xp)) then
      return "window"
    end
  end
  local late = forced ~= nil and (level == nil or level < forced)
  if late and last and last.level >= forced then
    st.level = last.level
    return "late"
  end
  -- At a level-up the XP the client reports may still be the old one (same XP, same size as before the
  -- level). Then it is not used: the rest of the old level counts and the new level starts at 0, the next
  -- reading adds what the new level holds.
  local unreliable = late
  if forced and last and last.level < forced then
    unreliable = late or xp == nil or xp == last.xp or (max ~= nil and max == last.max)
  end
  local readXp = xp
  if unreliable then
    level, xp, max = forced, 0, nil
  end
  st.level = level or st.level
  if not level then
    return "unreadable:level:" .. why("UnitLevel", "player")
  elseif not xp then
    return "unreadable:xp:" .. why("UnitXP", "player")
  elseif not unreliable and (not max or max <= 0) then
    return "unreadable:max:" .. why("UnitXPMax", "player")
  end
  local learned = learnedTable()
  if unreliable then
    max = XL.Need(level, sizesOf(learned, level, nil))
    st.stale = { xp = readXp, at = now() }
  elseif learned then
    learned[level] = max
  end
  local outcome = "nobase"
  if last and st.session then
    local gain = XL.Gain(last, { level = level, xp = xp, max = max }, sizesOf(learned, level, max))
    outcome = creditGain(gain, unreliable)
  elseif last then
    outcome = "nosession"
  end
  st.last = { level = level, xp = xp, max = max }
  return outcome
end

local function update(forced)
  tally(reading(forced))
end

-- Played time ------------------------------------------------------------------------------------------------------

local function requestPlayed(force)
  local roster = ns.RosterStats
  if type(roster) ~= "table" or type(roster.RequestPlayed) ~= "function" then
    return false
  end
  local ok, sent = pcall(roster.RequestPlayed, force)
  if ok and sent then
    st.playedAsked = now()
  end
  return ok and sent == true
end

local function maybeRequestPlayed()
  if not st.playedAsked or now() - st.playedAsked >= PLAYED_EVERY then
    requestPlayed(true)
  end
end

-- Chat at a level-up ---------------------------------------------------------------------------------------

local CHAT_CHANNELS = { "self", "group", "guild", "say" }
-- Seconds in which a refusal event still belongs to the Say message just sent.
local SAY_WINDOW = 2

-- Where the level-up line goes: settings.xpBar.chat with every key a boolean, missing ones from the defaults.
function XT.ChatChannels()
  local d = ns.Store.defaults.settings.xpBar.chat
  local cfg = ns.db and ns.db.settings and ns.db.settings.xpBar
  local raw = type(cfg) == "table" and type(cfg.chat) == "table" and cfg.chat or {}
  local out = {}
  for _, key in ipairs(CHAT_CHANNELS) do
    if type(raw[key]) == "boolean" then
      out[key] = raw[key]
    else
      out[key] = d[key]
    end
  end
  return out
end

-- The chat type for the group the player is in: instance group, raid, party, or nil.
local function groupChannel()
  local instanceGroup = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE") or 2
  if flag("IsInGroup", instanceGroup) then
    return "INSTANCE_CHAT"
  elseif flag("IsInRaid") then
    return "RAID"
  elseif flag("IsInGroup") then
    return "PARTY"
  end
end

-- True when the call went through without an error. The protected function is called from a Lua
-- function: handed straight to pcall the client reports it as UNKNOWN and blocks it.
local function sendTo(channel, text)
  local send = global("SendChatMessage")
  if not send or ns.AddonRestricted("Chat") then
    return false
  end
  return (pcall(function()
    send(text, channel)
  end))
end

-- Say stays closed to an addon without a key press: one hint per session, and the line goes to the
-- player's own window when it did not yet.
local function sayRefused(pending)
  if pending.done then
    return
  end
  pending.done = true
  if not st.sayHinted then
    st.sayHinted = true
    ns.Notify.chat(ns.L["xpbar.chat.sayBlocked"])
  end
  if not pending.ownShown then
    pending.ownShown = true
    ns.Notify.chat(pending.own)
  end
end

-- One call per level-up, nothing is sent again.
local function announce(level, levelSeconds, total)
  local channels = XT.ChatChannels()
  local pending = { own = XL.ChatLevelUp(level, levelSeconds, total), ownShown = false, at = now() }
  local text = XL.ChatLevelUp(level, levelSeconds, total, true)
  local group = channels.group and groupChannel()
  if group then
    sendTo(group, text)
  end
  if channels.guild and flag("IsInGuild") then
    sendTo("GUILD", text)
  end
  if channels.say then
    st.pendingSay = pending
    -- The refusal is handled here: the error catcher need not list it on every level-up.
    if ns.ErrorCatcher then
      ns.ErrorCatcher.ExpectBlock(SAY_WINDOW, "SendChatMessage", "UNKNOWN")
    end
    if not sendTo("SAY", text) then
      sayRefused(pending)
    end
  end
  if channels.self and not pending.ownShown then
    pending.ownShown = true
    ns.Notify.chat(pending.own)
  end
end

ns.On("ADDON_ACTION_BLOCKED", function(_, blockedAddon, func)
  local pending = st.pendingSay
  if pending and blockedAddon == addonName and now() - pending.at <= SAY_WINDOW then
    func = tostring(func)
    if func:find("SendChatMessage", 1, true) or func:find("UNKNOWN", 1, true) then
      sayRefused(pending)
    end
  end
end)

-- Closes the level-up that waits for the played time: stores the start of the new level (from our own
-- reckoning when the game did not answer in time) and writes the chat line when it is switched on.
local function finishLevelUp(fallback)
  local up = st.levelUp
  if not up then
    return
  end
  st.levelUp = nil
  local starts = charStore().levelStart
  local total = XL.PlayedNow(st.played, now())
  if fallback and total and not finite(starts[up.level]) then
    starts[up.level] = math.floor(total)
  end
  if not setting("chatLevelUp") or not ns.Notify then
    return
  end
  local before, from = starts[up.level - 1], starts[up.level]
  local levelSeconds = finite(before) and finite(from) and from >= before and from - before or nil
  announce(up.level, levelSeconds, total)
end

local function onPlayed(_, total, thisLevel)
  if not finite(total) then
    return
  end
  local t = now()
  st.played = { total = total, at = t }
  local up = st.levelUp
  -- An answer older than the level-up still describes the level before it.
  local fresh = up ~= nil and finite(thisLevel) and thisLevel <= t - up.at + ANSWER_SLACK
  local level = up and (fresh and up.level or up.level - 1) or st.level
  local start = XL.LevelStartFromPlayed(total, thisLevel)
  if level and start then
    charStore().levelStart[level] = math.floor(start)
  end
  if fresh then
    finishLevelUp(false)
  end
  persist()
  fire()
end

-- Quest XP -----------------------------------------------------------------------------------------------------------

-- Quest ids of the log, headers left out: { id, complete }. The completion is nil where the entry
-- does not carry it. Nothing here selects a quest.
local function questEntries()
  local entries = {}
  local log = rawget(_G, "C_QuestLog")
  if type(log) == "table" and type(log.GetNumQuestLogEntries) == "function" and type(log.GetInfo) == "function" then
    local count = numberOf(pcall(log.GetNumQuestLogEntries))
    for i = 1, math.min(count or 0, MAX_QUESTS) do
      local ok, info = pcall(log.GetInfo, i)
      if ok and type(info) == "table" and readable(info.isHeader) ~= true and readable(info.isHidden) ~= true then
        local id = readable(info.questID)
        if finite(id) and id > 0 then
          entries[#entries + 1] = { id = id }
        end
      end
    end
    return entries
  end
  local countFn, titleFn = global("GetNumQuestLogEntries"), global("GetQuestLogTitle")
  local count = countFn and numberOf(pcall(countFn))
  if not count or not titleFn then
    return entries
  end
  for i = 1, math.min(count, MAX_QUESTS) do
    local ok, _, _, _, isHeader, _, isComplete, _, id = pcall(titleFn, i)
    id = ok and readable(id) or nil
    if ok and readable(isHeader) ~= true and finite(id) and id > 0 then
      entries[#entries + 1] = { id = id, complete = readable(isComplete) == 1 or readable(isComplete) == true }
    end
  end
  return entries
end

local function isComplete(entry)
  if entry.complete ~= nil then
    return entry.complete
  end
  local log = rawget(_G, "C_QuestLog")
  for _, name in ipairs({ "ReadyForTurnIn", "IsComplete" }) do
    local fn = type(log) == "table" and log[name]
    if type(fn) == "function" then
      local ok, value = pcall(fn, entry.id)
      if ok and readable(value) == true then
        return true
      end
    end
  end
  return false
end

local function questXp(id)
  local fn = global("GetQuestLogRewardXP")
  local value = fn and numberOf(pcall(fn, id))
  if value == nil then
    local log = rawget(_G, "C_QuestLog")
    fn = type(log) == "table" and log.GetQuestLogRewardXP
    value = type(fn) == "function" and numberOf(pcall(fn, id)) or nil
  end
  return value and value > 0 and value or 0
end

-- Adds up the reward XP of the quests in the log: completed ones and open ones apart.
function XT.ScanQuests()
  local done, todo = 0, 0
  for _, entry in ipairs(questEntries()) do
    local xp = questXp(entry.id)
    if xp > 0 then
      if isComplete(entry) then
        done = done + xp
      else
        todo = todo + xp
      end
    end
  end
  if done ~= st.doneXp or todo ~= st.todoXp then
    st.doneXp, st.todoXp = done, todo
    fire()
  end
end

-- Several events in a row count once, half a second after the last one.
local function scheduleQuestScan()
  st.questToken = st.questToken + 1
  local token = st.questToken
  local queued = after(QUEST_DELAY, function()
    if token == st.questToken then
      XT.ScanQuests()
    end
  end)
  if not queued then
    XT.ScanQuests()
  end
end

-- Event XP -----------------------------------------------------------------------------------------------------------

local settle

-- An event amount waits SETTLE_DELAY seconds for a reading that confirms it. Lines that come after the
-- reading which already counted their XP claim the budget it left, so they wait for nothing.
local function hold(xp)
  local budget, pending = st.budget, st.pending
  if budget and now() - budget.at <= SETTLE_DELAY then
    local claimed = math.min(xp, budget.xp)
    budget.xp, xp = budget.xp - claimed, xp - claimed
  end
  if xp <= 0 then
    return
  end
  if pending.sum <= 0 then
    pending.id = pending.id + 1
    local id = pending.id
    after(SETTLE_DELAY, function()
      if id == pending.id then
        settle()
      end
    end)
  end
  pending.sum = pending.sum + xp
end

-- No reading confirmed the amounts in time: the readings are tried once more, and what they still do
-- not cover counts as the events reported it. The base is then behind (`direct`), so the difference
-- that comes later leaves these amounts out.
settle = function()
  local pending = st.pending
  if pending.sum <= 0 or not st.session then
    return
  end
  local hadBase = st.last ~= nil
  update()
  local rest = pending.sum
  if rest > 0 then
    pending.sum = 0
    local counted = XL.Record(st.session, rest)
    if hadBase then
      st.direct = st.direct + counted
    end
    tally("direct")
  end
  persist()
  fire()
end

-- An amount an event reports: the source sums take it, the gain waits for a reading.
local function source(src)
  local s = st.session
  if not st.ready or not s or XL.RecordSource(s, src) == 0 then
    return
  end
  hold(src.xp)
  persist()
  fire()
end

-- Session -------------------------------------------------------------------------------------------------------------

local function changeSession(changed)
  if changed then
    persist()
    fire()
  end
  return changed
end

local function syncAfk()
  if not st.session or not setting("autoPause") then
    return
  end
  local afk = flag("UnitIsAFK", "player")
  if afk then
    changeSession(XL.Pause(st.session, now(), true))
  elseif afk == false and st.session.auto then
    changeSession(XL.Resume(st.session, now()))
  end
end

-- Starts when the character is known: restores the saved session (or starts a new one when the
-- last one is stale and the setting asks for it) and takes the first reading.
local function start()
  if st.ready or type(ns.charDB) ~= "table" then
    return
  end
  st.ready = true
  local t, wall = now(), U.now()
  local saved = charStore().session
  local session
  if type(saved) == "table" then
    local stale = finite(saved.savedAt) and wall - saved.savedAt > STALE_SESSION
    if not (stale and setting("sessionResetOnLogin")) then
      session = XL.SessionLoad(saved, t)
    end
  end
  st.session = session or XL.SessionNew(t, wall)
  -- A reload keeps the gain between the last reading and now (only with the session it belongs to).
  st.last = session and XL.BaseLoad(charStore().last, wall) or nil
  update()
  syncAfk()
  persist()
  requestPlayed(true)
  scheduleQuestScan()
  fire()
end

-- API -----------------------------------------------------------------------------------------------------------------------

-- Everything the bar shows (XL.Compute), calculated from the readings of now.
function XT.Snapshot()
  local last = st.last or {}
  local xp, max = last.xp, last.max
  -- A fresh reading of the same level wins over the stored one, unless it is the old XP the client
  -- still reports right after a level-up.
  local freshXp, freshMax = read("UnitXP", "player"), read("UnitXPMax", "player")
  local stale = st.stale
  local carried = stale and freshXp == stale.xp and now() - stale.at <= LEVEL_UP_WINDOW
  if freshXp and freshMax and freshXp >= 0 and freshMax > 0 and not carried then
    if st.level ~= nil and read("UnitLevel", "player") == st.level then
      xp, max = freshXp, freshMax
    end
  end
  local level = last.level or st.level
  return XL.Compute({
    level = level,
    xp = xp,
    max = max,
    rested = st.rested,
    doneXp = st.doneXp,
    todoXp = st.todoXp,
    atMax = st.atMax,
    sizes = sizesOf(learnedTable(), level, max),
    session = st.session,
    played = st.played,
    levelStart = charStore().levelStart,
    now = now(),
  })
end

-- True when the state changed.
function XT.Pause()
  return st.session ~= nil and changeSession(XL.Pause(st.session, now(), false))
end

function XT.Resume()
  return st.session ~= nil and changeSession(XL.Resume(st.session, now()))
end

-- Returns whether the session runs afterwards.
function XT.TogglePause()
  if not st.session then
    return false
  end
  if st.session.running then
    XT.Pause()
  else
    XT.Resume()
  end
  return st.session.running
end

function XT.ResetSession()
  st.session = XL.SessionNew(now(), U.now())
  -- Amounts still waiting belong to the old session.
  st.pending.sum, st.budget = 0, nil
  changeSession(true)
end

function XT.SessionState()
  local s, t = st.session, now()
  if not s then
    return { running = false, auto = false, active = 0, gained = 0 }
  end
  return {
    running = s.running,
    auto = s.auto,
    active = XL.ActiveSeconds(s, t),
    gained = s.gained,
    startedAt = s.startedAt,
    xph = XL.Rate(s, t),
  }
end

-- Time from level `from` to level `to` out of the stored level starts: { seconds, missing, text }.
function XT.LevelTimeReport(from, to)
  local report = XL.Between(charStore().levelStart, from, to)
  report.text = XL.ReportText(report)
  return report
end

-- Calls fn() after every change of the readings, the session or the played time.
function XT.OnChange(fn)
  if type(fn) == "function" then
    listeners[#listeners + 1] = fn
  end
  return fn
end

-- For the diagnostics line: table build, calibration, learned levels, session state.
function XT.Info()
  local factor = sizes().factor
  local learned = 0
  for _ in pairs(learnedTable() or {}) do
    learned = learned + 1
  end
  return {
    tableBuild = ns.XpTable.build,
    factor = factor,
    estimated = factor ~= 1,
    learned = learned,
    running = st.session ~= nil and st.session.running == true,
  }
end

-- Diagnostics ---------------------------------------------------------------------------------------------------------

local DEBUG_EVENTS = {
  "PLAYER_XP_UPDATE",
  "UPDATE_EXHAUSTION",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "TIME_PLAYED_MSG",
  "QUEST_TURNED_IN",
  "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_SYSTEM",
}

-- The arguments of an event as one short text (secret values and errors named, not shown).
local function payloadText(...)
  local count = select("#", ...)
  if count == 0 then
    return "(none)"
  end
  local parts = {}
  for i = 1, count do
    local value = select(i, ...)
    if value ~= nil and readable(value) == nil then
      parts[i] = "secret"
    else
      local ok, shown = pcall(tostring, value)
      parts[i] = ok and shown or "?"
    end
  end
  local text = table.concat(parts, ", ")
  return #text > PAYLOAD_LETTERS and text:sub(1, PAYLOAD_LETTERS) .. "..." or text
end

local function seen(event, ...)
  local entry = st.events[event]
  if not entry then
    entry = { count = 0 }
    st.events[event] = entry
  end
  entry.count, entry.at, entry.payload = entry.count + 1, now(), payloadText(...)
end

-- What a game function answers right now: { type, secret, value } (value for numbers and strings only).
local function rawValue(name, ...)
  local fn = global(name)
  if not fn then
    return { type = "missing" }
  end
  local ok, value = pcall(fn, ...)
  if not ok then
    return { type = "error" }
  end
  local secret = value ~= nil and readable(value) == nil
  local kind = type(value)
  return { type = kind, secret = secret, value = not secret and (kind == "number" or kind == "string") and value or nil }
end

local function copy(map)
  local out = {}
  for key, value in pairs(map) do
    out[key] = value
  end
  return out
end

-- For /fg xpdiag, nothing in it changes the state: per event the count, the clock of the last one, its
-- payload and whether the client delivers it; how each update ended; the raw readings now; the session
-- and its sources; the event XP still waiting (pending), counted ahead of a reading (direct) and the
-- budget of late lines.
function XT.Debug()
  local t = now()
  local events = {}
  for _, name in ipairs(DEBUG_EVENTS) do
    local entry = st.events[name] or { count = 0 }
    events[#events + 1] = {
      name = name,
      count = entry.count,
      at = entry.at,
      payload = entry.payload,
      registered = ns.IsEventRegistered(name),
    }
  end
  local s = st.session
  local session
  if s then
    session = {
      running = s.running,
      since = s.since,
      active = XL.ActiveSeconds(s, t),
      gained = s.gained,
      auto = s.auto,
      startedAt = s.startedAt,
    }
    for _, field in ipairs(XL.SOURCE_FIELDS) do
      session[field] = s[field]
    end
  end
  local saved = type(ns.charDB) == "table" and type(ns.charDB.xp) == "table" and ns.charDB.xp or {}
  return {
    now = t,
    ready = st.ready,
    events = events,
    outcomes = copy(st.outcomes),
    raw = {
      level = rawValue("UnitLevel", "player"),
      xp = rawValue("UnitXP", "player"),
      max = rawValue("UnitXPMax", "player"),
      rested = rawValue("GetXPExhaustion"),
      secrets = global("issecretvalue") ~= nil,
    },
    last = st.last and copy(st.last) or nil,
    session = session,
    onCharDB = type(ns.charDB) == "table",
    savedSession = saved.session ~= nil,
    savedBase = saved.last ~= nil,
    pending = st.pending.sum,
    direct = st.direct,
    budget = st.budget and st.budget.xp or 0,
  }
end

-- Events ---------------------------------------------------------------------------------------------------------------------

local function refresh()
  if st.ready then
    update()
    persist()
    maybeRequestPlayed()
    fire()
  end
end

ns.On("PLAYER_LOGIN", start)
ns.On("PLAYER_ENTERING_WORLD", function(event, ...)
  seen(event, ...)
  if st.ready then
    refresh()
  else
    start()
  end
end)
ns.On("PLAYER_XP_UPDATE", function(event, unit)
  seen(event, unit)
  if unit == nil or unit == "player" then
    refresh()
  end
end)
ns.On("UPDATE_EXHAUSTION", function(event, ...)
  seen(event, ...)
  refresh()
end)

ns.On("PLAYER_LEVEL_UP", function(event, newLevel, ...)
  seen(event, newLevel, ...)
  if not st.ready then
    return
  end
  newLevel = finite(newLevel) and newLevel or nil
  st.levelUpAt = newLevel and now() or st.levelUpAt
  update(newLevel)
  persist()
  if newLevel then
    st.levelUpSeq = st.levelUpSeq + 1
    local seq = st.levelUpSeq
    st.levelUp = { level = newLevel, at = now() }
    requestPlayed(true)
    after(LEVEL_UP_TIMEOUT, function()
      if st.levelUp and seq == st.levelUpSeq then
        finishLevelUp(true)
      end
    end)
  end
  fire()
end)

-- The lines and amounts the client reports: the sums of the sources and the fallback for a reading
-- that fails. PLAYER_XP_UPDATE stays the truth for the gain.
local parsers

local function chatParsers()
  parsers = parsers
    or XL.ChatParsers(function(name)
      local text = rawget(_G, name)
      return type(text) == "string" and text or nil
    end)
  return parsers
end

ns.On("QUEST_TURNED_IN", function(event, questId, xpReward)
  seen(event, questId, xpReward)
  local xp = numberOf(true, xpReward)
  if xp and xp > 0 then
    source({ kind = "quest", xp = xp })
  end
end)

ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(event, text)
  seen(event, text)
  local line = type(text) == "string" and readable(text) or nil
  local gain = line and XL.ParseGain(chatParsers(), line)
  -- A line without a creature is the quest turn-in, which QUEST_TURNED_IN already reports.
  if gain and gain.kind == "kill" then
    source(gain)
  end
end)

ns.On("CHAT_MSG_SYSTEM", function(event, text)
  local line = type(text) == "string" and readable(text) or nil
  local xp = line and XL.ParseExplore(chatParsers(), line)
  if xp and xp > 0 then
    seen(event, text)
    source({ kind = "explore", xp = xp })
  end
end)

ns.On("QUEST_LOG_UPDATE", function()
  if st.ready then
    scheduleQuestScan()
  end
end)
ns.On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
  if st.ready and (unit == nil or unit == "player") then
    scheduleQuestScan()
  end
end)

ns.On("TIME_PLAYED_MSG", function(event, ...)
  seen(event, ...)
  if st.ready then
    onPlayed(event, ...)
  end
end)

ns.On("PLAYER_FLAGS_CHANGED", function(_, unit)
  if st.ready and unit == "player" then
    syncAfk()
  end
end)

-- The last state goes into the saved variables before they are written.
ns.On("PLAYER_LOGOUT", function()
  if st.ready then
    persist()
  end
end)
