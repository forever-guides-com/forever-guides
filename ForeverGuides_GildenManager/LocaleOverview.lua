-- Texts of the tab "Overview" (Overview.lua, RemindersLogic.lua): what is due, anniversaries, birthdays,
-- returners, the traffic light per rank, the week, the input of birthday and absence and the options of the
-- card "Reminders". One row per text { key, English, German }, so both languages carry the same keys.
-- Style: docs/TEXT-STIL.md.
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

add("gm.tab.overview", "Overview", "Übersicht")
add("gm.rem.noData", "No guild data yet", "Noch keine Gildendaten")
add("gm.rem.more", "and %d more", "und %d weitere")
add("gm.rem.local", "Stays on this PC, never sent.", "Bleibt auf diesem PC, wird nie gesendet.")
add("gm.rem.when.today", "today", "heute")
add("gm.rem.when.tomorrow", "tomorrow", "morgen")
add("gm.rem.when.days", "in %d days", "in %d Tagen")
add("gm.rem.ago.yesterday", "yesterday", "gestern")
add("gm.rem.ago.days", "%d days ago", "vor %d Tagen")

-- Due.
add("gm.rem.due", "Due", "Fällig")
add(
  "gm.rem.due.help",
  "Hint from your active rules.\nNothing runs from here.",
  "Hinweis aus deinen aktiven Regeln.\nHier läuft nichts ab."
)
add("gm.rem.due.group.promote", "Promote", "Befördern")
add("gm.rem.due.group.demote", "Demote", "Degradieren")
add("gm.rem.due.group.remove", "Remove", "Entfernen")
add("gm.rem.due.group.mark", "To check", "Prüfen")
add("gm.rem.due.line", "%s (%d): %s", "%s (%d): %s")
add("gm.rem.due.none", "Nothing due", "Nichts fällig")
add("gm.rem.due.noRules", "No rule is on. Make one in Rules.", "Keine Regel aktiv. Lege eine unter Regeln an.")
add("gm.rem.due.open", "Open Rules", "Regeln öffnen")

-- Anniversaries and birthdays.
add("gm.rem.people", "Anniversaries, birthdays", "Jubiläen und Geburtstage")
add(
  "gm.rem.people.help",
  "Joins and birthdays of the next days.\nBirthdays are typed by hand.",
  "Beitritte und Geburtstage der nächsten Tage.\nGeburtstage trägst du von Hand ein."
)
add("gm.rem.anniv.head", "Anniversaries", "Jubiläen")
add("gm.rem.anniv.line", "%s: %d years, %s", "%s: %d Jahre, %s")
add("gm.rem.anniv.one", "%s: 1 year, %s", "%s: 1 Jahr, %s")
add("gm.rem.anniv.unknown", "%d without an exact join date", "%d ohne genaues Beitrittsdatum")
add("gm.rem.birthday.head", "Birthdays", "Geburtstage")
add("gm.rem.birthday.line", "%s: %s, %s", "%s: %s, %s")
add("gm.rem.birthday.none", "No birthdays entered", "Keine Geburtstage eingetragen")
add("gm.rem.birthday.how", "Enter them in the member details.", "Trage sie in den Mitgliederdetails ein.")
add("gm.rem.people.empty", "Nothing in the next %d days", "Nichts in den nächsten %d Tagen")
add("gm.rem.birthday.clear", "Delete birthdays", "Geburtstage löschen")
add("gm.rem.clear.title", "Delete birthdays?", "Geburtstage löschen?")
add(
  "gm.rem.clear.body",
  "All birthdays of this guild are removed from this PC.",
  "Alle Geburtstage dieser Gilde werden von diesem PC entfernt."
)
add("gm.rem.clear.done", "%d birthdays deleted", "%d Geburtstage gelöscht")

-- Returners.
add("gm.rem.returners", "Returners", "Rückkehrer")
add(
  "gm.rem.returners.help",
  "Members who came back after a long break.\nShown for two weeks.",
  "Mitglieder, die nach langer Pause zurück sind.\nZwei Wochen lang sichtbar."
)
add("gm.rem.returner.line", "%s: back %s, offline %d days before", "%s: zurück %s, vorher %d Tage offline")
add("gm.rem.returner.lineShort", "%s: back %s", "%s: zurück %s")
add("gm.rem.returners.empty", "No returners in the last %d days", "Keine Rückkehrer in den letzten %d Tagen")

-- Traffic light and absence.
add("gm.rem.traffic", "Traffic light by rank", "Ampel je Rang")
add(
  "gm.rem.traffic.help",
  "Share of inactive members per rank.\nAbsent members do not count.",
  "Anteil Inaktiver je Rang.\nAbwesende zählen nicht mit."
)
add("gm.rem.traffic.hint", "Inactive: offline %d days or more", "Inaktiv: ab %d Tagen offline")
add("gm.rem.traffic.line", "%s: %s, %d of %d inactive (%d%%)", "%s: %s, %d von %d inaktiv (%d%%)")
add("gm.rem.traffic.noMembers", "%s: no members", "%s: keine Mitglieder")
add("gm.rem.level.green", "green", "grün")
add("gm.rem.level.yellow", "yellow", "gelb")
add("gm.rem.level.red", "red", "rot")
add("gm.rem.away.head", "Away", "Abwesend")
add("gm.rem.away.line", "%s, until %s", "%s, bis %s")

