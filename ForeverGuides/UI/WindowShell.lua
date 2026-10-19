-- Shared shell of every window of the addon (main window, note, drawing, calculator,
-- route and waypoint windows, dialogs): a clear edge, a title strip set apart from the
-- content and an active/inactive look, so it is obvious where a window starts and ends,
-- also on top of another window.
--
--   local shell = Shell.Attach(frame, { title = "locale.key" | text = "literal",
--     role = "ui", family = "heading", titleHeight = 22, shadow = true, shadowScale = 1,
--     active = false, fade = "main" (the stone follows the main window opacity),
--     band = true | false (title strip in the metal band, default true; the main window sets it itself and
--     lays out its page header in the band, UI/MainFrame.lua),
--     bandSize = "main" (the higher band of the main window, default: the band of every other window) })
--   shell.border      edge object (set(name, alpha), base, colorName) for WindowStyle.Apply
--   shell.shadow      frame with the drop shadow, nil without shadow = true
--   shell.titleBar    the title strip (parent of the buttons, drag target), height titleHeight. In the skin
--                     "forever" the strip moves up into the metal band above the window (see below)
--   shell.titleText   its title FontString, anchored LEFT 8 / RIGHT -4: windows with buttons
--                     anchor RIGHT to their leftmost button
--   shell.barFill     the strip's fill texture, shell.bars = { barFill } for parts.bars
--   shell.edge        the overlay frame of the edge, shell.divider the line under the strip
--   shell.band        the metal band the strip sits in (Skins.BandRect), nil while it sits in the window
--   shell.bandFill    texture of the window frame behind the band (color metrics.bar.backdrop), built when the
--                     band is first used, shown only while shell.band is set; below the metal and the strip. It
--                     reaches metrics.bar.bleed under the metal (sides and top), so no clear sliver of the art shows
--   Shell.Style(frame, style, parts)   WindowStyle.Apply reports the window's style: a background
--                            color of its own is kept, the opacity reaches the stone of the skin
--   Shell.IsTitleBar(frame)  true for the title strip of a shell (its "x" button is dressed)
--   Shell.MakeDraggable(frame, handle)   the handle moves the frame (Attach does it for the title strip:
--                            every window moves by its title bar, a window with drag scripts of its own keeps them)
--   Shell.FitToScreen(frame) shrinks a window larger than the screen and pulls it back from outside
--   Shell.RegisterEsc(frame, onEscape)   the window closes on Esc while shown, alone and newest first
--                            (ns.EscStack), never over UISpecialFrames: the client would close the vendor and
--                            the bags with it. Shell.SetEsc(frame, on) toggles it (pinned note).
--
-- Window style (UI/Skins.lua): in the skin "forever" the shell shows a metal frame around the edge
-- overlay, a tiled stone background, a gold title in the display font and the red close button.
-- Those parts are built when first needed and shown or hidden on every ns.RefreshUI, so a switch
-- needs no rebuild. Every part has the flat look as its fallback (art missing or an error).
--
-- Title strip in the metal band (skin "forever", windows with band = true): the strip itself moves, so
-- the title, the buttons and every drag, wheel and tooltip script of the window stay where they are
-- anchored (to the strip) and nothing is built twice. The strip spans the band (inset by
-- Skins.list.forever.metrics.bar.margin), its dark fill is hidden (shell.bandFill takes its place), the strip
-- and everything in it are lifted above the edge overlay (the metal would cover them otherwise), the title is
-- capped to the band.
-- The band is as high as metrics.bar says (main window 38, other windows 32 px), whatever the art measures: the metal
-- grows upwards over the window, so the window below keeps its layout and its anchors, the old strip area
-- stays empty stone. Flat undoes all of it.
--   Shell.SetActive(frame)   makes `frame` the active window: its edge and title are lit, the
--                            others are dimmed. Happens on OnShow and on every mouse down.
--   Shell.Of(frame)          the shell of a frame, nil without one
--
-- The edge is an overlay frame above the content, so full-bleed children (title strip,
-- footer, sidebar) never cover it. The metal frame of the skin lies around the window, never on
-- the content (Skins.lua). Nothing here changes the strata, and raising skips protected frames in combat.
local _, ns = ...
local W, Theme, Skins, U = ns.W, ns.Theme, ns.Skins, ns.U

