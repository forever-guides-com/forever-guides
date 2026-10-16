-- The handle of a Blizzard window (mode "grip" of Modules/FrameTweaksBar.lua, the default): one
-- small square, a child of the window, that ignores the window's scale and alpha, drawn without client
-- textures. It lives in the strata of its window a few levels above it (Handle.LEVEL), so it stacks with
-- the window: a window in front of it covers it, it never reaches over a window above its own.
-- It sits outside the lower right corner of the window where no part of the window hangs
-- (tabs, button rows), else beside or above it. A click opens a panel next to it with opacity
-- (- number +, slider), zoom (- number +, slider), "Reset" and a way to the settings page. Pulling
-- the handle zooms the window like the grip of the bar did. The panel closes on a click elsewhere,
-- on Escape (the window stays), a moment after the mouse left, in combat and with its window.
local _, ns = ...
local W, FL, Bar = ns.W, ns.FrameTweaksLogic, ns.FrameTweaksBar

local Handle = {}
ns.FrameTweaksHandle = Handle

Handle.SIZE = FL.HANDLE_SIZE
Handle.GAP = 2
Handle.TICK = 0.1
Handle.LEAVE_DELAY = 0.6
Handle.DRAG_DISTANCE = 4
Handle.RETRY = 1
Handle.LEVEL = Bar.LEVEL
Handle.PAD, Handle.PANEL_WIDTH, Handle.ROW = 10, 260, 18

ns.AddLocale("enUS", {
  ["bar.handle"] = "Window options",
  ["bar.handleTip"] = "Click: options\nDrag: zoom",
  ["bar.reset"] = "Reset",
  ["bar.resetTip"] = "Zoom and opacity to 100 %",
  ["bar.more"] = "Windows settings",
  ["bar.moreTip"] = "Opens the settings page",
})
ns.AddLocale("deDE", {
  ["bar.handle"] = "Fensteroptionen",
  ["bar.handleTip"] = "Klick: Optionen\nZiehen: Zoom",
  ["bar.reset"] = "Zurücksetzen",
  ["bar.resetTip"] = "Zoom und Deckkraft auf 100 %",
  ["bar.more"] = "Fenster-Einstellungen",
  ["bar.moreTip"] = "Öffnet die Einstellungsseite",
})

local handles = {} -- name -> handle button

local function guard(fn, ...)
  return pcall(fn, ...)
end

-- A gear on the 12 x 12 icon grid.
local function drawGear(p)
  p:Outline(3, 3, 6, 6)
  p:Rect(5, 5, 2, 2)
  p:Rect(5, 1, 2, 2)
  p:Rect(5, 9, 2, 2)
  p:Rect(1, 5, 2, 2)
  p:Rect(9, 5, 2, 2)
  p:Rect(2, 2, 1, 1)
  p:Rect(9, 2, 1, 1)
  p:Rect(2, 9, 1, 1)
  p:Rect(9, 9, 1, 1)
end

local function mouseDown()
  if type(IsMouseButtonDown) ~= "function" then
    return false
  end
  return IsMouseButtonDown("LeftButton") == true or IsMouseButtonDown("RightButton") == true
end

local function focusIn(owner)
  local focus = ns.Focus and ns.Focus.current
  return focus ~= nil and focus.fgBar == owner
end

-- Panel ---------------------------------------------------------------------------------------------

function Handle.Close(name)
  local h = handles[name]
  if h and h.pop and h.pop:IsShown() then
    h.pop:Hide()
  end
end

function Handle.CloseAll()
  for name in pairs(handles) do
    Handle.Close(name)
  end
end

