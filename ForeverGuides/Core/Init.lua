-- Startup order: SavedVariables ready (ADDON_LOADED) -> client ready
-- (PLAYER_LOGIN). Loads last so every module has registered by now.
local ADDON_NAME, ns = ...

ns.ProbeCapabilities()

ns.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then
    return
  end
  local ok, db, charDB = pcall(ns.Store.init, ForeverGuidesDB, ForeverGuidesCharDB)
  if not ok or type(db) ~= "table" or type(charDB) ~= "table" then
    print(ns.L["init.storefail"])
    return
  end
  ForeverGuidesDB, ForeverGuidesCharDB = db, charDB
  ns.db, ns.charDB = db, charDB
  ns.Errors.attach(ns.db.errors)
  ns.SetLocale(ns.db.settings.locale)
  ns.SubAddons.LoadAll()
end)

ns.On("PLAYER_LOGIN", function()
  -- Second probe: optional libraries may come from addons that loaded after us.
  ns.ProbeCapabilities()
  ns.MinimapButton.Init()
  ns.Dock.Restore()
  ns.Log.info("loaded %s", ns.version)
end)

-- Client language until SavedVariables are read.
ns.SetLocale("auto")
BINDING_HEADER_FOREVERGUIDES = "Forever Guides"
BINDING_NAME_FOREVERGUIDES_TOGGLE = ns.L["binding.toggle"]
BINDING_NAME_FOREVERGUIDES_SEARCH = ns.L["binding.search"]
BINDING_NAME_FOREVERGUIDES_DOCK = ns.L["binding.dock"]
BINDING_NAME_FOREVERGUIDES_SHOT = ns.L["binding.shot"]
for _, b in ipairs(ns.KeyBindings.list) do
  if b.fn then
    _G["BINDING_NAME_" .. b.name] = ns.L[b.label]
  end
end

-- Called from Bindings.xml.
function ns.BindingSearch()
  ns.Main.Show()
  -- Next frame, so the bound key is not typed into the box.
  C_Timer.After(0, function()
    ns.Main.search.edit:SetFocus()
  end)
end
