-- Opacity of the Blizzard windows handled by Modules/FrameTweaks.lua. Two modes:
--   background (default): the background of the window fades, text, icons, buttons, slots and models
--     keep their look. A breadth first scan through the child frames (depth and count are capped, never
--     into our own frames or other windows) collects the NineSlice frames and the textures that carry
--     the background: BACKGROUND and BORDER textures, large ones of any layer, the textures of frames
--     named like background art (Inset, Bg, Parchment ...). The gamepad focus glow (FrameGlow, atlas
--     "gamepad"/"-focus") is never one. Texture rules: FrameTweaksLogic.Classify.
--   window: the whole window fades, never below FrameTweaksLogic.WINDOW_ALPHA_MIN percent.
-- Saved per window as frames[name].alpha (percent, 100 = the client's look, not saved) and
-- frames[name].alphaMode, default settings.frameAlphaMode. The window is never hidden.
-- The client resets alphas when a window shows, lays out or turns a page (new pooled textures), so a
-- change on a child frame scans again after a short delay and sets the value once more. The scan runs
-- when the window attaches, shows, a value is set and on such a change, never per frame.
-- In combat a window the tweaks must not touch waits for PLAYER_REGEN_ENABLED.
local _, ns = ...
local FL = ns.FrameTweaksLogic

local A = {}
ns.FrameTweaksAlpha = A

local weak = { __mode = "k" }
local DEBOUNCE, RESCAN_GAP, MAX_FIELDS, TOP, TEXTURE_TAIL = 0.1, 0.25, 300, 10, 40

local windows = {} -- name -> window frame
local found = {} -- name -> parts that carry the background
local scannedAt = {} -- name -> time of the last scan
local original = setmetatable({}, weak) -- part -> alpha the client gave it
local applied = {} -- name -> set of parts that differ from the client's alpha
local pending = {} -- name -> true while a change waits for the end of combat
local scheduled = {} -- name -> true while a delayed scan is queued
local hookedFrames = setmetatable({}, weak) -- child frame -> true once its hooks are in
local panelHooked = false

local function guard(fn, ...)
  return pcall(fn, ...)
end

local function settings()
  return ns.db and ns.db.settings
end

local function enabled()
  local s = settings()
  return s ~= nil and s.frameTweaks ~= false
end

local function notify(name)
  local bar = ns.FrameTweaksBar
  if bar and type(bar.Refresh) == "function" then
    pcall(bar.Refresh, name)
  end
end

local function method(obj, name, ...)
  local fn = type(obj) == "table" and obj[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, obj, ...)
  return ok and value or nil
end

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

-- Scan ---------------------------------------------------------------------------------------------

local function listOf(obj, name)
  local fn = type(obj) == "table" and obj[name]
  if type(fn) ~= "function" then
    return {}
  end
  local ok, list = pcall(function()
    return { fn(obj) }
  end)
  return ok and list or {}
end

-- Field names under which the holder keeps its children and regions (unnamed art has only these).
local function keysOf(holder)
  local keys = {}
  pcall(function()
    local n = 0
    for key, value in pairs(holder) do
      n = n + 1
      if n > MAX_FIELDS then
        break
      end
      if type(key) == "string" and type(value) == "table" and keys[value] == nil and key:sub(1, 1) ~= "_" then
        keys[value] = key
      end
    end
  end)
  return keys
end

local function labelOf(obj, key)
  local name = method(obj, "GetName")
  if type(name) == "string" and name ~= "" then
    return name
  end
  return key
end

local function textureText(region)
  local atlas = method(region, "GetAtlas")
  local value = (type(atlas) == "string" and atlas ~= "") and ("atlas:" .. atlas) or method(region, "GetTexture")
  if value == nil then
    return nil
  end
  value = tostring(value)
  return #value > TEXTURE_TAIL and ("..." .. value:sub(-TEXTURE_TAIL)) or value
end

local function size(obj, name)
  local v = method(obj, name)
  return type(v) == "number" and v == v and v or 0
end

local function add(c, part)
  if type(part) == "table" and not c.seen[part] and type(part.SetAlpha) == "function" then
    c.seen[part] = true
    c.res.list[#c.res.list + 1] = part
    return true
  end
  return false
end

-- Sorts a texture into the background list or the skipped ones.
local function record(c, item, kind, key, region)
  local w, h = size(region, "GetWidth"), size(region, "GetHeight")
  local layer = method(region, "GetDrawLayer")
  local hit, large, reason = FL.Classify({
    layer = layer,
    w = w,
    h = h,
    windowArea = c.area,
    parentKind = kind,
    parentLabel = item.label,
    name = key or labelOf(region),
    atlas = method(region, "GetAtlas"),
    hinted = item.hinted,
  })
  local res = c.res
  if hit and not add(c, region) then
    return
  end
  if hit then
    res.nHits = res.nHits + 1
    res.nLarge = res.nLarge + (large and 1 or 0)
  else
    res.nSkipped = res.nSkipped + 1
  end
  if c.detail then
    local into = hit and res.hits or res.skipped
    into[#into + 1] = {
      i = #into + 1,
      area = w * h,
      w = w,
      h = h,
      layer = layer or "?",
      parent = item.path,
      tex = textureText(region),
      reason = reason,
    }
  end
end

-- Frames the scan never enters: forbidden, ours, and other windows (they have their own scan).
local function foreign(c, child, name)
  if c.attached[child] or method(child, "IsForbidden") == true then
    return true
  end
  return type(name) == "string" and (FL.Excluded(name) or FL.Listed(name))
end

local function inert(kind)
  return kind:find("Button", 1, true) ~= nil
    or kind:find("Model", 1, true) ~= nil
    or kind == "EditBox"
    or kind == "Slider"
end

local function visit(c, item)
  local frame = item.frame
  local kind = method(frame, "GetObjectType") or "Frame"
  local keys = keysOf(frame)
  for _, region in ipairs(listOf(frame, "GetRegions")) do
    if method(region, "GetObjectType") == "Texture" then
      record(c, item, kind, keys[region], region)
    end
  end
  if item.depth > 0 and item.depth <= FL.SCAN_HOOK_DEPTH and #c.res.hooks < FL.SCAN_MAX_HOOKS and not inert(kind) then
    c.res.hooks[#c.res.hooks + 1] = frame
  end
  if item.depth >= FL.SCAN_DEPTH or inert(kind) then
    return
  end
  for _, child in ipairs(listOf(frame, "GetChildren")) do
    if type(child) == "table" and not c.visited[child] then
      c.visited[child] = true
      local key = keys[child]
      local name = method(child, "GetName")
      if not foreign(c, child, name) then
        local label = labelOf(child, key)
        if key == "NineSlice" or name == "NineSlice" then
          -- The frame art as a whole: fading the frame fades its pieces.
          if add(c, child) then
            c.res.nine[#c.res.nine + 1] = child
            c.res.nHits = c.res.nHits + 1
            if c.detail then
              local w, h = size(child, "GetWidth"), size(child, "GetHeight")
              c.res.hits[#c.res.hits + 1] =
                { i = #c.res.hits + 1, area = w * h, w = w, h = h, layer = "NineSlice", parent = item.path }
            end
          end
        else
          c.queue[#c.queue + 1] = {
            frame = child,
            depth = item.depth + 1,
            path = item.path .. "." .. tostring(label or "?"),
            label = label,
            hinted = FL.BackgroundName(key) or FL.BackgroundName(name),
          }
        end
      end
    end
  end
end

-- detail: also keep one record per texture (for A.Survey). Nothing is written or hooked here.
local function scan(frame, detail)
  local res = {
    list = {},
    nine = {},
    hooks = {},
    nHits = 0,
    nLarge = 0,
    nSkipped = 0,
    frames = 0,
    hits = detail and {} or nil,
    skipped = detail and {} or nil,
  }
  local attached = {}
  for _, window in pairs(windows) do
    attached[window] = true
  end
  local c = {
    res = res,
    detail = detail,
    seen = {},
    visited = { [frame] = true },
    attached = attached,
    area = size(frame, "GetWidth") * size(frame, "GetHeight"),
    queue = { { frame = frame, depth = 0, path = labelOf(frame) or "?", label = labelOf(frame) } },
  }
  local head = 1
  while c.queue[head] and res.frames < FL.SCAN_MAX_FRAMES do
    res.frames = res.frames + 1
    visit(c, c.queue[head])
    head = head + 1
  end
  res.capped = c.queue[head] ~= nil
  return res
end

local function top(list)
  table.sort(list, function(a, b)
    if a.area ~= b.area then
      return a.area > b.area
    end
    return a.i < b.i
  end)
  local out = {}
  for i = 1, math.min(TOP, #list) do
    out[i] = list[i]
  end
  return out
end

-- Test seam: what the scan finds in a window, counts and the largest textures taken and skipped (w, h, layer,
-- parent, tex, reason). Read only.
function A.Survey(frame)
  local res = scan(frame, true)
  return {
    hits = res.nHits,
    large = res.nLarge,
    skipped = res.nSkipped,
    frames = res.frames,
    capped = res.capped,
    top = top(res.hits),
    skippedTop = top(res.skipped),
  }
end

-- Hooks ----------------------------------------------------------------------------------------------

-- A child frame showed or turned a page: scan again soon (once for a burst) and set the value.
function A.Changed(name)
  if not windows[name] or scheduled[name] then
    return
  end
  if not (applied[name] or A.Get(name) < FL.ALPHA_MAX) then
    return
  end
  scheduled[name] = true
  local function run()
    scheduled[name] = nil
    guard(function()
      A.Rescan(name)
      A.Apply(name)
    end)
  end
  local timer = rawget(_G, "C_Timer")
  if not (type(timer) == "table" and type(timer.After) == "function" and pcall(timer.After, DEBOUNCE, run)) then
    run()
  end
end

local function hookFrame(frame, fn)
  if hookedFrames[frame] then
    return
  end
  hookedFrames[frame] = true
  pcall(frame.HookScript, frame, "OnShow", fn)
  for _, key in ipairs(FL.REFRESH_METHODS) do
    if type(frame[key]) == "function" then
      pcall(hooksecurefunc, frame, key, fn)
    end
  end
end

local function hookParts(name, res)
  local function changed()
    guard(A.Changed, name)
  end
  for _, frame in ipairs(res.hooks) do
    hookFrame(frame, changed)
  end
  for _, nine in ipairs(res.nine) do
    if not hookedFrames[nine] and type(nine.Layout) == "function" then
      hookedFrames[nine] = true
      pcall(hooksecurefunc, nine, "Layout", function()
        guard(A.Apply, name)
      end)
    end
  end
end

-- Looks at the window's build again (it may have changed since the last look).
function A.Rescan(name)
  local frame = windows[name]
  if not frame then
    return
  end
  local ok, res = pcall(scan, frame, false)
  found[name] = ok and res.list or {}
  scannedAt[name] = now()
  if ok then
    guard(hookParts, name, res)
  end
end

-- Mode and value ---------------------------------------------------------------------------------------

-- The mode of a window: its own choice, else the setting, else the background.
function A.Mode(name)
  local raw = ns.FrameTweaks.SavedFrames()[name]
  local s = settings()
  return (type(raw) == "table" and FL.CleanMode(raw.alphaMode)) or FL.CleanMode(s and s.frameAlphaMode) or "background"
end

-- Can the opacity mode of the window be chosen?
function A.ModeAvailable(name)
  return windows[name] ~= nil and enabled() and ns.FrameTweaks.FeatureOn(name, "alpha")
end

-- Does the window have something to fade? Whole window mode always has.
function A.Available(name)
  if not (windows[name] and ns.FrameTweaks.FeatureOn(name, "alpha")) then
    return false
  end
  local list = found[name]
  return A.Mode(name) == "window" or (list ~= nil and #list > 0)
end

-- Saved opacity in percent.
function A.Get(name)
  local raw = ns.FrameTweaks.SavedFrames()[name]
  return type(raw) == "table" and FL.CleanAlpha(raw.alpha) or FL.ALPHA_MAX
end

-- Writes one field of the window's entry; nil removes it, an empty entry goes away.
local function put(name, field, value)
  local entries = ns.FrameTweaks.SavedFrames()
  local raw = entries[name]
  if value == nil then
    if type(raw) == "table" then
      raw[field] = nil
      if next(raw) == nil then
        entries[name] = nil
      end
    end
  elseif type(raw) == "table" then
    raw[field] = value
  else
    entries[name] = { [field] = value }
  end
end

local function putBack(part)
  pcall(part.SetAlpha, part, original[part] or 1)
  original[part] = nil
end

-- Puts the parts at the saved opacity (a part's own alpha times the percent) and every part that
-- is no longer wanted back to the client's alpha.
function A.Apply(name)
  local frame, list = windows[name], found[name]
  if not (frame and list and enabled()) then
    return
  end
  -- Off for this window: back to the client's look.
  local value = ns.FrameTweaks.FeatureOn(name, "alpha") and A.Get(name) or FL.ALPHA_MAX
  local current = applied[name]
  if value >= FL.ALPHA_MAX and not current then
    pending[name] = nil
    return
  end
  if not ns.FrameTweaks.CanTouch(name) then
    pending[name] = true
    return
  end
  pending[name] = nil
  local mode = A.Mode(name)
  local targets = {}
  if value < FL.ALPHA_MAX then
    targets = mode == "window" and { frame } or list
  end
  local want = setmetatable({}, weak)
  for _, part in ipairs(targets) do
    want[part] = true
  end
  for part in pairs(current or {}) do
    if not want[part] then
      putBack(part)
    end
  end
  local factor = FL.EffectiveAlpha(mode, value) / 100
  for _, part in ipairs(targets) do
    if original[part] == nil then
      original[part] = method(part, "GetAlpha") or 1
    end
    pcall(part.SetAlpha, part, original[part] * factor)
  end
  applied[name] = next(want) ~= nil and want or nil
end

-- Sets the opacity (0 to 100). Returns the value and whether it waits for the end of combat, nil
-- when the window has nothing to fade.
function A.Set(name, value)
  local v = FL.CleanAlpha(value)
  if not (v and windows[name] and enabled()) then
    return nil
  end
  local list = found[name]
  if not list or #list == 0 or now() - (scannedAt[name] or -1) > RESCAN_GAP then
    A.Rescan(name)
  end
  if not A.Available(name) then
    return nil
  end
  put(name, "alpha", v < FL.ALPHA_MAX and v or nil)
  A.Apply(name)
  notify(name)
  return v, pending[name] == true
end

-- Chooses the mode of one window (kept in its entry unless it equals the setting). Returns the
-- mode and whether the change waits for the end of combat.
function A.SetMode(name, mode)
  local m = FL.CleanMode(mode)
  if not (m and A.ModeAvailable(name)) then
    return nil
  end
  local s = settings()
  put(name, "alphaMode", m ~= (FL.CleanMode(s and s.frameAlphaMode) or "background") and m or nil)
  A.Apply(name)
  notify(name)
  return m, pending[name] == true
end

-- The settings page's choice for one window: nil goes back to the setting, a mode is kept even when
-- it equals the setting (SetMode drops that). Works for windows that are not loaded yet.
function A.ChooseMode(name, mode)
  local m = FL.CleanMode(mode)
  if type(name) ~= "string" or name == "" or (mode ~= nil and not m) then
    return false
  end
  put(name, "alphaMode", m)
  A.Apply(name)
  notify(name)
  return true
end

function A.ToggleMode(name)
  return A.SetMode(name, A.Mode(name) == "window" and "background" or "window")
end

local function applyAll()
  for name in pairs(windows) do
    if applied[name] or A.Get(name) < FL.ALPHA_MAX then
      guard(A.Apply, name)
    end
  end
end

-- Every window again (a limit, a switch or the saved values changed).
function A.ApplyAll()
  for name in pairs(windows) do
    guard(A.Apply, name)
  end
end

-- Called by FrameTweaks for every window it handles, once.
function A.Attach(name, frame)
  if windows[name] == frame then
    return
  end
  windows[name] = frame
  A.Rescan(name)
  pcall(frame.HookScript, frame, "OnShow", function()
    A.Rescan(name)
    A.Apply(name)
    guard(A.Changed, name)
  end)
  if not panelHooked and type(hooksecurefunc) == "function" then
    panelHooked = pcall(hooksecurefunc, "UpdateUIPanelPositions", function()
      guard(applyAll)
    end)
  end
  A.Apply(name)
end

ns.On("PLAYER_REGEN_ENABLED", function()
  local names = {}
  for name in pairs(pending) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    guard(A.Rescan, name)
    guard(A.Apply, name)
    notify(name)
  end
end)
