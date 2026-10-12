-- Resetting instances with a group message. The game's own reset (portrait menu "Reset all instances")
-- and our button both end in ResetInstances(), which is hooked once with hooksecurefunc (no protected
-- call, no taint). The hook opens a short window (InstanceResetLogic.WINDOW) in which the system messages
-- of the game (INSTANCE_RESET_SUCCESS and the failure formats) are collected. After the window ONE line goes
-- to the group chat, only when the reset started here (a reset by another leader sends the same system
-- messages; no window is open then) and the player is in a group. Without a group, with the switch off
-- or with the chat restricted the line stays local. Afterwards FG_INSTANCES_RESET is emitted with the
-- instances and the boss progress of the resolved ones is dropped.
local _, ns = ...
local Guard, L, RL = ns.AutoGuard, ns.L, ns.InstanceResetLogic
local W, Store = ns.W, ns.Store

local R = {}
ns.InstanceReset = R

ns.AddLocale("enUS", {
  ["act.reset"] = "Reset",
  ["ireset.title"] = "Reset instances",
  ["ireset.tip"] = "Resets all instances. Only outside of instances, in a group only as the group leader.",
  ["ireset.head"] = "Instances reset: %s.",
  ["ireset.failedHead"] = "Not reset: %s.",
  ["ireset.more"] = "and %d more",
  ["ireset.count"] = "%d instances",
  ["ireset.none"] = "No instance was reset.",
  ["ireset.error"] = "The reset could not be started.",
  ["ireset.blocked.combat"] = "Not in combat.",
  ["ireset.blocked.instance"] = "Not inside an instance.",
  ["ireset.blocked.leader"] = "Only the group leader can reset.",
  ["ireset.blocked.api"] = "This client has no reset function.",
  ["ireset.set.heading"] = "Instances",
  ["ireset.set.announce"] = "Report resets in group chat",
  ["ireset.set.announceTip"] = "After you reset instances, one line with their names goes to the party, raid or instance chat. Only in groups, never alone.",
})
ns.AddLocale("deDE", {
  ["act.reset"] = "Zurücksetzen",
  ["ireset.title"] = "Instanzen zurücksetzen",
  ["ireset.tip"] = "Setzt alle Instanzen zurück. Nur außerhalb von Instanzen, in einer Gruppe nur als Gruppenleiter.",
  ["ireset.head"] = "Instanzen zurückgesetzt: %s.",
  ["ireset.failedHead"] = "Nicht zurückgesetzt: %s.",
  ["ireset.more"] = "und %d weitere",
  ["ireset.count"] = "%d Instanzen",
  ["ireset.none"] = "Es wurde keine Instanz zurückgesetzt.",
  ["ireset.error"] = "Das Zurücksetzen ließ sich nicht starten.",
  ["ireset.blocked.combat"] = "Nicht im Kampf.",
  ["ireset.blocked.instance"] = "Nicht innerhalb einer Instanz.",
  ["ireset.blocked.leader"] = "Nur der Gruppenleiter kann zurücksetzen.",
  ["ireset.blocked.api"] = "Dieser Client hat keine Funktion zum Zurücksetzen.",
  ["ireset.set.heading"] = "Instanzen",
  ["ireset.set.announce"] = "Zurücksetzen im Gruppenchat melden",
  ["ireset.set.announceTip"] = "Nach dem Zurücksetzen geht eine Zeile mit den Namen in den Gruppen-, Schlachtzugs- oder Instanzchat. Nur in Gruppen, nie allein.",
})

R.EVENT = "FG_INSTANCES_RESET"

-- Global names of the game's formats. The failure names differ between clients, so every one that
-- exists counts.
local DONE_FORMATS = { "INSTANCE_RESET_SUCCESS" }
local FAILED_FORMATS = {
  "INSTANCE_RESET_FAILED",
  "INSTANCE_RESET_FAILED_OFFLINE",
  "INSTANCE_RESET_FAILED_ZONING",
  "INSTANCE_RESET_FAILED_ZONE",
}

