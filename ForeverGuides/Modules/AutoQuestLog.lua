-- Diagnostic log of the quest helper (/fg autoquest log): a ring buffer in memory, the fixed reason
-- codes of every place where the helper stays out, and the line format. No game calls. Lines hold
-- ids, numbers, decisions and reason codes only, never a title, a gossip text or a name, and a value
-- the game hides is written as "geheim".
local _, ns = ...

local Log = {}
ns.AutoQuestLog = Log

Log.CAPACITY = 300
-- The value is secret (hidden by the game). Callers pass this marker instead of the value.
Log.SECRET = setmetatable({}, {
  __tostring = function()
    return "geheim"
  end,
})

local KIND_WORD = { normal = "normal", daily = "taeglich", weekly = "woechentlich" }

-- Reason codes. Every silent exit of the helper has one, the station table below ties them to the
-- numbered places of the behaviour description (S01 to S30).
Log.Code = {
  off = "aus",
  handlerError = "fehler_im_handler",
  combat = "kampf",
  keyHeld = "taste_gehalten",
  keyNeeded = "taste_noetig",
  noQuestId = "keine_quest_id",
  questIdSecret = "quest_id_geheim",
  ignoredQuest = "ausnahme_quest",
  ignoredNpc = "ausnahme_npc",
  fromPlayer = "quest_von_spieler",
  autoAccept = "spiel_nimmt_selbst_an",
  kindSecret = "art_geheim",
  notReady = "nicht_abgabebereit",
  readySecret = "abgabestatus_geheim",
  notCompletable = "nicht_abgabebereit",
  goldSecret = "gold_geheim",
  goldMissing = "gold_fehlt",
  currencySecret = "waehrung_geheim",
  currencyMissing = "waehrung_fehlt",
  itemsSecret = "items_geheim",
  itemsMissing = "items_fehlt",
  choicesUnreadable = "auswahl_unlesbar",
  noEntries = "kein_questeintrag",
  nothingFits = "keiner_geeignet",
  alreadyTried = "bereits_versucht",
  learnedManual = "manuell_gelernt",
  rewardChoice = "belohnungswahl",
  goldDemand = "gold_gefordert",
  currencyDemand = "waehrung_gefordert",
  itemsDemand = "items_gefordert",
  listUnreadable = "liste_unlesbar",
  questLogFull = "questlog_voll",
  noEvent = "kein_ereignis",
  secretValue = "geheim",
}

-- code(name, detail): the fixed code, with the detail in brackets when there is one.
function Log.WithDetail(code, detail)
  if detail == nil then
    return code
  end
  return code .. "(" .. tostring(detail) .. ")"
end

function Log.Missing(path)
  return "api_fehlt:" .. tostring(path)
end

function Log.Secret(name)
  return "geheim:" .. tostring(name)
end

function Log.KindOff(kind)
  return "art_aus:" .. (KIND_WORD[kind] or KIND_WORD.normal)
end

-- The key names the step and the quest, for example "accept:77".
function Log.Loop(key, tries, seconds)
  return string.format("schleifenschutz:%s(%d,%.0fs)", tostring(key), tries or 0, seconds or 0)
end

-- Which code belongs to which numbered place. Used by the tests, each one has to be reachable.
Log.STATIONS = {
  S01 = Log.Code.off,
  S02 = Log.Code.handlerError,
  S03 = "api_fehlt",
  S04 = Log.Code.secretValue,
  S05 = Log.Code.combat,
  S06 = Log.Code.keyHeld,
  S07 = Log.Code.noQuestId,
  S08 = Log.Code.ignoredQuest,
  S09 = Log.Code.fromPlayer,
  S10 = "art_aus",
  S11 = "schleifenschutz:accept",
  S12 = Log.Code.notCompletable,
  S13 = Log.Code.goldDemand,
  S14 = Log.Code.currencyDemand,
  S15 = Log.Code.itemsDemand,
  S16 = "schleifenschutz:complete",
  S17 = Log.Code.choicesUnreadable,
  S18 = Log.Code.rewardChoice,
  S19 = "schleifenschutz:reward",
  S20 = "api_fehlt:C_GossipInfo",
  S21 = Log.Code.listUnreadable,
  S22 = Log.Code.listUnreadable,
  S23 = "api_fehlt:GetNumAvailableQuests",
  S24 = Log.Code.noEntries,
  S25 = Log.Code.ignoredQuest,
  S26 = Log.Code.alreadyTried,
  S27 = "art_aus",
  S28 = "schleifenschutz:select",
  S29 = Log.Code.keyNeeded,
  S30 = "api_fehlt:SelectAvailableQuest",
}

-- Values ------------------------------------------------------------------------------------------------

local ALLOWED = "^[%w_:%(%)#,%.%-/>=+ ]*$"

-- One value as text: numbers, yes or no, a fixed code, "geheim" or "leer".
function Log.Text(value)
  if value == nil then
    return "leer"
  end
  if value == Log.SECRET then
    return "geheim"
  end
  local kind = type(value)
  if kind == "boolean" then
    return value and "ja" or "nein"
  end
  if kind == "number" then
    if value ~= value then
      return "?"
    end
    return value == math.floor(value) and string.format("%d", value) or string.format("%.1f", value)
  end
  if kind == "string" and #value <= 80 and value:match(ALLOWED) then
    return value
  end
  return "?"
end

function Log.KV(key, value)
  return key .. "=" .. Log.Text(value)
end

-- Several pairs in one segment: Log.Group({ "angeboten", 2 }, { "aktiv", 1 }) -> "angeboten=2 aktiv=1".
function Log.Group(...)
  local parts = {}
  for _, pair in ipairs({ ... }) do
    parts[#parts + 1] = Log.KV(pair[1], pair[2])
  end
  return table.concat(parts, " ")
end

-- Buffer ------------------------------------------------------------------------------------------------

local enabled, startedAt = false, 0
local lines = {}

function Log.Enabled()
  return enabled
end

local function push(text)
  lines[#lines + 1] = text
  if #lines > Log.CAPACITY then
    table.remove(lines, 1)
  end
end

function Log.Clear()
  lines = {}
end

-- Switches on, empties the buffer and writes the header lines (plain text, no time).
function Log.Start(now, header)
  enabled, startedAt = true, tonumber(now) or 0
  lines = {}
  for _, text in ipairs(header or {}) do
    push(text)
  end
end

-- The buffer stays readable after it is off.
function Log.Stop()
  enabled = false
end

-- "+12.3 | EVENT | segment | segment". Does nothing while the log is off.
function Log.Add(now, event, segments)
  if not enabled then
    return
  end
  local parts = { string.format("+%.1f", (tonumber(now) or startedAt) - startedAt), event }
  for _, segment in ipairs(segments or {}) do
    parts[#parts + 1] = segment
  end
  push((table.concat(parts, " | "):gsub("[\r\n]+", " ")))
end

function Log.Count()
  return #lines
end

function Log.Lines()
  local copy = {}
  for i, text in ipairs(lines) do
    copy[i] = text
  end
  return copy
end

function Log.Dump()
  return table.concat(lines, "\n")
end
