-- The window of the reusable layout editor (ns.CanvasEditor): a preview of a canvas layout drawn by
-- CanvasRender (the host's own render functions), elements to select, drag and resize, a side panel
-- for position, anchor and the panel of the element type, canvas settings, undo, templates, exchange
-- strings. It edits a working copy: Apply hands it to the host, Discard throws it away. The model
-- and every calculation live in CanvasLogic.lua, the property controls in CanvasEditorControls.lua.
--
--   CanvasEditor.Open({
--     title = "text",                       window title (default: the editor title)
--     layout = layout,                      the layout to edit (any table, repaired by CanvasLogic.Validate)
--     types = { [type] = { label, new(), size = { w, h }, max, render(frame, element, ctx),
--                          panel(parent, element, onChange), textColor(element) -> "rrggbb" } },
--     presets = { { id, name, layout } },   templates of the "Template" dropdown (optional)
--     ctx = { values = fn(token) },         passed to every render (the real values)
--     sample = fn(token),                   sample values for the preview (optional)
--     onApply(layout), onCancel(),          Apply (and Live) hand over a clean copy
--     manager = {                           layouts of the host (optional, every function optional)
--       list() -> { { id, name } },         current() -> id,        select(id) -> layout copy | nil
--       save(id, layout),                   create(name, layout) -> id | nil, reason
--       rename(id, name) -> ok,             delete(id) -> ok,       canDelete(id) -> boolean
--       import(name, layout) -> id | nil, reason },
--     host = "xpbar" | "cursor",            names the display for export and import (default: by canvas kind)
--     sim = table,                          simulation state the host owns; reaches every render as ctx.sim
--     tools = { { id, label, icon, toggle, active?, onClick(active) } },
--                                           toggle buttons in the view bar (at most CE.MAX_TOOLS); a click only
--                                           redraws: no undo step, the layout stays clean
--     liveTest = function(active),          "Test at real cursor": the editor only calls it (and with false on close)
--     stage = { marker = { texture | atlas, tipX, tipY, size },
--               backdrops = { { id, label, color | texture, color2? } } },
--                                           cursor image at the hotspot over the elements (preview only) and a
--                                           backdrop selector (default list: CE.BACKDROPS)
--   })
-- A canvas of kind "cursor" (CanvasLogic: canvas.kind, hotX, hotY, symmetric) previews at its true screen size
-- (zoom 100 percent, CE.REAL_ZOOMS) and edits the hotspot in the canvas section.
-- CanvasEditor.Redraw() redraws the preview without an undo step.
-- With a manager the band under the title holds the list of all layouts (right, as wide as the
-- sidebar): a click or Enter switches, each row renames, duplicates and deletes, "New" adds a copy of
-- the working copy; Save and Save as new sit left in the band, Import adds a layout. A function the
-- host leaves out hides its control (the list needs list and select). Switching selects the layout
-- through the host and hands the host the new working copy with Live. The sidebar starts with the
-- elements.
--   CanvasEditor.Close() discards without a question, IsOpen(), Frame(), Layout() copy of the working
--   layout, Selected() id, Select(id), Apply(), Discard(force).
--
-- panel(parent, element, onChange) returns a frame; the editor calls onChange() after the panel changed
-- element.props. A frame with a Refresh(element) method is built once and reused for every element of
-- the type, one without is built again for each selection (frames cannot be freed).
-- The size of the window is fixed, all positions are explicit.
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle
local CL, CR = ns.CanvasLogic, ns.CanvasRender

local CE = ns.CanvasEditor or {}
ns.CanvasEditor = CE
local Controls = CE.Controls

local WIN_W, WIN_H, HEAD_H, PAD = 880, 600, 22, 8
local ROW_H = 24
-- The band under the title: tools, Export, Import and presets on the left, the layout list on the right.
local LAYOUT_ROWS, LAYOUT_HEAD_H = 3, 22
local BAND_Y, BAND_H = HEAD_H + 4, LAYOUT_HEAD_H + LAYOUT_ROWS * ROW_H
local BODY_Y = BAND_Y + BAND_H + 6
local FOOT_H = 40
local BODY_H = WIN_H - BODY_Y - FOOT_H - 4
local RIGHT_W = 300
local LEFT_W = WIN_W - PAD * 3 - RIGHT_W
local VIEWBAR_H = 46
local VIEW_H = BODY_H - VIEWBAR_H - 6
local ELEMENT_ROWS = 5
-- Height of the heading row of the Elements section (the Add button sits in it).
local ELEMENTS_HEAD_H = 22
-- Band controls: icon buttons, the gap between them, and Export and Import side by side in row 2.
local TOOL_SIZE, TOOL_GAP = 24, 5
local XFER_W, XFER_GAP, ROW2_Y = 100, 6, TOOL_SIZE + 4
local DROP_W = 160
local BACKDROP_W = 110
local CONTENT_W = RIGHT_W - 16
local REMOVE_W = 176
-- Wrapped rows of a type panel are measured at this width.
Controls.PANEL_WIDTH = CONTENT_W
local HALF_W = (CONTENT_W - 8) / 2
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local HANDLE_SIZE, HANDLE_HIT = 7, 7
-- Canvas handles: a frame the mouse can grab, with the visible square inside.
local CANVAS_HANDLE_FRAME = 13
local DRAG_MIN = 3
local MIN_ELEMENT = 4
local MAX_GRID_LINES = 150
local MIN_CONTRAST = 4.5
-- Smallest height of a wrapped note in the side panel (two lines of text).
local WARN_MIN_H = 28

CE.ZOOMS = { 1, 2, 3, 4 }
-- Zoom steps of a cursor canvas: 100 percent is the true size on the screen.
CE.REAL_ZOOMS = { 0.5, 1, 2, 3, 4 }
-- Backdrops of the preview for a stage without a list of its own; color plus color2 make a checker.
CE.BACKDROPS = {
  { id = "dark", label = "canvas.backdrop.dark", color = "1a1a1a" },
  { id = "mid", label = "canvas.backdrop.mid", color = "808080" },
  { id = "light", label = "canvas.backdrop.light", color = "e6e6e6" },
  { id = "checker", label = "canvas.backdrop.checker", color = "5a5a5a", color2 = "a6a6a6" },
}
CE.MAX_TOOLS = 4
local CHECKER_CELL = 32
CE.SNAPS = { 0, 1, 5, 10 }
CE.WIDTH, CE.HEIGHT = WIN_W, WIN_H

local HANDLES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_TEXT = {
  TOPLEFT = "canvas.point.topleft",
  TOP = "canvas.point.top",
  TOPRIGHT = "canvas.point.topright",
  LEFT = "canvas.point.left",
  CENTER = "canvas.point.center",
  RIGHT = "canvas.point.right",
  BOTTOMLEFT = "canvas.point.bottomleft",
  BOTTOM = "canvas.point.bottom",
  BOTTOMRIGHT = "canvas.point.bottomright",
}

ns.AddLocale("enUS", {
  ["canvas.title"] = "Layout editor",
  ["canvas.preset"] = "Template",
  ["canvas.presetPick"] = "Choose...",
  ["canvas.reset"] = "Reset to template",
  ["canvas.resetTip"] = "Replaces the layout with the template it started from. Undo brings it back.",
  ["canvas.add"] = "Add element",
  ["canvas.addPick"] = "Add...",
  ["canvas.addShort"] = "Add",
  ["canvas.elementsEmpty"] = "Click Add to place the first element.",
  ["canvas.addMax"] = "This element can only be added once.",
  ["canvas.addLimit"] = "The layout holds at most %d elements.",
  ["canvas.zoom"] = "Zoom",
  ["canvas.snap"] = "Snap",
  ["canvas.snapOff"] = "Off",
  ["canvas.snapPx"] = "%d px",
  ["canvas.grid"] = "Show grid",
  ["canvas.real"] = "Real values",
  ["canvas.realTip"] = "Shows your real values in the preview instead of sample values.",
  ["canvas.live"] = "Live",
  ["canvas.liveTip"] = "Every change shows in the real window at once. Apply keeps it, Discard takes it back.",
  ["canvas.discard"] = "Discard",
  ["canvas.close"] = "Close",
  ["canvas.discardTip"] = "Closes the editor without applying the changes.",
  ["canvas.discardTitle"] = "Discard changes",
  ["canvas.discardAsk"] = "Discard all changes since the last Apply?",
  ["canvas.elements"] = "Elements",
  ["canvas.visible"] = "Show or hide this element",
  ["canvas.forward"] = "Move forward",
  ["canvas.backward"] = "Move back",
  ["canvas.selected"] = "Selected element",
  ["canvas.selectedTitle"] = "Selected: %s",
  ["canvas.removeElement"] = "Remove element",
  ["canvas.removeTip"] = "Removes this element from the layout. Ctrl+Z brings it back.",
  ["canvas.removeRowTip"] = "Removes this element. Ctrl+Z brings it back.",
  ["canvas.renameElementTip"] = "Gives this element another name. F2 does the same for the selected element.",
  ["canvas.nameTip"] = "The name shown in the list. Leave it empty for the default name.",
  ["canvas.msg.removed"] = "Element removed. Ctrl+Z undoes it.",
  ["canvas.name"] = "Name",
  ["canvas.anchor"] = "Anchor",
  ["canvas.point.topleft"] = "Anchor: top left",
  ["canvas.point.top"] = "Anchor: top",
  ["canvas.point.topright"] = "Anchor: top right",
  ["canvas.point.left"] = "Anchor: left",
  ["canvas.point.center"] = "Anchor: center",
  ["canvas.point.right"] = "Anchor: right",
  ["canvas.point.bottomleft"] = "Anchor: bottom left",
  ["canvas.point.bottom"] = "Anchor: bottom",
  ["canvas.point.bottomright"] = "Anchor: bottom right",
  ["canvas.field.x"] = "X",
  ["canvas.field.y"] = "Y",
  ["canvas.field.w"] = "W",
  ["canvas.field.h"] = "H",
  ["canvas.field.xTip"] = "Distance from the anchor to the right, negative to the left.",
  ["canvas.field.yTip"] = "Distance from the anchor upward, negative downward.",
  ["canvas.field.wTip"] = "Width in pixels. 0 means automatic.",
  ["canvas.field.hTip"] = "Height in pixels.",
  ["canvas.elementSettings"] = "Element settings",
  ["canvas.nothing"] = "Nothing selected. Click an element in the preview or in the list.",
  ["canvas.contrast"] = "Text and background reach only %s:1, 4.5:1 is needed.",
  ["canvas.settings"] = "Canvas",
  ["canvas.cw"] = "Width",
  ["canvas.ch"] = "Height",
  ["canvas.bg"] = "Background",
  ["canvas.bgAlpha"] = "Background opacity",
  ["canvas.border"] = "Border",
  ["canvas.borderColor"] = "Border color",
  ["canvas.borderAlpha"] = "Border opacity",
  ["canvas.resizeHandle"] = "Drag to change the size of the canvas.",
  ["canvas.hotX"] = "Hotspot X",
  ["canvas.hotY"] = "Hotspot Y",
  ["canvas.hotTip"] = "The point of the canvas that sits on the mouse cursor, in percent of the canvas. 50 is the center.",
  ["canvas.symmetric"] = "Symmetric around the hotspot",
  ["canvas.symmetricTip"] = "Keeps the hotspot in the center. Resizing the canvas moves both edges, so the center stays where it is.",
  ["canvas.backdrop"] = "Backdrop",
  ["canvas.backdrop.dark"] = "Dark",
  ["canvas.backdrop.mid"] = "Medium",
  ["canvas.backdrop.light"] = "Light",
  ["canvas.backdrop.checker"] = "Checkered",
  ["canvas.liveTest"] = "Test at real cursor",
  ["canvas.liveTestTip"] = "Shows the layout at your real mouse cursor while the editor is open.",
  ["canvas.layouts"] = "Layouts",
  ["canvas.newTip"] = "Creates a new layout as a copy of the one you are editing.",
  ["canvas.layoutOpenTip"] = "Click to switch to this layout. Unsaved changes are asked about first.",
  ["canvas.layoutCurrentTip"] = "This layout is open.",
  ["canvas.layoutDirtyTip"] = "This layout is open and has unsaved changes.",
  ["canvas.saveTip"] = "Saves the layout under its name.",
  ["canvas.saveAs"] = "Save as new",
  ["canvas.saveAsTip"] = "Saves a copy under a new name and switches to it.",
  ["canvas.renameTip"] = "Gives this layout another name.",
  ["canvas.dupTip"] = "Makes a copy of this layout and switches to it.",
  ["canvas.deleteTip"] = "Deletes this layout. The last layout cannot be deleted.",
  ["canvas.deleteTitle"] = "Delete layout",
  ["canvas.deleteAsk"] = "Delete this layout for good? Export it first if you want to keep it.",
  ["canvas.name.label"] = "Name",
  ["canvas.name.newTitle"] = "Save as new layout",
  ["canvas.name.renameTitle"] = "Rename layout",
  ["canvas.name.importTitle"] = "Name of the imported layout",
  ["canvas.name.create"] = "Create",
  ["canvas.name.importDefault"] = "Imported",
  ["canvas.switch.title"] = "Unsaved changes",
  ["canvas.switch.text"] = "This layout has changes that are not saved. Save them before you switch?",
  ["canvas.switch.discard"] = "Discard changes",
  ["canvas.err"] = "The layout could not be changed.",
  ["canvas.err.name"] = "Enter a name for the layout.",
  ["canvas.err.limit"] = "There are too many layouts. Delete one first.",
  ["canvas.err.last"] = "The last layout cannot be deleted.",
  ["canvas.err.missing"] = "This layout does not exist any more.",
  ["canvas.msg.saved"] = "Layout saved.",
  ["canvas.export.title"] = "Export layout",
  ["canvas.export.hint"] = "Copy with Ctrl+C, Import reads it back.",
  ["canvas.export.fail"] = "The layout could not be exported.",
  ["canvas.import.title"] = "Import layout",
  ["canvas.import.hint"] = "Paste an exported layout.\nNothing changes until you press Import.",
  ["canvas.import.paste"] = "Exchange string",
  ["canvas.import.do"] = "Reads the pasted layout into the editor.",
  ["canvas.import.empty"] = "Paste an exchange string above.",
  ["canvas.import.ok"] = "Layout found with %d element(s). Import replaces the current one.",
  ["canvas.import.okNew"] = "Layout found with %d element(s). Import adds it as a new layout.",
  ["canvas.import.err.empty"] = "Paste an exchange string above.",
  ["canvas.import.err.too-large"] = "The text is too long to be a layout.",
  ["canvas.import.err.decode"] = "This is not a valid exchange string.",
  ["canvas.import.err.json"] = "The data inside is damaged.",
  ["canvas.import.err.shape"] = "The data is not a layout.",
  ["canvas.import.err.type"] = "This exchange string is not a layout.",
  ["canvas.import.err.version"] = "This layout comes from a newer version of the addon.",
  ["canvas.import.err.host"] = "This layout belongs to another display.",
  ["canvas.msg.imported"] = "Layout imported, %d value(s) repaired.",
  ["canvas.help.title"] = "Keyboard",
  ["canvas.help.keys"] = "Arrow keys move the element by 1 px, with Shift by 10 px.\nDelete removes it, F2 renames it, Ctrl+D duplicates it.\nCtrl+Z undoes, Ctrl+Y redoes.\nTab selects the next element, Shift+Tab the previous one.\nCtrl+Tab walks through the buttons, Enter presses one.\nThe mouse wheel zooms the preview, dragging the empty area moves a large one.",
})
ns.AddLocale("deDE", {
  ["canvas.title"] = "Layout-Editor",
  ["canvas.preset"] = "Vorlage",
  ["canvas.presetPick"] = "Wählen...",
  ["canvas.reset"] = "Auf Vorlage zurücksetzen",
  ["canvas.resetTip"] = "Ersetzt das Layout durch die Vorlage, mit der es begonnen hat. Rückgängig holt es zurück.",
  ["canvas.add"] = "Element hinzufügen",
  ["canvas.addPick"] = "Hinzufügen...",
  ["canvas.addShort"] = "Hinzufügen",
  ["canvas.elementsEmpty"] = "Mit Hinzufügen das erste Element platzieren.",
  ["canvas.addMax"] = "Dieses Element lässt sich nur einmal hinzufügen.",
  ["canvas.addLimit"] = "Ein Layout enthält höchstens %d Elemente.",
  ["canvas.zoom"] = "Zoom",
  ["canvas.snap"] = "Fangen",
  ["canvas.snapOff"] = "Aus",
  ["canvas.snapPx"] = "%d px",
  ["canvas.grid"] = "Raster zeigen",
  ["canvas.real"] = "Echte Werte",
  ["canvas.realTip"] = "Zeigt in der Vorschau deine echten Werte statt der Beispielwerte.",
  ["canvas.live"] = "Live",
  ["canvas.liveTip"] = "Jede Änderung erscheint sofort im echten Fenster. Übernehmen behält sie, Verwerfen nimmt sie zurück.",
  ["canvas.discard"] = "Verwerfen",
  ["canvas.close"] = "Schließen",
  ["canvas.discardTip"] = "Schließt den Editor ohne die Änderungen zu übernehmen.",
  ["canvas.discardTitle"] = "Änderungen verwerfen",
  ["canvas.discardAsk"] = "Alle Änderungen seit dem letzten Übernehmen verwerfen?",
  ["canvas.elements"] = "Elemente",
  ["canvas.visible"] = "Dieses Element zeigen oder verbergen",
  ["canvas.forward"] = "Nach vorne",
  ["canvas.backward"] = "Nach hinten",
  ["canvas.selected"] = "Gewähltes Element",
  ["canvas.selectedTitle"] = "Gewählt: %s",
  ["canvas.removeElement"] = "Element entfernen",
  ["canvas.removeTip"] = "Entfernt dieses Element aus dem Layout. Strg+Z holt es zurück.",
  ["canvas.removeRowTip"] = "Entfernt dieses Element. Strg+Z holt es zurück.",
  ["canvas.renameElementTip"] = "Gibt diesem Element einen anderen Namen. F2 macht das Gleiche für das gewählte Element.",
  ["canvas.nameTip"] = "Der Name in der Liste. Leer lassen für den Standardnamen.",
  ["canvas.msg.removed"] = "Element entfernt. Strg+Z macht es rückgängig.",
  ["canvas.name"] = "Name",
  ["canvas.anchor"] = "Anker",
  ["canvas.point.topleft"] = "Anker: oben links",
  ["canvas.point.top"] = "Anker: oben",
  ["canvas.point.topright"] = "Anker: oben rechts",
  ["canvas.point.left"] = "Anker: links",
  ["canvas.point.center"] = "Anker: Mitte",
  ["canvas.point.right"] = "Anker: rechts",
  ["canvas.point.bottomleft"] = "Anker: unten links",
  ["canvas.point.bottom"] = "Anker: unten",
  ["canvas.point.bottomright"] = "Anker: unten rechts",
  ["canvas.field.x"] = "X",
  ["canvas.field.y"] = "Y",
  ["canvas.field.w"] = "B",
  ["canvas.field.h"] = "H",
  ["canvas.field.xTip"] = "Abstand vom Anker nach rechts, negativ nach links.",
  ["canvas.field.yTip"] = "Abstand vom Anker nach oben, negativ nach unten.",
  ["canvas.field.wTip"] = "Breite in Pixeln. 0 bedeutet automatisch.",
  ["canvas.field.hTip"] = "Höhe in Pixeln.",
  ["canvas.elementSettings"] = "Element-Einstellungen",
  ["canvas.nothing"] = "Nichts gewählt. Klicke ein Element in der Vorschau oder in der Liste an.",
  ["canvas.contrast"] = "Text und Hintergrund erreichen nur %s:1, nötig sind 4,5:1.",
  ["canvas.settings"] = "Leinwand",
  ["canvas.cw"] = "Breite",
  ["canvas.ch"] = "Höhe",
  ["canvas.bg"] = "Hintergrund",
  ["canvas.bgAlpha"] = "Deckkraft des Hintergrunds",
  ["canvas.border"] = "Rand",
  ["canvas.borderColor"] = "Randfarbe",
  ["canvas.borderAlpha"] = "Deckkraft des Rands",
  ["canvas.resizeHandle"] = "Ziehen ändert die Größe der Leinwand.",
  ["canvas.hotX"] = "Fokus X",
  ["canvas.hotY"] = "Fokus Y",
  ["canvas.hotTip"] = "Der Punkt der Leinwand, der auf dem Mauszeiger liegt, in Prozent der Leinwand. 50 ist die Mitte.",
  ["canvas.symmetric"] = "Symmetrisch um den Fokus",
  ["canvas.symmetricTip"] = "Hält den Fokus in der Mitte. Ändert man die Größe der Leinwand, wandern beide Ränder, die Mitte bleibt also stehen.",
  ["canvas.backdrop"] = "Hintergrund",
  ["canvas.backdrop.dark"] = "Dunkel",
  ["canvas.backdrop.mid"] = "Mittel",
  ["canvas.backdrop.light"] = "Hell",
  ["canvas.backdrop.checker"] = "Karo",
  ["canvas.liveTest"] = "Am echten Cursor",
  ["canvas.liveTestTip"] = "Zeigt das Layout an deinem echten Mauszeiger, solange der Editor offen ist.",
  ["canvas.layouts"] = "Layouts",
  ["canvas.newTip"] = "Legt ein neues Layout als Kopie des Layouts an, das du gerade bearbeitest.",
  ["canvas.layoutOpenTip"] = "Klicken wechselt zu diesem Layout. Bei ungespeicherten Änderungen wird vorher gefragt.",
  ["canvas.layoutCurrentTip"] = "Dieses Layout ist geöffnet.",
  ["canvas.layoutDirtyTip"] = "Dieses Layout ist geöffnet und hat ungespeicherte Änderungen.",
  ["canvas.saveTip"] = "Speichert das Layout unter seinem Namen.",
  ["canvas.saveAs"] = "Als neu speichern",
  ["canvas.saveAsTip"] = "Speichert eine Kopie unter einem neuen Namen und wechselt dorthin.",
  ["canvas.renameTip"] = "Gibt diesem Layout einen anderen Namen.",
  ["canvas.dupTip"] = "Macht eine Kopie dieses Layouts und wechselt dorthin.",
  ["canvas.deleteTip"] = "Löscht dieses Layout. Das letzte Layout lässt sich nicht löschen.",
  ["canvas.deleteTitle"] = "Layout löschen",
  ["canvas.deleteAsk"] = "Dieses Layout endgültig löschen? Exportiere es vorher, wenn du es behalten willst.",
  ["canvas.name.label"] = "Name",
  ["canvas.name.newTitle"] = "Als neues Layout speichern",
  ["canvas.name.renameTitle"] = "Layout umbenennen",
  ["canvas.name.importTitle"] = "Name des importierten Layouts",
  ["canvas.name.create"] = "Anlegen",
  ["canvas.name.importDefault"] = "Importiert",
  ["canvas.switch.title"] = "Ungespeicherte Änderungen",
  ["canvas.switch.text"] = "Dieses Layout hat Änderungen, die nicht gespeichert sind. Vor dem Wechsel speichern?",
  ["canvas.switch.discard"] = "Änderungen verwerfen",
  ["canvas.err"] = "Das Layout ließ sich nicht ändern.",
  ["canvas.err.name"] = "Gib dem Layout einen Namen.",
  ["canvas.err.limit"] = "Es gibt zu viele Layouts. Lösche zuerst eines.",
  ["canvas.err.last"] = "Das letzte Layout lässt sich nicht löschen.",
  ["canvas.err.missing"] = "Dieses Layout gibt es nicht mehr.",
  ["canvas.msg.saved"] = "Layout gespeichert.",
  ["canvas.export.title"] = "Layout exportieren",
  ["canvas.export.hint"] = "Mit Strg+C kopieren, Importieren liest es wieder ein.",
  ["canvas.export.fail"] = "Das Layout ließ sich nicht exportieren.",
  ["canvas.import.title"] = "Layout importieren",
  ["canvas.import.hint"] = "Füge ein exportiertes Layout ein.\nErst Importieren ändert etwas.",
  ["canvas.import.paste"] = "Austausch-String",
  ["canvas.import.do"] = "Liest das eingefügte Layout in den Editor ein.",
  ["canvas.import.empty"] = "Füge oben einen Austausch-String ein.",
  ["canvas.import.ok"] = "Layout mit %d Element(en) gefunden. Importieren ersetzt das aktuelle.",
  ["canvas.import.okNew"] = "Layout mit %d Element(en) gefunden. Importieren legt es als neues Layout an.",
  ["canvas.import.err.empty"] = "Füge oben einen Austausch-String ein.",
  ["canvas.import.err.too-large"] = "Der Text ist zu lang für ein Layout.",
  ["canvas.import.err.decode"] = "Das ist kein gültiger Austausch-String.",
  ["canvas.import.err.json"] = "Die Daten darin sind beschädigt.",
  ["canvas.import.err.shape"] = "Die Daten sind kein Layout.",
  ["canvas.import.err.type"] = "Dieser Austausch-String ist kein Layout.",
  ["canvas.import.err.version"] = "Dieses Layout stammt aus einer neueren Version des Addons.",
  ["canvas.import.err.host"] = "Dieses Layout gehört zu einer anderen Anzeige.",
  ["canvas.msg.imported"] = "Layout importiert, %d Wert(e) repariert.",
  ["canvas.help.title"] = "Tastatur",
  ["canvas.help.keys"] = "Pfeiltasten verschieben das Element um 1 px, mit Umschalt um 10 px.\nEntf löscht es, F2 benennt es um, Strg+D dupliziert es.\nStrg+Z macht rückgängig, Strg+Y stellt wieder her.\nTab wählt das nächste Element, Umschalt+Tab das vorige.\nStrg+Tab geht durch die Knöpfe, Enter drückt einen.\nDas Mausrad zoomt die Vorschau, Ziehen im leeren Bereich verschiebt eine große.",
})

-- State ----------------------------------------------------------------------------------------

-- The open session: opts, work (layout), base (state at the last Apply), hist, sel (element id), zoom,
-- snap, grid, live, real, panX, panY, drag, guides, lastSent, measure.
local S
local frame, ui

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.canvaseditor) ~= "table" then
    frames.canvaseditor = {}
  end
  return frames.canvaseditor
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