-- The controls in the order the Tab key visits them.
local function itemsOf(p)
  local out = {}
  for _, w in ipairs(p.fgItems) do
    if w:IsShown() and w:IsEnabled() then
      out[#out + 1] = w
    end
  end
  return out
end

local function cycle(p, step)
  local list = itemsOf(p)
  if #list == 0 then
    return
  end
  local at = 0
  for i, w in ipairs(list) do
    if w == ns.Focus.current then
      at = i
    end
  end
  at = at + step
  if at < 1 then
    at = #list
  elseif at > #list then
    at = 1
  end
  ns.Focus.set(list[at])
end

-- Escape closes the panel and nothing else; the other keys reach the game.
local function onKey(self, key)
  local handled = false
  local focus = ns.Focus.current
  if key == "ESCAPE" then
    Handle.Close(self.fgName)
    handled = true
  elseif key == "TAB" then
    cycle(self, IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    handled = true
  elseif (key == "LEFT" or key == "RIGHT") and focusIn(self) and focus.fgArrow then
    focus:fgArrow(key == "LEFT" and -1 or 1)
    handled = true
  elseif (key == "ENTER" or key == "SPACE") and focusIn(self) then
    handled = ns.Focus.activate()
  end
  pcall(self.SetPropagateKeyboardInput, self, not handled)
end

-- Click elsewhere closes at once; leaving the panel and the handle closes after a short delay.
local function watch(self, elapsed)
  local name = self.fgName
  local h, frame = handles[name], Bar.Window(name)
  if not (h and frame and Bar.Wanted(name, frame)) then
    Handle.Close(name)
    return
  end
  local down = mouseDown()
  local over = self:IsMouseOver() == true or h:IsMouseOver() == true
  if down and not self.fgWasDown and not over then
    Handle.Close(name)
    return
  end
  self.fgWasDown = down
  self.fgWaited = (self.fgWaited or 0) + (elapsed or 0)
  if self.fgWaited < Handle.TICK then
    return
  end
  local waited = self.fgWaited
  self.fgWaited = 0
  Bar.Paint(self)
  if over or down or focusIn(self) then
    self.fgLeft = 0
  else
    self.fgLeft = (self.fgLeft or 0) + waited
    if self.fgLeft >= Handle.LEAVE_DELAY then
      Handle.Close(name)
    end
  end
end

-- Lays out the two control groups, the title and the two buttons.
local function layoutPanel(p)
  local pad, width = Handle.PAD, Handle.PANEL_WIDTH
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", pad, -8)
  local function group(top, label, out, value, inn, track, extra)
    label:SetSize(math.ceil(label:GetStringWidth()) + 2, 14)
    label:SetPoint("TOPLEFT", p, "TOPLEFT", pad, top - 2)
    inn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -pad, top)
    value:SetPoint("RIGHT", inn, "LEFT", -Bar.GAP, 0)
    out:SetPoint("RIGHT", value, "LEFT", -Bar.GAP, 0)
    if extra then
      extra:SetPoint("RIGHT", out, "LEFT", -Bar.GAP, 0)
    end
    track:SetWidth(width - 2 * pad)
    track:SetPoint("TOPLEFT", p, "TOPLEFT", pad, top - Handle.ROW - 6)
  end
  group(-30, p.alphaLabel, p.alphaOut, p.alphaValue, p.alphaIn, p.alphaSlider, p.alphaMode)
  group(-78, p.zoomLabel, p.zoomOut, p.zoomValue, p.zoomIn, p.zoomSlider)
  p.reset:SetPoint("TOPLEFT", p, "TOPLEFT", pad, -126)
  p.more:SetPoint("TOPRIGHT", p, "TOPRIGHT", -pad, -126)
  p:SetSize(width, 126 + p.reset:GetHeight() + pad)
end

local function buildPanel(name, h)
  local p = CreateFrame("Frame", nil, UIParent)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetFrameLevel(200)
  p:SetIgnoreParentScale(true)
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  p:EnableKeyboard(true)
  p:Hide()
  W.Fill(p, "surface2", 0.97)
  W.Border(p, "white", 0.4)
  Bar.NewControls(p, name)
  p.title = W.Text(p, { key = "bar.handle", role = "ui", color = "text" })
  p.reset = W.Action(p, {
    label = "act.reset",
    icon = "reset",
    width = 90,
    height = 22,
    tooltip = "bar.reset",
    tooltipText = "bar.resetTip",
    onClick = function()
      Bar.ResetLook(name)
    end,
  })
  p.more = W.Action(p, {
    label = "act.options",
    icon = "gear",
    variant = "ghost",
    width = Handle.PANEL_WIDTH - 2 * Handle.PAD - 96,
    height = 22,
    tooltip = "bar.more",
    tooltipText = "bar.moreTip",
    onClick = function()
      Handle.Close(name)
      if ns.Main and ns.Main.Show then
        ns.Main.Show("windows")
      end
    end,
  })
  p.reset.fgBar, p.more.fgBar = p, p
  p.fgItems = {
    p.alphaMode,
    p.alphaOut,
    p.alphaValue,
    p.alphaIn,
    p.alphaSlider,
    p.zoomOut,
    p.zoomValue,
    p.zoomIn,
    p.zoomSlider,
    p.reset,
    p.more,
  }
  layoutPanel(p)
  p:SetScript("OnKeyDown", ns.Wrap("frame-handle-keys", onKey))
  p:SetScript("OnUpdate", function(self, elapsed)
    guard(watch, self, elapsed)
  end)
  p:SetScript("OnShow", function(self)
    self.fgLeft, self.fgWaited, self.fgWasDown = 0, 0, mouseDown()
  end)
  p:HookScript("OnHide", function(self)
    if focusIn(self) then
      ns.Focus.clear()
    end
    h.fgOpen = false
  end)
  h.pop = p
  return p
end

-- Opens the panel next to the handle (keys: the focus goes to its first control).
function Handle.Open(name, withFocus)
  local h, frame = handles[name], Bar.Window(name)
  if not (h and frame and Bar.Wanted(name, frame)) then
    return
  end
  Handle.CloseAll()
  local p = h.pop or buildPanel(name, h)
  p:SetScale(UIParent:GetEffectiveScale())
  local screen = { w = UIParent:GetWidth(), h = UIParent:GetHeight() }
  local box = h.fgBox
  p:ClearAllPoints()
  if box then
    local at = FL.PlacePopover(box, { w = p:GetWidth(), h = p:GetHeight() }, screen, Handle.GAP)
    p:SetPoint(at.p, h, at.rp, at.x, at.y)
  else
    p:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, -Handle.GAP)
  end
  Bar.Paint(p)
  h.fgOpen = true
  W.Tooltip.Hide(h)
  p:Show()
  if withFocus then
    local first = itemsOf(p)[1]
    if first then
      ns.Focus.set(first)
    end
  end
