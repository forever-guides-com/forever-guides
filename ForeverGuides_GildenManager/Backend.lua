-- The one place of the add-on that changes the guild. Three ways, chosen per action:
--   direct  calls the game function from add-on code (only when the player chose it by name)
--   macro   arms a secure button with a slash command, one click per member, never in combat
--   copy    shows the command (or the note text) in the copy window, changes nothing
-- Choice "auto" takes macro when the secure button template works and we are out of combat, else copy.
-- Every game function is looked up at call time, nil safe and inside pcall: C_GuildInfo first, the older
-- global name second. A static test keeps all other files free of these calls.
local _, gm = ...
if not gm.ext then
  return
end
local FG = gm.FG
local PN = FG.PlayerName

local B = {}
gm.Backend = B

-- Values of the setting actionBackend; the first is the default.
B.CHOICES = { "auto", "macro", "copy", "direct" }
-- Slash command per action. Notes and rank orders have none.
B.SLASH = { promote = "/gpromote", demote = "/gdemote", remove = "/guninvite", invite = "/ginvite" }
-- First line of every macro: the secure code itself refuses to run in combat.
local GUARD_LINE = "/stopmacro [combat]"
local POOL_MAX = 4

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

-- The game function: C_GuildInfo.<new> first, the global <old> second. nil when the client has neither.
local function lookup(new, old)
  local info = rawget(_G, "C_GuildInfo")
  local fn = new and type(info) == "table" and info[new]
  if type(fn) == "function" then
    return fn
  end
  fn = old and rawget(_G, old)
  if type(fn) == "function" then
    return fn
  end
end

-- A name that is safe inside a slash command: one line, no escape sequences.
local function safeName(name)
  return type(name) == "string" and name ~= "" and #name <= 80 and not name:find("[%c|]") and name or nil
end

-- The command (or the text to paste) of an action for the copy window; nil when there is nothing to show.
function B.Command(action, step)
  step = type(step) == "table" and step or {}
  if action == "editNote" or action == "editOfficerNote" then
    return type(step.value) == "string" and step.value ~= "" and step.value or nil
  end
  local slash, name = B.SLASH[action], safeName(step.name)
  if slash and name then
    return slash .. " " .. name
  end
end

-- Macro text of an action, nil for an action without slash command or an unsafe name.
function B.MacroText(action, step)
  local slash, name = B.SLASH[action], safeName(type(step) == "table" and step.name)
  if slash and name then
    return GUARD_LINE .. "\n" .. slash .. " " .. name
  end
end

-- Direct way ------------------------------------------------------------------------------------------

-- "sent" when the call went through, false and a reason when the function is missing or raised.
local function call(fn, ...)
  if not fn then
    return false, "noApi"
  end
  if pcall(fn, ...) then
    return "sent"
  end
  return false, "failed"
end

-- Roster row at `index` is the member of the step (the old note functions go by index).
local function rowIs(index, name)
  local fn = rawget(_G, "GetGuildRosterInfo")
  if type(fn) ~= "function" or type(index) ~= "number" then
    return false
  end
  local ok, found = pcall(fn, index)
  return ok and type(found) == "string" and PN.Equal(found, name)
end

-- Rank change by order: only with a measured capability (rankOrder = true) and a GUID, asks the game
-- first whether the assignment is allowed. nil when this way does not apply.
local function byOrder(step)
  local fn = gm.Caps.Get("rankOrder") == true and lookup("SetGuildRankOrder")
  local order = gm.RunLogic.RankOrderOf(step.toRank)
  if not (fn and order and type(step.guid) == "string") then
    return nil
  end
  local allowed = lookup("IsGuildRankAssignmentAllowed")
  if allowed then
    local ok, yes = pcall(allowed, step.guid, order)
    if ok and yes == false then
      return false, "noRight"
    end
  end
  return call(fn, step.guid, order)
end

local function rank(new, old)
  return function(step)
    local status, why = byOrder(step)
    if status ~= nil then
      return status, why
    end
    return call(lookup(new, old), step.name)
  end
end

local function note(public)
  return function(step)
    local info = rawget(_G, "C_GuildInfo")
    local new = type(info) == "table" and type(info.SetNote) == "function" and info.SetNote
    if new then
      if type(step.guid) ~= "string" then
        return false, "noGuid"
      end
      return call(new, step.guid, step.value, public)
    end
    local old = lookup(nil, public and "GuildRosterSetPublicNote" or "GuildRosterSetOfficerNote")
    if not old then
      return false, "noApi"
    end
    if not rowIs(step.index, step.name) then
      return false, "noGuid"
    end
    return call(old, step.index, step.value)
  end
end

local DIRECT = {
  promote = rank("Promote", "GuildPromote"),
  demote = rank("Demote", "GuildDemote"),
  remove = function(step)
    local fn = lookup("RemoveFromGuild", "GuildUninvite")
    local info = rawget(_G, "C_GuildInfo")
    -- The new function takes the GUID, the old one the name; a member without GUID goes by name.
    local byGuid = type(info) == "table" and info.RemoveFromGuild == fn and type(step.guid) == "string"
    return call(fn, byGuid and step.guid or step.name)
  end,
  invite = function(step)
    return call(lookup("Invite", "GuildInvite"), step.name)
  end,
  -- A jump over several ranks only goes by order and only with the measured capability.
  setRank = function(step)
    local status, why = byOrder(step)
    if status == nil then
      return false, "noApi"
    end
    return status, why
  end,
  editNote = note(true),
  editOfficerNote = note(false),
}

