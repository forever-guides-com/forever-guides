-- Texts of the tab "Rules" (RulesTab.lua, RuleEditor.lua, PreviewList.lua, RunPanel.lua) and of the rule
-- engine (conditions, reasons, templates). One row per text { key, English, German }, so both languages
-- always carry the same keys. {name} marks a value that RulesUiLogic.Fill puts in, %d and %s are
-- string.format values. Style: docs/TEXT-STIL.md.
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

-- A "days" condition: label, help-free three answers and the words for missing data.
local function days(kind, label, labelDe, missing, missingDe)
  add("gm.cond." .. kind, label, labelDe)
  add(
    "gm.cond." .. kind .. ".yes",
    label .. ": {days} days, rule {op} {need}. Fits",
    labelDe .. ": {days} Tage, Regel {op} {need}. Passt"
  )
  add(
    "gm.cond." .. kind .. ".no",
    label .. ": {days} days, rule {op} {need}. Does not fit",
    labelDe .. ": {days} Tage, Regel {op} {need}. Passt nicht"
  )
  add("gm.cond." .. kind .. ".unknown", missing .. " (rule {op} {need})", missingDe .. " (Regel {op} {need})")
end

-- Tab and pages ------------------------------------------------------------------------------------------
add("gm.tab.rules", "Rules", "Regeln")
add("gm.rules.page.rules", "Rules", "Regeln")
add("gm.rules.page.templates", "Templates", "Vorlagen")
add("gm.rules.page.preview", "Check and run", "Prüfen und ausführen")
add(
  "gm.rules.guide.rules",
  "1. Create or edit a rule. 2. Check. 3. Run.",
  "1. Regel anlegen oder bearbeiten. 2. Prüfen. 3. Ausführen."
)
add(
  "gm.rules.guide.templates",
  "1. Pick a template, create a draft. 2. Check. 3. Run.",
  "1. Vorlage wählen, Entwurf anlegen. 2. Prüfen. 3. Ausführen."
)
add(
  "gm.rules.guide.preview",
  "1. Pick a rule and check. 2. Tick members. 3. Run.",
  "1. Regel wählen und prüfen. 2. Mitglieder abhaken. 3. Ausführen."
)

-- List -------------------------------------------------------------------------------------------------------
add("gm.rules.listTitle", "Your rules", "Deine Regeln")
add(
  "gm.rules.listTitle.help",
  "Rules only make suggestions.\nNothing runs by itself.\nThe top rule wins when two fit one member.\nA new rule starts off.",
  "Regeln machen nur Vorschläge.\nNichts läuft von selbst.\nBei zwei Treffern gewinnt die obere Regel.\nEine neue Regel startet aus."
)
add(
  "gm.rules.listHint",
  "Order = priority. Switch on only what you checked.",
  "Reihenfolge = Priorität. Nur Geprüftes einschalten."
)
add(
  "gm.rules.empty",
  "No rules yet. Start from a template or the assistant.",
  "Noch keine Regeln. Starte mit einer Vorlage oder dem Assistenten."
)
add("gm.rules.newFromTemplate", "From template", "Aus Vorlage")
add("gm.rules.newOwn", "Own rule", "Eigene Regel")
add("gm.rules.assistant", "Assistant", "Assistent")
add("gm.rules.up", "Up", "Hoch")
add("gm.rules.down", "Down", "Runter")
add("gm.rules.copy", "Copy", "Kopieren")
add("gm.rules.edit", "Edit", "Bearbeiten")
add("gm.rules.delete", "Delete", "Löschen")
add("gm.rules.delete.title", "Delete rule", "Regel löschen")
add("gm.rules.delete.body", "Delete this rule for good?", "Diese Regel endgültig löschen?")
add("gm.rules.unnamed", "(no name)", "(ohne Namen)")
add("gm.rules.damaged", "%s is damaged (%s). Delete it.", "%s ist beschädigt (%s). Bitte löschen.")
add("gm.rules.scope", "Ranks: {ranks}", "Ränge: {ranks}")
add("gm.rules.noRanks", "none chosen", "keine gewählt")
add("gm.rules.mainRank", "rank of the main", "Rang des Mains")
add("gm.rules.rankNone", "not chosen", "nicht gewählt")
add("gm.rules.miss.title", "Still missing:", "Fehlt noch:")
add("gm.rules.miss.noRanks", "Ranks: none chosen", "Ränge: keine gewählt")
add(
  "gm.rules.miss.rankChanged",
  "Ranks: a rank changed, please check",
  "Ränge: ein Rang hat sich geändert, bitte prüfen"
)
add("gm.rules.miss.badTargetRank", "Target rank: not chosen", "Zielrang: nicht gewählt")
add("gm.rules.miss.noNote", "Note text: empty", "Notiztext: leer")
add("gm.rules.miss.noTag", "Marker: empty", "Markierung: leer")
add("gm.rules.miss.noConditions", "Conditions: none yet", "Bedingungen: noch keine")
add("gm.rules.miss.badValue", "A condition has no value", "Eine Bedingung hat keinen Wert")

