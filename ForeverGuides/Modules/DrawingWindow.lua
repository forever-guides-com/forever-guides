-- Drawing windows: one small movable, resizable window per drawing (pool, at most
-- MAX_OPEN open at once) that shows the saved drawing read-only, scaled to fit.
-- A pinned window keeps its position and size and ignores Esc (only the X or the pin
-- button closes it), exactly like a pinned note window.
-- Look: background color, opacity, auto-hiding title bar and buttons come from
-- Modules/WindowStyle.lua (per-window overrides here, else the global defaults of the
-- settings page). The opacity applies to the window fill and border only: the drawing
-- itself stays fully drawn, and its white canvas is part of the image. "White canvas
-- transparent" (clearBg) leaves the canvas out so that only the strokes show.
-- Saved per drawing in ns.db.frames.drawingWindows[id] =
--   { x, y, w, h, pinned, shown, bg, alpha, autoHide, clearBg }
-- (validated on every read, entries of deleted drawings are dropped).
-- Opening, pinning or restyling never touches the drawing, its order or its timestamps.
local _, ns = ...
local W, L, Theme, U, DR, V, WS = ns.W, ns.L, ns.Theme, ns.U, ns.Drawings, ns.DrawingView, ns.WindowStyle

local DW = { byId = {}, pool = {}, made = 0 }
ns.DrawingWindow = DW

DW.MAX_OPEN = 8
local HEAD_H, PAD = 22, 4
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 90, 1400, 1000
local POS_LIMIT = 10000

ns.AddLocale("enUS", {
  ["drawwin.pin"] = "Pin",
  ["drawwin.pinTip"] = "Fixes position and size.\nEsc no longer closes it, only X or this button.",
  ["drawwin.close"] = "Close window",
  ["drawwin.editor"] = "Open in editor",
  ["drawwin.grip"] = "Drag to resize",
  ["drawwin.unreadable"] = "This drawing could not be read.",
  ["drawwin.limit"] = "At most %d drawing windows, close one first.",
  ["drawwin.usage"] = "Usage: /fg draw window <name>",
})

ns.AddLocale("deDE", {
  ["drawwin.pin"] = "Anheften",
  ["drawwin.pinTip"] = "Fixiert Position und Größe.\nEsc schließt nicht mehr, nur X oder dieser Knopf.",
  ["drawwin.close"] = "Fenster schließen",
  ["drawwin.editor"] = "Im Editor öffnen",
  ["drawwin.grip"] = "Ziehen zum Skalieren",
  ["drawwin.unreadable"] = "Diese Zeichnung ließ sich nicht lesen.",
  ["drawwin.limit"] = "Höchstens %d Zeichnungsfenster, erst eines schließen.",
  ["drawwin.usage"] = "Benutzung: /fg draw window <Name>",
})

-- Saved state ---------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Only valid fields survive. pinned/shown/clearBg are stored when true, autoHide as an
-- explicit override either way, bg and alpha only when they parse.
local function cleanEntry(raw)
  local e = {}
  if type(raw) ~= "table" then
    return e
  end
  if finite(raw.x) and finite(raw.y) then
    e.x, e.y = U.clamp(raw.x, -POS_LIMIT, POS_LIMIT), U.clamp(raw.y, -POS_LIMIT, POS_LIMIT)
  end
  if finite(raw.w) and finite(raw.h) then
    e.w, e.h = math.floor(U.clamp(raw.w, MIN_W, MAX_W)), math.floor(U.clamp(raw.h, MIN_H, MAX_H))
  end
  e.pinned = raw.pinned == true or nil
  e.shown = raw.shown == true or nil
  e.clearBg = raw.clearBg == true or nil
  if type(raw.autoHide) == "boolean" then
    e.autoHide = raw.autoHide
  end
  e.bg = WS.cleanHex(raw.bg, nil)
  e.alpha = WS.cleanAlpha(raw.alpha, nil)
  return e
end

local checked

-- The saved table, repaired once per database table: entries of drawings that no
-- longer exist are dropped.
local function store()
  local frames = ns.db.frames
  local t = frames.drawingWindows
  if type(t) ~= "table" then
    t = {}
    frames.drawingWindows = t
  end
  if checked ~= t then
    checked = t
    for id, raw in pairs(t) do
      if type(id) == "string" and DR.get(id) then
        t[id] = cleanEntry(raw)
      else
        t[id] = nil
      end
    end
  end
  return t
end

-- A validated copy of the saved state of drawing `id` (empty when nothing is saved).
local function read(id)
  return cleanEntry(store()[id])
