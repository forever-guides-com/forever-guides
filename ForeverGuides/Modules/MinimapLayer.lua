-- Pins on the real minimap: ore and herb spots (source "gather") and a register for more sources (instances,
-- flight points, zone crossings later). The math is Modules/MinimapPinLogic.lua. The pins are textures of one
-- frame of ours, a child of Minimap without mouse, so clicks and pings on the minimap stay untouched. Nothing
-- of Blizzard's is written: the zoom hook only tells us to lay the pins out again, and in combat only our own
-- frame changes.
--
-- Spots within the near range (setting minimapNear, yards) are drawn as a circle only, without a symbol and
-- without a fill, so the blip the game draws itself on the minimap stays visible; farther spots carry the
-- symbol. The circle is a baked ring texture of the cursor assets, a square frame of four lines without one.
--
-- A source is fn(view, add): view = { map, cont, wx, wy (player in world yards), frame (world frame of the
-- player's map), radius (yards), reach (yards, how far pins are kept) }; add(wx, wy, icon, kind) puts one pin
-- at a world position, with a texture path and a kind ("mining", "herbalism", anything else is drawn plain).
-- add returns false once the cap is reached, so a source can stop. A source may draw its own symbol:
-- add(wx, wy, nil, kind, custom) with custom = { size (px), paint(pin, host, anchor, alpha, scale) -> shown,
-- hide(pin) }; the layer places the anchor and the source owns the textures it makes on the pin.
-- Spots near the player are found in a grid per zone, so a layout looks at the points around the player
-- only, also when the radius reaches into the next zone (the zone frames come from the corners of each map).
local _, ns = ...
local Theme, MI = ns.Theme, ns.MapIcons
local ML, GM = ns.MinimapPinLogic, ns.GatheringMapLogic

local Layer = {}
ns.MinimapLayer = Layer

-- Pin edge in px (setting minimapSize) and opacity in percent (minimapAlpha).
Layer.SIZE_MIN, Layer.SIZE_MAX, Layer.SIZE_DEFAULT = 8, 24, 12
Layer.ALPHA_MIN, Layer.ALPHA_MAX, Layer.ALPHA_DEFAULT = 20, 100, 100
-- Pins pulled onto the edge are drawn this much fainter.
Layer.EDGE_ALPHA = 0.55
-- Most pins at once, and the seconds between two looks at the position.
Layer.MAX_PINS = 150
Layer.TICK = 0.05
-- Seconds before a zone whose frame could not be measured is tried again.
local RETRY = 5
local LEVEL_ABOVE = 2
-- The ring color of a pin per kind.
local RING = { mining = "warning", herbalism = "success" }

local host, pool, used = nil, {}, 0
local gate = ML.NewGate()
local sources, order = {}, {}
local active, hooked, dataReady = false, false, false
local zoneFrames, failedAt = {}, {}
local indexes, icons = {}, {}
-- Counts every change of the data or the filter, so cached grids and icons know when they are stale.
local version = 0
local acc, layouts = 0, 0
local lastView
-- Factor on the pin sizes (set by the farm HUD: the minimap has another effective scale there).
local sizeScale = 1

-- Access --------------------------------------------------------------------------------------------------

-- Secret values are never compared or calculated with.
local function secret(v)
  local check = rawget(_G, "issecretvalue")
  if type(check) ~= "function" then
    return false
  end
  local ok, hidden = pcall(check, v)
  return not ok or hidden == true
end

-- A number the client gave us, nil for anything else, secret values included.
local function readable(v)
  if type(v) ~= "number" or secret(v) then
    return nil
  end
  return ML.finite(v) and v or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a = pcall(fn, ...)
  if ok then
    return a
  end
end

local function flag(name)
  local value = call(rawget(_G, name))
  return not secret(value) and value == true
end

local function clock()
  return readable(call(rawget(_G, "GetTime"))) or 0
end

local function minimap()
  return rawget(_G, "Minimap")
end

-- Safe reads for the modules that work with the minimap beside the layer (Modules/FarmHud.lua).
Layer.Readable, Layer.Call, Layer.Flag, Layer.Secret = readable, call, flag, secret

local function setting(key)
  local gather = ns.Store.get("settings.gather")
  if type(gather) == "table" then
    return gather[key]
  end
end

local bounded = ML.Clamp

function Layer.Enabled()
  return setting("minimap") ~= false
end

function Layer.PinSize()
  return bounded(setting("minimapSize"), Layer.SIZE_MIN, Layer.SIZE_MAX, Layer.SIZE_DEFAULT)
end

function Layer.PinAlpha()
  return bounded(setting("minimapAlpha"), Layer.ALPHA_MIN, Layer.ALPHA_MAX, Layer.ALPHA_DEFAULT) / 100
end

function Layer.EdgeMode()
  return ML.EdgeMode(setting("minimapEdge"))
end

-- Near range in yards (0 = off), circle diameter and line width in px.
function Layer.NearRange()
  return ML.NearRange(setting("minimapNear"))
end

function Layer.RingSize()
  return bounded(setting("minimapRingSize"), ML.RING_SIZE_MIN, ML.RING_SIZE_MAX, ML.RING_SIZE_DEFAULT)
end

function Layer.RingWidth()
  return bounded(setting("minimapRingWidth"), ML.RING_WIDTH_MIN, ML.RING_WIDTH_MAX, ML.RING_WIDTH_DEFAULT)
end

-- Sources --------------------------------------------------------------------------------------------------

-- on() says whether the source wants the layer; without it the source follows the switch of the gathering
-- pins (gather.minimap). The layer runs while one source wants it.
function Layer.RegisterSource(name, fn, on)
  if type(name) ~= "string" or name == "" or type(fn) ~= "function" then
    return false
  end
  if not sources[name] then
    order[#order + 1] = name
  end
  sources[name] = { fn = fn, on = type(on) == "function" and on or Layer.Enabled }
  gate:Invalidate()
  return true
end

local function wanted(name)
  local ok, value = pcall(sources[name].on)
  return ok and value == true
end

-- Does one source want the layer?
function Layer.AnyEnabled()
  for _, name in ipairs(order) do
    if wanted(name) then
      return true
    end
  end
  return false
end

-- World frame of a map, measured once. A map the client cannot convert is tried again after RETRY seconds.
local function zoneFrame(mapId)
  local frame = zoneFrames[mapId]
  if frame then
    return frame
  end
  local now = clock()
  if failedAt[mapId] and now - failedAt[mapId] < RETRY then
    return nil
  end
  frame = ML.ZoneFrame(ns.TravelWalk.GamePos, mapId)
  if frame then
    zoneFrames[mapId], failedAt[mapId] = frame, nil
  else
    failedAt[mapId] = now
  end
  return frame
end
-- Further layer sources project with the same frames.
Layer.ZoneFrame = zoneFrame

-- The gathering data. A load of the data add-on is left to a quiet moment: nothing is loaded in combat.
local function gatherData()
  if not dataReady and flag("InCombatLockdown") then
    return nil
  end
  local data = ns.GatherDataAccess.Get()
  dataReady = data ~= nil
  return data
end

local function zoneIndex(data, mapId, frame)
  local entry = indexes[mapId]
  if entry and entry.version == version and entry.data == data then
    return entry.index
  end
  local set = ns.GatherFilter.ZoneItems(data, mapId)
  local index = ML.BuildIndex(next(set) and GM.Points(data, mapId, set) or {}, frame)
  indexes[mapId] = { version = version, data = data, index = index }
  return index
end

local function iconOf(data, itemId)
  local path = icons[itemId]
  if not path then
    path = ns.GatheringLogic.IconPath(itemId, data.items[itemId])
    icons[itemId] = path
  end
  return path
end

local function gatherSource(view, add)
  local data = gatherData()
  if not (data and type(data.zones) == "table" and type(data.items) == "table") then
    return
  end
  for mapId in pairs(data.zones) do
    local frame = zoneFrame(mapId)
    if ML.Near(frame, view.cont, view.wx, view.wy, view.reach) then
      for _, e in ipairs(ML.Query(zoneIndex(data, mapId, frame), view.wx, view.wy, view.reach)) do
        local item = data.items[e.itemId]
        add(e.wx, e.wy, iconOf(data, e.itemId), type(item) == "table" and item.prof or nil)
      end
    end
  end
end

Layer.RegisterSource("gather", gatherSource)

-- Pins ------------------------------------------------------------------------------------------------------

local function newPin()
  local ring = host:CreateTexture(nil, "BACKGROUND")
  local icon = host:CreateTexture(nil, "ARTWORK")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ring:SetPoint("CENTER", icon, "CENTER")
  local disc = MI.DiscKnown()
  local pin = { ring = ring, icon = icon, disc = disc }
  if disc then
    ring:SetTexture(MI.DISC)
    if host.CreateMaskTexture then
      local mask = host:CreateMaskTexture()
      mask:SetTexture(MI.DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(icon)
      icon:AddMaskTexture(mask)
      pin.mask = mask
    end
  end
  return pin
end

local function paintRing(pin, kind)
  local token = RING[kind] or "textSecondary"
  if pin.disc then
    pin.ring:SetVertexColor(Theme.color(token, 1))
  else
    pin.ring:SetColorTexture(Theme.color(token, 1))
  end
  pin.kind, pin.painted = kind, true
end

-- Path of the ring texture for a circle of `size` px with a line of `width` px, nil without one (then the
-- circle is a square frame). Looked up once per pair.
local ringPaths = {}

local function ringPath(size, width)
  local key = size * 100 + width
  local path = ringPaths[key]
  if path == nil then
    local assets = ns.CursorAssets
    local stem = assets and assets.NearestStroke("circle", width, size)
    path = stem and assets.Path(stem) or false
    ringPaths[key] = path
  end
  return path or nil
end

local function hideCircle(pin)
  if pin.circle then
    pin.circle:Hide()
  end
  if pin.edges then
    for _, edge in ipairs(pin.edges) do
      edge:Hide()
    end
  end
end

-- Hides what a source drew on the pin itself.
local function clearCustom(pin)
  if pin.custom then
    local custom = pin.custom
    pin.custom = nil
    ns.Safe("minimap-custom-hide", custom.hide, pin)
  end
end

-- The four lines of the frame, each anchored to the corners of the square around the pin's center.
local function placeEdges(pin, size, width, token, alpha)
  if not pin.edges then
    pin.edges = {}
    for i = 1, 4 do
      pin.edges[i] = host:CreateTexture(nil, "ARTWORK")
    end
  end
  local h = size / 2
  local top, bottom, left, right = pin.edges[1], pin.edges[2], pin.edges[3], pin.edges[4]
  local anchor = pin.icon
  top:ClearAllPoints()
  top:SetPoint("TOPLEFT", anchor, "CENTER", -h, h)
  top:SetPoint("TOPRIGHT", anchor, "CENTER", h, h)
  top:SetHeight(width)
  bottom:ClearAllPoints()
  bottom:SetPoint("BOTTOMLEFT", anchor, "CENTER", -h, -h)
  bottom:SetPoint("BOTTOMRIGHT", anchor, "CENTER", h, -h)
  bottom:SetHeight(width)
  left:ClearAllPoints()
  left:SetPoint("TOPLEFT", anchor, "CENTER", -h, h)
  left:SetPoint("BOTTOMLEFT", anchor, "CENTER", -h, -h)
  left:SetWidth(width)
  right:ClearAllPoints()
  right:SetPoint("TOPRIGHT", anchor, "CENTER", h, h)
  right:SetPoint("BOTTOMRIGHT", anchor, "CENTER", h, -h)
  right:SetWidth(width)
  for _, edge in ipairs(pin.edges) do
    edge:SetColorTexture(Theme.color(token, 1))
    edge:SetAlpha(alpha)
    edge:Show()
  end
end

local function placeCircle(pin, kind, size, width, alpha)
  local token = RING[kind] or "textSecondary"
  local path = ringPath(size, width)
  if path then
    if pin.edges then
      for _, edge in ipairs(pin.edges) do
        edge:Hide()
      end
    end
    if not pin.circle then
      pin.circle = host:CreateTexture(nil, "ARTWORK")
      pin.circle:SetPoint("CENTER", pin.icon, "CENTER")
    end
    pin.circle:SetTexture(path)
    pin.circle:SetVertexColor(Theme.color(token, 1))
    pin.circle:SetSize(size, size)
    pin.circle:SetAlpha(alpha)
    pin.circle:Show()
  else
    if pin.circle then
      pin.circle:Hide()
    end
    placeEdges(pin, size, width, token, alpha)
  end
  pin.ringPath = path
end

-- One pin at (x, y) from the center of the minimap. style "ring" draws the circle of the view only, "symbol"
-- the symbol with its ring. A custom symbol of a source is drawn by the source; false when it could not
-- (the pin stays hidden and the slot is free again).
local function place(i, x, y, path, kind, alpha, view, style, custom)
  local pin = pool[i]
  if not pin then
    -- A symbol of a source is not worth new textures in combat: its slot waits for the next layout.
    if custom and flag("InCombatLockdown") then
      return false
    end
    pin = newPin()
    pool[i] = pin
  end
  local ring = style == "ring"
  local size = custom and custom.size or ring and view.ringSize or view.size
  pin.icon:ClearAllPoints()
  pin.icon:SetPoint("CENTER", minimap(), "CENTER", x, y)
  pin.icon:SetSize(size, size)
  if custom then
    pin.icon:Hide()
    pin.ring:Hide()
    hideCircle(pin)
    pin.custom = custom
    local shown = custom.paint(pin, host, pin.icon, alpha, sizeScale)
    if not shown then
      clearCustom(pin)
      return false
    end
    style = "custom"
  elseif ring then
    clearCustom(pin)
    pin.icon:Hide()
    pin.ring:Hide()
    placeCircle(pin, kind, size, view.ringWidth, alpha)
  else
    clearCustom(pin)
    hideCircle(pin)
    if not pin.painted or pin.kind ~= kind then
      paintRing(pin, kind)
    end
    pin.ring:SetSize(size + 2, size + 2)
    if pin.path ~= path then
      pin.path = path
      pin.icon:SetTexture(path)
    end
    pin.icon:SetAlpha(alpha)
    pin.ring:SetAlpha(alpha)
    pin.icon:Show()
    pin.ring:Show()
  end
  pin.style, pin.shownKind, pin.size = style, kind, size
  pin.x, pin.y, pin.alpha = x, y, alpha
  return true
end

local function hideFrom(first)
  for i = first, used do
    local pin = pool[i]
    pin.icon:Hide()
    pin.ring:Hide()
    hideCircle(pin)
    clearCustom(pin)
  end
  used = math.min(used, first - 1)
end

local function hideAll()
  hideFrom(1)
  lastView = nil
end

-- A pixel size with the factor of the farm HUD applied, to a tenth of a pixel.
local function scaled(px)
  return math.floor(px * sizeScale * 10 + 0.5) / 10
end

-- Yards from the center of the minimap to its border, and its half width and height in its own units; nil
-- when the client gives no radius or no readable size.
local function readRadius(mm)
  local api = rawget(_G, "C_Minimap")
  local view = readable(type(api) == "table" and call(api.GetViewRadius) or nil)
  local zoom = readable(call(mm.GetZoom, mm))
  local radius = ML.Radius(view, zoom, flag("IsIndoors"))
  local width, height = readable(call(mm.GetWidth, mm)), readable(call(mm.GetHeight, mm))
  if not (radius and width and height and width > 0 and height > 0) then
    return nil
  end
  return radius, width / 2, height / 2
end

-- The state the pins are laid out for, or nil: instance, no position, no facing for a turning minimap, no
-- radius or no readable size of the minimap.
local function readView()
  local mm = minimap()
  if not mm or flag("IsInInstance") then
    return nil
  end
  local map, px, py = ns.Waypoints.PlayerPosition()
  if not map then
    return nil
  end
  local getCVar = rawget(_G, "GetCVar")
  local rotate = call(getCVar, "rotateMinimap") == "1"
  local facing = ns.Waypoints.Facing()
  if rotate and not facing then
    return nil
  end
  local radius, halfW, halfH = readRadius(mm)
  if not radius then
    return nil
  end
  local frame = zoneFrame(map)
  if not frame then
    return nil
  end
  local wx, wy = ML.WorldOf(frame, px, py)
  local mode, size, alpha = Layer.EdgeMode(), scaled(Layer.PinSize()), Layer.PinAlpha()
  local near, ringSize, ringWidth = Layer.NearRange(), scaled(Layer.RingSize()), scaled(Layer.RingWidth())
  local reach = ML.Reach(mode)
  return {
    map = map,
    cont = frame.cont,
    frame = frame,
    wx = wx,
    wy = wy,
    facing = facing,
    rotate = rotate,
    radius = radius,
    reachRatio = reach,
    reach = radius * reach,
    halfW = halfW,
    halfH = halfH,
    size = size,
    alpha = alpha,
    near = near,
    ringSize = ringSize,
    ringWidth = ringWidth,
    state = {
      map = map,
      wx = wx,
      wy = wy,
      facing = rotate and facing or 0,
      rotate = rotate,
      radius = radius,
      halfW = halfW,
      halfH = halfH,
      size = size,
      alpha = alpha,
      near = near,
      ringSize = ringSize,
      ringWidth = ringWidth,
      mode = mode,
      version = version,
    },
  }
end

local function layout(view)
  local n = 0
  local params = {
    facing = view.facing,
    rotate = view.rotate,
    radius = view.radius,
    halfW = view.halfW,
    halfH = view.halfH,
    reach = view.reachRatio,
  }
  local function add(wx, wy, path, kind, custom)
    if n >= Layer.MAX_PINS then
      return false
    end
    params.dN, params.dW = ML.Offset(view.frame, view.wx, view.wy, wx, wy)
    local p = ML.Project(params)
    if p and p.visible then
      n = n + 1
      local alpha = p.clamped and view.alpha * Layer.EDGE_ALPHA or view.alpha
      if place(n, p.x, p.y, path, kind, alpha, view, ML.Style(p.dist, view.near), custom) == false then
        n = n - 1
      end
    end
    return true
  end
  for _, name in ipairs(order) do
    if wanted(name) then
      ns.Safe("minimap-source-" .. name, sources[name].fn, view, add)
    end
  end
  hideFrom(n + 1)
  used = n
  lastView = view
  layouts = layouts + 1
end

-- Looks at the player once and lays the pins out again when the gate says so. force = true lays out whatever
-- the gate says.
function Layer.Update(force)
  if not active then
    return
  end
  local mm = minimap()
  if not mm or not ns.ProtectedAllowed(mm) then
    return
  end
  if force then
    gate:Invalidate()
  end
  local view = readView()
  if not view then
    if used > 0 or lastView then
      hideAll()
    end
    gate:Invalidate()
    return
  end
  if gate:Check(clock(), view.state) then
    layout(view)
  end
end

-- What the layer shows now, for the tests and a diagnosis: { active, pins (shown), layouts (how often the pins
-- were laid out), view (the last one), pool (textures made), hooked }.
function Layer.State()
  return { active = active, pins = used, layouts = layouts, view = lastView, pool = #pool, hooked = hooked }
end

-- The frame that carries the pins, nil until the layer was switched on once.
function Layer.Frame()
  return host
end

-- The shown pins as { x, y (offset from the minimap center), alpha, icon (nil for a circle), kind, style
-- ("symbol", "ring" or "custom"), size (px of the symbol or the circle), custom (the table a source gave
-- add) }.
function Layer.Pins()
  local out = {}
  for i = 1, used do
    local pin = pool[i]
    out[i] = {
      x = pin.x,
      y = pin.y,
      alpha = pin.alpha,
      icon = pin.style == "symbol" and pin.path or nil,
      kind = pin.shownKind,
      style = pin.style,
      size = pin.size,
      custom = pin.style == "custom" and pin.custom or nil,
    }
  end
  return out
end

-- Radius in yards and half width and height of the minimap now, nil when not readable.
function Layer.Radius()
  local mm = minimap()
  if not mm then
    return nil
  end
  return readRadius(mm)
end

-- Sets the factor on the pin sizes (1 = as set). A change lays the pins out again.
function Layer.SetScale(factor)
  factor = ML.Clamp(factor, 0.1, 10, 1)
  if factor ~= sizeScale then
    sizeScale = factor
    gate:Invalidate()
  end
end

-- The next look lays the pins out again (the minimap moved or changed its size).
function Layer.Invalidate()
  gate:Invalidate()
end

-- Puts the pin frame on its level above the minimap again (after the minimap got another parent) and lays the
-- pins out again.
function Layer.Refit()
  local mm = minimap()
  if host and mm then
    local level = readable(call(mm.GetFrameLevel, mm))
    if level then
      host:SetFrameLevel(level + LEVEL_ABOVE)
    end
  end
  gate:Invalidate()
end

-- Forgets the measured frames, grids and icons (tests, a data change).
function Layer.Reset()
  zoneFrames, failedAt, indexes, icons = {}, {}, {}, {}
  dataReady = false
  version = version + 1
  gate:Invalidate()
end

-- Switch ------------------------------------------------------------------------------------------------------

local function onUpdate(_, dt)
  acc = acc + (tonumber(dt) or 0)
  if acc < Layer.TICK then
    return
  end
  acc = 0
  ns.Safe("minimap-layer", Layer.Update)
end

-- A secure hook only tells the layer that the zoom changed. It reads nothing of the call and runs no
-- Blizzard code of ours inside it.
local function hookZoom(mm)
  local hook = rawget(_G, "hooksecurefunc")
  if hooked or type(hook) ~= "function" or type(mm.SetZoom) ~= "function" then
    return
  end
  hooked = pcall(hook, mm, "SetZoom", function()
    gate:Invalidate()
  end)
end

local function ensureHost(mm)
  if host then
    return host
  end
  host = CreateFrame("Frame", nil, mm)
  host:SetAllPoints(mm)
  host:EnableMouse(false)
  local level = readable(call(mm.GetFrameLevel, mm))
  if level then
    host:SetFrameLevel(level + LEVEL_ABOVE)
  end
  host:SetScript("OnUpdate", onUpdate)
  host:Hide()
  return host
end

-- Brings the layer in line with the switches of its sources (gather.minimap for the gathering pins). Waits
-- for the end of the combat when the minimap is restricted.
function Layer.Apply()
  local mm = minimap()
  if not mm or not ns.ProtectedAllowed(mm) then
    return
  end
  if Layer.AnyEnabled() then
    ensureHost(mm)
    hookZoom(mm)
    active = true
    gate:Invalidate()
    host:Show()
  else
    active = false
    if host then
      host:Hide()
    end
    hideAll()
  end
end

local function refresh()
  version = version + 1
  gate:Invalidate()
end

ns.On("PLAYER_LOGIN", function()
  ns.Debounce("minimap-layer-apply", 2, Layer.Apply)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  Layer.Apply()
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  gate:Invalidate()
end)

ns.On("ZONE_CHANGED_NEW_AREA", function()
  gate:Invalidate()
end)

ns.On("FG_GATHER_FILTER_CHANGED", refresh)
ns.On("FG_GATHER_SELECTION", refresh)
ns.On("FG_PACKAGE_CHANGED", refresh)

local OWN = {
  ["settings.gather.minimap"] = true,
  ["settings.gather.minimapEdge"] = true,
  ["settings.gather.minimapSize"] = true,
  ["settings.gather.minimapAlpha"] = true,
  ["settings.gather.minimapNear"] = true,
  ["settings.gather.minimapRingSize"] = true,
  ["settings.gather.minimapRingWidth"] = true,
}

ns.On("FG_SETTING_CHANGED", function(_, path)
  if not OWN[path] then
    return
  end
  if path == "settings.gather.minimap" then
    Layer.Apply()
  end
  gate:Invalidate()
end)
