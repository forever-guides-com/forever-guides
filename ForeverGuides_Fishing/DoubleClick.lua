-- Double click detection with an injectable clock. A double click is two clicks that are at least
-- MIN_GAP and at most the window apart. After a cast the next casts are locked for DEBOUNCE seconds,
-- so a triple click does not throw twice. The checks that depend on the game (combat, the left button,
-- an open loot window) are made by the caller, which calls Reset when one of them holds.
local _, fish = ...
if not fish.FG then
  return
end

local D = {}
fish.DoubleClick = D

D.MIN_GAP = 0.04
D.DEBOUNCE = 0.5
-- A click is short and quiet: held longer, or moved further than this, it is the camera and not a click.
-- Seconds from the press to the release.
D.CLICK_MAX_HOLD = 0.2
-- Physical pixels the pointer may travel between the press and the release, and the second click of a pair
-- may lie from the first.
D.CLICK_MAX_TRAVEL = 12
-- Clock values are floats: an edge of a window must not fail by a rounding error.
local EPSILON = 1e-6

local Detector = {}
Detector.__index = Detector

-- opts.clock() -> seconds, opts.window -> seconds or a function that returns them (the setting can change).
function D.New(opts)
  assert(type(opts) == "table" and type(opts.clock) == "function", "detector needs a clock")
  return setmetatable(
    { clock = opts.clock, window = opts.window or 0.2, last = nil, lockedUntil = -math.huge },
    Detector
  )
end

function Detector:_window()
  local window = type(self.window) == "function" and self.window() or self.window
  return type(window) == "number" and window or 0.2
end

-- True while the lock after a cast holds.
function Detector:Locked()
  return self.clock() < self.lockedUntil
end

-- Registers one click. True when it completes a double click; the second result is the time of its first click.
function Detector:Click()
  local now = self.clock()
  if now < self.lockedUntil then
    self.last = nil
    return false
  end
  if self.last ~= nil then
    local gap = now - self.last
    if gap < D.MIN_GAP - EPSILON then
      -- A bounce of the same click, the first time stays.
      return false
    end
    if gap <= self:_window() + EPSILON then
      local first = self.last
      self.last = nil
      return true, first
    end
  end
  self.last = now
  return false
end

-- A cast went out: locks further casts for the debounce time.
function Detector:Cast()
  self.lockedUntil = self.clock() + D.DEBOUNCE
  self.last = nil
end

function Detector:Reset()
  self.last = nil
end

local function distance(a, b)
  local dx, dy = a[1] - b[1], a[2] - b[2]
  return math.sqrt(dx * dx + dy * dy)
end

-- Judges one click from its press to its release (positions are {x, y} in physical pixels, or nil when
-- the client can not tell). Returns true, or false and the reason for the log.
function D.JudgeClick(held, from, to)
  if type(held) == "number" and held > D.CLICK_MAX_HOLD + EPSILON then
    return false, string.format("held %.2f s", held)
  end
  if from and to and distance(from, to) > D.CLICK_MAX_TRAVEL + EPSILON then
    return false, string.format("moved %d px", math.floor(distance(from, to) + 0.5))
  end
  return true
end

-- True when the second click of a pair lies too far from the first.
function D.TooFar(first, second)
  return first ~= nil and second ~= nil and distance(first, second) > D.CLICK_MAX_TRAVEL + EPSILON
end

-- True when the modifier state asks for a throw after the reel in: "recast" is on and the modifier is held
-- (or not held with recastInvert). Used for the double click and for the key.
function D.WantsRecast(options, modifierHeld)
  return options.recast == true and (modifierHeld == true) ~= (options.recastInvert == true)
end

-- What a double click does. channeling: the line is out. options: recast, recastInvert. modifierHeld:
-- a modifier key is down. Without the line out it casts. With the line out it always reels in: a throw
-- would cut the channel short and lose the catch. The second result is true when a throw after the reel in
-- is wanted (see Recast), that throw needs a click of its own.
function D.Action(channeling, options, modifierHeld)
  if not channeling then
    return "cast", false
  end
  return "reel", D.WantsRecast(options, modifierHeld)
end
