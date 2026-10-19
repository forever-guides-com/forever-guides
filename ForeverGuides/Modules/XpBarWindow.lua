-- The experience bar window (ns.XpBar): one movable window that draws the active canvas layout
-- (Modules/XpBarLayout.lua, CanvasRender) from the values of Modules/XpTracker.lua. A click on the bar
-- opens a menu, the layout editor (ns.CanvasEditor) changes the layout. The window is the canvas alone,
-- pinned or not: unpinned, the bar can be dragged, a grip scales it and a pin and an edit button show on hover.
-- Settings: ns.db.settings.xpBar = { shown, pinned, layoutId, layouts = { [id] = layout }, alpha,
-- autoPause, sessionResetOnLogin, chatLevelUp, hideInCombat, showAtMax }; position and scale live in
-- ns.db.frames.xpbar. Nothing here touches protected frames, so the bar works in combat.
local _, ns = ...
local W, L, U = ns.W, ns.L, ns.U
local XL, XT, XB, CR = ns.XpLogic, ns.XpTracker, ns.XpBarLayout, ns.CanvasRender

local XW = {}
ns.XpBar = XW

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 3, 0.1
local ALPHA_MIN = 0.2
local GRIP, PIN_SIZE = 16, 18
local MENU_W, MENU_ROW = 210, 26
local TICK = 1
local FLAGS = { "shown", "pinned", "chatLevelUp", "autoPause", "sessionResetOnLogin", "hideInCombat", "showAtMax" }