local Shell = {}
ns.WindowShell = Shell

-- Frame level of the edge overlay above the window content.
Shell.EDGE_LEVEL = 100
-- Shadow: rings of SHADOW_STEP px, nearest first, each lighter than the one before.
Shell.SHADOW_STEP = 3
Shell.SHADOW_ALPHA = { 0.22, 0.12, 0.06 }
-- Share of the edge opacity the dark inner line gets.
Shell.INNER_ALPHA = 0.85
Shell.LOOK = {
  active = { edge = "accent", divider = "accent2", alpha = 1, title = "accent2" },
  idle = { edge = "accent2", divider = "accentDim", alpha = 0.75, title = "textMuted" },
}

local STRATA = {
  BACKGROUND = 1,
  LOW = 2,
  MEDIUM = 3,
  HIGH = 4,
  DIALOG = 5,
  FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7,
  TOOLTIP = 8,
}

local shells = setmetatable({}, { __mode = "k" })
local titleBars = setmetatable({}, { __mode = "k" })
local active

function Shell.Of(frame)
  return shells[frame]
end

function Shell.IsTitleBar(frame)
  return titleBars[frame] ~= nil
end

-- Edge ---------------------------------------------------------------------------------------

-- Bright outer line, dark line inside it (it separates the edge from a light background),
-- and the 1 px divider under the title strip. One object, so WindowStyle treats it like a
-- W.Border and one alpha drives all three. With the metal frame of a skin (border.nine) that
-- frame takes the alpha and the flat lines are hidden.
local function buildEdge(frame, bar)
  local look = Shell.LOOK.idle
  local edge = CreateFrame("Frame", nil, frame)
  edge:SetAllPoints()
  edge:SetFrameLevel(frame:GetFrameLevel() + Shell.EDGE_LEVEL)
  local inner = CreateFrame("Frame", nil, edge)
  inner:SetPoint("TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", -1, 1)
  local outerRing = W.Border(edge, look.edge, look.alpha, 1)
  local innerRing = W.Border(inner, "bg", look.alpha * Shell.INNER_ALPHA, 1)
  local line = bar:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)

  local border = { shell = true, base = look.alpha, alpha = look.alpha, colorName = look.edge, divider = look.divider }
  local function paintLine()
    line:SetColorTexture(Theme.color(border.divider, border.alpha))
  end
  function border.set(name, a)
    border.colorName, border.alpha = name, a
    outerRing.set(name, a)
    innerRing.set("bg", a * Shell.INNER_ALPHA)
    paintLine()
    if border.nine then
      border.nine:SetAlpha(a)
    end
  end
  border.rings = { outerRing, innerRing }
  ns.Bind(line, paintLine)
  return border, edge, line
end

-- Shadow -------------------------------------------------------------------------------------

-- Rings of four strips around the window (a filled rectangle would darken a transparent
-- window from behind). A frame of its own, so it can fade as a whole and never takes clicks.
local function buildShadow(frame, scale)
  local holder = CreateFrame("Frame", nil, frame)
  holder:EnableMouse(false)
  local step = Shell.SHADOW_STEP
  for ring, alpha in ipairs(Shell.SHADOW_ALPHA) do
    local near, far = (ring - 1) * step, ring * step
    local function strip(p1, x1, y1, p2, x2, y2)
      local t = holder:CreateTexture(nil, "BACKGROUND")
      t:SetColorTexture(0, 0, 0, alpha * scale)
      t:SetPoint("TOPLEFT", frame, p1, x1, y1)
      t:SetPoint("BOTTOMRIGHT", frame, p2, x2, y2)
    end
    strip("TOPLEFT", -far, far, "TOPRIGHT", far, near)
    strip("BOTTOMLEFT", -far, -near, "BOTTOMRIGHT", far, -far)
    strip("TOPLEFT", -far, near, "BOTTOMLEFT", -near, -near)
    strip("TOPRIGHT", near, near, "BOTTOMRIGHT", far, -near)
  end
  return holder
end

-- Active window --------------------------------------------------------------------------------

