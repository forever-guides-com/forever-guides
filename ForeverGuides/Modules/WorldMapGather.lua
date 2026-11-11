-- Ore and herb spots and the explored look on Blizzard's world map (WorldMapFrame, the big window and the
-- small one are the same object). Nothing of Blizzard's is written: the frames are ours, children of the
-- map canvas, so they pan and zoom with it, and the hooks come from WorldMapLinks.lua, which tells the
-- changes with the message FG_WORLDMAP_VIEW ("map", "scale", "size", "hide").
--
-- Spots: the pool and the hover test are ns.GatheringMap (one frame without mouse, textures from a pool,
-- one throttled poll of the cursor). Here it draws for the map the window shows, not the zone of the
-- player, the items come from ns.GatherFilter.ZoneItems like on the addon map and a symbol keeps its size on the screen while the canvas
-- zooms. Spots without an item (chests, fishing schools, ns.GatherObjects) are a second layer of the same
-- kind under the same main switch, with their own filter.
--
-- Explored look: a frame under the spots draws every overlay picture of the zone (ns.MapReveal.Draw, data
-- of ForeverGuides_MapData) over the canvas. The client draws the explored pieces itself from the same
-- pictures, so a piece it draws on top of ours is the same picture at full opacity: nothing gets
-- brighter. Pictures the client has not drawn show up, pictures it draws stay as they are.
local _, ns = ...
local WL = ns.WorldMapGatherLogic

local WG = {}
ns.WorldMapGather = WG

-- The scale and size hooks fire on every step of the zoom animation; one repaint per interval is enough.
local REPAINT = 0.05

local ctl, octl, host
local lastMode = "off"
local artCache = {}

-- Access -------------------------------------------------------------------------------------------

local function map()
  return ns.WorldMapLinks and ns.WorldMapLinks.Map()
end

local function shown(frame)
  local ok, value = pcall(frame.IsShown, frame)
  return ok and value == true
end

local function mapShown()
  local m = map()
  return m ~= nil and shown(m)
end

