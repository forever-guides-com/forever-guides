-- The two faces of ns.SaveState (Modules/SaveState.lua): the "Save" button in the footer of the main window
-- and the small reminder bar. Both reload the interface from a click handler only (SaveState.Click). A
-- reload the game refuses ends in a notice with the /reload command to copy, never in silence.
local _, ns = ...
local W, Theme, L = ns.W, ns.Theme, ns.L

local SaveUI = {}
ns.SaveUI = SaveUI

local BUTTON_HEIGHT = 18
local DOT = 6
local HINT_WIDTH = 400
local HINT_PAD = 12
local HINT_BUTTON = 24
-- Seconds the reminder stays when nobody reacts.
local HINT_SECONDS = 60

local TIP_BY_REASON = {
  combat = "save.tipCombat",
  restricted = "save.tipRestricted",
  unsupported = "save.tipUnsupported",
}

-- Reload from inside a click scope. A refusal is shown, never swallowed.
local function reload()
  local ok, why = ns.SaveState.Reload()
  if ok or why == "noclick" then
    return ok
  end
  if why == "combat" then
    ns.Notify(L["save.combatNotice"], "warning")
  else
    ns.Dialogs.Copy("save.blockedTitle", "/reload", "save.blockedHint")
  end
  return false
end

-- The reload of both buttons: ask first when a group, an instance, a vendor window or a running scan is
-- at stake, otherwise reload at once. Call it inside a click scope; the confirm button is a click of its
-- own. afterReload runs after the reload call, also when the game refused it.
local function reloadConfirmed(afterReload)
  local S = ns.SaveState
  local function go()
    reload()
    if afterReload then
      afterReload()
    end
  end
  local why = S.CanReload() and S.ConfirmReason() or nil
  if why then
    ns.Dialogs.Confirm("save.confirmTitle", "save.confirm." .. why, S.Click(go))
  else
    go()
  end
end

local function onSaveClick()
  reloadConfirmed()
end

-- Footer button ------------------------------------------------------------------------------