end
DW.Entry = read

-- patch: x, y, w, h, pinned, shown, clearBg, autoHide, alpha, bg (false = back to the default),
-- resetStyle = true drops bg, alpha, autoHide and clearBg. Returns the saved entry or nil
-- for an unknown drawing.
function DW.Update(id, patch)
  if not DR.get(id) then
    return nil
  end
  local e = read(id)
  if patch.resetStyle then
    e.bg, e.alpha, e.autoHide, e.clearBg = nil, nil, nil, nil
  end
  for _, key in ipairs({ "x", "y", "w", "h", "pinned", "shown", "clearBg", "autoHide", "alpha" }) do
    if patch[key] ~= nil then
      e[key] = patch[key]
    end
  end
  if patch.bg ~= nil then
    e.bg = patch.bg or nil
  end
  local clean = cleanEntry(e)
  store()[id] = clean
  return clean
end

local function forget(id)
  store()[id] = nil
end

-- Looks ------------------------------------------------------------------------------------

function DW.Style(id)
  return WS.Resolve("drawing", read(id))
end

local function nameOf(item)
  return item.name ~= "" and item.name or L["draw.untitled"]
end

-- Window pool ---------------------------------------------------------------------------

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if f.drawId and left and top then
    DW.Update(f.drawId, { x = left, y = top })
  end
end

local function saveSize(f)
  if f.drawId then
    DW.Update(f.drawId, { w = f:GetWidth(), h = f:GetHeight() })
  end
end

local function place(f, e)
  f:ClearAllPoints()
  if e.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", e.x, e.y)
  else
    local offset = (DW.made % 6) * 24
    f:SetPoint("CENTER", UIParent, "CENTER", offset, -offset)
  end
end

-- A first size that shows the drawing at about double size, within sane limits.
local function defaultSize(item)
  if item.w > 0 and item.h > 0 then
    return U.clamp(item.w * 2 + 2 * PAD, MIN_W, 420), U.clamp(item.h * 2 + HEAD_H + 2 * PAD, MIN_H, 360)
  end
  return 240, 180
end

-- Shows the stored drawing scaled to the free area (decodes only when the data changed).
local function paint(f)
  local item = DR.get(f.drawId)
  if not item then
    return
  end
  local w, h = f:GetSize()
  local availW, availH = math.max(1, w - 2 * PAD), math.max(1, h - HEAD_H - 2 * PAD)
  if f.loaded ~= item.data then
    f.loaded = item.data
    local d = DR.load(f.drawId)
    if d then
      f.view:SetScale(V.FitScale(d.w, d.h, availW, availH))
    end
    f.view:SetDrawing(d)
  end
  local d = f.view.drawing
  f.view.frame:SetShown(d ~= nil)
  f.msg:SetShown(d == nil)
  f.msg:SetWidth(math.max(40, availW))
  if d then
    f.view:SetScale(V.FitScale(d.w, d.h, availW, availH))
  end
end

-- A shadow under the text keeps it readable on a transparent window.
local function applyShadows(f, style)
  local on = WS.TextShadow(style)
  local r, g, b = Theme.rgb("text")
  WS.ApplyShadow(f.title, on, r, g, b)
  WS.ApplyShadow(f.msg, on, r, g, b)
end

-- Background, opacity, border and the auto-hiding chrome (WS.Apply), the toggle glyph and
-- the optional canvas.
function DW.ApplyLook(f)
  local e = read(f.drawId)
  local style = WS.Resolve("drawing", e)
  WS.Apply(f, style, f.styleParts)
  f.autoHide:SetSelected(style.autoHide)
  f.view:SetSkipBackground(e.clearBg == true)
  applyShadows(f, style)
  return style
end

function DW.Refresh(id)
  local f, item = DW.byId[id], DR.get(id)
  if not (f and item) then
    return
  end
  local e = read(id)
  f.title:SetText(nameOf(item))
  f.pin:SetSelected(e.pinned)
  f.grip:SetShown(not e.pinned)
  f:SetMovable(not e.pinned)
  f:SetResizable(not e.pinned)
  ns.WindowShell.SetEsc(f, not e.pinned and f:IsShown())
  DW.ApplyLook(f)
  paint(f)
end

-- A look change without a drawing change (global defaults, the panel): repaints the frame only.
function DW.Restyle(id)
  local f = DW.byId[id]
  if f and DR.get(id) then
    DW.ApplyLook(f)
  end
end

