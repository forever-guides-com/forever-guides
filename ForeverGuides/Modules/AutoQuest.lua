-- Auto quests (settings.autoQuest, off by default): accepts and turns in quests as long as nothing has
-- to be chosen or paid. Accepting honors the switches for normal, daily and weekly quests. Turning in
-- stops at a gold or currency demand, at required items (unless "also with items" is on) and at
-- more than one reward choice, then the window stays open and one chat line says why (switch
-- autoQuestNotice). Gossip and quest greetings: only quest entries are ever picked (never another
-- gossip option). All entries of the list are looked at, turn-ins before offers, and the first one the
-- filters allow and this conversation has not tried yet is taken, so a quest that needs the player
-- never holds back the others. Shared quests (QUEST_ACCEPT_CONFIRM) are never touched. Exceptions by
-- quest id and NPC id, nothing in combat. The loop guard counts the tries the game did not answer
-- with QUEST_ACCEPTED, QUEST_TURNED_IN or the next window. The override key stops it, with "key
-- needed" it is the other way round. Every decision goes to AutoQuestLog while that log is on.
local _, ns = ...
local Guard, QL, Log, L = ns.AutoGuard, ns.AutoQuestLogic, ns.AutoQuestLog, ns.L
local Code = Log.Code
local Store = ns.Store

local Q = {}
ns.AutoQuest = Q

ns.AddLocale("enUS", {
  ["auto.quest.accepted"] = "Quest accepted: %s",
  ["auto.quest.done"] = "Quest turned in: %s",
  ["auto.quest.hint.choice"] = "This quest has a reward choice. Pick the reward yourself.",
  ["auto.quest.hint.items"] = 'This quest takes items. Hand it in yourself or switch on "Also with items" in the automation settings.',
  ["auto.quest.hint.money"] = "This quest asks for gold or a currency. Hand it in yourself.",
  ["auto.quest.hint.logfull"] = "Your quest log is full. Free a slot to take this quest.",
  ["auto.quest.added"] = "Ignored from now on: %s %d",
  ["auto.quest.kind.quest"] = "quest",
  ["auto.quest.kind.npc"] = "NPC",
  ["auto.quest.list"] = "Ignored quests: %s | ignored NPCs: %s",
  ["auto.quest.none"] = "none",
  ["auto.quest.usage"] = "Usage: /fg autoquest ignore <quest ID> | ignore npc <NPC ID> | list | log [on|off|show|clear]",
})
ns.AddLocale("deDE", {
  ["auto.quest.accepted"] = "Quest angenommen: %s",
  ["auto.quest.done"] = "Quest abgegeben: %s",
  ["auto.quest.hint.choice"] = "Diese Quest hat eine Belohnungswahl. Wähle die Belohnung selbst.",
  ["auto.quest.hint.items"] = 'Diese Quest nimmt Gegenstände. Gib sie selbst ab oder schalte "Auch mit Item-Abgabe" in den Automatik-Einstellungen ein.',
  ["auto.quest.hint.money"] = "Diese Quest verlangt Gold oder eine Währung. Gib sie selbst ab.",
  ["auto.quest.hint.logfull"] = "Dein Questlog ist voll. Mach einen Platz frei, um diese Quest anzunehmen.",
  ["auto.quest.added"] = "Wird ab jetzt ignoriert: %s %d",
  ["auto.quest.kind.quest"] = "Quest",
  ["auto.quest.kind.npc"] = "NPC",
  ["auto.quest.list"] = "Ignorierte Quests: %s | ignorierte NPCs: %s",
  ["auto.quest.none"] = "keine",
  ["auto.quest.usage"] = "Benutzung: /fg autoquest ignore <Quest-ID> | ignore npc <NPC-ID> | list | log [on|off|show|clear]",
})

local ID = "autoQuest"
local KEY = { quest = "autoQuestIgnoreQuests", npc = "autoQuestIgnoreNpcs" }