-- Editor -----------------------------------------------------------------------------------------------------
add("gm.rules.editorTitle", "Edit rule", "Regel bearbeiten")
add(
  "gm.rules.editorTitle.help",
  "All conditions must be true (AND).\nFor OR make a second rule.\nValues are clamped when you save.\nA rule with an open issue stays off.",
  "Alle Bedingungen müssen stimmen (UND).\nFür ODER eine zweite Regel anlegen.\nWerte werden beim Speichern begrenzt.\nEine Regel mit offenem Problem bleibt aus."
)
add("gm.rules.name", "Name", "Name")
add("gm.rules.namePlaceholder", "Name of the rule", "Name der Regel")
add("gm.rules.scopeLabel", "Applies to ranks", "Gilt für Ränge")
add(
  "gm.rules.scopeLabel.help",
  "Only members of these ranks are checked.\nThe guild master (rank 0) never is.",
  "Nur Mitglieder dieser Ränge werden geprüft.\nDer Gildenleiter (Rang 0) nie."
)
add("gm.rules.condLabel", "When all of this is true", "Wenn alles davon stimmt")
add(
  "gm.rules.condLabel.help",
  "All conditions must hold at once (AND).\nFor OR make a second rule.\nWith a date missing the rule never fires.",
  "Alle Bedingungen müssen zugleich stimmen (UND).\nFür ODER eine zweite Regel anlegen.\nFehlt ein Datum, trifft die Regel nie zu."
)
add("gm.rules.opLabel", "Comparison", "Vergleich")
add(
  "gm.rules.op.tip",
  "at least: this value or more.\nless than: below this value.",
  "mindestens: dieser Wert oder mehr.\nweniger als: unter diesem Wert."
)
add("gm.rules.addCond", "Add condition", "Bedingung")
add("gm.rules.removeCond", "Remove", "Entfernen")
add("gm.rules.actionLabel", "Then", "Dann")
add("gm.rules.targetLabel", "Choose target rank", "Zielrang wählen")
add("gm.rules.protectLabel", "Protection", "Schutz")
add("gm.rules.useGlobal", "Use the global protection", "Globalen Schutz nutzen")
add(
  "gm.rules.useGlobal.tip",
  "The protection list from the options applies here too:\nprotected ranks and members are never touched.",
  "Die Schutzliste aus den Optionen gilt auch hier:\nGeschützte Ränge und Mitglieder bleiben unberührt."
)
add("gm.rules.extraRanks", "Also protect these ranks", "Diese Ränge zusätzlich schützen")
add(
  "gm.rules.extraRanks.help",
  "Members of these ranks are never touched by this rule.\nOn top of the global protection.",
  "Mitglieder dieser Ränge fasst diese Regel nie an.\nZusätzlich zum globalen Schutz."
)
add("gm.rules.maxPerRun", "Most members per run", "Höchstens Mitglieder pro Lauf")
add(
  "gm.rules.maxPerRun.tip",
  "More matches wait for the next run.\nProtects against too many changes at once.",
  "Weitere Treffer warten auf den nächsten Lauf.\nSchützt vor zu vielen Änderungen auf einmal."
)
add("gm.rules.value.days", "Days", "Tage")
add("gm.rules.value.level", "Level", "Stufe")
add("gm.rules.value.text", "Text", "Text")
add("gm.rules.unit.days", "%d days", "%d Tage")
add("gm.rules.notePlaceholder", "Note text, at most 31 characters", "Notiztext, höchstens 31 Zeichen")
add("gm.rules.notePublic", "Public guild note", "Öffentliche Gildennotiz")
add(
  "gm.rules.notePublic.tip",
  "On: the guild note.\nOff: the officer note.",
  "An: die Gildennotiz.\nAus: die Offiziersnotiz."
)
add("gm.rules.tagPlaceholder", "Marker, for example inactive", "Markierung, zum Beispiel inactive")
add("gm.rules.chooseRank", "Choose rank", "Rang wählen")
add("gm.rules.save", "Save", "Speichern")
add("gm.rules.cancel", "Cancel", "Abbrechen")
add("gm.rules.err.notARule", "Not a rule", "Keine Regel")
add("gm.rules.err.badAction", "Unknown action", "Unbekannte Aktion")
add("gm.rules.err.badCondition", "A condition is damaged", "Eine Bedingung ist beschädigt")
add("gm.rules.err.badKind", "Unknown condition", "Unbekannte Bedingung")
add("gm.rules.err.badOp", "Unknown operator", "Unbekannter Operator")
add(
  "gm.rules.err.badValue",
  "A condition needs a value (choose a rank, enter text)",
  "Eine Bedingung braucht einen Wert (Rang wählen, Text eintragen)"
)
add("gm.rules.err.noConditions", "Add at least one condition", "Mindestens eine Bedingung nötig")
add("gm.rules.err.tooManyConditions", "Too many conditions", "Zu viele Bedingungen")
add("gm.rules.err.tooMany", "Too many rules", "Zu viele Regeln")
add("gm.rules.err.noGoal", "Choose what should happen", "Wähle, was passieren soll")
add("gm.rules.err.noRanks", "Choose at least one rank", "Mindestens einen Rang wählen")
add("gm.rules.err.rankChanged", "A rank changed, check the ranks", "Ein Rang hat sich geändert, Ränge prüfen")
add("gm.rules.err.badTargetRank", "Choose the target rank", "Zielrang wählen")
add("gm.rules.err.noNote", "Enter the note text", "Notiztext eintragen")
add("gm.rules.err.noTag", "Enter the marker", "Markierung eintragen")
add("gm.rules.err.unknownTemplate", "Unknown template", "Unbekannte Vorlage")
add("gm.rules.err.locked", "Nothing can be saved now", "Gerade kann nichts gespeichert werden")