local function paint(shell)
  local look = Shell.LOOK[shell.frame == active and "active" or "idle"]
  local border = shell.border
  border.base, border.divider = look.alpha, look.divider
  border.colorName = look.edge
  W.SetColor(shell.titleText, look.title)
  local WS = ns.WindowStyle
  if WS and WS.State(shell.frame) then
    WS.Repaint(shell.frame)
  else
    border.set(look.edge, look.alpha)
  end
end

function Shell.SetActive(frame)
  local shell = shells[frame]
  if not shell or active == frame then
    return
  end
  local previous = active and shells[active]
  active = frame
  if previous then
    paint(previous)
  end
  paint(shell)
end

-- Window style ---------------------------------------------------------------------------------

-- Background: the stone of the skin in place of the flat fill. A window whose own background
-- color was changed (note, drawing, calculator ...) keeps that color.
local function restyleBack(shell)
  local frame, style, WS = shell.frame, shell.style, ns.WindowStyle
  local own = style ~= nil and WS ~= nil and style.bg ~= WS.FALLBACK.bg
  local rock = Skins.Apply(frame, "rock", Skins.isForever() and not own)
  for _, tex in ipairs(shell.flat or { frame.fgBack }) do
    tex:SetShown(rock == nil)
  end
  if rock then
    if shell.fade == "main" then
      W.FadeWithWindow(rock)
    else
      rock:SetAlpha(style and style.alpha or 1)
    end
  end
end

-- The metal frame lies outside the window: the clamp keeps frame and metal on the screen, so the
-- title strip and the close button stay reachable at every screen edge. Insets: left, right, top,
-- bottom, positive values to the right and up (the client's own convention).
local function clampToFrame(frame, nine)
  local o = nine and nine.outset
  pcall(frame.SetClampRectInsets, frame, o and -o.left or 0, o and o.right or 0, o and o.top or 0, o and -o.bottom or 0)
end

-- Title strip ------------------------------------------------------------------------------------

-- The strip and every frame below it, parents first (a window adds its buttons after Attach).
local function stripFrames(bar)
  local list, head = { bar }, 1
  while list[head] and #list < 300 do
    local ok, children = pcall(function()
      return { list[head]:GetChildren() }
    end)
    head = head + 1
    for _, child in ipairs(ok and children or {}) do
      list[#list + 1] = child
    end
  end
  return list
end

-- The edge overlay lies at a high frame level, so the strip would sit below the metal band. Each frame
-- gets its level set absolutely (a client that moves children with the parent changes nothing here).
local function liftStrip(shell, on)
  local bar = shell.titleBar
  if on == (shell.lifted ~= nil) then
    return
  end
  local shift = shell.lifted
  if on then
    shift = shell.edge:GetFrameLevel() + 2 - bar:GetFrameLevel()
    if shift <= 0 then
      return
    end
  end
  local sign = on and 1 or -1
  local frames = stripFrames(bar)
  local levels = {}
  for i, f in ipairs(frames) do
    levels[i] = f:GetFrameLevel()
  end
  for i, f in ipairs(frames) do
    pcall(f.SetFrameLevel, f, math.max(0, levels[i] + sign * shift))
  end
  shell.lifted = on and shift or nil
end

-- The band's own fill (shell.bandFill): a texture of the window frame, so it lies below the metal (the rim stays
-- visible) and below the strip, and fills whatever the art leaves clear. It takes the opacity like the strip fill
-- does: the main window follows its own opacity, every other window the one WindowStyle reports.
local function paintBandFill(shell)
  local fill = shell.bandFill
  if not fill then
    return
  end
  if shell.fade == "main" then
    W.FadeWithWindow(fill)
    return
  end
  local style, WS = shell.style, ns.WindowStyle
  fill:SetAlpha(style and WS and WS.Edge(style.alpha) or 1)
end

local function restyleBandFill(shell, band)
  local fill = shell.bandFill
  if not band then
    if fill then
      fill:Hide()
    end
    return
  end
  if not fill then
    fill = shell.frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    local r, g, b = U.hex(Skins.list.forever.metrics.bar.backdrop)
    fill:SetColorTexture(r, g, b, 1)
    shell.bandFill = fill
  end
  if shell.fillKey ~= shell.barKey then
    shell.fillKey = shell.barKey
    -- Both sides hang on the same reference (the window), so the pixel rounding of one side never opens a gap
    -- the other does not have. The bleed lies under the metal, which is opaque there.
    local bleed = Skins.list.forever.metrics.bar.bleed
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", shell.frame, "TOPLEFT", -bleed.side, band.top + bleed.top)
    fill:SetPoint("BOTTOMRIGHT", shell.frame, "TOPRIGHT", bleed.side, band.bottom)
  end
  fill:Show()
  paintBandFill(shell)
end

-- Flat look: the strip at the top of the window on a dark fill. Forever look: the strip over the metal
-- band above the window, on the band's own fill (the strip's dark fill stays hidden).
local function restyleBar(shell)
  local bar = shell.titleBar
  local band = shell.useBand and Skins.BandRect(shell.edge) or nil
  local key = band and string.format("%g:%g", band.top, band.height) or "strip"
  if key ~= shell.barKey then
    shell.barKey = key
    bar:ClearAllPoints()
    if band then
      local margin = Skins.list.forever.metrics.bar.margin
      bar:SetPoint("TOPLEFT", shell.frame, "TOPLEFT", margin, band.top)
      bar:SetPoint("TOPRIGHT", shell.frame, "TOPRIGHT", -margin, band.top)
      bar:SetHeight(band.height)
    else
      bar:SetPoint("TOPLEFT")
      bar:SetPoint("TOPRIGHT")
      bar:SetHeight(shell.stripHeight)
    end
  end
  shell.band = band
  shell.barFill:SetShown(band == nil)
  restyleBandFill(shell, band)
  liftStrip(shell, band ~= nil)
  shell.titleCap = band and band.height - Skins.list.forever.metrics.bar.textPad or nil
  Skins.StyleTitle(shell.titleText, shell.role, shell.family, shell.titleCap)
