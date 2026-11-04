-- Cooldown element of the mouse cursor ring (ns.CursorCooldowns, type "spellcd"): the cooldown of a spell, a
-- pet spell or an item (a trinket, a potion) as a ring or square around its icon or as a status bar, with the
-- charges and a timer text. The saved layout holds the base id of the spell (account-wide) or the item (its
-- equipment slot or its id); the rank this character has learned or the item worn is looked up while the
-- element is drawn (CooldownCore.Resolve, ResolveItem). The logic lives in CooldownCore, this file talks to
-- the game.
--
-- The engine draws the ring: a Cooldown frame fed with duration objects, or the bar: a StatusBar that
-- SetTimerDuration fills. The timer has four looks (timerMode): a text the remaining duration of the duration
-- object is formatted into as the game gives it (the default), the engine's numbers in a second Cooldown
-- frame that draws nothing else, the engine's numbers in the ring, and an own text counted down by a 10 Hz
-- tick (readable values only, else the second frame). A look the game refuses falls back to the next one:
-- formatted, numbers frame, numbers in the ring. A secret number is only passed on to such a widget, never
-- read, compared or computed. The end of a cooldown is found by a 5 Hz check of the readable booleans
-- (isActive, IsZero) that runs only while a cooldown does, because no event comes when one runs out;
-- OnCooldownDone is a second signal. Every value of the game goes through pcall and issecretvalue; events
-- only trigger a new read.
-- A source (spell, pet, item) is one entry of SOURCES with the functions that read the game.
local _, ns = ...
local U, L, CU, A, E, S = ns.U, ns.L, ns.CursorLogic, ns.CursorAssets, ns.CursorElements, ns.CursorSim
local T, K, V, XB, SL = ns.CursorTimers, ns.CooldownCore, ns.CursorValuesLogic, ns.XpBarLayout, ns.ShowLogic
local TFmt, PL = ns.TimeFormat, ns.PanelLogic
local G = T.Guard
local finite, hidden, readable, now, api, try, method = G.finite, G.hidden, G.readable, G.now, G.api, G.try, G.method

local CC = {}
ns.CursorCooldowns = CC

CC.FORMS = { "circle", "square" }
CC.POSITIONS = { "center", "below", "above" }
CC.READY_MARKS = { "saturation", "text", "none" }
CC.WARNINGS = { "off", "short", "long" }
CC.UNKNOWNS = { "gray", "hide" }
CC.TIMER_MODES = { "formatted", "engineText", "engine", "own" }
CC.STYLES = { "ring", "bar" }
CC.BAR_DIRECTIONS = { "ltr", "rtl" }
CC.BAR_FILLS = { "elapsed", "remaining" }
CC.BAR_ICONS = { "left", "right", "off" }
CC.CURVE_TARGETS = { "text", "icon", "ring", "all" }
-- What the diagnosis window (/fg cdtest) reads: the checks made for the end of a cooldown, the last change
-- of a cooldown ({ event, at }), and whether the game refused the formatted value or the numbers frame and
-- why (stays until a reload).
CC.diag =
  { polls = 0, last = nil, formattedFailed = false, formattedWhy = nil, numbersFailed = false, numbersWhy = nil }
-- Length of the cooldown the editor preview counts down, and the seconds the simulation rests between two.
CC.SAMPLE_SECONDS = 8
local SIM_PAUSE = 2

local GRAY_ALPHA = 0.35
-- Gap between the ring and the icon in px.
local ICON_GAP = 1
-- Seconds between two steps of the text and between two checks for the end of a running cooldown.
local TICK = 0.1
local POLL = 0.2
-- Text field of the numbers frame in font sizes.
local NUMBERS_W, NUMBERS_H = 3, 1.5
-- Pulses of a warning and the seconds of one: fade in, fade out while the ring grows.
local PULSES = { short = 1, long = 3 }
local PULSE_IN, PULSE_OUT, PULSE_GROW = 0.12, 0.3, 1.25
local UNKNOWN_ICON = 134400
-- Range and step of the colour curve's thresholds in seconds.
local CURVE_MIN, CURVE_MAX, CURVE_STEP = 0.5, 120, 0.5
-- Size limits of the bar in px, its border width, and the gap to its icon.
local BAR_W_MIN, BAR_W_MAX, BAR_H_MIN, BAR_H_MAX, BAR_BORDER_MAX = 20, 400, 4, 64, 4
local BAR_GAP = 4