ns.AddLocale("enUS", {
  ["xpbar.win.title"] = "Experience bar",
  ["xpbar.win.pin"] = "Pin",
  ["xpbar.win.pinTip"] = "Fixes the position and hides the scale grip.",
  ["xpbar.win.edit"] = "Edit layout",
  ["xpbar.win.editTip"] = "Opens the layout editor for this bar.",
  ["xpbar.win.grip"] = "Scale",
  ["xpbar.win.gripTip"] = "Drag to scale the bar and all its texts. {key:windowScale} changes the size as well.",
  ["xpbar.menu.pause"] = "Pause session",
  ["xpbar.menu.resume"] = "Resume session",
  ["xpbar.menu.reset"] = "Reset session",
  ["xpbar.menu.edit"] = "Edit layout",
  ["xpbar.menu.pin"] = "Pin",
  ["xpbar.menu.unpin"] = "Unpin",
  ["xpbar.menu.layout"] = "Choose layout",
  ["xpbar.menu.newLayout"] = "New layout",
  ["xpbar.layout.copy"] = "%s copy",
  ["xpbar.layout.badName"] = "Enter a name for the layout.",
  ["xpbar.layout.limit"] = "There are too many layouts. Delete one first.",
  ["xpbar.layout.last"] = "The last layout cannot be deleted.",
  ["xpbar.menu.back"] = "Back",
  ["xpbar.menu.settings"] = "Settings",
  ["xpbar.menu.close"] = "Close window",
  ["xpbar.tip.level"] = "Level {level}: {xp} / {max} ({pct}%)",
  ["xpbar.tip.rested"] = "Rested: {rested} ({rested_pct}%)",
  ["xpbar.tip.quests"] = "Quests done: {done} ({done_pct}%), open: {todo}",
  ["xpbar.tip.levelTime"] = "Time on this level: {level_time}",
  ["xpbar.tip.xph"] = "XP per hour: {xph}, level up in {eta}",
  ["xpbar.tip.session"] = "Session: {session_time} ({state}), {session_gain} XP",
  ["xpbar.edit.title"] = "Experience bar layout",
  ["xpbar.edit.missing"] = "The layout editor is not available.",
  ["xpbar.slash.paused"] = "Experience session paused.",
  ["xpbar.slash.resumed"] = "Experience session running.",
  ["xpbar.slash.reset"] = "Experience session reset.",
  ["xpbar.slash.chatOn"] = "Chat message at level up: on.",
  ["xpbar.slash.chatOff"] = "Chat message at level up: off.",
  ["xpbar.slash.chatChannelOn"] = "Chat message at level up, %s: on.",
  ["xpbar.slash.chatChannelOff"] = "Chat message at level up, %s: off.",
  ["xpbar.slash.chatMasterOff"] = "The chat message is off as a whole: /fg xp chat on",
  ["xpbar.slash.chan.self"] = "own window",
  ["xpbar.slash.chan.group"] = "group",
  ["xpbar.slash.chan.guild"] = "guild",
  ["xpbar.slash.chan.say"] = "say",
  ["xpbar.slash.usage"] = "/fg xp [pause | reset | edit | time <from> <to> | chat on|off | chat <self|group|guild|say> on|off]",
  ["binding.xpbar"] = "Experience bar on or off",
})
ns.AddLocale("deDE", {
  ["xpbar.win.title"] = "Erfahrungsleiste",
  ["xpbar.win.pin"] = "Anheften",
  ["xpbar.win.pinTip"] = "Fixiert die Position und blendet den Skalierungsgriff aus.",
  ["xpbar.win.edit"] = "Layout bearbeiten",
  ["xpbar.win.editTip"] = "Öffnet den Layout-Editor für diese Leiste.",
  ["xpbar.win.grip"] = "Skalieren",
  ["xpbar.win.gripTip"] = "Ziehen skaliert die Leiste samt allen Texten. {key:windowScale} ändert die Größe ebenfalls.",
  ["xpbar.menu.pause"] = "Sitzung pausieren",
  ["xpbar.menu.resume"] = "Sitzung fortsetzen",
  ["xpbar.menu.reset"] = "Sitzung zurücksetzen",
  ["xpbar.menu.edit"] = "Layout bearbeiten",
  ["xpbar.menu.pin"] = "Anheften",
  ["xpbar.menu.unpin"] = "Lösen",
  ["xpbar.menu.layout"] = "Layout wählen",
  ["xpbar.menu.newLayout"] = "Neues Layout",
  ["xpbar.layout.copy"] = "%s Kopie",
  ["xpbar.layout.badName"] = "Gib dem Layout einen Namen.",
  ["xpbar.layout.limit"] = "Es gibt zu viele Layouts. Lösche zuerst eines.",
  ["xpbar.layout.last"] = "Das letzte Layout lässt sich nicht löschen.",
  ["xpbar.menu.back"] = "Zurück",
  ["xpbar.menu.settings"] = "Einstellungen",
  ["xpbar.menu.close"] = "Fenster schließen",
  ["xpbar.tip.level"] = "Stufe {level}: {xp} / {max} ({pct}%)",
  ["xpbar.tip.rested"] = "Ausgeruht: {rested} ({rested_pct}%)",
  ["xpbar.tip.quests"] = "Quests fertig: {done} ({done_pct}%), offen: {todo}",
  ["xpbar.tip.levelTime"] = "Zeit auf dieser Stufe: {level_time}",
  ["xpbar.tip.xph"] = "EP pro Stunde: {xph}, Stufenaufstieg in {eta}",
  ["xpbar.tip.session"] = "Sitzung: {session_time} ({state}), {session_gain} EP",
  ["xpbar.edit.title"] = "Layout der Erfahrungsleiste",
  ["xpbar.edit.missing"] = "Der Layout-Editor ist nicht verfügbar.",
  ["xpbar.slash.paused"] = "Erfahrungs-Sitzung pausiert.",
  ["xpbar.slash.resumed"] = "Erfahrungs-Sitzung läuft.",
  ["xpbar.slash.reset"] = "Erfahrungs-Sitzung zurückgesetzt.",
  ["xpbar.slash.chatOn"] = "Chat-Meldung beim Stufenaufstieg: an.",
  ["xpbar.slash.chatOff"] = "Chat-Meldung beim Stufenaufstieg: aus.",
  ["xpbar.slash.chatChannelOn"] = "Chat-Meldung beim Stufenaufstieg, %s: an.",
  ["xpbar.slash.chatChannelOff"] = "Chat-Meldung beim Stufenaufstieg, %s: aus.",
  ["xpbar.slash.chatMasterOff"] = "Die Chat-Meldung ist insgesamt aus: /fg erfahrung chat an",
  ["xpbar.slash.chan.self"] = "eigenes Fenster",
  ["xpbar.slash.chan.group"] = "Gruppe",
  ["xpbar.slash.chan.guild"] = "Gilde",
  ["xpbar.slash.chan.say"] = "Sagen",
  ["xpbar.slash.usage"] = "/fg erfahrung [pause | reset | edit | zeit <von> <bis> | chat an|aus | chat <selbst|gruppe|gilde|sagen> an|aus]",
  ["binding.xpbar"] = "Erfahrungsleiste ein oder aus",
})

