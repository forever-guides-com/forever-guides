-- The calculator window: one movable, resizable window (not pooled) around the content of
-- Modules/CalcView.lua, plus the sidebar page, the key binding and the top-level /calc.
-- Look (background, opacity, auto-hiding title bar) comes from Modules/WindowStyle.lua (kind
-- "calc"). Position, size, scale, the per-window look, the open state and the side panel (history
-- and memory, grows the window to the right) live in ns.db.frames.calcWindow; w is the width of
-- the calculator part, the side panel comes on top. Nothing here touches protected frames, so it
-- works in combat.
--
-- Esc: with focus in the input the first press empties it, the next one closes the window; without
-- focus the window closes at once (Shell.RegisterEsc, newest window first).
local _, ns = ...
local W, L, Theme, U, WS, V = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle, ns.CalcView

local CW = {}
ns.CalcWindow = CW

local HEAD_H = 22
local MIN_W, MIN_H, MAX_W, MAX_H = 240, 360, 560, 760
local DEFAULT_W, DEFAULT_H = 280, 420
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local KEY = "FOREVERGUIDES_CALC"

-- Look defaults of this window kind: settings calcWindowBg / Alpha / AutoHide.
WS.PREFIX.calc = "calcWindow"

ns.AddLocale("enUS", {
  ["calcui.win.title"] = "Calculator",
  ["calcui.win.close"] = "Close calculator",
  ["calcui.win.open"] = "Open in the addon",
  ["calcui.win.scaleTip"] = "Drag to move, {key:windowScale} changes the size.",
  ["calcui.win.grip"] = "Drag to resize",
  ["calcui.win.history"] = "History and memory",
  ["calcui.win.historyTip"] = "Shows or hides the panel.",
  ["binding.calc"] = "Calculator on or off",
})
ns.AddLocale("deDE", {
  ["calcui.win.title"] = "Rechner",
  ["calcui.win.close"] = "Rechner schließen",
  ["calcui.win.open"] = "Im Addon öffnen",
  ["calcui.win.scaleTip"] = "Ziehen verschiebt, {key:windowScale} ändert die Größe.",
  ["calcui.win.grip"] = "Zum Ändern der Größe ziehen",
  ["calcui.win.history"] = "Verlauf und Speicher",
  ["calcui.win.historyTip"] = "Zeigt oder versteckt das Feld.",
  ["binding.calc"] = "Rechner ein oder aus",
})

local frame

local function frameDb()
  local frames = ns.db.frames
  if type(frames.calcWindow) ~= "table" then
    frames.calcWindow = {}
  end
  return frames.calcWindow
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

-- Extra width of the open side panel.
local function sideExtra()
  return frameDb().side == true and V.SIDE_W + V.SIDE_GAP or 0
end

local function setBounds(f)
  local extra = sideExtra()
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W + extra, MIN_H, MAX_W + extra, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W + extra, MIN_H)
  end
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetSize(
    U.clamp(finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W) + sideExtra(),
    U.clamp(finite(db.h) and db.h or DEFAULT_H, MIN_H, MAX_H)
  )
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function saveSize(f)
  local db = frameDb()
  db.w, db.h = f:GetWidth() - sideExtra(), f:GetHeight()
end

-- Shows or hides the side panel; the window grows to the right, the left edge stays.
function CW.SetSide(on)
  local db = frameDb()
  db.side = on == true
  if frame then
    savePosition(frame)
    frame.view:SetSideShown(db.side)
    place(frame)
  end
end

function CW.ToggleSide()
  CW.SetSide(frameDb().side ~= true)
end

-- The content asks for more or less height (the row of extra keys).
local function resizeBy(f, dh)
  local db = frameDb()
  savePosition(f)
  db.w = f:GetWidth() - sideExtra()
  db.h = U.clamp(f:GetHeight() + dh, MIN_H, MAX_H)
  place(f)
end

-- Look -----------------------------------------------------------------------------------------

function CW.Style()
  return WS.Resolve("calc", frameDb().style)
end

local function applyLook(f)
  local style = CW.Style()
  WS.Apply(f, style, f.styleParts)
  WS.ApplyShadow(f.title, WS.TextShadow(style), Theme.rgb("accent2"))
  return style
end

-- patch: { bg = "rrggbb" | false, alpha = 0..1, autoHide = bool } from the appearance panel.
local function patchStyle(patch)
  local style = U.copy(frameDb().style or {})
  if patch.bg ~= nil then
    style.bg = patch.bg or nil
  end
  if patch.alpha ~= nil then
    style.alpha = patch.alpha
  end
  if patch.autoHide ~= nil then
    style.autoHide = patch.autoHide
  end
  frameDb().style = style
  if frame then
    applyLook(frame)
  end
end

function CW.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame.look, {
    frame = frame,
    kind = "calc",
    get = CW.Style,
    set = patchStyle,
    onSaveDefault = function()
      WS.SaveDefault("calc", CW.Style())
    end,
    onReset = function()
      frameDb().style = {}
      applyLook(frame)
    end,
  })
end