function DW.RestyleAll()
  for id in pairs(DW.byId) do
    DW.Restyle(id)
  end
end

-- patch: { bg = "rrggbb" | false (default), alpha = 0..1, autoHide = bool, clearBg = bool }
function DW.SetLook(id, patch)
  if DW.Update(id, patch) then
    DW.Restyle(id)
  end
end

function DW.ToggleAutoHide(id)
  if DR.get(id) then
    DW.SetLook(id, { autoHide = not DW.Style(id).autoHide })
  end
end

function DW.SetPinned(id, on)
  if DW.Update(id, { pinned = on and true or false }) then
    DW.Refresh(id)
  end
end

-- "Save as default": this window's color, opacity and auto-hide become the default of all drawing windows.
function DW.SaveLookAsDefault(id)
  if DR.get(id) then
    WS.SaveDefault("drawing", DW.Style(id))
  end
end

-- "Reset to default": drops the overrides of this window.
function DW.ResetLook(id)
  if DW.Update(id, { resetStyle = true }) then
    DW.Restyle(id)
  end
end

-- True while the appearance panel or the color picker of this window is open: the
-- auto-hiding chrome stays visible then (the palette hangs on the panel).
function DW.ChromeBusy(f)
  return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
end

function DW.OpenLookPanel(f)
  return WS.OpenPanel(f.look, {
    frame = f,
    kind = "drawing",
    get = function()
      return DW.Style(f.drawId)
    end,
    set = function(patch)
      DW.SetLook(f.drawId, patch)
    end,
    onSaveDefault = function()
      DW.SaveLookAsDefault(f.drawId)
    end,
    onReset = function()
      DW.ResetLook(f.drawId)
    end,
    clearBg = {
      get = function()
        return read(f.drawId).clearBg == true
      end,
      set = function(on)
        DW.SetLook(f.drawId, { clearBg = on })
      end,
    },
  })
end

