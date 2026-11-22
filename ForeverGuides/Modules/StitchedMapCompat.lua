-- Adapter for a map add-on that stitches its own world map over Blizzard's canvas and lets the player zoom
-- far in and out. Its art covers every canvas frame below a fixed frame level, so our layers (WML.LEVELS)
-- count from the top of that art while it is on. Without the add-on, or with its stitched map off, nothing
-- here changes anything: WML.CanvasLevel keeps counting from the canvas.
--
-- The public API of that add-on is read through its global (its global, major 1): IsStitched and
-- ArtTopLevel are asked on every use, the two callbacks are registered once and only if the API offers them.
-- The host map below the stitched art follows the view (it switches to the zone in view), so the zone to draw
-- is always WML.MapID(); a moved view only has to notice that the zone changed.
local _, ns = ...
local WML = ns.WorldMapLinks

local OC = {}
ns.StitchedMapCompat = OC

local API_GLOBAL = "OpenMapAPI"
local API_MAJOR = 1
local ADDON = "OpenMap"
local STITCHED_EVENT, VIEW_EVENT = "OpenMap_StitchedChanged", "OpenMap_ViewChanged"
-- Free levels between the top of the art and our lowest layer (reveal sits in the first).
local GAP = 2
-- Levels above the waypoint layer that stay free: its pins count up per entry (about 500) and the route
-- overlay lies above them.
local TOP_ROOM = 560
-- The view callback comes a few times a second; the repaint waits this long (as WorldMapGather's).
local SETTLE = 0.05

local function api()
  local a = rawget(_G, API_GLOBAL)
  if type(a) == "table" and a.major == API_MAJOR then
    return a
  end
end

-- Calls a function of the API that never raises; nil when it is missing or fails.
local function ask(name)
  local a = api()
  local fn = a and a[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn)
  if ok then
    return value
  end
end

local function sound(v)
  return type(v) == "number" and v == v and v > 0 and v < math.huge
end

-- True while the stitched map is on.
function OC.Stitched()
  return ask("IsStitched") == true
end

-- Absolute frame level per key of `levels` (WML.LEVELS) for a stitched art ending at `top`: the layers keep
-- their order and their gaps from `levels.spots` up. When the room up to `cap` (including TOP_ROOM above the
-- waypoints) is too small the gaps shrink evenly, the order stays. "ui" counts from the map, it is not planned.
function OC.Plan(top, cap, levels)
  local base = top + GAP
  local span = levels.waypoints - levels.spots + TOP_ROOM
  local room = math.max(cap - base, 0)
  local factor = room >= span and 1 or room / span
  local keys = {}
  for key in pairs(levels) do
    if key ~= "ui" and key ~= "reveal" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return levels[a] < levels[b]
  end)
  local plan, previous = { reveal = base - 1 }, base - 1
  for _, key in ipairs(keys) do
    local level = base + math.floor((levels[key] - levels.spots) * factor)
    previous = math.min(math.max(level, previous + 1), cap)
    plan[key] = previous
  end
  return plan
end

local cache = {}

-- Frame level of the layer `key` over the stitched art, nil when there is nothing to lift above.
function OC.Level(key)
  if not OC.Stitched() then
    return nil
  end
  local top = ask("ArtTopLevel")
  if not sound(top) then
    return nil
  end
  if cache.top ~= top then
    cache.top, cache.plan = top, OC.Plan(top, WML.LEVEL_CAP, WML.LEVELS)
  end
  return cache.plan[key]
end

-- Re-applies the levels of the frames that are set once. Our frames are unprotected; the check keeps this
-- from touching a map the client has locked in combat, it runs again when combat ends.
local waiting = false

local function relevel()
  local map = WML.Map()
  if map and not ns.ProtectedAllowed(map) then
    waiting = true
    return false
  end
  waiting = false
  WML.ReapplyLevels()
  return true
end

-- Levels again and a repaint of every layer: the stitched map went on or off.
function OC.Rebuild()
  if relevel() then
    ns.Emit("FG_WORLDMAP_VIEW", "map")
  end
end

local lastId, lastScale

-- The view moved: the zone below may have changed (draw its symbols), the canvas scale may have moved
-- (size only). Bundled, so a zoom does not repaint per step.
function OC.SyncView()
  local map = WML.Map()
  if not map or (waiting and not relevel()) then
    return
  end
  if WML.MapID() ~= lastId then
    ns.Emit("FG_WORLDMAP_VIEW", "map")
  elseif WML.CanvasScale() ~= lastScale then
    ns.Emit("FG_WORLDMAP_VIEW", "scale")
  end
end

-- Registered by method name: the callback handler of the add-on calls owner[method](owner, event, ...).
local owner = {}

function owner.StitchedChanged()
  ns.Safe("omc-stitched", OC.Rebuild)
end

function owner.ViewChanged()
  ns.Debounce("omc-view", SETTLE, OC.SyncView)
end

local registered = false

function OC.Register()
  local a = api()
  if registered or not a or type(a.RegisterCallback) ~= "function" then
    return
  end
  registered = pcall(a.RegisterCallback, owner, STITCHED_EVENT, "StitchedChanged")
    and pcall(a.RegisterCallback, owner, VIEW_EVENT, "ViewChanged")
end

ns.On("FG_WORLDMAP_VIEW", function(_, kind)
  if kind == "map" then
    OC.Register()
    lastId, lastScale = WML.MapID(), WML.CanvasScale()
    if api() then
      relevel()
    end
  elseif kind == "scale" then
    lastScale = WML.CanvasScale()
  end
end)

ns.On("PLAYER_LOGIN", OC.Register)

-- Load order of add-ons is not ours to know: the API may appear after our login.
ns.On("ADDON_LOADED", function(_, name)
  if name == ADDON then
    OC.Register()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if waiting then
    OC.Rebuild()
  end
end)
