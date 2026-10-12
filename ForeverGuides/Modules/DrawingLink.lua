-- Drawing links: a shared drawing goes into the chat as one short link
-- ("[Drawing - Name]") exactly like a note (see NoteLink.lua, which carries the
-- protocol: inline payload, reference with addon-message transfer, hash check,
-- limits, session-only sender snapshots). This file only adds what is specific
-- to drawings: the content is the drawing's own encoded string
-- (DrawingLogic.Encode, at most D.MAX_SHARE = 20 KB), it is always read back with
-- the strict DrawingLogic.Decode, and the receiver sees it in a read-only viewer.
-- A background map travels as its key only (DrawingMap resolves it on the receiver's
-- client); if it is unknown there, the viewer shows the sheet without it and says so.
-- ShareInfo / ShareLine / ShareTip tell the author how a picture of a given
-- packed size travels (inside the link, by transfer, too large), the editor
-- status bar, the drawings page and the share dialog show them.
-- Nothing is added to the receiver's drawings without a click.
local _, ns = ...
local W, L, D, DR, NL, V = ns.W, ns.L, ns.DrawingLogic, ns.Drawings, ns.NoteLink, ns.DrawingView

local DL = { TOKEN = "FGD", LINK = "FGDrawing" }
ns.DrawingLink = DL

local BOX_W, BOX_H = 528, 322