end

function Handle.Toggle(name, withFocus)
  local h = handles[name]
  if h and h.pop and h.pop:IsShown() then
    Handle.Close(name)
  else
    Handle.Open(name, withFocus)
  end
end

-- Handle ----------------------------------------------------------------------------------------------

function Handle.Of(name)
  return handles[name]
end

local function place(h, frame)
  local name = h.fgName
  local strata = frame:GetFrameStrata()
  local scale = UIParent:GetEffectiveScale()
  local win, parts, screen, key = Bar.Surround(name, frame)
  h:SetScale(scale)
  Bar.SyncLayer(name, h, frame)
  h:ClearAllPoints()
  if win then
    local at = FL.PlaceHandle(win, parts, Handle.SIZE, screen, Handle.GAP)
    h.fgBox, h.fgSide = at.box, at.side
    h:SetPoint(at.p, frame, at.rp, at.x, at.y)
  else
    h.fgBox, h.fgSide = nil, nil
    h:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -Handle.GAP)
  end
  h.fgState = { key = key, strata = strata, scale = scale }
end

local function release(h)
  h.fgDown, h.fgMoved = nil, false
  Bar.StopGrip()
end

-- While the button is down: a move of a few pixels turns the click into a zoom drag.
local function pulled(h, frame)
  local name = h.fgName
  if type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") ~= true then
    release(h)
    return
  end
  if not h.fgMoved then
    local x, y = Bar.Cursor()
    local far = math.abs(x - h.fgDown.x) + math.abs(y - h.fgDown.y) >= Handle.DRAG_DISTANCE
    if far and Bar.StartGrip(name, frame, h.fgDown.x, h.fgDown.y) then
      h.fgMoved = true
      Handle.Close(name)
    end
  end
  if h.fgMoved then
    Bar.DragStep(name)
  end