ns.AddLocale("enUS", {
  ["cursor.type.spellcd"] = "Cooldown",
  ["cursor.type.spellcd.desc"] = "Shows the cooldown of a spell, pet spell or item (trinket, potion) as a ring, square or status bar, with charges and a timer.",
  ["cursor.preset.spellcd"] = "Spell cooldown",
  ["cursor.cd.source"] = "Source",
  ["cursor.cd.source.tip"] = "What the element follows: a spell of the player, a spell of the pet, or an item such as a trinket or a potion.",
  ["cursor.cd.source.spell"] = "Spell of the player",
  ["cursor.cd.source.pet"] = "Spell of the pet",
  ["cursor.cd.source.item"] = "Item (trinket, potion, bandage)",
  ["cursor.cd.spell"] = "Spell",
  ["cursor.cd.spell.tip"] = "Opens the spell list with search and class filter.",
  ["cursor.cd.item"] = "Item",
  ["cursor.cd.item.tip"] = "Opens a list with the trinket slots, worn items with a use effect, usable items of your bags and a field for an item ID. A slot follows whatever you wear there.",
  ["cursor.cd.item.slot"] = "%s (slot %d)",
  ["cursor.cd.itemPicker"] = "Choose item for the cooldown",
  ["cursor.cd.itemNoObject"] = "This item has no use spell and the client gives no duration object for items. The time shows while the game lets the add-on read the cooldown, otherwise it stays unknown.",
  ["cursor.cd.style"] = "Style",
  ["cursor.cd.style.tip"] = "Ring or square around the icon, or a status bar with the icon next to it.",
  ["cursor.cd.style.ring"] = "Ring or square",
  ["cursor.cd.style.bar"] = "Status bar",
  ["cursor.cd.barMissing"] = "This client has no timed status bars. The ring shows instead.",
  ["cursor.cd.icon"] = "Show the icon",
  ["cursor.cd.icon.tip"] = "Shows the icon of the spell or item inside the ring.",
  ["cursor.cd.shape"] = "Shape",
  ["cursor.cd.shape.tip"] = "Round ring or square frame around the icon.",
  ["cursor.cd.shape.circle"] = "Ring",
  ["cursor.cd.shape.square"] = "Square",
  ["cursor.cd.color"] = "Cooldown color",
  ["cursor.cd.color.tip"] = "Color of the ring or bar while the cooldown runs, and its opacity.",
  ["cursor.cd.thickness.tip"] = "Width of the ring in pixels.",
  ["cursor.cd.readyColor"] = "Color when ready",
  ["cursor.cd.readyColor.tip"] = "Color of the ring or bar while nothing is cooling down.",
  ["cursor.cd.fills.tip"] = "Turns the direction in which the ring runs around.",
  ["cursor.cd.barWidth"] = "Bar width",
  ["cursor.cd.barWidth.tip"] = "Length of the bar in pixels.",
  ["cursor.cd.barHeight"] = "Bar height",
  ["cursor.cd.barHeight.tip"] = "Thickness of the bar in pixels. The icon next to it is as big.",
  ["cursor.cd.barDirection"] = "Direction",
  ["cursor.cd.barDirection.tip"] = "The side the bar starts from.",
  ["cursor.cd.barDirection.ltr"] = "Left to right",
  ["cursor.cd.barDirection.rtl"] = "Right to left",
  ["cursor.cd.barFill"] = "Bar shows",
  ["cursor.cd.barFill.tip"] = "The time that has passed (the bar fills up) or the time that is left (the bar empties).",
  ["cursor.cd.barFill.elapsed"] = "Time passed",
  ["cursor.cd.barFill.remaining"] = "Time left",
  ["cursor.cd.barIcon"] = "Icon next to the bar",
  ["cursor.cd.barIcon.tip"] = "Puts the icon left or right of the bar, or leaves it out.",
  ["cursor.cd.barIcon.left"] = "Left",
  ["cursor.cd.barIcon.right"] = "Right",
  ["cursor.cd.barIcon.off"] = "None",
  ["cursor.cd.barBackColor"] = "Bar background",
  ["cursor.cd.barBackColor.tip"] = "Color of the part of the bar that is not filled.",
  ["cursor.cd.barBorder"] = "Border width",
  ["cursor.cd.barBorder.tip"] = "Width of the border around the bar in pixels, 0 for none.",
  ["cursor.cd.barBorderColor"] = "Border color",
  ["cursor.cd.barBorderColor.tip"] = "Color of the border around the bar.",
  ["cursor.cd.readyMark"] = "Ready also shows as",
  ["cursor.cd.readyMark.tip"] = "A second sign for ready, so it does not rest on color alone.",
  ["cursor.cd.readyMark.saturation"] = "Icon in full color",
  ["cursor.cd.readyMark.text"] = "The word Ready",
  ["cursor.cd.readyMark.none"] = "Color only",
  ["cursor.cd.readyText"] = "Ready",
  ["cursor.show.when"] = "Show",
  ["cursor.show.when.tip"] = "When the element is visible.",
  ["cursor.show.when.always"] = "Always",
  ["cursor.show.when.always.tip"] = "The element stays visible all the time.",
  ["cursor.show.when.below"] = "Only below a time left",
  ["cursor.show.when.below.tip"] = "Appears when the time left drops to the number of seconds below, a cooldown for the time until the spell is ready again, an aura for the time it has left. Works in combat too.",
  ["cursor.show.when.running"] = "Only while it runs",
  ["cursor.show.when.running.tip"] = "Cooldown: only while it cools down, hidden when ready. Aura: only while the aura is active.",
  ["cursor.show.when.ready"] = "Only when ready",
  ["cursor.show.when.ready.tip"] = "Only while nothing is cooling down.",
  ["cursor.show.below"] = "From time left (seconds)",
  ["cursor.show.below.tip"] = "The element shows once this many seconds or fewer are left.",
  ["cursor.cd.warn"] = "Pulse when ready",
  ["cursor.cd.warn.tip"] = "A short flash when the cooldown ends.",
  ["cursor.cd.warn.off"] = "Off",
  ["cursor.cd.warn.short"] = "Short",
  ["cursor.cd.warn.long"] = "Long",
  ["cursor.cd.unknown"] = "Spell or item missing",
  ["cursor.cd.unknown.tip"] = "What the element does when the character does not know the spell or does not have the item.",
  ["cursor.cd.unknown.gray"] = "Grayed out",
  ["cursor.cd.unknown.hide"] = "Hidden",
  ["cursor.cd.chargesSection"] = "Charges",
  ["cursor.cd.charges"] = "Show the charges",
  ["cursor.cd.charges.tip"] = "Shows how many charges of the spell are left.",
  ["cursor.cd.timerSection"] = "Timer text",
  ["cursor.cd.timer"] = "Show the time",
  ["cursor.cd.timer.tip"] = "Shows the time that is left as text.",
  ["cursor.cd.timerPos"] = "Position",
  ["cursor.cd.timerPos.tip"] = "Where the time stands: on the icon (or the bar), below it or above it.",
  ["cursor.cd.timerPos.center"] = "Middle of the icon",
  ["cursor.cd.timerPos.below"] = "Below the icon",
  ["cursor.cd.timerPos.above"] = "Above the icon",
  ["cursor.cd.timeFormat"] = "Long times",
  ["cursor.cd.timeFormat.tip"] = "How times of a minute and more are written: minutes and seconds, or whole minutes and hours.",
  ["cursor.cd.timeStyle"] = "Time format",
  ["cursor.cd.timeStyle.tip"] = "How the time is written. In combat the game keeps the time secret: the add-on then lets the game's own formatter write it. If the game does not offer that formatter, the game's own number stands in.",
  ["cursor.cd.timeStyle.auto"] = "Automatic (4.2, 45, 29:05, 1:15)",
  ["cursor.cd.timeStyle.auto.tip"] = "A decimal below ten seconds, whole seconds up to a minute, then minutes and seconds, from an hour on hours and minutes. The decimal places, the s and the long-times choice below apply.",
  ["cursor.cd.timeStyle.seconds"] = "Seconds only (1736.2)",
  ["cursor.cd.timeStyle.seconds.tip"] = "One number of seconds, also in combat. A long time reads as a big number.",
  ["cursor.cd.timeStyle.clock"] = "Clock (0:45, 29:05, 1:02:05)",
  ["cursor.cd.timeStyle.clock.tip"] = "Minutes and seconds, hours from 60 minutes on. No decimals.",
  ["cursor.cd.timeStyle.short"] = "Compact (4.2, 45, 29m, 1h)",
  ["cursor.cd.timeStyle.short.tip"] = "Like automatic, with whole minutes and hours from a minute on.",
  ["cursor.cd.timeSample"] = "Preview: %s",
  ["cursor.cd.timeFormat.auto"] = "Seconds, then minutes and hours",
  ["cursor.cd.timeFormat.short"] = "Compact (2m, 1h)",
  ["cursor.cd.timerMode"] = "Time display",
  ["cursor.cd.timerMode.tip"] = "How the time is shown. A display the game refuses gives way to the next one: decimal number, number below the icon, number in the ring.",
  ["cursor.cd.timerMode.formatted"] = "Decimal number (own format)",
  ["cursor.cd.timerMode.formatted.tip"] = "The remaining time in the format you choose below, also in combat. The default.",
  ["cursor.cd.timerMode.engineText"] = "Game number below the icon",
  ["cursor.cd.timerMode.engineText.tip"] = "The number of the game in a field of its own, in your font. Long times read as 1:53.",
  ["cursor.cd.timerMode.engine"] = "Game number in the ring",
  ["cursor.cd.timerMode.engine.tip"] = "The number of the game inside the ring, in your font.",
  ["cursor.cd.timerMode.own"] = "Own text (outside combat only, game number in combat)",
  ["cursor.cd.timerMode.own.tip"] = "A text of this add-on with the format below. In combat the game keeps the time secret, then its own number counts.",
  ["cursor.cd.timeDecimals"] = "Decimal places",
  ["cursor.cd.timeDecimals.tip"] = "Digits after the decimal point of the decimal number.",
  ["cursor.cd.timeDecimals.0"] = "None (9)",
  ["cursor.cd.timeDecimals.1"] = "One (9.4)",
  ["cursor.cd.timeDecimals.2"] = "Two (9.43)",
  ["cursor.cd.timeSuffix"] = "Add s after the number",
  ["cursor.cd.timeSuffix.tip"] = "Writes an s behind the decimal number (9.4s).",
  ["cursor.cd.timerColor"] = "Text color",
  ["cursor.cd.timerColor.tip"] = "Color of the time text. The color by remaining time replaces it while that is on.",
  ["cursor.cd.tip.font"] = "Font of the text.",
  ["cursor.cd.tip.size"] = "Size of the text.",
  ["cursor.cd.tip.outline"] = "Outline of the text, it keeps the text readable.",
  ["cursor.cd.tip.shadow"] = "Shadow behind the text.",
  ["cursor.cd.formattedFailed"] = "The game does not take the formatted value here. The game number below the icon shows the time instead.",
  ["cursor.cd.numbersFailed"] = "The game does not take the number below the icon either. The number in the ring shows the time instead.",
  ["cursor.cd.ruleFailed"] = "The game does not offer its time formatter here. In combat the game number below the icon shows the time instead.",
  ["cursor.cd.colorCurve"] = "Color by remaining time",
  ["cursor.cd.colorCurve.tip"] = "Changes the color while the time runs down, in three steps. Works in combat too.",
  ["cursor.cd.curveMid"] = "Middle color below (seconds)",
  ["cursor.cd.curveMid.tip"] = "Below this many seconds the middle color shows.",
  ["cursor.cd.curveLow"] = "Last color below (seconds)",
  ["cursor.cd.curveLow.tip"] = "Below this many seconds the last color shows.",
  ["cursor.cd.curveColorHigh"] = "Color above",
  ["cursor.cd.curveColorHigh.tip"] = "Color while more time is left than the middle threshold, and its opacity.",
  ["cursor.cd.curveColorMid"] = "Middle color",
  ["cursor.cd.curveColorMid.tip"] = "Color between the two thresholds.",
  ["cursor.cd.curveColorLow"] = "Last color",
  ["cursor.cd.curveColorLow.tip"] = "Color in the last seconds.",
  ["cursor.cd.curveTarget"] = "Color applies to",
  ["cursor.cd.curveTarget.tip"] = "What takes the color: the time text, the icon, the ring (the bar for the status bar) or all three. The numbers of the game keep their color.",
  ["cursor.cd.curveTarget.text"] = "Text",
  ["cursor.cd.curveTarget.icon"] = "Icon",
  ["cursor.cd.curveTarget.ring"] = "Ring",
  ["cursor.cd.curveTarget.all"] = "Text, icon and ring",
  ["cursor.cd.curveMissing"] = "This client has no color curves. The color stays as it is.",
  ["cursor.cd.status.native"] = "In combat the engine draws ring, bar and time from the cooldown of the game.",
  ["cursor.cd.status.below"] = "The time threshold of the show rule needs color curves, which this client lacks. In combat the element stays visible.",
  ["cursor.cd.status.nothing"] = "Nothing is chosen yet, so the element shows nothing.",
  ["cursor.cd.note"] = "In combat the game may keep cooldown values secret. Then the numbers of the game count down in your font, and Hide while ready works only if the game says whether the spell is ready.",
})
ns.AddLocale("deDE", {
  ["cursor.type.spellcd"] = "Abklingzeit",
  ["cursor.type.spellcd.desc"] = "Zeigt die Abklingzeit eines Zaubers, Pet-Zaubers oder Gegenstands (Schmuckstück, Trank) als Ring, Quadrat oder Statusbalken, mit Aufladungen und Zeitanzeige.",
  ["cursor.preset.spellcd"] = "Zauber-Abklingzeit",
  ["cursor.cd.source"] = "Quelle",
  ["cursor.cd.source.tip"] = "Was das Element verfolgt: einen Zauber des Spielers, einen Zauber des Pets oder einen Gegenstand wie ein Schmuckstück oder einen Trank.",
  ["cursor.cd.source.spell"] = "Zauber des Spielers",
  ["cursor.cd.source.pet"] = "Zauber des Pets",
  ["cursor.cd.source.item"] = "Gegenstand (Schmuckstück, Trank, Verband)",
  ["cursor.cd.spell"] = "Zauber",
  ["cursor.cd.spell.tip"] = "Öffnet die Zauberliste mit Suche und Klassenfilter.",
  ["cursor.cd.item"] = "Gegenstand",
  ["cursor.cd.item.tip"] = "Öffnet eine Liste mit den Schmuckstück-Plätzen, getragenen Gegenständen mit Benutzen-Effekt, benutzbaren Gegenständen aus den Taschen und einem Feld für die Gegenstands-ID. Ein Platz folgt dem, was du dort trägst.",
  ["cursor.cd.item.slot"] = "%s (Platz %d)",
  ["cursor.cd.itemPicker"] = "Gegenstand für die Abklingzeit wählen",
  ["cursor.cd.itemNoObject"] = "Dieser Gegenstand hat keinen Nutzungszauber und der Client liefert für Gegenstände kein Dauer-Objekt. Die Zeit erscheint, solange das Spiel dem Addon die Abklingzeit zu lesen erlaubt, sonst bleibt sie unbekannt.",
  ["cursor.cd.style"] = "Stil",
  ["cursor.cd.style.tip"] = "Ring oder Quadrat um das Symbol, oder ein Statusbalken mit dem Symbol daneben.",
  ["cursor.cd.style.ring"] = "Ring oder Quadrat",
  ["cursor.cd.style.bar"] = "Statusbalken",
  ["cursor.cd.barMissing"] = "Dieser Client hat keine zeitgesteuerten Statusbalken. Stattdessen erscheint der Ring.",
  ["cursor.cd.icon"] = "Symbol anzeigen",
  ["cursor.cd.icon.tip"] = "Zeigt das Symbol des Zaubers oder Gegenstands im Ring.",
  ["cursor.cd.shape"] = "Form",
  ["cursor.cd.shape.tip"] = "Runder Ring oder eckiger Rahmen um das Symbol.",
  ["cursor.cd.shape.circle"] = "Ring",
  ["cursor.cd.shape.square"] = "Quadrat",
  ["cursor.cd.color"] = "Farbe der Abklingzeit",
  ["cursor.cd.color.tip"] = "Farbe von Ring oder Balken, solange die Abklingzeit läuft, und ihre Deckkraft.",
  ["cursor.cd.thickness.tip"] = "Breite des Rings in Pixeln.",
  ["cursor.cd.readyColor"] = "Farbe bei bereit",
  ["cursor.cd.readyColor.tip"] = "Farbe von Ring oder Balken, solange nichts abklingt.",
  ["cursor.cd.fills.tip"] = "Dreht die Richtung um, in der der Ring läuft.",
  ["cursor.cd.barWidth"] = "Breite des Balkens",
  ["cursor.cd.barWidth.tip"] = "Länge des Balkens in Pixeln.",
  ["cursor.cd.barHeight"] = "Höhe des Balkens",
  ["cursor.cd.barHeight.tip"] = "Dicke des Balkens in Pixeln. Das Symbol daneben ist genauso groß.",
  ["cursor.cd.barDirection"] = "Richtung",
  ["cursor.cd.barDirection.tip"] = "Die Seite, von der der Balken ausgeht.",
  ["cursor.cd.barDirection.ltr"] = "Von links nach rechts",
  ["cursor.cd.barDirection.rtl"] = "Von rechts nach links",
  ["cursor.cd.barFill"] = "Balken zeigt",
  ["cursor.cd.barFill.tip"] = "Die verstrichene Zeit (der Balken füllt sich) oder die verbleibende Zeit (der Balken leert sich).",
  ["cursor.cd.barFill.elapsed"] = "Verstrichene Zeit",
  ["cursor.cd.barFill.remaining"] = "Verbleibende Zeit",
  ["cursor.cd.barIcon"] = "Symbol neben dem Balken",
  ["cursor.cd.barIcon.tip"] = "Setzt das Symbol links oder rechts neben den Balken oder lässt es weg.",
  ["cursor.cd.barIcon.left"] = "Links",
  ["cursor.cd.barIcon.right"] = "Rechts",
  ["cursor.cd.barIcon.off"] = "Keines",
  ["cursor.cd.barBackColor"] = "Hintergrund des Balkens",
  ["cursor.cd.barBackColor.tip"] = "Farbe des Teils, der nicht gefüllt ist.",
  ["cursor.cd.barBorder"] = "Randbreite",
  ["cursor.cd.barBorder.tip"] = "Breite des Rands um den Balken in Pixeln, 0 für keinen.",
  ["cursor.cd.barBorderColor"] = "Randfarbe",
  ["cursor.cd.barBorderColor.tip"] = "Farbe des Rands um den Balken.",
  ["cursor.cd.readyMark"] = "Bereit zeigt sich auch durch",
  ["cursor.cd.readyMark.tip"] = "Ein zweites Zeichen für bereit, damit es nicht allein an der Farbe hängt.",
  ["cursor.cd.readyMark.saturation"] = "Symbol in voller Farbe",
  ["cursor.cd.readyMark.text"] = "Das Wort Bereit",
  ["cursor.cd.readyMark.none"] = "Nur Farbe",
  ["cursor.cd.readyText"] = "Bereit",
  ["cursor.show.when"] = "Anzeigen",
  ["cursor.show.when.tip"] = "Wann das Element sichtbar ist.",
  ["cursor.show.when.always"] = "Immer",
  ["cursor.show.when.always.tip"] = "Das Element bleibt die ganze Zeit sichtbar.",
  ["cursor.show.when.below"] = "Nur unter einer Restzeit",
  ["cursor.show.when.below.tip"] = "Erscheint, wenn die Restzeit auf die Sekunden unten gefallen ist, bei einer Abklingzeit die Zeit, bis der Zauber wieder bereit ist, bei einer Aura ihre Restzeit. Wirkt auch im Kampf.",
  ["cursor.show.when.running"] = "Nur solange es läuft",
  ["cursor.show.when.running.tip"] = "Abklingzeit: nur solange sie abklingt, bei bereit versteckt. Aura: nur solange die Aura aktiv ist.",
  ["cursor.show.when.ready"] = "Nur wenn bereit",
  ["cursor.show.when.ready.tip"] = "Nur solange nichts abklingt.",
  ["cursor.show.below"] = "Ab Restzeit (Sekunden)",
  ["cursor.show.below.tip"] = "Das Element erscheint, sobald so viele Sekunden oder weniger übrig sind.",
  ["cursor.cd.warn"] = "Puls bei bereit",
  ["cursor.cd.warn.tip"] = "Ein kurzes Aufblitzen, wenn die Abklingzeit endet.",
  ["cursor.cd.warn.off"] = "Aus",
  ["cursor.cd.warn.short"] = "Kurz",
  ["cursor.cd.warn.long"] = "Lang",
  ["cursor.cd.unknown"] = "Zauber oder Gegenstand fehlt",
  ["cursor.cd.unknown.tip"] = "Was das Element tut, wenn der Charakter den Zauber nicht kennt oder den Gegenstand nicht hat.",
  ["cursor.cd.unknown.gray"] = "Ausgegraut",
  ["cursor.cd.unknown.hide"] = "Versteckt",
  ["cursor.cd.chargesSection"] = "Aufladungen",
  ["cursor.cd.charges"] = "Aufladungen anzeigen",
  ["cursor.cd.charges.tip"] = "Zeigt, wie viele Aufladungen des Zaubers übrig sind.",
  ["cursor.cd.timerSection"] = "Zeittext",
  ["cursor.cd.timer"] = "Zeit anzeigen",
  ["cursor.cd.timer.tip"] = "Zeigt die verbleibende Zeit als Text.",
  ["cursor.cd.timerPos"] = "Position",
  ["cursor.cd.timerPos.tip"] = "Wo die Zeit steht: auf dem Symbol (oder dem Balken), darunter oder darüber.",
  ["cursor.cd.timerPos.center"] = "Mitte des Symbols",
  ["cursor.cd.timerPos.below"] = "Unter dem Symbol",
  ["cursor.cd.timerPos.above"] = "Über dem Symbol",
  ["cursor.cd.timeFormat"] = "Lange Zeiten",
  ["cursor.cd.timeFormat.tip"] = "Wie Zeiten ab einer Minute geschrieben werden: Minuten und Sekunden oder ganze Minuten und Stunden.",
  ["cursor.cd.timeStyle"] = "Zeitformat",
  ["cursor.cd.timeStyle.tip"] = "Wie die Zeit geschrieben wird. Im Kampf hält das Spiel die Zeit geheim: das Addon lässt sie dann vom Formatter des Spiels schreiben. Bietet das Spiel diesen Formatter nicht an, springt die Zahl des Spiels ein.",
  ["cursor.cd.timeStyle.auto"] = "Automatisch (4.2, 45, 29:05, 1:15)",
  ["cursor.cd.timeStyle.auto.tip"] = "Unter zehn Sekunden mit Dezimalstelle, bis zur Minute ganze Sekunden, dann Minuten und Sekunden, ab einer Stunde Stunden und Minuten. Nachkommastellen, das s und die Wahl bei langen Zeiten darunter gelten.",
  ["cursor.cd.timeStyle.seconds"] = "Nur Sekunden (1736.2)",
  ["cursor.cd.timeStyle.seconds.tip"] = "Eine Zahl in Sekunden, auch im Kampf. Eine lange Zeit steht als große Zahl da.",
  ["cursor.cd.timeStyle.clock"] = "Uhr (0:45, 29:05, 1:02:05)",
  ["cursor.cd.timeStyle.clock.tip"] = "Minuten und Sekunden, ab 60 Minuten Stunden. Keine Nachkommastellen.",
  ["cursor.cd.timeStyle.short"] = "Kompakt (4.2, 45, 29m, 1h)",
  ["cursor.cd.timeStyle.short.tip"] = "Wie Automatisch, ab einer Minute mit ganzen Minuten und Stunden.",
  ["cursor.cd.timeSample"] = "Vorschau: %s",
  ["cursor.cd.timeFormat.auto"] = "Sekunden, dann Minuten und Stunden",
  ["cursor.cd.timeFormat.short"] = "Kompakt (2m, 1h)",
  ["cursor.cd.timerMode"] = "Zeitanzeige",
  ["cursor.cd.timerMode.tip"] = "Wie die Zeit angezeigt wird. Eine Anzeige, die das Spiel verweigert, weicht der nächsten: Dezimalzahl, Zahl unter dem Symbol, Zahl im Ring.",
  ["cursor.cd.timerMode.formatted"] = "Dezimalzahl (eigenes Format)",
  ["cursor.cd.timerMode.formatted.tip"] = "Die Restzeit im Format, das du unten wählst, auch im Kampf. Die Voreinstellung.",
  ["cursor.cd.timerMode.engineText"] = "Engine-Zahl unter dem Symbol",
  ["cursor.cd.timerMode.engineText.tip"] = "Die Zahl des Spiels in einem eigenen Feld, in deiner Schrift. Lange Zeiten stehen als 1:53 da.",
  ["cursor.cd.timerMode.engine"] = "Engine-Zahl im Ring",
  ["cursor.cd.timerMode.engine.tip"] = "Die Zahl des Spiels im Ring, in deiner Schrift.",
  ["cursor.cd.timerMode.own"] = "Eigener Text (nur außerhalb des Kampfs, im Kampf Engine)",
  ["cursor.cd.timerMode.own.tip"] = "Ein Text dieses Addons mit dem Format unten. Im Kampf hält das Spiel die Zeit geheim, dann zählt seine eigene Zahl.",
  ["cursor.cd.timeDecimals"] = "Nachkommastellen",
  ["cursor.cd.timeDecimals.tip"] = "Stellen nach dem Komma bei der Dezimalzahl.",
  ["cursor.cd.timeDecimals.0"] = "Keine (9)",
  ["cursor.cd.timeDecimals.1"] = "Eine (9.4)",
  ["cursor.cd.timeDecimals.2"] = "Zwei (9.43)",
  ["cursor.cd.timeSuffix"] = "s hinter der Zahl",
  ["cursor.cd.timeSuffix.tip"] = "Schreibt ein s hinter die Dezimalzahl (9.4s).",
  ["cursor.cd.timerColor"] = "Textfarbe",
  ["cursor.cd.timerColor.tip"] = "Farbe des Zeittexts. Die Farbe nach Restzeit ersetzt sie, solange sie an ist.",
  ["cursor.cd.tip.font"] = "Schrift des Texts.",
  ["cursor.cd.tip.size"] = "Größe des Texts.",
  ["cursor.cd.tip.outline"] = "Kontur des Texts, sie hält ihn lesbar.",
  ["cursor.cd.tip.shadow"] = "Schatten hinter dem Text.",
  ["cursor.cd.formattedFailed"] = "Das Spiel nimmt den formatierten Wert hier nicht an. Stattdessen zeigt die Engine-Zahl unter dem Symbol die Zeit.",
  ["cursor.cd.numbersFailed"] = "Das Spiel nimmt auch die Zahl unter dem Symbol nicht an. Stattdessen zeigt die Engine-Zahl im Ring die Zeit.",
  ["cursor.cd.ruleFailed"] = "Das Spiel bietet seinen Zeit-Formatter hier nicht an. Im Kampf zeigt stattdessen die Engine-Zahl unter dem Symbol die Zeit.",
  ["cursor.cd.colorCurve"] = "Farbe nach Restzeit",
  ["cursor.cd.colorCurve.tip"] = "Ändert die Farbe, während die Zeit abläuft, in drei Stufen. Wirkt auch im Kampf.",
  ["cursor.cd.curveMid"] = "Mittlere Farbe unter (Sekunden)",
  ["cursor.cd.curveMid.tip"] = "Unter so vielen Sekunden erscheint die mittlere Farbe.",
  ["cursor.cd.curveLow"] = "Letzte Farbe unter (Sekunden)",
  ["cursor.cd.curveLow.tip"] = "Unter so vielen Sekunden erscheint die letzte Farbe.",
  ["cursor.cd.curveColorHigh"] = "Farbe darüber",
  ["cursor.cd.curveColorHigh.tip"] = "Farbe, solange mehr Zeit übrig ist als die mittlere Schwelle, und ihre Deckkraft.",
  ["cursor.cd.curveColorMid"] = "Mittlere Farbe",
  ["cursor.cd.curveColorMid.tip"] = "Farbe zwischen den beiden Schwellen.",
  ["cursor.cd.curveColorLow"] = "Letzte Farbe",
  ["cursor.cd.curveColorLow.tip"] = "Farbe in den letzten Sekunden.",
  ["cursor.cd.curveTarget"] = "Farbe wirkt auf",
  ["cursor.cd.curveTarget.tip"] = "Was die Farbe annimmt: den Zeittext, das Symbol, den Ring (beim Statusbalken den Balken) oder alle drei. Die Zahlen des Spiels behalten ihre Farbe.",
  ["cursor.cd.curveTarget.text"] = "Text",
  ["cursor.cd.curveTarget.icon"] = "Symbol",
  ["cursor.cd.curveTarget.ring"] = "Ring",
  ["cursor.cd.curveTarget.all"] = "Text, Symbol und Ring",
  ["cursor.cd.curveMissing"] = "Dieser Client hat keine Farbkurven. Die Farbe bleibt unverändert.",
  ["cursor.cd.status.native"] = "Im Kampf zeichnet die Engine Ring, Balken und Zeit aus der Abklingzeit des Spiels.",
  ["cursor.cd.status.below"] = "Die Zeitschwelle der Anzeigeregel braucht Farbkurven, die dieser Client nicht hat. Im Kampf bleibt das Element sichtbar.",
  ["cursor.cd.status.nothing"] = "Es ist noch nichts gewählt, das Element zeigt deshalb nichts.",
  ["cursor.cd.note"] = "Im Kampf kann das Spiel Abklingzeiten geheim halten. Dann zählen die Zahlen des Spiels in deiner Schrift herunter, und Ausblenden bei bereit klappt nur, wenn das Spiel verrät, ob der Zauber bereit ist.",
})

