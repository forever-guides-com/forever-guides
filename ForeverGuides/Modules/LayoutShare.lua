-- Layout links: a layout of the layout editor (mouse cursor ring, HUD windows, experience bar), one element or one
-- group with all its elements goes into the chat as one short link ("[Layout - Name (12)]") like a note, a drawing
-- or a build (see NoteLink.lua, which carries the protocol: inline payload, reference with addon-message transfer,
-- hash check, limits, consent of function linkShare, snapshots that live until the next reload). This file adds what
-- is specific to layouts: three kinds (L layout, E element, G group), the content is the exchange string of the
-- editor unchanged (LayoutShareLogic.lua builds and reads it), the sender shares from the editor, the dialog of
-- the layouts, the settings pages and the HUD window cards, and the receiver sees a preview first. Nothing changes
-- without a click: the import button hands the string to the import dialog of the open editor, which asks again
-- (name, or paste with one undo step).
local _, ns = ...
local W, L, NL, LSL = ns.W, ns.L, ns.NoteLink, ns.LayoutShareLogic

local LSH = { TOKENS = { L = "FGL", E = "FGE", G = "FGG" }, LINKS = { L = "FGLayout", E = "FGElement", G = "FGGroup" } }
ns.LayoutShare = LSH

local VIEW_W, VIEW_H = 520, 440
local BODY_W = 462

