-- Page "Windows" (/fg fenster open): the switches and defaults of Modules/FrameTweaks.lua, the list of
-- all windows with a switch each for moving, zoom, opacity and the bar, reset, ignore and a small
-- editor for position, zoom and opacity, plus export and import of the values as text.
-- Every change acts at once: the page calls FrameTweaks, the plain settings go through the Store.
local _, ns = ...
local W, L, K, Store, FL = ns.W, ns.L, ns.PageKit, ns.Store, ns.FrameTweaksLogic
local FT = ns.FrameTweaks

local P = {}
ns.FrameTweaksPage = P

local Flow = ns.FlowLayout

local FEATURES = { "move", "zoom", "alpha", "bar" }
local STATUSES = { "active", "auto", "added", "unloaded", "waiting", "ignored" }
-- Layout in px, scaled with the font where the text grows with it.
local TARGET = 24 -- least size of a switch or button
local SWITCH_GAP, ACTION_GAP, ROW_PAD = 10, 4, 8
local HEAD_HEIGHT, WIDE_HEIGHT, TITLE_MIN = 32, 36, 140
local SETTINGS_MIN, SETTINGS_MAX, SETTINGS_PAD = 280, 340, 4
local LIST_MIN, STACK_BELOW, LIST_MIN_ROWS = 400, 760, 4
local FILTER_WIDTH, SEARCH_MIN, SCROLLBAR = 220, 200, 12

