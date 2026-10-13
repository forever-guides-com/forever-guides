-- Forever Guides: GildenManager. Core: the check of the hook version, the local store and the
-- strings. The add-on has no window of its own, it extends the guild page of Forever Guides
-- through ForeverGuides.GuildExt. Only Actions.lua changes the guild, all data stays on this PC.
local ADDON_NAME, gm = ...

local FG = _G.ForeverGuides
local ext = FG and FG.GuildExt
-- No main add-on or a hook version this build does not know: stay silent, the guild page still works.
if not (ext and ext.version == 1) then
  return
end
gm.FG, gm.ext = FG, ext

gm.defaults = {
  v = 1,
  -- Offline days from which the tab "Inactive" lists a member.
  inactiveDays = 30,
  -- Per member key { name, main, mainKey, note } (MembersLogic.lua).
  members = {},
  -- Actions only show the preview and send nothing.
  dryRun = false,
  -- Log of the guild actions, oldest first (ActionsLogic.lua).
  log = {},
}
-- Usable before SavedVariables are read.
gm.db = FG.U.applyDefaults({}, gm.defaults)

-- What a companion add-on may use to run this add-on on a copy of its data in memory (see
-- GuildExt.Share): the defaults, the store and the member rules.
ext.Share("gildenmanager", {
  defaults = gm.defaults,
  Db = function()
    return gm.db
  end,
  SetDb = function(db)
    gm.db = db
  end,
  Members = function()
    return gm.MembersLogic
  end,
})

FG.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then
    return
  end
  local db = FG.U.applyDefaults(type(ForeverGuidesGMDB) == "table" and ForeverGuidesGMDB or {}, gm.defaults)
  gm.MembersLogic.Clean(db)
  gm.InactivityLogic.Clean(db)
  gm.ActionsLogic.Clean(db)
  ForeverGuidesGMDB, gm.db = db, db
end)

