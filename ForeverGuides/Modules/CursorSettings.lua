-- Settings card "Mouse cursor ring" (Modules/Cursor.lua) on the General tab: the switch, the layer, what the
-- ring does while the camera turns, when the ring is active, the layout with its buttons and the editor, and the
-- choices for this character only (a layout and on or off instead of the account's, with a note and a reset
-- while one applies). The page of the ring (Modules/CursorPage.lua) builds the same controls. Every change goes
-- through Store.set or Store.setChar, the ring follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, L, Store, CU, CS = ns.W, ns.L, ns.Store, ns.CursorLogic, ns.CharScopeLogic
-- The controls table of the editor, taken at load (a host may replace ns.CanvasEditor later).
local Controls = ns.CanvasEditor.Controls

local S = {}
ns.CursorSettings = S

ns.AddLocale("enUS", {
  ["cursor.set.heading"] = "Mouse cursor ring",
  ["cursor.set.hint"] = "A ring or shape that follows the mouse cursor. Choose a layout or draw your own in the layout editor.",
  ["cursor.set.enabled"] = "Show ring",
  ["cursor.set.enabledTip"] = "Switches the ring on or off, same as the key binding and /fg cursor. While it is off the add-on does nothing for it.",
  ["cursor.set.strata"] = "Layer",
  ["cursor.set.strataTip"] = "Which layer of the screen the ring is drawn in. Fullscreen (default) lies over the game windows and under menus, dialogs and tooltips, which therefore stay readable.",
  ["cursor.set.mouselook"] = "On camera turn",
  ["cursor.set.mouselookTip"] = "What the ring does while you turn the camera with the right mouse button.",
  ["cursor.set.load"] = "When active",
  ["cursor.set.layout"] = "Layout",
  ["cursor.set.edit"] = "Edit layout",
  ["cursor.set.reset"] = "Reset options",
  ["cursor.char.heading"] = "For this character",
  ["cursor.char.layout"] = "Layout for this character",
  ["cursor.char.layoutTip"] = "Shows this layout on this character, or on every character of its class (see the next choice). The layouts stay shared by the whole account.",
  ["cursor.char.scope"] = "Applies to",
  ["cursor.char.scopeTip"] = "Whether the layout above is used by this character only or by every character of the same class on the account. A choice for this character wins over a choice for the class.",
  ["cursor.char.scope.char"] = "This character only",
  ["cursor.char.scope.class"] = "Every character of this class",
  ["cursor.char.enabled"] = "Ring for this character",
  ["cursor.char.enabledTip"] = "Switches the ring on or off on this character only. Like the account follows the switch above. The key binding and /fg cursor switch the value that applies.",
  ["cursor.char.like"] = "Like the account (default)",
  ["cursor.char.on"] = "On",
  ["cursor.char.off"] = "Off",
  ["cursor.char.overridden"] = "Overridden for this character.",
  ["cursor.char.stale"] = "Overridden for this character. The layout chosen for it no longer exists, the account's layout applies.",
  ["cursor.char.reset"] = "Reset",
  ["cursor.char.resetTip"] = "Removes the layout and the switch of this character. The account's values apply again.",
  ["cursor.strata.BACKGROUND"] = "Background",
  ["cursor.strata.LOW"] = "Low",
  ["cursor.strata.MEDIUM"] = "Medium",
  ["cursor.strata.HIGH"] = "High",
  ["cursor.strata.DIALOG"] = "Dialog",
  ["cursor.strata.FULLSCREEN"] = "Fullscreen",
  ["cursor.strata.FULLSCREEN_DIALOG"] = "Fullscreen dialog",
  ["cursor.mouselook.hide"] = "Hide ring",
  ["cursor.mouselook.keep"] = "Keep at cursor",
  ["cursor.mouselook.center"] = "Screen center",
})
ns.AddLocale("deDE", {
  ["cursor.set.heading"] = "Mauszeiger-Ring",
  ["cursor.set.hint"] = "Ein Ring oder eine Form, die dem Mauszeiger folgt. Wähle ein Layout oder zeichne im Layout-Editor dein eigenes.",
  ["cursor.set.enabled"] = "Ring anzeigen",
  ["cursor.set.enabledTip"] = "Schaltet den Ring ein oder aus, wie die Tastenbelegung und /fg mauszeiger. Solange er aus ist, tut das Addon dafür nichts.",
  ["cursor.set.strata"] = "Ebene",
  ["cursor.set.strataTip"] = "In welcher Ebene des Bildschirms der Ring gezeichnet wird. Vollbild (Standard) liegt über den Spielfenstern und unter Menüs, Dialogen und Tooltips, die dadurch lesbar bleiben.",
  ["cursor.set.mouselook"] = "Beim Kameradrehen",
  ["cursor.set.mouselookTip"] = "Was der Ring tut, solange du die Kamera mit der rechten Maustaste drehst.",
  ["cursor.set.load"] = "Wann aktiv",
  ["cursor.set.layout"] = "Layout",
  ["cursor.set.edit"] = "Layout bearbeiten",
  ["cursor.set.reset"] = "Optionen zurücksetzen",
  ["cursor.char.heading"] = "Für diesen Charakter",
  ["cursor.char.layout"] = "Layout für diesen Charakter",
  ["cursor.char.layoutTip"] = "Zeigt dieses Layout auf diesem Charakter oder auf allen Charakteren seiner Klasse (siehe nächste Auswahl). Die Layouts bleiben für den ganzen Account gemeinsam.",
  ["cursor.char.scope"] = "Gilt für",
  ["cursor.char.scopeTip"] = "Ob das Layout oben nur dieser Charakter nutzt oder alle Charaktere derselben Klasse auf dem Account. Eine Wahl für diesen Charakter schlägt die Wahl für die Klasse.",
  ["cursor.char.scope.char"] = "Nur dieser Charakter",
  ["cursor.char.scope.class"] = "Alle Charaktere dieser Klasse",
  ["cursor.char.enabled"] = "Ring für diesen Charakter",
  ["cursor.char.enabledTip"] = "Schaltet den Ring nur auf diesem Charakter ein oder aus. Wie Account folgt dem Schalter oben. Die Tastenbelegung und /fg mauszeiger schalten den Wert, der gerade gilt.",
  ["cursor.char.like"] = "Wie Account (Standard)",
  ["cursor.char.on"] = "An",
  ["cursor.char.off"] = "Aus",
  ["cursor.char.overridden"] = "Für diesen Charakter überschrieben.",
  ["cursor.char.stale"] = "Für diesen Charakter überschrieben. Das gewählte Layout gibt es nicht mehr, es gilt das Layout des Accounts.",
  ["cursor.char.reset"] = "Zurücksetzen",
  ["cursor.char.resetTip"] = "Entfernt Layout und Schalter dieses Charakters. Es gelten wieder die Werte des Accounts.",
  ["cursor.strata.BACKGROUND"] = "Hintergrund",
  ["cursor.strata.LOW"] = "Niedrig",
  ["cursor.strata.MEDIUM"] = "Mittel",
  ["cursor.strata.HIGH"] = "Hoch",
  ["cursor.strata.DIALOG"] = "Dialog",
  ["cursor.strata.FULLSCREEN"] = "Vollbild",
  ["cursor.strata.FULLSCREEN_DIALOG"] = "Vollbild-Dialog",
  ["cursor.mouselook.hide"] = "Ring ausblenden",
  ["cursor.mouselook.keep"] = "Am Zeiger lassen",
  ["cursor.mouselook.center"] = "Bildschirmmitte",
})

