-- Forever Chat, the button on the screen (game access): one small button with the logo of the messenger that
-- opens or closes the window and shows the unread count as a badge ("99+" from 100). It is off by default
-- (options.screenButton). In the edit mode ("Edit position" on the settings page) the player drags it and pulls
-- the corner grip to change its size (24 to 96 pixels); place and size stay in frames.chatButton of the main
-- add-on and never leave the screen. The button is not protected, so it works in combat; the window itself is
-- not built in combat (Window.Open says so). Nothing is sent.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme = FG.W, FG.L, FG.Theme
local IL = chat.IconLogic

local Button = {}
chat.Button = Button

Button.NAME = "FGChatScreenButton"
-- Offset of the first place from the middle of the screen, before the player moved the button.
Button.DEFAULT_X, Button.DEFAULT_Y = 0, -220

local frame
local editing = false
local grip = {}

local function frameDb()
  local frames = FG.db.frames
  if type(frames.chatButton) ~= "table" then
    frames.chatButton = {}
  end
  return frames.chatButton
end

local function running()
  return chat.Ingest ~= nil and chat.Ingest.IsRunning() and FG.SubAddons.State("chat") == "active"
end

local function enabled()
  return chat.Settings ~= nil and chat.Settings.Value("screenButton") == true
end

-- Place and size ----------------------------------------------------------------------------------------------

local function place()
  local db = frameDb()
  local size = IL.ClampSize(db.size)
  local x, y = IL.ClampPosition(db.x, db.y, size, UIParent:GetWidth(), UIParent:GetHeight())
  frame:SetSize(size, size)
  frame:ClearAllPoints()
  if x then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", Button.DEFAULT_X, Button.DEFAULT_Y)
  end
end

local function save()
  local db = frameDb()
  local size = IL.ClampSize(frame:GetWidth())
  local left, top = frame:GetLeft(), frame:GetTop()
  db.size = size
  if left and top then
    db.x, db.y = IL.ClampPosition(left, top, size, UIParent:GetWidth(), UIParent:GetHeight())
  end
end

-- The look follows the size: the logo, the badge and its text grow with the button.
local function layout()
  local size = frame:GetWidth()
  local inner = math.max(12, size - 8)
  frame.icon:SetSize(inner, inner)
  frame.icon:SetTexture(FG.BadgeAssets.Path(inner))
  local badge = math.max(14, math.floor(size * 0.42))
  frame.badge:SetHeight(badge)
  Theme.shrinkFont(frame.badge.text, math.max(8, math.floor(badge * 0.6)))
end

-- Badge -------------------------------------------------------------------------------------------------------

function Button.Refresh()
  if not frame then
    return
  end
  local total = chat.Unread.Total(chat.convs) + chat.TeamsView.OpenInvites()
  local text = IL.BadgeText(total)
  frame.badge:SetShown(text ~= "")
  frame.badge.text:SetText(text)
  local width = math.max(frame.badge:GetHeight(), (frame.badge.text:GetStringWidth() or 0) + 8)
  frame.badge:SetWidth(width)
end

-- Shows or hides the button by the switch, the state of the messenger and the edit mode.
function Button.Apply()
  if not frame then
    if not IL.Visible(enabled(), running(), editing) then
      return
    end
    Button.Create()
  end
  frame:SetShown(IL.Visible(enabled(), running(), editing))
  Button.Refresh()
end

-- Edit mode -------------------------------------------------------------------------------------------------

local function stopSizing()
  grip.active = nil
  grip.frame:SetScript("OnUpdate", nil)
  save()
end

local function startSizing()
  local scale = frame:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  grip.active = { x = cx / scale, y = cy / scale, size = frame:GetWidth() }
  grip.frame:SetScript("OnUpdate", function()
    local start = grip.active
    if not start then
      return
    end
    local nx, ny = GetCursorPosition()
    local size = IL.ResizeBy(start.size, nx / scale - start.x, ny / scale - start.y)
    if size ~= frame:GetWidth() then
      frame:SetSize(size, size)
      layout()
      Button.Refresh()
    end
  end)
end

local function buildEdit()
  local edit = CreateFrame("Frame", nil, frame)
  edit:SetAllPoints()
  edit:SetFrameLevel(frame:GetFrameLevel() + 5)
  W.Border(edit, "accent", 1, 2)
  grip.frame = CreateFrame("Frame", nil, edit)
  grip.frame:SetSize(14, 14)
  grip.frame:SetPoint("BOTTOMRIGHT", 0, 0)
  grip.frame:EnableMouse(true)
  local tex = grip.frame:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip.frame:SetScript("OnMouseDown", FG.Wrap("chat-button-size", startSizing))
  grip.frame:SetScript("OnMouseUp", FG.Wrap("chat-button-size", stopSizing))
  grip.frame:SetScript("OnEnter", function(self)
    FG.ShowTooltip(self, L["chat.btn.grip"])
  end)
  grip.frame:SetScript("OnLeave", FG.HideTooltip)
  local done = W.Button(edit, {
    key = "chat.btn.done",
    width = 90,
    height = 22,
    tooltip = "chat.btn.done",
    tooltipText = "chat.btn.done.tip",
    onClick = function()
      Button.Edit(false)
    end,
  })
  done:SetPoint("TOP", frame, "BOTTOM", 0, -4)
  edit.done = done
  edit:Hide()
  -- Esc ends the mode like the button does.
  FG.WindowShell.RegisterEsc(edit)
  edit:SetScript("OnHide", function()
    if editing then
      Button.Edit(false)
    end
  end)
  return edit
