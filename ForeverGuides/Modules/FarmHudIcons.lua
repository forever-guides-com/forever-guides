-- Farm HUD: hides the minimap buttons of other add-ons while the HUD holds the minimap, and shows exactly the
-- ones it hid afterwards. Nothing is found by add-on name: a frame counts when it is a child of the minimap (or
-- of its backdrop or cluster), when it is anchored to one of them (the ring of buttons around the minimap), or
-- when LibDBIcon owns it. Only Show and Hide are used, never a parent or an anchor.
local _, ns = ...
local Layer = ns.MinimapLayer

local Icons = {}
ns.FarmHudIcons = Icons

-- Seconds between two looks at the frames already hidden (add-ons show their buttons again) and between two
-- searches for new ones (the search walks every frame of the game).
local RECHECK, DISCOVER = 0.5, 2

-- Game frames that stay: the minimap itself, its ping, the compass and the buffs and trackers that hang near the
-- cluster. Every other frame on the minimap is hidden, the game's own buttons (tracking, mail, zoom, zone text,
-- clock, queue, difficulty) included, because the HUD fills the screen and shows its own coordinates.
local STAY = {
  Minimap = true,
  MinimapBackdrop = true,
  MinimapCluster = true,
  MiniMapPing = true,
  MinimapPing = true,
  MinimapCompassTexture = true,
  BuffFrame = true,
  TemporaryEnchantFrame = true,
  DurabilityFrame = true,
  QuestWatchFrame = true,
  WatchFrame = true,
  ObjectiveTrackerFrame = true,
}
local KINDS = { Button = true, CheckButton = true, Frame = true }
local HOPS, ICON_MAX, POINTS_MAX = 3, 64, 16

local hidden, hiddenSet = {}, {}
local sinceRecheck, sinceDiscover = 0, 0

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a = pcall(fn, ...)
  local secret = rawget(_G, "issecretvalue")
  if ok and type(secret) == "function" and secret(a) then
    return nil
  end
  return ok and a or nil
end

-- A number the game gave us, or nil: other add-ons' frames and secret values answer with anything.
local function num(v)
  local secret = rawget(_G, "issecretvalue")
  if type(secret) == "function" and secret(v) then
    return nil
  end
  if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
    return v
  end
  return nil
end

