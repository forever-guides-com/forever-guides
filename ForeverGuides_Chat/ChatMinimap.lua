-- Forever Chat, the second minimap icon (game access): shows the unread count as a badge ("99+" from 100)
-- while the messenger runs. Left click opens or closes the window, right click opens a small menu (mark
-- everything as read, chat settings), the tooltip lists the unread lines per kind. The player drags it along
-- the edge; the angle stays in frames.chatMinimap of the main add-on and starts away from the icon of the main
-- add-on. The round button itself is built by the main add-on (MinimapButton.NewButton). Switch:
-- options.minimapIcon, on by default, only visible while the messenger is active. Nothing is sent.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L = FG.W, FG.L
local IL = chat.IconLogic

local Icon = {}
chat.MinimapIcon = Icon

Icon.NAME = "ForeverGuidesChatMinimapButton"
local ROW_H, MENU_W = 26, 220

local button, menu, blocker

local function frameDb()
  local frames = FG.db.frames
  if type(frames.chatMinimap) ~= "table" then
    frames.chatMinimap = {}
  end
  return frames.chatMinimap
end

local function running()
  return chat.Ingest ~= nil and chat.Ingest.IsRunning() and FG.SubAddons.State("chat") == "active"
end

local function enabled()
  return chat.Settings ~= nil and chat.Settings.Value("minimapIcon") == true
end

-- Menu ------------------------------------------------------------------------------------------------------

function Icon.CloseMenu()
  if menu and menu:IsShown() then
    menu:Hide()
    blocker:Hide()
  end
end

local ACTIONS = {
  function()
    IL.MarkAllRead(chat.convs)
    FG.Emit("FG_CHAT_UPDATE", {}, chat.Unread.Total(chat.convs))
  end,
  function()
    if chat.Open() then
      chat.Window.ShowSettings(true)
    end
  end,
}
local ROW_KEYS = { "chat.icon.markRead", "chat.icon.settings" }

local function buildMenu()
  blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("TOOLTIP")
  blocker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  blocker:SetScript("OnClick", Icon.CloseMenu)
  blocker:Hide()
  menu = CreateFrame("Frame", "FGChatMinimapMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetFrameLevel(blocker:GetFrameLevel() + 5)
  menu:SetClampedToScreen(true)
  menu:SetSize(MENU_W, ROW_H * #ACTIONS + 8)
  W.Fill(menu, "surface", 1)
  W.Border(menu, "accentDim", 1)
  menu:Hide()
  FG.WindowShell.RegisterEsc(menu)
  menu:SetScript("OnHide", function()
    blocker:Hide()
  end)
  for i, key in ipairs(ROW_KEYS) do
    local row = CreateFrame("Button", nil, menu)
    row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
    row:SetHeight(ROW_H)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.text = W.Text(row, { key = key, role = "ui", color = "text" })
    row.text:SetPoint("LEFT", 8, 0)
    row:SetScript("OnEnter", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0.1)
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0)
    end)
    row:SetScript(
      "OnClick",
      FG.Wrap("chat-minimap-menu", function()
        Icon.CloseMenu()
        ACTIONS[i]()
      end)
    )
  end
end

function Icon.OpenMenu(anchor)
  if not menu then
    buildMenu()
  end
  if menu:IsShown() then
    Icon.CloseMenu()
    return
  end
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  blocker:Show()
  menu:Show()
end

-- Badge and tooltip ---------------------------------------------------------------------------------------------

function Icon.Refresh()
  if not button then
    return
  end
  local text = IL.BadgeText(chat.Unread.Total(chat.convs) + chat.TeamsView.OpenInvites())
  button.badge:SetShown(text ~= "")
  button.badge.text:SetText(text)
  button.badge:SetWidth(math.max(14, (button.badge.text:GetStringWidth() or 0) + 6))
end

local function tooltip(self)
  local counts, total = IL.Counts(chat.convs)
  local lines = { string.format(L["chat.icon.unread"], total) }
  for _, tab in ipairs(chat.Conversations.TAB_ORDER) do
    lines[#lines + 1] = string.format("%s: %d", L["chat.tab." .. tab], counts[tab])
  end
  local invites = chat.TeamsView.OpenInvites()
  if invites > 0 then
    lines[#lines + 1] = chat.TeamsView.InviteLine(invites)
  end
  lines[#lines + 1] = L["chat.icon.leftClick"]
  lines[#lines + 1] = L["chat.icon.rightClick"]
  FG.ShowTooltip(self, L["chat.win.title"], nil, { lines = lines, anchor = "ANCHOR_LEFT" })
end

local function create()
  local make = FG.MinimapButton and FG.MinimapButton.NewButton
  if type(make) ~= "function" then
    return nil
  end
  button = make({
    name = Icon.NAME,
    icon = FG.BadgeAssets.Path(32),
    getAngle = function()
      return IL.ClampAngle(frameDb().angle or IL.ANGLE_DEFAULT)
    end,
    setAngle = function(angle)
      frameDb().angle = angle
    end,
    onClick = function(_, mouse)
      if mouse == "RightButton" then
        Icon.OpenMenu(button)
      else
        Icon.CloseMenu()
        chat.Toggle()
      end
    end,
    onEnter = tooltip,
  })
  if not button then
    return nil
  end
  button.badge = CreateFrame("Frame", nil, button)
  button.badge:SetFrameLevel(button:GetFrameLevel() + 6)
  button.badge:SetHeight(14)
  button.badge:SetPoint("TOPRIGHT", 4, 2)
  W.Fill(button.badge, "accent", 1)
  button.badge.text = W.Text(button.badge, { role = "micro", color = "bg" })
  button.badge.text:SetPoint("CENTER")
  button.badge:Hide()
  return button
end

-- Shows or hides the icon by the switch and the state of the messenger.
function Icon.Apply()
  local visible = IL.Visible(enabled(), running(), false)
  if not button then
    if not visible then
      return
    end
    if not create() then
      return
    end
  end
  button:SetShown(visible)
  if not visible then
    Icon.CloseMenu()
  end
  Icon.Refresh()
end

function Icon.Frame()
  return button
end

-- The angle goes back to the default place.
function Icon.Reset()
  frameDb().angle = nil
  if button then
    button.Place()
  end
end

FG.On("FG_CHAT_UPDATE", function()
  Icon.Refresh()
end)
-- Open invitations count in the badge.
FG.On("FG_CHAT_TEAMS", function()
  Icon.Refresh()
end)
FG.On("FG_CHAT_SETTING", function(_, id)
  if id == "minimapIcon" then
    Icon.Apply()
  end
end)
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id == "chat" then
    Icon.Apply()
  end
end)
FG.On("FG_UI_REFRESHED", function()
  Icon.Refresh()
end)

-- The switch is in the store, which is read at ADDON_LOADED.
FG.On("FG_CHAT_STORE_READY", function()
  Icon.Apply()
end)

-- The main add-on and the tests reach the parts through the handlers the window registered.
local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.MinimapIcon = Icon
end
