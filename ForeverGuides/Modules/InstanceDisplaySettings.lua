-- Settings card "Instances: display" (feature Instances of the group World): the pin size of the dungeon
-- map and a button that clears the favorite instances. The values and the rules are in
-- Modules/InstanceDisplayLogic.lua; every change goes through it, so the views follow through
-- FG_SETTING_CHANGED.
local _, ns = ...
local W = ns.W

local S = {}
ns.InstanceDisplaySettings = S

local BUTTON_W = 200
local clearButton

ns.AddLocale("enUS", {
  ["instdisp.set.heading"] = "Instances: display",
  ["instdisp.set.hint"] = "The star on an instance card marks a favorite. The pin size applies to the dungeon map on the instances page and in the world map.",
  ["instdisp.set.pinScale"] = "Pin size on the dungeon map",
  ["instdisp.set.pinScaleTip"] = "Size of the boss, entrance and own pins on the dungeon map in percent of the normal size.",
  ["instdisp.set.clear"] = "Clear favorites",
  ["instdisp.set.clearTip"] = "Removes every favorite mark from the instance cards. Nothing else changes.",
})
ns.AddLocale("deDE", {
  ["instdisp.set.heading"] = "Instanzen: Darstellung",
  ["instdisp.set.hint"] = "Der Stern auf einer Instanzkarte markiert einen Favoriten. Die Pin-Größe gilt für die Dungeonkarte auf der Instanzen-Seite und in der Weltkarte.",
  ["instdisp.set.pinScale"] = "Pin-Größe auf der Dungeonkarte",
  ["instdisp.set.pinScaleTip"] = "Größe der Boss-, Eingangs- und eigenen Pins auf der Dungeonkarte in Prozent der normalen Größe.",
  ["instdisp.set.clear"] = "Favoriten entfernen",
  ["instdisp.set.clearTip"] = "Entfernt jede Favoritenmarkierung von den Instanzkarten. Sonst ändert sich nichts.",
})

local function percent(value)
  return string.format("%d %%", math.floor(value + 0.5))
end

function S.Add(view)
  local D = ns.InstanceDisplay
  ns.AddHeading(view, "instdisp.set.heading")
  ns.AddParagraph(view, "instdisp.set.hint", { role = "micro", color = "textMuted", gap = 6 })
  local slider = W.Slider(view.content, {
    key = "instdisp.set.pinScale",
    min = D.PIN_MIN,
    max = D.PIN_MAX,
    step = D.PIN_STEP,
    get = D.PinScale,
    set = function(value)
      D.SetPinScale(value)
    end,
    format = percent,
    tooltip = "instdisp.set.pinScale",
    tooltipText = "instdisp.set.pinScaleTip",
  })
  slider.fgId = "instdisp-pinScale"
  view.stack:Add(slider, { height = 42, width = 320, gap = 6 })

  local clear = W.Button(view.content, {
    key = "instdisp.set.clear",
    width = BUTTON_W,
    height = 26,
    tooltip = "instdisp.set.clear",
    tooltipText = "instdisp.set.clearTip",
    onClick = function()
      D.ClearFavorites()
    end,
  })
  clear.fgId = "instdisp-clear"
  view.stack:Add(clear, { height = 26, width = BUTTON_W, gap = 6 })
  clearButton = clear
  S.Refresh()
end

-- The button is only usable while there is a favorite to remove.
function S.Refresh()
  if not clearButton then
    return
  end
  if ns.InstanceDisplay.FavoriteCount() > 0 then
    clearButton:Enable()
  else
    clearButton:Disable()
  end
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.instanceFavorites" then
    S.Refresh()
  end
end)

ns.SettingsPage.Add(S.Add, "social", "instances.display")
