-- Chat line when a quest of the log is ready to hand in (settings.questReadyNotice, off by default),
-- like the quest addons do. It watches the log read only: the completion of every entry is compared
-- with the last reading, the line comes when an open quest turned ready. Different from the quest
-- hints of the helper (autoQuestNotice), which only explain why a hand-in needs the player.
local _, ns = ...
local QR = ns.QuestReadyLogic

local M = {}
ns.QuestReady = M

ns.AddLocale("enUS", {
  ["questready.line"] = "Quest ready to hand in: %s",
})
ns.AddLocale("deDE", {
  ["questready.line"] = "Quest bereit zur Abgabe: %s",
})

local DELAY = 0.3
-- Seconds after a loading screen in which the log still fills up: readings count, nothing is announced.
local QUIET = 5

local state = { known = nil, token = 0, quietUntil = 0 }

local function now()
  local fn = rawget(_G, "GetTime")
  local ok, value = pcall(type(fn) == "function" and fn or function() end)
  return ok and type(value) == "number" and value or 0
end

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

local function enabled()
  return ns.db ~= nil and ns.db.settings ~= nil and ns.db.settings.questReadyNotice == true
end

local function text(value)
  value = readable(value)
  return type(value) == "string" and value or nil
end

local function call(fn, ...)
  local ok, value = pcall(fn, ...)
  if not ok then
    return nil
  end
  return readable(value)
end

-- Completion of one quest id through the modern log calls.
local function completeOf(id)
  local log = rawget(_G, "C_QuestLog")
  if type(log) ~= "table" then
    return nil
  end
  local result
  for _, name in ipairs({ "ReadyForTurnIn", "IsComplete" }) do
    if type(log[name]) == "function" then
      local value = call(log[name], id)
      if value == true then
        return true
      end
      if value == false then
        result = false
      end
    end
  end
  return result
end

-- Log entries as { id, title, complete }, headers and hidden entries left out.
function M.Read()
  local entries = {}
  local log = rawget(_G, "C_QuestLog")
  if type(log) == "table" and type(log.GetNumQuestLogEntries) == "function" and type(log.GetInfo) == "function" then
    local count = call(log.GetNumQuestLogEntries)
    if type(count) ~= "number" then
      return nil
    end
    for i = 1, math.min(count, QR.MAX_ENTRIES) do
      local ok, info = pcall(log.GetInfo, i)
      if ok and type(info) == "table" and readable(info.isHeader) ~= true and readable(info.isHidden) ~= true then
        local id = readable(info.questID)
        if type(id) == "number" then
          entries[#entries + 1] = { id = id, title = text(info.title), complete = completeOf(id) }
        end
      end
    end
    return entries
  end
  local countFn, titleFn = global("GetNumQuestLogEntries"), global("GetQuestLogTitle")
  if not countFn or not titleFn then
    return nil
  end
  local count = call(countFn)
  if type(count) ~= "number" then
    return nil
  end
  for i = 1, math.min(count, QR.MAX_ENTRIES) do
    local ok, title, _, _, isHeader, _, isComplete, _, id = pcall(titleFn, i)
    id = ok and readable(id) or nil
    if ok and readable(isHeader) ~= true and type(id) == "number" then
      entries[#entries + 1] = { id = id, title = text(title), complete = QR.Complete(readable(isComplete)) }
    end
  end
  return entries
end

function M.Scan()
  if not enabled() then
    state.known = nil
    return
  end
  local entries = M.Read()
  if not entries then
    return
  end
  local known, ready = QR.Diff(state.known, entries)
  state.known = known
  if now() < state.quietUntil then
    return
  end
  for _, entry in ipairs(ready) do
    ns.Notify.chat(QR.Line(ns.L["questready.line"], entry))
  end
end

-- Several events in a row count once.
local function schedule()
  if not enabled() then
    state.known = nil
    return
  end
  state.token = state.token + 1
  local token = state.token
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    local queued = pcall(timer.After, DELAY, function()
      if token == state.token then
        M.Scan()
      end
    end)
    if queued then
      return
    end
  end
  M.Scan()
end

-- A loading screen lists the log again, the next reading starts over without announcing.
ns.On("PLAYER_ENTERING_WORLD", function()
  state.known = nil
  state.quietUntil = now() + QUIET
  state.token = state.token + 1
  schedule()
end)
ns.On("QUEST_LOG_UPDATE", schedule)
ns.On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
  if unit == nil or unit == "player" then
    schedule()
  end
end)
