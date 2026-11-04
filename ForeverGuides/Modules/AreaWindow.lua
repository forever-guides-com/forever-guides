-- The free areas (ns.Areas): any number of windows, each one a canvas layout of kind "area" drawn by CanvasRender
-- with the element types of the cursor ring (CursorElements, host "area"). Every area owns its frame and its
-- state (a table made by Areas.New); the module only keeps the register of the areas, the event frame for the
-- screen size, the subscription to the shared game state (Modules/LoadState.lua) that the "when active"
-- conditions read, and a menu that every area opens. Data and rules are in
-- Modules/AreaLogic.lua, the settings card in Modules/AreaSettings.lua.
--
-- Storage: settings.areas.items[id] (account wide: name, layoutId, rules), the layout each one shows in
-- settings.areas.layouts (Modules/AreaLayouts.lua, one layout per window, named like it) and
-- ForeverGuidesCharDB.areas[id] (per character: x, y, scale, shown, locked), see AreaLogic. An area that is not
-- wanted has no elements and no event registration (CanvasRender.Clear releases them). The rules never hide or show a frame: they set the
-- opacity and the mouse of the area, so a change of state in combat touches nothing protected. Nothing here
-- attaches to a frame of the game.
local _, ns = ...
local W, L = ns.W, ns.L
local AL, AY, CL, CR, E, Store, LS, CS =
  ns.AreaLogic,
  ns.AreaLayouts,
  ns.CanvasLogic,
  ns.CanvasRender,
  ns.CursorElements,
  ns.Store,
  ns.LoadState,
  ns.CharScopeLogic

local Areas = {}
ns.Areas = Areas