-- Props -----------------------------------------------------------------------------------------------

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function flag(v, default)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function whole(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v + 0.5), lo, hi) or default
end

local function opacity(v, default)
  return finite(v) and U.clamp(v, 0, 1) or default
end

-- A number in steps of CURVE_STEP.
local function halves(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v / CURVE_STEP + 0.5) * CURVE_STEP, lo, hi) or default
end

-- The prop names of the two texts: the timer and the charge count (white, no colour prop).
local TEXT = {
  timer = { font = "font", size = "fontSize", outline = "outline", shadow = "shadow", color = "timerColor" },
  charge = { font = "chargeFont", size = "chargeFontSize", outline = "chargeOutline", shadow = "chargeShadow" },
}

local function cleanText(out, raw, d, keys)
  local font = raw[keys.font]
  out[keys.font] = type(font) == "string" and #font <= 44 and font or d[keys.font]
  out[keys.size] = whole(raw[keys.size], d[keys.size], XB.SIZE_MIN, XB.SIZE_MAX)
  out[keys.outline] = oneOf(raw[keys.outline], XB.OUTLINES, d[keys.outline])
  out[keys.shadow] = flag(raw[keys.shadow], d[keys.shadow])
  if keys.color then
    out[keys.color] = hex(raw[keys.color], d[keys.color])
  end
end

-- The look every element of the ring that counts down shares (cooldown and aura): style, ring, bar, the count
-- text (charges of a cooldown, stacks of an aura), the timer text and the colour curve.
local LOOK = {
  style = "ring",
  icon = true,
  shape = "circle",
  thickness = 3,
  color = "ffd24a",
  readyColor = "3fd05c",
  alpha = 0.9,
  reverse = true,
  barWidth = 120,
  barHeight = 16,
  barDirection = "ltr",
  barFill = "elapsed",
  barBackColor = "1a1a1a",
  barBorder = 1,
  barBorderColor = "000000",
  barIcon = "left",
  charges = true,
  chargeFont = "frizqt",
  chargeFontSize = 14,
  chargeOutline = "outline",
  chargeShadow = true,
  timer = true,
  timerPos = "center",
  timeFormat = "auto",
  timeStyle = "auto",
  timerMode = "formatted",
  timeDecimals = 1,
  timeSuffix = false,
  timerColor = "ffffff",
  colorCurve = false,
  curveMid = 5,
  curveLow = 2,
  curveTarget = "all",
  curveColorHigh = "ffffff",
  curveColorMid = "ffd24a",
  curveColorLow = "ff4d4d",
  curveAlphaHigh = 1,
  curveAlphaMid = 1,
  curveAlphaLow = 1,
  font = "frizqt",
  fontSize = 16,
  outline = "outline",
  shadow = true,
}
CC.LOOK_DEFAULTS = LOOK

-- The shared look props of a saved element, repaired.
local function cleanLook(raw, d)
  local p = {
    style = oneOf(raw.style, CC.STYLES, d.style),
    icon = flag(raw.icon, d.icon),
    shape = oneOf(raw.shape, CC.FORMS, d.shape),
    thickness = whole(raw.thickness, d.thickness, CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX),
    color = hex(raw.color, d.color),
    readyColor = hex(raw.readyColor, d.readyColor),
    alpha = opacity(raw.alpha, d.alpha),
    reverse = flag(raw.reverse, d.reverse),
    barWidth = whole(raw.barWidth, d.barWidth, BAR_W_MIN, BAR_W_MAX),
    barHeight = whole(raw.barHeight, d.barHeight, BAR_H_MIN, BAR_H_MAX),
    barDirection = oneOf(raw.barDirection, CC.BAR_DIRECTIONS, d.barDirection),
    barFill = oneOf(raw.barFill, CC.BAR_FILLS, d.barFill),
    barBackColor = hex(raw.barBackColor, d.barBackColor),
    barBorder = whole(raw.barBorder, d.barBorder, 0, BAR_BORDER_MAX),
    barBorderColor = hex(raw.barBorderColor, d.barBorderColor),
    barIcon = oneOf(raw.barIcon, CC.BAR_ICONS, d.barIcon),
    charges = flag(raw.charges, d.charges),
    timer = flag(raw.timer, d.timer),
    timerPos = oneOf(raw.timerPos, CC.POSITIONS, d.timerPos),
    timeFormat = oneOf(raw.timeFormat, K.TIME_FORMATS, d.timeFormat),
    timeStyle = oneOf(raw.timeStyle, K.TIME_STYLES, d.timeStyle),
    timerMode = oneOf(raw.timerMode, CC.TIMER_MODES, d.timerMode),
    timeDecimals = oneOf(raw.timeDecimals, K.DECIMALS, d.timeDecimals),
    timeSuffix = flag(raw.timeSuffix, d.timeSuffix),
    colorCurve = flag(raw.colorCurve, d.colorCurve),
    curveTarget = oneOf(raw.curveTarget, CC.CURVE_TARGETS, d.curveTarget),
    curveLow = halves(raw.curveLow, d.curveLow, CURVE_MIN, CURVE_MAX - CURVE_STEP),
    curveColorHigh = hex(raw.curveColorHigh, d.curveColorHigh),
    curveColorMid = hex(raw.curveColorMid, d.curveColorMid),
    curveColorLow = hex(raw.curveColorLow, d.curveColorLow),
    curveAlphaHigh = opacity(raw.curveAlphaHigh, d.curveAlphaHigh),
    curveAlphaMid = opacity(raw.curveAlphaMid, d.curveAlphaMid),
    curveAlphaLow = opacity(raw.curveAlphaLow, d.curveAlphaLow),
  }
  -- The middle threshold stays above the last one, the curve needs distinct points.
  p.curveMid = math.max(halves(raw.curveMid, d.curveMid, CURVE_MIN, CURVE_MAX), p.curveLow + CURVE_STEP)
  cleanText(p, raw, d, TEXT.timer)
  cleanText(p, raw, d, TEXT.charge)
  return p
end

CC.CleanLook = cleanLook

local DEFAULTS = {
  source = "spell",
  spellBase = 0,
  itemMode = "slot",
  itemSlot = 13,
  itemId = 0,
  readyMark = "saturation",
  showWhen = "always",
  showBelow = SL.BELOW_DEFAULT,
  warn = "short",
  unknown = "gray",
}
for key, value in pairs(LOOK) do
  DEFAULTS[key] = value
end

CU.Register("spellcd", {
  defaults = DEFAULTS,
  size = { 48, 48 },
  clean = function(raw, d)
    local p = cleanLook(raw, d)
    p.source = oneOf(raw.source, K.SOURCES, d.source)
    p.spellBase = whole(raw.spellBase, d.spellBase, 0, V.SPELL_ID_MAX)
    p.itemMode = oneOf(raw.itemMode, K.ITEM_MODES, d.itemMode)
    p.itemSlot = whole(raw.itemSlot, d.itemSlot, 1, K.SLOT_MAX)
    p.itemId = whole(raw.itemId, d.itemId, 0, K.ITEM_ID_MAX)
    p.readyMark = oneOf(raw.readyMark, CC.READY_MARKS, d.readyMark)
    p.showWhen, p.showBelow = SL.Clean(raw, d.showWhen, d.showBelow, SL.SHOW_WHEN)
    p.warn = oneOf(raw.warn, CC.WARNINGS, d.warn)
    p.unknown = oneOf(raw.unknown, CC.UNKNOWNS, d.unknown)
    return p
  end,
})

-- Game access -----------------------------------------------------------------------------------------

-- true or false for a readable boolean, else nil.
local function flagOf(v)
  if hidden(v) or type(v) ~= "boolean" then
    return nil
  end
  return v
end

local function index(t, key)
  return t[key]
end

-- The method `name` of a game object, nil when it has none (a protected read).
local function methodOf(obj, name)
  local ok, fn = pcall(index, obj, name)
  return ok and type(fn) == "function" and fn or nil