-- Week.
add("gm.rem.week", "Statistics of the week", "Wochenstatistik")
add(
  "gm.rem.week.help",
  "Counted from the recorded events.\nThe week start is an option.",
  "Gezählt aus den erfassten Ereignissen.\nDen Wochenbeginn stellst du ein."
)
add("gm.rem.week.range", "%s to %s", "%s bis %s")
add("gm.rem.week.joins", "Joined: %d", "Beigetreten: %d")
add("gm.rem.week.leaves", "Left: %d", "Ausgetreten: %d")
add("gm.rem.week.ranks", "Rank changes: %d", "Rangwechsel: %d")
add("gm.rem.week.empty", "Nothing recorded in this time", "In dieser Zeit wurde nichts erfasst")

-- Input in the member dialog and the detail lines.
add("gm.rem.birthday.fmt.dmy", "Birthday (DD.MM)", "Geburtstag (TT.MM)")
add("gm.rem.birthday.fmt.mdy", "Birthday (MM/DD)", "Geburtstag (MM/TT)")
add("gm.rem.birthday.fmt.iso", "Birthday (MM-DD)", "Geburtstag (MM-TT)")
add("gm.rem.birthdayEmpty", "Empty: none", "Leer: keiner")
add("gm.rem.away", "Away until", "Abwesend bis")
add("gm.rem.awayEmpty", "DD.MM.YYYY, empty: not away", "TT.MM.JJJJ, leer: nicht abwesend")
add("gm.rem.err.birthday.format", "Birthday: use day and month", "Geburtstag: nutze Tag und Monat")
add("gm.rem.err.birthday.month", "Birthday: month 1 to 12", "Geburtstag: Monat 1 bis 12")
add("gm.rem.err.birthday.day", "Birthday: this day does not exist", "Geburtstag: diesen Tag gibt es nicht")
add("gm.rem.err.away.invalid", "Away: not a date", "Abwesend: kein Datum")
add("gm.rem.err.away.ambiguous", "Away: use DD.MM.YYYY or YYYY-MM-DD", "Abwesend: nutze TT.MM.JJJJ oder JJJJ-MM-TT")
add("gm.rem.err.away.range", "Away: year out of range", "Abwesend: Jahr außerhalb des Bereichs")
add("gm.rem.err.away.past", "Away: the date is in the past", "Abwesend: das Datum liegt in der Vergangenheit")
add("gm.rem.err.away.far", "Away: at most one year ahead", "Abwesend: höchstens ein Jahr im Voraus")
add("gm.rem.detail.birthday", "Birthday: %s", "Geburtstag: %s")
add("gm.rem.detail.away", "Away until: %s", "Abwesend bis: %s")

-- Chat line at login.
add("gm.rem.chat.line", "GildenManager: %s", "GildenManager: %s")
add("gm.rem.chat.due", "Due: %d", "Fällig: %d")
add("gm.rem.chat.birthdays", "Birthdays: %s", "Geburtstage: %s")
add("gm.rem.chat.anniversaries", "Anniversaries: %s", "Jubiläen: %s")
add("gm.rem.chat.returners", "Returners: %d", "Rückkehrer: %d")

-- Import clashes (ExportLogic).
add("gm.imp.field.birthday", "Birthday", "Geburtstag")
add("gm.imp.field.away", "Absence", "Abwesenheit")

-- Options (card "Reminders" of the settings).
add("gm.set.card.reminders", "Reminders", "Erinnerungen")
add(
  "gm.set.card.reminders.help",
  "Lists of the Overview tab.\nStored per guild on this PC.",
  "Listen im Reiter Übersicht.\nGespeichert je Gilde auf diesem PC."
)
add("gm.set.reminderDays", "Look ahead", "Vorlauf")
add(
  "gm.set.reminderDays.hint",
  "Days ahead for birthdays and anniversaries",
  "Tage im Voraus für Geburtstage und Jubiläen"
)
add("gm.set.reminderChat", "Summary in chat", "Zusammenfassung im Chat")
add("gm.set.reminderChat.hint", "One line at login, off by default", "Eine Zeile beim Anmelden, standardmäßig aus")
add("gm.set.weekStart", "Week starts", "Woche beginnt")
add("gm.set.weekStart.hint", "Counts the statistics of the week", "Zählt die Wochenstatistik")
add("gm.set.weekStart.rolling", "Last 7 days", "Letzte 7 Tage")
add("gm.set.weekStart.mon", "Monday", "Montag")
add("gm.set.weekStart.sun", "Sunday", "Sonntag")

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
