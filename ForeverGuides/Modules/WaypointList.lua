-- The waypoint list: a window "Waypoints" and a sidebar page that share one builder.
-- WLUI.Build(parent) fills any frame with the tabs "List" (input field, actions, the list)
-- and "Settings", so a map page can embed the same content later. Everything it does goes
-- through ns.Waypoints; it only listens to FG_WAYPOINTS_CHANGED.
local _, ns = ...
local W, L, Theme, U, WL, WP, K, FL =
  ns.W, ns.L, ns.Theme, ns.U, ns.WaypointLogic, ns.Waypoints, ns.PageKit, ns.FlowLayout

local WLUI = {}
ns.WaypointList = WLUI

local HEAD_H = 22
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 300, 760, 900
local DEFAULT_W, DEFAULT_H = 380, 460
local REFRESH_EVERY = 1

ns.AddLocale("enUS", {
  ["page.waypoints"] = "Waypoints",
  ["wp.title"] = "Waypoints",
  ["wp.close"] = "Close waypoint list",
  ["wp.grip"] = "Drag to resize",
  ["wp.tab.list"] = "List",
  ["wp.tab.settings"] = "Settings",
  ["wp.input.placeholder"] = "Paste coordinates or /way text",
  ["wp.here"] = "Set here",
  ["wp.hereTip"] = "Sets a waypoint at your position.\nText in the field above is the title.",
  ["wp.next"] = "Next",
  ["wp.nextTip"] = "Makes the next waypoint of the list the active one.",
  ["wp.import"] = "Import...",
  ["wp.export"] = "Export...",
  ["wp.clear"] = "Remove all",
  ["wp.clearTip"] = "Removes every waypoint that is not pinned.",
  ["wp.empty"] = "No waypoints: paste coordinates or click Set here.",
  ["wp.pinned"] = "pinned",
  ["wp.act.remove"] = "Remove waypoint",
  ["wp.act.pin"] = "Pin (stays after Remove all and on arrival)",
  ["wp.act.unpin"] = "Unpin",
  ["wp.act.share"] = "Share",
  ["wp.act.edit"] = "Edit title, note and color",
  ["wp.clear.title"] = "Remove all waypoints",
  ["wp.clear.text"] = "Remove all unpinned waypoints?\nThis is permanent.",
  ["wp.export.title"] = "Export waypoints",
  ["wp.export.hint"] = "One /way line per waypoint, to import or share.",
  ["wp.import.title"] = "Import waypoints",
  ["wp.import.hint"] = "Paste /way lines or coordinates, one per line.",
  ["wp.import.paste"] = "Text to import",
  ["wp.import.do"] = "Import",
  ["wp.import.status"] = "%d waypoint(s) recognized, %d line(s) not readable.",
  ["wp.import.empty"] = "Paste text to see what will be imported.",
  ["wp.edit.title"] = "Edit waypoint",
  ["wp.edit.name"] = "Title",
  ["wp.edit.note"] = "Note",
  ["wp.edit.color"] = "Color: %s",
  ["wp.edit.save"] = "Save",
  ["wp.color.accent2"] = "gold",
  ["wp.color.actionHi"] = "teal",
  ["wp.color.success"] = "green",
  ["wp.color.warning"] = "orange",
  ["wp.color.danger"] = "red",
  ["wp.color.info"] = "blue",
  ["wp.color.accent"] = "rose",
  ["wp.color.textSecondary"] = "gray",
  ["wp.set.heading"] = "Arrow and behavior",
  ["wp.set.arrow"] = "Show the arrow",
  ["wp.set.radius"] = "Arrival radius",
  ["wp.set.autoClear"] = "Remove a waypoint when I arrive",
  ["wp.set.autoClearHint"] = "Pinned stay, the next waypoint becomes active.",
  ["wp.set.native"] = "Also mark it on the world map",
  ["wp.set.nativeHint"] = "Active waypoint as the game map pin.",
  ["wp.set.nativeMissing"] = "Client has no map pins, no effect.",
  ["wp.set.locked"] = "Lock the arrow position",
  ["wp.set.scale"] = "Arrow size",
  ["wp.set.look"] = "Arrow window appearance...",
  ["wp.set.lookHint"] = "Set a waypoint first, then adjust the arrow window.",
})
ns.AddLocale("deDE", {
  ["page.waypoints"] = "Wegpunkte",
  ["wp.title"] = "Wegpunkte",
  ["wp.close"] = "Wegpunkt-Liste schließen",
  ["wp.grip"] = "Ziehen zum Skalieren",
  ["wp.tab.list"] = "Liste",
  ["wp.tab.settings"] = "Einstellungen",
  ["wp.input.placeholder"] = "Koordinaten oder /way-Text einfügen",
  ["wp.here"] = "Hier setzen",
  ["wp.hereTip"] = "Setzt einen Wegpunkt an deiner Position.\nText im Feld oben wird der Titel.",
  ["wp.next"] = "Weiter",
  ["wp.nextTip"] = "Macht den nächsten Wegpunkt der Liste zum aktiven.",
  ["wp.import"] = "Importieren...",
  ["wp.export"] = "Exportieren...",
  ["wp.clear"] = "Alle entfernen",
  ["wp.clearTip"] = "Entfernt jeden Wegpunkt, der nicht angeheftet ist.",
  ["wp.empty"] = "Keine Wegpunkte: Koordinaten einfügen oder Hier setzen.",
  ["wp.pinned"] = "angeheftet",
  ["wp.act.remove"] = "Wegpunkt entfernen",
  ["wp.act.pin"] = "Anheften (bleibt nach Alle entfernen und bei Ankunft)",
  ["wp.act.unpin"] = "Lösen",
  ["wp.act.share"] = "Teilen",
  ["wp.act.edit"] = "Titel, Notiz und Farbe ändern",
  ["wp.clear.title"] = "Alle Wegpunkte entfernen",
  ["wp.clear.text"] = "Alle nicht angehefteten Wegpunkte entfernen?\nDas ist endgültig.",
  ["wp.export.title"] = "Wegpunkte exportieren",
  ["wp.export.hint"] = "Eine /way-Zeile je Wegpunkt, zum Importieren oder Teilen.",
  ["wp.import.title"] = "Wegpunkte importieren",
  ["wp.import.hint"] = "/way-Zeilen oder Koordinaten einfügen, eine je Zeile.",
  ["wp.import.paste"] = "Text zum Importieren",
  ["wp.import.do"] = "Importieren",
  ["wp.import.status"] = "%d Wegpunkt(e) erkannt, %d Zeile(n) nicht lesbar.",
  ["wp.import.empty"] = "Füge Text ein, dann siehst du, was importiert wird.",
  ["wp.edit.title"] = "Wegpunkt bearbeiten",
  ["wp.edit.name"] = "Titel",
  ["wp.edit.note"] = "Notiz",
  ["wp.edit.color"] = "Farbe: %s",
  ["wp.edit.save"] = "Speichern",
  ["wp.color.accent2"] = "Gold",
  ["wp.color.actionHi"] = "Türkis",
  ["wp.color.success"] = "Grün",
  ["wp.color.warning"] = "Orange",
  ["wp.color.danger"] = "Rot",
  ["wp.color.info"] = "Blau",
  ["wp.color.accent"] = "Rosa",
  ["wp.color.textSecondary"] = "Grau",
  ["wp.set.heading"] = "Pfeil und Verhalten",
  ["wp.set.arrow"] = "Pfeil anzeigen",
  ["wp.set.radius"] = "Ankunftsradius",
  ["wp.set.autoClear"] = "Wegpunkt bei Ankunft entfernen",
  ["wp.set.autoClearHint"] = "Angeheftete bleiben, der nächste Wegpunkt wird aktiv.",
  ["wp.set.native"] = "Zusätzlich auf der Weltkarte markieren",
  ["wp.set.nativeHint"] = "Aktiver Wegpunkt als Kartenmarkierung des Spiels.",
  ["wp.set.nativeMissing"] = "Client ohne Kartenmarkierung, ohne Wirkung.",
  ["wp.set.locked"] = "Position des Pfeils sperren",
  ["wp.set.scale"] = "Pfeil-Größe",
  ["wp.set.look"] = "Aussehen des Pfeil-Fensters...",
  ["wp.set.lookHint"] = "Erst Wegpunkt setzen, dann Pfeil-Fenster anpassen.",
})