local frame
-- True while the window is shown or hidden by the addon itself (combat, maximum level): what the
-- player chose stays as it is.
local auto = false
-- A manual opening ignores the maximum level rule until the window is closed.
local forced = false
local inCombat = false
local menu, menuMode

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Settings -------------------------------------------------------------------------------------------

local function defaults()
  return ns.Store.defaults.settings.xpBar
end

local function rawSettings()
  local s = ns.db.settings
  if type(s.xpBar) ~= "table" then
    s.xpBar = {}
  end
  return s.xpBar
end

-- Storage of the named layouts (Modules/LayoutSet.lua); the keys of this window's texts stay in use.
local LAYOUTS = ns.LayoutSet.New({
  id = "xpbar",
  path = "settings.xpBar",
  get = rawSettings,
  defaults = defaults,
  maxLayouts = 30,
  dialogName = "ForeverGuidesXpBarLayoutName",
  presets = function()
    return { ids = XB.PRESET_IDS, build = XB.Preset }
  end,
  keys = {
    copy = "xpbar.layout.copy",
    badName = "xpbar.layout.badName",
    limit = "xpbar.layout.limit",
    last = "xpbar.layout.last",
    new = "xpbar.set.new",
    dup = "xpbar.set.dup",
    rename = "xpbar.set.rename",
    delete = "xpbar.set.delete",
    newTitle = "xpbar.set.newTitle",
    renameTitle = "xpbar.set.renameTitle",
    name = "xpbar.set.name",
    from = "xpbar.set.from",
    create = "xpbar.set.create",
    deleteTitle = "xpbar.set.deleteTitle",
    deleteText = "xpbar.set.deleteText",
  },
})
XW.LayoutSet = LAYOUTS
XW.MAX_LAYOUTS = LAYOUTS.max

-- The settings with every field valid: flags are booleans, alpha a number in range, layoutId names a
-- stored layout (the first one, else the default id, when it does not).
function XW.Config()
  local d = defaults()
  local raw = ns.db and ns.db.settings.xpBar
  raw = type(raw) == "table" and raw or {}
  local cfg = {}
  for _, key in ipairs(FLAGS) do
    if type(raw[key]) == "boolean" then
      cfg[key] = raw[key]
    else
      cfg[key] = d[key]
    end
  end
  cfg.alpha = finite(raw.alpha) and U.clamp(raw.alpha, ALPHA_MIN, 1) or d.alpha
  cfg.layouts, cfg.layoutId = LAYOUTS.State(raw)
  return cfg
end

local function set(key, value)
  ns.Store.set("settings.xpBar." .. key, value)
end

-- Layouts: storage and management live in the layout set (Modules/LayoutSet.lua) ------------------------

XW.EnsureLayouts = LAYOUTS.EnsureLayouts
XW.Layouts = LAYOUTS.Layouts
XW.Layout = LAYOUTS.Layout
XW.SetLayout = LAYOUTS.SetLayout
XW.SaveLayout = LAYOUTS.SaveLayout
XW.NewLayout = LAYOUTS.NewLayout
XW.DuplicateLayout = LAYOUTS.DuplicateLayout
XW.RenameLayout = LAYOUTS.RenameLayout
XW.DeleteLayout = LAYOUTS.DeleteLayout
XW.Explain = LAYOUTS.Explain
XW.Manager = LAYOUTS.Manager

-- Values and tooltip --------------------------------------------------------------------------------

function XW.Context(v)
  return XB.Context(v or XT.Snapshot())
end

