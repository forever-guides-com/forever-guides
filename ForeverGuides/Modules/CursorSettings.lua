-- Settings card "Mouse cursor ring" (Modules/Cursor.lua) on the General tab: the switch, the layer, what the
-- ring does while the camera turns, the yes/no rules, the layout with its buttons and the editor. The page
-- of the ring (Modules/CursorPage.lua) builds the same controls. Every change goes through Store.set, the
-- ring follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store, CU = ns.W, ns.Store, ns.CursorLogic

local S = {}
ns.CursorSettings = S

ns.AddLocale("enUS", {
  ["cursor.set.heading"] = "Mouse cursor ring",
  ["cursor.set.hint"] = "A ring or shape that follows the mouse cursor. Choose a layout or draw your own in the layout editor.",
  ["cursor.set.enabled"] = "Show ring",
  ["cursor.set.enabledTip"] = "Switches the ring on or off, same as the key binding and /fg cursor. While it is off the add-on does nothing for it.",
  ["cursor.set.strata"] = "Layer",
  ["cursor.set.strataTip"] = "Which layer of the screen the ring is drawn in. Tooltip is the top layer.",
  ["cursor.set.mouselook"] = "On camera turn",
  ["cursor.set.mouselookTip"] = "What the ring does while you turn the camera with the right mouse button.",
  ["cursor.set.combat"] = "Only in combat",
  ["cursor.set.instance"] = "Only in instances",
  ["cursor.set.target"] = "Only with target",
  ["cursor.set.mounted"] = "Hide when mounted",
  ["cursor.set.vehicle"] = "Hide in vehicles",
  ["cursor.set.layout"] = "Layout",
  ["cursor.set.edit"] = "Edit layout",
  ["cursor.set.reset"] = "Reset options",
  ["cursor.strata.BACKGROUND"] = "Background",
  ["cursor.strata.LOW"] = "Low",
  ["cursor.strata.MEDIUM"] = "Medium",
  ["cursor.strata.HIGH"] = "High",
  ["cursor.strata.DIALOG"] = "Dialog",
  ["cursor.strata.FULLSCREEN"] = "Fullscreen",
  ["cursor.strata.FULLSCREEN_DIALOG"] = "Fullscreen dialog",
  ["cursor.strata.TOOLTIP"] = "Tooltip (top)",
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
  ["cursor.set.strataTip"] = "In welcher Ebene des Bildschirms der Ring gezeichnet wird. Tooltip ist die oberste Ebene.",
  ["cursor.set.mouselook"] = "Beim Kameradrehen",
  ["cursor.set.mouselookTip"] = "Was der Ring tut, solange du die Kamera mit der rechten Maustaste drehst.",
  ["cursor.set.combat"] = "Nur im Kampf",
  ["cursor.set.instance"] = "Nur in Instanzen",
  ["cursor.set.target"] = "Nur mit Ziel",
  ["cursor.set.mounted"] = "Beim Reiten aus",
  ["cursor.set.vehicle"] = "In Fahrzeugen aus",
  ["cursor.set.layout"] = "Layout",
  ["cursor.set.edit"] = "Layout bearbeiten",
  ["cursor.set.reset"] = "Optionen zurücksetzen",
  ["cursor.strata.BACKGROUND"] = "Hintergrund",
  ["cursor.strata.LOW"] = "Niedrig",
  ["cursor.strata.MEDIUM"] = "Mittel",
  ["cursor.strata.HIGH"] = "Hoch",
  ["cursor.strata.DIALOG"] = "Dialog",
  ["cursor.strata.FULLSCREEN"] = "Vollbild",
  ["cursor.strata.FULLSCREEN_DIALOG"] = "Vollbild-Dialog",
  ["cursor.strata.TOOLTIP"] = "Tooltip (oben)",
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

-- A toggle on one flag of settings.cursorRing; the ring repairs the value through Config().
local function flag(view, key, labelKey, tipKey)
  toggle(view, labelKey, tipKey, function()
    return ns.Cursor.Config()[key] == true
  end, function(v)
    Store.set("settings.cursorRing." .. key, v == true)
  end)
end

local function choice(view, key, options, get, set)
  local dropdown = keep(W.Dropdown(view.content, { key = key, width = 240, options = options, get = get, set = set }))
  view.stack:Add(dropdown, { height = 46, width = 240 })
end

local function listOf(values, prefix)
  local out = {}
  for i, value in ipairs(values) do
    out[i] = { value = value, key = prefix .. value }
  end
  return out
end

-- Builds the controls into a page view. opts.page: the page has its own title and intro, so the heading and
-- the hint of the card are left out.
function S.Add(view, opts)
  local C = ns.Cursor
  if not (opts and opts.page) then
    ns.AddHeading(view, "cursor.set.heading")
    ns.AddParagraph(view, "cursor.set.hint", { role = "micro", color = "textMuted" })
  end
  toggle(view, "cursor.set.enabled", "cursor.set.enabledTip", C.IsEnabled, C.SetEnabled)
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
  flag(view, "combatOnly", "cursor.set.combat")
  flag(view, "instanceOnly", "cursor.set.instance")
  flag(view, "needsTarget", "cursor.set.target")
  flag(view, "hideMounted", "cursor.set.mounted")
  flag(view, "hideInVehicle", "cursor.set.vehicle")
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
    return C.Config().layoutId
  end, C.SetLayout)
  view.stack:Add(
    ns.LayoutSet.BuildButtons(view.content, C.LayoutSet),
    { height = ns.LayoutSet.BUTTONS_H, width = ns.LayoutSet.BUTTONS_W, gap = 8 }
  )
  view.stack:Add(
    W.Button(view.content, { key = "cursor.set.edit", width = 170, onClick = C.Edit }),
    { height = 26, width = 170, gap = 8 }
  )
  view.stack:Add(
    W.Button(view.content, { key = "cursor.set.reset", width = 240, onClick = C.ResetOptions }),
    { height = 26, width = 240 }
  )
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.cursorRing") then
    for control in pairs(S.controls) do
      control.Refresh()
    end
  end
end)

ns.SettingsPage.Add(S.Add, "general")
