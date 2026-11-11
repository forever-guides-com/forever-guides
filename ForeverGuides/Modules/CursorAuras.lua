-- Aura element of the mouse cursor ring (ns.CursorAuras, type "aura"): a buff or debuff of the player, target,
-- focus or pet, or the activation glow of a spell (a proc such as Revenge), as a ring or square around its icon or
-- as a status bar, with the stacks and a timer text. It shows while the aura is there, only while it is gone
-- (a buff that fell off), or always (dimmed while gone), and by the shared show rule (CursorCooldowns.ShowRows)
-- only below a time left. The look, the timer text, the colour curve and the threshold curve are the ones of the
-- cooldown element (CursorCooldowns.Kit); the logic lives in AuraLogic and ShowLogic, this file talks to the game.
--
-- An aura is found by its spell id (GetPlayerAuraBySpellID, GetUnitAuraBySpellID), else by a scan of the unit's
-- auras. In combat the game may withhold both (the lookup then finds nothing): a miss proves nothing while
-- C_Secrets says auras are secret (AuraLogic.Presence). The element then keeps the aura instance it saw before
-- the fight: a removal event ends it, the duration object of that instance keeps ring and number going, else
-- the state before the fight stays (combatStale: keep, hide or dim). The time left comes as a duration object
-- (GetAuraDuration) the engine draws and formats; a time the game keeps secret is never compared: the show rule
-- "below" lets the engine evaluate a step curve on the duration object and takes its alpha. The stacks come as the
-- game's own display text (GetAuraApplicationDisplayCount) or, readable, as a number from two. A proc is read
-- as the overlay of the spell (IsSpellOverlayed, the glow events), as an aura by id, or both (procMode); a boolean
-- the game keeps secret goes to SetAlphaFromBoolean. Events trigger a read, a slow check catches what they miss.
--
-- The source "weapon" follows the temporary enchantment of a weapon (a poison, sharpening stone, oil or shaman weapon
-- buff), which is no aura. WeaponEnchantLogic reads both hands (C_PaperDollInfo.GetTemporaryEnchantmentInfo, else
-- GetWeaponEnchantInfo), the events of the inventory and the slow check keep it current, and the ring runs on the
-- element's own duration object. A reading the game keeps secret keeps the last readable run going until its end.
-- The weapon element (CursorWeapon.lua, type "weapon") has the props, the panel and the preset of its own and draws
-- through this file: propsOf turns its props into the ones of an aura element with the source "weapon".
--
-- In combat the element can show a buff or debuff of the player through the native aura container (AuraNative):
-- the engine fills icon, ring, number and stacks and Lua reads nothing. The element keeps the read and computed
-- state running underneath, because the show rule "below" and the condition "missing" are decided from it. The
-- native display is on only in combat; outside it the read display shows, which has every option.
local _, ns = ...
local W, L, CU, E, S = ns.W, ns.L, ns.CursorLogic, ns.CursorElements, ns.CursorSim
local T, CC, AL, SL, K = ns.CursorTimers, ns.CursorCooldowns, ns.AuraLogic, ns.ShowLogic, ns.CooldownCore
local TR = ns.AuraTrack
local NL, AN, PL = ns.AuraNativeLogic, ns.AuraNative, ns.PanelLogic
local WE, WF, U = ns.WeaponEnchantLogic, ns.WellFedLogic, ns.U
local Kit = CC.Kit
local G = T.Guard
local hidden, readable, now, api, try, method = G.hidden, G.readable, G.now, G.api, G.try, G.method
local invoke = Kit.invoke

local AU = {}
ns.CursorAuras = AU

-- What the diagnosis window (/fg auratest) reads: the checks of the slow timer, the variant a proc used last and
-- the computed timer (whether the cast event gave a readable spell id, which signal started the last run).
AU.diag = { polls = 0, procVia = nil, track = { castReadable = nil, via = nil, activations = 0 } }
-- Length of the aura the editor preview counts down.
AU.SAMPLE_SECONDS = 12
-- The color of the ring that stands for a missing weapon enchantment.
AU.WEAPON_MISSING_COLOR = "ff4d4d"
local SIM_PAUSE = 3
local POLL = 0.5
local UNKNOWN_ICON = 134400
local SCAN_MAX = 60

