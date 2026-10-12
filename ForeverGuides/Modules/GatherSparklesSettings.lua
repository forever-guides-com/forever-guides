-- Settings card "Highlight gathering spots" (Modules/GatherSparkles.lua) on the map tab: main switch,
-- one switch per kind of object, locked nodes, the quest item glitter, the game icons, the effect style and the notes on range and
-- on the graphics settings. Changes go through Store.set, the module listens to FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.GatherSparklesSettings = S

ns.AddLocale("enUS", {
  ["sparkles.set.heading"] = "Highlight gathering spots",
  ["sparkles.set.hint"] = "Ore and herbs glitter when you get close. This needs the soft targeting of the game: the switch sets it up and puts your own settings back when it goes off.",
  ["sparkles.set.enabled"] = "Gathering spots glitter",
  ["sparkles.set.ore"] = "Ore veins",
  ["sparkles.set.herbs"] = "Herbs",
  ["sparkles.set.quest"] = "Quest objects",
  ["sparkles.set.questHint"] = 'Adds our own sparkle effect for quest objects as you approach. Rarely needed: the game glitter of the switch "Quest items glitter" below already marks them.',
  ["sparkles.set.lockedNodes"] = "Show without the profession",
  ["sparkles.set.lockedNodesHint"] = "Shows ore and herbs even when you lack the profession, in gray light.",
  ["sparkles.set.gameIcons"] = "Show the interaction icons of the game",
  ["sparkles.set.gameIconsHint"] = "The icon over plants, ore and objects is drawn by the game, not by this addon. Off hides it while gathering sparkles are on.",
  ["sparkles.set.questItems"] = "Quest items glitter (graphics setting)",
  ["sparkles.set.questItemsHint"] = "Turns on the built-in glitter of the game on lootable quest items. The game does not show it by itself, the addon unlocks it through the graphics setting (outline mode off).",
  ["sparkles.set.style"] = "Effect style",
  ["sparkles.set.styleTip"] = "The original model may draw nothing at the target. Then switch back to automatic.",
  ["sparkles.style.auto"] = "Automatic",
  ["sparkles.style.original"] = "Original model (experimental)",
  ["sparkles.style.particles"] = "Own particles",
  ["sparkles.set.offsetY"] = "Effect height below the icon",
  ["sparkles.set.offsetYHint"] = "Moves the effect down from the icon of the game onto the object. Stand in front of a plant and drag until the sparkles sit on it.",
  ["sparkles.set.size"] = "Particle size",
  ["sparkles.set.sizeHint"] = "Scales the sparks, the glow and the dark layer behind them together. The number of sparks stays.",
  ["sparkles.set.range"] = "Detection range (yards)",
  ["sparkles.set.rangeHint"] = "How far the game looks for objects. The game offers objects up to %d yards at most (measured in the Forever client). A smaller value shows the effect only closer to the object. The game only offers objects the camera looks at. The effect is dimmed out of reach and gray when your skill is too low.",
  ["sparkles.set.rangeMax"] = "Maximum",
  ["sparkles.set.rangeTip"] = "At 0 yards objects are only offered right at your character.",
  ["sparkles.set.measureNone"] = "No measurement yet. Walk toward an ore until you reach it.",
  ["sparkles.set.measureLine"] = "Measured detection: last %d yards, at most %d, on average %d (%d measurements).",
  ["sparkles.set.measureLineOne"] = "Measured detection: last %d yards, at most %d, on average %d (%d measurement).",
  ["sparkles.set.measureHint"] = "Measures from the spot where the game first offers an object to the spot where you reach it. Start from afar and walk straight toward it with the camera on it. The value is a few yards below the real distance. No coordinates are stored, only distances.",
  ["sparkles.set.measureReset"] = "Reset measurement",
  ["sparkles.set.measureChat"] = "Show measurements in chat",
  ["sparkles.set.measureChatHint"] = "Prints one line in chat for every finished measurement.",
  ["sparkles.set.restore"] = "Switching off puts your graphics and targeting settings back. The restoration is complete after a full restart of the game.",
})
ns.AddLocale("deDE", {
  ["sparkles.set.heading"] = "Sammelpunkte hervorheben",
  ["sparkles.set.hint"] = "Erz und Kräuter funkeln, wenn du dich näherst. Das braucht das Soft-Targeting des Spiels: Der Schalter richtet es ein und stellt deine eigenen Einstellungen beim Ausschalten wieder her.",
  ["sparkles.set.enabled"] = "Sammelpunkte funkeln",
  ["sparkles.set.ore"] = "Erzadern",
  ["sparkles.set.herbs"] = "Kräuter",
  ["sparkles.set.quest"] = "Questobjekte",
  ["sparkles.set.questHint"] = 'Fügt unseren eigenen Funkel-Effekt für Questobjekte beim Annähern hinzu. Meist unnötig: Das Spiel-Glitzern des Schalters "Quest-Items funkeln" darunter markiert sie schon.',
  ["sparkles.set.lockedNodes"] = "Auch ohne den Beruf anzeigen",
  ["sparkles.set.lockedNodesHint"] = "Zeigt Erz und Kräuter auch dann, wenn dir der Beruf fehlt, in grauem Licht.",
  ["sparkles.set.gameIcons"] = "Interaktions-Symbole des Spiels anzeigen",
  ["sparkles.set.gameIconsHint"] = "Das Symbol über Pflanzen, Erzen und Objekten zeichnet das Spiel selbst, nicht dieses Addon. Aus blendet es aus, solange Sammelpunkte funkeln eingeschaltet ist.",
  ["sparkles.set.questItems"] = "Quest-Items funkeln (Grafik-Einstellung)",
  ["sparkles.set.questItemsHint"] = "Schaltet das eingebaute Glitzern des Spiels für lootbare Quest-Items ein. Das Spiel zeigt es von selbst nicht, das Addon gibt es über die Grafik-Einstellung frei (Umriss-Modus aus).",
  ["sparkles.set.style"] = "Effekt-Stil",
  ["sparkles.set.styleTip"] = "Das Original-Modell zeichnet am Ziel möglicherweise nichts. Dann zurück auf Automatisch stellen.",
  ["sparkles.style.auto"] = "Automatisch",
  ["sparkles.style.original"] = "Original-Modell (experimentell)",
  ["sparkles.style.particles"] = "Eigene Partikel",
  ["sparkles.set.offsetY"] = "Effekt-Höhe unter dem Symbol",
  ["sparkles.set.offsetYHint"] = "Schiebt den Effekt vom Symbol des Spiels nach unten auf das Objekt. Stell dich vor eine Pflanze und zieh den Regler, bis die Funken auf ihr sitzen.",
  ["sparkles.set.size"] = "Größe der Partikel",
  ["sparkles.set.sizeHint"] = "Skaliert Funken, Glühen und die dunkle Schicht dahinter gemeinsam. Die Anzahl der Funken bleibt.",
  ["sparkles.set.range"] = "Erkennungs-Reichweite (Yards)",
  ["sparkles.set.rangeHint"] = "Wie weit das Spiel nach Objekten sucht. Das Spiel bietet Objekte höchstens bis %d Yards an (im Forever-Client gemessen). Ein kleinerer Wert zeigt den Effekt erst näher am Objekt. Das Spiel bietet nur Objekte an, auf die die Kamera schaut. Außer Reichweite ist der Effekt gedimmt, bei zu niedriger Fertigkeit grau.",
  ["sparkles.set.rangeMax"] = "Maximum",
  ["sparkles.set.rangeTip"] = "Bei 0 Yards werden Objekte erst direkt am Spieler angeboten.",
  ["sparkles.set.measureNone"] = "Noch keine Messung. Laufe auf ein Erz zu, bis du es erreichst.",
  ["sparkles.set.measureLine"] = "Gemessene Erkennung: zuletzt %d Yards, höchstens %d, im Mittel %d (%d Messungen).",
  ["sparkles.set.measureLineOne"] = "Gemessene Erkennung: zuletzt %d Yards, höchstens %d, im Mittel %d (%d Messung).",
  ["sparkles.set.measureHint"] = "Misst vom Punkt, an dem das Spiel ein Objekt zum ersten Mal anbietet, bis dorthin, wo du es erreichst. Starte weit weg und laufe gerade darauf zu, mit der Kamera auf dem Objekt. Der Wert liegt einige Yards unter der echten Entfernung. Koordinaten werden nicht gespeichert, nur Entfernungen.",
  ["sparkles.set.measureReset"] = "Messung zurücksetzen",
  ["sparkles.set.measureChat"] = "Messwerte im Chat zeigen",
  ["sparkles.set.measureChatHint"] = "Gibt für jede abgeschlossene Messung eine Zeile im Chat aus.",
  ["sparkles.set.restore"] = "Beim Ausschalten kommen deine Grafik- und Zieleinstellungen zurück. Nach einem vollständigen Neustart des Spiels ist die Rückstellung komplett.",
})