end

-- obj:name(...) protected: true and the first four results, or false and "absent" (no such method) or the
-- error text.
local function invoke(obj, name, ...)
  local fn = methodOf(obj, name)
  if not fn then
    return false, "absent"
  end
  local ok, a, b, c, d = pcall(fn, obj, ...)
  if not ok then
    return false, tostring(a)
  end
  return true, a, b, c, d
end

-- true or false when a duration object says whether it is zero (a readable boolean), else nil.
local function zeroOf(object)
  local isZero = object ~= nil and methodOf(object, "IsZero") or nil
  if isZero then
    return flagOf(try(isZero, object))
  end
  return nil
end

-- true or false for the isActive field of a cooldown table when it is readable, else nil.
local function activeOf(info)
  if type(info) ~= "table" or hidden(info) then
    return nil
  end
  local ok, v = pcall(index, info, "isActive")
  if ok then
    return flagOf(v)
  end
  return nil
end

-- The number of the enum group `group`, nil when the client lacks it.
local function enumValue(group, name)
  local enum = rawget(_G, "Enum")
  local list = type(enum) == "table" and enum[group] or nil
  local value = type(list) == "table" and list[name] or nil
  return finite(value) and value or nil
end

local KNOWN_CHECKS = {
  { "C_SpellBook", "IsSpellKnownOrInSpellBook" },
  { "C_SpellBook", "IsSpellKnown" },
  { nil, "IsPlayerSpell" },
  { nil, "IsSpellKnown" },
}

-- Whether the player knows the spell: true, false, or nil when the client cannot say.
local function spellKnown(id)
  for _, check in ipairs(KNOWN_CHECKS) do
    local answer = flagOf(try(api(check[1], check[2]), id))
    if answer ~= nil then
      return answer
    end
  end
  return nil
end

-- Whether the pet knows the spell. No pet means no pet spell; the pet spellbook bank comes first, the old
-- second argument of IsSpellKnown (true = pet spell) last.
local function petKnown(id)
  if flagOf(try(api(nil, "UnitExists"), "pet")) == false then
    return false
  end
  local bank = enumValue("SpellBookSpellBank", "Pet")
  if bank then
    for _, name in ipairs({ "IsSpellKnownOrInSpellBook", "IsSpellKnown" }) do
      local answer = flagOf(try(api("C_SpellBook", name), id, bank))
      if answer ~= nil then
        return answer
      end
    end
  end
  return flagOf(try(api(nil, "IsSpellKnown"), id, true))
end

-- The spell that stands in for `id` right now (a talent or an aura can replace a spell), nil when none.
local function overrideOf(id)
  local replaced = readable(try(api("C_SpellBook", "FindSpellOverrideByID"), id))
  return replaced and replaced > 0 and replaced or nil
end

local function infoOf(id)
  return try(api("C_Spell", "GetSpellCooldown"), id)
end

-- The duration object of the spell's cooldown without the global cooldown; a client that does not take
-- the second argument answers without it.
local function durationOf(id)
  local fn = api("C_Spell", "GetSpellCooldownDuration")
  local object = try(fn, id, true)
  if object == nil then
    object = try(fn, id)
  end
  return object
end

local function chargesOf(id)
  return try(api("C_Spell", "GetSpellCharges"), id)
end

local function chargeDurationOf(id)
  return try(api("C_Spell", "GetSpellChargeDuration"), id)
end

local function textureOf(id)
  local texture = try(api("C_Spell", "GetSpellTexture"), id)
  if type(texture) == "string" and not hidden(texture) then
    return texture
  end
  return readable(texture)
end

-- Items --------------------------------------------------------------------------------------------------

-- The functions that read an item's cooldown as (start, duration, enable), the first the client has wins; the
-- inventory call for a slot comes before them. The functions that give a duration object are assumed under
-- these names (the client may lack them, then the object is built from readable numbers).
local ITEM_COOLDOWNS = {
  { "C_Item", "GetItemCooldown" },
  { "C_Container", "GetItemCooldown" },
  { nil, "GetItemCooldown" },
}
local ITEM_DURATIONS = {
  { "C_Item", "GetItemCooldownDuration" },
  { "C_Container", "GetItemCooldownDuration" },
}

-- Whether the client has a function that gives an item's cooldown as a duration object.
function CC.ItemDurationSupported()
  for _, call in ipairs(ITEM_DURATIONS) do
    if api(call[1], call[2]) then
      return true
    end
  end
  return false
end

local function slotItem(slot)
  return readable(try(api(nil, "GetInventoryItemID"), "player", slot))
end

-- How many of the item the character has (worn items count), nil when the client cannot say.
local function itemCount(id)
  return readable(try(api("C_Item", "GetItemCount"), id)) or readable(try(api(nil, "GetItemCount"), id))
end

local ITEM_ENV = { slotItem = slotItem, count = itemCount }

-- start, duration and enable of the item's cooldown as the game gave them (a value it keeps secret stays
-- secret); nothing when no function answers.
local function itemNumbers(res)
  local start, duration, enable
  if res.slot then
    start, duration, enable = try(api(nil, "GetInventoryItemCooldown"), "player", res.slot)
  end
  for _, call in ipairs(ITEM_COOLDOWNS) do
    if not rawequal(start, nil) then
      break
    end
    start, duration, enable = try(api(call[1], call[2]), res.id)
  end
  return start, duration, enable
end

-- The cooldown of an item as a table like a spell's, for fieldsOf.
local function itemInfo(_, res)
  local start, duration, enable = itemNumbers(res)
  if rawequal(start, nil) and rawequal(duration, nil) then
    return nil
  end
  return { startTime = start, duration = duration, enable = enable }
end

-- The id of the spell an item casts when used (a trinket, a potion), nil for an item without a use effect.
local function useSpellOf(itemId)
  local _, spellId = try(api("C_Item", "GetItemSpell"), itemId)
  spellId = readable(spellId)
  return spellId and spellId > 0 and spellId or nil
end

-- Whether the game can give a duration object for this item: its own call, or the object of its use spell.
function CC.ItemObjectAvailable(itemId)
  return CC.ItemDurationSupported() or (itemId ~= nil and itemId > 0 and useSpellOf(itemId) ~= nil)
end

-- An object built from start and duration, when both are readable (a secret one cannot be turned into an object).
local function builtDuration(res)
  local start, duration = itemNumbers(res)
  start, duration = readable(start), readable(duration)
  if not (start and duration and start > 0 and duration > 0) then
    return nil
  end
  local object = try(api("C_DurationUtil", "CreateDuration"))
  if object ~= nil and invoke(object, "SetTimeFromStart", start, duration) then
    return object
  end
  return nil
end

-- The duration object of an item's cooldown, by the ways of K.ItemReads: the game's own call for items, the
-- object of the spell the item casts (the client has no item call, the use spell carries the same cooldown and
-- keeps it readable by the engine in combat), else one built from the readable numbers. An object of the use
-- spell that says "nothing runs" while the readable numbers say it does is not taken.
local function itemDuration(_, res)
  for _, way in ipairs(K.ItemReads(CC.ItemDurationSupported(), useSpellOf(res.id))) do
    if way == "direct" then
      for _, call in ipairs(ITEM_DURATIONS) do
        local object = try(api(call[1], call[2]), res.id)
        if not rawequal(object, nil) then
          return object
        end
      end
    elseif way == "spell" then
      local object = durationOf(useSpellOf(res.id))
      if object ~= nil then
        local start, duration = itemNumbers(res)
        local running = readable(start) and readable(duration) and start > 0 and duration > 0
        if not (running and zeroOf(object) == true) then
          return object
        end
      end
    else
      return builtDuration(res)
    end
  end
  return nil
end

local function itemTexture(id, res)
  local icon = try(api("C_Item", "GetItemIconByID"), id)
  if not hidden(icon) and (type(icon) == "number" or type(icon) == "string") then
    return icon
  end
  local _, _, _, _, instant = try(api("C_Item", "GetItemInfoInstant"), id)
  if not hidden(instant) and instant ~= nil then
    return instant
  end
  local worn = res.slot and try(api(nil, "GetInventoryItemTexture"), "player", res.slot) or nil
  return not hidden(worn) and worn or nil
end

local function noCharges() end

-- What a source offers: resolve(p) the item or spell the props mean (nil when none is chosen), chosen(p),
-- info(id, res) the cooldown table, duration(id, res) its duration object, charges(id) and chargeDuration(id)
-- for spells with charges, texture(id, res) the icon, hasGcd whether the global cooldown may stand in the
-- cooldown. A spell source also has known(id) and override(id) for CooldownCore.Resolve.
local function spellSource(known, override)
  local src = {
    known = known,
    override = override,
    hasGcd = true,
    info = infoOf,
    duration = durationOf,
    charges = chargesOf,
    chargeDuration = chargeDurationOf,
    texture = textureOf,
  }
  function src.resolve(p)
    return p.spellBase > 0 and K.Resolve(p.spellBase, src) or nil
  end
  function src.chosen(p)
    return p.spellBase > 0
  end
  return src
end

local SOURCES = {
  spell = spellSource(spellKnown, overrideOf),
  pet = spellSource(petKnown, function()
    return nil
  end),
  item = {
    hasGcd = false,
    info = itemInfo,
    duration = itemDuration,
    charges = noCharges,
    chargeDuration = noCharges,
    texture = itemTexture,
    resolve = function(p)
      return K.ResolveItem(p, ITEM_ENV)
    end,
    chosen = function(p)
      return p.itemMode == "slot" or p.itemId > 0
    end,
  },
}

-- The readable part of the game's answers about a cooldown: a field the game keeps secret or lacks stays nil,
-- `secret` says it kept something back and `raw` holds those values for the engine.
local function readField(f, t, key, kind)
  local ok, v = pcall(index, t, key)
  if not ok or v == nil then
    return nil
  end
  if hidden(v) then
    f.secret = true
    f.raw = f.raw or {}
    f.raw[key] = v
    return nil
  end
  if kind == "number" then
    return finite(v) and v or nil
  end
  return flagOf(v)
end

-- The "enable" of an item's cooldown (a boolean, or 0 and 1): false when the game says the cooldown does not
-- count now, true when it does, nil when the field is absent or secret.
local function enabledOf(f, info)
  local ok, v = pcall(index, info, "enable")
  if not ok or rawequal(v, nil) then
    return nil
  end
  if hidden(v) then
    f.secret = true
    return nil
  end
  if type(v) == "boolean" then
    return v
  end
  if finite(v) then
    return v ~= 0
  end
  return nil
end

local function fieldsOf(info, charges)
  local f = {}
  if type(info) == "table" then
    if hidden(info) then
      f.secret = true
    else
      f.isActive = readField(f, info, "isActive", "boolean")
      f.isOnGCD = readField(f, info, "isOnGCD", "boolean")
      f.start = readField(f, info, "startTime", "number")
      f.duration = readField(f, info, "duration", "number")
      f.enabled = enabledOf(f, info)
    end
  end
  if type(charges) == "table" then
    if hidden(charges) then
      f.secret = true
    else
      local current = readField(f, charges, "currentCharges", "number")
      local max = readField(f, charges, "maxCharges", "number")
      if current and max then
        f.charges = { current = current, max = max }
        -- The time to the next charge stands in for the cooldown while one recharges; with every charge
        -- ready there is no cooldown to show (the global cooldown is none).
        if current < max then
          f.start = readField(f, charges, "cooldownStartTime", "number")
          f.duration = readField(f, charges, "cooldownDuration", "number")
        else
          f.start, f.duration = nil, nil
        end
      end
    end
  end
  return f
end

-- The length of the global cooldown in seconds: the reference spell's while it runs, else the longest one.
local function gcdLength()
  local f = fieldsOf(infoOf(K.GCD_SPELL))
  return f.duration and f.duration > 0 and f.duration or K.GCD_MAX
end

local function playerClass()
  local _, class = try(api(nil, "UnitClass"), "player")
  return type(class) == "string" and not hidden(class) and class or nil
end

-- Widgets ---------------------------------------------------------------------------------------------

local fontCount = 0

-- The parts of one element, created once per frame: the ring of the ready state behind, the icon (masked
-- round for a ring), the Cooldown frame, and a frame above it with the pulse and the two texts. `notes`
-- keeps what the game answered to the last call of each kind ("ok", "absent" or an error text). `anchor` is
-- what the texts and the pulse sit on: the frame for a ring, the host of the bar for a bar.
local function widgetOf(frame)
  local st = frame.fgCooldown
  if st then
    return st
  end
  st = { frame = frame, anchor = frame, notes = {} }
  st.track = frame:CreateTexture(nil, "BACKGROUND")
  st.track:SetAllPoints(frame)
  st.icon = frame:CreateTexture(nil, "ARTWORK")
  st.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  st.cd = CreateFrame("Cooldown", nil, frame)
  st.cd:SetAllPoints(frame)
  method(st.cd, "SetDrawEdge", false)
  method(st.cd, "SetDrawBling", false)
  method(st.cd, "SetHideCountdownNumbers", true)
  st.top = CreateFrame("Frame", nil, frame)
  st.top:SetAllPoints(frame)
  st.top:SetFrameLevel(st.cd:GetFrameLevel() + 1)
  st.pulse = st.top:CreateTexture(nil, "OVERLAY")
  st.pulse:SetAllPoints(frame)
  st.pulse:SetBlendMode("ADD")
  st.pulse:Hide()
  st.timer = st.top:CreateFontString(nil, "OVERLAY")
  st.charges = st.top:CreateFontString(nil, "OVERLAY")
  frame.fgCooldown = st
  return st
end

-- Whether this client has a StatusBar that a duration object can drive, asked once of a spare bar.
local barProbe

local function barSupported()
  if barProbe == nil then
    local ok, bar = pcall(CreateFrame, "StatusBar")
    barProbe = ok and type(bar) == "table" and methodOf(bar, "SetTimerDuration") ~= nil
  end
  return barProbe
end

CC.BarSupported = barSupported

-- The look in use: the bar when it is chosen and the client can drive it, else the ring.
local function styleOf(p)
  return p.style == "bar" and barSupported() and "bar" or "ring"
end

