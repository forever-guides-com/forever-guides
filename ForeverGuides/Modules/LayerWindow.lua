-- The layer window: one small movable window (not pooled) that opens from the label at the minimap and from
-- /fg layer. It shows the layer of this zone with zone, age, source and the layer before, a button that reads
-- again with its answer in a status line, the opt-in switches, the buttons and the progress line of a layer
-- switch (Modules/LayerWindowNet.lua) and the list of the hosts of the zone. The list shows the hosts that
-- LayerNet heard; ns.LayerWindow.SetEntries(list) puts another list in its place (nil gives it back).
-- Look (background, opacity, auto-hiding title bar) comes from Modules/WindowStyle.lua (kind
-- "layer"); position and scale live in ns.db.frames.layerWindow. Nothing here touches protected frames, so
-- it works in combat.
--
-- Keyboard: Modules/LayerWindowKeys.lua.
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle
local Layer, LL, Kit, LWN = ns.Layer, ns.LayerLogic, ns.GuildKit, ns.LayerWindowNet

local LW = {}
ns.LayerWindow = LW

local WIDTH, HEIGHT, HEAD_H, PAD, GAP = 360, 430, 22, 10, 6
local ROW_BASE, LIST_ROWS_MIN = 26, 3
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local LAYER_W, FREE_W, ICON = 56, 44, 16
-- Seconds between two redraws while the window is open (the age and the zone move on their own).
local REDRAW_GAP = 1
local STATUS_COLOR = { info = "textMuted", success = "success", warning = "warning" }

-- Look defaults of this window kind: settings layerWindowBg / Alpha / AutoHide.
WS.PREFIX.layer = "layerWindow"

ns.AddLocale("enUS", {
  ["layer.win.title"] = "Layer",
  ["layer.win.close"] = "Close layer window",
  ["layer.win.scaleTip"] = "Drag to move, {key:windowScale} changes the size.",
  ["layer.win.confirmed"] = "Confirmed %s (%s)",
  ["layer.win.previous"] = "Previously: %s",
  ["layer.win.refresh"] = "Read again",
  ["layer.win.refreshTip"] = "Reads the layer from the NPCs you can see right now.",
  ["layer.win.players"] = "Hosts in this zone",
  ["layer.win.switch"] = "Switch",
  ["layer.win.free"] = "%d free",
  ["layer.win.status.idle"] = "The layer is read from the NPCs you see.",
  ["layer.win.status.read"] = "Layer %d confirmed.",
  ["layer.win.status.found"] = "Layer %d detected.",
  ["layer.win.status.changed"] = "Layer changed from %d to %d.",
  ["layer.win.status.lost"] = "New zone, no layer known yet.",
})
ns.AddLocale("deDE", {
  ["layer.win.title"] = "Layer",
  ["layer.win.close"] = "Layer-Fenster schließen",
  ["layer.win.scaleTip"] = "Ziehen verschiebt, {key:windowScale} ändert die Größe.",
  ["layer.win.confirmed"] = "Bestätigt %s (%s)",
  ["layer.win.previous"] = "Zuvor: %s",
  ["layer.win.refresh"] = "Neu einlesen",
  ["layer.win.refreshTip"] = "Liest den Layer aus den NPCs, die du gerade siehst.",
  ["layer.win.players"] = "Hosts in dieser Zone",
  ["layer.win.switch"] = "Wechseln",
  ["layer.win.free"] = "%d frei",
  ["layer.win.status.idle"] = "Der Layer wird aus den NPCs gelesen, die du siehst.",
  ["layer.win.status.read"] = "Layer %d bestätigt.",
  ["layer.win.status.found"] = "Layer %d erkannt.",
  ["layer.win.status.changed"] = "Layer von %d auf %d gewechselt.",
  ["layer.win.status.lost"] = "Neue Zone, noch kein Layer bekannt.",
})

local frame
-- The rows shown, the list handed in by SetEntries (nil: the hosts LayerNet heard) and the line at the
-- bottom: { key, level, args = {...} }.
local entries, fed = {}, nil
local status = { key = "layer.win.status.idle", level = "info", args = {} }
local rows = {}

local function frameDb()
  local frames = ns.db.frames
  if type(frames.layerWindow) ~= "table" then
    frames.layerWindow = {}
  end
  return frames.layerWindow
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  end
  ns.WindowShell.FitToScreen(f)
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

-- Drawing -------------------------------------------------------------------------------------------------