ns.AddLocale("enUS", {
  ["page.windows"] = "Windows",
  ["win.intro"] = "Move, zoom and fade game windows.",
  ["win.enabled"] = "Adjust windows",
  ["win.enabledTip"] = "Off: windows stay as the game has them.",
  ["win.combat"] = "No changes in combat",
  ["win.combatTip"] = "Protected windows wait either way.",
  ["win.bar"] = "Bar below windows",
  ["win.barTip"] = "Opacity, zoom and grip.",
  ["win.barMode"] = "Window controls",
  ["win.barModeTip"] = "Handle: small button, panel on click.",
  ["win.barMode.grip"] = "Handle (default)",
  ["win.barMode.bar"] = "Bar",
  ["win.barMode.off"] = "Off",
  ["win.mapZoom"] = "Scale world map",
  ["win.mapZoomTip"] = "Zoom and grip for the map.",
  ["win.clamp"] = "Keep on screen",
  ["win.clampTip"] = "At least 40 px stay visible.",
  ["win.defaults"] = "Defaults",
  ["win.zoomStep"] = "Zoom step",
  ["win.alphaStep"] = "Opacity step",
  ["win.zoomMin"] = "Smallest zoom",
  ["win.zoomMax"] = "Largest zoom",
  ["win.alphaMin"] = "Lowest opacity",
  ["win.alphaMode"] = "Opacity applies to",
  ["win.alphaModeTip"] = "Whole window: text fades too, at least 35 %.",
  ["win.alphaMode.background"] = "Background",
  ["win.alphaMode.window"] = "Whole window",
  ["win.barPos"] = "Bar position",
  ["win.barPos.outside"] = "Outside (auto)",
  ["win.barPos.inside"] = "Inside, at the bottom",
  ["win.barHover"] = "Bar fully visible on hover",
  ["win.barHoverTip"] = "Off: bar always fully visible.",
  ["win.search"] = "Search windows",
  ["win.filter"] = "Show",
  ["win.filter.all"] = "All",
  ["win.filter.changed"] = "Changed only",
  ["win.filter.auto"] = "Detected (auto)",
  ["win.empty"] = "No windows found.",
  ["win.row.move"] = "Move",
  ["win.row.zoom"] = "Zoom",
  ["win.row.alpha"] = "Opacity",
  ["win.row.bar"] = "Bar",
  ["win.row.tip"] = "Off: this window is left alone.",
  ["win.st.active"] = "active",
  ["win.st.auto"] = "detected",
  ["win.st.added"] = "added",
  ["win.st.unloaded"] = "not loaded",
  ["win.st.waiting"] = "waiting",
  ["win.st.ignored"] = "ignored",
  ["win.st.protected"] = "protected",
  ["win.act.edit"] = "Edit values",
  ["win.act.reset"] = "Reset window",
  ["win.act.resetNone"] = "Already default",
  ["win.act.ignore"] = "Ignore window",
  ["win.act.unignore"] = "Use window again",
  ["win.resetAll"] = "Reset all windows",
  ["win.resetAll.title"] = "Reset windows",
  ["win.resetAll.text"] = "Reset position, zoom and opacity of all windows?",
  ["win.pick"] = "Pick window under mouse",
  ["win.pickTip"] = "Adds a window the detection missed.",
  ["win.pick.wait"] = "Point at a window (%d s)",
  ["win.pick.none"] = "No window found.",
  ["win.pick.bad"] = "Not possible: %s",
  ["win.pick.added"] = "Window added: %s",
  ["win.export"] = "Export",
  ["win.export.title"] = "Export windows",
  ["win.export.hint"] = "Position, zoom and opacity.",
  ["win.export.none"] = "Nothing to export.",
  ["win.import"] = "Import",
  ["win.import.title"] = "Import windows",
  ["win.import.hint"] = "Paste text, then click Apply.",
  ["win.import.empty"] = "Paste text first.",
  ["win.import.badHead"] = "Not a window export.",
  ["win.import.preview"] = "New %d, replaced %d, rejected %d",
  ["win.import.do"] = "Apply",
  ["win.imported"] = "Windows imported: %d",
  ["win.edit.title"] = "Edit: %s",
  ["win.edit.x"] = "X",
  ["win.edit.y"] = "Y",
  ["win.edit.zoom"] = "Zoom %",
  ["win.edit.alpha"] = "Opacity %",
  ["win.edit.mode"] = "Mode",
  ["win.edit.modeDefault"] = "Default",
  ["win.edit.default"] = "default",
  ["win.edit.hint"] = "Empty = default. X and Y go together.",
  ["win.edit.apply"] = "Apply",
  ["win.edit.number"] = "Numbers only.",
  ["win.edit.pair"] = "X and Y go together.",
  ["win.edit.range"] = "Value out of range.",
  ["win.edit.saved"] = "Saved: %s",
})
ns.AddLocale("deDE", {
  ["page.windows"] = "Fenster",
  ["win.intro"] = "Spielfenster verschieben, zoomen und ausblenden.",
  ["win.enabled"] = "Fenster anpassen",
  ["win.enabledTip"] = "Aus: Fenster bleiben wie im Spiel.",
  ["win.combat"] = "Im Kampf nichts ändern",
  ["win.combatTip"] = "Geschützte Fenster warten immer.",
  ["win.bar"] = "Leiste unter Fenstern",
  ["win.barTip"] = "Deckkraft, Zoom und Griff.",
  ["win.barMode"] = "Leiste am Fenster",
  ["win.barModeTip"] = "Griff: kleiner Knopf, Panel per Klick.",
  ["win.barMode.grip"] = "Griff (Standard)",
  ["win.barMode.bar"] = "Leiste",
  ["win.barMode.off"] = "Aus",
  ["win.mapZoom"] = "Weltkarte skalieren",
  ["win.mapZoomTip"] = "Zoom und Griff für die Karte.",
  ["win.clamp"] = "Auf dem Bildschirm halten",
  ["win.clampTip"] = "Mindestens 40 px bleiben sichtbar.",
  ["win.defaults"] = "Standardwerte",
  ["win.zoomStep"] = "Zoom-Schritt",
  ["win.alphaStep"] = "Deckkraft-Schritt",
  ["win.zoomMin"] = "Kleinster Zoom",
  ["win.zoomMax"] = "Größter Zoom",
  ["win.alphaMin"] = "Niedrigste Deckkraft",
  ["win.alphaMode"] = "Deckkraft wirkt auf",
  ["win.alphaModeTip"] = "Ganzes Fenster: Text blasst mit, mind. 35 %.",
  ["win.alphaMode.background"] = "Hintergrund",
  ["win.alphaMode.window"] = "Ganzes Fenster",
  ["win.barPos"] = "Leistenposition",
  ["win.barPos.outside"] = "Außen (automatisch)",
  ["win.barPos.inside"] = "Innen unten",
  ["win.barHover"] = "Leiste voll bei Maus",
  ["win.barHoverTip"] = "Aus: Leiste immer voll sichtbar.",
  ["win.search"] = "Fenster suchen",
  ["win.filter"] = "Anzeigen",
  ["win.filter.all"] = "Alle",
  ["win.filter.changed"] = "Nur geänderte",
  ["win.filter.auto"] = "Erkannt (auto)",
  ["win.empty"] = "Keine Fenster gefunden.",
  ["win.row.move"] = "Verschieben",
  ["win.row.zoom"] = "Zoom",
  ["win.row.alpha"] = "Deckkraft",
  ["win.row.bar"] = "Leiste",
  ["win.row.tip"] = "Aus: Fenster bleibt unberührt.",
  ["win.st.active"] = "aktiv",
  ["win.st.auto"] = "erkannt",
  ["win.st.added"] = "hinzugefügt",
  ["win.st.unloaded"] = "nicht geladen",
  ["win.st.waiting"] = "wartet",
  ["win.st.ignored"] = "ignoriert",
  ["win.st.protected"] = "geschützt",
  ["win.act.edit"] = "Werte bearbeiten",
  ["win.act.reset"] = "Fenster zurücksetzen",
  ["win.act.resetNone"] = "Schon Standard",
  ["win.act.ignore"] = "Fenster ignorieren",
  ["win.act.unignore"] = "Fenster wieder nutzen",
  ["win.resetAll"] = "Alle Fenster zurücksetzen",
  ["win.resetAll.title"] = "Fenster zurücksetzen",
  ["win.resetAll.text"] = "Position, Zoom und Deckkraft aller Fenster zurücksetzen?",
  ["win.pick"] = "Fenster unter der Maus",
  ["win.pickTip"] = "Fügt ein Fenster hinzu, das nicht erkannt wurde.",
  ["win.pick.wait"] = "Auf ein Fenster zeigen (%d s)",
  ["win.pick.none"] = "Kein Fenster gefunden.",
  ["win.pick.bad"] = "Nicht möglich: %s",
  ["win.pick.added"] = "Fenster hinzugefügt: %s",
  ["win.export"] = "Exportieren",
  ["win.export.title"] = "Fenster exportieren",
  ["win.export.hint"] = "Position, Zoom und Deckkraft.",
  ["win.export.none"] = "Nichts zu exportieren.",
  ["win.import"] = "Importieren",
  ["win.import.title"] = "Fenster importieren",
  ["win.import.hint"] = "Text einfügen, dann Anwenden.",
  ["win.import.empty"] = "Erst Text einfügen.",
  ["win.import.badHead"] = "Kein Fenster-Export.",
  ["win.import.preview"] = "Neu %d, ersetzt %d, abgelehnt %d",
  ["win.import.do"] = "Anwenden",
  ["win.imported"] = "Fenster importiert: %d",
  ["win.edit.title"] = "Bearbeiten: %s",
  ["win.edit.x"] = "X",
  ["win.edit.y"] = "Y",
  ["win.edit.zoom"] = "Zoom %",
  ["win.edit.alpha"] = "Deckkraft %",
  ["win.edit.mode"] = "Modus",
  ["win.edit.modeDefault"] = "Standard",
  ["win.edit.default"] = "Standard",
  ["win.edit.hint"] = "Leer = Standard. X und Y gehören zusammen.",
  ["win.edit.apply"] = "Anwenden",
  ["win.edit.number"] = "Nur Zahlen.",
  ["win.edit.pair"] = "X und Y gehören zusammen.",
  ["win.edit.range"] = "Wert außerhalb der Grenzen.",
  ["win.edit.saved"] = "Gespeichert: %s",
})

