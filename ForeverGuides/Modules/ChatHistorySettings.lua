-- Card "Chat history" on the tab "Guild and contacts" (ChatHistory.lua): the opt-in master switch, the
-- two limits that matter most and the button that deletes the history. The history stays on this PC.
-- The full set of limits lives in ChatHistoryLimits; every change goes through Store.set.
local _, ns = ...
local W, Store, Limits = ns.W, ns.Store, ns.ChatHistoryLimits

local S = {}
ns.ChatHistorySettings = S

local BUTTON_W = 200

ns.AddLocale("enUS", {
  ["chathistory.set.heading"] = "Chat window history",
  ["chathistory.set.hint"] = "Keeps the normal chat windows after /reload. Saved on this PC only, never sent.\nForever Chat saves its own chats with its option Save chats (on by default).",
  ["chathistory.set.enable"] = "Save window history",
  ["chathistory.set.enable.tip"] = "Off by default.\nNothing is saved while off.",
  ["chathistory.set.windowLines"] = "Lines per window",
  ["chathistory.set.windowDays"] = "Keep lines for",
  ["chathistory.set.days"] = "%d days",
  ["chathistory.set.clear"] = "Delete history",
  ["chathistory.set.clear.tip"] = "Deletes all saved lines after asking.\nContacts stay.",
})
ns.AddLocale("deDE", {
  ["chathistory.set.heading"] = "Chat-Fenster-Verlauf",
  ["chathistory.set.hint"] = "Hält die normalen Chatfenster nach /reload. Nur auf diesem PC gespeichert, nie gesendet.\nForever Chat speichert seine eigenen Chats mit der Option Chats speichern (Standard an).",
  ["chathistory.set.enable"] = "Fenster-Verlauf speichern",
  ["chathistory.set.enable.tip"] = "Standard aus.\nSolange aus, wird nichts gespeichert.",
  ["chathistory.set.windowLines"] = "Zeilen je Fenster",
  ["chathistory.set.windowDays"] = "Zeilen behalten für",
  ["chathistory.set.days"] = "%d Tage",
  ["chathistory.set.clear"] = "Verlauf löschen",
  ["chathistory.set.clear.tip"] = "Löscht alle gespeicherten Zeilen nach Rückfrage.\nKontakte bleiben.",
})

local live = setmetatable({}, { __mode = "k" })

local function refreshAll()
  for item in pairs(live) do
    if item.Refresh then
      item:Refresh()
    end
  end
end

local function chat()
  return ns.db and ns.db.settings and ns.db.settings.chat or {}
end

local function slider(view, key, id, fmt)
  local spec = Limits.NUMBERS[key]
  local s = W.Slider(view.content, {
    key = "chathistory.set." .. key,
    min = spec.min,
    max = spec.max,
    step = key == "windowLines" and 10 or 1,
    get = function()
      return chat()[key] or spec.default
    end,
    set = function(v)
      Store.set("settings.chat." .. key, math.max(spec.min, math.min(spec.max, math.floor(v + 0.5))))
    end,
    format = fmt,
  })
  s.fgId = id
  view.stack:Add(s, { height = 42, width = 320, gap = 6 })
  live[s] = true
end

function S.Add(view)
  ns.AddHeading(view, "chathistory.set.heading")
  ns.AddParagraph(view, "chathistory.set.hint", { role = "micro", color = "textMuted", gap = 6 })
  local toggle = W.Toggle(view.content, {
    key = "chathistory.set.enable",
    get = function()
      return chat().enabled == true
    end,
    set = function(v)
      Store.set("settings.chat.enabled", v == true)
    end,
    tooltip = "chathistory.set.enable",
    tooltipText = "chathistory.set.enable.tip",
  })
  toggle.fgId = "chathistory-enable"
  view.stack:Add(toggle, { height = 24, gap = 6 })
  live[toggle] = true
  slider(view, "windowLines", "chathistory-window-lines")
  slider(view, "windowDays", "chathistory-window-days", function(v)
    return string.format(ns.L["chathistory.set.days"], v)
  end)
  local clear = W.Button(view.content, {
    key = "chathistory.set.clear",
    width = BUTTON_W,
    height = 26,
    tooltip = "chathistory.set.clear",
    tooltipText = "chathistory.set.clear.tip",
    onClick = function()
      ns.ChatHistory.ConfirmClear()
    end,
  })
  clear.fgId = "chathistory-clear"
  view.stack:Add(clear, { height = 26, width = BUTTON_W, gap = 6 })
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.chat%.") then
    refreshAll()
  end
end)

ns.SettingsPage.Add(S.Add, "social", "chathistory.main")
