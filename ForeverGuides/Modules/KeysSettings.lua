-- Settings card "Key combinations" (tab General): one row per action of the registry in Core/Keys.lua
-- with a list of the allowed combinations, a line of description and a reset. Actions that share a
-- combination at the same place are marked in both rows, nothing is blocked. The keys that open the
-- addon, the search, the dock and the screenshot are the game's own key bindings (card above).
local _, ns = ...
local W, K = ns.W, ns.Keys

local KS = {}
ns.KeysSettings = KS

ns.AddLocale("enUS", {
  ["keys.set.heading"] = "Key combinations",
  ["keys.set.hint"] = "Mouse actions with a modifier key. Editor shortcuts such as Ctrl+C, Ctrl+Z or Shift+Tab stay as they are. Keys that open the addon, search, dock and screenshot are in the card Key bindings.",
  ["keys.set.resetOne"] = "Reset to default",
  ["keys.set.resetAll"] = "Reset all",
  ["keys.set.resetAllTip"] = "Sets every key combination back to its default",
  ["keys.set.resetAllTitle"] = "Reset key combinations",
  ["keys.set.resetAllText"] = "All key combinations go back to their defaults. Continue?",
  ["keys.set.conflict"] = "Same combination as: %s",
})
ns.AddLocale("deDE", {
  ["keys.set.heading"] = "Tastenkombinationen",
  ["keys.set.hint"] = "Mausaktionen mit Zusatztaste. Editor-Kürzel wie Strg+C, Strg+Z oder Umschalt+Tab bleiben fest. Tasten für Addon öffnen, Suche, Dock und Screenshot stehen in der Karte Tastenbelegung.",
  ["keys.set.resetOne"] = "Auf Standard zurücksetzen",
  ["keys.set.resetAll"] = "Alle zurücksetzen",
  ["keys.set.resetAllTip"] = "Setzt jede Tastenkombination auf den Standard zurück",
  ["keys.set.resetAllTitle"] = "Tastenkombinationen zurücksetzen",
  ["keys.set.resetAllText"] = "Alle Tastenkombinationen gehen auf ihren Standard zurück. Fortfahren?",
  ["keys.set.conflict"] = "Gleiche Belegung wie: %s",
})

local FIELD_WIDTH = 210
local RESET_SIZE = 24

local function options(id)
  local out = {}
  for _, combo in ipairs(K.Options(id)) do
    out[#out + 1] = { value = combo, key = "keys.combo." .. combo }
  end
  return out
end

-- Names of the other actions that use the same combination at the same place.
local function conflictNames(id)
  local names = {}
  for _, other in ipairs(K.ConflictsOf(id)) do
    names[#names + 1] = ns.L["keys.name." .. other]
  end
  return table.concat(names, ", ")
end

-- One row: list, reset, description and the conflict line. Returns the row with paint().
local function addRow(view, id, onChange)
  local row = { id = id }
  local dd = W.Dropdown(view.content, {
    key = "keys.name." .. id,
    width = FIELD_WIDTH,
    options = options(id),
    get = function()
      return K.Get(id)
    end,
    set = function(value)
      K.Set(id, value)
      onChange()
    end,
  })
  dd.fgId = "keys-" .. id
  row.dropdown = dd
  row.reset = W.Action(dd, {
    icon = "reset",
    size = RESET_SIZE,
    tooltip = "keys.set.resetOne",
    tooltipText = "keys.name." .. id,
    onClick = function()
      K.Reset(id)
      onChange()
    end,
  })
  row.reset.fgId = "keys-reset-" .. id
  row.reset:SetPoint("TOPLEFT", dd, "TOPLEFT", FIELD_WIDTH + 8, -W.DROPDOWN_FIELD_Y)
  view.stack:Add(dd, { height = 46, width = FIELD_WIDTH + 8 + RESET_SIZE, gap = 2 })
  ns.AddParagraph(view, "keys.desc." .. id, { role = "micro", color = "textMuted", gap = 6 })
  row.conflict = W.Text(view.content, { role = "micro", color = "warning", wrap = true })
  row.conflict:Hide()
  view.stack:Add(row.conflict, { gap = 6 })

  local baseRefresh = dd.Refresh
  -- Returns true when the conflict line appeared or went away (the card needs a new layout).
  function row.paint()
    if baseRefresh then
      baseRefresh()
    end
    local names = conflictNames(id)
    local clash = names ~= ""
    local changed = clash ~= row.conflict:IsShown()
    W.SetColor(dd.label, clash and "warning" or "text")
    row.conflict:SetText(clash and string.format(ns.L["keys.set.conflict"], names) or "")
    row.conflict:SetShown(clash)
    row.reset:SetShown(not K.IsDefault(id))
    return changed
  end
  dd.Refresh = row.paint
  return row
end

-- Fills a card: heading, hint, rows grouped by area, reset of all.
function KS.Add(view)
  ns.AddHeading(view, "keys.set.heading")
  ns.AddParagraph(view, "keys.set.hint", { role = "micro", color = "textMuted" })
  local rows = {}
  local function repaint()
    -- The texts of other cards name the combinations too.
    ns.RefreshUI()
    local changed = false
    for _, row in ipairs(rows) do
      changed = row.paint() or changed
    end
    if changed and view.Layout then
      view:Layout()
    end
  end
  local area
  for _, id in ipairs(K.List()) do
    local def = K.Def(id)
    if def.area ~= area then
      area = def.area
      view.stack:Add(
        W.Text(view.content, { key = "keys.area." .. area, role = "ui", color = "accent2", wrap = true }),
        { gap = 4 }
      )
    end
    rows[#rows + 1] = addRow(view, id, repaint)
  end
  for _, row in ipairs(rows) do
    row.paint()
  end
  local all = W.Action(view.content, {
    label = "keys.set.resetAll",
    icon = "reset",
    tooltip = "keys.set.resetAll",
    tooltipText = "keys.set.resetAllTip",
    width = 220,
    height = 28,
    onClick = function()
      ns.Dialogs.Confirm("keys.set.resetAllTitle", "keys.set.resetAllText", function()
        K.ResetAll()
        repaint()
      end)
    end,
  })
  all.fgId = "keys-reset-all"
  view.stack:Add(all, { height = 28, width = 220 })
end
