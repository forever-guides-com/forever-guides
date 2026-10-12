-- The frame around the note editor, laid out like a desktop text editor in the
-- addon's own design: menu bar (File, Edit, View), the formatting toolbar centered
-- below it, the editing area, and a status bar (line and column, character count,
-- mode, zoom, encoding). One build for the floating note window and the Notes page.
--
--   local chrome = NC.Build(parent, noteEditor, {
--     getId = function() -> note id or nil,
--     onNew = function(),         -- File > New note and Ctrl+N
--     onClose = function(),       -- File > Close
--     onDeleted = function(id),   -- after File > Move to trash was confirmed
--     extras = { menu item... },  -- extra File items below "New note"
--     windowStyle = { openPanel(), autoHide() -> bool, toggleAutoHide(), saveDefault(), reset() },
--                                 -- optional: View menu entries for the window look
--     titleBox = frame,           -- optional first row above the menu bar
--   })
--   chrome.menu, chrome.toolbar, chrome.status    the three bars
--   chrome:Update()                               re-reads the status bar texts
--   chrome:ApplyStatusShown()                     shows or hides the status bar
--
-- The text zoom (50 to 300 percent) and the status bar switch are account-wide
-- settings (settings.noteZoom, settings.noteStatusBar), every chrome follows them.
local _, ns = ...
local W, L, N, RE = ns.W, ns.L, ns.Notes, ns.RichEditor

local NC = {}
ns.NoteChrome = NC

ns.AddLocale("enUS", {
  ["notes.menu.file"] = "File",
  ["notes.menu.edit"] = "Edit",
  ["notes.menu.view"] = "View",
  ["notes.menu.ctrl"] = "Ctrl",
  ["notes.menu.new"] = "New note",
  ["notes.menu.openWindow"] = "Open in own window",
  ["notes.menu.pin"] = "Sticky",
  ["notes.menu.share"] = "Share in chat...",
  ["notes.menu.export"] = "Export",
  ["notes.menu.exportString"] = "As exchange string...",
  ["notes.menu.exportText"] = "As plain text...",
  ["notes.menu.trash"] = "Move to trash",
  ["notes.menu.close"] = "Close",
  ["notes.menu.undo"] = "Undo",
  ["notes.menu.redo"] = "Redo",
  ["notes.menu.cut"] = "Cut",
  ["notes.menu.copy"] = "Copy",
  ["notes.menu.paste"] = "Paste",
  ["notes.menu.selectAll"] = "Select all",
  ["notes.menu.align"] = "Alignment",
  ["notes.menu.zoomIn"] = "Zoom in",
  ["notes.menu.zoomOut"] = "Zoom out",
  ["notes.menu.zoomReset"] = "Default zoom",
  ["notes.menu.statusBar"] = "Status bar",
  ["notes.menu.look"] = "Window appearance...",
  ["notes.menu.saveDefault"] = "Save as default for all note windows",
  ["notes.menu.resetDefault"] = "Reset to default",
  ["notes.menu.copied"] = "Copied in notes, Ctrl+C also fills the game clipboard.",
  ["notes.status.pos"] = "Ln %d, Col %d",
  ["notes.status.chars"] = "%d characters",
  ["notes.status.char1"] = "1 character",
  ["notes.status.charsSel"] = "%d characters (%d selected)",
  ["notes.status.formatted"] = "Formatted text",
  ["notes.status.code"] = "Code (markup)",
  ["notes.status.encoding"] = "UTF-8",
})