local function try(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

-- Patterns of the formats the client has, built per window so a changed language is picked up.
local function patterns()
  local list = {}
  for kind, names in pairs({ done = DONE_FORMATS, failed = FAILED_FORMATS }) do
    for _, name in ipairs(names) do
      local pattern = RL.Pattern(rawget(_G, name))
      if pattern then
        list[#list + 1] = { kind = kind, pattern = pattern }
      end
    end
  end
  return list
end

-- Only an explicit false switches the report off.
function R.Announce()
  return not (ns.db and ns.db.settings and ns.db.settings.instanceResetAnnounce == false)
end

-- Collecting window ------------------------------------------------------------------------------

local session

-- The system messages of the game (a secret or unreadable text is ignored).
function R.OnSystem(msg)
  local s = session
  if not s then
    return false
  end
  local text = Guard.Safe(msg)
  if type(text) ~= "string" then
    return false
  end
  local kind, name = RL.Parse(text, s.patterns)
  if not kind then
    return false
  end
  return RL.Add(s.batch, kind, name)
end

ns.On("CHAT_MSG_SYSTEM", function(_, msg)
  R.OnSystem(msg)
end)

-- Group chat channel for the current group, nil without one (the helper of PeerComm).
local function channel()
  return ns.PeerComm and ns.PeerComm.GroupChannel() or nil
end

-- Instances by name, resolved against Data.Instances (English or German name). Entries without a
-- match keep instanceId nil.
function R.Resolve(names)
  local RLL, out = ns.RaidLockLogic, {}
  for _, name in ipairs(names) do
    local inst = RLL.Find({ nameKey = RLL.NameKey(name) })
    out[#out + 1] = { name = name, instanceId = inst and type(inst.id) == "number" and inst.id or nil }
  end
  return out
end

local function say(text)
  ns.Notify.chat(text)
end

-- One line to the group. True when the game accepted the call.
local function post(text)
  local target = channel()
  if not target or ns.AddonRestricted("Chat") then
    return false
  end
  local send = rawget(_G, "SendChatMessage")
  if type(send) ~= "function" then
    return false
  end
  return (pcall(send, text, target))
end

local function announce(names)
  local line = RL.Line(names, L["ireset.head"], L["ireset.more"], L["ireset.count"])
  if R.Announce() and post(line) then
    return
  end
  say(line)
end

local function finish(s)
  if session ~= s then
    return
  end
  session = nil
  local done, failed = s.batch.done, s.batch.failed
  if #failed > 0 then
    say(RL.Line(failed, L["ireset.failedHead"], L["ireset.more"], L["ireset.count"], math.huge))
  end
  if #done == 0 then
    if #failed == 0 and s.manual then
      say(L["ireset.none"])
    end
    return
  end
  local list = R.Resolve(done)
  local progress = ns.BossProgress
  if progress and type(progress.Reset) == "function" then
    for _, entry in ipairs(list) do
      if entry.instanceId then
        pcall(progress.Reset, entry.instanceId)
      end
    end
  end
  ns.Emit(R.EVENT, list)
  ns.Safe("instreset-announce", announce, done)
end

-- Opens the window after a reset call. False without a timer (the messages arrive later, so
-- nothing could be collected) or while a window is already open.
function R.Begin()
  local manual = R.manualNext == true
  R.manualNext = nil
  local timer = rawget(_G, "C_Timer")
  if session or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return false
  end
  local s = { batch = RL.NewBatch(), patterns = patterns(), manual = manual }
  session = s
  local run = ns.Wrap("instreset-finish", function()
    finish(s)
  end)
  if not pcall(timer.After, RL.WINDOW, run) then
    session = nil
    return false
  end
  return true
end

-- Hook -------------------------------------------------------------------------------------------

function R.Install()
  if R.hooked then
    return true
  end
  local hook = rawget(_G, "hooksecurefunc")
  if type(hook) ~= "function" or type(rawget(_G, "ResetInstances")) ~= "function" then
    return false
  end
  R.hooked = pcall(hook, "ResetInstances", ns.Wrap("instreset-hook", R.Begin))
  return R.hooked
end

R.Install()
ns.On("PLAYER_LOGIN", R.Install)

-- Button -----------------------------------------------------------------------------------------

-- true, or false and the locale key of the reason.
function R.CanReset()
  if type(rawget(_G, "ResetInstances")) ~= "function" then
    return false, "ireset.blocked.api"
  end
  if Guard.Blocked() then
    return false, "ireset.blocked.combat"
  end
  if try("IsInInstance") == true then
    return false, "ireset.blocked.instance"
  end
  if try("IsInGroup") == true and try("UnitIsGroupLeader", "player") ~= true then
    return false, "ireset.blocked.leader"
  end
  return true
end

-- Starts the game's reset. The hook opens the window; without a hook the window opens here.
function R.Reset()
  local ok, reason = R.CanReset()
  if not ok then
    say(L[reason])
    return false
  end
  R.manualNext = true
  local called = pcall(rawget(_G, "ResetInstances"))
  if not called then
    R.manualNext = nil
    say(L["ireset.error"])
    return false
  end
  if not R.hooked then
    R.Begin()
  end
  R.manualNext = nil
  return true
end

local BUTTON_H = 26
local REFRESH_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "PARTY_LEADER_CHANGED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_REGEN_DISABLED",
}

-- The button of the page Instances: icon and short label (W.Action). When a reset is not possible it
-- stays focusable but dimmed, the click and the tooltip name the reason (like the map button).
function R.Button(parent)
  local b = W.Action(parent, {
    label = "act.reset",
    icon = "reset",
    height = BUTTON_H,
    onClick = R.Reset,
    wrap = "instreset-click",
    manual = true,
  })
  b.fgNameKey = "ireset.title"
  local function show()
    local _, reason = R.CanReset()
    local text = L["ireset.tip"]
    if reason then
      text = text .. "\n" .. L[reason]
    end
    ns.ShowTooltip(b, L["ireset.title"], text)
  end
  function b:Refresh()
    local ok = R.CanReset()
    self.fgBlocked = not ok
    self:SetAlpha(ok and 1 or 0.45)
  end
  b:HookScript("OnEnter", show)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = show, ns.HideTooltip
  for _, event in ipairs(REFRESH_EVENTS) do
    ns.On(event, function()
      b:Refresh()
    end)
  end
  b:Refresh()
  return b
end

-- Settings ---------------------------------------------------------------------------------------

function R.AddSettings(view)
  ns.AddHeading(view, "ireset.set.heading")
  view.stack:Add(
    W.Toggle(view.content, {
      key = "ireset.set.announce",
      get = R.Announce,
      set = function(v)
        Store.set("settings.instanceResetAnnounce", v == true)
      end,
      tooltip = "ireset.set.announce",
      tooltipText = "ireset.set.announceTip",
    }),
    { height = 24, gap = 6 }
  )
end

ns.SettingsPage.Add(R.AddSettings, "social")
