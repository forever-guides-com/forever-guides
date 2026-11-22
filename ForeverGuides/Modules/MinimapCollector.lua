-- Minimap button collector (settings.minimapCollect, off by default): the round buttons of other add-ons move
-- into one flyout behind a single button of ours and go back to where they were when the switch goes off.
-- Only named, non-protected buttons of the minimap that look like add-on buttons are taken; frames of the
-- client are skipped (issecurevariable on the global name). Reparenting waits for a calm moment: a scan in
-- combat is dropped and repeated when the combat ends, a switch by the player in combat is refused.
local _, ns = ...
local L = ns.L

local MC = {}
ns.MinimapCollector = MC

ns.AddLocale("enUS", {
  ["settings.minimapCollect"] = "Collect minimap buttons",
  ["settings.minimapCollectHint"] = "Moves buttons of other add-ons into one flyout.",
  ["minimap.collect.tooltip"] = "Shows the collected minimap buttons.",
  ["minimap.collect.title"] = "Minimap buttons",
})
ns.AddLocale("deDE", {
  ["settings.minimapCollect"] = "Minimap-Knöpfe bündeln",
  ["settings.minimapCollectHint"] = "Verschiebt Knöpfe anderer Addons in ein Flyout.",
  ["minimap.collect.tooltip"] = "Zeigt die gebündelten Minimap-Knöpfe.",
  ["minimap.collect.title"] = "Minimap-Knöpfe",
})

local COLUMNS, CELL, PAD, MAX_SIZE = 5, 34, 6, 48
local SCAN_DELAY = 4

local flyout, toggle
-- Buttons held by the flyout, in order, and what each one needs to go back (parent, anchors, strata, level).
local held, saved = {}, {}
local scanPending, reverting = false, false

function MC.Enabled()
  return ns.db ~= nil and ns.db.settings.minimapCollect == true
end

local function isOwn(name)
  return name:find("^ForeverGuides") ~= nil or name:find("^ForeverChat") ~= nil or name:find("^LibDBIcon10_ForeverGuides") ~= nil
end

-- Is the frame a button of an add-on that belongs in the flyout?
function MC.Candidate(frame)
  if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
    return false
  end
  local name = frame:GetName()
  if type(name) ~= "string" or isOwn(name) then
    return false
  end
  local lib = name:find("^LibDBIcon10_") ~= nil
  if not (lib or name:find("MinimapButton", 1, true) or name:find("MinimapIcon", 1, true)) then
    return false
  end
  -- Globals created by the client are secure; those of add-ons are not.
  local secure = rawget(_G, "issecurevariable")
  if type(secure) == "function" and secure(name) then
    return false
  end
  if type(frame.IsProtected) == "function" and frame:IsProtected() then
    return false
  end
  local w, h = frame:GetWidth(), frame:GetHeight()
  return not (type(w) == "number" and type(h) == "number" and (w > MAX_SIZE or h > MAX_SIZE))
end

local function create()
  if flyout or not ns.MinimapButton or not ns.MinimapButton.NewButton then
    return flyout ~= nil
  end
  local W = ns.W
  flyout = CreateFrame("Frame", "ForeverGuidesCollectorFlyout", UIParent)
  flyout:SetFrameStrata("DIALOG")
  flyout:Hide()
  W.Fill(flyout, "surface2")
  W.Border(flyout, "white", 0.4)
  toggle = ns.MinimapButton.NewButton({
    name = "ForeverGuidesCollectorButton",
    opens = true,
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    getAngle = function()
      return ns.db.settings.minimapCollectAngle
    end,
    setAngle = function(angle)
      ns.db.settings.minimapCollectAngle = angle
    end,
    onClick = function()
      MC.Toggle()
    end,
    onEnter = function(self)
      W.Tooltip.Show(self, { title = L["minimap.collect.title"], text = L["minimap.collect.tooltip"], anchor = "ANCHOR_LEFT" })
    end,
  })
  if not toggle then
    flyout = nil
    return false
  end
  flyout:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -4)
  return true