ns.AddLocale("deDE", {
  ["notes.menu.file"] = "Datei",
  ["notes.menu.edit"] = "Bearbeiten",
  ["notes.menu.view"] = "Ansicht",
  ["notes.menu.ctrl"] = "Strg",
  ["notes.menu.new"] = "Neue Notiz",
  ["notes.menu.openWindow"] = "In eigenem Fenster öffnen",
  ["notes.menu.pin"] = "Anheften",
  ["notes.menu.share"] = "Im Chat teilen...",
  ["notes.menu.export"] = "Exportieren",
  ["notes.menu.exportString"] = "Als Austausch-String...",
  ["notes.menu.exportText"] = "Als reiner Text...",
  ["notes.menu.trash"] = "In den Papierkorb",
  ["notes.menu.close"] = "Schließen",
  ["notes.menu.undo"] = "Rückgängig",
  ["notes.menu.redo"] = "Wiederholen",
  ["notes.menu.cut"] = "Ausschneiden",
  ["notes.menu.copy"] = "Kopieren",
  ["notes.menu.paste"] = "Einfügen",
  ["notes.menu.selectAll"] = "Alles auswählen",
  ["notes.menu.align"] = "Ausrichtung",
  ["notes.menu.zoomIn"] = "Vergrößern",
  ["notes.menu.zoomOut"] = "Verkleinern",
  ["notes.menu.zoomReset"] = "Standardzoom",
  ["notes.menu.statusBar"] = "Statusleiste",
  ["notes.menu.look"] = "Fensterdarstellung...",
  ["notes.menu.saveDefault"] = "Als Standard für alle Notizfenster speichern",
  ["notes.menu.resetDefault"] = "Auf Standard zurücksetzen",
  ["notes.menu.copied"] = "In Notizen kopiert, Strg+C auch in die Spiel-Zwischenablage.",
  ["notes.status.pos"] = "Ze %d, Sp %d",
  ["notes.status.chars"] = "%d Zeichen",
  ["notes.status.char1"] = "1 Zeichen",
  ["notes.status.charsSel"] = "%d Zeichen (%d markiert)",
  ["notes.status.formatted"] = "Formatierter Text",
  ["notes.status.code"] = "Code (Markup)",
  ["notes.status.encoding"] = "UTF-8",
})

local GAP = 4
local MENU_HEIGHT, STATUS_HEIGHT = 24, 22

local chromes = setmetatable({}, { __mode = "k" })

function NC.statusShown()
  local s = ns.db and ns.db.settings
  return not (s and s.noteStatusBar == false)
end

function NC.setStatusShown(shown)
  ns.Store.set("settings.noteStatusBar", shown and true or false)
end

-- "Ze 3, Sp 12", "1 Zeichen", "12 Zeichen (4 markiert)".
function NC.positionText(line, col)
  return string.format(L["notes.status.pos"], line, col)
end

function NC.countText(chars, selected)
  if selected and selected > 0 then
    return string.format(L["notes.status.charsSel"], chars, selected)
  end
  return chars == 1 and L["notes.status.char1"] or string.format(L["notes.status.chars"], chars)
end

-- Menus -------------------------------------------------------------------------------

local function shortcut(text)
  return function()
    return L["notes.menu.ctrl"] .. "+" .. text
  end
end

local function noteOf(host)
  local id = host.getId and host.getId()
  return id and N.get(id), id
end

local function exportString(note)
  local strings = N.exportStrings({ note })
  if strings then
    ns.Dialogs.Copy("notes.export.title", strings[1], "notes.export.hint")
  else
    ns.Notify(L["notes.msg.exportFail"], "error")
  end
end