-- Actions as words --------------------------------------------------------------------------------------------
add("gm.rules.act.promote", "Promote", "Befördern")
add("gm.rules.act.demote", "Demote", "Degradieren")
add("gm.rules.act.setRank", "Set rank", "Rang setzen")
add("gm.rules.act.remove", "Remove from guild", "Aus der Gilde entfernen")
add("gm.rules.act.setNote", "Write note: {note}", "Notiz schreiben: {note}")
add("gm.rules.act.mark", "Mark: {tag}", "Markieren: {tag}")
add("gm.rules.act.none", "Hint only", "Nur Hinweis")
add("gm.rules.actName.promote", "Promote one rank", "Einen Rang befördern")
add("gm.rules.actName.demote", "Demote one rank", "Einen Rang degradieren")
add("gm.rules.actName.setRank", "Set a rank", "Rang setzen")
add("gm.rules.actName.remove", "Remove from guild", "Aus der Gilde entfernen")
add("gm.rules.actName.setNote", "Write a note", "Notiz schreiben")
add("gm.rules.actName.mark", "Only mark", "Nur markieren")
add("gm.rules.actName.none", "Hint only", "Nur Hinweis")
add("gm.tag.inactive", "inactive", "inaktiv")
add("gm.tag.review", "check", "prüfen")
add("gm.tag.cleanup", "clean up", "aufräumen")
add("gm.tag.returned", "returned", "zurückgekehrt")
add("gm.tag.returnee", "returnee", "Rückkehrer")
add("gm.tag.protect", "protected", "geschützt")

-- Operators and data fields ------------------------------------------------------------------------------------
for _, op in ipairs({
  { "in", "is one of", "ist einer von" },
  { "atLeast", "at least", "mindestens" },
  { "lessThan", "less than", "weniger als" },
  { "atMost", "at most", "höchstens" },
  { "equals", "equals", "gleich" },
  { "isMax", "is max level", "ist Maximalstufe" },
  { "isMain", "is a main", "ist Main" },
  { "isAlt", "is an alt", "ist Alt" },
  { "hasAlts", "has alts", "hat Alts" },
  { "equal", "same as main", "wie der Main" },
  { "higher", "main is higher", "Main ist höher" },
  { "lower", "main is lower", "Main ist niedriger" },
  { "differs", "differs from main", "anders als der Main" },
  { "contains", "contains", "enthält" },
  { "notContains", "does not contain", "enthält nicht" },
  { "isEmpty", "is empty", "ist leer" },
  { "has", "has", "hat" },
  { "hasNot", "has not", "hat nicht" },
  { "exact", "known to the day", "auf den Tag bekannt" },
  { "bounded", "known at least", "mindestens bekannt" },
  { "is", "is", "ist" },
  { "isNot", "is not", "ist nicht" },
}) do
  add("gm.op." .. op[1], op[2], op[3])
end
for _, f in ipairs({
  { "joined", "join date", "Beitrittsdatum" },
  { "rankSince", "date of the last rank change", "Datum der letzten Rangänderung" },
  { "lastOnline", "last online", "zuletzt online" },
  { "rank", "rank", "Rang" },
  { "level", "level", "Stufe" },
  { "maxLevel", "max level (see settings)", "Maximalstufe (siehe Einstellungen)" },
  { "main", "main", "Main" },
  { "publicNote", "guild note", "Gildennotiz" },
  { "officerNote", "officer note (no right to read)", "Offiziersnotiz (kein Leserecht)" },
  { "online", "online state", "Online-Status" },
}) do
  add("gm.data." .. f[1], f[2], f[3])
end