FG.AddLocale("enUS", {
  ["gm.tab.inactive"] = "Inactive",
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
  ["gm.inactive.days"] = "Offline for at least",
  ["gm.inactive.daysValue"] = "%d days",
  ["gm.inactive.count"] = "Inactive: %d of %d",
  ["gm.tab.log"] = "Log",
  ["gm.act.promote"] = "Promote",
  ["gm.act.demote"] = "Demote",
  ["gm.act.editNote"] = "Edit guild note",
  ["gm.act.editOfficerNote"] = "Edit officer note",
  ["gm.act.remove"] = "Remove",
  ["gm.act.confirm"] = "Confirm",
  ["gm.field.note"] = "New text",
  ["gm.confirm.name"] = "Type the name to confirm",
  ["gm.pv.rank"] = "Rank: %s > %s",
  ["gm.pv.rankN"] = "Rank %d",
  ["gm.pv.old"] = "Old: %s",
  ["gm.pv.new"] = "New: %s",
  ["gm.pv.empty"] = "(empty)",
  ["gm.pv.remove"] = "Removes %s from the guild",
  ["gm.dry.option"] = "Dry run",
  ["gm.dry.tip"] = "Actions only show the preview.\nNothing is sent.",
  ["gm.dry.hint"] = "Dry run: nothing is sent",
  ["gm.dry.done"] = "Dry run: %s for %s, nothing sent",
  ["gm.sent.promote"] = "Promotion sent: %s",
  ["gm.sent.demote"] = "Demotion sent: %s",
  ["gm.sent.editNote"] = "Note sent: %s",
  ["gm.sent.editOfficerNote"] = "Officer note sent: %s",
  ["gm.sent.remove"] = "Removal sent: %s",
  ["gm.log.clear"] = "Clear log",
  ["gm.log.clearAsk"] = "Delete all log entries?",
  ["gm.log.count"] = "Entries: %d of %d",
  ["gm.why.unknownAction"] = "Unknown action",
  ["gm.why.noRight"] = "Guild right missing",
  ["gm.why.noTarget"] = "Member not found",
  ["gm.why.unknownRank"] = "Rank unknown",
  ["gm.why.self"] = "Not on yourself",
  ["gm.why.leader"] = "Not on the guild master",
  ["gm.why.notLower"] = "Rank not below yours",
  ["gm.why.promoteCap"] = "Highest allowed rank",
  ["gm.why.lowest"] = "Already the lowest rank",
  ["gm.why.combat"] = "Not in combat",
  ["gm.why.throttle"] = "Wait a moment, then retry",
  ["gm.why.noApi"] = "Not available in this client",
  ["gm.why.noGuid"] = "Member ID missing, reload the list",
  ["gm.why.failed"] = "The game refused the call",
  ["gm.why.unchanged"] = "Text unchanged",
  ["gm.why.nameMismatch"] = "Name does not match",
})
FG.AddLocale("deDE", {
  ["gm.tab.inactive"] = "Inaktiv",
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
  ["gm.inactive.days"] = "Offline seit mindestens",
  ["gm.inactive.daysValue"] = "%d Tage",
  ["gm.inactive.count"] = "Inaktiv: %d von %d",
  ["gm.tab.log"] = "Protokoll",
  ["gm.act.promote"] = "Befördern",
  ["gm.act.demote"] = "Degradieren",
  ["gm.act.editNote"] = "Gildennotiz ändern",
  ["gm.act.editOfficerNote"] = "Offiziersnotiz ändern",
  ["gm.act.remove"] = "Entfernen",
  ["gm.act.confirm"] = "Bestätigen",
  ["gm.field.note"] = "Neuer Text",
  ["gm.confirm.name"] = "Name zur Bestätigung eingeben",
  ["gm.pv.rank"] = "Rang: %s > %s",
  ["gm.pv.rankN"] = "Rang %d",
  ["gm.pv.old"] = "Alt: %s",
  ["gm.pv.new"] = "Neu: %s",
  ["gm.pv.empty"] = "(leer)",
  ["gm.pv.remove"] = "Entfernt %s aus der Gilde",
  ["gm.dry.option"] = "Trockenlauf",
  ["gm.dry.tip"] = "Aktionen zeigen nur die Vorschau.\nNichts wird gesendet.",
  ["gm.dry.hint"] = "Trockenlauf: nichts wird gesendet",
  ["gm.dry.done"] = "Trockenlauf: %s bei %s, nichts gesendet",
  ["gm.sent.promote"] = "Beförderung gesendet: %s",
  ["gm.sent.demote"] = "Degradierung gesendet: %s",
  ["gm.sent.editNote"] = "Notiz gesendet: %s",
  ["gm.sent.editOfficerNote"] = "Offiziersnotiz gesendet: %s",
  ["gm.sent.remove"] = "Entfernung gesendet: %s",
  ["gm.log.clear"] = "Protokoll löschen",
  ["gm.log.clearAsk"] = "Alle Protokolleinträge löschen?",
  ["gm.log.count"] = "Einträge: %d von %d",
  ["gm.why.unknownAction"] = "Unbekannte Aktion",
  ["gm.why.noRight"] = "Gildenrecht fehlt",
  ["gm.why.noTarget"] = "Mitglied nicht gefunden",
  ["gm.why.unknownRank"] = "Rang unbekannt",
  ["gm.why.self"] = "Nicht bei dir selbst",
  ["gm.why.leader"] = "Nicht beim Gildenleiter",
  ["gm.why.notLower"] = "Rang nicht unter deinem",
  ["gm.why.promoteCap"] = "Höchster erlaubter Rang",
  ["gm.why.lowest"] = "Schon der unterste Rang",
  ["gm.why.combat"] = "Nicht im Kampf",
  ["gm.why.throttle"] = "Kurz warten, dann erneut",
  ["gm.why.noApi"] = "Im Client nicht verfügbar",
  ["gm.why.noGuid"] = "Mitglieds-ID fehlt, Liste neu laden",
  ["gm.why.failed"] = "Das Spiel hat den Aufruf abgelehnt",
  ["gm.why.unchanged"] = "Text unverändert",
  ["gm.why.nameMismatch"] = "Name stimmt nicht überein",
})
