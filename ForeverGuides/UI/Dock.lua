-- Compact mode: small free-floating frame for the active route or the
-- trainer reminder. Scaffold only; content arrives with the route module.
local _, ns = ...
local W = ns.W

local Dock = {}
ns.Dock = Dock
local frame

local function save()
  local point, _, rel, x, y = frame:GetPoint(1)
  local db = ns.db.frames.dock
  db.point, db.rel, db.x, db.y = point, rel, x, y
end

local function create()
  frame = CreateFrame("Frame", "ForeverGuidesDock", UIParent)
  frame:SetSize(260, 120)
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
  local shell = ns.WindowShell.Attach(frame, { title = "dock.title", titleHeight = 26 })
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
    onClick = function()
      ns.Main.Show()
    end,
  })
  open:SetPoint("BOTTOMRIGHT", -6, 6)
  local db = ns.db.frames.dock
  frame:SetPoint(db.point or "CENTER", UIParent, db.rel or "CENTER", db.x or 0, db.y or -220)
  frame:Hide()
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
end

function Dock.Restore()
  if ns.db.frames.dock.shown then
    Dock.Toggle(true)
  end
end