local function newFrame()
  DW.made = DW.made + 1
  local f = CreateFrame("Frame", "FGDrawingWindow" .. DW.made, UIParent)
  -- Above the main addon window (strata "MEDIUM"), like the note windows.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.view = V.New(f, { scale = 1, kind = "window" })
  f.view.frame:SetPoint("CENTER", f, "CENTER", 0, -HEAD_H / 2)
  f.msg = W.Text(f, { key = "drawwin.unreadable", role = "ui", color = "textMuted", wrap = true, justify = "CENTER" })
  f.msg:SetPoint("CENTER", f, "CENTER", 0, -HEAD_H / 2)
  f.msg:Hide()

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    if f.drawId and not read(f.drawId).pinned then
      WS.Hold(f, "move", true)
      f:StartMoving()
    end
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("drawwin-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )

  -- Buttons from the right: close, pin, auto-hide, appearance, editor.
  local last
  local function button(icon, tooltip, tooltipText, onClick)
    local b = W.Action(f.bar, { icon = icon, size = 18, tooltip = tooltip, tooltipText = tooltipText })
    if last then
      b:SetPoint("RIGHT", last, "LEFT", -2, 0)
    else
      b:SetPoint("RIGHT", -2, 0)
    end
    b:SetScript("OnClick", ns.Wrap("drawwin-button", onClick))
    last = b
    return b
  end
  f.close = button("close", "drawwin.close", nil, function()
    f:Hide()
  end)
  f.pin = button("pin", "drawwin.pin", "drawwin.pinTip", function()
    if f.drawId then
      DW.SetPinned(f.drawId, not read(f.drawId).pinned)
    end
  end)
  f.autoHide = button("eye-off", "wstyle.autoHide", "wstyle.autoHideTip", function()
    DW.ToggleAutoHide(f.drawId)
  end)
  f.look = button("palette", "wstyle.title", nil, function()
    DW.OpenLookPanel(f)
  end)
  f.editor = button("pencil", "drawwin.editor", nil, function()
    if f.drawId then
      ns.DrawingEditor.Open(f.drawId)
    end
  end)
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 6, 0)
  f.title:SetPoint("RIGHT", f.editor, "LEFT", -4, 0)

  f.grip = CreateFrame("Button", nil, f)
  f.grip:SetSize(14, 14)
  f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
  f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
  f.grip.tex = f.grip:CreateTexture(nil, "OVERLAY")
  f.grip.tex:SetAllPoints()
  f.grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetScript("OnMouseDown", function()
    if f.drawId and not read(f.drawId).pinned then
      WS.Hold(f, "size", true)
      f:StartSizing("BOTTOMRIGHT")
    end
  end)
  f.grip:SetScript(
    "OnMouseUp",
    ns.Wrap("drawwin-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      ns.WindowShell.FitToScreen(f)
      saveSize(f)
      savePosition(f)
      if f.drawId then
        paint(f)
      end
    end)
  )
  f.grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["drawwin.grip"])
  end)
  f.grip:SetScript("OnLeave", ns.HideTooltip)

  -- What WS.Apply restyles: the fill, the border and everything that auto-hides. The
  -- drawing (f.view) is content and never fades.
  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, f.grip },
    busy = function()
      return DW.ChromeBusy(f)
    end,
  }

  f:SetScript("OnSizeChanged", function()
    if f.drawId then
      ns.Debounce(f.view, 0.1, function()
        if f.drawId then
          paint(f)
        end
      end)
    end
  end)
  f:SetScript(
    "OnHide",
    ns.Wrap("drawwin-hide", function()
      ns.WindowShell.SetEsc(f, false)
      if WS.PanelOpenFor(f) then
        WS.ClosePanel()
      end
      local id = f.drawId
      if id then
        DW.byId[id] = nil
        f.drawId, f.loaded = nil, nil
        f.view:Clear()
        DW.Update(id, { shown = false })
        DW.pool[#DW.pool + 1] = f
      end
    end)
  )
  f:Hide()
  return f
end

-- Public API ----------------------------------------------------------------------------

function DW.IsOpen(id)
  return DW.byId[id] ~= nil
end

function DW.OpenCount()
  local n = 0
  for _ in pairs(DW.byId) do
    n = n + 1
  end
  return n
end

-- Opens the window for drawing `id` (or raises it). Returns the frame, or nil, reason
-- ("missing" | "limit").
function DW.Open(id)
  local item = DR.get(id)
  if not item then
    return nil, "missing"
  end
  local f = DW.byId[id]
  local fresh = f == nil
  if fresh then
    if DW.OpenCount() >= DW.MAX_OPEN then
      ns.Notify(string.format(L["drawwin.limit"], DW.MAX_OPEN), "warning")
      return nil, "limit"
    end
    f = table.remove(DW.pool) or newFrame()
    f.drawId = id
    DW.byId[id] = f
    local e = read(id)
    local w, h = defaultSize(item)
    f:SetSize(e.w or w, e.h or h)
    place(f, e)
    f:Show()
    ns.WindowShell.FitToScreen(f)
    DW.Update(id, { shown = true })
  end
  f:Raise()
  DW.Refresh(id)
  if fresh then
    -- A pooled frame may still be faded from its last drawing: show the chrome, it hides again by itself.
    WS.Reveal(f)
  end
  return f
end

function DW.Close(id)
  local f = DW.byId[id]
  if f then
    f:Hide()
  end
end

function DW.Toggle(id)
  if DW.IsOpen(id) then
    DW.Close(id)
  else
    DW.Open(id)
  end
end

function DW.CloseAll()
  local n = 0
  for _, f in pairs(DW.byId) do
    f:Hide()
    n = n + 1
  end
  return n
end

function DW.RefreshAll()
  for id in pairs(DW.byId) do
    DW.Refresh(id)
  end
end

-- Opens the windows that were open at logout (in list order, at most MAX_OPEN).
function DW.RestoreAll()
  local opened = 0
  for _, item in ipairs(DR.list()) do
    if opened < DW.MAX_OPEN and read(item.id).shown then
      if DW.Open(item.id) then
        opened = opened + 1
      end
    end
  end
end

-- /fg draw window <name>
function DW.Slash(rest)
  rest = U.trim(rest or "")
  if rest == "" then
    ns.Notify(L["drawwin.usage"], "info")
    return
  end
  local item = ns.DrawingEditor.Find(rest)
  if not item then
    ns.Notify(string.format(L["draw.slash.none"], rest), "info")
    return
  end
  DW.Open(item.id)
end

ns.On("FG_DRAWINGS_CHANGED", function(_, kind, id)
  if kind == "delete" and id then
    DW.Close(id)
    forget(id)
  elseif id and kind ~= "order" and DW.byId[id] then
    DW.Refresh(id)
  end
end)
ns.On("FG_UI_REFRESHED", function()
  DW.RefreshAll()
end)
-- Defaults changed on the settings page (or by "Save as default"): windows follow at once.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if WS.AffectsKind(path, "drawing") then
    DW.RestyleAll()
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and ns.db.frames then
    DW.RestoreAll()
  end
end)
