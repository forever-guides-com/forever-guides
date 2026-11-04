-- Forever Chat, the saved conversations (game side). While the add-on is switched on and the option "archive"
-- is on (default), every line the messenger takes is also written into ForeverGuidesChatDB.archive, and the
-- next start (reload, relog, restart of the game) puts the conversations back as read lines. The rules, limits
-- and file format are in ChatArchiveLogic.lua. Nothing is sent, the data stays in the SavedVariables of the
-- player.
--
-- Writer: this file alone. The recorder of the main add-on stops writing whispers while this one runs
-- (ChatHistory.SetMessengerStore), so no line is saved twice.
-- Restoring runs in small steps over several frames, newest conversations first, and a conversation that
-- gets a new line before its turn is restored first, so the order of the lines stays right.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local AL, Conv, Unread = chat.ArchiveLogic, chat.Conversations, chat.Unread

local Archive = {}
chat.Archive = Archive

-- Lines put back per frame, fewer in combat.
Archive.STEP_LINES = 250
Archive.STEP_LINES_COMBAT = 60
Archive.TRIM_DELAY = 20

local attached, restored = false, false
local own = ""
local generation = 0
local opts = AL.Options(nil)
local sections = {}
local counts = { char = 0, acct = 0 }
local pending, queue, queueAt = {}, {}, 1

local function history()
  local db = chat.db
  if type(db) ~= "table" then
    return nil
  end
  if type(db.archive) ~= "table" then
    db.archive = AL.NewHistory()
  end
  return db.archive
end

-- Texts that stand for a line the game would not let the add-on read; they are never saved.
local function placeholders()
  local L = FG.L
  return { [L["chat.restricted.name"]] = true, [L["chat.bnet.unknown"]] = true }
end

local function stableOwn(name)
  return type(name) == "string" and name:find("%S+%-%S+") ~= nil
end

local function wanted()
  local ingest = chat.Ingest
  return opts.enabled and opts.intake and ingest ~= nil and ingest.IsRunning() and ingest.Wanted()
end

-- State -------------------------------------------------------------------------------------------------------

function Archive.Active()
  return attached
end

function Archive.Wanted()
  return wanted() and true or false
end

function Archive.LegacyDone()
  local h = history()
  return h ~= nil and h.legacy == true
end

function Archive.MarkLegacy()
  local h = history()
  if h then
    h.legacy = true
  end
end

-- Lines and size per scope, for the diagnosis.
function Archive.Report()
  local out = { lines = { char = counts.char, acct = counts.acct }, bytes = 0 }
  for _, section in pairs(sections) do
    out.bytes = out.bytes + AL.EstimateBytes(section)
  end
  return out
end

local function setSink(on)
  local main = FG.ChatHistory
  if main and main.SetMessengerStore then
    main.SetMessengerStore(on == true)
  end
end

local function emit(keys)
  if next(keys) ~= nil then
    FG.Emit("FG_CHAT_UPDATE", keys, Unread.Total(chat.convs))
  end
end

local function recount()
  counts.char, counts.acct = AL.Total(sections.char), AL.Total(sections.acct)
end

-- Cleaning -----------------------------------------------------------------------------------------------------

function Archive.Trim()
  if not attached then
    return
  end
  local h, now = history(), FG.U.now()
  local pins = chat.db.pins
  for scope, section in pairs(sections) do
    AL.Trim(section, { now = now, days = opts.days, pins = pins, cap = AL.CAP[scope] })
  end
  AL.TrimChars(h, now, opts.days, own)
  recount()
end

local function scheduleTrim()
  FG.Debounce("chat-archive-trim", Archive.TRIM_DELAY, Archive.Trim)
end

-- Writing ------------------------------------------------------------------------------------------------------

local function record(conv, line)
  if not attached then
    return
  end
  local scope = AL.Scope(conv.kind)
  local section = scope and sections[scope]
  if not section or (conv.public and not opts.public) then
    return
  end
  local time, code, sender, text = AL.Pack(line, placeholders())
  if not time then
    return
  end
  counts[scope] = counts[scope] + AL.Append(section, conv.key, conv, time, code, sender, text, FG.U.now())
  if counts[scope] > AL.CAP[scope] + AL.CAP_SLACK then
    scheduleTrim()
  end
end

-- Takes the lines of a merged conversation as the new content of its entry, and drops the old key.
function Archive.Merged(conv, oldKey)
  if not attached then
    return
  end
  local scope = AL.Scope(conv.kind)
  local section = scope and sections[scope]
  if not section then
    return
  end
  section.c[oldKey] = nil
  AL.Rewrite(section, conv.key, conv, conv.lines, placeholders(), FG.U.now())
  pending[oldKey] = nil
  recount()
end

-- Removes the saved lines of one conversation ("Remove history" in the menu).
function Archive.Forget(key)
  pending[key] = nil
  local scope = AL.Scope(Conv.KindOf(key))
  local section = scope and sections[scope] or nil
  if section then
    section.c[key] = nil
    recount()
  end
end

-- Restoring -----------------------------------------------------------------------------------------------------

local function restoreOne(item, touched)
  pending[item.key] = nil
  local lines = AL.Read(item.entry)
  if not lines or #lines == 0 then
    return 0
  end
  local conv = Conv.Restore(chat.convs, item.key, {
    name = item.entry.n,
    public = item.entry.p,
    tag = item.entry.g,
    character = item.entry.w,
    lines = lines,
  })
  if conv then
    touched[item.key] = true
  end
  return #lines