local function fileMenu(host)
  local function hasNote()
    return noteOf(host) ~= nil
  end
  local items = {
    { key = "notes.menu.new", shortcut = shortcut("N"), onClick = host.onNew },
  }
  for _, extra in ipairs(host.extras or {}) do
    items[#items + 1] = extra
  end
  local rest = {
    {
      key = "notes.menu.pin",
      separator = true,
      enabled = hasNote,
      checked = function()
        local note = noteOf(host)
        return note ~= nil and note.window.sticky == true
      end,
      onClick = function()
        local note, id = noteOf(host)
        if note then
          ns.NoteWindow.SetSticky(id, not note.window.sticky)
        end
      end,
    },
    {
      key = "notes.menu.share",
      enabled = hasNote,
      onClick = function()
        local note = noteOf(host)
        if note then
          ns.Share.OpenNote(note)
        end
      end,
    },
    {
      key = "notes.menu.export",
      enabled = hasNote,
      items = {
        {
          key = "notes.menu.exportString",
          onClick = function()
            local note = noteOf(host)
            if note then
              exportString(note)
            end
          end,
        },
        {
          key = "notes.menu.exportText",
          onClick = function()
            local note = noteOf(host)
            if note then
              ns.Dialogs.Copy("notes.export.title", N.exportText({ note }), "notes.exportText.hint")
            end
          end,
        },
      },
    },
    {
      key = "notes.menu.trash",
      separator = true,
      enabled = hasNote,
      onClick = function()
        local note, id = noteOf(host)
        if note then
          ns.Dialogs.Confirm("notes.delete.title", "notes.delete.text", function()
            N.delete(id)
            if host.onDeleted then
              host.onDeleted(id)
            end
          end)
        end
      end,
    },
    {
      key = "notes.menu.close",
      separator = true,
      onClick = host.onClose,
    },
  }
  for _, item in ipairs(rest) do
    items[#items + 1] = item
  end
  return { key = "notes.menu.file", items = items }
end

-- One entry of Edit > Alignment: checked while the lines at the caret have this alignment.
local function alignItem(editor, value, key)
  return {
    key = "notes.tb.align" .. value:sub(1, 1):upper() .. value:sub(2),
    shortcut = shortcut(key),
    checked = function()
      return editor:AlignState() == value
    end,
    onClick = function()
      editor:Align(value)
    end,
  }
end

local function editMenu(editor)
  local function rich()
    return editor.mode == "normal" and editor.rich ~= nil
  end
  return {
    key = "notes.menu.edit",
    items = {
      {
        key = "notes.menu.undo",
        shortcut = shortcut("Z"),
        enabled = function()
          return editor:CanUndo(false)
        end,
        onClick = function()
          editor:Undo(false)
        end,
      },
      {
        key = "notes.menu.redo",
        shortcut = shortcut("Y"),
        enabled = function()
          return editor:CanUndo(true)
        end,
        onClick = function()
          editor:Undo(true)
        end,
      },
      {
        key = "notes.menu.cut",
        separator = true,
        shortcut = shortcut("X"),
        enabled = function()
          return editor:HasSelection()
        end,
        onClick = function()
          editor:Copy(true)
        end,
      },
      {
        key = "notes.menu.copy",
        shortcut = shortcut("C"),
        enabled = function()
          return editor:HasSelection()
        end,
        onClick = function()
          editor:Copy(false)
        end,
      },
      {
        key = "notes.menu.paste",
        shortcut = shortcut("V"),
        enabled = function()
          return editor:CanPaste()
        end,
        onClick = function()
          editor:Paste()
        end,
      },
      {
        key = "notes.rich.menuCopy",
        enabled = rich,
        onClick = function()
          editor.rich:OpenCopyDialog()
        end,
      },
      {
        key = "notes.menu.selectAll",
        separator = true,
        shortcut = shortcut("A"),
        onClick = function()
          editor:SelectAll()
        end,
      },
      {
        key = "notes.menu.align",
        separator = true,
        items = {
          alignItem(editor, "left", "L"),
          alignItem(editor, "center", "E"),
          alignItem(editor, "right", "R"),
        },
      },
    },
  }
end

local function viewMenu(editor, host)
  local function zoom(name)
    return function()
      editor:Command(name)
      editor:Focus()
    end
  end
  local items = {
    {
      key = "notes.menu.zoomIn",
      shortcut = shortcut("+"),
      enabled = function()
        return RE.zoom() < RE.ZOOM_MAX
      end,
      onClick = zoom("zoomIn"),
    },
    {
      key = "notes.menu.zoomOut",
      shortcut = shortcut("-"),
      enabled = function()
        return RE.zoom() > RE.ZOOM_MIN
      end,
      onClick = zoom("zoomOut"),
    },
    {
      key = "notes.menu.zoomReset",
      shortcut = shortcut("0"),
      enabled = function()
        return RE.zoom() ~= RE.ZOOM_DEFAULT
      end,
      onClick = zoom("zoomReset"),
    },
    {
      key = "notes.tb.mode",
      separator = true,
      enabled = function()
        return editor.rich ~= nil
      end,
      checked = function()
        return editor.mode == "code"
      end,
      onClick = function()
        editor:Toggle()
      end,
    },
    {
      key = "notes.menu.statusBar",
      checked = NC.statusShown,
      onClick = function()
        NC.setStatusShown(not NC.statusShown())
      end,
    },
  }
  -- Only a floating window has a look of its own (host.windowStyle, see UI/NoteWindow.lua).
  local ws = host.windowStyle
  if ws then
    items[#items + 1] = { key = "notes.menu.look", separator = true, onClick = ws.openPanel }
    items[#items + 1] = { key = "wstyle.autoHide", checked = ws.autoHide, onClick = ws.toggleAutoHide }
    items[#items + 1] = { key = "notes.menu.saveDefault", separator = true, onClick = ws.saveDefault }
    items[#items + 1] = { key = "notes.menu.resetDefault", onClick = ws.reset }
  end
  return { key = "notes.menu.view", items = items }
end

-- Build -------------------------------------------------------------------------------

function NC.Build(parent, editor, host)
  local chrome = { parent = parent, editor = editor, host = host, titleBox = host.titleBox, last = {} }
  chromes[chrome] = true

  chrome.menu = W.MenuBar(
    parent,
    { fileMenu(host), editMenu(editor), viewMenu(editor, host) },
    { height = MENU_HEIGHT }
  )
  chrome.toolbar = editor.toolbar
  W.Fill(chrome.toolbar, "surface", 1)

  chrome.status = W.StatusBar(parent, {
    height = STATUS_HEIGHT,
    segments = {
      { id = "pos", text = "", fit = true, align = "LEFT" },
      { id = "count", text = "", fit = true, align = "LEFT", priority = 2 },
      { id = "mode", text = "", fit = true, align = "LEFT", priority = 4 },
      { id = "gap", text = "", minWidth = 4, spacer = true },
      {
        id = "zoom",
        type = "slider",
        min = RE.ZOOM_MIN,
        max = RE.ZOOM_MAX,
        step = RE.ZOOM_STEP,
        value = RE.zoom(),
        width = 190,
        priority = 3,
        onChange = function(v)
          RE.setZoom(v)
        end,
      },
      { id = "enc", key = "notes.status.encoding", fit = true, align = "LEFT", priority = 5 },
    },
  })

  -- Vertical order: optional title row, menu bar, toolbar, text area, status bar.
  function chrome:Layout()
    local last = self.titleBox
    if last then
      last:ClearAllPoints()
      last:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
      last:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    self.menu:ClearAllPoints()
    self.menu:SetPoint("TOPLEFT", last or parent, last and "BOTTOMLEFT" or "TOPLEFT", 0, last and -GAP or 0)
    self.menu:SetPoint("TOPRIGHT", last or parent, last and "BOTTOMRIGHT" or "TOPRIGHT", 0, last and -GAP or 0)
    self.toolbar:ClearAllPoints()
    self.toolbar:SetPoint("TOPLEFT", self.menu, "BOTTOMLEFT", 0, -2)
    self.toolbar:SetPoint("TOPRIGHT", self.menu, "BOTTOMRIGHT", 0, -2)
    self.status:ClearAllPoints()
    self.status:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    self.status:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local body = editor.body
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", self.toolbar, "BOTTOMLEFT", 0, -GAP)
    if NC.statusShown() then
      body:SetPoint("BOTTOMRIGHT", self.status, "TOPRIGHT", 0, GAP)
    else
      body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
  end

  function chrome:ApplyStatusShown()
    self.status:SetShown(NC.statusShown())
    self:Layout()
  end

  -- Height of the chrome around a text area of `bodyHeight` (base pixels).
  function chrome.heightFor(bodyHeight)
    local scaled = ns.Desktop.scaled
    return scaled(MENU_HEIGHT) + 2 + scaled(28) + GAP + bodyHeight + GAP + scaled(STATUS_HEIGHT)
  end

  local function set(id, text)
    if chrome.last[id] ~= text then
      chrome.last[id] = text
      chrome.status:SetSegment(id, text)
    end
  end

  function chrome:Update()
    local st = editor:Stats()
    set("pos", NC.positionText(st.line, st.col))
    set("count", NC.countText(st.chars, st.selected))
    set("mode", L[st.mode == "code" and "notes.status.code" or "notes.status.formatted"])
    local zoom = RE.zoom()
    if chrome.last.zoom ~= zoom then
      chrome.last.zoom = zoom
      chrome.status:SetSegment("zoom", zoom)
    end
  end

  editor.chrome = chrome
  editor.onStatus = function()
    chrome:Update()
  end
  chrome:Layout()
  chrome:ApplyStatusShown()
  chrome:Update()
  return chrome
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.noteStatusBar" then
    for c in pairs(chromes) do
      c:ApplyStatusShown()
    end
  end
end)

-- A language change rewrites the texts the status bar computed.
ns.On("FG_UI_REFRESHED", function()
  for c in pairs(chromes) do
    c.last = {}
    c:Update()
  end
end)