ns.AddLocale("enUS", {
  ["drawlink.label"] = "Drawing",
  ["drawlink.from"] = "From %s",
  ["drawlink.size"] = "%d x %d cells",
  ["drawlink.save"] = "Add to my drawings",
  ["drawlink.saveDone"] = "Added",
  ["drawlink.saved"] = "Drawing added to your drawings.",
  ["drawlink.window"] = "Open as window",
  ["drawlink.windowTip"] = "Opens a small window over the game.\nNeeds the drawing in your list.",
  ["drawlink.edit"] = "Open in editor",
  ["drawlink.editTip"] = "Opens a copy in the editor.\nIt joins your list only when saved.",
  ["drawlink.loading"] = "Requesting the drawing from %s ...",
  ["drawlink.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["drawlink.gone"] = "%s no longer offers it (only until /reload or logout).",
  ["drawlink.badData"] = "The drawing from %s could not be read.",
  ["drawlink.tooLarge"] = "The drawing from %s is too large.",
  ["drawlink.err.tooLarge"] = "Too large to share (%s KB packed, limit 20 KB).\nUse a smaller canvas, fewer colors or no soft edges.",
  ["drawlink.kb"] = "%s KB",
  ["drawlink.v.inline"] = "Chat: inside the link",
  ["drawlink.v.transfer"] = "Chat: transfer, %d parts, about %s s",
  ["drawlink.v.big"] = "Too large to share (over 20 KB)",
  ["drawlink.v.nosave"] = "Too large to save (over 64 KB)",
  ["drawlink.tip.title"] = "Size and chat sharing",
  ["drawlink.tip.inline"] = "Fits into the chat link, works even offline.",
  ["drawlink.tip.transfer"] = "Receiver fetches %d parts (about %s s), stay online.",
  ["drawlink.tip.big"] = "Over 20 KB packed: no chat, saving up to 64 KB.",
  ["drawlink.tip.nosave"] = "Over 64 KB packed: cannot be saved, make it smaller.",
  ["drawlink.tip.limits"] = "Limits: link 0.2 KB, transfer 20 KB, saving 64 KB.",
  ["drawlink.tip.channels"] = "Receiver needs the addon: Say, Party, Raid, Guild, Whisper.",
  ["drawlink.tip.shrink"] = "Smaller canvas, fewer colors, soft edges off.",
  ["drawlink.err.unavailable"] = "Sharing not possible (compression library missing).",
  ["drawlink.err.unreadable"] = "Unreadable drawing, cannot be shared.",
})
ns.AddLocale("deDE", {
  ["drawlink.label"] = "Zeichnung",
  ["drawlink.from"] = "Von %s",
  ["drawlink.size"] = "%d x %d Zellen",
  ["drawlink.save"] = "In meine Zeichnungen übernehmen",
  ["drawlink.saveDone"] = "Übernommen",
  ["drawlink.saved"] = "Zeichnung in deine Zeichnungen übernommen.",
  ["drawlink.window"] = "Als Fenster öffnen",
  ["drawlink.windowTip"] = "Öffnet ein kleines Fenster über dem Spiel.\nErst nach dem Übernehmen möglich.",
  ["drawlink.edit"] = "Im Editor öffnen",
  ["drawlink.editTip"] = "Öffnet eine Kopie im Editor.\nIn die Liste kommt sie erst beim Speichern.",
  ["drawlink.loading"] = "Frage die Zeichnung bei %s an ...",
  ["drawlink.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["drawlink.gone"] = "%s bietet sie nicht mehr an (nur bis /reload oder Logout).",
  ["drawlink.badData"] = "Die Zeichnung von %s konnte nicht gelesen werden.",
  ["drawlink.tooLarge"] = "Die Zeichnung von %s ist zu groß.",
  ["drawlink.err.tooLarge"] = "Zu groß zum Teilen (%s KB gepackt, erlaubt 20 KB).\nKleinere Fläche, weniger Farben oder weiche Kanten aus.",
  ["drawlink.kb"] = "%s KB",
  ["drawlink.v.inline"] = "Chat: direkt im Link",
  ["drawlink.v.transfer"] = "Chat: Übertragung, %d Teile, ca. %s s",
  ["drawlink.v.big"] = "Zu groß zum Teilen (über 20 KB)",
  ["drawlink.v.nosave"] = "Zu groß zum Speichern (über 64 KB)",
  ["drawlink.tip.title"] = "Größe und Teilen im Chat",
  ["drawlink.tip.inline"] = "Passt in den Chat-Link, geht auch offline.",
  ["drawlink.tip.transfer"] = "Empfänger holt %d Teile ab (ca. %s s), bleib online.",
  ["drawlink.tip.big"] = "Über 20 KB gepackt: kein Chat, Speichern bis 64 KB.",
  ["drawlink.tip.nosave"] = "Über 64 KB gepackt: nicht speicherbar, erst verkleinern.",
  ["drawlink.tip.limits"] = "Grenzen: Link 0,2 KB, Übertragung 20 KB, Speichern 64 KB.",
  ["drawlink.tip.channels"] = "Empfänger mit Addon: Sagen, Gruppe, Schlachtzug, Gilde, Flüstern.",
  ["drawlink.tip.shrink"] = "Kleinere Fläche, weniger Farben, weiche Kanten aus.",
  ["drawlink.err.unavailable"] = "Teilen nicht möglich (Kompressionsbibliothek fehlt).",
  ["drawlink.err.unreadable"] = "Zeichnung nicht lesbar, Teilen nicht möglich.",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

-- Size and sharing verdict -----------------------------------------------------------

-- "3.2" in English, "3,2" in German.
local function decimal(value)
  local text = string.format("%.1f", value)
  if ns.GetActiveLocale() == "deDE" then
    text = text:gsub("%.", ",")
  end
  return text
end

-- "3,2" (kilobytes, localized decimal mark) for a number of bytes.
function DL.Kilobytes(bytes)
  return decimal(bytes / 1024)
end

-- "3,2 KB" for a number of bytes.
function DL.SizeText(bytes)
  return fmt("drawlink.kb", DL.Kilobytes(bytes))
end

-- How a picture whose encoded string has `bytes` characters travels. The
-- protocol decides (NoteLink.BuildFor with a stand-in string of that length):
-- tier "inline" (the whole picture is in the chat link), "transfer" (a short
-- reference, the receiver requests the data in chunks; parts and seconds are
-- worked out from NoteLink's chunk size and gap), "big" (over MAX_SHARE, saving
-- still works) or "nosave" (over MAX_ENCODED, not even saving works).
function DL.ShareInfo(bytes, title)
  local info = { bytes = bytes }
  if bytes > D.MAX_ENCODED then
    info.tier = "nosave"
  elseif bytes > D.MAX_SHARE then
    info.tier = "big"
  else
    local built = NL.BuildFor("D", string.rep("0", bytes), string.rep("0", 8), DR.cleanName(title or ""))
    if not built then
      info.tier = "big"
    elseif built.entry then
      info.tier = "transfer"
      info.parts = math.ceil(bytes / NL.CHUNK)
      info.seconds = info.parts * NL.CHUNK_GAP
    else
      info.tier = "inline"
    end
  end
  return info
end

-- Short verdict for the status bar and the lines on the page and in the share
-- dialog, and the color token to draw it in.
function DL.ShareLine(info)
  local tier = info.tier
  if tier == "transfer" then
    return fmt("drawlink.v.transfer", info.parts, decimal(info.seconds)), "textSecondary"
  end
  return L["drawlink.v." .. tier], (tier == "big" or tier == "nosave") and "warning" or "textSecondary"
end

-- The tooltip: the verdict explained, the limits, the channels and a tip.
function DL.ShareTip(info)
  local first
  if info.tier == "transfer" then
    first = fmt("drawlink.tip.transfer", info.parts, decimal(info.seconds))
  else
    first = L["drawlink.tip." .. info.tier]
  end
  return table.concat({ first, L["drawlink.tip.limits"], L["drawlink.tip.channels"], L["drawlink.tip.shrink"] }, "\n")
end

-- Content ----------------------------------------------------------------------------

-- Returns the drawing for a received code, or nil, reason. `hash` (optional) is
-- checked against the received string before it is decoded.
function DL.Decode(code, hash)
  if hash and NL.Hash(code) ~= hash then
    return nil, "hash"
  end
  return D.Decode(code, D.MAX_SHARE)
end

-- Builds the one chat message for a stored drawing (an item of ns.Drawings).
-- Returns { msg, entry } or nil, "tooLarge" | "unavailable" | "unreadable"; a
-- too large picture also returns its packed length.
-- `entry` must be passed to NoteLink.Register once the message was really sent.
function DL.Build(item, mode)
  local drawing, why = DR.load(item.id)
  if not drawing then
    return nil, why == "unavailable" and "unavailable" or "unreadable"
  end
  local code = item.data
  if #code > D.MAX_SHARE then
    return nil, "tooLarge", #code
  end
  return NL.BuildFor("D", code, NL.Hash(code), item.name, mode)
end

-- Viewer -------------------------------------------------------------------------------

local view

local function saveCopy()
  local data = view and view.data
  if not data or data.saved then
    return
  end
  local item, why = DR.add(data.title, data.drawing)
  if not item then
    ns.Notify(
      why == "limit" and fmt("draw.msg.limit", DR.MAX_ITEMS) or L["draw.msg.saveFailed"],
      why == "limit" and "warning" or "error"
    )
    return
  end
  data.saved, data.savedId = true, item.id
  view.save:Disable()
  view.window:Enable()
  W.SetText(view.save.label, "drawlink.saveDone")
  ns.Notify(L["drawlink.saved"], "success")
end

local function openAsWindow()
  local id = view and view.data and view.data.savedId
  if id and DR.get(id) then
    ns.DrawingWindow.Open(id)
  end
end

local function openInEditor()
  local data = view and view.data
  if not data then
    return
  end
  view:Hide()
  ns.DrawingEditor.OpenCopy(data.drawing, data.title)
end

local function build()
  if view then
    return view
  end
  local d = ns.Dialogs.Create("ForeverGuidesDrawingLinkView", 560, 500)
  view = d
  d.author = W.Text(d, { role = "ui", color = "textSecondary" })
  d.author:SetPoint("TOPLEFT", 16, -44)
  d.author:SetPoint("RIGHT", -16, 0)
  d.info = W.Text(d, { role = "micro", color = "textMuted" })
  d.info:SetPoint("TOPLEFT", d.author, "BOTTOMLEFT", 0, -2)
  d.box = CreateFrame("Frame", nil, d)
  d.box:SetPoint("TOPLEFT", 16, -88)
  d.box:SetSize(BOX_W, BOX_H)
  W.Fill(d.box, "surface", 1)
  W.Border(d.box, "white", 0.3)
  d.image = V.New(d.box, { scale = 2 })
  d.image.frame:SetPoint("CENTER")
  d.save = W.Button(d, { key = "drawlink.save", variant = "primary", width = 240, onClick = saveCopy })
  d.save:SetPoint("BOTTOMRIGHT", -16, 14)
  d.window = W.Action(d, {
    label = "act.open",
    icon = "open",
    width = 150,
    tooltip = "drawlink.window",
    tooltipText = "drawlink.windowTip",
    onClick = openAsWindow,
  })
  d.window:SetPoint("BOTTOMRIGHT", d.save, "TOPRIGHT", 0, 6)
  d.edit = W.Action(d, {
    label = "act.edit",
    icon = "pencil",
    width = 150,
    tooltip = "drawlink.edit",
    tooltipText = "drawlink.editTip",
    onClick = openInEditor,
  })
  d.edit:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 100,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.edit, "LEFT", -8, 0)
  d:HookScript("OnHide", function()
    d.image:Clear()
  end)
  return d
end

-- drawing: already decoded and validated. title: from the chat link (untrusted).
function DL.Show(sender, drawing, title)
  local d = build()
  title = DR.cleanName((tostring(title or ""):gsub("|", "")))
  d.data = { sender = sender, title = title, drawing = drawing }
  W.SetText(d.title, nil, title ~= "" and title or L["draw.untitled"])
  W.SetText(d.author, nil, fmt("drawlink.from", sender))
  d.image:SetScale(V.FitScale(drawing.w, drawing.h, BOX_W - 16, BOX_H - 16))
  d.image:SetDrawing(drawing)
  -- A map this client does not know: the sheet shows without it, the line says so.
  local info = fmt("drawlink.size", drawing.w, drawing.h)
  if d.image.mapReason then
    info = info .. "   |   " .. fmt("draw.map.missing", ns.DrawingMap.Describe(drawing.map))
  end
  W.SetText(d.info, nil, info)
  W.SetText(d.save.label, "drawlink.save")
  d.save:Enable()
  d.window:Disable()
  d:Show()
  return d
end

NL.RegisterKind("D", {
  token = DL.TOKEN,
  link = DL.LINK,
  label = "drawlink.label",
  prefix = "drawlink",
  untitled = "draw.untitled",
  decode = function(code, hash)
    local drawing, why = DL.Decode(code, hash)
    if not drawing then
      return nil, why
    end
    return drawing
  end,
  show = function(sender, drawing, title)
    DL.Show(sender, drawing, title)
  end,
})
