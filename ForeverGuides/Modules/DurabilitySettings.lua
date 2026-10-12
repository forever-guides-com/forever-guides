-- Settings section "Durability window" (Modules/DurabilityWindow.lua, DurabilityView.lua) on the Items
-- tab: show the window, the three limits of the colors, "only while a part is low" and the chat warning.
-- Every change goes through Store.set, the window and the warning follow at once through
-- FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store
local DL = ns.DurabilityLogic

local S = {}
ns.DurabilitySettings = S

ns.AddLocale("enUS", {
  ["dur.set.heading"] = "Durability window",
  ["dur.set.hint"] = "A window with the condition of your equipment: percent and bar per part, in combat too.\nThe colors change below the limits set here, the percent is always shown as text.",
  ["dur.set.show"] = "Show durability window",
  ["dur.set.showTip"] = "Opens or closes the window, same as the key binding and /fg durability.",
  ["dur.set.yellow"] = "Yellow below",
  ["dur.set.orange"] = "Orange below",
  ["dur.set.red"] = "Red below",
  ["dur.set.onlyBelow"] = "Only show while a part is low",
  ["dur.set.onlyBelowTip"] = "The window stays hidden until a part falls below the limit. Opening it by hand shows it until you close it.",
  ["dur.set.onlyBelowPct"] = "Show below",
  ["dur.set.warn"] = "Chat warning when a part gets low",
  ["dur.set.warnTip"] = "One chat line per part and drop, not during combat. It comes again after a repair and a new drop.",
  ["dur.set.warnPct"] = "Warn below",
})
ns.AddLocale("deDE", {
  ["dur.set.heading"] = "Haltbarkeits-Fenster",
  ["dur.set.hint"] = "Ein Fenster mit dem Zustand deiner Ausrüstung: Prozent und Balken je Teil, auch im Kampf.\nDie Farben wechseln unter den hier gesetzten Grenzen, der Prozentwert steht immer als Text da.",
  ["dur.set.show"] = "Haltbarkeits-Fenster anzeigen",
  ["dur.set.showTip"] = "Öffnet oder schließt das Fenster, wie die Tastenbelegung und /fg haltbarkeit.",
  ["dur.set.yellow"] = "Gelb unter",
  ["dur.set.orange"] = "Orange unter",
  ["dur.set.red"] = "Rot unter",
  ["dur.set.onlyBelow"] = "Nur anzeigen, wenn ein Teil niedrig ist",
  ["dur.set.onlyBelowTip"] = "Das Fenster bleibt verborgen, bis ein Teil unter die Grenze fällt. Öffnest du es von Hand, bleibt es bis zum Schließen sichtbar.",
  ["dur.set.onlyBelowPct"] = "Anzeigen unter",
  ["dur.set.warn"] = "Chat-Warnung, wenn ein Teil niedrig wird",
  ["dur.set.warnTip"] = "Eine Chat-Zeile je Teil und Unterschreitung, nie im Kampf. Nach einer Reparatur und einem neuen Abfall kommt sie wieder.",
  ["dur.set.warnPct"] = "Warnen unter",
})

local function percent(v)
  return string.format(ns.L["dur.fmt.percent"], math.floor(v + 0.5))
end

local function get(key)
  return ns.db.settings[key]
end

local function toggle(view, key, labelKey, tipKey, getter, setter)
  view.stack:Add(
    W.Toggle(view.content, {
      key = labelKey,
      get = getter or function()
        return get(key) == true
      end,
      set = setter or function(v)
        Store.set("settings." .. key, v == true)
      end,
      tooltip = labelKey,
      tooltipText = tipKey,
    }),
    { height = 24, gap = 6 }
  )
end

local function slider(view, labelKey, getter, setter)
  local s = W.Slider(view.content, {
    key = labelKey,
    min = 1,
    max = 99,
    step = 1,
    get = getter,
    set = setter,
    format = percent,
  })
  view.stack:Add(s, { height = 42, width = 320 })
  return s
end

-- The three color limits stay in falling order: the one that was moved wins, the others give way.
local LIMITS = {
  { key = "durabilityYellow", name = "yellow", label = "dur.set.yellow" },
  { key = "durabilityOrange", name = "orange", label = "dur.set.orange" },
  { key = "durabilityRed", name = "red", label = "dur.set.red" },
}

local function limitValues(prefer)
  local s = ns.db.settings
  return DL.Thresholds(s.durabilityYellow, s.durabilityOrange, s.durabilityRed, prefer)
end

function S.Add(view)
  ns.AddHeading(view, "dur.set.heading")
  ns.AddParagraph(view, "dur.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, nil, "dur.set.show", "dur.set.showTip", ns.DurabilityWindow.IsWanted, ns.DurabilityWindow.SetWanted)

  local sliders = {}
  for i, limit in ipairs(LIMITS) do
    sliders[i] = slider(view, limit.label, function()
      return (select(i, limitValues()))
    end, function(v)
      Store.set("settings." .. limit.key, v)
      local values = { limitValues(limit.name) }
      for j, other in ipairs(LIMITS) do
        if get(other.key) ~= values[j] then
          Store.set("settings." .. other.key, values[j])
        end
      end
      for _, sl in ipairs(sliders) do
        sl:Refresh()
      end
    end)
  end

  toggle(view, "durabilityOnlyBelow", "dur.set.onlyBelow", "dur.set.onlyBelowTip")
  slider(view, "dur.set.onlyBelowPct", function()
    return DL.CleanLimit(get("durabilityOnlyBelowPct"), DL.DEFAULTS.onlyBelow)
  end, function(v)
    Store.set("settings.durabilityOnlyBelowPct", DL.CleanLimit(v, DL.DEFAULTS.onlyBelow))
  end)

  toggle(view, "durabilityWarn", "dur.set.warn", "dur.set.warnTip")
  slider(view, "dur.set.warnPct", function()
    return DL.CleanLimit(get("durabilityWarnPct"), DL.DEFAULTS.warn)
  end, function(v)
    Store.set("settings.durabilityWarnPct", DL.CleanLimit(v, DL.DEFAULTS.warn))
  end)
end

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "bags")