-- Dialogs --------------------------------------------------------------------------------------

function WLUI.ConfirmClear()
  if #WP.List() == 0 then
    ns.Notify(L["wp.none"], "info")
    return
  end
  ns.Dialogs.Confirm("wp.clear.title", "wp.clear.text", function()
    local removed, kept = WP.Clear()
    ns.Notify(string.format(kept > 0 and L["wp.clearedKept"] or L["wp.cleared"], removed, kept), "info")
  end)
end

local editDlg
local function showEdit(wp)
  if not editDlg then
    local d = ns.Dialogs.Create("ForeverGuidesWaypointEdit", 400, 280)
    editDlg = d
    d.nameLabel = W.Text(d, { key = "wp.edit.name", role = "ui" })
    d.nameLabel:SetPoint("TOPLEFT", 16, -44)
    d.name = W.EditBox(d, { placeholder = "wp.edit.name" })
    d.name:SetPoint("TOPLEFT", 16, -62)
    d.name:SetPoint("TOPRIGHT", -16, -62)
    d.name.edit:SetMaxLetters(WL.MAX_TITLE)
    d.noteLabel = W.Text(d, { key = "wp.edit.note", role = "ui" })
    d.noteLabel:SetPoint("TOPLEFT", 16, -100)
    d.note = W.EditBox(d, { placeholder = "wp.edit.note" })
    d.note:SetPoint("TOPLEFT", 16, -118)
    d.note:SetPoint("TOPRIGHT", -16, -118)
    d.note.edit:SetMaxLetters(WL.MAX_NOTE)
    d.colorLabel = W.Text(d, { role = "ui" })
    d.colorLabel:SetPoint("TOPLEFT", 16, -158)
    d.swatches = {}
    local function paintSwatches()
      for name, s in pairs(d.swatches) do
        s.border.show(d.color == name)
      end
      W.SetText(d.colorLabel, nil, string.format(L["wp.edit.color"], L["wp.color." .. d.color]))
    end
    local prev
    for _, name in ipairs(WL.PALETTE) do
      local s = CreateFrame("Button", nil, d)
      s:SetSize(28, 28)
      s:SetPoint("TOPLEFT", prev or d, prev and "TOPRIGHT" or "TOPLEFT", prev and 6 or 16, prev and 0 or -180)
      s.fill = s:CreateTexture(nil, "ARTWORK")
      s.fill:SetPoint("TOPLEFT", 3, -3)
      s.fill:SetPoint("BOTTOMRIGHT", -3, 3)
      ns.Bind(s.fill, function(t)
        t:SetColorTexture(Theme.color(name))
      end)
      s.border = W.Border(s, "text", 1, 2)
      s:SetScript("OnClick", function()
        d.color = name
        paintSwatches()
      end)
      s:SetScript("OnEnter", function(self)
        ns.ShowTooltip(self, L["wp.color." .. name])
      end)
      s:SetScript("OnLeave", ns.HideTooltip)
      ns.Focus.register(s, function(self)
        self:Click()
      end)
      d.swatches[name] = s
      prev = s
    end
    d.paint = paintSwatches
    d.save =
      W.Action(d, { label = "act.save", icon = "save", tooltip = "wp.edit.save", variant = "primary", width = 120 })
    d.save:SetPoint("BOTTOMRIGHT", -16, 14)
    d.cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    d.cancel:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
  end
  local d = editDlg
  W.SetText(d.title, "wp.edit.title")
  d.name.edit:SetText(wp.title)
  d.note.edit:SetText(wp.note)
  d.color = wp.color
  d.paint()
  d.save:SetScript(
    "OnClick",
    ns.Wrap("wp-edit-save", function()
      WP.Rename(wp.id, d.name.edit:GetText())
      WP.SetNote(wp.id, d.note.edit:GetText())
      WP.SetColor(wp.id, d.color)
      d:Hide()
    end)
  )
  d:Show()
  d.name.edit:SetFocus()