ns.AddLocale("enUS", {
  ["cursor.type.aura"] = "Aura",
  ["cursor.type.aura.desc"] = "Shows a buff or debuff, or the glow of a proc such as Revenge, as a ring, square or status bar. Can show only while the aura is missing, or only when little time is left.",
  ["cursor.preset.aura"] = "Aura (buff missing)",
  ["cursor.aura.source"] = "Source",
  ["cursor.aura.source.tip"] = "An aura (buff or debuff) on a unit, or the glow a spell gets when it procs.",
  ["cursor.aura.source.aura"] = "Aura (buff or debuff)",
  ["cursor.aura.source.proc"] = "Proc (spell glow)",
  ["cursor.preset.wellfed"] = "Well Fed (missing)",
  ["cursor.aura.unit"] = "Unit",
  ["cursor.aura.unit.tip"] = "Whose auras are looked at.",
  ["cursor.aura.unit.player"] = "You",
  ["cursor.aura.unit.target"] = "Target",
  ["cursor.aura.unit.focus"] = "Focus",
  ["cursor.aura.unit.pet"] = "Pet",
  ["cursor.aura.mineOnly"] = "Only my own auras",
  ["cursor.aura.mineOnly.tip"] = "Counts only auras you or your pet applied. Switched on by default for target and focus.",
  ["cursor.aura.spell"] = "Aura or spell",
  ["cursor.aura.spell.tip"] = "Opens the spell list with search. The saved base ID counts for all ranks.",
  ["cursor.aura.wellFed"] = "Any Well Fed buff counts",
  ["cursor.aura.wellFed.tip"] = "Every food gives its own Well Fed buff with another spell ID. On (default): the element counts any of them, found by ID and by the name Well Fed. Off: only the spell you chose counts.",
  ["cursor.aura.rank"] = "Rank",
  ["cursor.aura.rank.tip"] = "Which rank of the chosen spell counts. Highest rank matches every rank of the spell, so a new rank needs no change here. Chosen ID matches exactly the spell you picked, with its rank.",
  ["cursor.aura.rank.max"] = "Highest rank (default)",
  ["cursor.aura.rank.max.tip"] = "Any rank of the spell counts as the aura or proc.",
  ["cursor.aura.rank.exact"] = "Chosen ID only",
  ["cursor.aura.rank.exact.tip"] = "Only the spell ID you picked counts. Pick the spell again to choose its rank. A layout saved before this option has no exact ID yet and uses the first rank.",
  ["cursor.aura.spellId"] = "Spell ID",
  ["cursor.aura.spellId.tip"] = "Types the spell ID of the aura, or of the spell for a proc. Enter or leaving the field saves it.",
  ["cursor.aura.current"] = "Current auras...",
  ["cursor.aura.current.tip"] = "Lists the auras you have right now. Out of combat only, the game hides them in combat. A click takes the aura.",
  ["cursor.aura.picker.title"] = "Choose an aura",
  ["cursor.aura.picker.search"] = "Search by name or ID",
  ["cursor.aura.picker.empty"] = "No readable auras",
  ["cursor.aura.picker.emptyHint"] = "Auras can only be read out of combat. Type an ID to take it directly.",
  ["cursor.aura.picker.line"] = "ID %d",
  ["cursor.aura.picker.line.time"] = "ID %d, %s s",
  ["cursor.aura.procMode"] = "Read the proc by",
  ["cursor.aura.procMode.tip"] = "How the proc is found. Automatic takes the glow of the spell and an aura by ID together and uses whichever answers.",
  ["cursor.aura.procMode.auto"] = "Automatic (glow and aura)",
  ["cursor.aura.procMode.overlay"] = "Spell glow only",
  ["cursor.aura.procMode.aura"] = "Aura only",
  ["cursor.aura.procAuraId"] = "Proc aura ID",
  ["cursor.aura.procAuraId.tip"] = "The ID of the aura the proc gives, 0 takes the spell ID. Used by the aura variant.",
  ["cursor.aura.when"] = "Condition",
  ["cursor.aura.when.tip"] = "When the element counts as active.",
  ["cursor.aura.when.active"] = "While the aura is active",
  ["cursor.aura.when.active.tip"] = "Shows while the aura is there, for example a proc.",
  ["cursor.aura.when.missing"] = "Only while the aura is missing",
  ["cursor.aura.when.missing.tip"] = "Shows only when you do not have the aura, for example a buff that fell off.",
  ["cursor.aura.when.always"] = "Always, dimmed while missing",
  ["cursor.aura.when.always.tip"] = "Always visible, dimmed and grayed while the aura is missing.",
  ["cursor.aura.combatStale"] = "In combat without data",
  ["cursor.aura.combatStale.tip"] = "In combat the game can withhold the aura. The element then keeps the state from before the fight until a readable sign says it ended.",
  ["cursor.aura.combatStale.keep"] = "Keep showing the state before the fight",
  ["cursor.aura.combatStale.hide"] = "Hide",
  ["cursor.aura.combatStale.dim"] = "Dim (state before the fight)",
  ["cursor.aura.pulseOnEnd"] = "Pulse when the aura ends",
  ["cursor.aura.pulseOnEnd.tip"] = "Plays the pulse of the cooldown element once when the aura runs out. Off by default: the icon just disappears (or appears, for the condition missing).",
  ["cursor.aura.dimAlpha"] = "Opacity while missing",
  ["cursor.aura.dimAlpha.tip"] = "How visible the dimmed element is while the aura is missing.",
  ["cursor.aura.permanentCounts"] = "Auras without end count as below",
  ["cursor.aura.permanentCounts.tip"] = "An aura that never runs out has no time left. On shows it anyway, off keeps it hidden.",
  ["cursor.aura.missingColor"] = "Color while missing",
  ["cursor.aura.missingColor.tip"] = "Color of the ring or bar while the aura is missing (condition always).",
  ["cursor.aura.stacksSection"] = "Stacks",
  ["cursor.aura.stacks"] = "Show the stacks",
  ["cursor.aura.stacks.tip"] = "Shows how many stacks the aura has, from two on.",
  ["cursor.aura.note"] = "In combat the game may keep aura values secret. The ring, the time and the stacks still show through the engine, and the show rule uses its time curve instead of a comparison.",
  ["cursor.preset.auracalc"] = "Aura in combat (calculated)",
  ["cursor.aura.trackSection"] = "In combat",
  ["cursor.aura.trackMode"] = "Display in combat",
  ["cursor.aura.trackMode.tip"] = "In combat the game hides aura values. Automatic lets the game's own aura container show the aura, and calculates it from your cast and the learned duration where the container cannot.",
  ["cursor.aura.trackMode.auto"] = "Automatic (engine if possible)",
  ["cursor.aura.trackMode.auto.tip"] = "The engine shows icon, ring, number and stacks in combat. Without the container (or for other units) the element calculates the time instead.",
  ["cursor.aura.trackMode.native"] = "Native (engine)",
  ["cursor.aura.trackMode.native.tip"] = "Only your own buffs and debuffs. The game fills the display itself, the add-on reads nothing. The calculated timer below stays as the fallback.",
  ["cursor.aura.trackMode.cast"] = "Calculated (from the cast)",
  ["cursor.aura.trackMode.cast.tip"] = "Counts the time from your cast and the learned duration. A buff that is cancelled early cannot be seen in combat.",
  ["cursor.aura.trackMode.live"] = "Only read live",
  ["cursor.aura.trackMode.live.tip"] = "Reads the aura outside combat only. In combat the state before the fight stays.",
  ["cursor.aura.auraType"] = "Aura type",
  ["cursor.aura.auraType.tip"] = "Whether the game's container looks for a buff or a debuff on you.",
  ["cursor.aura.auraType.buff"] = "Buff on you",
  ["cursor.aura.auraType.debuff"] = "Debuff on you",
  ["cursor.aura.status.native"] = "In combat: the engine shows icon, ring, number and stacks.",
  ["cursor.aura.status.calc"] = "In combat: calculated from the activation (%s).",
  ["cursor.aura.status.live"] = "In combat: only the state before the fight.",
  ["cursor.aura.status.dur.manual"] = "duration %s s, typed",
  ["cursor.aura.status.dur.learned"] = "duration %s s, learned",
  ["cursor.aura.status.dur.base"] = "duration %s s, base duration",
  ["cursor.aura.status.dur.none"] = "duration unknown",
  ["cursor.aura.status.limits"] = "In combat: icon and ring native, missing condition and threshold calculated.",
  ["cursor.aura.status.clip"] = "Experimental: a clip hides the missing symbol while the aura is there (dev setting).",
  ["cursor.aura.status.unavailable"] = "This client has no native aura container, so the element calculates.",
  ["cursor.aura.status.missing"] = "The condition 'missing' needs the calculated state, so the element calculates.",
  ["cursor.aura.status.unit"] = "Only auras on yourself use the engine, other units are read live.",
  ["cursor.aura.status.source"] = "A proc is read through the glow of the spell, not through the container.",
  ["cursor.aura.status.poolFull"] = "All native containers are in use. The element calculates until one is free.",
  ["cursor.aura.status.failed"] = "The game refused the container. The element calculates instead.",
  ["cursor.aura.previewNote"] = "Preview: the editor shows sample values (a running countdown, 3 stacks). The engine fills the real element in combat only.",
  ["cursor.aura.trackSpell"] = "Trigger spell",
  ["cursor.aura.trackSpell.tip"] = "The spell whose successful cast starts the timer. Empty takes the aura itself.",
  ["cursor.aura.trackSpellId"] = "Trigger ID",
  ["cursor.aura.trackSpellId.tip"] = "Types the ID of the trigger spell, 0 takes the aura itself.",
  ["cursor.aura.trackDuration"] = "Duration (s)",
  ["cursor.aura.trackDuration.tip"] = "Length of the aura in seconds. 0 uses the duration learned the last time the aura was seen out of combat.",
  ["cursor.aura.trackStacks"] = "Count stacks per cast",
  ["cursor.aura.trackStacks.tip"] = "Every cast while the timer runs adds a stack, shown on the icon. Off by default.",
  ["cursor.aura.trackMark"] = "Mark for calculated values",
  ["cursor.aura.trackMark.tip"] = "Shows a small dot on the icon while the time is calculated and not read.",
  ["cursor.aura.trackMark.none"] = "No mark",
  ["cursor.aura.trackMark.dot"] = "Dot on the icon",
  ["cursor.aura.trackNote"] = "In combat the time is calculated from the cast and the learned duration. A buff that is cancelled early cannot be seen in combat. Out of combat the real value corrects it.",
  ["cursor.aura.track.manual"] = "Duration used: %s s (typed).",
  ["cursor.aura.track.learned"] = "Duration used: %s s, learned from the last time the aura was seen. Talents and haste can change it, type the duration above to correct it.",
  ["cursor.aura.track.base"] = "Duration used: %s s (base duration of the aura).",
  ["cursor.aura.track.none"] = "Duration unknown. Use the aura once out of combat so it is learned, or type the duration above. Until then the element is dimmed in combat.",
})
ns.AddLocale("deDE", {
  ["cursor.type.aura"] = "Aura",
  ["cursor.type.aura.desc"] = "Zeigt einen Buff oder Debuff oder das Leuchten eines Procs wie Rache als Ring, Quadrat oder Statusbalken. Kann nur erscheinen, wenn die Aura fehlt, oder nur bei wenig Restzeit.",
  ["cursor.preset.aura"] = "Aura (Buff fehlt)",
  ["cursor.aura.source"] = "Quelle",
  ["cursor.aura.source.tip"] = "Eine Aura (Buff oder Debuff) auf einer Einheit oder das Leuchten, das ein Zauber bei einem Proc bekommt.",
  ["cursor.aura.source.aura"] = "Aura (Buff oder Debuff)",
  ["cursor.aura.source.proc"] = "Proc (Zauberleuchten)",
  ["cursor.preset.wellfed"] = "Satt (fehlt)",
  ["cursor.aura.unit"] = "Einheit",
  ["cursor.aura.unit.tip"] = "Wessen Auren angesehen werden.",
  ["cursor.aura.unit.player"] = "Du",
  ["cursor.aura.unit.target"] = "Ziel",
  ["cursor.aura.unit.focus"] = "Fokus",
  ["cursor.aura.unit.pet"] = "Pet",
  ["cursor.aura.mineOnly"] = "Nur eigene Auren",
  ["cursor.aura.mineOnly.tip"] = "Zählt nur Auren, die du oder dein Pet gewirkt haben. Bei Ziel und Fokus standardmäßig an.",
  ["cursor.aura.spell"] = "Aura oder Zauber",
  ["cursor.aura.spell.tip"] = "Öffnet die Zauberliste mit Suche. Die gespeicherte Basis-ID gilt für alle Ränge.",
  ["cursor.aura.wellFed"] = "Jeder Satt-Buff zählt",
  ["cursor.aura.wellFed.tip"] = "Jede Nahrung gibt ihren eigenen Satt-Buff mit einer anderen Zauber-ID. An (Standard): das Element zählt jeden davon, gefunden über die ID und über den Namen Satt. Aus: nur der gewählte Zauber zählt.",
  ["cursor.aura.rank"] = "Rang",
  ["cursor.aura.rank.tip"] = "Welcher Rang des gewählten Zaubers gilt. Höchster Rang passt auf jeden Rang des Zaubers, ein neuer Rang braucht hier keine Änderung. Gewählte ID passt genau auf den Zauber, den du gewählt hast, mit seinem Rang.",
  ["cursor.aura.rank.max"] = "Höchster Rang (Standard)",
  ["cursor.aura.rank.max.tip"] = "Jeder Rang des Zaubers zählt als Aura oder Proc.",
  ["cursor.aura.rank.exact"] = "Nur die gewählte ID",
  ["cursor.aura.rank.exact.tip"] = "Nur die gewählte Zauber-ID zählt. Wähle den Zauber neu, um seinen Rang zu wählen. Ein Layout, das vor dieser Option gespeichert wurde, hat noch keine genaue ID und nimmt den ersten Rang.",
  ["cursor.aura.spellId"] = "Zauber-ID",
  ["cursor.aura.spellId.tip"] = "Tippt die Zauber-ID der Aura ein, bei einem Proc die des Zaubers. Enter oder das Verlassen des Felds speichert.",
  ["cursor.aura.current"] = "Aktuelle Auren...",
  ["cursor.aura.current.tip"] = "Listet die Auren, die du gerade hast. Nur außerhalb des Kampfs, im Kampf verbirgt das Spiel sie. Ein Klick übernimmt die Aura.",
  ["cursor.aura.picker.title"] = "Aura wählen",
  ["cursor.aura.picker.search"] = "Suche nach Name oder ID",
  ["cursor.aura.picker.empty"] = "Keine lesbaren Auren",
  ["cursor.aura.picker.emptyHint"] = "Auren lassen sich nur außerhalb des Kampfs lesen. Tippe eine ID, um sie direkt zu übernehmen.",
  ["cursor.aura.picker.line"] = "ID %d",
  ["cursor.aura.picker.line.time"] = "ID %d, %s s",
  ["cursor.aura.procMode"] = "Proc lesen über",
  ["cursor.aura.procMode.tip"] = "Wie der Proc gefunden wird. Automatisch nimmt das Leuchten des Zaubers und eine Aura per ID zusammen und nutzt, was antwortet.",
  ["cursor.aura.procMode.auto"] = "Automatisch (Leuchten und Aura)",
  ["cursor.aura.procMode.overlay"] = "Nur Zauberleuchten",
  ["cursor.aura.procMode.aura"] = "Nur Aura",
  ["cursor.aura.procAuraId"] = "ID der Proc-Aura",
  ["cursor.aura.procAuraId.tip"] = "Die ID der Aura, die der Proc gibt, 0 nimmt die Zauber-ID. Gilt für die Aura-Variante.",
  ["cursor.aura.when"] = "Bedingung",
  ["cursor.aura.when.tip"] = "Wann das Element als aktiv zählt.",
  ["cursor.aura.when.active"] = "Solange die Aura aktiv ist",
  ["cursor.aura.when.active.tip"] = "Zeigt, solange die Aura da ist, zum Beispiel ein Proc.",
  ["cursor.aura.when.missing"] = "Nur solange die Aura fehlt",
  ["cursor.aura.when.missing.tip"] = "Zeigt nur, wenn du die Aura nicht hast, zum Beispiel einen Buff, der abgelaufen ist.",
  ["cursor.aura.when.always"] = "Immer, abgedunkelt wenn sie fehlt",
  ["cursor.aura.when.always.tip"] = "Immer sichtbar, abgedunkelt und ausgegraut, solange die Aura fehlt.",
  ["cursor.aura.combatStale"] = "Im Kampf ohne Daten",
  ["cursor.aura.combatStale.tip"] = "Im Kampf kann das Spiel die Aura zurückhalten. Das Element behält dann den Stand vor dem Kampf, bis ein lesbares Zeichen das Ende meldet.",
  ["cursor.aura.combatStale.keep"] = "Stand vor dem Kampf weiter zeigen",
  ["cursor.aura.combatStale.hide"] = "Ausblenden",
  ["cursor.aura.combatStale.dim"] = "Abdunkeln (Stand vor dem Kampf)",
  ["cursor.aura.pulseOnEnd"] = "Puls beim Ende der Aura",
  ["cursor.aura.pulseOnEnd.tip"] = "Spielt einmal den Puls des Abklingzeit-Elements, wenn die Aura abläuft. Standardmäßig aus: das Symbol verschwindet einfach (oder erscheint bei der Bedingung fehlt).",
  ["cursor.aura.dimAlpha"] = "Deckkraft bei fehlender Aura",
  ["cursor.aura.dimAlpha.tip"] = "Wie sichtbar das abgedunkelte Element ist, solange die Aura fehlt.",
  ["cursor.aura.permanentCounts"] = "Auren ohne Ende zählen als darunter",
  ["cursor.aura.permanentCounts.tip"] = "Eine Aura, die nie abläuft, hat keine Restzeit. An zeigt sie trotzdem, aus hält sie versteckt.",
  ["cursor.aura.missingColor"] = "Farbe bei fehlender Aura",
  ["cursor.aura.missingColor.tip"] = "Farbe von Ring oder Balken, solange die Aura fehlt (Bedingung immer).",
  ["cursor.aura.stacksSection"] = "Stapel",
  ["cursor.aura.stacks"] = "Stapel anzeigen",
  ["cursor.aura.stacks.tip"] = "Zeigt, wie viele Stapel die Aura hat, ab zwei.",
  ["cursor.aura.note"] = "Im Kampf kann das Spiel Aurawerte geheim halten. Ring, Zeit und Stapel erscheinen trotzdem über die Engine, und die Anzeigeregel nutzt ihre Zeitkurve statt eines Vergleichs.",
  ["cursor.preset.auracalc"] = "Aura im Kampf berechnen",
  ["cursor.aura.trackSection"] = "Im Kampf",
  ["cursor.aura.trackMode"] = "Anzeige im Kampf",
  ["cursor.aura.trackMode.tip"] = "Im Kampf verbirgt das Spiel Aurawerte. Automatisch lässt den eigenen Aura-Container des Spiels die Aura zeigen und rechnet aus deinem Zauber und der gelernten Dauer, wo der Container nicht reicht.",
  ["cursor.aura.trackMode.auto"] = "Automatisch (Engine, wenn möglich)",
  ["cursor.aura.trackMode.auto.tip"] = "Die Engine zeigt im Kampf Symbol, Ring, Zahl und Stapel. Ohne den Container (oder bei anderen Einheiten) rechnet das Element die Zeit stattdessen.",
  ["cursor.aura.trackMode.native"] = "Nativ (Engine)",
  ["cursor.aura.trackMode.native.tip"] = "Nur eigene Buffs und Debuffs. Das Spiel füllt die Anzeige selbst, das Addon liest nichts. Der berechnete Timer unten bleibt als Rückfall.",
  ["cursor.aura.trackMode.cast"] = "Berechnet (aus dem Zauber)",
  ["cursor.aura.trackMode.cast.tip"] = "Zählt die Zeit aus deinem Zauber und der gelernten Dauer. Ein vorzeitig abgebrochener Buff ist im Kampf nicht zu sehen.",
  ["cursor.aura.trackMode.live"] = "Nur live lesen",
  ["cursor.aura.trackMode.live.tip"] = "Liest die Aura nur außerhalb des Kampfs. Im Kampf bleibt der Stand vor dem Kampf.",
  ["cursor.aura.auraType"] = "Auratyp",
  ["cursor.aura.auraType.tip"] = "Ob der Container des Spiels einen Buff oder einen Debuff auf dir sucht.",
  ["cursor.aura.auraType.buff"] = "Buff auf dir",
  ["cursor.aura.auraType.debuff"] = "Debuff auf dir",
  ["cursor.aura.status.native"] = "Im Kampf: Engine zeigt Symbol, Ring, Zahl und Stapel.",
  ["cursor.aura.status.calc"] = "Im Kampf: berechnet aus Aktivierung (%s).",
  ["cursor.aura.status.live"] = "Im Kampf: nur Stand vor dem Kampf.",
  ["cursor.aura.status.dur.manual"] = "Dauer %s s, eingegeben",
  ["cursor.aura.status.dur.learned"] = "Dauer %s s, gelernt",
  ["cursor.aura.status.dur.base"] = "Dauer %s s, Basisdauer",
  ["cursor.aura.status.dur.none"] = "Dauer unbekannt",
  ["cursor.aura.status.limits"] = "Im Kampf: Symbol und Ring nativ, Fehlt-Bedingung und Schwelle berechnet.",
  ["cursor.aura.status.clip"] = "Experimentell: ein Clip verbirgt das Fehlt-Symbol, solange die Aura da ist (Dev-Einstellung).",
  ["cursor.aura.status.unavailable"] = "Dieser Client hat keinen nativen Aura-Container, das Element rechnet deshalb.",
  ["cursor.aura.status.missing"] = "Die Bedingung 'fehlt' braucht den berechneten Stand, das Element rechnet deshalb.",
  ["cursor.aura.status.unit"] = "Nur Auren auf dir nutzen die Engine, andere Einheiten werden live gelesen.",
  ["cursor.aura.status.source"] = "Ein Proc wird über das Leuchten des Zaubers gelesen, nicht über den Container.",
  ["cursor.aura.status.poolFull"] = "Alle nativen Container sind belegt. Das Element rechnet, bis einer frei ist.",
  ["cursor.aura.status.failed"] = "Das Spiel hat den Container abgelehnt. Das Element rechnet stattdessen.",
  ["cursor.aura.previewNote"] = "Vorschau: Der Editor zeigt Beispielwerte (ein ablaufender Countdown, 3 Stapel). Die Engine füllt das echte Element nur im Kampf.",
  ["cursor.aura.trackSpell"] = "Auslöser-Zauber",
  ["cursor.aura.trackSpell.tip"] = "Der Zauber, dessen erfolgreiches Wirken den Timer startet. Leer nimmt die Aura selbst.",
  ["cursor.aura.trackSpellId"] = "Auslöser-ID",
  ["cursor.aura.trackSpellId.tip"] = "Tippt die ID des Auslöser-Zaubers ein, 0 nimmt die Aura selbst.",
  ["cursor.aura.trackDuration"] = "Dauer (Sek)",
  ["cursor.aura.trackDuration.tip"] = "Länge der Aura in Sekunden. 0 nimmt die Dauer, die beim letzten Sehen der Aura außerhalb des Kampfs gelernt wurde.",
  ["cursor.aura.trackStacks"] = "Stapel je Zauber zählen",
  ["cursor.aura.trackStacks.tip"] = "Jedes Wirken, solange der Timer läuft, fügt einen Stapel hinzu, angezeigt am Symbol. Standardmäßig aus.",
  ["cursor.aura.trackMark"] = "Kennzeichen für berechnete Werte",
  ["cursor.aura.trackMark.tip"] = "Zeigt einen kleinen Punkt am Symbol, solange die Zeit berechnet und nicht gelesen wird.",
  ["cursor.aura.trackMark.none"] = "Kein Kennzeichen",
  ["cursor.aura.trackMark.dot"] = "Punkt am Symbol",
  ["cursor.aura.trackNote"] = "Im Kampf wird die Zeit aus dem Zauber und der gelernten Dauer berechnet. Ein vorzeitig abgebrochener Buff ist im Kampf nicht zu sehen. Außerhalb des Kampfs korrigiert der echte Wert.",
  ["cursor.aura.track.manual"] = "Genutzte Dauer: %s s (eingegeben).",
  ["cursor.aura.track.learned"] = "Genutzte Dauer: %s s, gelernt beim letzten Sehen der Aura. Talente und Tempo können sie ändern, gib die Dauer oben ein, um sie zu korrigieren.",
  ["cursor.aura.track.base"] = "Genutzte Dauer: %s s (Basisdauer der Aura).",
  ["cursor.aura.track.none"] = "Dauer unbekannt. Nutze die Aura einmal außerhalb des Kampfs, damit sie gelernt wird, oder gib die Dauer oben ein. Bis dahin ist das Element im Kampf abgedunkelt.",
})