local function showTip(b)
  local S = ns.SaveState
  local dirty = S.Dirty().since ~= nil
  local lines = { { text = S.StateText(), color = dirty and "warning" or "textSecondary" } }
  local can, why = S.CanReload()
  if not can and TIP_BY_REASON[why] then
    lines[#lines + 1] = { text = L[TIP_BY_REASON[why]], color = "textMuted" }
  end
  ns.ShowTooltip(b, L["save.tipTitle"], L["save.tip"], { lines = lines })
end

function SaveUI.Build(footer)
  local S = ns.SaveState
  local b = W.Action(footer, {
    label = "save.button",
    icon = "save",
    variant = "save",
    height = BUTTON_HEIGHT,
    onClick = S.Click(onSaveClick),
  })
  b.fgId = "footer-save"
  -- A dot in the left padding of the button on top of the warning fill of the unsaved state; the
  -- tooltip names the state in words as well.
  b.dot = b:CreateTexture(nil, "OVERLAY")
  b.dot:SetSize(DOT, DOT)
  b.dot:SetPoint("LEFT", b, "LEFT", 1, 0)
  ns.Bind(b.dot, function(t)
    t:SetColorTexture(Theme.color("bg"))
  end)
  b:HookScript("OnEnter", showTip)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus = showTip
  b.fgOnBlur = ns.HideTooltip

  -- The footer sizes the button when it lays out: with its caption (width follows font size and
  -- language) or as the bare icon when the controls next to it need the room. Returns the width.
  b.fgManaged = true
  function b.FitCaption(withCaption)
    local width
    if withCaption then
      width = b:Fit()
    else
      width = b:Fit(0)
    end
    b:SetWidth(width)
    return width
  end

  function b.Paint()
    local dirty = S.Dirty().since ~= nil
    b.dot:SetShown(dirty)
    b:SetEnabled(not (rawget(_G, "InCombatLockdown") and InCombatLockdown()))
    -- Last: the repaint of the variant sees the final enabled state.
    b:SetVariant(dirty and "saveDirty" or "save")
  end
  ns.Bind(b, b.Paint)
  ns.On("FG_SAVESTATE_CHANGED", b.Paint)
  ns.On("PLAYER_REGEN_DISABLED", b.Paint)
  ns.On("PLAYER_REGEN_ENABLED", b.Paint)
  return b
end

-- Reminder bar -------------------------------------------------------------------------------

local hint
local hintGeneration = 0

local function layoutHint(f)
  local width =
    math.max(HINT_WIDTH, HINT_PAD * 2 + f.later:GetWidth() + (f.now:IsShown() and f.now:GetWidth() + 8 or 0))
  f:SetWidth(width)
  f.text:SetWidth(width - HINT_PAD * 2)
  local textHeight = math.max(14, f.text:GetStringHeight() or 0)
  f:SetHeight(HINT_PAD + textHeight + 8 + HINT_BUTTON + HINT_PAD)
end

local function buildHint()
  local S = ns.SaveState
  local f = CreateFrame("Frame", "ForeverGuidesSaveHint", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetSize(HINT_WIDTH, 70)
  f:SetPoint("TOP", UIParent, "TOP", 0, -110)
  W.Fill(f, "surface", 0.97)
  W.Border(f, "accent2", 0.9)
  f.text = W.Text(f, { role = "ui", wrap = true })
  f.text:SetPoint("TOPLEFT", HINT_PAD, -HINT_PAD)
  f.later = W.Action(f, {
    key = "save.hintLater",
    variant = "secondary",
    height = HINT_BUTTON,
    onClick = function()
      S.Snooze()
      f:Hide()
    end,
  })
  f.later:SetPoint("BOTTOMRIGHT", -HINT_PAD, HINT_PAD)
  f.now = W.Action(f, {
    key = "save.hintNow",
    icon = "save",
    variant = "primary",
    height = HINT_BUTTON,
    onClick = S.Click(function()
      -- The reload first: nothing else runs between the click and the call. The bar goes after it and
      -- stays when the player cancels the question.
      reloadConfirmed(function()
        f:Hide()
      end)
    end),
  })
  f.now:SetPoint("RIGHT", f.later, "LEFT", -8, 0)
  f.later:SetWidth(f.later:FullWidth())
  f.now:SetWidth(f.now:FullWidth())
  f:SetScript("OnShow", function()
    f:SetScale(Theme.windowScale())
  end)
  f:Hide()
  return f
end

function SaveUI.HintFrame()
  return hint
end

-- Shows the reminder: with a reload button, or only the /reload hint when the game does not allow the
-- reload. Returns true when it shows.
function SaveUI.ShowHint()
  local S = ns.SaveState
  local d = S.Dirty()
  if not d.since then
    return false
  end
  hint = hint or buildHint()
  local can = S.CanReload()
  hint.text:SetText(string.format(L[can and "save.hint" or "save.hintType"], S.MinutesText(d.minutes)))
  hint.now:SetShown(can)
  hint.later:SetWidth(hint.later:FullWidth())
  hint.now:SetWidth(hint.now:FullWidth())
  layoutHint(hint)
  hint:Show()
  hintGeneration = hintGeneration + 1
  local mine = hintGeneration
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(HINT_SECONDS, function()
      if hintGeneration == mine then
        hint:Hide()
      end
    end)
  end
  return true
end

local function hideHint()
  if hint and hint:IsShown() then
    hint:Hide()
  end
end
ns.On("PLAYER_REGEN_DISABLED", hideHint)
ns.On("FG_SAVESTATE_CHANGED", function()
  if hint and hint:IsShown() and not ns.SaveState.Dirty().since then
    hint:Hide()
  end
end)
ns.On("FG_UI_REFRESHED", function()
  if hint and hint:IsShown() then
    hint.later:SetWidth(hint.later:FullWidth())
    hint.now:SetWidth(hint.now:FullWidth())
    layoutHint(hint)
  end
end)
