-- Drawing editor window: a Paint-like tool for the raster drawings of
-- Modules\Drawings.lua. One window per session, movable and resizable, its
-- position, size and open state live in ns.db.frames.drawingEditor (same
-- scheme as the route window). The bitmap model, tools and undo history come
-- from DrawingLogic, the picture is painted by DrawingView. The canvas can be
-- resized like in Paint: three drag handles at the right edge, bottom edge and
-- bottom right corner, the "Resize canvas..." dialog and "Crop to selection"
-- (Edit menu). Every resize is one undo step that also restores cropped-off
-- cells. The zoom (cell size in pixels) is separate.
--
-- Layout (top to bottom): title bar, menu bar with quick icons and the name
-- field, ribbon (selection, image, tools, brush, shapes, colors), the stage
-- (brush size slider on the left, scrollable canvas on a dark surround) and a
-- status bar (cursor cell, selection, canvas size, hint, fit button, zoom).
-- The widgets come from UI\Desktop*.lua. When the ribbon does not fit the
-- width, the shapes group collapses into dropdowns; the window never gets
-- narrower than the collapsed ribbon.
--
-- Mouse input: the viewport frame gets OnMouseDown, OnUpdate then polls the
-- cursor (GetCursorPosition through the frame scale) and feeds the editor once
-- per changed cell (soft or smoothed freehand strokes: once per quarter cell,
-- with the fractional position); the release is taken from OnMouseUp and from
-- polling IsMouseButtonDown, so a release outside the window still ends the stroke.
--
-- Background map: the Map group of the ribbon (and the Edit menu) opens the "Choose map" window
-- (DrawingMapPicker). The map is part of the drawing (doc.drawing.map, a key only), drawn under
-- the cells by DrawingView and saved with them; it is no undo step. Over a map the pen draws hard
-- edges (soft edges would blend against white).
--
-- Soft edges, stroke smoothing and the fill tolerance are editor settings kept
-- with the window state (frames.drawingEditor). The status bar shows the packed
-- size of the drawing and how it can be shared in chat; the size is worked out
-- (three deflate passes) 0.4 s after the last change, never while drawing.
local _, ns = ...
local W, L, Theme, U, D, DR, V = ns.W, ns.L, ns.Theme, ns.U, ns.DrawingLogic, ns.Drawings, ns.DrawingView
local Desktop, IconDraw = ns.Desktop, ns.IconDraw

local DE = {}
ns.DrawingEditor = DE

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil

-- Size floors (the width floor rises with the collapsed ribbon, see layout()).
local MIN_W, MIN_H, MAX_W, MAX_H = 700, 460, 1400, 1000
local DEFAULT_W, DEFAULT_H = 900, 680
local HEAD_H = 24
-- Base pixels, scaled with the font size where they hold text or icons.
local TOP_H, RIBBON_H, STATUS_H = 36, 100, 24
local SIDE_W, STAGE_PAD = 56, 6
local PANEL_H = 212
local PALETTE_COLS, PALETTE_VISIBLE, MORE_COLS = 10, 30, 16
local ZOOM_MIN, ZOOM_MAX = 1, 16
-- Resize handles: the hit area is HANDLE_HIT square (well above the 10 px
-- minimum), the visible square HANDLE_VIS plus a 1 px outline. The scroll area
-- keeps HANDLE_MARGIN free on every side of the canvas, so the handles stay
-- reachable when the canvas fills the viewport.
local HANDLE_HIT, HANDLE_VIS, HANDLE_MARGIN = 14, 8, 16
DE.HANDLE_MARGIN, DE.HANDLE_HIT = HANDLE_MARGIN, HANDLE_HIT
local ZOOM_STEPS = { 1, 2, 3, 4, 6, 8, 12, 16 }
local SHAPE_TOOLS = { line = true, rect = true, ellipse = true }
local scaled = Desktop.scaled

ns.AddLocale("enUS", {
  ["draw.editor.title"] = "Drawing",
  ["draw.untitled"] = "Untitled drawing",
  ["draw.namePlaceholder"] = "Name of the drawing",
  ["draw.save"] = "Save",
  ["draw.saveTip"] = "Saves the drawing in your list (Ctrl+S).",
  ["draw.saveClose"] = "Save and close",
  ["draw.share"] = "Share in chat",
  ["draw.window"] = "Show as window",
  ["draw.share.tip"] = "Saves and opens the chat link dialog.",
  ["draw.export"] = "Export string",
  ["draw.menu.file"] = "File",
  ["draw.menu.edit"] = "Edit",
  ["draw.menu.view"] = "View",
  ["draw.menu.deleteSel"] = "Delete selection",
  ["draw.menu.clearAll"] = "Clear everything",
  ["draw.menu.statusBar"] = "Status bar",
  ["draw.menu.resize"] = "Resize canvas...",
  ["draw.menu.crop"] = "Crop to selection",
  ["draw.sc.save"] = "Ctrl+S",
  ["draw.sc.undo"] = "Ctrl+Z",
  ["draw.sc.redo"] = "Ctrl+Y",
  ["draw.sc.cut"] = "Ctrl+X",
  ["draw.sc.copy"] = "Ctrl+C",
  ["draw.sc.paste"] = "Ctrl+V",
  ["draw.sc.all"] = "Ctrl+A",
  ["draw.sc.delete"] = "Del",
  ["draw.group.select"] = "Selection",
  ["draw.group.image"] = "Image",
  ["draw.group.tools"] = "Tools",
  ["draw.group.brush"] = "Brush",
  ["draw.group.shapes"] = "Shapes",
  ["draw.group.color"] = "Colors",
  ["draw.tool.pencil"] = "Pencil",
  ["draw.tool.pencil.tip"] = "Draw freehand. Hold the left mouse button.",
  ["draw.tool.eraser"] = "Eraser",
  ["draw.tool.eraser.tip"] = "Paints with the background color.",
  ["draw.tool.line"] = "Line",
  ["draw.tool.line.tip"] = "Drag from the start to the end of a straight line.",
  ["draw.tool.rect"] = "Rectangle",
  ["draw.tool.rect.tip"] = "Drag a rectangle.\nOutline or fill: see Fill style.",
  ["draw.tool.ellipse"] = "Ellipse",
  ["draw.tool.ellipse.tip"] = "Drag an ellipse.\nOutline or fill: see Fill style.",
  ["draw.tool.fill"] = "Fill",
  ["draw.tool.fill.tip"] = "Fills an area of one color.\nSimilar colors count (Edit > Fill tolerance).",
  ["draw.tool.pick"] = "Pick",
  ["draw.tool.pick.tip"] = "Click a cell to take its color.",
  ["draw.tool.select"] = "Select",
  ["draw.tool.select.tip"] = "Drag to select. Drag inside to move.\nEsc clears.",
  ["draw.tool.zoom"] = "Magnifier",
  ["draw.tool.zoom.tip"] = "Click zooms in, Shift+click out.\nCtrl + mouse wheel zooms anywhere.",
  ["draw.tool.pencil.hint"] = "Hold the mouse button and draw.",
  ["draw.tool.eraser.hint"] = "Paints with the background color.",
  ["draw.tool.line.hint"] = "Drag to draw a straight line.",
  ["draw.tool.rect.hint"] = "Drag to draw a rectangle.",
  ["draw.tool.ellipse.hint"] = "Drag to draw an ellipse.",
  ["draw.tool.fill.hint"] = "Click an area to fill it.",
  ["draw.tool.pick.hint"] = "Click a cell to pick its color.",
  ["draw.tool.select.hint"] = "Drag a rectangle, Esc clears.",
  ["draw.tool.zoom.hint"] = "Click zooms in, Shift+click out.",
  ["draw.shapes"] = "Shapes",
  ["draw.shapes.tip"] = "Line, rectangle and ellipse.",
  ["draw.fillStyle"] = "Fill style",
  ["draw.fillStyle.tip"] = "How rectangle and ellipse are filled.",
  ["draw.act.cut"] = "Cut",
  ["draw.act.copy"] = "Copy",
  ["draw.act.paste"] = "Paste",
  ["draw.act.selectAll"] = "Select all",
  ["draw.act.selectNone"] = "Clear selection",
  ["draw.sel.rect"] = "Rectangle selection",
  ["draw.act.flipH"] = "Flip horizontally",
  ["draw.act.flipH.tip"] = "Mirrors selection or drawing, left to right.",
  ["draw.act.flipV"] = "Flip vertically",
  ["draw.act.flipV.tip"] = "Mirrors selection or drawing, top to bottom.",
  ["draw.act.invert"] = "Invert colors",
  ["draw.act.invert.tip"] = "Inverts colors of selection or drawing.",
  ["draw.act.clear"] = "Clear all",
  ["draw.act.clear.tip"] = "Empties the drawing (can be undone).",
  ["draw.brush"] = "Brush size",
  ["draw.brush.tip"] = "Size 0.25 to 9 cells.\nBelow 1 needs soft edges, not for the eraser.",
  ["draw.brush.smaller"] = "Smaller brush",
  ["draw.brush.bigger"] = "Bigger brush",
  ["draw.brush.shape"] = "Brush tip",
  ["draw.brush.shape.tip"] = "Square or round tip of the brush.",
  ["draw.shape.square"] = "Square",
  ["draw.shape.square.tip"] = "Square brush tip.",
  ["draw.shape.round"] = "Round",
  ["draw.shape.round.tip"] = "Round brush tip.",
  ["draw.fill.outline"] = "Outline",
  ["draw.fill.outline.tip"] = "Rectangle and ellipse: only the outline.",
  ["draw.fill.fill"] = "Filled with outline",
  ["draw.fill.fill.tip"] = "Outline: current color, inside: background color.",
  ["draw.fill.solid"] = "Filled",
  ["draw.fill.solid.tip"] = "Inside gets the outline color.",
  ["draw.undo"] = "Undo",
  ["draw.undo.tip"] = "Takes back the last step (Ctrl+Z).",
  ["draw.redo"] = "Redo",
  ["draw.redo.tip"] = "Repeats the step you took back (Ctrl+Y).",
  ["draw.zoom.out"] = "Zoom out",
  ["draw.zoom.in"] = "Zoom in",
  ["draw.fit"] = "Fit to window",
  ["draw.fit.tip"] = "Largest whole zoom that shows everything.",
  ["draw.grid"] = "Grid",
  ["draw.color.wheel"] = "Color wheel",
  ["draw.color.wheel.tip"] = "Opens the color picker, adds the color to the palette.",
  ["draw.color.more"] = "More",
  ["draw.color.more.tip"] = "Shows the whole palette of this drawing.",
  ["draw.color.pair"] = "Current and background color",
  ["draw.color.pair.tip"] = "Front color paints, back color erases.\nClick swaps them.",
  ["draw.color.swatch"] = "Color %d (%d, %d, %d)",
  ["draw.status.sel"] = "Selection: %d × %d px",
  ["draw.status.size"] = "%d × %d px",
  ["draw.status.modified"] = "Unsaved changes",
  ["draw.status.unsaved"] = "Not saved yet",
  ["draw.status.saved"] = "Saved",
  ["draw.status.coarse"] = "Simplified display: coarser resolution (every %d. cell)",
  ["draw.status.tones"] = "Simplified display: soft tones reduced (%d tones)",
  ["draw.status.over"] = "Display limit reached: parts of the picture are left out",
  ["draw.status.restore"] = "Full display is possible again (View menu)",
  ["draw.status.load"] = "Objects %s / %s",
  ["draw.fullDisplay"] = "Full display",
  ["draw.load.title"] = "Display load",
  ["draw.load.tip"] = "Each colored rectangle is one object.\nLimit: %s per window, %s in total.\nAbout %s ms per 1000 objects, full budget %d ms per frame.\nOver the limit: merged, visible part only, tones, resolution.\nCurrent display: %s. Drawing stays unchanged.",
  ["draw.load.stage.exact"] = "full",
  ["draw.load.stage.merged"] = "rectangles merged",
  ["draw.load.stage.culled"] = "visible part only",
  ["draw.load.stage.tones"] = "tones reduced",
  ["draw.load.stage.step"] = "coarser resolution",
  ["draw.status.thinNeedsSoft"] = "A thin pen needs soft edges",
  ["draw.status.pending"] = "...",
  ["draw.status.noSize"] = "?",
  ["draw.quality"] = "Soft",
  ["draw.quality.tip"] = "Soft edges and stroke smoothing.",
  ["draw.aa"] = "Soft edges",
  ["draw.aa.tip"] = "Blends stroke edges into the background.\nAdds hidden helper colors to the palette.",
  ["draw.smooth"] = "Smooth strokes",
  ["draw.smooth.tip"] = "Evens out freehand strokes (pencil, eraser).\nThe stroke follows the mouse slightly late.",
  ["draw.tolerance"] = "Fill tolerance",
  ["draw.tolerance.exact"] = "0 % (exact)",
  ["draw.grip"] = "Drag to resize",
  ["draw.handle"] = "Canvas size",
  ["draw.handle.tip"] = "Drag to resize the canvas.\nCells on the right and bottom are added or cut off.",
  ["draw.resize.title"] = "Resize canvas",
  ["draw.resize.current"] = "Current size: %d × %d px",
  ["draw.resize.width"] = "Width (px)",
  ["draw.resize.height"] = "Height (px)",
  ["draw.resize.keep"] = "Keep aspect ratio",
  ["draw.resize.presets"] = "Presets",
  ["draw.resize.hint"] = "Top left anchor: smaller crops, bigger adds background.",
  ["draw.resize.apply"] = "Resize",
  ["draw.resize.err.number"] = "Enter whole numbers for width and height.",
  ["draw.resize.err.range"] = "Width and height: 8 to 320 px, at most 80000 cells.",
  ["draw.msg.resizeLimit"] = "Limit: 8 to 320 px, 80000 cells",
  ["draw.msg.cropSmall"] = "The selection is too small (at least 8 × 8 px).",
  ["draw.discard.title"] = "Discard changes?",
  ["draw.discard.text"] = "Close without saving?",
  ["draw.clear.title"] = "Clear the drawing?",
  ["draw.clear.text"] = "The whole canvas becomes empty (Ctrl+Z undoes it).",
  ["draw.msg.saved"] = "Drawing saved: %s",
  ["draw.msg.limit"] = "Drawing limit %d reached: delete one first.",
  ["draw.msg.tooLarge"] = "Too detailed to save (%s KB packed, limit 64 KB).\nUse a smaller canvas, fewer colors or no soft edges.",
  ["draw.msg.unavailable"] = "Saving not possible (compression library missing).",
  ["draw.msg.saveFailed"] = "The drawing could not be saved.",
  ["draw.msg.paletteFull"] = "The palette is full (%d colors).",
  ["draw.msg.noSelection"] = "Select an area first.",
  ["draw.msg.noClip"] = "Clipboard empty: copy or cut first.",
  ["draw.msg.loadFailed"] = "The drawing could not be read.",
  ["draw.slash.none"] = "No drawing found for: %s",
})