end

local function step(token)
  if token ~= generation then
    return
  end
  local budget = FG.InCombat() and Archive.STEP_LINES_COMBAT or Archive.STEP_LINES
  local touched, used = {}, 0
  while queueAt <= #queue and (used < budget or used == 0) do
    local item = queue[queueAt]
    queueAt = queueAt + 1
    if pending[item.key] then
      used = used + restoreOne(item, touched)
    end
  end
  emit(touched)
  if queueAt <= #queue then
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      timer.After(0, function()
        step(token)
      end)
    else
      step(token)
    end
  end
end

local function buildQueue()
  local pins, list = chat.db.pins, {}
  for scope, section in pairs(sections) do
    for key, entry in pairs(section.c) do
      local kind = Conv.KindOf(key)
      if kind and AL.Scope(kind) == scope then
        list[#list + 1] = { key = key, entry = entry, pinned = pins[key] == true, t = tonumber(entry.t) or 0 }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.pinned ~= b.pinned then
      return a.pinned
    end
    if a.t ~= b.t then
      return a.t > b.t
    end
    return a.key < b.key
  end)
  for i = #list, chat.convs.limits.conversations + 1, -1 do
    list[i] = nil
  end
  pending, queue, queueAt = {}, list, 1
  for _, item in ipairs(list) do
    pending[item.key] = item
  end
end

local function onBefore(key)
  local item = pending[key]
  if item then
    restoreOne(item, {})
  end
end

local function startRestore()
  if restored then
    return
  end
  restored = true
  buildQueue()
  if #queue > 0 then
    local token = generation
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      timer.After(0, function()
        step(token)
      end)
    else
      step(token)
    end
  end
end

-- Attaching -----------------------------------------------------------------------------------------------------

local function lineLimit(conv)
  return AL.LineLimit(conv.kind, conv.public)
end

local function attach()
  if attached or not stableOwn(own) then
    return
  end
  local h = history()
  local now = FG.U.now()
  sections = { char = AL.Section(h, "char", own), acct = AL.Section(h, "acct") }
  AL.TrimChars(h, now, opts.days, own)
  for scope, section in pairs(sections) do
    AL.Trim(section, { now = now, days = opts.days, pins = chat.db.pins, cap = AL.CAP[scope] })
  end
  recount()
  attached = true
  local state = chat.convs
  state.onAdd, state.onBefore, state.lineLimit = record, onBefore, lineLimit
  -- The whispers of the old recorder come in once, before anything is restored.
  if chat.Ingest and chat.Ingest.LoadHistory then
    chat.Ingest.LoadHistory()
  end
  startRestore()
end

local function detach()
  local state = chat.convs
  if state.onAdd == record then
    state.onAdd, state.onBefore, state.lineLimit = nil, nil, nil
  end
  attached = false
  generation = generation + 1
  pending, queue, queueAt = {}, {}, 1
end

-- Follows the switches: the add-on running, the option and the intake. own: the character as "Name-Realm".
function Archive.Refresh(ownName)
  if type(ownName) == "string" then
    own = ownName
  end
  opts = AL.Options(chat.db)
  local on = wanted()
  setSink(on and stableOwn(own))
  if on then
    attach()
  elseif attached then
    detach()
  end
end

-- After the memory was emptied (Ingest.Stop with clear): the next start restores again.
function Archive.Reset()
  detach()
  restored = false
  sections = {}
  counts.char, counts.acct = 0, 0
  setSink(false)
end

-- Deleting -------------------------------------------------------------------------------------------------------

-- Deletes the saved conversations and the ones in memory. scope: "all" (every character and the account) or a tab
-- of the messenger (Conversations.TAB_KINDS: this character and the account). Returns the number of lines saved
-- that were deleted.
function Archive.Clear(scope)
  local h = history()
  local kinds = scope ~= "all" and Conv.TAB_KINDS[scope] or nil
  if scope ~= "all" and not kinds then
    return 0
  end
  local removed = 0
  if h then
    if kinds == nil then
      for _, section in pairs(h.chars) do
        removed = removed + AL.Clear(section, nil)
      end
      removed = removed + AL.Clear(h.acct, nil)
    else
      local mine = type(own) == "string" and own ~= "" and h.chars[own] or nil
      removed = AL.Clear(mine, kinds) + AL.Clear(h.acct, kinds)
    end
  end
  local gone = {}
  for key, conv in pairs(chat.convs.convs) do
    if conv.kind ~= "team" and (kinds == nil or kinds[conv.kind]) then
      gone[#gone + 1] = key
    end
  end
  local touched = {}
  for _, key in ipairs(gone) do
    Conv.Remove(chat.convs, key)
    touched[key] = true
    pending[key] = nil
  end
  recount()
  emit(touched)
  return removed
end

FG.On("PLAYER_LOGOUT", function()
  if attached then
    Archive.Trim()
  end
end)

-- The own name may be known only after the login: look again.
local function again()
  if chat.Ingest and chat.Ingest.IsRunning() then
    Archive.Refresh(chat.Ingest.Own())
  end
end
FG.On("PLAYER_LOGIN", again)
FG.On("PLAYER_ENTERING_WORLD", again)

-- The saved data came in (ChatIngest.lua starts the intake after this): nothing taken from the defaults stays.
FG.On("FG_CHAT_STORE_READY", Archive.Reset)