-- The card and the page build the same controls, so every built control is kept (weakly) and repainted
-- when a setting changes, whoever changed it.
S.controls = setmetatable({}, { __mode = "k" })

local function keep(control)
  S.controls[control] = true
  return control
end

local function toggle(view, labelKey, tipKey, get, set)
  view.stack:Add(
    keep(W.Toggle(view.content, {
      key = labelKey,
      get = get,
      set = set,
      tooltip = labelKey,
      tooltipText = tipKey,
    })),
    { height = 24, gap = 6 }
  )
end

local function choice(view, key, options, get, set, tip)
  local dropdown = keep(
    W.Dropdown(
      view.content,
      { key = key, width = 240, options = options, get = get, set = set, tooltip = tip and key, tooltipText = tip }
    )
  )
  view.stack:Add(dropdown, { height = 46, width = 240 })
end

local function listOf(values, prefix)
  local out = {}
  for i, value in ipairs(values) do
    out[i] = { value = value, key = prefix .. value }
  end
  return out
end

-- The choices for this character: its own layout and on/off, and while one applies a note and the reset.
local function addCharacter(view)
  local C = ns.Cursor
  ns.AddHeading(view, "cursor.char.heading", { role = "ui", gap = 4 })
  local layoutOptions = { { value = "", key = "cursor.char.like" } }
  -- The scope picked while no layout is assigned yet; an assigned layout shows its own.
  local picked = "char"
  local function assigned()
    local cfg = C.Config()
    return cfg.layoutSource ~= "account" and cfg.layoutId or nil, cfg.layoutSource
  end
  choice(view, "cursor.char.layout", layoutOptions, function()
    for i = #layoutOptions, 2, -1 do
      layoutOptions[i] = nil
    end
    for _, entry in ipairs(C.Layouts()) do
      layoutOptions[#layoutOptions + 1] = { value = entry.id, text = entry.name }
    end
    return assigned() or ""
  end, function(v)
    local current = assigned()
    if v == "" then
      if current then
        C.Assign(current, nil)
      end
      -- A class entry of this class that sits behind a character override goes too: "like the account".
      local layout = C.Config().layoutId
      if C.Config().layoutSource == "class" then
        C.Assign(layout, nil)
      end
    else
      C.Assign(v, picked)
    end
  end, "cursor.char.layoutTip")
  choice(view, "cursor.char.scope", {
    { value = "char", key = "cursor.char.scope.char" },
    { value = "class", key = "cursor.char.scope.class" },
  }, function()
    local id, source = assigned()
    return id and source or picked
  end, function(v)
    picked = v
    local id = assigned()
    if id then
      C.Assign(id, v)
    end
  end, "cursor.char.scopeTip")
  local enabledOptions = {
    { value = "account", key = "cursor.char.like" },
    { value = "on", key = "cursor.char.on" },
    { value = "off", key = "cursor.char.off" },
  }
  choice(view, "cursor.char.enabled", enabledOptions, function()
    local node = ns.charDB and ns.charDB.cursorRing
    local v = CS.CleanEnabled(type(node) == "table" and node.enabled or nil)
    return v == true and "on" or v == false and "off" or "account"
  end, function(v)
    if v == "on" then
      C.SetEnabledOverride(true)
    elseif v == "off" then
      C.SetEnabledOverride(false)
    else
      C.SetEnabledOverride(nil)
    end
  end, "cursor.char.enabledTip")

  -- The note and the reset button take room only while this character overrides something.
  local note = CreateFrame("Frame", nil, view.content)
  note.text = W.Text(note, { text = "", role = "small", color = "warning", wrap = true })
  note.reset = W.Button(note, {
    key = "cursor.char.reset",
    width = 140,
    tooltip = "cursor.char.reset",
    tooltipText = "cursor.char.resetTip",
    onClick = C.ResetOverride,
  })
  function note:fgGridLayout(width)
    note.text:ClearAllPoints()
    note.text:SetPoint("TOPLEFT", note, "TOPLEFT", 0, 0)
    note.text:SetWidth(width)
    local h = math.ceil(note.text:GetStringHeight()) + 6
    note.reset:ClearAllPoints()
    note.reset:SetPoint("TOPLEFT", note, "TOPLEFT", 0, -h)
    note.reset:SetSize(math.min(note.reset:FullWidth(), width), 26)
    note:SetHeight(h + 26)
    return h + 26
  end
  local shownBefore
  function note.Refresh()
    local on = C.HasOverride()
    W.SetText(note.text, nil, L[C.Config().layoutStale and "cursor.char.stale" or "cursor.char.overridden"])
    note:SetShown(on)
    if shownBefore ~= nil and shownBefore ~= on and type(view.Layout) == "function" then
      view:Layout()
    end
    shownBefore = on
  end
  keep(note)
  note.Refresh()
  view.stack:Add(note, { gap = 10 })
end

-- Builds the controls into a page view. opts.page: the page has its own title and intro, so the heading and
-- the hint of the card are left out.
function S.Add(view, opts)
  local C = ns.Cursor
  if not (opts and opts.page) then
    ns.AddHeading(view, "cursor.set.heading")
    ns.AddParagraph(view, "cursor.set.hint", { role = "micro", color = "textMuted" })
  end
  toggle(view, "cursor.set.enabled", "cursor.set.enabledTip", function()
    return C.Config().accountEnabled
  end, C.SetAccountEnabled)
  choice(view, "cursor.set.strata", listOf(CU.STRATA, "cursor.strata."), function()
    return C.Config().strata
  end, function(v)
    Store.set("settings.cursorRing.strata", v)
  end)
  choice(view, "cursor.set.mouselook", listOf(CU.MOUSELOOK, "cursor.mouselook."), function()
    return C.Config().mouselook
  end, function(v)
    Store.set("settings.cursorRing.mouselook", v)
  end)
  ns.AddHeading(view, "cursor.set.load", { role = "ui", gap = 4 })
  view.stack:Add(
    keep(Controls.LoadPanel(view.content, {
      get = function()
        return C.Config().load
      end,
      set = function(load)
        Store.set("settings.cursorRing.load", load)
      end,
      onResize = function()
        if type(view.Layout) == "function" then
          view:Layout()
        end
      end,
    })),
    { gap = 10 }
  )
  -- The game's own swing bars double the swing timer element: say so where the ring is set up.
  local timers = ns.CursorTimers
  if type(timers) == "table" and type(timers.SwingHint) == "function" and timers.SwingHint() ~= nil then
    ns.AddParagraph(view, "cursor.timers.swingNative", { role = "micro", color = "textMuted" })
  end

  -- The list is refilled in place on every read: layouts come and go while the card is open.
  local options = {}
  choice(view, "cursor.set.layout", options, function()
    for i = #options, 1, -1 do
      options[i] = nil
    end
    for _, entry in ipairs(C.Layouts()) do
      options[#options + 1] = { value = entry.id, text = entry.name }
    end
    return C.Config().accountLayoutId
  end, C.SetAccountLayout)
  view.stack:Add(
    ns.LayoutSet.BuildButtons(view.content, C.LayoutSet),
    { height = ns.LayoutSet.BUTTONS_H, width = ns.LayoutSet.BUTTONS_W, gap = 8 }
  )
  view.stack:Add(
    W.Button(view.content, { key = "cursor.set.edit", width = 190, opens = true, onClick = C.Edit }),
    { height = 26, width = 190, gap = 8 }
  )
  view.stack:Add(
    W.Button(view.content, { key = "cursor.set.reset", width = 240, onClick = C.ResetOptions }),
    { height = 26, width = 240, gap = 16 }
  )
  addCharacter(view)
end

ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if type(path) ~= "string" then
    return
  end
  local mine = scope == "char" and path:find("^cursorRing") or path:find("^settings%.cursorRing")
  if mine then
    for control in pairs(S.controls) do
      control.Refresh()
    end
  end
end)

ns.SettingsPage.Add(S.Add, "general")
