-- Compact mode: small free-floating frame for the active route or the
-- trainer reminder. Scaffold only; content arrives with the route module.
local _, ns = ...
local W = ns.W

local Dock = {}
ns.Dock = Dock
local frame
local HEX, HEIGHT, HEIGHT_CHAT = 16, 120, 152

local function save()
  local point, _, rel, x, y = frame:GetPoint(1)
  local db = ns.db.frames.dock
  db.point, db.rel, db.x, db.y = point, rel, x, y
end

local function create()
  frame = CreateFrame("Frame", "ForeverGuidesDock", UIParent)
  frame:SetSize(260, HEIGHT)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    save()
  end)
  W.Fill(frame, "bg", 0.9)
  -- esc = false: the compact display stays on screen while the player works, like the other trackers.
  local shell = ns.WindowShell.Attach(frame, { title = "dock.title", titleHeight = 26, esc = false })
  local close = W.Action(shell.titleBar, { icon = "close", size = 18, tooltip = "common.close" })
  close:SetPoint("RIGHT", -4, 0)
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 10, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -4, 0)
  close:SetScript("OnClick", function()
    Dock.Toggle(false)
  end)
  frame.body = W.Text(frame, { key = "dock.empty", role = "ui", color = "textSecondary", wrap = true })
  frame.body:SetPoint("TOPLEFT", 10, -30)
  frame.body:SetPoint("RIGHT", -10, 0)
  local open = W.Action(frame, {
    label = "act.open",
    icon = "open",
    tooltip = "dock.open",
    variant = "ghost",
    width = 140,
    height = 20,
    opens = true,
    onClick = function()
      ns.Main.Show()
    end,
  })
  open:SetPoint("BOTTOMRIGHT", -6, 6)
  -- Entry of Forever Chat: built here once (never when the sub-addon switches on), shown by Dock.RefreshChat.
  local entry = CreateFrame("Button", nil, frame)
  frame.chat = entry
  entry:SetHeight(26)
  entry:SetPoint("BOTTOMLEFT", 10, 34)
  entry:SetPoint("BOTTOMRIGHT", -10, 34)
  W.Fill(entry, "surface2", 0.9)
  W.Border(entry, "white", 0.25)
  entry.logo = entry:CreateTexture(nil, "ARTWORK")
  entry.logo:SetSize(HEX, HEX)
  entry.logo:SetPoint("LEFT", 8, 0)
  entry.hex = entry:CreateTexture(nil, "ARTWORK")
  entry.hex:SetSize(HEX, HEX)
  entry.hex:SetPoint("RIGHT", -8, 0)
  entry.count = W.Text(entry, { role = "micro", color = "text", justify = "RIGHT" })
  entry.count:SetPoint("RIGHT", entry.hex, "LEFT", -4, 0)
  entry.label = W.Text(entry, { key = "chatlaunch.dock.title", role = "ui", color = "text" })
  entry.label:SetPoint("LEFT", entry.logo, "RIGHT", 6, 0)
  entry.label:SetPoint("RIGHT", entry.count, "LEFT", -6, 0)
  entry.label:SetWordWrap(false)
  ns.Bind(entry, function()
    entry.logo:SetTexture(ns.BadgeAssets.Path(HEX))
    entry.hex:SetTexture(ns.BadgeAssets.Path(HEX))
  end)
  entry.fgNameKey = "chatlaunch.dock.title"
  entry:SetScript(
    "OnClick",
    ns.Wrap("dock-chat", function()
      ns.ChatLauncher.Toggle()
    end)
  )
  entry:SetScript("OnEnter", function(self)
    local unread = ns.ChatLauncher.Unread()
    ns.ShowTooltip(
      self,
      ns.L["chatlaunch.dock.title"],
      unread > 0 and string.format(ns.L["chatlaunch.dock.unread"], unread) or ns.L["chatlaunch.dock.tip"]
    )
  end)
  entry:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(entry, function(self)
    self:Click()
  end)
  entry:Hide()
  local db = ns.db.frames.dock
  frame:SetPoint(db.point or "CENTER", UIParent, db.rel or "CENTER", db.x or 0, db.y or -220)
  frame:Hide()
end

-- Shows the entry of Forever Chat with the unread badge while the sub-addon runs, hides it otherwise. Only
-- changes frames that exist, nothing is built here (safe in combat).
function Dock.RefreshChat()
  local entry = frame and frame.chat
  if not entry then
    return
  end
  local active = ns.ChatLauncher.Active()
  entry:SetShown(active)
  frame:SetHeight(active and HEIGHT_CHAT or HEIGHT)
  if active then
    local label = ns.ChatLauncher.UnreadLabel()
    entry.count:SetText(label)
    entry.count:SetShown(label ~= "")
    entry.hex:SetShown(label ~= "")
  end
end

function Dock.Toggle(show)
  if not frame then
    create()
  end
  if show == nil then
    show = not frame:IsShown()
  end
  frame:SetShown(show)
  frame:SetScale(ns.Theme.windowScale())
  ns.db.frames.dock.shown = show
  Dock.RefreshChat()
end

for _, event in ipairs({ "FG_CHAT_UPDATE", "FG_CHAT_READY", "FG_SUBADDON_CHANGED", "FG_UI_REFRESHED" }) do
  ns.On(event, function()
    Dock.RefreshChat()
  end)
end

function Dock.Restore()
  if ns.db.frames.dock.shown then
    Dock.Toggle(true)
  end
end
