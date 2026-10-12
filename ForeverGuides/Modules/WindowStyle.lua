-- Look of the floating windows (note windows now, drawing windows next): background
-- color, opacity (0 = fully transparent), auto-hiding chrome and a text shadow policy
-- for readability on a transparent window. Pure helpers plus one applier.
--
--   style = { bg = "rrggbb", alpha = 0..1, autoHide = bool, textShadow = "auto"|"on"|"off",
--             border = bool (nil counts as true) }
--   WS.Defaults(kind)            global defaults from the settings ("note" or "drawing")
--   WS.Resolve(kind, per)        per-window overrides (bg, alpha, autoHide, textShadow, border; nil
--                                 = inherit) over the global defaults, every field validated
--   WS.Apply(frame, style, parts)
--     parts.bg      textures that get the background color and the window opacity. In the skin
--                   "forever" the shell hides them behind its stone while the color is the default.
--     parts.bars    textures with their own color (title strip) that fade with the opacity
--     parts.border  W.Border object: its alpha follows the opacity, gone at 0 unless hovered.
--                   The border of the window shell (UI/WindowShell.lua) is the exception: with
--                   style.border on it never drops below WS.BORDER_FLOOR.
--     parts.shadow  frame of the shell's drop shadow, shown in full while the border is kept
--     parts.chrome  frames/regions that fade out with auto-hide (title bar, buttons, grip,
--                   menu, toolbar, status bar). Never Hide()n: they keep their hit area.
--     parts.busy    function() -> true while a menu, popup or dialog of the window is open
--     parts.focus   EditBoxes in the chrome: no hiding while one has focus
--   WS.Hold(frame, key, on)      keeps the chrome visible (dragging, resizing)
--   WS.TextShadow(style)         whether the note text gets a shadow
-- The content (text, drawing) is simply not listed in `parts`, so it never fades.
local _, ns = ...
local U = ns.U

local WS = {}
ns.WindowStyle = WS

WS.FALLBACK = { bg = "1a1a1a", alpha = 0.92, autoHide = false }
WS.SHADOW_MODES = { "auto", "on", "off" }
-- "auto" shadows the text when the window is more transparent than this.
WS.SHADOW_BELOW = 0.45
WS.FADE_TIME, WS.HIDE_DELAY = 0.12, 0.4
-- Settings key prefix per window kind: <prefix>Bg, <prefix>Alpha, <prefix>AutoHide.
WS.PREFIX = { note = "noteWindow", drawing = "drawingWindow" }
WS.SHADOW_KEY = "windowTextShadow"
-- "Always show the window frame" (default on): a shell border keeps this opacity at least.
WS.BORDER_KEY = "windowBorderAlways"
WS.BORDER_FLOOR = 0.6

-- Validation ------------------------------------------------------------------------

function WS.cleanHex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

function WS.cleanAlpha(v, default)
  v = tonumber(v)
  if not v or v ~= v then
    return default
  end
  return U.round(U.clamp(v, 0, 1), 0.01)
end

function WS.cleanShadow(v)
  for _, mode in ipairs(WS.SHADOW_MODES) do
    if v == mode then
      return v
    end
  end
  return "auto"
end

-- Defaults and resolving --------------------------------------------------------------

function WS.Defaults(kind)
  local s = (ns.db and ns.db.settings) or {}
  local prefix = WS.PREFIX[kind] or WS.PREFIX.note
  return {
    bg = WS.cleanHex(s[prefix .. "Bg"], WS.FALLBACK.bg),
    alpha = WS.cleanAlpha(s[prefix .. "Alpha"], WS.FALLBACK.alpha),
    autoHide = s[prefix .. "AutoHide"] == true,
    textShadow = WS.cleanShadow(s[WS.SHADOW_KEY]),
    border = s[WS.BORDER_KEY] ~= false,
  }
end

function WS.Resolve(kind, per)
  local style = WS.Defaults(kind)
  if type(per) == "table" then
    style.bg = WS.cleanHex(per.bg, style.bg)
    style.alpha = WS.cleanAlpha(per.alpha, style.alpha)
    if type(per.autoHide) == "boolean" then
      style.autoHide = per.autoHide
    end
    if per.textShadow ~= nil then
      style.textShadow = WS.cleanShadow(per.textShadow)
    end
    if type(per.border) == "boolean" then
      style.border = per.border
    end
  end
  return style
end

-- Stores a window's look as the global default of its kind (three settings, one event each).
function WS.SaveDefault(kind, style)
  local prefix = WS.PREFIX[kind] or WS.PREFIX.note
  ns.Store.set("settings." .. prefix .. "Bg", WS.cleanHex(style.bg, WS.FALLBACK.bg))
  ns.Store.set("settings." .. prefix .. "Alpha", WS.cleanAlpha(style.alpha, WS.FALLBACK.alpha))
  ns.Store.set("settings." .. prefix .. "AutoHide", style.autoHide == true)
end

