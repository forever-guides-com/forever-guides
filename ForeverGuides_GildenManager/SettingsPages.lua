-- Which cards each page of the tab "Settings" holds and which options each card shows (the options
-- themselves are defined in SettingsLogic.lua). A card names its title and help through the locale
-- keys "gm.set.card.<id>" and "gm.set.card.<id>.help". Optional fields: columns (switches of the guild
-- list columns), fixed (the lines of the checks that cannot be switched off), note (locale key of a
-- plain text), build(card, api) (a package that fills the card on its own, e.g. sharing; api: ctx,
-- uiCtx, addText, addOption).
local _, gm = ...
if not gm.ext then
  return
end

gm.SettingsPages = {
  {
    id = "general",
    cards = {
      { id = "general", options = { "inactiveDays", "maxLevel" } },
      { id = "reminders", options = { "reminderDays", "reminderChat", "weekStart" } },
    },
  },
  {
    id = "protect",
    cards = {
      { id = "periods", options = { "newbieDays", "graceDays", "activeGroupDays" } },
      { id = "words", options = { "protectWords" } },
    },
  },
  {
    id = "actions",
    cards = {
      { id = "safety", options = { "dryRun", "removeNoPreview" }, fixed = true },
      { id = "run", options = { "actionBackend", "runMode", "pauseSec", "longPauseSec", "maxTotal" } },
      { id = "after", options = { "undoDays", "notifyDone" } },
    },
  },
  {
    id = "capture",
    cards = {
      { id = "record", options = { "history" } },
      { id = "limits", options = { "maxEvents", "maxActions" } },
    },
  },
  {
    id = "display",
    cards = {
      {
        id = "columns",
        columns = { { id = "gm-main", key = "gm.col.main" }, { id = "gm-joined", key = "gm.col.joined" } },
      },
      { id = "dates", options = { "dateFormat" } },
    },
  },
  {
    id = "share",
    cards = {
      {
        id = "share",
        options = { "shareChannel", "shareMinRank", "shareJoins", "shareMarks", "shareNotes" },
        build = function(card, api)
          gm.ShareTab.Build(card, api)
        end,
      },
    },
  },
}
