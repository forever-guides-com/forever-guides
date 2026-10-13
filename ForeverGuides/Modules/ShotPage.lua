-- Page "Location screenshots": capture button, saved list with status, delete,
-- mark as uploaded, collective export (type "shots") and the save-by-reload button.
-- The addon has no network: the player uploads pictures plus this data on the website.
local _, ns = ...
local W, L, S, Shot, K = ns.W, ns.L, ns.ShotLogic, ns.Shot, ns.PageKit

ns.Tutorials.register({
  id = "shots",
  page = "shots",
  version = 1,
  title = "tour.shots.title",
  steps = {
    { id = "intro" },
    { id = "capture", target = "FG.Shots.Capture" },
    { id = "save", target = "FG.Shots.Save" },
    { id = "list", target = "FG.Shots.List" },
    { id = "manage", target = "FG.Shots.Manage" },
  },
})

ns.AddLocale("enUS", {
  ["page.shots"] = "Location screenshots",
  ["binding.shot"] = "Location screenshot",
  ["shots.intro"] = "Screenshot without the interface, with zone, map position, direction and time.\nUpload pictures and list on forever-guides.com for the location guessing game.\nThe addon sends nothing.",
  ["shots.privacy"] = "Privacy: screenshots can show your character name, name plates and chat.\nThe addon hides the interface (and name plates if enabled). Check your pictures before uploading.",
  ["shots.take"] = "Take screenshot",
  ["shots.takeTip"] = "Hides the interface and takes the screenshot.\nSame as /fg shot or the key binding. Not in combat.",
  ["shots.save"] = "Save (reload)",
  ["shots.saveTip"] = "The game saves data only on logout or /reload.\nA crash loses newer entries. Reloads the interface, not in combat.",
  ["shots.plates"] = "Hide name plates while shooting",
  ["shots.usage"] = "%d of %d entries (%d new, %d uploaded). Not saved: %d.",
  ["shots.check.bad"] = "Checksum wrong: %d entry(ies) changed by hand.",
  ["shots.check.gaps"] = "%d gap(s) in the chain (deleted entries).",
  ["shots.empty"] = "No screenshots yet. Button, key binding or /fg shot.",
  ["shots.pick"] = "Pick an entry to change or delete it.",
  ["shots.st.new"] = "new",
  ["shots.st.up"] = "uploaded",
  ["shots.row"] = "%s / %s  file %s",
  ["shots.row.facing"] = "facing %d deg",
  ["shots.act.mark"] = "Mark as uploaded",
  ["shots.act.unmark"] = "Mark as new",
  ["shots.act.delete"] = "Delete entry",
  ["shots.act.exportNew"] = "Export new",
  ["shots.act.exportAll"] = "Export all",
  ["shots.act.markAll"] = "All new: uploaded",
  ["shots.act.deleteUp"] = "Delete uploaded",
  ["shots.delete.title"] = "Delete entry?",
  ["shots.delete.text"] = "Removes the entry from the list. The picture file stays.",
  ["shots.deleteUp.title"] = "Delete all uploaded entries?",
  ["shots.deleteUp.text"] = "Removes all entries marked as uploaded. Picture files stay.",
  ["shots.reload.title"] = "Reload the interface?",
  ["shots.reload.text"] = "Saves the list. Addons reload, you stay connected.",
  ["shots.export.title"] = "Export for the website",
  ["shots.export.hint"] = "%d entries in %d string(s), one block each. Copy with Ctrl+C.\nThe website also reads ForeverGuides.lua (WTF/Account/<account>/SavedVariables) directly, then you need no string.\nEntries marked as uploaded are not in the new-only export.",
  ["shots.export.none"] = "Nothing to export.",
  ["shots.export.fail"] = "Export failed.",
  ["shots.msg.saved"] = "Location shot %s saved: %s, %s, %s. Not saved: %d (Save or /reload).",
  ["shots.msg.timeout"] = "Screenshot not confirmed. Check the Screenshots folder, entry kept.",
  ["shots.msg.failed"] = "Screenshot failed, no entry made.",
  ["shots.msg.abort"] = "Screenshot cancelled, the interface is back.",
  ["shots.msg.busy"] = "A screenshot is already running.",
  ["shots.msg.combat"] = "Not in combat.",
  ["shots.msg.limit"] = "List full (200). Delete entries or mark them as uploaded.",
  ["shots.msg.noapi"] = "This client does not allow addons to take screenshots.",
  ["shots.msg.id"] = "Could not create an entry id.",
  ["shots.msg.saveCombat"] = "Saving by reload is not possible in combat.",
  ["shots.warn.instance"] = "Instance: a poor guessing location.",
  ["shots.warn.city"] = "City or resting area: usually a poor guessing location.",
  ["shots.web"] = "Upload on forever-guides.com: choose your pictures (Screenshots folder) and this data.\nPairing uses the time in the file name (WoWScrnShot_MMDDYY_HHMMSS, 2 seconds tolerance).",
  ["shots.limit"] = "Limit: the game saves data only on logout or reload, a crash loses newer entries.\nThe checksum chain detects accidental or manual changes only, it is no security feature.",
  ["shots.preview"] = "Show a preview of the picture",
  ["shots.d.zone"] = "%s / %s",
  ["shots.d.pos"] = "Position %s",
  ["shots.d.facing"] = "facing %d deg",
  ["shots.d.time"] = "Time %s",
  ["shots.d.file"] = "File %s",
  ["shots.d.folder"] = "Folder: Screenshots in your game folder",
  ["shots.d.none"] = "No preview available.",
  ["shots.d.off"] = "Preview is switched off.",
  ["shots.d.hint"] = "Not shown in the game: open the file in the Screenshots folder.",
  ["shots.act.copyName"] = "Copy file name",
  ["shots.act.copyNames"] = "Copy all file names",
  ["shots.act.copyCode"] = "Copy upload code",
  ["shots.act.copyCodes"] = "Copy all upload codes",
  ["shots.copyName.title"] = "File name",
  ["shots.copyName.hint"] = "Pick this file in your Screenshots folder when uploading.\nThe time may differ by up to 2 seconds.",
  ["shots.copyNames.title"] = "File names",
  ["shots.copyNames.hint"] = "%d file names, one per line.\nPick these files in your Screenshots folder when uploading.",
  ["shots.copyCode.title"] = "Upload code",
  ["shots.copyCode.hint"] = "One entry as a code: position, time, chain link, file name, check token.\nNo picture inside. Upload picture and code together.",
  ["shots.copyCodes.title"] = "Upload codes",
  ["shots.copyCodes.hint"] = "%d codes, one per line, newest last.\nNo pictures inside. Upload each picture with its code.",
  ["tour.shots.title"] = "Location screenshots",
  ["tour.shots.intro.title"] = "Location screenshots",
  ["tour.shots.intro.text"] = "For the location guessing game. Check screenshots for name and chat before uploading.",
  ["tour.shots.capture.title"] = "Take screenshot",
  ["tour.shots.capture.text"] = "Hides the interface and takes the picture. Also /fg shot or a key. Not in combat.",
  ["tour.shots.save.title"] = "Save by reload",
  ["tour.shots.save.text"] = "Data reaches the disk only on logout or reload. Use this after a few shots.",
  ["tour.shots.list.title"] = "Your shots",
  ["tour.shots.list.text"] = "Time, zone, position per shot. New ones are not uploaded yet.",
  ["tour.shots.manage.title"] = "Export and clean up",
  ["tour.shots.manage.text"] = "Export new entries, mark as uploaded, delete single or all uploaded.",
})