-- The capability that can forbid an action in the direct way.
local CAP_OF = {
  promote = "direct",
  demote = "direct",
  invite = "direct",
  remove = "remove",
  setRank = "rankOrder",
  editNote = "setNote",
  editOfficerNote = "setNote",
}

-- Macro way -------------------------------------------------------------------------------------------

local pool, secureFailed = {}, false
-- Slots whose attributes could not be cleared in combat; cleared as soon as the combat ends.
local stale = {}

local function make()
  local ok, b = pcall(function()
    return CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
  end)
  if not (ok and type(b) == "table") then
    secureFailed = true
    return nil
  end
  b:RegisterForClicks("AnyUp", "AnyDown")
  -- Our own code runs after the secure click; it never changes what the click does.
  b:HookScript("PostClick", function(self)
    -- The macro stops itself in combat: nothing was sent, the button stays armed for another click.
    if inCombat() then
      return
    end
    local done = self.fgDone
    self.fgDone = nil
    if done then
      done(self)
    end
  end)
  local slot = { button = b, free = true }
  b.fgSlot = slot
  pool[#pool + 1] = slot
  return slot
end

local function take()
  for _, slot in ipairs(pool) do
    if slot.free then
      return slot
    end
  end
  if not secureFailed and #pool < POOL_MAX then
    return make()
  end
end

-- True when the secure button template works here. The first call creates the first pool button.
function B.SecureAvailable()
  if #pool > 0 then
    return true
  end
  return not secureFailed and make() ~= nil
end

-- Number of buttons the pool made (the pool is reused and never grows past POOL_MAX).
function B.PoolSize()
  return #pool
end

local function clear(slot)
  slot.button:SetAttribute("type", nil)
  slot.button:SetAttribute("macrotext", nil)
  slot.button.fgDone = nil
  stale[slot] = nil
  slot.free = true
end

-- Arms a pool button with the command of the action. onClick(button) runs after the click. Answers the
-- button, or false and a reason code. Attributes only change out of combat.
function B.Arm(action, step, onClick)
  if inCombat() then
    return false, "combat"
  end
  local text = B.MacroText(action, step)
  local slot = text and take()
  if not slot then
    return false, "noApi"
  end
  slot.free = false
  slot.button:SetAttribute("type", "macro")
  slot.button:SetAttribute("macrotext", text)
  slot.button.fgDone = onClick
  return slot.button
end

-- Gives the button back to the pool. In combat the attributes stay until the combat ends.
function B.Disarm(button)
  local slot = type(button) == "table" and button.fgSlot
  if not slot or slot.free then
    return false
  end
  if inCombat() then
    stale[slot] = true
    return false
  end
  clear(slot)
  return true
end

FG.On("PLAYER_REGEN_ENABLED", function()
  for slot in pairs(stale) do
    clear(slot)
  end
end)

-- Entry ------------------------------------------------------------------------------------------------

-- Which way an action takes. env = { combat, secure } (read from the game when missing). Only the
-- choice "direct" ever gives "direct"; a macro that cannot run gives "copy".
function B.Resolve(choice, action, env)
  if choice == "direct" then
    return "direct"
  elseif choice == "copy" then
    return "copy"
  end
  env = env or {}
  local combat, secure = env.combat, env.secure
  if combat == nil then
    combat = inCombat()
  end
  if secure == nil then
    secure = B.SecureAvailable()
  end
  if B.SLASH[action] and secure and not combat and gm.Caps.Get("macro") ~= false then
    return "macro"
  end
  return "copy"
end

-- True when the way of the choice can take the action now; false and "noApi" when the client lacks the
-- call of the direct way. Second result of the true case: the way (see Resolve).
function B.Available(choice, action, env)
  local kind = B.Resolve(choice, action, env)
  if kind == "direct" then
    local cap = CAP_OF[action]
    if not DIRECT[action] or (cap and gm.Caps.Get(cap) == false) then
      return false, "noApi"
    end
  end
  return true, kind
end

-- Runs an action the chosen way. step = { name, guid, index, toRank, value }. opts = { choice, env,
-- onClick }. Answers (status, info, kind):
--   "sent", nil, "direct"      the game function was called
--   "armed", button, "macro"   the button waits for one click
--   "copy", text, "copy"       the copy window shows the command
--   false, reason, kind        nothing happened (reason: a code of ActionsLogic.REASONS)
function B.Do(action, step, opts)
  opts = opts or {}
  step = type(step) == "table" and step or {}
  local kind = B.Resolve(opts.choice, action, opts.env)
  if inCombat() then
    return false, "combat", kind
  end
  if kind == "direct" then
    local fn, cap = DIRECT[action], CAP_OF[action]
    if not fn or (cap and gm.Caps.Get(cap) == false) then
      return false, "noApi", kind
    end
    local status, why = fn(step)
    return status, why, kind
  elseif kind == "macro" then
    local button, why = B.Arm(action, step, opts.onClick)
    if not button then
      return false, why, kind
    end
    return "armed", button, kind
  end
  local text = B.Command(action, step)
  if not text then
    return false, "noApi", kind
  end
  local copy = FG.Dialogs and FG.Dialogs.Copy
  if type(copy) == "function" then
    pcall(copy, "gm.copy.title", text, "gm.copy.hint")
  end
  return "copy", text, kind
end
