-- Chat line when a quest of the log is ready to hand in (settings.questReadyNotice, off by default),
-- like the quest addons do. With settings.questReadyGroup (off by default) the group gets one line with
-- the quest link as well: queued, one line per quest and session, held back while the client restricts chat.
-- With settings.questProgressGroup (off by default, independent of both) the group also gets a line when an
-- objective count goes up ("Wolves slain: 3/10"), coalesced per objective so kill quests do not flood the chat.
-- It watches the log read only: the completion of every entry is compared
-- with the last reading, the line comes when an open quest turned ready. Different from the quest
-- hints of the helper (autoQuestNotice), which only explain why a hand-in needs the player.
local _, ns = ...
local QR = ns.QuestReadyLogic

local M = {}
ns.QuestReady = M

ns.AddLocale("enUS", {
  ["questready.line"] = "Quest ready to hand in: %s",
  ["questready.group"] = "%s complete",
  ["questready.progress"] = "%s %s",
  ["questready.prefix"] = "Forever Guides: ",
  ["questready.done"] = "(done)",
})
ns.AddLocale("deDE", {
  ["questready.line"] = "Quest bereit zur Abgabe: %s",
  ["questready.group"] = "%s abgeschlossen",
  ["questready.progress"] = "%s %s",
  ["questready.prefix"] = "Forever Guides: ",
  ["questready.done"] = "(fertig)",
})

local DELAY = 0.3
-- Seconds after a loading screen in which the log still fills up: readings count, nothing is announced.
local QUIET = 5

local RETRY = 3

local state = { known = nil, token = 0, quietUntil = 0, queue = QR.NewQueue(), pumping = false,
  counts = nil, progress = QR.NewCoalescer() }

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

local function setting(key)
  return ns.db ~= nil and ns.db.settings ~= nil and ns.db.settings[key] == true
end

local function enabled()
  return setting("questReadyNotice") or setting("questReadyGroup") or setting("questProgressGroup")
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

-- Objectives of one quest as { text, have, need, finished }, nil when the client gives none.
local function objectivesOf(id)
  local log = rawget(_G, "C_QuestLog")
  if type(log) ~= "table" or type(log.GetQuestObjectives) ~= "function" then
    return nil
  end
  local list = call(log.GetQuestObjectives, id)
  if type(list) ~= "table" then
    return nil
  end
  local out = {}
  for i, raw in ipairs(list) do
    if type(raw) ~= "table" then
      return nil
    end
    local finished = readable(raw.finished)
    out[i] = {
      text = text(raw.text),
      have = type(readable(raw.numFulfilled)) == "number" and raw.numFulfilled or nil,
      need = type(readable(raw.numRequired)) == "number" and raw.numRequired or nil,
      finished = type(finished) == "boolean" and finished or nil,
    }
  end
  return out
end

-- Log entries as { id, title, complete, objectives }, headers and hidden entries left out. Objectives are
-- read on request only.
function M.Read(withObjectives)
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
          entries[#entries + 1] = {
            id = id,
            title = text(info.title),
            complete = completeOf(id),
            objectives = withObjectives and objectivesOf(id) or nil,
          }
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

local function flag(name, ...)
  local fn = global(name)
  return fn ~= nil and call(fn, ...) == true
end

local function channel()
  local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
  return QR.Channel({
    group = flag("IsInGroup"),
    instance = instance ~= nil and flag("IsInGroup", instance),
    raid = flag("IsInRaid"),
  })
end

-- Quest link for the chat (client link or title link), nil when only plain text is possible.
local function questLink(id)
  local link, isLink = ns.ChatSafe.QuestLink(id)
  return isLink and link or nil
end

-- Addon chat is blocked in encounters and similar restricted states.
local function restricted()
  local info = rawget(_G, "C_ChatInfo")
  if type(info) == "table" and type(info.InChatMessagingLockdown) == "function" and call(info.InChatMessagingLockdown) == true then
    return true
  end
  return ns.AddonRestricted("Chat")
end

local function later(delay, fn)
  local timer = rawget(_G, "C_Timer")
  return type(timer) == "table" and type(timer.After) == "function" and pcall(timer.After, delay, fn)
end

local function post(line, target)
  local info = rawget(_G, "C_ChatInfo")
  local send = type(info) == "table" and type(info.SendChatMessage) == "function" and info.SendChatMessage
    or global("SendChatMessage")
  return send ~= nil and (pcall(ns.ChatSafe.Send, line, target, nil, send))