local GRIP, PIN_SIZE = 16, 18
local GEAR_SIZE, GEAR_DELAY = 18, 0.3
-- The menu is as wide as its widest entry needs; MENU_W and MENU_ROW are the minimum.
local MENU_W, MENU_ROW = 150, 22
-- Only the screen size is watched here; combat, target, mount and the rest come from LoadState.
local EVENTS = { "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }
Areas.EVENTS = EVENTS

ns.AddLocale(
  "enUS",
  ns.AreaTerms.Apply("enUS", {
    ["areas.win.pin"] = "Lock",
    ["areas.win.pinTip"] = "Fixes the position and hides the scale grip.",
    ["areas.win.edit"] = "Edit layout",
    ["areas.win.editTip"] = "Opens the layout editor for this window.",
    ["areas.win.grip"] = "Scale",
    ["areas.win.gripTip"] = "Drag to scale the window and all its elements. {key:windowScale} changes the size as well.",
    ["areas.win.hint"] = "Dragging moves the window, the gear opens the menu.",
    ["areas.win.hintLocked"] = "Pinned: the mouse and the camera pass through the window. Hold {mod:windowGear} to show the gear.",
    ["areas.win.menu"] = "Window menu",
    ["areas.win.menuTip"] = "Edit the layout, lock, hide or open the settings.",
    ["areas.menu.edit"] = "Edit layout",
    ["areas.menu.lock"] = "Lock",
    ["areas.menu.unlock"] = "Unlock",
    ["areas.menu.hide"] = "Hide window",
    ["areas.menu.settings"] = "Settings",
    ["areas.edit.title"] = "Window: %s",
    ["areas.edit.head"] = "Windows",
    ["areas.edit.deleteAsk"] = "Delete this window and its layout for good? Export it first if you want to keep it.",
    ["areas.edit.missing"] = "The layout editor is not available.",
    ["areas.delete.title"] = "Delete window",
    ["areas.delete.text"] = "The window and its layout are deleted for good, on all characters.",
    ["areas.copy.title"] = "Copy content",
    ["areas.copy.text"] = "The elements of the target window are replaced by those of the source window. This cannot be undone.",
    ["areas.lib.badName"] = "Enter a name.",
    ["areas.lib.dup"] = "Another window already has this name.",
    ["areas.lib.limit"] = "There are too many layouts. Delete a window first.",
    ["areas.lib.missing"] = "This window does not exist any more.",
    ["areas.slash.created"] = "Window created: %s. Unlocked windows can be moved by dragging, /fg {cmd} edit %s opens the editor.",
    ["areas.slash.limit"] = "There are too many windows. Delete one first.",
    ["areas.slash.deleted"] = "Window deleted: %s.",
    ["areas.slash.none"] = "No window called %s.",
    ["areas.slash.pick"] = "Which window? Give its name: /fg {cmd} %s <name>",
    ["areas.slash.empty"] = "No windows yet. /fg {cmd} new [name] creates one.",
    ["areas.slash.line"] = "%s: %s, %s",
    ["areas.slash.shown"] = "shown",
    ["areas.slash.hidden"] = "hidden",
    ["areas.slash.locked"] = "locked",
    ["areas.slash.unlocked"] = "unlocked",
    ["areas.slash.didShow"] = "Window shown: %s.",
    ["areas.slash.didHide"] = "Window hidden: %s.",
    ["areas.slash.didLock"] = "Window locked: %s.",
    ["areas.slash.nameHint"] = "<name>",
    ["areas.slash.unlockEditor"] = "Unlock in the layout editor (/fg {cmd} edit %s) or in the gear menu of the window.",
    ["areas.unlock.editor"] = "A pinned window can be unlocked in the layout editor or in the gear menu of the window.",
    ["areas.host.head"] = "Window",
    ["areas.host.shown"] = "Visible",
    ["areas.host.shownTip"] = "Shows or hides this window on this character. The card of the window on the page shows the same switch.",
    ["areas.host.locked"] = "Pinned (locked)",
    ["areas.host.lockedTip"] = "A pinned window cannot be dragged and shows no scale grip. The mouse and the camera pass through it, hold {mod:windowGear} to show the gear. Unlock it here in the editor or in the gear menu of the window.",
    ["areas.host.x"] = "X",
    ["areas.host.xTip"] = "Distance of the middle of the window from the middle of the screen in units, to the right is positive.",
    ["areas.host.y"] = "Y",
    ["areas.host.yTip"] = "Distance of the middle of the window from the middle of the screen in units, upwards is positive.",
    ["areas.host.scale"] = "Scale",
    ["areas.host.scaleTip"] = "Scale of the whole window on this character, from 0.5 to 3. The middle of the window stays where it is.",
    ["areas.host.strata"] = "Layer",
    ["areas.host.strataTip"] = "Which windows this one covers: Background lies behind everything, Medium (default) is level with the game's panels, High lies over them. It never goes above the game's dialogs. Reset position leaves the layer alone.",
    ["areas.host.strata.BACKGROUND"] = "Background",
    ["areas.host.strata.LOW"] = "Low",
    ["areas.host.strata.MEDIUM"] = "Medium",
    ["areas.host.strata.HIGH"] = "High",
    ["areas.host.reset"] = "Reset position",
    ["areas.host.resetTip"] = "Puts the middle of the window into the middle of the screen. The scale stays.",
    ["areas.host.unlockFirst"] = "Unlock first: untick Pinned. X, Y, scale, layer and reset are fixed while the window is pinned.",
    ["areas.slash.didDuplicate"] = "Window duplicated: %s (copy of %s).",
    ["areas.slash.didCopy"] = "%s now shows the content of %s.",
    ["areas.slash.needPair"] = "Give two names: /fg {cmd} %s <from> <to>, in quotes when a name has blanks.",
    ["areas.slash.samePair"] = "Give two different windows.",
    ["areas.slash.gone"] = "This command does not exist any more. A layout is now a window, see /fg {cmd} list.",
    ["areas.slash.usage"] = "/fg {cmd} [new [name] | edit <name> | duplicate <name> | show [name] | hide [name] | lock [name] | unlock [name] | delete <name> | list | copy <from> <to>]",
  })
)
ns.AddLocale(
  "deDE",
  ns.AreaTerms.Apply("deDE", {
    ["areas.win.pin"] = "Sperren",
    ["areas.win.pinTip"] = "Fixiert die Position und blendet den Skalierungsgriff aus.",
    ["areas.win.edit"] = "Layout bearbeiten",
    ["areas.win.editTip"] = "Öffnet den Layout-Editor für dieses Fenster.",
    ["areas.win.grip"] = "Skalieren",
    ["areas.win.gripTip"] = "Ziehen skaliert das Fenster samt allen Elementen. {key:windowScale} ändert die Größe ebenfalls.",
    ["areas.win.hint"] = "Ziehen verschiebt das Fenster, das Zahnrad öffnet das Menü.",
    ["areas.win.hintLocked"] = "Angepinnt: Maus und Kamera gehen durch das Fenster. Halte {mod:windowGear}, dann erscheint das Zahnrad.",
    ["areas.win.menu"] = "Fenster-Menü",
    ["areas.win.menuTip"] = "Layout bearbeiten, sperren, verstecken oder die Einstellungen öffnen.",
    ["areas.menu.edit"] = "Layout bearbeiten",
    ["areas.menu.lock"] = "Sperren",
    ["areas.menu.unlock"] = "Entsperren",
    ["areas.menu.hide"] = "Fenster verstecken",
    ["areas.menu.settings"] = "Einstellungen",
    ["areas.edit.title"] = "Fenster: %s",
    ["areas.edit.head"] = "Fenster",
    ["areas.edit.deleteAsk"] = "Dieses Fenster und sein Layout endgültig löschen? Exportiere es vorher, wenn du es behalten willst.",
    ["areas.edit.missing"] = "Der Layout-Editor ist nicht verfügbar.",
    ["areas.delete.title"] = "Fenster löschen",
    ["areas.delete.text"] = "Das Fenster und sein Layout werden endgültig gelöscht, für alle Charaktere.",
    ["areas.copy.title"] = "Inhalt kopieren",
    ["areas.copy.text"] = "Die Elemente des Zielfensters werden durch die des Quellfensters ersetzt. Das lässt sich nicht rückgängig machen.",
    ["areas.lib.badName"] = "Gib einen Namen ein.",
    ["areas.lib.dup"] = "Ein anderes Fenster hat diesen Namen schon.",
    ["areas.lib.limit"] = "Es gibt zu viele Layouts. Lösche zuerst ein Fenster.",
    ["areas.lib.missing"] = "Dieses Fenster existiert nicht mehr.",
    ["areas.slash.created"] = "Fenster angelegt: %s. Entsperrte Fenster lassen sich per Ziehen verschieben, /fg {cmd} bearbeiten %s öffnet den Editor.",
    ["areas.slash.limit"] = "Es gibt zu viele Fenster. Lösche zuerst eines.",
    ["areas.slash.deleted"] = "Fenster gelöscht: %s.",
    ["areas.slash.none"] = "Es gibt kein Fenster namens %s.",
    ["areas.slash.pick"] = "Welches Fenster? Nenne den Namen: /fg {cmd} %s <Name>",
    ["areas.slash.empty"] = "Noch keine Fenster. /fg {cmd} neu [Name] legt eines an.",
    ["areas.slash.line"] = "%s: %s, %s",
    ["areas.slash.shown"] = "sichtbar",
    ["areas.slash.hidden"] = "versteckt",
    ["areas.slash.locked"] = "gesperrt",
    ["areas.slash.unlocked"] = "entsperrt",
    ["areas.slash.didShow"] = "Fenster sichtbar: %s.",
    ["areas.slash.didHide"] = "Fenster versteckt: %s.",
    ["areas.slash.didLock"] = "Fenster gesperrt: %s.",
    ["areas.slash.nameHint"] = "<Name>",
    ["areas.slash.unlockEditor"] = "Entsperren geht im Layout-Editor (/fg {cmd} bearbeiten %s) oder im Zahnrad-Menü des Fensters.",
    ["areas.unlock.editor"] = "Ein angepinntes Fenster lässt sich im Layout-Editor oder im Zahnrad-Menü des Fensters entsperren.",
    ["areas.host.head"] = "Fenster",
    ["areas.host.shown"] = "Sichtbar",
    ["areas.host.shownTip"] = "Zeigt oder versteckt dieses Fenster auf diesem Charakter. Die Karte des Fensters auf der Seite zeigt denselben Schalter.",
    ["areas.host.locked"] = "Angepinnt (gesperrt)",
    ["areas.host.lockedTip"] = "Ein angepinntes Fenster lässt sich nicht ziehen und zeigt keinen Skalierungsgriff. Maus und Kamera gehen durch das Fenster, mit {mod:windowGear} erscheint das Zahnrad. Entsperren geht hier im Editor oder im Zahnrad-Menü des Fensters.",
    ["areas.host.x"] = "X",
    ["areas.host.xTip"] = "Abstand der Fenstermitte von der Bildschirmmitte in Einheiten, nach rechts ist positiv.",
    ["areas.host.y"] = "Y",
    ["areas.host.yTip"] = "Abstand der Fenstermitte von der Bildschirmmitte in Einheiten, nach oben ist positiv.",
    ["areas.host.scale"] = "Skalierung",
    ["areas.host.scaleTip"] = "Skalierung des ganzen Fensters auf diesem Charakter, von 0,5 bis 3. Die Mitte des Fensters bleibt, wo sie ist.",
    ["areas.host.strata"] = "Ebene",
    ["areas.host.strataTip"] = "Welche Fenster dieses Fenster überdeckt: Hintergrund liegt hinter allem, Mittel (Standard) liegt auf einer Höhe mit den Fenstern des Spiels, Hoch liegt darüber. Über den Dialogen des Spiels liegt es nie. Position zurücksetzen lässt die Ebene unverändert.",
    ["areas.host.strata.BACKGROUND"] = "Hintergrund",
    ["areas.host.strata.LOW"] = "Niedrig",
    ["areas.host.strata.MEDIUM"] = "Mittel",
    ["areas.host.strata.HIGH"] = "Hoch",
    ["areas.host.reset"] = "Position zurücksetzen",
    ["areas.host.resetTip"] = "Setzt die Mitte des Fensters in die Mitte des Bildschirms. Die Skalierung bleibt.",
    ["areas.host.unlockFirst"] = "Zuerst entsperren: Haken bei Angepinnt entfernen. X, Y, Skalierung, Ebene und Zurücksetzen sind gesperrt, solange das Fenster angepinnt ist.",
    ["areas.slash.didDuplicate"] = "Fenster dupliziert: %s (Kopie von %s).",
    ["areas.slash.didCopy"] = "%s zeigt jetzt den Inhalt von %s.",
    ["areas.slash.needPair"] = "Nenne zwei Namen: /fg {cmd} %s <von> <nach>, in Anführungszeichen, wenn ein Name Leerzeichen hat.",
    ["areas.slash.samePair"] = "Nenne zwei verschiedene Fenster.",
    ["areas.slash.gone"] = "Diesen Befehl gibt es nicht mehr. Ein Layout ist jetzt ein Fenster, siehe /fg {cmd} liste.",
    ["areas.slash.usage"] = "/fg {cmd} [neu [Name] | bearbeiten <Name> | duplizieren <Name> | zeigen [Name] | verstecken [Name] | sperren [Name] | entsperren [Name] | löschen <Name> | liste | kopieren <von> <nach>]",
  })
)

-- The areas that exist, by id. Each one is the table Areas.New made.
local instances = {}
-- Frames of deleted areas: the client cannot free a frame, so the next area takes one of them.
local spare = {}
local watcher, modifiers
local menu, menuOwner
-- True while the key combination "windowGear" (Keys registry) is held; only read while a pinned window exists.
local chordDown = false

-- Data -----------------------------------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The stored areas of the account; an empty table before the database is there.
local function items()
  local settings = ns.db and ns.db.settings
  local node = type(settings) == "table" and settings.areas
  return type(node) == "table" and type(node.items) == "table" and node.items or {}
end

-- The placement table of one area of this character, created when asked for (position and scale are written
-- straight into it: a drag must not raise an event at every step).
local function charEntry(id)
  local char = ns.charDB
  if type(char) ~= "table" then
    return {}
  end
  if type(char.areas) ~= "table" then
    char.areas = {}
  end
  if type(char.areas[id]) ~= "table" then
    char.areas[id] = {}
  end
  return char.areas[id]
end

local function placementOf(a)
  return AL.Placement(charEntry(a.id))
end

-- The windows and layouts of the account: one set of functions bound to the settings, every change goes through
-- Store.
local library
local function lib()
  library = library
    or AY.New({
      get = function()
        local settings = ns.db and ns.db.settings
        return settings and settings.areas
      end,
      put = function(path, value)
        Store.set("settings.areas." .. path, value)
      end,
    })
  return library
end
Areas.Library = lib

local function layoutOf(a)
  return lib().Layout(a.id)
end

local function nameOf(a)
  local item = items()[a.id]
  return AL.CleanName(item and item.name, a.id)
end

-- Placement ------------------------------------------------------------------------------------------------

local function indexOf(id)
  for i, entry in ipairs(AL.List(items())) do
    if entry.id == id then
      return i
    end
  end
  return 1
end

local function place(a)
  local f, p = a.frame, placementOf(a)
  f:ClearAllPoints()
  if p.x and p.y then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / p.scale, p.y / p.scale)
  else
    local dx, dy = AL.DefaultOffset(indexOf(a.id))
    f:SetPoint("CENTER", UIParent, "CENTER", dx / p.scale, dy / p.scale)
  end
  ns.WindowShell.FitToScreen(f)
