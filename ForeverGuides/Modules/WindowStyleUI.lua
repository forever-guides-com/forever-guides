-- Controls for the window look (Modules/WindowStyle.lua), shared by the settings page
-- and the appearance panel of every floating window:
--   WS.NewControls(parent, { get = fn -> style, set = fn(patch), frame = window })
--       background color button, opacity slider (0 to 100 percent), auto-hide toggle.
--       patch = { bg = "rrggbb" | false (back to the default), alpha = 0..1, autoHide = bool }
--   WS.NewPreview(parent, { get = fn -> style })   swatch on a checker pattern
--   WS.OpenPanel(anchor, { frame, kind, get, set, onSaveDefault, onReset, clearBg })
--       clearBg = { get = fn -> bool, set = fn(bool) } adds the "white canvas transparent"
--       toggle (drawing windows only)
--       toggles = { { key, labelKey, tipKey?, get = fn -> bool, set = fn(bool) } } adds one
--       more toggle row per entry (the waypoint arrow: title bar, background)
--   WS.OpenPalette(anchor, currentHex, onPick(hex|nil))   palette popup + custom color
--   WS.PickColor(currentHex, onChange, ownerFrame)         the game's color picker
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle

ns.AddLocale("enUS", {
  ["wstyle.title"] = "Window appearance",
  ["wstyle.color"] = "Background color",
  ["wstyle.colorTip"] = "Opens a color palette.",
  ["wstyle.custom"] = "Custom color...",
  ["wstyle.opacity"] = "Opacity",
  ["wstyle.autoHide"] = "Hide title bar and buttons automatically",
  ["wstyle.autoHideTip"] = "Title bar and buttons show only while you hover.",
  ["wstyle.autoHideRow"] = "Hide title bar automatically",
  ["wstyle.saveDefault"] = "Save as default",
  ["wstyle.saveDefaultNote"] = "Color, opacity, auto-hide for all note windows.",
  ["wstyle.saveDefaultDrawing"] = "Color, opacity, auto-hide for all drawing windows.",
  ["wstyle.reset"] = "Reset to default",
  ["wstyle.resetTip"] = "Back to the default for all windows.",
  ["wstyle.shadow"] = "Text shadow",
  ["wstyle.shadow.auto"] = "Automatic",
  ["wstyle.shadow.on"] = "Always",
  ["wstyle.shadow.off"] = "Off",
  ["wstyle.border"] = "Always show window frame",
  ["wstyle.borderTip"] = "Frame and title line stay visible at 0 percent opacity.\nApplies to all windows.",
  ["wstyle.saveDefaultWaypoint"] = "Look and auto-hide for the waypoint arrow.",
  ["wstyle.sample"] = "Sample text",
  ["wstyle.clearBg"] = "Make white canvas transparent",
  ["wstyle.clearBgTip"] = "Hides the white drawing background, only strokes show.\nWith low opacity the window turns see-through.",
})

ns.AddLocale("deDE", {
  ["wstyle.title"] = "Fensterdarstellung",
  ["wstyle.color"] = "Hintergrundfarbe",
  ["wstyle.colorTip"] = "Öffnet eine Farbpalette.",
  ["wstyle.custom"] = "Eigene Farbe...",
  ["wstyle.opacity"] = "Deckkraft",
  ["wstyle.autoHide"] = "Kopfzeile und Knöpfe automatisch ausblenden",
  ["wstyle.autoHideTip"] = "Kopfzeile und Knöpfe erscheinen nur bei Maus darüber.",
  ["wstyle.autoHideRow"] = "Kopfzeile selbst ausblenden",
  ["wstyle.saveDefault"] = "Als Standard speichern",
  ["wstyle.saveDefaultNote"] = "Farbe, Deckkraft, Ausblenden für alle Notizfenster.",
  ["wstyle.saveDefaultDrawing"] = "Farbe, Deckkraft, Ausblenden für alle Zeichnungsfenster.",
  ["wstyle.reset"] = "Auf Standard zurücksetzen",
  ["wstyle.resetTip"] = "Zurück zum Standard für alle Fenster.",
  ["wstyle.shadow"] = "Textschatten",
  ["wstyle.shadow.auto"] = "Automatisch",
  ["wstyle.shadow.on"] = "Immer",
  ["wstyle.shadow.off"] = "Aus",
  ["wstyle.border"] = "Fensterrahmen immer anzeigen",
  ["wstyle.borderTip"] = "Rahmen und Linie bleiben bei 0 Prozent Deckkraft sichtbar.\nGilt für alle Fenster.",
  ["wstyle.saveDefaultWaypoint"] = "Aussehen und Ausblenden für den Wegpunkt-Pfeil.",
  ["wstyle.sample"] = "Beispieltext",
  ["wstyle.clearBg"] = "Weiße Fläche transparent",
  ["wstyle.clearBgTip"] = "Blendet den weißen Zeichnungshintergrund aus, nur Striche bleiben.\nMit niedriger Deckkraft wird das Fenster durchsichtig.",
})