ns.AddLocale("deDE", {
  ["draw.editor.title"] = "Zeichnung",
  ["draw.untitled"] = "Unbenannte Zeichnung",
  ["draw.namePlaceholder"] = "Name der Zeichnung",
  ["draw.save"] = "Speichern",
  ["draw.saveTip"] = "Speichert die Zeichnung in deiner Liste (Strg+S).",
  ["draw.saveClose"] = "Speichern und schließen",
  ["draw.share"] = "Teilen im Chat",
  ["draw.window"] = "Als Fenster anzeigen",
  ["draw.share.tip"] = "Speichert und öffnet den Chat-Link-Dialog.",
  ["draw.export"] = "Exportieren",
  ["draw.menu.file"] = "Datei",
  ["draw.menu.edit"] = "Bearbeiten",
  ["draw.menu.view"] = "Ansicht",
  ["draw.menu.deleteSel"] = "Auswahl löschen",
  ["draw.menu.clearAll"] = "Alles leeren",
  ["draw.menu.statusBar"] = "Statusleiste",
  ["draw.menu.resize"] = "Größe ändern...",
  ["draw.menu.crop"] = "Auf Auswahl zuschneiden",
  ["draw.sc.save"] = "Strg+S",
  ["draw.sc.undo"] = "Strg+Z",
  ["draw.sc.redo"] = "Strg+Y",
  ["draw.sc.cut"] = "Strg+X",
  ["draw.sc.copy"] = "Strg+C",
  ["draw.sc.paste"] = "Strg+V",
  ["draw.sc.all"] = "Strg+A",
  ["draw.sc.delete"] = "Entf",
  ["draw.group.select"] = "Auswahl",
  ["draw.group.image"] = "Bild",
  ["draw.group.tools"] = "Tools",
  ["draw.group.brush"] = "Pinsel",
  ["draw.group.shapes"] = "Formen",
  ["draw.group.color"] = "Farben",
  ["draw.tool.pencil"] = "Stift",
  ["draw.tool.pencil.tip"] = "Frei zeichnen. Linke Maustaste halten.",
  ["draw.tool.eraser"] = "Radierer",
  ["draw.tool.eraser.tip"] = "Malt mit der Hintergrundfarbe.",
  ["draw.tool.line"] = "Linie",
  ["draw.tool.line.tip"] = "Zieh von Anfang bis Ende einer geraden Linie.",
  ["draw.tool.rect"] = "Rechteck",
  ["draw.tool.rect.tip"] = "Rechteck aufziehen.\nKontur oder gefüllt: siehe Füllung.",
  ["draw.tool.ellipse"] = "Ellipse",
  ["draw.tool.ellipse.tip"] = "Ellipse aufziehen.\nKontur oder gefüllt: siehe Füllung.",
  ["draw.tool.fill"] = "Füllen",
  ["draw.tool.fill.tip"] = "Füllt eine Farbfläche.\nÄhnliche Farben zählen (Bearbeiten > Füll-Toleranz).",
  ["draw.tool.pick"] = "Pipette",
  ["draw.tool.pick.tip"] = "Zelle anklicken, Farbe übernehmen.",
  ["draw.tool.select"] = "Auswahl",
  ["draw.tool.select.tip"] = "Ziehen wählt aus, darin ziehen verschiebt.\nEsc hebt auf.",
  ["draw.tool.zoom"] = "Lupe",
  ["draw.tool.zoom.tip"] = "Klick zoomt hinein, Umschalt+Klick heraus.\nStrg + Mausrad zoomt überall.",
  ["draw.tool.pencil.hint"] = "Maustaste halten und zeichnen.",
  ["draw.tool.eraser.hint"] = "Malt mit der Hintergrundfarbe.",
  ["draw.tool.line.hint"] = "Zieh eine gerade Linie auf.",
  ["draw.tool.rect.hint"] = "Zieh ein Rechteck auf.",
  ["draw.tool.ellipse.hint"] = "Zieh eine Ellipse auf.",
  ["draw.tool.fill.hint"] = "Klick füllt die Fläche.",
  ["draw.tool.pick.hint"] = "Klick übernimmt die Farbe.",
  ["draw.tool.select.hint"] = "Rechteck aufziehen, Esc hebt auf.",
  ["draw.tool.zoom.hint"] = "Klick zoomt, Umschalt+Klick zurück.",
  ["draw.shapes"] = "Formen",
  ["draw.shapes.tip"] = "Linie, Rechteck und Ellipse.",
  ["draw.fillStyle"] = "Füllung",
  ["draw.fillStyle.tip"] = "Wie Rechteck und Ellipse gefüllt werden.",
  ["draw.act.cut"] = "Ausschneiden",
  ["draw.act.copy"] = "Kopieren",
  ["draw.act.paste"] = "Einfügen",
  ["draw.act.selectAll"] = "Alles auswählen",
  ["draw.act.selectNone"] = "Auswahl aufheben",
  ["draw.sel.rect"] = "Rechteck-Auswahl",
  ["draw.act.flipH"] = "Horizontal spiegeln",
  ["draw.act.flipH.tip"] = "Spiegelt Auswahl oder Zeichnung, links nach rechts.",
  ["draw.act.flipV"] = "Vertikal spiegeln",
  ["draw.act.flipV.tip"] = "Spiegelt Auswahl oder Zeichnung, oben nach unten.",
  ["draw.act.invert"] = "Farben invertieren",
  ["draw.act.invert.tip"] = "Invertiert Farben von Auswahl oder Zeichnung.",
  ["draw.act.clear"] = "Alles leeren",
  ["draw.act.clear.tip"] = "Leert die Zeichnung (rückgängig möglich).",
  ["draw.brush"] = "Pinselgröße",
  ["draw.brush.tip"] = "Größe 0.25 bis 9 Zellen.\nUnter 1 braucht weiche Kanten, nicht für Radierer.",
  ["draw.brush.smaller"] = "Kleinerer Pinsel",
  ["draw.brush.bigger"] = "Größerer Pinsel",
  ["draw.brush.shape"] = "Pinselspitze",
  ["draw.brush.shape.tip"] = "Quadratische oder runde Spitze des Pinsels.",
  ["draw.shape.square"] = "Quadrat",
  ["draw.shape.square.tip"] = "Quadratische Pinselspitze.",
  ["draw.shape.round"] = "Rund",
  ["draw.shape.round.tip"] = "Runde Pinselspitze.",
  ["draw.fill.outline"] = "Konturen",
  ["draw.fill.outline.tip"] = "Rechteck und Ellipse: nur die Kontur.",
  ["draw.fill.fill"] = "Gefüllt mit Kontur",
  ["draw.fill.fill.tip"] = "Kontur: aktuelle Farbe, innen: Hintergrundfarbe.",
  ["draw.fill.solid"] = "Gefüllt",
  ["draw.fill.solid.tip"] = "Innen in der Farbe der Kontur.",
  ["draw.undo"] = "Rückgängig",
  ["draw.undo.tip"] = "Nimmt den letzten Schritt zurück (Strg+Z).",
  ["draw.redo"] = "Wiederholen",
  ["draw.redo.tip"] = "Wiederholt den zurückgenommenen Schritt (Strg+Y).",
  ["draw.zoom.out"] = "Verkleinern",
  ["draw.zoom.in"] = "Vergrößern",
  ["draw.fit"] = "An Fenster anpassen",
  ["draw.fit.tip"] = "Größte ganze Zoomstufe, die alles zeigt.",
  ["draw.grid"] = "Raster",
  ["draw.color.wheel"] = "Farbrad",
  ["draw.color.wheel.tip"] = "Öffnet die Farbauswahl, fügt die Farbe der Palette hinzu.",
  ["draw.color.more"] = "Mehr",
  ["draw.color.more.tip"] = "Zeigt die ganze Palette dieser Zeichnung.",
  ["draw.color.pair"] = "Aktuelle Farbe und Hintergrundfarbe",
  ["draw.color.pair.tip"] = "Vordere Farbe malt, hintere radiert.\nKlick tauscht beide.",
  ["draw.color.swatch"] = "Farbe %d (%d, %d, %d)",
  ["draw.status.sel"] = "Auswahl: %d × %d px",
  ["draw.status.size"] = "%d × %d px",
  ["draw.status.modified"] = "Ungespeichert",
  ["draw.status.unsaved"] = "Neu, ungespeichert",
  ["draw.status.saved"] = "Gespeichert",
  ["draw.status.coarse"] = "Anzeige vereinfacht: gröbere Auflösung (jede %d. Zelle)",
  ["draw.status.tones"] = "Anzeige vereinfacht: weiche Töne reduziert (%d Töne)",
  ["draw.status.over"] = "Anzeigegrenze erreicht: Teile des Bildes fehlen",
  ["draw.status.restore"] = "Volle Darstellung wieder möglich (Menü Ansicht)",
  ["draw.status.load"] = "Objekte %s / %s",
  ["draw.fullDisplay"] = "Volle Darstellung",
  ["draw.load.title"] = "Anzeigelast",
  ["draw.load.tip"] = "Jedes farbige Rechteck ist ein Objekt.\nGrenze: %s pro Fenster, %s insgesamt.\nCa. %s ms pro 1000 Objekte, volles Budget %d ms pro Bild.\nÜber dem Limit: zusammengefasst, nur Sichtbares, Töne, Auflösung.\nAktuelle Anzeige: %s. Zeichnung bleibt unverändert.",
  ["draw.load.stage.exact"] = "voll",
  ["draw.load.stage.merged"] = "Rechtecke zusammengefasst",
  ["draw.load.stage.culled"] = "nur der sichtbare Teil",
  ["draw.load.stage.tones"] = "Töne reduziert",
  ["draw.load.stage.step"] = "gröbere Auflösung",
  ["draw.status.thinNeedsSoft"] = "Dünner Stift braucht weiche Kanten",
  ["draw.status.pending"] = "...",
  ["draw.status.noSize"] = "?",
  ["draw.quality"] = "Weich",
  ["draw.quality.tip"] = "Weiche Kanten und Strich glätten.",
  ["draw.aa"] = "Weiche Kanten",
  ["draw.aa.tip"] = "Mischt Strichränder in den Hintergrund.\nLegt versteckte Hilfsfarben in der Palette an.",
  ["draw.smooth"] = "Strich glätten",
  ["draw.smooth.tip"] = "Glättet freie Striche (Stift, Radierer).\nDer Strich folgt der Maus leicht verzögert.",
  ["draw.tolerance"] = "Füll-Toleranz",
  ["draw.tolerance.exact"] = "0 % (genau)",
  ["draw.grip"] = "Ziehen, um die Größe zu ändern",
  ["draw.handle"] = "Größe der Zeichenfläche",
  ["draw.handle.tip"] = "Ziehen ändert die Zeichenfläche.\nRechts und unten kommen Zellen dazu oder fallen weg.",
  ["draw.resize.title"] = "Größe ändern",
  ["draw.resize.current"] = "Aktuelle Größe: %d × %d px",
  ["draw.resize.width"] = "Breite (px)",
  ["draw.resize.height"] = "Höhe (px)",
  ["draw.resize.keep"] = "Seitenverhältnis beibehalten",
  ["draw.resize.presets"] = "Vorgaben",
  ["draw.resize.hint"] = "Anker oben links: kleiner schneidet ab, größer füllt auf.",
  ["draw.resize.apply"] = "Ändern",
  ["draw.resize.err.number"] = "Gib für Breite und Höhe ganze Zahlen ein.",
  ["draw.resize.err.range"] = "Breite und Höhe: 8 bis 320 px, höchstens 80000 Zellen.",
  ["draw.msg.resizeLimit"] = "Grenze: 8 bis 320 px, 80000 Zellen",
  ["draw.msg.cropSmall"] = "Die Auswahl ist zu klein (mindestens 8 × 8 px).",
  ["draw.discard.title"] = "Änderungen verwerfen?",
  ["draw.discard.text"] = "Ohne Speichern schließen?",
  ["draw.clear.title"] = "Zeichnung leeren?",
  ["draw.clear.text"] = "Die ganze Fläche wird leer (Strg+Z macht es rückgängig).",
  ["draw.msg.saved"] = "Zeichnung gespeichert: %s",
  ["draw.msg.limit"] = "Zeichnungs-Limit %d erreicht: erst eine löschen.",
  ["draw.msg.tooLarge"] = "Zu detailreich zum Speichern (%s KB gepackt, erlaubt 64 KB).\nKleinere Fläche, weniger Farben oder weiche Kanten aus.",
  ["draw.msg.unavailable"] = "Speichern nicht möglich (Kompressionsbibliothek fehlt).",
  ["draw.msg.saveFailed"] = "Die Zeichnung konnte nicht gespeichert werden.",
  ["draw.msg.paletteFull"] = "Die Palette ist voll (%d Farben).",
  ["draw.msg.noSelection"] = "Wähle zuerst einen Bereich aus.",
  ["draw.msg.noClip"] = "Zwischenablage leer: erst kopieren oder ausschneiden.",
  ["draw.msg.loadFailed"] = "Die Zeichnung konnte nicht gelesen werden.",
  ["draw.slash.none"] = "Keine Zeichnung gefunden für: %s",
})

local function fmt(key, ...)
  local ok, text = pcall(string.format, L[key], ...)
  return ok and text or L[key]
end

-- Glyphs -------------------------------------------------------------------------------

-- Pixel icons on the 12 x 12 grid of IconDraw for the functions the shared set
-- does not cover.
IconDraw.register("draw-invert", function(p)
  p:Outline(1, 1, 10, 10)
  p:Rect(1, 1, 5, 10)
end)

IconDraw.register("draw-clear", function(p)
  p:Rect(2, 3, 8, 1)
  p:Rect(4, 1, 4, 2)
  p:Outline(3, 4, 6, 7)
  p:Rect(5, 6, 1, 3, "accent2")
  p:Rect(7, 6, 1, 3, "accent2")
end)

IconDraw.register("draw-select-all", function(p)
  p:Outline(1, 1, 10, 10)
  p:Rect(3, 3, 6, 6, "accent2")
end)

IconDraw.register("draw-brush-size", function(p)
  p:Ellipse(0, 9, 2, 2, true)
  p:Ellipse(3, 8, 3, 3, true)
  p:Ellipse(7, 6, 5, 5, true)
end)

IconDraw.register("draw-brush-square", function(p)
  p:Rect(2, 2, 8, 8)
end)

IconDraw.register("draw-brush-round", function(p)
  p:Ellipse(2, 2, 8, 8, true)
end)

IconDraw.register("draw-fill-outline", function(p)
  p:Outline(1, 2, 10, 8)
end)

IconDraw.register("draw-fill-fill", function(p)
  p:Outline(1, 2, 10, 8)
  p:Rect(3, 4, 6, 4, "accent2")
end)

IconDraw.register("draw-fill-solid", function(p)
  p:Rect(1, 2, 10, 8)
end)

IconDraw.register("draw-soft", function(p)
  p:Rect(1, 5, 10, 2)
  p:Rect(1, 4, 10, 1, "accent2")
  p:Rect(1, 7, 10, 1, "accent2")
end)