local loops = QL.NewLoops()
local talk = QL.NewTalk()
Q.loops, Q.talk = loops, talk

-- Why the last unanswered try of a key failed ("kein_ereignis", "questlog_voll").
local failed = {}
-- The quest the helper accepted last, for the quest log full message that follows.
local lastAccept

function Q.Failed(key)
  return failed[key]
end

local function settings()
  return ns.db.settings
end

-- Reading the game ------------------------------------------------------------------------------------

-- True when the game hides the value from the add-on.
local function hidden(value)
  return value ~= nil and Guard.Safe(value) == nil
end

local function number(value)
  value = Guard.Safe(value)
  return type(value) == "number" and value == value and value or nil
end

-- "ok" and the value, "missing" when the function does not exist, "secret" when its answer is hidden.
local function read(path, ...)
  local found, value = Guard.Call(path, ...)
  if not found then
    return "missing"
  end
  if hidden(value) then
    return "secret"
  end
  return "ok", value
end

-- A yes or no answer: true or false, Log.SECRET when hidden. A missing function answers false.
local function truth(path, ...)
  local state, value = read(path, ...)
  if state == "secret" then
    return Log.SECRET
  end
  return state == "ok" and value == true
end

-- Writing the log ---------------------------------------------------------------------------------------

-- When the helper last called the game, for the answers it watches.
local lastActionAt