local FIELD_WIDTH = 270

local function stored(key)
  local value = ns.db.settings.sparkles
  value = type(value) == "table" and value[key]
  if value == nil then
    value = Store.defaults.settings.sparkles[key]
  end
  return value
end

local function toggle(view, key, hint)
  local t = W.Toggle(view.content, {
    key = "sparkles.set." .. key,
    tooltip = hint and "sparkles.set." .. key or nil,
    tooltipText = hint,
    get = function()
      return stored(key) == true
    end,
    set = function(v)
      Store.set("settings.sparkles." .. key, v)
    end,
  })
  t.fgId = "sparkles-" .. key
  view.stack:Add(t, { height = 24, gap = hint and 2 or 6 })
  if hint then
    ns.AddParagraph(view, hint, { role = "micro", color = "textMuted", gap = 6 })
  end
end

-- A slider with its hint below. Live, not on release: these only change the effect (no rebuild, no
-- window), and the player needs to see it move while the thumb is held.
local function slider(view, key, min, max, step, clean, pattern)
  local s = W.Slider(view.content, {
    key = "sparkles.set." .. key,
    min = min,
    max = max,
    step = step,
    get = function()
      return clean(stored(key))
    end,
    set = function(v)
      Store.set("settings.sparkles." .. key, clean(v))
    end,
    format = function(v)
      return string.format(pattern, v)
    end,
  })
  s.fgId = "sparkles-" .. key
  view.stack:Add(s, { height = 42, gap = 2 })
  ns.AddParagraph(view, "sparkles.set." .. key .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
end

-- The page that is built last (status line), for the repaint when a measurement arrives.
local current

local function statusText()
  local summary = ns.GatherSparkles.Measured()
  if not summary then
    return ns.L["sparkles.set.measureNone"]
  end
  local round = ns.GatherSparklesLogic.RoundYards
  local key = summary.n == 1 and "sparkles.set.measureLineOne" or "sparkles.set.measureLine"
  return string.format(ns.L[key], round(summary.last), round(summary.max), round(summary.avg), math.floor(summary.n))
end

-- Range in yards from 0 to the game maximum; the top of the slider is the setting "max".
local function rangeSlider(view)
  local Logic = ns.GatherSparklesLogic
  local s = W.Slider(view.content, {
    key = "sparkles.set.range",
    min = Logic.RANGE_MIN,
    max = Logic.RANGE_GAME_MAX,
    step = Logic.RANGE_STEP,
    get = function()
      return Logic.RangeSlider(stored("range"))
    end,
    set = function(v)
      Store.set("settings.sparkles.range", Logic.RangeSetting(v))
    end,
    format = function(v)
      if v < Logic.RANGE_GAME_MAX then
        return string.format("%d", v)
      end
      return ns.L["sparkles.set.rangeMax"]
    end,
  })
  s.fgId = "sparkles-range"
  s.slider:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, ns.L["sparkles.set.range"], ns.L["sparkles.set.rangeTip"])
  end)
  s.slider:HookScript("OnLeave", ns.HideTooltip)
  view.stack:Add(s, { height = 42, gap = 2 })
  local hint = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 6, text = " " })
  hint.fgId = "sparkles-rangeHint"
  ns.Bind(hint, function(fs)
    fs:SetText(string.format(ns.L["sparkles.set.rangeHint"], Logic.RANGE_GAME_MAX))
  end)
