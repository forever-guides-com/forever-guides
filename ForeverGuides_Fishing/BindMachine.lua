-- The state machine of the key bindings. The helper wants one of three modes:
--   off   no override binding, the key does what the game says,
--   cast  the key clicks the secure cast button (throws the line),
--   reel  the key interacts with the soft target, which is the bobber while the line is out.
-- Override bindings can only change outside of combat, and the secure frame that owns them drops them
-- when a fight starts. So a wish that arrives in combat is kept and carried out when combat ends.
-- Pure: the game is reached through env.inCombat and env.apply.
local _, fish = ...
if not fish.FG then
  return
end

local M = {}
fish.BindMachine = M

M.MODES = { "off", "cast", "reel" }

-- The mode the situation asks for. input: enabled (the feature is on), keys (number of bound keys),
-- allowed (fishing is possible now), channeling (the line is out).
function M.Desired(input)
  if input.enabled ~= true or (input.keys or 0) < 1 then
    return "off"
  end
  if input.channeling == true then
    return "reel"
  end
  return input.allowed == true and "cast" or "off"
end

local Machine = {}
Machine.__index = Machine

-- env.inCombat() -> boolean
-- env.apply(mode) -> true, or false and an error text. It writes the bindings of that mode.
function M.New(env)
  assert(type(env) == "table", "machine needs an env")
  return setmetatable({ env = env, applied = "off", wanted = "off", deferred = false }, Machine)
end

-- Asks for a mode. Returns "same" (already in place), "applied", "deferred" (combat, done later),
-- "disabled" or "failed" with the error text.
function Machine:Want(mode)
  self.wanted = mode
  if self.disabled then
    return "disabled"
  end
  if mode == self.applied then
    self.deferred = false
    return "same"
  end
  if self.env.inCombat() then
    self.deferred = true
    return "deferred"
  end
  local ok, err = self.env.apply(mode)
  if not ok then
    -- What is in place is unknown now: the next wish writes again.
    self.applied, self.deferred, self.lastError = nil, false, err
    return "failed", err
  end
  self.applied, self.deferred, self.lastError = mode, false, nil
  return "applied"
end

-- Combat ended: carries out the wish that waited.
function Machine:Flush()
  if self.deferred then
    return self:Want(self.wanted)
  end
  return "same"
end

-- A fight started: the owner frame dropped its bindings, a wish for something else waits.
function Machine:CombatStarted()
  self.applied = "off"
  self.deferred = self.wanted ~= "off" and not self.disabled
end

-- What is bound is not known any more (the owner was cleared by hand): the next wish writes again.
function Machine:Forget()
  self.applied, self.deferred = nil, false
end

-- Stops the machine for good (until Enable): used when the game blocked a call.
function Machine:Disable(reason)
  self.disabled = reason or true
  self.deferred = false
end

function Machine:Enable()
  self.disabled = nil
end

function Machine:State()
  return {
    applied = self.applied,
    wanted = self.wanted,
    deferred = self.deferred,
    disabled = self.disabled,
    lastError = self.lastError,
  }
end