-- Parts are ready made segments. Nothing is read from the game for the log, only what the handler has.
-- The log only watches: a failure in it never reaches the helper.
local function emit(event, now, parts, decision, reason, action)
  if not Log.Enabled() then
    return
  end
  local segments = {}
  for _, part in ipairs(parts) do
    segments[#segments + 1] = part
  end
  segments[#segments + 1] = Log.KV("entscheidung", decision)
  if reason then
    segments[#segments + 1] = Log.KV("grund", reason)
  end
  if action then
    segments[#segments + 1] = Log.KV("aktion", action)
  end
  if decision == "beobachtet" and lastActionAt then
    segments[#segments + 1] = string.format("seit_aktion=%.1fs", now - lastActionAt)
  end
  pcall(Log.Add, now, event, segments)
end

local function stay(ctx, reason)
  emit(ctx.event, ctx.now, ctx.parts, "ueberspringen", reason)
end

-- Context of one window -------------------------------------------------------------------------------

-- Not in combat, and the override key decides: held stops the helper, or with "key needed" starts it.
-- Returns the reason code while it has to stay out.
local function paused()
  if Guard.Blocked() then
    return Code.combat
  end
  local held = Guard.Override()
  if held == (settings().autoQuestNeedKey == true) then
    return nil
  end
  return held and Code.keyHeld or Code.keyNeeded
end

-- The NPC id of the open window and what the log shows for it.
local function npcId()
  local state, guid = read("UnitGUID", "npc")
  if state == "secret" then
    return nil, Log.SECRET
  end
  local id = state == "ok" and QL.NpcId(guid) or nil
  return id, id
end

-- The quest id of the open window, else nil with the reason and what the log shows.
local function questId()
  local state, value = read("GetQuestID")
  if state == "missing" then
    return nil, Log.Missing("GetQuestID")
  end
  if state == "secret" then
    return nil, Code.questIdSecret, Log.SECRET
  end
  value = number(value)
  if value and value > 0 then
    return value
  end
  return nil, Code.noQuestId
end

-- The title is read before the quest is taken or turned in: the window text is gone afterwards. Without it
-- the quest log knows the title of the id.
local function title(id)
  local found, text = Guard.Call("GetTitleText")
  text = found and Guard.Safe(text) or nil
  if type(text) ~= "string" or text == "" then
    local foundLog, logged = Guard.Call("C_QuestLog.GetTitleForQuestID", id)
    text = foundLog and Guard.Safe(logged) or nil
  end
  return type(text) == "string" and text ~= "" and text or "?"
end

-- The game answered a try of the helper: gives the loop guard its count back. Returns the seconds it took.
local function answered(key, now)
  local ok, waited = loops.confirm(key, now)
  if ok then
    failed[key] = nil
  end
  return ok and waited or nil
end

-- Starts a handler: the conversation memory moves on, the id is read, the answers of the game to earlier
-- tries are booked (prefixes of the loop keys the window answers) and the checks that apply to every
-- window run. Returns the context, or nil after the reason went to the log.
local function begin(event, ...)
  local now = Guard.Now()
  talk.touch(now)
  local id, reason, shown = questId()
  local npc, npcShown = npcId()
  local ctx = {
    event = event,
    now = now,
    id = id,
    npc = npc,
    parts = { Log.KV("quest", id or shown), Log.KV("npc", npcShown) },
  }
  if id then
    for _, prefix in ipairs({ ... }) do
      answered(prefix .. id, now)
    end
  end
  local pause = paused()
  if pause then
    return stay(ctx, pause)
  end
  if not id then
    return stay(ctx, reason)
  end
  local by = QL.IgnoredBy(settings(), id, npc)
  if by then
    return stay(ctx, by == "quest" and Code.ignoredQuest or Code.ignoredNpc)
  end
  return ctx
end

-- A try of the helper: counted until the game answers. Returns true while it is within the limit,
-- otherwise the reason code.
local function attempt(key, now)
  failed[key] = nil
  local ok, tries, seconds = loops.try(key, now)
  if ok then
    return true
  end
  return false, Log.Loop(key, tries, seconds)
end

-- Looks in two seconds whether the game answered, and counts every try it did not.
local function watch()
  lastActionAt = Guard.Now()
  Guard.After(ID, QL.CONFIRM_WINDOW, Q.Verify)
end

function Q.Verify()
  local now = Guard.Now()
  for _, key in ipairs(loops.expire(now)) do
    failed[key] = failed[key] or Code.noEvent
    local waited = string.format("ergebnis=keins nach %.1fs", QL.CONFIRM_WINDOW)
    emit("PRUEFUNG", now, { Log.KV("schritt", key), waited }, "fehlgeschlagen", failed[key])
  end
end

-- Chat hints ------------------------------------------------------------------------------------------------

-- One line that says why nothing happens, once per quest and conversation. Only for cases that need the
-- player. Not tied to "messages in chat": it only explains.
local function hint(kind, id)
  if settings().autoQuestNotice == false or not talk.firstHint(kind .. ":" .. id) then
    return
  end
  ns.Notify.chat(L["auto.quest.hint." .. kind])
end

-- Accepting -------------------------------------------------------------------------------------------------

-- The kind of the quest in the window. "geheim" when the game hides it.
local function windowKind()
  local daily, weekly = truth("QuestIsDaily"), truth("QuestIsWeekly")
  if daily == Log.SECRET or weekly == Log.SECRET then
    return "geheim"
  end
  return QL.Kind(daily, weekly)
end

function Q.OnDetail()
  local ctx = begin("QUEST_DETAIL", "select:available:")
  if not ctx then
    return
  end
  local id = ctx.id
  -- A quest offered by a player is a shared quest, and an auto-accept quest is taken by the game.
  local fromPlayer, taken = truth("UnitIsPlayer", "npc"), truth("QuestGetAutoAccept")
  if fromPlayer == Log.SECRET then
    return stay(ctx, Log.Secret("UnitIsPlayer"))
  end
  if taken == Log.SECRET then
    return stay(ctx, Log.Secret("QuestGetAutoAccept"))
  end
  if fromPlayer then
    return stay(ctx, Code.fromPlayer)
  end
  if taken then
    return stay(ctx, Code.autoAccept)
  end
  local kind = windowKind()
  ctx.parts[#ctx.parts + 1] = Log.KV("art", kind)
  if kind == "geheim" then
    if not QL.AllKindsAllowed(settings()) then
      return stay(ctx, Code.kindSecret)
    end
  elseif not QL.KindAllowed(settings(), kind) then
    return stay(ctx, Log.KindOff(kind))
  end
  if not Guard.Has("AcceptQuest") then
    return stay(ctx, Log.Missing("AcceptQuest"))
  end
  local ok, loop = attempt("accept:" .. id, ctx.now)
  if not ok then
    return stay(ctx, loop)
  end
  local name = title(id)
  lastAccept = { id = id, at = ctx.now }
  Guard.Call("AcceptQuest")
  emit(ctx.event, ctx.now, ctx.parts, "annehmen", nil, "AcceptQuest")
  Guard.Say(ID, string.format(L["auto.quest.accepted"], name))
  watch()
end

-- Turning in -------------------------------------------------------------------------------------------------

-- The first reason the helper cannot hand the quest in, as a reason code. The second value names the
-- demands that need the player ("money" or "items"), nil for a value that could not be read.
local function demand()
  local state, gold = read("GetQuestMoneyToGet")
  if state == "missing" then
    return Code.goldMissing
  end
  if state == "secret" then
    return Code.goldSecret
  end
  gold = number(gold)
  if gold == nil then
    return Code.goldMissing
  end
  if gold > 0 then
    return Log.WithDetail(Code.goldDemand, gold), "money"
  end
  local currencyState, currencies = read("GetNumQuestCurrencies")
  if currencyState == "secret" then
    return Code.currencySecret
  end
  if currencyState == "ok" then
    currencies = number(currencies)
    if currencies == nil then
      return Code.currencyMissing
    end
    if currencies > 0 then
      return Log.WithDetail(Code.currencyDemand, currencies), "money"
    end
  end
  local itemState, items = read("GetNumQuestItems")
  if itemState == "missing" then
    return Code.itemsMissing
  end
  if itemState == "secret" then
    return Code.itemsSecret
  end
  items = number(items)
  if items == nil then
    return Code.itemsMissing
  end
  if items > 0 and settings().autoQuestItems ~= true then
    return Log.WithDetail(Code.itemsDemand, items), "items"
  end
end

function Q.OnProgress()
  local ctx = begin("QUEST_PROGRESS", "select:active:")
  if not ctx then
    return
  end
  local id = ctx.id
  local completable = truth("IsQuestCompletable")
  if completable == Log.SECRET then
    return stay(ctx, Log.Secret("IsQuestCompletable"))
  end
  if not completable then
    return stay(ctx, Code.notCompletable)
  end
  local reason, kind = demand()
  if reason then
    if kind then
      talk.setManual(id, kind == "items" and Code.itemsDemand or Code.goldDemand, ctx.now, kind == "items")
      hint(kind, id)
    end
    return stay(ctx, reason)
  end
  if not Guard.Has("CompleteQuest") then
    return stay(ctx, Log.Missing("CompleteQuest"))
  end
  local ok, loop = attempt("complete:" .. id, ctx.now)
  if not ok then
    return stay(ctx, loop)
  end
  Guard.Call("CompleteQuest")
  emit(ctx.event, ctx.now, ctx.parts, "abgeben", nil, "CompleteQuest")
  watch()
end

function Q.OnComplete()
  local ctx = begin("QUEST_COMPLETE", "select:active:", "complete:")
  if not ctx then
    return
  end
  local id = ctx.id
  local state, count = read("GetNumQuestChoices")
  local choices = state == "ok" and number(count) or nil
  if choices == nil then
    return stay(ctx, state == "missing" and Log.Missing("GetNumQuestChoices") or Code.choicesUnreadable)
  end
  ctx.parts[#ctx.parts + 1] = Log.KV("auswahl", choices)
  if choices > 1 then
    talk.setManual(id, Code.rewardChoice, ctx.now, false)
    hint("choice", id)
    return stay(ctx, Log.WithDetail(Code.rewardChoice, choices))
  end
  if not Guard.Has("GetQuestReward") then
    return stay(ctx, Log.Missing("GetQuestReward"))
  end
  local ok, loop = attempt("reward:" .. id, ctx.now)
  if not ok then
    return stay(ctx, loop)
  end
  local name = title(id)
  Guard.Call("GetQuestReward", choices == 1 and 1 or 0)
  emit(ctx.event, ctx.now, ctx.parts, "belohnung", nil, "GetQuestReward")
  Guard.Say(ID, string.format(L["auto.quest.done"], name))
  watch()
end

-- Answers of the game -----------------------------------------------------------------------------------------

-- The segments of an answer of the game: the quest id and, when it answered a try, how long it took.
local function answerParts(id, waited)
  local parts = { Log.KV("quest", id or Log.SECRET) }
  if waited then
    parts[#parts + 1] = string.format("ergebnis=ok nach %.1fs", waited)
  end
  return parts
end

-- QUEST_ACCEPTED brings the quest id, after the log index in some clients.
function Q.OnAccepted(first, second)
  local now = Guard.Now()
  local id = number(second) or number(first)
  local waited
  if id then
    waited = answered("accept:" .. id, now)
    talk.release("available:" .. id)
  end
  talk.releasePositions()
  emit("QUEST_ACCEPTED", now, answerParts(id, waited), "beobachtet")
end

function Q.OnTurnedIn(first)
  local now = Guard.Now()
  local id = number(first)
  local waited
  if id then
    waited = answered("reward:" .. id, now)
    answered("complete:" .. id, now)
    talk.release("active:" .. id)
    talk.forget(id)
  end
  talk.releasePositions()
  emit("QUEST_TURNED_IN", now, answerParts(id, waited), "beobachtet")
end

-- GOSSIP_CLOSED and QUEST_FINISHED end a conversation once the next window stays away.
function Q.OnClosed(event)
  local now = Guard.Now()
  talk.closed(now)
  emit(event, now, {}, "beobachtet")
end

-- QUEST_AUTOCOMPLETE brings a quest id, QUEST_ACCEPT_CONFIRM only names, which the log never holds.
function Q.OnWatched(event, first)
  local id = event == "QUEST_AUTOCOMPLETE" and number(first) or nil
  emit(event, Guard.Now(), id and { Log.KV("quest", id) } or {}, "beobachtet")
end

-- "Your quest log is full" right after the helper accepted a quest.
function Q.OnUiError(...)
  local last = lastAccept
  if not last then
    return
  end
  local now = Guard.Now()
  local full = rawget(_G, "ERR_QUEST_LOG_FULL")
  if now - last.at > QL.CONFIRM_WINDOW then
    lastAccept = nil
    return
  end
  if type(full) ~= "string" then
    return
  end
  for i = 1, select("#", ...) do
    if Guard.Safe((select(i, ...))) == full then
      lastAccept = nil
      failed["accept:" .. last.id] = Code.questLogFull
      hint("logfull", last.id)
      emit("UI_ERROR_MESSAGE", now, { Log.KV("quest", last.id) }, "beobachtet", Code.questLogFull)
      return
    end
  end
end

-- Gossip and greeting lists --------------------------------------------------------------------------------

-- The turn-in state of an entry: true, false or QL.SECRET, with the quest log as an extra check for an
-- entry the list does not call complete. The second value is true when only the quest log said so.
local function completeOf(raw, id)
  local complete = false
  if hidden(raw) then
    complete = QL.SECRET
  elseif raw == true then
    return true
  end
  if id then
    local state, logged = read("C_QuestLog.IsComplete", id)
    if state == "ok" and logged == true then
      return true, true
    end
  end
  return complete
end

-- Entries of C_GossipInfo (quest ids), else nil and the reason. A hidden id marks that entry only.
local function modernEntries()
  local foundOffers, offers = Guard.Call("C_GossipInfo.GetAvailableQuests")
  local foundActive, active = Guard.Call("C_GossipInfo.GetActiveQuests")
  if not (foundOffers and foundActive) then
    return nil, Log.Missing(foundOffers and "C_GossipInfo.GetActiveQuests" or "C_GossipInfo.GetAvailableQuests")
  end
  if type(offers) ~= "table" or type(active) ~= "table" then
    return nil, Code.noEntries
  end
  local entries = {}
  for position, quest in ipairs(active) do
    local id = type(quest) == "table" and number(quest.questID) or nil
    local complete, viaLog = completeOf(type(quest) == "table" and quest.isComplete or nil, id)
    entries[#entries + 1] = {
      kind = "active",
      id = id,
      ref = id,
      pos = position,
      unreadable = id == nil,
      complete = complete,
      viaLog = viaLog,
    }
  end
  for position, quest in ipairs(offers) do
    local offer = type(quest) == "table" and quest or {}
    local id = number(offer.questID)
    entries[#entries + 1] = {
      kind = "available",
      id = id,
      ref = id,
      pos = position,
      unreadable = id == nil,
      kindUnknown = hidden(offer.frequency),
      frequency = number(offer.frequency),
    }
  end
  return entries
end

-- A list of results as one table, nil when the function does not exist.
local function collect(found, ...)
  if not found then
    return nil
  end
  return { n = select("#", ...), ... }
end

-- The 4th value of every record of a flat list (title, level, isTrivial, frequency or isComplete, ...). The
-- record size is not fixed across clients, so it is worked out from the count. Nil when the list does not
-- have the expected form.
local function fourth(path, count)
  if count < 1 then
    return nil
  end
  local values = collect(Guard.Call(path))
  if not values or values.n % count ~= 0 then
    return nil
  end
  local size = values.n / count
  if size < 4 then
    return nil
  end
  local out = {}
  for i = 1, count do
    local title_ = values[(i - 1) * size + 1]
    if type(title_) ~= "string" and not hidden(title_) then
      return nil
    end
    out[i] = values[(i - 1) * size + 4]
  end
  return out, size
end

-- The older gossip calls: counts and positions, no quest ids. Only used when C_GossipInfo gives nothing.
local function classicEntries()
  local stateOffers, offers = read("GetNumGossipAvailableQuests")
  local stateActive, active = read("GetNumGossipActiveQuests")
  if stateOffers == "missing" or stateActive == "missing" then
    return nil, Log.Missing(stateOffers == "missing" and "GetNumGossipAvailableQuests" or "GetNumGossipActiveQuests")
  end
  offers, active = number(offers), number(active)
  if not (offers and active) then
    return nil, Code.listUnreadable
  end
  local entries = {}
  local done, activeSize = fourth("GetGossipActiveQuests", active)
  done = done or {}
  for i = 1, active do
    local raw = done and done[i]
    entries[#entries + 1] = { kind = "active", ref = i, pos = i, complete = completeOf(raw, nil) }
  end
  local frequencies, offerSize = fourth("GetGossipAvailableQuests", offers)
  frequencies = frequencies or {}
  entries.layout = tostring(activeSize or "?") .. "/" .. tostring(offerSize or "?")
  for i = 1, offers do
    local frequency = frequencies and frequencies[i]
    entries[#entries + 1] = {
      kind = "available",
      ref = i,
      pos = i,
      kindUnknown = number(frequency) == nil,
      frequency = number(frequency),
    }
  end
  return entries
end

-- The list of a gossip window from one source only: C_GossipInfo, and the older calls when that gives no
-- entry. Returns the entries, the source and the reason when there are none.
local function gossipEntries()
  local entries, reason = modernEntries()
  if entries and #entries > 0 then
    return entries, "gossip"
  end
  local classic, classicReason = classicEntries()
  if classic and #classic > 0 then
    return classic, "classic"
  end
  if entries then
    return entries, "gossip", Code.noEntries
  end
  return nil, "gossip", reason or classicReason
end

-- The older quest greeting list: positions, with the id as far as the game tells it.
local function greetingEntries()
  local stateOffers, offers = read("GetNumAvailableQuests")
  local stateActive, active = read("GetNumActiveQuests")
  if stateOffers == "missing" or stateActive == "missing" then
    return nil, Log.Missing(stateOffers == "missing" and "GetNumAvailableQuests" or "GetNumActiveQuests")
  end
  offers, active = number(offers), number(active)
  if not (offers and active) then
    return nil, Code.listUnreadable
  end
  local entries = {}
  for i = 1, active do
    local _, _, raw = Guard.Call("GetActiveTitle", i)
    local _, id = Guard.Call("GetActiveQuestID", i)
    id = number(id)
    local complete, viaLog = completeOf(raw, id)
    entries[#entries + 1] = { kind = "active", id = id, ref = i, pos = i, complete = complete, viaLog = viaLog }
  end
  for i = 1, offers do
    local _, _, frequency, _, _, id = Guard.Call("GetAvailableQuestInfo", i)
    entries[#entries + 1] = {
      kind = "available",
      id = number(id),
      ref = i,
      pos = i,
      kindUnknown = hidden(frequency),
      frequency = number(frequency),
    }
  end
  return entries
end

local SELECT = {
  gossip = { active = "C_GossipInfo.SelectActiveQuest", available = "C_GossipInfo.SelectAvailableQuest" },
  classic = { active = "SelectGossipActiveQuest", available = "SelectGossipAvailableQuest" },
  greeting = { active = "SelectActiveQuest", available = "SelectAvailableQuest" },
}

local MAX_LISTED = 6

-- The counts and the entries passed over, as log segments.
local function describe(ctx, source, entries, passed)
  local offered, open, ready, viaLog = 0, 0, 0, 0
  for _, entry in ipairs(entries) do
    if entry.kind == "available" then
      offered = offered + 1
    else
      open = open + 1
      if entry.complete == true then
        ready = ready + 1
      end
      if entry.viaLog then
        viaLog = viaLog + 1
      end
    end
  end
  local parts = ctx.parts
  parts[#parts + 1] = Log.KV("quelle", source)
  parts[#parts + 1] = Log.Group({ "angeboten", offered }, { "aktiv", open }, { "fertig", ready })
  if viaLog > 0 then
    parts[#parts + 1] = Log.KV("fertig_ueber_questlog", viaLog)
  end
  if entries.layout then
    parts[#parts + 1] = Log.KV("schritt_aktiv_angeboten", entries.layout)
  end
  for i, item in ipairs(passed) do
    if i > MAX_LISTED then
      parts[#parts + 1] = Log.KV("weitere_uebergangen", #passed - MAX_LISTED)
      break
    end
    local entry = item.entry
    parts[#parts + 1] = Log.KV(
      "uebergangen",
      (entry.kind == "active" and "aktiv:" or "angeboten:")
        .. (entry.id and tostring(entry.id) or ("#" .. tostring(entry.pos)))
        .. ":"
        .. item.reason
    )
  end
end

local function choose(ctx, source, entries, reason)
  if not entries or #entries == 0 then
    return stay(ctx, reason or Code.noEntries)
  end
  local npc = ctx.npc
  local entry, passed = QL.Pick(entries, settings(), npc, talk, ctx.now)
  describe(ctx, source, entries, passed)
  if not entry then
    return stay(ctx, Log.WithDetail(Code.nothingFits, #entries))
  end
  local path = SELECT[source][entry.kind]
  if not Guard.Has(path) then
    return stay(ctx, Log.Missing(path))
  end
  -- An entry known by its position only has no id for the answer to refer to, the conversation memory
  -- guards it.
  if entry.id then
    local ok, loop = attempt("select:" .. entry.kind .. ":" .. entry.id, ctx.now)
    if not ok then
      return stay(ctx, loop)
    end
  end
  talk.mark(QL.EntryKey(entry))
  Guard.Call(path, entry.ref)
  ctx.parts[#ctx.parts + 1] = Log.KV(
    "gewaehlt",
    (entry.kind == "active" and "aktiv:" or "angeboten:") .. tostring(entry.id or ("#" .. entry.ref))
  )
  emit(ctx.event, ctx.now, ctx.parts, "waehle", nil, path)
  watch()
end

-- The window of an NPC: there is no quest id in it yet, only the list.
local function listWindow(event)
  local now = Guard.Now()
  talk.touch(now)
  local npc, npcShown = npcId()
  local ctx = { event = event, now = now, npc = npc, parts = { Log.KV("npc", npcShown) } }
  local pause = paused()
  if pause then
    return stay(ctx, pause)
  end
  return ctx
end

function Q.OnGossip()
  local ctx = listWindow("GOSSIP_SHOW")
  if ctx then
    local entries, source, reason = gossipEntries()
    choose(ctx, source, entries, reason)
  end
end

function Q.OnGreeting()
  local ctx = listWindow("QUEST_GREETING")
  if ctx then
    local entries, reason = greetingEntries()
    choose(ctx, "greeting", entries, reason)
  end
end

-- Chat command ----------------------------------------------------------------------------------

local function listText(kind)
  local ids = ns.SellLogic.ParseIds(settings()[KEY[kind]])
  return #ids > 0 and ns.SellLogic.JoinIds(ids) or L["auto.quest.none"]
end

function Q.Slash(rest)
  local command = QL.ParseCommand(rest)
  if command.action == "list" then
    ns.Notify.chat(string.format(L["auto.quest.list"], listText("quest"), listText("npc")))
  elseif command.action == "log" then
    ns.AutoQuestReport.Command(command.sub)
  elseif command.action == "ignore" then
    local text = QL.AddIgnore(settings()[KEY[command.kind]], command.id)
    if not text then
      ns.Notify.chat(L["auto.quest.usage"])
      return
    end
    Store.set("settings." .. KEY[command.kind], text)
    ns.Notify.chat(string.format(L["auto.quest.added"], L["auto.quest.kind." .. command.kind], command.id))
  else
    ns.Notify.chat(L["auto.quest.usage"])
  end
end

-- Events ---------------------------------------------------------------------------------------------------

-- The handler runs while the helper is on, protected. While it is off or fails, the log says so.
local function listen(event, fn)
  ns.On(event, function(_, ...)
    if not Guard.On(ID) then
      return Log.Enabled() and emit(event, Guard.Now(), {}, "ueberspringen", Code.off)
    end
    if not Guard.Run(ID, fn, ...) and Log.Enabled() then
      emit(event, Guard.Now(), {}, "ueberspringen", Code.handlerError)
    end
  end)
end

listen("QUEST_DETAIL", Q.OnDetail)
listen("QUEST_PROGRESS", Q.OnProgress)
listen("QUEST_COMPLETE", Q.OnComplete)
listen("GOSSIP_SHOW", Q.OnGossip)
listen("QUEST_GREETING", Q.OnGreeting)
listen("QUEST_ACCEPTED", Q.OnAccepted)
listen("QUEST_TURNED_IN", Q.OnTurnedIn)
ns.On("GOSSIP_CLOSED", function(event)
  if Guard.On(ID) then
    Guard.Run(ID, Q.OnClosed, event)
  end
end)
ns.On("QUEST_FINISHED", function(event)
  if Guard.On(ID) then
    Guard.Run(ID, Q.OnClosed, event)
  end
end)
-- Watched only for the log: the helper never answers these.
for _, event in ipairs({ "QUEST_ACCEPT_CONFIRM", "QUEST_AUTOCOMPLETE" }) do
  ns.On(event, function(_, first)
    if Log.Enabled() and Guard.On(ID) then
      Guard.Run(ID, Q.OnWatched, event, first)
    end
  end)
end
ns.On("UI_ERROR_MESSAGE", function(_, ...)
  if lastAccept and Guard.On(ID) then
    Guard.Run(ID, Q.OnUiError, ...)
  end
end)
