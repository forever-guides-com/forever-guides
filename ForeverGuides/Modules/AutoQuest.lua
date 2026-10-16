-- Auto quests (settings.autoQuest, off by default): accepts and turns in quests as long as nothing has
-- to be chosen or paid. Accepting honors the switches for normal, daily and weekly quests. Turning in
-- stops at a gold or currency demand, at required items (unless "also with items" is on) and at
-- more than one reward choice, then the window stays open and a chat line says so. Gossip and quest
-- greetings: only quest entries are ever picked (never another gossip option), and only the first
-- quest ready to turn in or the single quest to accept. Shared quests (QUEST_ACCEPT_CONFIRM) are
-- never touched. Exceptions by quest id and NPC id, at most two tries per step and quest (loop
-- guard), nothing in combat. The override key stops it, with "key needed" it is the other way round.
local _, ns = ...
local Guard, QL, L = ns.AutoGuard, ns.AutoQuestLogic, ns.L
local Store = ns.Store

local Q = {}
ns.AutoQuest = Q

ns.AddLocale("enUS", {
  ["auto.quest.accepted"] = "Quest accepted: %s",
  ["auto.quest.done"] = "Quest turned in: %s",
  ["auto.quest.choose"] = "Choose your reward",
  ["auto.quest.added"] = "Ignored from now on: %s %d",
  ["auto.quest.kind.quest"] = "quest",
  ["auto.quest.kind.npc"] = "NPC",
  ["auto.quest.list"] = "Ignored quests: %s | ignored NPCs: %s",
  ["auto.quest.none"] = "none",
  ["auto.quest.usage"] = "Usage: /fg autoquest ignore <quest ID> | ignore npc <NPC ID> | list",
})
ns.AddLocale("deDE", {
  ["auto.quest.accepted"] = "Quest angenommen: %s",
  ["auto.quest.done"] = "Quest abgegeben: %s",
  ["auto.quest.choose"] = "Belohnung wählen",
  ["auto.quest.added"] = "Wird ab jetzt ignoriert: %s %d",
  ["auto.quest.kind.quest"] = "Quest",
  ["auto.quest.kind.npc"] = "NPC",
  ["auto.quest.list"] = "Ignorierte Quests: %s | ignorierte NPCs: %s",
  ["auto.quest.none"] = "keine",
  ["auto.quest.usage"] = "Benutzung: /fg autoquest ignore <Quest-ID> | ignore npc <NPC-ID> | list",
})

local ID = "autoQuest"
local KEY = { quest = "autoQuestIgnoreQuests", npc = "autoQuestIgnoreNpcs" }

local loops = QL.NewLoops()

local function settings()
  return ns.db.settings
end

local function number(value)
  value = Guard.Safe(value)
  return type(value) == "number" and value == value and value or nil
end

-- Not in combat, and the override key decides: held stops the helper, or with "key needed" starts it.
local function ready()
  if Guard.Blocked() then
    return false
  end
  return Guard.Override() == (settings().autoQuestNeedKey == true)
end

local function npcId()
  local found, guid = Guard.Call("UnitGUID", "npc")
  return found and QL.NpcId(Guard.Safe(guid)) or nil
end

local function questId()
  local found, id = Guard.Call("GetQuestID")
  id = found and number(id) or nil
  return id and id > 0 and id or nil
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

-- The id of the quest in the open window, nil when the helper has to stay out.
local function current()
  if not ready() then
    return nil
  end
  local id = questId()
  if not id or QL.Ignored(settings(), id, npcId()) then
    return nil
  end
  return id
end

local function allowedTry(key)
  return loops.try(key, Guard.Now())
end

function Q.OnDetail()
  local id = current()
  if not id then
    return
  end
  -- A quest offered by a player is a shared quest, and an auto-accept quest is taken by the game.
  local _, fromPlayer = Guard.Call("UnitIsPlayer", "npc")
  local _, taken = Guard.Call("QuestGetAutoAccept")
  if fromPlayer == true or taken == true then
    return
  end
  local _, daily = Guard.Call("QuestIsDaily")
  local _, weekly = Guard.Call("QuestIsWeekly")
  if not QL.KindAllowed(settings(), QL.Kind(daily == true, weekly == true)) or not allowedTry("accept:" .. id) then
    return
  end
  local name = title(id)
  Guard.Call("AcceptQuest")
  Guard.Say(ID, string.format(L["auto.quest.accepted"], name))
end

