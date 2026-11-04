-- Title of the window (ChatWindow.lua). The other texts are in LocaleWindow.lua.
local _, chat = ...
if not chat.hook then
  return
end

chat.FG.AddLocale("enUS", {
  ["chat.win.title"] = "Forever Chat",
})
chat.FG.AddLocale("deDE", {
  ["chat.win.title"] = "Forever Chat",
})