end

function Button.IsEditing()
  return editing
end

-- Turns the edit mode on or off. The button shows while it is on, whatever the switch says.
function Button.Edit(on)
  on = on == true
  if on and not running() then
    return false
  end
  if on == editing then
    return true
  end
  editing = on
  Button.Apply()
  if frame then
    if on then
      frame.edit:Show()
    else
      frame.edit:Hide()
      save()
    end
  end
  return true
end

-- Puts the button back to the first place and the default size.
function Button.Reset()
  local db = frameDb()
  db.x, db.y, db.size = nil, nil, nil
  if frame then
    place()
    layout()
    Button.Refresh()
  end
end

-- Frame -----------------------------------------------------------------------------------------------------

local function tooltip(self)
  local counts, total = IL.Counts(chat.convs)
  local lines = { L["chat.btn.tip"] }
  local invites = chat.TeamsView.OpenInvites()
  if invites > 0 then
    lines[#lines + 1] = chat.TeamsView.InviteLine(invites)
  end
  if total > 0 then
    lines[#lines + 1] = string.format(L["chat.icon.unread"], total)
    for _, tab in ipairs(chat.Conversations.TAB_ORDER) do
      if counts[tab] > 0 then
        lines[#lines + 1] = string.format("%s: %d", L["chat.tab." .. tab], counts[tab])
      end
    end
  end
  FG.ShowTooltip(self, L["chat.win.title"], nil, { lines = lines, anchor = "ANCHOR_LEFT" })
end

function Button.Create()
  if frame then
    return frame
  end
  frame = CreateFrame("Button", Button.NAME, UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForClicks("LeftButtonUp")
  frame:RegisterForDrag("LeftButton")
  W.Fill(frame, "surface", 0.95)
  W.Border(frame, "accentDim", 1)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("CENTER")
  frame.badge = CreateFrame("Frame", nil, frame)
  frame.badge:SetFrameLevel(frame:GetFrameLevel() + 3)
  frame.badge:SetPoint("TOPRIGHT", 6, 6)
  W.Fill(frame.badge, "accent", 1)
  frame.badge.text = W.Text(frame.badge, { role = "ui", color = "bg" })
  frame.badge.text:SetPoint("CENTER")
  frame.badge:Hide()
  frame:SetScript(
    "OnClick",
    FG.Wrap("chat-button", function()
      if not editing then
        chat.Toggle()
      end
    end)
  )
  frame:SetScript("OnDragStart", function(self)
    if editing then
      self:StartMoving()
    end
  end)
  frame:SetScript(
    "OnDragStop",
    FG.Wrap("chat-button-move", function(self)
      self:StopMovingOrSizing()
      save()
      place()
    end)
  )
  frame:SetScript("OnEnter", function(self)
    if not editing then
      tooltip(self)
    end
  end)
  frame:SetScript("OnLeave", FG.HideTooltip)
  frame.edit = buildEdit()
  place()
  layout()
  frame:Hide()
  return frame
end

function Button.Frame()
  return frame
end

FG.On("FG_CHAT_UPDATE", function()
  Button.Refresh()
end)
-- Open invitations count in the badge.
FG.On("FG_CHAT_TEAMS", function()
  Button.Refresh()
end)
FG.On("FG_CHAT_SETTING", function(_, id)
  if id == "screenButton" then
    Button.Apply()
  end
end)
FG.On("FG_UI_REFRESHED", function()
  if frame then
    layout()
    Button.Refresh()
  end
end)
-- The screen changed (resolution, UI scale): the button comes back inside.
FG.On("DISPLAY_SIZE_CHANGED", function()
  if frame then
    place()
  end
end)
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id == "chat" then
    if running() then
      Button.Apply()
    elseif frame then
      editing = false
      frame.edit:Hide()
      frame:Hide()
    end
  end
end)

-- The switch is in the store, which is read at ADDON_LOADED.
FG.On("FG_CHAT_STORE_READY", function()
  Button.Apply()
end)

-- The main add-on and the tests reach the parts through the handlers the window registered.
local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.Button, api.IconLogic = Button, IL
end
