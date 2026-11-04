-- Texts of the tab "Log" (ActionLog.lua, LogLogic.lua) and of the export and import windows (Export.lua,
-- ExportLogic.lua). One row per text { key, English, German }, so both languages carry the same keys.
-- Style: docs/TEXT-STIL.md.
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

add("gm.tab.log", "Log", "Protokoll")
add("gm.log.clear", "Clear log", "Protokoll löschen")
add("gm.log.clearAsk", "Delete all log entries?", "Alle Protokolleinträge löschen?")
add("gm.log.clearEvents", "Clear events", "Ereignisse löschen")
add(
  "gm.log.clearEventsAsk",
  "Delete all events? Join and rank dates stay.",
  "Alle Ereignisse löschen? Beitritts- und Rangdaten bleiben."
)
add("gm.log.count", "Entries: %d of %d", "Einträge: %d von %d")
add("gm.log.pageOf", "Page %d of %d", "Seite %d von %d")
add("gm.log.page.actions", "Actions", "Aktionen")
add("gm.log.page.events", "Events", "Ereignisse")
add("gm.log.kind", "Kind", "Art")
add("gm.log.all", "All", "Alle")
add("gm.log.period", "Period", "Zeitraum")
add("gm.log.period.0", "All time", "Gesamt")
add("gm.log.period.7", "Last 7 days", "Letzte 7 Tage")
add("gm.log.period.30", "Last 30 days", "Letzte 30 Tage")
add("gm.log.period.90", "Last 90 days", "Letzte 90 Tage")
add("gm.log.resultLabel", "Result", "Ergebnis")
add("gm.log.filter.sent", "Sent", "Gesendet")
add("gm.log.filter.verified", "Verified", "Bestätigt")
add("gm.log.filter.unverified", "Unverified", "Ungeprüft")
add("gm.log.filter.mismatch", "Not matching", "Abweichend")
add("gm.log.filter.undone", "Undone", "Rückgängig")
add("gm.log.result.sent", "sent", "gesendet")
add("gm.log.result.verified", "verified", "bestätigt")
add("gm.log.result.unverified", "unverified", "ungeprüft")
add("gm.log.result.mismatch", "not matching", "abweichend")
add("gm.log.undone", "undone", "rückgängig")
add("gm.log.rule", "Rule: %s", "Regel: %s")
add("gm.log.member", "Member", "Mitglied")
add("gm.log.ruleField", "Rule", "Regel")
add("gm.log.export", "Export", "Export")
add("gm.log.import", "Import", "Import")
add("gm.log.prev", "Back", "Zurück")
add("gm.log.next", "Next", "Weiter")
add("gm.log.undoTip", "Opens the preview of the reverse step.", "Öffnet die Vorschau des Gegenschritts.")
add("gm.log.emptyActions", "No actions yet.", "Noch keine Aktionen.")
add(
  "gm.log.emptyEvents",
  "No events yet. They appear as the roster changes.",
  "Noch keine Ereignisse. Sie entstehen mit der Gildenliste."
)
add("gm.log.noMatch", "Nothing matches the filter.", "Nichts passt zum Filter.")

add("gm.ev.join", "Joined", "Beigetreten")
add("gm.ev.leave", "Left", "Ausgetreten")
add("gm.ev.remove", "Removed", "Entfernt")
add("gm.ev.promote", "Promoted", "Befördert")
add("gm.ev.demote", "Demoted", "Degradiert")
add("gm.ev.rename", "Renamed", "Umbenannt")
add("gm.ev.note", "Note changed", "Notiz geändert")
add("gm.ev.return", "Returned", "Zurückgekehrt")
add("gm.ev.note.public", "guild note", "Gildennotiz")
add("gm.ev.note.officer", "officer note", "Offiziersnotiz")
add("gm.ev.note.both", "both notes", "beide Notizen")
add("gm.ev.returnDays", "offline for %d days before", "vorher %d Tage offline")
add("gm.ev.by", "by %s", "durch %s")
add("gm.ev.fuzz", "up to %d days earlier", "bis zu %d Tage früher")