-- The tooltip text for a value table: the lines of the placeholders that have a meaning for it.
function XW.TooltipText(v)
  local keys = {
    "xpbar.tip.level",
    "xpbar.tip.rested",
    "xpbar.tip.quests",
    "xpbar.tip.levelTime",
    "xpbar.tip.xph",
    "xpbar.tip.session",
  }
  local lines = {}
  for _, key in ipairs(keys) do
    if v.atMax and (key == "xpbar.tip.rested" or key == "xpbar.tip.quests") then
      key = nil
    end
    if key then
      lines[#lines + 1] = XL.Render(L[key], v)
    end
  end
  if v.atMax then
    lines[1] = L["xpbar.maxLevel"]
  end
  return table.concat(lines, "\n")
end

local function showTip(owner)
  ns.ShowTooltip(owner, L["xpbar.win.title"], XW.TooltipText(XT.Snapshot()))
end

-- Frame geometry -------------------------------------------------------------------------------------

local function frameDb()
  local frames = ns.db.frames
  if type(frames.xpbar) ~= "table" then
    frames.xpbar = {}
  end
  return frames.xpbar
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

-- The window is as big as the canvas, the scale of the frame multiplies it.
local function fit(f)
  local canvas = XW.Layout().canvas
  f:SetSize(canvas.w, canvas.h)
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

-- Whole percent values, so repeated changes never drift.
local function roundScale(s)
  return U.clamp(math.floor(s * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
end

-- Scale: the top left corner stays where it is.
local function applyScale(f, scale)
  local db = frameDb()
  db.scale = roundScale(scale)
  f:SetScale(db.scale)
  place(f)
end

local function changeScale(f, delta)
  savePosition(f)
  applyScale(f, scaleOf(frameDb()) + delta * SCALE_STEP)
end

-- The scale at which the bottom right corner of a w by h canvas lies under a cursor dx right of and dy
-- below the top left corner: the best fit of s * (w, h) to (dx, dy), so a slip on one axis stays calm.
function XW.ScaleFor(dx, dy, w, h)
  if not (finite(dx) and finite(dy) and finite(w) and finite(h)) or w <= 0 or h <= 0 then
    return 1
  end
  return roundScale((dx * w + dy * h) / (w * w + h * h))
end

-- Scale by pulling the grip: the cursor in the space of UIParent against the saved top left corner.
local function dragScale(f)
  local db, canvas = frameDb(), XW.Layout().canvas
  local cx, cy = GetCursorPosition()
  local ui = UIParent:GetEffectiveScale()
  if not (finite(cx) and finite(cy) and finite(ui) and ui > 0 and finite(db.x) and finite(db.y)) then
    return
  end
  applyScale(f, XW.ScaleFor(cx / ui - db.x, db.y - cy / ui, canvas.w, canvas.h))
end

-- Drawing --------------------------------------------------------------------------------------------

function XW.Repaint()
  if not (frame and frame:IsShown()) then
    return
  end
  local v = XT.Snapshot()
  CR.Draw(frame.canvas, XW.Layout(), XB.Types(), XW.Context(v))
  fit(frame)
  if frame.tip then
    ns.ShowTooltip(frame.hit, L["xpbar.win.title"], XW.TooltipText(v))
  end
end

-- The pin button, the edit button and the grip show on mouse-over (and while scaling) and only while
-- unpinned. They stay shown and turn transparent, so the mouse can pass from the bar onto them without a gap.
local function setChrome(f, on)
  local alpha = (on or f.scaling) and 1 or 0
  f.pin:SetAlpha(alpha)
  f.edit:SetAlpha(alpha)
  f.grip:SetAlpha(alpha)
end

local function applyPin(f)
  local pinned = XW.Config().pinned
  f:SetMovable(not pinned)
  f.pin:SetShown(not pinned)
  f.edit:SetShown(not pinned)
  f.grip:SetShown(not pinned)
  setChrome(f, false)
end

-- Everything a settings change can reach: pin, opacity, size and the picture.
function XW.Refresh()
  if not frame then
    return
  end
  applyPin(frame)
  frame:SetAlpha(XW.Config().alpha)
  XW.Repaint()
  place(frame)
end

-- Menu -------------------------------------------------------------------------------------------------

local function menuOpen()
  local layer = ns.Desktop.Layer
  return layer.current ~= nil and layer.current.owner == frame and menu ~= nil and menu:IsShown()
end

local function closeMenu()
  if menuOpen() then
    ns.Desktop.Layer.close("api")
  end
end

local function focusRow(step)
  local rows = menu.shown
  local index = 0
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
        local run, keep = r.run, r.keep
        if not keep then
          ns.Desktop.Layer.close("select")
        end
        if run then
          run()
        end
      end,
    })
    -- Icon in front, text left aligned behind it: every row starts its text at the same place.
    r.label:SetJustifyH("LEFT")
    menu.rows[i] = r
  end
  return r
end

-- Fills the popup with items { key | text, icon, run, keep } (keep: the menu stays open, run changes it).
-- An item without an icon keeps the gap, so the texts stay aligned. The text carries the meaning.
local function fill(items)
  menu.shown = {}
  for i, item in ipairs(items) do
    local r = row(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
    W.SetText(r.label, item.key, item.text)
    if item.icon then
      r:SetIcon(item.icon)
    end
    r.icon:SetShown(item.icon ~= nil)
    r.run, r.keep = item.run, item.keep
    r:Show()
    menu.shown[i] = r
  end
  for i = #items + 1, #menu.rows do
    menu.rows[i]:Hide()
  end
  menu:SetSize(MENU_W + 4, #items * MENU_ROW + 4)
end

local function mainItems()
  local running = XT.SessionState().running
  return {
    {
      key = running and "xpbar.menu.pause" or "xpbar.menu.resume",
      icon = running and "history" or "play",
      run = function()
        XT.TogglePause()
      end,
    },
    {
      key = "xpbar.menu.reset",
      icon = "reset",
      run = function()
        XT.ResetSession()
      end,
    },
    {
      key = "xpbar.menu.edit",
      icon = "pencil",
      run = function()
        XW.Edit()
      end,
    },
    {
      key = XW.Config().pinned and "xpbar.menu.unpin" or "xpbar.menu.pin",
      icon = "pin",
      run = function()
        XW.SetPinned(not XW.Config().pinned)
      end,
    },
    {
      key = "xpbar.menu.layout",
      icon = "palette",
      keep = true,
      run = function()
        XW.ShowLayoutMenu()
      end,
    },
    {
      key = "xpbar.menu.settings",
      icon = "gear",
      run = function()
        ns.Main.Show("xpbar")
      end,
    },
    {
      key = "xpbar.menu.close",
      icon = "close",
      run = function()
        XW.Hide()
      end,
    },
  }
end

function XW.ShowLayoutMenu()
  if not menuOpen() then
    return
  end
  menuMode = "layout"
  local items = {
    {
      key = "xpbar.menu.back",
      icon = "chevron-left",
      keep = true,
      run = function()
        menuMode = "main"
        fill(mainItems())
        ns.Focus.set(menu.shown[1])
      end,
    },
  }
  local current = XW.Config().layoutId
  for _, entry in ipairs(XW.Layouts()) do
    items[#items + 1] = {
      -- The chosen layout carries a marker in the text, not only a color.
      text = (entry.id == current and "> " or "  ") .. entry.name,
      icon = entry.id == current and "check" or nil,
      run = function()
        XW.SetLayout(entry.id)
      end,
    }
  end
  items[#items + 1] = {
    key = "xpbar.menu.newLayout",
    icon = "plus",
    run = function()
      local id, reason = XW.DuplicateLayout(current)
      if id then
        XW.SetLayout(id)
      else
        XW.Explain(reason)
      end
    end,
  }
  fill(items)
  ns.Focus.set(menu.shown[2] or menu.shown[1])
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

function XW.OpenMenu()
  if not frame then
    return
  end
  if menuOpen() then
    closeMenu()
    return
  end
  menu = menu or buildMenu()
  frame:Raise()
  menuMode = "main"
  fill(mainItems())
  ns.Desktop.Layer.open({ frames = { menu }, owner = frame, move = focusRow })
  ns.Desktop.Layer.place(menu, frame.hit, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  menu:Show()
  ns.Focus.set(menu.shown[1])
end

function XW.MenuMode()
  return menuOpen() and menuMode or nil
end

-- Window -----------------------------------------------------------------------------------------------

-- Three rows of dots in the bottom right corner, each light with a dark rim so it reads on any bar.
local function paintGrip(g)
  local lr, lg, lb = ns.Theme.rgb("text")
  local dr, dg, db = ns.Theme.rgb("bg")
  for _, dot in ipairs(g.dots) do
    dot.rim:SetColorTexture(dr, dg, db, 0.8)
    dot.light:SetColorTexture(lr, lg, lb, 1)
  end
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
    if not f.scaling then
      return
    end
    f.scaling = false
    g:SetScript("OnUpdate", nil)
    setChrome(f, f.hit:IsMouseOver() or g:IsMouseOver())
  end
  g:SetScript("OnEnter", function(self)
    setChrome(f, true)
    ns.ShowTooltip(self, L["xpbar.win.grip"], L["xpbar.win.gripTip"])
  end)
  g:SetScript("OnLeave", function()
    setChrome(f, false)
    ns.HideTooltip()
  end)
  g:SetScript(
    "OnMouseDown",
    ns.Wrap("xpbar-grip", function(_, button)
      f:Raise()
      if button ~= "LeftButton" or XW.Config().pinned then
        return
      end
      savePosition(f)
      f.scaling = true
      setChrome(f, true)
      ns.HideTooltip()
      g:SetScript(
        "OnUpdate",
        ns.Wrap("xpbar-grip", function()
          dragScale(f)
        end)
      )
    end)
  )
  g:SetScript("OnMouseUp", ns.Wrap("xpbar-grip", stop))
  g:SetScript("OnHide", stop)
  return g
end

local function create()
  local f = CreateFrame("Frame", "FGXpBarWindow", UIParent)
  -- Same strata as the main window and the game's panels, so a click raises exactly the clicked one and a
  -- higher strata would keep this window above them all.
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)

  f.canvas = CreateFrame("Frame", nil, f)
  f.canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  -- A plain frame over the canvas takes the mouse: a click opens the menu, a drag moves the window.
  f.hit = CreateFrame("Frame", nil, f)
  f.hit:SetAllPoints(f.canvas)
  f.hit:SetFrameLevel(f.canvas:GetFrameLevel() + 100)
  f.hit:EnableMouse(true)
  f.hit:EnableMouseWheel(true)
  f.hit:RegisterForDrag("LeftButton")
  f.hit:SetScript("OnMouseDown", function()
    f.dragged = false
    f:Raise()
  end)
  -- The release after a drag is no click.
  f.hit:SetScript(
    "OnMouseUp",
    ns.Wrap("xpbar-click", function(_, button)
      if f.dragged then
        f.dragged = false
      elseif button == "LeftButton" or button == "RightButton" then
        XW.OpenMenu()
      end
    end)
  )
  f.hit:SetScript(
    "OnDragStart",
    ns.Wrap("xpbar-move", function()
      if XW.Config().pinned then
        return
      end
      f.dragged, f.moving, f.tip = true, true, false
      ns.HideTooltip()
      f:StartMoving()
    end)
  )
  f.hit:SetScript(
    "OnDragStop",
    ns.Wrap("xpbar-move", function()
      if f.moving then
        f.moving = false
        f:StopMovingOrSizing()
        savePosition(f)
      end
    end)
  )
  f.hit:SetScript("OnEnter", function(self)
    f.tip = true
    setChrome(f, true)
    showTip(self)
  end)
  f.hit:SetScript("OnLeave", function()
    f.tip = false
    setChrome(f, false)
    ns.HideTooltip()
  end)
  f.hit:SetScript(
    "OnMouseWheel",
    ns.Wrap("xpbar-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )

  -- Pin button, top right of the bar: a plain action, seen on mouse-over while unpinned.
  f.pin = W.Action(f, { icon = "pin", size = PIN_SIZE, tooltip = "xpbar.win.pin", tooltipText = "xpbar.win.pinTip" })
  f.pin:SetPoint("TOPRIGHT", f.canvas, "TOPRIGHT", -2, -2)
  f.pin:SetFrameLevel(f.hit:GetFrameLevel() + 10)
  f.pin:SetScript(
    "OnClick",
    ns.Wrap("xpbar-pin", function()
      XW.SetPinned(not XW.Config().pinned)
    end)
  )
  f.pin:HookScript("OnEnter", function()
    setChrome(f, true)
  end)
  f.pin:HookScript("OnLeave", function()
    setChrome(f, false)
  end)
  f.pin:HookScript("OnMouseDown", function()
    f:Raise()
  end)

  -- Edit button next to the pin button: the same strip, the same hover rules.
  f.edit =
    W.Action(f, { icon = "pencil", size = PIN_SIZE, tooltip = "xpbar.win.edit", tooltipText = "xpbar.win.editTip" })
  f.edit:SetPoint("RIGHT", f.pin, "LEFT", -2, 0)
  f.edit:SetFrameLevel(f.hit:GetFrameLevel() + 10)
  f.edit:SetScript(
    "OnClick",
    ns.Wrap("xpbar-edit", function()
      XW.Edit()
    end)
  )
  f.edit:HookScript("OnEnter", function()
    setChrome(f, true)
  end)
  f.edit:HookScript("OnLeave", function()
    setChrome(f, false)
  end)
  f.edit:HookScript("OnMouseDown", function()
    f:Raise()
  end)

  -- Scale grip, bottom right: a plain frame with its own cursor tracking, no secure code involved.
  f.grip = buildGrip(f)

  f:SetScript(
    "OnShow",
    ns.Wrap("xpbar-show", function(self)
      if not auto then
        set("shown", true)
      end
      local elapsed = 0
      self:SetScript(
        "OnUpdate",
        ns.Wrap("xpbar-tick", function(_, dt)
          elapsed = elapsed + dt
          if elapsed >= TICK then
            elapsed = 0
            XW.Repaint()
          end
        end)
      )
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("xpbar-hide", function(self)
      self:SetScript("OnUpdate", nil)
      closeMenu()
      if not auto then
        set("shown", false)
        forced = false
      end
    end)
  )
  f:Hide()
  return f
end

function XW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function XW.Frame()
  return frame
end

-- What the player wants: open (true) or closed.
function XW.IsWanted()
  return ns.db ~= nil and XW.Config().shown
end

local function setVisible(on)
  if on == XW.IsShown() then
    return
  end
  auto = true
  local ok, err = pcall(function()
    if on then
      if not frame then
        frame = create()
      end
      frame:SetScale(scaleOf(frameDb()))
      frame:Show()
      frame:Raise()
      XW.Refresh()
    else
      frame:Hide()
    end
  end)
  auto = false
  if not ok then
    error(err, 0)
  end
end

-- Applies the open state and the rules of combat and maximum level to the current readings.
function XW.Apply()
  if not ns.db then
    return
  end
  local cfg = XW.Config()
  local show = cfg.shown
  if show and cfg.hideInCombat and inCombat then
    show = false
  end
  if show and not forced and not cfg.showAtMax and XT.Snapshot().atMax then
    show = false
  end
  setVisible(show)
end

function XW.Open()
  if not ns.db then
    return
  end
  forced = true
  set("shown", true)
  XW.Apply()
  if frame then
    frame:Raise()
  end
end

function XW.Hide()
  if not ns.db then
    return
  end
  forced = false
  set("shown", false)
  XW.Apply()
end

function XW.Toggle()
  if XW.IsWanted() then
    XW.Hide()
  else
    XW.Open()
  end
end

function XW.SetWanted(on)
  if on then
    XW.Open()
  else
    XW.Hide()
  end
end

function XW.SetPinned(on)
  on = on == true
  if on ~= XW.Config().pinned then
    set("pinned", on)
  end
end

function XW.Edit()
  local editor = ns.CanvasEditor
  if not (editor and editor.Open) then
    ns.Notify.send(L["xpbar.edit.missing"], "warning")
    return
  end
  XW.EnsureLayouts()
  local manager = XW.Manager()
  editor.Open({
    title = L["xpbar.edit.title"],
    layout = XW.Layout(),
    types = XB.Types(),
    presets = XB.Presets(),
    ctx = {
      values = function()
        return XT.Snapshot()
      end,
    },
    sample = XB.SampleValues,
    manager = manager,
    -- The editor may have switched the layout since it was opened: the result goes to the current one.
    onApply = function(layout)
      manager.save(manager.current(), layout)
    end,
  })
end

-- /fg erfahrung, /fg xp, /fg xpbar: no word toggles the window, the words below are handled here.
local function onOff(word)
  word = (word or ""):lower()
  if word == "on" or word == "an" or word == "1" then
    return true
  elseif word == "off" or word == "aus" or word == "0" then
    return false
  end
end

-- Channel words, English and German, to the keys of settings.xpBar.chat.
local CHAT_WORDS = {
  self = "self",
  selbst = "self",
  group = "group",
  gruppe = "group",
  guild = "guild",
  gilde = "guild",
  say = "say",
  sagen = "say",
}

-- `chat on|off` is the master switch, `chat <channel> on|off` one channel. Returns false for anything else.
local function chatCommand(arg)
  local on = onOff(arg)
  if on ~= nil then
    set("chatLevelUp", on)
    ns.Notify.chat(L[on and "xpbar.slash.chatOn" or "xpbar.slash.chatOff"])
    return true
  end
  local word, state = arg:match("^(%a+)%s+(%a+)$")
  local key = word and CHAT_WORDS[word:lower()]
  on = state and onOff(state)
  if not key or on == nil then
    return false
  end
  set("chat." .. key, on)
  ns.Notify.chat(
    string.format(L[on and "xpbar.slash.chatChannelOn" or "xpbar.slash.chatChannelOff"], L["xpbar.slash.chan." .. key])
  )
  if on and not XW.Config().chatLevelUp then
    ns.Notify.chat(L["xpbar.slash.chatMasterOff"])
  end
  return true
end

function XW.Slash(rest)
  local word, arg = tostring(rest or ""):match("^%s*(%a*)%s*(.-)%s*$")
  word = word:lower()
  if word == "" then
    XW.Toggle()
  elseif word == "pause" then
    ns.Notify.chat(L[XT.TogglePause() and "xpbar.slash.resumed" or "xpbar.slash.paused"])
  elseif word == "reset" then
    XT.ResetSession()
    ns.Notify.chat(L["xpbar.slash.reset"])
  elseif word == "edit" then
    XW.Edit()
  elseif word == "zeit" or word == "time" then
    local from, to = arg:match("^(%d+)%s+(%d+)$")
    if from then
      ns.Notify.chat(XT.LevelTimeReport(tonumber(from), tonumber(to)).text)
    else
      ns.Notify.chat(L["xpbar.slash.usage"])
    end
  elseif word == "chat" then
    if not chatCommand(arg) then
      ns.Notify.chat(L["xpbar.slash.usage"])
    end
  else
    ns.Notify.chat(L["xpbar.slash.usage"])
  end
end

-- Events ------------------------------------------------------------------------------------------------

XT.OnChange(function()
  if XW.IsWanted() then
    XW.Apply()
  end
  XW.Repaint()
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) ~= "string" then
    return
  end
  if path:find("^settings%.xpBar") then
    XW.Apply()
    XW.Refresh()
  end
end)
ns.On("PLAYER_REGEN_DISABLED", function()
  inCombat = true
  if XW.IsWanted() then
    XW.Apply()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  inCombat = false
  if XW.IsWanted() then
    XW.Apply()
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and XW.IsWanted() then
    XW.Apply()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
  end
end)

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it).
ns.KeyBindings.list[#ns.KeyBindings.list + 1] = { name = "FOREVERGUIDES_XPBAR", label = "binding.xpbar", fn = "XpBar" }
ns.KeyBindings.XpBar = function()
  ns.Safe("binding:XpBar", XW.Toggle)
end