end

local function layout()
  local shown = {}
  for _, btn in ipairs(held) do
    if btn:IsShown() then
      shown[#shown + 1] = btn
    end
  end
  local rows = math.max(1, math.ceil(#shown / COLUMNS))
  flyout:SetSize(PAD * 2 + math.min(math.max(#shown, 1), COLUMNS) * CELL, PAD * 2 + rows * CELL)
  for i, btn in ipairs(shown) do
    local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD + col * CELL + 1, -(PAD + row * CELL + 1))
  end
end

function MC.Toggle()
  if not flyout then
    return
  end
  if flyout:IsShown() then
    flyout:Hide()
    return
  end
  layout()
  flyout:Show()
end

local function take(btn)
  local points = {}
  for i = 1, tonumber((btn:GetNumPoints())) or 0 do
    points[i] = { btn:GetPoint(i) }
  end
  saved[btn] = {
    parent = btn:GetParent(),
    points = points,
    strata = btn:GetFrameStrata(),
    level = btn:GetFrameLevel(),
  }
  held[#held + 1] = btn
  btn:SetParent(flyout)
  btn:SetFrameStrata("DIALOG")
  btn:SetFrameLevel(flyout:GetFrameLevel() + 2)
  -- A drag would pull the button back onto the ring of the minimap.
  btn:RegisterForDrag()
end

local function release(btn)
  local s = saved[btn]
  saved[btn] = nil
  if not s then
    return
  end
  btn:SetParent(s.parent)
  btn:ClearAllPoints()
  for _, p in ipairs(s.points) do
    btn:SetPoint(p[1], p[2], p[3], p[4], p[5])
  end
  if s.strata then
    btn:SetFrameStrata(s.strata)
  end
  if s.level then
    btn:SetFrameLevel(s.level)
  end
  btn:RegisterForDrag("LeftButton")
  local name = btn:GetName() or ""
  local lib = rawget(_G, "LibStub") and LibStub.GetLibrary and LibStub:GetLibrary("LibDBIcon-1.0", true)
  local key = name:match("^LibDBIcon10_(.+)$")
  if lib and key then
    pcall(lib.Refresh, lib, key)
  end
end

-- Takes the buttons of the minimap that are not held yet. No-op outside the switch or in combat (repeated when it ends).
function MC.Scan()
  if not MC.Enabled() or not Minimap then
    return
  end
  if ns.InCombat() then
    scanPending = true
    return
  end
  scanPending = false
  if not create() then
    return
  end
  for _, child in ipairs({ Minimap:GetChildren() }) do
    if not saved[child] and MC.Candidate(child) and child:IsShown() then
      take(child)
    end
  end
  toggle:SetShown(#held > 0)
  if flyout:IsShown() then
    layout()
  end
end

-- Gives every held button back and hides ours.
function MC.Restore()
  for i = #held, 1, -1 do
    release(held[i])
    held[i] = nil
  end
  if flyout then
    flyout:Hide()
  end
  if toggle then
    toggle:Hide()
  end
end

function MC.Apply()
  if MC.Enabled() then
    MC.Scan()
  else
    scanPending = false
    MC.Restore()
  end
end

local function later(fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(SCAN_DELAY, fn)
  else
    fn()
  end
end

-- Add-ons make their buttons a moment after the login.
ns.On("PLAYER_ENTERING_WORLD", function()
  later(MC.Scan)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if scanPending then
    MC.Scan()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path ~= "settings.minimapCollect" or reverting then
    return
  end
  -- The player's switch is refused in combat and put back: nothing is queued.
  if ns.InCombat() then
    ns.CombatBlocked("minimap collector")
    reverting = true
    ns.Store.set(path, not value)
    reverting = false
    return
  end
  MC.Apply()
end)