IconDraw.register("draw-wheel", function(p)
  p:Ellipse(1, 1, 10, 10, false)
  p:Rect(5, 3, 2, 2, "danger")
  p:Rect(3, 5, 2, 2, "success")
  p:Rect(7, 5, 2, 2, "info")
  p:Rect(5, 7, 2, 2, "warning")
end)

IconDraw.register("draw-map", function(p)
  p:Outline(1, 2, 10, 8)
  p:Rect(4, 2, 1, 8, "accent2")
  p:Rect(7, 2, 1, 8, "accent2")
  p:Rect(9, 4, 1, 2, "danger")
end)

-- State --------------------------------------------------------------------------------

-- Tool settings live for the session, the document is whatever the window shows.
local S = {
  tool = "pencil",
  lastShape = "rect",
  brush = 1,
  shape = "square",
  fillMode = "outline",
  color = 2,
  zoom = 4,
  grid = false,
  statusBar = true,
  aa = true,
  smooth = true,
  tolerance = D.DEFAULT_TOLERANCE,
}
DE.state = S
local doc
local frame
local ui = { tools = {}, acts = {}, boxes = {} }
DE.ui = ui
local view

-- Clipboard shared by all drawings of the session: { x, y, w, h, cells, palette }.
local clip

function DE.Doc()
  return doc
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.drawingEditor) ~= "table" then
    frames.drawingEditor = {}
  end
  return frames.drawingEditor
end

local function numberOr(v, fallback)
  return type(v) == "number" and v or fallback
end

local function isDirty()
  return doc ~= nil
    and (
      doc.ed:isModified()
      or doc.id == nil
      or DR.cleanName(doc.name) ~= doc.savedName
      or not D.sameMap(doc.drawing.map, doc.savedMap)
    )
end
DE.IsDirty = isDirty

function DE.IsOpen()
  return frame ~= nil and frame:IsShown() and doc ~= nil
end

local function swatchColor(c)
  local p = doc and doc.drawing.palette[c]
  if not p then
    return 0, 0, 0
  end
  return p[1] / 255, p[2] / 255, p[3] / 255
end

-- Document operations -------------------------------------------------------------------

local refreshUI, layout, layoutCanvas, updateHandles

local function setSelection(r)
  if r then
    r = { min(r[1], r[3]), min(r[2], r[4]), max(r[1], r[3]), max(r[2], r[4]) }
  end
  S.sel = r
  if view then
    if r then
      view:SetSelection(r[1], r[2], r[3], r[4])
    else
      view:SetSelection(nil)
    end
  end
end

local function hideResizePreview()
  if ui.preview then
    ui.preview:Hide()
  end
end

local function cancelStroke()
  local hadStroke = S.stroke ~= nil or S.drag ~= nil
  if S.stroke and doc then
    doc.ed:cancelStroke()
  end
  S.stroke, S.drag, S.resize = nil, nil, nil
  hideResizePreview()
  if hadStroke and view then
    view:Refresh()
    setSelection(S.sel)
  end
  if updateHandles then
    updateHandles()
  end
end

-- Repaints exactly the bands a changeset touched. A simplified display stays
-- until the view levels up or "Full display" is chosen, the re-evaluation here
-- only finds out whether the full picture would fit again. A resize (also its
-- undo and redo) rebuilds the view and the scroll area.
local function repaint(ch)
  S.sizePending, S.sizeWait = true, 0
  view:ApplyChangeset(ch)
  if ch.kind == "resize" then
    S.hover = nil
    setSelection(nil)
    layoutCanvas()
  elseif view:Stats().level > 0 then
    view:Refresh()
  end
  DE.UpdateStatus()
end

