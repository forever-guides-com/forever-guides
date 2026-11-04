-- Texts of the add-on extras of the messenger (ChatPeer.lua): the options, the notices and the signs on the lines.
-- Style: docs/TEXT-STIL.md (label up to 25 characters, hint up to 60).
local _, chat = ...
if not chat.hook then
  return
end

chat.FG.AddLocale("enUS", {
  ["chat.set.group.extras"] = "Addon extras",
  ["chat.set.extras.hint"] = "Add-on messages, never text. Off by default.",
  ["chat.set.extras.notice.receive"] = "Showing extras of others needs sharing.",
  ["chat.set.extras.notice.send"] = "Sending extras needs sharing.",
  ["chat.set.peerTypingShow"] = "Show typing",
  ["chat.set.peerTypingShow.hint"] = "Shows when a partner types.",
  ["chat.set.peerTypingSend"] = "Send typing",
  ["chat.set.peerTypingSend.hint"] = "Tells a partner that you type.",
  ["chat.set.peerSeenShow"] = "Show seen",
  ["chat.set.peerSeenShow.hint"] = "Shows that a partner read your line.",
  ["chat.set.peerSeenSend"] = "Send seen",
  ["chat.set.peerSeenSend.hint"] = "Tells a partner which line you read.",
  ["chat.set.peerReact"] = "Reactions",
  ["chat.set.peerReact.hint"] = "Show and send. Click a line or press Ctrl+R.",
  ["chat.peer.typing"] = "typing ..",
  ["chat.peer.seen"] = "Seen",
  ["chat.peer.react.tip"] = "React to this line",
})
chat.FG.AddLocale("deDE", {
  ["chat.set.group.extras"] = "Addon-Extras",
  ["chat.set.extras.hint"] = "Addon-Nachrichten, nie Text. Standard aus.",
  ["chat.set.extras.notice.receive"] = "Extras anderer anzeigen braucht Teilen.",
  ["chat.set.extras.notice.send"] = "Extras senden braucht Teilen.",
  ["chat.set.peerTypingShow"] = "Tippen anzeigen",
  ["chat.set.peerTypingShow.hint"] = "Zeigt, wenn ein Partner tippt.",
  ["chat.set.peerTypingSend"] = "Tippen senden",
  ["chat.set.peerTypingSend.hint"] = "Sagt einem Partner, dass du tippst.",
  ["chat.set.peerSeenShow"] = "Gesehen anzeigen",
  ["chat.set.peerSeenShow.hint"] = "Zeigt, dass ein Partner deine Zeile las.",
  ["chat.set.peerSeenSend"] = "Gesehen senden",
  ["chat.set.peerSeenSend.hint"] = "Sagt einem Partner, welche Zeile du last.",
  ["chat.set.peerReact"] = "Reaktionen",
  ["chat.set.peerReact.hint"] = "Anzeigen und senden. Zeile anklicken oder Strg+R.",
  ["chat.peer.typing"] = "tippt ..",
  ["chat.peer.seen"] = "Gesehen",
  ["chat.peer.react.tip"] = "Auf diese Zeile reagieren",
})