end

-- Metal frame, flat edge lines and the divider under the title strip.
local function restyleFrame(shell)
  local border = shell.border
  local nine = Skins.Apply(shell.edge, "nine")
  border.nine = nine
  clampToFrame(shell.frame, nine)
  for _, ring in ipairs(border.rings) do
    ring.show(nine == nil)
  end
  shell.divider:SetShown(nine == nil)
  paint(shell)
end

function Shell.Style(frame, style, parts)
  local shell = shells[frame]
  if not shell then
    return
  end
  shell.style, shell.flat = style, parts and parts.bg
  restyleBack(shell)
  paintBandFill(shell)
end

-- The top window that is still open takes over when the active one closes.
local function promote()
  local best, bestStrata, bestLevel
  for frame in pairs(shells) do
    if frame:IsShown() then
      local strata = STRATA[frame:GetFrameStrata() or ""] or 0
      local level = frame:GetFrameLevel() or 0
      if not best or strata > bestStrata or (strata == bestStrata and level > bestLevel) then
        best, bestStrata, bestLevel = frame, strata, level
      end
    end
  end
  if best then
    Shell.SetActive(best)
  end
end

-- Within the strata only: the strata (and with it the order against the game UI) stays.
local function raise(frame)
  if InCombatLockdown() and frame:IsProtected() then
    return
  end
  pcall(frame.Raise, frame)
end

-- A click on any child (text, buttons) never reaches the window's own OnMouseDown, so the
-- client's global click event covers those: the hit frame's parents tell the window.
local watcher
local function watchClicks()
  if watcher then
    return
  end
  watcher = CreateFrame("Frame")
  if not pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN") then
    return
  end
  watcher:SetScript(
    "OnEvent",
    ns.Wrap("shell-click", function()
      local foci, legacy = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
      local node = foci and foci()[1] or legacy and legacy() or nil
      for _ = 1, 40 do
        if type(node) ~= "table" then
          return
        elseif shells[node] then
          Shell.SetActive(node)
          return
        end
        node = ns.SafeParent(node)
      end
    end)
  )
end

-- Moving ---------------------------------------------------------------------------------------

-- The handle (the title strip of every window) moves the frame. The handle takes the mouse itself,
-- so a client that gives child frames the mouse never swallows the drag. The frame's own drag
-- scripts (saving the position, locks) run in place of the plain move when it has them; its
-- buttons are children of the strip and keep their clicks.
function Shell.MakeDraggable(frame, handle)
  handle = handle or frame
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  local function own(script)
    return handle ~= frame and type(frame.GetScript) == "function" and frame:GetScript(script) or nil
  end
  handle:SetScript("OnDragStart", function()
    local run = own("OnDragStart")
    if run then
      run(frame)
    else
      frame:StartMoving()
    end
  end)
  handle:SetScript("OnDragStop", function()
    local run = own("OnDragStop")
    if run then
      run(frame)
    else
      frame:StopMovingOrSizing()
    end
  end)
