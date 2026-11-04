-- Texts of sharing with other officers (ShareLogic.lua, Share.lua, ShareTab.lua) and the options of the
-- page "Sharing" in the tab "Settings". One row per text { key, English, German }. Style: docs/TEXT-STIL.md.
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

-- Options (labels up to 25 characters, hints up to 60).
add("gm.set.shareJoins", "Join dates", "Beitrittsdaten")
add(
  "gm.set.shareJoins.hint",
  "Send and accept join dates of members",
  "Beitrittsdaten von Mitgliedern senden und annehmen"
)
add("gm.set.shareMarks", "Marks", "Markierungen")
add("gm.set.shareMarks.hint", "Send and accept: returned, inactive", "Senden und annehmen: zurückgekehrt, inaktiv")
add("gm.set.shareNotes", "Own notes", "Eigene Notizen")
add(
  "gm.set.shareNotes.hint",
  "Notes can hold private text. Off is safer.",
  "Notizen können Privates enthalten. Aus ist sicherer."
)
add("gm.set.shareChannel", "Channel", "Kanal")
add("gm.set.shareChannel.hint", "Both sides need the same channel", "Beide Seiten brauchen denselben Kanal")
add("gm.set.shareChannel.officer", "Officer chat", "Offizierschat")
add("gm.set.shareChannel.guild", "Guild chat", "Gildenchat")
add("gm.set.shareMinRank", "Accept from rank", "Annehmen ab Rang")
add(
  "gm.set.shareMinRank.hint",
  "This rank and better, others are dropped",
  "Dieser Rang und besser, andere werden verworfen"
)
add("gm.set.unit.rank", "Rank %d", "Rang %d")

-- Page.
add(
  "gm.share.intro",
  "Share data with officers who use the GildenManager. Received data waits in the inbox.",
  "Daten mit Offizieren teilen, die den GildenManager nutzen. Empfangenes wartet im Eingang."
)
add("gm.share.send", "Send my data", "Meine Daten senden")
add(
  "gm.share.send.tip",
  "Sends the chosen categories to your officers.",
  "Sendet die gewählten Kategorien an deine Offiziere."
)
add("gm.share.recv", "Receive data", "Daten empfangen")
add("gm.share.recv.tip", "Puts data of others into the inbox.", "Legt Daten anderer in den Eingang.")
add(
  "gm.share.noChannel",
  "Your rank cannot use the officer chat. Choose the guild chat or ask your guild master.",
  "Dein Rang darf den Offizierschat nicht nutzen. Wähle den Gildenchat oder frag den Leiter."
)
add("gm.share.noGuild", "Sharing needs a guild.", "Teilen braucht eine Gilde.")
add("gm.share.cats", "Categories for sending and receiving", "Kategorien zum Senden und Empfangen")
add("gm.share.rankNames", "Accepted: %s", "Angenommen von: %s")
add("gm.share.rankNone", "Accepted: nobody known yet", "Angenommen von: noch niemand bekannt")
add("gm.share.counts", "Sent: %d, received: %d, in the inbox: %d", "Gesendet: %d, empfangen: %d, im Eingang: %d")
add("gm.share.peers", "Officers sharing right now: %d", "Offiziere, die gerade teilen: %d")
add("gm.share.open", "Open sharing settings", "Teilen-Einstellungen öffnen")
add("gm.share.needRecv", "The inbox needs receiving to be on.", "Der Eingang braucht eingeschaltetes Empfangen.")

-- Inbox.
add("gm.share.inbox", "Inbox", "Eingang")
add("gm.share.inbox.empty", "Nothing waiting.", "Nichts wartet.")
add("gm.share.inbox.more", "%d more offers are not shown", "%d weitere Angebote werden nicht angezeigt")
add("gm.share.what.J", "Join date: %s", "Beitritt: %s")
add("gm.share.what.M", "Marks: %s", "Markierungen: %s")
add("gm.share.what.N", "Note: %s", "Notiz: %s")
add("gm.share.from", "From %s (%s), %s, source %s", "Von %s (%s), %s, Quelle %s")
add("gm.share.also", "also from %d more", "auch von %d weiteren")
add("gm.share.adopt", "Adopt", "Übernehmen")
add("gm.share.discard", "Discard", "Verwerfen")
add("gm.share.discardAll", "Discard all", "Alle verwerfen")
add("gm.share.discardAll.title", "Discard all offers?", "Alle Angebote verwerfen?")
add(
  "gm.share.discardAll.body",
  "The inbox is emptied. Your data stays as it is.",
  "Der Eingang wird geleert. Deine Daten bleiben, wie sie sind."
)
add("gm.share.wipe", "Delete everything", "Alles löschen")
add("gm.share.wipe.title", "Delete all sharing data?", "Alle Teilen-Daten löschen?")
add(
  "gm.share.wipe.body",
  "Inbox, counters and the sent record are deleted. Your own data stays.",
  "Eingang, Zähler und Sendeprotokoll werden gelöscht. Deine Daten bleiben."
)
add("gm.share.result.ok", "Adopted.", "Übernommen.")
add("gm.share.result.same", "Nothing new, removed.", "Nichts Neues, entfernt.")
add("gm.share.result.conflict", "A note exists already, not changed.", "Es gibt schon eine Notiz, nichts geändert.")
add("gm.share.result.gone", "The offer is gone.", "Das Angebot ist weg.")

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
