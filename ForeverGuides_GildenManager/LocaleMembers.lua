-- Texts of the member links and the own note (Members.lua).
local _, gm = ...
if not gm.ext then
  return
end

gm.FG.AddLocale("enUS", {
  ["gm.col.main"] = "Main",
  ["gm.col.mainValue"] = "Main: %s",
  ["gm.detail.main"] = "Main: %s",
  ["gm.detail.alts"] = "Alts: %s",
  ["gm.detail.note"] = "Own note: %s",
  ["gm.edit"] = "Main and note",
  ["gm.edit.title"] = "Main and note",
  ["gm.edit.main"] = "Main character",
  ["gm.edit.mainEmpty"] = "Empty: is a main itself",
  ["gm.edit.note"] = "Own note",
  ["gm.edit.noteEmpty"] = "No note",
  ["gm.edit.save"] = "Save",
  ["gm.err.hasAlts"] = "This member has alts itself",
  ["gm.err.mainIsAlt"] = "That main is an alt itself",
})
gm.FG.AddLocale("deDE", {
  ["gm.col.main"] = "Main",
  ["gm.col.mainValue"] = "Main: %s",
  ["gm.detail.main"] = "Main: %s",
  ["gm.detail.alts"] = "Alts: %s",
  ["gm.detail.note"] = "Eigene Notiz: %s",
  ["gm.edit"] = "Main und Notiz",
  ["gm.edit.title"] = "Main und Notiz",
  ["gm.edit.main"] = "Main-Charakter",
  ["gm.edit.mainEmpty"] = "Leer: ist selbst Main",
  ["gm.edit.note"] = "Eigene Notiz",
  ["gm.edit.noteEmpty"] = "Keine Notiz",
  ["gm.edit.save"] = "Speichern",
  ["gm.err.hasAlts"] = "Dieses Mitglied hat selbst Alts",
  ["gm.err.mainIsAlt"] = "Dieser Main ist selbst ein Alt",
})