-- The bar, made when the style first needs it: a host frame the size of the bar with the border and the
-- background behind it and the StatusBar the game fills. The background is a white colour texture, every
-- colour is a vertex colour (so a colour curve can set it the same way).
local function barOf(st)
  if st.bar then
    return st.bar
  end
  local host = CreateFrame("Frame", nil, st.frame)
  host:SetFrameLevel(st.cd:GetFrameLevel())
  st.barEdge = host:CreateTexture(nil, "BACKGROUND")
  st.barEdge:SetDrawLayer("BACKGROUND", -2)
  st.barBack = host:CreateTexture(nil, "BACKGROUND")
  st.barBack:SetDrawLayer("BACKGROUND", -1)
  st.barBack:SetAllPoints(host)
  st.barBack:SetColorTexture(1, 1, 1, 1)
  st.bar = CreateFrame("StatusBar", nil, host)
  st.bar:SetAllPoints(host)
  method(st.bar, "SetStatusBarTexture", E.Texture("fill-square"))
  method(st.bar, "SetMinMaxValues", 0, 1)
  method(st.bar, "SetValue", 0)
  st.barHost = host
  st.top:SetFrameLevel(st.bar:GetFrameLevel() + 1)
  return st.bar
end

-- Font, colour and shadow of a text; the font is set again only when it changed. `fs` is a FontString or the
-- font object the Cooldown frame counts with. A text with a colour prop takes it, else it is white.
local function styleText(st, fs, keys)
  local p = st.p
  local key = p[keys.font] .. "|" .. p[keys.size] .. "|" .. p[keys.outline]
  st.fontKeys = st.fontKeys or {}
  if st.fontKeys[fs] ~= key then
    st.fontKeys[fs] = key
    XB.ApplyFont(fs, { font = p[keys.font], size = p[keys.size], outline = p[keys.outline] })
  end
  local r, g, b = 1, 1, 1
  if keys.color then
    r, g, b = U.hex(p[keys.color])
  end
  fs:SetTextColor(r, g, b, 1)
  ns.WindowStyle.ApplyShadow(fs, p[keys.shadow], 1, 1, 1)
end

local function setCountdownFont(st, cd)
  if st.countFont then
    method(cd, "SetCountdownFont", st.countFontName)
  end
end

-- The font object of the numbers the game counts down with (made once per element), in the timer font.
local function styleEngineNumbers(st)
  if st.countFont == nil then
    fontCount = fontCount + 1
    local name = "ForeverGuidesCursorCountdown" .. fontCount
    st.countFont = try(api(nil, "CreateFont"), name) or false
    st.countFontName = name
  end
  if st.countFont then
    styleText(st, st.countFont, TEXT.timer)
    setCountdownFont(st, st.cd)
    if st.nums then
      setCountdownFont(st, st.nums)
    end
  end
end

-- Puts a region of the timer at the chosen place of the icon (or the bar).
local function anchorTimer(region, anchor, pos)
  region:ClearAllPoints()
  if pos == "below" then
    region:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
  elseif pos == "above" then
    region:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
  else
    region:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  end
end

-- The numbers frame is a text field of the timer font's size at the place of the timer text.
local function placeNumbers(st)
  st.nums:SetSize(st.p.fontSize * NUMBERS_W, st.p.fontSize * NUMBERS_H)
  anchorTimer(st.nums, st.anchor, st.p.timerPos)
end

-- The second Cooldown frame that draws only the numbers (no swipe, edge or bling), made when a look needs it.
local function numbersOf(st)
  if not st.nums then
    local cd = CreateFrame("Cooldown", nil, st.top)
    method(cd, "SetDrawSwipe", false)
    method(cd, "SetDrawEdge", false)
    method(cd, "SetDrawBling", false)
    method(cd, "SetHideCountdownNumbers", false)
    st.nums = cd
    setCountdownFont(st, cd)
    placeNumbers(st)
  end
  return st.nums
end

