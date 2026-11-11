-- Rules of the plate badge (PlateBadge.lua): which nameplate gets the logo, size and place from the settings,
-- the count of the frame pool and the error counter. No game calls here: the caller hands in the facts.
local _, ns = ...

local PBL = {}
ns.PlateBadgeLogic = PBL

PBL.MIN_SIZE = 8
PBL.MAX_SIZE = 32
PBL.DEFAULT_SIZE = 16
-- Most logos at the same time, which is also the number of pool frames.
PBL.MAX_LOGOS = 40
PBL.MAX_ERRORS = 3
-- Limit of a shift (pixels) in either direction.
PBL.MAX_OFFSET = 60
PBL.SIDES = { "center", "left", "right" }
PBL.DEFAULT_SIDE = "center"
-- Distance of the logo row from the middle line of the name (left and right) and above the top edge of the name.
-- The width of the name is never read, so the side is a fixed gap and not a measured one.
PBL.GAP = 6
PBL.RISE = 1
-- Guild and community symbols next to the logo: at most this many, the gap between two symbols and the widest
-- row (pixels), so a plate never gets wider than a plate is.
PBL.MAX_CRESTS = 3
PBL.ICON_GAP = 2
PBL.MAX_WIDTH = 96

-- Settings --------------------------------------------------------------------------------------------

function PBL.CleanSize(size)
  size = tonumber(size)
  if not size or size ~= size then
    return PBL.DEFAULT_SIZE
  end
  return math.max(PBL.MIN_SIZE, math.min(PBL.MAX_SIZE, math.floor(size + 0.5)))
end

function PBL.CleanSide(side)
  if side == "right" or side == "left" or side == "center" then
    return side
  end
  return PBL.DEFAULT_SIDE
end

function PBL.CleanOffset(value)
  value = tonumber(value)
  if not value or value ~= value then
    return 0
  end
  return math.max(-PBL.MAX_OFFSET, math.min(PBL.MAX_OFFSET, math.floor(value + 0.5)))
end

-- Anchor of the logo row at the name of the plate: { point, relPoint, x, y }. The row sits on the top edge of
-- the name, centered, or ending left or right of the middle line; dx and dy shift it (limited to PBL.MAX_OFFSET).
function PBL.Position(side, dx, dy)
  local shift = PBL.CleanOffset(dx)
  local y = PBL.RISE + PBL.CleanOffset(dy)
  side = PBL.CleanSide(side)
  if side == "right" then
    return { point = "BOTTOMLEFT", relPoint = "TOP", x = PBL.GAP + shift, y = y }
  elseif side == "left" then
    return { point = "BOTTOMRIGHT", relPoint = "TOP", x = -PBL.GAP + shift, y = y }
  end
  return { point = "BOTTOM", relPoint = "TOP", x = shift, y = y }
end

-- Size and width of a row of `count` symbols at the wanted size: the symbols shrink (never below the minimum)
-- when the row would be wider than PBL.MAX_WIDTH.
function PBL.Layout(count, size)
  count = math.max(1, math.floor(tonumber(count) or 1))
  size = PBL.CleanSize(size)
  local gap = PBL.ICON_GAP
  if count * size + (count - 1) * gap > PBL.MAX_WIDTH then
    size = math.max(PBL.MIN_SIZE, math.floor((PBL.MAX_WIDTH - (count - 1) * gap) / count))
  end
  return { size = size, gap = gap, width = count * size + (count - 1) * gap }
end