end

-- Brings a window that is larger than the screen, or saved outside of it, back on the screen
-- (the clamp of the client keeps a window in reach only while it is moved). Units of the frame.
function Shell.FitToScreen(frame)
  local parent = UIParent
  local scale, ui = frame:GetEffectiveScale(), parent:GetEffectiveScale()
  if not scale or scale <= 0 or not ui then
    return
  end
  local screenW, screenH = parent:GetWidth() * ui / scale, parent:GetHeight() * ui / scale
  local w, h = frame:GetWidth(), frame:GetHeight()
  if w > screenW or h > screenH then
    w, h = math.min(w, screenW), math.min(h, screenH)
    frame:SetSize(w, h)
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  if not (left and top) then
    return
  end
  local x, y = math.max(0, math.min(left, screenW - w)), math.max(h, math.min(top, screenH))
  if x ~= left or y ~= top then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", x, y)
  end
end

-- Esc -----------------------------------------------------------------------------------------
-- Our windows stay out of UISpecialFrames: the client closes every special frame and panel (the
-- vendor, the bags) with one Esc. Instead an open window takes Esc itself and closes alone, the
-- newest first; with none open Esc reaches the client untouched.

local Esc = { list = {} }
ns.EscStack = Esc

-- frame -> onEscape(frame) of RegisterEsc: may take the key instead of the close.
local escHandlers = setmetatable({}, { __mode = "k" })
local escHooked = setmetatable({}, { __mode = "k" })
-- Windows that left the stack on purpose (pinned, closed): Esc.Close does not take them back.
local escOff = setmetatable({}, { __mode = "k" })

function Esc.Remove(frame)
  for i = #Esc.list, 1, -1 do
    if Esc.list[i] == frame then
      table.remove(Esc.list, i)
    end
  end
end

function Esc.Push(frame)
  Esc.Remove(frame)
  table.insert(Esc.list, frame)
end

-- The newest window that is open and on screen: a window can be shown while a hidden parent (or
-- the hidden interface) keeps it out of sight, and Hide() on it would change nothing visible.
function Esc.Top()
  for i = #Esc.list, 1, -1 do
    local f = Esc.list[i]
    if f:IsShown() and f:IsVisible() then
      return f
    end
  end
end

-- One Esc: an open dropdown first, then the newest visible window (or its onEscape, which returns
-- true when it took the key, like leaving a focus). A window that is still on screen after Hide()
-- did not take the key: Esc goes on to the next one. False when nothing was closed.
-- receiver: the window whose key handler runs. It joins the stack if a client that dropped the
-- show hook (a later SetScript) left it out.
function Esc.Close(receiver)
  if ns.Popups and ns.Popups.close() then
    return true
  end
  if receiver and escHooked[receiver] and not escOff[receiver] and receiver:IsShown() then
    local known = false
    for _, f in ipairs(Esc.list) do
      known = known or f == receiver
    end
    if not known then
      Esc.Push(receiver)
    end
  end
  local snapshot = { unpack(Esc.list) }
  for i = #snapshot, 1, -1 do
    local f = snapshot[i]
    if f:IsShown() and f:IsVisible() then
      local onEscape = escHandlers[f]
      if onEscape and onEscape(f) then
        return true
      end
      f:Hide()
      if not f:IsVisible() then
        return true
      end
    end
  end
  return false
end

-- Support line for /fg diag: the stack as the Esc key sees it.
function Esc.Report()
  local parts = {}
  for i = #Esc.list, 1, -1 do
    local f = Esc.list[i]
    if #parts < 8 then
      parts[#parts + 1] = string.format(
        "%s %s/%s",
        f:GetName() or "?",
        f:IsShown() and "shown" or "hidden",
        f:IsVisible() and "visible" or "unseen"
      )
    end
  end
  return string.format(
    "esc stack: %d windows%s%s",
    #Esc.list,
    #parts > 0 and " (newest first): " or "",
    table.concat(parts, ", ")
  )
