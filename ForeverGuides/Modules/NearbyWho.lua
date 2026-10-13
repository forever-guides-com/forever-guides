-- The "Update" button of a contact (tab Social): one who query for exactly that name, on click only,
-- one query per NearbyLogic.WHO_EVERY seconds for all contacts together, never in combat. The answer
-- refreshes level, class and guild and notes "confirmed online" with the zone of the player (the time
-- and place of the last sighting stay: a who answer is no sighting). Only the row of the asked name is
-- taken, the answer is read at most for the 50 rows the game sends. The result window of the game
-- stays closed when the client allows it (SetWhoToUi), else the game decides where the answer shows.
-- Every game call is protected, a missing function means "not available".
local _, ns = ...
local NL, SP, L = ns.NearbyLogic, ns.SeenPlayers, ns.L

local W = {}
ns.NearbyWho = W

ns.AddLocale("enUS", {
  ["nearby.who.found"] = "Updated: %s",
  ["nearby.who.none"] = "%s is not online or not found.",
  ["nearby.who.sent"] = "Asking for %s ...",
  ["nearby.who.why.no-api"] = "Not available in this client.",
  ["nearby.who.why.combat"] = "Not possible in combat.",
  ["nearby.who.why.wait"] = "Please wait %d s.",
  ["nearby.who.why.pending"] = "The last query is still running.",
  ["nearby.who.why.error"] = "The game refused the query.",
  ["nearby.who.tip"] = "Asks the game who this player is and updates level, class, guild and zone. Once per 10 seconds.",
  ["nearby.who.update"] = "Update",
  ["nearby.who.online"] = "Online confirmed: %s in %s",
  ["nearby.who.onlineNoZone"] = "Online confirmed: %s",
})
ns.AddLocale("deDE", {
  ["nearby.who.found"] = "Aktualisiert: %s",
  ["nearby.who.none"] = "%s ist nicht online oder nicht gefunden.",
  ["nearby.who.sent"] = "Frage nach %s ...",
  ["nearby.who.why.no-api"] = "In diesem Client nicht verfügbar.",
  ["nearby.who.why.combat"] = "Im Kampf nicht möglich.",
  ["nearby.who.why.wait"] = "Bitte %d s warten.",
  ["nearby.who.why.pending"] = "Die letzte Abfrage läuft noch.",
  ["nearby.who.why.error"] = "Das Spiel hat die Abfrage abgelehnt.",
  ["nearby.who.tip"] = "Fragt das Spiel, wer dieser Spieler ist, und aktualisiert Stufe, Klasse, Gilde und Zone. Einmal je 10 Sekunden.",
  ["nearby.who.update"] = "Aktualisieren",
  ["nearby.who.online"] = "Online bestätigt: %s in %s",
  ["nearby.who.onlineNoZone"] = "Online bestätigt: %s",
})

local lastAt
local pending -- { name, at } while an answer is awaited

local function g(name)
  return rawget(_G, name)
end

local function clock()
  local now = g("GetTime")
  if type(now) ~= "function" then
    return 0
  end
  local ok, value = pcall(now)
  return ok and tonumber(value) or 0
end

local function friendList()
  local list = g("C_FriendList")
  return type(list) == "table" and list or nil
end

-- The function that sends a query, the one of C_FriendList first.
local function sender()
  local list = friendList()
  if list and type(list.SendWho) == "function" then
    return list.SendWho
  end
  local fn = g("SendWho")
  return type(fn) == "function" and fn or nil
end

function W.Available()
  return sender() ~= nil
end

-- Why no query can go out now: "no-api", "combat", "pending" or "wait" and the seconds; nil when it can.
function W.Block()
  if not W.Available() then
    return "no-api"
  end
  if ns.AutoGuard.Blocked() then
    return "combat"
  end
  local now = clock()
  if pending and now - pending.at < NL.WHO_TIMEOUT then
    return "pending"
  end
  local wait = NL.Wait(lastAt, now, NL.WHO_EVERY)
  if wait > 0 then
    return "wait", wait
  end
  return nil
end

-- Text of a block reason for the tooltip.
function W.WhyText(reason, wait)
  local key = "nearby.who.why." .. tostring(reason)
  return reason == "wait" and string.format(L[key], wait or 0) or L[key]
end

-- Silences the result window where the client has the switch.
local function quiet()
  local list = friendList()
  if list and type(list.SetWhoToUi) == "function" then
    pcall(list.SetWhoToUi, false)
  elseif type(g("SetWhoToUI")) == "function" then
    pcall(g("SetWhoToUI"), 0)
  end
end

-- Asks for one contact (an entry of the seen list). Returns true, or false and the reason.
function W.Request(e)
  local reason, wait = W.Block()
  if reason then
    return false, reason, wait
  end
  local query = type(e) == "table" and NL.WhoQuery(e.name)
  if not query then
    return false, "error"
  end
  quiet()
  local now = clock()
  local ok = pcall(sender(), query)
  if not ok then
    return false, "error"
  end
  lastAt, pending = now, { name = e.name, at = now }
  ns.Notify(string.format(L["nearby.who.sent"], e.name), "info")
  -- The buttons were dimmed for the wait; this redraws the page when the wait is over.
  local timer = g("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    pcall(timer.After, NL.WHO_EVERY + 0.2, function()
      ns.Emit("FG_SEEN_UPDATE")
    end)
  end
  return true
end

-- The rows of the answer as NearbyLogic.WhoRow shapes them.
local function readRows()
  local rows = {}
  local list = friendList()
  local count = 0
  if list and type(list.GetNumWhoResults) == "function" then
    local ok, n = pcall(list.GetNumWhoResults)
    count = ok and tonumber(n) or 0
  end
  for i = 1, math.min(count, NL.MAX_WHO_ROWS) do
    local ok, info = pcall(list.GetWhoInfo, i)
    local row = ok and NL.WhoRow(info)
    if row then
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- One-line summary of what an answer changed: "Name, level 60 Mage".
local function summary(e)
  local parts = { e.name }
  if e.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], e.level)
  end
  if e.class ~= "" then
    parts[#parts + 1] = ns.RefLogic.className(e.class)
  end
  return table.concat(parts, ", ")
end

-- WHO_LIST_UPDATE: takes the answer only while one of our queries waits for it, and only its row.
function W.OnAnswer()
  local asked = pending
  if not asked then
    return
  end
  pending = nil
  if clock() - asked.at >= NL.WHO_TIMEOUT then
    return
  end
  local row = NL.WhoMatch(readRows(), asked.name)
  if not row then
    ns.Notify(string.format(L["nearby.who.none"], asked.name), "info")
    return
  end
  local e = SP.FindName(asked.name)
  if not e then
    return
  end
  NL.ApplyWho(e, row, ns.U.now())
  ns.Notify(string.format(L["nearby.who.found"], summary(e)), "success")
  ns.Emit("FG_SEEN_UPDATE")
end

function W.Reset()
  lastAt, pending = nil, nil
end

ns.On("WHO_LIST_UPDATE", function()
  W.OnAnswer()
end)
