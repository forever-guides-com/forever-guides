-- Settings card "Experience bar" (Modules/XpBarWindow.lua, XpTracker.lua) on the General tab: show and pin
-- the window, choose the layout, open the editor, the chat message at a level up, auto pause, new
-- session at login, hiding in combat and at the maximum level, reset of the session. Every change goes
-- through Store.set, the window follows through FG_SETTING_CHANGED.
local _, ns = ...
local W, Store = ns.W, ns.Store

local S = {}
ns.XpBarSettings = S

ns.AddLocale("enUS", {
  ["xpbar.set.heading"] = "Experience bar",
  ["xpbar.set.hint"] = "A window with your experience as a bar and texts you place yourself: time per level, XP per hour, rested and quest XP. Click the bar for a menu.",
  ["xpbar.set.show"] = "Show bar",
  ["xpbar.set.showTip"] = "Opens or closes the window, same as the key binding and /fg xp.",
  ["xpbar.set.pin"] = "Pin bar",
  ["xpbar.set.pinTip"] = "Pinned: the bar cannot be moved and shows no scale grip and no pin button. Unpinned: drag the bar to move it, the grip in the corner scales it.",
  ["xpbar.set.layout"] = "Layout",
  ["xpbar.set.edit"] = "Edit layout",
  ["xpbar.set.new"] = "New",
  ["xpbar.set.dup"] = "Copy",
  ["xpbar.set.rename"] = "Rename",
  ["xpbar.set.delete"] = "Delete",
  ["xpbar.set.newTitle"] = "New layout",
  ["xpbar.set.renameTitle"] = "Rename layout",
  ["xpbar.set.name"] = "Name",
  ["xpbar.set.from"] = "Start from",
  ["xpbar.set.create"] = "Create",
  ["xpbar.set.deleteTitle"] = "Delete layout",
  ["xpbar.set.deleteText"] = "The chosen layout is deleted for good. Export it in the editor first if you want to keep it.",
  ["xpbar.set.chat"] = "Chat at level up",
  ["xpbar.set.chatTip"] = "Chat message at a level up: names the time the finished level took and the total played time.",
  ["xpbar.set.chatSelf"] = "In my chat window",
  ["xpbar.set.chatSelfTip"] = "Shows the level-up line in your own chat window.",
  ["xpbar.set.chatGroup"] = "Group (if in one)",
  ["xpbar.set.chatGroupTip"] = "Sends the line to your party, raid or instance group. Skipped when you are not in a group.",
  ["xpbar.set.chatGuild"] = "Guild",
  ["xpbar.set.chatGuildTip"] = "Sends the line to the guild chat. Skipped when you are not in a guild.",
  ["xpbar.set.chatSay"] = "Say",
  ["xpbar.set.chatSayTip"] = "Sends the line to Say. The game blocks addons from writing to Say outside instances without a key press, so it usually fails there: you then get one hint and the line in your own window.",
  ["xpbar.set.autoPause"] = "Auto pause",
  ["xpbar.set.autoPauseTip"] = "Pauses the session while you are marked away: session time and XP per hour stand still.",
  ["xpbar.set.newSession"] = "New after break",
  ["xpbar.set.newSessionTip"] = "New session at login after a long break: starts a new session when the last one ended more than 30 minutes ago.",
  ["xpbar.set.combat"] = "Hide in combat",
  ["xpbar.set.maxLevel"] = "Show at max level",
  ["xpbar.set.maxLevelTip"] = "Keeps the bar on screen at the maximum level, where the experience no longer counts.",
  ["xpbar.set.reset"] = "Reset session",
})
ns.AddLocale("deDE", {
  ["xpbar.set.heading"] = "Erfahrungsleiste",
  ["xpbar.set.hint"] = "Ein Fenster mit deiner Erfahrung als Leiste und Texten, die du selbst platzierst: Zeit pro Stufe, EP pro Stunde, Ausgeruht und Quest-EP. Ein Klick auf die Leiste öffnet ein Menü.",
  ["xpbar.set.show"] = "Leiste anzeigen",
  ["xpbar.set.showTip"] = "Öffnet oder schließt das Fenster, wie die Tastenbelegung und /fg erfahrung.",
  ["xpbar.set.pin"] = "Leiste anheften",
  ["xpbar.set.pinTip"] = "Angeheftet: Die Leiste lässt sich nicht verschieben und zeigt weder Skalierungsgriff noch Anheften-Knopf. Gelöst: Zieh die Leiste zum Verschieben, der Griff in der Ecke skaliert sie.",
  ["xpbar.set.layout"] = "Layout",
  ["xpbar.set.edit"] = "Layout bearbeiten",
  ["xpbar.set.new"] = "Neu",
  ["xpbar.set.dup"] = "Kopieren",
  ["xpbar.set.rename"] = "Umbenennen",
  ["xpbar.set.delete"] = "Löschen",
  ["xpbar.set.newTitle"] = "Neues Layout",
  ["xpbar.set.renameTitle"] = "Layout umbenennen",
  ["xpbar.set.name"] = "Name",
  ["xpbar.set.from"] = "Ausgehend von",
  ["xpbar.set.create"] = "Anlegen",
  ["xpbar.set.deleteTitle"] = "Layout löschen",
  ["xpbar.set.deleteText"] = "Das gewählte Layout wird endgültig gelöscht. Exportiere es vorher im Editor, wenn du es behalten willst.",
  ["xpbar.set.chat"] = "Chat bei Aufstieg",
  ["xpbar.set.chatTip"] = "Chat-Meldung beim Stufenaufstieg: nennt die Zeit der abgeschlossenen Stufe und die gesamte Spielzeit.",
  ["xpbar.set.chatSelf"] = "Im eigenen Chat",
  ["xpbar.set.chatSelfTip"] = "Zeigt die Aufstiegszeile in deinem eigenen Chatfenster.",
  ["xpbar.set.chatGroup"] = "Gruppe (falls da)",
  ["xpbar.set.chatGroupTip"] = "Sendet die Zeile an Gruppe, Schlachtzug oder Instanzgruppe. Entfällt, wenn du in keiner Gruppe bist.",
  ["xpbar.set.chatGuild"] = "Gilde",
  ["xpbar.set.chatGuildTip"] = "Sendet die Zeile in den Gildenchat. Entfällt, wenn du in keiner Gilde bist.",
  ["xpbar.set.chatSay"] = "Sagen",
  ["xpbar.set.chatSayTip"] = "Sendet die Zeile per Sagen. Das Spiel sperrt Addons außerhalb von Instanzen ohne Tastendruck für Sagen, daher scheitert es dort meist: du bekommst dann einen Hinweis und die Zeile im eigenen Fenster.",
  ["xpbar.set.autoPause"] = "Auto-Pause",
  ["xpbar.set.autoPauseTip"] = "Pausiert die Sitzung, solange du als abwesend markiert bist: Sitzungszeit und EP pro Stunde stehen still.",
  ["xpbar.set.newSession"] = "Neu nach Pause",
  ["xpbar.set.newSessionTip"] = "Neue Sitzung beim Anmelden nach langer Pause: startet eine neue Sitzung, wenn die letzte mehr als 30 Minuten zurückliegt.",
  ["xpbar.set.combat"] = "Im Kampf ausblenden",
  ["xpbar.set.maxLevel"] = "Bei Maximalstufe",
  ["xpbar.set.maxLevelTip"] = "Lässt die Leiste auf der Maximalstufe sichtbar, wo die Erfahrung nicht mehr zählt.",
  ["xpbar.set.reset"] = "Sitzung zurücksetzen",
})

