-- Pure rules of the quest helper (Modules/AutoQuest.lua): quest kinds, the exception lists, the
-- choice among the quests of one NPC, the memory of one conversation and the loop guard. No game
-- calls.
local _, ns = ...
local SL = ns.SellLogic
local Log = ns.AutoQuestLog
local Code = Log.Code

local QL = {}
ns.AutoQuestLogic = QL

-- At most two failed tries per step and quest inside the window (seconds). A try counts as done when
-- the game confirms it within CONFIRM_WINDOW seconds.
QL.LOOP_LIMIT = 2
QL.LOOP_WINDOW = 30
QL.CONFIRM_WINDOW = 2
-- A conversation is over when its windows stay closed this long (seconds), or after a quiet spell.
QL.CONVERSATION_GAP = 0.5
QL.CONVERSATION_STALE = 30
-- A quest that has to be handled by hand is remembered this long (seconds).
QL.MANUAL_TTL = 600
-- Marker for a list entry value the game hides.
QL.SECRET = "secret"

local KIND_SETTING = { normal = "autoQuestNormal", daily = "autoQuestDaily", weekly = "autoQuestWeekly" }
local NPC_KINDS = { Creature = true, Vehicle = true, GameObject = true }
local FREQUENCY_DAILY, FREQUENCY_WEEKLY = 1, 2

function QL.Kind(daily, weekly)
  if weekly then
    return "weekly"
  end
  return daily and "daily" or "normal"
end

-- Enum.QuestFrequency of a gossip or greeting entry (0 normal, 1 daily, anything above is weekly).
function QL.KindOfFrequency(frequency)
  if type(frequency) ~= "number" then
    return "normal"
  end
  return QL.Kind(frequency == FREQUENCY_DAILY, frequency >= FREQUENCY_WEEKLY)
end

-- Each kind has its own switch, on unless it is set to false.
function QL.KindAllowed(settings, kind)
  return settings[KIND_SETTING[kind] or KIND_SETTING.normal] ~= false
end

-- A kind the game hides is only taken when none of the kinds is switched off.
function QL.AllKindsAllowed(settings)
  return QL.KindAllowed(settings, "normal") and QL.KindAllowed(settings, "daily") and QL.KindAllowed(settings, "weekly")
end

