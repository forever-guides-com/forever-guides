-- Texts of the saved chats of the messenger (ChatArchive.lua, ChatArchiveUI.lua): the options of the group
-- "History", the notes under it and the dialog that deletes the saved chats.
-- Style: docs/TEXT-STIL.md (label up to 25 characters, hint up to 60).
local _, chat = ...
if not chat.hook then
  return
end

chat.FG.AddLocale("enUS", {
  ["chat.set.group.history"] = "History",
  ["chat.set.archive"] = "Save chats",
  ["chat.set.archive.hint"] = "Chats stay after a reload and a restart.",
  ["chat.set.archive.tip"] = "Chats stay after reload.\nSaved on this PC only.",
  ["chat.set.archiveDays"] = "Keep for",
  ["chat.set.archiveDays.hint"] = "The addon removes older lines.",
  ["chat.set.archiveDays.7"] = "7 days",
  ["chat.set.archiveDays.30"] = "30 days",
  ["chat.set.archiveDays.90"] = "90 days",
  ["chat.set.archivePublic"] = "Public channels",
  ["chat.set.archivePublic.hint"] = "Save Trade, General and others, 100 lines.",
  ["chat.set.archivePublic.tip"] = "On by default.\nThese channels are very busy.",
  ["chat.archive.info1"] = "The chats stay after a reload and a restart.",
  ["chat.archive.info2"] = "The addon saves on this PC only and sends nothing.",
  ["chat.archive.info3"] = "Saved: chat texts, sender names and times.",
  ["chat.archive.info4"] = "Battle.net chats also save BattleTag and character.",
  ["chat.archive.info5"] = "\"Public channels\" on: lines of strangers are saved too.",
  ["chat.archive.info6"] = "Switching off deletes nothing. Use the button below.",
  ["chat.archive.scope"] = "Delete which chats",
  ["chat.archive.scope.all"] = "All chats",
  ["chat.archive.clear"] = "Delete saved chats",
  ["chat.archive.clear.tip"] = "Deletes after asking.\nPins and notes stay.",
  ["chat.archive.clear.title"] = "Delete saved chats",
  ["chat.archive.clear.text"] = "The addon deletes the chosen chats for good.",
  ["chat.archive.clear.yes"] = "Delete",
  ["chat.archive.cleared"] = "Saved chats deleted (%d lines).",
})
chat.FG.AddLocale("deDE", {
  ["chat.set.group.history"] = "Verlauf",
  ["chat.set.archive"] = "Chats speichern",
  ["chat.set.archive.hint"] = "Chats bleiben nach Reload und Neustart erhalten.",
  ["chat.set.archive.tip"] = "Chats bleiben nach Reload.\nNur auf diesem PC gespeichert.",
  ["chat.set.archiveDays"] = "Aufbewahren",
  ["chat.set.archiveDays.hint"] = "Das Addon entfernt ältere Zeilen.",
  ["chat.set.archiveDays.7"] = "7 Tage",
  ["chat.set.archiveDays.30"] = "30 Tage",
  ["chat.set.archiveDays.90"] = "90 Tage",
  ["chat.set.archivePublic"] = "Öffentliche Kanäle",
  ["chat.set.archivePublic.hint"] = "Handel, Allgemein und weitere speichern, 100 Zeilen.",
  ["chat.set.archivePublic.tip"] = "Standard an.\nDiese Kanäle sind sehr laut.",
  ["chat.archive.info1"] = "Die Chats bleiben nach Reload und Neustart erhalten.",
  ["chat.archive.info2"] = "Das Addon speichert nur auf diesem PC und sendet nichts.",
  ["chat.archive.info3"] = "Gespeichert: Chattexte, Absendernamen und Zeiten.",
  ["chat.archive.info4"] = "Bei Battle.net auch BattleTag und Charakter gespeichert.",
  ["chat.archive.info5"] = "Bei „Öffentliche Kanäle“ an auch Zeilen von Fremden.",
  ["chat.archive.info6"] = "Ausschalten löscht nichts. Dafür gibt es den Knopf unten.",
  ["chat.archive.scope"] = "Welche Chats löschen",
  ["chat.archive.scope.all"] = "Alle Chats",
  ["chat.archive.clear"] = "Gespeicherte Chats löschen",
  ["chat.archive.clear.tip"] = "Löscht nach Rückfrage.\nPins und Notizen bleiben.",
  ["chat.archive.clear.title"] = "Gespeicherte Chats löschen",
  ["chat.archive.clear.text"] = "Das Addon löscht die gewählten Chats endgültig.",
  ["chat.archive.clear.yes"] = "Löschen",
  ["chat.archive.cleared"] = "Gespeicherte Chats gelöscht (%d Zeilen).",
})
