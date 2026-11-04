-- What the element types tell a group about their place (see GroupLogic.RegisterOccupancy): whether the frame of an
-- element is there ("yes"), not there ("no") or not known ("nil", the game keeps it secret). The adapters only read
-- what the elements keep on their own frame: the opacity our own code set, the flags of their state. They never
-- touch the native aura button and never read a number the game keeps secret. Types that cannot hide (ring,
-- shape, crosshair, swing and the rest) need no adapter, GroupLogic.Occupancy counts them as "yes".
local _, ns = ...
local GL = ns.GroupLogic
local G = ns.CursorTimers.Guard
local readable, try = G.readable, G.try

-- The element state that cooldown and aura keep on their frame (`fgCooldown`), nil for a frame that is not driven
-- (editor preview, not started yet).
local function stateOf(frame)
  local st = type(frame) == "table" and frame.fgCooldown or nil
  return st and st.driven and st or nil
end

-- "no" while the frame is fully transparent, "yes" above that. The opacity is a number of ours.
local function byOpacity(frame)
  local alpha = readable(try(frame.GetAlpha, frame))
  if alpha == nil then
    return nil
  end
  return alpha > 0 and "yes" or "no"
end

-- The opacity of a cooldown follows its show rule. A threshold the engine evaluates on a curve is not ours to know.
local function cooldownPlace(frame)
  local st = stateOf(frame)
  if not st then
    return "yes"
  end
  if st.viaCurve then
    return nil
  end
  return byOpacity(frame)
end

-- An aura on the native container is shown by the engine, a presence the game keeps secret or a threshold on a
-- curve is not known either. The calculated aura sets its opacity itself.
local function auraPlace(frame)
  local st = stateOf(frame)
  if not st then
    return "yes"
  end
  if st.nativeShown or st.viaCurve then
    return nil
  end
  local s = st.s
  if s and s.present == nil and s.presentRaw ~= nil then
    return nil
  end
  return byOpacity(frame)
end

-- Running (true), ready (false) or not known (nil), and the seconds left. The seconds are only read outside combat
-- and only when the game lets us: a sorting by remaining time keeps the order of the start of the fight.
local function cooldownReading(frame, _, combat)
  local st = stateOf(frame)
  local s = st and st.s
  if not s then
    return nil
  end
  local active
  if s.state == "active" then
    active = true
  elseif s.state == "ready" or s.state == "gcd" then
    active = false
  end
  return { active = active, remaining = not combat and readable(s.remaining) or nil }
end

local function auraReading(frame, _, combat)
  local st = stateOf(frame)
  local s = st and st.s
  if not s then
    return nil
  end
  local active
  if s.present == true then
    active = true
  elseif s.present == false then
    active = false
  end
  return { active = active, remaining = not combat and readable(s.remaining) or nil }
end

GL.RegisterOccupancy("spellcd", cooldownPlace)
GL.RegisterOccupancy("aura", auraPlace)
GL.RegisterReading("spellcd", cooldownReading)
GL.RegisterReading("aura", auraReading)