-- True when a FG_SETTING_CHANGED path changes how windows of `kind` look.
function WS.AffectsKind(path, kind)
  if type(path) ~= "string" then
    return false
  end
  local prefix = "settings." .. (WS.PREFIX[kind] or WS.PREFIX.note)
  return path:sub(1, #prefix) == prefix or path == "settings." .. WS.SHADOW_KEY or path == "settings." .. WS.BORDER_KEY
end

-- Text readability -----------------------------------------------------------------------

function WS.TextShadow(style)
  if style.textShadow == "on" then
    return true
  elseif style.textShadow == "off" then
    return false
  end
  return style.alpha < WS.SHADOW_BELOW
end

-- A dark shadow under light text, a light one under dark text (otherwise it vanishes).
function WS.ShadowColor(r, g, b)
  if 0.299 * r + 0.587 * g + 0.114 * b < 0.4 then
    return 1, 1, 1, 0.85
  end
  return 0, 0, 0, 0.9
end

function WS.ApplyShadow(fs, on, r, g, b)
  if on then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(WS.ShadowColor(r or 1, g or 1, b or 1))
  else
    fs:SetShadowOffset(0, 0)
  end
end

-- Share of the opacity the edge elements (border, title strip) keep: full from 50 % up.
function WS.Edge(alpha)
  return math.min(1, alpha * 2)
end

-- True when `region` is `frame` or one of its descendants.
function WS.IsInside(region, frame)
  local node = region
  for _ = 1, 24 do
    if node == nil then
      return false
    elseif node == frame then
      return true
    end
    node = ns.SafeParent(node)
  end
  return false
end

-- Applier -----------------------------------------------------------------------------------

local states = setmetatable({}, { __mode = "k" })

function WS.State(frame)
  return states[frame]
end

local function mouseOver(o)
  if o.IsMouseOver then
    return o:IsMouseOver() == true
  end
  local legacy = rawget(_G, "MouseIsOver")
  return legacy ~= nil and legacy(o) == true
end

local function paintChrome(st)
  for _, o in ipairs(st.parts.chrome or {}) do
    o:SetAlpha(st.chrome)
  end
end

local function paintBorder(st)
  local border = st.parts.border
  if not border then
    return
  end
  -- A shell border states its own base (it changes with the active window); a plain
  -- W.Border keeps the alpha it had when the style was first applied.
  local base = border.base or st.borderBase or border.alpha or 0.4
  st.borderBase = base
  local a = base * WS.Edge(st.style.alpha)
  if st.style.alpha <= 0 and st.hover then
    a = base * 0.5
  end
  local kept = border.shell and st.style.border ~= false
  if kept then
    a = math.max(a, math.min(base, WS.BORDER_FLOOR))
  end
  border.set(border.colorName, a)
  if st.parts.shadow then
    st.parts.shadow:SetAlpha(kept and 1 or WS.Edge(st.style.alpha))
  end
end

-- Paints the border again after its base changed (window became active or inactive).
function WS.Repaint(frame)
  local st = states[frame]
  if st and st.parts then
    paintBorder(st)
  end
end

local function inside(st)
  if mouseOver(st.frame) then
    return true
  end
  -- A chrome frame may reach past the window frame.
  for _, o in ipairs(st.parts.chrome or {}) do
    if o.IsMouseOver and o:IsShown() and o:IsMouseOver() then
      return true
    end
  end
  return false
end

local function busy(st)
  for _, on in pairs(st.holds) do
    if on then
      return true
    end
  end
  local fn = st.parts.busy
  if fn then
    local ok, v = pcall(fn)
    if ok and v then
      return true
    end
  end
  for _, eb in ipairs(st.parts.focus or {}) do
    if eb:HasFocus() then
      return true
    end
  end
  return false
end

local function tick(st, dt)
  local hover = inside(st)
  if hover ~= st.hover then
    st.hover = hover
    paintBorder(st)
  end
  if not st.style.autoHide then
    return
  end
  if hover or busy(st) then
    st.idle, st.target = 0, 1
  else
    st.idle = st.idle + dt
    if st.idle >= WS.HIDE_DELAY then
      st.target = 0
    end
  end
  local cur, target = st.chrome, st.target
  if cur == target then
    return
  end
  if ns.Theme.reduceMotion() then
    cur = target
  elseif target > cur then
    cur = math.min(target, cur + dt / WS.FADE_TIME)
  else
    cur = math.max(target, cur - dt / WS.FADE_TIME)
  end
  st.chrome = cur
  paintChrome(st)
end

local function newState(frame)
  local st = { frame = frame, holds = {}, chrome = 1, target = 1, idle = 0, hover = false }
  -- A drag that was cut short by hiding the window must not pin the chrome forever.
  frame:HookScript("OnHide", function()
    st.holds = {}
  end)
  return st
end

-- Polls the mouse only while it matters: auto-hide is on, or the border of a fully
-- transparent window waits for the hover.
local function setTracking(st, on)
  if on and not st.driver then
    st.driver = CreateFrame("Frame", nil, st.frame)
  end
  if st.driver then
    st.driver:SetScript("OnUpdate", on and function(_, dt)
      tick(st, dt)
    end or nil)
  end
end

function WS.Apply(frame, style, parts)
  local st = states[frame]
  if not st then
    st = newState(frame)
    states[frame] = st
  end
  parts = parts or {}
  st.style, st.parts = style, parts
  local r, g, b = U.hex(style.bg)
  for _, tex in ipairs(parts.bg or {}) do
    tex:SetColorTexture(r, g, b, 1)
    tex:SetAlpha(style.alpha)
  end
  for _, tex in ipairs(parts.bars or {}) do
    tex:SetAlpha(WS.Edge(style.alpha))
  end
  -- The stone of the window skin takes the opacity too (UI/WindowShell.lua).
  if ns.WindowShell then
    ns.WindowShell.Style(frame, style, parts)
  end
  paintBorder(st)
  if not style.autoHide then
    st.chrome, st.target, st.idle = 1, 1, 0
  end
  paintChrome(st)
  setTracking(st, style.autoHide or style.alpha <= 0)
  return st
end

-- Keeps the chrome visible while `key` is held (dragging, resizing).
function WS.Hold(frame, key, on)
  local st = states[frame]
  if st then
    st.holds[key] = on and true or nil
    if on then
      st.idle, st.target = 0, 1
    end
  end
end

-- Shows the chrome at once and restarts the hide delay.
function WS.Reveal(frame)
  local st = states[frame]
  if st then
    st.chrome, st.target, st.idle = 1, 1, 0
    paintChrome(st)
  end
end
