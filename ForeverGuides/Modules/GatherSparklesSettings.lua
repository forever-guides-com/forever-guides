-- Settings cards of the gathering sparkles (Modules/GatherSparkles.lua), three cards on the gathering feature:
-- Add (main switch, quest item glitter, measurement), AddKinds (one tab per kind of object with its switch, style
-- from the style catalog, color, size, height, count and spread) and AddGeneral (detection range and the options
-- for all kinds). The kind and general cards write the model (settings.sparkles.kinds and .general) directly. The
-- module listens to FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.GatherSparklesSettings = S

ns.AddLocale("enUS", {
  ["sparkles.cfg.group.visibility"] = "Visibility",
  ["sparkles.cfg.group.travel"] = "On the way",
  ["sparkles.cfg.group.gather"] = "While gathering",
  ["sparkles.cfg.group.filter"] = "Filters",
  ["sparkles.cfg.kindsHeading"] = "Effect for each kind of object",
  ["sparkles.cfg.kindsHint"] = "Every kind of object keeps its own switch, style, color and size. They are set in a window of their own.",
  ["sparkles.cfg.openWindow"] = "Edit effects",
  ["sparkles.cfg.openWindowHint"] = "Opens the window for the effect of each kind of object: pick a style from a gallery with previews, choose the color, size, height, number of sparks and spread.",
  ["sparkles.cfg.summaryLine"] = "%s: %s, style %s",
  ["sparkles.cfg.on"] = "Show the effect for this kind",
  ["sparkles.cfg.onHint"] = "Off: this kind of object gets no effect.",
  ["sparkles.cfg.style"] = "Style",
  ["sparkles.cfg.styleTip"] = "Automatic picks the style that fits the kind. The list shows only styles that work for this kind.",
  ["sparkles.cfg.color"] = "Choose color",
  ["sparkles.cfg.colorHint"] = "Opens the color picker of the game. The effect follows while you choose. Cancel keeps the old color. Out of reach it is dimmed, locked gathering spots stay gray.",
  ["sparkles.cfg.colorReset"] = "Default colour",
  ["sparkles.cfg.colorResetHint"] = "Sets the color of this kind to the default colour.",
  ["sparkles.cfg.height"] = "Height below the icon",
  ["sparkles.cfg.heightHint"] = "Moves the effect down from the icon of the game onto the object.",
  ["sparkles.cfg.size"] = "Size",
  ["sparkles.cfg.sizeHint"] = "Scales all textures of the effect together.",
  ["sparkles.cfg.count"] = "Number of sparks",
  ["sparkles.cfg.countHint"] = "For styles made of several small sprites. Styles with a fixed look ignore it.",
  ["sparkles.cfg.spread"] = "Spread",
  ["sparkles.cfg.spreadHint"] = "How far the sprites spread around the center, in percent of the style radius.",
  ["sparkles.cfg.preview"] = "Preview: stand in front of an object of this kind. Every change shows on the effect at once, also while you drag a slider.",
  ["sparkles.cfg.certain"] = "Detection: confirmed in the game.",
  ["sparkles.cfg.assumed"] = "Detection: based on assumed cursor names, not yet confirmed in the game.",
  ["sparkles.cfg.generalHeading"] = "Gathering spots: general",
  ["sparkles.cfg.generalHint"] = "These options apply to every kind of object.",
  ["sparkles.cfg.rangeHeld"] = "The client currently holds %s yards.",
  ["sparkles.cfg.rangeUnknown"] = "The client has not reported its range yet.",
  ["sparkles.cfg.brightness"] = "Overall brightness",
  ["sparkles.cfg.brightnessHint"] = "Weakens or strengthens the whole effect, including flash and finish.",
  ["sparkles.cfg.reachLook"] = "Show distant gathering spots paler",
  ["sparkles.cfg.reachLookHint"] = "Off: a gathering spot looks the same far away and in reach, and the flash follows the reach.",
  ["sparkles.cfg.combatHide"] = "Pause during combat",
  ["sparkles.cfg.instanceHide"] = "Pause inside instances",
  ["sparkles.cfg.myProfessionsOnly"] = "Only gathering spots of my professions",
  ["sparkles.cfg.myProfessionsOnlyHint"] = "Herbs only with herbalism, ore only with mining, skinning only with skinning. If the game does not name your professions, everything shows.",
  ["sparkles.cfg.rareGlow"] = "Highlight rare gathering spots",
  ["sparkles.cfg.rareGlowHint"] = "The list of rare gathering spots is still empty, so this shows nothing yet.",
  ["sparkles.cfg.sound"] = "Chime when in reach",
  ["sparkles.cfg.soundHint"] = "Plays one short sound when a gathering spot you can gather from comes into reach.",
  ["sparkles.cfg.gatherDim"] = "Tone the effect down while gathering",
  ["sparkles.cfg.gatherDimHint"] = "The effect fades while your gather cast runs. The cast spell ids are not confirmed in the game.",
  ["sparkles.cfg.finish"] = "Finish effect",
  ["sparkles.cfg.finishHint"] = "What the effect does once the gather cast succeeds.",
  ["sparkles.set.heading"] = "Highlight gathering spots",
  ["sparkles.set.hint"] = "Ore and herbs glitter when you get close. This needs the soft targeting of the game: the switch sets it up and puts your own settings back when it goes off.",
  ["sparkles.set.enabled"] = "Gathering spots glitter",
  ["sparkles.set.lockedNodes"] = "Show gathering spots you cannot gather",
  ["sparkles.set.lockedNodesHint"] = "In gathering reach the game shows an \"unable\" cursor when a gathering spot is closed to you, for example because the profession is missing. The addon reads only that cursor, no skill values. Such spots glow gray. Off: they get no effect.",
  ["sparkles.set.reachFlash"] = "Flash when a gathering spot comes into reach",
  ["sparkles.set.gameIcons"] = "Show the interaction icons of the game",
  ["sparkles.set.gameIconsHint"] = "The icon over plants, ore and objects is drawn by the game, not by this addon. Off hides it while gathering sparkles are on.",
  ["sparkles.set.questItems"] = "Quest items glitter (graphics setting)",
  ["sparkles.set.questItemsHint"] = "Turns on the built-in glitter of the game on lootable quest items. The game does not show it by itself, the addon unlocks it through the graphics setting (outline mode off).",
  ["sparkles.set.style"] = "Effect style",
  ["sparkles.set.styleTip"] = "Automatic picks a fitting style for each kind of object. A style made for one kind (for example petals for herbs) stays automatic for the others. The original model may draw nothing at the target. Then switch back to automatic.",
  ["sparkles.style.auto"] = "Automatic",
  ["sparkles.style.original"] = "Original model (experimental)",
  ["sparkles.style.particles"] = "Own particles",
  ["sparkles.style.glints"] = "Glints",
  ["sparkles.style.lightbeam"] = "Light beam",
  ["sparkles.style.fireflies"] = "Fireflies",
  ["sparkles.style.dust"] = "Dust motes",
  ["sparkles.style.twinkle"] = "Twinkle",
  ["sparkles.style.pollen"] = "Pollen",
  ["sparkles.style.starcrown"] = "Star crown",
  ["sparkles.style.wisp"] = "Wisp",
  ["sparkles.style.settledust"] = "Settling dust",
  ["sparkles.style.lens"] = "Lens star",
  ["sparkles.style.orbglow"] = "Glow orb",
  ["sparkles.style.halo"] = "Halo ring",
  ["sparkles.style.tumble"] = "Tumbling sparks",
  ["sparkles.style.prism"] = "Prism star",
  ["sparkles.style.snowfall"] = "Snowflakes",
  ["sparkles.style.flare"] = "Flare",
  ["sparkles.style.petals"] = "Petals",
  ["sparkles.style.leaves"] = "Falling leaves",
  ["sparkles.style.emberspark"] = "Ember sparks",
  ["sparkles.style.goldglint"] = "Gold glint",
  ["sparkles.style.beacon"] = "Beacon",
  ["sparkles.style.glowmark"] = "Pulse ring",
  ["sparkles.set.offsetY"] = "Effect height below the icon",
  ["sparkles.set.offsetYHint"] = "Moves the effect down from the icon of the game onto the object. Stand in front of a plant and drag until the sparkles sit on it.",
  ["sparkles.set.size"] = "Particle size",
  ["sparkles.set.sizeHint"] = "Scales the sparks, the glow and the dark layer behind them together. The number of sparks stays.",
  ["sparkles.set.range"] = "Detection range (yards)",
  ["sparkles.set.rangeHint"] = "How far the game looks for objects, from 10 up to %d yards. A smaller value shows the effect only closer to the object. The client may keep less than you ask for: the support report shows the value it really holds. The game only offers objects the camera looks at. The effect is dimmed out of reach and gray when your skill is too low.",
  ["sparkles.set.rangeMax"] = "Maximum",
  ["sparkles.set.rangeTip"] = "A higher value shows the effect from farther away.",
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
  ["sparkles.cfg.group.visibility"] = "Sichtbarkeit",
  ["sparkles.cfg.group.travel"] = "Unterwegs",
  ["sparkles.cfg.group.gather"] = "Beim Sammeln",
  ["sparkles.cfg.group.filter"] = "Filter",
  ["sparkles.cfg.kindsHeading"] = "Effekt je Objektart",
  ["sparkles.cfg.kindsHint"] = "Jede Objektart hat ihren eigenen Schalter, Stil, ihre Farbe und Größe. Eingestellt wird das in einem eigenen Fenster.",
  ["sparkles.cfg.openWindow"] = "Effekte bearbeiten",
  ["sparkles.cfg.openWindowHint"] = "Öffnet das Fenster für den Effekt jeder Objektart: Stil aus einer Galerie mit Vorschau wählen, dazu Farbe, Größe, Höhe, Anzahl der Funken und Streuung.",
  ["sparkles.cfg.summaryLine"] = "%s: %s, Stil %s",
  ["sparkles.cfg.on"] = "Effekt für diese Art zeigen",
  ["sparkles.cfg.onHint"] = "Aus: Objekte dieser Art bekommen keinen Effekt.",
  ["sparkles.cfg.style"] = "Stil",
  ["sparkles.cfg.styleTip"] = "Automatisch wählt den Stil, der zur Art passt. Die Liste zeigt nur Stile, die für diese Art funktionieren.",
  ["sparkles.cfg.color"] = "Farbe wählen",
  ["sparkles.cfg.colorHint"] = "Öffnet die Farbauswahl des Spiels. Der Effekt folgt schon während der Wahl. Abbrechen behält die alte Farbe. Außer Reichweite wird er gedimmt, gesperrte Sammelstellen bleiben grau.",
  ["sparkles.cfg.colorReset"] = "Standardfarbe",
  ["sparkles.cfg.colorResetHint"] = "Setzt die Farbe dieser Art auf die Standardfarbe.",
  ["sparkles.cfg.height"] = "Höhe unter dem Symbol",
  ["sparkles.cfg.heightHint"] = "Schiebt den Effekt vom Symbol des Spiels nach unten auf das Objekt.",
  ["sparkles.cfg.size"] = "Größe",
  ["sparkles.cfg.sizeHint"] = "Skaliert alle Texturen des Effekts gemeinsam.",
  ["sparkles.cfg.count"] = "Anzahl der Funken",
  ["sparkles.cfg.countHint"] = "Für Stile aus mehreren kleinen Bildern. Stile mit festem Aussehen ignorieren den Wert.",
  ["sparkles.cfg.spread"] = "Streuung",
  ["sparkles.cfg.spreadHint"] = "Wie weit sich die Bilder um die Mitte verteilen, in Prozent des Radius des Stils.",
  ["sparkles.cfg.preview"] = "Vorschau: Stell dich vor ein Objekt dieser Art. Jede Änderung wirkt sofort auf den Effekt, auch beim Ziehen eines Reglers.",
  ["sparkles.cfg.certain"] = "Erkennung: im Spiel bestätigt.",
  ["sparkles.cfg.assumed"] = "Erkennung: beruht auf angenommenen Cursor-Namen und ist im Spiel noch nicht bestätigt.",
  ["sparkles.cfg.generalHeading"] = "Sammelpunkte: Allgemein",
  ["sparkles.cfg.generalHint"] = "Diese Optionen gelten für jede Objektart.",
  ["sparkles.cfg.rangeHeld"] = "Der Client hält gerade %s Yards.",
  ["sparkles.cfg.rangeUnknown"] = "Der Client hat seine Reichweite noch nicht gemeldet.",
  ["sparkles.cfg.brightness"] = "Gesamthelligkeit",
  ["sparkles.cfg.brightnessHint"] = "Schwächt oder stärkt den ganzen Effekt, auch Aufblitzen und Abschluss.",
  ["sparkles.cfg.reachLook"] = "Ferne Sammelstellen blasser zeigen",
  ["sparkles.cfg.reachLookHint"] = "Aus: Eine Sammelstelle sieht in der Ferne und in Reichweite gleich aus, das Aufblitzen folgt der Reichweite.",
  ["sparkles.cfg.combatHide"] = "Im Kampf pausieren",
  ["sparkles.cfg.instanceHide"] = "In Instanzen pausieren",
  ["sparkles.cfg.myProfessionsOnly"] = "Nur Sammelstellen meiner Berufe",
  ["sparkles.cfg.myProfessionsOnlyHint"] = "Kräuter nur mit Kräuterkunde, Erz nur mit Bergbau, Kürschnern nur mit Kürschnerei. Nennt das Spiel deine Berufe nicht, wird alles gezeigt.",
  ["sparkles.cfg.rareGlow"] = "Seltene Sammelstellen hervorheben",
  ["sparkles.cfg.rareGlowHint"] = "Die Liste seltener Sammelstellen ist noch leer, deshalb zeigt das vorerst nichts.",
  ["sparkles.cfg.sound"] = "Signalton bei Reichweite",
  ["sparkles.cfg.soundHint"] = "Spielt einen kurzen Ton, wenn eine abbaubare Sammelstelle in Reichweite kommt.",
  ["sparkles.cfg.gatherDim"] = "Effekt beim Sammeln zurücknehmen",
  ["sparkles.cfg.gatherDimHint"] = "Der Effekt blasst aus, solange dein Sammelzauber läuft. Die Zauber-IDs sind im Spiel nicht bestätigt.",
  ["sparkles.cfg.finish"] = "Abschlusseffekt",
  ["sparkles.cfg.finishHint"] = "Was der Effekt tut, sobald der Sammelzauber gelingt.",
  ["sparkles.set.heading"] = "Sammelpunkte hervorheben",
  ["sparkles.set.hint"] = "Erz und Kräuter funkeln, wenn du dich näherst. Das braucht das Soft-Targeting des Spiels: Der Schalter richtet es ein und stellt deine eigenen Einstellungen beim Ausschalten wieder her.",
  ["sparkles.set.enabled"] = "Sammelpunkte funkeln",
  ["sparkles.set.lockedNodes"] = "Nicht abbaubare Sammelstellen zeigen",
  ["sparkles.set.lockedNodesHint"] = "In Abbaureichweite zeigt das Spiel den Cursor \"nicht möglich\", wenn eine Sammelstelle für dich gesperrt ist, zum Beispiel weil der Beruf fehlt. Das Addon liest nur diesen Cursor und keine Fertigkeitswerte. Solche Sammelstellen leuchten grau. Aus: Sie bekommen keinen Effekt.",
  ["sparkles.set.reachFlash"] = "Aufblitzen beim Erreichen der Abbaureichweite",
  ["sparkles.set.gameIcons"] = "Interaktions-Symbole des Spiels anzeigen",
  ["sparkles.set.gameIconsHint"] = "Das Symbol über Pflanzen, Erzen und Objekten zeichnet das Spiel selbst, nicht dieses Addon. Aus blendet es aus, solange Sammelpunkte funkeln eingeschaltet ist.",
  ["sparkles.set.questItems"] = "Quest-Items funkeln (Grafik-Einstellung)",
  ["sparkles.set.questItemsHint"] = "Schaltet das eingebaute Glitzern des Spiels für lootbare Quest-Items ein. Das Spiel zeigt es von selbst nicht, das Addon gibt es über die Grafik-Einstellung frei (Umriss-Modus aus).",
  ["sparkles.set.style"] = "Effekt-Stil",
  ["sparkles.set.styleTip"] = "Automatisch wählt für jede Objektart einen passenden Stil. Ein Stil für eine bestimmte Art (zum Beispiel Blütenblätter für Kräuter) bleibt bei den anderen Arten automatisch. Das Original-Modell zeichnet am Ziel möglicherweise nichts. Dann zurück auf Automatisch stellen.",
  ["sparkles.style.auto"] = "Automatisch",
  ["sparkles.style.original"] = "Original-Modell (experimentell)",
  ["sparkles.style.particles"] = "Eigene Partikel",
  ["sparkles.style.glints"] = "Glitzern",
  ["sparkles.style.lightbeam"] = "Lichtstrahl",
  ["sparkles.style.fireflies"] = "Glühwürmchen",
  ["sparkles.style.dust"] = "Schwebestaub",
  ["sparkles.style.twinkle"] = "Funkeln",
  ["sparkles.style.pollen"] = "Blütenstaub",
  ["sparkles.style.starcrown"] = "Sternenkrone",
  ["sparkles.style.wisp"] = "Irrlicht",
  ["sparkles.style.settledust"] = "Sinkender Staub",
  ["sparkles.style.lens"] = "Linsenstern",
  ["sparkles.style.orbglow"] = "Leuchtkugel",
  ["sparkles.style.halo"] = "Halo-Ring",
  ["sparkles.style.tumble"] = "Kippfunken",
  ["sparkles.style.prism"] = "Prismastern",
  ["sparkles.style.snowfall"] = "Schneeflocken",
  ["sparkles.style.flare"] = "Leuchtfeuer",
  ["sparkles.style.petals"] = "Blütenblätter",
  ["sparkles.style.leaves"] = "Fallendes Laub",
  ["sparkles.style.emberspark"] = "Glutfunken",
  ["sparkles.style.goldglint"] = "Goldblitz",
  ["sparkles.style.beacon"] = "Wegweiser",
  ["sparkles.style.glowmark"] = "Pulsring",
  ["sparkles.set.offsetY"] = "Effekt-Höhe unter dem Symbol",
  ["sparkles.set.offsetYHint"] = "Schiebt den Effekt vom Symbol des Spiels nach unten auf das Objekt. Stell dich vor eine Pflanze und zieh den Regler, bis die Funken auf ihr sitzen.",
  ["sparkles.set.size"] = "Größe der Partikel",
  ["sparkles.set.sizeHint"] = "Skaliert Funken, Glühen und die dunkle Schicht dahinter gemeinsam. Die Anzahl der Funken bleibt.",
  ["sparkles.set.range"] = "Erkennungs-Reichweite (Yards)",
  ["sparkles.set.rangeHint"] = "Wie weit das Spiel nach Objekten sucht, von 10 bis %d Yards. Ein kleinerer Wert zeigt den Effekt erst näher am Objekt. Der Client übernimmt unter Umständen weniger als angefragt: der Support-Bericht zeigt den Wert, den er wirklich hält. Das Spiel bietet nur Objekte an, auf die die Kamera schaut. Außer Reichweite ist der Effekt gedimmt, bei zu niedriger Fertigkeit grau.",
  ["sparkles.set.rangeMax"] = "Maximum",
  ["sparkles.set.rangeTip"] = "Ein höherer Wert zeigt den Effekt schon aus größerer Entfernung.",
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

local Logic = ns.GatherSparklesLogic

local function sparkles()
  local value = ns.db.settings.sparkles
  return type(value) == "table" and value or {}
end

-- The flat keys the card still owns: the switches and values that are no part of the per-kind model.
local function stored(key)
  local value = sparkles()[key]
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

-- The page that is built last (status line), for the repaint when a measurement arrives.
local current, heldLine

local function statusText()
  local summary = ns.GatherSparkles.Measured()
  if not summary then
    return ns.L["sparkles.set.measureNone"]
  end
  local round = ns.GatherSparklesLogic.RoundYards
  local key = summary.n == 1 and "sparkles.set.measureLineOne" or "sparkles.set.measureLine"
  return string.format(ns.L[key], round(summary.last), round(summary.max), round(summary.avg), math.floor(summary.n))
end

-- Range in yards from RANGE_MIN to RANGE_TOP; the top of the slider is the setting "max".
local function rangeSlider(view)
  local s = W.Slider(view.content, {
    key = "sparkles.set.range",
    min = Logic.RANGE_MIN,
    max = Logic.RANGE_TOP,
    step = Logic.RANGE_STEP,
    get = function()
      return Logic.RangeSlider(stored("range"))
    end,
    set = function(v)
      Store.set("settings.sparkles.range", Logic.RangeSetting(v))
    end,
    format = function(v)
      if v < Logic.RANGE_TOP then
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
    fs:SetText(string.format(ns.L["sparkles.set.rangeHint"], Logic.RANGE_TOP))
  end)
  local held = ns.AddParagraph(view, nil, { role = "micro", color = "textSecondary", gap = 6, text = " " })
  held.fgId = "sparkles-rangeHeld"
  ns.Bind(held, function(fs)
    fs:SetText(S.HeldText())
  end)
  heldLine = held
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

-- The line under the range slider: what the client really keeps of the range the module asked for.
function S.HeldText()
  local held = ns.GatherSparkles and ns.GatherSparkles.RangeHeld and ns.GatherSparkles.RangeHeld()
  if not held then
    return ns.L["sparkles.cfg.rangeUnknown"]
  end
  return string.format(ns.L["sparkles.cfg.rangeHeld"], string.format("%g", held))
end

-- A slider with a tooltip and a hint below. Live, not on release: the sliders only change the effect (no rebuild,
-- no window), and the player needs to see it move while the thumb is held. o: key (locale key), id (fgId), min,
-- max, step, get, set, format.
local function slider(view, o)
  local s = W.Slider(view.content, {
    key = o.key,
    tooltip = o.key,
    tooltipText = o.key .. "Hint",
    min = o.min,
    max = o.max,
    step = o.step,
    get = o.get,
    set = o.set,
    format = function(v)
      return string.format(o.format, v)
    end,
  })
  s.fgId = o.id
  view.stack:Add(s, { height = 42, gap = 2 })
  ns.AddParagraph(view, o.key .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
  return s
end

local function whole(value, min, max)
  return math.max(min, math.min(max, math.floor((tonumber(value) or min) + 0.5)))
end

-- Per kind -------------------------------------------------------------------------------------------------------

-- Kinds whose detection rests on assumed cursor names (not confirmed in the game, see docs/SAMMELPUNKTE.md).
local ASSUMED = { chests = true, bobber = true, skinning = true }

function S.IsAssumed(kindKey)
  return ASSUMED[kindKey] == true
end

-- The kind the pages show; kept while the settings window is rebuilt.
local selected = Logic.KINDS[1].key

function S.Selected()
  return selected
end

local function kindData(kindKey)
  local kinds = sparkles().kinds
  kindKey = kindKey or selected
  return Logic.KindSettings(kindKey, type(kinds) == "table" and kinds[kindKey] or nil)
end

local function kindPath(field, kindKey)
  return "settings.sparkles.kinds." .. (kindKey or selected) .. "." .. field
end

-- Opens the color picker of the game on the stored color of the kind. The effect follows while the player picks
-- (the module reads the color live), a cancel writes the old color back.
local function openPicker(kindKey, after)
  local picker = rawget(_G, "ColorPickerFrame")
  if not picker then
    return
  end
  local path = kindPath("color", kindKey)
  local before = Logic.KindSettings(kindKey, (sparkles().kinds or {})[kindKey]).color
  local function write(color)
    Store.set(path, { r = color.r, g = color.g, b = color.b })
  end
  local function apply()
    local r, g, b = picker:GetColorRGB()
    write({ r = r, g = g, b = b })
    after()
  end
  local function cancel()
    write(before)
    after()
  end
  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({
      r = before.r,
      g = before.g,
      b = before.b,
      hasOpacity = false,
      swatchFunc = apply,
      cancelFunc = cancel,
    })
  else
    picker:SetColorRGB(before.r, before.g, before.b)
    picker.hasOpacity = false
    picker.func = apply
    picker.cancelFunc = cancel
    picker:Show()
  end
end

-- Shared with the effect window (Modules/GatherSparklesWindow.lua) ---------------------------------------

function S.Select(kindKey)
  if Logic.KindSettings(kindKey) then
    selected = kindKey
  end
end

S.KindData = kindData
S.KindPath = kindPath
S.OpenPicker = openPicker
S.Whole = whole

-- Writes the style of a kind. The sprite count follows the style (its catalog count), like the old style
-- dropdown did.
function S.SetStyle(kindKey, value)
  local effective = value == "auto" and Logic.AutoStyle(kindKey) or value
  Store.set(kindPath("count", kindKey), whole(Logic.StyleCount(effective), Logic.COUNT_MIN, Logic.COUNT_MAX))
  Store.set(kindPath("style", kindKey), Logic.KindStyle(kindKey, value))
end

-- The line of a kind in the summary: name, switch state and style.
function S.SummaryLine(kindKey, label)
  local data = kindData(kindKey)
  local styleKey = "sparkles.style.auto"
  for _, entry in ipairs(Logic.STYLE_CATALOG) do
    if entry.key == data.style then
      styleKey = entry.label
    end
  end
  return string.format(
    ns.L["sparkles.cfg.summaryLine"],
    ns.L[label],
    ns.L[data.on and "common.on" or "common.off"],
    ns.L[styleKey]
  )
end

local summaryLine

local function summaryText()
  local lines = {}
  for _, entry in ipairs(Logic.KINDS) do
    lines[#lines + 1] = S.SummaryLine(entry.key, entry.label)
  end
  return table.concat(lines, "\n")
end

-- The card of the effect per kind: a short summary and the button that opens the effect window, where the
-- style gallery, color and sliders of every kind live.
function S.AddKinds(view)
  ns.AddHeading(view, "sparkles.cfg.kindsHeading")
  ns.AddParagraph(view, "sparkles.cfg.kindsHint", { role = "micro", color = "textMuted" })
  local open = W.Button(view.content, {
    key = "sparkles.cfg.openWindow",
    width = 260,
    height = 28,
    opens = true,
    tooltip = "sparkles.cfg.openWindow",
    tooltipText = "sparkles.cfg.openWindowHint",
    onClick = function()
      ns.GatherSparklesWindow.Open()
    end,
  })
  open.fgId = "sparkles-kind-open"
  view.stack:Add(open, { height = 28, width = 260, gap = 8 })
  local summary = ns.AddParagraph(view, nil, { role = "micro", color = "textSecondary", gap = 4, text = " " })
  summary.fgId = "sparkles-kind-summary"
  ns.Bind(summary, function(fs)
    fs:SetText(summaryText())
  end)
  summaryLine = summary
end

-- General --------------------------------------------------------------------------------------------------------

-- The general switches in order. name: option of Logic.General, flat: the flat key that is its source (nil: it
-- lives in general), id: fgId, key: locale key (the hint is key .. "Hint" when hint is true), more: behind the section.
local GENERAL_TOGGLES = {
  { name = "reachLook", id = "reachLook", key = "sparkles.cfg.reachLook", hint = true },
  { name = "reachFlash", flat = "reachFlash", id = "reachFlash", key = "sparkles.set.reachFlash" },
  { name = "combatHide", id = "combatHide", key = "sparkles.cfg.combatHide" },
  { name = "instanceHide", id = "instanceHide", key = "sparkles.cfg.instanceHide", more = true },
  { name = "myProfessionsOnly", id = "myProfessionsOnly", key = "sparkles.cfg.myProfessionsOnly", hint = true, more = true },
  { name = "rareGlow", id = "rareGlow", key = "sparkles.cfg.rareGlow", hint = true, more = true },
  { name = "sound", id = "sound", key = "sparkles.cfg.sound", hint = true, more = true },
  { name = "gatherDim", id = "gatherDim", key = "sparkles.cfg.gatherDim", hint = true, more = true },
  { name = "grayTooHard", flat = "lockedNodes", id = "lockedNodes", key = "sparkles.set.lockedNodes", hint = true, more = true },
  { name = "gameIcons", flat = "gameIcons", id = "gameIcons", key = "sparkles.set.gameIcons", hint = true, more = true },
}

S.GENERAL_TOGGLES = GENERAL_TOGGLES

local function general()
  return Logic.General(sparkles().general, sparkles())
end

local function generalToggle(view, spec)
  local t = W.Toggle(view.content, {
    key = spec.key,
    tooltip = spec.hint and spec.key or nil,
    tooltipText = spec.hint and spec.key .. "Hint" or nil,
    get = function()
      return general()[spec.name] == true
    end,
    set = function(v)
      Store.set(spec.flat and "settings.sparkles." .. spec.flat or "settings.sparkles.general." .. spec.name, v)
    end,
  })
  t.fgId = "sparkles-" .. spec.id
  view.stack:Add(t, { height = 24, gap = spec.hint and 2 or 6 })
  if spec.hint then
    ns.AddParagraph(view, spec.key .. "Hint", { role = "micro", color = "textMuted", gap = 6 })
  end
end

local function groupTitle(view, group)
  local title = W.Text(view.content, { key = "sparkles.cfg.group." .. group, role = "ui", color = "accent" })
  view.stack:Add(title, { gap = 6 })
end

local function generalSpec(name)
  for _, spec in ipairs(GENERAL_TOGGLES) do
    if spec.name == name then
      return spec
    end
  end
end

function S.AddGeneral(view)
  ns.AddHeading(view, "sparkles.cfg.generalHeading")
  ns.AddParagraph(view, "sparkles.cfg.generalHint", { role = "micro", color = "textMuted" })
  groupTitle(view, "visibility")
  slider(view, {
    key = "sparkles.cfg.brightness",
    id = "sparkles-brightness",
    min = Logic.BRIGHTNESS_MIN,
    max = Logic.BRIGHTNESS_MAX,
    step = 5,
    format = "%d%%",
    get = function()
      return general().brightness
    end,
    set = function(v)
      Store.set("settings.sparkles.general.brightness", whole(v, Logic.BRIGHTNESS_MIN, Logic.BRIGHTNESS_MAX))
    end,
  })
  generalToggle(view, generalSpec("reachLook"))
  generalToggle(view, generalSpec("combatHide"))
  groupTitle(view, "travel")
  rangeSlider(view)
  generalToggle(view, generalSpec("reachFlash"))
  groupTitle(view, "gather")
  local options = {}
  for _, finish in ipairs(Logic.FINISHES) do
    options[#options + 1] = { value = finish, key = "sparkles.finish." .. finish }
  end
  local finish = W.Dropdown(view.content, {
    key = "sparkles.cfg.finish",
    tooltip = "sparkles.cfg.finish",
    tooltipText = "sparkles.cfg.finishHint",
    width = FIELD_WIDTH,
    options = options,
    get = function()
      return general().finish
    end,
    set = function(v)
      Store.set("settings.sparkles.general.finish", Logic.CleanFinish(v))
    end,
  })
  finish.fgId = "sparkles-finish"
  view.stack:Add(finish, { height = 46, width = FIELD_WIDTH, gap = 6 })
  generalToggle(view, generalSpec("gatherDim"))
  -- The rarely changed options sit behind "More settings", under the same group titles.
  local more = W.Accordion(view, { id = view.id or "gathering.sparkles.general" })
  groupTitle(more, "visibility")
  generalToggle(more, generalSpec("instanceHide"))
  generalToggle(more, generalSpec("gameIcons"))
  groupTitle(more, "travel")
  generalToggle(more, generalSpec("sound"))
  groupTitle(more, "filter")
  generalToggle(more, generalSpec("myProfessionsOnly"))
  generalToggle(more, generalSpec("grayTooHard"))
  generalToggle(more, generalSpec("rareGlow"))
end

function S.Add(view)
  ns.AddHeading(view, "sparkles.set.heading")
  ns.AddParagraph(view, "sparkles.set.hint", { role = "micro", color = "textMuted" })
  toggle(view, "enabled")
  -- Everything else is rarely changed: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "gathering.sparkles" })
  toggle(more, "questItems", "sparkles.set.questItemsHint")
  current = { status = measureSection(more), view = view }
  ns.AddParagraph(more, "sparkles.set.restore", { role = "micro", color = "textMuted" })
end

-- The client may hold less than asked for, and it only reports that after the write: the line follows the range.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.sparkles.range" and heldLine and heldLine.SetText then
    heldLine:SetText(S.HeldText())
  end
  if type(path) == "string" and path:find("^settings%.sparkles%.kinds") and summaryLine and summaryLine.SetText then
    summaryLine:SetText(summaryText())
  end
end)

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
