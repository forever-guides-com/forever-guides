-- The durability window: one movable window (not pooled) around the content of
-- Modules/DurabilityView.lua, plus the sidebar page, the key binding and /fg durability. Look
-- (background, opacity, auto-hiding title bar) comes from Modules/WindowStyle.lua (kind "durability").
-- Position, width, scale, the per-window look and the open state live in ns.db.frames.durabilityWindow;
-- the height follows the number of rows. Nothing here touches protected frames, so it works in combat.
--
-- Open state: frames.durabilityWindow.shown is what the player wants. With the setting "only while a
-- part is low" the window stays hidden until a part falls below the limit, unless it was opened by hand
-- (key, command, settings): that shows it until it is closed. Esc closes it at once.
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle
local DV, DL = ns.DurabilityView, ns.DurabilityLogic

local DW = {}
ns.DurabilityWindow = DW

local HEAD_H, PAD = 22, 8
local MIN_W, MAX_W, DEFAULT_W = 240, 480, 270
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local TITLE_ICON = "Interface\\Icons\\INV_Chest_Plate06"

-- Look defaults of this window kind: settings durabilityWindowBg / Alpha / AutoHide.
WS.PREFIX.durability = "durabilityWindow"

ns.AddLocale("enUS", {
  ["page.durability"] = "Durability",
  ["dur.win.title"] = "Durability",
  ["dur.win.close"] = "Close durability window",
  ["dur.win.open"] = "Open in the addon",
  ["dur.win.scaleTip"] = "Drag to move, {key:windowScale} changes the size.",
  ["dur.win.grip"] = "Drag to resize",
  ["dur.page.intro"] = "Condition of your worn equipment: icon, percent and a bar per part. The numbers update after fights, repairs and when you change gear.",
  ["dur.page.window"] = "Open in a window",
  ["dur.page.settings"] = "Settings",
  ["binding.durability"] = "Durability window on or off",
})
ns.AddLocale("deDE", {
  ["page.durability"] = "Haltbarkeit",
  ["dur.win.title"] = "Haltbarkeit",
  ["dur.win.close"] = "Haltbarkeits-Fenster schließen",
  ["dur.win.open"] = "Im Addon öffnen",
  ["dur.win.scaleTip"] = "Ziehen verschiebt, {key:windowScale} ändert die Größe.",
  ["dur.win.grip"] = "Zum Ändern der Größe ziehen",
  ["dur.page.intro"] = "Zustand deiner Ausrüstung: Symbol, Prozent und ein Balken je Teil. Die Werte aktualisieren sich nach Kämpfen, Reparaturen und beim Wechsel der Ausrüstung.",
  ["dur.page.window"] = "In einem Fenster öffnen",
  ["dur.page.settings"] = "Einstellungen",
  ["binding.durability"] = "Haltbarkeits-Fenster ein oder aus",
})

local frame
-- True while the window is shown or hidden by the addon itself (condition rule, build): the open state
-- the player chose stays as it is.
local auto = false
-- A manual opening ignores the "only while a part is low" rule until the window is closed.
local forced = false

local function frameDb()
  local frames = ns.db.frames
  if type(frames.durabilityWindow) ~= "table" then
    frames.durabilityWindow = {}
  end
  return frames.durabilityWindow
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

-- Size: the saved width, the height of the rows (the grip changes the width only).
local function fit(f)
  local db = frameDb()
  local h = HEAD_H + 6 + f.view:Height() + 14
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, h, MAX_W, h)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, h)
  end
  f:SetSize(U.clamp(finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W), h)
end

local function place(f)
  local db = frameDb()
  fit(f)
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", -260, 0)
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
  frameDb().w = f:GetWidth()
end

-- Look -----------------------------------------------------------------------------------------

function DW.Style()
  return WS.Resolve("durability", frameDb().style)
end

local function applyLook(f)
  local style = DW.Style()
  WS.Apply(f, style, f.styleParts)
  WS.ApplyShadow(f.title, WS.TextShadow(style), Theme.rgb("accent2"))
  -- The text colors depend on the background they have to read on.
  f.view.shadow = WS.TextShadow(style)
  f.view:Update(f.view.data)
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