-- Conditions: label, help and the three answers ------------------------------------------------------------------
add("gm.cond.invalid", "Condition is damaged", "Bedingung ist beschädigt")
add("gm.cond.rank", "Rank", "Rang")
add("gm.cond.rank.help", "The member has one of these ranks.", "Das Mitglied hat einen dieser Ränge.")
add("gm.cond.rank.yes", "Rank {rank} is in the list", "Rang {rank} steht in der Liste")
add("gm.cond.rank.no", "Rank {rank} is not in the list", "Rang {rank} steht nicht in der Liste")
add("gm.cond.rank.unknown", "Rank unknown", "Rang unbekannt")
days("daysInGuild", "In the guild", "In der Gilde", "Join date unknown", "Beitrittsdatum unbekannt")
days("daysInRank", "In the rank", "Im Rang", "Rank date unknown", "Rangdatum unbekannt")
days("daysOffline", "Offline", "Offline", "Last online unknown", "Zuletzt online unbekannt")
days(
  "groupDaysOffline",
  "Offline (main and alts)",
  "Offline (Main und Alts)",
  "Last online unknown",
  "Zuletzt online unbekannt"
)
add(
  "gm.cond.daysInGuild.help",
  "Counts from the join date. No exact date: minimum only.",
  "Zählt ab Beitrittsdatum. Ohne genaues Datum nur Minimum."
)
add(
  "gm.cond.daysInRank.help",
  "Counts from the last rank change the add-on saw.",
  "Zählt ab der letzten Rangänderung, die das Addon sah."
)
add(
  "gm.cond.daysOffline.help",
  "Server time is rough. The rule uses the safe lower bound.",
  "Serverzeit ist grob. Es gilt die sichere Untergrenze."
)
add(
  "gm.cond.groupDaysOffline.help",
  "Last visit of main or an alt counts. Protects active alts.",
  "Letzter Besuch von Main oder Alt zählt. Schützt aktive Alts."
)
add("gm.cond.level", "Level", "Stufe")
add("gm.cond.level.help", "Character level from the guild list.", "Charakterstufe aus der Gildenliste.")
add("gm.cond.level.yes", "Level {level}, rule {op} {need}. Fits", "Stufe {level}, Regel {op} {need}. Passt")
add(
  "gm.cond.level.no",
  "Level {level}, rule {op} {need}. Does not fit",
  "Stufe {level}, Regel {op} {need}. Passt nicht"
)
add("gm.cond.level.unknown", "Level unknown", "Stufe unbekannt")
add("gm.cond.link", "Main or alt", "Main oder Alt")
add(
  "gm.cond.link.help",
  "Needs the main and alt links you keep in the detail card.",
  "Braucht die Main-Alt-Verknüpfungen aus der Detailkarte."
)
add("gm.cond.link.yes", "Link: {op}. Fits", "Verknüpfung: {op}. Passt")
add("gm.cond.link.no", "Link: not {op}. Does not fit", "Verknüpfung: nicht {op}. Passt nicht")
add("gm.cond.link.unknown", "Link unknown", "Verknüpfung unbekannt")
add("gm.cond.mainRank", "Rank of the main", "Rang des Mains")
add("gm.cond.mainRank.help", "Compares an alt with its main.", "Vergleicht einen Alt mit seinem Main.")
add("gm.cond.mainRank.yes", "Main {mainRank}, alt {rank}: {op}. Fits", "Main {mainRank}, Alt {rank}: {op}. Passt")
add(
  "gm.cond.mainRank.no",
  "Main {mainRank}, alt {rank}: {op}. Does not fit",
  "Main {mainRank}, Alt {rank}: {op}. Passt nicht"
)
add("gm.cond.mainRank.unknown", "Main not in the guild list", "Main nicht in der Gildenliste")
add("gm.cond.publicNote", "Guild note", "Gildennotiz")
add("gm.cond.publicNote.help", "Upper and lower case do not matter.", "Groß und Klein spielt keine Rolle.")
add("gm.cond.publicNote.yes", "Guild note: {op} {text}. Fits", "Gildennotiz: {op} {text}. Passt")
add("gm.cond.publicNote.no", "Guild note: {op} {text}. Does not fit", "Gildennotiz: {op} {text}. Passt nicht")
add("gm.cond.publicNote.unknown", "Guild note not readable", "Gildennotiz nicht lesbar")
add("gm.cond.officerNote", "Officer note", "Offiziersnotiz")
add(
  "gm.cond.officerNote.help",
  "Needs the right to read officer notes.",
  "Braucht das Recht, Offiziersnotizen zu lesen."
)
add("gm.cond.officerNote.yes", "Officer note: {op} {text}. Fits", "Offiziersnotiz: {op} {text}. Passt")
add("gm.cond.officerNote.no", "Officer note: {op} {text}. Does not fit", "Offiziersnotiz: {op} {text}. Passt nicht")
add(
  "gm.cond.officerNote.unknown",
  "Officer note not readable (right missing)",
  "Offiziersnotiz nicht lesbar (Recht fehlt)"
)
add("gm.cond.ownNote", "Own note", "Eigene Notiz")
add(
  "gm.cond.ownNote.help",
  "Your own note from the detail card, saved only on this PC.",
  "Deine Notiz aus der Detailkarte, nur auf diesem PC."
)
add("gm.cond.ownNote.yes", "Own note: {op} {text}. Fits", "Eigene Notiz: {op} {text}. Passt")
add("gm.cond.ownNote.no", "Own note: {op} {text}. Does not fit", "Eigene Notiz: {op} {text}. Passt nicht")
add("gm.cond.ownNote.unknown", "Own note unknown", "Eigene Notiz unbekannt")
add("gm.cond.tag", "Marker", "Markierung")
add(
  "gm.cond.tag.help",
  "Markers come from rules that only mark, or from you.",
  "Markierungen aus Regeln, die nur markieren, oder von dir."
)
add("gm.cond.tag.yes", "Marker {tag}: {op}. Fits", "Markierung {tag}: {op}. Passt")
add("gm.cond.tag.no", "Marker {tag}: {op}. Does not fit", "Markierung {tag}: {op}. Passt nicht")
add("gm.cond.tag.unknown", "Marker unknown", "Markierung unbekannt")
add("gm.cond.dateKnown", "Date known", "Datum bekannt")
add(
  "gm.cond.dateKnown.help",
  "Demands good data, for example a join date known to the day.",
  "Verlangt gute Daten, z. B. ein tagesgenaues Beitrittsdatum."
)
add("gm.cond.dateKnown.yes", "The {field} is known well enough", "Das Datum ({field}) ist gut genug bekannt")
add("gm.cond.dateKnown.no", "The {field} is not known well enough", "Das Datum ({field}) ist nicht gut genug bekannt")
add("gm.cond.dateKnown.unknown", "Date unknown", "Datum unbekannt")
add("gm.cond.online", "Online now", "Jetzt online")
add("gm.cond.online.help", "Uses the state of the guild list.", "Nutzt den Stand der Gildenliste.")
add("gm.cond.online.yes", "Online state: {op}. Fits", "Online-Status: {op}. Passt")
add("gm.cond.online.no", "Online state: {op}. Does not fit", "Online-Status: {op}. Passt nicht")
add("gm.cond.online.unknown", "Online state unknown", "Online-Status unbekannt")

-- Why an entry is not ready -----------------------------------------------------------------------------------
add("gm.why.staleRoster", "Guild list is old, refresh first", "Gildenliste ist alt, erst aktualisieren")
add("gm.why.leaderTarget", "The guild master is never a target", "Der Gildenleiter ist nie ein Ziel")
add("gm.why.unknownData", "Data missing: {missing}", "Daten fehlen: {missing}")
add("gm.why.noMain", "Main not in the guild list", "Main nicht in der Gildenliste")
add("gm.why.protectTag", "Protected by a marker", "Durch Markierung geschützt")
add("gm.why.protectAway", "Away until day {untilDay}", "Abwesend bis {untilDay}")
add("gm.why.protectSkip", "Skipped until {untilDay}", "Übersprungen bis {untilDay}")
add("gm.why.protectKey", "On the protected list", "Auf der Schutzliste")
add("gm.why.protectRank", "Protected rank", "Geschützter Rang")
add("gm.why.protectWord", "Note holds the protect word {word}", "Notiz enthält das Schutzwort {word}")
add("gm.why.protectNewbie", "New member (needs {need} safe days)", "Neu dabei (braucht {need} sichere Tage)")
add("gm.why.protectGrace", "Just returned ({days} of {need} days)", "Gerade zurück ({days} von {need} Tagen)")
add("gm.why.protectGroup", "An alt or the main was active lately", "Ein Alt oder der Main war zuletzt aktiv")
add("gm.why.overruled", "Another rule above this one wins", "Eine Regel darüber gewinnt")
add("gm.why.maxPerRun", "Limit of the rule reached, next run", "Grenze der Regel erreicht, nächster Lauf")
add("gm.why.maxTotal", "Limit of the run reached, next run", "Grenze des Laufs erreicht, nächster Lauf")
add("gm.rules.span.atLeast", "at least {n}", "mindestens {n}")
add("gm.rules.span.range", "{lo} to {hi}", "{lo} bis {hi}")