local function equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not equal(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

local function sel()
  if S and S.sel then
    return CL.Find(S.work, S.sel)
  end
end

local function isDirty()
  return S ~= nil and not equal(S.base, S.work)
end

local function snapStep()
  return S.snap > 0 and S.snap or 0
end

local function noteFail(key, ...)
  ns.Notify(string.format(L[key], ...), "warning")
end

-- Modifier keys of the keyboard shortcuts (Ctrl or Cmd with Z, Y, D, Tab; Shift for ten pixels and back).
local function ctrl()
  return (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown()) or false
end

local function shift()
  return IsShiftKeyDown and IsShiftKeyDown() or false
end

-- Values for the render functions: the host's context, with sample values unless "Real values" is on.
local function drawCtx()
  local base = type(S.opts.ctx) == "table" and S.opts.ctx or {}
  local ctx = {}
  for k, v in pairs(base) do
    ctx[k] = v
  end
  ctx.editor = true
  ctx.sim = S.opts.sim or base.sim
  if type(S.opts.sample) == "function" and not (S.real and base.values) then
    ctx.values = S.opts.sample
  end
  return ctx
end

local function hasRealValues()
  return type(S.opts.sample) == "function" and type(S.opts.ctx) == "table" and type(S.opts.ctx.values) == "function"
end

-- Forward declarations: the parts call each other.
local redraw, refreshAll, changed, selectElement, paintOverlay, refreshManager, refreshViewBar

-- Preview --------------------------------------------------------------------------------------

local function cursorMode()
  return S ~= nil and CL.Kind(S.work) == "cursor"
end

-- Canvas scale at 100 percent of a cursor canvas: one canvas pixel covers one pixel of the real screen,
-- whatever scale the editor window has.
local function realScale()
  local up = UIParent:GetEffectiveScale()
  local win = frame and frame:GetEffectiveScale()
  if finite(up) and finite(win) and up > 0 and win > 0 then
    return up / win
  end
  return 1
end

-- The zoom steps of the session: whole numbers for a bar, shares of the true size for a cursor canvas.
local function zoomSteps()
  return cursorMode() and CE.REAL_ZOOMS or CE.ZOOMS
end

-- Canvas scale of a zoom step (S.zoom holds it, S.step the step).
local function factorOf(step)
  return cursorMode() and step * realScale() or step
end

-- The largest step that shows the whole canvas; a cursor canvas starts at the true size at most.
local function bestZoom()
  local cv, cursor = S.work.canvas, cursorMode()
  local steps = zoomSteps()
  local best = steps[1]
  for _, z in ipairs(steps) do
    local f = factorOf(z)
    if (not cursor or z <= 1) and cv.w * f <= LEFT_W - 16 and cv.h * f <= VIEW_H - 16 then
      best = z
    end
  end
  return best
end

-- Puts the canvas into the view: centered while it fits, else shifted by the pan. Fills S.origin with the
-- top left corner of the canvas in view units.
local function layoutPreview()
  local z, cv = S.zoom, S.work.canvas
  local sw, sh = cv.w * z, cv.h * z
  S.panX = U.clamp(S.panX, 0, math.max(0, sw - LEFT_W))
  S.panY = U.clamp(S.panY, 0, math.max(0, sh - VIEW_H))
  local mx = sw <= LEFT_W and (LEFT_W - sw) / 2 or -S.panX
  local my = sh <= VIEW_H and (VIEW_H - sh) / 2 or -S.panY
  local pin = S.drag and S.drag.pin
  if pin and pin.symmetric then
    -- A symmetric canvas grows on both sides: its center stays where it is.
    mx, my = pin.x + (pin.w - cv.w) * z / 2, pin.y + (pin.h - cv.h) * z / 2
  elseif pin then
    -- While a canvas handle is dragged the edge opposite to it stays put, so the handle follows the mouse.
    mx = pin.left and pin.x + (pin.w - cv.w) * z or pin.x
    my = pin.top and pin.y + (pin.h - cv.h) * z or pin.y
  end
  S.origin = { mx, my }
  ui.canvas:SetScale(z)
  ui.canvas:ClearAllPoints()
  ui.canvas:SetPoint("TOPLEFT", ui.view, "TOPLEFT", mx / z, -my / z)
end

function redraw()
  ns.Safe("canvas-draw", CR.Draw, ui.canvas, S.work, S.opts.types, drawCtx())
  layoutPreview()
  paintOverlay()
end

-- Mouse position in canvas pixels (origin top left, y down), nil while the client has no geometry.
local function cursorCanvas()
  local cx, cy = GetCursorPosition()
  local scale = ui.canvas:GetEffectiveScale()
  local left, top = ui.canvas:GetLeft(), ui.canvas:GetTop()
  if not (finite(cx) and finite(cy) and finite(scale) and scale > 0 and left and top) then
    return nil
  end
  return cx / scale - left, top - cy / scale
end

-- Mouse position in view pixels (origin top left, y down).
local function cursorView()
  local cx, cy = GetCursorPosition()
  local scale = ui.view:GetEffectiveScale()
  local left, top = ui.view:GetLeft(), ui.view:GetTop()
  if not (finite(cx) and finite(cy) and finite(scale) and scale > 0 and left and top) then
    return nil
  end
  return cx / scale - left, top - cy / scale
end

-- Overlay: textures on the mouse surface, in view units. Every group has a pool that grows on demand.
local function take(name, layer)
  local pool = ui.pools[name]
  pool.n = pool.n + 1
  local t = pool[pool.n]
  if not t then
    t = ui.surface:CreateTexture(nil, layer)
    pool[pool.n] = t
  end
  t:Show()
  return t
end

local function finishPool(name)
  local pool = ui.pools[name]
  for i = pool.n + 1, #pool do
    pool[i]:Hide()
  end
  pool.n = 0
end

local function box(name, layer, l, t, w, h, r, g, b, a)
  local tex = take(name, layer)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", ui.surface, "TOPLEFT", l, -t)
  tex:SetSize(math.max(1, w), math.max(1, h))
  tex:SetColorTexture(r, g, b, a)
end

local function ring(name, layer, l, t, w, h, thick, r, g, b, a)
  box(name, layer, l, t, w, thick, r, g, b, a)
  box(name, layer, l, t + h - thick, w, thick, r, g, b, a)
  box(name, layer, l, t + thick, thick, h - 2 * thick, r, g, b, a)
  box(name, layer, l + w - thick, t + thick, thick, h - 2 * thick, r, g, b, a)
end

local function handlePoint(name, l, t, w, h)
  local fx = name:find("LEFT") and 0 or (name:find("RIGHT") and 1 or 0.5)
  local fy = name:find("TOP") and 0 or (name:find("BOTTOM") and 1 or 0.5)
  return l + fx * w, t + fy * h
end

local function gridStep()
  local step = S.snap > 0 and S.snap or 10
  local cv = S.work.canvas
  while (cv.w + cv.h) / step > MAX_GRID_LINES do
    step = step * 2
  end
  return step
end

-- Stage ----------------------------------------------------------------------------------------

local function stageOf()
  local stage = S and S.opts.stage
  return type(stage) == "table" and stage or nil
end

local function backdropList()
  local stage = stageOf()
  return stage and type(stage.backdrops) == "table" and #stage.backdrops > 0 and stage.backdrops or CE.BACKDROPS
end

local function backdropById(id)
  local list = backdropList()
  for _, b in ipairs(list) do
    if b.id == id then
      return b
    end
  end
  return list[1]
end

-- Fills the view behind the canvas with the chosen backdrop: a color, a texture, or a checker of two colors
-- (squares of the second color on a base of the first). Nothing shows without a stage.
local function paintBackdrop()
  local b = stageOf() and backdropById(S.backdrop)
  local checker = ui.checker
  if not b then
    ui.backdrop:Hide()
    for _, square in ipairs(checker) do
      square:Hide()
    end
    return
  end
  ui.backdrop:Show()
  if b.texture then
    ui.backdrop:SetTexture(b.texture)
  else
    ui.backdrop:SetColorTexture(U.hex(b.color or "000000"))
  end
  local n = 0
  if b.color2 then
    local r, g, bl = U.hex(b.color2)
    for row = 0, math.ceil(VIEW_H / CHECKER_CELL) - 1 do
      for col = 0, math.ceil(LEFT_W / CHECKER_CELL) - 1 do
        if (row + col) % 2 == 1 then
          n = n + 1
          local square = checker[n]
          if not square then
            square = ui.view:CreateTexture(nil, "BACKGROUND")
            square:SetDrawLayer("BACKGROUND", 3)
            checker[n] = square
          end
          square:ClearAllPoints()
          square:SetPoint("TOPLEFT", ui.view, "TOPLEFT", col * CHECKER_CELL, -row * CHECKER_CELL)
          square:SetSize(
            math.min(CHECKER_CELL, LEFT_W - col * CHECKER_CELL),
            math.min(CHECKER_CELL, VIEW_H - row * CHECKER_CELL)
          )
          square:SetColorTexture(r, g, bl, 1)
          square:Show()
        end
      end
    end
  end
  for i = n + 1, #checker do
    checker[i]:Hide()
  end
end

-- The mouse cursor image at the hotspot of the canvas, over the elements. A texture of the preview only: it
-- takes no clicks, is no element and never reaches the layout. Its tip (tipX, tipY: shares of the image)
-- sits on the hotspot; its size scales with the zoom like the canvas.
local function paintMarker(ox, oy, z)
  local stage = stageOf()
  local marker = stage and type(stage.marker) == "table" and stage.marker or nil
  if not marker then
    ui.marker:Hide()
    return
  end
  local size = (finite(marker.size) and marker.size > 0 and marker.size or 32) * z
  local hx, hy = CL.HotPoint(S.work)
  local tipX = finite(marker.tipX) and marker.tipX or 0
  local tipY = finite(marker.tipY) and marker.tipY or 0
  ui.marker:ClearAllPoints()
  ui.marker:SetPoint("TOPLEFT", ui.surface, "TOPLEFT", ox + hx * z - tipX * size, -(oy + hy * z - tipY * size))
  ui.marker:SetSize(size, size)
  ui.marker:Show()
end

function paintOverlay()
  if not (S and ui) then
    return
  end
  local z = S.zoom
  local ox, oy = S.origin[1], S.origin[2]
  local cv = S.work.canvas
  paintMarker(ox, oy, z)
  if ui.canvasHandles then
    local tr, tg, tb = Theme.rgb("text")
    for name, handle in pairs(ui.canvasHandles) do
      local px, py = handlePoint(name, ox, oy, cv.w * z, cv.h * z)
      handle:ClearAllPoints()
      handle:SetPoint("CENTER", ui.view, "TOPLEFT", px, -py)
      handle.square:SetColorTexture(tr, tg, tb, 1)
    end
  end
  if S.grid then
    local step = gridStep()
    for x = step, cv.w - 1, step do
      box("grid", "BACKGROUND", ox + x * z, oy, 1, cv.h * z, 1, 1, 1, 0.18)
    end
    for y = step, cv.h - 1, step do
      box("grid", "BACKGROUND", ox, oy + y * z, cv.w * z, 1, 1, 1, 1, 0.18)
    end
  end
  finishPool("grid")
  -- Every visible element gets a thin outline: a transparent text still shows where it is.
  for _, el in ipairs(S.work.elements) do
    if el.visible ~= false and el.id ~= S.sel then
      local l, t, w, h = CL.Rect(S.work, el, S.measure)
      ring("bounds", "BORDER", ox + l * z, oy + t * z, w * z, h * z, 1, 1, 1, 1, 0.3)
    end
  end
  finishPool("bounds")
  local el = sel()
  if el then
    local l, t, w, h = CL.Rect(S.work, el, S.measure)
    local sl, st, sw, sh = ox + l * z, oy + t * z, math.max(1, w * z), math.max(1, h * z)
    ring("select", "ARTWORK", sl - 1, st - 1, sw + 2, sh + 2, 1, 0, 0, 0, 0.9)
    local r, g, b = Theme.rgb("accent2")
    ring("select", "ARTWORK", sl, st, sw, sh, 2, r, g, b, 1)
    if el.visible ~= false then
      for _, name in ipairs(HANDLES) do
        local px, py = handlePoint(name, sl, st, sw, sh)
        local half = HANDLE_SIZE / 2
        box("handle", "OVERLAY", px - half - 1, py - half - 1, HANDLE_SIZE + 2, HANDLE_SIZE + 2, 0, 0, 0, 1)
        box("handle", "OVERLAY", px - half, py - half, HANDLE_SIZE, HANDLE_SIZE, r, g, b, 1)
      end
    end
  end
  finishPool("select")
  finishPool("handle")
  if S.guides then
    local r, g, b = Theme.rgb("warning")
    for _, line in ipairs(S.guides) do
      if line.axis == "x" then
        box("guide", "OVERLAY", ox + line.at * z, oy + line.from * z, 1, (line.to - line.from) * z, r, g, b, 1)
      else
        box("guide", "OVERLAY", ox + line.from * z, oy + line.at * z, (line.to - line.from) * z, 1, r, g, b, 1)
      end
    end
  end
  finishPool("guide")
end

-- The element under the point, and the handle when the point is on one of the selected element.
local function hitTest(x, y)
  local z = S.zoom
  local el = sel()
  if el and el.visible ~= false then
    local l, t, w, h = CL.Rect(S.work, el, S.measure)
    for _, name in ipairs(HANDLES) do
      local px, py = handlePoint(name, l, t, w, h)
      if math.abs(x - px) <= HANDLE_HIT / z and math.abs(y - py) <= HANDLE_HIT / z then
        return el, name
      end
    end
  end
  local list = CL.Sorted(S.work)
  local slack = 2 / z
  for i = #list, 1, -1 do
    local e = list[i]
    if e.visible ~= false then
      local l, t, w, h = CL.Rect(S.work, e, S.measure)
      if x >= l - slack and x <= l + w + slack and y >= t - slack and y <= t + h + slack then
        return e
      end
    end
  end
end

-- Dragging -------------------------------------------------------------------------------------

local function beginDrag(el, handle, x, y)
  local l, t, w, h = CL.Rect(S.work, el, S.measure)
  S.drag = { id = el.id, handle = handle, x = x, y = y, l = l, t = t, w = w, h = h, moved = false, orig = U.copy(el) }
end

local function snapped(v)
  return CL.Snap(v, snapStep())
end

local function moveTo(el, d, dx, dy)
  local cv = S.work.canvas
  local left = U.clamp(d.l + dx, 0, math.max(0, cv.w - d.w))
  local top = U.clamp(d.t + dy, 0, math.max(0, cv.h - d.h))
  CL.Place(S.work, el, left, top, S.measure)
  local g = CL.GuideLines(S.work, el, math.max(0.5, CL.TOLERANCE / S.zoom), S.measure)
  left = g.dx ~= 0 and left + g.dx or snapped(left)
  top = g.dy ~= 0 and top + g.dy or snapped(top)
  CL.Place(S.work, el, U.clamp(left, 0, math.max(0, cv.w - d.w)), U.clamp(top, 0, math.max(0, cv.h - d.h)), S.measure)
  S.guides = CL.GuideLines(S.work, el, 0, S.measure).lines
end

local function resizeTo(el, d, dx, dy)
  local cv = S.work.canvas
  local left, top, right, bottom = d.l, d.t, d.l + d.w, d.t + d.h
  local h = d.handle
  if h:find("LEFT") then
    left = U.clamp(snapped(d.l + dx), 0, right - MIN_ELEMENT)
  elseif h:find("RIGHT") then
    right = U.clamp(snapped(d.l + d.w + dx), left + MIN_ELEMENT, cv.w)
  end
  if h:find("TOP") then
    top = U.clamp(snapped(d.t + dy), 0, bottom - MIN_ELEMENT)
  elseif h:find("BOTTOM") then
    bottom = U.clamp(snapped(d.t + d.h + dy), top + MIN_ELEMENT, cv.h)
  end
  el.w, el.h = U.round(right - left, 0.5), U.round(bottom - top, 0.5)
  CL.Place(S.work, el, left, top, S.measure)
  S.guides = nil
end

local function dragTo(x, y)
  local d = S.drag
  local el = d and CL.Find(S.work, d.id)
  if not el then
    S.drag = nil
    return
  end
  local dx, dy = x - d.x, y - d.y
  if not d.moved and (math.abs(dx) + math.abs(dy)) * S.zoom < DRAG_MIN then
    return
  end
  d.moved = true
  if d.handle then
    resizeTo(el, d, dx, dy)
  else
    moveTo(el, d, dx, dy)
  end
  redraw()
  ui.refreshFields()
end

-- Canvas handles -------------------------------------------------------------------------------

-- Every element goes back to the geometry it had when the drag began, so dragging the canvas smaller
-- and larger again leaves the elements where they were.
local function restoreElements(saved)
  for _, el in ipairs(S.work.elements) do
    local s = saved[el.id]
    if s then
      el.point, el.x, el.y, el.w, el.h = s.point, s.x, s.y, s.w, s.h
    end
  end
end

local function beginCanvasDrag(name, button)
  if not S or button ~= "LeftButton" then
    return
  end
  local vx, vy = cursorView()
  if not vx then
    return
  end
  local cv = S.work.canvas
  local symmetric = cursorMode() and cv.symmetric == true
  local saved = {}
  for _, el in ipairs(S.work.elements) do
    saved[el.id] = { point = el.point, x = el.x, y = el.y, w = el.w, h = el.h }
    if symmetric then
      saved[el.id].l, saved[el.id].t = CL.Rect(S.work, el, S.measure)
    end
  end
  S.drag = {
    canvas = name,
    vx = vx,
    vy = vy,
    w = cv.w,
    h = cv.h,
    moved = false,
    saved = saved,
    symmetric = symmetric,
    pin = {
      x = S.origin[1],
      y = S.origin[2],
      w = cv.w,
      h = cv.h,
      left = name:find("LEFT") ~= nil,
      top = name:find("TOP") ~= nil,
      symmetric = symmetric,
    },
  }
end

-- The grabbed edge follows the mouse (mouse in view pixels); the opposite edge stays where it is.
local function resizeCanvasTo(d, vx, vy)
  local dx, dy = (vx - d.vx) / S.zoom, (vy - d.vy) / S.zoom
  -- Symmetric: both edges move, so the size changes twice as fast as the handle.
  local grow = d.symmetric and 2 or 1
  local w, h = d.w, d.h
  if d.canvas:find("LEFT") then
    w = d.w - dx * grow
  elseif d.canvas:find("RIGHT") then
    w = d.w + dx * grow
  end
  if d.canvas:find("TOP") then
    h = d.h - dy * grow
  elseif d.canvas:find("BOTTOM") then
    h = d.h + dy * grow
  end
  local step = math.max(1, snapStep())
  restoreElements(d.saved)
  local cv = S.work.canvas
  cv.w = U.clamp(CL.Snap(w, step), CL.MIN_CANVAS, CL.MAX_CANVAS)
  cv.h = U.clamp(CL.Snap(h, step), CL.MIN_CANVAS, CL.MAX_CANVAS)
  if d.symmetric then
    -- Every element keeps its place relative to the center.
    for _, el in ipairs(S.work.elements) do
      local s = d.saved[el.id]
      if s then
        CL.Place(S.work, el, s.l + (cv.w - d.w) / 2, s.t + (cv.h - d.h) / 2, S.measure)
      end
    end
  end
  CL.Clamp(S.work, S.measure)
end

local function dragCanvasTo(vx, vy)
  local d = S.drag
  local dx, dy = vx - d.vx, vy - d.vy
  if not d.moved and math.abs(dx) + math.abs(dy) < DRAG_MIN then
    return
  end
  d.moved = true
  resizeCanvasTo(d, vx, vy)
  redraw()
  ui.cw:Refresh()
  ui.ch:Refresh()
  ui.refreshFields()
end

local function endDrag()
  local d = S.drag
  S.drag, S.guides = nil, nil
  if d and d.moved then
    changed(d.canvas and "canvas:size" or ("drag:" .. d.id))
  else
    paintOverlay()
  end
end

-- Esc during a drag puts the element or the canvas size back and keeps the editor open.
local function cancelDrag()
  local d = S.drag
  S.drag, S.guides = nil, nil
  if d.canvas then
    restoreElements(d.saved)
    S.work.canvas.w, S.work.canvas.h = d.w, d.h
  else
    local el, index = CL.Find(S.work, d.id)
    if el then
      S.work.elements[index] = d.orig
    end
  end
  redraw()
  refreshAll()
end

local function onMouseDown(_, button)
  if not S or button ~= "LeftButton" then
    return
  end
  local x, y = cursorCanvas()
  if not x then
    return
  end
  local el, handle = hitTest(x, y)
  if el then
    if S.sel ~= el.id then
      selectElement(el.id)
    end
    beginDrag(el, handle, x, y)
  else
    selectElement(nil)
    -- Dragging the empty area moves a preview that is larger than the view.
    local vx, vy = cursorView()
    if vx then
      S.pan = { x = vx, y = vy, panX = S.panX, panY = S.panY }
    end
  end
end

local function onMouseUp(_, button)
  if not S or button ~= "LeftButton" then
    return
  end
  S.pan = nil
  if S.drag then
    endDrag()
  end
end

local function onUpdate()
  local d = S and S.drag
  if not (d or (S and S.pan)) then
    return
  end
  -- A release outside the client (alt-tab) never arrives as a mouse up.
  if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
    S.pan = nil
    if d then
      endDrag()
    end
    return
  end
  if not d then
    local vx, vy = cursorView()
    if vx then
      S.panX, S.panY = S.pan.panX - (vx - S.pan.x), S.pan.panY - (vy - S.pan.y)
      redraw()
    end
    return
  end
  if d.canvas then
    local vx, vy = cursorView()
    if vx and (vx ~= d.lastX or vy ~= d.lastY) then
      d.lastX, d.lastY = vx, vy
      dragCanvasTo(vx, vy)
    end
    return
  end
  local x, y = cursorCanvas()
  if x and (x ~= d.lastX or y ~= d.lastY) then
    d.lastX, d.lastY = x, y
    dragTo(x, y)
  end
end

local function setZoom(z)
  z = finite(z) and z or 1
  if cursorMode() then
    local best, dist
    for _, step in ipairs(CE.REAL_ZOOMS) do
      if not dist or math.abs(step - z) < dist then
        best, dist = step, math.abs(step - z)
      end
    end
    z = best
  else
    z = U.clamp(math.floor(z), CE.ZOOMS[1], CE.ZOOMS[#CE.ZOOMS])
  end
  S.step, S.zoom = z, factorOf(z)
  ui.zoom:Refresh()
  redraw()
end

local function onWheel(_, delta)
  if not S then
    return
  end
  local dir = delta > 0 and 1 or -1
  if not cursorMode() then
    setZoom(S.step + dir)
    return
  end
  local at = 1
  for i, step in ipairs(CE.REAL_ZOOMS) do
    if step == S.step then
      at = i
    end
  end
  setZoom(CE.REAL_ZOOMS[U.clamp(at + dir, 1, #CE.REAL_ZOOMS)])
end

-- Actions --------------------------------------------------------------------------------------

local act = {}
CE.Do = act

local function send()
  S.lastSent = CL.Pack(S.work)
  ns.Safe("canvas-apply", S.opts.onApply, CL.Pack(S.work))
end

-- A change of the working copy: history, preview, panels and, with Live, the real window.
function changed(key)
  CL.Record(S.hist, S.work, key)
  redraw()
  refreshAll()
  if S.live then
    send()
  end
end

function selectElement(id)
  S.sel = id and CL.Find(S.work, id) and id or nil
  refreshAll()
  paintOverlay()
end

-- The layout the editor works on after undo, redo, a template or an import. The selection stays when
-- the element is still there.
local function adopt(layout, key)
  S.work = layout
  if S.sel and not CL.Find(S.work, S.sel) then
    S.sel = nil
  end
  if key then
    changed(key)
  else
    redraw()
    refreshAll()
    if S.live then
      send()
    end
  end
end

function act.undo()
  local layout = CL.Undo(S.hist)
  if layout then
    adopt(layout)
  end
end

function act.redo()
  local layout = CL.Redo(S.hist)
  if layout then
    adopt(layout)
  end
end

-- The definition of an element type of the host, nil when the host has none.
local function typeDef(kind)
  local def = S and S.opts.types[kind]
  return type(def) == "table" and def or nil
end

-- The text of a locale key, nil for anything that is not a key with a text.
local function localized(key)
  local text = type(key) == "string" and L[key] or nil
  return type(text) == "string" and text ~= key and text or nil
end

-- The title of an element in the list and in the panel head: the host's own `title(element)`, else the name
-- of the element, else the label of its type.
local function titleOf(el)
  local def = typeDef(el.type)
  if def and type(def.title) == "function" then
    local ok, title = pcall(def.title, el)
    if ok and type(title) == "string" and title ~= "" then
      return title
    end
  end
  if type(el.name) == "string" and el.name ~= "" then
    return el.name
  end
  return def and type(def.label) == "string" and def.label or el.type
end

-- The label of the type of an element and what the type is for (nil without a description): the tooltip of
-- its row and the line at the top of its panel.
local function tipOf(el)
  local def = typeDef(el.type)
  return def and type(def.label) == "string" and def.label or el.type, def and localized(def.desc)
end

-- Tooltip of a list row: the type and what it is for, and for an element with a name of its own the whole
-- name as a line of its own (the row cuts a long one).
local function rowTip(el)
  local title = titleOf(el)
  local label, description = tipOf(el)
  return label, description, title ~= label and { L["canvas.name"] .. ": " .. title } or nil
end

-- The variants a type offers in the Add menu: { id, label (locale key), props } with an id and a label.
local function variantsOf(def)
  local out = {}
  for _, v in ipairs(def and type(def.variants) == "table" and def.variants or {}) do
    if type(v) == "table" and type(v.id) == "string" and type(v.label) == "string" then
      out[#out + 1] = v
    end
  end
  return out
end

-- `variant` is one entry of types[kind].variants: its props are merged into the new element's props and its
-- label is the default name.
function act.add(kind, variant)
  local element = { type = kind }
  if variant then
    local def = typeDef(kind)
    local ok, props = pcall(def and def.new or function() end)
    props = ok and type(props) == "table" and props or {}
    for key, value in pairs(type(variant.props) == "table" and variant.props or {}) do
      props[key] = value
    end
    element.props = props
    element.name = localized(variant.label)
  end
  local el, why = CL.AddElement(S.work, element, S.opts.types)
  if not el then
    if why == "max" then
      noteFail("canvas.addMax")
    elseif why == "limit" then
      noteFail("canvas.addLimit", CL.MAX_ELEMENTS)
    end
    return nil
  end
  S.sel = el.id
  changed("add")
  return el
end

-- The name an element gets from the editor when it is added: the label of its variant, else of its type.
local function defaultName(el)
  local def = typeDef(el.type)
  local props = type(el.props) == "table" and el.props or {}
  for _, v in ipairs(variantsOf(def)) do
    local match = type(v.props) == "table" and next(v.props) ~= nil
    for key, value in pairs(match and v.props or {}) do
      match = match and props[key] == value
    end
    if match and localized(v.label) then
      return localized(v.label)
    end
  end
  return def and type(def.label) == "string" and def.label or el.type
end

-- Removes element `id` (default: the selected one). The selection moves to the next element in the z order
-- when the removed one was selected and stays where it is otherwise. Undo brings the element back.
function act.remove(id)
  local el = id == nil and sel() or CL.Find(S.work, id)
  if not el then
    return
  end
  local at = 1
  for i, e in ipairs(CL.Sorted(S.work)) do
    if e == el then
      at = i
    end
  end
  local wasSelected = S.sel == el.id
  CL.RemoveElement(S.work, el)
  if wasSelected then
    local rest = CL.Sorted(S.work)
    S.sel = rest[math.min(at, #rest)] and rest[math.min(at, #rest)].id or nil
  end
  if not S.removedNote then
    S.removedNote = true
    ns.Notify(L["canvas.msg.removed"], "info")
  end
  changed("remove")
end

-- Names element `id` with `text` (cleaned, empty gives the default name): one undo step per element.
function act.renameElement(id, text)
  local el = CL.Find(S.work, id)
  if el and CL.Rename(S.work, el, text, defaultName(el)) then
    changed("name:" .. el.id)
  end
end

-- Selects element `id` (default: the selected one) and puts the keyboard in its name field.
function act.focusName(id)
  if id ~= nil then
    selectElement(id)
  end
  if sel() then
    ui.props:ScrollTo(0)
    ui.name.edit:SetFocus()
    ui.name.edit:HighlightText()
  end
end

function act.duplicate()
  local el = sel()
  if not el then
    return
  end
  local copy, why = CL.Duplicate(S.work, el, S.opts.types)
  if not copy then
    noteFail(why == "max" and "canvas.addMax" or "canvas.addLimit", CL.MAX_ELEMENTS)
    return
  end
  S.sel = copy.id
  changed("duplicate")
end

function act.nudge(dx, dy)
  local el = sel()
  if el then
    CL.Move(el, dx, dy)
    changed("nudge:" .. el.id)
  end
end

function act.reorder(id, how)
  if CL.Reorder(S.work, id, how) then
    changed("order")
  end
end

function act.toggleVisible(id)
  local el = CL.Find(S.work, id)
  if el then
    el.visible = el.visible == false
    changed("visible:" .. id)
  end
end

function act.setAnchor(point)
  local el = sel()
  if el and CL.SetAnchor(S.work, el, point, S.measure) then
    changed("anchor:" .. el.id)
  end
end

function act.zoom(z)
  setZoom(z)
end

-- Switches the backdrop of the stage (a view setting, no change of the layout).
function act.backdrop(id)
  if not stageOf() then
    return
  end
  S.backdrop = backdropById(id).id
  frameDb().backdrop = S.backdrop
  paintBackdrop()
  ui.backdropDd:Refresh()
end

-- A simulation tool of the host (opts.tools). Toggling and clicking only redraw the preview: a tool never
-- records an undo step and never marks the layout as changed.
function act.tool(id)
  for _, def in ipairs(S.tools) do
    if def.id == id then
      local on = true
      if def.toggle then
        on = not S.toolOn[id]
        S.toolOn[id] = on
      end
      refreshViewBar()
      if type(def.onClick) == "function" then
        ns.Safe("canvas-tool", def.onClick, on)
      end
      redraw()
      return
    end
  end
end

-- "Test at real cursor": only tells the host, which shows the layout at the real cursor.
function act.liveTest(on)
  on = on == true
  if on == S.liveTest then
    return
  end
  S.liveTest = on
  if type(S.opts.liveTest) == "function" then
    ns.Safe("canvas-livetest", S.opts.liveTest, on)
  end
end

function act.snap(step)
  for _, s in ipairs(CE.SNAPS) do
    if s == step then
      S.snap = step
      frameDb().snap = step
      ui.snapDd:Refresh()
      paintOverlay()
      return
    end
  end
end

local function findPreset(id)
  for _, p in ipairs(S.opts.presets or {}) do
    if p.id == id then
      return p
    end
  end
end

function act.preset(id)
  local p = findPreset(id)
  if not p then
    return
  end
  local layout = CL.Validate(p.layout)
  layout.id, layout.name, layout.preset = S.work.id, S.work.name, p.id
  adopt(layout, "preset")
end

function act.reset()
  local current = findPreset(S.work.preset) or (S.opts.presets or {})[1]
  if current then
    act.preset(current.id)
  end
end

function act.export()
  local text = CL.Export(S.work, S.opts.host)
  if text then
    ns.Dialogs.Copy("canvas.export.title", text, "canvas.export.hint")
  else
    noteFail("canvas.export.fail")
  end
end

-- Hands the layout to the host's own storage when it manages layouts: Apply counts as Save.
local function store()
  local save = S.mgr and S.mgr.save
  if type(save) ~= "function" then
    return true
  end
  return (ns.Safe("canvas-manager.save", save, S.layoutId, CL.Pack(S.work)))
end

function act.apply()
  send()
  if store() then
    S.base = U.copy(S.work)
  end
  refreshAll()
end

-- Ends the session: live changes the host got are taken back, onCancel runs. The window closes.
local function finish()
  if not S then
    return
  end
  local s = S
  S = nil
  if s.liveTest and type(s.opts.liveTest) == "function" then
    ns.Safe("canvas-livetest", s.opts.liveTest, false)
  end
  if s.lastSent and not equal(s.lastSent, s.base) then
    ns.Safe("canvas-revert", s.opts.onApply, CL.Pack(s.base))
  end
  if type(s.opts.onCancel) == "function" then
    ns.Safe("canvas-cancel", s.opts.onCancel)
  end
  if frame and frame:IsShown() then
    frame:Hide()
  end
end

-- Discard (and Esc and the close button): asks first while there are changes. force skips the question.
function act.discard(force)
  if not S then
    return
  end
  if force or not isDirty() then
    finish()
    return
  end
  ns.Dialogs.Confirm("canvas.discardTitle", "canvas.discardAsk", finish)
end

-- Layout manager -------------------------------------------------------------------------------

-- The host may pass opts.manager (see the top of the file). Every function is optional and every
-- call is protected: a missing function hides its control, a failing one is recorded and the editor
-- carries on.
local function mgrFn(name)
  local fn = S and S.mgr and S.mgr[name]
  return type(fn) == "function" and fn or nil
end

-- ok, first and second result of the manager function; false when it is missing or failed.
local function mgrCall(name, ...)
  local fn = mgrFn(name)
  if not fn then
    return false
  end
  return ns.Safe("canvas-manager." .. name, fn, ...)
end

local function explain(reason)
  local key = "canvas.err." .. tostring(reason)
  noteFail(L[key] ~= key and key or "canvas.err")
end

local function layoutList()
  local out = {}
  local ok, list = mgrCall("list")
  for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
    if type(entry) == "table" and entry.id ~= nil then
      -- Names come from the host's storage: shown as plain text, never as escapes.
      local name = CL.CleanText(type(entry.name) == "string" and entry.name or tostring(entry.id), CL.MAX_LAYOUT_NAME)
      out[#out + 1] = { id = entry.id, name = name }
    end
  end
  return out
end

-- The name of layout `id`: the working copy's own while it is open, else the host's list.
local function layoutName(id)
  if id == S.layoutId and (S.work.name ~= "" or not S.mgr) then
    return S.work.name
  end
  for _, entry in ipairs(layoutList()) do
    if entry.id == id then
      return entry.name
    end
  end
  return ""
end

local function currentName()
  return layoutName(S.layoutId)
end

local function updateTitle()
  local title = type(S.opts.title) == "string" and S.opts.title ~= "" and S.opts.title or L["canvas.title"]
  local name = currentName()
  W.SetText(frame.title, nil, name ~= "" and (title .. ": " .. name) or title)
end

local function canDelete(id)
  local ok, can = mgrCall("canDelete", id == nil and S.layoutId or id)
  return ok and can == true
end

-- Live changes the host took over go back to the state of the last save before another layout opens.
local function revertLive()
  if S.lastSent and not equal(S.lastSent, S.base) then
    ns.Safe("canvas-revert", S.opts.onApply, CL.Pack(S.base))
  end
  S.lastSent = nil
end

-- The layout the editor works on after a switch: new history, nothing selected, nothing unsaved.
local function loadLayout(layout, id)
  S.work = CL.Validate(layout)
  S.base = U.copy(S.work)
  S.hist = CL.History(S.work, now)
  S.layoutId = id
  S.sel, S.lastBorder, S.panX, S.panY = nil, nil, 0, 0
  updateTitle()
  redraw()
  refreshAll()
  if S.live then
    send()
  end
end

-- The host selects `id` and returns the layout to edit; `fallback` stands in when it returns none.
local function switchNow(id, fallback)
  local ok, layout = mgrCall("select", id)
  if not (ok and type(layout) == "table") then
    layout = fallback
  end
  if type(layout) ~= "table" then
    explain("missing")
    refreshManager()
    return false
  end
  loadLayout(layout, id)
  return true
end

local function saveNow()
  if mgrFn("save") and store() then
    S.base = U.copy(S.work)
    ns.Notify(L["canvas.msg.saved"], "success")
    refreshAll()
    return true
  end
  return false
end

local switchDlg

-- Save, Discard changes or Cancel (the dialog just closes) before the editor leaves a changed layout.
local function askUnsaved(onSave, onDiscard)
  if not switchDlg then
    local d = ns.Dialogs.Create("ForeverGuidesCanvasSwitch", 540, 170)
    switchDlg = d
    W.SetText(d.title, "canvas.switch.title")
    d.text = W.Text(d, { key = "canvas.switch.text", role = "text", wrap = true })
    d.text:SetPoint("TOPLEFT", 16, -48)
    d.text:SetPoint("RIGHT", -16, 0)
    d.save = W.Action(d, {
      label = "act.save",
      icon = "save",
      tooltip = "act.save",
      variant = "primary",
      width = 110,
    })
    d.save:SetPoint("BOTTOMRIGHT", -16, 14)
    d.discard = W.Action(d, {
      label = "canvas.switch.discard",
      icon = "trash",
      tooltip = "canvas.switch.discard",
      width = 180,
    })
    d.discard:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
    d.cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    d.cancel:SetPoint("RIGHT", d.discard, "LEFT", -8, 0)
  end
  local d = switchDlg
  d.save:SetEnabled(mgrFn("save") ~= nil)
  d.save:SetScript(
    "OnClick",
    ns.Wrap("canvas-switch-save", function()
      d:Hide()
      onSave()
    end)
  )
  d.discard:SetScript(
    "OnClick",
    ns.Wrap("canvas-switch-discard", function()
      d:Hide()
      onDiscard()
    end)
  )
  d:Show()
end

-- Opens layout `id` in the editor. A changed layout asks first. `fallback` is the layout to show when
-- the host's select returns none (a layout it has just created from the working copy). `after` runs once
-- the layout is open.
function act.switchTo(id, fallback, after)
  if not (S and S.mgr and mgrFn("select")) or (id == S.layoutId and not fallback) then
    return
  end
  local session = S
  local function go()
    if S == session then
      revertLive()
      if switchNow(id, fallback) and after then
        after()
      end
    end
  end
  if not isDirty() then
    go()
    return
  end
  askUnsaved(function()
    if S == session and saveNow() then
      go()
    end
  end, go)
end

function act.save()
  if S then
    saveNow()
  end
end

local nameDlg

-- Asks for a name. onDone(name) runs for a name that is not empty.
local function askName(titleKey, goKey, current, onDone)
  if not nameDlg then
    local d = ns.Dialogs.Create("ForeverGuidesCanvasName", 420, 190)
    nameDlg = d
    d.label = W.Text(d, { key = "canvas.name.label", role = "ui" })
    d.label:SetPoint("TOPLEFT", 16, -48)
    d.name = W.EditBox(d, {
      onEnter = function()
        d.go:Click()
      end,
    })
    d.name:SetPoint("TOPLEFT", 16, -68)
    d.name:SetPoint("RIGHT", -16, 0)
    d.name.edit:SetMaxLetters(CL.MAX_LAYOUT_NAME)
    d.go = W.Button(d, { key = "canvas.name.create", variant = "primary", width = 130 })
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
  W.SetText(d.title, titleKey)
  W.SetText(d.go.label, goKey)
  d.name.edit:SetText(current or "")
  d.go:SetScript(
    "OnClick",
    ns.Wrap("canvas-name-dialog", function()
      local name = CL.CleanText(d.name.edit:GetText(), CL.MAX_LAYOUT_NAME)
      if name == "" then
        explain("name")
        return
      end
      d:Hide()
      onDone(name)
    end)
  )
  d:Show()
  d.name.edit:SetFocus()
end

-- A new layout from the working copy under `name`, opened at once. The layout it came from keeps its
-- saved state.
local function createFrom(name, session)
  name = CL.CleanText(name, CL.MAX_LAYOUT_NAME)
  local ok, id, reason = mgrCall("create", name, CL.Pack(S.work))
  if not (ok and id ~= nil) then
    explain(reason)
    return false
  end
  local copy = CL.Pack(S.work)
  copy.id, copy.name = id, name
  if S == session then
    revertLive()
    switchNow(id, copy)
  end
  return true
end

function act.saveAs()
  if not (S and mgrFn("create")) then
    return
  end
  local session = S
  askName("canvas.name.newTitle", "canvas.name.create", "", function(name)
    if S == session then
      createFrom(name, session)
    end
  end)
end

-- Copies a layout: the working copy of the open one, any other one is opened first (it may ask about
-- unsaved changes) because only the host's select hands out its contents.
function act.dupLayout(id)
  if not (S and mgrFn("create")) then
    return
  end
  if id ~= nil and id ~= S.layoutId then
    act.switchTo(id, nil, function()
      act.dupLayout()
    end)
    return
  end
  createFrom(string.format(L["canvas.copy"], currentName()), S)
end

-- Renames layout `id` (default: the open one).
function act.rename(id)
  if not (S and mgrFn("rename")) then
    return
  end
  id = id == nil and S.layoutId or id
  local session = S
  askName("canvas.name.renameTitle", "act.rename", layoutName(id), function(name)
    if S ~= session then
      return
    end
    local ok, done, reason = mgrCall("rename", id, name)
    if not (ok and done) then
      explain(reason)
      return
    end
    if id == S.layoutId then
      -- A rename is stored at once, so it does not count as an unsaved change.
      local clean = CL.Validate({ name = name }).name
      S.work.name, S.base.name = clean, clean
      for _, state in ipairs(S.hist.states) do
        state.name = clean
      end
      updateTitle()
    end
    refreshAll()
  end)
end

-- Deletes layout `id` (default: the open one) after a confirmation.
function act.deleteLayout(id)
  if not (S and mgrFn("delete")) then
    return
  end
  id = id == nil and S.layoutId or id
  if not canDelete(id) then
    explain("last")
    return
  end
  local session = S
  ns.Dialogs.Confirm("canvas.deleteTitle", "canvas.deleteAsk", function()
    if S ~= session then
      return
    end
    local ok, done, reason = mgrCall("delete", id)
    if not (ok and done) then
      explain(reason)
      return
    end
    if id ~= S.layoutId then
      refreshAll()
      return
    end
    -- The layout is gone, so there is nothing of it left to take back.
    S.lastSent = nil
    local _, nextId = mgrCall("current")
    switchNow(nextId, nil)
  end)
end

-- Import dialog --------------------------------------------------------------------------------

local importDlg

-- Adds an imported layout to the host's layouts under a name the player picks and opens it.
function act.importAs(layout, problems)
  local session = S
  local default = layout.name ~= "" and layout.name or L["canvas.name.importDefault"]
  askName("canvas.name.importTitle", "act.import", default, function(name)
    if S ~= session then
      return
    end
    local copy = CL.Pack(layout)
    copy.name = name
    local ok, id, reason = mgrCall("import", name, copy)
    if not (ok and id ~= nil) then
      explain(reason)
      return
    end
    ns.Notify(string.format(L["canvas.msg.imported"], type(problems) == "table" and #problems or 0), "success")
    copy.id = id
    act.switchTo(id, copy)
  end)
end

local function showImport()
  if not importDlg then
    local d = ns.Dialogs.Create("ForeverGuidesCanvasImport", 520, 380)
    importDlg = d
    W.SetText(d.title, "canvas.import.title")
    d.hint = W.Text(d, { key = "canvas.import.hint", role = "ui", color = "textSecondary", wrap = true })
    d.hint:SetPoint("TOPLEFT", 16, -48)
    d.hint:SetPoint("RIGHT", -16, 0)
    d.pasteLabel = W.Text(d, { key = "canvas.import.paste", role = "ui" })
    d.pasteLabel:SetPoint("TOPLEFT", 16, -100)
    d.paste = W.TextArea(d, {
      height = 140,
      onChange = function(text)
        d.refresh(text)
      end,
    })
    d.paste:SetPoint("TOPLEFT", 16, -120)
    d.paste:SetPoint("RIGHT", -16, 0)
    d.paste.edit:SetMaxLetters(0)
    d.status = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
    d.status:SetPoint("TOPLEFT", 16, -272)
    d.status:SetPoint("RIGHT", -16, 0)
    d.go = W.Action(d, {
      label = "act.import",
      icon = "import",
      tooltip = "act.import",
      tooltipText = "canvas.import.do",
      variant = "primary",
      width = 130,
    })
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
      local host = S and (type(S.opts.host) == "string" and S.opts.host or CL.HostOf(S.work)) or nil
      local layout, why = CL.Import(text or "", host)
      -- Second result: what had to be repaired when it worked, the reason when it did not.
      d.layout, d.problems = layout, why
      if layout then
        local key = mgrFn("import") and "canvas.import.okNew" or "canvas.import.ok"
        W.SetText(d.status, nil, string.format(L[key], #layout.elements))
        d.go:Enable()
        return
      end
      local key = "canvas.import.err." .. tostring(why)
      W.SetText(d.status, L[key] ~= key and key or "canvas.import.err.decode")
      d.go:Disable()
    end
    d.go:SetScript(
      "OnClick",
      ns.Wrap("canvas-import", function()
        local layout, problems = d.layout, d.problems
        if not (layout and S) then
          return
        end
        d:Hide()
        if mgrFn("import") then
          act.importAs(layout, problems)
          return
        end
        layout.id, layout.name = S.work.id, layout.name ~= "" and layout.name or S.work.name
        adopt(layout, "import")
        ns.Notify(string.format(L["canvas.msg.imported"], type(problems) == "table" and #problems or 0), "success")
      end)
    )
  end
  importDlg.paste:SetValue("")
  importDlg.refresh("")
  importDlg:Show()
  importDlg.paste.edit:SetFocus()
end

act.import = showImport

-- Keyboard -------------------------------------------------------------------------------------

local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, -1 }, DOWN = { 0, 1 } }

local function insideWindow(f)
  while f do
    if f == frame then
      return true
    end
    f = f:GetParent()
  end
  return false
end

local function cycle(step)
  local list = CL.Sorted(S.work)
  if #list == 0 then
    return
  end
  local at = 0
  for i, e in ipairs(list) do
    if e.id == S.sel then
      at = i
    end
  end
  local nextAt = at == 0 and (step > 0 and 1 or #list) or ((at - 1 + step) % #list) + 1
  selectElement(list[nextAt].id)
end

-- Up and Down inside the layout list move the keyboard focus to the row above or below, scrolling the
-- list at its edge. Enter then switches (the focused row's button is pressed). True when handled.
local function moveLayoutFocus(step)
  local shown = {}
  local at
  for _, row in ipairs(ui.layoutRows) do
    if row:IsShown() then
      shown[#shown + 1] = row
      if row.name == ns.Focus.current then
        at = #shown
      end
    end
  end
  if not at then
    return false
  end
  if shown[at + step] then
    ns.Focus.set(shown[at + step].name)
  else
    ui.layoutList:ScrollBy(step)
  end
  return true
end

local function dialogOpen()
  for f in pairs(ns.Dialogs.open) do
    if f:IsShown() then
      return true
    end
  end
  return false
end

-- True when the key was used (it is then not passed on to the game).
local function handleKey(key)
  if not (S and frame:IsShown()) then
    return false
  end
  if key == "ESCAPE" then
    if S.drag then
      cancelDrag()
      return true
    end
    return ns.EscStack.Close(frame)
  end
  if dialogOpen() or not (frame:IsMouseOver() or S.drag) then
    return false
  end
  if S.drag then
    return false
  end
  local c = ctrl()
  if c then
    if key == "Z" then
      if shift() then
        act.redo()
      else
        act.undo()
      end
    elseif key == "Y" then
      act.redo()
    elseif key == "D" then
      act.duplicate()
    elseif key == "TAB" then
      ns.Focus.move(shift() and -1 or 1)
    else
      return false
    end
    return true
  end
  local focus = ns.Focus.current
  if (key == "UP" or key == "DOWN") and focus and focus.fgLayoutRow and insideWindow(focus) then
    return moveLayoutFocus(key == "UP" and -1 or 1)
  end
  local arrow = ARROWS[key]
  if arrow then
    if not sel() then
      return false
    end
    local step = shift() and 10 or 1
    act.nudge(arrow[1] * step, arrow[2] * step)
    return true
  end
  if key == "DELETE" or key == "BACKSPACE" then
    if sel() then
      act.remove()
      return true
    end
    return false
  end
  if key == "F2" then
    if sel() then
      act.focusName()
      return true
    end
    return false
  end
  if key == "TAB" then
    cycle(shift() and -1 or 1)
    return true
  end
  if key == "ENTER" or key == "SPACE" then
    local f = ns.Focus.current
    if f and insideWindow(f) then
      return ns.Focus.activate()
    end
  end
  return false
end

-- Side panel -----------------------------------------------------------------------------------

local function contrastRatio()
  local el = sel()
  local def = el and S.opts.types[el.type]
  if not (type(def) == "table" and type(def.textColor) == "function") then
    return nil
  end
  local ok, color = pcall(def.textColor, el)
  local text = ok and type(color) == "string" and color:match("^#?(%x%x%x%x%x%x)$")
  if not text then
    return nil
  end
  return Theme.contrastRatio("#" .. text, "#" .. S.work.canvas.bg)
end

-- The panel of the host for the selected element. A panel with Refresh is built once per type function.
local panelCache = setmetatable({}, { __mode = "k" })

local function onPanelChange()
  if S then
    local el = sel()
    changed("props:" .. (el and el.id or ""))
  end
end

local function showTypePanel(el)
  local def = el and S.opts.types[el.type]
  local build = type(def) == "table" and def.panel
  local cached = type(build) == "function" and panelCache[build] or nil
  -- The panel that is already shown stays shown: hiding it on every change would end the drag of a slider
  -- the player holds in it (the hide reaches the slider and the engine drops the drag).
  if ui.panel and ui.panel ~= cached then
    ui.panel:Hide()
    ui.panel = nil
  end
  if type(build) ~= "function" then
    return 0
  end
  local panel = cached
  if panel then
    ns.Safe("canvas-panel-refresh", panel.Refresh, panel, el)
  else
    local ok, made = ns.Safe("canvas-panel", build, ui.holder, el, onPanelChange)
    panel = ok and made or nil
    if not panel then
      return 0
    end
    -- rawget: the panel's own method, not a lookup in the client's frame methods.
    if type(rawget(panel, "Refresh")) == "function" then
      panelCache[build] = panel
    end
  end
  if ui.panel ~= panel then
    panel:SetParent(ui.holder)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", ui.holder, "TOPLEFT", 0, 0)
    panel:SetWidth(CONTENT_W)
    panel:Show()
    ui.panel = panel
  end
  local h = panel:GetHeight()
  return finite(h) and h > 0 and h or 40
end

local function layoutSide()
  local y = 0
  local content = ui.content
  local function put(f, h, x)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", content, "TOPLEFT", x or 0, -y)
    y = y + h
  end
  local el = sel()
  for _, f in ipairs(ui.elementParts) do
    f:SetShown(el ~= nil)
  end
  ui.nothing:SetShown(el == nil)
  -- Hidden first: the warning belongs to a selected element and must not stay behind at its old spot.
  ui.warn:Hide()
  if el then
    W.SetText(ui.headEl, nil, string.format(L["canvas.selectedTitle"], titleOf(el)))
    put(ui.headEl, 22)
    put(ui.name, 32)
    put(ui.remove, 32)
    put(ui.anchorBox, 0)
    ui.fx:ClearAllPoints()
    ui.fx:SetPoint("TOPLEFT", content, "TOPLEFT", 84, -y)
    ui.fy:ClearAllPoints()
    ui.fy:SetPoint("TOPLEFT", content, "TOPLEFT", 84 + 100, -y)
    ui.fw:ClearAllPoints()
    ui.fw:SetPoint("TOPLEFT", content, "TOPLEFT", 84, -y - 32)
    ui.fh:ClearAllPoints()
    ui.fh:SetPoint("TOPLEFT", content, "TOPLEFT", 84 + 100, -y - 32)
    y = y + 82
    local _, description = tipOf(el)
    ui.desc:SetShown(description ~= nil)
    if description then
      W.SetText(ui.desc, nil, description)
      local h = math.max(14, math.ceil(ui.desc:GetStringHeight() or 0) + 2)
      ui.desc:SetHeight(h)
      put(ui.desc, h + 8)
    end
    local panelH = showTypePanel(el)
    ui.holder:SetShown(panelH > 0)
    ui.holder:SetHeight(math.max(1, panelH))
    if panelH > 0 then
      put(ui.holder, panelH + 8)
    end
    local ratio = contrastRatio()
    local low = ratio ~= nil and ratio < MIN_CONTRAST
    if low then
      ui.warn:Show()
      W.SetText(ui.warn, nil, string.format(L["canvas.contrast"], string.format("%.1f", ratio)))
      -- The wrapped text decides the height, so the next row never starts inside it.
      local h = math.max(WARN_MIN_H, math.ceil(ui.warn:GetStringHeight() or 0) + 4)
      ui.warn:SetHeight(h)
      put(ui.warn, h + 8)
    end
  else
    local h = math.max(WARN_MIN_H, math.ceil(ui.nothing:GetStringHeight() or 0) + 4)
    ui.nothing:SetHeight(h)
    put(ui.nothing, h + 12)
    showTypePanel(nil)
    ui.holder:Hide()
  end
  put(ui.headCanvas, 22)
  put(ui.cw, 32)
  ui.ch:ClearAllPoints()
  ui.ch:SetPoint("TOPLEFT", ui.cw, "TOPLEFT", HALF_W + 8, 0)
  put(ui.bg, 32)
  put(ui.bgAlpha, 48)
  put(ui.borderOn, 30)
  local border = S.work.canvas.border ~= nil
  ui.borderColor:SetShown(border)
  ui.borderAlpha:SetShown(border)
  if border then
    put(ui.borderColor, 32)
    put(ui.borderAlpha, 48)
  end
  local cursor = cursorMode()
  ui.hotX:SetShown(cursor)
  ui.hotY:SetShown(cursor)
  ui.symmetric:SetShown(cursor)
  if cursor then
    put(ui.hotX, 32)
    ui.hotY:ClearAllPoints()
    ui.hotY:SetPoint("TOPLEFT", ui.hotX, "TOPLEFT", HALF_W + 8, 0)
    put(ui.symmetric, 30)
  end
  ui.props:SetContentHeight(y + 8)
end

local function refreshFields()
  local el = sel()
  if not el then
    return
  end
  if ui.nameFor ~= el.id then
    if ui.name.edit:HasFocus() then
      ui.name.edit:ClearFocus()
    end
    ui.nameFor = el.id
  end
  ui.name:Refresh()
  ui.fx:Refresh()
  ui.fy:Refresh()
  ui.fw:Refresh()
  ui.fh:Refresh()
  for point, b in pairs(ui.anchors) do
    b:SetSelected(el.point == point)
  end
end
ui = { refreshFields = refreshFields }

local function refreshList()
  local data = {}
  ui.listIndex = {}
  local sorted = CL.Sorted(S.work)
  for i = #sorted, 1, -1 do
    data[#data + 1] = sorted[i]
    ui.listIndex[sorted[i].id] = #data
  end
  ui.list:SetData(data)
  ui.elementsEmpty:SetShown(#data == 0)
  if S.sel and ui.list.Reveal then
    ui.list:Reveal(ui.listIndex[S.sel] or 1)
  end
end

-- The backdrop selector and the tool buttons of the view bar: only a stage has a backdrop, only the tools
-- of the host get buttons (kept between sessions, frames cannot be freed).
function refreshViewBar()
  local staged = stageOf() ~= nil
  ui.backdropDd:SetShown(staged)
  if staged then
    ui.backdropDd:Refresh()
  end
  local x = ui.toolX + (staged and BACKDROP_W + 12 or 0)
  for i = 1, math.max(#ui.tools, #S.tools) do
    local def = S.tools[i]
    local b = ui.tools[i]
    if def and not b then
      b = W.Action(ui.root, {
        icon = "reset",
        size = TOOL_SIZE,
        manual = true,
        wrap = "canvas-tool",
        onClick = function()
          if S and b.fgToolId then
            act.tool(b.fgToolId)
          end
        end,
      })
      b:HookScript("OnEnter", function(self)
        if self.fgNameKey then
          ns.ShowTooltip(self, L[self.fgNameKey])
        end
      end)
      b:HookScript("OnLeave", ns.HideTooltip)
      ui.tools[i] = b
    end
    if b then
      b:SetShown(def ~= nil)
      if def then
        b.fgToolId, b.fgNameKey = def.id, def.label
        b:SetIcon(type(def.icon) == "string" and ns.UI_ICONS[def.icon] and def.icon or "reset")
        b:SetSelected(S.toolOn[def.id] == true)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ui.root, "TOPLEFT", x, -ui.toolY)
        x = x + TOOL_SIZE + TOOL_GAP
      end
    end
  end
end

local function refreshTop()
  ui.undo:SetEnabled(CL.CanUndo(S.hist))
  ui.redo:SetEnabled(CL.CanRedo(S.hist))
  local presets = S.opts.presets or {}
  ui.preset:SetShown(#presets > 0)
  ui.add:SetShown(true)
  ui.reset:SetEnabled(#presets > 0)
  ui.preset:Refresh()
  ui.add:Refresh()
  ui.zoom:Refresh()
  ui.snapDd:Refresh()
  refreshViewBar()
  ui.grid:Refresh()
  ui.real:SetShown(hasRealValues())
  ui.real:Refresh()
  ui.liveTest:SetShown(type(S.opts.liveTest) == "function")
  ui.liveTest:Refresh()
  ui.live:Refresh()
  refreshManager()
  W.SetText(ui.discard.label, isDirty() and "canvas.discard" or "canvas.close")
end

function refreshAll()
  refreshTop()
  refreshList()
  local el = sel()
  if el then
    refreshFields()
  end
  ui.cw:Refresh()
  ui.ch:Refresh()
  ui.bg:Refresh()
  ui.bgAlpha:Refresh()
  ui.borderOn:Refresh()
  if S.work.canvas.border then
    ui.borderColor:Refresh()
    ui.borderAlpha:Refresh()
  end
  if cursorMode() then
    ui.hotX:Refresh()
    ui.hotY:Refresh()
    ui.symmetric:Refresh()
  end
  layoutSide()
end

-- Window parts ---------------------------------------------------------------------------------

-- Save and Save as new of the layout manager. Which of them shows depends on what the host's manager
-- offers (see refreshManager). Switching, renaming, copying and deleting live in the layout list.
local function buildManager(f)
  ui.mgrSave = W.Action(f, {
    icon = "save",
    size = TOOL_SIZE,
    tooltip = "act.save",
    tooltipText = "canvas.saveTip",
    onClick = act.save,
  })
  ui.mgrSaveAs = W.Action(f, {
    label = "canvas.saveAs",
    icon = "plus",
    height = TOOL_SIZE,
    tooltip = "canvas.saveAs",
    tooltipText = "canvas.saveAsTip",
    onClick = act.saveAs,
  })
end

-- A dropdown the editor anchors itself. Its wrapper frame has a height only, so it gets the width of its
-- button: without a width the client has no rectangle for it and may draw nothing.
local function placedDropdown(parent, opts)
  local dropdown = W.Dropdown(parent, opts)
  dropdown:SetWidth(opts.width)
  return dropdown
end

-- Where the band and the sidebar controls sit. Left: Save, Undo, Redo, Reset and Save as new in one
-- line (Save as new drops its text when the width runs out), under it Export, Import, preset and add.
-- Right: when the manager can list and select, the layout list over the full sidebar width. The
-- sidebar starts with the elements.
local function placeBand()
  local x = PAD
  -- Control and the manager function(s) it needs.
  for _, item in ipairs({
    { ui.mgrSave, "save" },
    { ui.undo },
    { ui.redo },
    { ui.reset },
  }) do
    local control = item[1]
    local shown = item[2] == nil or mgrFn(item[2]) ~= nil
    control:SetShown(shown)
    if shown then
      control:ClearAllPoints()
      control:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -BAND_Y)
      x = x + TOOL_SIZE + TOOL_GAP
    end
  end
  local canCreate = mgrFn("create") ~= nil
  ui.mgrSaveAs:SetShown(canCreate)
  if canCreate then
    x = x + 3
    ui.mgrSaveAs:ClearAllPoints()
    ui.mgrSaveAs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -BAND_Y)
    ui.mgrSaveAs:SetSize(ui.mgrSaveAs:Fit(PAD + LEFT_W - x), TOOL_SIZE)
  end
  -- Row 2: Export and Import (text and icon, icon only when the width runs out), then preset and add.
  local row2Y = BAND_Y + ROW2_Y
  local ex = PAD
  for _, button in ipairs({ ui.export, ui.importButton }) do
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", ex, -row2Y)
    local width = button:Fit(XFER_W)
    button:SetSize(width, TOOL_SIZE)
    ex = ex + width + XFER_GAP
  end
  ex = ex + 8 - XFER_GAP
  ui.preset:ClearAllPoints()
  ui.preset:SetPoint("TOPLEFT", frame, "TOPLEFT", ex, -row2Y)
  ui.add:ClearAllPoints()
  ui.add:SetPoint("TOPLEFT", frame, "TOPLEFT", ex + DROP_W + 8, -row2Y)

  local sx = PAD + LEFT_W + PAD
  local layouts = mgrFn("list") ~= nil and mgrFn("select") ~= nil
  ui.layoutHead:SetShown(layouts)
  ui.layoutList:SetShown(layouts)
  ui.layoutNew:SetShown(layouts and canCreate)
  if layouts then
    ui.layoutHead:ClearAllPoints()
    ui.layoutHead:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -(BAND_Y + 3))
    ui.layoutNew:ClearAllPoints()
    ui.layoutNew:SetPoint("TOPRIGHT", frame, "TOPLEFT", sx + RIGHT_W, -BAND_Y)
    ui.layoutList:ClearAllPoints()
    ui.layoutList:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -(BAND_Y + LAYOUT_HEAD_H))
    ui.layoutList:SetSize(RIGHT_W, LAYOUT_ROWS * ROW_H)
  end

  local y = BODY_Y
  ui.elementsHead:ClearAllPoints()
  ui.elementsHead:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -(y + 3))
  ui.elementsAdd:ClearAllPoints()
  ui.elementsAdd:SetPoint("TOPRIGHT", frame, "TOPLEFT", sx + RIGHT_W, -y)
  ui.list:ClearAllPoints()
  ui.list:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -(y + ELEMENTS_HEAD_H))
  ui.list:SetSize(RIGHT_W, ELEMENT_ROWS * ROW_H)
  y = y + ELEMENTS_HEAD_H + ELEMENT_ROWS * ROW_H + 6
  ui.props:ClearAllPoints()
  ui.props:SetPoint("TOPLEFT", frame, "TOPLEFT", sx, -y)
  ui.props:SetSize(RIGHT_W, BODY_H - (y - BODY_Y))
end

function refreshManager()
  ui.mgrSave:SetEnabled(isDirty())
  placeBand()
  if ui.layoutList:IsShown() then
    local list = layoutList()
    ui.layoutList:SetData(list)
    -- Scrolls to the open layout when it changes, not on every refresh (the player may be scrolling).
    if ui.layoutRevealed ~= S.layoutId then
      ui.layoutRevealed = S.layoutId
      for i, entry in ipairs(list) do
        if entry.id == S.layoutId then
          ui.layoutList:Reveal(i)
        end
      end
    end
  end
end

local function buildTop(f)
  local function tool(icon, tip, tipText, shortcut, onClick)
    return W.Action(f, {
      icon = icon,
      size = TOOL_SIZE,
      tooltip = tip,
      tooltipText = tipText,
      shortcut = shortcut,
      onClick = onClick,
    })
  end
  ui.undo = tool("undo", "act.undo", nil, "Ctrl+Z", function()
    act.undo()
  end)
  ui.redo = tool("redo", "act.redo", nil, "Ctrl+Y", function()
    act.redo()
  end)
  ui.reset = tool("reset", "canvas.reset", "canvas.resetTip", nil, function()
    act.reset()
  end)

  local presetOptions = {}
  ui.preset = placedDropdown(f, {
    key = "canvas.preset",
    width = DROP_W,
    options = presetOptions,
    get = function()
      return S and S.work.preset or "_"
    end,
    set = function(id)
      if id ~= "_" then
        act.preset(id)
      end
    end,
  })
  local presetRefresh = ui.preset.Refresh
  function ui.preset:Refresh()
    for i = #presetOptions, 1, -1 do
      presetOptions[i] = nil
    end
    presetOptions[1] = { value = "_", key = "canvas.presetPick" }
    for _, p in ipairs(S.opts.presets or {}) do
      presetOptions[#presetOptions + 1] = { value = p.id, text = p.name or p.id }
    end
    presetRefresh()
  end

  local addOptions = {}
  -- option value -> { kind, variant? }: a type with variants lists one entry per variant instead of itself.
  local addTargets = {}
  ui.add = placedDropdown(f, {
    key = "canvas.add",
    width = DROP_W,
    options = addOptions,
    get = function()
      return "_"
    end,
    set = function(value)
      local target = addTargets[value]
      if target then
        act.add(target.kind, target.variant)
      end
    end,
  })
  local addRefresh = ui.add.Refresh
  function ui.add:Refresh()
    for i = #addOptions, 1, -1 do
      addOptions[i] = nil
    end
    addTargets = {}
    addOptions[1] = { value = "_", key = "canvas.addPick" }
    local kinds = {}
    for kind, def in pairs(S.opts.types) do
      local tip = type(def) == "table" and localized(def.desc) or nil
      local variants = variantsOf(typeDef(kind))
      if #variants == 0 then
        addTargets[kind] = { kind = kind }
        kinds[#kinds + 1] = { value = kind, text = type(def) == "table" and def.label or kind, tooltip = tip }
      end
      for _, variant in ipairs(variants) do
        local value = kind .. ":" .. variant.id
        addTargets[value] = { kind = kind, variant = variant }
        kinds[#kinds + 1] = { value = value, text = localized(variant.label) or value, tooltip = tip }
      end
    end
    table.sort(kinds, function(a, b)
      return tostring(a.text) < tostring(b.text)
    end)
    for _, o in ipairs(kinds) do
      addOptions[#addOptions + 1] = o
    end
    addRefresh()
  end

  -- Export and Import sit in row 2 of the band; placeBand sizes them (text or icon only).
  local function transfer(label, icon, onClick)
    local b = W.Action(f, {
      label = label,
      icon = icon,
      tooltip = label,
      height = TOOL_SIZE,
      onClick = onClick,
    })
    b.fgManaged = true
    return b
  end
  ui.export = transfer("act.export", "export", function()
    act.export()
  end)
  ui.importButton = transfer("act.import", "import", function()
    act.import()
  end)
end

local function buildView(f)
  local view = CreateFrame("Frame", nil, f)
  view:SetSize(LEFT_W, VIEW_H)
  view:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -BODY_Y)
  view:SetClipsChildren(true)
  W.Fill(view, "surface", 1)
  W.Border(view, "white", 0.25)
  ui.view = view
  ui.root = f
  -- The backdrop of a stage: above the fill of the view, below the canvas.
  ui.backdrop = view:CreateTexture(nil, "BACKGROUND")
  ui.backdrop:SetDrawLayer("BACKGROUND", 2)
  ui.backdrop:SetAllPoints(view)
  ui.backdrop:Hide()
  ui.checker = {}
  ui.canvas = CreateFrame("Frame", nil, view)
  -- The mouse surface and the overlay in one: above the drawn elements, whatever they catch themselves.
  local surface = CreateFrame("Frame", nil, view)
  surface:SetAllPoints(view)
  surface:SetFrameLevel(view:GetFrameLevel() + 120)
  surface:EnableMouse(true)
  surface:EnableMouseWheel(true)
  surface:SetScript("OnMouseDown", ns.Wrap("canvas-down", onMouseDown))
  surface:SetScript("OnMouseUp", ns.Wrap("canvas-up", onMouseUp))
  surface:SetScript("OnUpdate", ns.Wrap("canvas-update", onUpdate))
  surface:SetScript("OnMouseWheel", ns.Wrap("canvas-wheel", onWheel))
  ui.surface = surface
  ui.marker = surface:CreateTexture(nil, "ARTWORK")
  ui.marker:SetDrawLayer("ARTWORK", 2)
  ui.marker:Hide()
  ui.pools = {}
  for _, name in ipairs({ "grid", "bounds", "select", "handle", "guide" }) do
    ui.pools[name] = { n = 0 }
  end

  -- Handles on the edge of the canvas: plain frames above the mouse surface, a dark rim around a light
  -- square, so they read against the preview without relying on color.
  ui.canvasHandles = {}
  for _, name in ipairs(HANDLES) do
    local handle = CreateFrame("Frame", nil, view)
    handle:SetSize(CANVAS_HANDLE_FRAME, CANVAS_HANDLE_FRAME)
    handle:SetFrameLevel(surface:GetFrameLevel() + 5)
    handle:EnableMouse(true)
    handle.rim = handle:CreateTexture(nil, "OVERLAY")
    handle.rim:SetSize(HANDLE_SIZE + 4, HANDLE_SIZE + 4)
    handle.rim:SetPoint("CENTER")
    handle.rim:SetColorTexture(0, 0, 0, 1)
    handle.square = handle:CreateTexture(nil, "OVERLAY")
    handle.square:SetDrawLayer("OVERLAY", 1)
    handle.square:SetSize(HANDLE_SIZE + 2, HANDLE_SIZE + 2)
    handle.square:SetPoint("CENTER")
    handle.square:SetColorTexture(1, 1, 1, 1)
    handle:SetScript(
      "OnMouseDown",
      ns.Wrap("canvas-handle-down", function(_, button)
        beginCanvasDrag(name, button)
      end)
    )
    handle:SetScript("OnMouseUp", ns.Wrap("canvas-handle-up", onMouseUp))
    handle:SetScript("OnEnter", function(self)
      ns.ShowTooltip(self, L["canvas.resizeHandle"])
    end)
    handle:SetScript("OnLeave", ns.HideTooltip)
    ui.canvasHandles[name] = handle
  end

  -- View bar below the preview.
  local bx, by = PAD, BODY_Y + VIEW_H + 6
  -- The steps follow the kind of canvas: the list is refilled in place on every read.
  local zoomOptions = {}
  ui.zoom = placedDropdown(f, {
    key = "canvas.zoom",
    width = 90,
    options = zoomOptions,
    get = function()
      for i = #zoomOptions, 1, -1 do
        zoomOptions[i] = nil
      end
      for _, z in ipairs(S and zoomSteps() or CE.ZOOMS) do
        zoomOptions[#zoomOptions + 1] = { value = z, text = string.format("%d%%", z * 100) }
      end
      return S and S.step or 1
    end,
    set = function(z)
      act.zoom(z)
    end,
  })
  ui.zoom:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -by)
  bx = bx + 90 + 8
  local snapOptions = {}
  for _, s in ipairs(CE.SNAPS) do
    snapOptions[#snapOptions + 1] = s == 0 and { value = 0, key = "canvas.snapOff" }
      or { value = s, text = string.format(L["canvas.snapPx"], s) }
  end
  ui.snapDd = placedDropdown(f, {
    key = "canvas.snap",
    width = 90,
    options = snapOptions,
    get = function()
      return S and S.snap or 0
    end,
    set = function(s)
      act.snap(s)
    end,
  })
  ui.snapDd:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -by)
  bx = bx + 90 + 8

  -- Backdrop of a stage and the simulation tools; both only show when the host asks for them.
  local backdropOptions = {}
  ui.backdropDd = placedDropdown(f, {
    key = "canvas.backdrop",
    width = BACKDROP_W,
    options = backdropOptions,
    get = function()
      for i = #backdropOptions, 1, -1 do
        backdropOptions[i] = nil
      end
      if S then
        for _, b in ipairs(backdropList()) do
          backdropOptions[#backdropOptions + 1] = { value = b.id, key = b.label }
        end
      end
      return S and S.backdrop or nil
    end,
    set = function(id)
      act.backdrop(id)
    end,
  })
  ui.backdropDd:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -by)
  ui.backdropDd:Hide()
  ui.toolX, ui.toolY = bx, by + W.DROPDOWN_FIELD_Y
  ui.tools = {}
end

-- A list row: show toggle, name (selects), forward, backward.
local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.eye = W.Action(row, {
    icon = "eye",
    size = 22,
    tooltip = "canvas.visible",
    onClick = function()
      act.toggleVisible(row.id)
    end,
  })
  row.eye:SetPoint("LEFT", 0, 0)
  -- Remove and rename sit at the right edge, next to the arrows; both have the size of the other icons.
  row.del = W.Action(row, {
    icon = "trash",
    size = 22,
    tooltip = "act.remove",
    tooltipText = "canvas.removeRowTip",
    onClick = function()
      act.remove(row.id)
    end,
  })
  row.del:SetPoint("RIGHT", 0, 0)
  row.ren = W.Action(row, {
    icon = "pencil",
    size = 22,
    tooltip = "act.rename",
    tooltipText = "canvas.renameElementTip",
    onClick = function()
      act.focusName(row.id)
    end,
  })
  row.ren:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
  row.down = W.Action(row, {
    icon = "chevron-down",
    size = 22,
    tooltip = "canvas.backward",
    onClick = function()
      act.reorder(row.id, "down")
    end,
  })
  row.down:SetPoint("RIGHT", row.ren, "LEFT", -2, 0)
  row.up = W.Action(row, {
    icon = "chevron-up",
    size = 22,
    tooltip = "canvas.forward",
    onClick = function()
      act.reorder(row.id, "up")
    end,
  })
  row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
  row.name = W.Action(row, {
    text = " ",
    variant = "ghost",
    height = 22,
    width = 100,
    wrap = "canvas-row",
    onClick = function()
      selectElement(row.id)
    end,
  })
  row.name:SetPoint("LEFT", row.eye, "RIGHT", 2, 0)
  row.name:SetPoint("RIGHT", row.up, "LEFT", -2, 0)
  row.name.label:SetJustifyH("LEFT")
  -- The accessible name is the whole name, the row may show a cut one.
  row.name.fgName = function()
    return row.fullName
  end
  -- Hover and keyboard focus on the name tell what the type is for; the small buttons keep their own tips.
  local function tip(self)
    if row.tipText or row.tipLines then
      ns.ShowTooltip(self, row.tipTitle, row.tipText, row.tipLines and { lines = row.tipLines } or nil)
    end
  end
  row.name:HookScript("OnEnter", tip)
  row.name:HookScript("OnLeave", ns.HideTooltip)
  row.name.fgOnFocus, row.name.fgOnBlur = tip, ns.HideTooltip
  return row
end

-- A row of the layout list: the check mark of the open layout, its name (switches), then rename,
-- duplicate and delete as icons in fixed slots from the right edge.
local LAYOUT_ICON, LAYOUT_FLAG_W = 22, 14

local function createLayoutRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  ui.layoutRows[#ui.layoutRows + 1] = row
  row.mark = W.Glyph(row, "check", 14, "accent2")
  row.mark:SetPoint("LEFT", 4, 0)
  row.flag = W.Text(row, { text = "*", role = "ui", color = "warning", justify = "RIGHT" })
  row.flag:SetWidth(LAYOUT_FLAG_W - 4)
  local function icon(name, tip, tipText, onClick)
    return W.Action(row, {
      icon = name,
      size = LAYOUT_ICON,
      tooltip = tip,
      tooltipText = tipText,
      wrap = "canvas-layout-row",
      onClick = onClick,
    })
  end
  row.del = icon("trash", "act.delete", "canvas.deleteTip", function()
    act.deleteLayout(row.id)
  end)
  row.dup = icon("copy", "act.duplicate", "canvas.dupTip", function()
    act.dupLayout(row.id)
  end)
  row.ren = icon("pencil", "act.rename", "canvas.renameTip", function()
    act.rename(row.id)
  end)
  row.name = W.Action(row, {
    text = " ",
    variant = "ghost",
    height = LAYOUT_ICON,
    width = 100,
    wrap = "canvas-layout-row",
    onClick = function()
      act.switchTo(row.id)
    end,
  })
  row.name.label:SetJustifyH("LEFT")
  row.name.fgLayoutRow = true
  -- The accessible name is the layout's own name.
  row.name.fgName = function()
    return row.fullName
  end
  -- The state of the row (open, unsaved) is told by tooltip too, on hover and on keyboard focus.
  local function tip(self)
    local key = row.dirty and "canvas.layoutDirtyTip"
      or (row.current and "canvas.layoutCurrentTip" or "canvas.layoutOpenTip")
    ns.ShowTooltip(self, row.fullName, L[key])
  end
  row.name:HookScript("OnEnter", tip)
  row.name:HookScript("OnLeave", ns.HideTooltip)
  row.name.fgOnFocus, row.name.fgOnBlur = tip, ns.HideTooltip
  return row
end

local function bindLayoutRow(row, entry)
  row.id, row.fullName = entry.id, entry.name
  row.current = entry.id == S.layoutId
  -- Only the open layout can hold unsaved changes: a switch asks about them first.
  row.dirty = row.current and isDirty()
  row.mark:SetShown(row.current)
  W.SetText(row.name.label, nil, entry.name)
  row.name:SetSelected(row.current)
  local slots = 0
  for _, item in ipairs({
    { row.del, mgrFn("delete") ~= nil },
    { row.dup, mgrFn("create") ~= nil },
    { row.ren, mgrFn("rename") ~= nil },
  }) do
    local button, offered = item[1], item[2]
    button:Hide()
    if offered then
      button:ClearAllPoints()
      button:SetPoint("RIGHT", row, "RIGHT", -slots * (LAYOUT_ICON + 2), 0)
      slots = slots + 1
      -- A layout the host will not delete (the last one) shows no delete icon.
      button:SetShown(button ~= row.del or canDelete(entry.id))
    end
  end
  local edge = slots * (LAYOUT_ICON + 2)
  -- The star of unsaved changes has its own slot, so a long name cannot push it out of sight.
  row.flag:SetShown(row.dirty)
  row.flag:ClearAllPoints()
  row.flag:SetPoint("RIGHT", row, "RIGHT", -edge - 2, 0)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row, "LEFT", 22, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -edge - (row.dirty and LAYOUT_FLAG_W or 0), 0)
end

local function bindRow(row, el)
  row.id = el.id
  local on = el.visible ~= false
  row.eye:SetIcon(on and "eye" or "eye-off")
  W.SetText(row.name.label, nil, titleOf(el))
  row.tipTitle, row.tipText, row.tipLines = rowTip(el)
  row.fullName = titleOf(el)
  row.name:SetSelected(el.id == S.sel)
end

local function numberField(parent, key, prop, lo, hi)
  local c = Controls.Number(parent, {
    label = "canvas.field." .. key,
    tooltip = "canvas.field." .. key .. "Tip",
    min = lo,
    max = hi,
    step = 0.5,
    labelWidth = 16,
    get = function()
      local el = sel()
      return el and el[prop]
    end,
    set = function(v)
      local el = sel()
      if el then
        el[prop] = v
        changed("field:" .. prop .. ":" .. el.id)
      end
    end,
  })
  c:SetWidth(96)
  return c
end

local function buildSide(f)
  -- placeBand sets every position and size (the layout list only shows with a manager).
  ui.layoutHead = W.Text(f, { key = "canvas.layouts", role = "ui", color = "accent2" })
  ui.layoutHead:SetSize(RIGHT_W - 84, 18)
  ui.layoutNew = W.Action(f, {
    label = "act.new",
    icon = "plus",
    tooltip = "act.new",
    tooltipText = "canvas.newTip",
    height = 22,
    width = 80,
    onClick = function()
      act.saveAs()
    end,
  })
  ui.layoutRows = {}
  ui.layoutList = W.ScrollList(f, {
    rowHeight = ROW_H,
    createRow = createLayoutRow,
    bindRow = bindLayoutRow,
  })

  ui.elementsHead = W.Text(f, { key = "canvas.elements", role = "ui", color = "accent2" })
  -- Same choice as the Add element dropdown of the band, where the player looks first.
  ui.elementsAdd = W.Action(f, {
    label = "canvas.addShort",
    icon = "plus",
    tooltip = "canvas.add",
    height = 22,
    width = 110,
    onClick = function()
      ui.add:Refresh()
      ui.add:Open(ui.elementsAdd)
    end,
  })
  ui.list = W.ScrollList(f, {
    rowHeight = ROW_H,
    createRow = createRow,
    bindRow = bindRow,
  })
  ui.listIndex = {}
  -- A region of the list itself: the list is a frame above the window, so text of the window would lie behind it.
  ui.elementsEmpty =
    W.Text(ui.list, { key = "canvas.elementsEmpty", role = "ui", color = "textSecondary", wrap = true })
  ui.elementsEmpty:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 8, -8)
  ui.elementsEmpty:SetWidth(RIGHT_W - 16)

  local props = W.ScrollArea(f)
  ui.props, ui.content = props, props.content
  local c = props.content
  local function heading(key)
    local text = W.Text(c, { key = key, role = "ui", color = "accent2" })
    text:SetHeight(18)
    return text
  end

  ui.nothing = W.Text(c, { key = "canvas.nothing", role = "ui", color = "textSecondary", wrap = true })
  ui.nothing:SetWidth(CONTENT_W)
  ui.headEl = heading("canvas.selected")
  ui.name = Controls.Text(c, {
    label = "canvas.name",
    inline = true,
    labelWidth = 50,
    maxLetters = CL.MAX_NAME,
    commit = true,
    -- The field belongs to the element it was loaded for, so leaving it after a click on another element
    -- still names the first one.
    get = function()
      local el = S and ui.nameFor and CL.Find(S.work, ui.nameFor)
      return el and el.name or ""
    end,
    set = function(text)
      if S and ui.nameFor then
        act.renameElement(ui.nameFor, text)
      end
    end,
  })
  ui.name:SetWidth(CONTENT_W)
  ui.name.edit:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["canvas.name"], L["canvas.nameTip"])
  end)
  ui.name.edit:HookScript("OnLeave", ns.HideTooltip)
  ui.remove = W.Action(c, {
    key = "canvas.removeElement",
    icon = "trash",
    variant = "danger",
    tooltip = "canvas.removeElement",
    tooltipText = "canvas.removeTip",
    height = 24,
    width = REMOVE_W,
    wrap = "canvas-remove",
    onClick = function()
      act.remove()
    end,
  })

  ui.anchorBox = CreateFrame("Frame", nil, c)
  ui.anchorBox:SetSize(76, 76)
  ui.anchors = {}
  for i, point in ipairs(CL.POINTS) do
    local b = W.Action(ui.anchorBox, {
      text = "",
      width = 24,
      height = 24,
      tooltip = POINT_TEXT[point],
      wrap = "canvas-anchor",
      onClick = function()
        act.setAnchor(point)
      end,
    })
    b:SetPoint("TOPLEFT", ui.anchorBox, "TOPLEFT", ((i - 1) % 3) * 26, -math.floor((i - 1) / 3) * 26)
    ui.anchors[point] = b
  end
  ui.fx = numberField(c, "x", "x", -CL.MAX_OFFSET, CL.MAX_OFFSET)
  ui.fy = numberField(c, "y", "y", -CL.MAX_OFFSET, CL.MAX_OFFSET)
  ui.fw = numberField(c, "w", "w", 0, CL.MAX_SIZE)
  ui.fh = numberField(c, "h", "h", 1, CL.MAX_SIZE)

  ui.holder = CreateFrame("Frame", nil, c)
  ui.holder:SetSize(CONTENT_W, 1)
  ui.warn = W.Text(c, { role = "ui", color = "warning", wrap = true })
  ui.warn:SetWidth(CONTENT_W)
  -- What the type of the selected element is for; the height follows the wrapped text.
  ui.desc = W.Text(c, { role = "ui", color = "textMuted", wrap = true })
  ui.desc:SetWidth(CONTENT_W)
  ui.headEl:SetWidth(CONTENT_W)
  ui.elementParts = { ui.headEl, ui.name, ui.remove, ui.anchorBox, ui.fx, ui.fy, ui.fw, ui.fh, ui.desc }

  ui.headCanvas = heading("canvas.settings")
  local function canvasNumber(key, prop, lo, hi)
    local n = Controls.Number(c, {
      label = key,
      min = lo,
      max = hi,
      step = 1,
      labelWidth = 48,
      get = function()
        return S and S.work.canvas[prop]
      end,
      set = function(v)
        S.work.canvas[prop] = v
        CL.Clamp(S.work, S.measure)
        changed("canvas:" .. prop)
      end,
    })
    n:SetWidth(HALF_W)
    return n
  end
  ui.cw = canvasNumber("canvas.cw", "w", CL.MIN_CANVAS, CL.MAX_CANVAS)
  ui.ch = canvasNumber("canvas.ch", "h", CL.MIN_CANVAS, CL.MAX_CANVAS)
  ui.bg = Controls.Color(c, {
    label = "canvas.bg",
    owner = f,
    default = CL.CANVAS.bg,
    get = function()
      return S and S.work.canvas.bg
    end,
    set = function(hex)
      S.work.canvas.bg = hex
      changed("canvas:bg")
    end,
  })
  ui.bg:SetWidth(CONTENT_W)
  ui.bgAlpha = Controls.Slider(c, {
    label = "canvas.bgAlpha",
    min = 0,
    max = 100,
    step = 5,
    get = function()
      return S and math.floor(S.work.canvas.bgAlpha * 100 + 0.5) or 0
    end,
    set = function(v)
      S.work.canvas.bgAlpha = v / 100
      changed("canvas:alpha")
    end,
    format = function(v)
      return v .. "%"
    end,
  })
  ui.bgAlpha:SetWidth(CONTENT_W)
  ui.borderOn = W.Checkbox(c, {
    key = "canvas.border",
    get = function()
      return S ~= nil and S.work.canvas.border ~= nil
    end,
    set = function(on)
      S.work.canvas.border = on and (S.lastBorder or "ffffff") or nil
      if not on then
        S.lastBorder = nil
      end
      changed("canvas:border")
    end,
  })
  ui.borderOn:SetSize(CONTENT_W, 22)
  ui.borderColor = Controls.Color(c, {
    label = "canvas.borderColor",
    owner = f,
    default = "ffffff",
    get = function()
      return S and S.work.canvas.border
    end,
    set = function(hex)
      S.work.canvas.border = hex
      S.lastBorder = hex
      changed("canvas:borderColor")
    end,
  })
  ui.borderColor:SetWidth(CONTENT_W)
  ui.borderAlpha = Controls.Slider(c, {
    label = "canvas.borderAlpha",
    min = 0,
    max = 100,
    step = 5,
    get = function()
      return S and math.floor(S.work.canvas.borderAlpha * 100 + 0.5) or 100
    end,
    set = function(v)
      S.work.canvas.borderAlpha = v / 100
      changed("canvas:borderAlpha")
    end,
    format = function(v)
      return v .. "%"
    end,
  })
  ui.borderAlpha:SetWidth(CONTENT_W)

  -- The hotspot of a cursor canvas: the point that sits on the mouse cursor (percent of the canvas).
  local function hotNumber(key, prop)
    local n = Controls.Number(c, {
      label = key,
      tooltip = "canvas.hotTip",
      min = 0,
      max = 100,
      step = 1,
      labelWidth = 64,
      get = function()
        local v = S and S.work.canvas[prop]
        return S and math.floor((finite(v) and v or CL.HOT_DEFAULT) * 100 + 0.5)
      end,
      set = function(v)
        S.work.canvas[prop] = v / 100
        S.work.canvas.symmetric = false
        changed("canvas:" .. prop)
      end,
    })
    n:SetWidth(HALF_W)
    return n
  end
  ui.hotX = hotNumber("canvas.hotX", "hotX")
  ui.hotY = hotNumber("canvas.hotY", "hotY")
  ui.symmetric = W.Checkbox(c, {
    key = "canvas.symmetric",
    tooltip = "canvas.symmetric",
    tooltipText = "canvas.symmetricTip",
    get = function()
      return S ~= nil and S.work.canvas.symmetric == true
    end,
    set = function(on)
      local cv = S.work.canvas
      cv.symmetric = on == true
      if on then
        cv.hotX, cv.hotY = CL.HOT_DEFAULT, CL.HOT_DEFAULT
      end
      changed("canvas:symmetric")
    end,
  })
  ui.symmetric:SetSize(CONTENT_W, 22)
end

local function buildFooter(f)
  local y = WIN_H - FOOT_H
  ui.live = W.Checkbox(f, {
    key = "canvas.live",
    tooltip = "canvas.live",
    tooltipText = "canvas.liveTip",
    get = function()
      return S ~= nil and S.live
    end,
    set = function(on)
      S.live = on
      if on then
        send()
      end
    end,
  })
  ui.live:SetSize(70, 22)
  ui.live:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 8))
  ui.help = W.InfoButton(f, "canvas.help.title", "canvas.help.keys")
  ui.help:SetPoint("LEFT", ui.live, "RIGHT", 8, 0)
  ui.grid = W.Checkbox(f, {
    key = "canvas.grid",
    get = function()
      return S ~= nil and S.grid
    end,
    set = function(on)
      S.grid = on
      frameDb().grid = on
      paintOverlay()
    end,
  })
  ui.grid:SetSize(140, 22)
  ui.grid:SetPoint("LEFT", ui.help, "RIGHT", 20, 0)
  ui.real = W.Checkbox(f, {
    key = "canvas.real",
    tooltip = "canvas.real",
    tooltipText = "canvas.realTip",
    get = function()
      return S ~= nil and S.real
    end,
    set = function(on)
      S.real = on
      redraw()
    end,
  })
  ui.real:SetSize(150, 22)
  ui.real:SetPoint("LEFT", ui.grid, "RIGHT", 12, 0)
  ui.liveTest = W.Checkbox(f, {
    key = "canvas.liveTest",
    tooltip = "canvas.liveTest",
    tooltipText = "canvas.liveTestTip",
    get = function()
      return S ~= nil and S.liveTest == true
    end,
    set = function(on)
      act.liveTest(on)
    end,
  })
  ui.liveTest:SetSize(150, 22)
  ui.liveTest:SetPoint("LEFT", ui.real, "RIGHT", 12, 0)
  ui.discard = W.Action(f, {
    text = " ",
    icon = "close",
    tooltip = "canvas.discard",
    tooltipText = "canvas.discardTip",
    width = 130,
    height = 28,
    onClick = function()
      act.discard()
    end,
  })
  ui.discard:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)
  ui.apply = W.Action(f, {
    label = "act.apply",
    icon = "check",
    tooltip = "act.apply",
    variant = "primary",
    width = 130,
    height = 28,
    onClick = function()
      act.apply()
    end,
  })
  ui.apply:SetPoint("RIGHT", ui.discard, "LEFT", -8, 0)
end

-- Window ---------------------------------------------------------------------------------------

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function applyLook(f)
  local style = WS.Resolve("canvaseditor", frameDb().style)
  -- The chrome never fades: its controls sit over the page behind the window.
  style.autoHide = false
  WS.Apply(f, style, f.styleParts)
  return style
end

-- Scale: mouse wheel with the windowScale key on the title bar, the top left corner stays where it is.
local function changeScale(f, delta)
  local db = frameDb()
  savePosition(f)
  db.scale = U.clamp(math.floor(scaleOf(db) * 100 + delta * SCALE_STEP * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
  f:SetScale(db.scale)
  place(f)
  -- A cursor canvas keeps its true size on the screen while the window scale changes.
  if S and cursorMode() then
    S.zoom = factorOf(S.step)
    redraw()
  end
end

-- Solid surfaces under the toolbar band and the sidebar column: a translucent shell (skin, style) must
-- not let the page behind the window show through the controls.
local function buildSurfaces(f)
  local function solid(left, top, width, height)
    local tex = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top)
    tex:SetSize(width, height)
    ns.Bind(tex, function(t)
      t:SetColorTexture(Theme.color("surface", 1))
    end)
    return tex
  end
  f.bandFill = solid(0, HEAD_H, WIN_W, BODY_Y - 3 - HEAD_H)
  local sx = PAD + LEFT_W + PAD / 2
  f.sideFill = solid(sx, BODY_Y - 3, WIN_W - sx, BODY_H + 6)
end

local function create()
  local f = CreateFrame("Frame", "FGCanvasEditor", UIParent)
  -- Same strata as the main window, so the clicked window is the one in front.
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetSize(WIN_W, WIN_H)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "canvas.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f:SetScript(
    "OnDragStop",
    ns.Wrap("canvas-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("canvas-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "common.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("canvas-close", function()
      act.discard()
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.close, "LEFT", -4, 0)

  buildSurfaces(f)
  ui = ui or {}
  buildManager(f)
  buildTop(f)
  buildView(f)
  buildSide(f)
  buildFooter(f)
  -- The preview stacks its surface and handles far above the window; the band dropdowns go above that
  -- (the popup lies in a higher strata). A frame keeps its children's levels, so each part gets its own.
  local level = ui.surface:GetFrameLevel() + 10
  for _, dropdown in ipairs({ ui.preset, ui.add }) do
    dropdown:SetFrameLevel(level)
    dropdown.button:SetFrameLevel(level + 1)
    dropdown.arrow:SetFrameLevel(level + 2)
  end
  f.ui = ui

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar },
    busy = function()
      return WS.PickerOpenFor(f)
    end,
  }

  -- Hidden before the hooks exist: the first Hide must not end a session.
  f:Hide()
  -- Own key handler first: the shell only installs its Esc handler on a window that has none.
  f:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then
      return
    end
    local _, handled = ns.Safe("canvas-key", handleKey, key)
    ns.PropagateKeys(self, not handled)
  end)
  ns.WindowShell.RegisterEsc(f, function()
    if S and isDirty() then
      act.discard()
      return true
    end
    return false
  end)
  f:HookScript("OnHide", function()
    finish()
  end)
  return f
end

-- API ------------------------------------------------------------------------------------------

local function validSnap(v)
  for _, s in ipairs(CE.SNAPS) do
    if s == v then
      return v
    end
  end
  return 0
end

-- Opens the editor for opts (see the top of the file). Returns the window, nil for unusable options.
function CE.Open(opts)
  if not (ns.db and type(opts) == "table" and type(opts.layout) == "table" and type(opts.types) == "table") then
    return nil
  end
  if S then
    finish()
  end
  local db = frameDb()
  local work = CL.Validate(opts.layout)
  S = {
    opts = opts,
    work = work,
    base = U.copy(work),
    hist = CL.History(work, now),
    snap = validSnap(db.snap),
    grid = db.grid == true,
    -- Live and the real values start on at every opening: they are the state the player expects to see.
    live = true,
    liveTest = false,
    panX = 0,
    panY = 0,
    mgr = type(opts.manager) == "table" and opts.manager or nil,
    tools = {},
    toolOn = {},
  }
  for _, def in ipairs(type(opts.tools) == "table" and opts.tools or {}) do
    if
      #S.tools < CE.MAX_TOOLS
      and type(def) == "table"
      and type(def.id) == "string"
      and type(def.label) == "string"
    then
      S.tools[#S.tools + 1] = def
      S.toolOn[def.id] = def.toggle == true and def.active == true
    end
  end
  S.backdrop = stageOf() and backdropById(db.backdrop).id or nil
  S.real = hasRealValues()
  ui.layoutRevealed = nil
  if not frame then
    frame = create()
  end
  S.measure = CR.Measurer(ui.canvas)
  CR.Clear(ui.canvas)
  local _, current = mgrCall("current")
  S.layoutId = current ~= nil and current or work.id
  updateTitle()
  frame:SetScale(scaleOf(db))
  -- The zoom needs the scale of the window (a cursor canvas shows the true size).
  S.step = bestZoom()
  S.zoom = factorOf(S.step)
  local marker = stageOf() and stageOf().marker
  if type(marker) == "table" then
    if marker.atlas then
      ui.marker:SetAtlas(marker.atlas)
    elseif marker.texture ~= nil then
      ui.marker:SetTexture(marker.texture)
    end
  end
  paintBackdrop()
  place(frame)
  frame:Show()
  frame:Raise()
  applyLook(frame)
  place(frame)
  redraw()
  refreshAll()
  return frame
end

-- Closes without a question: live changes are taken back, onCancel runs.
function CE.Close()
  if S then
    act.discard(true)
  end
end

function CE.IsOpen()
  return S ~= nil and frame ~= nil and frame:IsShown()
end

function CE.Frame()
  return frame
end

function CE.Layout()
  return S and U.copy(S.work) or nil
end

function CE.Selected()
  return S and S.sel or nil
end

-- Draws the preview again, for a host whose simulation (opts.sim) changed. Not a change of the layout:
-- no undo step, the layout stays as clean as it was.
function CE.Redraw()
  if S and ui then
    redraw()
  end
end

function CE.Select(id)
  if S then
    selectElement(id)
  end
end

function CE.Apply()
  if S then
    act.apply()
  end
end

function CE.Discard(force)
  act.discard(force)
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "canvaseditor") then
    applyLook(frame)
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
  end
end)
