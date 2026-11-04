-- Texts of the help buttons of the tabs Inactive, Log and Lists, of the member dialog and of the tour of the
-- guild page (Tour.lua). One row per text { key, English, German }, so both languages carry the same keys.
-- Style: docs/TEXT-STIL.md (tour steps: one sentence of at most 100 characters).
local _, gm = ...
if not gm.ext then
  return
end

local T = {}
local function add(key, en, de)
  T[#T + 1] = { key, en, de }
end

-- Help buttons ------------------------------------------------------------------------------------------------
add("gm.help.inactive", "Inactive members", "Inaktive Mitglieder")
add(
  "gm.help.inactive.help",
  "Members by last online time.\nSet the days and filter by rank.\nA click opens the detail card.\nThe button makes a rule from your values.\nNothing changes before you confirm.",
  "Mitglieder nach letzter Anmeldung.\nTage einstellen, nach Rang filtern.\nEin Klick öffnet die Detailkarte.\nDer Knopf macht aus den Werten eine Regel.\nOhne Bestätigung ändert sich nichts."
)
add("gm.help.log", "Log", "Protokoll")
add(
  "gm.help.log.help",
  "Events: what happened in the guild.\nActions: what this add-on did.\nRank changes can be undone for a while.\nRemoved members can be invited again.\nExport and import stay on this PC.",
  "Ereignisse: was in der Gilde geschah.\nAktionen: was dieses Addon tat.\nRangänderungen lassen sich eine Weile zurücknehmen.\nEntfernte Mitglieder kannst du wieder einladen.\nExport und Import bleiben auf diesem PC."
)
add("gm.help.lists", "Lists", "Listen")
add(
  "gm.help.lists.help",
  "Ban list: typed by hand, a warning only.\nFormer members: from the events, with last rank.\nAlt groups: from the main and alt links.\nInvite again shows a preview first.\nNothing is removed or invited automatically.",
  "Banliste: von Hand, nur eine Warnung.\nEhemalige: aus den Ereignissen, mit letztem Rang.\nAlt-Gruppen: aus den Main-und-Alt-Links.\nWieder einladen zeigt zuerst eine Vorschau.\nNichts wird automatisch entfernt oder eingeladen."
)
add(
  "gm.edit.help",
  "Main: links an alt to its main.\nNote: only for you, stays on this PC.\nBirthday and absence feed the overview.\nJoin: sets the join date by hand.",
  "Main: verknüpft einen Alt mit seinem Main.\nNotiz: nur für dich, bleibt auf diesem PC.\nGeburtstag und Abwesenheit speisen die Übersicht.\nBeitritt: setzt das Beitrittsdatum von Hand."
)

-- Tour of the guild page --------------------------------------------------------------------------------------
add("tour.guildmanager.title", "Guild tools", "Gildenwerkzeuge")
add("tour.guildmanager.intro.title", "GildenManager", "GildenManager")
add(
  "tour.guildmanager.intro.text",
  "Tools for your guild (Enter: next, Esc: end).",
  "Werkzeuge für deine Gilde (Enter: weiter, Esc: Ende)."
)
add("tour.guildmanager.tabs.title", "Tabs", "Reiter")
add(
  "tour.guildmanager.tabs.text",
  "Overview, Rules, Inactive, Log, Lists, Settings (Tab, Enter).",
  "Übersicht, Regeln, Inaktiv, Protokoll, Listen, Einstellungen (Tab, Enter)."
)
add("tour.guildmanager.due.title", "Due now", "Jetzt fällig")
add(
  "tour.guildmanager.due.text",
  "What your rules suggest today. A click opens the preview.",
  "Was deine Regeln heute vorschlagen. Ein Klick öffnet die Vorschau."
)
add("tour.guildmanager.info.title", "Info buttons", "Info-Knöpfe")
add(
  "tour.guildmanager.info.text",
  "The i button explains its area (Enter shows it).",
  "Der i-Knopf erklärt seinen Bereich (Enter zeigt ihn)."
)
add("tour.guildmanager.rules.title", "Rules", "Regeln")
add(
  "tour.guildmanager.rules.text",
  "Rules only suggest. You tick, confirm and click each step.",
  "Regeln schlagen nur vor. Du hakst an, bestätigst und klickst."
)
add("tour.guildmanager.safety.title", "Dry run", "Trockenlauf")
add(
  "tour.guildmanager.safety.text",
  "The dry run is on first and sends nothing. Switch it off in Settings.",
  "Der Trockenlauf ist zuerst an und sendet nichts. Aus unter Einstellungen."
)
add("tour.guildmanager.share.title", "Sharing", "Teilen")
add(
  "tour.guildmanager.share.text",
  "Sharing is off until you switch it on (Settings, Sharing).",
  "Teilen ist aus, bis du es einschaltest (Einstellungen, Teilen)."
)
add("gm.tour.offerTitle", "Tour GildenManager?", "Tour zum GildenManager?")
add("gm.tour.offerText", "A short tour of the tabs.", "Eine kurze Tour durch die Reiter.")

local en, de = {}, {}
for _, row in ipairs(T) do
  en[row[1]], de[row[1]] = row[2], row[3]
end
gm.FG.AddLocale("enUS", en)
gm.FG.AddLocale("deDE", de)