-- The NPC id of a creature GUID, nil for anything else.
function QL.NpcId(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  return NPC_KINDS[kind] and tonumber(id) or nil
end

local function set(text)
  local out = {}
  for _, id in ipairs(SL.ParseIds(text)) do
    out[id] = true
  end
  return out
end

-- "quest" or "npc" for the list that holds the id, nil when none does.
function QL.IgnoredBy(settings, questId, npcId)
  if questId and set(settings.autoQuestIgnoreQuests)[questId] then
    return "quest"
  end
  if npcId ~= nil and set(settings.autoQuestIgnoreNpcs)[npcId] == true then
    return "npc"
  end
end

function QL.Ignored(settings, questId, npcId)
  return QL.IgnoredBy(settings, questId, npcId) ~= nil
end

-- The stored text with one more id, nil when it is no id.
function QL.AddIgnore(text, id)
  id = tonumber(id)
  if not id or id < 1 or id ~= math.floor(id) then
    return nil
  end
  return SL.AddId(text, id)
end

local LOG_WORDS = {
  on = "on",
  an = "on",
  off = "off",
  aus = "off",
  show = "show",
  anzeigen = "show",
  clear = "clear",
  leeren = "clear",
}

-- "ignore 123", "ignore npc 456", "list", "log [on|off|show|clear]" -> { action, kind, id, sub }.
-- Anything else is { action = "usage" }.
function QL.ParseCommand(text)
  local words = {}
  for word in tostring(text or ""):lower():gmatch("[^ ]+") do
    words[#words + 1] = word
  end
  if words[1] == "log" then
    local sub = words[2] == nil and "show" or LOG_WORDS[words[2]]
    if sub and #words <= 2 then
      return { action = "log", sub = sub }
    end
    return { action = "usage" }
  end
  if words[1] == "list" or words[1] == "liste" then
    return { action = "list" }
  end
  if words[1] == "ignore" or words[1] == "ignorieren" then
    local kind = "quest"
    if words[2] == "npc" then
      kind = "npc"
      table.remove(words, 2)
    elseif words[2] == "quest" then
      table.remove(words, 2)
    end
    local id = tonumber(words[2])
    if id and #words == 2 then
      return { action = "ignore", kind = kind, id = id }
    end
  end
  return { action = "usage" }
end

-- Memory of one conversation with an NPC: which entries the helper already selected (until the game
-- confirms the result), which hints were said, and the quests that need the player. A conversation is
-- over when GOSSIP_CLOSED or QUEST_FINISHED was seen and the next event comes after the gap.
function QL.NewTalk(gap, stale, ttl)
  gap, stale, ttl = gap or QL.CONVERSATION_GAP, stale or QL.CONVERSATION_STALE, ttl or QL.MANUAL_TTL
  local talk = {}
  local tried, hinted, manual = {}, {}, {}
  local closedAt, lastAt

  -- Called at the start of every handler.
  function talk.touch(now)
    if (closedAt and now - closedAt >= gap) or (lastAt and now - lastAt > stale) then
      tried, hinted = {}, {}
    end
    closedAt, lastAt = nil, now
  end

  function talk.closed(now)
    closedAt = now
  end

  function talk.mark(key)
    tried[key] = true
  end

  function talk.tried(key)
    return tried[key] == true
  end

  -- The game confirmed the result: the entry may be looked at again (a repeatable quest).
  function talk.release(key)
    tried[key] = nil
  end

  -- Entries known by their list position only: the positions move once a quest is gone from the list.
  function talk.releasePositions()
    for key in pairs(tried) do
      if key:find("#", 1, true) then
        tried[key] = nil
      end
    end
  end

  -- True once per key and conversation, so a hint is never said twice.
  function talk.firstHint(key)
    if hinted[key] then
      return false
    end
    hinted[key] = true
    return true
  end

  -- A quest the helper cannot hand in. An item demand only counts while the items switch stays off.
  function talk.setManual(id, reason, now, itemsOnly)
    if id then
      manual[id] = { reason = reason, at = now, itemsOnly = itemsOnly == true }
    end
  end

  -- The reason, or nil when the quest is not known as manual (any more).
  function talk.manualReason(id, now, settings)
    local record = id and manual[id]
    if not record then
      return nil
    end
    if now - record.at > ttl or (record.itemsOnly and settings.autoQuestItems == true) then
      manual[id] = nil
      return nil
    end
    return record.reason
  end

  function talk.forget(id)
    manual[id] = nil
  end

  function talk.reset()
    tried, hinted, manual, closedAt, lastAt = {}, {}, {}, nil, nil
  end

  return talk
end

-- The key of a list entry: kind and quest id, or the list position when the id is not known.
function QL.EntryKey(entry)
  return entry.kind .. ":" .. (entry.id and tostring(entry.id) or ("#" .. tostring(entry.ref)))
end

-- Why an entry stays untouched, nil when it may be taken. The reasons are the codes of AutoQuestLog.
local function passReason(entry, settings, npcId, talk, now)
  if entry.unreadable then
    return Code.listUnreadable
  end
  if entry.kind == "active" then
    if entry.complete == QL.SECRET then
      return Code.readySecret
    end
    if entry.complete ~= true then
      return Code.notReady
    end
  end
  local by = QL.IgnoredBy(settings, entry.id, npcId)
  if by then
    return by == "quest" and Code.ignoredQuest or Code.ignoredNpc
  end
  if entry.kind == "available" then
    if entry.kindUnknown then
      if not QL.AllKindsAllowed(settings) then
        return Code.kindSecret
      end
    else
      local kind = QL.KindOfFrequency(entry.frequency)
      if not QL.KindAllowed(settings, kind) then
        return Log.KindOff(kind)
      end
    end
  end
  if talk then
    local manual = talk.manualReason(entry.id, now, settings)
    if manual then
      return Code.learnedManual .. ":" .. manual
    end
    if talk.tried(QL.EntryKey(entry)) then
      return Code.alreadyTried
    end
  end
end

-- entries: { kind = "available" | "active", id, complete, frequency, kindUnknown, unreadable, ref } of
-- one NPC. Takes the first quest ready to turn in, else the first one to accept, that the filters and
-- the memory of the conversation let through, so one entry the helper cannot do never holds back the
-- others. Returns the entry and the list of { entry, reason } of those passed over before it.
function QL.Pick(entries, settings, npcId, talk, now)
  local passed = {}
  for _, kind in ipairs({ "active", "available" }) do
    for _, entry in ipairs(entries) do
      if entry.kind == kind then
        local reason = passReason(entry, settings, npcId, talk, now or 0)
        if not reason then
          return entry, passed
        end
        passed[#passed + 1] = { entry = entry, reason = reason }
      end
    end
  end
  return nil, passed
end

-- Counts the tries without an answer per key; a pause longer than the window starts a key afresh. A try
-- counts when it is made and is given back by confirm() when the game answers in time, so only the
-- failed ones stay.
function QL.NewLoops(limit, window, confirmWindow)
  limit, window = limit or QL.LOOP_LIMIT, window or QL.LOOP_WINDOW
  confirmWindow = confirmWindow or QL.CONFIRM_WINDOW
  local seen = {}
  local loops = {}
  -- True while the try is within the limit, then the counted tries and the seconds since the first.
  function loops.try(key, now)
    local entry = seen[key]
    if not entry or now - entry.at > window then
      entry = { n = 0, first = now }
      seen[key] = entry
    end
    entry.n, entry.at = entry.n + 1, now
    if entry.n <= limit then
      entry.pending = now
    end
    return entry.n <= limit, entry.n, now - entry.first
  end
  -- The game answered the last try of the key in time: it no longer counts. Returns true and the seconds
  -- it took.
  function loops.confirm(key, now)
    local entry = seen[key]
    if not (entry and entry.pending and now - entry.pending <= confirmWindow) then
      return false
    end
    local waited = now - entry.pending
    entry.pending = nil
    entry.n = math.max(entry.n - 1, 0)
    return true, waited
  end
  -- Keys whose last try got no answer in time. Each is reported once.
  function loops.expire(now)
    local out = {}
    for key, entry in pairs(seen) do
      if entry.pending and now - entry.pending >= confirmWindow then
        entry.pending = nil
        out[#out + 1] = key
      end
    end
    table.sort(out)
    return out
  end
  function loops.reset()
    seen = {}
  end
  return loops
end
