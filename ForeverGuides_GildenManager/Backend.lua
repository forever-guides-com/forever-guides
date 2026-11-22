-- The one place of the add-on that changes the guild. Three ways, chosen per action:
--   direct  calls the game function from add-on code (only when the player chose it by name)
--   macro   arms a secure button with slash commands, never in combat: one command per click (Arm) or
--           several commands per click (ArmBatch, at most MACRO_MAX characters)
--   copy    shows the command (or the note text) in the copy window, changes nothing
-- Choice "auto" takes macro when the secure button template works and we are out of combat, else copy.
-- On a client that blocks guild changes from add-on code (Locked, WoW Forever) the add-on never calls a
-- guild function: "direct" becomes copy, and the macro way only carries the commands the player could
-- type (promote, demote, remove), never an invite and never a note. A measured block of the secure
-- button (Caps "macro" = false) sends the player back to the copy window.
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
-- The command the player types on a locked client; /gremove is the short form of /guildremove.
B.TYPED = { promote = "/gpromote", demote = "/gdemote", remove = "/gremove", invite = "/ginvite" }
-- Reason code (locale key "gm.why.<code>") per action that has no typed command at all.
B.NO_COMMAND = { editNote = "clientNote", editOfficerNote = "clientNote", setRank = "clientRank" }
-- First line of every macro: the secure code itself refuses to run in combat.
local GUARD_LINE = "/stopmacro [combat]"
-- Longest macro text the game takes; a batch stops before a line that would not fit.
B.MACRO_MAX = 255
-- The actions whose slash command a secure button may carry on a locked client.
local MACRO_LOCKED = { promote = true, demote = true, remove = true }
local POOL_MAX = 4

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

-- True on a client that blocks guild changes from add-on code, see Caps.Locked.
function B.Locked()
  return gm.Caps.Locked()
end

-- Why the action cannot be offered on this client, nil when it can: a locked client only has the typed
-- commands of B.TYPED. A note or a rank set directly has no command; a jump over several ranks is the
-- same promote or demote command once per rank, so the secure button (choice given) can carry it.
function B.Unavailable(action, choice)
  if not B.Locked() or B.TYPED[action] then
    return nil
  end
  -- Combat is no reason here: the run waits for it, it never drops the step.
  if action == "setRank" and choice ~= nil and B.Resolve(choice, action, { combat = false }) == "macro" then
    return nil
  end
  return B.NO_COMMAND[action] or "noApi"
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
  if B.Locked() then
    local typed, who = B.TYPED[action], safeName(step.name)
    return typed and who and typed .. " " .. who or nil
  end
  if action == "editNote" or action == "editOfficerNote" then
    return type(step.value) == "string" and step.value ~= "" and step.value or nil
  end
  local slash, name = B.SLASH[action], safeName(step.name)
  if slash and name then
    return slash .. " " .. name
  end
end

-- The slash command a secure button runs for the action, nil when it has none here. A jump over
-- several ranks (setRank) is carried by the promote or demote command, see commandOf.
local function macroSlash(action)
  if action == "setRank" then
    action = "promote"
  end
  if B.Locked() then
    return MACRO_LOCKED[action] and B.TYPED[action] or nil
  end
  return B.SLASH[action]
end

-- True when a secure button can carry the action on this client.
function B.HasMacro(action)
  return macroSlash(action) ~= nil
end

-- The command lines of a step ({ action, name, fromRank, toRank }): one line, or one per rank for a jump
-- over several ranks. nil without command, with an unsafe name or without both ranks.
local function commandLines(action, step)
  step = type(step) == "table" and step or {}
  local name, count = safeName(step.name), 1
  if action == "setRank" then
    local from, to = step.fromRank, step.toRank
    if type(from) ~= "number" or type(to) ~= "number" or from == to then
      return nil
    end
    action, count = to < from and "promote" or "demote", math.abs(from - to)
  end
  local slash = macroSlash(action)
  if not (slash and name and count <= 9) then
    return nil
  end
  local lines = {}
  for i = 1, count do
    lines[i] = slash .. " " .. name
  end
  return lines
end

-- Macro text of an action, nil for an action without slash command, an unsafe name or a text the game
-- would cut.
function B.MacroText(action, step)
  local lines = commandLines(action, step)
  local text = lines and GUARD_LINE .. "\n" .. table.concat(lines, "\n")
  return text and #text <= B.MACRO_MAX and text or nil
end

