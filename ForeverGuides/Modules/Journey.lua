-- Runtime glue for a journey (JourneyLogic): reads the player position, the taxi state and the zone
-- events, feeds them into the state machine and points the waypoint arrow at the current target.
-- Off until the player starts a journey; while it is off no frame runs and no event is registered.
--   Journey.Start(plan, nameOf) -> true | nil, "empty"   nameOf(slug) gives the place name for texts
--   Journey.Stop()               Journey.Active() -> state or nil
--   Journey.Feed(input)          one input by hand (the tick and the events call this)
local _, ns = ...
local JL, WL = ns.JourneyLogic, ns.WaypointLogic

local JR = {}
ns.Journey = JR

local TICK = 1 -- seconds between position checks
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

local state, frame, elapsed, wasTaxi

local function onTaxi()
  local fn = rawget(_G, "UnitOnTaxi")
  return type(fn) == "function" and fn("player") == true
end

-- The arrow follows the current target; a target without a map position leaves the arrow alone.
local function point(cur)
  local WP = ns.Waypoints
  if not (cur and WP and WP.Set) then
    return
  end
  local t = cur.target
  local title = string.format(ns.L[cur.textKey], state.nameOf(cur.slug))
  if t.pos and (cur.index ~= state.shown or cur.phase ~= state.phase) then
    pcall(WP.Set, { map = t.pos.map, x = t.pos.x, y = t.pos.y, title = title, source = "journey" })
  end
  state.shown, state.phase = cur.index, cur.phase
  if state.lastText ~= title then
    state.lastText = title
    pcall(ns.Notify, title, "info")
  end
end

function JR.Feed(input)
  if not state then
    return
  end
  local _, cur = JL.Update(state.j, input)
  if cur then
    point(cur)
  else
    pcall(ns.Notify, ns.L["journey.done"], "info")
    JR.Stop()
  end
end

local function tick()
  local input = { flying = onTaxi() }
  local WP = ns.Waypoints
  local map, x, y
  if WP and WP.PlayerPosition then
    map, x, y = WP.PlayerPosition()
  end
  if map then
    input.pos = { map = map, x = x, y = y }
  end
  if input.flying and not wasTaxi then
    input.event = "taxi"
  elseif wasTaxi and not input.flying then
    input.event = "landed"
  end
  wasTaxi = input.flying
  JR.Feed(input)
end

function JR.Active()
  return state
end

function JR.Start(plan, nameOf)
  if not (plan and plan.targets and #plan.targets > 0 and CreateFrame) then
    return nil, "empty"
  end
  JR.Stop()
  state = {
    j = JL.New(ns.Data.Travel, plan, {
      distance = function(a, b)
        return WL.distanceYards(a.map, a.x, a.y, b.map, b.x, b.y)
      end,
    }),
    nameOf = nameOf or function(slug)
      return slug
    end,
  }
  frame = frame or CreateFrame("Frame")
  for _, e in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, e)
  end
  frame:SetScript("OnEvent", function()
    JR.Feed({ event = "zone" })
  end)
  elapsed, wasTaxi = 0, onTaxi()
  frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= TICK then
      elapsed = 0
      tick()
    end
  end)
  point(JL.Current(state.j))
  return true
end

function JR.Stop()
  if frame then
    frame:SetScript("OnUpdate", nil)
    frame:SetScript("OnEvent", nil)
    pcall(frame.UnregisterAllEvents, frame)
  end
  local WP = ns.Waypoints
  local wp = WP and WP.Active and WP.Active()
  if wp and wp.source == "journey" and WP.Remove then
    pcall(WP.Remove, wp.id, true)
  end
  state = nil
end
