-- A journey along a planned trip (TravelPlan): which target is current, which text belongs to it, and
-- when to move on. Pure state machine without WoW API; the runtime feeds in what happened.
--
--   local j = JL.New(data, plan, { radius = 25, distance = function(a, b) ... end })
--   JL.Update(j, { pos = { map, x, y }, event = "taxi" | "landed" | "zone" }) -> changed, current
--   JL.Current(j) -> nil when finished, else { index, count, target, phase, step, textKey, slug, riding }
--   JL.Skip(j)    -> moves on to the next target
-- input.flying = true while on a taxi, so that flying past a place does not count as arriving.
-- distance(a, b) gives yards between two { map, x, y } points, or nil when it cannot tell (other
-- map, unknown conversion); then only events move the journey on. Walk targets and boarding places
-- are reached inside the radius. A ride ends on the landing (flights), on a zone change (every
-- other ride) or when the player stands at the end of a ride step; a hearthstone or spell ride
-- needs no walk to its start.
local _, ns = ...
local TP = ns.TravelPlan

local JL = {}
ns.JourneyLogic = JL

JL.RADIUS = 25

ns.AddLocale("enUS", {
  ["journey.walk"] = "Walk to %s.",
  ["journey.go.flight"] = "Go to the flight master in %s.",
  ["journey.go.boat"] = "Go to the dock at %s.",
  ["journey.go.zeppelin"] = "Go to the zeppelin tower at %s.",
  ["journey.go.tram"] = "Go to the tram at %s.",
  ["journey.go.portal"] = "Go to the portal at %s.",
  ["journey.go.lift"] = "Go to the lift at %s.",
  ["journey.go.spell"] = "Go to %s and cast your spell there.",
  ["journey.go.teleport"] = "Use your hearthstone.",
  ["journey.ride.flight"] = "Fly to %s.",
  ["journey.ride.boat"] = "Take the boat to %s.",
  ["journey.ride.zeppelin"] = "Take the zeppelin to %s.",
  ["journey.ride.tram"] = "Take the tram to %s.",
  ["journey.ride.portal"] = "Step through the portal to %s.",
  ["journey.ride.lift"] = "Take the lift to %s.",
  ["journey.ride.spell"] = "Cast your spell to %s.",
  ["journey.ride.teleport"] = "Use your hearthstone to get to %s.",
  ["journey.done"] = "You have arrived.",
})
ns.AddLocale("deDE", {
  ["journey.walk"] = "Gehe zu %s.",
  ["journey.go.flight"] = "Gehe zum Flugmeister in %s.",
  ["journey.go.boat"] = "Gehe zum Anleger bei %s.",
  ["journey.go.zeppelin"] = "Gehe zum Zeppelinturm bei %s.",
  ["journey.go.tram"] = "Gehe zur Tiefenbahn bei %s.",
  ["journey.go.portal"] = "Gehe zum Portal bei %s.",
  ["journey.go.lift"] = "Gehe zum Aufzug bei %s.",
  ["journey.go.spell"] = "Gehe nach %s und wirke dort deinen Zauber.",
  ["journey.go.teleport"] = "Benutze deinen Ruhestein.",
  ["journey.ride.flight"] = "Fliege nach %s.",
  ["journey.ride.boat"] = "Fahre mit dem Boot nach %s.",
  ["journey.ride.zeppelin"] = "Fahre mit dem Zeppelin nach %s.",
  ["journey.ride.tram"] = "Fahre mit der Tiefenbahn nach %s.",
  ["journey.ride.portal"] = "Gehe durch das Portal nach %s.",
  ["journey.ride.lift"] = "Fahre mit dem Aufzug nach %s.",
  ["journey.ride.spell"] = "Wirke deinen Zauber nach %s.",
  ["journey.ride.teleport"] = "Benutze deinen Ruhestein, um nach %s zu kommen.",
  ["journey.done"] = "Du bist angekommen.",
})