local function readable(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function mapId()
  return ns.WorldMapLinks.MapID()
end

local function pinsSwitch()
  local gather = ns.Store.get("settings.gather")
  return type(gather) ~= "table" or gather.worldmap ~= false
end

-- The explored look has its own switch, independent of the spots.
local function revealSwitch()
  return ns.Store.get("settings.worldMapReveal") ~= false
end

local function shownSymbols(layer)
  local count = 0
  for _, s in ipairs(layer and layer.pool or {}) do
    if s.icon:IsShown() then
      count = count + 1
    end
  end
  return count
end

-- Which parts the map shows now, for the tests and the panel: { pins = number of ore and herb symbols,
-- objects = number of symbols of chests and schools, reveal = mode, pieces = number of overlay textures }.
function WG.State()
  local pins = shownSymbols(ctl)
  local pieces = 0
  for _, tex in ipairs(host and host.overlayTiles or {}) do
    if tex:IsShown() then
      pieces = pieces + 1
    end
  end
  return { pins = pins, objects = shownSymbols(octl), reveal = lastMode, pieces = pieces }
end

function WG.Parts()
  return { gather = ctl, objects = octl, reveal = host }
end

-- Forgets the cached art layers (tests).
function WG.Reset()
  artCache = {}
end

-- Spots ---------------------------------------------------------------------------------------------

-- The set of items to draw for the map: the zone's items that pass the filter, nothing on a map without spots.
-- The data add-on loads here, the first time a zone map needs it.
local function wantedItems(id)
  if not WL.PinsWanted(pinsSwitch(), id, ns.WorldMapLinks.MapType(id)) then
    return nil
  end
  local data = ns.GatherDataAccess.Get()
  return data and ns.GatherFilter.ZoneItems(data, id) or nil
end

-- The set of kinds without an item to draw for the map, same rules as above.
local function wantedKinds(id)
  if not WL.PinsWanted(pinsSwitch(), id, ns.WorldMapLinks.MapType(id)) then
    return nil
  end
  local data = ns.GatherDataAccess.Get()
  return data and ns.GatherObjects.ZoneKinds(data, id) or nil
end

-- One layer of the symbols on the canvas: feed (nil: the ores and herbs) and the set of what to draw.
local function attachLayer(canvas, feed, items)
  local WLinks = ns.WorldMapLinks
  local container = WLinks.Container()
  local layer = ns.GatheringMap.Attach({
    canvas = canvas,
    mapId = mapId,
    enabled = pinsSwitch,
    items = items,
    feed = feed,
    window = function()
      return 0, 0, canvas:GetWidth(), canvas:GetHeight()
    end,
    cursor = function()
      local m = map()
      local ok, nx, ny = pcall(m.GetNormalizedCursorPosition, m)
      if ok and readable(nx) and readable(ny) then
        return nx, ny
      end
    end,
    unit = function()
      return WL.Unit(WLinks.CanvasScale())
    end,
    pinSize = function()
      return WL.PinSize(WLinks.CanvasScale())
    end,
    onMap = function(target)
      return target == canvas or target == container
    end,
  })
  layer.layer:SetFrameLevel(WLinks.CanvasLevel(canvas, "spots"))
  return layer
end

local function ensurePins(canvas)
  if not ctl then
    ctl = attachLayer(canvas, nil, wantedItems)
  end
  if not octl then
    octl = attachLayer(canvas, ns.GatherObjects.Feed, wantedKinds)
  end
  return ctl
end

-- State for /fg mapdiag: how many spots the data has for the map (computed), how many of them the plan
-- keeps (planned, capped at cap), the textures made so far (pool) and the ones shown (drawn).
function WG.Debug()
  local GM = ns.GatheringMapLogic
  local id = mapId()
  local state = WG.State()
  local out = { map = id, switch = pinsSwitch(), cap = GM.MAX_PINS, pool = ctl and #ctl.pool or 0, drawn = state.pins }
  out.reveal, out.pieces = state.reveal, state.pieces
  out.revealLevel = host and host:GetFrameLevel()
  local plan = ctl and ctl.plan
  out.planned, out.inExtent, out.truncated = plan and #plan.pins, plan and plan.total, plan and plan.truncated
  if ctl then
    out.level, out.layerShown = ctl.layer:GetFrameLevel(), ctl.layer:IsShown()
  end
  local set = id and wantedItems(id)
  local data = set and ns.GatherDataAccess.Get()
  if data then
    out.items = 0
    for _ in pairs(set) do
      out.items = out.items + 1
    end
    out.computed = #GM.Points(data, id, set)
  end
  local kinds = id and wantedKinds(id)
  out.objectsDrawn = state.objects
  if kinds and data then
    out.objects = #ns.GatherObjects.Points(data, id, kinds)
  end
  return out
end

-- Lays the spots out for the map of the window. force = false (zoom or size only) keeps a plan that still
-- fits. Nothing is built before the switch is on and the map is open.
function WG.PaintPins(force)
  local m = map()
  if not m or not ns.ProtectedAllowed(m) then
    return
  end
  local canvas = ns.WorldMapLinks.Canvas()
  if not canvas then
    return
  end
  if not ctl and not (pinsSwitch() and shown(m)) then
    return
  end
  ensurePins(canvas)
  if shown(m) then
    ctl.Paint(force)
    octl.Paint(force)
  else
    ctl.Clear()
    octl.Clear()
  end
end

-- Explored look --------------------------------------------------------------------------------------

local function artOf(id)
  local cached = artCache[id]
  if cached == nil then
    cached = ns.MapWorld.LoadArt(id) or false
    artCache[id] = cached
  end
  return cached or nil
end

local function clearReveal()
  if host then
    ns.MapReveal.Draw(host, nil, nil)
    ns.MapReveal.ReleaseTextures(host)
    host:Hide()
  end
end

local function ensureReveal(canvas)
  if host then
    return host
  end
  host = CreateFrame("Frame", nil, canvas)
  host:SetAllPoints(canvas)
  host:SetFrameLevel(ns.WorldMapLinks.CanvasLevel(canvas, "reveal"))
  host:EnableMouse(false)
  host:Hide()
  return host
end

-- Draws every area of the zone the window shows, or puts the normal look back (no leftovers: the textures
-- are hidden and give their files back).
function WG.PaintReveal()
  local m = map()
  if not m or not ns.ProtectedAllowed(m) then
    return
  end
  local canvas = ns.WorldMapLinks.Canvas()
  local id = ns.WorldMapLinks.MapID()
  local RV = ns.MapReveal
  local state = RV.Available() and "ready" or ns.PackageUI.State(RV.ADDON)
  local mode = WL.RevealMode(revealSwitch() and canvas ~= nil and shown(m), id, ns.WorldMapLinks.MapType(id), state)
  lastMode = mode
  if mode ~= "draw" then
    clearReveal()
    return
  end
  local art = artOf(id)
  local pieces = art and RV.Pieces(ns.MapWorld.ArtId(id))
  if not pieces then
    lastMode = "banner"
    clearReveal()
    return
  end
  ensureReveal(canvas)
  RV.Draw(host, art, pieces, 1, { x = 0, y = 0, w = canvas:GetWidth(), h = canvas:GetHeight() })
  host:Show()
end

-- Both ---------------------------------------------------------------------------------------------

function WG.Refresh()
  ns.Safe("wmg-reveal", WG.PaintReveal)
  ns.Safe("wmg-pins", WG.PaintPins, true)
end

local function clearAll()
  clearReveal()
  if ctl then
    ctl.Clear()
    octl.Clear()
  end
end

ns.On("FG_WORLDMAP_VIEW", function(_, kind)
  if kind == "map" then
    WG.Refresh()
  elseif kind == "hide" then
    clearAll()
  elseif kind == "scale" then
    ns.Debounce("wmg-scale", REPAINT, function()
      WG.PaintPins(false)
    end)
  elseif kind == "size" then
    ns.Debounce("wmg-size", REPAINT, function()
      WG.PaintReveal()
      WG.PaintPins(false)
    end)
  end
end)

-- The filter changed (it tells once per change, the single settings it writes are not listened to).
ns.On("FG_GATHER_FILTER_CHANGED", function()
  WG.PaintPins(true)
end)

-- The page of the items changed the choice of a zone.
ns.On("FG_GATHER_SELECTION", function()
  WG.PaintPins(true)
end)

-- The two switches of the settings page and the panel.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.worldMapReveal" then
    WG.PaintReveal()
  elseif path == "settings.gather.worldmap" then
    WG.PaintPins(true)
  end
end)

-- The data add-ons changed.

ns.On("FG_PACKAGE_CHANGED", function()
  if mapShown() then
    WG.Refresh()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if mapShown() then
    WG.Refresh()
  end
end)