end

-- Sends the waiting lines one by one. A restricted client keeps them queued, a retry timer tries again.
local function pump()
  state.pumping = false
  if state.queue.Size() == 0 then
    return
  end
  local wait = RETRY
  local target = channel()
  if not target then
    state.queue.Clear()
    return
  end
  if not restricted() then
    local line, gap = state.queue.Pop(now())
    if line then
      post(line, target)
      wait = QR.GAP
    else
      wait = gap
    end
  end
  if state.queue.Size() > 0 then
    state.pumping = later(wait, pump)
  end
end

-- Icon and addon name in front of a group line, from the settings (the prefix is on unless switched off).
local function decorate(body)
  local s = ns.db and ns.db.settings or {}
  return QR.Decorate(body, s.questChatIcon, s.questChatPrefix, ns.L["questready.prefix"])
end

local function announceGroup(entry)
  if not setting("questReadyGroup") or not channel() then
    return
  end
  local line = decorate(string.format(ns.L["questready.group"], QR.Reference(questLink(entry.id), entry)))
  if state.queue.Push(entry.id, line) and not state.pumping then
    pump()
  end
end

-- Moves the objective lines whose window is over into the queue and sends. The small margin covers a
-- timer that fires a hair early.
local function drain(at)
  for _, item in ipairs(state.progress.Take(at or now() + 0.1)) do
    state.queue.PushKeyed(item.key, item.text)
  end
  if state.queue.Size() > 0 and not state.pumping then
    pump()
  end
end

local function announceProgress(up, readyIds)
  if not channel() then
    state.progress.Clear()
    return
  end
  local covered = setting("questReadyGroup")
  for _, change in ipairs(up) do
    if not (covered and readyIds[change.id]) then
      local reference = QR.Reference(questLink(change.id), change)
      local line = decorate(
        QR.ProgressLine(ns.L["questready.progress"], reference, change.objective, ns.L["questready.done"])
      )
      state.progress.Push(change.id .. ":" .. change.index, line, now())
    end
  end
  if state.progress.Size() > 0 and not later(QR.COALESCE, drain) then
    -- Without a timer the window cannot rest, the lines go out at once.
    drain(now() + QR.COALESCE)
  end
end

function M.Scan()
  if not enabled() then
    state.known, state.counts = nil, nil
    return
  end
  local wantProgress = setting("questProgressGroup")
  local entries = M.Read(wantProgress)
  if not entries then
    return
  end
  local known, ready = QR.Diff(state.known, entries)
  state.known = known
  local up = {}
  if wantProgress then
    state.counts, up = QR.DiffProgress(state.counts, entries)
  else
    state.counts = nil
    state.progress.Clear()
  end
  if now() < state.quietUntil then
    return
  end
  if #up > 0 then
    local readyIds = {}
    for _, entry in ipairs(ready) do
      readyIds[entry.id] = true
    end
    announceProgress(up, readyIds)
  end
  for _, entry in ipairs(ready) do
    if setting("questReadyNotice") then
      ns.Notify.chat(QR.Line(ns.L["questready.line"], entry))
    end
    announceGroup(entry)
  end
end

-- Receiver side of the logo choice: in group chat the leading logo mark becomes the add-on logo on this screen
-- only, the text of the message is not changed otherwise.
local GROUP_EVENTS = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }

local function logoMarkup()
  local assets = ns.BadgeAssets
  if not assets then
    return nil
  end
  return string.format("|T%s:%d:%d:0:0|t", assets.Path(QR.LOGO_SIZE), QR.LOGO_SIZE, QR.LOGO_SIZE)
end

function M.Filter(_, _, msg, ...)
  local guard = ns.AutoGuard
  local line = guard and guard.Safe(msg)
  if type(line) ~= "string" then
    return false
  end
  local ok, out = pcall(function()
    return QR.ShowLogo(line, logoMarkup())
  end)
  if ok and out then
    return false, out, ...
  end
  return false
end

if ChatFrame_AddMessageEventFilter then
  for _, name in ipairs(GROUP_EVENTS) do
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. name, M.Filter)
  end
end

-- Several events in a row count once.
local function schedule()
  if not enabled() then
    state.known, state.counts = nil, nil
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
  state.known, state.counts = nil, nil
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