local function maskOf(st)
  if st.mask == nil then
    local create = st.frame.CreateMaskTexture
    st.mask = type(create) == "function" and create(st.frame) or false
    if st.mask then
      st.mask:SetTexture(E.DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      st.mask:SetAllPoints(st.icon)
    end
  end
  return st.mask or nil
end

local function placeTexts(st)
  anchorTimer(st.timer, st.anchor, st.p.timerPos)
  if st.nums then
    placeNumbers(st)
  end
  st.charges:ClearAllPoints()
  st.charges:SetPoint("BOTTOMRIGHT", st.anchor, "BOTTOMRIGHT", -2, 2)
end

-- The icon of the spell or item: the catalog's file first for a spell (no game call), then the client's own
-- answer. An item is looked up even in the editor, where nothing is resolved while it is not drawn in the game.
local function paintIcon(st)
  local p = st.p
  local src = SOURCES[p.source] or SOURCES.spell
  local res = st.res or (p.source == "item" and src.resolve(p)) or nil
  local texture
  if p.source == "item" then
    texture = res and res.id > 0 and src.texture(res.id, res) or nil
  else
    local id = res and res.id or p.spellBase
    local spell = id > 0 and ns.DataApi.Spell(id) or nil
    texture = spell and spell.fid or (id > 0 and src.texture(id)) or nil
  end
  st.icon:SetTexture(texture or UNKNOWN_ICON)
end

-- Colours of the bar for the state: ready fills it with the ready colour; while a cooldown runs the elapsed
-- share shows the cooldown colour on the background ("elapsed"), or, for the time left, the game fills the
-- elapsed share in the background colour over a backdrop in the cooldown colour, from the other side.
local function paintBar(st, ready)
  local p = st.p
  local cr, cg, cb = U.hex(ready and p.readyColor or p.color)
  local br, bg, bb = U.hex(p.barBackColor)
  if ready or p.barFill == "remaining" then
    st.barBack:SetVertexColor(cr, cg, cb, p.alpha)
    method(st.bar, "SetStatusBarColor", br, bg, bb, 1)
  else
    st.barBack:SetVertexColor(br, bg, bb, 1)
    method(st.bar, "SetStatusBarColor", cr, cg, cb, p.alpha)
  end
end

-- The look of the bar: size, place, border, icon at its side, the side the game fills from. The pulse covers
-- the bar. Colours come with the state (paintBar).
local function layoutBar(st)
  local frame, p = st.frame, st.p
  barOf(st)
  local host, left, withIcon = st.barHost, p.barIcon == "left", p.barIcon ~= "off"
  host:SetSize(p.barWidth, p.barHeight)
  host:ClearAllPoints()
  local shift = withIcon and (p.barHeight + BAR_GAP) / 2 * (left and 1 or -1) or 0
  host:SetPoint("CENTER", frame, "CENTER", shift, 0)
  host:Show()
  st.anchor = host
  st.cd:Hide()
  st.track:Hide()
  local edge = p.barBorder
  st.barEdge:ClearAllPoints()
  st.barEdge:SetPoint("TOPLEFT", host, "TOPLEFT", -edge, edge)
  st.barEdge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", edge, -edge)
  st.barEdge:SetColorTexture(U.hex(p.barBorderColor))
  st.barEdge:SetShown(edge > 0)
  method(st.bar, "SetReverseFill", (p.barDirection == "rtl") ~= (p.barFill == "remaining"))
  st.icon:ClearAllPoints()
  st.icon:SetSize(p.barHeight, p.barHeight)
  st.icon:SetPoint(
    left and "RIGHT" or "LEFT",
    host,
    left and "LEFT" or "RIGHT",
    (left and -1 or 1) * (BAR_GAP + edge),
    0
  )
  st.icon:SetShown(withIcon)
  st.pulse:ClearAllPoints()
  st.pulse:SetAllPoints(host)
  st.pulse:SetColorTexture(U.hex(p.readyColor))
end

-- The look of the ring: ring textures and colours, the icon inside it.
local function layoutRing(st, element)
  local frame, p = st.frame, st.p
  local side = T.SideOf(frame, element)
  local path = E.Texture(A.NearestStroke(p.shape, p.thickness, side))
  local r, g, b = U.hex(p.color)
  if st.barHost then
    st.barHost:Hide()
  end
  st.anchor = frame
  st.cd:Show()
  method(st.cd, "SetSwipeTexture", path)
  method(st.cd, "SetSwipeColor", r, g, b, p.alpha)
  method(st.cd, "SetReverse", p.reverse == true)
  local rr, rg, rb = U.hex(p.readyColor)
  st.track:SetTexture(path)
  st.track:SetVertexColor(rr, rg, rb, p.alpha)
  st.pulse:ClearAllPoints()
  st.pulse:SetAllPoints(frame)
  st.pulse:SetTexture(path)
  st.pulse:SetVertexColor(rr, rg, rb, 1)
  local inset = math.max(0, math.min(p.thickness + ICON_GAP, side / 2 - 4))
  st.icon:ClearAllPoints()
  st.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
  st.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
  st.icon:SetShown(p.icon)
end

-- The static look: the style's parts, the icon mask, fonts and places. State and numbers come later.
local function layout(st, element)
  local p = st.p
  st.style = styleOf(p)
  if st.style == "bar" then
    layoutBar(st)
  else
    layoutRing(st, element)
  end
  local round = st.style == "ring" and p.shape == "circle"
  local mask = maskOf(st)
  if mask and round ~= (st.masked == true) then
    if round then
      st.icon:AddMaskTexture(mask)
    else
      st.icon:RemoveMaskTexture(mask)
    end
    st.masked = round
  end
  styleText(st, st.timer, TEXT.timer)
  styleText(st, st.charges, TEXT.charge)
  styleEngineNumbers(st)
  placeTexts(st)
end

-- State and numbers ------------------------------------------------------------------------------------

local function stopPulse(st)
  for _, group in pairs(st.pulses or {}) do
    group:Stop()
  end
  st.pulse:Hide()
end

-- The animation group of a warning with `count` pulses, built once: the ring fades in, then out while it
-- grows. The engine plays it, no Lua runs while it does.
local function pulseGroup(st, count)
  st.pulses = st.pulses or {}
  if st.pulses[count] then
    return st.pulses[count]
  end
  local group = st.pulse:CreateAnimationGroup()
  group:SetToFinalAlpha(true)
  for i = 1, count do
    local fadeIn = group:CreateAnimation("Alpha")
    fadeIn:SetOrder(2 * i - 1)
    fadeIn:SetDuration(PULSE_IN)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    local fadeOut = group:CreateAnimation("Alpha")
    fadeOut:SetOrder(2 * i)
    fadeOut:SetDuration(PULSE_OUT)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    local grow = group:CreateAnimation("Scale")
    grow:SetOrder(2 * i)
    grow:SetDuration(PULSE_OUT)
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(PULSE_GROW, PULSE_GROW)
    grow:SetOrigin("CENTER", 0, 0)
  end
  group:SetScript("OnFinished", function()
    st.pulse:Hide()
  end)
  st.pulses[count] = group
  return group
end

-- Plays the warning of a spell that became ready (`kind` overrides the element's own choice, for the elements
-- that have none). With reduced motion the ready ring alone shows it.
local function warn(st, kind)
  local count = PULSES[kind or st.p.warn]
  if not count or st.reduce then
    return
  end
  stopPulse(st)
  st.pulse:Show()
  pulseGroup(st, count):Play()
end

local function reduceMotion(ctx)
  if ctx and ctx.reduceMotion ~= nil then
    return ctx.reduceMotion == true
  end
  local fn = ns.Theme and ns.Theme.reduceMotion
  return type(fn) == "function" and fn() == true
end

-- The clock of an element: it runs while there is time to count down in own text (`endAt`, readable values) or
-- a live value to pass on (the formatted text, the colour curve).
local function stopTick(st)
  st.endAt, st.live = nil, false
  if st.tick and st.frame:GetScript("OnUpdate") == st.tick then
    st.frame:SetScript("OnUpdate", nil)
  end
end

local refresh, applyView

-- The stages that may write the time text of the element, in order: the numeric rule formatter for a time the
-- add-on cannot read or an own duration object, the game-formatted decimal number in the seconds style.
local function stagesOf(st)
  local stages = {}
  if st.secretTime or st.ownTime then
    stages[#stages + 1] = "rule"
  end
  if st.p.timeStyle == "seconds" then
    stages[#stages + 1] = "format"
  end
  return stages
end

-- The remaining duration of the duration object goes to the text through the stages of TimeFormat (a secret
-- number in combat, never read). False when no stage can make the text, true also when there is nothing to show.
local function paintFormatted(st)
  local object, fs = st.object, st.timer
  if object == nil then
    return true
  end
  local ok, result = TFmt.Write(fs, object, st.p, stagesOf(st))
  if not ok then
    st.notes.text = result
    return false
  end
  st.notes.text, st.notes.stage = "ok", result
  fs:Show()
  return true
end

-- Whether this client can make a colour curve at all.
local function curveSupported()
  local util = rawget(_G, "C_CurveUtil")
  return type(util) == "table"
    and type(util.CreateColorCurve) == "function"
    and type(rawget(_G, "CreateColor")) == "function"
end

-- A step colour curve over the remaining seconds from points { seconds, hex colour, opacity }. nil and the
-- reason when the client cannot make it.
local function buildColorCurve(points)
  if not curveSupported() then
    return nil, "absent"
  end
  local ok, curve = pcall(_G.C_CurveUtil.CreateColorCurve)
  if not ok or curve == nil then
    return nil, ok and "no curve" or tostring(curve)
  end
  local step = enumValue("LuaCurveType", "Step")
  if step then
    invoke(curve, "SetType", step)
  end
  for _, point in ipairs(points) do
    local r, g, b = U.hex(point[2])
    local made, color = pcall(_G.CreateColor, r, g, b, point[3])
    local added, why = invoke(curve, "AddPoint", point[1], made and color or nil)
    if not (made and added) then
      return nil, made and why or tostring(color)
    end
  end
  return curve
end

-- The colour curve of the element: the last colour from 0, the middle one from `curveLow`, the first from
-- `curveMid` (each with its opacity).
local function buildCurve(p)
  return buildColorCurve({
    { 0, p.curveColorLow, p.curveAlphaLow },
    { p.curveLow, p.curveColorMid, p.curveAlphaMid },
    { p.curveMid, p.curveColorHigh, p.curveAlphaHigh },
  })
end

-- The curve of the element, rebuilt when its thresholds or colours changed.
local function curveOf(st)
  local p = st.p
  local key = table.concat({
    p.curveMid,
    p.curveLow,
    p.curveColorHigh,
    p.curveColorMid,
    p.curveColorLow,
    p.curveAlphaHigh,
    p.curveAlphaMid,
    p.curveAlphaLow,
  }, "|")
  if st.curveKey ~= key then
    st.curveKey = key
    st.curve, st.curveWhy = buildCurve(p)
  end
  return st.curve, st.curveWhy
end

-- Colours a texture or text with the colour a curve gave. The numbers of the colour may be secret: they go to
-- the widget as they are.
local function tint(target, setter, color)
  local ok, r, g, b, a = invoke(color, "GetRGBA")
  if ok then
    return invoke(target, setter, r, g, b, a)
  end
  return invoke(target, setter, color)
end

-- What the "ring" of the curve target is: the swipe of the ring, or the part of the bar that shows the
-- cooldown colour (the elapsed fill, or the backdrop when the bar shows the time left).
local function ringTarget(st)
  if st.style ~= "bar" then
    return st.cd, "SetSwipeColor"
  elseif st.p.barFill == "remaining" then
    return st.barBack, "SetVertexColor"
  end
  return st.bar, "SetStatusBarColor"
end

-- Gives the targets of the curve a colour: put(target, setter) sets it and answers true, or false and the
-- reason. The text only counts while one shows. Returns true, or false and the first reason.
local function paintTargets(st, put)
  local want = st.p.curveTarget
  local all = want == "all"
  local ok, why = true, nil
  local function apply(target, setter)
    local done, reason = put(target, setter)
    if done then
      st.tinted = true
    elseif ok then
      ok, why = false, reason
    end
  end
  if all or want == "icon" then
    apply(st.icon, "SetVertexColor")
  end
  if (all or want == "text") and st.timer:IsShown() then
    apply(st.timer, "SetTextColor")
  end
  if all or want == "ring" then
    apply(ringTarget(st))
  end
  return ok, why
end

-- The targets take the colour the curve gives for the time left.
local function paintCurve(st)
  local curve, why = curveOf(st)
  if not curve then
    st.notes.curve = why
    return
  end
  local ok, color = invoke(st.object, "EvaluateRemainingDuration", curve)
  if not ok then
    st.notes.curve = color
    return
  end
  local painted, reason = paintTargets(st, function(target, setter)
    return tint(target, setter, color)
  end)
  st.notes.curve = painted and "ok" or reason
end

-- The editor preview colours the targets from the simulated time left, the same steps as the curve.
local function paintCurvePreview(st, remaining)
  local hexColor, a = K.CurveColor(remaining, st.p)
  local r, g, b = U.hex(hexColor)
  paintTargets(st, function(target, setter)
    return invoke(target, setter, r, g, b, a)
  end)
end

-- The step curve of the show rule "below": full alpha under the threshold, none above. Its alpha goes to the
-- frame, so the engine decides without anyone comparing a secret time.
local function thresholdOf(st)
  local below = st.p.showBelow
  if st.thresholdKey ~= below then
    st.thresholdKey = below
    local points = {}
    for i, point in ipairs(SL.CurvePoints(below)) do
      points[i] = { point[1], "ffffff", point[2] }
    end
    st.threshold, st.thresholdWhy = buildColorCurve(points)
  end
  return st.threshold, st.thresholdWhy
end

-- Whether the show rule can be decided for a time the game keeps secret: a curve and a duration object.
local function canCurve(st)
  return st.object ~= nil and curveSupported()
end

-- The frame takes the alpha of the threshold curve at the time left. A refusal shows the element (better
-- seen than lost) and is kept as the reason in notes.show.
local function paintThreshold(st)
  local curve, why = thresholdOf(st)
  local ok, color = false, why
  if curve then
    ok, color = invoke(st.object, "EvaluateRemainingDuration", curve)
  end
  local shown = false
  if ok then
    local got, _, _, _, a = invoke(color, "GetRGBA")
    if got then
      shown, color = invoke(st.frame, "SetAlpha", a)
    else
      color = "no colour"
    end
  end
  st.notes.show = shown and "ok" or color
  if not shown then
    st.frame:SetAlpha(1)
  end
end

local function resetTint(st)
  if st.tinted then
    st.tinted = false
    local p = st.p
    st.icon:SetVertexColor(1, 1, 1, 1)
    local tr, tg, tb = U.hex(p.timerColor)
    st.timer:SetTextColor(tr, tg, tb, 1)
    if st.style == "bar" then
      paintBar(st, st.ready)
    else
      local r, g, b = U.hex(p.color)
      method(st.cd, "SetSwipeColor", r, g, b, p.alpha)
    end
  end
end

-- The game refused the formatted value: every element falls back to the numbers frame from now on. The styles
-- other than seconds have their own memory (TimeFormat.state): they only lose the rule formatter.
local function formattedRefused(st)
  if st.p.timeStyle == "seconds" then
    CC.diag.formattedFailed, CC.diag.formattedWhy = true, st.notes.text
  end
end

-- One step of what needs a fresh value every tick.
local function liveStep(st)
  if st.kind == "formatted" and not paintFormatted(st) then
    formattedRefused(st)
    local apply = st.applyFn or applyView
    apply(st)
    return
  end
  if st.p.colorCurve then
    paintCurve(st)
  end
  if st.viaCurve then
    paintThreshold(st)
  end
end

local function startTick(st, endAt)
  st.endAt = endAt
  if st.tick == nil then
    st.tick = function(_, elapsed)
      st.acc = st.acc + elapsed
      if st.acc < TICK then
        return
      end
      st.acc = 0
      if st.endAt then
        local left = st.endAt - now()
        if left <= 0 then
          stopTick(st)
          local again = st.refreshFn or refresh
          again(st)
          return
        end
        if st.kind == "own" then
          st.timer:SetText(K.FormatStyled(left, st.p, "own"))
        end
      end
      if st.visAt and now() >= st.visAt then
        -- The time left reached the threshold of the show rule: read again and decide anew.
        st.visAt = nil
        local again = st.refreshFn or refresh
        again(st)
        return
      end
      if st.live then
        liveStep(st)
      end
    end
  end
  if st.frame:GetScript("OnUpdate") ~= st.tick then
    st.acc = 0
    st.frame:SetScript("OnUpdate", st.tick)
  end
end

-- The look the timer takes now: the chosen one, or what stands in for it when the game does not allow it
-- (secret values for the own text, a time that no duration object carries, a formatted value or a numbers
-- frame the game refused, the ring numbers a bar does not have). The editor preview shows text only.
local function kindOf(st, s)
  local mode = st.p.timerMode
  if st.editor or (st.object == nil and s.remaining ~= nil) then
    return "own"
  end
  if mode == "formatted" and st.p.timeStyle ~= "seconds" then
    -- The styles write a readable time in own text. A time the game keeps secret, and the duration object of a
    -- computed timer, go through the game's rule formatter; without it the numbers frame shows a secret time
    -- (it counts long times as minutes and hours itself).
    local rule = st.object ~= nil and TFmt.Open("rule")
    if s.remaining == nil then
      mode = rule and "formatted" or "engineText"
    else
      mode = st.ownTime and rule and "formatted" or "own"
    end
  end
  if mode == "own" and s.remaining == nil then
    mode = "engineText"
  end
  if st.style == "bar" and mode == "engine" then
    mode = "engineText"
  end
  if mode == "formatted" and CC.diag.formattedFailed then
    mode = "engineText"
  end
  if mode == "engineText" and CC.diag.numbersFailed then
    mode = "engine"
  end
  return mode
end

-- The numbers frame counts the object's time while that is the look, else it is empty and hidden. False when
-- the game refused to feed it (every element then goes on to the ring numbers).
local function numbersView(st, kind)
  if kind ~= "engineText" or st.object == nil then
    if st.nums then
      method(st.nums, "Clear")
      st.nums:Hide()
      st.numsFed = nil
    end
    return true
  end
  local nums = numbersOf(st)
  nums:Show()
  if st.numsFed ~= st.object then
    local ok, why = invoke(nums, "SetCooldownFromDurationObject", st.object)
    st.numsFed = st.object
    st.notes.nums = ok and "ok" or why
    if not ok then
      CC.diag.numbersFailed, CC.diag.numbersWhy = true, why
      return false
    end
  end
  return true
end

-- The text of the editor preview: the style's text, in the seconds style the decimal number the formatted look
-- gives or else the own text.
local function previewText(st, remaining)
  local p = st.p
  return K.FormatStyled(remaining, p, p.timerMode == "formatted" and "formatted" or "own")
end

-- The timer text, the colour curve and the tick of state s. spec: running (a time is counting), timed (start
-- and duration are readable, `s.remaining` counts down), curve (colour the targets), idleText (the text while
-- nothing counts), viaCurve (the show rule needs a fresh engine value each tick). The timer is counted down in
-- own text while that is the chosen look and the time is readable, else drawn by the game from the duration
-- object. False when the game refused a look: the caller shows again with the stand-in.
local function paintTimer(st, s, spec)
  local p = st.p
  st.secretTime, st.ownTime = s.remaining == nil, spec.calc == true
  local kind = spec.running and kindOf(st, s) or nil
  st.kind = kind
  st.notes.kind = kind or st.notes.kind
  st.notes.stage = kind or st.notes.stage
  local text = ""
  if kind == "own" and spec.timed then
    text = st.editor and previewText(st, s.remaining) or K.FormatStyled(s.remaining, p, "own")
  elseif spec.idleText then
    text = spec.idleText
  end
  st.timer:SetText(text)
  st.timer:SetShown(text ~= "")
  method(st.cd, "SetHideCountdownNumbers", kind ~= "engine")
  if not numbersView(st, kind) then
    return false
  end
  if kind == "formatted" and not paintFormatted(st) then
    formattedRefused(st)
    return false
  end
  if kind == "engineText" and p.timerMode == "formatted" then
    st.notes.text = CC.diag.formattedWhy or TFmt.diag.why.rule
  end
  if spec.curve and (st.editor or st.object ~= nil) then
    if st.editor then
      paintCurvePreview(st, s.remaining or 0)
    else
      paintCurve(st)
    end
  else
    resetTint(st)
  end
  local live = not st.editor
    and st.object ~= nil
    and ((kind ~= nil and (kind == "formatted" or p.colorCurve)) or spec.viaCurve == true)
  if (spec.timed and not st.editor) or live then
    startTick(st, spec.timed and not st.editor and now() + s.remaining or nil)
  else
    stopTick(st)
  end
  st.live = live
  return true
end

-- Shows the state `st.s`: visibility, icon colour, the ready ring or bar, the charges and the time.
function applyView(st)
  local p, s = st.p, st.s
  if not (p and s) then
    return
  end
  local missing = s.state == "missing"
  local ready = s.state == "ready" or s.state == "gcd"
  local active = s.state == "active"
  local bar = st.style == "bar"
  local recharging = s.charges ~= nil and s.charges.current < s.charges.max
  local timed = s.remaining ~= nil and s.remaining > 0 and (active or recharging)
  local alpha, viaCurve
  if missing then
    alpha = (p.unknown == "hide" or not st.chosen) and 0 or GRAY_ALPHA
  else
    local idle
    if ready then
      idle = true
    elseif active or recharging then
      idle = false
    end
    local verdict = SL.Decide(p, { idle = idle, remaining = s.remaining, canCurve = not st.editor and canCurve(st) })
    alpha = verdict == "hide" and 0 or 1
    viaCurve = verdict == "curve"
  end
  st.viaCurve = viaCurve
  local cross = not st.editor and SL.CrossIn(p, s.remaining)
  st.visAt = cross and now() + cross or nil
  if viaCurve then
    paintThreshold(st)
  else
    st.frame:SetAlpha(alpha)
  end
  st.icon:SetDesaturated(missing or (active and p.readyMark == "saturation"))
  st.ready = ready
  st.track:SetShown(ready and not bar)
  if bar then
    paintBar(st, ready)
  end
  local ok = paintTimer(st, s, {
    running = p.timer
      and not missing
      and (active or recharging or s.state == "unknown" or (s.charged and s.charges == nil)),
    timed = timed,
    curve = p.colorCurve and (active or recharging or s.state == "unknown"),
    idleText = p.timer and ready and p.readyMark == "text" and L["cursor.cd.readyText"] or nil,
    viaCurve = viaCurve,
  })
  if not ok then
    return applyView(st)
  end
  -- The count of the charges; a secret one goes to the engine as it is.
  local count
  if p.charges and not missing and s.charged then
    if s.charges then
      count = s.charges.max > 1 and tostring(s.charges.current) or nil
    else
      count = s.chargesRaw
    end
  end
  local shown = count ~= nil and pcall(st.charges.SetText, st.charges, count)
  if not shown then
    st.charges:SetText("")
  end
  st.charges:SetShown(shown)
end

-- Running cooldowns --------------------------------------------------------------------------------------

-- The elements whose cooldown runs, checked together by one frame that has a script only while there is one.
local watched, watchedCount = {}, 0
local driver, driverStep
local pollAcc = 0

-- The end of a cooldown comes without an event. isActive and IsZero stay readable in combat, so one look at
-- them tells it; the element then reads everything again and goes the same way as for any other end.
local function pollOne(st)
  local res = st.res
  if not (res and st.src) then
    return
  end
  CC.diag.polls = CC.diag.polls + 1
  local object = st.s and st.s.charged and st.src.chargeDuration(res.id) or st.src.duration(res.id, res)
  if K.Poll(activeOf(st.src.info(res.id, res)), zeroOf(object)) == "ready" then
    refresh(st)
  end
end

local function pollStep(_, elapsed)
  pollAcc = pollAcc + elapsed
  if pollAcc < POLL then
    return
  end
  pollAcc = 0
  for st in pairs(watched) do
    pollOne(st)
  end
end

local function track(st, on)
  if on and not watched[st] then
    watched[st] = true
    watchedCount = watchedCount + 1
    if watchedCount == 1 then
      driver = driver or CreateFrame("Frame")
      driverStep = driverStep or ns.Wrap("cursorcooldowns-poll", pollStep)
      pollAcc = 0
      driver:SetScript("OnUpdate", driverStep)
    end
  elseif not on and watched[st] then
    watched[st] = nil
    watchedCount = watchedCount - 1
    if watchedCount == 0 then
      driver:SetScript("OnUpdate", nil)
    end
  end
end

-- How many cooldowns are checked now and the script of the checking frame (nil while none is).
function CC.Polling()
  return watchedCount, driver and driver:GetScript("OnUpdate") or nil
end

-- Sets the state, plays the warning when a cooldown ended, shows it.
local function setState(st, s)
  local event = K.Transition(st.state, s.state, s.ended)
  st.s, st.state = s, s.state
  track(st, s.state == "active" and st.driven == true and not st.editor)
  applyView(st)
  if event and st.driven then
    CC.diag.last = { event = event, at = try(api(nil, "date"), "%H:%M:%S") }
  end
  if event == "ready" then
    warn(st)
  end
end

-- The state of a cooldown the game keeps secret: the duration object says whether it is zero, else the
-- Cooldown frame (fed with it) knows its length, else the frame has told the end. Without an object nothing
-- was fed, the frame's empty length would pass for ready.
local function engineState(st, object)
  if object ~= nil then
    local zero = zeroOf(object)
    if zero == true then
      return "ready"
    elseif zero == false then
      return "active"
    end
    local length = readable(try(methodOf(st.cd, "GetCooldownDuration"), st.cd))
    if length ~= nil then
      return length > 0 and "active" or "ready"
    end
  end
  if st.done then
    return "ready"
  end
  return nil
end

local function resolve(st)
  local p = st.p
  st.src = SOURCES[p.source] or SOURCES.spell
  st.res = st.src.resolve(p)
  st.chosen = st.src.chosen(p)
  st.own = { source = p.source, ids = st.res and st.res.ids or {}, slot = st.res and st.res.slot or nil }
  st.notes.id = st.res and st.res.id or nil
end

-- Feeds the ring (and the bar, in that style) from the duration object, or empties them.
local function feed(st, object)
  st.object = object
  if object ~= nil then
    local ok, why = invoke(st.cd, "SetCooldownFromDurationObject", object)
    st.notes.ring = ok and "ok" or why
    if st.style == "bar" then
      local filled, reason = invoke(st.bar, "SetTimerDuration", object)
      st.notes.bar = filled and "ok" or reason
    end
  else
    method(st.cd, "Clear")
    if st.style == "bar" then
      method(st.bar, "SetValue", 0)
    end
  end
end

-- Reads the game again and shows the result: which spell, its cooldown, charges, and the ring fed from the
-- right duration object.
function refresh(st)
  local p, res = st.p, st.res
  if not p or st.editor then
    return
  end
  if not res or res.known == false then
    feed(st, nil)
    setState(st, { state = "missing" })
    return
  end
  local src, id = st.src, res.id
  local charges = src.charges(id)
  local f = fieldsOf(src.info(id, res), charges)
  local gcd = src.hasGcd and f.isOnGCD == nil and f.duration and gcdLength() or nil
  local s = K.State(f, now(), gcd)
  s.charged = type(charges) == "table"
  s.chargesRaw = f.raw and f.raw.currentCharges
  local object
  if s.charged then
    if not (s.charges and s.charges.current >= s.charges.max) then
      object = src.chargeDuration(id)
    end
  elseif s.state == "active" or s.state == "unknown" then
    object = src.duration(id, res)
  end
  feed(st, object)
  if s.state == "unknown" then
    s.state = engineState(st, object) or "unknown"
  end
  s.ended = st.done == true
  st.done = nil
  setState(st, s)
end

-- Events ----------------------------------------------------------------------------------------------

-- A payload value the game does not keep secret, else nil.
local function plain(v)
  if hidden(v) then
    return nil
  end
  return v
end

local hub = T.NewHub({
  "SPELL_UPDATE_COOLDOWN",
  "SPELL_UPDATE_CHARGES",
  "SPELLS_CHANGED",
  "LEARNED_SPELL_IN_SKILL_LINE",
  "PET_BAR_UPDATE_COOLDOWN",
  "BAG_UPDATE_COOLDOWN",
  "ACTIONBAR_UPDATE_COOLDOWN",
  "PLAYER_EQUIPMENT_CHANGED",
  "BAG_UPDATE",
}, {
  { "UNIT_SPELLCAST_SUCCEEDED", "player", "pet" },
  { "UNIT_PET", "player" },
}, function(st, event, a1, a2, a3)
  if not st.own then
    return
  end
  local action = K.Route(event, st.own, plain(a1), plain(a2), plain(a3))
  if action == "resolve" then
    resolve(st)
    paintIcon(st)
  end
  if action then
    refresh(st)
  end
end, "cursorcooldowns-event")

-- Number of elements that are drawn in the game and so listen, for the diagnosis and tests.
function CC.Listening()
  return hub.Count()
end

-- What the game answered to the calls of one drawn element, for the diagnosis window: { id = the spell id,
-- kind = the look in use, ring, nums, text, curve = "ok", "absent" or an error text }, nil for a frame
-- without an element.
function CC.Notes(frame)
  local st = frame and frame.fgCooldown
  return st and st.notes or nil
end

CC.PlayerClass = playerClass

-- The duration object of the cooldown the props choose (the test window feeds its own bar with it), nil when
-- nothing is chosen or the character does not have it.
function CC.ObjectOf(p)
  local src = SOURCES[p.source] or SOURCES.spell
  local res = src.resolve(p)
  if not res or res.known == false then
    return nil
  end
  return src.duration(res.id, res)
end

-- Drawing ---------------------------------------------------------------------------------------------

-- The editor preview: a cooldown that runs down, or the ready state, from the simulation (a still ring
-- while none runs). The charges show as 2 of 3.
local function preview(st, ctx)
  local progress = T.PreviewProgress(ctx, "cdProgress")
  local s = { state = "ready", charged = true, charges = { current = 3, max = 3 } }
  if progress ~= false then
    s = {
      state = "active",
      charged = true,
      charges = { current = 2, max = 3 },
      remaining = (1 - progress) * CC.SAMPLE_SECONDS,
    }
  end
  if st.style == "bar" then
    method(st.bar, "SetValue", progress or 0)
  else
    T.FreezeRing(st, progress)
  end
  setState(st, s)
end

-- What makes an element follow something else or show it another way: a change reads the game again.
local function identity(p)
  return table.concat({ p.source, p.spellBase, p.itemMode, p.itemSlot, p.itemId, p.timerMode, p.style }, "|")
end

local function render(frame, element, ctx)
  local p = CU.Props("spellcd", element.props)
  local st = widgetOf(frame)
  local key = identity(p)
  local changed = st.identity ~= nil and st.identity ~= key
  st.identity = key
  st.p, st.editor, st.reduce = p, ctx and ctx.editor == true, reduceMotion(ctx)
  layout(st, element)
  paintIcon(st)
  if st.editor then
    preview(st, ctx)
  elseif changed and st.driven then
    resolve(st)
    paintIcon(st)
    refresh(st)
  elseif st.s then
    applyView(st)
  end
end

local function drive(frame, _, ctx)
  local st = frame.fgCooldown
  if (ctx and ctx.editor) or not st then
    return
  end
  st.driven = true
  hub.Add(frame, st)
  method(st.cd, "SetScript", "OnCooldownDone", function()
    if st.driven then
      st.done = true
      refresh(st)
    end
  end)
  resolve(st)
  paintIcon(st)
  refresh(st)
end

local function release(frame)
  hub.Remove(frame)
  local st = frame.fgCooldown
  if st then
    st.driven = false
    track(st, false)
    stopTick(st)
    stopPulse(st)
    feed(st, nil)
    numbersView(st, nil)
    resetTint(st)
    st.s, st.state, st.res, st.own = nil, nil, nil, nil
    st.frame:SetAlpha(1)
  end
end

-- Simulation (editor) ----------------------------------------------------------------------------------

-- A cooldown that runs down, then a rest, in a loop; step writes the elapsed share, false while ready.
S.RegisterSource("spellcd", {
  reset = function(sim)
    sim.cdProgress = nil
  end,
  step = function(sim, _, t)
    local c = t % (CC.SAMPLE_SECONDS + SIM_PAUSE)
    sim.cdProgress = c < CC.SAMPLE_SECONDS and c / CC.SAMPLE_SECONDS or false
  end,
})

-- Panel -----------------------------------------------------------------------------------------------

local function controls()
  return ns.CanvasEditor.Controls
end

-- Lays the rows out again after a change that shows or hides rows.
local function restack(state)
  local panel = state.panel
  if type(rawget(panel, "Refresh")) == "function" then
    panel:Refresh()
  end
end

-- The locale key of a control's tooltip text: the label's own `.tip`, unless `tip` names another.
local function tipOf(label, tip)
  return tip or (label .. ".tip")
end

local function toggleRow(state, add, label, key, shown, tip)
  local C = controls()
  add(
    C.Toggle(state.panel, {
      label = label,
      tooltip = label,
      tooltipText = tipOf(label, tip),
      get = function()
        return state.get(key)
      end,
      set = function(on)
        state.write(key, on == true)
        restack(state)
      end,
    }),
    C.HEIGHT.toggle,
    shown
  )
end

-- `optionTips`: every option carries the tooltip `<label>.<value>.tip`.
local function choiceRow(state, add, label, key, list, shown, optionTips)
  local C = controls()
  add(
    C.Choice(state.panel, {
      label = label,
      tooltip = label,
      tooltipText = tipOf(label),
      options = C.Choices(list, label .. ".", optionTips),
      get = function()
        return state.get(key)
      end,
      set = function(value)
        state.write(key, value)
        restack(state)
      end,
    }),
    C.HEIGHT.choice,
    shown
  )
end

local function sliderRow(state, add, label, key, spec, shown)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = label,
      tooltipText = tipOf(label, spec.tip),
      min = spec.min,
      max = spec.max,
      step = spec.step,
      format = spec.format,
      get = function()
        return state.get(key)
      end,
      set = function(v)
        state.write(key, v)
      end,
    }),
    C.HEIGHT.slider,
    shown
  )