end

function Handle.Tick(name)
  local h, frame = handles[name], Bar.Window(name)
  if not (h and frame and h:IsShown()) then
    return
  end
  if not Bar.Wanted(name, frame) then
    Handle.Hide(name)
    return
  end
  local state = h.fgState
  local _, _, _, key = Bar.Surround(name, frame)
  if
    not state
    or state.key ~= key
    or state.strata ~= frame:GetFrameStrata()
    or state.scale ~= UIParent:GetEffectiveScale()
  then
    place(h, frame)
  end
  Bar.SyncLayer(name, h, frame)
  h:SetAlpha(Bar.Hot(h, frame, h.fgOpen == true) and 1 or Bar.IdleAlpha())
  -- The bar had no free spot: try again now and then, the window may have changed.
  if h.fgFallback then
    h.fgRetry = (h.fgRetry or 0) + Handle.TICK
    if h.fgRetry >= Handle.RETRY then
      h.fgRetry = 0
      Bar.Refresh(name)
    end
  end
end

local function build(name, frame)
  local h = CreateFrame("Button", nil, frame)
  h.fgName = name
  h:SetSize(Handle.SIZE, Handle.SIZE)
  h:SetIgnoreParentScale(true)
  h:SetIgnoreParentAlpha(true)
  h:SetClampedToScreen(true)
  h:EnableMouse(true)
  W.Fill(h, "surface2", 0.9)
  W.Border(h, "white", 0.3)
  h.icon = ns.IconDraw.new(h, 12)
  h.icon:SetPoint("CENTER", 0, 0)
  h.icon:Draw(drawGear)
  h:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
      local x, y = Bar.Cursor()
      self.fgDown, self.fgMoved = { x = x, y = y }, false
    end
  end)
  h:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.fgDown then
      return
    end
    local moved = self.fgMoved
    release(self)
    if not moved then
      Handle.Toggle(name)
    end
  end)
  h:HookScript("OnHide", function(self)
    release(self)
    Handle.Close(name)
  end)
  h:HookScript("OnEnter", function(self)
    self.icon:SetTint("accent")
    if not self.fgOpen then
      Bar.Tip(self, "bar.handle", "bar.handleTip")
    end
  end)
  h:HookScript("OnLeave", function(self)
    self.icon:SetTint("textSecondary")
    W.Tooltip.Hide(self)
  end)
  h.fgBar = h
  h.fgArrow = function(_, dir)
    Bar.ZoomBy(name, dir)
  end
  ns.Focus.register(h, function()
    Handle.Toggle(name, true)
  end)
  local waited = 0
  h:SetScript("OnUpdate", function(self, elapsed)
    if self.fgDown then
      guard(pulled, self, frame)
    end
    waited = waited + (elapsed or 0)
    if waited >= Handle.TICK then
      waited = 0
      guard(Handle.Tick, name)
    end
  end)
  handles[name] = h
  Bar.HookLayer(name, frame)
  return h
end

-- fallback: the bar of the mode found no free spot and the handle stands in for it.
function Handle.Show(name, frame, fallback)
  local h = handles[name] or build(name, frame)
  h.fgFallback = fallback == true
  place(h, frame)
  if h.pop and h.pop:IsShown() then
    Bar.Paint(h.pop)
  end
  h:SetAlpha(Bar.Hot(h, frame, h.fgOpen == true) and 1 or Bar.IdleAlpha())
  h:Show()
end

function Handle.Hide(name)
  local h = handles[name]
  if h then
    Handle.Close(name)
    h:Hide()
  end
end

ns.On("PLAYER_REGEN_DISABLED", Handle.CloseAll)
