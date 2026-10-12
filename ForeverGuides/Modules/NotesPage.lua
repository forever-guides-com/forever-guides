-- Notes manager page: list with search, tags, sort and favorites, per-note
-- settings, trash, export/import (preview first, never automatic) and backup.
-- Two panes (list left, note right, stacked on narrow pages) from FlowLayout.lua.
-- Notes stay on this computer, they are never sent to the web account.
local _, ns = ...
local W, L, U, N, NW, K, FL = ns.W, ns.L, ns.U, ns.Notes, ns.NoteWindow, ns.PageKit, ns.FlowLayout

ns.Tutorials.register({
  id = "notes",
  page = "notes",
  version = 1,
  title = "tour.notes.title",
  steps = {
    { id = "intro" },
    { id = "toolbar", target = "FG.Notes.Toolbar" },
    { id = "filters", target = "FG.Notes.Filters" },
    { id = "list", target = "FG.Notes.List" },
    { id = "actions", target = "FG.Notes.Actions", optional = true },
    { id = "tabs", target = "FG.Notes.Tabs" },
  },
})

ns.AddLocale("enUS", {
  ["page.notes"] = "Notes",
  ["notes.intro"] = "Note windows. Everything stays on this computer.",
  ["notes.new"] = "New note",
  ["notes.import"] = "Import...",
  ["notes.backup"] = "Backup (all)",
  ["notes.closeAll"] = "Close all note windows",
  ["notes.backupTip"] = "Copies all notes as strings.\nBack up after bigger changes.",
  ["notes.tab.notes"] = "Notes",
  ["notes.tab.trash"] = "Trash",
  ["notes.search"] = "Search title, text, tags",
  ["notes.filter.tag"] = "Tag",
  ["notes.filter.allTags"] = "All tags",
  ["notes.filter.sort"] = "Sort",
  ["notes.filter.fav"] = "Favorites only",
  ["notes.sort.manual"] = "Manual",
  ["notes.sort.updated"] = "Last changed",
  ["notes.sort.created"] = "Created",
  ["notes.sort.title"] = "Title",
  ["notes.order.hintManual"] = "Drag or use the arrows.\n{mod:listToEdge}: to the top or bottom.",
  ["notes.order.hintOther"] = 'To reorder, set the sort to "Manual".',
  ["notes.act.up"] = "Move up ({mod:listToEdge}: to the top)",
  ["notes.act.down"] = "Move down ({mod:listToEdge}: to the bottom)",
  ["notes.usage"] = "%d of %d notes, %d open as window.",
  ["notes.usage.warn"] = "The limit is close.",
  ["notes.empty"] = 'No notes yet. Click "New note" or type /fg note new.',
  ["notes.emptyFilter"] = "No note matches the filter.",
  ["notes.pick"] = "Pick a note in the list to change it.",
  ["notes.state.open"] = "open",
  ["notes.state.sticky"] = "open, sticky",
  ["notes.chars"] = "%d characters",
  ["notes.act.open"] = "Open window",
  ["notes.act.close"] = "Close window",
  ["notes.act.edit"] = "Edit text",
  ["notes.act.duplicate"] = "Duplicate",
  ["notes.act.exportString"] = "Export string",
  ["notes.act.exportText"] = "Copy as text",
  ["notes.act.share"] = "Share",
  ["notes.act.delete"] = "Delete",
  ["notes.appearance"] = "Appearance of this note",
  ["notes.field.title"] = "Title",
  ["notes.field.tags"] = "Tags (comma separated, up to 8)",
  ["notes.field.font"] = "Font",
  ["notes.field.size"] = "Text size",
  ["notes.field.theme"] = "Colors",
  ["notes.field.colorText"] = "Text color",
  ["notes.field.colorBg"] = "Background color",
  ["notes.field.alpha"] = "Background opacity",
  ["notes.field.scale"] = "Window scale",
  ["notes.field.fav"] = "Favorite",
  ["notes.field.sticky"] = "Sticky",
  ["notes.field.stickyTip"] = "Fixes position and size, Esc does not close the window.",
  ["notes.font.frizqt"] = "Friz Quadrata (default)",
  ["notes.font.arialn"] = "Arial Narrow (compact)",
  ["notes.font.morpheus"] = "Morpheus (decorative)",
  ["notes.font.skurri"] = "Skurri (decorative)",
  ["notes.theme.dark"] = "Dark",
  ["notes.theme.parchment"] = "Parchment",
  ["notes.theme.night"] = "Night blue",
  ["notes.theme.forest"] = "Forest",
  ["notes.theme.paper"] = "Light paper",
  ["notes.theme.contrast"] = "High contrast",
  ["notes.theme.custom"] = "Custom (imported)",
  ["notes.renderer"] = "Display",
  ["notes.renderer.auto"] = "Automatic (formatted view)",
  ["notes.renderer.html"] = "SimpleHTML (older view)",
  ["notes.renderer.blocks"] = "Blocks (always works)",
  ["notes.renderer.tip"] = "Notes look wrong? Pick SimpleHTML or Blocks.\nBold, italic, sizes: formatted view only.\nLinks: formatted view and SimpleHTML.",
  ["notes.trash.hint"] = "Kept %d days (max. %d).\nRestoring needs a free slot.",
  ["notes.trash.empty"] = "The trash is empty.",
  ["notes.trash.sub"] = "Deleted %s, removed after %d more day(s)",
  ["notes.trash.restore"] = "Restore",
  ["notes.trash.purge"] = "Delete forever",
  ["notes.trash.emptyAll"] = "Empty trash",
  ["notes.trash.pick"] = "Pick a deleted note.",
  ["notes.delete.title"] = "Delete note?",
  ["notes.delete.text"] = "Moves to the trash for 30 days.",
  ["notes.purge.title"] = "Delete forever?",
  ["notes.purge.text"] = "This note is removed for good.",
  ["notes.purgeAll.title"] = "Empty the trash?",
  ["notes.purgeAll.text"] = "All deleted notes are removed for good.",
  ["notes.export.title"] = "Export note",
  ["notes.export.hint"] = "Ctrl+C copies the string.\nImport it with Import... on this page.\nContains title, text, tags, colors.",
  ["notes.exportText.hint"] = "Plain text without markup, for chat or forums.",
  ["notes.backup.title"] = "Backup of all notes",
  ["notes.backup.hint"] = "Several strings, one per block.\nRestore: paste all into Import...",
  ["notes.msg.limit"] = "Note limit reached (%d), delete some first.",
  ["notes.msg.restoreLimit"] = "No free slot, delete a note first.",
  ["notes.msg.imported"] = "%d note(s) imported, %d skipped (limit).",
  ["notes.msg.exportFail"] = "Export failed.",
  ["notes.msg.noNotes"] = "There are no notes to back up.",
  ["notes.import.title"] = "Import notes",
  ["notes.import.hint"] = "Paste string(s), JSON export or plain text.\nNothing is added until you press Import.",
  ["notes.import.paste"] = "Paste here",
  ["notes.import.do"] = "Import",
  ["notes.import.preview"] = "Preview",
  ["notes.import.empty"] = "Waiting for input.",
  ["notes.import.ok"] = "%d note(s) found (%s), Import adds them.",
  ["notes.import.src.strings"] = "exchange string",
  ["notes.import.src.json"] = "JSON",
  ["notes.import.src.text"] = "plain text",
  ["notes.import.item"] = "%d. %s (%d characters%s)",
  ["notes.import.cut"] = ", shortened",
  ["notes.import.more"] = "... and %d more",
  ["notes.import.err.empty"] = "Nothing to import.",
  ["notes.import.err.too-large"] = "The input is too large or unpacks to too much data.",
  ["notes.import.err.too-many"] = "Too many strings at once (at most 8).",
  ["notes.import.err.decode"] = "Invalid string, copy it completely.",
  ["notes.import.err.json"] = "The data inside the string is damaged.",
  ["notes.import.err.shape"] = "The data has an unexpected shape.",
  ["notes.import.err.type"] = "This string is not a notes export.",
  ["notes.import.err.version"] = "This string comes from a newer version of the addon.",
  ["notes.import.err.items"] = "Notes in the string are invalid or too many (max. 50).",
  ["notes.import.err.at"] = " (entry %d)",
  ["tour.notes.title"] = "Notes",
  ["tour.notes.intro.title"] = "Notes",
  ["tour.notes.intro.text"] = "Small note windows (Enter: next, Esc: end)",
  ["tour.notes.toolbar.title"] = "New, import, backup",
  ["tour.notes.toolbar.text"] = "Create, import or back up all notes.",
  ["tour.notes.filters.title"] = "Search and filter",
  ["tour.notes.filters.text"] = "Search, filter by tag, sort, favorites only.",
  ["tour.notes.list.title"] = "Your notes",
  ["tour.notes.list.text"] = "Pick a note to change it, the right column shows open ones.",
  ["tour.notes.actions.title"] = "Window and settings",
  ["tour.notes.actions.text"] = "Open window, edit text, sticky, font, colors, export, delete.",
  ["tour.notes.tabs.title"] = "Trash",
  ["tour.notes.tabs.text"] = "Deleted notes can be restored for 30 days.",
})