end

-- Tells the editor that where a window sits changed, so its section shows the new values.
local function hostChanged()
  local editor = ns.CanvasEditor
  if editor and editor.RefreshHost then
    editor.RefreshHost()
  end
end

local function savePosition(a)
  local left, top = a.frame:GetLeft(), a.frame:GetTop()
  if left and top then
    local s, db = a.frame:GetScale(), charEntry(a.id)
    db.x, db.y = left * s, top * s
  end
end

-- The gear is a child of the window; the inverse scale keeps it at its own size on screen whatever the window's.
local function setScale(a, scale)
  local f = a.frame
  f:SetScale(scale)
  f.gear:SetScale(scale > 0 and 1 / scale or 1)
end

-- Scale: the top left corner stays where it is.
local function applyScale(a, scale)
  charEntry(a.id).scale = AL.RoundScale(scale)
  setScale(a, charEntry(a.id).scale)
  place(a)
  hostChanged()
end

local function changeScale(a, delta)
  savePosition(a)
  applyScale(a, placementOf(a).scale + delta * 0.1)
end

-- Scale by pulling the grip: the cursor in the space of UIParent against the saved top left corner.
local function dragScale(a)
  local db, canvas = charEntry(a.id), layoutOf(a).canvas
  local cx, cy = GetCursorPosition()
  local ui = UIParent:GetEffectiveScale()
  if not (finite(cx) and finite(cy) and finite(ui) and ui > 0 and finite(db.x) and finite(db.y)) then
    return
  end
  applyScale(a, AL.ScaleFor(cx / ui - db.x, db.y - cy / ui, canvas.w, canvas.h))
end

-- Drawing and rules ----------------------------------------------------------------------------------------

local function repaint(a)
  local f = a.frame
  if not (f and f:IsShown()) then
    return
  end
  local layout = layoutOf(a)
  CR.Draw(f.canvas, layout, E.Types("area"), { host = "area", editor = false, reduceMotion = ns.Theme.reduceMotion() })
  f:SetSize(layout.canvas.w, layout.canvas.h)
end

-- The pin button, the edit button and the grip show on mouse-over (and while scaling) and only while the area
-- is unlocked. They stay shown and turn transparent, so the mouse can pass from the area onto them.
local function setChrome(a, on)
  local f = a.frame
  local alpha = (on or a.scaling) and 1 or 0
  f.pin:SetAlpha(alpha)
  f.edit:SetAlpha(alpha)
  f.grip:SetAlpha(alpha)
end

-- The gear belongs to the window and shows while the mouse is on the window or one of its parts (gear, buttons,
-- grip), while its menu is open and while it has the keyboard focus. It stays shown and turns transparent otherwise, so keys reach it.
local menuOpen

local function updateGear(a)
  local f = a.frame
  if not f then
    return
  end
  local on = a.overHit or a.overPart or a.gearFocus or (menuOpen() and menuOwner == f.gear)
  f.gear:SetAlpha(on and 1 or 0)
end

-- Leaving the window gets a short grace time, so the mouse can travel onto the gear.
local function updateGearLater(a)
  a.gearToken = (a.gearToken or 0) + 1
  local token = a.gearToken
  C_Timer.After(GEAR_DELAY, function()
    if a.gearToken == token then
      updateGear(a)
    end
  end)
end

-- Which frames of a window take the mouse. A pinned window is click-through: the mouse, the camera and the
-- target pick pass over it. The chord (or an open menu) gives it the mouse for the gear; dragging and scaling
-- stay refused by their own scripts while it is pinned. Own frames only, so this is allowed in combat.
local function applyMouse(a)
  local f = a.frame
  local p, item = placementOf(a), items()[a.id]
  if not (f and item and p.shown) then
    return
  end
  local visible = AL.Visible(item, LS.Get())
  local mouse = visible and (not p.locked or chordDown or a.menuHeld == true)
  local chrome = visible and not p.locked
  a.live = visible
  f.hit:EnableMouse(mouse)
  f.hit:EnableMouseWheel(chrome)
  f.gear:EnableMouse(mouse)
  f.pin:EnableMouse(chrome)
  f.edit:EnableMouse(chrome)
  f.grip:EnableMouse(chrome)
  if not mouse then
    a.overHit, a.overPart = false, false
  end
  if not visible then
    a.gearFocus = false
  end
end

-- A failing modifier function counts as not held.
local function chordHeld()
  local ok, down = pcall(ns.Keys.Matches, "windowGear")
  return ok and down == true
end

-- The event frame lives while a pinned window is shown: no polling, only the change of a modifier key.
local function syncModifiers()
  local any = false
  for _, a in pairs(instances) do
    if a.frame and a.frame:IsShown() and placementOf(a).locked then
      any = true
      break
    end
  end
  if any == (modifiers ~= nil and modifiers:IsEventRegistered("MODIFIER_STATE_CHANGED")) then
    return
  end
  if any then
    if not modifiers then
      modifiers = CreateFrame("Frame")
      modifiers:SetScript(
        "OnEvent",
        ns.Wrap("areas-chord", function()
          local down = chordHeld()
          if down ~= chordDown then
            chordDown = down
            for _, a in pairs(instances) do
              applyMouse(a)
            end
          end
        end)
      )
    end
    pcall(modifiers.RegisterEvent, modifiers, "MODIFIER_STATE_CHANGED")
    chordDown = chordHeld()
    for _, a in pairs(instances) do
      applyMouse(a)
    end
  else
    modifiers:UnregisterEvent("MODIFIER_STATE_CHANGED")
    chordDown = false
  end
end

-- The wish of the player and the rules: a frame that is not wanted leaves the picture (its elements and
-- event registrations go), a wanted one is drawn when it appears. The rules only set the opacity and the
-- mouse of the area, the lock the movability, the mouse and the chrome.
local function applyRules(a)
  local f = a.frame
  if not f then
    return
  end
  local p, item = placementOf(a), items()[a.id]
  if not (item and p.shown) then
    if f:IsShown() then
      CR.Clear(f.canvas)
      f:Hide()
    end
    syncModifiers()
    return
  end
  if not f:IsShown() then
    f:Show()
    repaint(a)
  end
  local visible = AL.Visible(item, LS.Get())
  f:SetAlpha(visible and 1 or 0)
  applyMouse(a)
  updateGear(a)
  f:SetMovable(not p.locked)
  local chrome = visible and not p.locked
  f.pin:SetShown(chrome)
  f.edit:SetShown(chrome)
  f.grip:SetShown(chrome)
  setChrome(a, false)
  syncModifiers()
end

