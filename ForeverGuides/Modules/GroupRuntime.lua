-- Closing up and sorting of the groups while the game runs. CanvasRender lists the canvases that show a group whose
-- places change (it closes up or sorts); this file watches them: it asks the frames of the children whether they
-- are there (GroupOccupancy), lets CanvasRender.Reflow set the new places and does that again when a cooldown, the
-- combat state or the clock (four times a second) says something may have changed. It only reads states and only
-- sets points on frames of ours, so it also runs in combat. It sleeps while no such canvas is on screen.
local _, ns = ...
local CR, GL = ns.CanvasRender, ns.GroupLogic

local GRT = { INTERVAL = 0.25, SOON = 0.05 }
ns.GroupRuntime = GRT

local EVENTS = { "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local watcher
local combat, dirty, waited = false, false, 0

local function inCombat()
  local ok, value = pcall(InCombatLockdown)
  return ok and value == true
end

-- Occupancy and readings of every child of the layout drawn on `canvas`.
local function inputsOf(canvas, layout)
  local occupancy, readings = {}, {}
  for _, el in ipairs(layout.elements) do
    if el.group ~= nil then
      local frame = CR.Frame(canvas, el.id)
      if frame then
        occupancy[el.id] = GL.Occupancy(el, frame)
        readings[el.id] = GL.Reading(el, frame, combat)
      else
        occupancy[el.id] = "no"
      end
    end
  end
  return { occupancy = occupancy, readings = readings, combat = combat }
end

-- One pass over the watched canvases. Returns the number of frames that moved.
function GRT.Run()
  local list = {}
  for canvas in pairs(CR.live) do
    list[#list + 1] = canvas
  end
  local moved = 0
  for _, canvas in ipairs(list) do
    local state = canvas.fgCanvas
    local layout = state and state.layout
    if layout then
      moved = moved + CR.Reflow(canvas, layout, inputsOf(canvas, layout))
    end
  end
  return moved
end

function GRT.Tick(elapsed)
  waited = waited + (elapsed or 0)
  if waited >= GRT.INTERVAL or (dirty and waited >= GRT.SOON) then
    waited, dirty = 0, false
    ns.Safe("groups.run", GRT.Run)
  end
end

local function onEvent(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    combat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    combat = false
  end
  dirty = true
end

-- Wakes up when a canvas with a moving group appears, sleeps when the last one is gone.
local function sync()
  if next(CR.live) then
    if not watcher then
      watcher = CreateFrame("Frame")
      watcher:SetScript("OnEvent", ns.Wrap("groups-event", onEvent))
    end
    combat, dirty, waited = inCombat(), true, 0
    for _, event in ipairs(EVENTS) do
      pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnUpdate", function(_, elapsed)
      GRT.Tick(elapsed)
    end)
  elseif watcher then
    watcher:UnregisterAllEvents()
    watcher:SetScript("OnUpdate", nil)
  end
end

CR.onLive = sync

-- The frame that holds the registrations, nil until a moving group was on screen.
function GRT.Watcher()
  return watcher
end
