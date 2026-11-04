-- Ring buffer of what our code does with Blizzard's world map (hooks that run after its methods, click
-- handlers, opening a map). When the game blocks a protected call of the map, the error list attaches the
-- last entries (Modules/ErrorCatcher.lua), so the next occurrence shows what ran just before it.
local _, ns = ...
local U = ns.U

local MapOps = {}
ns.MapOps = MapOps

MapOps.LIMIT = 30
MapOps.REPORT = 10

local ring = ns.Ring.new(MapOps.LIMIT)

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function clock()
  return type(GetTime) == "function" and GetTime() or 0
end

-- name: what ran, detail: optional short text (a map id, a script name). The same operation in the same
-- combat state right after itself only counts up, so a hook that fires every frame cannot push the
-- older entries out.
function MapOps.Record(name, detail)
  detail = detail ~= nil and tostring(detail) or nil
  local combat = inCombat()
  local items = ring:list()
  local last = items[#items]
  if last and last.name == name and last.detail == detail and last.combat == combat then
    last.n, last.at, last.time = last.n + 1, clock(), U.now()
    return
  end
  ring:push({ name = name, detail = detail, combat = combat, n = 1, at = clock(), time = U.now() })
end

-- Runs fn on the next frame, protected, after recording it. Hooks of Blizzard's map use this so that
-- nothing of ours runs inside the call they are hooked to.
function MapOps.Defer(name, fn)
  MapOps.Record(name)
  local function run()
    ns.Safe(name, fn)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, run)
  else
    run()
  end
end

-- The newest `count` entries (default MapOps.REPORT), oldest first.
function MapOps.Last(count)
  local items = ring:list()
  local out = {}
  for i = math.max(1, #items - (count or MapOps.REPORT) + 1), #items do
    out[#out + 1] = items[i]
  end
  return out
end

function MapOps.Clear()
  ring:clear()
end