ns.AddLocale("deDE", {
  ["page.shots"] = "Orts-Screenshots",
  ["binding.shot"] = "Orts-Screenshot",
  ["shots.intro"] = "Screenshot ohne Oberfläche, mit Zone, Kartenposition, Blickrichtung und Zeit.\nBilder und Liste lädst du auf forever-guides.com für das Orte-Raten hoch.\nDas Addon sendet nichts.",
  ["shots.privacy"] = "Datenschutz: Screenshots können Charaktername, Namensplaketten und Chat zeigen.\nDas Addon blendet die Oberfläche aus (Namensplaketten falls aktiv). Prüfe Bilder vor dem Hochladen.",
  ["shots.take"] = "Screenshot aufnehmen",
  ["shots.takeTip"] = "Blendet die Oberfläche aus und macht den Screenshot.\nWie /fg shot oder die Tastenbelegung. Nicht im Kampf.",
  ["shots.save"] = "Sichern (Neuladen)",
  ["shots.saveTip"] = "Das Spiel speichert nur beim Ausloggen oder /reload.\nEin Absturz verliert neuere Einträge. Lädt die Oberfläche neu, nicht im Kampf.",
  ["shots.plates"] = "Namensplaketten beim Aufnehmen ausblenden",
  ["shots.usage"] = "%d von %d Einträgen (%d neu, %d hochgeladen). Nicht gesichert: %d.",
  ["shots.check.bad"] = "Prüfsumme falsch: %d Eintrag/Einträge von Hand geändert.",
  ["shots.check.gaps"] = "%d Lücke(n) in der Kette (gelöschte Einträge).",
  ["shots.empty"] = "Noch keine Screenshots. Knopf, Tastenbelegung oder /fg shot.",
  ["shots.pick"] = "Wähle einen Eintrag, um ihn zu ändern oder zu löschen.",
  ["shots.st.new"] = "neu",
  ["shots.st.up"] = "hochgeladen",
  ["shots.row"] = "%s / %s  Datei %s",
  ["shots.row.facing"] = "Blick %d Grad",
  ["shots.act.mark"] = "Als hochgeladen markieren",
  ["shots.act.unmark"] = "Als neu markieren",
  ["shots.act.delete"] = "Eintrag löschen",
  ["shots.act.exportNew"] = "Neue exportieren",
  ["shots.act.exportAll"] = "Alle exportieren",
  ["shots.act.markAll"] = "Alle neuen: hochgeladen",
  ["shots.act.deleteUp"] = "Hochgeladene löschen",
  ["shots.delete.title"] = "Eintrag löschen?",
  ["shots.delete.text"] = "Entfernt den Eintrag aus der Liste. Die Bilddatei bleibt.",
  ["shots.deleteUp.title"] = "Alle hochgeladenen Einträge löschen?",
  ["shots.deleteUp.text"] = "Entfernt alle als hochgeladen markierten Einträge. Bilddateien bleiben.",
  ["shots.reload.title"] = "Oberfläche neu laden?",
  ["shots.reload.text"] = "Speichert die Liste. Addons laden neu, du bleibst verbunden.",
  ["shots.export.title"] = "Export für die Website",
  ["shots.export.hint"] = "%d Einträge in %d String(s), je ein Block. Mit Strg+C kopieren.\nDie Website liest auch ForeverGuides.lua (WTF/Account/<Konto>/SavedVariables) direkt, dann brauchst du keinen String.\nAls hochgeladen markierte Einträge fehlen im Export der neuen.",
  ["shots.export.none"] = "Nichts zu exportieren.",
  ["shots.export.fail"] = "Export fehlgeschlagen.",
  ["shots.msg.saved"] = "Orts-Shot %s gespeichert: %s, %s, %s. Nicht gesichert: %d (Sichern oder /reload).",
  ["shots.msg.timeout"] = "Screenshot nicht bestätigt. Prüfe den Screenshots-Ordner, Eintrag bleibt.",
  ["shots.msg.failed"] = "Screenshot fehlgeschlagen, kein Eintrag angelegt.",
  ["shots.msg.abort"] = "Screenshot abgebrochen, die Oberfläche ist zurück.",
  ["shots.msg.busy"] = "Ein Screenshot läuft schon.",
  ["shots.msg.combat"] = "Nicht im Kampf.",
  ["shots.msg.limit"] = "Liste voll (200). Lösche Einträge oder markiere sie als hochgeladen.",
  ["shots.msg.noapi"] = "Dieser Client erlaubt Addons keine Screenshots.",
  ["shots.msg.id"] = "Konnte keine Eintrags-ID erzeugen.",
  ["shots.msg.saveCombat"] = "Sichern per Neuladen geht im Kampf nicht.",
  ["shots.warn.instance"] = "Instanz: schlechter Ort zum Raten.",
  ["shots.warn.city"] = "Stadt oder Ruhegebiet: meist ein schlechter Ort zum Raten.",
  ["shots.web"] = "Hochladen auf forever-guides.com: wähle deine Bilder (Screenshots-Ordner) und diese Daten.\nZuordnung über die Zeit im Dateinamen (WoWScrnShot_MMDDYY_HHMMSS, 2 Sekunden Toleranz).",
  ["shots.limit"] = "Grenze: Das Spiel speichert nur beim Ausloggen oder Neuladen, ein Absturz verliert neuere Einträge.\nDie Prüfsummen-Kette erkennt nur Zufall oder Handänderungen, keine Sicherheitsfunktion.",
  ["shots.preview"] = "Vorschau des Bildes anzeigen",
  ["shots.d.zone"] = "%s / %s",
  ["shots.d.pos"] = "Position %s",
  ["shots.d.facing"] = "Blick %d Grad",
  ["shots.d.time"] = "Zeit %s",
  ["shots.d.file"] = "Datei %s",
  ["shots.d.folder"] = "Ordner: Screenshots im Spielordner",
  ["shots.d.none"] = "Keine Vorschau verfügbar.",
  ["shots.d.off"] = "Die Vorschau ist ausgeschaltet.",
  ["shots.d.hint"] = "Im Spiel nicht anzeigbar: Datei im Ordner Screenshots öffnen.",
  ["shots.act.copyName"] = "Dateiname kopieren",
  ["shots.act.copyNames"] = "Alle Dateinamen kopieren",
  ["shots.act.copyCode"] = "Upload-Code kopieren",
  ["shots.act.copyCodes"] = "Alle Upload-Codes kopieren",
  ["shots.copyName.title"] = "Dateiname",
  ["shots.copyName.hint"] = "Wähle diese Datei beim Hochladen im Ordner Screenshots aus.\nDie Zeit kann um bis zu 2 Sekunden abweichen.",
  ["shots.copyNames.title"] = "Dateinamen",
  ["shots.copyNames.hint"] = "%d Dateinamen, einer pro Zeile.\nWähle diese Dateien beim Hochladen im Ordner Screenshots aus.",
  ["shots.copyCode.title"] = "Upload-Code",
  ["shots.copyCode.hint"] = "Ein Eintrag als Code: Position, Zeit, Kettenglied, Dateiname, Prüfwert.\nEnthält kein Bild. Lade Bild und Code zusammen hoch.",
  ["shots.copyCodes.title"] = "Upload-Codes",
  ["shots.copyCodes.hint"] = "%d Codes, einer pro Zeile, neuester zuletzt.\nEnthalten keine Bilder. Lade jedes Bild mit seinem Code hoch.",
  ["tour.shots.title"] = "Orts-Screenshots",
  ["tour.shots.intro.title"] = "Orts-Screenshots",
  ["tour.shots.intro.text"] = "Für das Orte-Raten. Prüfe Bilder vor dem Hochladen auf Name und Chat.",
  ["tour.shots.capture.title"] = "Screenshot aufnehmen",
  ["tour.shots.capture.text"] = "Blendet die Oberfläche aus und macht das Bild. Auch per /fg shot oder Taste. Nicht im Kampf.",
  ["tour.shots.save.title"] = "Sichern per Neuladen",
  ["tour.shots.save.text"] = "Daten landen nur beim Ausloggen oder Neuladen auf der Platte. Knopf nach ein paar Aufnahmen.",
  ["tour.shots.list.title"] = "Deine Aufnahmen",
  ["tour.shots.list.text"] = "Zeit, Zone, Position je Aufnahme. Neue sind noch nicht hochgeladen.",
  ["tour.shots.manage.title"] = "Exportieren und aufräumen",
  ["tour.shots.manage.text"] = "Neue exportieren, als hochgeladen markieren, einzelne oder alle hochgeladenen löschen.",
})