add("gm.exp.window", "Export", "Export")
add("gm.exp.format", "Format", "Format")
add("gm.exp.fmt.text", "Text", "Text")
add("gm.exp.fmt.csv", "CSV", "CSV")
add("gm.exp.fmt.json", "JSON", "JSON")
add("gm.exp.fmt.backup", "Restore point", "Sicherungspunkt")
add("gm.exp.part.members", "Members and notes", "Mitglieder und Notizen")
add("gm.exp.part.events", "Events", "Ereignisse")
add("gm.exp.part.actions", "Actions", "Aktionen")
add("gm.exp.part.bans", "Ban list", "Banliste")
add("gm.exp.part.rules", "Rules", "Regeln")
add(
  "gm.exp.note",
  "Nothing is sent. The text stays on this PC.",
  "Nichts wird gesendet. Der Text bleibt auf diesem PC."
)
add("gm.exp.create", "Create", "Erstellen")
add("gm.exp.copyTitle", "Export", "Export")
add("gm.exp.copyHint", "Ctrl+A, then Ctrl+C copies the text.", "Strg+A, dann Strg+C kopiert den Text.")
add(
  "gm.exp.copyHintBackup",
  "Keep this text safe. Import restores it.",
  "Text sicher aufbewahren. Der Import stellt ihn wieder her."
)
add("gm.exp.title", "GildenManager export: %s", "GildenManager Export: %s")
add("gm.exp.sec.members", "Members (%d)", "Mitglieder (%d)")
add("gm.exp.sec.events", "Events (%d)", "Ereignisse (%d)")
add("gm.exp.sec.actions", "Actions (%d)", "Aktionen (%d)")
add("gm.exp.sec.bans", "Ban list (%d)", "Banliste (%d)")
add("gm.exp.sec.rules", "Rules (%d)", "Regeln (%d)")
add("gm.exp.truncated", "[Cut: the text was too long]", "[Gekürzt: der Text war zu lang]")
add("gm.exp.truncatedNote", "The export was cut. Pick fewer parts.", "Der Export wurde gekürzt. Wähle weniger Teile.")
add("gm.exp.err.noParts", "Pick at least one part.", "Wähle mindestens einen Teil.")
add("gm.exp.err.tooLarge", "Too large. Lower the log sizes.", "Zu groß. Verkleinere die Protokolle.")
add("gm.exp.err.json", "Could not build the text.", "Der Text ließ sich nicht erstellen.")
add("gm.exp.err.format", "Unknown format.", "Unbekanntes Format.")
add("gm.exp.err.noCodec", "Compression is not available.", "Komprimierung ist nicht verfügbar.")

add("gm.imp.window", "Import restore point", "Sicherungspunkt importieren")
add("gm.imp.hint", "Paste the restore point, then check.", "Sicherungspunkt einfügen, dann prüfen.")
add("gm.imp.check", "Check", "Prüfen")
add("gm.imp.apply", "Apply (%d)", "Übernehmen (%d)")
add("gm.imp.from", "Restore point of %s (%s)", "Sicherungspunkt von %s (%s)")
add("gm.imp.otherGuild", "This is another guild than yours.", "Das ist eine andere Gilde als deine.")
add(
  "gm.imp.counts",
  "New or changed: %d members, %d events, %d actions, %d bans, %d rules",
  "Neu oder geändert: %d Mitglieder, %d Ereignisse, %d Aktionen, %d Bans, %d Regeln"
)
add("gm.imp.repaired", "%d damaged entries skipped.", "%d beschädigte Einträge übersprungen.")
add("gm.imp.conflicts", "%d clashes with your own entries.", "%d Konflikte mit deinen eigenen Einträgen.")
add("gm.imp.nothing", "Nothing new in this restore point.", "Nichts Neues in diesem Sicherungspunkt.")
add("gm.imp.listHint", "Click a line to switch its choice.", "Zeile anklicken, um die Wahl zu wechseln.")
add("gm.imp.conflict", "Mine: %s / Backup: %s", "Meins: %s / Sicherung: %s")
add("gm.imp.keepMine", "Keep mine", "Meins behalten")
add("gm.imp.takeBackup", "Take backup", "Sicherung nehmen")
add("gm.imp.allMine", "Keep all mine", "Alles Meins behalten")
add("gm.imp.allTheirs", "Take all from backup", "Alles aus Sicherung")
add("gm.imp.field.note", "Note", "Notiz")
add("gm.imp.field.main", "Main", "Main")
add("gm.imp.field.joined", "Join date", "Beitrittsdatum")
add("gm.imp.field.rankSince", "In rank since", "Im Rang seit")
add("gm.imp.field.ban", "Ban entry", "Banlisten-Eintrag")
add("gm.imp.field.rule", "Rule", "Regel")
add("gm.imp.confirmTitle", "Import now?", "Jetzt importieren?")
add(
  "gm.imp.confirmText",
  "Adds %d entries and takes %d values from the backup. Your other entries stay.",
  "Fügt %d Einträge hinzu und übernimmt %d Werte aus der Sicherung. Der Rest bleibt."
)
add("gm.imp.yes", "Import", "Importieren")
add("gm.imp.done", "%d entries imported", "%d Einträge importiert")
add("gm.imp.err.empty", "Nothing pasted.", "Nichts eingefügt.")
add("gm.imp.err.format", "Not a restore point.", "Kein Sicherungspunkt.")
add("gm.imp.err.tooLarge", "The text is too large.", "Der Text ist zu groß.")
add("gm.imp.err.noCodec", "Compression is not available.", "Komprimierung ist nicht verfügbar.")
add("gm.imp.err.decode", "The text is damaged.", "Der Text ist beschädigt.")
add("gm.imp.err.json", "The content is damaged.", "Der Inhalt ist beschädigt.")
add("gm.imp.err.newer", "Made by a newer version.", "Von einer neueren Version erstellt.")
add(
  "gm.imp.err.sum",
  "Checksum wrong. The text was changed or cut.",
  "Prüfsumme falsch. Der Text wurde geändert oder gekürzt."
)
add("gm.imp.err.shape", "The content has the wrong shape.", "Der Inhalt hat die falsche Form.")

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
