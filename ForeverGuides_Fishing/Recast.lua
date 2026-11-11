-- The state machine of the throw after reeling in. The helper reels in first (the game only lets a click throw
-- the line, and a throw while the line is out would cut the channel short and lose the catch), remembers the
-- wish to throw again, and offers the throw once the channel has ended and the loot window is closed.
--   ready    nothing to do,
--   out      the line is out,
--   reeled   a throw again is wanted, waiting for the end of the channel and the loot,
--   armed    the next click or key press throws, for ARM_TIMEOUT seconds at most,
--   expired  the time ran out, the wish is gone,
--   combat   a fight holds everything, the wish is kept and applied again after the fight.
-- Pure: the clock is injected, the game is reached by the caller.
local _, fish = ...
if not fish.FG then
  return
end

local R = {}
fish.Recast = R

-- Seconds the next click may throw before the wish lapses.
R.ARM_TIMEOUT = 5
-- Seconds a wish waits for the end of the channel and the loot before it lapses (the reel in did not happen).
R.WAIT_LIMIT = 20
-- Clock values are floats: an edge must not fail by a rounding error.
local EPSILON = 1e-6

local Machine = {}
Machine.__index = Machine

-- opts.clock() -> seconds, opts.pause -> seconds or a function that returns them (the setting can change).
function R.New(opts)
  assert(type(opts) == "table" and type(opts.clock) == "function", "recast needs a clock")
  return setmetatable({
    clock = opts.clock,
    pause = opts.pause or 1,
    phase = "ready",
    fight = false,
  }, Machine)
end

function Machine:_pause()
  local pause = type(self.pause) == "function" and self.pause() or self.pause
  return type(pause) == "number" and pause >= 0 and pause or 1
end

-- The state as a text; "combat" while a fight holds the wish.
function Machine:State()
  if self.fight then
    return "combat"
  end
  return self.phase
end

-- True while the wish waits for the end of the channel and the loot (the throw is not offered yet).
function Machine:Holding()
  return self.phase == "reeled"
end

-- True when the next click throws. source: "mouse" or "key" restricts it to a wish made that way.
function Machine:Armed(source)
  return not self.fight and self.phase == "armed" and (source == nil or self.source == source)
end

-- The line went out (also a throw made by hand while a wish waited: the old wish is void).
function Machine:ChannelStarted()
  self.phase, self.source = "out", nil
  self.channelDone, self.lootOpen, self.lootClosed = nil, nil, nil
end

-- The channel ended. A wish that waits moves on, everything else is at rest.
function Machine:ChannelStopped()
  if self.phase == "reeled" then
    self.channelDone, self.stoppedAt = true, self.clock()
  elseif self.phase == "out" or self.phase == "expired" then
    self.phase = "ready"
  end
end

-- The wish to throw again after the reel in. Allowed with the line out (or when the caller saw it out).
-- Returns true when a wish is kept.
function Machine:Request(source)
  if self.phase == "reeled" then
    return true
  end
  if self.phase ~= "out" and self.phase ~= "ready" and self.phase ~= "expired" then
    return false
  end
  local now = self.clock()
  self.phase, self.source, self.requestedAt = "reeled", source, now
  self.channelDone, self.stoppedAt, self.lootOpen, self.lootClosed = nil, nil, nil, nil
  return true
end

function Machine:LootOpened()
  if self.phase == "reeled" or self.phase == "armed" then
    self.lootOpen, self.lootClosed = true, nil
    if self.phase == "armed" then
      -- A window came up after all: the throw waits until it is closed.
      self.phase = "reeled"
    end
  end
end

function Machine:LootClosed()
  self.lootOpen = false
  if self.phase == "reeled" then
    self.lootClosed = true
  end
end

-- Moves the state with the time: offers the throw, lets a wish lapse. Returns the state.
function Machine:Tick()
  if self.fight then
    return "combat"
  end
  local now = self.clock()
  if self.phase == "reeled" then
    if now - self.requestedAt > R.WAIT_LIMIT + EPSILON then
      self.phase = "expired"
    elseif self.channelDone and not self.lootOpen then
      if self.lootClosed or now - self.stoppedAt >= self:_pause() - EPSILON then
        self.phase, self.armedAt = "armed", now
      end
    end
  elseif self.phase == "armed" then
    if now - self.armedAt > R.ARM_TIMEOUT + EPSILON then
      self.phase = "expired"
    end
  end
  return self.phase
end

-- A click or key press threw: true when it was the offered throw.
function Machine:Consume()
  if self:Tick() ~= "armed" then
    return false
  end
  self.phase, self.source = "ready", nil
  return true
end

-- Drops the wish (the option went off, the helper stopped).
function Machine:Cancel()
  self.phase, self.source, self.fight = "ready", nil, false
  self.channelDone, self.lootOpen, self.lootClosed = nil, nil, nil
end

-- A fight started: the wish is kept and the offer stops.
function Machine:CombatStarted()
  self.fight = true
end

-- The fight ended: the wish continues with fresh waiting times (the old ones ran during the fight).
function Machine:CombatEnded()
  if not self.fight then
    return
  end
  self.fight = false
  local now = self.clock()
  if self.phase == "reeled" then
    self.requestedAt = now
    if self.channelDone then
      self.stoppedAt = now
    end
  elseif self.phase == "armed" then
    self.armedAt = now
  end
end