ns.AddLocale("deDE", {
  ["page.notes"] = "Notizen",
  ["notes.intro"] = "Notizfenster. Alles bleibt auf diesem Computer.",
  ["notes.new"] = "Neue Notiz",
  ["notes.import"] = "Import...",
  ["notes.backup"] = "Sicherung (alle)",
  ["notes.closeAll"] = "Alle Notizfenster schließen",
  ["notes.backupTip"] = "Kopiert alle Notizen als Strings.\nNach größeren Änderungen sichern.",
  ["notes.tab.notes"] = "Notizen",
  ["notes.tab.trash"] = "Papierkorb",
  ["notes.search"] = "Titel, Text, Tags durchsuchen",
  ["notes.filter.tag"] = "Tag",
  ["notes.filter.allTags"] = "Alle Tags",
  ["notes.filter.sort"] = "Sortierung",
  ["notes.filter.fav"] = "Nur Favoriten",
  ["notes.sort.manual"] = "Manuell",
  ["notes.sort.updated"] = "Zuletzt geändert",
  ["notes.sort.created"] = "Erstellt",
  ["notes.sort.title"] = "Titel",
  ["notes.order.hintManual"] = "Ziehen oder Pfeile nutzen.\n{mod:listToEdge}: ganz nach oben oder unten.",
  ["notes.order.hintOther"] = 'Zum Verschieben: Sortierung "Manuell".',
  ["notes.act.up"] = "Nach oben ({mod:listToEdge}: ganz nach oben)",
  ["notes.act.down"] = "Nach unten ({mod:listToEdge}: ganz nach unten)",
  ["notes.usage"] = "%d von %d Notizen, %d als Fenster offen.",
  ["notes.usage.warn"] = "Das Limit ist bald erreicht.",
  ["notes.empty"] = 'Noch keine Notizen. Klicke "Neue Notiz" oder tippe /fg note new.',
  ["notes.emptyFilter"] = "Keine Notiz passt zum Filter.",
  ["notes.pick"] = "Wähle eine Notiz in der Liste, um sie zu ändern.",
  ["notes.state.open"] = "offen",
  ["notes.state.sticky"] = "offen, angeheftet",
  ["notes.chars"] = "%d Zeichen",
  ["notes.act.open"] = "Fenster öffnen",
  ["notes.act.close"] = "Fenster schließen",
  ["notes.act.edit"] = "Text bearbeiten",
  ["notes.act.duplicate"] = "Duplizieren",
  ["notes.act.exportString"] = "Export-String",
  ["notes.act.exportText"] = "Als Text kopieren",
  ["notes.act.share"] = "Teilen",
  ["notes.act.delete"] = "Löschen",
  ["notes.appearance"] = "Darstellung dieser Notiz",
  ["notes.field.title"] = "Titel",
  ["notes.field.tags"] = "Tags (mit Komma getrennt, bis zu 8)",
  ["notes.field.font"] = "Schrift",
  ["notes.field.size"] = "Textgröße",
  ["notes.field.theme"] = "Farben",
  ["notes.field.colorText"] = "Textfarbe",
  ["notes.field.colorBg"] = "Hintergrundfarbe",
  ["notes.field.alpha"] = "Hintergrund-Deckkraft",
  ["notes.field.scale"] = "Fensterskalierung",
  ["notes.field.fav"] = "Favorit",
  ["notes.field.sticky"] = "Angeheftet",
  ["notes.field.stickyTip"] = "Fixiert Position und Größe, Esc schließt das Fenster nicht.",
  ["notes.font.frizqt"] = "Friz Quadrata (Standard)",
  ["notes.font.arialn"] = "Arial Narrow (kompakt)",
  ["notes.font.morpheus"] = "Morpheus (Zierschrift)",
  ["notes.font.skurri"] = "Skurri (Zierschrift)",
  ["notes.theme.dark"] = "Dunkel",
  ["notes.theme.parchment"] = "Pergament",
  ["notes.theme.night"] = "Nachtblau",
  ["notes.theme.forest"] = "Wald",
  ["notes.theme.paper"] = "Helles Papier",
  ["notes.theme.contrast"] = "Hoher Kontrast",
  ["notes.theme.custom"] = "Eigene (importiert)",
  ["notes.renderer"] = "Darstellung",
  ["notes.renderer.auto"] = "Automatisch (formatierte Ansicht)",
  ["notes.renderer.html"] = "SimpleHTML (ältere Ansicht)",
  ["notes.renderer.blocks"] = "Blöcke (funktioniert immer)",
  ["notes.renderer.tip"] = "Notizen sehen falsch aus? SimpleHTML oder Blöcke wählen.\nFett, Kursiv, Größen: nur formatierte Ansicht.\nLinks: formatiert und SimpleHTML.",
  ["notes.trash.hint"] = "%d Tage im Papierkorb (max. %d).\nWiederherstellen braucht freien Platz.",
  ["notes.trash.empty"] = "Der Papierkorb ist leer.",
  ["notes.trash.sub"] = "Gelöscht %s, wird in %d Tag(en) entfernt",
  ["notes.trash.restore"] = "Wiederherstellen",
  ["notes.trash.purge"] = "Endgültig löschen",
  ["notes.trash.emptyAll"] = "Papierkorb leeren",
  ["notes.trash.pick"] = "Wähle eine gelöschte Notiz.",
  ["notes.delete.title"] = "Notiz löschen?",
  ["notes.delete.text"] = "Bleibt 30 Tage im Papierkorb.",
  ["notes.purge.title"] = "Endgültig löschen?",
  ["notes.purge.text"] = "Diese Notiz wird unwiderruflich entfernt.",
  ["notes.purgeAll.title"] = "Papierkorb leeren?",
  ["notes.purgeAll.text"] = "Alle gelöschten Notizen werden unwiderruflich entfernt.",
  ["notes.export.title"] = "Notiz exportieren",
  ["notes.export.hint"] = "Strg+C kopiert den String.\nImport: Import... auf dieser Seite.\nEnthält Titel, Text, Tags, Farben.",
  ["notes.exportText.hint"] = "Reiner Text ohne Markup, für Chat oder Foren.",
  ["notes.backup.title"] = "Sicherung aller Notizen",
  ["notes.backup.hint"] = "Mehrere Strings, je ein Block.\nWiederherstellen: alle in Import... einfügen.",
  ["notes.msg.limit"] = "Notiz-Limit erreicht (%d), zuerst löschen.",
  ["notes.msg.restoreLimit"] = "Kein freier Platz, lösche zuerst eine Notiz.",
  ["notes.msg.imported"] = "%d Notiz(en) importiert, %d übersprungen (Limit).",
  ["notes.msg.exportFail"] = "Export fehlgeschlagen.",
  ["notes.msg.noNotes"] = "Es gibt keine Notizen zum Sichern.",
  ["notes.import.title"] = "Notizen importieren",
  ["notes.import.hint"] = "String(s), JSON-Export oder Klartext einfügen.\nErst Importieren fügt hinzu.",
  ["notes.import.paste"] = "Hier einfügen",
  ["notes.import.do"] = "Importieren",
  ["notes.import.preview"] = "Vorschau",
  ["notes.import.empty"] = "Warte auf Eingabe.",
  ["notes.import.ok"] = "%d Notiz(en) gefunden (%s), Importieren legt sie an.",
  ["notes.import.src.strings"] = "Austausch-String",
  ["notes.import.src.json"] = "JSON",
  ["notes.import.src.text"] = "Klartext",
  ["notes.import.item"] = "%d. %s (%d Zeichen%s)",
  ["notes.import.cut"] = ", gekürzt",
  ["notes.import.more"] = "... und %d weitere",
  ["notes.import.err.empty"] = "Nichts zu importieren.",
  ["notes.import.err.too-large"] = "Die Eingabe ist zu groß oder entpackt zu viel Daten.",
  ["notes.import.err.too-many"] = "Zu viele Strings auf einmal (höchstens 8).",
  ["notes.import.err.decode"] = "Ungültiger String, kopiere ihn vollständig.",
  ["notes.import.err.json"] = "Die Daten im String sind beschädigt.",
  ["notes.import.err.shape"] = "Die Daten haben eine unerwartete Form.",
  ["notes.import.err.type"] = "Dieser String ist kein Notizen-Export.",
  ["notes.import.err.version"] = "Dieser String stammt aus einer neueren Addon-Version.",
  ["notes.import.err.items"] = "Notizen im String ungültig oder zu viele (max. 50).",
  ["notes.import.err.at"] = " (Eintrag %d)",
  ["tour.notes.title"] = "Notizen",
  ["tour.notes.intro.title"] = "Notizen",
  ["tour.notes.intro.text"] = "Kleine Notizfenster (Enter: weiter, Esc: Ende)",
  ["tour.notes.toolbar.title"] = "Neu, Import, Sicherung",
  ["tour.notes.toolbar.text"] = "Anlegen, importieren oder alle sichern.",
  ["tour.notes.filters.title"] = "Suchen und filtern",
  ["tour.notes.filters.text"] = "Suchen, nach Tag filtern, sortieren, nur Favoriten.",
  ["tour.notes.list.title"] = "Deine Notizen",
  ["tour.notes.list.text"] = "Notiz wählen zum Ändern, rechts stehen die offenen.",
  ["tour.notes.actions.title"] = "Fenster und Einstellungen",
  ["tour.notes.actions.text"] = "Fenster, Text bearbeiten, anheften, Schrift, Farben, Export, Löschen.",
  ["tour.notes.tabs.title"] = "Papierkorb",
  ["tour.notes.tabs.text"] = "Gelöschte Notizen 30 Tage wiederherstellbar.",
})

