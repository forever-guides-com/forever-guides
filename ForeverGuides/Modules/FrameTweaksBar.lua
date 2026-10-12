-- Opacity and zoom controls of a Blizzard window handled by Modules/FrameTweaks.lua, in three modes
-- (settings.frameBarMode): "grip" (default) a small handle that opens a panel, see FrameTweaksHandle.lua;
-- "bar" the bar built here, background opacity "- 100 % +" with a slider, zoom "- 100 % +" with a
-- slider and the resize grip; "off" nothing (keys and commands only). A bar is an own frame on
-- UIParent that ignores the window's scale and alpha, so it stays readable and equally big whatever
-- the zoom. Windows narrower than 360 px get numbers and buttons only. It is fully visible only
-- while the mouse is over the window or the bar, or a bar control has the focus.
-- Placement: the window's parts that hang out of it (tabs, button rows) are measured once and again
-- when the window changes its size; the bar goes under the deepest one, else above the window, else
-- beside it, and never over a part. Without a free spot the handle stands in for the bar.
-- Settings: frameBarMode (grip, bar, off), frameBar = false (switch of older versions, means off),
-- frameBars[name] = false (one window), frameMapZoom (world map zoom: without it the zoom controls
-- are locked, the rest works), frameBarPos (outside = automatic, inside the window's bottom edge),
-- frameBarHover (dimmed without the mouse).
local _, ns = ...
local W, FL, L = ns.W, ns.FrameTweaksLogic, ns.L

local Bar = {}
ns.FrameTweaksBar = Bar

Bar.HEIGHT = FL.BAR_HEIGHT
Bar.BUTTON = 18
Bar.VALUE_WIDTH = 32
Bar.SLIDER_WIDTH = 76
Bar.SLIDER_HEIGHT = 14
Bar.PAD, Bar.GAP, Bar.SEPARATE = 4, 2, 4
Bar.TICK = 0.1
-- Parts of a window are looked for this deep, at most this many, and measured again this many times
-- after the window opened (tabs are built a moment later).
Bar.PART_DEPTH, Bar.PART_MAX, Bar.SETTLE = 2, 150, 8

ns.AddLocale("enUS", {
  ["bar.alpha"] = "Opacity",
  ["bar.alphaTip"] = "Background only\n0 % = invisible",
  ["bar.alphaValue"] = "Click: 100 %\n0 % = invisible",
  ["bar.alphaOut"] = "Less opaque",
  ["bar.alphaIn"] = "More opaque",
  ["bar.alphaNone"] = "Not available here",
  ["bar.modeBackground"] = "Background only",
  ["bar.modeWindow"] = "Whole window",
  ["bar.modeToWindow"] = "Click: whole window",
  ["bar.modeToBackground"] = "Click: background only\nMin. 35 %",
  ["bar.zoom"] = "Zoom",
  ["bar.zoomOut"] = "Smaller",
  ["bar.zoomIn"] = "Larger",
  ["bar.zoomValue"] = "Click: 100 %\nArrows: change",
  ["bar.zoomOff"] = "Zoom is off",
  ["bar.slider"] = "Drag or mouse wheel",
  ["bar.grip"] = "Resize",
  ["bar.gripTip"] = "Drag: zoom\n{mod:scaleSnap}: 5 % steps",
})
ns.AddLocale("deDE", {
  ["bar.alpha"] = "Deckkraft",
  ["bar.alphaTip"] = "Nur Hintergrund\n0 % = unsichtbar",
  ["bar.alphaValue"] = "Klick: 100 %\n0 % = unsichtbar",
  ["bar.alphaOut"] = "Weniger deckend",
  ["bar.alphaIn"] = "Mehr deckend",
  ["bar.alphaNone"] = "Hier nicht verfügbar",
  ["bar.modeBackground"] = "Nur Hintergrund",
  ["bar.modeWindow"] = "Ganzes Fenster",
  ["bar.modeToWindow"] = "Klick: ganzes Fenster",
  ["bar.modeToBackground"] = "Klick: nur Hintergrund\nMind. 35 %",
  ["bar.zoom"] = "Zoom",
  ["bar.zoomOut"] = "Kleiner",
  ["bar.zoomIn"] = "Größer",
  ["bar.zoomValue"] = "Klick: 100 %\nPfeile: ändern",
  ["bar.zoomOff"] = "Zoom ist aus",
  ["bar.slider"] = "Ziehen oder Mausrad",
  ["bar.grip"] = "Größe",
  ["bar.gripTip"] = "Ziehen: Zoom\n{mod:scaleSnap}: 5-%-Schritte",
})

local bars = {} -- name -> bar frame
local windows = {} -- name -> window frame
local measured = {} -- name -> { size, parts, settle }: the window's parts that hang out of it
local dragging -- { name, cx, cy, scale, w, h } while the grip is pulled

local function guard(fn, ...)
  return pcall(fn, ...)
end

local function settings()
  return ns.db and ns.db.settings
end

-- The bar of a window, nil before it was ever shown.
function Bar.Of(name)
  return bars[name]
end

function Bar.Window(name)
  return windows[name]
end

-- The mode in force: grip, bar or off.
function Bar.Mode()
  local s = settings()
  if not s then
    return "off"
  end
  return FL.BarMode(s.frameBarMode, s.frameBar)
end

-- May a window show its handle or bar at all?
function Bar.Enabled(name)
  local s = settings()
  if not s or Bar.Mode() == "off" or ns.FrameTweaks.Ignored(name) then
    return false
  end
  local off = s.frameBars
  if type(off) == "table" and off[name] == false then
    return false
  end
  return s.frameTweaks ~= false
end

-- One window on or off; the other windows keep their choice.
function Bar.SetEnabled(name, on)
  local s = settings()
  if not s then
    return
  end
  if type(s.frameBars) ~= "table" then
    s.frameBars = {}
  end
  if on then
    s.frameBars[name] = nil
  else
    s.frameBars[name] = false
  end
  Bar.Refresh(name)
end

local function isMaximized(name, frame)
  if not FL.MAXIMIZABLE[name] then
    return false
  end
  local ok, value = pcall(function()
    return frame:IsMaximized()
  end)
  return ok and value == true
end

local function wanted(name, frame)
  return Bar.Enabled(name) and frame:IsShown() and not isMaximized(name, frame)
end
Bar.Wanted = wanted

-- Zoom --------------------------------------------------------------------------------------------

local function zoomTo(name, value)
  local FT = ns.FrameTweaks
  FT.SetScale(name, value)
  Bar.Refresh(name)
end

local function zoomBy(name, dir)
  zoomTo(name, FL.StepScale(ns.FrameTweaks.GetScale(name) or 1, dir))
end
Bar.ZoomBy = zoomBy

-- Opacity -------------------------------------------------------------------------------------------

local function alphaTo(name, value)
  ns.FrameTweaksAlpha.Set(name, value)
  Bar.Refresh(name)
end

local function alphaBy(name, dir)
  alphaTo(name, FL.StepAlpha(ns.FrameTweaksAlpha.Get(name), dir))
end

-- Zoom and opacity of a window back to the client's look (the position stays).
function Bar.ResetLook(name)
  ns.FrameTweaks.SetScale(name, 1)
  ns.FrameTweaksAlpha.Set(name, FL.ALPHA_MAX)
  Bar.Refresh(name)
end

local function cursor()
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  return x / scale, y / scale
end
Bar.Cursor = cursor

local function stopGrip()
  dragging = nil
end
Bar.StopGrip = stopGrip

-- x, y: where the mouse went down (units of UIParent), the cursor now when missing.
local function startGrip(name, frame, x, y)
  local cx, cy = x, y
  if not (cx and cy) then
    cx, cy = cursor()
  end
  local ok, w, h = pcall(function()
    return frame:GetWidth(), frame:GetHeight()
  end)
  local scale = ns.FrameTweaks.GetScale(name)
  if ok and scale and ns.FrameTweaks.Scalable(name) then
    dragging = { name = name, cx = cx, cy = cy, scale = scale, w = w, h = h }
    return true
  end
  return false
end
Bar.StartGrip = startGrip

local function dragStep()
  local d = dragging
  local x, y = cursor()
  local snap = ns.Keys.Matches("scaleSnap")
  local value = FL.DragScale(d.scale, d.w, d.h, x - d.cx, y - d.cy, snap)
  local current = ns.FrameTweaks.GetScale(d.name)
  if current == nil or math.abs(current - value) >= 0.001 then
    ns.FrameTweaks.SetScale(d.name, value)
  end
end

-- Moves the zoom with the mouse while a grip of this window is pulled.
function Bar.DragStep(name)
  if dragging and dragging.name == name then
    guard(dragStep)
  end
end

function Bar.Dragging(name)
  return dragging ~= nil and dragging.name == name
end

-- Surroundings ------------------------------------------------------------------------------------

local function shown(frame)
  local ok, value = pcall(frame.IsShown, frame)
  return ok and value == true
end

-- Child frames of the window (some levels deep) and its tabs by the client's names.
local function partsOf(name, frame)
  local out, seen = {}, { [frame] = true }
  local function add(part)
    if type(part) == "table" and not seen[part] and #out < Bar.PART_MAX then
      seen[part] = true
      out[#out + 1] = part
      return true
    end
    return false
  end
  local queue, at = { { frame, 0 } }, 1
  while queue[at] and #out < Bar.PART_MAX do
    local holder, depth = queue[at][1], queue[at][2]
    at = at + 1
    if depth < Bar.PART_DEPTH then
      local ok, children = pcall(function()
        return { holder:GetChildren() }
      end)
      for _, child in ipairs(ok and children or {}) do
        if add(child) then
          queue[#queue + 1] = { child, depth + 1 }
        end
      end
    end
  end
  for i = 1, 12 do
    add(rawget(_G, name .. "Tab" .. i))
  end
  local tabs = frame.Tabs
  if type(tabs) == "table" then
    for _, tab in pairs(tabs) do
      add(tab)
    end
  end
  return out
end

-- Rectangle of a frame in the units of the window (they differ by the scale of the two).
local function rectIn(frame, part)
  local ok, l, b, r, t = pcall(function()
    local k = part:GetEffectiveScale() / frame:GetEffectiveScale()
    return part:GetLeft() * k, part:GetBottom() * k, part:GetRight() * k, part:GetTop() * k
  end)
  return ok and FL.Rect(l, b, r, t) or nil
end

-- The parts that hang out of the window, as offsets from its lower left corner in window units.
local function measure(name, frame, own)
  local out = {}
  for _, part in ipairs(partsOf(name, frame)) do
    if part.fgName == nil and shown(part) then
      local rect = rectIn(frame, part)
      local hang = rect and FL.Protrusion(own, rect)
      if hang then
        out[#out + 1] = { l = hang.l - own.l, b = hang.b - own.b, r = hang.r - own.l, t = hang.t - own.b }
      end
    end
  end
  return out
end

-- Forgets what was measured around a window (it opened, or the client built its parts again).
function Bar.Invalidate(name)
  measured[name] = nil
end

-- The window's rectangle, the parts that hang out of it (all in UIParent units), the screen and a key
-- that changes when the window moves or the screen changes. Parts are measured again only when the
-- window's size changed, force is set or the window is new (a few more times right after it opened).
-- The key also changes with the parts, so a tab that shows up later moves what sits beside it.
-- Nil when the window has no rectangle yet.
function Bar.Surround(name, frame, force)
  local ok, own, ratio, w, h = pcall(function()
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local rect = FL.Rect(frame:GetLeft(), frame:GetBottom(), frame:GetRight(), frame:GetTop())
    return rect, scale, UIParent:GetWidth(), UIParent:GetHeight()
  end)
  if not (ok and own and FL.Rect(0, 0, w, h)) then
    return nil
  end
  local win = { l = own.l * ratio, b = own.b * ratio, r = own.r * ratio, t = own.t * ratio }
  local size = string.format("%.1f:%.1f", own.r - own.l, own.t - own.b)
  local cache = measured[name]
  if force or not cache or cache.size ~= size then
    cache = { size = size, settle = Bar.SETTLE }
    measured[name] = cache
  end
  if cache.settle > 0 or not cache.parts then
    cache.settle = cache.settle - 1
    cache.parts = measure(name, frame, own)
    local sig = {}
    for i, p in ipairs(cache.parts) do
      sig[i] = string.format("%.0f,%.0f,%.0f,%.0f", p.l, p.b, p.r, p.t)
    end
    cache.sig = table.concat(sig, ";")
  end
  local parts = {}
  for i, p in ipairs(cache.parts) do
    parts[i] = { l = win.l + p.l * ratio, b = win.b + p.b * ratio, r = win.l + p.r * ratio, t = win.b + p.t * ratio }
  end
  local key = string.format("%.1f,%.1f,%.1f,%.1f|%d,%d|%s", win.l, win.b, win.r, win.t, w, h, cache.sig)
  return win, parts, { w = w, h = h }, key
end

-- Placement ---------------------------------------------------------------------------------------

-- Does the window leave room for the sliders? Its width in screen units.
local function wideFor(frame)
  local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return FL.BarSliders(frame:GetWidth() * ratio)
end

-- Width of the two captions: another language changes it.
local function labelsOf(bar)
  return bar.alphaLabel:GetStringWidth() + bar.zoomLabel:GetStringWidth()
end

-- Places every control of the bar from left to right; narrow windows get no sliders.
local function layout(bar, wide)
  local x = Bar.PAD
  local function put(widget, width)
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + width + Bar.GAP
  end
  local function group(label, out, value, inn, track, extra)
    local width = math.ceil(label:GetStringWidth()) + 2
    label:SetWidth(width)
    put(label, width)
    put(out, Bar.BUTTON)
    put(value, Bar.VALUE_WIDTH)
    put(inn, Bar.BUTTON)
    track:SetShown(wide)
    if wide then
      x = x + 1
      put(track, Bar.SLIDER_WIDTH)
    end
    if extra then
      put(extra, Bar.BUTTON)
    end
  end
  local function divide(line)
    x = x - Bar.GAP + Bar.SEPARATE
    line:ClearAllPoints()
    line:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + 1 + Bar.SEPARATE
  end
  group(bar.alphaLabel, bar.alphaOut, bar.alphaValue, bar.alphaIn, bar.alphaSlider, bar.alphaMode)
  divide(bar.divider1)
  group(bar.zoomLabel, bar.zoomOut, bar.zoomValue, bar.zoomIn, bar.zoomSlider)
  divide(bar.divider2)
  put(bar.grip, Bar.BUTTON)
  bar:SetWidth(x - Bar.GAP + Bar.PAD)
end

-- The player wants the bar inside the bottom edge of the window.
local function insideWanted()
  local s = settings()
  return s ~= nil and s.frameBarPos == "inside"
end

-- Opacity of a control the mouse is not over: dimmed, or fully visible when the player turned that off.
function Bar.IdleAlpha()
  local s = settings()
  return (s == nil or s.frameBarHover ~= false) and FL.BAR_IDLE_ALPHA or 1
end

-- Puts the bar where no part of the window is in the way. False when no spot is free.
local function place(bar, frame, force)
  local strata = FL.BarStrata(frame:GetFrameStrata())
  local scale = UIParent:GetEffectiveScale()
  local wide = wideFor(frame)
  local inside = insideWanted()
  layout(bar, wide)
  local win, parts, screen, key = Bar.Surround(bar.fgName, frame, force)
  local p, rp, x, y = "TOP", "BOTTOM", 0, -FL.BAR_GAP
  if win and inside then
    p, rp, y = "BOTTOM", "BOTTOM", FL.BarPlacement(win.b, Bar.HEIGHT, FL.BAR_GAP, true).y
  elseif win then
    local at = FL.PlaceBar(win, parts, { w = bar:GetWidth(), h = Bar.HEIGHT }, screen, FL.BAR_GAP)
    if not at then
      bar.fgState = nil
      return false
    end
    p, rp, x, y = at.p, at.rp, at.x, at.y
  end
  bar.fgState = { key = key, strata = strata, scale = scale, wide = wide, labels = labelsOf(bar), inside = inside }
  bar:SetScale(scale)
  bar:SetFrameStrata(strata)
  bar:ClearAllPoints()
  bar:SetPoint(p, frame, rp, x, y)
  return true
end

-- Is the mouse over the window or the owner (bar, handle), is it pulled or does a control have the
-- focus? extra: something else that keeps the owner awake (an open panel).
function Bar.Hot(owner, frame, extra)
  if extra or (dragging and dragging.name == owner.fgName) then
    return true
  end
  local focus = ns.Focus and ns.Focus.current
  if focus and focus.fgBar == owner then
    return true
  end
  return owner:IsMouseOver() == true or frame:IsMouseOver() == true
end

-- Keeps a control and its number readable as "off".
local function dim(on, ...)
  for _, w in ipairs({ ... }) do
    w:SetAlpha(on and 1 or 0.3)
  end
end

-- Moves a slider to a value without telling its script.
local function syncSlider(slider, value)
  if slider.fgValue ~= value and not slider.fgHeld then
    slider.fgValue = value
    slider.fgSyncing = true
    slider:SetValue(value)
    slider.fgSyncing = false
  end
end

-- Follows a changed step or limit of the settings page (the sliders were built with the defaults).
local function syncRange(slider, min, max, step)
  local o = slider.fgOpts
  if o.min ~= min or o.max ~= max or o.step ~= step then
    o.min, o.max, o.step = min, max, step
    slider.fgSyncing = true
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider.fgSyncing = false
    slider.fgValue = nil
  end
end

-- Background mode: a frame around a solid middle. Window mode: one solid block.
local function drawMode(icon, mode)
  icon:Draw(function(p)
    if mode == "window" then
      p:Rect(1, 1, 10, 10)
    else
      p:Outline(1, 1, 10, 10)
      p:Rect(4, 4, 4, 4)
    end
  end)
end

-- Shows the current zoom and opacity in the controls of an owner (the bar or the panel of the handle).
local function paint(bar)
  local name = bar.fgName
  local FT, A = ns.FrameTweaks, ns.FrameTweaksAlpha
  syncRange(bar.zoomSlider, FL.Percent(FL.SCALE_MIN), FL.Percent(FL.SCALE_MAX), FL.Percent(FL.SCALE_STEP))
  syncRange(bar.alphaSlider, FL.ALPHA_MIN, FL.ALPHA_MAX, FL.ALPHA_STEP)
  local value = FT.GetScale(name) or 1
  local pct = FL.Percent(value)
  local canZoom = FT.Scalable(name)
  if not bar.zoomSlider.fgHeld then
    bar.zoomValue.text:SetText(string.format("%d %%", pct))
  end
  bar.zoomOut:SetEnabled(canZoom and value > FL.SCALE_MIN + 0.001)
  bar.zoomIn:SetEnabled(canZoom and value < FL.SCALE_MAX - 0.001)
  bar.zoomSlider:SetEnabled(canZoom)
  syncSlider(bar.zoomSlider, math.max(FL.SCALE_MIN * 100, math.min(FL.SCALE_MAX * 100, pct)))
  dim(canZoom, bar.zoomValue.text, bar.zoomSlider, bar.zoomLabel)

  local can = A.Available(name)
  local opacity = A.Get(name)
  bar.alphaValue.text:SetText(string.format("%d %%", opacity))
  bar.alphaOut:SetEnabled(can and opacity > FL.ALPHA_MIN)
  bar.alphaIn:SetEnabled(can and opacity < FL.ALPHA_MAX)
  bar.alphaSlider:SetEnabled(can)
  syncSlider(bar.alphaSlider, opacity)
  dim(can, bar.alphaValue.text, bar.alphaSlider, bar.alphaLabel)
  local mode = A.Mode(name)
  bar.alphaMode:SetEnabled(A.ModeAvailable(name))
  if bar.alphaMode.fgMode ~= mode then
    bar.alphaMode.fgMode = mode
    drawMode(bar.alphaMode.icon, mode)
  end
end
Bar.Paint = paint

-- Widgets -----------------------------------------------------------------------------------------

local function dimWhenDisabled(button, glyph)
  button:HookScript("OnDisable", function()
    glyph:SetAlpha(0.3)
  end)
  button:HookScript("OnEnable", function()
    glyph:SetAlpha(1)
  end)
end

-- textKey: a locale key, or a function that answers one (or nil) when the text depends on the state.
local function tip(owner, titleKey, textKey)
  if type(textKey) == "function" then
    textKey = textKey()
  end
  W.Tooltip.Show(owner, { title = L[titleKey], text = textKey and L[textKey], anchor = "ANCHOR_TOP" })
end
Bar.Tip = tip

local function hover(widget, titleKey, textKey)
  widget:HookScript("OnEnter", function(self)
    tip(self, titleKey, textKey)
  end)
  widget:HookScript("OnLeave", function(self)
    W.Tooltip.Hide(self)
  end)
end

-- Tooltip text of an opacity or zoom control: its own, or why it does not work.
local function alphaText(name, key)
  return function()
    return ns.FrameTweaksAlpha.Available(name) and key or "bar.alphaNone"
  end
end

local function zoomText(name, key)
  return function()
    if ns.FrameTweaks.Scalable(name) then
      return key
    end
    return "bar.zoomOff"
  end
end

-- The number between the two buttons; a click sets 100 %.
local function valueButton(owner, onClick, titleKey, textKey)
  local b = W.ValueButton(owner, { width = Bar.VALUE_WIDTH, height = Bar.BUTTON, onClick = onClick })
  b.fgNameKey = titleKey
  hover(b, titleKey, textKey)
  return b
end

local function separator(bar)
  local line = bar:CreateTexture(nil, "ARTWORK")
  line:SetSize(1, Bar.HEIGHT - 8)
  line:SetColorTexture(1, 1, 1, 0.25)
  return line
end

-- A short slider (drag, mouse wheel, arrow keys). o: min, max, step, set(v), titleKey, textKey.
-- applyOn = "release": set(v) runs once when the thumb is let go, preview(v) while it is held.
local function slider(owner, o)
  local s = CreateFrame("Slider", nil, owner)
  s:SetOrientation("HORIZONTAL")
  s:EnableMouse(true)
  s:SetSize(Bar.SLIDER_WIDTH, Bar.SLIDER_HEIGHT)
  s:SetMinMaxValues(o.min, o.max)
  s:SetValueStep(o.step)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  local rim = s:CreateTexture(nil, "BACKGROUND")
  rim:SetDrawLayer("BACKGROUND", -1)
  rim:SetPoint("LEFT", 0, 0)
  rim:SetPoint("RIGHT", 0, 0)
  rim:SetHeight(6)
  rim:SetColorTexture(1, 1, 1, 0.35)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 1, 0)
  track:SetPoint("RIGHT", -1, 0)
  track:SetHeight(4)
  local thumb = s:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(8, Bar.SLIDER_HEIGHT)
  s:SetThumbTexture(thumb)
  ns.Bind(s, function()
    track:SetColorTexture(ns.Theme.color("surface3"))
    thumb:SetColorTexture(ns.Theme.color("accent2"))
  end)
  local gate = o.applyOn == "release" and W.ReleaseGate(s, { preview = o.preview, commit = o.set })
  local function move(delta)
    if s:IsEnabled() then
      if gate then
        gate.flush()
      end
      s:SetValue(ns.U.clamp(s:GetValue() + delta * o.step, o.min, o.max))
    end
  end
  s:SetScript(
    "OnValueChanged",
    ns.Wrap("frame-bar", function(self, v)
      if self.fgSyncing or not self:IsEnabled() then
        return
      end
      v = ns.U.round(v, o.step)
      self.fgValue = v
      if gate then
        gate.change(v)
        return
      end
      o.set(v)
    end)
  )
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(_, delta)
    move(delta)
  end)
  s.fgArrow = function(_, delta)
    move(delta)
  end
  hover(s, o.titleKey, o.textKey)
  ns.Focus.register(s, nil)
  s.fgBar = owner
  s.fgOpts = o
  return s
end

-- Three dots in the corner, drawn on the icon grid (no font involved).
local function gripButton(bar, name, frame)
  local b = CreateFrame("Button", nil, bar)
  b:SetSize(Bar.BUTTON, Bar.BUTTON)
  local icon = ns.IconDraw.new(b, Bar.BUTTON)
  icon:SetPoint("CENTER", 0, 0)
  icon:Draw(function(p)
    p:Rect(8, 8, 2, 2)
    p:Rect(4, 8, 2, 2)
    p:Rect(8, 4, 2, 2)
  end)
  b.icon = icon
  b:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      guard(startGrip, name, frame)
    end
  end)
  b:SetScript("OnMouseUp", stopGrip)
  b:HookScript("OnHide", stopGrip)
  b:HookScript("OnEnter", function(self)
    icon:SetTint("accent")
    tip(self, "bar.grip", "bar.gripTip")
  end)
  b:HookScript("OnLeave", function(self)
    icon:SetTint("textSecondary")
    W.Tooltip.Hide(self)
  end)
  ns.Focus.register(b, nil)
  return b
end

-- Switch between fading the background only and the whole window.
local function modeButton(owner, name)
  local b = CreateFrame("Button", nil, owner)
  b:SetSize(Bar.BUTTON, Bar.BUTTON)
  b.icon = ns.IconDraw.new(b, Bar.BUTTON)
  b.icon:SetPoint("CENTER", 0, 0)
  b:SetScript(
    "OnClick",
    ns.Wrap("frame-bar", function()
      if b:IsEnabled() then
        ns.FrameTweaksAlpha.ToggleMode(name)
        Bar.Refresh(name)
      end
    end)
  )
  b:HookScript("OnEnter", function(self)
    self.icon:SetTint("accent")
    local window = ns.FrameTweaksAlpha.Mode(name) == "window"
    W.Tooltip.Show(self, {
      title = L[window and "bar.modeWindow" or "bar.modeBackground"],
      text = L[window and "bar.modeToBackground" or "bar.modeToWindow"],
      anchor = "ANCHOR_TOP",
    })
  end)
  b:HookScript("OnLeave", function(self)
    self.icon:SetTint("textSecondary")
    W.Tooltip.Hide(self)
  end)
  dimWhenDisabled(b, b.icon)
  b.fgBar = owner
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

-- The opacity and zoom controls of a window on an owner (the bar, or the panel of the handle): the
-- fields alphaLabel, alphaOut, alphaValue, alphaIn, alphaSlider, alphaMode and the same for zoom.
-- The owner places them. Buttons keep it awake (fgBar) and answer the arrow keys (fgArrow).
function Bar.NewControls(owner, name)
  owner.fgName = name
  local function label(key)
    return W.Text(owner, { key = key, role = "micro", color = "textSecondary" })
  end
  local function button(icon, titleKey, textKey, onClick)
    local b = W.Action(owner, { icon = icon, size = Bar.BUTTON, onClick = onClick, manual = true })
    b.fgNameKey = titleKey
    b.fgBar = owner
    hover(b, titleKey, textKey)
    return b
  end
  local function value(onClick, titleKey, textKey)
    local b = valueButton(owner, onClick, titleKey, textKey)
    b.fgBar = owner
    return b
  end
  local function alphaStep(dir)
    return function()
      alphaBy(name, dir)
    end
  end
  local function zoomStep(dir)
    return function()
      zoomBy(name, dir)
    end
  end

  owner.alphaLabel = label("bar.alpha")
  owner.alphaOut = button("minus", "bar.alphaOut", alphaText(name, "bar.alphaTip"), alphaStep(-1))
  owner.alphaValue = value(function()
    alphaTo(name, FL.ALPHA_MAX)
  end, "bar.alpha", alphaText(name, "bar.alphaValue"))
  owner.alphaIn = button("plus", "bar.alphaIn", alphaText(name, "bar.alphaTip"), alphaStep(1))
  owner.alphaSlider = slider(owner, {
    min = FL.ALPHA_MIN,
    max = FL.ALPHA_MAX,
    step = FL.ALPHA_STEP,
    titleKey = "bar.alpha",
    textKey = alphaText(name, "bar.slider"),
    set = function(v)
      alphaTo(name, v)
    end,
  })
  owner.alphaMode = modeButton(owner, name)

  owner.zoomLabel = label("bar.zoom")
  owner.zoomOut = button("minus", "bar.zoomOut", zoomText(name), zoomStep(-1))
  owner.zoomValue = value(function()
    zoomTo(name, 1)
  end, "bar.zoom", zoomText(name, "bar.zoomValue"))
  owner.zoomIn = button("plus", "bar.zoomIn", zoomText(name), zoomStep(1))
  owner.zoomSlider = slider(owner, {
    min = FL.SCALE_MIN * 100,
    max = FL.SCALE_MAX * 100,
    step = FL.SCALE_STEP * 100,
    titleKey = "bar.zoom",
    textKey = zoomText(name, "bar.slider"),
    applyOn = "release",
    preview = function(v)
      owner.zoomValue.text:SetText(string.format("%d %%", v))
    end,
    set = function(v)
      zoomTo(name, v / 100)
    end,
  })

  -- Arrow keys change the value while one of the buttons has the focus.
  for _, b in ipairs({ owner.alphaOut, owner.alphaIn, owner.alphaValue }) do
    b.fgArrow = function(_, dir)
      alphaBy(name, dir)
    end
  end
  for _, b in ipairs({ owner.zoomOut, owner.zoomIn, owner.zoomValue }) do
    b.fgArrow = function(_, dir)
      zoomBy(name, dir)
    end
  end
end

local function build(name, frame)
  local bar = CreateFrame("Frame", nil, UIParent)
  bar:SetSize(Bar.PAD, Bar.HEIGHT)
  bar:SetIgnoreParentScale(true)
  bar:SetIgnoreParentAlpha(true)
  bar:SetClampedToScreen(true)
  bar:EnableMouse(true)
  W.Fill(bar, "surface2", 0.9)
  W.Border(bar, "white", 0.3)
  Bar.NewControls(bar, name)
  bar.divider1 = separator(bar)
  bar.divider2 = separator(bar)
  bar.grip = gripButton(bar, name, frame)
  bar.grip.fgBar = bar
  bar.grip.fgArrow = function(_, dir)
    zoomBy(name, dir)
  end

  local waited = 0
  bar:SetScript("OnUpdate", function(_, elapsed)
    Bar.DragStep(name)
    waited = waited + (elapsed or 0)
    if waited >= Bar.TICK then
      waited = 0
      guard(Bar.Tick, name)
    end
  end)
  bars[name] = bar
  return bar
end

-- Refresh -----------------------------------------------------------------------------------------

-- Keeps the look of the bar current: alpha, and the placement when the window or screen changed.
function Bar.Tick(name)
  local bar, frame = bars[name], windows[name]
  if not (bar and frame and bar:IsShown()) then
    return
  end
  if not wanted(name, frame) then
    bar:Hide()
    return
  end
  local state = bar.fgState
  local strata = FL.BarStrata(frame:GetFrameStrata())
  local _, _, _, key = Bar.Surround(name, frame)
  if
    not state
    or state.key ~= key
    or state.strata ~= strata
    or state.scale ~= UIParent:GetEffectiveScale()
    or state.wide ~= wideFor(frame)
    or state.labels ~= labelsOf(bar)
    or state.inside ~= insideWanted()
  then
    if not place(bar, frame) then
      Bar.Refresh(name)
      return
    end
  end
  bar:SetAlpha(Bar.Hot(bar, frame) and 1 or Bar.IdleAlpha())
  paint(bar)
end

-- Shows what the mode asks for: the bar, the handle (also when the bar finds no free spot) or nothing.
function Bar.Refresh(name)
  local frame = windows[name]
  if not frame then
    return
  end
  guard(function()
    local bar, handle = bars[name], ns.FrameTweaksHandle
    if not wanted(name, frame) then
      if bar then
        bar:Hide()
      end
      if handle then
        handle.Hide(name)
      end
      return
    end
    if Bar.Mode() == "bar" then
      bar = bar or build(name, frame)
      if place(bar, frame) then
        paint(bar)
        bar:SetAlpha(Bar.Hot(bar, frame) and 1 or Bar.IdleAlpha())
        bar:Show()
        if handle then
          handle.Hide(name)
        end
        return
      end
      bar:Hide()
    elseif bar then
      bar:Hide()
    end
    if handle then
      handle.Show(name, frame, Bar.Mode() == "bar")
    end
  end)
end

function Bar.RefreshAll()
  for name in pairs(windows) do
    Bar.Refresh(name)
  end
end

-- Called by FrameTweaks for every window it handles, once.
function Bar.Attach(name, frame)
  if windows[name] == frame then
    return
  end
  windows[name] = frame
  pcall(frame.HookScript, frame, "OnShow", function()
    Bar.Invalidate(name)
    Bar.Refresh(name)
  end)
  pcall(frame.HookScript, frame, "OnHide", function()
    Bar.Refresh(name)
  end)
  Bar.Refresh(name)
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if
    path == "settings.frameBar"
    or path == "settings.frameBarMode"
    or path == "settings.frameBars"
    or path == "settings.frameTweaks"
    or path == "settings.frameMapZoom"
    or path == "settings.frameBarPos"
    or path == "settings.frameBarHover"
  then
    Bar.RefreshAll()
  end
end)
