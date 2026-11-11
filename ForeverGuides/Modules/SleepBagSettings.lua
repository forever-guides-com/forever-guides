-- Settings card "Sleeping bag" (Modules/SleepBag.lua) in the feature Sleeping bag of the group Display:
-- the display on or off (off by default), the message when a run ends, the locked position. Every change goes
-- through Store.set, the display follows at once through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.SleepBagSettings = S

ns.AddLocale("enUS", {
  ["sleepbag.set.heading"] = "Sleeping bag",
  ["sleepbag.set.hint"] = "A small bar while you use the sleeping bag: the cast, the walk to the bag, then the stacks of Well Rested (one more for every minute of lying, up to 3) with the countdown to the next stack and how long the effect lasts. Standing up with one or two stacks keeps the bar until the effect ends, at 3 stacks it ends with standing up.",
  ["sleepbag.set.enable"] = "Show the sleeping bag display",
  ["sleepbag.set.enableTip"] = "Shows the bar from the moment you use the sleeping bag until you stand up (with one or two stacks until the effect ends). It works in combat too. Hover the bar for the details.",
  ["sleepbag.set.message"] = "Chat message when it ends",
  ["sleepbag.set.messageTip"] = "One short line with the lying time and the stacks, or a note when you got up before the first stack.",
  ["sleepbag.set.lock"] = "Lock the position",
  ["sleepbag.set.lockTip"] = "Without the lock you move the bar by dragging it.",
})
ns.AddLocale("deDE", {
  ["sleepbag.set.heading"] = "Schlafsack",
  ["sleepbag.set.hint"] = "Eine kleine Leiste beim Benutzen des Schlafsacks: das Ausrollen, der Weg zum Sack, danach die Stapel von Gut erholt (jede Minute im Liegen kommt einer dazu, höchstens 3) mit dem Countdown bis zum nächsten Stapel und der Dauer des Effekts. Wer mit ein oder zwei Stapeln aufsteht, behält die Leiste bis der Effekt endet, bei 3 Stapeln endet sie mit dem Aufstehen.",
  ["sleepbag.set.enable"] = "Schlafsack-Anzeige anzeigen",
  ["sleepbag.set.enableTip"] = "Zeigt die Leiste ab dem Benutzen des Schlafsacks, bis du aufstehst (mit ein oder zwei Stapeln bis der Effekt endet). Sie funktioniert auch im Kampf. Fahre mit der Maus über die Leiste für die Details.",
  ["sleepbag.set.message"] = "Chat-Meldung am Ende",
  ["sleepbag.set.messageTip"] = "Eine kurze Zeile mit der Liegedauer und den Stapeln, oder ein Hinweis, wenn du vor dem ersten Stapel aufgestanden bist.",
  ["sleepbag.set.lock"] = "Position sperren",
  ["sleepbag.set.lockTip"] = "Ohne Sperre verschiebst du die Leiste durch Ziehen.",
})

local function toggle(view, key, default, labelKey, tipKey)
  local t = W.Toggle(view.content, {
    key = labelKey,
    get = function()
      local value = ns.db.settings[key]
      if value == nil then
        return default
      end
      return value == true
    end,
    set = function(v)
      Store.set("settings." .. key, v == true)
    end,
    tooltip = labelKey,
    tooltipText = tipKey,
  })
  -- The id of the control for the search and the jumps: the last part of its label key.
  t.fgId = "sleepbag-" .. labelKey:match("[^.]+$")
  view.stack:Add(t, { height = 24, gap = 6 })
end

function S.Add(view)
  ns.AddHeading(view, "sleepbag.set.heading")
  ns.AddParagraph(view, "sleepbag.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "sleepBag", false, "sleepbag.set.enable", "sleepbag.set.enableTip")
  toggle(view, "sleepBagMessage", true, "sleepbag.set.message", "sleepbag.set.messageTip")
  toggle(view, "sleepBagLocked", false, "sleepbag.set.lock", "sleepbag.set.lockTip")
end

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "sleepbag", "sleepbag.main")