local function toggle(view, labelKey, tipKey, get, set)
  view.stack:Add(
    W.Toggle(view.content, {
      key = labelKey,
      get = get,
      set = set,
      tooltip = labelKey,
      tooltipText = tipKey,
    }),
    { height = 24, gap = 6 }
  )
end

-- A toggle on one flag of settings.xpBar; the window repairs the value through Config().
local function flag(view, key, labelKey, tipKey)
  toggle(view, labelKey, tipKey, function()
    return ns.XpBar.Config()[key] == true
  end, function(v)
    Store.set("settings.xpBar." .. key, v == true)
  end)
end

-- The four targets of the level-up line, indented below the master toggle. They are shown dimmed and
-- do not react while the master toggle is off.
local CHAT_BOXES = {
  { "self", "xpbar.set.chatSelf", "xpbar.set.chatSelfTip" },
  { "group", "xpbar.set.chatGroup", "xpbar.set.chatGroupTip" },
  { "guild", "xpbar.set.chatGuild", "xpbar.set.chatGuildTip" },
  { "say", "xpbar.set.chatSay", "xpbar.set.chatSayTip" },
}

local function chatEnabled()
  return ns.XpBar.Config().chatLevelUp == true
end

-- The card and the page of the bar build the same controls, so every built set is kept and repainted.
S.chatBoxes, S.layoutChoices = {}, {}