-- Macro text for several steps ({ action, name, fromRank, toRank }), in order, as many as `limit`
-- (default all) and B.MACRO_MAX allow. A step goes in with all its lines or not at all. Stops at the
-- first step that has no command or an unsafe name, so the order of a run never changes. Answers the
-- text and the number of steps in it (0: nothing fits, text nil).
function B.BatchText(steps, limit)
  local text, n = GUARD_LINE, 0
  for _, step in ipairs(type(steps) == "table" and steps or {}) do
    local lines = type(step) == "table" and commandLines(step.action, step)
    local add = lines and "\n" .. table.concat(lines, "\n")
    if not add or n >= (limit or math.huge) or #text + #add > B.MACRO_MAX then
      break
    end
    text, n = text .. add, n + 1
  end
  return n > 0 and text or nil, n
end

-- Direct way ------------------------------------------------------------------------------------------

-- "sent" when the call went through, false and a reason when the function is missing or raised.
local function call(fn, ...)
  if not fn or B.Locked() then
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

-- A protected frame that is anchored to a window makes that window protected in combat (Hide, Show and
-- SetPoint refused). So the button hangs on UIParent only, hidden and without anchors while it is unused.
local function detach(button)
  button:Hide()
  button:ClearAllPoints()
  button:SetParent(UIParent)
end

local function clear(slot)
  slot.button:SetAttribute("type", nil)
  slot.button:SetAttribute("macrotext", nil)
  slot.button.fgDone = nil
  detach(slot.button)
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

-- Arms a pool button with the commands of several steps ({ action, name }, see BatchText). One click
-- runs them all. Answers the button and the number of steps it carries, or false and a reason code.
function B.ArmBatch(steps, limit, onClick)
  if inCombat() then
    return false, "combat"
  end
  local text, n = B.BatchText(steps, limit)
  local slot = text and take()
  if not slot then
    return false, "noApi"
  end
  slot.free = false
  slot.button:SetAttribute("type", "macro")
  slot.button:SetAttribute("macrotext", text)
  slot.button.fgDone = onClick
  return slot.button, n
end

-- Lays an armed button over `anchor` without anchoring it to it: the button stays a child of UIParent
-- and takes the screen rectangle of the anchor, so no window becomes protected. `shown` (default the
-- anchor) says whether the overlay is visible. Only out of combat; call again after the window moved.
function B.Place(button, anchor, shown)
  local slot = type(button) == "table" and button.fgSlot
  if not slot or slot.free or type(anchor) ~= "table" or inCombat() then
    return false
  end
  local ok = pcall(function()
    local ratio = (anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not (left and bottom) then
      error("anchor has no rectangle")
    end
    button:SetParent(UIParent)
    button:ClearAllPoints()
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetSize(anchor:GetWidth() * ratio, anchor:GetHeight() * ratio)
    button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio)
    button:SetShown((shown or anchor):IsVisible() == true)
  end)
  return ok
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
  if choice == "copy" then
    return "copy"
  elseif choice == "direct" then
    return B.Locked() and "copy" or "direct"
  end
  env = env or {}
  local combat, secure = env.combat, env.secure
  if combat == nil then
    combat = inCombat()
  end
  if secure == nil then
    secure = B.SecureAvailable()
  end
  if macroSlash(action) and secure and not combat and gm.Caps.Get("macro") ~= false then
    return "macro"
  end
  return "copy"
end

-- True when the way of the choice can take the action now; false and "noApi" when the client lacks the
-- call of the direct way. Second result of the true case: the way (see Resolve).
function B.Available(choice, action, env)
  local kind = B.Resolve(choice, action, env)
  local why = B.Unavailable(action)
  if why then
    return false, why
  end
  if kind == "direct" then
    local cap = CAP_OF[action]
    if not DIRECT[action] or (cap and gm.Caps.Get(cap) == false) then
      return false, "noApi"
    end
  end
  return true, kind
end

-- Shows the command (or the note text) of an action in the copy window. Answers the text, nil when there
-- is nothing to show. Changes nothing in the game.
function B.ShowCopy(action, step)
  local text = B.Command(action, step)
  if not text then
    return nil
  end
  local copy = FG.Dialogs and FG.Dialogs.Copy
  if type(copy) == "function" then
    pcall(copy, "gm.copy.title", text, B.Locked() and "gm.copy.hintTyped" or "gm.copy.hint")
  end
  return text
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
  local unavailable = B.Unavailable(action, opts.choice)
  if unavailable then
    return false, unavailable, kind
  end
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
  local text = B.ShowCopy(action, step)
  if not text then
    return false, "noApi", kind
  end
  return "copy", text, kind
end