-- Runs one editor tool as an undo step and repaints exactly what it changed.
local function run(tool, opts)
  if S.stroke or S.drag or S.resize then
    return nil
  end
  local ed = doc.ed
  local before = ed.seq
  local ok, extra = ed:run(tool, opts)
  if ed.seq ~= before then
    repaint(ed.undoStack[#ed.undoStack])
  end
  refreshUI()
  return ok, extra
end

local function setTool(tool)
  if S.tool ~= tool then
    S.tool = tool
    if tool ~= "select" then
      setSelection(nil)
    end
  end
  if SHAPE_TOOLS[tool] then
    S.lastShape = tool
  end
  S.note = nil
  refreshUI()
end

-- Size of the part of the stage the canvas scrolls in.
local function viewportSize()
  local fw, fh = frame:GetWidth(), frame:GetHeight()
  local status = S.statusBar and ui.status:GetHeight() or 0
  local chrome = HEAD_H + ui.top:GetHeight() + ui.ribbon:GetHeight() + status
  return max(1, fw - scaled(SIDE_W) - STAGE_PAD - 12), max(1, fh - chrome - 2 * STAGE_PAD)
end

DE.ViewportSize = viewportSize

local function clampScroll(now)
  local vw, vh = viewportSize()
  local hw, hh = ui.holder:GetWidth(), ui.holder:GetHeight()
  local maxX, maxY = max(0, hw - vw), max(0, hh - vh)
  local x = U.clamp(numberOr(ui.scroll:GetHorizontalScroll(), 0), 0, maxX)
  local y = U.clamp(numberOr(ui.scroll:GetVerticalScroll(), 0), 0, maxY)
  ui.scroll:SetHorizontalScroll(x)
  ui.scroll:SetVerticalScroll(y)
  ui.vbar:Update(maxY > 0 and vh / hh or 1, maxY > 0 and y / maxY or 0)
  ui.hbar:Update(maxX > 0 and vw / hw or 1, maxX > 0 and x / maxX or 0)
  -- The view paints only what is near the visible part when it has to save textures
  -- (the picture sits in the middle of the holder). Scrolling is throttled by the
  -- view, a layout change (zoom, size, new drawing) repaints at once.
  if view and doc then
    local left, top = (hw - view.frame:GetWidth()) / 2, (hh - view.frame:GetHeight()) / 2
    view:SetViewport(x - left, y - top, x - left + vw, y - top + vh, now)
  end
end

function layoutCanvas()
  local d = doc and doc.drawing
  local vw, vh = viewportSize()
  local cw, ch = d and d.w * S.zoom or 0, d and d.h * S.zoom or 0
  ui.holder:SetSize(max(vw, cw + 2 + 2 * HANDLE_MARGIN), max(vh, ch + 2 + 2 * HANDLE_MARGIN))
  ui.canvas:SetSize(cw + 2, ch + 2)
  clampScroll(true)
  updateHandles()
end

local function setZoom(z)
  z = U.clamp(floor(z + 0.5), ZOOM_MIN, ZOOM_MAX)
  if z == S.zoom then
    return
  end
  S.zoom = z
  if view and doc then
    view:SetScale(z)
  end
  layoutCanvas()
  refreshUI()
end

local function fitZoom()
  local d = doc.drawing
  local vw, vh = viewportSize()
  local room = 4 + 2 * HANDLE_MARGIN
  S.zoom = U.clamp(floor(min((vw - room) / d.w, (vh - room) / d.h)), ZOOM_MIN, ZOOM_MAX)
  view:SetScale(S.zoom)
end

-- Largest whole zoom level that shows the whole drawing.
function DE.Fit()
  if not doc then
    return
  end
  fitZoom()
  ui.scroll:SetHorizontalScroll(0)
  ui.scroll:SetVerticalScroll(0)
  layoutCanvas()
  refreshUI()
end

-- Scrolls so that cell (cx, cy) sits in the middle of the viewport.
local function centerOnCell(cx, cy)
  local d = doc.drawing
  local vw, vh = viewportSize()
  local ox = (ui.holder:GetWidth() - (d.w * S.zoom + 2)) / 2
  local oy = (ui.holder:GetHeight() - (d.h * S.zoom + 2)) / 2
  ui.scroll:SetHorizontalScroll(max(0, ox) + 1 + (cx - 0.5) * S.zoom - vw / 2)
  ui.scroll:SetVerticalScroll(max(0, oy) + 1 + (cy - 0.5) * S.zoom - vh / 2)
  clampScroll()
end

-- Magnifier: next level from ZOOM_STEPS, or the fit when already at the top.
local function magnify(cx, cy, out)
  local target
  if out then
    for i = #ZOOM_STEPS, 1, -1 do
      if ZOOM_STEPS[i] < S.zoom then
        target = ZOOM_STEPS[i]
        break
      end
    end
    target = target or ZOOM_STEPS[1]
  else
    for _, z in ipairs(ZOOM_STEPS) do
      if z > S.zoom then
        target = z
        break
      end
    end
  end
  if target then
    setZoom(target)
  else
    DE.Fit()
  end
  centerOnCell(cx, cy)
end

-- Clip colors re-mapped onto this drawing's palette (adds missing colors, or
-- the nearest one when the palette is full).
local function mapClip(c)
  local d = doc.drawing
  if not c.palette then
    return c
  end
  local map, same = {}, true
  for _, idx in ipairs(c.cells) do
    if not map[idx] then
      local p = c.palette[idx]
      local mapped = p and D.addColor(d, p[1], p[2], p[3], c.auto ~= nil and c.auto[idx] == true)
      if not mapped then
        local best, dist = 1, math.huge
        for j, q in ipairs(d.palette) do
          local dd = p and ((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2) or 0
          if dd < dist then
            best, dist = j, dd
          end
        end
        mapped = best
      end
      map[idx] = mapped
      same = same and mapped == idx
    end
  end
  if same then
    return c
  end
  local out = { x = c.x, y = c.y, w = c.w, h = c.h, cells = {}, palette = c.palette, auto = c.auto }
  for i, idx in ipairs(c.cells) do
    out.cells[i] = map[idx]
  end
  return out
end

local function storeClip(c)
  if not c then
    return
  end
  c.palette = {}
  for i, p in ipairs(doc.drawing.palette) do
    c.palette[i] = { p[1], p[2], p[3] }
  end
  if doc.drawing.auto then
    c.auto = {}
    for i in pairs(doc.drawing.auto) do
      c.auto[i] = true
    end
  end
  clip = c
end

local function note(key)
  S.note = L[key]
  refreshUI()
end

local function selectionBox()
  local r = S.sel
  return r and { x1 = r[1], y1 = r[2], x2 = r[3], y2 = r[4] }
end

function DE.Copy()
  local r = S.sel
  if not (doc and r) then
    return note("draw.msg.noSelection")
  end
  storeClip(D.copy(doc.drawing, r[1], r[2], r[3], r[4]))
  refreshUI()
end

function DE.Cut()
  local box = selectionBox()
  if not (doc and box) then
    return note("draw.msg.noSelection")
  end
  local ok, c = run("cut", box)
  if ok then
    storeClip(c)
  end
  refreshUI()
end

function DE.Delete()
  local box = selectionBox()
  if not (doc and box) then
    return note("draw.msg.noSelection")
  end
  run("cut", box)
end

-- Cell at the top left of the visible part of the canvas.
local function viewportOrigin()
  local d = doc.drawing
  local px = max(0, numberOr(ui.scroll:GetLeft(), 0) - numberOr(view.frame:GetLeft(), 0))
  local py = max(0, numberOr(view.frame:GetTop(), 0) - numberOr(ui.scroll:GetTop(), 0))
  return U.clamp(floor(px / S.zoom) + 1, 1, d.w), U.clamp(floor(py / S.zoom) + 1, 1, d.h)
end

function DE.Paste()
  if not doc then
    return
  end
  if not clip then
    return note("draw.msg.noClip")
  end
  local c = mapClip(clip)
  local d = doc.drawing
  local x, y = viewportOrigin()
  x, y = min(x, max(1, d.w - c.w + 1)), min(y, max(1, d.h - c.h + 1))
  local ok = run("paste", { clip = c, x = x, y = y })
  if ok then
    S.tool = "select"
    setSelection({ x, y, x + c.w - 1, y + c.h - 1 })
    refreshUI()
  end
end

function DE.SelectAll()
  if doc then
    S.tool = "select"
    setSelection({ 1, 1, doc.drawing.w, doc.drawing.h })
    refreshUI()
  end
end

local function areaOpts()
  return selectionBox() or {}
end

function DE.SelectNone()
  if doc then
    setSelection(nil)
    refreshUI()
  end
end

-- The pair of colors: the current one swaps with the background color (the
-- eraser color, fixed by the file format) and swaps back on the next click.
function DE.SwapColors()
  if not doc then
    return
  end
  if S.color ~= D.BACKGROUND then
    S.lastColor, S.color = S.color, D.BACKGROUND
  else
    S.color = S.lastColor or 2
  end
  refreshUI()
end

function DE.Flip(horizontal)
  if doc then
    run(horizontal and "flipH" or "flipV", areaOpts())
  end
end

function DE.Invert()
  if doc then
    run("invert", areaOpts())
  end
end

function DE.Clear()
  if doc then
    ns.Dialogs.Confirm("draw.clear.title", "draw.clear.text", function()
      if doc then
        run("clear", {})
      end
    end)
  end
end

-- Canvas size ----------------------------------------------------------------------------

-- Resizes the canvas, anchored at the top left, as one undo step. Returns true
-- or nil, "dims" | "same" | "busy".
function DE.Resize(w, h)
  if not doc then
    return nil, "doc"
  end
  if not D.validDims(w, h) then
    return nil, "dims"
  end
  return run("resize", { w = w, h = h })
end

-- Paint's "Crop": the canvas becomes the selection.
function DE.CropToSelection()
  local box = selectionBox()
  if not (doc and box) then
    return note("draw.msg.noSelection")
  end
  local ok, why = run("crop", box)
  if not ok and why == "dims" then
    note("draw.msg.cropSmall")
  end
  return ok
end

-- Background map ---------------------------------------------------------------------------

-- Soft edges are off over a map: they blend against the white of the sheet.
local function softEdges()
  return S.aa and not (doc and doc.drawing.map)
end

-- Sets (a map table) or removes (nil) the background map. Returns true or nil, "doc" | "busy" | "map".
function DE.SetMap(map)
  if not doc then
    return nil, "doc"
  end
  if S.stroke or S.drag or S.resize then
    return nil, "busy"
  end
  local clean = map ~= nil and D.cleanMap(map) or nil
  if map ~= nil and not clean then
    return nil, "map"
  end
  doc.drawing.map = clean
  view:SetMap(clean)
  S.sizePending, S.sizeWait = true, 0
  refreshUI()
  return true
end

function DE.RemoveMap()
  return DE.SetMap(nil)
end

-- Gives the sheet the shape of its map (one undo step). Returns true or nil, reason.
function DE.FitToMap()
  local map = doc and doc.drawing.map
  if not map then
    return nil, "map"
  end
  local w, h = ns.DrawingMap.FitSize(map)
  if not w then
    note("draw.map.fitNone")
    return nil, "unavailable"
  end
  local ok, why = DE.Resize(w, h)
  if not ok and why == "same" then
    note("draw.map.fitSame")
  end
  return ok, why
end

-- Opens the "Choose map" window for the open drawing.
function DE.ChooseMap()
  if not doc then
    return nil, "doc"
  end
  ns.DrawingMapPicker.Open({
    map = doc.drawing.map,
    onChange = function(map)
      DE.SetMap(map)
    end,
    onFit = function()
      DE.FitToMap()
    end,
  })
  return true
end

-- Whole number from the text of a size field, or nil.
local function parseDim(text)
  local digits = tostring(text or ""):match("^%s*(%d+)%s*$")
  return digits and #digits <= 4 and tonumber(digits) or nil
end

local function buildResizeDialog()
  local d = ns.Dialogs.Create("ForeverGuidesDrawingResize", 400, 372)
  W.SetText(d.title, "draw.resize.title")
  d.ratio, d.keep = 1, false
  d.current = W.Text(d, { role = "ui", color = "accent2" })
  d.current:SetPoint("TOPLEFT", 16, -44)
  d.hint = W.Text(d, { key = "draw.resize.hint", role = "ui", color = "textSecondary", wrap = true })
  d.hint:SetPoint("TOPLEFT", 16, -64)
  d.hint:SetPoint("RIGHT", -16, 0)

  local function apply()
    local w, h = parseDim(d.width.edit:GetText()), parseDim(d.height.edit:GetText())
    if not (w and h) then
      d.msg:SetText(L["draw.resize.err.number"])
      return
    end
    if not D.validDims(w, h) then
      d.msg:SetText(L["draw.resize.err.range"])
      return
    end
    d:Hide()
    DE.Resize(w, h)
  end
  -- With "keep aspect ratio" the other field follows what the user typed.
  local function mirror(text, to, toHeight)
    d.msg:SetText("")
    local v = d.keep and parseDim(text)
    if v then
      to.edit:SetText(tostring(floor((toHeight and v / d.ratio or v * d.ratio) + 0.5)))
    end
  end
  local function field(labelKey, x, onChange)
    local label = W.Text(d, { key = labelKey, role = "ui" })
    label:SetPoint("TOPLEFT", x, -112)
    local box = W.EditBox(d, { onChange = onChange, onEnter = apply })
    box:SetPoint("TOPLEFT", x, -132)
    box:SetWidth(168)
    box.edit:SetNumeric(true)
    box.edit:SetMaxLetters(3)
    return box
  end
  d.width = field("draw.resize.width", 16, function(text)
    mirror(text, d.height, true)
  end)
  d.height = field("draw.resize.height", 216, function(text)
    mirror(text, d.width, false)
  end)
  d.keepBox = W.Checkbox(d, {
    key = "draw.resize.keep",
    get = function()
      return d.keep
    end,
    set = function(v)
      d.keep = v
    end,
  })
  d.keepBox:SetPoint("TOPLEFT", 16, -170)
  d.keepBox:SetPoint("RIGHT", -16, 0)
  d.presetLabel = W.Text(d, { key = "draw.resize.presets", role = "ui" })
  d.presetLabel:SetPoint("TOPLEFT", 16, -204)
  d.presets = {}
  for i, p in ipairs(D.PRESETS) do
    local b = W.Button(d, {
      text = p.w .. " × " .. p.h,
      width = 112,
      onClick = function()
        d.width.edit:SetText(tostring(p.w))
        d.height.edit:SetText(tostring(p.h))
        d.msg:SetText("")
      end,
    })
    b:SetPoint("TOPLEFT", 16 + ((i - 1) % 3) * 120, -224 - floor((i - 1) / 3) * 30)
    d.presets[i] = b
  end
  d.msg = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.msg:SetPoint("TOPLEFT", 16, -292)
  d.msg:SetPoint("RIGHT", -16, 0)
  d.go = W.Action(d, {
    label = "act.apply",
    icon = "check",
    tooltip = "draw.resize.apply",
    variant = "primary",
    width = 130,
    onClick = apply,
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
  return d
end

-- Dialog with width and height fields, aspect lock and the new-drawing presets.
function DE.ResizeDialog()
  if not doc then
    return
  end
  local d = ui.resizeDlg
  if not d then
    d = buildResizeDialog()
    ui.resizeDlg = d
  end
  local dw = doc.drawing
  d.ratio, d.keep = dw.w / dw.h, false
  d.current:SetText(fmt("draw.resize.current", dw.w, dw.h))
  d.width.edit:SetText(tostring(dw.w))
  d.height.edit:SetText(tostring(dw.h))
  d.msg:SetText("")
  d.keepBox.Refresh()
  d:Show()
  d.width.edit:SetFocus()
  d.width.edit:HighlightText()
end

function DE.Undo()
  if not doc then
    return
  end
  local ch = doc.ed:undo()
  if ch then
    repaint(ch)
    refreshUI()
  end
end

function DE.Redo()
  if not doc then
    return
  end
  local ch = doc.ed:redo()
  if ch then
    repaint(ch)
    refreshUI()
  end
end

-- Saving ---------------------------------------------------------------------------------

local SAVE_ERRORS =
  { limit = "draw.msg.limit", ["too-large"] = "draw.msg.tooLarge", unavailable = "draw.msg.unavailable" }

-- Returns true when the drawing is stored.
function DE.Save()
  if not doc then
    return false
  end
  cancelStroke()
  local item, why, size
  if doc.id then
    item, why, size = DR.update(doc.id, doc.drawing)
    if item then
      DR.rename(doc.id, doc.name)
    elseif why == "missing" then
      -- Deleted elsewhere in the meantime: saving brings it back as a new one.
      doc.id = nil
    end
  end
  if not doc.id then
    item, why, size = DR.add(doc.name, doc.drawing)
    if item then
      doc.id = item.id
    end
  end
  if not item then
    local key = SAVE_ERRORS[why]
    local text = L[key or "draw.msg.saveFailed"]
    if key == "draw.msg.limit" then
      text = fmt(key, DR.MAX_ITEMS)
    elseif key == "draw.msg.tooLarge" then
      -- The size estimate is only worked out when a save fails (encoding is not free).
      text = fmt(key, size and string.format("%.1f", size / 1024) or "?")
    end
    ns.Notify(text, (key == "draw.msg.limit" or key == "draw.msg.tooLarge") and "warning" or "error")
    return false
  end
  doc.ed:markSaved()
  doc.savedMap = D.cleanMap(doc.drawing.map)
  frameDb().shown, frameDb().id = true, doc.id
  doc.savedName = item.name
  doc.name = item.name ~= "" and item.name or doc.name
  ns.Notify(fmt("draw.msg.saved", item.name ~= "" and item.name or L["draw.untitled"]), "success")
  refreshUI()
  return true
end

local function closeNow()
  if frame then
    frame:Hide()
  end
end

-- Closes the window, asking first when there is unsaved work.
function DE.Close(force)
  if not DE.IsOpen() then
    return closeNow()
  end
  if force or not isDirty() then
    return closeNow()
  end
  ns.Dialogs.Confirm("draw.discard.title", "draw.discard.text", closeNow)
end

function DE.SaveAndClose()
  if DE.Save() then
    closeNow()
  end
end

-- Export and share work on the stored drawing, so unsaved work is saved first.
local function saveForUse()
  if isDirty() then
    return DE.Save()
  end
  return true
end

function DE.Export()
  if not (doc and saveForUse()) then
    return
  end
  local text = DR.exportString(doc.id)
  if text then
    ns.Dialogs.Copy("draw.export.title", text, "draw.export.hint")
  else
    ns.Notify(L["draw.msg.exportFail"], "error")
  end
end

function DE.Share()
  if doc and saveForUse() then
    ns.Share.OpenDrawing(doc.id)
  end
end

-- The window shows the stored drawing, so unsaved work is saved first.
function DE.ShowAsWindow()
  if doc and saveForUse() then
    ns.DrawingWindow.Open(doc.id)
  end
end

-- Mouse ----------------------------------------------------------------------------------

local function clampCell(x, y)
  local d = doc.drawing
  return U.clamp(x, 1, d.w), U.clamp(y, 1, d.h)
end

local function fillOption()
  if S.fillMode == "fill" then
    return D.BACKGROUND
  elseif S.fillMode == "solid" then
    return true
  end
  return nil
end

-- One step of a running stroke: a new cell, or for soft and smoothed freehand
-- strokes a new position at least a quarter cell away (taken from the cursor
-- itself, so the brush follows the mouse between cell centers).
local function feedStroke(x, y)
  local st = S.stroke
  if st.fractional then
    local px, py = view:CursorPoint()
    if px then
      local d = doc.drawing
      -- Cell centers are whole numbers, the picture spans 0.5 .. size + 0.5.
      x, y = U.clamp(px / S.zoom + 0.5, 0.5, d.w + 0.5), U.clamp(py / S.zoom + 0.5, 0.5, d.h + 0.5)
      -- The brush is centered on the cursor, the logic anchors even sizes half a cell off.
      x, y = x - D.brushOffset(S.brush), y - D.brushOffset(S.brush)
    else
      x, y = clampCell(x, y)
    end
    if st.x and (x - st.x) ^ 2 + (y - st.y) ^ 2 < 0.0625 then
      return
    end
  else
    x, y = clampCell(x, y)
    if st.x == x and st.y == y then
      return
    end
  end
  st.x, st.y = x, y
  local dirty, preview = doc.ed:strokeTo(x, y)
  if st.shape then
    view:SetOverlay(preview)
  elseif dirty then
    view:RepaintRows(dirty.y1, dirty.y2)
  end
end

local function finishStroke()
  local st = S.stroke
  if not st then
    return
  end
  S.stroke = nil
  local ch = doc.ed:endStroke()
  view:SetOverlay(nil)
  if ch then
    repaint(ch)
  end
  updateHandles()
  refreshUI()
end

local function feedDrag(x, y)
  local drag = S.drag
  x, y = clampCell(x, y)
  if drag.x == x and drag.y == y then
    return
  end
  drag.x, drag.y = x, y
  if drag.kind == "new" then
    view:SetSelection(drag.ax, drag.ay, x, y)
    DE.UpdateStatus({ drag.ax, drag.ay, x, y })
    return
  end
  local r = drag.rect
  local dx, dy = x - drag.ax, y - drag.ay
  local ch, moved =
    D.move(doc.drawing, { x1 = r[1], y1 = r[2], x2 = r[3], y2 = r[4], dx = dx, dy = dy, preview = true })
  view:SetOverlay(ch)
  if moved then
    view:SetSelection(moved.x1, moved.y1, moved.x2, moved.y2)
  end
end

local function finishDrag()
  local drag = S.drag
  if not drag then
    return
  end
  S.drag = nil
  if drag.kind == "new" then
    if drag.x and (drag.x ~= drag.ax or drag.y ~= drag.ay) then
      setSelection({ drag.ax, drag.ay, drag.x, drag.y })
    else
      setSelection(nil)
    end
  else
    view:SetOverlay(nil)
    local dx, dy = (drag.x or drag.ax) - drag.ax, (drag.y or drag.ay) - drag.ay
    local r = drag.rect
    if dx ~= 0 or dy ~= 0 then
      local ok, moved = run("move", { x1 = r[1], y1 = r[2], x2 = r[3], y2 = r[4], dx = dx, dy = dy })
      if ok and moved then
        setSelection({ moved.x1, moved.y1, moved.x2, moved.y2 })
      end
    else
      setSelection(r)
    end
  end
  updateHandles()
  refreshUI()
end

-- Resize handles ------------------------------------------------------------------------

local function showResizePreview(w, h)
  local p = ui.preview
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", view.frame, "TOPLEFT", 0, 0)
  p:SetSize(max(1, w * S.zoom), max(1, h * S.zoom))
  p:Show()
end

local function startResize(edge)
  if not doc or S.stroke or S.drag or S.resize then
    return
  end
  local px, py = view:CursorPoint()
  if not px then
    return
  end
  local d = doc.drawing
  S.note = nil
  S.resize = { edge = edge, px = px, py = py, w0 = d.w, h0 = d.h, w = d.w, h = d.h }
  showResizePreview(d.w, d.h)
  DE.UpdateStatus()
end

-- The dragged edge follows the cursor in whole cells, clamped to the limits.
local function feedResize()
  local r = S.resize
  local px, py = view:CursorPoint()
  if not (r and px) then
    return
  end
  local dx, dy = floor((px - r.px) / S.zoom + 0.5), floor((py - r.py) / S.zoom + 0.5)
  local w = r.edge == "bottom" and r.w0 or r.w0 + dx
  local h = r.edge == "right" and r.h0 or r.h0 + dy
  -- When the cell limit bites, the side that moved less stays.
  local keep = r.edge == "right" and "h" or r.edge == "bottom" and "w" or (math.abs(dx) >= math.abs(dy) and "h" or "w")
  local cw, ch, limited = D.clampDims(w, h, keep)
  if cw == r.w and ch == r.h and limited == r.limited then
    return
  end
  r.w, r.h, r.limited = cw, ch, limited
  showResizePreview(cw, ch)
  DE.UpdateStatus()
end

local function finishResize()
  local r = S.resize
  if not r then
    return
  end
  S.resize = nil
  hideResizePreview()
  if r.w ~= r.w0 or r.h ~= r.h0 then
    DE.Resize(r.w, r.h)
    if r.limited then
      note("draw.msg.resizeLimit")
    end
  else
    refreshUI()
  end
end

local HANDLES = {
  { id = "right", anchor = "LEFT", rel = "RIGHT", x = 1, y = 0 },
  { id = "bottom", anchor = "TOP", rel = "BOTTOM", x = 0, y = -1 },
  { id = "corner", anchor = "TOPLEFT", rel = "BOTTOMRIGHT", x = 1, y = -1 },
}

-- Handles are hidden while a stroke or a selection move is running.
function updateHandles()
  if not ui.handleList then
    return
  end
  local show = doc ~= nil and not S.stroke and not S.drag
  for _, h in ipairs(ui.handleList) do
    h:SetShown(show)
  end
end

local function buildHandles()
  ui.handles, ui.handleList = {}, {}
  for _, def in ipairs(HANDLES) do
    local h = CreateFrame("Button", nil, ui.holder)
    h:SetSize(HANDLE_HIT, HANDLE_HIT)
    h:SetPoint(def.anchor, ui.canvas, def.rel, def.x, def.y)
    h:SetFrameLevel(ui.canvas:GetFrameLevel() + 10)
    h:EnableMouse(true)
    local outline = h:CreateTexture(nil, "BACKGROUND")
    outline:SetSize(HANDLE_VIS + 2, HANDLE_VIS + 2)
    outline:SetPoint("CENTER")
    local fill = h:CreateTexture(nil, "ARTWORK")
    fill:SetSize(HANDLE_VIS, HANDLE_VIS)
    fill:SetPoint("CENTER")
    h.fill = fill
    local function paint()
      outline:SetColorTexture(0, 0, 0, 1)
      fill:SetColorTexture(Theme.color(h.hover and "text" or "accent2"))
    end
    ns.Bind(h, paint)
    h:SetScript("OnEnter", function()
      h.hover = true
      paint()
      ns.ShowTooltip(h, L["draw.handle"], L["draw.handle.tip"])
    end)
    h:SetScript("OnLeave", function()
      h.hover = false
      paint()
      ns.HideTooltip()
    end)
    h:SetScript(
      "OnMouseDown",
      ns.Wrap("draw-handle", function(_, button)
        if button == "LeftButton" then
          startResize(def.id)
        end
      end)
    )
    h:SetScript(
      "OnMouseUp",
      ns.Wrap("draw-handle", function(_, button)
        if button == "LeftButton" and S.resize then
          feedResize()
          finishResize()
        end
      end)
    )
    ui.handles[def.id] = h
    ui.handleList[#ui.handleList + 1] = h
  end
end

-- Dark and light outline in one: readable on the white canvas and on the dark surround.
local function buildPreview()
  local p = CreateFrame("Frame", nil, ui.holder)
  p:SetFrameLevel(ui.canvas:GetFrameLevel() + 8)
  local function ring(r, g, b, inset, thick, sublevel)
    local function edge(p1, p2, horizontal)
      local t = p:CreateTexture(nil, "OVERLAY", nil, sublevel)
      t:SetColorTexture(r, g, b, 1)
      for _, point in ipairs({ p1, p2 }) do
        t:SetPoint(point, p, point, point:find("LEFT") and inset or -inset, point:find("TOP") and -inset or inset)
      end
      if horizontal then
        t:SetHeight(thick)
      else
        t:SetWidth(thick)
      end
    end
    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
  end
  ring(0, 0, 0, 0, 3, 0)
  ring(1, 1, 1, 1, 1, 1)
  p:Hide()
  ui.preview = p
end

local function onMouseDown(_, button)
  if button ~= "LeftButton" or not doc or S.stroke or S.drag or S.resize then
    return
  end
  local cx, cy = view:CursorCell()
  if not cx then
    return
  end
  local d = doc.drawing
  local inside = cx >= 1 and cx <= d.w and cy >= 1 and cy <= d.h
  local tool = S.tool
  S.note = nil
  if tool == "select" then
    local r = S.sel
    if r and cx >= r[1] and cx <= r[3] and cy >= r[2] and cy <= r[4] then
      S.drag = { kind = "move", ax = cx, ay = cy, rect = r }
    elseif inside then
      S.drag = { kind = "new", ax = cx, ay = cy }
      setSelection(nil)
    else
      setSelection(nil)
      refreshUI()
    end
    updateHandles()
    return
  end
  if tool == "zoom" then
    local zx, zy = clampCell(cx, cy)
    magnify(zx, zy, IsShiftKeyDown() == true)
    return
  end
  if not inside then
    return
  end
  if tool == "pick" then
    S.color = D.pick(d, cx, cy) or S.color
    refreshUI()
  elseif tool == "fill" then
    run("fill", { x = cx, y = cy, color = S.color, tolerance = S.tolerance })
  elseif
    doc.ed:beginStroke(
      tool,
      S.color,
      S.brush,
      { shape = S.shape, fill = fillOption(), aa = softEdges(), smooth = S.smooth }
    )
  then
    local isShape = tool == "line" or tool == "rect" or tool == "ellipse"
    S.stroke = { shape = isShape, fractional = not isShape and (softEdges() or S.smooth) }
    S.sizePending, S.sizeWait = true, 0
    DE.UpdateStatus()
    updateHandles()
    feedStroke(cx, cy)
  end
end

local function onMouseUp(_, button)
  if button ~= "LeftButton" then
    return
  end
  if S.stroke then
    local cx, cy = view:CursorCell()
    if cx then
      feedStroke(cx, cy)
    end
    finishStroke()
  elseif S.drag then
    local cx, cy = view:CursorCell()
    if cx then
      feedDrag(cx, cy)
    end
    finishDrag()
  end
end

local SIZE_DELAY = 0.4

-- Packed size and chat verdict of the drawing. Encoding deflates up to three
-- times, so this only runs once the drawing was left alone for SIZE_DELAY
-- seconds (see onUpdate), never while a stroke, drag or resize is running.
local function computeSize()
  S.sizePending = false
  local d = doc and doc.drawing
  S.bytes, S.sizeInfo = nil, nil
  if d then
    local size, _, length = D.EncodedSize(d)
    local bytes = size or length
    if bytes then
      S.bytes = bytes
      S.sizeInfo = ns.DrawingLink.ShareInfo(bytes, doc.name)
    else
      S.bytes = false
    end
  end
  DE.UpdateStatus()
end

-- Tools that draw with the brush width (the eraser stays on whole cells).
local THIN_TOOLS = { pencil = true, line = true, rect = true, ellipse = true }

-- 9200 -> "9.2k", 16000 -> "16k", below a thousand the plain number.
local function kilo(n)
  if n < 1000 then
    return tostring(floor(n))
  end
  return (string.format("%.1f", n / 1000):gsub("%.0$", "")) .. "k"
end

-- Fills the status bar segments from the current state. `live` is a selection
-- rectangle being dragged (corner order does not matter).
function DE.UpdateStatus(live)
  local bar = ui.status
  if not bar then
    return
  end
  local d = doc and doc.drawing
  bar:SetSegment("pos", S.hover and (S.hover[1] .. ", " .. S.hover[2]) or "")
  local r = live or S.sel
  bar:SetSegment("sel", r and fmt("draw.status.sel", math.abs(r[3] - r[1]) + 1, math.abs(r[4] - r[2]) + 1) or "")
  local rs = S.resize
  local w, h = rs and rs.w or d and d.w, rs and rs.h or d and d.h
  bar:SetSegment("size", d and fmt("draw.status.size", w, h) or "")
  local state = ""
  if doc then
    state = doc.id == nil and L["draw.status.unsaved"] or L[isDirty() and "draw.status.modified" or "draw.status.saved"]
  end
  bar:SetSegment("state", state)
  bar:SetSegment("load", doc and fmt("draw.status.load", kilo(view:Stats().objects), kilo(view:Stats().limit)) or "")
  local hint = S.note or L["draw.tool." .. S.tool .. ".hint"]
  if rs and rs.limited then
    hint = L["draw.msg.resizeLimit"]
  end
  local load = doc and view:Stats()
  if load then
    local why = load.over and L["draw.status.over"]
      or load.stage == "tones" and fmt("draw.status.tones", load.tones)
      or load.stage == "step" and fmt("draw.status.coarse", load.step)
    if why then
      hint = why .. (load.canRestore and ". " .. L["draw.status.restore"] or "") .. "   |   " .. hint
    end
  end
  if doc and d.map and THIN_TOOLS[S.tool] and (S.aa or S.brush < 1) then
    hint = L["draw.map.hardEdges"] .. "   |   " .. hint
  elseif doc and S.brush < 1 and not S.aa and THIN_TOOLS[S.tool] then
    hint = L["draw.status.thinNeedsSoft"] .. "   |   " .. hint
  end
  if doc and view.mapReason then
    hint = fmt("draw.map.missing", ns.DrawingMap.Describe(d.map)) .. "   |   " .. hint
  end
  bar:SetSegment("hint", hint)
  local bytesText, verdict, color = "", "", "textSecondary"
  if doc and S.sizePending then
    bytesText = L["draw.status.pending"]
  elseif doc and S.bytes then
    bytesText = ns.DrawingLink.SizeText(S.bytes)
    verdict, color = ns.DrawingLink.ShareLine(S.sizeInfo)
  elseif doc and S.bytes == false then
    bytesText = L["draw.status.noSize"]
  end
  bar:SetSegment("bytes", bytesText)
  bar:SetSegment("share", verdict)
  W.SetColor(bar.byId.bytes.fs, color == "warning" and color or "textSecondary")
  W.SetColor(bar.byId.share.fs, color)
  bar:SetSegment("zoom", S.zoom * 100)
end

local function onUpdate(_, elapsed)
  if not doc then
    return
  end
  if S.sizePending and not (S.stroke or S.drag or S.resize) then
    S.sizeWait = (S.sizeWait or 0) + (elapsed or 0)
    if S.sizeWait >= SIZE_DELAY then
      computeSize()
    end
  end
  local cx, cy = view:CursorCell()
  local d = doc.drawing
  local inside = cx and cx >= 1 and cx <= d.w and cy >= 1 and cy <= d.h
  local hx, hy = inside and cx or nil, inside and cy or nil
  if (S.hover and S.hover[1]) ~= hx or (S.hover and S.hover[2]) ~= hy then
    S.hover = inside and { cx, cy } or nil
    DE.UpdateStatus()
  end
  if not (S.stroke or S.drag or S.resize) then
    return
  end
  -- A release outside the window never reaches OnMouseUp: poll the button.
  local held = true
  if IsMouseButtonDown then
    held = IsMouseButtonDown("LeftButton")
  end
  if S.resize then
    feedResize()
    if not held then
      finishResize()
    end
    return
  end
  if cx then
    if S.stroke then
      feedStroke(cx, cy)
    else
      feedDrag(cx, cy)
    end
  end
  if not held then
    if S.stroke then
      finishStroke()
    else
      finishDrag()
    end
  end
end

local function onWheel(_, delta)
  if not doc then
    return
  end
  if IsControlKeyDown() then
    setZoom(S.zoom + (delta > 0 and 1 or -1))
  elseif IsShiftKeyDown() then
    ui.scroll:SetHorizontalScroll(numberOr(ui.scroll:GetHorizontalScroll(), 0) - delta * 40)
    clampScroll()
  else
    ui.scroll:SetVerticalScroll(numberOr(ui.scroll:GetVerticalScroll(), 0) - delta * 40)
    clampScroll()
  end
end

-- Keyboard -------------------------------------------------------------------------------

-- Returns true when the key was used (it is then not passed on to the game).
local function handleKey(key)
  if not (doc and frame:IsShown()) then
    return false
  end
  -- An open menu or gallery takes Esc first.
  if key == "ESCAPE" and Desktop.Layer.current and Desktop.Layer.escape() then
    return true
  end
  if not frame:IsMouseOver() and not (S.stroke or S.drag or S.resize) then
    return false
  end
  local ctrl = IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
  if key == "ESCAPE" then
    if S.stroke or S.drag or S.resize then
      cancelStroke()
    elseif S.sel then
      setSelection(nil)
      refreshUI()
    else
      DE.Close()
    end
    return true
  end
  if S.stroke or S.drag or S.resize then
    return false
  end
  if ctrl then
    if key == "Z" then
      if IsShiftKeyDown() then
        DE.Redo()
      else
        DE.Undo()
      end
    elseif key == "Y" then
      DE.Redo()
    elseif key == "C" then
      DE.Copy()
    elseif key == "X" then
      DE.Cut()
    elseif key == "V" then
      DE.Paste()
    elseif key == "A" then
      DE.SelectAll()
    elseif key == "S" then
      DE.Save()
    else
      return false
    end
    return true
  end
  if key == "DELETE" or key == "BACKSPACE" then
    if S.sel then
      DE.Delete()
      return true
    end
  end
  return false
end

local keyboardReady
local function setupKeyboard()
  if keyboardReady or not ns.can.propagateKeyboard then
    return
  end
  -- Propagation cannot be changed in combat, so keys then keep going to the game.
  if InCombatLockdown() then
    ns.On("PLAYER_REGEN_ENABLED", setupKeyboard)
    return
  end
  keyboardReady = true
  ns.PropagateKeys(frame, true)
  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then
      return
    end
    local _, handled = ns.Safe("draw-key", handleKey, key)
    ns.PropagateKeys(self, not handled)
  end)
end

-- Custom colors -----------------------------------------------------------------------

local function commitPicked()
  local c = S.pending
  S.pending = nil
  if not (c and doc) then
    return
  end
  local idx = D.addColor(doc.drawing, c[1] * 255, c[2] * 255, c[3] * 255)
  if idx then
    S.color = idx
  else
    ns.Notify(fmt("draw.msg.paletteFull", D.MAX_PALETTE), "warning")
  end
  refreshUI()
end

-- Blizzard's picker reports every change while it is open, so the color is
-- only added to the palette once the picker closes (and was not cancelled).
function DE.PickColor()
  if not (doc and ColorPickerFrame) then
    return
  end
  local p = doc.drawing.palette[S.color] or { 0, 0, 0 }
  local r, g, b = p[1] / 255, p[2] / 255, p[3] / 255
  S.pending = nil
  local function apply()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    S.pending = { nr, ng, nb }
  end
  local function cancel()
    S.pending = nil
  end
  if not S.pickerHooked then
    S.pickerHooked = true
    ColorPickerFrame:HookScript("OnHide", ns.Wrap("draw-color", commitPicked))
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

-- UI refresh and layout ----------------------------------------------------------------

-- The first `limit` colors a user picks from as normalized colors for a swatch
-- grid, plus the palette index behind every swatch. The helper colors the soft
-- edges added to the palette (auto colors) never show up here.
local function swatchList(limit)
  local list, map = {}, {}
  local d = doc and doc.drawing
  for _, idx in ipairs(d and D.userColors(d) or {}) do
    if #list >= limit then
      break
    end
    local p = d.palette[idx]
    list[#list + 1] = { p[1] / 255, p[2] / 255, p[3] / 255 }
    map[#list] = idx
  end
  return list, map
end

-- Re-reads the palette into the ribbon grid when the drawing, its color count
-- or the set of helper colors changed. Returns true when it did.
local function syncPalette()
  local d = doc and doc.drawing
  local key = "0"
  if d then
    local autos = 0
    for _ in pairs(d.auto or {}) do
      autos = autos + 1
    end
    key = #d.palette .. ":" .. autos
  end
  if ui.paletteKey == key and ui.paletteDoc == doc then
    return false
  end
  ui.paletteKey, ui.paletteDoc = key, doc
  local list, map = swatchList(PALETTE_VISIBLE)
  ui.paletteMap = map
  ui.palette:SetColors(list)
  return true
end

local function layoutTop()
  ui.top:SetHeight(scaled(TOP_H))
  ui.menu:Layout()
  local w = 4
  for _, title in ipairs(ui.menu.titles) do
    w = w + title:GetWidth()
  end
  -- The bar's own width decides what counts as "inside" for the popup watcher.
  ui.menu:SetWidth(w)
  ui.menuWidth = w
end

local function relayoutBoxes()
  for _, box in ipairs(ui.boxes) do
    box:Relayout()
  end
end

-- Ribbon width in both modes; leaves the ribbon in full mode.
local function measureRibbon()
  ui.compact = true
  relayoutBoxes()
  ui.ribbon:Layout()
  local compactW = ui.ribbon.contentWidth or 0
  ui.compact = false
  relayoutBoxes()
  ui.ribbon:Layout()
  return compactW, ui.ribbon.contentWidth or 0
end

local function layoutStage()
  local stage = ui.stage
  stage:ClearAllPoints()
  stage:SetPoint("TOPLEFT", ui.ribbon, "BOTTOMLEFT", 0, 0)
  stage:SetPoint("TOPRIGHT", ui.ribbon, "BOTTOMRIGHT", 0, 0)
  if S.statusBar then
    stage:SetPoint("BOTTOMLEFT", ui.status, "TOPLEFT", 0, 0)
    stage:SetPoint("BOTTOMRIGHT", ui.status, "TOPRIGHT", 0, 0)
  else
    stage:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    stage:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  end
  ui.status:SetShown(S.statusBar)
  ui.panel:SetSize(scaled(40), scaled(PANEL_H))
  ui.scroll:ClearAllPoints()
  ui.scroll:SetPoint("TOPLEFT", stage, "TOPLEFT", scaled(SIDE_W), -STAGE_PAD)
  ui.scroll:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", -STAGE_PAD, STAGE_PAD)
end

-- Smallest size the window may have: the collapsed ribbon, the top row and
-- the brush panel must fit without clipping.
function DE.MinSize()
  return ui.minW or MIN_W, ui.minH or MIN_H
end

function layout()
  if not (frame and ui.ready) or ui.laying then
    return
  end
  ui.laying = true
  syncPalette()
  layoutTop()
  local compactW, fullW = measureRibbon()
  local topNeed = ui.menuWidth + 12 + 4 * scaled(32) + 10 + 12 + 150
  ui.minW = max(MIN_W, ceil(max(compactW, topNeed)) + 2)
  ui.minH = max(
    MIN_H,
    ceil(HEAD_H + ui.top:GetHeight() + ui.ribbon:GetHeight() + scaled(STATUS_H) + scaled(PANEL_H) + 2 * STAGE_PAD)
  )
  if frame.SetResizeBounds then
    frame:SetResizeBounds(ui.minW, ui.minH, MAX_W, MAX_H)
  elseif frame.SetMinResize then
    frame:SetMinResize(ui.minW, ui.minH)
  end
  if frame:GetWidth() < ui.minW or frame:GetHeight() < ui.minH then
    frame:SetSize(max(frame:GetWidth(), ui.minW), max(frame:GetHeight(), ui.minH))
  end
  -- Shapes collapse into dropdowns only when the full ribbon does not fit.
  ui.compact = fullW > frame:GetWidth()
  relayoutBoxes()
  ui.ribbon:Layout()
  layoutStage()
  ui.status:Layout(frame:GetWidth() - 17)
  layoutCanvas()
  ui.laying = false
end

function refreshUI()
  if not (frame and ui.ready) then
    return
  end
  local has = doc ~= nil
  if has and S.color > #doc.drawing.palette then
    S.color = 1
  end
  if syncPalette() then
    layout()
  end
  if has then
    ui.primary:SetColor(swatchColor(S.color))
    ui.background:SetColor(swatchColor(D.BACKGROUND))
  end
  ui.ribbon:Refresh()
  for _, b in ipairs(ui.quick) do
    b:Refresh()
  end
  ui.brush:Refresh()
  ui.brushValue:SetText(tostring(S.brush))
  ui.menu:Refresh()
  local title = L["draw.editor.title"]
  if has then
    local name = DR.cleanName(doc.name)
    title = title .. ": " .. (name ~= "" and name or L["draw.untitled"]) .. (isDirty() and " *" or "")
  end
  ui.title:SetText(title)
  if has and not ui.name.edit:HasFocus() and ui.name.edit:GetText() ~= doc.name then
    ui.name.edit:SetText(doc.name)
  end
  DE.UpdateStatus()
end

-- Window -------------------------------------------------------------------------------------

local function applyScale()
  local scale = ns.db.settings and ns.db.settings.scale
  frame:SetScale(U.clamp(numberOr(scale, 1), 0.5, 2))
end

local function place()
  local db = frameDb()
  local w, h = U.clamp(numberOr(db.w, DEFAULT_W), ui.minW or MIN_W, MAX_W), numberOr(db.h, DEFAULT_H)
  frame:SetSize(w, U.clamp(h, ui.minH or MIN_H, MAX_H))
  frame:ClearAllPoints()
  local s = frame:GetScale()
  if type(db.x) == "number" and type(db.y) == "number" then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  ns.WindowShell.FitToScreen(frame)
end

local function savePosition()
  local left, top = frame:GetLeft(), frame:GetTop()
  if left and top then
    local s, db = frame:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function saveSize()
  local db = frameDb()
  db.w, db.h = frame:GetWidth(), frame:GetHeight()
end

local function saveSettings()
  local db = frameDb()
  db.grid, db.brush, db.shape, db.fillMode, db.statusBar = S.grid, S.brush, S.shape, S.fillMode, S.statusBar
  db.aa, db.smooth, db.tolerance = S.aa, S.smooth, S.tolerance
end

local function loadSettings()
  local db = frameDb()
  S.grid = db.grid == true
  local brush = numberOr(db.brush, 1)
  S.brush = brush < 1 and D.brushSize(brush) or U.clamp(floor(brush), 1, D.MAX_BRUSH)
  S.shape = db.shape == "round" and "round" or "square"
  S.fillMode = (db.fillMode == "fill" or db.fillMode == "solid") and db.fillMode or "outline"
  S.statusBar = db.statusBar ~= false
  S.aa = db.aa ~= false
  S.smooth = db.smooth ~= false
  S.tolerance = D.DEFAULT_TOLERANCE
  for _, pct in ipairs(D.TOLERANCES) do
    if db.tolerance == pct then
      S.tolerance = pct
    end
  end
end

local function scrollbarH(parent, onScroll)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(6)
  bar:SetPoint("BOTTOMLEFT", 2, 2)
  bar:SetPoint("BOTTOMRIGHT", -12, 2)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetHeight(6)
  ns.Bind(thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)
  function bar:Update(visibleFrac, pos)
    if visibleFrac >= 1 then
      bar:Hide()
      return
    end
    bar:Show()
    local w = bar:GetWidth()
    local tw = max(20, w * visibleFrac)
    thumb:SetWidth(tw)
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", (w - tw) * pos, 0)
  end
  local function frac(self)
    local cx = GetCursorPosition()
    local s = self:GetEffectiveScale()
    return U.clamp((cx / s - numberOr(self:GetLeft(), 0)) / max(1, self:GetWidth()), 0, 1)
  end
  bar:EnableMouse(true)
  bar:SetScript("OnMouseDown", function(self)
    onScroll(frac(self))
    self:SetScript("OnUpdate", function(bar2)
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        bar2:SetScript("OnUpdate", nil)
        return
      end
      onScroll(frac(bar2))
    end)
  end)
  bar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return bar
end

-- Builders -------------------------------------------------------------------------------

local function hasDoc()
  return doc ~= nil
end

local function hasSelection()
  return doc ~= nil and S.sel ~= nil
end

local function hasMap()
  return doc ~= nil and doc.drawing.map ~= nil
end

-- Index of the preset closest to the current brush width.
local function brushIndex()
  local best, bestDist = 1, math.huge
  for i, size in ipairs(D.BRUSH_SIZES) do
    local dist = math.abs(size - S.brush)
    if dist < bestDist then
      best, bestDist = i, dist
    end
  end
  return best
end

local function setBrush(v)
  S.brush = v < 1 and D.brushSize(v) or U.clamp(floor(v), 1, D.MAX_BRUSH)
  saveSettings()
  refreshUI()
end

local function setBrushShape(shape)
  S.shape = shape
  saveSettings()
  refreshUI()
end

local function setFillMode(mode)
  S.fillMode = mode
  saveSettings()
  refreshUI()
end

local function setAA(on)
  S.aa = on == true
  saveSettings()
  refreshUI()
end

local function setSmooth(on)
  S.smooth = on == true
  saveSettings()
  refreshUI()
end

local function setTolerance(pct)
  S.tolerance = pct
  saveSettings()
  refreshUI()
end

local function setGrid(on)
  S.grid = on
  if view and doc then
    view:SetGrid(on)
  end
  saveSettings()
  refreshUI()
end

local function setStatusBar(on)
  S.statusBar = on
  saveSettings()
  layout()
  refreshUI()
end

local function pickColor(index)
  S.color = index
  refreshUI()
end

-- Current color as a normalized triple (nil without a drawing).
local function currentColor()
  local p = doc and doc.drawing.palette[S.color]
  return p and { p[1] / 255, p[2] / 255, p[3] / 255 } or nil
end

-- Tooltip and pick handler of a swatch grid whose swatch positions map to
-- palette indices through ui[mapKey].
local function swatchTip(mapKey)
  return function(_, index)
    local idx = ui[mapKey] and ui[mapKey][index]
    local p = idx and doc and doc.drawing.palette[idx]
    return p and fmt("draw.color.swatch", idx, p[1], p[2], p[3]) or nil
  end
end

local function swatchPick(mapKey)
  return function(_, index)
    local idx = ui[mapKey] and ui[mapKey][index]
    if idx then
      pickColor(idx)
    end
  end
end

-- Menu bar ------------------------------------------------------------------------------

local function shortcut(key)
  return function()
    return L[key]
  end
end

-- Radio entries 0 / 6 / 12 / 25 / 40 percent for the fill tolerance submenu.
local function toleranceItems()
  local items = {}
  for i, pct in ipairs(D.TOLERANCES) do
    items[i] = {
      id = "tol" .. pct,
      key = pct == 0 and "draw.tolerance.exact" or nil,
      text = pct ~= 0 and (pct .. " %") or nil,
      checked = function()
        return S.tolerance == pct
      end,
      onClick = function()
        setTolerance(pct)
      end,
    }
  end
  return items
end

local function menuDef()
  local function canUndo()
    return doc ~= nil and doc.ed:canUndo()
  end
  local function canRedo()
    return doc ~= nil and doc.ed:canRedo()
  end
  return {
    {
      key = "draw.menu.file",
      id = "file",
      items = {
        {
          id = "save",
          key = "draw.save",
          shortcut = shortcut("draw.sc.save"),
          enabled = hasDoc,
          onClick = function()
            DE.Save()
          end,
        },
        {
          id = "saveClose",
          key = "draw.saveClose",
          enabled = hasDoc,
          onClick = function()
            DE.SaveAndClose()
          end,
        },
        {
          id = "export",
          key = "draw.export",
          separator = true,
          enabled = hasDoc,
          onClick = function()
            DE.Export()
          end,
        },
        {
          id = "share",
          key = "draw.share",
          enabled = hasDoc,
          onClick = function()
            DE.Share()
          end,
        },
        {
          id = "window",
          key = "draw.window",
          enabled = hasDoc,
          onClick = function()
            DE.ShowAsWindow()
          end,
        },
        {
          id = "close",
          key = "common.close",
          separator = true,
          onClick = function()
            DE.Close()
          end,
        },
      },
    },
    {
      key = "draw.menu.edit",
      id = "edit",
      items = {
        {
          id = "undo",
          key = "draw.undo",
          shortcut = shortcut("draw.sc.undo"),
          enabled = canUndo,
          onClick = function()
            DE.Undo()
          end,
        },
        {
          id = "redo",
          key = "draw.redo",
          shortcut = shortcut("draw.sc.redo"),
          enabled = canRedo,
          onClick = function()
            DE.Redo()
          end,
        },
        {
          id = "cut",
          key = "draw.act.cut",
          separator = true,
          shortcut = shortcut("draw.sc.cut"),
          enabled = hasSelection,
          onClick = function()
            DE.Cut()
          end,
        },
        {
          id = "copy",
          key = "draw.act.copy",
          shortcut = shortcut("draw.sc.copy"),
          enabled = hasSelection,
          onClick = function()
            DE.Copy()
          end,
        },
        {
          id = "paste",
          key = "draw.act.paste",
          shortcut = shortcut("draw.sc.paste"),
          enabled = function()
            return doc ~= nil and clip ~= nil
          end,
          onClick = function()
            DE.Paste()
          end,
        },
        {
          id = "selectAll",
          key = "draw.act.selectAll",
          separator = true,
          shortcut = shortcut("draw.sc.all"),
          enabled = hasDoc,
          onClick = function()
            DE.SelectAll()
          end,
        },
        {
          id = "deleteSel",
          key = "draw.menu.deleteSel",
          shortcut = shortcut("draw.sc.delete"),
          enabled = hasSelection,
          onClick = function()
            DE.Delete()
          end,
        },
        {
          id = "clearAll",
          key = "draw.menu.clearAll",
          enabled = hasDoc,
          onClick = function()
            DE.Clear()
          end,
        },
        {
          id = "resize",
          key = "draw.menu.resize",
          separator = true,
          enabled = hasDoc,
          onClick = function()
            DE.ResizeDialog()
          end,
        },
        {
          id = "crop",
          key = "draw.menu.crop",
          enabled = hasSelection,
          onClick = function()
            DE.CropToSelection()
          end,
        },
        {
          id = "map",
          key = "draw.map.choose",
          separator = true,
          enabled = hasDoc,
          onClick = function()
            DE.ChooseMap()
          end,
        },
        {
          id = "mapFit",
          key = "draw.map.fit",
          enabled = hasMap,
          onClick = function()
            DE.FitToMap()
          end,
        },
        {
          id = "mapRemove",
          key = "draw.map.remove",
          enabled = hasMap,
          onClick = function()
            DE.RemoveMap()
          end,
        },
        {
          id = "aa",
          key = "draw.aa",
          separator = true,
          checked = function()
            return S.aa
          end,
          onClick = function()
            setAA(not S.aa)
          end,
        },
        {
          id = "smooth",
          key = "draw.smooth",
          checked = function()
            return S.smooth
          end,
          onClick = function()
            setSmooth(not S.smooth)
          end,
        },
        {
          id = "tolerance",
          key = "draw.tolerance",
          items = toleranceItems(),
        },
      },
    },
    {
      key = "draw.menu.view",
      id = "view",
      items = {
        {
          id = "grid",
          key = "draw.grid",
          enabled = hasDoc,
          checked = function()
            return S.grid
          end,
          onClick = function()
            setGrid(not S.grid)
          end,
        },
        {
          id = "zoomIn",
          key = "draw.zoom.in",
          separator = true,
          enabled = hasDoc,
          onClick = function()
            setZoom(S.zoom + 1)
          end,
        },
        {
          id = "zoomOut",
          key = "draw.zoom.out",
          enabled = hasDoc,
          onClick = function()
            setZoom(S.zoom - 1)
          end,
        },
        {
          id = "fit",
          key = "draw.fit",
          enabled = hasDoc,
          onClick = function()
            DE.Fit()
          end,
        },
        {
          id = "fullDisplay",
          key = "draw.fullDisplay",
          enabled = function()
            return doc ~= nil and view:Stats().canRestore
          end,
          onClick = function()
            view:Restore()
            DE.UpdateStatus()
          end,
        },
        {
          id = "statusBar",
          key = "draw.menu.statusBar",
          separator = true,
          checked = function()
            return S.statusBar
          end,
          onClick = function()
            setStatusBar(not S.statusBar)
          end,
        },
      },
    },
  }
end

-- Top row: menu bar, quick icons and the name field.
local function buildTop(f)
  local row = CreateFrame("Frame", nil, f)
  row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD_H)
  row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD_H)
  row:SetHeight(scaled(TOP_H))
  W.Fill(row, "surface2", 1)
  ui.top = row
  ui.menu = W.MenuBar(row, menuDef(), { height = TOP_H, fill = false })
  ui.menu:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

  -- An icon button of the top row; Refresh follows def.enabled.
  local function quick(def)
    local b = W.Action(row, {
      icon = def.icon,
      size = 32,
      tooltip = def.tooltip,
      tooltipText = def.tooltipText,
      onClick = def.onClick,
    })
    function b.Refresh()
      b:SetEnabled(def.enabled())
    end
    b.Refresh()
    return b
  end
  ui.save = quick({
    icon = "save",
    tooltip = "draw.save",
    tooltipText = "draw.saveTip",
    enabled = hasDoc,
    onClick = function()
      DE.Save()
    end,
  })
  ui.share = quick({
    icon = "share",
    tooltip = "draw.share",
    tooltipText = "draw.share.tip",
    enabled = hasDoc,
    onClick = function()
      DE.Share()
    end,
  })
  ui.undo = quick({
    icon = "undo",
    tooltip = "draw.undo",
    tooltipText = "draw.undo.tip",
    enabled = function()
      return doc ~= nil and doc.ed:canUndo()
    end,
    onClick = function()
      DE.Undo()
    end,
  })
  ui.redo = quick({
    icon = "redo",
    tooltip = "draw.redo",
    tooltipText = "draw.redo.tip",
    enabled = function()
      return doc ~= nil and doc.ed:canRedo()
    end,
    onClick = function()
      DE.Redo()
    end,
  })
  ui.quick = { ui.save, ui.share, ui.undo, ui.redo }
  ui.save:SetPoint("LEFT", ui.menu, "RIGHT", 12, 0)
  ui.share:SetPoint("LEFT", ui.save, "RIGHT", 2, 0)
  ui.undo:SetPoint("LEFT", ui.share, "RIGHT", 10, 0)
  ui.redo:SetPoint("LEFT", ui.undo, "RIGHT", 2, 0)

  ui.name = W.EditBox(row, {
    placeholder = "draw.namePlaceholder",
    height = 22,
    onChange = function(text)
      if doc then
        doc.name = text
        refreshUI()
      end
    end,
  })
  ui.name:SetPoint("LEFT", ui.redo, "RIGHT", 12, 0)
  ui.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  ui.name.edit:SetMaxLetters(DR.MAX_NAME)
end

-- Ribbon --------------------------------------------------------------------------------

-- A frame that stacks `parts` (widgets created with it as parent) top down.
local function newStack(parent, parts, gap)
  local box = CreateFrame("Frame", nil, parent)
  box.parts = parts
  for _, part in ipairs(parts) do
    part:SetParent(box)
  end
  function box:Relayout()
    local y, w = 0, 0
    for _, part in ipairs(parts) do
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
      y = y + part:GetHeight() + gap
      w = max(w, part:GetWidth())
    end
    box:SetSize(max(1, w), max(1, y - gap))
  end
  function box:Refresh()
    for _, part in ipairs(parts) do
      if part.Refresh then
        part:Refresh()
      end
    end
  end
  ui.boxes[#ui.boxes + 1] = box
  return box
end

local function toolDef(tool, glyph)
  return {
    glyph = glyph,
    tooltip = "draw.tool." .. tool,
    tooltipText = "draw.tool." .. tool .. ".tip",
    selected = function()
      return S.tool == tool
    end,
    onClick = function()
      setTool(tool)
    end,
  }
end

-- Adds "also selected" and "also run" behavior to a dropdown button def.
local function wrapDropdown(btn, isActive, onClick)
  local baseSelected, baseClick = btn.def.selected, btn.def.onClick
  btn.def.selected = function(b)
    return baseSelected(b) or isActive()
  end
  btn.def.onClick = function(b)
    onClick()
    baseClick(b)
  end
end

local function buildSelectionGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.select" })
  local btn = W.IconDropdownButton(g, {
    glyph = "select-rect",
    size = 44,
    width = 210,
    tooltip = "draw.tool.select",
    tooltipText = "draw.tool.select.tip",
    enabled = hasDoc,
    items = {
      { value = "rect", glyph = "select-rect", key = "draw.sel.rect" },
      { value = "all", glyph = "draw-select-all", key = "draw.act.selectAll" },
      { value = "none", glyph = "close", key = "draw.act.selectNone" },
    },
    get = function()
      return S.tool == "select" and "rect" or nil
    end,
    onPick = function(value)
      if value == "rect" then
        setTool("select")
      elseif value == "all" then
        DE.SelectAll()
      else
        DE.SelectNone()
      end
    end,
  })
  -- A click picks the tool and opens the list, like a split button.
  wrapDropdown(btn, function()
    return S.tool == "select"
  end, function()
    if S.tool ~= "select" then
      setTool("select")
    end
  end)
  g:Add(btn)
  ui.tools.select = btn
end

local function buildImageGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.image" })
  local function act(glyph, key, fn)
    return {
      glyph = glyph,
      tooltip = "draw.act." .. key,
      tooltipText = "draw.act." .. key .. ".tip",
      enabled = hasDoc,
      onClick = fn,
    }
  end
  local grid = g:AddTools({
    columns = 2,
    size = 32,
    items = {
      act("flip-h", "flipH", function()
        DE.Flip(true)
      end),
      act("flip-v", "flipV", function()
        DE.Flip(false)
      end),
      act("draw-invert", "invert", function()
        DE.Invert()
      end),
      act("draw-clear", "clear", function()
        DE.Clear()
      end),
    },
  })
  for i, key in ipairs({ "flipH", "flipV", "invert", "clear" }) do
    ui.acts[key] = grid.buttons[i]
  end
end

local function buildMapGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.map" })
  ui.mapBtn = W.ToolButton(g, {
    glyph = "draw-map",
    size = 44,
    tooltip = "draw.map.title",
    tooltipText = "draw.map.choose.tip",
    enabled = hasDoc,
    selected = hasMap,
    onClick = function()
      DE.ChooseMap()
    end,
  })
  g:Add(ui.mapBtn)
end

local function buildToolsGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.tools" })
  local list = {
    { "pencil", "pencil" },
    { "fill", "bucket" },
    { "eraser", "eraser" },
    { "pick", "picker" },
    { "zoom", "magnifier" },
  }
  local items = {}
  for i, t in ipairs(list) do
    items[i] = toolDef(t[1], t[2])
  end
  local grid = g:AddTools({ columns = 3, size = 32, items = items })
  for i, t in ipairs(list) do
    ui.tools[t[1]] = grid.buttons[i]
  end
end

-- Popup below the quality button: the two switches that make strokes finer.
local function toggleQuality(btn)
  local Layer = Desktop.Layer
  if Layer.current and Layer.current.owner == btn then
    Layer.close("api")
    return
  end
  local pop = ui.quality
  if not pop then
    pop = Layer.newPopup("surface")
    pop.boxes = {}
    local function check(key, tip, get, set, y)
      local box = W.Checkbox(pop, { key = key, tooltip = key, tooltipText = tip, get = get, set = set })
      box:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -y)
      box:SetWidth(176)
      pop.boxes[#pop.boxes + 1] = box
    end
    check("draw.aa", "draw.aa.tip", function()
      return S.aa
    end, setAA, 8)
    check("draw.smooth", "draw.smooth.tip", function()
      return S.smooth
    end, setSmooth, 34)
    pop:SetSize(192, 66)
    ui.quality = pop
  end
  for _, box in ipairs(pop.boxes) do
    box:Refresh()
  end
  Layer.place(pop, btn, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  pop:Show()
  Layer.open({
    frames = { pop },
    owner = btn,
    onClose = function()
      btn:Refresh()
    end,
  })
  btn:Refresh()
end

local function buildBrushGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.brush" })
  ui.brushShape = W.IconDropdownButton(g, {
    size = 32,
    columns = 2,
    tooltip = "draw.brush.shape",
    tooltipText = "draw.brush.shape.tip",
    items = {
      {
        value = "square",
        glyph = "draw-brush-square",
        key = "draw.shape.square",
        tooltipText = "draw.shape.square.tip",
      },
      { value = "round", glyph = "draw-brush-round", key = "draw.shape.round", tooltipText = "draw.shape.round.tip" },
    },
    get = function()
      return S.shape
    end,
    onPick = setBrushShape,
  })
  local sizes = {}
  for i, size in ipairs(D.BRUSH_SIZES) do
    sizes[i] = { value = size, glyph = size < 1 and tostring(size):sub(2) or tostring(size) }
  end
  ui.brushSize = W.IconDropdownButton(g, {
    size = 32,
    columns = 3,
    tooltip = "draw.brush",
    tooltipText = "draw.brush.tip",
    items = sizes,
    get = function()
      return S.brush
    end,
    onPick = setBrush,
  })
  local box = newStack(g, { ui.brushShape, ui.brushSize }, 4)
  box:Relayout()
  g:Add(box)
  ui.qualityBtn = W.ToolButton(g, {
    glyph = "draw-soft",
    size = 32,
    chevron = true,
    tooltip = "draw.quality",
    tooltipText = "draw.quality.tip",
    enabled = hasDoc,
    selected = function()
      return Desktop.Layer.current ~= nil and Desktop.Layer.current.owner == ui.qualityBtn
    end,
    onClick = toggleQuality,
  })
  g:Add(ui.qualityBtn)
end

-- Shapes: three buttons and the fill style; collapsed into two dropdowns when
-- the ribbon is too wide for the window.
local function buildShapesGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.shapes" })
  local box = CreateFrame("Frame", nil, g)
  local grid = W.ToolGrid(box, {
    columns = 3,
    size = 32,
    items = {
      toolDef("line", "line"),
      toolDef("rect", "rectangle"),
      toolDef("ellipse", "ellipse"),
    },
  })
  ui.tools.line, ui.tools.rect, ui.tools.ellipse = grid.buttons[1], grid.buttons[2], grid.buttons[3]
  ui.shapeDrop = W.IconDropdownButton(box, {
    size = 32,
    columns = 3,
    tooltip = "draw.shapes",
    tooltipText = "draw.shapes.tip",
    items = {
      { value = "line", glyph = "line", key = "draw.tool.line", tooltipText = "draw.tool.line.tip" },
      { value = "rect", glyph = "rectangle", key = "draw.tool.rect", tooltipText = "draw.tool.rect.tip" },
      { value = "ellipse", glyph = "ellipse", key = "draw.tool.ellipse", tooltipText = "draw.tool.ellipse.tip" },
    },
    get = function()
      return S.lastShape
    end,
    onPick = setTool,
  })
  wrapDropdown(ui.shapeDrop, function()
    return SHAPE_TOOLS[S.tool] == true
  end, function() end)
  ui.fillDrop = W.IconDropdownButton(box, {
    size = 32,
    width = 190,
    tooltip = "draw.fillStyle",
    tooltipText = "draw.fillStyle.tip",
    items = {
      { value = "outline", glyph = "draw-fill-outline", key = "draw.fill.outline" },
      { value = "fill", glyph = "draw-fill-fill", key = "draw.fill.fill" },
      { value = "solid", glyph = "draw-fill-solid", key = "draw.fill.solid" },
    },
    get = function()
      return S.fillMode
    end,
    onPick = setFillMode,
  })
  function box:Relayout()
    local top = ui.compact and ui.shapeDrop or grid
    grid:SetShown(not ui.compact)
    ui.shapeDrop:SetShown(ui.compact == true)
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    ui.fillDrop:ClearAllPoints()
    ui.fillDrop:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
    box:SetSize(max(top:GetWidth(), ui.fillDrop:GetWidth()), top:GetHeight() + 4 + ui.fillDrop:GetHeight())
  end
  function box:Refresh()
    grid:Refresh()
    ui.shapeDrop:Refresh()
    ui.fillDrop:Refresh()
  end
  ui.boxes[#ui.boxes + 1] = box
  box:Relayout()
  g:Add(box)
end

-- Paint-like color circle: a ring and the color inside, both round through
-- the alpha mask the client ships for portraits.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function newCircle(parent, ringToken)
  local c = CreateFrame("Frame", nil, parent)
  c.ring = c:CreateTexture(nil, "BACKGROUND")
  c.ring:SetAllPoints()
  c.ring:SetTexture(CIRCLE_MASK)
  c.dot = c:CreateTexture(nil, "ARTWORK")
  c.dot:SetPoint("TOPLEFT", 2, -2)
  c.dot:SetPoint("BOTTOMRIGHT", -2, 2)
  c.dot:SetTexture(CIRCLE_MASK)
  ns.Bind(c, function()
    c.ring:SetVertexColor(Theme.rgb(ringToken))
  end)
  function c:SetColor(r, g, b)
    c.color = { r, g, b }
    c.dot:SetVertexColor(r, g, b, 1)
  end
  return c
end

-- The current color (front) over the background color (behind). One click
-- anywhere on the pair swaps them.
local function newColorPair(parent)
  local pair = CreateFrame("Button", nil, parent)
  ui.background = newCircle(pair, "accentDim")
  ui.primary = newCircle(pair, "accent2")
  ui.primary:SetFrameLevel(ui.background:GetFrameLevel() + 2)
  ns.Bind(pair, function()
    local size = scaled(56)
    pair:SetSize(size, size)
    ui.background:SetSize(size * 0.6, size * 0.6)
    ui.background:ClearAllPoints()
    ui.background:SetPoint("BOTTOMRIGHT", pair, "BOTTOMRIGHT", -2, 2)
    ui.primary:SetSize(size * 0.68, size * 0.68)
    ui.primary:ClearAllPoints()
    ui.primary:SetPoint("TOPLEFT", pair, "TOPLEFT", 2, -2)
  end)
  pair:SetScript(
    "OnClick",
    ns.Wrap("draw-color-pair", function()
      DE.SwapColors()
    end)
  )
  pair:SetScript("OnEnter", function()
    ns.ShowTooltip(pair, L["draw.color.pair"], L["draw.color.pair.tip"])
  end)
  pair:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(pair, function(self)
    self:Click()
  end)
  return pair
end

-- All colors of the drawing in a popup below the "More" button.
local function toggleMore(btn)
  local Layer = Desktop.Layer
  if Layer.current and Layer.current.owner == btn then
    Layer.close("api")
    return
  end
  local pop = ui.more
  if not pop then
    pop = Layer.newPopup("surface")
    pop.grid = W.ColorSwatchGrid(pop, {
      colors = {},
      columns = MORE_COLS,
      swatchSize = 16,
      gap = 2,
      get = currentColor,
      tooltipFor = swatchTip("moreMap"),
      onPick = function(_, index)
        swatchPick("moreMap")(nil, index)
        Layer.close("select")
      end,
    })
    pop.grid:SetPoint("TOPLEFT", pop, "TOPLEFT", 3, -3)
    ui.more = pop
  end
  local list, map = swatchList(D.MAX_PALETTE)
  ui.moreMap = map
  pop.grid:SetColors(list)
  pop:SetSize(pop.grid:GetWidth() + 6, pop.grid:GetHeight() + 6)
  Layer.place(pop, btn, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  pop:Show()
  Layer.open({
    frames = { pop },
    owner = btn,
    onClose = function()
      btn:Refresh()
    end,
  })
  btn:Refresh()
end

local function buildColorGroup(ribbon)
  local g = ribbon:AddGroup({ key = "draw.group.color" })
  g:Add(newColorPair(g))
  ui.palette = W.ColorSwatchGrid(g, {
    colors = {},
    columns = PALETTE_COLS,
    swatchSize = 16,
    gap = 2,
    get = currentColor,
    tooltipFor = swatchTip("paletteMap"),
    onPick = swatchPick("paletteMap"),
  })
  g:Add(ui.palette)
  ui.custom = W.ToolButton(g, {
    glyph = "draw-wheel",
    key = "draw.color.wheel",
    size = 32,
    width = 96,
    tooltip = "draw.color.wheel",
    tooltipText = "draw.color.wheel.tip",
    enabled = hasDoc,
    onClick = function()
      DE.PickColor()
    end,
  })
  ui.moreBtn = W.ToolButton(g, {
    glyph = "plus",
    key = "draw.color.more",
    size = 32,
    width = 96,
    chevron = true,
    tooltip = "draw.color.more",
    tooltipText = "draw.color.more.tip",
    enabled = function()
      return doc ~= nil and #D.userColors(doc.drawing) > PALETTE_VISIBLE
    end,
    selected = function()
      return Desktop.Layer.current ~= nil and Desktop.Layer.current.owner == ui.moreBtn
    end,
    onClick = toggleMore,
  })
  local box = newStack(g, { ui.custom, ui.moreBtn }, 4)
  box:Relayout()
  g:Add(box)
end

local function buildRibbon(f)
  local ribbon = W.Ribbon(f, { height = RIBBON_H })
  ribbon:SetPoint("TOPLEFT", ui.top, "BOTTOMLEFT", 0, 0)
  ribbon:SetPoint("TOPRIGHT", ui.top, "BOTTOMRIGHT", 0, 0)
  ribbon:SetClipsChildren(true)
  ui.ribbon = ribbon
  buildSelectionGroup(ribbon)
  buildImageGroup(ribbon)
  buildMapGroup(ribbon)
  buildToolsGroup(ribbon)
  buildBrushGroup(ribbon)
  buildShapesGroup(ribbon)
  buildColorGroup(ribbon)
  return ribbon
end

-- Brush size panel at the left edge of the stage.
local function buildPanel(stage)
  local panel = CreateFrame("Frame", nil, stage)
  panel:SetPoint("TOPLEFT", stage, "TOPLEFT", STAGE_PAD + 2, -STAGE_PAD)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "accentDim", 0.8)
  panel:EnableMouse(true)
  panel:SetScript("OnEnter", function()
    ns.ShowTooltip(panel, L["draw.brush"], L["draw.brush.tip"])
  end)
  panel:SetScript("OnLeave", ns.HideTooltip)
  local icon = IconDraw.new(panel, 24)
  icon:Draw("draw-brush-size")
  icon:SetPoint("TOP", panel, "TOP", 0, -8)
  ui.brushValue = W.Text(panel, { role = "micro", color = "accent2", justify = "CENTER" })
  ui.brushValue:SetPoint("TOP", icon, "BOTTOM", 0, -2)
  ui.brushValue:SetWidth(32)
  -- The slider walks the preset list by index (0.25 .. 9 is not a uniform scale).
  ui.brush = W.VSlider(panel, {
    min = 1,
    max = #D.BRUSH_SIZES,
    step = 1,
    height = 140,
    icon = "plus",
    iconBottom = "minus",
    iconTip = "draw.brush.bigger",
    iconBottomTip = "draw.brush.smaller",
    tooltip = "draw.brush",
    get = brushIndex,
    set = function(index)
      setBrush(D.BRUSH_SIZES[U.clamp(floor(index + 0.5), 1, #D.BRUSH_SIZES)])
    end,
  })
  ui.brush:SetPoint("TOP", ui.brushValue, "BOTTOM", 0, -4)
  ui.panel = panel
end

local function buildStatus(f)
  local bar = W.StatusBar(f, {
    height = STATUS_H,
    segments = {
      { id = "pos", width = 64 },
      { id = "sel", width = 126, priority = 4 },
      { id = "size", width = 96, priority = 5 },
      { id = "bytes", fit = true, priority = 2 },
      { id = "share", fit = true, priority = 3 },
      { id = "state", width = 124, priority = 6 },
      { id = "load", fit = true, priority = 8 },
      { id = "hint", minWidth = 80, priority = 7, spacer = true },
      {
        id = "fit",
        type = "button",
        glyph = "fit",
        tooltip = "draw.fit",
        tooltipText = "draw.fit.tip",
        onClick = function()
          DE.Fit()
        end,
      },
      {
        id = "zoom",
        type = "slider",
        min = ZOOM_MIN * 100,
        max = ZOOM_MAX * 100,
        step = 100,
        value = S.zoom * 100,
        width = 210,
        onChange = function(v)
          setZoom(v / 100)
        end,
      },
    },
  })
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 1)
  -- The readout "1400 %" must never be cut off (the shared slider keeps it narrower).
  local zoom = bar.byId.zoom.slider
  ns.Bind(zoom, function()
    zoom.value:SetWidth(scaled(64))
  end)
  -- Size and chat verdict explain themselves in a tooltip.
  for _, id in ipairs({ "bytes", "share" }) do
    local seg = bar.byId[id]
    seg:EnableMouse(true)
    seg:SetScript("OnEnter", function(self)
      if S.sizeInfo then
        ns.ShowTooltip(self, L["drawlink.tip.title"], ns.DrawingLink.ShareTip(S.sizeInfo))
      end
    end)
    seg:SetScript("OnLeave", ns.HideTooltip)
  end
  -- The object count explains the display budget in a tooltip.
  local load = bar.byId.load
  load:EnableMouse(true)
  load:SetScript("OnEnter", function(self)
    local B, stats = V.BUDGET, view and view:Stats()
    if not stats then
      return
    end
    ns.ShowTooltip(
      self,
      L["draw.load.title"],
      fmt(
        "draw.load.tip",
        kilo(stats.cap),
        kilo(B.global),
        tostring(B.msPer1000),
        floor(stats.cap / 1000 * B.msPer1000 + 0.5),
        L["draw.load.stage." .. stats.stage]
      )
    )
  end)
  load:SetScript("OnLeave", ns.HideTooltip)
  return bar
end

local function create()
  local f = CreateFrame("Frame", "ForeverGuidesDrawingEditor", UIParent)
  frame = f
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
  -- Fully opaque: the main window and its text must not show through.
  W.Fill(f, "bg", 1)
  local shell = ns.WindowShell.Attach(f, { titleHeight = HEAD_H, shadow = true })
  local bar = shell.titleBar
  ui.titleBar = bar
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  bar:SetScript(
    "OnDragStop",
    ns.Wrap("draw-move", function()
      f:StopMovingOrSizing()
      savePosition()
    end)
  )
  local close = W.Action(bar, { icon = "close", size = 18, tooltip = "common.close" })
  close:SetPoint("RIGHT", -3, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("draw-close", function()
      DE.Close()
    end)
  )
  ui.closeBtn = close
  ui.title = shell.titleText
  ui.title:ClearAllPoints()
  ui.title:SetPoint("LEFT", 8, 0)
  ui.title:SetPoint("RIGHT", close, "LEFT", -4, 0)

  buildTop(f)
  buildRibbon(f)
  ui.status = buildStatus(f)

  -- Stage: dark surround with the brush panel and the canvas. Viewport
  -- (mouse target) > holder (scroll child, at least the viewport size so a
  -- small drawing sits in the middle) > bordered canvas.
  ui.stage = CreateFrame("Frame", nil, f)
  W.Fill(ui.stage, "bg", 1)
  buildPanel(ui.stage)
  local scroll = CreateFrame("ScrollFrame", nil, ui.stage)
  ui.scroll = scroll
  scroll:SetClipsChildren(true)
  W.Fill(scroll, "surface", 1)
  ui.holder = CreateFrame("Frame", nil, scroll)
  ui.holder:SetSize(1, 1)
  scroll:SetScrollChild(ui.holder)
  ui.canvas = CreateFrame("Frame", nil, ui.holder)
  ui.canvas:SetPoint("CENTER")
  W.Border(ui.canvas, "accent2", 0.7, 1)
  view = V.New(ui.canvas, { scale = S.zoom, kind = "editor" })
  view.frame:SetPoint("CENTER")
  ui.view = view
  buildHandles()
  buildPreview()
  ui.vbar = W.Scrollbar(scroll, function(frac)
    local _, vh = viewportSize()
    scroll:SetVerticalScroll(max(0, ui.holder:GetHeight() - vh) * frac)
    clampScroll()
  end)
  ui.hbar = scrollbarH(scroll, function(frac)
    local vw = viewportSize()
    scroll:SetHorizontalScroll(max(0, ui.holder:GetWidth() - vw) * frac)
    clampScroll()
  end)
  scroll:EnableMouse(true)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseDown", ns.Wrap("draw-mouse", onMouseDown))
  scroll:SetScript("OnMouseUp", ns.Wrap("draw-mouse", onMouseUp))
  scroll:SetScript("OnMouseWheel", ns.Wrap("draw-wheel", onWheel))
  -- Own frame for the polling: it only runs while the window is shown.
  ui.ticker = CreateFrame("Frame", nil, f)
  ui.ticker:SetScript("OnUpdate", ns.Wrap("draw-update", onUpdate))

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
    ns.Wrap("draw-size", function()
      f:StopMovingOrSizing()
      ns.WindowShell.FitToScreen(f)
      saveSize()
      savePosition()
      layout()
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["draw.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)

  f:SetScript("OnSizeChanged", ns.Wrap("draw-layout", layout))
  f:SetScript(
    "OnShow",
    ns.Wrap("draw-show", function()
      frameDb().shown = doc ~= nil and doc.id ~= nil
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("draw-hide", function()
      Desktop.Layer.close("hidden")
      ns.DrawingMapPicker.Close()
      cancelStroke()
      frameDb().shown = false
      doc = nil
      S.sel, S.hover, S.note = nil, nil, nil
      S.sizePending, S.bytes, S.sizeInfo = false, nil, nil
      view:Clear()
    end)
  )
  ui.ready = true
  setupKeyboard()
  f:Hide()
  return f
end

-- Opening ------------------------------------------------------------------------------------

local function ensureWindow()
  if not frame then
    loadSettings()
    create()
  end
  applyScale()
  if not frame:IsShown() then
    place()
  end
end

-- Shows `drawing` (edited in place) in the window. id = nil: not stored yet.
local function show(drawing, id, name)
  ensureWindow()
  local ed, why = D.newEditor(drawing)
  if not ed then
    ns.Notify(L["draw.msg.loadFailed"] .. " (" .. tostring(why) .. ")", "error")
    return false
  end
  cancelStroke()
  ns.DrawingMapPicker.Close()
  view:Clear()
  local clean = DR.cleanName(name)
  doc = {
    id = id,
    name = clean,
    savedName = id and clean or nil,
    savedMap = D.cleanMap(drawing.map),
    drawing = drawing,
    ed = ed,
  }
  S.sel, S.hover, S.note, S.stroke, S.drag, S.resize = nil, nil, nil, nil, nil, nil
  S.sizePending, S.sizeWait, S.bytes, S.sizeInfo = true, 0, nil, nil
  view:SetDrawing(drawing)
  view:SetGrid(S.grid)
  frame:Show()
  ui.name.edit:SetText(clean)
  ui.paletteDoc = nil
  layout()
  fitZoom()
  ui.scroll:SetHorizontalScroll(0)
  ui.scroll:SetVerticalScroll(0)
  layout()
  refreshUI()
  frameDb().shown = id ~= nil
  if id then
    frameDb().id = id
  end
  return true
end

-- Opens drawing `id` for editing. A window with unsaved work asks first.
function DE.Open(id)
  local item = DR.get(id)
  if not item then
    return false
  end
  DR.setLastOpened(id)
  if doc and doc.id == id and frame:IsShown() then
    frame:Raise()
    return true
  end
  local function go()
    local drawing, why = DR.load(id)
    if not drawing then
      ns.Notify(L["draw.msg.loadFailed"] .. " (" .. tostring(why) .. ")", "error")
      return false
    end
    return show(drawing, id, item.name)
  end
  if DE.IsOpen() and isDirty() then
    ns.Dialogs.Confirm("draw.discard.title", "draw.discard.text", go)
    return true
  end
  return go()
end

-- Opens a copy as a new, not yet saved drawing (saving creates the entry).
function DE.OpenCopy(drawing, name)
  local copy = D.clone(drawing)
  if DE.IsOpen() and isDirty() then
    ns.Dialogs.Confirm("draw.discard.title", "draw.discard.text", function()
      show(copy, nil, name)
    end)
    return true
  end
  return show(copy, nil, name)
end

-- Best match for a typed name: exact, then start of the name, then anywhere.
function DE.Find(query)
  query = U.trim(query):lower()
  if query == "" then
    return nil
  end
  local list = DR.list()
  for pass = 1, 3 do
    for _, item in ipairs(list) do
      local name = item.name:lower()
      if
        (pass == 1 and name == query)
        or (pass == 2 and name:sub(1, #query) == query)
        or (pass == 3 and name:find(query, 1, true))
      then
        return item
      end
    end
  end
end

-- /fg draw [name]
function DE.Slash(rest)
  rest = U.trim(rest or "")
  if rest == "" then
    ns.Main.Show("drawings")
    return
  end
  local item = DE.Find(rest)
  if not item then
    ns.Notify(fmt("draw.slash.none", rest), "info")
    return
  end
  DE.Open(item.id)
end

-- The editor follows changes made on the page: a deleted drawing becomes an
-- unsaved one (the work is kept), a rename shows up in the name field.
ns.On("FG_DRAWINGS_CHANGED", function(_, kind, id)
  if not (doc and id and doc.id == id) then
    return
  end
  if kind == "delete" then
    doc.id, doc.savedName = nil, nil
    frameDb().shown = false
  elseif kind == "rename" then
    local item = DR.get(id)
    if item and doc.savedName == DR.cleanName(doc.name) then
      doc.name, doc.savedName = item.name, item.name
    end
  end
  refreshUI()
end)

ns.On("FG_UI_REFRESHED", function()
  if frame and frame:IsShown() then
    applyScale()
    place()
    layout()
    refreshUI()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition()
    saveSize()
    saveSettings()
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and ns.db.frames then
    local db = frameDb()
    if db.shown == true and type(db.id) == "string" and DR.get(db.id) then
      DE.Open(db.id)
    end
  end
end)