-- Props -----------------------------------------------------------------------------------------------

local DEFAULTS = {}
for key, value in pairs(CC.LOOK_DEFAULTS) do
  DEFAULTS[key] = value
end
for key, value in pairs(AL.DEFAULTS) do
  DEFAULTS[key] = value
end
for key, value in pairs(TR.DEFAULTS) do
  DEFAULTS[key] = value
end
DEFAULTS.color = "4aa8ff"
DEFAULTS.readyColor = "6b6b6b"

-- The props of an aura element with every field valid; `d` holds the defaults (the weapon element passes its own).
local function cleanProps(raw, d)
  local p = CC.CleanLook(raw, d)
  for key, value in pairs(AL.Clean(raw, d)) do
    p[key] = value
  end
  for key, value in pairs(TR.Clean(raw, d)) do
    p[key] = value
  end
  return p
end

AU.DEFAULTS, AU.CleanProps = DEFAULTS, cleanProps

CU.Register("aura", {
  defaults = DEFAULTS,
  size = { 48, 48 },
  clean = cleanProps,
})

-- Game access -----------------------------------------------------------------------------------------

local function index(t, key)
  return t[key]
end

-- The field of a table the game gave, nil when absent. A secret value comes back as it is.
local function get(t, key)
  local ok, v = pcall(index, t, key)
  if ok and not rawequal(v, nil) then
    return v
  end
  return nil
end

local function plainString(v)
  return type(v) == "string" and not hidden(v) and v or nil
end

-- The readable part of an aura table: instance id (kept raw for the engine), duration, end time, applications,
-- spell id, name, icon, and whether it is the player's own (nil when unknown).
local function auraFields(aura)
  local f = { raw = aura }
  if type(aura) ~= "table" or hidden(aura) then
    return f
  end
  f.instance = get(aura, "auraInstanceID")
  f.duration = readable(get(aura, "duration"))
  f.expirationTime = readable(get(aura, "expirationTime"))
  f.applications = readable(get(aura, "applications"))
  f.spellId = readable(get(aura, "spellId"))
  f.name = plainString(get(aura, "name"))
  local icon = get(aura, "icon")
  f.icon = (type(icon) == "number" or type(icon) == "string") and not hidden(icon) and icon or nil
  f.mine = AL.IsMine(Kit.flagOf(get(aura, "isFromPlayerOrPlayerPet")), plainString(get(aura, "sourceUnit")))
  return f