-- True when the quest asks for gold, a currency, or items the player did not allow.
local function demands()
  local foundGold, gold = Guard.Call("GetQuestMoneyToGet")
  gold = number(gold)
  if not foundGold or gold == nil or gold > 0 then
    return true
  end
  local foundCurrency, currencies = Guard.Call("GetNumQuestCurrencies")
  if foundCurrency and (number(currencies) or 1) > 0 then
    return true
  end
  local foundItems, items = Guard.Call("GetNumQuestItems")
  items = number(items)
  if not foundItems or items == nil then
    return true
  end
  return items > 0 and settings().autoQuestItems ~= true
end

function Q.OnProgress()
  local id = current()
  if not id then
    return
  end
  local _, completable = Guard.Call("IsQuestCompletable")
  if completable ~= true or demands() or not allowedTry("complete:" .. id) then
    return
  end
  Guard.Call("CompleteQuest")
end

function Q.OnComplete()
  local id = current()
  if not id then
    return
  end
  local found, choices = Guard.Call("GetNumQuestChoices")
  choices = found and number(choices) or nil
  if choices == nil then
    return
  end
  if choices > 1 then
    Guard.Say(ID, L["auto.quest.choose"])
    return
  end
  if not allowedTry("reward:" .. id) then
    return
  end
  local name = title(id)
  Guard.Call("GetQuestReward", choices == 1 and 1 or 0)
  Guard.Say(ID, string.format(L["auto.quest.done"], name))
end

-- The quest entries of an NPC window: gossip (quest ids) or the older greeting (list positions).
local function gossipEntries()
  local foundOffers, offers = Guard.Call("C_GossipInfo.GetAvailableQuests")
  local foundActive, active = Guard.Call("C_GossipInfo.GetActiveQuests")
  if not (foundOffers and foundActive and type(offers) == "table" and type(active) == "table") then
    return nil
  end
  local entries = {}
  for _, quest in ipairs(active) do
    local id = number(quest.questID)
    if not id then
      return nil
    end
    entries[#entries + 1] = { kind = "active", id = id, ref = id, complete = quest.isComplete == true }
  end
  for _, quest in ipairs(offers) do
    local id = number(quest.questID)
    if not id then
      return nil
    end
    entries[#entries + 1] = { kind = "available", id = id, ref = id, frequency = number(quest.frequency) }
  end
  return entries
end

local function greetingEntries()
  local foundOffers, offers = Guard.Call("GetNumAvailableQuests")
  local foundActive, active = Guard.Call("GetNumActiveQuests")
  offers, active = number(offers), number(active)
  if not (foundOffers and foundActive and offers and active) then
    return nil
  end
  local entries = {}
  for i = 1, active do
    local _, _, complete = Guard.Call("GetActiveTitle", i)
    local _, id = Guard.Call("GetActiveQuestID", i)
    entries[#entries + 1] = { kind = "active", id = number(id), ref = i, complete = complete == true }
  end
  for i = 1, offers do
    local _, _, frequency, _, _, id = Guard.Call("GetAvailableQuestInfo", i)
    entries[#entries + 1] = { kind = "available", id = number(id), ref = i, frequency = number(frequency) }
  end
  return entries
end

local SELECT = {
  gossip = { active = "C_GossipInfo.SelectActiveQuest", available = "C_GossipInfo.SelectAvailableQuest" },
  greeting = { active = "SelectActiveQuest", available = "SelectAvailableQuest" },
}

local function choose(source, entries)
  if not entries then
    return
  end
  local npc = npcId()
  local entry = QL.Pick(entries, settings(), npc)
  if not entry or not allowedTry("select:" .. entry.kind .. ":" .. tostring(entry.id or ("#" .. entry.ref))) then
    return
  end
  Guard.Call(SELECT[source][entry.kind], entry.ref)
end

function Q.OnGossip()
  if ready() then
    choose("gossip", gossipEntries())
  end
end

function Q.OnGreeting()
  if ready() then
    choose("greeting", greetingEntries())
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

ns.On("QUEST_DETAIL", function()
  Guard.Run(ID, Q.OnDetail)
end)
ns.On("QUEST_PROGRESS", function()
  Guard.Run(ID, Q.OnProgress)
end)
ns.On("QUEST_COMPLETE", function()
  Guard.Run(ID, Q.OnComplete)
end)
ns.On("GOSSIP_SHOW", function()
  Guard.Run(ID, Q.OnGossip)
end)
ns.On("QUEST_GREETING", function()
  Guard.Run(ID, Q.OnGreeting)
end)