-- The theme color, or black or white when it does not read on the window color chosen in the look panel.
local function ink(name, bg)
  local r, g, b = Theme.rgb(name)
  local hex = string.format("#%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
  local against = "#" .. bg
  if Theme.contrastRatio(hex, against) >= Theme.MIN_CONTRAST then
    return r, g, b
  end
  local light = Theme.contrastRatio("#ffffff", against) >= Theme.contrastRatio("#000000", against)
  local v = light and 1 or 0
  return v, v, v
end

-- Text colors and shadow for the look the window has now.
local function paint(f, style)
  style = style or LW.Style()
  local shadow = WS.TextShadow(style)
  for _, fs in ipairs(f.texts) do
    local r, g, b = ink(fs.fgColor, style.bg)
    fs:SetTextColor(r, g, b)
    WS.ApplyShadow(fs, shadow, r, g, b)
  end
  WS.ApplyShadow(f.title, shadow, Theme.rgb("accent2"))
end

-- Sets a line of text, empty for nil. Texts go through W.SetText so a language switch keeps them.
local function setLine(fs, text, color)
  W.SetText(fs, nil, text or "")
  if color then
    W.SetColor(fs, color)
  end
end

local function render(f)
  local layer, mapId, _, source, previous = Layer.Get()
  setLine(f.big, Layer.Text())
  setLine(f.zone, string.format(L["layer.tip.zone"], Layer.ZoneName(mapId)))
  if layer then
    setLine(
      f.confirmed,
      string.format(L["layer.win.confirmed"], Layer.Age() or "?", L["layer.source." .. tostring(source)]),
      "text"
    )
    setLine(f.previous, previous and string.format(L["layer.win.previous"], string.format(L["layer.label"], previous)))
  else
    setLine(f.confirmed, L["layer.tip.none"], "textSecondary")
    setLine(f.previous)
  end
  setLine(f.status, string.format(L[status.key], unpack(status.args)), STATUS_COLOR[status.level])
  LWN.Refresh()
  entries = fed or LL.CleanEntries(LWN.Live())
  LWN.Render(f)
  W.SetText(f.empty, LWN.EmptyKey())
  f.empty:SetShown(#entries == 0)
end

-- Places a line under y and answers the y below it; an empty line takes no room.
local function put(f, fs, y, width)
  fs:ClearAllPoints()
  if (fs:GetText() or "") == "" then
    fs:Hide()
    return y
  end
  fs:Show()
  fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
  fs:SetWidth(width)
  return y + math.ceil(fs:GetStringHeight()) + 2
end

-- The window keeps its width and grows in height when large fonts need the room.
local function layout(f)
  local width = math.max(1, f:GetWidth() - 2 * PAD)
  local y = HEAD_H + GAP
  for _, fs in ipairs({ f.big, f.zone, f.confirmed, f.previous }) do
    y = put(f, fs, y, width)
  end
  y = LWN.Layout(f, y + GAP, width, put, PAD) + GAP
  y = put(f, f.listTitle, y, width) + 2
  f.status:ClearAllPoints()
  f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  f.status:SetWidth(width)
  local statusH = math.ceil(f.status:GetStringHeight())
  local rowH = Theme.lineHeight(ROW_BASE, "ui")
  -- A frame whose height only follows from its anchors has no rectangle yet, so the list gets a number.
  local listH = math.max(LIST_ROWS_MIN * rowH, HEIGHT - y - PAD - GAP - statusH)
  f.laidWidth = f:GetWidth()
  f:SetHeight(y + listH + GAP + statusH + PAD)
  f.list:ClearAllPoints()
  f.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
  f.list:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
  f.list:SetHeight(listH)
  f.empty:ClearAllPoints()
  f.empty:SetPoint("TOPLEFT", f.list, "TOPLEFT", PAD, -PAD)
  f.empty:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", -PAD - 10, -PAD)
  f.list:SetRowHeight(rowH)
  f.list:SetData(entries)
end

local function redraw(f)
  render(f)
  paint(f)
  layout(f)
end

-- Look ----------------------------------------------------------------------------------------------------

function LW.Style()
  return WS.Resolve("layer", frameDb().style)
end

local function applyLook(f)
  local style = LW.Style()
  WS.Apply(f, style, f.styleParts)
  paint(f, style)
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

function LW.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame.look, {
    frame = frame,
    kind = "layer",
    get = LW.Style,
    set = patchStyle,
    onSaveDefault = function()
      WS.SaveDefault("layer", LW.Style())
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

-- Status ----------------------------------------------------------------------------------------------------

-- The line at the bottom. level is info, success or warning; the text is formatted when it is drawn.
local function setStatus(key, level, ...)
  status = { key = key, level = level, args = { ... } }
end

-- Reads again and says what came of it, in the window.
function LW.Read()
  if Layer.Refresh() and Layer.Get() then
    setStatus("layer.win.status.read", "success", (Layer.Get()))
  else
    setStatus("layer.none", "warning")
  end
  if frame and frame:IsShown() then
    redraw(frame)
  end
end

-- List ------------------------------------------------------------------------------------------------------

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 4, 0)
  row.btn = W.Action(row, { key = "layer.win.switch", height = 22, manual = true })
  row.btn:SetPoint("RIGHT", -2, 0)
  row.btn.fgRow = row
  -- A button that cannot be used says why, a usable one says what it does.
  row.btn:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["layer.win.switch"], self.fgBlock or L["layer.win.switchTip"])
  end)
  row.btn:HookScript("OnLeave", ns.HideTooltip)
  row.free = W.Text(row, { role = "ui", color = "textSecondary", justify = "RIGHT" })
  row.layer = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
  row.name = W.Text(row, { role = "ui", color = "text" })
  rows[#rows + 1] = row
  return row
end

local function bindRow(row, entry, index)
  row.index = index
  local paintIcon = Kit.ClassIcon(entry.class)
  if paintIcon then
    paintIcon(row.icon)
  end
  row.icon:SetShown(paintIcon ~= nil)
  W.SetText(row.name, nil, Kit.ColoredName(entry.name, entry.class))
  W.SetText(row.layer, nil, LL.EntryLayerText(entry, L))
  W.SetText(row.free, nil, LL.EntryFreeText(entry, L))
  local btn = row.btn
  btn:SetShown(entry.onClick ~= nil)
  btn:SetWidth(btn:FullWidth())
  btn.fgBlock = entry.blocked
  btn:SetEnabled(entry.blocked == nil)
  btn:SetScript("OnClick", nil)
  if entry.onClick then
    btn:SetScript(
      "OnClick",
      ns.Wrap("layer-switch", function()
        entry.onClick(entry)
      end)
    )
  end
  -- Columns from the right: button, free places, layer; the name takes what is left. Measured, so a large
  -- font widens a column instead of cutting its text.
  row.free:SetWidth(math.max(FREE_W, math.ceil(row.free:GetStringWidth())))
  row.layer:SetWidth(math.max(LAYER_W, math.ceil(row.layer:GetStringWidth())))
  row.free:ClearAllPoints()
  if entry.onClick then
    row.free:SetPoint("RIGHT", btn, "LEFT", -GAP, 0)
  else
    row.free:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  end
  row.layer:ClearAllPoints()
  row.layer:SetPoint("RIGHT", row.free, "LEFT", -4, 0)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetPoint("RIGHT", row.layer, "LEFT", -4, 0)
end

-- Another list in place of the hosts of the zone: { name, class (token), layer, free, blocked (text, the
-- button is disabled), onClick(entry) }. Everything is checked (ns.LayerLogic.CleanEntries), an empty or
-- broken list shows the empty state. nil brings the hosts of the zone back.
function LW.SetEntries(list)
  fed = list ~= nil and LL.CleanEntries(list) or nil
  if frame and frame:IsShown() then
    redraw(frame)
  end
end

-- Keyboard ----------------------------------------------------------------------------------------------------

local function ownFocus(f)
  return ns.LayerWindowKeys.OwnFocus(f, rows)
end

local function handleKey(f, key)
  return ns.LayerWindowKeys.Handle(f, rows, #entries, key)
end

-- Window ----------------------------------------------------------------------------------------------------

local function create()
  local f = CreateFrame("Frame", "FGLayerWindow", UIParent)
  -- Above the main addon window (strata "MEDIUM"), like the note windows.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetSize(WIDTH, HEIGHT)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "layer.win.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("layer-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("layer-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )
  f.bar:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["layer.win.title"], L["layer.win.scaleTip"])
  end)
  f.bar:SetScript("OnLeave", ns.HideTooltip)

  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "layer.win.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("layer-close", function()
      LW.Hide()
    end)
  )
  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("layer-look", function()
      LW.OpenLook()
    end)
  )
  f.title:SetPoint("RIGHT", f.look, "LEFT", -4, 0)

  f.big = W.Text(f, { role = "title", family = "heading", color = "text" })
  f.zone = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.confirmed = W.Text(f, { role = "ui", color = "text", wrap = true })
  f.previous = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.refresh = W.Action(f, {
    key = "layer.win.refresh",
    icon = "refresh",
    variant = "primary",
    height = 26,
    tooltip = "layer.win.refresh",
    tooltipText = "layer.win.refreshTip",
    onClick = LW.Read,
  })
  f.listTitle = W.Text(f, { key = "layer.win.players", role = "ui", color = "textSecondary", wrap = true })
  f.status = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.texts = { f.big, f.zone, f.confirmed, f.previous, f.listTitle, f.status }
  f.net = LWN.Create(f)
  for _, fs in ipairs(f.net.texts) do
    f.texts[#f.texts + 1] = fs
  end

  f.list = W.ScrollList(f, { rowHeight = Theme.lineHeight(ROW_BASE, "ui"), createRow = createRow, bindRow = bindRow })
  W.Fill(f.list, "surface", 1)
  f.empty = W.Text(f.list, { key = "layer.win.empty.none", role = "ui", color = "textMuted", wrap = true })

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar },
    busy = function()
      return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
    end,
  }

  f:SetScript(
    "OnSizeChanged",
    ns.Wrap("layer-size", function(self)
      if self:IsShown() and self:GetWidth() ~= self.laidWidth then
        layout(self)
      end
    end)
  )
  -- Set before the Esc registration: the shell keeps a key handler that is already there.
  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = ns.Safe("layer-key", handleKey, self, key)
    pcall(self.SetPropagateKeyboardInput, self, not handled)
  end)
  f:SetScript(
    "OnShow",
    ns.Wrap("layer-show", function()
      ns.WindowShell.SetEsc(f, true)
      f.waited = 0
      f:SetScript(
        "OnUpdate",
        ns.Wrap("layer-tick", function(self, elapsed)
          self.waited = self.waited + elapsed
          if self.waited >= REDRAW_GAP then
            self.waited = 0
            redraw(self)
          end
        end)
      )
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("layer-hide", function()
      f:SetScript("OnUpdate", nil)
      ns.WindowShell.SetEsc(f, false)
      if ownFocus(f) then
        ns.Focus.clear()
      end
    end)
  )
  f:Hide()
  return f
end

function LW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function LW.Frame()
  return frame
end

function LW.Open()
  if not ns.db then
    return
  end
  local wasShown = LW.IsShown()
  if not frame then
    frame = create()
  end
  if not wasShown then
    setStatus("layer.win.status.idle", "info")
    frame:SetScale(scaleOf(frameDb()))
    place(frame)
    applyLook(frame)
    frame:Show()
  end
  redraw(frame)
  frame:Raise()
end

function LW.Hide()
  if frame then
    frame:Hide()
  end
end

function LW.Toggle()
  if LW.IsShown() then
    LW.Hide()
  else
    LW.Open()
  end
end

-- /fg layer and /fg ebene toggle the window; status prints the line, refresh reads again (LayerLabel.Slash);
-- hosts lists the hosts of the zone, switch asks them (the button "Pick best host"), cancel stops a switch.
function LW.Slash(rest)
  local word = (rest or ""):lower()
  if word == "status" or word == "refresh" or word == "neu" then
    ns.LayerLabel.Slash(word)
  elseif word == "hosts" then
    LWN.PrintHosts()
  elseif word == "switch" or word == "wechseln" then
    LWN.SwitchBest()
  elseif word == "cancel" or word == "abbrechen" then
    LWN.CancelCommand()
  else
    LW.Toggle()
  end
end

-- Events ----------------------------------------------------------------------------------------------------

ns.On("FG_LAYER_CHANGED", function(_, layer, old)
  if not frame then
    return
  end
  if layer == nil then
    setStatus("layer.win.status.lost", "warning")
  elseif old == nil then
    setStatus("layer.win.status.found", "success", layer)
  else
    setStatus("layer.win.status.changed", "success", old, layer)
  end
  if frame:IsShown() then
    redraw(frame)
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "layer") then
    applyLook(frame)
  end
  if frame and frame:IsShown() and (path == "settings.layerShare" or path == "settings.layerHost") then
    redraw(frame)
  end
end)
-- The hosts of the zone or the progress of a switch changed.
for _, message in ipairs({ "FG_LAYER_PEERS", "FG_LAYER_SWITCH" }) do
  ns.On(message, function()
    if frame and frame:IsShown() then
      redraw(frame)
    end
  end)
end
-- A new zone has another name at once; the layer follows when it is read.
for _, event in ipairs({
  "PLAYER_ENTERING_WORLD",
  "ZONE_CHANGED_NEW_AREA",
  "ZONE_CHANGED",
  "ZONE_CHANGED_INDOORS",
  "FG_UI_REFRESHED",
}) do
  ns.On(event, function()
    if frame and frame:IsShown() then
      redraw(frame)
      applyLook(frame)
    end
  end)
end
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
  end
end)
