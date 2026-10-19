-- The game side of the experience bar: reads XP, rested XP and the quest log, keeps the session
-- (gain, active time, pause), the played time per level and the learned level sizes, and hands the
-- window one Snapshot(). Every game value goes through rawget and pcall and has to be a plain number,
-- so a missing API or a secret value leaves the old reading in place and never raises. The arithmetic
-- lives in Modules/XpLogic.lua.
-- Per character (ForeverGuidesCharDB.xp): session and levelStart[level] (played seconds when the level
-- began). Account wide (ForeverGuidesDB.xpLearned[build][level]): XP per level the client reported.
-- SavedVariables are written on reload and logout only, so the session is saved at every change.
local addonName, ns = ...
local XL, U = ns.XpLogic, ns.U

local XT = {}
ns.XpTracker = XT

local QUEST_DELAY = 0.5
local PLAYED_EVERY = 600
local LEVEL_UP_TIMEOUT = 5
-- Seconds after a level-up event in which a reading from before it is dropped.
local LEVEL_UP_WINDOW = 3
local STALE_SESSION = 1800
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
  if st.session then
    charStore().session = XL.SessionSave(st.session, now(), U.now())
  end
end

local function fire()
  for _, fn in ipairs(listeners) do
    ns.Safe("xptracker.change", fn)
  end
end

-- XP and level ---------------------------------------------------------------------------------------------------

-- Reads level, XP and rested XP, counts the gain while the session runs and learns the level size.
-- `forced` is the level a PLAYER_LEVEL_UP announced, for a client whose UnitLevel is late.
local function update(forced)
  local level = read("UnitLevel", "player")
  local xp, max = read("UnitXP", "player"), read("UnitXPMax", "player")
  local last = st.last
  st.atMax = flag("IsPlayerAtEffectiveMaxLevel") == true
  st.rested = read("GetXPExhaustion") or 0
  -- Shortly after a level-up event the client may still report the level and XP from before it: such a
  -- reading is dropped. Later on a lower value is a resync and counts no gain.
  if not forced and last and st.levelUpAt and now() - st.levelUpAt <= LEVEL_UP_WINDOW then
    if level and (level < last.level or (level == last.level and xp and xp < last.xp)) then
      return
    end
  end
  local late = forced ~= nil and (level == nil or level < forced)
  if late and last and last.level >= forced then
    st.level = last.level
    return
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
  if not level or not xp or (not unreliable and (not max or max <= 0)) then
    return
  end
  local learned = learnedTable()
  if unreliable then
    max = XL.Need(level, sizesOf(learned, level, nil))
    st.stale = { xp = readXp, at = now() }
  elseif learned then
    learned[level] = max
  end
  if last and st.session then
    XL.Record(st.session, (XL.Gain(last, { level = level, xp = xp, max = max }, sizesOf(learned, level, max))))
  end
  st.last = { level = level, xp = xp, max = max }
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
ns.On("PLAYER_ENTERING_WORLD", function()
  if st.ready then
    refresh()
  else
    start()
  end
end)
ns.On("PLAYER_XP_UPDATE", function(_, unit)
  if unit == nil or unit == "player" then
    refresh()
  end
end)
ns.On("UPDATE_EXHAUSTION", refresh)

ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
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

ns.On("TIME_PLAYED_MSG", function(...)
  if st.ready then
    onPlayed(...)
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