end

-- Propagation stays on for every other key, so walking, bars and chat keep working. In combat
-- the client may refuse the change; the window still closes then.
local function onEscKey(self, key)
  local _, handled = ns.Safe("esc-key", function()
    return key == "ESCAPE" and Esc.Close(self)
  end)
  ns.PropagateKeys(self, not handled)
end

-- on = true: the window takes part (newest on top), false: it leaves, e.g. a pinned note that
-- stays open on Esc. A client without key propagation keeps the old way over UISpecialFrames.
function Shell.SetEsc(frame, on)
  if not ns.can.propagateKeyboard then
    local name = ns.can.specialFrames and frame:GetName()
    if name then
      for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then
          table.remove(UISpecialFrames, i)
        end
      end
      if on then
        table.insert(UISpecialFrames, name)
      end
    end
    return
  end
  escOff[frame] = not on or nil
  if not on then
    Esc.Remove(frame)
    pcall(frame.EnableKeyboard, frame, false)
    return
  end
  -- A window with a key handler of its own (the main window) calls Esc.Close from it.
  if not frame:GetScript("OnKeyDown") then
    frame:SetScript("OnKeyDown", onEscKey)
  end
  ns.PropagateKeys(frame, true)
  pcall(frame.EnableKeyboard, frame, true)
  Esc.Push(frame)
end

-- A window that closes on Esc while it is shown. onEscape(frame) is optional: it may take the key
-- instead of the close (return true).
function Shell.RegisterEsc(frame, onEscape)
  escHandlers[frame] = onEscape
  if not escHooked[frame] then
    escHooked[frame] = true
    frame:HookScript("OnShow", function()
      Shell.SetEsc(frame, true)
    end)
    frame:HookScript("OnHide", function()
      Shell.SetEsc(frame, false)
    end)
  end
  Shell.SetEsc(frame, frame:IsShown())
end

-- Attach --------------------------------------------------------------------------------------

function Shell.Attach(frame, opts)
  if shells[frame] then
    return shells[frame]
  end
  opts = opts or {}
  local shell = { frame = frame, fade = opts.fade, role = opts.role or "ui", family = opts.family or "heading" }
  shell.useBand = opts.band
  if shell.useBand == nil then
    shell.useBand = opts.fade ~= "main"
  end
  shell.stripHeight = opts.titleHeight or 22
  shells[frame] = shell

  if opts.shadow then
    shell.shadow = buildShadow(frame, opts.shadowScale or 1)
  end

  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(shell.stripHeight)
  shell.titleBar = bar
  titleBars[bar] = shell
  shell.barFill = W.Fill(bar, "surface3", 1)
  shell.bars = { shell.barFill }
  shell.titleText = W.Text(bar, {
    key = opts.title,
    text = opts.text,
    role = shell.role,
    family = shell.family,
    color = Shell.LOOK.idle.title,
  })
  shell.titleText:SetPoint("LEFT", 8, 0)
  shell.titleText:SetPoint("RIGHT", -4, 0)

  shell.border, shell.edge, shell.divider = buildEdge(frame, bar)
  -- Read by Skins.bandHeight when the metal frame is first built (the ns.Bind below runs after this line).
  shell.edge.bandSize = opts.bandSize
  -- On the title's own list, after the font of W.Text: the order of two owners is not defined.
  ns.Bind(shell.titleText, function(fs)
    Skins.StyleTitle(fs, shell.role, shell.family, shell.titleCap)
  end)

  local function pressed()
    Shell.SetActive(frame)
    raise(frame)
  end
  Shell.MakeDraggable(frame, bar)
  frame:HookScript("OnMouseDown", ns.Wrap("shell-down", pressed))
  bar:HookScript("OnMouseDown", ns.Wrap("shell-down", pressed))
  frame:HookScript("OnShow", function()
    Shell.SetActive(frame)
  end)
  frame:HookScript("OnHide", function()
    if active == frame then
      active = nil
      paint(shell)
      promote()
    end
  end)
  watchClicks()

  if opts.active then
    Shell.SetActive(frame)
  else
    paint(shell)
  end
  ns.Bind(shell, function()
    restyleFrame(shell)
    restyleBar(shell)
    restyleBack(shell)
  end)
  return shell
end