end

-- The measurement of the detection range: status line, how it works, reset, chat line.
local function measureSection(view)
  local status = ns.AddParagraph(view, nil, { role = "micro", color = "textSecondary", gap = 2, text = " " })
  status.fgId = "sparkles-measureStatus"
  ns.Bind(status, function(fs)
    fs:SetText(statusText())
  end)
  ns.AddParagraph(view, "sparkles.set.measureHint", { role = "micro", color = "textMuted", gap = 6 })
  local reset = W.Button(view.content, {
    key = "sparkles.set.measureReset",
    width = 200,
    onClick = function()
      ns.GatherSparkles.MeasureReset()
    end,
  })
  reset.fgId = "sparkles-measureReset"
  view.stack:Add(reset, { height = 26, width = 200, gap = 6 })
  toggle(view, "measureChat", "sparkles.set.measureChatHint")
  return status
end

function S.Add(view)
  ns.AddHeading(view, "sparkles.set.heading")
  ns.AddParagraph(view, "sparkles.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "enabled")
  toggle(view, "ore")
  toggle(view, "herbs")
  toggle(view, "lockedNodes", "sparkles.set.lockedNodesHint")
  toggle(view, "quest", "sparkles.set.questHint")
  toggle(view, "questItems", "sparkles.set.questItemsHint")
  toggle(view, "gameIcons", "sparkles.set.gameIconsHint")
  local Logic = ns.GatherSparklesLogic
  slider(view, "offsetY", Logic.OFFSET_MIN, Logic.OFFSET_MAX, Logic.OFFSET_STEP, Logic.CleanOffset, "%d")
  slider(view, "size", Logic.SIZE_MIN, Logic.SIZE_MAX, Logic.SIZE_STEP, Logic.CleanSize, "%d%%")
  rangeSlider(view)
  current = { status = measureSection(view), view = view }
  local style = W.Dropdown(view.content, {
    key = "sparkles.set.style",
    tooltip = "sparkles.set.style",
    tooltipText = "sparkles.set.styleTip",
    width = FIELD_WIDTH,
    options = {
      { value = "auto", key = "sparkles.style.auto" },
      { value = "original", key = "sparkles.style.original" },
      { value = "particles", key = "sparkles.style.particles" },
    },
    get = function()
      return ns.GatherSparklesLogic.CleanStyle(stored("style"))
    end,
    set = function(v)
      Store.set("settings.sparkles.style", ns.GatherSparklesLogic.CleanStyle(v))
    end,
  })
  style.fgId = "sparkles-style"
  view.stack:Add(style, { height = 46, width = FIELD_WIDTH })
  ns.AddParagraph(view, "sparkles.set.styleTip", { role = "micro", color = "textMuted" })
  ns.AddParagraph(view, "sparkles.set.restore", { role = "micro", color = "textMuted" })
end

-- A finished measurement or a reset: the texts change even while the page is hidden, so they are right
-- when it opens again.
ns.On("FG_SPARKLES_MEASURED", function()
  if not current then
    return
  end
  current.status:SetText(statusText())
  if current.status:IsVisible() then
    current.view.stack:Layout()
  end
end)