function DW.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame.look, {
    frame = frame,
    kind = "durability",
    get = DW.Style,
    set = patchStyle,
    onSaveDefault = function()
      WS.SaveDefault("durability", DW.Style())
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
  local f = CreateFrame("Frame", "FGDurabilityWindow", UIParent)
  -- Above the main addon window (strata "MEDIUM"), like the note windows.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "dur.win.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("durability-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("durability-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )
  f.bar:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["dur.win.title"], L["dur.win.scaleTip"])
  end)
  f.bar:SetScript("OnLeave", ns.HideTooltip)

  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "dur.win.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("durability-close", function()
      DW.Hide()
    end)
  )
  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("durability-look", function()
      DW.OpenLook()
    end)
  )
  f.open = W.Action(f.bar, { icon = "open", size = 18, tooltip = "dur.win.open" })
  f.open:SetPoint("RIGHT", f.look, "LEFT", -2, 0)
  f.open:SetScript(
    "OnClick",
    ns.Wrap("durability-open-addon", function()
      DW.Hide()
      ns.Main.Show("durability")
    end)
  )
  f.icon = f.bar:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(14, 14)
  f.icon:SetPoint("LEFT", 6, 0)
  f.icon:SetTexture(TITLE_ICON)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
  f.title:SetPoint("RIGHT", f.open, "LEFT", -4, 0)

  f.view = DV.build(f, {
    adapt = true,
    bg = function()
      return "#" .. DW.Style().bg
    end,
    onResize = function()
      fit(f)
    end,
  })
  f.view.frame:SetPoint("TOPLEFT", PAD, -(HEAD_H + 6))
  f.view.frame:SetPoint("BOTTOMRIGHT", -PAD, 12)

  -- A plain frame, not a button: the grip is a drag handle, no action.
  local grip = CreateFrame("Frame", nil, f)
  grip:SetSize(14, 14)
  grip:EnableMouse(true)
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
    ns.Wrap("durability-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      saveSize(f)
      savePosition(f)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["dur.win.grip"])
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

  f:SetScript(
    "OnShow",
    ns.Wrap("durability-show", function()
      if not auto then
        frameDb().shown = true
      end
      ns.WindowShell.SetEsc(f, true)
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("durability-hide", function()
      if not auto then
        frameDb().shown = false
        forced = false
      end
      ns.WindowShell.SetEsc(f, false)
    end)
  )
  f:Hide()
  return f
end

function DW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function DW.Frame()
  return frame
end

-- What the player wants: open (true) or closed.
function DW.IsWanted()
  return ns.db ~= nil and frameDb().shown == true
end

-- Shows or hides the window without touching what the player wants.
local function setVisible(on, data)
  if on == DW.IsShown() then
    return
  end
  auto = true
  local ok, err = pcall(function()
    if on then
      if not frame then
        frame = create()
      end
      frame:SetScale(scaleOf(frameDb()))
      place(frame)
      frame:Show()
      frame:Raise()
      applyLook(frame)
      frame.view:Update(data)
      place(frame)
    else
      frame:Hide()
    end
  end)
  auto = false
  if not ok then
    error(err, 0)
  end
end

-- Applies the open state and the "only while a part is low" rule to the current readings.
function DW.Apply(data)
  if not (ns.db and DW.IsWanted()) then
    return
  end
  local s = ns.db.settings
  local show = forced or s.durabilityOnlyBelow ~= true
  if not show then
    show = DL.AnyBelow(data.entries, DL.CleanLimit(s.durabilityOnlyBelowPct, DL.DEFAULTS.onlyBelow))
  end
  setVisible(show, data)
end

function DW.Open()
  if not ns.db then
    return
  end
  forced = true
  frameDb().shown = true
  local data = DV.Collect()
  setVisible(true, data)
  if frame then
    frame:Raise()
  end
end

function DW.Hide()
  if not ns.db then
    return
  end
  forced = false
  frameDb().shown = false
  if frame then
    frame:Hide()
  end
end

function DW.Toggle()
  if DW.IsShown() then
    DW.Hide()
  else
    DW.Open()
  end
end

function DW.SetWanted(on)
  if on then
    DW.Open()
  else
    DW.Hide()
  end
end

-- /fg durability, /fg haltbarkeit: toggles the window.
function DW.Slash()
  DW.Toggle()
end

ns.On("FG_DURABILITY_UPDATED", function(_, data)
  DW.Apply(data)
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "durability") then
    applyLook(frame)
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
    saveSize(frame)
  end
end)

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it).
ns.KeyBindings.list[#ns.KeyBindings.list + 1] =
  { name = "FOREVERGUIDES_DURABILITY", label = "binding.durability", fn = "Durability" }
ns.KeyBindings.Durability = function()
  ns.Safe("binding:Durability", DW.Toggle)
end

ns.On("PLAYER_LOGIN", function()
  if ns.db and DW.IsWanted() then
    DW.Apply(DV.Collect())
  end
end)

-- Page ---------------------------------------------------------------------------------------------

ns.RegisterPage({
  id = "durability",
  order = 99,
  group = "tools",
  title = "page.durability",
  icon = ns.ICONS.durability,
  aliases = { "haltbarkeit", "durability", "reparatur", "repair", "ausruestung", "ausrüstung", "equipment", "armor" },
  build = function(container)
    local view = ns.NewPageView(container)
    ns.AddParagraph(view, "dur.page.intro")
    view.stack:Add(
      W.Action(view.content, {
        label = "act.open",
        icon = "open",
        tooltip = "dur.page.window",
        width = 170,
        height = 28,
        onClick = function()
          DW.Open()
        end,
      }),
      { height = 28, width = 170, gap = 6 }
    )
    view.stack:Add(
      W.Action(view.content, {
        label = "act.options",
        icon = "gear",
        tooltip = "dur.page.settings",
        width = 170,
        height = 28,
        onClick = function()
          ns.SettingsPage.Select("bags")
          ns.Main.Show("settings")
        end,
      }),
      { height = 28, width = 170 }
    )
    local spec = { height = DV.SUMMARY_H + DV.ROW_H, width = 420 }
    local content = DV.build(view.content, {
      onResize = function(height)
        spec.height = height
        view:Layout()
      end,
    })
    view.stack:Add(content.frame, spec)
    view.dur = content
    function view:Show()
      content:Update()
    end
    return view
  end,
})