local function percent(v)
  return string.format("%d %%", math.floor(v + 0.5))
end

local function setting(key, default)
  return function()
    local v = ns.db.settings[key]
    if v == nil then
      return default
    end
    return v
  end, function(v)
    Store.set("settings." .. key, v)
  end
end

-- Import dialog ------------------------------------------------------------------------------------

local importDialog

function P.ShowImport()
  if not importDialog then
    local d = ns.Dialogs.Create("ForeverGuidesWindowImport", 540, 380)
    importDialog = d
    W.SetText(d.title, "win.import.title")
    d.hint = W.Text(d, { key = "win.import.hint", role = "ui", color = "textSecondary", wrap = true })
    d.hint:SetPoint("TOPLEFT", 16, -44)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.status = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
    d.status:SetPoint("BOTTOMLEFT", 16, 52)
    d.status:SetPoint("RIGHT", -16, 0)
    d.go =
      W.Action(d, { label = "act.apply", icon = "check", tooltip = "win.import.do", variant = "primary", width = 130 })
    d.go:SetPoint("BOTTOMRIGHT", -16, 14)
    d.cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    d.cancel:SetPoint("RIGHT", d.go, "LEFT", -8, 0)
    -- The text is checked on every change and nothing is written before the button is clicked.
    function d.refresh(text)
      local parsed = FL.ParseImport(text)
      d.parsed = parsed
      d.go:SetEnabled(#parsed.entries > 0)
      if (text or ""):match("^%s*$") then
        W.SetText(d.status, "win.import.empty")
      elseif not parsed.head then
        W.SetText(d.status, "win.import.badHead")
      else
        local new, replaced, rejected = FL.ImportCounts(parsed, FT.SavedFrames())
        W.SetText(d.status, nil, string.format(L["win.import.preview"], new, replaced, rejected))
      end
    end
    d.paste = W.TextArea(d, {
      height = 200,
      onChange = function(text)
        d.refresh(text)
      end,
    })
    d.paste:SetPoint("TOPLEFT", 16, -84)
    d.paste:SetPoint("RIGHT", -16, 0)
    d.paste.edit:SetMaxLetters(0)
    d.go:SetScript(
      "OnClick",
      ns.Wrap("windows-import", function()
        local count = FT.Import(d.parsed)
        ns.Notify(string.format(L["win.imported"], count), count > 0 and "success" or "warning")
        d:Hide()
        if P.refresh then
          P.refresh()
        end
      end)
    )
  end
  importDialog.paste:SetValue("")
  importDialog.refresh("")
  importDialog:Show()
  importDialog.paste.edit:SetFocus()
end

function P.ShowExport()
  local text = FT.ExportText()
  if text == FL.EXPORT_HEAD then
    ns.Notify(L["win.export.none"], "info")
    return
  end
  ns.Dialogs.Copy("win.export.title", text, "win.export.hint")
end

-- Rows -------------------------------------------------------------------------------------------

local function tooltip(owner, title, text)
  W.Tooltip.Show(owner, { title = title, text = text, anchor = "ANCHOR_TOP" })
end

-- Options of the opacity mode dropdowns; withDefault adds "default" (the window follows the setting).
function P.ModeOptions(withDefault)
  local options = {
    { value = "background", key = "win.alphaMode.background" },
    { value = "window", key = "win.alphaMode.window" },
  }
  if withDefault then
    table.insert(options, 1, { value = "default", key = "win.edit.modeDefault" })
  end
  return options
end

-- A small check box with a label: one switch of a window row.
local function miniToggle(row, feature, onClick)
  local b = CreateFrame("Button", nil, row)
  b:SetHeight(TARGET)
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(14, 14)
  box:SetPoint("LEFT")
  W.Fill(box, "surface2")
  local on = W.Fill(box, "action", 1)
  local border = W.Border(box, "white", 0.4)
  local check = W.CheckMark(box, 10, "text")
  check:SetPoint("CENTER")
  b.label = W.Text(b, { key = "win.row." .. feature, role = "micro", color = "textSecondary" })
  b.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
  local function fit()
    b:SetWidth(math.max(TARGET, 14 + 4 + math.ceil(b.label:GetStringWidth()) + 2))
  end
  ns.Bind(b, fit)
  fit()
  function b.paint(isOn)
    check:SetShown(isOn)
    on:SetShown(isOn)
    border.set(isOn and "actionHi" or "white", isOn and 1 or 0.4)
  end
  b:SetScript("OnClick", ns.Wrap("windows-row-switch", onClick))
  b:HookScript("OnEnter", function(self)
    tooltip(self, L["win.row." .. feature], L["win.row.tip"])
  end)
  b:HookScript("OnLeave", function(self)
    W.Tooltip.Hide(self)
  end)
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

-- A small icon button (edit, reset, ignore); the owner sets b.tipKey, the tooltip names the action.
local function iconButton(row, icon, onClick)
  local b = W.Action(row, { icon = icon, size = TARGET, manual = true })
  b:SetScript("OnClick", ns.Wrap("windows-row-action", onClick))
  b.fgName = function()
    return b.tipKey and L[b.tipKey] or nil
  end
  b:HookScript("OnEnter", function(self)
    if self.tipKey then
      tooltip(self, L[self.tipKey])
    end
  end)
  b:HookScript("OnLeave", function(self)
    W.Tooltip.Hide(self)
  end)
  return b
end

local function statusText(item)
  local text = L["win.st." .. item.status]
  if item.protected then
    text = text .. " · " .. L["win.st.protected"]
  end
  return text
end

-- Page -----------------------------------------------------------------------------------------------

-- Width of a text in the font of the hidden `measure` text.
local function widthOf(measure, text)
  measure:SetText(text)
  return math.ceil(measure:GetStringWidth())
end

-- What a row needs in width: the four switches and the widest status text.
local function rowMetrics(measure)
  local m = { switches = {}, total = 0 }
  for i, feature in ipairs(FEATURES) do
    local w = math.max(TARGET, 14 + 4 + widthOf(measure, L["win.row." .. feature]) + 2)
    m.switches[i] = w
    m.total = m.total + w + (i > 1 and SWITCH_GAP or 0)
  end
  local widest = 0
  for _, status in ipairs(STATUSES) do
    widest = math.max(widest, widthOf(measure, L["win.st." .. status]))
  end
  m.status = widest + widthOf(measure, " · " .. L["win.st.protected"])
  return m
end

-- The switches in lines of `width`: { x, line } per switch and the number of lines.
local function flowSwitches(m, width)
  local spots, x, line = {}, 0, 1
  for i, w in ipairs(m.switches) do
    if x > 0 and x + w > width then
      x, line = 0, line + 1
    end
    spots[i] = { x = x, line = line }
    x = x + w + SWITCH_GAP
  end
  return spots, line
end

-- How the rows of a list `width` px wide are built: "wide" is one line (title, switches, status and
-- buttons), "two" has the switches in a second line, "flow" wraps them to more lines.
local function rowGeometry(m, width)
  local head = K.scaledHeight(HEAD_HEIGHT)
  local actions = 3 * TARGET + 2 * ACTION_GAP + ROW_PAD
  local wide = ROW_PAD + K.scaledHeight(TITLE_MIN) + 12 + m.total + 12 + m.status + 8 + actions
  if width >= wide then
    return { mode = "wide", height = math.max(TARGET + 12, K.scaledHeight(WIDE_HEIGHT)), key = "wide" }
  end
  local spots, lines = flowSwitches(m, width - 2 * ROW_PAD)
  local key = { lines }
  for _, spot in ipairs(spots) do
    key[#key + 1] = spot.x .. ":" .. spot.line
  end
  return {
    mode = lines == 1 and "two" or "flow",
    spots = spots,
    head = head,
    height = head + lines * (TARGET + 2) + 4,
    key = table.concat(key, ","),
  }
end

local function placeRow(row, geo, m)
  row.geo = geo
  for _, part in ipairs({ row.ignore, row.reset, row.edit, row.status, row.title }) do
    part:ClearAllPoints()
  end
  local wide = geo.mode == "wide"
  if wide then
    row.ignore:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
  else
    row.ignore:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_PAD, -math.floor((geo.head - TARGET) / 2))
  end
  row.reset:SetPoint("RIGHT", row.ignore, "LEFT", -ACTION_GAP, 0)
  row.edit:SetPoint("RIGHT", row.reset, "LEFT", -ACTION_GAP, 0)
  row.status:SetPoint("RIGHT", row.edit, "LEFT", -8, 0)
  if wide then
    -- One line: the status column has a fixed width so the switches line up from row to row.
    row.status:SetWidth(m.status)
    local anchor = row.status
    for i = #FEATURES, 1, -1 do
      local sw = row.switches[FEATURES[i]]
      sw:ClearAllPoints()
      sw:SetPoint("RIGHT", anchor, "LEFT", -(i == #FEATURES and 12 or SWITCH_GAP), 0)
      anchor = sw
    end
    row.title:SetPoint("LEFT", row, "LEFT", ROW_PAD, 0)
    row.title:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
    return
  end
  row.status:SetWidth(math.ceil(row.status:GetStringWidth()) + 1)
  for i, feature in ipairs(FEATURES) do
    local sw, spot = row.switches[feature], geo.spots[i]
    sw:ClearAllPoints()
    sw:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + spot.x, -(geo.head + (spot.line - 1) * (TARGET + 2)))
  end
  row.title:SetPoint("LEFT", row, "TOPLEFT", ROW_PAD, -geo.head / 2)
  row.title:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
end

local function build(container)
  local view = ns.NewPageView(container)
  local state = { query = "", filter = "all", sel = nil }
  local refreshers = {}
  local settings, rightPane, list, search, filterBox, editor, empty, conflict, pickStatus, buttons
  local measure, metrics, geo, room
  local allRows = {}
  local refresh, layoutLeft, layoutRight

  ns.AddParagraph(view, "win.intro", { role = "ui", color = "textSecondary", gap = 8 })
  conflict = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = 8 })

  -- Two columns: the settings (own scroll area) and the window list that takes the rest of the page.
  -- Below the stack width the list sits under the settings and the page scrolls.
  local splitOpts = {
    ratio = 0.3,
    minHeight = 300,
    stackedShare = 0,
    stackedLeftMin = 1,
    stackedRightMin = 1,
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function(_, given)
      room = given or room
      return room and (room.viewHeight - room.top - room.pad) or 0
    end,
  }
  -- The sizes follow the font scale, so they are read again on every pass.
  local function scaleOpts(gap)
    splitOpts.leftMin, splitOpts.leftMax = K.scaledHeight(SETTINGS_MIN), K.scaledHeight(SETTINGS_MAX)
    splitOpts.rightMin = K.scaledHeight(LIST_MIN)
    splitOpts.stackBelow = math.max(STACK_BELOW, splitOpts.leftMin + gap + splitOpts.rightMin)
  end
  function splitOpts.onLayout(info)
    scaleOpts(info.gap)
    local needLeft = layoutLeft(info)
    return info.mode == "stacked" and needLeft or nil, layoutRight(info)
  end
  scaleOpts(16)
  local split = Flow.TwoPane(view.content, splitOpts)
  view.stack:Add(split, { gap = 0 })
  rightPane = split.right

  -- Left column: switches and defaults ---------------------------------------------------------
  settings = ns.NewPageView(split.left)
  settings.stack.pad = SETTINGS_PAD
  local s = settings.stack

  local function add(widget, opts)
    s:Add(widget, opts)
    if widget.Refresh then
      refreshers[#refreshers + 1] = widget
    end
    return widget
  end

  local function toggle(key, labelKey, tipKey, default)
    local get, set = setting(key, default)
    local widget = W.Toggle(settings.content, {
      key = labelKey,
      get = get,
      set = set,
      tooltip = labelKey,
      tooltipText = tipKey,
    })
    widget.fgId = "win-" .. key
    return add(widget, { height = 24, gap = 6 })
  end
  toggle("frameTweaks", "win.enabled", "win.enabledTip", true)
  toggle("frameTweaksCombat", "win.combat", "win.combatTip", true)
  -- The old switch frameBar (false = off) is cleared with the choice, so the choice counts from then on.
  local function barModeGet()
    return ns.FrameTweaksBar.Mode()
  end
  local function barModeSet(v)
    Store.set("settings.frameBarMode", v)
    if ns.db.settings.frameBar ~= true then
      Store.set("settings.frameBar", true)
    end
  end
  local barMode = W.Dropdown(settings.content, {
    key = "win.barMode",
    width = 240,
    options = {
      { value = "grip", key = "win.barMode.grip" },
      { value = "bar", key = "win.barMode.bar" },
      { value = "off", key = "win.barMode.off" },
    },
    get = barModeGet,
    set = barModeSet,
    tooltip = "win.barMode",
    tooltipText = "win.barModeTip",
  })
  barMode.fgId = "win-frameBarMode"
  add(Flow.FitDropdown(barMode), { height = 46, width = 240, gap = 6 })
  toggle("frameMapZoom", "win.mapZoom", "win.mapZoomTip", true)
  toggle("frameClamp", "win.clamp", "win.clampTip", true)

  ns.AddHeading(settings, "win.defaults", { gap = 8 })
  -- release: the limits can resize windows at once, so they apply when the thumb is let go.
  local function slider(key, labelKey, min, max, step, default, release)
    local get, set = setting(key, default)
    local widget = W.Slider(settings.content, {
      key = labelKey,
      min = min,
      max = max,
      step = step,
      applyOn = release and "release" or nil,
      get = get,
      set = set,
      format = percent,
    })
    widget.fgId = "win-" .. key
    return add(widget, { height = 42, width = 320 })
  end
  slider("frameZoomStep", "win.zoomStep", 1, 10, 1, 5)
  slider("frameAlphaStep", "win.alphaStep", 1, 10, 1, 5)
  slider("frameZoomMin", "win.zoomMin", 50, 100, 5, 50, true)
  slider("frameZoomMax", "win.zoomMax", 100, 200, 5, 200, true)
  slider("frameAlphaMin", "win.alphaMin", 0, 90, 5, 0)
  local modeGet, modeSet = setting("frameAlphaMode", "background")
  local alphaMode = W.Dropdown(settings.content, {
    key = "win.alphaMode",
    width = 240,
    options = P.ModeOptions(),
    get = modeGet,
    set = modeSet,
    tooltip = "win.alphaMode",
    tooltipText = "win.alphaModeTip",
  })
  alphaMode.fgId = "win-frameAlphaMode"
  add(Flow.FitDropdown(alphaMode), { height = 46, width = 240 })
  local barGet, barSet = setting("frameBarPos", "outside")
  local barPos = W.Dropdown(settings.content, {
    key = "win.barPos",
    width = 240,
    options = {
      { value = "outside", key = "win.barPos.outside" },
      { value = "inside", key = "win.barPos.inside" },
    },
    get = barGet,
    set = barSet,
  })
  barPos.fgId = "win-barPos"
  add(Flow.FitDropdown(barPos), { height = 46, width = 240 })
  toggle("frameBarHover", "win.barHover", "win.barHoverTip", true)

  -- Right column: buttons, search, filter, the list and the editor of the chosen window ----------
  measure = W.Text(rightPane, { role = "micro" })
  measure:Hide()

  buttons = Flow.ButtonRow(rightPane, {
    {
      id = "resetAll",
      label = "act.reset",
      icon = "reset",
      tooltip = "win.resetAll",
      onClick = function()
        ns.Dialogs.Confirm("win.resetAll.title", "win.resetAll.text", function()
          ns.Notify(string.format(L["tweaks.resetAll"], FT.ResetAll()), "success")
          refresh()
        end)
      end,
    },
    {
      id = "pick",
      label = "act.pick",
      icon = "search",
      tooltip = "win.pick",
      tooltipText = "win.pickTip",
      onClick = function()
        W.SetText(pickStatus, nil, string.format(L["win.pick.wait"], FT.PICK_DELAY))
        pickStatus:Show()
        view:Layout()
        FT.Pick(function(name)
          pickStatus:Hide()
          P.Picked(name, refresh, state, list, search, filterBox)
          view:Layout()
        end)
      end,
    },
    {
      id = "export",
      label = "act.export",
      icon = "export",
      tooltip = "win.export",
      onClick = function()
        P.ShowExport()
      end,
    },
    {
      id = "import",
      label = "act.import",
      icon = "import",
      tooltip = "win.import",
      onClick = function()
        P.ShowImport()
      end,
    },
  })
  -- Nothing saved: the button is off and its tooltip says why.
  buttons:GetButton("resetAll"):HookScript("OnEnter", function(self)
    if not self:IsEnabled() then
      tooltip(self, L["win.resetAll"], L["win.act.resetNone"])
    end
  end)
  pickStatus = W.Text(rightPane, { role = "micro", color = "accent2", wrap = true })
  pickStatus:Hide()

  search = W.EditBox(rightPane, {
    placeholder = "win.search",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  filterBox = W.Dropdown(rightPane, {
    key = "win.filter",
    width = 240,
    options = {
      { value = "all", key = "win.filter.all" },
      { value = "changed", key = "win.filter.changed" },
      { value = "auto", key = "win.filter.auto" },
    },
    get = function()
      return state.filter
    end,
    set = function(v)
      state.filter = v
      refresh()
    end,
  })
  Flow.FitDropdown(filterBox)
  refreshers[#refreshers + 1] = filterBox

  local function changed()
    refresh()
  end

  local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    allRows[#allRows + 1] = row
    row:SetClipsChildren(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    local function paint()
      row.bg:SetColorTexture(1, 1, 1, row.selected and 0.1 or (row.hover and 0.05 or 0))
      row.line:SetColorTexture(1, 1, 1, ns.Theme.lineAlpha())
    end
    row.paint = paint
    ns.Bind(row, paint)
    row:SetScript("OnEnter", function()
      row.hover = true
      paint()
    end)
    row:SetScript("OnLeave", function()
      row.hover = false
      paint()
    end)
    local function pick()
      local item = row.item
      if item then
        state.sel = state.sel ~= item.name and item.name or nil
        refresh()
      end
    end
    row:SetScript("OnClick", ns.Wrap("windows-row", pick))
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    row.switches = {}
    for _, feature in ipairs(FEATURES) do
      row.switches[feature] = miniToggle(row, feature, function()
        local item = row.item
        if item then
          FT.SetFeature(item.name, feature, item.off[feature] == true)
          changed()
        end
      end)
    end
    row.ignore = iconButton(row, "eye-off", function()
      local item = row.item
      if item then
        if item.status == "ignored" then
          FT.Unignore(item.name)
        else
          FT.Ignore(item.name)
        end
        changed()
      end
    end)
    row.reset = iconButton(row, "reset", function()
      local item = row.item
      if item then
        FT.Reset(item.name)
        changed()
      end
    end)
    row.edit = iconButton(row, "pencil", pick)
    row.edit.tipKey = "win.act.edit"
    row.status = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.title = W.Text(row, { role = "ui" })
    metrics = metrics or rowMetrics(measure)
    placeRow(row, geo or rowGeometry(metrics, 400), metrics)
    return row
  end

  local function bindRow(row, item)
    row.item = item
    row.selected = item.name == state.sel
    W.SetText(row.title, nil, item.name)
    W.SetColor(row.title, item.status == "ignored" and "textMuted" or "text")
    W.SetText(row.status, nil, statusText(item))
    if row.geo and row.geo.mode ~= "wide" then
      row.status:SetWidth(math.ceil(row.status:GetStringWidth()) + 1)
    end
    row.reset:SetEnabled(item.hasValues)
    row.reset.tipKey = item.hasValues and "win.act.reset" or "win.act.resetNone"
    for _, feature in ipairs(FEATURES) do
      row.switches[feature].paint(item.off[feature] ~= true)
    end
    row.ignore.tipKey = item.status == "ignored" and "win.act.unignore" or "win.act.ignore"
    row.ignore:SetIcon(item.status == "ignored" and "eye" or "eye-off")
    row.paint()
  end

  list = W.ScrollList(rightPane, {
    rowHeight = K.scaledHeight(HEAD_HEIGHT + TARGET + 6),
    createRow = createRow,
    bindRow = bindRow,
  })
  W.Fill(list, "surface", 1)
  empty = W.Text(rightPane, { key = "win.empty", role = "ui", color = "textMuted", wrap = true })

  editor = P.NewEditor(rightPane, function()
    refresh()
  end)

  -- Fills the right column: the controls on top at their height, the editor at the bottom when a
  -- window is chosen and the list in between. Returns the height the column needs at least.
  function layoutRight(info)
    local width, y = info.rightWidth, 0
    local function put(frame, top, w, h, left)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", rightPane, "TOPLEFT", left or 0, -top)
      if w then
        frame:SetSize(w, h)
      end
    end
    buttons:SetWidth(width)
    put(buttons, y)
    y = y + buttons:fgGridLayout(width) + 8
    if pickStatus:IsShown() then
      pickStatus:SetWidth(width)
      put(pickStatus, y)
      y = y + math.ceil(pickStatus:GetStringHeight()) + 8
    end
    local filterWidth = math.min(K.scaledHeight(FILTER_WIDTH), width)
    if width >= filterWidth + 12 + SEARCH_MIN then
      put(search, y + 17, width - filterWidth - 12, 26)
      put(filterBox, y, filterWidth, 46, width - filterWidth)
      y = y + 46 + 8
    else
      put(search, y, width, 26)
      put(filterBox, y + 26 + 8, filterWidth, 46)
      y = y + 26 + 8 + 46 + 8
    end
    Flow.FitDropdown(filterBox)
    metrics = rowMetrics(measure)
    local fresh = rowGeometry(metrics, width - SCROLLBAR)
    if not geo or geo.key ~= fresh.key then
      geo = fresh
      for _, row in ipairs(allRows) do
        placeRow(row, geo, metrics)
      end
    end
    list:SetRowHeight(geo.height)
    local below = 0
    if editor:IsShown() then
      editor:SetWidth(width)
      below = editor:fgGridLayout(width) + 12
    end
    local least = y + below
    if list:IsShown() then
      local listHeight = math.max(LIST_MIN_ROWS * geo.height, info.rightHeight - y - below)
      put(list, y, width, listHeight)
      least = least + LIST_MIN_ROWS * geo.height
      y = y + listHeight + 12
    elseif empty:IsShown() then
      empty:SetWidth(width)
      put(empty, y)
      y = y + math.ceil(empty:GetStringHeight()) + 12
      least = least + math.ceil(empty:GetStringHeight()) + 12
    end
    if editor:IsShown() then
      put(editor, y)
    end
    return least
  end

  -- Fills the left column: the settings scroll inside it when they are taller than the page.
  -- Stacked, the column is as tall as its settings and the page scrolls instead.
  function layoutLeft(info)
    local area = settings.area
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", split.left, "TOPLEFT", 0, 0)
    area:SetSize(info.leftWidth, info.leftHeight)
    area.content:SetWidth(math.max(1, info.leftWidth - SCROLLBAR))
    area:EnableMouseWheel(info.mode == "side")
    settings.stack:Layout()
    return area.content:GetHeight()
  end

  local function selectedItem(rows)
    for _, item in ipairs(rows) do
      if item.name == state.sel then
        return item
      end
    end
    return nil
  end

  function refresh()
    local rows = FT.Rows()
    local shown = FL.FilterRows(rows, state.query, state.filter)
    local anySaved = false
    for _, entry in ipairs(rows) do
      anySaved = anySaved or entry.hasValues
    end
    buttons:SetItemEnabled("resetAll", anySaved)
    list:SetData(shown)
    list:SetShown(#shown > 0)
    empty:SetShown(#shown == 0)
    local others = FT.Conflicts()
    conflict:SetShown(#others > 0)
    if #others > 0 then
      conflict:SetText(string.format(L["tweaks.conflict"], table.concat(others, ", ")))
    end
    local item = selectedItem(rows)
    if not item then
      state.sel = nil
    end
    editor:SetShown(item ~= nil)
    if item then
      editor:Load(item.name)
    end
    for _, widget in ipairs(refreshers) do
      widget:Refresh()
    end
    view:Layout()
  end
  P.refresh = refresh

  ns.On("FG_SETTING_CHANGED", function(_, path)
    if container:IsShown() and type(path) == "string" and path:find("^settings%.frame") then
      refresh()
    end
  end)

  function view:Show()
    refresh()
  end
  view.settings, view.split = settings, split
  view.list, view.state, view.editor, view.search, view.buttons = list, state, editor, search, buttons
  view.filterBox, view.conflict, view.pickStatus = filterBox, conflict, pickStatus
  return view
end

-- The player picked a window under the mouse: add it and show it in the list.
function P.Picked(name, refresh, state, list, search, filterBox)
  if not name then
    ns.Notify(L["win.pick.none"], "warning")
    return
  end
  if not FT.Window(name) then
    local ok = FT.Add(name)
    if not ok then
      ns.Notify(string.format(L["win.pick.bad"], name), "warning")
      return
    end
    ns.Notify(string.format(L["win.pick.added"], name), "success")
  end
  state.query, state.filter, state.sel = "", "all", name
  search.edit:SetText("")
  filterBox:Refresh()
  refresh()
  for i, item in ipairs(FL.FilterRows(FT.Rows(), "", "all")) do
    if item.name == name then
      list:Reveal(i)
      break
    end
  end
end

-- Editor -----------------------------------------------------------------------------------------

local FIELDS = { "x", "y", "zoom", "alpha" }

-- "" is a cleared value (nil, true), a number its value, anything else is refused (nil, false).
local function parseNumber(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
  if text == "" then
    return nil, true
  end
  local n = tonumber(text)
  if n then
    return n, true
  end
  return nil, false
end

local function show(n)
  return n == nil and "" or string.format("%g", n)
end

function P.NewEditor(parent, onApplied)
  local f = CreateFrame("Frame", nil, parent)
  f.title = W.Text(f, { role = "ui", color = "accent2" })
  f.title:SetPoint("TOPLEFT")
  f.captions, f.boxes = {}, {}
  for _, field in ipairs(FIELDS) do
    f.captions[field] = W.Text(f, { key = "win.edit." .. field, role = "micro", color = "textSecondary" })
    f.boxes[field] = W.EditBox(f, { placeholder = "win.edit.default" })
  end
  -- The mode acts at once like the bar's switch; the number fields wait for "Apply".
  f.mode = W.Dropdown(f, {
    key = "win.edit.mode",
    width = 240,
    tooltip = "win.alphaMode",
    tooltipText = "win.alphaModeTip",
    options = P.ModeOptions(true),
    get = function()
      local raw = f.name and FT.SavedFrames()[f.name]
      return type(raw) == "table" and FL.CleanMode(raw.alphaMode) or "default"
    end,
    set = function(v)
      if f.name then
        ns.FrameTweaksAlpha.ChooseMode(f.name, v ~= "default" and v or nil)
      end
    end,
  })
  f.hint = W.Text(f, { key = "win.edit.hint", role = "micro", color = "textMuted", wrap = true })
  f.apply = W.Action(f, {
    label = "act.apply",
    icon = "check",
    tooltip = "win.edit.apply",
    variant = "primary",
    width = 130,
    onClick = function()
      f:Apply()
    end,
  })

  function f:Load(name)
    f.name = name
    W.SetText(f.title, nil, string.format(L["win.edit.title"], name))
    local v = FT.Values(name)
    for _, field in ipairs(FIELDS) do
      f.boxes[field].edit:SetText(show(v[field]))
    end
    f.mode:Refresh()
  end

  function f:Apply()
    local values = {}
    for _, field in ipairs(FIELDS) do
      local n, ok = parseNumber(f.boxes[field].edit:GetText())
      if not ok then
        ns.Notify(L["win.edit.number"], "warning")
        return false
      end
      values[field] = n
    end
    local ok, reason = FT.SetValues(f.name, values)
    if not ok then
      ns.Notify(L["win.edit." .. reason], "warning")
      return false
    end
    ns.Notify(string.format(L["win.edit.saved"], f.name), "success")
    onApplied()
    return true
  end

  function f:fgGridLayout(width)
    f.title:SetWidth(width)
    local y = math.ceil(f.title:GetStringHeight()) + 6
    local columns = width >= 420 and 4 or 2
    local gap = 8
    local boxWidth = math.floor((width - gap * (columns - 1)) / columns)
    for i, field in ipairs(FIELDS) do
      local col, line = (i - 1) % columns, math.floor((i - 1) / columns)
      local x, top = col * (boxWidth + gap), y + line * 46
      local caption, box = f.captions[field], f.boxes[field]
      caption:ClearAllPoints()
      caption:SetPoint("TOPLEFT", f, "TOPLEFT", x, -top)
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(top + 16))
      box:SetSize(boxWidth, 26)
    end
    y = y + math.ceil(#FIELDS / columns) * 46
    f.mode:ClearAllPoints()
    f.mode:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    f.mode:SetSize(math.min(width, 240), 46)
    ns.FlowLayout.FitDropdown(f.mode)
    y = y + 46 + 4
    f.hint:SetWidth(width)
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    y = y + math.ceil(f.hint:GetStringHeight()) + 8
    f.apply:ClearAllPoints()
    f.apply:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    y = y + 26
    f:SetHeight(y)
    return y
  end
  return f
end

ns.RegisterPage({
  id = "windows",
  order = 740,
  group = "system",
  title = "page.windows",
  icon = ns.ICONS.windows,
  aliases = { "fenster", "windows" },
  build = build,
})