function JL.New(data, plan, opts)
  opts = opts or {}
  local j = {
    data = data,
    steps = plan.steps or {},
    targets = plan.targets or {},
    radius = opts.radius or JL.RADIUS,
    distance = opts.distance,
    i = 1,
    reached = {}, -- { stop, goal, leg } of every stop and goal passed, in order
    ride = 0, -- steps of the current ride that are done
    riding = false,
  }
  JL.Enter(j)
  return j
end

-- Sets the phase for the target that just became current.
function JL.Enter(j)
  j.ride, j.riding = 0, false
  local t = j.targets[j.i]
  if t and t.kind == "board" and t.hearth then
    j.phase = "ride"
  else
    j.phase = "go"
  end
end

local function finished(j)
  return j.i > #j.targets
end

function JL.Finished(j)
  return finished(j)
end

-- The destination of the ride that ends the current board target.
local function rideEnd(j, t)
  local step = j.steps[t.step + t.rides - 1]
  return step and step.to or t.slug
end

function JL.Current(j)
  if finished(j) then
    return nil
  end
  local t = j.targets[j.i]
  local key, slug = "journey.walk", t.slug
  local step = j.steps[t.step]
  if t.kind == "board" then
    if j.phase == "go" then
      key = "journey.go." .. t.mode
    else
      key, slug = "journey.ride." .. t.mode, rideEnd(j, t)
    end
    step = j.steps[t.step + j.ride]
  elseif t.kind == "arrive" then
    key = "journey.done"
  end
  return {
    index = j.i,
    count = #j.targets,
    target = t,
    phase = j.phase,
    step = step,
    textKey = key,
    slug = slug,
    riding = j.riding,
  }
end

local function near(j, pos, place)
  if not (pos and place and j.distance) then
    return false
  end
  local ok, yards = pcall(j.distance, pos, place)
  return ok and type(yards) == "number" and yards <= j.radius
end

function JL.Skip(j)
  if not finished(j) then
    local t = j.targets[j.i]
    if t.stop or t.goal then
      j.reached[#j.reached + 1] = { stop = t.stop, goal = t.goal, leg = t.leg }
    end
    j.i = j.i + 1
    JL.Enter(j)
  end
end

-- One input against the current target. True when the journey moved (a phase or a target).
local function advance(j, input)
  local t = j.targets[j.i]
  if t.kind == "arrive" then
    JL.Skip(j)
    return true
  end
  if t.kind == "walk" then
    if near(j, input.pos, t.pos) then
      JL.Skip(j)
      return true
    end
    return false
  end
  if j.phase == "go" then
    if near(j, input.pos, t.pos) then
      j.phase = "ride"
      return true
    end
    return false
  end
  -- Riding: the steps of the ride in turn.
  local last = t.step + t.rides - 1
  local at = t.step + j.ride
  local step = j.steps[at]
  local moved = false
  if input.event == "taxi" and step and step.mode == "flight" and not j.riding then
    j.riding, moved = true, true
  elseif input.event == "landed" and step and step.mode == "flight" then
    -- One flight covers every hop of the taxi trip.
    j.ride = last - t.step + 1
    moved = true
  elseif input.event == "zone" and step and step.mode ~= "flight" then
    j.ride = j.ride + 1
    moved = true
  elseif step and not (step.mode == "flight" and input.flying) then
    -- Standing at the end of a later step of the ride counts, the events may have been missed.
    for k = last, at, -1 do
      if near(j, input.pos, TP.PositionOf(j.data, j.steps[k].to)) then
        j.ride, moved = k - t.step + 1, true
        break
      end
    end
  end
  if t.step + j.ride > last then
    JL.Skip(j)
    return true
  end
  return moved
end

-- input = { pos, event }. Returns whether anything changed and the current state (nil at the end).
function JL.Update(j, input)
  local changed = false
  -- A position can satisfy several targets in a row; an event only counts for the first.
  local guard = #j.targets + 2
  while not finished(j) and guard > 0 do
    guard = guard - 1
    if not advance(j, input) then
      break
    end
    changed = true
    input = { pos = input.pos }
  end
  return changed, JL.Current(j)
end
