-- Card "Web addresses in chat" on the tab Chat name (ChatUrl.lua): one switch, on by default. Every change goes
-- through Store.set and the next chat line follows.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.ChatUrlSettings = S

ns.AddLocale("enUS", {
  ["chaturl.heading"] = "Web addresses in chat",
  ["chaturl.hint"] = "Turns web addresses in chat lines into links. A click shows a window to copy the address, the game cannot open web pages.\nOnly on your screen, nothing is sent.",
  ["chaturl.enable"] = "Clickable web addresses in chat",
  ["chaturl.enable.tip"] = "On by default.\nOff leaves every chat line as it is.",
})
ns.AddLocale("deDE", {
  ["chaturl.heading"] = "Webadressen im Chat",
  ["chaturl.hint"] = "Macht Webadressen in Chatzeilen zu Links. Ein Klick zeigt ein Fenster zum Kopieren der Adresse, das Spiel kann keine Webseiten öffnen.\nNur auf deinem Bildschirm, es wird nichts gesendet.",
  ["chaturl.enable"] = "Webadressen im Chat klickbar",
  ["chaturl.enable.tip"] = "Standard an.\nAus lässt jede Chatzeile unverändert.",
})

function S.Add(view)
  ns.AddHeading(view, "chaturl.heading")
  ns.AddParagraph(view, "chaturl.hint", { role = "micro", color = "textMuted", gap = 6 })
  local toggle = W.Toggle(view.content, {
    key = "chaturl.enable",
    get = function()
      return ns.ChatUrl.Enabled()
    end,
    set = function(v)
      Store.set("settings.chatUrl", v == true)
    end,
    tooltip = "chaturl.enable",
    tooltipText = "chaturl.enable.tip",
  })
  toggle.fgId = "chaturl-enable"
  view.stack:Add(toggle, { height = 24, gap = 6 })
end

ns.SettingsPage.Add(S.Add, "social", "chaturl.main")