-- The guild and community symbols to draw out of the logos of a player (entries as CrestLocal.Shown gives them:
-- guild first, then communities): the first guild if wanted, communities after it, at most PBL.MAX_CRESTS.
-- wanted: { guild, community } booleans (nil counts as wanted).
function PBL.CleanCrests(entries, wanted)
  local out = {}
  if type(entries) ~= "table" then
    return out
  end
  wanted = wanted or {}
  local guildOn, communityOn = wanted.guild ~= false, wanted.community ~= false
  local hasGuild = false
  for _, entry in ipairs(entries) do
    if #out >= PBL.MAX_CRESTS then
      break
    end
    if type(entry) == "table" and (entry.path or entry.icon) then
      if entry.kind == "guild" and guildOn and not hasGuild then
        hasGuild = true
        out[#out + 1] = entry
      elseif entry.kind == "community" and communityOn then
        out[#out + 1] = entry
      end
    end
  end
  return out
end

-- Decision --------------------------------------------------------------------------------------------

-- Does this plate get a logo? Returns true, or false and the reason. facts:
--   enabled    the switch is on and the feature is not off for the session
--   listening  the receive consent of the presence mark is given (group or guild)
--   player     result of UnitIsPlayer, only true counts
--   name       readable name of the unit, nil when secret or unknown
--   self       the unit is the player
--   selfOn     the own logo is wanted
--   present    register entry { chatOnly } of the name, nil when nothing is known
function PBL.Decide(facts)
  if facts.enabled ~= true then
    return false, "off"
  elseif facts.listening ~= true then
    return false, "consent"
  elseif facts.player ~= true then
    return false, "notplayer"
  elseif type(facts.name) ~= "string" or facts.name == "" then
    return false, "noname"
  elseif facts.self == true then
    return facts.selfOn == true, "self"
  elseif type(facts.present) ~= "table" then
    return false, "unknown"
  elseif facts.present.chatOnly == true then
    return false, "chatonly"
  end
  return true, "ok"
end

-- What to draw for a plate: { forever = bool, crests = list } and "ok" or "crests", or nil and the reason. The add-on
-- logo follows Decide (and the switch for it, facts.logoOn); a player the register does not know still gets the
-- guild and community symbols the local recognition has for him. facts has the facts of Decide and
--   entries   logos of the player (guild first, then communities), may be empty or nil
--   wanted    { guild, community } booleans
function PBL.Plan(facts)
  local show, why = PBL.Decide(facts)
  local crests = PBL.CleanCrests(facts.entries, facts.wanted)
  if show and why == "self" or (show and why == "ok") then
    local forever = facts.logoOn ~= false
    if forever or #crests > 0 then
      return { forever = forever, crests = crests }, "ok"
    end
    return nil, "logo off"
  elseif not show and why == "unknown" and #crests > 0 then
    return { forever = false, crests = crests }, "crests"
  end
  return nil, why
end

-- Pool (count only) ---------------------------------------------------------------------------------

-- Counts frames: built (never destroyed) and free (waiting). Plan says what a new logo may do.
function PBL.NewPool(cap)
  local pool = { cap = cap or PBL.MAX_LOGOS }
  local built, free = 0, 0

  -- "reuse" when a frame waits, "build" when none waits, the pool is not full and building is allowed,
  -- else nil and the reason ("locked" or "full").
  function pool:Plan(locked)
    if free > 0 then
      return "reuse"
    end
    if built >= self.cap then
      return nil, "full"
    end
    if locked then
      return nil, "locked"
    end
    return "build"
  end

  -- Frames still to build until the pool is full.
  function pool:Missing()
    return self.cap - built
  end

  function pool:Built()
    built, free = built + 1, free + 1
  end

  function pool:Take()
    if free <= 0 then
      return false
    end
    free = free - 1
    return true
  end

  function pool:Put()
    if free >= built then
      return false
    end
    free = free + 1
    return true
  end

  function pool:Stats()
    return { built = built, free = free, used = built - free }
  end

  return pool
end

-- Errors ----------------------------------------------------------------------------------------------

-- Hit() counts an error and returns true exactly once, when the limit is reached and the feature goes off.
function PBL.NewErrors(max)
  local errors = { max = max or PBL.MAX_ERRORS }
  local count, off = 0, false

  function errors:Hit()
    count = count + 1
    if count >= self.max and not off then
      off = true
      return true
    end
    return false
  end

  function errors:Count()
    return count
  end

  function errors:IsOff()
    return off
  end

  function errors:Reset()
    count, off = 0, false
  end

  return errors
end