-- Preview ------------------------------------------------------------------------------------------------------
add("gm.rules.pvTitle", "1. Check", "1. Prüfen")
add(
  "gm.rules.pvTitle.help",
  "Built fresh from the guild list.\nOnly ticked entries run.\nRemovals are never ticked in advance.\nGrey entries show why they cannot run.",
  "Frisch aus der Gildenliste gebaut.\nNur angehakte Einträge laufen.\nEntfernen ist nie vorangehakt.\nGraue Einträge nennen den Grund."
)
add(
  "gm.rules.pvHint",
  "Tick what should happen. Nothing runs before you confirm.",
  "Hake an, was passieren soll. Ohne Bestätigung läuft nichts."
)
add("gm.rules.pvHead", "%d ready, %d held back", "%d bereit, %d zurückgehalten")
add("gm.rules.pickRule", "Rule to check", "Regel wählen")
add("gm.rules.pick.active", "All active rules", "Alle aktiven Regeln")
add("gm.rules.pick.off", "%s (off)", "%s (aus)")
add(
  "gm.rules.pvOff",
  "This rule is off. Check it first, then switch it on.",
  "Diese Regel ist aus. Erst prüfen, dann einschalten."
)
add("gm.rules.enableRule", "Switch rule on", "Regel einschalten")
add("gm.rules.pvNoRule", "No active rule. Pick a rule above.", "Keine aktive Regel. Wähle oben eine Regel.")
add("gm.rules.pvNoMatch", "No member fits. See the data below.", "Kein Mitglied passt. Siehe Datenlage unten.")
add("gm.rules.pvEmpty", "Nothing in this view.", "Nichts in dieser Ansicht.")
add("gm.rules.protect", "Protect", "Schutz")
add(
  "gm.rules.protect.tip",
  "Puts the member on the protection list.\nRules with their own protection ignore it.",
  "Setzt das Mitglied auf die Schutzliste.\nRegeln mit eigenem Schutz ignorieren sie."
)
add("gm.rules.skipToday", "Skip today", "Heute überspringen")
add(
  "gm.rules.skipToday.tip",
  "Leaves the member out of every rule today.\nTomorrow the rules apply again.",
  "Lässt das Mitglied heute bei jeder Regel aus.\nMorgen gelten die Regeln wieder."
)
add("gm.rules.markUndo", "Undo", "Rückgängig")
add("gm.rules.mark.protect", "%s is on the protection list.", "%s steht auf der Schutzliste.")
add("gm.rules.mark.skipToday", "%s is skipped today.", "%s wird heute übersprungen.")
add("gm.rules.markUndone", "Mark of %s undone.", "Markierung von %s zurückgenommen.")
add("gm.rules.markErr.noTarget", "No member chosen.", "Kein Mitglied gewählt.")
add("gm.rules.markErr.leader", "The guild master is never a target.", "Der Gildenleiter ist nie ein Ziel.")
add("gm.rules.markErr.noClock", "The date is not known yet.", "Das Datum ist noch nicht bekannt.")
add("gm.rules.markErr.full", "The list is full.", "Die Liste ist voll.")
add("gm.rules.pvMore", "%d more entries, narrow the filter", "%d weitere Einträge, Filter enger stellen")
add("gm.rules.filter", "Show", "Anzeigen")
add("gm.rules.mat.ready", "Ready", "Bereit")
add("gm.rules.mat.later", "Later", "Später")
add("gm.rules.mat.unknown", "Unknown (data missing)", "Unbekannt (Daten fehlen)")
add("gm.rules.mat.conflict", "Conflict", "Konflikt")
add("gm.rules.mat.noRight", "Right missing", "Recht fehlt")
add("gm.rules.mat.blocked", "Blocked", "Blockiert")
add("gm.rules.mat.protected", "Protected", "Geschützt")
add("gm.rules.mat.all", "All", "Alle")
add("gm.rules.why", "Why not?", "Warum nicht?")
add("gm.rules.details", "Details", "Details")
add("gm.rules.refresh", "Refresh", "Aktualisieren")
add("gm.rules.pickAll", "Tick all valid", "Alle gültigen")
add("gm.rules.pickNone", "Tick none", "Keine")
add(
  "gm.rules.summary",
  "Ticked: %d promote, %d demote, %d remove, %d note, %d mark",
  "Angehakt: %d befördern, %d degradieren, %d entfernen, %d Notiz, %d markieren"
)
add("gm.rules.marks.done", "%d markers set", "%d Markierungen gesetzt")
add("gm.rules.dryOn", "Dry run: nothing is sent", "Trockenlauf: nichts wird gesendet")
add("gm.rules.dryOff", "Live: steps change the guild", "Live: Schritte ändern die Gilde")
add("gm.rules.way", "Way: %s. Now: %s", "Weg: %s. Jetzt: %s")
add("gm.rules.choice.auto", "automatic", "automatisch")
add("gm.rules.choice.macro", "secure button", "sicherer Knopf")
add("gm.rules.choice.copy", "copy command", "Befehl kopieren")
add("gm.rules.choice.direct", "direct call", "direkter Aufruf")
add("gm.rules.way.macro", "one click per step on a secure button", "ein Klick pro Schritt auf einem sicheren Knopf")
add("gm.rules.way.copy", "command to paste into the chat", "Befehl zum Einfügen in den Chat")
add("gm.rules.way.direct", "direct call, the game decides", "direkter Aufruf, das Spiel entscheidet")
add(
  "gm.rules.way.locked",
  "Way: copy. The game does not allow guild changes from add-ons here,\nyou type each command yourself (Ctrl+C, Enter, Ctrl+V, Enter).",
  "Weg: Kopieren. Das Spiel lässt Addons hier keine Gildenänderung zu,\ndu tippst jeden Befehl selbst (Strg+C, Enter, Strg+V, Enter)."
)