local function roots()
  local out, set = {}, {}
  for _, name in ipairs({ "Minimap", "MinimapBackdrop", "MinimapCluster" }) do
    local f = rawget(_G, name)
    if type(f) == "table" then
      out[#out + 1] = f
      set[f] = true
    end
  end
  return out, set
end

local function ownFrame()
  return Layer and Layer.Frame and Layer.Frame() or nil
end

-- A small shown texture with a file on the minimap itself: some add-ons draw their icon there.
local function iconTexture(t)
  local w, h = num(call(t.GetWidth, t)), num(call(t.GetHeight, t))
  return call(t.GetTexture, t) ~= nil
    and w ~= nil
    and h ~= nil
    and w > 0
    and h > 0
    and w < ICON_MAX
    and h < ICON_MAX
end

-- Why a frame stays as it is, or nil when it is a candidate to hide (combat is looked at separately).
local function kept(f, rootSet, own)
  if type(f) ~= "table" then
    return "not a frame"
  end
  if rootSet[f] or f == own or f.fgKeep then
    return "own or marked fgKeep"
  end
  local name = call(f.GetName, f)
  if type(name) == "string" and STAY[name] then
    return "kept by name"
  end
  local kind = call(f.GetObjectType, f)
  if kind == "Texture" then
    if not iconTexture(f) then
      return "not an icon texture"
    end
  elseif not KINDS[kind] then
    return "not a candidate type"
  end
  if call(f.IsForbidden, f) then
    return "forbidden"
  end
  if call(f.IsShown, f) ~= true then
    return "already hidden"
  end
  return nil
end

-- True when a point of the frame is one of the roots, or a frame that reaches one in fewer hops. The HUD's own
-- frames end the walk: what hangs on the pin layer is ours.
local function reaches(f, rootSet, own, hops)
  local n = math.min(num(call(f.GetNumPoints, f)) or 0, POINTS_MAX)
  for i = 1, n do
    local ok, _, rel = pcall(f.GetPoint, f, i)
    if ok and type(rel) == "table" and rel ~= own and not rel.fgKeep then
      if rootSet[rel] or (hops > 1 and reaches(rel, rootSet, own, hops - 1)) then
        return true
      end
    end
  end
  return false
end

-- A frame the game would block in combat is left for the next look.
local function touchable(f)
  if call(f.IsProtected, f) and call(rawget(_G, "InCombatLockdown")) then
    return false
  end
  return ns.ProtectedAllowed(f)
end

-- A frame hidden before stays as it is (it is not a candidate); one we hid and an add-on showed again is hidden again.
local function take(f)
  if not touchable(f) then
    return
  end
  if pcall(f.Hide, f) and not hiddenSet[f] then
    hiddenSet[f] = true
    hidden[#hidden + 1] = f
  end
end

-- Every shown frame or small texture of other add-ons that hangs on the minimap, hidden and remembered.
function Icons.Sweep()
  local list, rootSet = roots()
  local own = ownFrame()
  local found = {}
  for _, root in ipairs(list) do
    local ok, children = pcall(function()
      return { root:GetChildren() }
    end)
    for _, child in ipairs(ok and children or {}) do
      found[#found + 1] = child
    end
  end
  local mm = rawget(_G, "Minimap")
  if type(mm) == "table" then
    local ok, regions = pcall(function()
      return { mm:GetRegions() }
    end)
    for _, region in ipairs(ok and regions or {}) do
      found[#found + 1] = region
    end
  end
  local enumerate = rawget(_G, "EnumerateFrames")
  if type(enumerate) == "function" then
    local f = call(enumerate)
    while f do
      local ok, hangs = pcall(function()
        return call(f.IsShown, f) == true and reaches(f, rootSet, own, HOPS)
      end)
      if ok and hangs then
        found[#found + 1] = f
      end
      f = call(enumerate, f)
    end
  end
  local dbicon = call(rawget(_G, "LibStub"), "LibDBIcon-1.0", true)
  if type(dbicon) == "table" and type(dbicon.GetButtonList) == "function" then
    for _, name in ipairs(call(dbicon.GetButtonList, dbicon) or {}) do
      found[#found + 1] = call(dbicon.GetMinimapButton, dbicon, name)
    end
  end
  for _, f in ipairs(found) do
    -- One odd frame never aborts the sweep.
    pcall(function()
      if kept(f, rootSet, own) == nil then
        take(f)
      end
    end)
  end
end

-- For /fg dev minimapicons: the frame is a child of a root or reaches one by an anchor chain of up to three hops.
function Icons.Hangs(f)
  local _, rootSet = roots()
  local parent = call(f.GetParent, f)
  return (parent ~= nil and rootSet[parent] == true) or reaches(f, rootSet, ownFrame(), HOPS)
end

-- What the sweep does with the frame: true for "hidden", else false and the reason it stays.
function Icons.Verdict(f)
  local _, rootSet = roots()
  local reason = kept(f, rootSet, ownFrame())
  if reason then
    return false, reason
  end
  if not touchable(f) then
    return false, "protected in combat"
  end
  return true
end

-- Small textures drawn straight on the minimap, shown ones only (for /fg dev minimapicons).
function Icons.Textures()
  local out = {}
  local mm = rawget(_G, "Minimap")
  local ok, regions = pcall(function()
    return { mm:GetRegions() }
  end)
  for _, t in ipairs(ok and regions or {}) do
    if call(t.GetObjectType, t) == "Texture" and call(t.IsShown, t) == true then
      out[#out + 1] = t
    end
  end
  return out
end

-- Hides again what an add-on showed, and now and then looks for new frames.
function Icons.Tick(dt)
  dt = tonumber(dt) or 0
  sinceRecheck, sinceDiscover = sinceRecheck + dt, sinceDiscover + dt
  if sinceDiscover >= DISCOVER then
    sinceRecheck, sinceDiscover = 0, 0
    Icons.Sweep()
  elseif sinceRecheck >= RECHECK then
    sinceRecheck = 0
    for _, f in ipairs(hidden) do
      if call(f.IsShown, f) == true and touchable(f) then
        pcall(f.Hide, f)
      end
    end
  end
end

-- Shows what was hidden, in the order it was hidden. Idempotent.
function Icons.Restore()
  local list = hidden
  hidden, hiddenSet = {}, {}
  sinceRecheck, sinceDiscover = 0, 0
  for _, f in ipairs(list) do
    pcall(f.Show, f)
  end
end

-- How many frames are hidden now, for the tests.
function Icons.Count()
  return #hidden
end
