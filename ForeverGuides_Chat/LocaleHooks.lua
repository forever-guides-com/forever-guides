-- Texts of the join with the chat of the game (ChatHooks.lua, ChatFilters.lua and the switches on the settings page).
local _, chat = ...
if not chat.hook then
  return
end

chat.FG.AddLocale("enUS", {
  ["chat.hooks.group"] = "Game chat",
  ["chat.hooks.hideWhispers"] = "Hide whispers in chat",
  ["chat.hooks.hideWhispers.hint"] = "Only what the messenger shows",
  ["chat.hooks.hideOnlyWhenOpen"] = "Only while window is open",
  ["chat.hooks.hideOnlyWhenOpen.hint"] = "Closed window: whispers stay visible",
  ["chat.hooks.ignoreIgnored"] = "Skip ignored players",
  ["chat.hooks.ignoreIgnored.hint"] = "Their messages stay out of the messenger",
  ["chat.hooks.otherChatAddonHint"] = "Other chat add-on hint",
  ["chat.hooks.otherChatAddonHint.hint"] = "Only with a game chat switch on",
  ["chat.hooks.otherAddons"] = "Other chat add-on seen. Behavior may differ.",
  ["chat.hooks.noReply"] = "No whisper to answer yet.",
  ["chat.hooks.filterOff"] = "Hiding is off after %d errors. Game chat shows whispers.",
})
chat.FG.AddLocale("deDE", {
  ["chat.hooks.group"] = "Spiel-Chat",
  ["chat.hooks.hideWhispers"] = "Flüstern ausblenden",
  ["chat.hooks.hideWhispers.hint"] = "Nur was der Messenger zeigt",
  ["chat.hooks.hideOnlyWhenOpen"] = "Nur bei offenem Fenster",
  ["chat.hooks.hideOnlyWhenOpen.hint"] = "Fenster zu: Flüstern bleiben sichtbar",
  ["chat.hooks.ignoreIgnored"] = "Ignorierte überspringen",
  ["chat.hooks.ignoreIgnored.hint"] = "Ihre Nachrichten bleiben draußen",
  ["chat.hooks.otherChatAddonHint"] = "Hinweis bei Chat-Addons",
  ["chat.hooks.otherChatAddonHint.hint"] = "Nur mit einem Spiel-Chat-Schalter an",
  ["chat.hooks.otherAddons"] = "Anderes Chat-Addon erkannt. Verhalten kann abweichen.",
  ["chat.hooks.noReply"] = "Noch kein Flüstern zum Antworten.",
  ["chat.hooks.filterOff"] = "Ausblenden aus nach %d Fehlern. Chat zeigt Flüstern wieder.",
})