-- Data and run step ------------------------------------------------------------------------------------------------
add("gm.rules.dataTitle", "Data", "Datenlage")
add(
  "gm.rules.dataTitle.help",
  "Rules by guild time need join dates.\nWithout a date a member never fits (safety).\nAdd dates by hand, import them or read notes.",
  "Regeln nach Gildenzeit brauchen Beitrittsdaten.\nOhne Datum passt ein Mitglied nie (Sicherheit).\nDaten eintragen, importieren oder aus Notizen lesen."
)
add(
  "gm.rules.data.known",
  "Of %d members, %d have a known join date (%d exact, %d at least).",
  "Von %d Mitgliedern ist bei %d das Beitrittsdatum bekannt (%d genau, %d mindestens)."
)
add("gm.rules.data.since", "Recording since %s.", "Die Erfassung läuft seit %s.")
add("gm.rules.data.noScan", "Recording has not started yet.", "Die Erfassung hat noch nicht begonnen.")
add("gm.rules.data.lack", "Rules by guild time lack data.", "Für Regeln nach Gildenzeit fehlen Daten.")
add("gm.rules.data.unknown", "%d unknown: date missing", "%d unbekannt: Datum fehlt")
add("gm.rules.data.ok", "All join dates are known.", "Alle Beitrittsdaten sind bekannt.")
add("gm.rules.data.enter", "Enter join dates", "Beitrittsdaten eintragen")
add(
  "gm.rules.data.enter.tip",
  "Opens the import: type or paste dates.\nOne line per member.",
  "Öffnet den Import: Daten tippen oder einfügen.\nEine Zeile pro Mitglied."
)
add("gm.rules.data.notes", "Read from notes", "Aus Notizen lesen")
add(
  "gm.rules.data.notes.tip",
  "Reads markers such as 'since 2026-01-15'\nfrom guild and officer notes.",
  "Liest Marker wie 'seit 15.01.2026'\naus Gilden- und Offiziersnotiz."
)
add("gm.rules.data.notesDone", "%d join dates read from notes", "%d Beitrittsdaten aus Notizen gelesen")
add("gm.rules.data.notesNone", "Nothing new in the notes.", "In den Notizen nichts Neues.")
add("gm.rules.execTitle", "2. Run", "2. Ausführen")
add(
  "gm.rules.execTitle.help",
  "The button wakes up when everything is ready.\nA click shows first what will happen.\nOnly your confirmation starts it.",
  "Der Knopf wird aktiv, wenn alles bereit ist.\nEin Klick zeigt zuerst, was passiert.\nErst deine Bestätigung startet den Lauf."
)
add("gm.rules.runNow", "Run", "Ausführen")
add(
  "gm.rules.runNow.tip",
  "Shows first what will happen.\nNothing starts before you confirm.",
  "Zeigt zuerst, was passiert.\nOhne Bestätigung startet nichts."
)
add("gm.rules.ready.all", "Everything is ready.", "Alles bereit.")
add("gm.rules.chk.rule", "Rule: no active rule yet", "Regel: noch keine aktive Regel")
add("gm.rules.chk.ruleOpen", "Rule is incomplete: %s", "Regel unvollständig: %s")
add("gm.rules.chk.members", "Members: tick at least one", "Mitglieder: mindestens eines anhaken")
add("gm.rules.chk.rights", "Rights: your rank lacks a right", "Rechte: deinem Rang fehlt ein Recht")
add("gm.rules.chk.way", "Way: the game has no call for it", "Weg: das Spiel hat dafür keinen Aufruf")
add("gm.rules.chk.combat", "Combat: wait until it ends", "Kampf: warte, bis er vorbei ist")
add("gm.rules.chk.roster", "Guild list: refresh first", "Gildenliste: erst aktualisieren")
add("gm.rules.cf.intro", "This will happen:", "Das passiert:")
add("gm.rules.cf.promote", "%d promote: %s", "%d befördern: %s")
add("gm.rules.cf.setRank", "%d set rank: %s", "%d Rang setzen: %s")
add("gm.rules.cf.demote", "%d demote: %s", "%d degradieren: %s")
add("gm.rules.cf.remove", "%d remove: %s", "%d entfernen: %s")
add("gm.rules.cf.setNote", "%d notes: %s", "%d Notizen: %s")
add("gm.rules.cf.mark", "%d mark: %s", "%d markieren: %s")
add("gm.rules.cf.more", "and %d more", "und %d weitere")
add("gm.rules.cf.local", "Markers are saved on this PC only.", "Markierungen liegen nur auf diesem PC.")
add("gm.rules.cf.dry", "Dry run: nothing changes in your guild", "Trockenlauf: es wird nichts an der Gilde geändert")
add("gm.rules.cf.live", "Real run: changes your guild", "Echter Lauf: ändert deine Gilde")
add("gm.rules.cf.pause", "Pause between steps: %d seconds", "Pause zwischen den Schritten: %d Sekunden")
add("gm.rules.cf.stop", "You can stop at any time.", "Du kannst jederzeit abbrechen.")
add("gm.rules.cf.undo", "Rank changes can be undone for %d days.", "Rangänderungen lassen sich %d Tage zurücknehmen.")
add("gm.rules.cf.removeAsk", "Removal: you type each name next.", "Entfernen: du tippst danach jeden Namen ein.")
add("gm.rules.cf.title", "Confirm run", "Lauf bestätigen")
-- Run ------------------------------------------------------------------------------------------------------------
add("gm.rules.runTitle", "Run", "Lauf")
add(
  "gm.rules.runTitle.help",
  "One click, one step by default.\nEvery step checks fresh data first.\nStop ends the run at once.\nRank changes can be undone for a few days.",
  "Standard: ein Klick, ein Schritt.\nJeder Schritt prüft zuerst frische Daten.\nStopp beendet den Lauf sofort.\nRangänderungen lassen sich einige Tage zurücknehmen."
)
add("gm.rules.noSteps", "No step to run.", "Kein Schritt zum Ausführen.")
add("gm.rules.runReady", "%d steps wait for your confirmation.", "%d Schritte warten auf deine Bestätigung.")
add("gm.rules.runStep", "Step %d of %d.", "Schritt %d von %d.")
add(
  "gm.rules.runDone",
  "Run over: %d done, %d skipped, %d failed.",
  "Lauf beendet: %d erledigt, %d übersprungen, %d fehlgeschlagen."
)
add("gm.rules.confirmRun", "Confirm run", "Lauf bestätigen")
add("gm.rules.next", "Next step", "Nächster Schritt")
add("gm.rules.skip", "Skip this step", "Schritt überspringen")
add("gm.rules.again", "Show command again", "Befehl erneut zeigen")
add("gm.rules.startSeries", "Start series", "Serie starten")
add("gm.rules.stop", "Stop", "Stopp")
add("gm.rules.closeRun", "Close", "Schließen")
add("gm.rules.undo", "Undo", "Rückgängig")
add("gm.rules.countHint", "Type the number of removals", "Anzahl der Entfernungen eintippen")
add("gm.rules.res.pending", "waiting", "wartet")
add("gm.rules.res.sent", "sent", "gesendet")
add("gm.rules.res.verified", "confirmed by the list", "von der Liste bestätigt")
add("gm.rules.res.unverified", "not confirmed yet", "noch nicht bestätigt")
add("gm.rules.res.mismatch", "list shows something else", "Liste zeigt etwas anderes")
add("gm.rules.res.dry", "dry run, not sent", "Trockenlauf, nicht gesendet")
add("gm.rules.res.copy", "command copied", "Befehl kopiert")
add("gm.rules.res.open", "open, the list showed no change", "offen, die Liste zeigte keine Änderung")
add("gm.rules.res.skipped", "skipped", "übersprungen")
add("gm.rules.res.failed", "failed", "fehlgeschlagen")
add("gm.rules.wait.wait", "Pause between steps", "Pause zwischen den Schritten")
add("gm.rules.wait.gap", "Pause between steps", "Pause zwischen den Schritten")
add("gm.rules.wait.combat", "Waiting: combat", "Wartet: Kampf")
add(
  "gm.rules.wait.roster",
  "Waiting for the guild list, the step goes on by itself",
  "Wartet auf die Gildenliste, der Schritt geht danach von selbst weiter"
)
add(
  "gm.rules.wait.change",
  "Waiting for the change in the guild list. Type the command, or skip the step.",
  "Wartet auf die Änderung in der Gildenliste. Befehl eintippen oder Schritt überspringen."
)
add("gm.rules.wait.verify", "Waiting for the list to confirm", "Wartet auf die Bestätigung der Liste")
add("gm.rules.wait.click", "Click the button", "Auf den Knopf klicken")
add("gm.rules.wait.state", "Not possible in this state", "In diesem Zustand nicht möglich")

