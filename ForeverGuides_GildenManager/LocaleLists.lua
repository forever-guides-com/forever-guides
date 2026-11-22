-- Texts of the tab "Lists" (Lists.lua): ban list, former members, alt groups and the re-join warning.
-- One row per text { key, English, German }. Style: docs/TEXT-STIL.md.
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

add("gm.tab.lists", "Lists", "Listen")
add("gm.lists.page.bans", "Ban list", "Banliste")
add("gm.lists.page.former", "Former members", "Ehemalige")
add("gm.lists.page.alts", "Alt groups", "Alt-Gruppen")
add("gm.lists.page.suggest", "Alt suggestions", "Alt-Vorschläge")
add("gm.lists.hint.bans", "Typed by hand, stays on this PC.", "Von Hand eingetragen, bleibt auf diesem PC.")
add("gm.lists.hint.former", "From the events: who left and when.", "Aus den Ereignissen: wer ging und wann.")
add(
  "gm.lists.hint.alts",
  "Main and alt links from the member list.",
  "Main- und Alt-Verbindungen aus der Mitgliederliste."
)
add(
  "gm.lists.hint.suggest",
  "Guesses from notes. Linked only when you click.",
  "Vermutungen aus Notizen. Verknüpft wird nur per Klick."
)
add("gm.lists.count", "Entries: %d of %d", "Einträge: %d von %d")
add("gm.lists.noMatch", "Nothing matches the search.", "Nichts passt zur Suche.")
add("gm.lists.empty.bans", "The ban list is empty.", "Die Banliste ist leer.")
add("gm.lists.empty.former", "No former members recorded yet.", "Noch keine Ehemaligen erfasst.")
add(
  "gm.lists.empty.alts",
  "No alt links yet. Set a main in the member list.",
  "Noch keine Alt-Verbindungen. Lege einen Main in der Mitgliederliste fest."
)
add(
  "gm.lists.empty.suggest",
  "No suggestions. Notes like \"Alt von Name\" or \"Name's alt\" produce some.",
  "Keine Vorschläge. Notizen wie „Alt von Name“ oder „Name's alt“ liefern welche."
)

add("gm.alt.title", "%s: alt of %s?", "%s: Alt von %s?")
add("gm.alt.link", "Link as alt", "Als Alt verknüpfen")
add("gm.alt.dismiss", "Discard the suggestion", "Vorschlag verwerfen")
add("gm.alt.conf.high", "high", "hoch")
add("gm.alt.conf.medium", "medium", "mittel")
add("gm.alt.conf.low", "low", "niedrig")
add("gm.alt.src.public", "guild note", "Gildennotiz")
add("gm.alt.src.officer", "officer note", "Offiziersnotiz")
add("gm.alt.src.own", "own note", "eigene Notiz")
add("gm.alt.reason.altOf", "%s names %s as the main", "%s nennt %s als Main")
add("gm.alt.reason.mainIs", "%s names %s as the main", "%s nennt %s als Main")
add("gm.alt.reason.possessive", "%s: \"%s's alt\"", "%s: „%s's Alt“")
add("gm.alt.reason.paren", "%s names %s in brackets", "%s nennt %s in Klammern")
add("gm.alt.reason.sameNote", "Same %s as %s", "Gleiche %s wie bei %s")
add("gm.alt.err.changed", "The links changed. The suggestion no longer fits.", "Die Verknüpfungen haben sich geändert. Der Vorschlag passt nicht mehr.")

add("gm.ban.add", "Add ban", "Ban eintragen")
add("gm.ban.title", "Ban list entry", "Banlisten-Eintrag")
add("gm.ban.name", "Name", "Name")
add("gm.ban.nameHint", "Name of the player", "Name des Spielers")
add("gm.ban.reason", "Reason", "Grund")
add("gm.ban.reasonHint", "Short reason", "Kurzer Grund")
add("gm.ban.note", "Note", "Notiz")
add("gm.ban.noteHint", "Own note", "Eigene Notiz")
add("gm.ban.save", "Save the entry", "Eintrag speichern")
add("gm.ban.edit", "Edit entry", "Eintrag ändern")
add("gm.ban.remove", "Remove entry", "Eintrag entfernen")
add("gm.ban.removeAsk", "Remove %s from the ban list?", "%s von der Banliste entfernen?")
add("gm.ban.noReason", "No reason", "Kein Grund")
add("gm.ban.err.name", "Enter a name.", "Gib einen Namen ein.")
add("gm.ban.err.limit", "The ban list is full.", "Die Banliste ist voll.")
add("gm.ban.warn", "On the ban list: %s (%s)", "Auf der Banliste: %s (%s)")
add("gm.ban.warnMain", "Alt of a banned main: %s (%s)", "Alt eines gebannten Mains: %s (%s)")
add("gm.ban.warnMore", "and %d more", "und %d weitere")

add("gm.former.leave", "Left", "Ausgetreten")
add("gm.former.remove", "Removed", "Entfernt")
add("gm.former.rank", "last rank %s", "letzter Rang %s")
add("gm.former.banned", "Banned", "Gebannt")
add("gm.former.ban", "Add to ban list", "Auf die Banliste")
add("gm.alts.list", "Alts: %s", "Alts: %s")

-- Sample entries of the demo mode.
add("gm.demo.ban.scam", "Gold scam in the guild chat", "Gold-Betrug im Gildenchat")
add("gm.demo.ban.note", "Seen again on another realm", "Auf einem anderen Realm wieder gesehen")
add("gm.demo.ban.dispute", "Left in a dispute", "Im Streit ausgetreten")
add("gm.demo.ban.rejoin", "Sample: banned and in the roster", "Beispiel: gebannt und in der Liste")

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
