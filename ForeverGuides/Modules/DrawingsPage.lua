-- Drawings page: the list of your drawings on the left, a read-only preview
-- and the actions for the selected one on the right. The editor opens in its
-- own window (Modules\DrawingEditor.lua). Drawings stay on this computer and
-- only leave the game as exchange strings or chat links.
local _, ns = ...
local W, L, U, K, D, DR, V, DE =
  ns.W, ns.L, ns.U, ns.PageKit, ns.DrawingLogic, ns.Drawings, ns.DrawingView, ns.DrawingEditor

local P = {}
ns.DrawingsPage = P

local floor, max = math.floor, math.max
local DOUBLE_CLICK = 0.4

ns.AddLocale("enUS", {
  ["page.drawings"] = "Drawings",
  ["draw.intro"] = "Paint-like editor, stored locally, shareable in chat.",
  ["draw.new"] = "New drawing",
  ["draw.import"] = "Import...",
  ["draw.backup"] = "Backup (all)",
  ["draw.backupTip"] = "Copies all drawings as strings.\nSettings save only at logout.",
  ["draw.empty"] = 'Empty: "New drawing" or /fg draw.',
  ["draw.pick"] = "Pick a drawing in the list to see its preview.",
  ["draw.usage"] = "%d of %d drawings.",
  ["draw.usage.warn"] = "The limit is close.",
  ["draw.order.hint"] = "Drag or use arrows to sort ({mod:listToEdge}: top/bottom).\nDouble-click or Enter opens the editor.",
  ["draw.row.up"] = "Move up ({mod:listToEdge}: to the top)",
  ["draw.row.down"] = "Move down ({mod:listToEdge}: to the bottom)",
  ["draw.row.delete"] = "Delete",
  ["draw.row.sub"] = "%d x %d cells, %s",
  ["draw.row.broken"] = "unreadable",
  ["draw.page.open"] = "Open in new window",
  ["draw.page.openTip"] = "Opens the editor, resizable.",
  ["draw.page.window"] = "Open as window",
  ["draw.page.windowTip"] = "Small window over the game.\nPin it, make it transparent, auto-hide the title bar.",
  ["draw.page.rename"] = "Rename",
  ["draw.page.duplicate"] = "Duplicate",
  ["draw.page.delete"] = "Delete",
  ["draw.page.share"] = "Share",
  ["draw.page.export"] = "Export string",
  ["draw.info"] = "%d x %d cells, stored %s of %s, changed %s",
  ["draw.info.broken"] = "Unreadable. You can still export or delete it.",
  ["draw.dlg.newTitle"] = "New drawing",
  ["draw.dlg.renameTitle"] = "Rename drawing",
  ["draw.dlg.name"] = "Name",
  ["draw.dlg.size"] = "Size (you can change it later in the editor)",
  ["draw.dlg.preset"] = "%d x %d cells",
  ["draw.dlg.create"] = "Create",
  ["draw.dlg.rename"] = "Rename",
  ["draw.delete.title"] = "Delete drawing?",
  ["draw.delete.text"] = "Removed for good, export first to keep a copy.",
  ["draw.export.title"] = "Export drawing",
  ["draw.export.hint"] = "Copy with Ctrl+C, Import... reads it back.",
  ["draw.backup.title"] = "Backup of all drawings",
  ["draw.backup.hint"] = "To restore, paste all blocks into Import...",
  ["draw.msg.limit"] = "Drawing limit %d reached: delete one first.",
  ["draw.msg.createFailed"] = "The drawing could not be created.",
  ["draw.msg.exportFail"] = "Export failed.",
  ["draw.msg.noDrawings"] = "There are no drawings to back up.",
  ["draw.msg.imported"] = "%d drawing(s) imported, %d skipped (limit).",
  ["draw.import.title"] = "Import drawings",
  ["draw.import.hint"] = "Paste strings, one per block.\nNothing is added until you press Import.",
  ["draw.import.paste"] = "Paste here",
  ["draw.import.preview"] = "Preview",
  ["draw.import.do"] = "Import",
  ["draw.import.empty"] = "Waiting for input.",
  ["draw.import.ok"] = "%d drawing(s) found, Import adds them.",
  ["draw.import.item"] = "%d. %s (%d x %d cells)",
  ["draw.import.more"] = "... and %d more",
  ["draw.import.err.empty"] = "Nothing to import.",
  ["draw.import.err.too-large"] = "The input is too large.",
  ["draw.import.err.too-many"] = "Too many strings at once (at most 8).",
  ["draw.import.err.decode"] = "Not a valid string. Copy it again completely.",
  ["draw.import.err.json"] = "The data inside the string is damaged.",
  ["draw.import.err.shape"] = "The data has an unexpected shape.",
  ["draw.import.err.type"] = "This string is not a drawings export.",
  ["draw.import.err.version"] = "This string comes from a newer version of the addon.",
  ["draw.import.err.items"] = "Drawings in this string are invalid or too many.",
  ["draw.import.err.drawing"] = "A drawing in this string is damaged.",
  ["draw.import.err.at"] = " (entry %d)",
})