-- Scale: mouse wheel with the windowScale key (default Ctrl) on the title bar, the top left corner stays where it is.
local function changeScale(f, delta)
  local db = frameDb()
  savePosition(f)
  -- Whole percent steps, so repeated wheel turns never drift.
  db.scale = U.clamp(math.floor(scaleOf(db) * 100 + delta * SCALE_STEP * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
  f:SetScale(db.scale)
  place(f)
end

-- Window ---------------------------------------------------------------------------------------

local function create()
  local f = CreateFrame("Frame", "FGCalcWindow", UIParent)
  -- Above the main addon window (strata "MEDIUM"), like the note windows.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "calcui.win.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("calc-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("calc-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )
  f.bar:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["calcui.win.title"], L["calcui.win.scaleTip"])
  end)
  f.bar:SetScript("OnLeave", ns.HideTooltip)

  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "calcui.win.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("calc-close", function()
      f:Hide()
    end)
  )
  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("calc-look", function()
      CW.OpenLook()
    end)
  )
  f.open = W.Action(f.bar, { icon = "open", size = 18, tooltip = "calcui.win.open" })
  f.open:SetPoint("RIGHT", f.look, "LEFT", -2, 0)
  f.open:SetScript(
    "OnClick",
    ns.Wrap("calc-open-addon", function()
      f:Hide()
      ns.Main.Show("calc")
    end)
  )
  f.history = W.Action(f.bar, {
    icon = "history",
    size = 18,
    tooltip = "calcui.win.history",
    tooltipText = "calcui.win.historyTip",
  })
  f.history:SetPoint("RIGHT", f.open, "LEFT", -2, 0)
  f.history:SetScript(
    "OnClick",
    ns.Wrap("calc-history", function()
      CW.ToggleSide()
      f.view:FocusInput()
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.history, "LEFT", -4, 0)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 8, -(HEAD_H + 6))
  content:SetPoint("BOTTOMRIGHT", -8, 16)
  f.view = V.build(content, {
    window = true,
    root = f,
    onEscape = function()
      f:Hide()
    end,
    onResizeBy = function(_, dh)
      resizeBy(f, dh)
    end,
  })

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local gripTex = grip:CreateTexture(nil, "OVERLAY")
  gripTex:SetAllPoints()
  gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    WS.Hold(f, "size", true)
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("calc-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      saveSize(f)
      savePosition(f)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["calcui.win.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)
  f.grip = grip

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, grip },
    busy = function()
      return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
    end,
  }

  -- A click anywhere in the window gives the keyboard to the input.
  f:HookScript("OnMouseDown", function()
    f.view:FocusInput()
  end)
  f:SetScript(
    "OnShow",
    ns.Wrap("calc-show", function()
      frameDb().shown = true
      ns.WindowShell.SetEsc(f, true)
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("calc-hide", function()
      frameDb().shown = false
      ns.WindowShell.SetEsc(f, false)
      f.view.input:ClearFocus()
    end)
  )
  f:Hide()
  return f
end

function CW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function CW.Frame()
  return frame
end

function CW.Open()
  if not ns.db then
    return
  end
  if not frame then
    frame = create()
  end
  frame:SetScale(scaleOf(frameDb()))
  frame.view:SetSideShown(frameDb().side == true)
  place(frame)
  applyLook(frame)
  frame:Show()
  frame:Raise()
  frame.view:Show()
end

function CW.Hide()
  if frame then
    frame:Hide()
  end
end

function CW.Toggle()
  if CW.IsShown() then
    CW.Hide()
  else
    CW.Open()
  end
end

-- /fg calc and /calc: without text the window toggles, with text the result goes to chat or toast
-- and into the history.
function CW.Slash(rest)
  rest = U.trim(rest or "")
  if rest == "" then
    CW.Toggle()
    return
  end
  V.Announce(rest, V.Submit(rest))
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "calc") then
    applyLook(frame)
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
    saveSize(frame)
  end
end)

-- Top-level /calc ------------------------------------------------------------------------------------

CW.status = "not checked"

-- Registers /calc only when no other addon owns it. Returns true when it is ours afterwards
-- (calling it again is harmless: our own entry does not count as an owner).
function CW.RegisterSlash()
  local owners = {}
  for _, name in ipairs(ns.WaypointSlash.SlashOwners("/calc")) do
    if name ~= KEY then
      owners[#owners + 1] = name
    end
  end
  if #owners > 0 then
    CW.status = "not registered: /calc belongs to " .. owners[1]
    return false
  end
  SlashCmdList[KEY] = function(msg)
    ns.Safe("slash:calc", CW.Slash, msg)
  end
  rawset(_G, "SLASH_" .. KEY .. "1", "/calc")
  -- The chat frame keeps its own lookup table of commands; refresh it when the game offers it.
  local refresh = rawget(_G, "ChatFrame_ImportAllListsToHash")
  if type(refresh) == "function" then
    pcall(refresh)
  end
  CW.status = "registered"
  return true
end

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it).
ns.KeyBindings.list[#ns.KeyBindings.list + 1] = { name = "FOREVERGUIDES_CALC", label = "binding.calc", fn = "Calc" }
ns.KeyBindings.Calc = function()
  ns.Safe("binding:Calc", CW.Toggle)
end

ns.On("PLAYER_LOGIN", function()
  if not ns.db then
    return
  end
  if frameDb().shown == true then
    CW.Open()
  end
  -- Late: other addons have registered their commands by then.
  C_Timer.After(0, function()
    ns.Safe("calc-slash", CW.RegisterSlash)
  end)
end)

ns.RegisterPage({
  id = "calc",
  order = 650,
  group = "tools",
  title = "page.calc",
  icon = ns.ICONS.calc,
  aliases = { "rechner", "calc", "taschenrechner", "calculator" },
  build = function(container)
    return V.build(container)
  end,
})
