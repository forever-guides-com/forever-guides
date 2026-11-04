-- Forever Chat, the end of the settings group "History": what is saved, where, and the way to delete it
-- (ChatArchive.Clear after a question). The switches of the group come from the settings registry.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W = FG.W
local L = FG.L

local UI = {}
chat.ArchiveUI = UI

-- The choices of "which chats": all, then the tabs that hold saved chats.
UI.SCOPES = { "all", "whisper", "group", "raid", "guild", "channel" }

local scope = "all"

local function choices()
  local out = {}
  for _, id in ipairs(UI.SCOPES) do
    out[#out + 1] = { value = id, key = id == "all" and "chat.archive.scope.all" or ("chat.tab." .. id) }
  end
  return out
end

function UI.Confirm(id)
  FG.Dialogs.Confirm("chat.archive.clear.title", "chat.archive.clear.text", function()
    local removed = chat.Archive.Clear(id)
    FG.Notify(string.format(L["chat.archive.cleared"], removed), "success")
  end, nil, { yesKey = "chat.archive.clear.yes" })
end

function UI.BuildFooter(view)
  local notes = {
    "chat.archive.info1",
    "chat.archive.info2",
    "chat.archive.info3",
    "chat.archive.info4",
    "chat.archive.info5",
    "chat.archive.info6",
  }
  for _, key in ipairs(notes) do
    FG.AddParagraph(view, key, { role = "micro", color = "textMuted", gap = 2 })
  end
  local drop = W.Dropdown(view.content, {
    key = "chat.archive.scope",
    width = 240,
    options = choices(),
    get = function()
      return scope
    end,
    set = function(value)
      scope = value
    end,
  })
  drop.fgId = "chat-archive-scope"
  view.stack:Add(drop, { height = 46, width = 240, gap = 2 })
  local button = W.Button(view.content, {
    key = "chat.archive.clear",
    width = 220,
    height = 26,
    tooltip = "chat.archive.clear",
    tooltipText = "chat.archive.clear.tip",
    onClick = function()
      UI.Confirm(scope)
    end,
  })
  button.fgId = "chat-archive-clear"
  view.stack:Add(button, { height = 26, width = 220, gap = 6 })
end

if chat.Settings and chat.Settings.AddFooter then
  chat.Settings.AddFooter("history", UI.BuildFooter)
end