ns.AddLocale("deDE", {
  ["page.drawings"] = "Zeichnungen",
  ["draw.intro"] = "Editor wie Paint, Zeichnungen lokal, im Chat teilbar.",
  ["draw.new"] = "Neue Zeichnung",
  ["draw.import"] = "Import...",
  ["draw.backup"] = "Sicherung (alle)",
  ["draw.backupTip"] = "Kopiert alle Zeichnungen als Strings.\nEinstellungen speichern erst beim Ausloggen.",
  ["draw.empty"] = 'Noch leer: "Neue Zeichnung" oder /fg draw.',
  ["draw.pick"] = "Wähle eine Zeichnung in der Liste, um die Vorschau zu sehen.",
  ["draw.usage"] = "%d von %d Zeichnungen.",
  ["draw.usage.warn"] = "Das Limit ist bald erreicht.",
  ["draw.order.hint"] = "Ziehen oder Pfeile sortieren ({mod:listToEdge}: ganz oben/unten).\nDoppelklick oder Enter öffnet den Editor.",
  ["draw.row.up"] = "Nach oben ({mod:listToEdge}: ganz nach oben)",
  ["draw.row.down"] = "Nach unten ({mod:listToEdge}: ganz nach unten)",
  ["draw.row.delete"] = "Löschen",
  ["draw.row.sub"] = "%d x %d Zellen, %s",
  ["draw.row.broken"] = "nicht lesbar",
  ["draw.page.open"] = "In neuem Fenster öffnen",
  ["draw.page.openTip"] = "Öffnet den Editor, Größe änderbar.",
  ["draw.page.window"] = "Als Fenster öffnen",
  ["draw.page.windowTip"] = "Kleines Fenster über dem Spiel.\nAnheften, durchsichtig, Kopfzeile automatisch ausblenden.",
  ["draw.page.rename"] = "Umbenennen",
  ["draw.page.duplicate"] = "Duplizieren",
  ["draw.page.delete"] = "Löschen",
  ["draw.page.share"] = "Teilen",
  ["draw.page.export"] = "Export-String",
  ["draw.info"] = "%d x %d Zellen, gespeichert %s von %s, geändert %s",
  ["draw.info.broken"] = "Nicht lesbar. Exportieren oder löschen möglich.",
  ["draw.dlg.newTitle"] = "Neue Zeichnung",
  ["draw.dlg.renameTitle"] = "Zeichnung umbenennen",
  ["draw.dlg.name"] = "Name",
  ["draw.dlg.size"] = "Größe (im Editor jederzeit änderbar)",
  ["draw.dlg.preset"] = "%d x %d Zellen",
  ["draw.dlg.create"] = "Anlegen",
  ["draw.dlg.rename"] = "Umbenennen",
  ["draw.delete.title"] = "Zeichnung löschen?",
  ["draw.delete.text"] = "Wird unwiderruflich entfernt, vorher exportieren.",
  ["draw.export.title"] = "Zeichnung exportieren",
  ["draw.export.hint"] = "Mit Strg+C kopieren, Import... liest ihn wieder ein.",
  ["draw.backup.title"] = "Sicherung aller Zeichnungen",
  ["draw.backup.hint"] = "Zum Wiederherstellen alle Blöcke in Import... einfügen.",
  ["draw.msg.limit"] = "Zeichnungs-Limit %d erreicht: erst eine löschen.",
  ["draw.msg.createFailed"] = "Die Zeichnung konnte nicht angelegt werden.",
  ["draw.msg.exportFail"] = "Export fehlgeschlagen.",
  ["draw.msg.noDrawings"] = "Es gibt keine Zeichnungen zum Sichern.",
  ["draw.msg.imported"] = "%d Zeichnung(en) importiert, %d übersprungen (Limit).",
  ["draw.import.title"] = "Zeichnungen importieren",
  ["draw.import.hint"] = "Strings einfügen, einer je Block.\nErst Importieren fügt etwas hinzu.",
  ["draw.import.paste"] = "Hier einfügen",
  ["draw.import.preview"] = "Vorschau",
  ["draw.import.do"] = "Importieren",
  ["draw.import.empty"] = "Warte auf Eingabe.",
  ["draw.import.ok"] = "%d Zeichnung(en) gefunden, Importieren fügt sie hinzu.",
  ["draw.import.item"] = "%d. %s (%d x %d Zellen)",
  ["draw.import.more"] = "... und %d weitere",
  ["draw.import.err.empty"] = "Nichts zu importieren.",
  ["draw.import.err.too-large"] = "Die Eingabe ist zu groß.",
  ["draw.import.err.too-many"] = "Zu viele Strings auf einmal (höchstens 8).",
  ["draw.import.err.decode"] = "Kein gültiger String. Komplett neu kopieren.",
  ["draw.import.err.json"] = "Die Daten im String sind beschädigt.",
  ["draw.import.err.shape"] = "Die Daten haben eine unerwartete Form.",
  ["draw.import.err.type"] = "Dieser String ist kein Zeichnungs-Export.",
  ["draw.import.err.version"] = "Dieser String stammt aus einer neueren Addon-Version.",
  ["draw.import.err.items"] = "Zeichnungen im String ungültig oder zu viele.",
  ["draw.import.err.drawing"] = "Eine Zeichnung in diesem String ist beschädigt.",
  ["draw.import.err.at"] = " (Eintrag %d)",
})