end

-- The tooltip texts of the font rows, which carry labels shared with other panels.
local FONT_TIPS = {
  font = "cursor.cd.tip.font",
  size = "cursor.cd.tip.size",
  outline = "cursor.cd.tip.outline",
  shadow = "cursor.cd.tip.shadow",
}

-- Font, size, outline and shadow of a text, shown while `shown` says so.
local function fontRows(state, add, keys, shown)
  local C = controls()
  add(
    C.Font(state.panel, {
      label = "xpbar.panel.font",
      tooltip = "xpbar.panel.font",
      tooltipText = FONT_TIPS.font,
      get = function()
        return state.get(keys.font)
      end,
      set = function(key)
        state.write(keys.font, key)
      end,
    }),
    C.HEIGHT.choice,
    shown
  )
  sliderRow(state, add, "xpbar.panel.size", keys.size, {
    min = XB.SIZE_MIN,
    max = XB.SIZE_MAX,
    step = 1,
    tip = FONT_TIPS.size,
  }, shown)
  add(
    C.Choice(state.panel, {
      label = "xpbar.panel.outline",
      tooltip = "xpbar.panel.outline",
      tooltipText = FONT_TIPS.outline,
      options = C.Choices(XB.OUTLINES, "xpbar.panel.outline."),
      get = function()
        return state.get(keys.outline)
      end,
      set = function(value)
        state.write(keys.outline, value)
      end,
    }),
    C.HEIGHT.choice,
    shown
  )
  add(
    C.Toggle(state.panel, {
      label = "xpbar.panel.shadow",
      tooltip = "xpbar.panel.shadow",
      tooltipText = FONT_TIPS.shadow,
      get = function()
        return state.get(keys.shadow)
      end,
      set = function(on)
        state.write(keys.shadow, on == true)
      end,
    }),
    C.HEIGHT.toggle,
    shown
  )
end

local function seconds(v)
  return string.format("%g s", v)
end

-- Colour and opacity of one step of the curve (`step` is High, Mid or Low).
local function curveColorRow(state, add, step, default, shown)
  local C = controls()
  local label = "cursor.cd.curveColor" .. step
  add(
    C.ColorAlpha(state.panel, {
      label = label,
      tooltipText = tipOf(label),
      owner = state.owner(),
      default = default,
      get = function()
        return state.get("curveColor" .. step)
      end,
      alpha = function()
        return state.get("curveAlpha" .. step)
      end,
      set = function(color, alpha)
        state.write("curveColor" .. step, color)
        state.write("curveAlpha" .. step, alpha)
      end,
    }),
    C.HEIGHT.colorAlpha,
    shown
  )
end

-- What the colour curve takes (the text, the icon, the ring), its two thresholds and its three colours, shown
-- while it is on.
local function curveRows(state, add, shown)
  choiceRow(state, add, "cursor.cd.curveTarget", "curveTarget", CC.CURVE_TARGETS, shown)
  sliderRow(
    state,
    add,
    "cursor.cd.curveMid",
    "curveMid",
    { min = 2 * CURVE_MIN, max = CURVE_MAX, step = CURVE_STEP, format = seconds },
    shown
  )
  sliderRow(
    state,
    add,
    "cursor.cd.curveLow",
    "curveLow",
    { min = CURVE_MIN, max = CURVE_MAX - CURVE_STEP, step = CURVE_STEP, format = seconds },
    shown
  )
  curveColorRow(state, add, "High", "ffffff", shown)
  curveColorRow(state, add, "Mid", "ffd24a", shown)
  curveColorRow(state, add, "Low", "ff4d4d", shown)
end

