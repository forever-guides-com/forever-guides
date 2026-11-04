-- Forever Chat, the ways to open the window on the settings page (game access): the switches of the screen
-- button and the minimap icon, the buttons to move and reset them, the card "Open by macro" with the macro
-- text to copy, and the rules of the automatic opening in one short paragraph. The registry entries of the
-- switches that open the window by themselves are added by ChatAutoOpen.lua. Texts: LocaleOpen.lua.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W = FG.W

local Launch = {}
chat.Launch = Launch

Launch.GROUP = "launch"
-- The text of the card: the button of the main add-on that toggles the window, usable from any macro.
Launch.MACRO = "/click FGChatToggleButton"

Launch.OPTIONS = {
  { id = "screenButton", default = false },
  { id = "minimapIcon", default = true },
}

local function apply(id)
  return function()
    if id == "screenButton" and chat.Button then
      chat.Button.Apply()
    elseif id == "minimapIcon" and chat.MinimapIcon then
      chat.MinimapIcon.Apply()
    end
  end
end

-- Gives the switches to the settings registry. Returns the number registered.
function Launch.RegisterOptions()
  local settings = chat.Settings
  if type(settings) ~= "table" or type(settings.AddOption) ~= "function" then
    return 0
  end
  local count = 0
  for _, def in ipairs(Launch.OPTIONS) do
    local ok = pcall(settings.AddOption, {
      id = def.id,
      group = Launch.GROUP,
      group_label = "chat.launch.group",
      type = "toggle",
      default = def.default,
      label = "chat.launch." .. def.id,
      hint = "chat.launch." .. def.id .. ".hint",
      apply = apply(def.id),
    })
    if ok then
      count = count + 1
    end
  end
  return count
end

local function button(view, key, id, tip, onClick)
  local b = W.Button(view.content, {
    key = key,
    width = 220,
    height = 26,
    tooltip = key,
    tooltipText = tip,
    onClick = onClick,
  })
  b.fgId = id
  view.stack:Add(b, { height = 26, width = 220, gap = 6 })
  return b
end

-- The field with the macro: the text is selected on a click, typing changes nothing.
local function macroField(view)
  local box = W.EditBox(view.content, { height = 26 })
  box.fgId = "chat-launch-macro"
  local edit = box.edit
  edit:SetText(Launch.MACRO)
  edit:SetCursorPosition(0)
  edit:HookScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  edit:HookScript("OnMouseUp", function(self)
    self:HighlightText()
  end)
  edit:HookScript("OnTextChanged", function(self, user)
    if user and self:GetText() ~= Launch.MACRO then
      self:SetText(Launch.MACRO)
      self:HighlightText()
    end
  end)
  view.stack:Add(box, { height = 26, gap = 4 })
  return box
end

-- After the last switch of the group "launch": move and reset the button, then the macro card.
function Launch.BuildFooter(view)
  local Button, Icon = chat.Button, chat.MinimapIcon
  button(view, "chat.launch.edit", "chat-launch-edit", "chat.launch.edit.tip", function()
    if Button then
      Button.Edit(not Button.IsEditing())
    end
  end)
  button(view, "chat.launch.reset", "chat-launch-reset", "chat.launch.reset.tip", function()
    if Button then
      Button.Reset()
    end
    if Icon then
      Icon.Reset()
    end
  end)
  FG.AddHeading(view, "chat.launch.macro", { role = "ui", gap = 4 })
  macroField(view)
  FG.AddParagraph(view, "chat.launch.macro.hint", { role = "micro", color = "textMuted", gap = 8 })
end

if chat.Settings and chat.Settings.AddFooter then
  chat.Settings.AddFooter(Launch.GROUP, Launch.BuildFooter)
  chat.Settings.AddFooter(chat.OpenLogic.GROUP, function(view)
    for _, key in ipairs({ "chat.open.rules1", "chat.open.rules2", "chat.open.rules3" }) do
      FG.AddParagraph(view, key, { role = "micro", color = "textMuted", gap = 2 })
    end
  end)
end
Launch.RegisterOptions()
-- The icons wait for their switches: the registry knows the defaults only now.
if chat.Button then
  chat.Button.Apply()
end
if chat.MinimapIcon then
  chat.MinimapIcon.Apply()
end

-- The main add-on and the tests reach the parts through the handlers the window registered.
local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.Launch = Launch
end