-- Helpers ------------------------------------------------------------------------------

local function fmt(key, ...)
  local ok, text = pcall(string.format, L[key], ...)
  return ok and text or L[key]
end

local function nameOf(item)
  return item.name ~= "" and item.name or L["draw.untitled"]
end

local function kb(bytes)
  return string.format("%.1f KB", bytes / 1024)
end

local function dateText(ts)
  local d = rawget(_G, "date")
  return d and d("%Y-%m-%d", ts or 0) or tostring(ts)
end

local function now()
  return GetTime and GetTime() or os.clock()
end

-- Moves drawing `id` to the place before (or, with `after`, behind) `anchorId`
-- using the stepwise DR.move, which is the storage's only ordering call.
local function reorder(id, anchorId, after)
  local from, to
  for i, item in ipairs(DR.list()) do
    from = item.id == id and i or from
    to = item.id == anchorId and i or to
  end
  if not (from and to) or from == to then
    return
  end
  local dest
  if from < to then
    dest = after and to or to - 1
  else
    dest = after and to + 1 or to
  end
  local dir = dest > from and 1 or -1
  for _ = 1, math.abs(dest - from) do
    DR.move(id, dir)
  end
end

local function moveToEdge(id, dir)
  for _ = 1, DR.MAX_ITEMS do
    if not DR.move(id, dir) then
      return
    end
  end
end

-- New / rename dialog ----------------------------------------------------------------------

local nameDlg

-- mode "new": name and size, "rename": only the name.
local function showNameDialog(mode, item, onDone)
  if not nameDlg then
    local d = ns.Dialogs.Create("ForeverGuidesDrawingName", 420, 250)
    nameDlg = d
    d.nameLabel = W.Text(d, { key = "draw.dlg.name", role = "ui" })
    d.nameLabel:SetPoint("TOPLEFT", 16, -48)
    d.name = W.EditBox(d, {
      placeholder = "draw.namePlaceholder",
      onEnter = function()
        d.go:Click()
      end,
    })
    d.name:SetPoint("TOPLEFT", 16, -68)
    d.name:SetPoint("RIGHT", -16, 0)
    d.name.edit:SetMaxLetters(DR.MAX_NAME)
    d.preset = 1
    d.options = {}
    for i, p in ipairs(D.PRESETS) do
      d.options[i] = { value = i, text = fmt("draw.dlg.preset", p.w, p.h) }
    end
    d.size = W.Dropdown(d, {
      key = "draw.dlg.size",
      width = 300,
      options = d.options,
      get = function()
        return d.preset
      end,
      set = function(v)
        d.preset = v
      end,
    })
    d.size:SetPoint("TOPLEFT", 16, -108)
    d.go = W.Button(d, { key = "draw.dlg.create", variant = "primary", width = 130 })
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
  end
  local d = nameDlg
  W.SetText(d.title, mode == "new" and "draw.dlg.newTitle" or "draw.dlg.renameTitle")
  W.SetText(d.go.label, mode == "new" and "draw.dlg.create" or "draw.dlg.rename")
  d.size:SetShown(mode == "new")
  d.preset = 1
  d.size.Refresh()
  d.name.edit:SetText(item and item.name or "")
  d.go:SetScript(
    "OnClick",
    ns.Wrap("draw-name-dialog", function()
      local name = d.name.edit:GetText()
      d:Hide()
      onDone(name, D.PRESETS[d.preset])
    end)
  )
  d:Show()
  d.name.edit:SetFocus()
