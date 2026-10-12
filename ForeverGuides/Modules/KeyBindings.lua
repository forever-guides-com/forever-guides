-- Key bindings for pages and windows. Bindings.xml calls ns.KeyBindings.<Name>();
-- no key is assigned by default, players set them in the game's key bindings
-- window. Page bindings toggle: the same key hides the main window again while
-- that page is showing. Everything here only shows or hides unprotected
-- frames, so it is safe in combat.
local _, ns = ...

local KB = {}
ns.KeyBindings = KB

local function currentPage()
  local current = ns.Router.current
  if current then
    return (ns.RouterClass.parse(current))
  end
end

local function togglePage(id)
  if ns.Main.IsShown() and currentPage() == id then
    ns.Main.Hide()
  else
    ns.Main.Show(id)
  end
end

-- Binding name, label locale key and handler, in the order shown in the
-- settings page. The four older bindings keep their own handlers in
-- Bindings.xml; they are listed here only so the settings page shows them.
KB.list = {
  { name = "FOREVERGUIDES_TOGGLE", label = "binding.toggle" },
  { name = "FOREVERGUIDES_SEARCH", label = "binding.search" },
  { name = "FOREVERGUIDES_DOCK", label = "binding.dock" },
  { name = "FOREVERGUIDES_SHOT", label = "binding.shot" },
  { name = "FOREVERGUIDES_NOTES", label = "binding.notes", fn = "Notes" },
  { name = "FOREVERGUIDES_NOTE_NEW", label = "binding.noteNew", fn = "NewNote" },
  { name = "FOREVERGUIDES_DRAWINGS", label = "binding.drawings", fn = "Drawings" },
  { name = "FOREVERGUIDES_DRAWING_NEW", label = "binding.drawingNew", fn = "NewDrawing" },
  { name = "FOREVERGUIDES_TALENTS", label = "binding.talents", fn = "Talents" },
  { name = "FOREVERGUIDES_LEVELS", label = "binding.levels", fn = "Levels" },
  { name = "FOREVERGUIDES_MAP", label = "binding.map", fn = "Map" },
  { name = "FOREVERGUIDES_ROUTE", label = "binding.route", fn = "Route" },
  { name = "FOREVERGUIDES_WEAPONS", label = "binding.weapons", fn = "Weapons" },
  { name = "FOREVERGUIDES_TRAINERS", label = "binding.trainers", fn = "Trainers" },
  { name = "FOREVERGUIDES_SHARE", label = "binding.share", fn = "Share" },
}

-- Errors land in the addon's error list instead of the game's error frame.
local function handler(name, fn)
  KB[name] = function()
    ns.Safe("binding:" .. name, fn)
  end
end

local function pageHandler(name, id)
  handler(name, function()
    togglePage(id)
  end)
end

pageHandler("Notes", "notes")
pageHandler("Drawings", "drawings")
pageHandler("Talents", "talents")
pageHandler("Levels", "levels")
pageHandler("Map", "map")
pageHandler("Weapons", "weapons")
pageHandler("Trainers", "trainers")

handler("NewNote", function()
  ns.NoteWindow.Slash("new")
end)

-- Same path as the "New drawing" button on the page, which owns the dialog.
handler("NewDrawing", function()
  ns.Main.Show("drawings")
  local ui = ns.DrawingsPage.ui
  if ui and ui.newBtn then
    ui.newBtn:Click()
  end
end)

handler("Route", function()
  ns.RouteBuilder.Toggle()
end)

handler("Share", function()
  ns.Share.Open("", nil)
end)

-- Current keys of a binding as display text, nil when unbound.
function KB.KeysText(name)
  local ok, key1, key2 = pcall(GetBindingKey, name)
  if not ok then
    return nil
  end
  local keys = {}
  for _, key in ipairs({ key1 or false, key2 or false }) do
    if key then
      local shown
      if GetBindingText then
        local okText, text = pcall(GetBindingText, key, "KEY_")
        shown = okText and text
      end
      keys[#keys + 1] = type(shown) == "string" and shown ~= "" and shown or key
    end
  end
  return #keys > 0 and table.concat(keys, ", ") or nil
end

-- Opens the game's key bindings window. Returns true when it is the key
-- bindings category itself, false when only the options window (or nothing)
-- could be shown.
function KB.OpenUI()
  -- Showing Blizzard's option panels in combat can raise ADDON_ACTION_BLOCKED.
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  local ok, direct = pcall(function()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
      Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
      return true
    end
    if not KeyBindingFrame and C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_BindingUI")
    end
    if KeyBindingFrame and ShowUIPanel then
      ShowUIPanel(KeyBindingFrame)
      return true
    end
    if SettingsPanel and ShowUIPanel then
      ShowUIPanel(SettingsPanel)
    end
    return false
  end)
  return ok and direct == true
end

ns.AddLocale("enUS", {
  ["binding.notes"] = "Notes page",
  ["binding.noteNew"] = "New note",
  ["binding.drawings"] = "Drawings page",
  ["binding.drawingNew"] = "New drawing",
  ["binding.talents"] = "Talent editor",
  ["binding.levels"] = "Learn list (level overview)",
  ["binding.map"] = "Map page",
  ["binding.route"] = "Route window",
  ["binding.weapons"] = "Weapon masters",
  ["binding.trainers"] = "Class trainers",
  ["binding.share"] = "Share dialog",
})
ns.AddLocale("deDE", {
  ["binding.notes"] = "Notizen-Seite",
  ["binding.noteNew"] = "Neue Notiz",
  ["binding.drawings"] = "Zeichnungen-Seite",
  ["binding.drawingNew"] = "Neue Zeichnung",
  ["binding.talents"] = "Talent-Editor",
  ["binding.levels"] = "Lernliste (Stufen-Übersicht)",
  ["binding.map"] = "Karten-Seite",
  ["binding.route"] = "Routen-Fenster",
  ["binding.weapons"] = "Waffenmeister",
  ["binding.trainers"] = "Klassenlehrer",
  ["binding.share"] = "Teilen-Dialog",
})