end

local function sortedIds(ids)
  local list = {}
  for id in pairs(ids) do
    list[#list + 1] = id
  end
  table.sort(list)
  return list
end

-- Reader A: the aura of one spell id. Returns whether the client has the call, and the aura table or nil.
local function byId(unit, id)
  if unit == "player" then
    local fn = api("C_UnitAuras", "GetPlayerAuraBySpellID")
    if fn then
      return true, try(fn, id)
    end
  end
  local fn = api("C_UnitAuras", "GetUnitAuraBySpellID")
  if fn then
    return true, try(fn, unit, id)
  end
  return false
end

-- Reader B: a scan of the unit's auras by index, matched on readable spell ids and, when `names` is given, on a
-- readable aura name (a food buff the data does not list yet). Returns whether the client has the call, and the
-- first aura of the set or nil.
local function scan(unit, ids, mineOnly, names)
  local at = api("C_UnitAuras", "GetAuraDataByIndex")
  if not at then
    return false
  end
  for _, filter in ipairs(names and { "HELPFUL" } or { "HELPFUL", "HARMFUL" }) do
    local full = filter .. (mineOnly and "|PLAYER" or "")
    for i = 1, SCAN_MAX do
      local aura = try(at, unit, i, full)
      if aura == nil then
        break
      end
      local f = auraFields(aura)
      if AL.Matches(ids, f.spellId) or (names and WF.IsName(f.name)) then
        return true, aura
      end
    end
  end
  return true, nil
end

AU.ReadById, AU.ReadScan, AU.Fields = byId, scan, auraFields

-- The aura of the set on the unit. Returns the aura table (or nil), whether any reader could answer, and the
-- reader that did ("id", "scan" or "name"). A unit that does not exist has no aura. With `names` an aura that
-- no id found is searched by its name as well.
local function lookup(unit, list, ids, mineOnly, names)
  if unit ~= "player" and Kit.flagOf(try(api(nil, "UnitExists"), unit)) == false then
    return nil, true, "none"
  end
  local answered = false
  for _, id in ipairs(list) do
    local has, aura = byId(unit, id)
    if has then
      answered = true
      if aura ~= nil and not (mineOnly and auraFields(aura).mine == false) then
        return aura, true, "id"
      end
    end
  end
  if answered and not names then
    return nil, true, "id"
  end
  local has, aura = scan(unit, ids, mineOnly, names)
  if answered then
    return aura, true, aura ~= nil and "name" or "id"
  end
  return aura, has, has and "scan" or nil
end

local OVERLAY_CALLS = {
  { "C_SpellActivationOverlay", "IsSpellOverlayed" },
  { "C_Spell", "IsSpellOverlayed" },
  { nil, "IsSpellOverlayed" },
}

-- Whether the game shows the activation glow for one of the ids: true, false, or nil when no call answered. A
-- boolean the game keeps secret is returned second, for SetAlphaFromBoolean.
local function overlayState(list)
  local answered, secretBool = false, nil
  for _, id in ipairs(list) do
    for _, call in ipairs(OVERLAY_CALLS) do
      local fn = api(call[1], call[2])
      local ok, v = false, nil
      if fn then
        ok, v = pcall(fn, id)
      end
      if ok and type(v) == "boolean" then
        if hidden(v) then
          secretBool = v
        elseif v then
          return true
        else
          answered = true
        end
        break
      end
    end
  end
  if answered then
    return false, secretBool
  end
  return nil, secretBool
end

AU.OverlayState = overlayState

-- The duration object of an aura: the game's own for its instance id, else one built from readable end time
-- and duration.
local function durationOf(unit, f)
  if f.instance ~= nil then
    local object = try(api("C_UnitAuras", "GetAuraDuration"), unit, f.instance)
    if object ~= nil then
      return object
    end
  end
  if f.duration and f.duration > 0 and f.expirationTime then
    return (ns.TimeFormat.OwnDuration(f.expirationTime - f.duration, f.duration))
  end
  return nil
end

-- The stack text the game makes for an instance (empty below two, may be secret), nil when it cannot.
local function stackTextOf(unit, f)
  if f.instance == nil then
    return nil
  end
  return try(api("C_UnitAuras", "GetAuraApplicationDisplayCount"), unit, f.instance, 2, 999)
end

local function textureOf(id)
  local spell = id > 0 and ns.DataApi.Spell(id) or nil
  if spell and spell.fid then
    return spell.fid
  end
  local texture = id > 0 and try(api("C_Spell", "GetSpellTexture"), id) or nil
  if not hidden(texture) and (type(texture) == "number" or type(texture) == "string") then
    return texture
  end
  return nil
end

local function playerClass()
  return CC.PlayerClass()
end

-- State ------------------------------------------------------------------------------------------------

-- The name of a spell as the game gives it, nil when it is unreadable or unknown.
local function spellNameOf(id)
  if id <= 0 then
    return nil
  end
  local name = try(api("C_Spell", "GetSpellName"), id)
  return plainString(name)
end

-- Whether the chosen spell is a well fed buff, for the panel and the lookup.
function AU.IsWellFed(spellBase, spellExact)
  return WF.Chosen({ spellBase = spellBase, spellExact = spellExact }, spellNameOf(spellBase))
end

-- What an element looks up: the unit, the ids of the spell (the glow), the ids of the aura and, for any well fed
-- buff, the names to compare.
local function resolve(st)
  local p = st.p
  local proc = p.source == "proc"
  local spellIds = AL.SpellIds(p)
  local auraIds = spellIds
  if proc and p.procAuraId > 0 then
    auraIds = AL.SpellIds(p, p.procAuraId)
  end
  local names
  auraIds, names = AL.LookFor(p, auraIds, p.source == "aura" and spellNameOf(p.spellBase) or nil)
  local all = {}
  for id in pairs(spellIds) do
    all[id] = true
  end
  for id in pairs(auraIds) do
    all[id] = true
  end
  local triggerBase = p.trackSpell > 0 and p.trackSpell or p.spellBase
  st.own = {
    source = p.source,
    unit = proc and "player" or p.unit,
    ids = all,
    spellList = sortedIds(spellIds),
    auraIds = auraIds,
    auraNames = names,
    auraList = sortedIds(auraIds),
    trigger = AL.SpellIds(p, triggerBase),
    triggerBase = triggerBase,
  }
  st.notes.id = p.spellBase
end

-- Whether the game withholds the aura lookups of this element now.
local function restricted(st)
  local own = st.own
  local spell = Kit.flagOf(try(api("C_Secrets", "ShouldSpellAuraBeSecret"), own.auraList[1] or own.spellList[1] or 0))
  local auras = Kit.flagOf(try(api("C_Secrets", "ShouldAurasBeSecret")))
  local combat = Kit.flagOf(try(api(nil, "InCombatLockdown"))) == true
    or Kit.flagOf(try(api(nil, "UnitAffectingCombat"), "player")) == true
  return AL.Restricted(spell, auras, combat)
end

-- The removed instance ids of an UNIT_AURA payload the game let us read, nil when there are none.
local function removedIds(info)
  if type(info) ~= "table" or hidden(info) then
    return nil
  end
  local list = get(info, "removedAuraInstanceIDs")
  if type(list) ~= "table" or hidden(list) then
    return nil
  end
  local out = {}
  for _, id in ipairs(list) do
    out[#out + 1] = readable(id)
  end
  return out
end

-- Computed timer ---------------------------------------------------------------------------------------

-- The learned durations of the account, repaired on the first use of a database.
local cleanedFor
local function durations()
  local db = ns.db
  if type(db) ~= "table" then
    return nil
  end
  if cleanedFor ~= db then
    db.auraDurations = TR.CleanStore(db.auraDurations)
    cleanedFor = db
  end
  return db.auraDurations
end

-- The aura id a duration is learned and looked up under.
local function durationKey(p)
  return p.spellBase
end

-- Notes the duration (and base duration) of a readable own aura of the player for later fights.
local function learn(st, f)
  local p = st.p
  local store = durations()
  if not (store and TR.Applies(p) and f.duration and f.duration > 0 and f.mine ~= false) then
    return
  end
  local base = f.instance ~= nil and readable(try(api("C_UnitAuras", "GetAuraBaseDuration"), "player", f.instance))
    or nil
  TR.Learn(store, durationKey(p), f.duration, base)
end

-- The duration the computed timer counts with and where it comes from: seconds and "manual", "learned" or "base".
local function trackDuration(p)
  local store = durations()
  local entry = store and TR.Lookup(store, durationKey(p))
  return TR.PickDuration(p.trackDuration, entry and entry.duration, entry and entry.base)
end

AU.TrackDuration = trackDuration

local function inFight(st)
  return st.calc.combat == true or Kit.flagOf(try(api(nil, "InCombatLockdown"))) == true
end

-- A cast of the trigger spell was seen: starts or restarts the timer. Mode auto counts only in a fight (outside,
-- the aura is read). Returns whether a run started.
local function activate(st, via)
  local p, calc = st.p, st.calc
  if TR.Reads(p) and not inFight(st) then
    return false
  end
  local seconds, source = trackDuration(p)
  if not TR.Activate(calc, seconds, now(), source, p.trackStacks) then
    return false
  end
  local diag = AU.diag.track
  diag.via, diag.activations = via, diag.activations + 1
  return true
end

-- The cooldown route for a client whose cast event carries no readable spell id: the trigger spell's cooldown
-- turning active (and not the global cooldown) counts as the cast. Every call samples the baseline; only a call
-- with `act` lets a change start a run.
local function cooldownSignal(st, act, idMatches)
  local info = try(api("C_Spell", "GetSpellCooldown"), st.own.triggerBase)
  local active, gcd
  if type(info) == "table" and not hidden(info) then
    active, gcd = Kit.flagOf(get(info, "isActive")), Kit.flagOf(get(info, "isOnGCD"))
  end
  local started, remembered = TR.Fallback(st.calc.cdActive, active, gcd, idMatches)
  st.calc.cdActive = remembered
  return started and act and activate(st, "cooldown") or false
end

-- What a game event means for the computed timer; true when the state changed and the element reads again.
local function trackEvent(st, event, a1, _, a3)
  local p, calc = st.p, st.calc
  if not (calc and st.own and TR.Applies(p)) then
    return false
  end
  if event == "PLAYER_REGEN_DISABLED" then
    TR.CombatStart(calc, now(), TR.Reads(p))
    return true
  elseif event == "PLAYER_REGEN_ENABLED" then
    TR.CombatEnd(calc, p.trackMode == "cast")
    return true
  elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    TR.Reset(calc)
    return true
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local id = readable(a3)
    AU.diag.track.castReadable = id ~= nil
    calc.castOk = id ~= nil
    if id == nil then
      return cooldownSignal(st, true, false)
    end
    return TR.IsTrigger(st.own.trigger, id) and activate(st, "cast")
  elseif event == "SPELL_UPDATE_COOLDOWN" and calc.castOk ~= true then
    -- The cast event gave no readable id so far (or never came): the cooldown event that names the trigger, or
    -- gives no id, tells the cast.
    local id = readable(a1)
    if id == nil then
      return cooldownSignal(st, true, false)
    elseif TR.IsTrigger(st.own.trigger, id) then
      return cooldownSignal(st, true, true)
    end
  end
  return false
end

-- The duration object of a computed run, made from the add-on's own numbers and kept while they stay the same.
local function calcObject(st, c)
  local key = c.startAt .. ":" .. c.duration
  if st.calcKey == key and st.calcObject ~= nil then
    return st.calcObject
  end
  local object = ns.TimeFormat.OwnDuration(c.startAt, c.duration)
  if object ~= nil then
    st.calcKey, st.calcObject = key, object
    return object
  end
  st.calcKey, st.calcObject = nil, nil
  return nil
end

-- The state of the computed timer for the show of one reading: the fields the element needs, and what it notes
-- for the diagnosis window.
local function calcView(st, c, s)
  s.remaining, s.permanent, s.unknown, s.calc = c.remaining, c.permanent, c.unknown, true
  s.stacks = st.p.trackStacks and AL.StackText(c.stacks) or nil
  if c.startAt and c.duration and c.remaining and c.remaining > 0 then
    s.object = calcObject(st, c)
    s.calcStart, s.calcDuration = c.startAt, c.duration
  end
  local seconds, source = trackDuration(st.p)
  st.notes.track = {
    duration = c.duration or seconds,
    source = c.source == "seen" and "seen" or source,
    remaining = c.remaining,
    unknown = c.unknown == true,
    object = s.object ~= nil,
  }
end

-- Weapon enchantment -----------------------------------------------------------------------------------

local function plainValue(v)
  if hidden(v) then
    return nil
  end
  return v
end

-- The two calls of the client for WeaponEnchantLogic.Read. A call the client lacks stays out, the logic then
-- falls back to the other and never raises.
local function weaponReader()
  return {
    plain = plainValue,
    temporary = api("C_PaperDollInfo", "GetTemporaryEnchantmentInfo"),
    legacy = api(nil, "GetWeaponEnchantInfo"),
  }
end

-- The texture of the item in an inventory slot of the player, nil when empty or unreadable.
local function slotTexture(slot)
  local texture = plainValue(try(api(nil, "GetInventoryItemTexture"), "player", slot))
  if type(texture) == "number" or type(texture) == "string" then
    return texture
  end
  return nil
end

-- Whether each hand holds a weapon: { main, off }.
local function weaponEquip()
  local equip = {}
  local info = api("C_Item", "GetItemInfoInstant") or api(nil, "GetItemInfoInstant")
  for hand, slot in pairs(WE.SLOT) do
    local id = readable(try(api(nil, "GetInventoryItemID"), "player", slot))
    local has = (id ~= nil and id > 0) or slotTexture(slot) ~= nil
    local class
    if has and id and info then
      -- GetItemInfoInstant: id, type, subtype, equip location, icon, class id, subclass id.
      local ok, _, _, _, _, _, classId = pcall(info, id)
      class = ok and readable(classId) or nil
    end
    equip[hand] = WE.EquippedWeapon(has, class)
  end
  return equip
end

AU.WeaponReader, AU.WeaponEquip = weaponReader, weaponEquip

local function weaponData()
  return ns.Data and ns.Data.WeaponEnchants and ns.Data.WeaponEnchants.e or nil
end

-- The state of a weapon element: the fields of an aura reading (present, remaining, permanent, stacks, object)
-- plus the symbol and name of the enchantment, low (under the warning threshold) and the hand it came from.
local function readWeapon(st)
  local p = st.p
  local reading = WE.Read(weaponReader())
  local equip = weaponEquip()
  local data = weaponData()
  local state = WE.State(p, reading, equip, st.weaponMem, now(), data)
  st.weaponMem = state.mem
  st.weaponReading, st.weaponEquip = reading, equip
  local s = {
    present = state.present,
    how = state.stale and "stale" or "weapon",
    via = reading.how,
    stale = state.stale,
    remaining = state.remaining,
    permanent = state.permanent,
    unknown = state.unknown,
    stacks = state.stacks,
    low = state.low,
    hand = state.hand,
    enchantID = state.enchantID,
  }
  if state.hand then
    local described =
      WE.Describe(state.enchantID, data, slotTexture(WE.SLOT[state.hand]), L["cursor.weapon.name"], ns.T)
    s.icon, s.name = described.icon, described.name
  end
  if state.present == true and state.startAt and state.duration and state.remaining and state.remaining > 0 then
    s.object = calcObject(st, { startAt = state.startAt, duration = state.duration })
    s.calcStart, s.calcDuration = state.startAt, state.duration
  end
  return s
end

AU.ReadWeapon = readWeapon

-- Reads the game for one element: { present, via, how, stale, remaining, permanent, object, stacks, stacksRaw,
-- presentRaw }. `how` says what the presence came from (AuraLogic.Presence), `stale` that it is the state from
-- before the fight.
local function read(st)
  local p, own = st.p, st.own
  local s = {}
  if own ~= nil and p.source == "weapon" then
    return readWeapon(st)
  end
  if own == nil or (p.spellBase == 0 and p.procAuraId == 0) then
    return s
  end
  local proc = p.source == "proc"
  local unit = own.unit
  -- While the game withholds auras no aura call is made at all (the scans raise errors, the lookups answer
  -- nothing): the state comes from the computed timer, the end time read before the fight and the cast events.
  local withheld = restricted(st)
  local aura, answered
  if not withheld and (not proc or p.procMode ~= "overlay") then
    aura, answered, s.via = lookup(unit, own.auraList, own.auraIds, p.mineOnly, own.auraNames)
    if not answered then
      s.via = nil
    end
  end
  local found
  if answered then
    found = aura ~= nil
  end
  local mem = st.mem
  local object = not withheld and mem and try(api("C_UnitAuras", "GetAuraDuration"), unit, mem.instance) or nil
  local tracking = st.calc ~= nil and TR.Applies(p)
  st.notes.track = nil
  local status = tracking and TR.Status(st.calc, now()) or nil
  local present
  present, s.how, s.stale = AL.Presence({
    lookup = found,
    restricted = withheld,
    memory = mem ~= nil,
    memoryObject = not rawequal(object, nil),
    removed = st.removed == true,
    last = st.last,
    calc = status and status.present,
    drives = status ~= nil and p.trackMode == "cast",
    knownEnd = st.knownEnd,
    now = now(),
  })
  st.removed = nil
  if s.how == "removed" or (s.how == "lookup" and present == false) then
    st.mem = nil
  end
  if s.how == "lookup" and present == false and found == false then
    st.knownEnd = nil
    if tracking then
      TR.Seen(st.calc, nil, now())
    end
  end
  if not s.stale and s.how ~= "calc" then
    st.last = present
  end
  if not proc then
    s.present = present
  else
    local overlay
    if p.procMode ~= "aura" then
      overlay, s.presentRaw = overlayState(own.spellList)
    end
    local via
    s.present, via = AL.ProcPresent(p.procMode, overlay, present)
    AU.diag.procVia = via or AU.diag.procVia
    s.via = via
  end
  local f = aura ~= nil and auraFields(aura) or nil
  if f and s.present == true then
    if f.duration and f.duration <= 0 then
      st.knownEnd = nil
    elseif f.duration and f.expirationTime then
      st.knownEnd = f.expirationTime
    end
  end
  if tracking and f then
    learn(st, f)
    if TR.Reads(p) then
      TR.Seen(st.calc, f, now())
    elseif f.instance ~= nil then
      st.mem = { instance = f.instance }
    end
  end
  if s.how == "calc" then
    calcView(st, status, s)
  elseif f ~= nil and s.present == true then
    if f.instance ~= nil then
      st.mem = { instance = f.instance }
    end
    local sum = AL.Summary(f, now())
    s.remaining, s.permanent = sum.remaining, sum.permanent
    s.object = durationOf(unit, f)
    local text = stackTextOf(unit, f)
    if hidden(text) then
      s.stacksRaw = text
    elseif type(text) == "string" then
      s.stacks = text ~= "" and text or nil
    else
      s.stacks = AL.StackText(sum.stacks)
    end
  elseif s.present == true and aura == nil and (mem ~= nil or s.stale) then
    -- Withheld lookup: the remembered instance's duration object carries ring and number, the stacks of the
    -- last trusted reading stay.
    local last = st.s
    s.object = s.how == "instance" and object or last and last.object or nil
    s.permanent = last and last.permanent
    s.stacks, s.stacksRaw = last and last.stacks, last and last.stacksRaw
  end
  return s
end

local refresh, applyView

local function iconTexture(p)
  if p.source == "weapon" then
    return slotTexture(WE.SLOT[p.weaponHand == "off" and "off" or "main"]) or UNKNOWN_ICON
  end
  local spell = p.rankMode == "exact" and K.ExactOf(p) or p.spellBase
  return textureOf(spell > 0 and spell or p.procAuraId) or UNKNOWN_ICON
end

local function paintIcon(st)
  st.icon:SetTexture(iconTexture(st.p))
end

-- Native container --------------------------------------------------------------------------------------

-- The dev setting that picks how the condition "missing" works with the native display (AuraNativeLogic).
local function missingStrategy()
  local db = ns.db
  local cfg = type(db) == "table" and type(db.settings) == "table" and db.settings.cursorRing or nil
  return NL.Strategy(type(cfg) == "table" and cfg.nativeMissing or nil)
end

-- What this client can do, as AuraNativeLogic.Plan wants it. A client that was not asked yet (the first element
-- came up in a fight) counts as able: the element then waits for the end of the fight.
local function nativeCaps()
  return { container = AN.Available() ~= false, strategy = missingStrategy() }
end

AU.NativeCaps = nativeCaps

-- Whether the native display is the one on show: the element holds a working container and the fight is on.
-- Outside a fight the read display shows, it has every option.
local function nativeLive(st)
  return not st.editor and st.driven == true and AN.Entry(st) ~= nil and inFight(st)
end

local nativeSync

-- A container that waited for the end of a fight was built: the element looks again.
local function nativeChanged(st)
  if st.driven then
    nativeSync(st)
    refresh(st)
  end
end

-- Gives the display of the native container back: the read display parts come back to their look.
local function nativeLeave(st)
  if st.nativeShown then
    st.nativeShown = false
    AN.Show(st, false)
    st.icon:SetAlpha(1)
    Kit.layout(st, st.element)
  end
end

-- Takes the container back into the pool (the element is hidden, hidden by the rule, edited or released).
local function nativeStop(st)
  nativeLeave(st)
  AN.Release(st)
end

-- Decides whether the element runs on the native container and gives it one, or takes it back. Outside a fight
-- the container is built at once; in one the build waits (the element keeps the computed display) and nativeChanged
-- runs when it is done. Notes for the diagnosis: what the plan said and what the pool answered.
function nativeSync(st)
  local p = st.p
  local plan = NL.Plan(p, nativeCaps())
  local ids = plan.mode == "native" and sortedIds(st.own and st.own.auraIds or AL.SpellIds(p)) or {}
  local notes = { mode = plan.mode, reason = plan.reason }
  st.notes.native = notes
  if st.editor or not st.driven or #ids == 0 then
    notes.state = "stopped"
    return nativeStop(st)
  end
  local _, state = AN.Reconfigure(st, {
    spec = NL.Spec(p, ids),
    p = p,
    element = st.element,
    clip = p.when == "missing" and missingStrategy() == NL.MissingStrategy.clip,
    onChange = nativeChanged,
  })
  notes.state = state
end

-- The alpha of the element when the game keeps the glow secret: the engine picks from the boolean.
local function paintSecretGlow(st, raw)
  local p = st.p
  local on, off = 1, 0
  if p.when == "missing" then
    on, off = 0, 1
  elseif p.when == "always" then
    off = p.dimAlpha
  end
  local ok, why = invoke(st.frame, "SetAlphaFromBoolean", raw, on, off)
  st.notes.show = ok and "ok" or why
  if not ok then
    st.frame:SetAlpha(1)
  end
end

-- The small dot on the icon that says the time is calculated, made on first use.
local function paintMark(st, on)
  if on and not st.mark then
    st.mark = st.frame:CreateTexture(nil, "OVERLAY")
    method(st.mark, "SetSize", 6, 6)
    method(st.mark, "SetPoint", "TOPRIGHT", st.frame, "TOPRIGHT", -2, -2)
    method(st.mark, "SetColorTexture", 1, 1, 1, 0.9)
  end
  if st.mark then
    method(st.mark, "SetShown", on)
  end
end

-- The native display of one element in combat: the engine draws icon, ring, number and stacks (the face under
-- the container), the add-on's own icon only stands in as the placeholder under it and its own ring, numbers and
-- stacks are off. The clip variant of "missing" has its own grey symbol.
local function paintNative(st, viaCurve)
  local p, s = st.p, st.s
  local bar = st.style == "bar"
  local clip = p.when == "missing" and missingStrategy() == NL.MissingStrategy.clip
  local ph = NL.Placeholder(p)
  local iconOn = bar and p.barIcon ~= "off" or (not bar and p.icon)
  st.nativeShown = true
  AN.Show(st, true)
  st.cd:Hide()
  if st.barHost then
    st.barHost:Hide()
  end
  st.icon:SetShown(ph.shown and iconOn and not clip)
  st.icon:SetAlpha(ph.alpha)
  st.icon:SetDesaturated(ph.desaturated)
  st.track:SetShown(ph.shown and not bar and not clip)
  AN.Missing(st, clip and iconTexture(p) or nil)
  paintMark(st, false)
  Kit.paintTimer(st, { remaining = s.remaining }, {
    running = false,
    timed = s.remaining ~= nil and s.remaining > 0,
    curve = false,
    viaCurve = viaCurve,
  })
  st.charges:SetText("")
  st.charges:SetShown(false)
end

-- Ring (or bar) and time text in the low color while a weapon enchantment is about to run out. The next paint of
-- the timer takes it back through resetTint.
local function paintLow(st)
  local p = st.p
  local r, g, b = U.hex(p.curveColorLow)
  if st.style == "bar" then
    method(st.bar, "SetStatusBarColor", r, g, b, p.alpha)
  else
    method(st.cd, "SetSwipeColor", r, g, b, p.alpha)
  end
  st.timer:SetTextColor(r, g, b, 1)
  st.tinted = true
end

-- Shows the state `st.s`: visibility by condition and show rule, the ring or bar, the time and the stacks.
function applyView(st)
  local p, s = st.p, st.s
  if not (p and s) then
    return
  end
  local bar = st.style == "bar"
  local native = nativeLive(st)
  local verdict = (native and NL.Visible or AL.Visible)(p, {
    present = s.present,
    remaining = s.remaining,
    permanent = s.permanent,
    unknown = s.unknown,
    canCurve = not st.editor and s.object ~= nil and Kit.canCurve(st),
  })
  local viaCurve = verdict.mode == "curve"
  st.viaCurve = viaCurve
  local cross = not st.editor and SL.CrossIn(p, s.remaining)
  st.visAt = cross and now() + cross or nil
  -- For the diagnosis window: what the show rule decided, and where the presence came from. notes.show is only
  -- written by the paths that call the game (the threshold curve, the secret glow).
  st.notes.verdict, st.notes.how = verdict.mode, s.how
  if not viaCurve and not (s.present == nil and s.presentRaw ~= nil) then
    st.notes.show = nil
  end
  if s.present == nil and s.presentRaw ~= nil and not st.editor then
    paintSecretGlow(st, s.presentRaw)
  elseif not native and s.stale and p.combatStale ~= "keep" and verdict.mode ~= "hide" then
    st.frame:SetAlpha(p.combatStale == "hide" and 0 or p.dimAlpha)
  elseif viaCurve then
    Kit.paintThreshold(st)
  else
    st.frame:SetAlpha(verdict.mode == "hide" and 0 or (verdict.dim and p.dimAlpha or 1))
  end
  if native then
    return paintNative(st, viaCurve)
  end
  nativeLeave(st)
  paintMark(st, p.trackMark == "dot" and s.calc == true)
  if p.source == "weapon" and s.icon and not st.editor then
    st.icon:SetTexture(s.icon)
  end
  local absent = s.present == false
  st.icon:SetDesaturated(absent)
  st.ready = absent
  st.track:SetShown(absent and not bar)
  if bar then
    Kit.paintBar(st, absent)
  end
  local present = s.present == true
  local ok = Kit.paintTimer(st, { remaining = s.remaining }, {
    running = p.timer and present and (s.object ~= nil or s.remaining ~= nil),
    timed = s.remaining ~= nil and s.remaining > 0,
    curve = p.colorCurve and present,
    viaCurve = viaCurve,
    calc = s.calc == true and s.object ~= nil,
  })
  if not ok then
    return applyView(st)
  end
  if s.low and present and not p.colorCurve and not st.editor then
    paintLow(st)
  end
  local count = present and p.charges and (s.stacksRaw or s.stacks) or nil
  local shown = count ~= nil and pcall(st.charges.SetText, st.charges, count)
  if not shown then
    st.charges:SetText("")
  end
  st.charges:SetShown(shown)
end

-- The pulse of the cooldown element, played when an aura that was there ends (option pulseOnEnd, off by default).
local function setState(st, s)
  local ended = st.driven and st.s and st.s.present == true and s.present == false
  st.s = s
  applyView(st)
  if ended and st.p.pulseOnEnd then
    Kit.warn(st, "short")
  end
end

-- Reads the game again and shows the result, the ring fed from the aura's duration object.
function refresh(st)
  if not st.p or st.editor then
    return
  end
  local s = read(st)
  Kit.feed(st, s.object)
  if s.object == nil and s.calcStart then
    method(st.cd, "SetCooldown", s.calcStart, s.calcDuration)
  end
  setState(st, s)
end

-- Events and the slow check -----------------------------------------------------------------------------

local function plain(v)
  if hidden(v) then
    return nil
  end
  return v
end

local hub = T.NewHub({
  "PLAYER_TARGET_CHANGED",
  "PLAYER_FOCUS_CHANGED",
  "SPELLS_CHANGED",
  "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
  "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_DEAD",
  "PLAYER_ALIVE",
  "PLAYER_UNGHOST",
  "SPELL_UPDATE_COOLDOWN",
  "PLAYER_EQUIPMENT_CHANGED",
}, {
  { "UNIT_AURA", "player", "target", "focus", "pet" },
  { "UNIT_INVENTORY_CHANGED", "player" },
  { "UNIT_PET", "player" },
  { "UNIT_SPELLCAST_SUCCEEDED", "player" },
}, function(st, event, a1, a2, a3)
  if not st.own then
    return
  end
  if event == "UNIT_AURA" and st.mem and AL.RemovesInstance(removedIds(a2), st.mem.instance) then
    st.removed = true
    if st.calc then
      TR.End(st.calc)
    end
  end
  if trackEvent(st, event, a1, a2, a3) then
    refresh(st)
  end
  local action = AL.Route(event, st.own, plain(a1))
  if action == "resolve" then
    resolve(st)
    paintIcon(st)
  end
  if action then
    refresh(st)
  end
end, "cursorauras-event")

-- Number of elements that are drawn in the game and so listen, for the diagnosis and tests.
function AU.Listening()
  return hub.Count()
end

-- Events are not reliable for every aura in combat, so one frame reads every drawn element again every POLL
-- seconds. It has a script only while an element is drawn.
local watched, watchedCount = {}, 0
local driver, driverStep
local pollAcc = 0

local function pollStep(_, elapsed)
  pollAcc = pollAcc + elapsed
  if pollAcc < POLL then
    return
  end
  pollAcc = 0
  AU.diag.polls = AU.diag.polls + 1
  for st in pairs(watched) do
    if st.calc and st.own and TR.Applies(st.p) then
      cooldownSignal(st, st.calc.castOk ~= true, false)
    end
    refresh(st)
  end
end

local function track(st, on)
  if on and not watched[st] then
    watched[st] = true
    watchedCount = watchedCount + 1
    if watchedCount == 1 then
      driver = driver or CreateFrame("Frame")
      driverStep = driverStep or ns.Wrap("cursorauras-poll", pollStep)
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

-- How many elements the slow check reads and its script (nil while none is drawn).
function AU.Polling()
  return watchedCount, driver and driver:GetScript("OnUpdate") or nil
end

-- What the game answered to the calls of one drawn element, for the diagnosis window.
AU.Notes = CC.Notes

-- Drawing ---------------------------------------------------------------------------------------------

-- The editor preview: an aura that runs down, then a rest, from the simulation (a still ring while none runs).
local function preview(st, ctx)
  local progress = T.PreviewProgress(ctx, "auraProgress")
  local s = { present = false }
  if progress ~= false then
    s = { present = true, remaining = (1 - progress) * AU.SAMPLE_SECONDS, stacks = "3" }
  end
  if st.style == "bar" then
    method(st.bar, "SetValue", progress or 0)
  else
    T.FreezeRing(st, progress)
  end
  setState(st, s)
end

local function identity(p)
  return table.concat({
    p.source,
    p.unit,
    p.spellBase,
    p.spellExact,
    p.rankMode,
    p.anyWellFed and 1 or 0,
    p.procAuraId,
    p.procMode,
    p.mineOnly and 1 or 0,
    p.trackMode,
    p.trackSpell,
    p.timerMode,
    p.style,
    p.weaponHand,
  }, "|")
end

-- The props the drawing runs on: an aura element's own, and for a weapon element the same with the source "weapon".
local function propsOf(element)
  if element.type ~= "weapon" then
    return CU.Props("aura", element.props)
  end
  local p = CU.Props("weapon", element.props)
  p.source = "weapon"
  return CU.Props("aura", p)
end

local function render(frame, element, ctx)
  local p = propsOf(element)
  local st = Kit.widgetOf(frame)
  st.refreshFn, st.applyFn = refresh, applyView
  local key = identity(p)
  local changed = st.identity ~= nil and st.identity ~= key
  st.identity = key
  st.p, st.editor, st.reduce = p, ctx and ctx.editor == true, Kit.reduceMotion(ctx)
  st.element = element
  Kit.layout(st, element)
  paintIcon(st)
  if st.editor then
    nativeStop(st)
    preview(st, ctx)
  elseif changed and st.driven then
    local combat = st.calc ~= nil and st.calc.combat == true
    st.calc, st.calcKey, st.calcObject, st.knownEnd = TR.New(), nil, nil, nil
    st.weaponMem = nil
    st.calc.combat = combat
    resolve(st)
    paintIcon(st)
    nativeSync(st)
    refresh(st)
  elseif st.driven then
    nativeSync(st)
    if st.s then
      applyView(st)
    end
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
  st.refreshFn, st.applyFn = refresh, applyView
  st.calc = TR.New()
  st.calc.combat = Kit.flagOf(try(api(nil, "InCombatLockdown"))) == true
  hub.Add(frame, st)
  track(st, true)
  method(st.cd, "SetScript", "OnCooldownDone", function()
    if st.driven then
      refresh(st)
    end
  end)
  resolve(st)
  paintIcon(st)
  if TR.Applies(st.p) then
    cooldownSignal(st, false)
  end
  nativeSync(st)
  refresh(st)
end

local function release(frame)
  hub.Remove(frame)
  local st = frame.fgCooldown
  if st then
    st.driven = false
    nativeStop(st)
    track(st, false)
    Kit.stopTick(st)
    st.visAt, st.viaCurve = nil, false
    Kit.feed(st, nil)
    Kit.numbersView(st, nil)
    Kit.resetTint(st)
    st.s, st.own, st.mem, st.last, st.removed = nil, nil, nil, nil, nil
    st.calc, st.calcKey, st.calcObject, st.knownEnd = nil, nil, nil, nil
    st.weaponMem, st.weaponReading, st.weaponEquip = nil, nil, nil
    paintMark(st, false)
    st.frame:SetAlpha(1)
  end
end

-- An aura that runs down, then a rest, in a loop; step writes the elapsed share, false while it is gone.
S.RegisterSource("aura", {
  reset = function(sim)
    sim.auraProgress = nil
  end,
  step = function(sim, _, t)
    local c = t % (AU.SAMPLE_SECONDS + SIM_PAUSE)
    sim.auraProgress = c < AU.SAMPLE_SECONDS and c / AU.SAMPLE_SECONDS or false
  end,
})

-- Picker for the current auras --------------------------------------------------------------------------

-- The readable auras of the player: { id, name, icon, duration }, each id once, buffs first.
function AU.CurrentAuras()
  local at = api("C_UnitAuras", "GetAuraDataByIndex")
  local rows, seen = {}, {}
  if not at or restricted({ own = { auraList = {}, spellList = {} } }) then
    return rows
  end
  for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
    for i = 1, SCAN_MAX do
      local aura = try(at, "player", i, filter)
      if aura == nil then
        break
      end
      local f = auraFields(aura)
      if f.spellId and f.name and not seen[f.spellId] then
        seen[f.spellId] = true
        rows[#rows + 1] = { id = f.spellId, name = f.name, icon = f.icon, duration = f.duration }
      end
    end
  end
  return rows
end

-- The rows of the picker for a typed query: the current auras that match by name or id prefix, plus the typed
-- id itself when no aura has it.
function AU.Search(query)
  local text = (query or ""):lower()
  local typed = tonumber(text:match("^%s*(%d+)%s*$"))
  local rows, known = {}, {}
  for _, row in ipairs(AU.CurrentAuras()) do
    known[row.id] = true
    local ok = text == ""
    if typed then
      ok = tostring(row.id):find("^" .. typed) ~= nil
    elseif not ok then
      ok = row.name:lower():find(text, 1, true) ~= nil
    end
    if ok then
      rows[#rows + 1] = row
    end
  end
  if typed and typed > 0 and typed <= AL.SPELL_ID_MAX and not known[typed] then
    local spell = ns.DataApi.Spell(typed)
    rows[#rows + 1] = { id = typed, name = spell and ns.MacroSpells.displayName(spell) or ("ID " .. typed) }
  end
  return rows
end

local picker

local function buildPicker()
  local f = ns.Dialogs.Create("ForeverGuidesAuraPicker", 420, 420)
  local st = { data = {}, query = "" }
  f.st = st
  local list, host, empty
  local function pick(row)
    if not row or not st.onPick then
      return
    end
    f:Hide()
    st.onPick(row)
  end
  st.pick = pick
  local function refreshList()
    st.data = AU.Search(st.query)
    list:SetData(st.data)
    list:SetShown(#st.data > 0)
    empty:SetShown(#st.data == 0)
  end
  st.refresh = refreshList
  local search = W.EditBox(f, {
    placeholder = "cursor.aura.picker.search",
    clear = true,
    onChange = function(text)
      st.query = text
      ns.Debounce("cursor-aura-search", 0.15, refreshList)
    end,
    onEnter = function()
      pick(st.data[1])
    end,
  })
  search:SetPoint("TOPLEFT", 16, -52)
  search:SetPoint("RIGHT", -16, 0)
  st.search = search
  host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT", 16, -90)
  host:SetPoint("BOTTOMRIGHT", -16, 16)
  W.Fill(host, "surface", 1)
  list = ns.PageKit.NewList(host, {
    rowHeight = 40,
    bind = function(row)
      local line = row.duration
          and row.duration > 0
          and string.format(L["cursor.aura.picker.line.time"], row.id, string.format("%g", row.duration))
        or string.format(L["cursor.aura.picker.line"], row.id)
      return { title = row.name, sub = line, icon = row.icon or textureOf(row.id) }
    end,
    onClick = pick,
  })
  list:SetAllPoints(host)
  empty =
    W.EmptyState(host, { text = "cursor.aura.picker.empty", hint = "cursor.aura.picker.emptyHint", icon = "search" })
  empty:Fill()
  return f
end

-- Opens the picker; onPick(row) gets the chosen { id, name }.
function AU.OpenPicker(onPick)
  picker = picker or buildPicker()
  local st = picker.st
  st.onPick, st.query = onPick, ""
  W.SetText(picker.title, "cursor.aura.picker.title")
  st.search.edit:SetText("")
  picker:Show()
  st.refresh()
  st.search.edit:SetFocus()
end

-- Panel -----------------------------------------------------------------------------------------------

local function controls()
  return ns.CanvasEditor.Controls
end

-- A button row that opens the picker of current auras.
local function currentRow(state, add, shown)
  local row = CreateFrame("Frame", nil, state.panel)
  row:SetHeight(28)
  local button = W.Action(row, {
    key = "cursor.aura.current",
    height = 24,
    tooltip = "cursor.aura.current",
    tooltipText = "cursor.aura.current.tip",
    wrap = "cursor-aura-current",
    onClick = function()
      AU.OpenPicker(function(picked)
        state.writeMany({ spellBase = K.BaseOf(picked.id), spellExact = picked.id })
        state.panel:Refresh()
      end)
    end,
  })
  button:SetPoint("TOPLEFT", 0, -2)
  button:SetPoint("TOPRIGHT", 0, -2)
  row.button = button
  return add(row, 28, shown)
end

-- Where the duration of the computed timer comes from, as a sentence for the panel.
function AU.DurationNote(p)
  local seconds, source = trackDuration(p)
  if not seconds then
    return L["cursor.aura.track.none"]
  end
  return string.format(L["cursor.aura.track." .. source], string.format("%g", seconds))
end

-- A wrapped text row that says which duration the computed timer uses now (read again with every refresh).
local function durationNoteRow(state, add, shown)
  local row = CreateFrame("Frame", nil, state.panel)
  local text = W.Text(row, { role = "ui", color = "textMuted", wrap = true })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  text:SetWidth(controls().PANEL_WIDTH or 284)
  function row:Refresh()
    W.SetText(
      text,
      nil,
      AU.DurationNote({ trackDuration = state.get("trackDuration"), spellBase = state.get("spellBase") })
    )
  end
  row:Refresh()
  return add(row, function()
    local height = controls().FitText(state, text)
    row:SetHeight(height)
    return height
  end, shown)
end

-- What each hand holds now, as lines for the panel: "Main hand: Instant Poison V, 24:30".
function AU.WeaponLines()
  local reading, equip = WE.Read(weaponReader()), weaponEquip()
  local data = weaponData()
  local lines = {}
  for _, hand in ipairs(WE.Hands(reading, equip)) do
    local what
    if reading.how == nil then
      what = L["cursor.weapon.kind.unreadable"]
    elseif hand.kind == "enchanted" then
      local described = WE.Describe(hand.entry.enchantID, data, nil, L["cursor.weapon.name"], ns.T)
      what = described.name
      if hand.entry.remainingSec then
        what = what .. ", " .. K.FormatStyled(hand.entry.remainingSec, { timeStyle = "clock" }, "own")
      end
    else
      what = L["cursor.weapon.kind." .. hand.kind]
    end
    lines[#lines + 1] = string.format(L["cursor.weapon.line"], L["cursor.weapon.hand." .. hand.hand], what)
  end
  return lines
end

-- The status of the combat display for the props `p`, for the panel line and the test window: { key, color, text }.
-- `st` is the drawn element (nil in the editor), which knows whether the game refused its container.
function AU.Status(p, st)
  if p.source == "weapon" then
    return { key = "weapon", color = "success", text = L["cursor.weapon.status"] }
  end
  local state = st ~= nil and st.notes.native and st.notes.native.state or nil
  local status = NL.Status(p, nativeCaps(), {
    poolFull = AN.Info().full or state == "limit",
    failed = state == "fallback",
  })
  local text
  if status.key == "calc" then
    local seconds, source = trackDuration(p)
    local duration = seconds and string.format(L["cursor.aura.status.dur." .. source], string.format("%g", seconds))
      or L["cursor.aura.status.dur.none"]
    text = string.format(L["cursor.aura.status.calc"], duration)
  else
    text = L["cursor.aura.status." .. status.key]
  end
  local lines = { text }
  for _, note in ipairs(status.notes) do
    lines[#lines + 1] = L["cursor.aura.status." .. note]
  end
  return { key = status.key, color = status.color, text = table.concat(lines, "\n") }
end

local function statusProps(state)
  local p = {}
  for _, key in ipairs({
    "trackMode",
    "source",
    "unit",
    "when",
    "showWhen",
    "showBelow",
    "auraType",
    "spellBase",
    "trackDuration",
  }) do
    p[key] = state.get(key)
  end
  return p
end

function AU.Panel(parent, element, onChange)
  return controls().NewPanel(parent, {
    element = element,
    kind = "aura",
    onChange = onChange,
    props = function(raw)
      return CU.Props("aura", raw)
    end,
    build = function(state, add)
      local C = controls()
      local R = CC.Rows
      local c = CC.LookConds(state)
      local proc = c.on("source", "proc")
      local aura = c.on("source", "aura")
      local whenAlways = c.on("when", "always")
      -- The spell shown in the fields: the exact id while only the chosen id counts, else the base.
      local function shownSpell()
        if state.get("rankMode") == "exact" then
          return K.ExactOf({ spellBase = state.get("spellBase"), spellExact = state.get("spellExact") })
        end
        return state.get("spellBase")
      end
      local belowOn = c.on("showWhen", "below")
      local procAuraOn = c.both(proc, function()
        return state.get("procMode") ~= "overlay"
      end)
      state.section("basics", "canvas.sec.basics")
      add(
        C.Choice(state.panel, {
          label = "cursor.aura.source",
          tooltip = "cursor.aura.source",
          tooltipText = "cursor.aura.source.tip",
          options = C.Choices(AL.UI_SOURCES, "cursor.aura.source."),
          get = function()
            return state.get("source")
          end,
          set = function(source)
            state.write("source", source)
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.choice
      )
      -- Own auras only is the usual wish for a target or focus, so choosing the unit sets it too.
      add(
        C.Choice(state.panel, {
          label = "cursor.aura.unit",
          tooltip = "cursor.aura.unit",
          tooltipText = "cursor.aura.unit.tip",
          options = C.Choices(AL.UNITS, "cursor.aura.unit."),
          get = function()
            return state.get("unit")
          end,
          set = function(unit)
            state.write("unit", unit)
            state.write("mineOnly", unit == "target" or unit == "focus")
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.choice,
        aura
      )
      R.toggle(state, add, "cursor.aura.mineOnly", "mineOnly", aura)
      add(
        C.Spell(state.panel, {
          label = "cursor.aura.spell",
          tooltipText = "cursor.aura.spell.tip",
          class = function()
            return playerClass() or "ALL"
          end,
          get = function()
            local id = shownSpell()
            return id > 0 and id or nil
          end,
          set = function(id)
            state.writeMany({ spellBase = id and K.BaseOf(id) or 0, spellExact = id or 0 })
          end,
        }),
        C.HEIGHT.spell
      )
      add(
        C.Number(state.panel, {
          label = "cursor.aura.spellId",
          tooltip = "cursor.aura.spellId.tip",
          labelWidth = 90,
          min = 0,
          max = AL.SPELL_ID_MAX,
          step = 1,
          get = function()
            return shownSpell()
          end,
          set = function(id)
            state.writeMany({ spellBase = K.BaseOf(id), spellExact = id })
          end,
        }),
        C.HEIGHT.number
      )
      R.choice(state, add, "cursor.aura.rank", "rankMode", AL.RANK_MODES, nil, true)
      R.toggle(
        state,
        add,
        "cursor.aura.wellFed",
        "anyWellFed",
        c.both(aura, function()
          return AU.IsWellFed(state.get("spellBase"), state.get("spellExact"))
        end)
      )
      currentRow(state, add, aura)
      R.choice(state, add, "cursor.aura.procMode", "procMode", AL.PROC_MODES, proc)
      add(
        C.Number(state.panel, {
          label = "cursor.aura.procAuraId",
          tooltip = "cursor.aura.procAuraId.tip",
          labelWidth = 110,
          min = 0,
          max = AL.SPELL_ID_MAX,
          step = 1,
          get = function()
            return state.get("procAuraId")
          end,
          set = function(id)
            state.write("procAuraId", id)
          end,
        }),
        C.HEIGHT.number,
        procAuraOn
      )
      R.choice(state, add, "cursor.aura.when", "when", AL.WHEN, nil, true)
      state.section("combat", "cursor.aura.trackSection")
      R.choice(state, add, "cursor.aura.combatStale", "combatStale", AL.COMBAT_STALE)
      local playerAura = function()
        return state.get("source") == "aura" and state.get("unit") == "player"
      end
      local trackOn = function()
        return playerAura() and state.get("trackMode") ~= "live"
      end
      R.choice(state, add, "cursor.aura.trackMode", "trackMode", TR.MODES, playerAura, true)
      C.StatusRow(state, add, function()
        return AU.Status(statusProps(state))
      end, function()
        return state.get("source") == "aura"
      end)
      R.choice(state, add, "cursor.aura.auraType", "auraType", AL.AURA_TYPES, playerAura)
      C.TextRow(state, add, "cursor.aura.previewNote", nil, function()
        return playerAura() and NL.Plan(statusProps(state), nativeCaps()).mode == "native"
      end)
      add(
        C.Spell(state.panel, {
          label = "cursor.aura.trackSpell",
          tooltipText = "cursor.aura.trackSpell.tip",
          class = function()
            return playerClass() or "ALL"
          end,
          get = function()
            local id = state.get("trackSpell")
            return id > 0 and id or nil
          end,
          set = function(id)
            state.write("trackSpell", id and K.BaseOf(id) or 0)
          end,
        }),
        C.HEIGHT.spell,
        trackOn
      )
      add(
        C.Number(state.panel, {
          label = "cursor.aura.trackSpellId",
          tooltip = "cursor.aura.trackSpellId.tip",
          labelWidth = 90,
          min = 0,
          max = TR.SPELL_ID_MAX,
          step = 1,
          get = function()
            return state.get("trackSpell")
          end,
          set = function(id)
            state.write("trackSpell", id > 0 and K.BaseOf(id) or 0)
          end,
        }),
        C.HEIGHT.number,
        trackOn
      )
      add(
        C.Number(state.panel, {
          label = "cursor.aura.trackDuration",
          tooltip = "cursor.aura.trackDuration.tip",
          labelWidth = 90,
          min = 0,
          max = TR.DURATION_MAX,
          step = 1,
          get = function()
            return state.get("trackDuration")
          end,
          set = function(seconds)
            state.write("trackDuration", seconds)
            state.panel:Refresh()
          end,
        }),
        C.HEIGHT.number,
        trackOn
      )
      durationNoteRow(state, add, trackOn)
      R.toggle(state, add, "cursor.aura.trackStacks", "trackStacks", trackOn)
      R.choice(state, add, "cursor.aura.trackMark", "trackMark", TR.MARKS, trackOn)
      C.TextRow(state, add, "cursor.aura.trackNote", nil, trackOn)
      state.section("look", "canvas.sec.look")
      CC.StyleRows(state, add, c, "cursor.aura.missingColor", function()
        return PL.ReadyColorShown("aura", { when = state.get("when"), pulseOnEnd = state.get("pulseOnEnd") })
      end)
      state.section("behavior", "canvas.sec.behavior", false)
      R.toggle(state, add, "cursor.aura.pulseOnEnd", "pulseOnEnd")
      R.slider(state, add, "cursor.aura.dimAlpha", "dimAlpha", { min = 0, max = 1, step = 0.05 }, whenAlways)
      CC.ShowRows(state, add, SL.AURA_SHOW_WHEN)
      R.toggle(state, add, "cursor.aura.permanentCounts", "permanentCounts", belowOn)
      state.section("stacks", "cursor.aura.stacksSection", false)
      R.toggle(state, add, "cursor.aura.stacks", "charges")
      R.font(state, add, CC.TEXT.charge, function()
        return state.get("charges")
      end)
      CC.TimerRows(state, add, c)
      state.section(nil)
      C.TextRow(state, add, "cursor.aura.note")
    end,
  })
end

-- Presets ---------------------------------------------------------------------------------------------

-- A ring that shows while the class buff is missing (Battle Shout for a warrior), so the element has something
-- to show.
CU.RegisterPreset("aura", function(el, build)
  return build("aura", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("aura", "aura", 56, 56, { spellBase = AL.Sample(playerClass()) or 0, when = "missing" }),
  })
end)

-- A ring that shows while the player has no well fed buff of any food.
CU.RegisterPreset("wellfed", function(el, build)
  return build("wellfed", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("aura", "aura", 56, 56, { spellBase = WF.SAMPLE, spellExact = WF.SAMPLE, when = "missing" }),
  })
end)

-- A ring that counts the buff in combat from the cast and the learned duration, for a buff the player casts
-- on themselves (the class buff of the sample, else the aura is chosen in the panel).
CU.RegisterPreset("auracalc", function(el, build)
  return build("auracalc", {
    el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
    el("aura", "aura", 56, 56, {
      spellBase = AL.Sample(playerClass()) or 0,
      trackMode = "auto",
      trackMark = "dot",
    }),
  })
end)

-- Registry ---------------------------------------------------------------------------------------------

AU.Render, AU.Drive, AU.Release = render, drive, release

E.Register("aura", { render = render, drive = drive, release = release, panel = AU.Panel })