-- Scale and position as well; an area that is being dragged keeps the place the drag gives it.
local function apply(a)
  local f = a.frame
  if not f or a.moving then
    return
  end
  setScale(a, placementOf(a).scale)
  f:SetFrameStrata(placementOf(a).strata)
  place(a)
  applyRules(a)
end

-- Everything a change of the layout, the name or the rules can reach.
local function refresh(a)
  if not a.frame then
    return
  end
  repaint(a)
  apply(a)
end

-- Menu -----------------------------------------------------------------------------------------------------

function menuOpen()
  local layer = ns.Desktop.Layer
  return menu ~= nil and layer.current ~= nil and layer.current.owner == menuOwner and menu:IsShown()
end

local function closeMenu(a)
  if menuOpen() and menuOwner == (a and a.frame.gear or menuOwner) then
    ns.Desktop.Layer.close("api")
  end
end

local function focusRow(step)
  local rows, index = menu.shown, 0
  for i, row in ipairs(rows) do
    if ns.Focus.current == row then
      index = i
    end
  end
  if #rows == 0 then
    return
  end
  index = index == 0 and (step > 0 and 1 or #rows) or (index - 1 + step) % #rows + 1
  ns.Focus.set(rows[index])
end

local function row(i)
  local r = menu.rows[i]
  if not r then
    r = W.Action(menu, {
      text = " ",
      icon = "pencil",
      variant = "ghost",
      width = MENU_W,
      height = MENU_ROW,
      wrap = "button",
      onClick = function()
        local run = r.run
        ns.Desktop.Layer.close("select")
        if run then
          run()
        end
      end,
    })
    r.label:SetJustifyH("LEFT")
    menu.rows[i] = r
  end
  return r
end

local function fill(entries)
  -- A false entry is a row that does not apply now.
  local list = {}
  for _, item in ipairs(entries) do
    list[#list + 1] = item or nil
  end
  menu.shown = {}
  -- Width and height follow the text (font size setting, language) so no row is cut off.
  local width, height = MENU_W, MENU_ROW
  for i, item in ipairs(list) do
    local r = row(i)
    W.SetText(r.label, item.key)
    r:SetIcon(item.icon)
    r.run = item.run
    width = math.max(width, r:FullWidth())
    height = math.max(height, math.ceil(r.label:GetStringHeight()) + 8)
    menu.shown[i] = r
  end
  for i, r in ipairs(menu.shown) do
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * height)
    r:SetSize(width, height)
    r:Show()
  end
  for i = #list + 1, #menu.rows do
    menu.rows[i]:Hide()
  end
  menu:SetSize(width + 4, #list * height + 4)
end

local function buildMenu()
  local p = ns.Desktop.Layer.newPopup("surface2")
  p.rows = {}
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      ns.Desktop.Layer.close("escape")
    elseif key == "UP" or key == "DOWN" then
      focusRow(key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    -- Protected in combat: the keys then stay with the menu.
    ns.PropagateKeys(self, not handled)
  end)
  return p
end

local function openMenu(a)
  if menuOpen() then
    local same = menuOwner == a.frame.gear
    closeMenu()
    if same then
      return
    end
  end
  menu = menu or buildMenu()
  menuOwner = a.frame.gear
  a.frame:Raise()
  fill({
    {
      key = "areas.menu.edit",
      icon = "pencil",
      run = function()
        Areas.Edit(a.id)
      end,
    },
    -- Unlocking from the gear is a deliberate click, so a pinned window may be released here.
    placementOf(a).locked and {
      key = "areas.menu.unlock",
      icon = "pin",
      run = function()
        Areas.SetLocked(a.id, false, "menu")
      end,
    } or {
      key = "areas.menu.lock",
      icon = "pin",
      run = function()
        Areas.SetLocked(a.id, true)
      end,
    },
    {
      key = "areas.menu.hide",
      icon = "close",
      run = function()
        Areas.SetShown(a.id, false)
      end,
    },
    {
      key = "areas.menu.settings",
      icon = "gear",
      run = function()
        ns.Main.Show("settings")
      end,
    },
  })
  ns.Desktop.Layer.open({
    frames = { menu },
    owner = a.frame.gear,
    move = focusRow,
    onClose = function()
      a.menuHeld = false
      applyMouse(a)
      updateGearLater(a)
    end,
  })
  a.menuHeld = a.frame.hit:IsMouseEnabled()
  ns.Desktop.Layer.place(menu, a.frame.gear, "TOPRIGHT", "BOTTOMRIGHT", 0, -2)
  menu:Show()
  updateGear(a)
  ns.Focus.set(menu.shown[1])
end

-- Window ---------------------------------------------------------------------------------------------------

-- Three rows of dots in the bottom right corner, each light with a dark rim so it reads on any layout.
local function paintGrip(g)
  local lr, lg, lb = ns.Theme.rgb("text")
  local dr, dg, db = ns.Theme.rgb("bg")
  for _, dot in ipairs(g.dots) do
    dot.rim:SetColorTexture(dr, dg, db, 0.8)
    dot.light:SetColorTexture(lr, lg, lb, 1)
  end
end

-- The owner of a frame: what its scripts act for. nil while the frame is spare.
local function ownerOf(f)
  return f.fgArea
end

local function buildGrip(f)
  local g = CreateFrame("Frame", nil, f)
  g:SetSize(GRIP, GRIP)
  g:SetPoint("BOTTOMRIGHT", f.canvas, "BOTTOMRIGHT", 0, 0)
  g:SetFrameLevel(f.hit:GetFrameLevel() + 10)
  g:EnableMouse(true)
  g.dots = {}
  for line = 0, 2 do
    for col = 0, 2 - line do
      local rim, light = g:CreateTexture(nil, "ARTWORK"), g:CreateTexture(nil, "OVERLAY")
      rim:SetSize(4, 4)
      rim:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -2 - col * 4, 2 + line * 4)
      light:SetSize(2, 2)
      light:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -3 - col * 4, 3 + line * 4)
      g.dots[#g.dots + 1] = { rim = rim, light = light }
    end
  end
  ns.Bind(g, paintGrip)

  local function stop()
    local a = ownerOf(f)
    if not (a and a.scaling) then
      return
    end
    a.scaling = false
    g:SetScript("OnUpdate", nil)
    setChrome(a, f.hit:IsMouseOver() or g:IsMouseOver())
  end
  g:SetScript("OnEnter", function(self)
    local a = ownerOf(f)
    if a then
      a.overPart = true
      setChrome(a, true)
      updateGear(a)
    end
    ns.ShowTooltip(self, L["areas.win.grip"], L["areas.win.gripTip"])
  end)
  g:SetScript("OnLeave", function()
    local a = ownerOf(f)
    if a then
      a.overPart = false
      setChrome(a, false)
      updateGearLater(a)
    end
    ns.HideTooltip()
  end)
  g:SetScript(
    "OnMouseDown",
    ns.Wrap("areas-grip", function(_, button)
      local a = ownerOf(f)
      f:Raise()
      if not a or button ~= "LeftButton" or placementOf(a).locked then
        return
      end
      savePosition(a)
      a.scaling = true
      setChrome(a, true)
      ns.HideTooltip()
      g:SetScript(
        "OnUpdate",
        ns.Wrap("areas-grip", function()
          dragScale(a)
        end)
      )
    end)
  )
  g:SetScript("OnMouseUp", ns.Wrap("areas-grip", stop))
  g:SetScript("OnHide", stop)
  return g
end

-- A button of the chrome strip: plain action that lights the strip while the mouse is on it.
local function chromeButton(f, icon, key)
  local b = W.Action(f, { icon = icon, size = PIN_SIZE, tooltip = key, tooltipText = key .. "Tip" })
  b:SetFrameLevel(f.hit:GetFrameLevel() + 10)
  b:HookScript("OnEnter", function()
    local a = ownerOf(f)
    if a then
      a.overPart = true
      setChrome(a, true)
      updateGear(a)
    end
  end)
  b:HookScript("OnLeave", function()
    local a = ownerOf(f)
    if a then
      a.overPart = false
      setChrome(a, false)
      updateGearLater(a)
    end
  end)
  b:HookScript("OnMouseDown", function()
    f:Raise()
  end)
  return b
end

-- The gear in the top right corner opens the menu. It is no child of the hit frame, so it never takes part in a
-- drag, and it is lit like the grip: a surface with a light edge and a dark rim reads on any layout.
local function buildGear(f)
  local g = W.Action(f, {
    icon = "gear",
    boxed = true,
    size = GEAR_SIZE,
    tooltip = "areas.win.menu",
    tooltipText = "areas.win.menuTip",
    wrap = "areas-gear",
    onClick = function()
      local a = ownerOf(f)
      -- A window a rule hides has a dead gear. A pinned one keeps it for the keyboard, which needs no mouse.
      if a and a.live then
        openMenu(a)
      end
    end,
  })
  g:SetFrameLevel(f.hit:GetFrameLevel() + 10)
  g:SetPoint("TOPRIGHT", f.canvas, "TOPRIGHT", -2, -2)
  g:SetAlpha(0)
  local rim = g:CreateTexture(nil, "BACKGROUND")
  rim:SetPoint("TOPLEFT", g, "TOPLEFT", -1, 1)
  rim:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 1, -1)
  ns.Bind(g, function()
    local r, gr, b = ns.Theme.rgb("bg")
    rim:SetColorTexture(r, gr, b, 0.8)
  end)
  g:HookScript("OnEnter", function()
    local a = ownerOf(f)
    if a then
      a.overPart = true
      setChrome(a, true)
      updateGear(a)
    end
  end)
  g:HookScript("OnLeave", function()
    local a = ownerOf(f)
    if a then
      a.overPart = false
      setChrome(a, false)
      updateGearLater(a)
    end
  end)
  g:HookScript("OnMouseDown", function()
    f:Raise()
  end)
  g.fgOnFocus = function()
    local a = ownerOf(f)
    if a then
      a.gearFocus = true
      updateGear(a)
    end
  end
  g.fgOnBlur = function()
    local a = ownerOf(f)
    if a then
      a.gearFocus = false
      updateGearLater(a)
    end
  end
  return g
