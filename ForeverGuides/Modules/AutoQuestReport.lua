-- /fg autoquest log on | off | show | clear: the game side of the quest helper log (AutoQuestLog is the
-- buffer and the format). Switching it on writes a header with the client, the settings and which game
-- functions and events exist, so a copied report explains itself. Nothing is saved: the log lives in memory
-- and is gone after a reload.
local _, ns = ...
local Guard, Log, SL, L = ns.AutoGuard, ns.AutoQuestLog, ns.SellLogic, ns.L

local D = {}
ns.AutoQuestReport = D

ns.AddLocale("enUS", {
  ["auto.quest.log.title"] = "Quest helper log",
  ["auto.quest.log.hint"] = "Copy the text with Ctrl+C and send it along. It holds ids and numbers only, no names and no texts.",
  ["auto.quest.log.on"] = "Quest log is on. Talk to quest givers, then show it with /fg autoquest log.",
  ["auto.quest.log.off"] = "Quest log is off. /fg autoquest log shows what it wrote.",
  ["auto.quest.log.cleared"] = "Quest log emptied.",
  ["auto.quest.log.empty"] = "Nothing logged yet. Switch it on with /fg autoquest log on.",
})
ns.AddLocale("deDE", {
  ["auto.quest.log.title"] = "Protokoll der Quest-Automatik",
  ["auto.quest.log.hint"] = "Kopiere den Text mit Strg+C und schicke ihn mit. Er enthält nur IDs und Zahlen, keine Namen und keine Texte.",
  ["auto.quest.log.on"] = "Quest-Protokoll ist an. Sprich mit Questgebern, danach zeigt /fg autoquest log es an.",
  ["auto.quest.log.off"] = "Quest-Protokoll ist aus. /fg autoquest log zeigt, was es geschrieben hat.",
  ["auto.quest.log.cleared"] = "Quest-Protokoll geleert.",
  ["auto.quest.log.empty"] = "Noch nichts protokolliert. Mit /fg autoquest log on einschalten.",
})

-- Game functions the helper uses or may use, and the events it listens to.
D.FUNCTIONS = {
  "AcceptQuest",
  "CompleteQuest",
  "GetQuestReward",
  "GetQuestID",
  "GetTitleText",
  "C_QuestLog.GetTitleForQuestID",
  "C_QuestLog.IsComplete",
  "QuestGetAutoAccept",
  "QuestIsDaily",
  "QuestIsWeekly",
  "UnitIsPlayer",
  "UnitGUID",
  "IsQuestCompletable",
  "GetQuestMoneyToGet",
  "GetNumQuestCurrencies",
  "GetNumQuestItems",
  "GetNumQuestChoices",
  "C_GossipInfo.GetAvailableQuests",
  "C_GossipInfo.GetActiveQuests",
  "C_GossipInfo.SelectAvailableQuest",
  "C_GossipInfo.SelectActiveQuest",
  "GetNumGossipAvailableQuests",
  "GetGossipAvailableQuests",
  "SelectGossipAvailableQuest",
  "GetNumGossipActiveQuests",
  "GetGossipActiveQuests",
  "SelectGossipActiveQuest",
  "GetNumAvailableQuests",
  "GetNumActiveQuests",
  "GetAvailableQuestInfo",
  "GetActiveTitle",
  "GetActiveQuestID",
  "SelectAvailableQuest",
  "SelectActiveQuest",
  "GetTime",
  "C_Timer.After",
  "issecretvalue",
  "canaccessvalue",
}

D.EVENTS = {
  "GOSSIP_SHOW",
  "QUEST_GREETING",
  "QUEST_DETAIL",
  "QUEST_PROGRESS",
  "QUEST_COMPLETE",
  "QUEST_ACCEPTED",
  "QUEST_TURNED_IN",
  "QUEST_FINISHED",
  "GOSSIP_CLOSED",
  "QUEST_ACCEPT_CONFIRM",
  "QUEST_AUTOCOMPLETE",
  "UI_ERROR_MESSAGE",
}

local MAX_LINE = 110

-- "name=ja" pairs, several to a line.
local function packed(prefix, names, test)
  local out, line = {}, prefix
  for _, name in ipairs(names) do
    local item = " " .. name .. "=" .. (test(name) and "ja" or "fehlt")
    if #line + #item > MAX_LINE then
      out[#out + 1] = line
      line = prefix
    end
    line = line .. item
  end
  out[#out + 1] = line
  return out
end

local function count(text)
  return #SL.ParseIds(text)
end

-- The lines at the top of a log: client, settings, functions and events.
function D.Header()
  local s = ns.db.settings
  local header = { "autoquest log (ids and numbers only, no texts)" }
  local locale = rawget(_G, "GetLocale")
  header[#header + 1] = "client: "
    .. ns.Client.DiagLine()
    .. " locale="
    .. Log.Text(type(locale) == "function" and select(2, pcall(locale)) or nil)
  header[#header + 1] = "settings: "
    .. Log.Group(
      { "autoQuest", s.autoQuest == true },
      { "normal", s.autoQuestNormal ~= false },
      { "daily", s.autoQuestDaily ~= false },
      { "weekly", s.autoQuestWeekly ~= false },
      { "items", s.autoQuestItems == true },
      { "needKey", s.autoQuestNeedKey == true },
      { "notice", s.autoQuestNotice ~= false },
      { "key", Guard.KeyId() },
      { "chat", s.autoChat ~= false },
      { "ignoredQuests", count(s.autoQuestIgnoreQuests) },
      { "ignoredNpcs", count(s.autoQuestIgnoreNpcs) }
    )
  for _, line in ipairs(packed("functions:", D.FUNCTIONS, Guard.Has)) do
    header[#header + 1] = line
  end
  for _, line in ipairs(packed("events:", D.EVENTS, ns.IsEventRegistered)) do
    header[#header + 1] = line
  end
  return header
end

local function say(key)
  ns.Notify.chat(L[key])
end

-- sub: "on", "off", "show" or "clear".
function D.Command(sub)
  if sub == "on" then
    Log.Start(Guard.Now(), D.Header())
    say("auto.quest.log.on")
  elseif sub == "off" then
    Log.Stop()
    say("auto.quest.log.off")
  elseif sub == "clear" then
    Log.Clear()
    say("auto.quest.log.cleared")
  else
    local text = Log.Dump()
    ns.Dialogs.Copy("auto.quest.log.title", text ~= "" and text or L["auto.quest.log.empty"], "auto.quest.log.hint")
  end
end