local function fmt(key, ...)
  local ok, text = pcall(string.format, L[key], ...)
  return ok and text or L[key]
end

-- Best-effort picture preview. The client only loads textures from known paths, so the
-- screenshot (written by the game to <game folder>\Screenshots) may or may not show. Switch
-- off with the setting shotPreview (default on); the entry data is always shown next to it.
local Preview = { DIR = "Screenshots\\" }
ns.ShotPreview = Preview

function Preview.enabled()
  return ns.Store.get("settings.shotPreview") ~= false
end

-- Paths to try: names with +-2 s drift in the current format first, other formats next, then
-- the same without extension (the client may add one itself).
function Preview.paths(e)
  local out, plain, seen = {}, {}, {}
  for _, name in ipairs(S.candidateNames(e, Shot.Format())) do
    out[#out + 1] = Preview.DIR .. name
    local stem = name:match("^(.-)%.%w+$")
    if stem and not seen[stem] then
      seen[stem] = true
      plain[#plain + 1] = Preview.DIR .. stem
    end
  end
  for _, path in ipairs(plain) do
    out[#out + 1] = path
  end
  return out
end

-- Replaceable in tests. true when the client took the path (a loaded texture reports it back).
function Preview.load(tex, path)
  if not pcall(tex.SetTexture, tex, path) then
    return false
  end
  local got = tex:GetTexture()
  return got ~= nil and got ~= "" and got ~= 0
end

-- Returns the path that loaded, or nil + "off" / "missing". Leaves the texture empty on failure.
function Preview.show(tex, e)
  if not Preview.enabled() then
    tex:SetTexture(nil)
    return nil, "off"
  end
  for _, path in ipairs(Preview.paths(e)) do
    if Preview.load(tex, path) then
      return path
    end
  end
  tex:SetTexture(nil)
  return nil, "missing"
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { sel = nil }
  local refresh

  ns.AddParagraph(view, "shots.intro")
  ns.AddParagraph(view, "shots.privacy", { role = "ui", color = "textSecondary" })

  local bar = CreateFrame("Frame", nil, view.content)
  local takeBtn = W.Action(bar, {
    label = "act.shot",
    icon = "eye",
    variant = "primary",
    width = 190,
    height = 28,
    tooltip = "shots.take",
    tooltipText = "shots.takeTip",
    onClick = function()
      Shot.Capture()
    end,
  })
  takeBtn:SetPoint("TOPLEFT")
  K.Anchor("FG.Shots.Capture", takeBtn)
  local saveBtn = W.Action(bar, {
    label = "act.save",
    icon = "save",
    width = 170,
    height = 28,
    tooltip = "shots.save",
    tooltipText = "shots.saveTip",
    onClick = function()
      ns.Dialogs.Confirm("shots.reload.title", "shots.reload.text", function()
        Shot.Save()
      end)
    end,
  })
  saveBtn:SetPoint("LEFT", takeBtn, "RIGHT", 8, 0)
  K.Anchor("FG.Shots.Save", saveBtn)
  s:Add(bar, { height = 28 })

  s:Add(
    W.Toggle(view.content, {
      key = "shots.plates",
      get = function()
        return Shot.PlatesEnabled()
      end,
      set = function(v)
        Shot.SetPlates(v)
      end,
    }),
    { height = 26 }
  )
  s:Add(
    W.Toggle(view.content, {
      key = "shots.preview",
      get = Preview.enabled,
      set = function(v)
        ns.Store.set("settings.shotPreview", v and true or false)
        refresh()
      end,
    }),
    { height = 26 }
  )

  local usage = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })
  local check = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })

  local list = K.NewList(view.content, {
    rowHeight = 42,
    bind = function(e)
      local sub = fmt("shots.row", e.zone, e.sub ~= "" and e.sub or "-", e.file or "")
      local pos = K.Coord(e.x, e.y)
      local face = type(e.face) == "number" and fmt("shots.row.facing", math.deg(e.face)) or nil
      local extra = {}
      if pos then
        extra[#extra + 1] = pos
      end
      if face then
        extra[#extra + 1] = face
      end
      return {
        title = e.lt .. (#extra > 0 and ("  " .. table.concat(extra, " / ")) or ""),
        sub = sub,
        right = L["shots.st." .. (e.st == "up" and "up" or "new")],
        selected = e.id == state.sel,
      }
    end,
    onClick = function(e)
      state.sel = e.id
      refresh()
    end,
  })
  K.Anchor("FG.Shots.List", list)
  s:Add(list, { height = K.scaledHeight(42) * 6 })
  local listNote = ns.AddParagraph(view, nil, { role = "ui", color = "textMuted" })

  -- Detail card: picture preview (when the client loads it) next to the entry data, or the
  -- data alone with a hint when it does not.
  local detail = CreateFrame("Frame", nil, view.content)
  W.Fill(detail, "surface", 1)
  K.Anchor("FG.Shots.Detail", detail)
  detail.tex = detail:CreateTexture(nil, "ARTWORK")
  detail.tex:SetSize(256, 144)
  detail.tex:SetPoint("TOPLEFT", 8, -8)
  detail.info = W.Text(detail, { role = "ui", color = "text", wrap = true })
  detail.hint = W.Text(detail, { role = "micro", color = "textMuted", wrap = true })
  detail.hint:SetPoint("TOPLEFT", detail.info, "BOTTOMLEFT", 0, -6)
  detail.hint:SetPoint("RIGHT", detail.info, "RIGHT", 0, 0)
  s:Add(detail, { height = K.scaledHeight(160) })

  local function updateDetail(sel)
    detail.path = nil
    if not sel then
      detail.tex:SetTexture(nil)
      detail.tex:Hide()
      detail.info:ClearAllPoints()
      detail.info:SetPoint("TOPLEFT", 12, -10)
      detail.info:SetPoint("RIGHT", -12, 0)
      W.SetText(detail.info, "shots.pick")
      W.SetText(detail.hint, nil, "")
      return
    end
    local path, why = Preview.show(detail.tex, sel)
    detail.path = path
    detail.tex:SetShown(path ~= nil)
    detail.info:ClearAllPoints()
    if path then
      detail.info:SetPoint("TOPLEFT", detail.tex, "TOPRIGHT", 12, 0)
    else
      detail.info:SetPoint("TOPLEFT", 12, -10)
    end
    detail.info:SetPoint("RIGHT", -12, 0)
    local lines = { fmt("shots.d.zone", sel.zone, sel.sub ~= "" and sel.sub or "-") }
    local pos = K.Coord(sel.x, sel.y)
    if pos then
      local face = type(sel.face) == "number" and ("  /  " .. fmt("shots.d.facing", math.deg(sel.face))) or ""
      lines[#lines + 1] = fmt("shots.d.pos", pos) .. face
    end
    lines[#lines + 1] = fmt("shots.d.time", sel.lt or "?")
    lines[#lines + 1] = fmt("shots.d.file", Shot.ExpectedFile(sel))
    lines[#lines + 1] = L["shots.d.folder"]
    W.SetText(detail.info, nil, table.concat(lines, "\n"))
    local note = path and "" or (why == "off" and L["shots.d.off"] .. " " or L["shots.d.none"] .. " ")
    W.SetText(detail.hint, nil, note .. (path and "" or L["shots.d.hint"]))
  end

  local manage = CreateFrame("Frame", nil, view.content)
  K.Anchor("FG.Shots.Manage", manage)
  local btn = {}
  local function mk(id, key, col, row, onClick)
    local b = W.Button(manage, { key = key, width = 190, onClick = onClick })
    b:SetPoint("TOPLEFT", col * 196, -row * 30)
    btn[id] = b
    K.Anchor("FG.Shots.Btn." .. id, b)
    return b
  end
  mk("mark", "shots.act.mark", 0, 0, function()
    local e = state.sel and S.get(state.sel)
    if e then
      S.setStatus(e.id, e.st == "up" and "new" or "up")
      refresh()
    end
  end)
  mk("delete", "shots.act.delete", 1, 0, function()
    if state.sel then
      ns.Dialogs.Confirm("shots.delete.title", "shots.delete.text", function()
        S.remove(state.sel)
        state.sel = nil
        refresh()
      end)
    end
  end)
  local function exportItems(onlyNew)
    local items = {}
    for _, e in ipairs(S.items()) do
      if not onlyNew or e.st ~= "up" then
        items[#items + 1] = e
      end
    end
    if #items == 0 then
      ns.Notify(L["shots.export.none"], "info")
      return
    end
    local strings = S.exportStrings(items)
    if not strings then
      ns.Notify(L["shots.export.fail"], "error")
      return
    end
    local dialog = ns.Dialogs.Copy("shots.export.title", table.concat(strings, "\n\n"))
    W.SetText(dialog.hint, nil, fmt("shots.export.hint", #items, #strings))
  end
  mk("exportNew", "shots.act.exportNew", 0, 2, function()
    exportItems(true)
  end)
  mk("exportAll", "shots.act.exportAll", 1, 2, function()
    exportItems(false)
  end)
  mk("markAll", "shots.act.markAll", 0, 3, function()
    S.markAllUploaded()
    refresh()
  end)
  mk("deleteUp", "shots.act.deleteUp", 1, 3, function()
    ns.Dialogs.Confirm("shots.deleteUp.title", "shots.deleteUp.text", function()
      S.removeUploaded()
      state.sel = nil
      refresh()
    end)
  end)
  local function copyDialog(titleKey, text, hint)
    local dialog = ns.Dialogs.Copy(titleKey, text)
    W.SetText(dialog.hint, nil, hint)
  end
  mk("copyName", "shots.act.copyName", 0, 1, function()
    local e = state.sel and S.get(state.sel)
    if e then
      copyDialog("shots.copyName.title", Shot.ExpectedFile(e), L["shots.copyName.hint"])
    end
  end)
  mk("copyCode", "shots.act.copyCode", 1, 1, function()
    local e = state.sel and S.get(state.sel)
    local text = e and S.encodeCode(e, Shot.Format())
    if text then
      copyDialog("shots.copyCode.title", text, L["shots.copyCode.hint"])
    elseif e then
      ns.Notify(L["shots.export.fail"], "error")
    end
  end)
  mk("copyNames", "shots.act.copyNames", 0, 4, function()
    local names = {}
    for _, e in ipairs(S.items()) do
      names[#names + 1] = Shot.ExpectedFile(e)
    end
    if #names == 0 then
      ns.Notify(L["shots.export.none"], "info")
      return
    end
    copyDialog("shots.copyNames.title", table.concat(names, "\n"), fmt("shots.copyNames.hint", #names))
  end)
  mk("copyCodes", "shots.act.copyCodes", 1, 4, function()
    local text, count = S.encodeCodes(S.items(), Shot.Format())
    if not text then
      ns.Notify(L["shots.export.fail"], "error")
      return
    end
    if count == 0 then
      ns.Notify(L["shots.export.none"], "info")
      return
    end
    copyDialog("shots.copyCodes.title", text, fmt("shots.copyCodes.hint", count))
  end)
  s:Add(manage, { height = 152 })

  ns.AddParagraph(view, "shots.web", { role = "micro", color = "textMuted" })
  ns.AddParagraph(view, "shots.limit", { role = "micro", color = "textMuted" })

  function refresh()
    state.dirty = false
    local items = S.list()
    local new, up = S.count()
    W.SetText(usage, nil, fmt("shots.usage", new + up, S.MAX, new, up, S.unsaved))
    local v = S.verify()
    local notes = {}
    if v.bad > 0 then
      notes[#notes + 1] = fmt("shots.check.bad", v.bad)
    end
    if v.gaps > 0 then
      notes[#notes + 1] = fmt("shots.check.gaps", v.gaps)
    end
    W.SetText(check, nil, table.concat(notes, " "))
    check:SetShown(#notes > 0)
    list:SetData(items)
    local sel = state.sel and S.get(state.sel)
    if not sel then
      state.sel = nil
    end
    if sel and state.reveal then
      for i, e in ipairs(items) do
        if e == sel then
          list:Reveal(i)
          break
        end
      end
    end
    state.reveal = false
    W.SetText(listNote, nil, #items == 0 and L["shots.empty"] or "")
    listNote:SetShown(#items == 0)
    updateDetail(sel)
    btn.mark:SetEnabled(sel ~= nil)
    btn.delete:SetEnabled(sel ~= nil)
    btn.copyName:SetEnabled(sel ~= nil)
    btn.copyCode:SetEnabled(sel ~= nil)
    W.SetText(btn.mark.label, sel and sel.st == "up" and "shots.act.unmark" or "shots.act.mark")
    btn.exportNew:SetEnabled(new > 0)
    btn.exportAll:SetEnabled(new + up > 0)
    btn.markAll:SetEnabled(new > 0)
    btn.deleteUp:SetEnabled(up > 0)
    btn.copyNames:SetEnabled(new + up > 0)
    btn.copyCodes:SetEnabled(new + up > 0)
    view:Layout()
  end

  function view:Show()
    refresh()
  end

  -- id: a new or just finished entry, selected and scrolled into view. A hidden page (the
  -- interface is hidden while the picture is taken) refreshes as soon as it is shown again.
  ns.On("FG_SHOTS_CHANGED", function(_, id)
    if id and S.get(id) then
      state.sel, state.reveal = id, true
    end
    if view.area:IsVisible() then
      refresh()
    else
      state.dirty = true
    end
  end)
  view.area:HookScript("OnShow", function()
    if state.dirty then
      refresh()
    end
  end)
  return view
end

ns.RegisterPage({
  id = "shots",
  order = 640,
  group = "tools",
  title = "page.shots",
  icon = ns.ICONS.shots,
  aliases = { "shots", "orts-screenshots", "screenshots", "ortsshots" },
  build = build,
})