end

-- Import dialog -----------------------------------------------------------------------------

local importDlg

local function importPreview(items)
  local lines = {}
  for i, item in ipairs(items) do
    if i > 12 then
      lines[#lines + 1] = fmt("draw.import.more", #items - 12)
      break
    end
    local name = item.name ~= "" and item.name or L["draw.untitled"]
    lines[#lines + 1] = fmt("draw.import.item", i, name, item.drawing.w, item.drawing.h)
  end
  return fmt("draw.import.ok", #items) .. "\n\n" .. table.concat(lines, "\n")
end

local function showImport(onDone)
  if not importDlg then
    local d = ns.Dialogs.Create("ForeverGuidesDrawingImport", 560, 480)
    importDlg = d
    W.SetText(d.title, "draw.import.title")
    d.hint = W.Text(d, { key = "draw.import.hint", role = "ui", color = "textSecondary", wrap = true })
    d.hint:SetPoint("TOPLEFT", 16, -44)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.pasteLabel = W.Text(d, { key = "draw.import.paste", role = "ui" })
    d.pasteLabel:SetPoint("TOPLEFT", 16, -96)
    d.paste = W.TextArea(d, {
      height = 130,
      onChange = function(text)
        d.refresh(text)
      end,
    })
    d.paste:SetPoint("TOPLEFT", 16, -116)
    d.paste:SetPoint("RIGHT", -16, 0)
    d.paste.edit:SetMaxLetters(0)
    d.previewLabel = W.Text(d, { key = "draw.import.preview", role = "ui" })
    d.previewLabel:SetPoint("TOPLEFT", 16, -256)
    d.preview = W.TextArea(d, { height = 130, readOnly = true })
    d.preview:SetPoint("TOPLEFT", 16, -276)
    d.preview:SetPoint("RIGHT", -16, 0)
    d.go = W.Action(
      d,
      { label = "act.import", icon = "import", tooltip = "draw.import.do", variant = "primary", width = 130 }
    )
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
    d.status = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
    d.status:SetPoint("BOTTOMLEFT", 16, 52)
    d.status:SetPoint("RIGHT", -16, 0)
    function d.refresh(text)
      local parsed, why, index = DR.parseImport(text)
      d.parsed = parsed
      if parsed then
        d.preview:SetValue(importPreview(parsed.items))
        W.SetText(d.status, nil, "")
        d.go:Enable()
      else
        d.preview:SetValue("")
        local key = "draw.import.err." .. tostring(why)
        local msg = L[key] ~= key and L[key] or L["draw.import.err.decode"]
        if index and index > 0 then
          msg = msg .. fmt("draw.import.err.at", index)
        end
        W.SetText(d.status, nil, (text and U.trim(text) ~= "") and msg or L["draw.import.empty"])
        d.go:Disable()
      end
    end
  end
  importDlg.go:SetScript(
    "OnClick",
    ns.Wrap("draw-import", function()
      local parsed = importDlg.parsed
      if parsed then
        local added, skipped = DR.importItems(parsed.items)
        ns.Notify(fmt("draw.msg.imported", added, skipped), "success")
        importDlg:Hide()
        if onDone then
          onDone()
        end
      end
    end)
  )
  importDlg.paste:SetValue("")
  importDlg.refresh("")
  importDlg:Show()
  importDlg.paste.edit:SetFocus()
end

-- Page ---------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { sel = nil }
  P.state, P.view = state, view
  local refresh
  local last = { id = nil, at = 0 }
  local ui = {}
  P.ui = ui

  ns.AddParagraph(view, "draw.intro")

  local bar = CreateFrame("Frame", nil, view.content)
  local newBtn = W.Action(bar, {
    label = "act.new",
    icon = "plus",
    tooltip = "draw.new",
    height = 28,
    variant = "primary",
    width = 150,
    onClick = function()
      showNameDialog("new", nil, function(name, preset)
        local item, why = DR.create(name, preset.w, preset.h)
        if not item then
          ns.Notify(
            why == "limit" and fmt("draw.msg.limit", DR.MAX_ITEMS) or L["draw.msg.createFailed"],
            why == "limit" and "warning" or "error"
          )
          return
        end
        state.sel = item.id
        refresh()
        DE.Open(item.id)
      end)
    end,
  })
  newBtn:SetPoint("TOPLEFT")
  local importBtn = W.Action(bar, {
    label = "act.import",
    icon = "import",
    tooltip = "draw.import",
    height = 28,
    width = 120,
    onClick = function()
      showImport()
    end,
  })
  importBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
  local backupBtn = W.Action(bar, {
    label = "act.backup",
    icon = "save",
    height = 28,
    width = 150,
    tooltip = "draw.backup",
    tooltipText = "draw.backupTip",
    onClick = function()
      local strings, why = DR.exportBackup()
      if not strings then
        ns.Notify(
          why == "empty" and L["draw.msg.noDrawings"] or L["draw.msg.exportFail"],
          why == "empty" and "info" or "error"
        )
        return
      end
      ns.Dialogs.Copy("draw.backup.title", table.concat(strings, "\n\n"), "draw.backup.hint")
    end,
  })
  backupBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
  s:Add(bar, { height = 28 })
  ui.newBtn, ui.importBtn, ui.backupBtn = newBtn, importBtn, backupBtn

  local usage = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted" })
  local emptyText = ns.AddParagraph(view, "draw.empty", { role = "ui", color = "textMuted" })
  ui.usage, ui.emptyText = usage, emptyText

  -- Two panes in one row: list left, preview and actions right.
  local split = CreateFrame("Frame", nil, view.content)
  local leftPane = CreateFrame("Frame", nil, split)
  local rightPane = CreateFrame("Frame", nil, split)
  s:Add(split, {})
  ui.split = split

  local function selectItem(id)
    state.sel = id
    DR.setLastOpened(id)
    refresh()
  end

  local function open(item)
    DE.Open(item.id)
  end

  -- Click selects; a second click on the same row within DOUBLE_CLICK seconds
  -- and Enter on the keyboard-focused row open the editor.
  local function activate(item)
    local t = now()
    local double = last.id == item.id and t - last.at <= DOUBLE_CLICK
    local focused = ns.Focus and ns.Focus.current
    local byKeyboard = focused ~= nil and focused.item == item
    last.id, last.at = item.id, t
    if state.sel ~= item.id then
      selectItem(item.id)
    end
    if double or byKeyboard then
      open(item)
    end
  end

  local function move(item, dir)
    if ns.Keys.Matches("listToEdge") then
      moveToEdge(item.id, dir)
    else
      DR.move(item.id, dir)
    end
  end

  local function confirmDelete(item)
    ns.Dialogs.Confirm("draw.delete.title", "draw.delete.text", function()
      DR.delete(item.id)
      if state.sel == item.id then
        state.sel = nil
      end
    end)
  end

  local list = K.NewList(leftPane, {
    rowHeight = 42,
    canReorder = function()
      return true
    end,
    onReorder = function(item, anchor, after)
      reorder(item.id, anchor.id, after)
    end,
    bind = function(item)
      return {
        title = nameOf(item),
        sub = item.w > 0 and fmt("draw.row.sub", item.w, item.h, kb(#item.data)) or L["draw.row.broken"],
        selected = item.id == state.sel,
        actions = {
          {
            icon = "trash",
            tooltip = L["draw.row.delete"],
            onClick = function()
              confirmDelete(item)
            end,
          },
          {
            icon = "chevron-down",
            tooltip = L["draw.row.down"],
            onClick = function()
              move(item, 1)
            end,
          },
          {
            icon = "chevron-up",
            tooltip = L["draw.row.up"],
            onClick = function()
              move(item, -1)
            end,
          },
        },
      }
    end,
    onClick = activate,
  })
  ui.list = list
  local orderHint = W.Text(leftPane, { key = "draw.order.hint", role = "micro", color = "textMuted", wrap = true })

  -- Right pane.
  local heading = W.Text(rightPane, { role = "h2", family = "heading", color = "accent2", wrap = true })
  local box = CreateFrame("Frame", nil, rightPane)
  W.Fill(box, "surface", 1)
  W.Border(box, "white", 0.3)
  local preview = V.New(box, { scale = 2, kind = "page" })
  preview.frame:SetPoint("CENTER")
  ui.preview, ui.box = preview, box
  local sizeLine = W.Text(rightPane, { role = "micro", color = "textSecondary", wrap = true })
  local info = W.Text(rightPane, { role = "micro", color = "textSecondary", wrap = true })
  local broken = W.Text(rightPane, { key = "draw.info.broken", role = "ui", color = "warning", wrap = true })
  local actions = CreateFrame("Frame", nil, rightPane)
  local pick = W.Text(rightPane, { key = "draw.pick", role = "ui", color = "textMuted", wrap = true })
  ui.heading, ui.info, ui.broken, ui.pick, ui.sizeLine = heading, info, broken, pick, sizeLine

  -- Packed size and chat verdict of the selected drawing; the stored string is
  -- the packed size, so only the verdict needs work, cached per drawing state.
  local verdict = {}
  local function showSize(item)
    local key = item.id .. "\0" .. #item.data .. "\0" .. item.name .. "\0" .. ns.GetActiveLocale()
    if verdict.key ~= key then
      local DL = ns.DrawingLink
      local line, color = DL.ShareLine(DL.ShareInfo(#item.data, item.name))
      verdict.key, verdict.text, verdict.color = key, DL.SizeText(#item.data) .. ", " .. line, color
    end
    sizeLine:SetText(verdict.text)
    W.SetColor(sizeLine, verdict.color)
  end

  local function sel()
    return state.sel and DR.get(state.sel)
  end
  local buttons = {}
  local function actionButton(id, key, label, icon, width, onClick, extra)
    local opts = { label = label, icon = icon, tooltip = key, width = width, height = 28, onClick = onClick }
    for k, v in pairs(extra or {}) do
      opts[k] = v
    end
    local b = W.Action(actions, opts)
    buttons[#buttons + 1] = b
    ui[id] = b
    return b
  end
  actionButton("openBtn", "draw.page.open", "act.edit", "pencil", 200, function()
    local item = sel()
    if item then
      open(item)
    end
  end, { variant = "primary", tooltip = "draw.page.open", tooltipText = "draw.page.openTip" })
  actionButton("windowBtn", "draw.page.window", "act.open", "open", 170, function()
    local item = sel()
    if item then
      ns.DrawingWindow.Open(item.id)
    end
  end, { tooltip = "draw.page.window", tooltipText = "draw.page.windowTip" })
  actionButton("renameBtn", "draw.page.rename", "act.rename", "tag", 110, function()
    local item = sel()
    if item then
      showNameDialog("rename", item, function(name)
        DR.rename(item.id, name)
      end)
    end
  end)
  actionButton("dupBtn", "draw.page.duplicate", "act.duplicate", "copy", 110, function()
    local item = sel()
    if item then
      local copy, why = DR.duplicate(item.id)
      if copy then
        state.sel = copy.id
        refresh()
      elseif why == "limit" then
        ns.Notify(fmt("draw.msg.limit", DR.MAX_ITEMS), "warning")
      end
    end
  end)
  actionButton("deleteBtn", "draw.page.delete", "act.delete", "trash", 100, function()
    local item = sel()
    if item then
      confirmDelete(item)
    end
  end)
  actionButton("shareBtn", "draw.page.share", "act.share", "share", 100, function()
    local item = sel()
    if item then
      ns.Share.OpenDrawing(item.id)
    end
  end)
  actionButton("exportBtn", "draw.page.export", "act.export", "export", 130, function()
    local item = sel()
    local text = item and DR.exportString(item.id)
    if text then
      ns.Dialogs.Copy("draw.export.title", text, "draw.export.hint")
    else
      ns.Notify(L["draw.msg.exportFail"], "error")
    end
  end)
  function actions:fgGridLayout(width)
    local x, y, rowH, gap = 0, 0, 28, 6
    for _, b in ipairs(buttons) do
      local w = b:GetWidth()
      if x > 0 and x + w > width then
        x, y = 0, y + rowH + gap
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", actions, "TOPLEFT", x, -y)
      x = x + w + gap
    end
    actions:SetHeight(y + rowH)
    return y + rowH
  end

  -- Preview scale follows the box, the picture is only re-read from storage
  -- when the stored data of the selected drawing changed.
  local function fitPreview()
    local d = preview.drawing
    if d then
      preview:SetScale(V.FitScale(d.w, d.h, max(1, box:GetWidth() - 16), max(1, box:GetHeight() - 16)))
    end
  end

  local loaded = { key = nil }
  local function showPreview(item)
    local key = item.id .. "\0" .. item.data
    if loaded.key ~= key then
      loaded.key = key
      preview:SetDrawing(DR.load(item.id))
    end
    broken:SetShown(preview.drawing == nil)
    box:SetShown(preview.drawing ~= nil)
    fitPreview()
  end

  function split:fgGridLayout(width)
    local gap = 16
    local leftW = U.clamp(floor(width * 0.38), 220, 360)
    local rightW = max(260, width - gap - leftW)
    leftPane:ClearAllPoints()
    leftPane:SetPoint("TOPLEFT")
    leftPane:SetWidth(leftW)
    rightPane:ClearAllPoints()
    rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", gap, 0)
    rightPane:SetWidth(rightW)

    local listH = K.scaledHeight(42) * 7
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, 0)
    list:SetSize(leftW, listH)
    orderHint:ClearAllPoints()
    orderHint:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -(listH + 6))
    orderHint:SetWidth(leftW)
    local leftH = listH + 6 + orderHint:GetStringHeight()

    local y = 0
    local function place(item, h)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -y)
      item:SetWidth(rightW)
      if h then
        item:SetHeight(h)
      end
      y = y + (h or item:GetStringHeight()) + 8
    end
    if pick:IsShown() then
      place(pick)
    end
    if heading:IsShown() then
      place(heading)
    end
    if box:IsShown() then
      place(box, U.clamp(floor(rightW * 0.7), 180, 340))
    end
    if sizeLine:IsShown() then
      place(sizeLine)
    end
    if broken:IsShown() then
      place(broken)
    end
    if info:IsShown() then
      place(info)
    end
    if actions:IsShown() then
      actions:ClearAllPoints()
      actions:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 0, -y)
      actions:SetWidth(rightW)
      y = y + actions:fgGridLayout(rightW) + 8
    end
    fitPreview()
    local h = max(leftH, y, 1)
    leftPane:SetHeight(h)
    rightPane:SetHeight(h)
    self:SetHeight(h)
    return h
  end

  function refresh()
    local items = DR.list()
    P.listed = items
    local item = sel()
    if not item then
      state.sel = nil
    end
    local total = #items
    W.SetText(
      usage,
      nil,
      fmt("draw.usage", total, DR.MAX_ITEMS) .. (total >= DR.MAX_ITEMS - 5 and (" " .. L["draw.usage.warn"]) or "")
    )
    emptyText:SetShown(total == 0)
    split:SetShown(total > 0)
    list:SetData(items)
    orderHint:SetShown(total > 1)
    pick:SetShown(item == nil and total > 0)
    for _, w in ipairs({ heading, info, sizeLine, actions }) do
      w:SetShown(item ~= nil)
    end
    if item then
      heading:SetText(nameOf(item))
      info:SetText(fmt("draw.info", item.w, item.h, kb(#item.data), kb(DR.MAX_BYTES), dateText(item.updated)))
      showSize(item)
      showPreview(item)
    else
      box:SetShown(false)
      broken:SetShown(false)
    end
    view:Layout()
  end

  function view:Show(params)
    local id = params and params[1]
    if id and DR.get(id) then
      state.sel = id
      DR.setLastOpened(id)
    elseif not sel() then
      -- Nothing selected yet (or the drawing is gone): preview the last opened one, as if clicked.
      local start = DR.startItem()
      state.sel = start and start.id or nil
    end
    refresh()
  end

  -- Hooks for the tests and the slash command.
  P.Select, P.Activate, P.Reorder, P.Refresh = selectItem, activate, reorder, function()
    refresh()
  end

  ns.On("FG_DRAWINGS_CHANGED", function()
    if view.area:IsVisible() then
      refresh()
    end
  end)
  refresh()
  return view
end

ns.RegisterPage({
  id = "drawings",
  order = 630,
  group = "tools",
  title = "page.drawings",
  icon = ns.ICONS.drawings,
  aliases = { "zeichnungen", "drawings", "paint" },
  crumbLabel = function(param)
    local item = DR.get(param)
    return item and nameOf(item) or param
  end,
  build = build,
})