end

local function create()
  local f = CreateFrame("Frame", nil, UIParent)
  -- Same strata as the main window and the game's panels, so a click raises exactly the clicked one.
  f:SetFrameStrata(AL.DEFAULT_STRATA)
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)

  f.canvas = CreateFrame("Frame", nil, f)
  f.canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  -- A plain frame over the canvas takes the mouse: a drag moves the area, a click does nothing (the gear opens
  -- the menu). Besides the gear and the chrome buttons it is the only frame of the area with the mouse on, and it
  -- is off while a rule hides the area.
  f.hit = CreateFrame("Frame", nil, f)
  f.hit:SetAllPoints(f.canvas)
  f.hit:SetFrameLevel(f.canvas:GetFrameLevel() + 100)
  f.hit:EnableMouse(true)
  f.hit:EnableMouseWheel(true)
  f.hit:RegisterForDrag("LeftButton")
  f.hit:SetScript("OnMouseDown", function()
    f:Raise()
  end)
  f.hit:SetScript(
    "OnDragStart",
    ns.Wrap("areas-move", function()
      local a = ownerOf(f)
      if not a or placementOf(a).locked then
        return
      end
      a.moving = true
      ns.HideTooltip()
      f:StartMoving()
    end)
  )
  f.hit:SetScript(
    "OnDragStop",
    ns.Wrap("areas-move", function()
      local a = ownerOf(f)
      if a and a.moving then
        a.moving = false
        f:StopMovingOrSizing()
        savePosition(a)
        hostChanged()
      end
    end)
  )
  f.hit:SetScript("OnEnter", function(self)
    local a = ownerOf(f)
    if a then
      a.overHit = true
      setChrome(a, true)
      updateGear(a)
      ns.ShowTooltip(self, nameOf(a), L[placementOf(a).locked and "areas.win.hintLocked" or "areas.win.hint"])
    end
  end)
  f.hit:SetScript("OnLeave", function()
    local a = ownerOf(f)
    if a then
      a.overHit = false
      setChrome(a, false)
      updateGearLater(a)
    end
    ns.HideTooltip()
  end)
  f.hit:SetScript(
    "OnMouseWheel",
    ns.Wrap("areas-scale", function(_, delta)
      local a = ownerOf(f)
      if a and not placementOf(a).locked and ns.Keys.Matches("windowScale") then
        changeScale(a, delta)
      end
    end)
  )

  f.gear = buildGear(f)
  f.pin = chromeButton(f, "pin", "areas.win.pin")
  f.pin:SetPoint("RIGHT", f.gear, "LEFT", -2, 0)
  f.pin:SetScript(
    "OnClick",
    ns.Wrap("areas-pin", function()
      local a = ownerOf(f)
      if a then
        Areas.SetLocked(a.id, true)
      end
    end)
  )
  f.edit = chromeButton(f, "pencil", "areas.win.edit")
  f.edit:SetPoint("RIGHT", f.pin, "LEFT", -2, 0)
  f.edit:SetScript(
    "OnClick",
    ns.Wrap("areas-edit", function()
      local a = ownerOf(f)
      if a then
        Areas.Edit(a.id)
      end
    end)
  )
  f.grip = buildGrip(f)
  f:Hide()
  return f
end

-- Events ---------------------------------------------------------------------------------------------------

local function applyAll(full)
  for _, a in pairs(instances) do
    if full then
      apply(a)
    else
      applyRules(a)
    end
  end
end