-- The size and look of the bar, shown while the style is the bar.
local function barRows(state, add, shown)
  local C = controls()
  sliderRow(state, add, "cursor.cd.barWidth", "barWidth", { min = BAR_W_MIN, max = BAR_W_MAX, step = 1 }, shown)
  sliderRow(state, add, "cursor.cd.barHeight", "barHeight", { min = BAR_H_MIN, max = BAR_H_MAX, step = 1 }, shown)
  choiceRow(state, add, "cursor.cd.barDirection", "barDirection", CC.BAR_DIRECTIONS, shown)
  choiceRow(state, add, "cursor.cd.barFill", "barFill", CC.BAR_FILLS, shown)
  choiceRow(state, add, "cursor.cd.barIcon", "barIcon", CC.BAR_ICONS, shown)
  C.ColorRow(state, add, "cursor.cd.barBackColor", "barBackColor", "1a1a1a", shown, tipOf("cursor.cd.barBackColor"))
  sliderRow(state, add, "cursor.cd.barBorder", "barBorder", { min = 0, max = BAR_BORDER_MAX, step = 1 }, shown)
  C.ColorRow(
    state,
    add,
    "cursor.cd.barBorderColor",
    "barBorderColor",
    "000000",
    shown,
    tipOf("cursor.cd.barBorderColor")
  )
end

-- Name and icon of the item the props choose, for the item control: a slot by its name (and the item worn
-- there), an item by its id; nil when none is chosen.
local function itemFacts(p)
  local items = ns.MacroItems
  local res = SOURCES.item.resolve(p)
  local name = res.id > 0 and items.clientName(res.id) or nil
  if p.itemMode == "slot" then
    local text = string.format(L["cursor.cd.item.slot"], items.slotName(p.itemSlot), p.itemSlot)
    return name and (text .. ": " .. name) or text, res.id > 0 and SOURCES.item.texture(res.id, res) or nil
  end
  if p.itemId <= 0 then
    return nil
  end
  return name or ("ID " .. p.itemId), SOURCES.item.texture(p.itemId, res)
end

CC.ItemFacts = itemFacts

-- The conditions the rows of the shared look depend on, for one panel state.
local function lookConds(state)
  local c = {}
  function c.on(key, value)
    return function()
      return state.get(key) == value
    end
  end
  function c.both(a, b)
    return function()
      return a() and b()
    end
  end
  function c.negate(fn)
    return function()
      return not fn()
    end
  end
  c.bar = c.on("style", "bar")
  c.ring = c.negate(c.bar)
  c.timerOn = function()
    return state.get("timer")
  end
  c.curveOn = function()
    return state.get("colorCurve")
  end
  c.ownOn = c.both(c.timerOn, c.on("timerMode", "own"))
  c.formattedOn = c.both(c.timerOn, c.on("timerMode", "formatted"))
  -- The time format applies to the two looks that write text: the decimal number and the own text.
  c.styledOn = c.both(c.timerOn, function()
    return state.get("timerMode") == "formatted" or state.get("timerMode") == "own"
  end)
  -- The digits and the s belong to the auto and short styles and to the seconds style of the decimal number; the
  -- minutes-and-hours choice to the auto style and to the seconds style of the own text.
  c.decimalsOn = c.both(c.styledOn, function()
    local style = state.get("timeStyle")
    return style == "auto" or style == "short" or (style == "seconds" and state.get("timerMode") == "formatted")
  end)
  c.longOn = c.both(c.styledOn, function()
    local style = state.get("timeStyle")
    return style == "auto" or (style == "seconds" and state.get("timerMode") == "own")
  end)
  return c
end

-- Times the preview line writes in the chosen format: a decimal, seconds, minutes and an hour and more.
local SAMPLE_TIMES = { 4.2, 45, 1745, 4500 }

-- A line that shows the chosen time format on the sample times.
local function timeSampleRow(state, add, shown)
  local row = CreateFrame("Frame", nil, state.panel)
  row:SetHeight(16)
  local text = ns.W.Text(row, { text = "", role = "ui", color = "textMuted" })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  function row:Refresh()
    local p = {
      timeStyle = state.get("timeStyle"),
      timeFormat = state.get("timeFormat"),
      timeDecimals = state.get("timeDecimals"),
      timeSuffix = state.get("timeSuffix"),
    }
    local list = {}
    for i, sample in ipairs(SAMPLE_TIMES) do
      list[i] = K.FormatStyled(sample, p, state.get("timerMode") == "formatted" and "formatted" or "own")
    end
    ns.W.SetText(text, nil, string.format(L["cursor.cd.timeSample"], table.concat(list, "  ")))
  end
  row:Refresh()
  return add(row, 16, shown)
end

-- Style, ring or bar, colours and direction: the rows both elements share. `readyLabel` names the colour of the
-- state without a count (ready for a cooldown, missing for an aura).
function CC.StyleRows(state, add, c, readyLabel, readyShown)
  local C = controls()
  local noBarOn = c.both(c.bar, function()
    return not barSupported()
  end)
  choiceRow(state, add, "cursor.cd.style", "style", CC.STYLES)
  C.TextRow(state, add, "cursor.cd.barMissing", nil, noBarOn)
  toggleRow(state, add, "cursor.cd.icon", "icon", c.ring)
  choiceRow(state, add, "cursor.cd.shape", "shape", CC.FORMS, c.ring)
  T.Rows.thickness(state, add, c.ring, "cursor.cd.thickness.tip")
  T.Rows.color(state, add, "cursor.cd.color", "cursor.cd.color.tip")
  C.ColorRow(state, add, readyLabel, "readyColor", "3fd05c", readyShown, tipOf(readyLabel))
  toggleRow(state, add, "cursor.panel.fills", "reverse", c.ring, "cursor.cd.fills.tip")
  barRows(state, add, c.bar)
end

-- The show rule: the choice and, for "below", the number of seconds. `list` holds the rules the element knows.
function CC.ShowRows(state, add, list)
  choiceRow(state, add, "cursor.show.when", "showWhen", list, nil, true)
  sliderRow(state, add, "cursor.show.below", "showBelow", {
    min = SL.BELOW_MIN,
    max = SL.BELOW_MAX,
    step = SL.BELOW_STEP,
    format = seconds,
  }, function()
    return state.get("showWhen") == "below"
  end)
end

-- The timer text section and the colour curve.
function CC.TimerRows(state, add, c)
  local C = controls()
  local failedOn = c.both(c.formattedOn, function()
    return CC.diag.formattedFailed
  end)
  -- The styles other than seconds need the game's rule formatter for a time in combat.
  local ruleOn = c.both(c.formattedOn, function()
    return state.get("timeStyle") ~= "seconds" and not TFmt.Open("rule")
  end)
  local numbersOn = c.both(function()
    return state.get("timerMode") ~= "own" and state.get("timerMode") ~= "engine"
  end, function()
    return c.timerOn() and CC.diag.numbersFailed
  end)
  local textColorOn = c.both(c.timerOn, c.negate(c.curveOn))
  local missingOn = c.both(c.curveOn, function()
    return not curveSupported()
  end)
  local posOn = c.both(c.timerOn, function()
    return PL.TimerPositionShown({ timerMode = state.get("timerMode"), style = state.get("style") })
  end)
  state.section("timer", "cursor.cd.timerSection", false)
  toggleRow(state, add, "cursor.cd.timer", "timer")
  choiceRow(state, add, "cursor.cd.timerMode", "timerMode", CC.TIMER_MODES, c.timerOn, true)
  C.TextRow(state, add, "cursor.cd.formattedFailed", nil, failedOn)
  C.TextRow(state, add, "cursor.cd.ruleFailed", nil, ruleOn)
  C.TextRow(state, add, "cursor.cd.numbersFailed", nil, numbersOn)
  choiceRow(state, add, "cursor.cd.timerPos", "timerPos", CC.POSITIONS, posOn)
  choiceRow(state, add, "cursor.cd.timeStyle", "timeStyle", K.TIME_STYLES, c.styledOn, true)
  timeSampleRow(state, add, c.styledOn)
  choiceRow(state, add, "cursor.cd.timeFormat", "timeFormat", K.TIME_FORMATS, c.longOn)
  choiceRow(state, add, "cursor.cd.timeDecimals", "timeDecimals", K.DECIMALS, c.decimalsOn)
  toggleRow(state, add, "cursor.cd.timeSuffix", "timeSuffix", c.decimalsOn)
  fontRows(state, add, TEXT.timer, c.timerOn)
  C.ColorRow(state, add, "cursor.cd.timerColor", "timerColor", "ffffff", textColorOn, tipOf("cursor.cd.timerColor"))
  toggleRow(state, add, "cursor.cd.colorCurve", "colorCurve")
  C.TextRow(state, add, "cursor.cd.curveMissing", nil, missingOn)
  curveRows(state, add, c.curveOn)
end

CC.Rows = { toggle = toggleRow, choice = choiceRow, slider = sliderRow, font = fontRows, seconds = seconds }
CC.LookConds = lookConds
CC.TEXT = TEXT

-- The locale key of the line a note of PanelLogic.CooldownStatus stands for.
local STATUS_NOTES = {
  below = "cursor.cd.status.below",
  curve = "cursor.cd.curveMissing",
  bar = "cursor.cd.barMissing",
  nothing = "cursor.cd.status.nothing",
  item = "cursor.cd.itemNoObject",
}

-- What the cooldown element does in combat for the repaired props `p`, for the panel line:
-- { key, color, text }.
function CC.Status(p)
  local itemOk = p.source ~= "item" or CC.ItemObjectAvailable(SOURCES.item.resolve(p).id)
  local status = PL.CooldownStatus(p, { itemObject = itemOk, curve = curveSupported(), bar = barSupported() })
  local lines = {}
  if status.key ~= "none" then
    lines[1] = L["cursor.cd.status.native"]
  end
  for _, note in ipairs(status.notes) do
    lines[#lines + 1] = L[STATUS_NOTES[note]]
  end
  return { key = status.key, color = status.color, text = table.concat(lines, "\n") }
end

function CC.Panel(parent, element, onChange)
  return controls().NewPanel(parent, {
    element = element,
    kind = "spellcd",
    onChange = onChange,
    props = function(raw)
      return CU.Props("spellcd", raw)
    end,
    build = function(state, add)
      local C = controls()
      local c = lookConds(state)
      local item = c.on("source", "item")
      local spell = c.negate(item)
      local noObjectOn = c.both(item, function()
        return not CC.ItemObjectAvailable(SOURCES.item.resolve(CU.Props("spellcd", state.element.props)).id)
      end)
      C.StatusRow(state, add, function()
        return CC.Status(CU.Props("spellcd", state.element.props))
      end)
      state.section("basics", "canvas.sec.basics")
      choiceRow(state, add, "cursor.cd.source", "source", K.SOURCES)
      add(
        C.Spell(state.panel, {
          label = "cursor.cd.spell",
          tooltipText = "cursor.cd.spell.tip",
          class = function()
            return playerClass() or "ALL"
          end,
          get = function()
            local id = state.get("spellBase")
            return id > 0 and id or nil
          end,
          set = function(id)
            state.write("spellBase", id and K.BaseOf(id) or 0)
          end,
        }),
        C.HEIGHT.spell,
        spell
      )
      add(
        C.Item(state.panel, {
          label = "cursor.cd.item",
          title = "cursor.cd.itemPicker",
          tooltipText = "cursor.cd.item.tip",
          search = function(query, opts)
            return ns.MacroItems.searchUsable(query, opts)
          end,
          describe = function()
            local p = CU.Props("spellcd", state.element.props)
            return itemFacts(p)
          end,
          set = function(row)
            if row == nil then
              state.write("itemMode", "id")
              state.write("itemId", 0)
            elseif row.slot then
              state.write("itemMode", "slot")
              state.write("itemSlot", row.slot)
            else
              state.write("itemMode", "id")
              state.write("itemId", row.id)
            end
          end,
        }),
        C.HEIGHT.spell,
        item
      )
      C.TextRow(state, add, "cursor.cd.itemNoObject", nil, noObjectOn)
      state.section("look", "canvas.sec.look")
      CC.StyleRows(state, add, c, "cursor.cd.readyColor", function()
        return PL.ReadyColorShown("spellcd", { showWhen = state.get("showWhen"), warn = state.get("warn") })
      end)
      state.section("behavior", "canvas.sec.behavior", false)
      choiceRow(state, add, "cursor.cd.readyMark", "readyMark", CC.READY_MARKS)
      CC.ShowRows(state, add, SL.SHOW_WHEN)
      choiceRow(state, add, "cursor.cd.warn", "warn", CC.WARNINGS)
      choiceRow(state, add, "cursor.cd.unknown", "unknown", CC.UNKNOWNS)
      state.section("charges", "cursor.cd.chargesSection", false)
      toggleRow(state, add, "cursor.cd.charges", "charges", spell)
      fontRows(
        state,
        add,
        TEXT.charge,
        c.both(spell, function()
          return state.get("charges")
        end)
      )
      CC.TimerRows(state, add, c)
      state.section(nil)
      C.TextRow(state, add, "cursor.cd.note")
    end,
  })
end

-- Presets ---------------------------------------------------------------------------------------------

-- A ring with the cooldown of a well-known spell of the class, so the element has something to show.
CU.RegisterPreset("spellcd", function(el, build)
  return build("spellcd", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("spellcd", "spellcd", 56, 56, { spellBase = K.Sample(playerClass()) or 0 }),
  })
end)

-- The parts of the element the aura element builds on: the widgets and their look, the timer text, the colour
-- curve, the show rule's threshold and the guarded calls. An element that uses them sets `st.refreshFn` and
-- `st.applyFn` (what to run when the time ends and when a look has to be shown again with the stand-in).
CC.Kit = {
  widgetOf = widgetOf,
  layout = layout,
  feed = feed,
  paintTimer = paintTimer,
  paintBar = paintBar,
  paintThreshold = paintThreshold,
  canCurve = canCurve,
  stopTick = stopTick,
  resetTint = resetTint,
  numbersView = numbersView,
  reduceMotion = reduceMotion,
  warn = warn,
  invoke = invoke,
  methodOf = methodOf,
  flagOf = flagOf,
  zeroOf = zeroOf,
  enumValue = enumValue,
  curveSupported = curveSupported,
  curveOf = curveOf,
  tint = tint,
}

-- Registry ---------------------------------------------------------------------------------------------

E.Register("spellcd", { render = render, drive = drive, release = release, panel = CC.Panel })