-- Assistant ----------------------------------------------------------------------------------------------------
add("gm.rules.wiz.title", "Rule assistant", "Regel-Assistent")
add("gm.rules.wiz.who", "1. Who?", "1. Wer?")
add("gm.rules.wiz.what", "2. What?", "2. Was?")
add("gm.rules.wiz.when", "3. When?", "3. Wann?")
add(
  "gm.rules.wiz.hint",
  "Days: for a rank rule the days in the rank, for inactivity the days offline.",
  "Tage: bei Rangregeln die Tage im Rang, bei Inaktivität die Tage offline."
)
add("gm.rules.wiz.create", "Create rule", "Regel anlegen")
add("gm.rules.wiz.done", "%d rule(s) created, still off", "%d Regel(n) angelegt, noch aus")
add("gm.rules.goal.promote", "Promote after time in the rank", "Befördern nach Zeit im Rang")
add("gm.rules.goal.demote", "Demote when inactive", "Degradieren bei Inaktivität")
add("gm.rules.goal.mark", "Mark inactive members", "Inaktive markieren")
add("gm.rules.goal.remove", "Remove inactive members", "Inaktive entfernen")
add(
  "gm.rules.draftMade",
  "%d draft(s) created, still off. Check the ranks, then switch on.",
  "%d Entwurf/Entwürfe angelegt, noch aus. Ränge prüfen, dann einschalten."
)
add("gm.rules.createDraft", "Create draft", "Entwurf anlegen")
add("gm.inactive.makeRule", "Make rule from this", "Regel daraus machen")
add(
  "gm.inactive.makeRule.tip",
  "Opens the assistant with this threshold and rank.\nThe rule starts off.",
  "Öffnet den Assistenten mit dieser Schwelle und diesem Rang.\nDie Regel startet aus."
)