local function onEvent(_, event)
  applyAll(event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED")
end

-- A change of the shared game state only needs the rules applied again.
local function onLoadState(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    -- A change of a group that waited for the end of the combat.
    for _, a in pairs(instances) do
      if a.frame and CR.Deferred(a.frame.canvas) then
        repaint(a)
      end
    end
  end
  applyAll(false)
end

-- The event frame and the subscription live while at least one area exists.
local function syncEvents()
  if next(instances) then
    if not watcher then
      watcher = CreateFrame("Frame")
      watcher:SetScript("OnEvent", ns.Wrap("areas-event", onEvent))
    end
    for _, event in ipairs(EVENTS) do
      pcall(watcher.RegisterEvent, watcher, event)
    end
    LS.Subscribe(onLoadState)
  else
    if watcher then
      watcher:UnregisterAllEvents()
    end
    LS.Unsubscribe(onLoadState)
  end
end

-- The areas ------------------------------------------------------------------------------------------------

-- Makes the area of `id`: its own frame (a spare one of a deleted area, else a new one) and its own state. It
-- is drawn at once when its stored data says it shows. Areas.Sync is the way that normally calls this.
function Areas.New(id)
  local a = { id = id }
  a.frame = table.remove(spare) or create()
  a.frame.fgArea = a
  instances[id] = a
  syncEvents()
  apply(a)
  return a
end

-- Frees the elements, the event registrations and the mouse of an area; its frame goes to the spare ones.
function Areas.Destroy(id)
  local a = instances[id]
  if not a then
    return
  end
  instances[id] = nil
  closeMenu(a)
  local f = a.frame
  if a.scaling then
    f.grip:SetScript("OnUpdate", nil)
  end
  CR.Clear(f.canvas)
  f:Hide()
  f.fgArea = nil
  spare[#spare + 1] = f
  a.frame = nil
  syncEvents()
  syncModifiers()
end

function Areas.Get(id)
  return instances[id]
end

-- The frame that holds the event registrations, nil until the first area existed.
function Areas.Watcher()
  return watcher
end

-- The ids of the areas that exist, sorted by name.
function Areas.Ids()
  local out = {}
  for i, entry in ipairs(AL.List(items())) do
    out[i] = entry.id
  end
  return out
end

-- Brings the areas that exist in line with the stored ones: new ones appear, deleted ones go, the placement
-- of a deleted area leaves this character.
function Areas.Sync()
  if not ns.db then
    return
  end
  -- One layout per window: shared layouts become copies, leftover layouts become windows, names are made
  -- unique. A window made from a leftover layout stays hidden on this character.
  local migrated, leftovers = AY.Migrate(ns.db.settings.areas)
  -- The six old yes/no rules move into `load` before anything reads them.
  migrated = migrated + AL.MigrateLoad(items())
  local stored = items()
  -- A window this character has no entry for yet starts shown or hidden as the account setting says.
  local char = ns.charDB
  if type(char) == "table" then
    if type(char.areas) ~= "table" then
      char.areas = {}
    end
    for id, item in pairs(stored) do
      if AL.CleanId(id) and type(item) == "table" then
        if char.areas[id] == nil then
          char.areas[id] = {}
        end
        CS.SeedShown(char.areas[id], ns.db.settings.areas, item)
      end
    end
    for _, id in ipairs(leftovers) do
      char.areas[id].shown = false
    end
  end
  for id in pairs(instances) do
    if type(stored[id]) ~= "table" then
      Areas.Destroy(id)
    end
  end
  for id, item in pairs(stored) do
    if AL.CleanId(id) and type(item) == "table" and not instances[id] then
      Areas.New(id)
    end
  end
  if type(char) == "table" and type(char.areas) == "table" then
    for id in pairs(char.areas) do
      if type(stored[id]) ~= "table" then
        char.areas[id] = nil
      end
    end
  end
  applyAll(true)
  if migrated > 0 then
    for _, a in pairs(instances) do
      refresh(a)
    end
  end
end

-- Storage ----------------------------------------------------------------------------------------------------

-- A new window with a new layout, both named `name` (cleaned and made unique, empty means "Window <n>"). `source`
-- is nil for an empty layout or { layout = table } for one that is given (an import, the working copy of the
-- editor). The window the player makes shows on this character whatever the setting for new characters says.
-- Returns the id, or nil and "limit" (windows), "layoutLimit", "name".
function Areas.Create(name, source)
  if not ns.db then
    return nil
  end
  local clean = AL.CleanName(name, nil) or AL.DefaultName(items())
  local layout = type(source) == "table" and source.layout or nil
  local id, reason = lib().CreateWindow(clean, layout, function(areaId)
    Store.setChar(AL.CharPath(areaId) .. ".shown", true)
  end)
  if not id then
    return nil, reason
  end
  return id
end

-- A copy of window `id` with a copy of its layout (default name "<name> Copy"). Returns the new id, or nil and the
-- reason. Every way to duplicate (settings page, slash command, editor) ends here; `layout` (optional) is the
-- content to copy instead of the stored one, the editor passes its working copy.
function Areas.Duplicate(id, name, layout)
  if not ns.db then
    return nil
  end
  local newId, reason = lib().DuplicateWindow(id, AL.CleanName(name, nil), function(areaId)
    Store.setChar(AL.CharPath(areaId) .. ".shown", true)
  end, layout)
  if not newId then
    return nil, reason
  end
  return newId
end

-- Renames the window and its layout. Returns true, or nil and "name", "dup", "missing".
function Areas.Rename(id, name)
  return lib().RenameWindow(id, name)
end

-- Replaces the elements of window `targetId` by a copy of those of window `sourceId`.
function Areas.CopyContent(sourceId, targetId)
  return lib().CopyContent(sourceId, targetId)
end

-- Deletes the window and its layout for good (account wide). The settings page and /fg hudwindow delete ask first.
function Areas.Delete(id)
  return lib().DeleteWindow(id) == true
end

function Areas.ConfirmDelete(id)
  ns.Dialogs.Confirm("areas.delete.title", "areas.delete.text", function()
    Areas.Delete(id)
  end)
end

function Areas.SetShown(id, on)
  if items()[id] then
    Store.setChar(AL.CharPath(id) .. ".shown", on == true)
  end
end

-- Locks or unlocks the window on this character. A pinned window is released only by a deliberate act: `via` is
-- "editor" (true counts as "editor") or "menu" (the gear menu). Every other caller gets false when it asks for "off".
function Areas.SetLocked(id, on, via)
  if not items()[id] then
    return false
  end
  if on ~= true and via ~= "editor" and via ~= "menu" and via ~= true then
    return false
  end
  Store.setChar(AL.CharPath(id) .. ".locked", on == true)
  return true
end

-- Where the window of `id` sits on this character as the editor shows it: x and y are the offset of the middle of
-- the window from the middle of the screen in units (right and up positive), then scale, locked and strata. nil for an
-- unknown window. A window that was never placed sits at its default place.
function Areas.Position(id)
  if type(items()[id]) ~= "table" then
    return nil
  end
  local p = Areas.Placement(id)
  local canvas = lib().Layout(id).canvas
  local cx, cy
  if p.x and p.y then
    cx, cy = AL.CenterOffset(p.x, p.y, p.scale, canvas.w, canvas.h, UIParent:GetWidth(), UIParent:GetHeight())
  else
    cx, cy = AL.DefaultOffset(indexOf(id))
  end
  return { x = cx or 0, y = cy or 0, scale = p.scale, locked = p.locked, strata = p.strata }
end

-- Moves the middle of the window to the offset cx, cy from the middle of the screen. Refused (false) for a pinned
-- window, a window that is not there and numbers that are no numbers; the real window follows at once and is
-- held on the screen.
function Areas.SetPosition(id, cx, cy)
  local a = instances[id]
  if not (a and a.frame) or Areas.Placement(id).locked then
    return false
  end
  local p, canvas = Areas.Placement(id), lib().Layout(id).canvas
  local x, y = AL.CornerFor(cx, cy, p.scale, canvas.w, canvas.h, UIParent:GetWidth(), UIParent:GetHeight())
  if not x then
    return false
  end
  local db = charEntry(id)
  db.x, db.y = x, y
  apply(a)
  hostChanged()
  return true
end

-- Sets the scale (whole percent, 0.5 to 3) around the middle of the window, so x and y keep their values.
function Areas.SetScale(id, scale)
  local a = instances[id]
  if not (a and a.frame) or Areas.Placement(id).locked then
    return false
  end
  local pos, canvas = Areas.Position(id), lib().Layout(id).canvas
  local newScale = AL.RoundScale(scale)
  local x, y = AL.CornerFor(pos.x, pos.y, newScale, canvas.w, canvas.h, UIParent:GetWidth(), UIParent:GetHeight())
  local db = charEntry(id)
  db.scale = newScale
  if x then
    db.x, db.y = x, y
  end
  apply(a)
  hostChanged()
  return true
end

-- Sets the layer (frame strata, one of AreaLogic.STRATAS) of the window. Refused (false) for a pinned window, a
-- window that is not there and a value that is not a strata. The entry only stores a value that differs from the
-- default.
function Areas.SetStrata(id, strata)
  local a = instances[id]
  if not (a and a.frame) or Areas.Placement(id).locked or AL.CleanStrata(strata) ~= strata then
    return false
  end
  charEntry(id).strata = AL.StoredStrata(strata)
  apply(a)
  hostChanged()
  return true
end

-- Puts the middle of the window into the middle of the screen; the scale and the layer stay.
function Areas.ResetPosition(id)
  return Areas.SetPosition(id, 0, 0)
end

-- The state of an area for this character: shown and locked as booleans.
function Areas.Placement(id)
  return AL.Placement(ns.charDB and ns.charDB.areas and ns.charDB.areas[id])
end

-- The text the player reads for a refusal of the library functions; nil for a reason nobody knows.
local REASON_KEYS = {
  name = "areas.lib.badName",
  dup = "areas.lib.dup",
  limit = "areas.slash.limit",
  layoutLimit = "areas.lib.limit",
  missing = "areas.lib.missing",
}

function Areas.ReasonText(reason)
  local key = REASON_KEYS[reason]
  return key and L[key] or nil
end

function Areas.Explain(reason)
  local text = Areas.ReasonText(reason)
  if text then
    ns.Notify.send(text, "warning")
  end
end

-- The layout manager the editor drives (the format of LayoutSet.Manager). The editor speaks of layouts, here
-- each one is a window: the list holds every window under its name (the id is the id of its layout), `select`
-- lets the editor work on another window and changes nothing else, and New, Import, Rename and Delete act on the
-- window together with its layout. The window the editor starts on is `areaId`. The editor tells the player why a
-- call was refused.
function Areas.Manager(areaId)
  local m = {
    -- The editor names the list after what it holds and asks about what a delete does.
    labels = { layouts = "areas.edit.head", deleteTitle = "areas.delete.title", deleteAsk = "areas.edit.deleteAsk" },
  }
  local picked = areaId
  -- The window the editor works on.
  function m.window()
    return picked
  end
  function m.list()
    local out = {}
    for _, window in ipairs(lib().Windows()) do
      if window.layoutId then
        out[#out + 1] = { id = window.layoutId, name = window.name }
      end
    end
    return out
  end
  function m.current()
    return picked and lib().LayoutId(picked) or nil
  end
  function m.select(layoutId)
    local windowId = lib().WindowOf(layoutId)
    if not windowId then
      return nil, "missing"
    end
    picked = windowId
    return CL.Copy(lib().Layout(windowId))
  end
  function m.save(layoutId, layout)
    return lib().Save(layoutId, layout)
  end
  -- A new window with the given layout (nil: an empty one); returns the id of its layout.
  function m.create(name, layout)
    local windowId, reason = Areas.Create(name, { layout = layout })
    if not windowId then
      return nil, reason
    end
    return lib().LayoutId(windowId)
  end
  m.import = m.create
  -- "Duplicate" of the editor: a copy of window `layoutId` with `layout` (the working copy) as its content and
  -- the conditions of the window; returns the id of the new layout.
  function m.duplicate(layoutId, name, layout)
    local windowId = lib().WindowOf(layoutId)
    if not windowId then
      return nil, "missing"
    end
    local newId, reason = Areas.Duplicate(windowId, name, layout)
    if not newId then
      return nil, reason
    end
    return lib().LayoutId(newId)
  end
  -- "New" of the editor: a new window with an empty layout.
  function m.new(name)
    return m.create(name)
  end
  function m.rename(layoutId, name)
    return lib().RenameWindow(lib().WindowOf(layoutId), name)
  end
  -- The editor needs a window to show, so the last one stays. The editor moves to the first other window when
  -- the one it shows goes.
  function m.delete(layoutId)
    local windowId = lib().WindowOf(layoutId)
    if not windowId then
      return nil, "missing"
    end
    local replacement
    for _, window in ipairs(lib().Windows()) do
      if window.id ~= windowId and window.layoutId then
        replacement = replacement or window.id
      end
    end
    if not replacement then
      return nil, "last"
    end
    local ok, reason = lib().DeleteWindow(windowId)
    if ok and picked == windowId then
      picked = replacement
    end
    return ok, reason
  end
  function m.canDelete(layoutId)
    return lib().Has(layoutId) and lib().Count() > 1
  end
  return m
end

-- Window section of the editor ----------------------------------------------------------------------------------

local MAX_UNITS = 10000

-- The state of the window the editor works on, as the section shows it; nil without a window.
local function hostState(manager)
  local id = manager and manager.window and manager.window()
  return id, id and Areas.Position(id) or nil
end

local hostManager

-- The section "Window" of the editor (option hostSection, a stable function so the editor builds it once): visible
-- and pinned, X, Y, scale and layer of the window on the whole screen, and a button that puts it into the middle. All of
-- it is per character and works on the real window at once. While the window is pinned X, Y, scale, layer and the
-- button are off and a line says to unlock first, "Pinned" stays usable.
function Areas.HostSection(parent)
  local Controls = ns.CanvasEditor.Controls
  local f = CreateFrame("Frame", nil, parent)
  local function window()
    return (hostState(hostManager))
  end
  local function position()
    return select(2, hostState(hostManager))
  end
  f.head = W.Text(f, { key = "areas.host.head", role = "ui", color = "accent2" })
  f.shown = W.Checkbox(f, {
    key = "areas.host.shown",
    tooltip = "areas.host.shown",
    tooltipText = "areas.host.shownTip",
    get = function()
      local id = window()
      return id ~= nil and Areas.Placement(id).shown
    end,
    set = function(on)
      local id = window()
      if id then
        Areas.SetShown(id, on)
      end
    end,
  })
  f.locked = W.Checkbox(f, {
    key = "areas.host.locked",
    tooltip = "areas.host.locked",
    tooltipText = "areas.host.lockedTip",
    get = function()
      local id = window()
      return id ~= nil and Areas.Placement(id).locked
    end,
    set = function(on)
      local id = window()
      if id then
        Areas.SetLocked(id, on, "editor")
      end
    end,
  })
  local function number(key, min, max, step, get, set)
    return Controls.Number(f, {
      label = "areas.host." .. key,
      tooltip = "areas.host." .. key .. "Tip",
      min = min,
      max = max,
      step = step,
      labelWidth = 120,
      get = get,
      set = set,
    })
  end
  f.x = number("x", -MAX_UNITS, MAX_UNITS, 1, function()
    local p = position()
    return p and p.x
  end, function(v)
    local p = position()
    if p then
      Areas.SetPosition(window(), v, p.y)
    end
  end)
  f.y = number("y", -MAX_UNITS, MAX_UNITS, 1, function()
    local p = position()
    return p and p.y
  end, function(v)
    local p = position()
    if p then
      Areas.SetPosition(window(), p.x, v)
    end
  end)
  f.scale = number("scale", AL.SCALE_MIN, AL.SCALE_MAX, 0.01, function()
    local p = position()
    return p and p.scale
  end, function(v)
    local id = window()
    if id then
      Areas.SetScale(id, v)
    end
  end)
  local strataOptions = {}
  for _, strata in ipairs(AL.STRATAS) do
    strataOptions[#strataOptions + 1] = { value = strata, key = "areas.host.strata." .. strata }
  end
  f.strata = Controls.Choice(f, {
    label = "areas.host.strata",
    tooltip = "areas.host.strata",
    tooltipText = "areas.host.strataTip",
    options = strataOptions,
    get = function()
      local p = position()
      return p and p.strata
    end,
    set = function(v)
      local id = window()
      if id then
        Areas.SetStrata(id, v)
      end
    end,
  })
  f.reset = W.Button(f, {
    key = "areas.host.reset",
    width = 160,
    tooltip = "areas.host.reset",
    tooltipText = "areas.host.resetTip",
    onClick = function()
      local id = window()
      if id then
        Areas.ResetPosition(id)
      end
    end,
  })
  f.hint = W.Text(f, { key = "areas.host.unlockFirst", role = "small", color = "textMuted", wrap = true })
  local gap = 6
  function f:Refresh()
    local width = math.max(self:GetWidth() or 0, 120)
    local p = position()
    local locked = p ~= nil and p.locked == true
    local y = 0
    local function put(control, h)
      control:ClearAllPoints()
      control:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      control:SetWidth(width)
      control:SetHeight(h)
      y = y + h + gap
    end
    put(f.head, ns.Theme.lineHeight(20))
    f.shown.Refresh()
    f.locked.Refresh()
    put(f.shown, ns.Theme.lineHeight(24))
    put(f.locked, ns.Theme.lineHeight(24))
    for _, field in ipairs({ f.x, f.y, f.scale }) do
      field:Refresh()
      put(field, ns.Theme.lineHeight(28))
      field.edit:SetEnabled(not locked)
      field:SetAlpha(locked and 0.5 or 1)
    end
    f.strata.Refresh()
    put(f.strata, Controls.HEIGHT.choice)
    f.strata.button:SetEnabled(not locked)
    f.strata:SetAlpha(locked and 0.5 or 1)
    f.reset:ClearAllPoints()
    f.reset:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    f.reset:SetSize(math.min(f.reset:FullWidth(), width), ns.Theme.lineHeight(26))
    f.reset:SetEnabled(not locked)
    f.reset:SetAlpha(locked and 0.5 or 1)
    y = y + ns.Theme.lineHeight(26) + gap
    f.hint:SetShown(locked)
    if locked then
      f.hint:ClearAllPoints()
      f.hint:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      f.hint:SetWidth(width)
      y = y + math.ceil(f.hint:GetStringHeight()) + gap
    end
    self:SetHeight(math.max(y - gap, 1))
  end
  f:Refresh()
  return f
end

-- "Window: <name>".
local function editTitle(layoutName, layoutId)
  return string.format(L["areas.edit.title"], layoutName ~= "" and layoutName or lib().Name(layoutId))
end

local function openEditor(manager, layout)
  local editor = ns.CanvasEditor
  if not (editor and editor.Open) then
    ns.Notify.send(L["areas.edit.missing"], "warning")
    return
  end
  -- The tool buttons start off at every opening, so the simulation starts empty too.
  ns.CursorSim.Reset()
  hostManager = manager
  editor.Open({
    host = "area",
    groups = true,
    title = editTitle,
    layout = layout,
    types = E.Types("area"),
    presets = AL.Presets(),
    tools = ns.CursorSim.Tools(),
    sim = ns.CursorSim.State(),
    manager = manager,
    hostSection = Areas.HostSection,
    -- The editor may have switched the window since it was opened: the result goes to the current one.
    onApply = function(result)
      local current = manager.current()
      if current then
        manager.save(current, result)
      end
    end,
    onCancel = ns.CursorSim.Reset,
  })
end

-- Opens the layout editor on the window `id`; the list of the editor holds every window.
function Areas.Edit(id)
  if items()[id] then
    openEditor(Areas.Manager(id), lib().Layout(id))
  end
end

-- /fg hudfenster ----------------------------------------------------------------------------------------------

local function say(key, ...)
  ns.Notify.chat(string.format(L[key], ...))
end

-- The id and name for the word of the player; says why when there is none. A missing word means the only
-- area when there is just one.
local function resolve(arg, verb)
  local list = AL.List(items())
  if arg == "" and #list == 1 then
    return list[1].id, list[1].name
  end
  if arg == "" then
    say("areas.slash.pick", verb)
    return nil
  end
  local id = AL.Find(items(), arg)
  if not id then
    say("areas.slash.none", arg)
    return nil
  end
  return id, AL.CleanName(items()[id].name, id)
end

-- Runs fn(id, name) for the area of the word, or for every area when the word is missing.
local function eachOrOne(arg, verb, fn)
  if arg == "" then
    for _, entry in ipairs(AL.List(items())) do
      fn(entry.id, entry.name)
    end
    return
  end
  local id, name = resolve(arg, verb)
  if id then
    fn(id, name)
  end
end

local function list()
  local entries = AL.List(items())
  if #entries == 0 then
    ns.Notify.chat(L["areas.slash.empty"])
    return
  end
  for _, entry in ipairs(entries) do
    local p = Areas.Placement(entry.id)
    say(
      "areas.slash.line",
      entry.name,
      L[p.shown and "areas.slash.shown" or "areas.slash.hidden"],
      L[p.locked and "areas.slash.locked" or "areas.slash.unlocked"]
    )
  end
end

local function areaName(id)
  return AL.CleanName(items()[id] and items()[id].name, id)
end

-- /fg hudfenster copy <from> <to>: the elements of the first window replace those of the second after a question.
local function slashCopy(arg)
  local readings = AL.PairReadings(arg)
  if #readings == 0 then
    say("areas.slash.needPair", "copy")
    return
  end
  local source, target
  for _, pair in ipairs(readings) do
    local first, second = AL.Find(items(), pair[1]), AL.Find(items(), pair[2])
    if first and second then
      source, target = first, second
      break
    end
  end
  if not source then
    local pair = readings[1]
    say("areas.slash.none", AL.Find(items(), pair[1]) and pair[2] or pair[1])
    return
  end
  if source == target then
    ns.Notify.chat(L["areas.slash.samePair"])
    return
  end
  ns.Dialogs.Confirm("areas.copy.title", "areas.copy.text", function()
    local ok, reason = Areas.CopyContent(source, target)
    if ok then
      say("areas.slash.didCopy", areaName(target), areaName(source))
    else
      ns.Notify.chat(Areas.ReasonText(reason) or L["areas.slash.usage"])
    end
  end)
end

function Areas.Slash(rest)
  if not ns.db then
    return
  end
  local verb, arg = AL.ParseSlash(rest)
  if verb == "list" then
    list()
  elseif verb == "gone" then
    ns.Notify.chat(L["areas.slash.gone"])
  elseif verb == "copy" then
    slashCopy(arg)
  elseif verb == "duplicate" then
    local id = resolve(arg, "duplicate")
    if id then
      local newId, reason = Areas.Duplicate(id)
      if newId then
        say("areas.slash.didDuplicate", areaName(newId), areaName(id))
      else
        ns.Notify.chat(Areas.ReasonText(reason) or L["areas.slash.usage"])
      end
    end
  elseif verb == "new" then
    local id, reason = Areas.Create(arg)
    if id then
      local name = AL.CleanName(items()[id].name, id)
      say("areas.slash.created", name, name)
    elseif Areas.ReasonText(reason) then
      ns.Notify.chat(Areas.ReasonText(reason))
    end
  elseif verb == "edit" then
    local id = resolve(arg, "edit")
    if id then
      Areas.Edit(id)
    end
  elseif verb == "delete" then
    local id = resolve(arg, "delete")
    if id then
      Areas.ConfirmDelete(id)
    end
  elseif verb == "show" or verb == "hide" then
    local on = verb == "show"
    eachOrOne(arg, verb, function(id, name)
      Areas.SetShown(id, on)
      say(on and "areas.slash.didShow" or "areas.slash.didHide", name)
    end)
  elseif verb == "lock" then
    eachOrOne(arg, verb, function(id, name)
      Areas.SetLocked(id, true)
      say("areas.slash.didLock", name)
    end)
  elseif verb == "unlock" then
    -- Refused here on purpose: the layout editor and the gear menu unlock.
    if arg == "" then
      say("areas.slash.unlockEditor", L["areas.slash.nameHint"])
    else
      local id, name = resolve(arg, verb)
      if id then
        say("areas.slash.unlockEditor", name)
      end
    end
  else
    ns.Notify.chat(L["areas.slash.usage"])
  end
end

-- Events -----------------------------------------------------------------------------------------------------

-- A change of one area repaints that area only: another area keeps its elements and its event registrations.
ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if type(path) ~= "string" then
    return
  end
  if scope == "char" then
    local id = path:match("^areas%.([%w_%-]+)")
    local a = id and instances[id]
    if a then
      -- Anything of this character only moves or shows the window.
      apply(a)
    end
    hostChanged()
    return
  end
  local layoutId, layoutRest = path:match("^settings%.areas%.layouts%.([%w_%-]+)(.*)$")
  if layoutId then
    -- A layout changed: the window that shows it repaints, no other. A new name changes no picture.
    if not layoutRest:find("^%.name") then
      for _, a in pairs(instances) do
        if lib().LayoutId(a.id) == layoutId then
          refresh(a)
        end
      end
    end
    return
  end
  local id, rest = path:match("^settings%.areas%.items%.([%w_%-]+)(.*)$")
  if not id then
    if path == "settings.areas.items" or path == "settings.areas" then
      Areas.Sync()
    elseif path == "settings.areas.layouts" then
      for _, a in pairs(instances) do
        refresh(a)
      end
    end
    return
  end
  local a = instances[id]
  if (a == nil) ~= (type(items()[id]) ~= "table") then
    Areas.Sync()
  elseif a and (rest == "" or rest:find("^%.layout") or rest:find("^%.name")) then
    refresh(a)
  elseif a then
    apply(a)
  end
end)
ns.On("PLAYER_LOGIN", function()
  Areas.Sync()
end)
ns.On("PLAYER_LOGOUT", function()
  for _, a in pairs(instances) do
    if a.frame:IsShown() then
      savePosition(a)
    end
  end
end)
