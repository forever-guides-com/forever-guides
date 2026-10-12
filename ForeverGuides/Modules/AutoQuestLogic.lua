-- Pure rules of the quest helper (Modules/AutoQuest.lua): quest kinds, the exception lists, the
-- choice among the quests of one NPC and the loop guard. No game calls.
local _, ns = ...
local SL = ns.SellLogic

local QL = {}
ns.AutoQuestLogic = QL

-- At most two tries per step and quest inside the window (seconds).
QL.LOOP_LIMIT = 2
QL.LOOP_WINDOW = 30

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

function QL.Ignored(settings, questId, npcId)
  if questId and set(settings.autoQuestIgnoreQuests)[questId] then
    return true
  end
  return npcId ~= nil and set(settings.autoQuestIgnoreNpcs)[npcId] == true
end

-- The stored text with one more id, nil when it is no id.
function QL.AddIgnore(text, id)
  id = tonumber(id)
  if not id or id < 1 or id ~= math.floor(id) then
    return nil
  end
  return SL.AddId(text, id)
end

-- "ignore 123", "ignore npc 456", "list" -> { action, kind, id }. Anything else is { action = "usage" }.
function QL.ParseCommand(text)
  local words = {}
  for word in tostring(text or ""):lower():gmatch("[^ ]+") do
    words[#words + 1] = word
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

-- entries: { kind = "available" | "active", id, complete, frequency, ref } of one NPC. Picks the first
-- quest ready to turn in, else the only entry when it is a quest to accept. Never anything else:
-- an NPC with several quests to choose from is left to the player.
function QL.Pick(entries, settings, npcId)
  for _, e in ipairs(entries) do
    if e.kind == "active" and e.complete == true and not QL.Ignored(settings, e.id, npcId) then
      return e
    end
  end
  local only = #entries == 1 and entries[1] or nil
  if
    only
    and only.kind == "available"
    and not QL.Ignored(settings, only.id, npcId)
    and QL.KindAllowed(settings, QL.KindOfFrequency(only.frequency))
  then
    return only
  end
end

-- Counts the tries per key; a pause longer than the window starts a key afresh.
function QL.NewLoops(limit, window)
  limit, window = limit or QL.LOOP_LIMIT, window or QL.LOOP_WINDOW
  local seen = {}
  local loops = {}
  -- True while the try is within the limit.
  function loops.try(key, now)
    local entry = seen[key]
    if not entry or now - entry.at > window then
      entry = { n = 0 }
      seen[key] = entry
    end
    entry.n, entry.at = entry.n + 1, now
    return entry.n <= limit
  end
  function loops.reset()
    seen = {}
  end
  return loops
end