-- Helpers ----------------------------------------------------------------------

local function fmt(key, ...)
  local ok, text = pcall(string.format, L[key], ...)
  return ok and text or L[key]
end

local function dateText(ts)
  local d = rawget(_G, "date")
  return d and d("%Y-%m-%d", ts or 0) or tostring(ts)
end

local function fontLabel(key)
  local label = L["notes.font." .. key]
  if label ~= "notes.font." .. key then
    return label
  end
  return (key:gsub("^lsm:", ""))
end

local function preview(items, source)
  local lines = {}
  for i, item in ipairs(items) do
    if i > 12 then
      lines[#lines + 1] = fmt("notes.import.more", #items - 12)
      break
    end
    lines[#lines + 1] = fmt(
      "notes.import.item",
      i,
      N.cleanTitle(item.title) ~= "" and item.title or L["notes.untitled"],
      ns.Markup.length(item.text),
      item.cut and L["notes.import.cut"] or ""
    )
  end
  return fmt("notes.import.ok", #items, L["notes.import.src." .. source]) .. "\n\n" .. table.concat(lines, "\n")
end

-- Import dialog ------------------------------------------------------------------

local importDlg
local function showImport(onDone)
  if not importDlg then
    local d = ns.Dialogs.Create("ForeverGuidesNotesImport", 560, 480)
    importDlg = d
    W.SetText(d.title, "notes.import.title")
    d.hint = W.Text(d, { key = "notes.import.hint", role = "ui", color = "textSecondary", wrap = true })
    d.hint:SetPoint("TOPLEFT", 16, -44)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.pasteLabel = W.Text(d, { key = "notes.import.paste", role = "ui" })
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
    d.previewLabel = W.Text(d, { key = "notes.import.preview", role = "ui" })
    d.previewLabel:SetPoint("TOPLEFT", 16, -256)
    d.preview = W.TextArea(d, { height = 130, readOnly = true })
    d.preview:SetPoint("TOPLEFT", 16, -276)
    d.preview:SetPoint("RIGHT", -16, 0)
    d.go = W.Action(
      d,
      { label = "act.import", icon = "import", tooltip = "notes.import.do", variant = "primary", width = 130 }
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
      local parsed, why, index = N.parseImport(text)
      d.parsed = parsed
      if parsed then
        d.preview:SetValue(preview(parsed.items, parsed.source))
        W.SetText(d.status, nil, "")
        d.go:Enable()
      else
        d.preview:SetValue("")
        local msg = L["notes.import.err." .. tostring(why)]
        if msg == "notes.import.err." .. tostring(why) then
          msg = L["notes.import.err.decode"]
        end
        if index and index > 0 then
          msg = msg .. fmt("notes.import.err.at", index)
        end
        W.SetText(d.status, nil, (text and U.trim(text) ~= "") and msg or L["notes.import.empty"])
        d.go:Disable()
      end
    end
  end
  importDlg.go:SetScript(
    "OnClick",
    ns.Wrap("notes-import", function()
      local parsed = importDlg.parsed
      if parsed then
        local added, skipped = N.importItems(parsed.items, "paste")
        ns.Notify(fmt("notes.msg.imported", added, skipped), "success")
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
ns.NotesImport = showImport

-- Two-pane layout ---------------------------------------------------------------------

-- Vertical layout for the content of one pane. Same semantics as W.Stack in Scroll.lua
-- (explicit height, fgGridLayout, GetStringHeight fallback, gap, indent) without a
-- ScrollArea to report to, plus: one entry with `fill` takes the height left in `height`
-- (at least `minFill`, then onFill(h) runs), `maxWidth` stops an entry from growing wider.
-- Entries span the pane with an anchor on each side, so they follow its width.
-- Returns the content height and the least height the pane needs (fill at `minFill`).
local function layoutColumn(parent, entries, width, height)
  local placed, used, gap, fill = {}, 0, 0, nil
  for _, entry in ipairs(entries) do
    local item, o = entry.item, entry.opts or {}
    if item:IsShown() or o.keepSpace then
      local indent = o.indent or 0
      local w = width - indent
      local stretch = not (o.maxWidth and w > o.maxWidth)
      if not stretch then
        w = o.maxWidth
      end
      local h, text = o.height, false
      if o.fill then
        h = 0
      elseif item.fgGridLayout then
        h = item:fgGridLayout(w)
      elseif not h and item.GetStringHeight then
        item:SetWidth(w)
        h = item:GetStringHeight()
        text = true
      elseif not h then
        h = item:GetHeight()
      end
      gap = o.gap or 10
      local p = { item = item, o = o, h = h, indent = indent, w = w, stretch = stretch, text = text }
      placed[#placed + 1] = p
      fill = o.fill and p or fill
      used = used + h + gap
    end
  end
  local needed = used - gap
  if fill then
    local least = fill.o.minFill or 0
    needed = needed + least
    fill.h = math.max(least, (height or 0) - used)
    used = used + fill.h
  end
  local y = 0
  for _, p in ipairs(placed) do
    local item, o = p.item, p.o
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", p.indent, -y)
    if p.stretch then
      item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
    end
    if o.fill or p.text or (o.height and not item.fgGridLayout) then
      item:SetHeight(p.h)
    end
    if p.text or not p.stretch then
      item:SetWidth(p.w)
    end
    if o.fill and o.onFill then
      o.onFill(p.h)
    end
    y = y + p.h + (o.gap or 10)
  end
  return math.max(0, used - gap), math.max(0, needed)
end

local function toHex(r, g, b)
  local function byte(v)
    return U.clamp(math.floor(v * 255 + 0.5), 0, 255)
  end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Opens Blizzard's native color picker for a note's fg/bg hex color.
-- SetupColorPickerAndShow is the modern (Retail/Camelot) API; guarded with
-- a fallback to the older direct-property API in case it is ever missing.
local function openColorPicker(currentHex, onChange)
  if not ColorPickerFrame then
    return
  end
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
end

-- Page ---------------------------------------------------------------------------

local BODY_HEIGHT = 300 -- text area of the editor (base pixels)
local MIN_EDITOR = 220 -- smallest editor height with its menu, toolbar and status bar
local SCROLLBAR = 12 -- gutter of a ScrollArea
local APPEARANCE_MAX = 760 -- the appearance section does not grow wider than this

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { tab = "notes", query = "", tag = "", sort = "manual", fav = false, sel = nil, trashSel = nil }
  local refresh
  local titleBox, tagsBox
  local groups = { notes = {}, trash = {} }
  local leftEntries, rightEntries, detailGroup, appControls = {}, {}, {}, {}
  local layoutPanes

  local function track(group, item)
    groups[group][#groups[group] + 1] = item
    return item
  end

  local intro = ns.AddParagraph(view, "notes.intro", { role = "micro", gap = 6 })

  -- Used by the New button, File > New note and Ctrl+N in the editor.
  local function newNote()
    local note = N.create({})
    if not note then
      ns.Notify(fmt("notes.msg.limit", N.MAX_NOTES), "warning")
      return
    end
    -- The new note opens in its own window in edit mode, ready to type. It is also
    -- selected here; N.create emits FG_NOTES_CHANGED, which this page's listener turns
    -- into a refresh(), and NW.Open remembers it as the last opened note.
    state.tab, state.sel = "notes", note.id
    NW.Open(note.id, { edit = true })
  end

  -- Two panes under the slim header: the list side on the left, the note on the right
  -- (stacked on narrow pages). The split fills the page height, the lists and the editor
  -- grow with it. layoutPanes below places the content of both panes.
  local split = FL.TwoPane(view.content, {
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      local above = intro:GetHeight() + 6
      return view.area:GetHeight() - 2 * s.pad - above
    end,
    onLayout = function(info)
      return layoutPanes(info)
    end,
  })
  s:Add(split, { gap = 0 })
  local leftPane, rightPane = split.left, split.right
  local rightArea = W.ScrollArea(rightPane)
  rightArea:SetFrameLevel(rightPane:GetFrameLevel() + 1)
  rightArea:SetAllPoints()
  local rc = rightArea.content

  local function addLeft(item, opts)
    leftEntries[#leftEntries + 1] = { item = item, opts = opts }
    return item
  end
  local function addRight(item, opts)
    rightEntries[#rightEntries + 1] = { item = item, opts = opts }
    return item
  end
  local function addDetail(item, opts)
    detailGroup[#detailGroup + 1] = addRight(item, opts)
    return item
  end

  -- Left pane: buttons, counter, tabs ------------------------------------------------
  local bar = FL.ButtonRow(leftPane, {
    { id = "new", label = "act.new", icon = "plus", tooltip = "notes.new", variant = "primary", onClick = newNote },
    {
      id = "import",
      label = "act.import",
      icon = "import",
      tooltip = "notes.import",
      onClick = function()
        showImport()
      end,
    },
    {
      id = "backup",
      label = "act.backup",
      icon = "save",
      tooltip = "notes.backup",
      tooltipText = "notes.backupTip",
      onClick = function()
        local all = N.list({ sort = "manual" })
        if #all == 0 then
          ns.Notify(L["notes.msg.noNotes"], "info")
          return
        end
        local strings = N.exportStrings(all)
        if not strings then
          ns.Notify(L["notes.msg.exportFail"], "error")
          return
        end
        ns.Dialogs.Copy("notes.backup.title", table.concat(strings, "\n\n"), "notes.backup.hint")
      end,
    },
    {
      id = "closeAll",
      label = "act.closeAll",
      icon = "close",
      tooltip = "notes.closeAll",
      variant = "ghost",
      onClick = function()
        ns.Notify(string.format(L["notes.slash.closed"], NW.CloseAll()), "success")
      end,
    },
  })
  K.Anchor("FG.Notes.Toolbar", bar)
  addLeft(bar, { gap = 8 })

  local usage = addLeft(W.Text(leftPane, { role = "micro", color = "textMuted", wrap = true }), { gap = 6 })

  local tabs = W.Tabs(leftPane, {
    tabs = { { id = "notes", key = "notes.tab.notes" }, { id = "trash", key = "notes.tab.trash" } },
    onSelect = function(id)
      state.tab = id
      refresh()
    end,
  })
  K.Anchor("FG.Notes.Tabs", tabs)
  addLeft(tabs, { height = 28, gap = 8 })

  -- Notes tab, left pane: search, filters and the list ----------------------------------
  local filters = CreateFrame("Frame", nil, leftPane)
  K.Anchor("FG.Notes.Filters", filters)
  local search = W.EditBox(filters, {
    placeholder = "notes.search",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT")
  search:SetPoint("TOPRIGHT")
  local tagOptions = {}
  local tagDd = FL.FitDropdown(W.Dropdown(filters, {
    key = "notes.filter.tag",
    options = tagOptions,
    get = function()
      return state.tag
    end,
    set = function(v)
      state.tag = v
      refresh()
    end,
  }))
  local sortDd = FL.FitDropdown(W.Dropdown(filters, {
    key = "notes.filter.sort",
    options = {
      { value = "manual", key = "notes.sort.manual" },
      { value = "updated", key = "notes.sort.updated" },
      { value = "created", key = "notes.sort.created" },
      { value = "title", key = "notes.sort.title" },
    },
    get = function()
      return state.sort
    end,
    set = function(v)
      state.sort = v
      refresh()
    end,
  }))
  -- Icon-only toggle instead of a labelled checkbox: compact enough to sit
  -- next to the two dropdowns, name only shown as a tooltip on hover.
  local favBtn = W.Action(filters, {
    icon = "star",
    size = 26,
    boxed = true,
    tooltip = "notes.filter.fav",
    onClick = function()
      state.fav = not state.fav
      refresh()
    end,
  })
  function favBtn.Refresh()
    favBtn:SetSelected(state.fav)
  end
  -- Tag and sort share the width, the favorites toggle sits at the right edge. Every field is
  -- anchored on both sides, so it follows the pane width.
  function filters:fgGridLayout(width)
    local favSize, gap = 26, 6
    local ddWidth = math.max(60, math.floor((width - favSize - gap * 2) / 2))
    tagDd:ClearAllPoints()
    tagDd:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -34)
    tagDd:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(width - ddWidth), -34)
    sortDd:ClearAllPoints()
    sortDd:SetPoint("TOPLEFT", self, "TOPLEFT", ddWidth + gap, -34)
    sortDd:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(favSize + gap), -34)
    favBtn:ClearAllPoints()
    favBtn:SetSize(favSize, favSize)
    favBtn:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(34 + 17))
    local h = 34 + 46
    self:SetHeight(h)
    return h
  end
  track("notes", addLeft(filters, { gap = 8 }))

  -- Notes as currently listed (filtered), the base for up/down steps.
  local listed = {}
  local reveal
  local function moveNote(note, dir)
    local moved
    if ns.Keys.Matches("listToEdge") then
      moved = N.moveToEdge(note.id, dir < 0 and "top" or "bottom")
    else
      moved = N.step(note.id, dir, listed)
    end
    if moved then
      reveal(note.id)
    end
  end
  -- The list takes the height the pane has left and scrolls inside it.
  local function fillList(list)
    return function(h)
      if list.fgFill ~= h then
        list.fgFill = h
        list.Refresh()
      end
    end
  end
  local list = K.NewList(leftPane, {
    rowHeight = 42,
    canReorder = function()
      return state.sort == "manual"
    end,
    onReorder = function(note, anchor, after)
      N.reorder(note.id, anchor.id, after)
    end,
    bind = function(note)
      local w = note.window
      local state_ = w.open and (w.sticky and L["notes.state.sticky"] or L["notes.state.open"]) or ""
      local tags = table.concat(note.tags or {}, ", ")
      local sub = fmt("notes.chars", ns.Markup.length(note.text)) .. (tags ~= "" and (" · " .. tags) or "")
      local actions = {
        {
          icon = note.fav and "star" or "star-outline",
          selected = note.fav,
          tooltip = L["notes.field.fav"],
          onClick = function()
            N.update(note.id, { fav = not note.fav })
          end,
        },
        {
          icon = "trash",
          tooltip = L["notes.act.delete"],
          onClick = function()
            ns.Dialogs.Confirm("notes.delete.title", "notes.delete.text", function()
              N.delete(note.id)
              if state.sel == note.id then
                state.sel = nil
              end
            end)
          end,
        },
      }
      if state.sort == "manual" then
        actions[3] = {
          icon = "chevron-down",
          tooltip = L["notes.act.down"],
          onClick = function()
            moveNote(note, 1)
          end,
        }
        actions[4] = {
          icon = "chevron-up",
          tooltip = L["notes.act.up"],
          onClick = function()
            moveNote(note, -1)
          end,
        }
      end
      return {
        title = (note.fav and "* " or "") .. N.displayTitle(note),
        sub = sub,
        right = state_,
        selected = note.id == state.sel,
        actions = actions,
      }
    end,
    onClick = function(note)
      state.sel = note.id
      N.setLastOpened(note.id)
      refresh()
    end,
  })
  K.Anchor("FG.Notes.List", list)
  track("notes", addLeft(list, { fill = true, minFill = K.scaledHeight(42) * 3, gap = 8, onFill = fillList(list) }))
  function reveal(id)
    for i, note in ipairs(listed) do
      if note.id == id then
        list:Reveal(i)
        return
      end
    end
  end
  local listNote =
    track("notes", addLeft(W.Text(leftPane, { role = "ui", color = "textSecondary", wrap = true }), { gap = 6 }))
  local orderHint =
    track("notes", addLeft(W.Text(leftPane, { role = "micro", color = "textMuted", wrap = true }), { gap = 0 }))

  local function sel()
    return state.sel and N.get(state.sel)
  end
  local function patch(p)
    if state.sel then
      N.update(state.sel, p)
    end
  end

  -- Trash tab, left pane -----------------------------------------------------------------
  local trashList = K.NewList(leftPane, {
    rowHeight = 42,
    bind = function(entry)
      local left = math.max(0, N.TRASH_DAYS - math.floor((U.now() - (entry.deleted or 0)) / 86400))
      return {
        title = N.displayTitle(entry.note),
        sub = fmt("notes.trash.sub", dateText(entry.deleted), left),
        selected = entry.note.id == state.trashSel,
      }
    end,
    onClick = function(entry)
      state.trashSel = entry.note.id
      refresh()
    end,
  })
  track(
    "trash",
    addLeft(trashList, { fill = true, minFill = K.scaledHeight(42) * 3, gap = 8, onFill = fillList(trashList) })
  )
  local trashBar = FL.ButtonRow(leftPane, {
    {
      id = "restore",
      label = "act.restore",
      icon = "undo",
      tooltip = "notes.trash.restore",
      variant = "primary",
      onClick = function()
        if state.trashSel then
          local note, why = N.restore(state.trashSel)
          if note then
            state.trashSel = nil
          elseif why == "limit" then
            ns.Notify(L["notes.msg.restoreLimit"], "warning")
          end
        end
      end,
    },
    {
      id = "purge",
      label = "act.delete",
      icon = "trash",
      tooltip = "notes.trash.purge",
      onClick = function()
        if state.trashSel then
          ns.Dialogs.Confirm("notes.purge.title", "notes.purge.text", function()
            N.purge(state.trashSel)
            state.trashSel = nil
          end)
        end
      end,
    },
    {
      id = "emptyAll",
      label = "act.clear",
      icon = "trash",
      tooltip = "notes.trash.emptyAll",
      onClick = function()
        ns.Dialogs.Confirm("notes.purgeAll.title", "notes.purgeAll.text", function()
          N.emptyTrash()
          state.trashSel = nil
        end)
      end,
    },
  })
  track("trash", addLeft(trashBar, { gap = 0 }))

  -- Right pane: actions, title, tags, editor, appearance -----------------------------------
  local actions = FL.ButtonRow(rc, {
    {
      id = "window",
      label = "act.open",
      icon = "open",
      tooltip = "notes.act.open",
      onClick = function()
        if sel() then
          NW.Toggle(state.sel)
        end
      end,
    },
    {
      id = "dup",
      label = "act.duplicate",
      icon = "copy",
      tooltip = "notes.act.duplicate",
      onClick = function()
        local copy, why
        if sel() then
          copy, why = N.duplicate(state.sel)
        end
        if why == "limit" then
          ns.Notify(fmt("notes.msg.limit", N.MAX_NOTES), "warning")
        elseif copy then
          state.sel = copy.id
          N.setLastOpened(copy.id)
        end
      end,
    },
    {
      id = "edit",
      label = "act.edit",
      icon = "pencil",
      tooltip = "notes.act.edit",
      onClick = function()
        if sel() then
          NW.Open(state.sel, { edit = true })
        end
      end,
    },
    {
      id = "exportString",
      label = "act.export",
      icon = "export",
      tooltip = "notes.act.exportString",
      onClick = function()
        local note = sel()
        local strings = note and N.exportStrings({ note })
        if strings then
          ns.Dialogs.Copy("notes.export.title", strings[1], "notes.export.hint")
        else
          ns.Notify(L["notes.msg.exportFail"], "error")
        end
      end,
    },
    {
      id = "exportText",
      label = "act.text",
      icon = "copy",
      tooltip = "notes.act.exportText",
      onClick = function()
        local note = sel()
        if note then
          ns.Dialogs.Copy("notes.export.title", N.exportText({ note }), "notes.exportText.hint")
        end
      end,
    },
    {
      id = "share",
      label = "act.share",
      icon = "share",
      tooltip = "notes.act.share",
      onClick = function()
        local note = sel()
        if note then
          ns.Share.OpenNote(note)
        end
      end,
    },
    {
      id = "delete",
      label = "act.delete",
      icon = "trash",
      tooltip = "notes.act.delete",
      onClick = function()
        if sel() then
          ns.Dialogs.Confirm("notes.delete.title", "notes.delete.text", function()
            N.delete(state.sel)
            state.sel = nil
          end)
        end
      end,
    },
  })
  K.Anchor("FG.Notes.Actions", actions)
  addDetail(actions, { gap = 8 })

  -- One line: a long title is cut with an ellipsis instead of wrapping.
  local heading = W.Text(rc, { role = "h2", family = "heading", color = "accent2" })
  addDetail(heading, { gap = 6 })

  local function rlabel(key)
    return addDetail(W.Text(rc, { key = key, role = "ui", color = "textSecondary" }), { gap = 2 })
  end
  rlabel("notes.field.title")
  titleBox = W.EditBox(rc, {
    placeholder = "notes.field.title",
    onChange = function()
      ns.Debounce(titleBox, 0.4, function()
        patch({ title = titleBox.edit:GetText() })
      end)
    end,
  })
  titleBox.edit:SetMaxLetters(N.MAX_TITLE)
  K.Anchor("FG.Notes.Title", titleBox)
  addDetail(titleBox, { height = 26, gap = 6 })
  rlabel("notes.field.tags")
  tagsBox = W.EditBox(rc, {
    placeholder = "notes.field.tags",
    onChange = function()
      ns.Debounce(tagsBox, 0.5, function()
        patch({ tags = tagsBox.edit:GetText() })
      end)
    end,
    onEnter = function(text)
      patch({ tags = text })
    end,
  })
  K.Anchor("FG.Notes.Tags", tagsBox)
  addDetail(tagsBox, { height = 26, gap = 8 })

  -- Body editor: the same control as the floating note window (formatted editor
  -- or code view with the toolbar, Modules/RichEditor.lua), debounced the same way
  -- as the title and tags fields above instead of saving on every keystroke.
  --
  -- bodySynced tracks which note's text is currently loaded into the
  -- editor; reloading only on an actual selection change (not every
  -- refresh) keeps the undo/redo history intact while the player edits
  -- other fields on the same note.
  --
  -- bodyDirty marks text that is not saved yet. Without it, an edit made in
  -- the floating window (same note) would leave this editor on the old text,
  -- and the next change here would write that old text back over it.
  local bodySynced
  local bodyEdit
  local bodyDirty = false
  local function scheduleBodySave()
    bodyDirty = true
    ns.Debounce(bodyEdit, 0.5, function()
      bodyDirty = false
      patch({ text = bodyEdit:GetValue() })
    end)
  end
  --
  -- The editor sits in one box with the same menu bar, toolbar and status bar as the
  -- floating window (Modules/NoteChrome.lua). The box takes the height the pane has left.
  local editorBox = CreateFrame("Frame", nil, rc)
  bodyEdit = ns.RichEditor.NewNoteEditor(editorBox, {
    height = BODY_HEIGHT,
    getNote = sel,
    onChange = scheduleBodySave,
    onNew = newNote,
  })
  ns.NoteChrome.Build(editorBox, bodyEdit, {
    getId = function()
      return state.sel
    end,
    onNew = newNote,
    onClose = function()
      state.sel = nil
      refresh()
    end,
    onDeleted = function()
      state.sel = nil
    end,
    extras = {
      {
        key = "notes.menu.openWindow",
        onClick = function()
          if sel() then
            NW.Open(state.sel)
          end
        end,
      },
    },
  })
  K.Anchor("FG.Notes.Editor", editorBox)
  addDetail(editorBox, { fill = true, minFill = MIN_EDITOR, gap = 10 })

  -- Appearance of the note: collapsed by default, the choice is remembered.
  local appOpen = N.root().ui.appearanceOpen == true
  local appHeader = W.Button(rc, {
    key = "notes.appearance",
    variant = "ghost",
    onClick = function()
      appOpen = not appOpen
      N.root().ui.appearanceOpen = appOpen
      refresh()
    end,
  })
  local function paintAppHeader()
    W.SetText(appHeader.label, nil, (appOpen and "v " or "> ") .. L["notes.appearance"])
  end
  paintAppHeader()
  ns.On("FG_UI_REFRESHED", paintAppHeader)
  K.Anchor("FG.Notes.Appearance", appHeader)
  addDetail(appHeader, { height = 26, gap = 8 })

  local appBox = CreateFrame("Frame", nil, rc)
  local cells = {}
  local function cell(item, height)
    cells[#cells + 1] = { item = item, height = height }
    appControls[#appControls + 1] = item
    return item
  end
  -- One or two columns, depending on the width the section gets.
  function appBox:fgGridLayout(width)
    local cols = width >= 520 and 2 or 1
    local gap = 12
    local cellWidth = math.floor((width - gap * (cols - 1)) / cols)
    local y, col, rowHeight = 0, 0, 0
    for _, c in ipairs(cells) do
      local x = col * (cellWidth + gap)
      c.item:ClearAllPoints()
      c.item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      c.item:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(width - x - cellWidth), -y)
      c.item:SetHeight(c.height)
      rowHeight = math.max(rowHeight, c.height)
      col = col + 1
      if col == cols then
        col, y, rowHeight = 0, y + rowHeight + 8, 0
      end
    end
    if col > 0 then
      y = y + rowHeight + 8
    end
    local h = math.max(0, y - 8)
    self:SetHeight(h)
    return h
  end
  addRight(appBox, { maxWidth = APPEARANCE_MAX, gap = 10 })

  local fontOptions = {}
  cell(
    FL.FitDropdown(W.Dropdown(appBox, {
      key = "notes.field.font",
      options = fontOptions,
      get = function()
        local note = sel()
        return note and note.style.font or "frizqt"
      end,
      set = function(v)
        patch({ style = { font = v } })
      end,
    })),
    46
  )
  local themeOptions = {}
  for _, t in ipairs(N.THEMES) do
    themeOptions[#themeOptions + 1] = { value = t.id, key = "notes.theme." .. t.id }
  end
  themeOptions[#themeOptions + 1] = { value = "custom", key = "notes.theme.custom" }
  cell(
    FL.FitDropdown(W.Dropdown(appBox, {
      key = "notes.field.theme",
      options = themeOptions,
      get = function()
        local note = sel()
        if note then
          for _, t in ipairs(N.THEMES) do
            if t.fg == note.style.fg and t.bg == note.style.bg then
              return t.id
            end
          end
        end
        return "custom"
      end,
      set = function(v)
        for _, t in ipairs(N.THEMES) do
          if t.id == v then
            patch({ style = { fg = t.fg, bg = t.bg } })
          end
        end
      end,
    })),
    46
  )

  -- Custom color pickers complement the theme presets above (presets for a
  -- quick match, these for anything else); N.cleanStyle already accepts any
  -- 6-hex color, this just gives the player a way to pick one.
  local function colorField(key, getHex, setHex)
    local f = CreateFrame("Button", nil, appBox)
    f:SetHeight(26)
    local swatch = CreateFrame("Frame", nil, f)
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", 0, 0)
    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    W.Border(swatch, "white", 0.4)
    local lbl = W.Text(f, { key = key, role = "ui" })
    lbl:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    lbl:SetPoint("RIGHT")
    f:SetScript(
      "OnClick",
      ns.Wrap("notes-color", function()
        local note = sel()
        if note then
          openColorPicker(getHex(note), setHex)
        end
      end)
    )
    f:SetScript("OnEnter", function()
      ns.ShowTooltip(f, L[key])
    end)
    f:SetScript("OnLeave", ns.HideTooltip)
    ns.Focus.register(f, function(self)
      self:Click()
    end)
    function f.Refresh()
      local note = sel()
      if note then
        tex:SetColorTexture(U.hex(getHex(note)))
      end
    end
    return f
  end
  cell(
    colorField("notes.field.colorText", function(note)
      return note.style.fg
    end, function(hex)
      patch({ style = { fg = hex } })
    end),
    26
  )
  cell(
    colorField("notes.field.colorBg", function(note)
      return note.style.bg
    end, function(hex)
      patch({ style = { bg = hex } })
    end),
    26
  )

  cell(
    W.Slider(appBox, {
      key = "notes.field.size",
      min = N.SIZE_MIN,
      max = N.SIZE_MAX,
      step = 1,
      get = function()
        local note = sel()
        return note and note.style.size or 13
      end,
      set = function(v)
        patch({ style = { size = v } })
      end,
    }),
    42
  )
  cell(
    W.Slider(appBox, {
      key = "notes.field.alpha",
      min = 30,
      max = 100,
      step = 5,
      format = function(v)
        return v .. "%"
      end,
      get = function()
        local note = sel()
        return note and math.floor(note.style.alpha * 100 + 0.5) or 92
      end,
      set = function(v)
        patch({ style = { alpha = v / 100 } })
      end,
    }),
    42
  )
  cell(
    W.Slider(appBox, {
      key = "notes.field.scale",
      min = 50,
      max = 200,
      step = 5,
      applyOn = "release",
      format = function(v)
        return v .. "%"
      end,
      get = function()
        local note = sel()
        return note and math.floor(note.window.scale * 100 + 0.5) or 100
      end,
      set = function(v)
        patch({ window = { scale = v / 100 } })
      end,
    }),
    42
  )
  cell(
    W.Toggle(appBox, {
      key = "notes.field.sticky",
      tooltip = "notes.field.sticky",
      tooltipText = "notes.field.stickyTip",
      get = function()
        local note = sel()
        return note and note.window.sticky
      end,
      set = function(v)
        if state.sel then
          NW.SetSticky(state.sel, v)
        end
      end,
    }),
    26
  )
  cell(
    W.Toggle(appBox, {
      key = "notes.field.fav",
      get = function()
        local note = sel()
        return note and note.fav
      end,
      set = function(v)
        patch({ fav = v })
      end,
    }),
    26
  )

  local pick = track(
    "notes",
    addRight(W.Text(rc, { key = "notes.pick", role = "ui", color = "textMuted", wrap = true }), {
      gap = 10,
    })
  )

  local rendererDd = FL.FitDropdown(W.Dropdown(rc, {
    key = "notes.renderer",
    options = {
      { value = "auto", key = "notes.renderer.auto" },
      { value = "html", key = "notes.renderer.html" },
      { value = "blocks", key = "notes.renderer.blocks" },
    },
    get = function()
      local choice = N.root().ui.renderer
      return (choice == "html" or choice == "blocks") and choice or "auto"
    end,
    set = function(v)
      N.root().ui.renderer = v
      NW.RefreshAll()
    end,
  }))
  track("notes", addRight(rendererDd, { height = 46, maxWidth = 360, gap = 6 }))
  local rendererTip = track(
    "notes",
    addRight(W.Text(rc, { key = "notes.renderer.tip", role = "micro", color = "textMuted", wrap = true }), { gap = 0 })
  )

  -- Trash tab, right pane: hint and state of the selection.
  local trashHint =
    track("trash", addRight(W.Text(rc, { role = "ui", color = "textSecondary", wrap = true }), { gap = 10 }))
  W.SetText(trashHint, nil, fmt("notes.trash.hint", N.TRASH_DAYS, N.MAX_TRASH))
  local trashPick = track(
    "trash",
    addRight(W.Text(rc, { key = "notes.trash.pick", role = "ui", color = "textMuted", wrap = true }), { gap = 10 })
  )
  local trashEmpty = track(
    "trash",
    addRight(W.Text(rc, { key = "notes.trash.empty", role = "ui", color = "textMuted", wrap = true }), { gap = 0 })
  )

  -- Places the content of both panes. The left pane reports the height it needs at least, so
  -- the split never cuts it off; the right pane scrolls.
  function layoutPanes(info)
    local _, neededLeft = layoutColumn(leftPane, leftEntries, info.leftWidth, info.leftHeight)
    local contentWidth = math.max(1, info.rightWidth - SCROLLBAR)
    rc:SetWidth(contentWidth)
    local total = layoutColumn(rc, rightEntries, contentWidth, info.rightHeight)
    rightArea:SetContentHeight(total)
    return neededLeft
  end

  local function fillTagOptions()
    for i = #tagOptions, 1, -1 do
      tagOptions[i] = nil
    end
    tagOptions[1] = { value = "", key = "notes.filter.allTags" }
    for _, t in ipairs(N.allTags()) do
      tagOptions[#tagOptions + 1] = { value = t.name, text = t.name .. " (" .. t.count .. ")" }
    end
  end

  local function fillFontOptions(current)
    for i = #fontOptions, 1, -1 do
      fontOptions[i] = nil
    end
    local seen = {}
    for _, key in ipairs(NW.FontList()) do
      fontOptions[#fontOptions + 1] = { value = key, text = fontLabel(key) }
      seen[key] = true
    end
    if current and not seen[current] then
      fontOptions[#fontOptions + 1] = { value = current, text = fontLabel(current) .. " *" }
    end
  end

  local function setGroup(name, shown)
    for _, item in ipairs(groups[name]) do
      item:SetShown(shown)
    end
  end

  function refresh()
    local notes = N.list({ query = state.query, tag = state.tag, fav = state.fav, sort = state.sort })
    listed = notes
    local open = NW.OpenCount()
    local total = N.count()
    W.SetText(
      usage,
      nil,
      fmt("notes.usage", total, N.MAX_NOTES, open) .. (total >= N.WARN_NOTES and (" " .. L["notes.usage.warn"]) or "")
    )
    local trash = N.trashList()
    local showNotes = state.tab == "notes"
    tabs.selected = state.tab
    setGroup("notes", showNotes)
    setGroup("trash", not showNotes)
    fillTagOptions()
    list:SetData(notes)
    local note = sel()
    if not note then
      state.sel = nil
    end
    if showNotes then
      local emptyText = total == 0 and L["notes.empty"] or (#notes == 0 and L["notes.emptyFilter"] or "")
      W.SetText(listNote, nil, emptyText)
      listNote:SetShown(emptyText ~= "")
      W.SetText(orderHint, nil, L[state.sort == "manual" and "notes.order.hintManual" or "notes.order.hintOther"])
      orderHint:SetShown(total > 1)
      pick:SetShown(note == nil and total > 0)
    end
    for _, item in ipairs(detailGroup) do
      item:SetShown(showNotes and note ~= nil)
    end
    appBox:SetShown(showNotes and note ~= nil and appOpen)
    paintAppHeader()
    if note and showNotes then
      heading:SetText(N.displayTitle(note))
      actions:SetItemText("window", NW.IsOpen(note.id) and "notes.act.close" or "notes.act.open")
      fillFontOptions(note.style.font)
      if not titleBox.edit:HasFocus() then
        titleBox.edit:SetText(note.title)
      end
      if not tagsBox.edit:HasFocus() then
        tagsBox.edit:SetText(table.concat(note.tags or {}, ", "))
      end
      local stale = not bodyDirty and bodyEdit:IsStale(note.text)
      if not bodyEdit:HasFocus() and (bodySynced ~= note.id or stale) then
        bodyEdit:SetValue(note.text)
        bodySynced = note.id
      else
        bodyEdit:Restyle()
      end
      if appOpen then
        for _, control in ipairs(appControls) do
          control.Refresh()
        end
      end
    else
      bodySynced = nil
    end
    favBtn.Refresh()
    rendererDd.Refresh()
    rendererTip:SetShown(showNotes)
    trashList:SetData(trash)
    if not showNotes then
      local found = false
      for _, entry in ipairs(trash) do
        found = found or entry.note.id == state.trashSel
      end
      if not found then
        state.trashSel = nil
      end
    end
    trashEmpty:SetShown(not showNotes and #trash == 0)
    trashPick:SetShown(not showNotes and #trash > 0 and state.trashSel == nil)
    trashBar:SetItemEnabled("restore", state.trashSel ~= nil)
    trashBar:SetItemEnabled("purge", state.trashSel ~= nil)
    trashBar:SetItemEnabled("emptyAll", #trash > 0)
    view:Layout()
  end

  function view:Show(params)
    local id = params and params[1]
    if id and N.get(id) then
      state.tab, state.sel = "notes", id
      N.setLastOpened(id)
    elseif not sel() then
      -- Nothing selected yet (or the note is gone): show the last opened note, as if clicked.
      local start = N.startNote()
      state.sel = start and start.id or nil
    end
    tabs:Select(state.tab)
  end

  ns.On("FG_NOTES_CHANGED", function()
    if view.area:IsVisible() then
      refresh()
    end
  end)
  ns.Debounce(view, 0, function()
    N.pruneTrash()
  end)
  view.split, view.right, view.actions, view.appearance = split, rightArea, actions, appBox
  return view
end

ns.RegisterPage({
  id = "notes",
  order = 95,
  group = "tools",
  title = "page.notes",
  icon = ns.ICONS.notes,
  aliases = { "notizen", "notes", "notiz" },
  crumbLabel = function(param)
    local note = N.get(param)
    return note and N.displayTitle(note) or param
  end,
  build = build,
})