local function paintChatBoxes()
  local on = chatEnabled()
  for _, box in ipairs(S.chatBoxes) do
    box:SetEnabled(on)
    box:SetAlpha(on and 1 or 0.5)
    box.Refresh()
  end
end

local function addChatTargets(view)
  for _, def in ipairs(CHAT_BOXES) do
    local key = def[1]
    local box = W.Checkbox(view.content, {
      key = def[2],
      tooltip = def[2],
      tooltipText = def[3],
      get = function()
        return ns.XpTracker.ChatChannels()[key]
      end,
      set = function(v)
        if chatEnabled() then
          Store.set("settings.xpBar.chat." .. key, v == true)
        end
      end,
    })
    view.stack:Add(box, { height = 22, gap = 4, indent = 24 })
    S.chatBoxes[#S.chatBoxes + 1] = box
  end
  paintChatBoxes()
end

-- Builds the controls into a page view. opts.page: the page of the bar has its own title and intro, so
-- the heading and the hint of the card are left out.
function S.Add(view, opts)
  local XW = ns.XpBar
  if not (opts and opts.page) then
    ns.AddHeading(view, "xpbar.set.heading")
    ns.AddParagraph(view, "xpbar.set.hint", { role = "micro", color = "textMuted" })
  end
  toggle(view, "xpbar.set.show", "xpbar.set.showTip", XW.IsWanted, XW.SetWanted)
  toggle(view, "xpbar.set.pin", "xpbar.set.pinTip", function()
    return XW.Config().pinned
  end, XW.SetPinned)

  -- The list is refilled in place on every read: layouts come and go while the card is open.
  local options = {}
  local function fillOptions()
    for i = #options, 1, -1 do
      options[i] = nil
    end
    for _, entry in ipairs(XW.Layouts()) do
      options[#options + 1] = { value = entry.id, text = entry.name }
    end
  end
  local layout = W.Dropdown(view.content, {
    key = "xpbar.set.layout",
    width = 240,
    options = options,
    get = function()
      fillOptions()
      return XW.Config().layoutId
    end,
    set = XW.SetLayout,
  })
  view.stack:Add(layout, { height = 46, width = 240 })
  S.layoutChoices[#S.layoutChoices + 1] = layout
  view.stack:Add(
    ns.LayoutSet.BuildButtons(view.content, XW.LayoutSet),
    { height = ns.LayoutSet.BUTTONS_H, width = ns.LayoutSet.BUTTONS_W, gap = 8 }
  )
  view.stack:Add(
    W.Button(view.content, {
      key = "xpbar.set.edit",
      width = 170,
      onClick = XW.Edit,
    }),
    { height = 26, width = 170, gap = 8 }
  )

  flag(view, "chatLevelUp", "xpbar.set.chat", "xpbar.set.chatTip")
  addChatTargets(view)
  flag(view, "autoPause", "xpbar.set.autoPause", "xpbar.set.autoPauseTip")
  flag(view, "sessionResetOnLogin", "xpbar.set.newSession", "xpbar.set.newSessionTip")
  flag(view, "hideInCombat", "xpbar.set.combat")
  flag(view, "showAtMax", "xpbar.set.maxLevel", "xpbar.set.maxLevelTip")
  view.stack:Add(
    W.Button(view.content, {
      key = "xpbar.set.reset",
      width = 240,
      onClick = ns.XpTracker.ResetSession,
    }),
    { height = 26, width = 240 }
  )
end

-- The layout list follows every change of the layouts, whoever made it.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.xpBar.chatLevelUp" then
    paintChatBoxes()
  end
  if type(path) == "string" and path:find("^settings%.xpBar%.layout") then
    for _, choice in ipairs(S.layoutChoices) do
      choice.Refresh()
    end
  end
end)

ns.SettingsPage.Add(S.Add, "general")