ns.AddLocale("enUS", {
  ["layoutshare.label.layout"] = "Layout",
  ["layoutshare.label.element"] = "Layout element",
  ["layoutshare.label.group"] = "Layout group",
  ["layoutshare.untitled"] = "Layout",
  ["layoutshare.btn"] = "Share in chat",
  ["layoutshare.tip.layout"] = "Shares this layout as a link in the chat you choose. Others with Forever Guides click it, see a preview and import it. Needs sending of chat links in the settings.",
  ["layoutshare.tip.element"] = "Shares this element as a link in the chat you choose (a group with all its elements). Others with Forever Guides click it, see a preview and add it to their layout.",
  ["layoutshare.hint.layout"] = "Sends only a link, not the layout.\nWith Forever Guides one click opens a preview, others see a short code.",
  ["layoutshare.hint.element"] = "Sends only a link, not the element.\nWith Forever Guides one click opens a preview, others see a short code.",
  ["layoutshare.hint.group"] = "Sends only a link, not the group.\nWith Forever Guides one click opens a preview, others see a short code.",
  ["layoutshare.size"] = "%s KB",
  ["layoutshare.err.tooLarge"] = "Too large to share in chat (limit 20 KB).",
  ["layoutshare.err.tooLargeKb"] = "Too large to share in chat (%s KB, limit 20 KB). Remove elements first.",
  ["layoutshare.err.unavailable"] = "Sharing unavailable (compression library missing).",
  ["layoutshare.err.encode"] = "The layout could not be packed for sharing.",
  ["layoutshare.err.missing"] = "There is nothing to share here.",
  ["layoutshare.loading"] = "Requesting the layout data from %s ...",
  ["layoutshare.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["layoutshare.gone"] = "%s no longer shares this (only until /reload or logout).",
  ["layoutshare.badData"] = "The layout data from %s could not be read.",
  ["layoutshare.tooLarge"] = "The layout data from %s is too large.",
  ["layoutshare.wrongType"] = "The link from %s holds another kind of content than its label says (layout, element or group mixed up).",
  ["layoutshare.view.layout"] = "Shared layout",
  ["layoutshare.view.element"] = "Shared element",
  ["layoutshare.view.group"] = "Shared group",
  ["layoutshare.from"] = "From %s",
  ["layoutshare.host.cursor"] = "Mouse cursor ring",
  ["layoutshare.host.area"] = "HUD window",
  ["layoutshare.host.xpbar"] = "Experience bar",
  ["layoutshare.sum.layout"] = 'Layout "%s", %d elements',
  ["layoutshare.sum.group"] = 'Group "%s" with %d elements',
  ["layoutshare.sum.element"] = 'Element "%s"',
  ["layoutshare.more"] = "... and %d more",
  ["layoutshare.noElements"] = "No elements.",
  ["layoutshare.note.layout"] = "Import adds it as a layout of its own, you choose the name. Nothing changes before that.",
  ["layoutshare.note.element"] = "Import adds it to the open layout as one undo step, or as a layout of its own. Nothing changes before that.",
  ["layoutshare.import"] = "Import ...",
  ["layoutshare.importTip"] = "Opens the import dialog of the layout editor with this content. It asks again before anything changes.",
  ["layoutshare.copyText"] = "Copy as text",
  ["layoutshare.copyTextTip"] = "Shows the content as an exchange string you can paste into any layout editor.",
  ["layoutshare.copyTitle"] = "Shared layout as text",
  ["layoutshare.copyHint"] = "Copy with Ctrl+C. The Import button of the layout editor reads it.",
  ["layoutshare.wrongHost"] = "This content is for the %s. Open its layout editor and import it there.",
  ["layoutshare.noEditor"] = "The layout editor of the %s could not be opened.",
})
ns.AddLocale("deDE", {
  ["layoutshare.label.layout"] = "Layout",
  ["layoutshare.label.element"] = "Layout-Element",
  ["layoutshare.label.group"] = "Layout-Gruppe",
  ["layoutshare.untitled"] = "Layout",
  ["layoutshare.btn"] = "Im Chat teilen",
  ["layoutshare.tip.layout"] = "Teilt dieses Layout als Link in den Chat, den du wählst. Andere mit Forever Guides klicken ihn an, sehen eine Vorschau und importieren es. Braucht in den Einstellungen das Senden von Chat-Links.",
  ["layoutshare.tip.element"] = "Teilt dieses Element (eine Gruppe mit allen Unterelementen) als Link in den Chat, den du wählst. Andere mit Forever Guides klicken ihn an, sehen eine Vorschau und fügen es in ihr Layout ein.",
  ["layoutshare.hint.layout"] = "Sendet nur einen Link, nicht das Layout.\nMit Forever Guides öffnet ein Klick eine Vorschau, andere sehen einen kurzen Code.",
  ["layoutshare.hint.element"] = "Sendet nur einen Link, nicht das Element.\nMit Forever Guides öffnet ein Klick eine Vorschau, andere sehen einen kurzen Code.",
  ["layoutshare.hint.group"] = "Sendet nur einen Link, nicht die Gruppe.\nMit Forever Guides öffnet ein Klick eine Vorschau, andere sehen einen kurzen Code.",
  ["layoutshare.size"] = "%s KB",
  ["layoutshare.err.tooLarge"] = "Zu groß zum Teilen im Chat (erlaubt 20 KB).",
  ["layoutshare.err.tooLargeKb"] = "Zu groß zum Teilen im Chat (%s KB, erlaubt 20 KB). Entferne zuerst Elemente.",
  ["layoutshare.err.unavailable"] = "Teilen nicht verfügbar (Kompressionsbibliothek fehlt).",
  ["layoutshare.err.encode"] = "Das Layout ließ sich nicht zum Teilen verpacken.",
  ["layoutshare.err.missing"] = "Hier gibt es nichts zu teilen.",
  ["layoutshare.loading"] = "Frage die Layout-Daten bei %s an ...",
  ["layoutshare.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["layoutshare.gone"] = "%s teilt das nicht mehr (nur bis /reload oder Logout).",
  ["layoutshare.badData"] = "Die Layout-Daten von %s konnten nicht gelesen werden.",
  ["layoutshare.tooLarge"] = "Die Layout-Daten von %s sind zu groß.",
  ["layoutshare.wrongType"] = "Der Link von %s enthält etwas anderes, als seine Beschriftung sagt (Layout, Element oder Gruppe verwechselt).",
  ["layoutshare.view.layout"] = "Geteiltes Layout",
  ["layoutshare.view.element"] = "Geteiltes Element",
  ["layoutshare.view.group"] = "Geteilte Gruppe",
  ["layoutshare.from"] = "Von %s",
  ["layoutshare.host.cursor"] = "Mauszeiger-Ring",
  ["layoutshare.host.area"] = "HUD-Fenster",
  ["layoutshare.host.xpbar"] = "Erfahrungsleiste",
  ["layoutshare.sum.layout"] = 'Layout "%s", %d Elemente',
  ["layoutshare.sum.group"] = 'Gruppe "%s" mit %d Elementen',
  ["layoutshare.sum.element"] = 'Element "%s"',
  ["layoutshare.more"] = "... und %d weitere",
  ["layoutshare.noElements"] = "Keine Elemente.",
  ["layoutshare.note.layout"] = "Der Import legt es als eigenes Layout an, den Namen wählst du. Vorher ändert sich nichts.",
  ["layoutshare.note.element"] = "Der Import fügt es als ein Rückgängig-Schritt in das offene Layout ein oder legt es als eigenes Layout an. Vorher ändert sich nichts.",
  ["layoutshare.import"] = "Importieren ...",
  ["layoutshare.importTip"] = "Öffnet den Import-Dialog des Layout-Editors mit diesem Inhalt. Vor jeder Änderung fragt er noch einmal.",
  ["layoutshare.copyText"] = "Als Text kopieren",
  ["layoutshare.copyTextTip"] = "Zeigt den Inhalt als Austauschtext, den du in jeden Layout-Editor einfügen kannst.",
  ["layoutshare.copyTitle"] = "Geteiltes Layout als Text",
  ["layoutshare.copyHint"] = "Mit Strg+C kopieren. Der Import-Knopf des Layout-Editors liest ihn.",
  ["layoutshare.wrongHost"] = "Dieser Inhalt ist für: %s. Öffne dessen Layout-Editor und importiere ihn dort.",
  ["layoutshare.noEditor"] = "Der Layout-Editor für %s ließ sich nicht öffnen.",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

local function hostName(host)
  local key = "layoutshare.host." .. tostring(host)
  return L[key] ~= key and L[key] or tostring(host)
end

-- Sending ------------------------------------------------------------------------------------------------------

-- Opens the share dialog with the link message for an exchange string and its summary (LayoutShareLogic.Build*), or
-- with the reason when there is nothing to send. The dialog keeps the link back while the send consent is off.
local function offer(code, info, why, size, kind)
  local built
  if code then
    built, why = NL.BuildFor(info.letter, code, NL.Hash(code), LSL.Title(info))
    size = #code
  end
  built = built or { err = why == "too-large" and "tooLarge" or why }
  kind = info and LSL.TypeOf(info.letter) or kind
  if size then
    built.sizeLine = fmt("layoutshare.size", string.format("%.1f", size / 1024))
  end
  if built.err == "tooLarge" and size then
    built.errText = fmt("layoutshare.err.tooLargeKb", string.format("%.1f", size / 1024))
  end
  return ns.Share.OpenLink(built, "layoutshare.hint." .. kind, "layoutshare.err.")
end

-- `layout` is a layout table (the working copy of the editor or a stored one), `host` the display it belongs to.
function LSH.ShareLayout(layout, host)
  if not ns.LibDeflate then
    return offer(nil, nil, "unavailable", nil, "layout")
  end
  local code, info, size = LSL.BuildLayout(layout, host)
  return offer(code, code and info or nil, not code and info or nil, size, "layout")
end

-- One element (a table of `layout` or its id), with all its elements when it is a group.
function LSH.ShareElement(layout, ref, host)
  if not ns.LibDeflate then
    return offer(nil, nil, "unavailable", nil, "element")
  end
  local code, info, size = LSL.BuildElement(layout, ref, host)
  return offer(code, code and info or nil, not code and info or nil, size, "element")
end

-- Receiving ----------------------------------------------------------------------------------------------------

-- Opens the editor that draws `host` so a string can be imported into it. Returns whether an editor is open now.
local OPENERS = {
  cursor = function()
    if ns.Cursor and ns.Cursor.Edit then
      ns.Cursor.Edit()
    end
  end,
  area = function()
    local areas = ns.Areas
    local id = areas and areas.Ids and areas.Ids()[1]
    if id then
      areas.Edit(id)
    end
  end,
  xpbar = function()
    if ns.XpBar and ns.XpBar.Edit then
      ns.XpBar.Edit()
    end
  end,
}

-- A string the editor of `host` can take: the open editor must be the right one. Elements fit the ring and the HUD
-- windows alike, so any open editor of those two takes them.
local function importInto(data)
  local CE = ns.CanvasEditor
  local read, host = data.read, data.info.host
  local open = CE and CE.IsOpen and CE.IsOpen()
  if open and not LSL.FitsHost(read, CE.Host()) then
    ns.Notify(fmt("layoutshare.wrongHost", hostName(host)), "warning")
    return false
  end
  if not open then
    local opener = OPENERS[host]
    if opener then
      opener()
    end
    open = CE and CE.IsOpen and CE.IsOpen()
    if not open then
      ns.Notify(fmt("layoutshare.noEditor", hostName(host)), "warning")
      return false
    end
  end
  CE.ImportText(data.code)
  return true
end

local view

local function structureText(info)
  if #info.lines == 0 then
    return L["layoutshare.noElements"]
  end
  local rows = {}
  for i, line in ipairs(info.lines) do
    rows[i] = string.rep("    ", line.depth) .. "- " .. line.name
  end
  if info.more > 0 then
    rows[#rows + 1] = fmt("layoutshare.more", info.more)
  end
  return table.concat(rows, "\n")
end

local function build()
  if view then
    return view
  end
  local d = ns.Dialogs.Create("ForeverGuidesLayoutShareView", VIEW_W, VIEW_H)
  view = d
  d.author = W.Text(d, { role = "ui", color = "textSecondary" })
  d.author:SetPoint("TOPLEFT", 16, -44)
  d.author:SetPoint("RIGHT", -16, 0)
  d.summary = W.Text(d, { role = "ui", color = "text", wrap = true })
  d.summary:SetPoint("TOPLEFT", d.author, "BOTTOMLEFT", 0, -4)
  d.summary:SetPoint("RIGHT", -16, 0)
  d.area = W.ScrollArea(d)
  d.area:SetPoint("TOPLEFT", 16, -96)
  d.area:SetPoint("BOTTOMRIGHT", -16, 112)
  W.Fill(d.area, "surface", 1)
  d.body = W.Text(d.area.content, { role = "text", wrap = true })
  d.body:SetPoint("TOPLEFT", 6, -6)
  d.note = W.Text(d, { role = "small", color = "textSecondary", wrap = true })
  d.note:SetPoint("BOTTOMLEFT", 16, 56)
  d.note:SetPoint("RIGHT", -16, 0)
  d.import = W.Action(d, {
    label = "layoutshare.import",
    icon = "import",
    variant = "primary",
    width = 160,
    tooltip = "layoutshare.import",
    tooltipText = "layoutshare.importTip",
    opens = true,
    onClick = function()
      if d.data and importInto(d.data) then
        d:Hide()
      end
    end,
  })
  d.import:SetPoint("BOTTOMRIGHT", -16, 14)
  d.copy = W.Action(d, {
    label = "layoutshare.copyText",
    icon = "export",
    width = 150,
    tooltip = "layoutshare.copyText",
    tooltipText = "layoutshare.copyTextTip",
    opens = true,
    onClick = function()
      if d.data then
        ns.Dialogs.Copy("layoutshare.copyTitle", d.data.code, "layoutshare.copyHint")
      end
    end,
  })
  d.copy:SetPoint("RIGHT", d.import, "LEFT", -8, 0)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 100,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.copy, "LEFT", -8, 0)
  return d
end

-- data: { read, info, code }, already decoded and validated; nothing is added anywhere before the import button.
function LSH.Show(sender, data)
  local d = build()
  d.data = data
  local info = data.info
  W.SetText(d.title, "layoutshare.view." .. info.kind)
  W.SetText(d.author, nil, fmt("layoutshare.from", sender) .. "  ·  " .. hostName(info.host))
  local name = info.name ~= "" and info.name or L["layoutshare.untitled"]
  if info.kind == "element" then
    W.SetText(d.summary, nil, fmt("layoutshare.sum.element", name))
  else
    W.SetText(d.summary, nil, fmt("layoutshare.sum." .. info.kind, name, info.count))
  end
  d.body:SetWidth(BODY_W)
  W.SetText(d.body, nil, structureText(info))
  d.area:SetContentHeight(d.body:GetStringHeight() + 16)
  d.area:ScrollTo(0)
  W.SetText(d.note, "layoutshare.note." .. (info.kind == "layout" and "layout" or "element"))
  d:Show()
  return d
end

local function register(letter, kind)
  NL.RegisterKind(letter, {
    token = LSH.TOKENS[letter],
    link = LSH.LINKS[letter],
    label = "layoutshare.label." .. kind,
    prefix = "layoutshare",
    untitled = "layoutshare.untitled",
    wrongType = true,
    decode = function(code, hash)
      if hash and NL.Hash(code) ~= hash then
        return nil, "hash"
      end
      local read, why = LSL.Read(code, letter)
      if not read then
        return nil, why
      end
      return { read = read, info = LSL.Describe(read), code = code }
    end,
    show = function(sender, result)
      LSH.Show(sender, result)
    end,
  })
end

register(LSL.KIND_LAYOUT, "layout")
register(LSL.KIND_ELEMENT, "element")
register(LSL.KIND_GROUP, "group")