-- Templates ------------------------------------------------------------------------------------------------------
local function tpl(id, title, titleDe, desc, descDe, warn, warnDe, params)
  add("gm.tpl." .. id .. ".title", title, titleDe)
  add("gm.tpl." .. id .. ".desc", desc, descDe)
  if warn then
    add("gm.tpl." .. id .. ".warn", warn, warnDe)
  end
  for _, p in ipairs(params) do
    add("gm.tpl." .. id .. ".p." .. p[1], p[2], p[3])
  end
end
local RANK, RANKS, DAYS = { "rank", "Rank", "Rang" }, { "ranks", "Ranks", "Ränge" }, { "days", "Days", "Tage" }
tpl(
  "promoteByTime",
  "Promote by time in rank",
  "Aufstieg nach Zeit im Rang",
  "Promotes one rank after N days in the rank.",
  "Befördert nach N Tagen im Rang einen Rang.",
  "Needs the date of the last rank change. Fresh installs only know a minimum.",
  "Braucht das Datum der letzten Rangänderung. Frisch installiert nur ein Minimum.",
  { RANK, DAYS }
)
tpl(
  "promoteByGuildTime",
  "Promote by time in guild",
  "Aufstieg nach Gildenzeit",
  "Sets a higher rank after N days in the guild.",
  "Setzt nach N Tagen in der Gilde einen höheren Rang.",
  "Needs the join date. Add it by hand or from notes for faster results.",
  "Braucht das Beitrittsdatum. Für schnellere Ergebnisse von Hand oder aus Notizen eintragen.",
  { RANK, DAYS, { "targetRank", "Target rank", "Zielrang" } }
)
tpl(
  "promoteByLevel",
  "Promote by level",
  "Aufstieg nach Stufe",
  "Promotes one rank at a level.",
  "Befördert ab einer Stufe einen Rang.",
  nil,
  nil,
  { RANK, { "level", "Level", "Stufe" } }
)
tpl(
  "reviewNewcomers",
  "Check newcomers",
  "Neulinge prüfen",
  "Marks new members after N days for a look.",
  "Markiert Neulinge nach N Tagen zum Prüfen.",
  "Only members with a join date known to the day.",
  "Nur Mitglieder mit auf den Tag genauem Beitrittsdatum.",
  { RANK, DAYS }
)
tpl(
  "demoteByInactivity",
  "Demote when inactive",
  "Abstieg bei Inaktivität",
  "Demotes one rank when main and alts were offline for N days.",
  "Degradiert einen Rang, wenn Main und Alts N Tage offline waren.",
  nil,
  nil,
  { RANK, DAYS }
)
tpl(
  "markInactive",
  "Mark inactive",
  "Inaktive markieren",
  "Marks members who were offline for N days.",
  "Markiert Mitglieder, die N Tage offline waren.",
  nil,
  nil,
  { RANKS, DAYS }
)
tpl(
  "removeInactive",
  "Remove inactive",
  "Inaktive entfernen",
  "Removes members offline for N days.",
  "Entfernt Mitglieder, die N Tage offline waren.",
  "Removal cannot be undone. Every removal needs its own tick and confirmation.",
  "Entfernen ist endgültig. Jede Entfernung braucht ein Häkchen und eine Bestätigung.",
  { RANKS, DAYS, { "requireMark", "Only after the marker inactive", "Nur nach der Markierung inaktiv" } }
)
tpl(
  "cleanupAlts",
  "Clean up inactive alts",
  "Inaktive Alts aufräumen",
  "Marks alts that are offline while the main is active.",
  "Markiert Alts, die offline sind, während der Main aktiv ist.",
  "Needs main and alt links.",
  "Braucht Main-Alt-Verknüpfungen.",
  { RANKS, DAYS }
)
tpl(
  "matchAltRank",
  "Match alt rank to main",
  "Alt-Rang an Main angleichen",
  "Sets the rank of an alt to the rank of its main.",
  "Setzt den Rang eines Alts auf den Rang seines Mains.",
  "Needs main and alt links.",
  "Braucht Main-Alt-Verknüpfungen.",
  { RANKS }
)
tpl(
  "returnees",
  "Check returnees",
  "Rückkehrer prüfen",
  "Marks members who came back within N days.",
  "Markiert Mitglieder, die innerhalb von N Tagen zurückkamen.",
  "Needs a return seen by the add-on.",
  "Braucht eine vom Addon gesehene Rückkehr.",
  { RANKS, DAYS }
)
tpl(
  "writeJoinDate",
  "Write join date to note",
  "Beitrittsdatum in Notiz schreiben",
  "Writes the join date into the note.",
  "Schreibt das Beitrittsdatum in die Notiz.",
  "Only works if the client allows notes. Join date must be exact.",
  "Geht nur, wenn der Client Notizen erlaubt. Das Beitrittsdatum muss genau sein.",
  { RANKS, { "public", "Guild note (off: officer note)", "Gildennotiz (aus: Offiziersnotiz)" } }
)
tpl(
  "inactivityLadder",
  "Inactivity ladder",
  "Inaktivitätsleiter",
  "Three rules in one click: mark, demote, remove.",
  "Drei Regeln mit einem Klick: markieren, degradieren, entfernen.",
  "Creates three rules. The days rise from top to bottom.",
  "Legt drei Regeln an. Die Tage steigen von oben nach unten.",
  {
    RANKS,
    { "rank", "Rank to demote", "Rang zum Degradieren" },
    { "markDays", "Mark after days", "Markieren nach Tagen" },
    { "demoteDays", "Demote after days", "Degradieren nach Tagen" },
    { "removeDays", "Remove after days", "Entfernen nach Tagen" },
  }
)

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