-- Color choice ------------------------------------------------------------------------------

local function toHex(r, g, b)
  local function byte(v)
    return U.clamp(math.floor(v * 255 + 0.5), 0, 255)
  end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Opens the game's color picker. onChange(hex) runs while the player picks and again
-- with the old color when the picker is cancelled. ownerFrame keeps that window's
-- chrome visible while the picker is open (WS.PickerOpenFor).
function WS.PickColor(currentHex, onChange, ownerFrame)
  if not ColorPickerFrame then
    return false
  end
  WS.pickerOwner = ownerFrame
  local r, g, b = U.hex(currentHex)
  local function apply()
    onChange(toHex(ColorPickerFrame:GetColorRGB()))
  end
  local function cancel()
    onChange(currentHex)
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r = r,
      g = g,
      b = b,
      hasOpacity = false,
      swatchFunc = apply,
      cancelFunc = cancel,
    })
  else
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func = apply
    ColorPickerFrame.cancelFunc = cancel
    ColorPickerFrame:Show()
  end
  return true
end

function WS.PickerOpenFor(frame)
  return ColorPickerFrame ~= nil and WS.pickerOwner == frame and ColorPickerFrame:IsShown() == true
end

local CUSTOM_ROW = 26

-- The "Custom color..." button hangs on the shared palette popup of the note toolbar and
-- only exists while a window style opened it.
local function customButton(p)
  if not p.fgCustom then
    p.fgBaseHeight = p:GetHeight()
    local b = W.Action(
      p,
      { label = "act.pick", icon = "palette", tooltip = "wstyle.custom", width = p:GetWidth() - 12, height = 22 }
    )
    b:SetPoint("BOTTOMLEFT", 6, 6 + CUSTOM_ROW)
    b:SetScript(
      "OnClick",
      ns.Wrap("wstyle-custom", function()
        local fn = p.fgOnCustom
        ns.RichToolbar.ClosePopups()
        if fn then
          fn()
        end
      end)
    )
    p.items[#p.items + 1] = b
    p:HookScript("OnHide", function()
      b:Hide()
      p.fgOnCustom = nil
      p:SetHeight(p.fgBaseHeight)
    end)
    p.fgCustom = b
  end
  return p.fgCustom
end

-- A popup of the quick palette (the note toolbar's) plus "Custom color...". onPick gets
-- the color as "rrggbb", or nil for "Default color".
function WS.OpenPalette(anchor, currentHex, onPick, ownerFrame)
  local RT = ns.RichToolbar
  local ctx = { fg = "f3eee2", bg = currentHex or WS.FALLBACK.bg }
  local current = currentHex and ("#" .. currentHex) or nil
  local p = RT.OpenPopup("color", anchor, function(value, kind)
    if kind == "reset" or value == nil then
      onPick(nil)
    else
      onPick(RT.swatchHex(value, ctx))
    end
  end, current, ctx)
  if not p then
    return nil
  end
  local b = customButton(p)
  p:SetHeight(p.fgBaseHeight + CUSTOM_ROW)
  p.fgOnCustom = function()
    WS.PickColor(currentHex or WS.FALLBACK.bg, onPick, ownerFrame)
  end
  b:Show()
  -- Opened from a panel: the panel's outside-click watcher must treat the palette as part of it.
  local layer = ns.Desktop.Layer.current
  if layer then
    local known = false
    for _, f in ipairs(layer.frames) do
      known = known or f == p
    end
    if not known then
      layer.frames[#layer.frames + 1] = p
    end
  end
  return p
end

-- Controls ----------------------------------------------------------------------------------

local CONTROLS_HEIGHT = 26 + 6 + 42 + 6 + 24

function WS.NewControls(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(o.width or 280, CONTROLS_HEIGHT)

  local sw = CreateFrame("Button", nil, f)
  sw:SetHeight(26)
  sw:SetPoint("TOPLEFT")
  sw:SetPoint("TOPRIGHT")
  local chip = CreateFrame("Frame", nil, sw)
  chip:SetSize(22, 22)
  chip:SetPoint("LEFT")
  chip.tex = chip:CreateTexture(nil, "ARTWORK")
  chip.tex:SetAllPoints()
  W.Border(chip, "white", 0.4)
  local label = W.Text(sw, { key = "wstyle.color", role = "ui" })
  label:SetPoint("LEFT", chip, "RIGHT", 8, 0)
  local hexText = W.Text(sw, { role = "micro", color = "textMuted", justify = "RIGHT" })
  hexText:SetPoint("RIGHT")
  f.swatch = sw

  f.opacity = W.Slider(f, {
    key = "wstyle.opacity",
    min = 0,
    max = 100,
    step = 5,
    get = function()
      return math.floor(o.get().alpha * 100 + 0.5)
    end,
    set = function(v)
      o.set({ alpha = v / 100 })
    end,
    format = function(v)
      return v .. "%"
    end,
  })
  f.opacity:SetPoint("TOPLEFT", sw, "BOTTOMLEFT", 0, -6)
  f.opacity:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", 0, -6)

  f.autoHide = W.Toggle(f, {
    key = "wstyle.autoHideRow",
    get = function()
      return o.get().autoHide
    end,
    set = function(v)
      o.set({ autoHide = v })
    end,
    tooltip = "wstyle.autoHide",
    tooltipText = "wstyle.autoHideTip",
  })
  f.autoHide:SetPoint("TOPLEFT", f.opacity, "BOTTOMLEFT", 0, -6)
  f.autoHide:SetPoint("TOPRIGHT", f.opacity, "BOTTOMRIGHT", 0, -6)

  function f:Refresh()
    local style = o.get()
    chip.tex:SetColorTexture(U.hex(style.bg))
    hexText:SetText("#" .. style.bg:upper())
    f.opacity:Refresh()
    f.autoHide:Refresh()
  end

  sw:SetScript(
    "OnClick",
    ns.Wrap("wstyle-color", function()
      WS.OpenPalette(sw, o.get().bg, function(hex)
        o.set({ bg = hex or false })
        f:Refresh()
      end, o.frame)
    end)
  )
  sw:SetScript("OnEnter", function()
    ns.ShowTooltip(sw, L["wstyle.color"], L["wstyle.colorTip"])
  end)
  sw:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(sw, function(self)
    self:Click()
  end)
  f:Refresh()
  return f
end

-- Preview -------------------------------------------------------------------------------------

local CHECK, COLS, ROWS = 12, 14, 3

function WS.NewPreview(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(COLS * CHECK, ROWS * CHECK)
  for row = 0, ROWS - 1 do
    for col = 0, COLS - 1 do
      local t = f:CreateTexture(nil, "BACKGROUND")
      t:SetSize(CHECK, CHECK)
      t:SetPoint("TOPLEFT", col * CHECK, -row * CHECK)
      local shade = (row + col) % 2 == 0 and 0.42 or 0.62
      t:SetColorTexture(shade, shade, shade, 1)
    end
  end
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetAllPoints()
  W.Border(f, "white", 0.4)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetPoint("CENTER")
  ns.Bind(f.text, function(fs)
    Theme.applyFont(fs, "text", "body")
    fs:SetText(L["wstyle.sample"])
  end)
  function f:Refresh()
    local style = o.get()
    f.fill:SetColorTexture(U.hex(style.bg))
    f.fill:SetAlpha(style.alpha)
    f.text:SetTextColor(0.95, 0.93, 0.89, 1)
    WS.ApplyShadow(f.text, WS.TextShadow(style), 0.95, 0.93, 0.89)
  end
  ns.Bind(f, function()
    f:Refresh()
  end)
  return f
end

-- Appearance panel ----------------------------------------------------------------------------

local panel

local SAVE_NOTE = { drawing = "wstyle.saveDefaultDrawing", waypoint = "wstyle.saveDefaultWaypoint" }
local TOGGLE_ROW = 30

-- One pooled toggle per opts.toggles key: frames cannot be destroyed, so a key is built once.
local function extraToggle(p, def)
  local t = p.extra[def.key]
  if not t then
    local function current()
      for _, d in ipairs(p.o and p.o.toggles or {}) do
        if d.key == def.key then
          return d
        end
      end
    end
    t = W.Toggle(p, {
      key = def.labelKey,
      get = function()
        local d = current()
        return d ~= nil and d.get() == true
      end,
      set = function(v)
        local d = current()
        if d then
          d.set(v)
        end
      end,
      tooltip = def.labelKey,
      tooltipText = def.tipKey,
    })
    p.extra[def.key] = t
  end
  return t
end

local function buildPanel()
  local p = CreateFrame("Frame", "FGWindowStylePanel", UIParent)
  p:SetFrameStrata("FULLSCREEN")
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  W.Fill(p, "surface2", 1)
  W.Border(p, "accentDim", 1)
  p.baseHeight = 12 + 18 + 8 + CONTROLS_HEIGHT + 30 + 10 + 26 + 6 + 26 + 12
  p:SetSize(296, p.baseHeight)
  local title = W.Text(p, { key = "wstyle.title", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", 12, -12)
  p.close = W.CloseButton(p)
  p.copts = {
    width = 272,
    get = function()
      return p.o and p.o.get() or WS.Defaults("note")
    end,
    set = function(patch)
      if p.o then
        p.o.set(patch)
      end
    end,
  }
  p.controls = WS.NewControls(p, p.copts)
  p.controls:SetPoint("TOPLEFT", 12, -(12 + 18 + 8))
  p.controls:SetPoint("TOPRIGHT", -12, -(12 + 18 + 8))
  -- Global like the text shadow policy: one setting for all windows.
  p.border = W.Toggle(p, {
    key = "wstyle.border",
    get = function()
      return WS.Defaults("note").border
    end,
    set = function(v)
      ns.Store.set("settings." .. WS.BORDER_KEY, v)
    end,
    tooltip = "wstyle.border",
    tooltipText = "wstyle.borderTip",
  })
  p.extra = {}
  p.border:SetPoint("TOPLEFT", p.controls, "BOTTOMLEFT", 0, -6)
  p.border:SetPoint("TOPRIGHT", p.controls, "BOTTOMRIGHT", 0, -6)
  p.clearBg = W.Toggle(p, {
    key = "wstyle.clearBg",
    get = function()
      return p.o ~= nil and p.o.clearBg ~= nil and p.o.clearBg.get() == true
    end,
    set = function(v)
      if p.o and p.o.clearBg then
        p.o.clearBg.set(v)
      end
    end,
    tooltip = "wstyle.clearBg",
    tooltipText = "wstyle.clearBgTip",
  })
  p.clearBg:SetPoint("TOPLEFT", p.border, "BOTTOMLEFT", 0, -6)
  p.clearBg:SetPoint("TOPRIGHT", p.border, "BOTTOMRIGHT", 0, -6)
  p.clearBg:Hide()
  p.save = W.Action(p, {
    label = "act.save",
    icon = "save",
    tooltip = "wstyle.saveDefault",
    width = 272,
    onClick = function()
      if p.o.onSaveDefault then
        p.o.onSaveDefault()
      end
    end,
  })
  p.save:SetPoint("TOPLEFT", p.border, "BOTTOMLEFT", 0, -10)
  p.save:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["wstyle.saveDefault"], L[SAVE_NOTE[p.o.kind] or "wstyle.saveDefaultNote"])
  end)
  p.save:HookScript("OnLeave", ns.HideTooltip)
  p.reset = W.Action(p, {
    label = "act.reset",
    icon = "reset",
    tooltip = "wstyle.reset",
    width = 272,
    onClick = function()
      if p.o.onReset then
        p.o.onReset()
      end
      p.controls:Refresh()
      p.clearBg:Refresh()
      for _, t in pairs(p.extra) do
        t:Refresh()
      end
    end,
  })
  p.reset:SetPoint("TOPLEFT", p.save, "BOTTOMLEFT", 0, -6)
  p.reset:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["wstyle.reset"], L["wstyle.resetTip"])
  end)
  p.reset:HookScript("OnLeave", ns.HideTooltip)
  p:Hide()
  return p
end

function WS.PanelOpenFor(frame)
  return panel ~= nil and panel:IsShown() and panel.o ~= nil and panel.o.frame == frame
end

function WS.ClosePanel()
  if panel and panel:IsShown() then
    return ns.Desktop.Layer.close("api")
  end
  return false
end

-- Opens the panel below `anchor`, or closes it when it is already open for that anchor.
-- o = { frame (the styled window), kind, get() -> style, set(patch), onSaveDefault(), onReset(),
--       clearBg?, toggles? }
function WS.OpenPanel(anchor, o)
  panel = panel or buildPanel()
  if panel:IsShown() and panel.anchor == anchor then
    WS.ClosePanel()
    return nil
  end
  local layer = ns.Desktop.Layer
  layer.open({
    frames = { panel },
    owner = anchor,
    onClose = function()
      panel.o, panel.anchor = nil, nil
    end,
  })
  panel.o, panel.anchor = o, anchor
  -- The controls pass the window to the picker: it keeps the chrome visible meanwhile.
  panel.copts.frame = o.frame
  -- The extra toggle pushes the default buttons down by its row.
  local extra = o.clearBg ~= nil
  panel.clearBg:SetShown(extra)
  local last = extra and panel.clearBg or panel.border
  for _, t in pairs(panel.extra) do
    t:Hide()
  end
  local rows = extra and 1 or 0
  for _, def in ipairs(o.toggles or {}) do
    local t = extraToggle(panel, def)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -6)
    t:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -6)
    t:Show()
    t:Refresh()
    last = t
    rows = rows + 1
  end
  panel.save:ClearAllPoints()
  panel.save:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
  panel:SetHeight(panel.baseHeight + rows * TOGGLE_ROW)
  layer.place(panel, anchor, "TOPRIGHT", "BOTTOMRIGHT", 0, -2)
  panel:Show()
  panel.controls:Refresh()
  panel.border:Refresh()
  if extra then
    panel.clearBg:Refresh()
  end
  return panel
end