end

local importDlg
local function showImport()
  if not importDlg then
    local d = ns.Dialogs.Create("ForeverGuidesWaypointImport", 560, 380)
    importDlg = d
    W.SetText(d.title, "wp.import.title")
    d.hint = W.Text(d, { key = "wp.import.hint", role = "ui", color = "textSecondary", wrap = true })
    d.hint:SetPoint("TOPLEFT", 16, -44)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.pasteLabel = W.Text(d, { key = "wp.import.paste", role = "ui" })
    d.pasteLabel:SetPoint("TOPLEFT", 16, -96)
    d.status = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
    d.status:SetPoint("BOTTOMLEFT", 16, 52)
    d.status:SetPoint("RIGHT", -16, 0)
    d.go =
      W.Action(d, { label = "act.import", icon = "import", tooltip = "wp.import.do", variant = "primary", width = 130 })
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
    function d.refresh(text)
      local result = WL.importText(text, WP.ParseContext())
      d.recognized = #result.specs
      d.go:SetEnabled(#result.specs > 0)
      if U.trim(text) == "" then
        W.SetText(d.status, "wp.import.empty")
      else
        W.SetText(d.status, nil, string.format(L["wp.import.status"], #result.specs, #result.errors))
      end
    end
    d.paste = W.TextArea(d, {
      height = 180,
      onChange = function(text)
        d.refresh(text)
      end,
    })
    d.paste:SetPoint("TOPLEFT", 16, -116)
    d.paste:SetPoint("RIGHT", -16, 0)
    d.paste.edit:SetMaxLetters(0)
    d.go:SetScript(
      "OnClick",
      ns.Wrap("wp-import", function()
        local added, skipped = WP.Import(d.paste:GetValue())
        ns.Notify(string.format(L["wp.imported"], added, skipped), added > 0 and "success" or "warning")
        d:Hide()
      end)
    )
  end
  importDlg.paste:SetValue("")
  importDlg.refresh("")
  importDlg:Show()
  importDlg.paste.edit:SetFocus()
end
WLUI.ShowImport = showImport

local function showExport()
  if #WP.List() == 0 then
    ns.Notify(L["wp.none"], "info")
    return
  end
  ns.Dialogs.Copy("wp.export.title", WP.Export(), "wp.export.hint")
end

-- Content -------------------------------------------------------------------------------------------

local function distanceText(wp)
  local yards = WP.Distance(wp)
  return yards and WL.formatDistance(yards, ns.GetActiveLocale()) or ""
end

local function bindRow(wp)
  local active = WP.data().active == wp.id
  local sub = string.format("%s · %s", WP.MapName(wp.map), WL.coordText(wp.x, wp.y))
  if wp.pinned then
    sub = sub .. " · " .. L["wp.pinned"]
  end
  return {
    title = (active and "> " or "") .. wp.title,
    sub = sub,
    right = distanceText(wp),
    selected = active,
    iconPaint = function(tex)
      tex:SetColorTexture(Theme.rgb(wp.color))
    end,
    actions = {
      {
        icon = "close",
        tooltip = L["wp.act.remove"],
        onClick = function()
          WP.Remove(wp.id)
        end,
      },
      {
        icon = "pin",
        selected = wp.pinned,
        tooltip = L[wp.pinned and "wp.act.unpin" or "wp.act.pin"],
        onClick = function()
          WP.SetPinned(wp.id, not wp.pinned)
        end,
      },
      {
        icon = "share",
        tooltip = L["wp.act.share"],
        onClick = function()
          ns.Share.Open(wp.title, WL.formatLine(wp))
        end,
      },
      {
        icon = "pencil",
        tooltip = L["wp.act.edit"],
        onClick = function()
          showEdit(wp)
        end,
      },
    },
  }
end

local function buildList(pane, view)
  local input = W.EditBox(pane, {
    placeholder = "wp.input.placeholder",
    clear = true,
    onEnter = function(text)
      if U.trim(text) ~= "" and WP.Command(text) then
        view.input.edit:SetText("")
      end
    end,
  })
  input:SetPoint("TOPLEFT", 0, 0)
  input:SetPoint("TOPRIGHT", 0, 0)
  view.input = input
  local buttons = {
    {
      id = "here",
      label = "act.here",
      icon = "marker",
      variant = "primary",
      tooltip = "wp.here",
      tooltipText = "wp.hereTip",
      onClick = function()
        WP.SetHere(input.edit:GetText())
      end,
    },
    {
      id = "next",
      label = "act.next",
      icon = "chevron-right",
      tooltip = "wp.next",
      tooltipText = "wp.nextTip",
      onClick = function()
        WP.Next()
      end,
    },
    { id = "import", label = "act.import", icon = "import", tooltip = "wp.import", onClick = showImport },
    { id = "export", label = "act.export", icon = "export", tooltip = "wp.export", onClick = showExport },
    {
      id = "clear",
      label = "act.clear",
      icon = "trash",
      variant = "ghost",
      tooltip = "wp.clear",
      tooltipText = "wp.clearTip",
      onClick = WLUI.ConfirmClear,
    },
  }
  -- The map test exists only when an extension registers it.
  local mapTest = ns.DevTools.byId.mapprobe
  if mapTest then
    buttons[#buttons + 1] = {
      id = "probe",
      label = "act.probe",
      icon = "search",
      variant = "ghost",
      tooltip = "wp.probe",
      tooltipText = "wp.probeTip",
      onClick = mapTest.run,
    }
  end
  view.buttons = FL.ButtonRow(pane, buttons)
  view.buttons:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -6)
  view.buttons:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, -6)
  view.list = K.NewList(pane, {
    rowHeight = 42,
    bind = bindRow,
    onClick = function(wp)
      WP.Activate(wp.id)
    end,
  })
  view.list:SetPoint("TOPLEFT", view.buttons, "BOTTOMLEFT", 0, -6)
  view.list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  view.empty = W.Text(pane, { key = "wp.empty", role = "ui", color = "textMuted", wrap = true })
  view.empty:SetPoint("TOPLEFT", view.buttons, "BOTTOMLEFT", 8, -16)
  view.empty:SetPoint("RIGHT", pane, "RIGHT", -8, 0)
end

local function addToggle(view, key, setting, hintKey)
  local t = W.Toggle(view.content, {
    key = key,
    get = function()
      return WP.Settings()[setting]
    end,
    set = function(on)
      WP.SetSetting(setting, on)
    end,
  })
  view.stack:Add(t, { height = 24, gap = hintKey and 2 or 10 })
  view.controls[#view.controls + 1] = t
  if hintKey then
    ns.AddParagraph(view, hintKey, { role = "micro", color = "textMuted", gap = 10 })
  end
  return t
end

local function buildSettings(pane, view)
  local sv = ns.NewPageView(pane)
  view.content, view.stack, view.controls = sv.content, sv.stack, {}
  ns.AddHeading(view, "wp.set.heading")
  addToggle(view, "wp.set.arrow", "arrow")
  local radius = W.Slider(view.content, {
    key = "wp.set.radius",
    min = WL.RADIUS_MIN,
    max = WL.RADIUS_MAX,
    step = 1,
    get = function()
      return WP.Settings().arrivalRadius
    end,
    set = function(v)
      WP.SetSetting("arrivalRadius", v)
    end,
    format = function(v)
      return WL.formatDistance(v, ns.GetActiveLocale())
    end,
  })
  view.stack:Add(radius, { height = 42, gap = 10 })
  view.controls[#view.controls + 1] = radius
  addToggle(view, "wp.set.autoClear", "autoClear", "wp.set.autoClearHint")
  addToggle(
    view,
    "wp.set.native",
    "nativeMarker",
    ns.can.userWaypoint and "wp.set.nativeHint" or "wp.set.nativeMissing"
  )
  addToggle(view, "wp.set.locked", "locked")
  local scale = W.Slider(view.content, {
    key = "wp.set.scale",
    min = 50,
    max = 200,
    step = 5,
    applyOn = "release",
    get = function()
      return math.floor(WP.Settings().scale * 100 + 0.5)
    end,
    set = function(v)
      WP.SetSetting("scale", v / 100)
    end,
    format = function(v)
      return string.format("%d%%", v)
    end,
  })
  view.stack:Add(scale, { height = 42, gap = 10 })
  view.controls[#view.controls + 1] = scale
  view.stack:Add(
    W.Action(view.content, {
      label = "act.look",
      icon = "palette",
      tooltip = "wp.set.look",
      width = 240,
      onClick = function()
        if ns.WaypointArrow.IsShown() then
          ns.WaypointArrow.OpenLook()
        else
          ns.Notify(L["wp.set.lookHint"], "info")
        end
      end,
    }),
    { height = 26, width = 240 }
  )
  sv:Layout()
  view.settingsView = sv
end

-- Fills `parent` with the tabs and both panes. Returns the view { frame, Refresh, Select }.
function WLUI.Build(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints()
  local view = { frame = frame }
  local listPane = CreateFrame("Frame", nil, frame)
  local settingsPane = CreateFrame("Frame", nil, frame)
  view.panes = { list = listPane, settings = settingsPane }
  view.tabs = W.Tabs(frame, {
    tabs = { { id = "list", key = "wp.tab.list" }, { id = "settings", key = "wp.tab.settings" } },
    onSelect = function(id)
      for name, pane in pairs(view.panes) do
        pane:SetShown(name == id)
      end
      view.selected = id
    end,
  })
  view.tabs:SetPoint("TOPLEFT", 0, 0)
  view.tabs:SetPoint("TOPRIGHT", 0, 0)
  for _, pane in pairs(view.panes) do
    pane:SetPoint("TOPLEFT", view.tabs, "BOTTOMLEFT", 0, -8)
    pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  end
  buildList(listPane, view)
  buildSettings(settingsPane, view)

  function view:Select(id)
    view.tabs:Select(id == "settings" and "settings" or "list")
  end

  -- Re-reads data, distances and the switches.
  function view:Refresh()
    local items = WP.List()
    view.list:SetData(items)
    view.empty:SetShown(#items == 0)
    for _, control in ipairs(view.controls) do
      control:Refresh()
    end
  end

  ns.On("FG_WAYPOINTS_CHANGED", function()
    if frame:IsVisible() then
      view:Refresh()
    end
  end)
  ns.On("FG_UI_REFRESHED", function()
    if frame:IsVisible() then
      view:Refresh()
    end
  end)
  -- Distances change while walking: a slow refresh only while the content is visible.
  local acc = 0
  frame:SetScript("OnShow", function()
    view:Refresh()
    acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + elapsed
      if acc >= REFRESH_EVERY and view.selected == "list" then
        acc = 0
        ns.Safe("waypoint-list", view.Refresh, view)
      end
    end)
  end)
  frame:SetScript("OnHide", function()
    frame:SetScript("OnUpdate", nil)
  end)
  view:Select("list")
  view:Refresh()
  return view
end

-- Window ----------------------------------------------------------------------------------------------------

local win

local function frameDb()
  local frames = ns.db.frames
  if type(frames.waypointList) ~= "table" then
    frames.waypointList = {}
  end
  return frames.waypointList
end

local function place(f)
  local db = frameDb()
  f:SetSize(
    U.clamp(WL.finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W),
    U.clamp(WL.finite(db.h) and db.h or DEFAULT_H, MIN_H, MAX_H)
  )
  f:ClearAllPoints()
  local s = f:GetScale()
  if WL.finite(db.x) and WL.finite(db.y) then
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
  local db = frameDb()
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

local function createWindow()
  local f = CreateFrame("Frame", "FGWaypointList", UIParent)
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
  W.Fill(f, "bg", 0.95)
  local shell = ns.WindowShell.Attach(f, { title = "wp.title", titleHeight = HEAD_H, shadow = true })
  local bar = shell.titleBar
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  bar:SetScript(
    "OnDragStop",
    ns.Wrap("waypoint-list-move", function()
      f:StopMovingOrSizing()
      savePosition(f)
    end)
  )
  local close = W.Action(bar, { icon = "close", size = 18, tooltip = "wp.close" })
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("waypoint-list-close", function()
      f:Hide()
    end)
  )
  local title = shell.titleText
  title:ClearAllPoints()
  title:SetPoint("LEFT", 8, 0)
  title:SetPoint("RIGHT", close, "LEFT", -4, 0)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 8, -(HEAD_H + 6))
  content:SetPoint("BOTTOMRIGHT", -8, 16)
  f.view = WLUI.Build(content)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local gripTex = grip:CreateTexture(nil, "OVERLAY")
  gripTex:SetAllPoints()
  gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("waypoint-list-size", function()
      f:StopMovingOrSizing()
      saveSize(f)
      savePosition(f)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["wp.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)

  f:SetScript(
    "OnShow",
    ns.Wrap("waypoint-list-show", function()
      frameDb().shown = true
      ns.WindowShell.SetEsc(f, true)
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("waypoint-list-hide", function()
      frameDb().shown = false
      ns.WindowShell.SetEsc(f, false)
    end)
  )
  f:Hide()
  return f
end

function WLUI.IsShown()
  return win ~= nil and win:IsShown()
end

function WLUI.Window()
  return win
end

-- tab: "settings" opens the settings tab, anything else the list.
function WLUI.Open(tab)
  if not ns.db then
    return
  end
  if not win then
    win = createWindow()
  end
  win:SetScale(U.clamp(ns.db.settings.scale or 1, 0.5, 2))
  place(win)
  win:Show()
  win:Raise()
  win.view:Select(tab)
  win.view:Refresh()
end

function WLUI.Hide()
  if win then
    win:Hide()
  end
end

function WLUI.Toggle()
  if WLUI.IsShown() then
    WLUI.Hide()
  else
    WLUI.Open()
  end
end

ns.On("PLAYER_LOGOUT", function()
  if win and win:IsShown() then
    savePosition(win)
    saveSize(win)
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and ns.db.frames and frameDb().shown == true then
    WLUI.Open()
  end
end)

ns.RegisterPage({
  id = "waypoints",
  order = 21,
  group = "world",
  title = "page.waypoints",
  icon = ns.ICONS.waypoints,
  aliases = { "wegpunkte", "waypoints" },
  build = function(container)
    return WLUI.Build(container)
  end,
})
