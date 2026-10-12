-- Tour overlay: dims everything except the target, gold frame + glow on
-- the target, bubble with back/next/skip. Pauses in combat.
local _, ns = ...
local W, L, Theme, U = ns.W, ns.L, ns.Theme, ns.U

local UI = {}
ns.TutorialUI = UI

local overlay, dims, highlight, bubble
local active -- { tour, index, steps }

local function ensure()
  if overlay then
    return
  end
  overlay = CreateFrame("Frame", nil, UIParent)
  overlay:SetAllPoints(UIParent)
  overlay:SetFrameStrata("FULLSCREEN_DIALOG")
  overlay:Hide()
  dims = {}
  for i = 1, 4 do
    -- Buttons swallow clicks outside the target.
    local d = CreateFrame("Button", nil, overlay)
    d.tex = d:CreateTexture(nil, "BACKGROUND")
    d.tex:SetAllPoints()
    d.tex:SetColorTexture(0, 0, 0, 0.45)
    dims[i] = d
  end
  highlight = CreateFrame("Frame", nil, overlay)
  highlight.border = W.Border(highlight, "accent2", 1, 2)
  highlight.glow = highlight:CreateTexture(nil, "BACKGROUND")
  highlight.glow:SetPoint("TOPLEFT", -10, 10)
  highlight.glow:SetPoint("BOTTOMRIGHT", 10, -10)
  highlight.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  highlight.glow:SetBlendMode("ADD")
  highlight.glow:SetVertexColor(Theme.rgb("accent2"))
  local anim = highlight.glow:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local a = anim:CreateAnimation("Alpha")
  a:SetFromAlpha(0.25)
  a:SetToAlpha(0.9)
  a:SetDuration(1.2)
  highlight.anim = anim

  bubble = CreateFrame("Frame", nil, overlay)
  bubble:SetSize(320, 170)
  bubble:SetClampedToScreen(true)
  bubble:SetFrameLevel(overlay:GetFrameLevel() + 10)
  W.Fill(bubble, "surface", 1)
  W.Border(bubble, "accent2", 1)
  bubble.title = W.Text(bubble, { role = "h3", family = "heading", color = "accent2", wrap = true })
  bubble.title:SetPoint("TOPLEFT", 12, -10)
  bubble.title:SetPoint("RIGHT", -12, 0)
  bubble.text = W.Text(bubble, { role = "ui", wrap = true })
  bubble.text:SetPoint("TOPLEFT", bubble.title, "BOTTOMLEFT", 0, -6)
  bubble.text:SetPoint("RIGHT", -12, 0)
  bubble.step = W.Text(bubble, { role = "micro", color = "textMuted" })
  bubble.step:SetPoint("BOTTOMLEFT", 12, 40)
  bubble.never = W.Checkbox(bubble, {
    key = "tour.never",
    get = function()
      local e = active and ns.db.tutorials.seen[active.tour.id]
      return e and e.never or false
    end,
    set = function(v)
      ns.Tutorials.setNever(active.tour.id, v)
    end,
  })
  bubble.never:SetPoint("BOTTOMLEFT", 10, 10)
  bubble.never:SetWidth(140)
  bubble.next = W.Button(bubble, {
    key = "tour.next",
    variant = "primary",
    width = 76,
    height = 22,
    onClick = function()
      UI.Next()
    end,
  })
  bubble.next:SetPoint("BOTTOMRIGHT", -10, 10)
  bubble.back = W.Action(bubble, {
    label = "act.back",
    icon = "chevron-left",
    tooltip = "tour.back",
    width = 66,
    height = 22,
    onClick = function()
      UI.Back()
    end,
  })
  bubble.back:SetPoint("RIGHT", bubble.next, "LEFT", -6, 0)
  local skip = W.Button(bubble, {
    key = "tour.skip",
    variant = "ghost",
    width = 80,
    height = 20,
    onClick = function()
      UI.Finish("skipped")
    end,
  })
  skip:SetPoint("BOTTOMRIGHT", -10, 36)
end

local function targetFrame(step)
  local f = step.target and ns.Anchors[step.target]
  if f and f:IsVisible() and f:GetLeft() then
    return f
  end
end

-- Rect of a frame in UIParent units.
local function rect(f)
  local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return f:GetLeft() * s, f:GetRight() * s, f:GetTop() * s, f:GetBottom() * s
end

local function layoutDims(l, r, t, b)
  local W_, H = UIParent:GetWidth(), UIParent:GetHeight()
  local pad = 4
  l, r, t, b = l - pad, r + pad, t + pad, b - pad
  local spec = {
    { 0, H, W_, t }, -- above
    { 0, b, W_, 0 }, -- below
    { 0, t, l, b }, -- left
    { r, t, W_, b }, -- right
  }
  for i, d in ipairs(dims) do
    local x1, y1, x2, y2 = spec[i][1], spec[i][2], spec[i][3], spec[i][4]
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", x1, y1)
    d:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT", math.max(x1 + 1, x2), math.min(y1 - 1, y2))
    d:Show()
  end
end

local function placeBubble(l, r, t, b)
  local W_, H = UIParent:GetWidth(), UIParent:GetHeight()
  local bw, bh = bubble:GetWidth(), bubble:GetHeight()
  bubble:ClearAllPoints()
  if W_ - r > bw + 16 then
    bubble:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", r + 12, U.clamp(t, bh, H))
  elseif b > bh + 16 then
    bubble:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", U.clamp(l, 0, W_ - bw), b - 12)
  elseif l > bw + 16 then
    bubble:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", l - 12, U.clamp(t, bh, H))
  else
    bubble:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", U.clamp(l, 0, W_ - bw), t + 12)
  end
end

local function render()
  local step = active.steps[active.index]
  local key = "tour." .. active.tour.id .. "." .. step.id
  W.SetText(bubble.title, key .. ".title")
  W.SetText(bubble.text, key .. ".text")
  bubble.step:SetText(string.format(L["tour.step"], active.index, #active.steps))
  bubble.back:SetEnabled(active.index > 1)
  W.SetText(bubble.next.label, active.index == #active.steps and "tour.done" or "tour.next")
  bubble.never:Refresh()
  bubble:SetHeight(96 + bubble.title:GetStringHeight() + bubble.text:GetStringHeight())
  local f = targetFrame(step)
  if f then
    local l, r, t, b = rect(f)
    layoutDims(l, r, t, b)
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", l - 4, t + 4)
    highlight:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT", r + 4, b - 4)
    highlight:Show()
    if Theme.reduceMotion() then
      highlight.anim:Stop()
      highlight.glow:SetAlpha(0.6)
    else
      highlight.anim:Play()
    end
    placeBubble(l, r, t, b)
  else
    -- No target: centered card over a full dimmer.
    for i, d in ipairs(dims) do
      d:SetShown(i == 1)
    end
    dims[1]:ClearAllPoints()
    dims[1]:SetAllPoints(overlay)
    highlight:Hide()
    bubble:ClearAllPoints()
    bubble:SetPoint("CENTER", overlay, "CENTER")
  end
  overlay:Show()
end

function UI.Start(id)
  local tour = ns.Tutorials.tours[id]
  if not tour then
    return false
  end
  if InCombatLockdown() then
    ns.Notify(L["tour.combat"], "warning")
    return false
  end
  ensure()
  if not ns.Main.IsShown() then
    ns.Main.Show()
  end
  if tour.start or (tour.page and ns.RouterClass.parse(ns.Router.current) ~= tour.page) then
    ns.Router:navigate(tour.start or tour.page)
  end
  local steps = {}
  for _, step in ipairs(tour.steps) do
    if not (step.optional and step.target and not targetFrame(step)) then
      steps[#steps + 1] = step
    end
  end
  active = { tour = tour, index = 1, steps = steps }
  -- Wait one frame so the main window has its final layout.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if active then
        ns.Safe("tour-render", render)
      end
    end)
  else
    render()
  end
  return true
end

function UI.Next()
  if not active then
    return
  end
  if active.index >= #active.steps then
    UI.Finish("done")
  else
    active.index = active.index + 1
    render()
  end
end

function UI.Back()
  if active and active.index > 1 then
    active.index = active.index - 1
    render()
  end
end

function UI.Finish(how)
  if not active then
    return
  end
  ns.Tutorials.mark(active.tour.id, how)
  active = nil
  overlay:Hide()
  ns.Emit("FG_TUTORIAL_CHANGED")
end

function UI.IsActive()
  return active ~= nil
end

function UI.HandleKey(key)
  if not active or not overlay:IsShown() then
    return false
  end
  if key == "ESCAPE" then
    UI.Finish("skipped")
  elseif key == "ENTER" or key == "RIGHT" then
    UI.Next()
  elseif key == "LEFT" then
    UI.Back()
  else
    return false
  end
  return true
end

ns.On("PLAYER_REGEN_DISABLED", function()
  if active then
    overlay:Hide()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if active then
    render()
  end
end)

-- Closing the main window ends the tour (targets are gone).
ns.On("FG_MAIN_HIDDEN", function()
  if active then
    UI.Finish("skipped")
  end
end)

-- First open: offer the start tour instead of forcing it.
ns.On("FG_MAIN_SHOWN", function()
  if UI.offered or active or not ns.Tutorials.shouldOffer("addon-start") then
    return
  end
  UI.offered = true
  ns.Dialogs.Confirm("tour.offerTitle", "tour.offerText", function()
    UI.Start("addon-start")
  end, function()
    ns.Tutorials.mark("addon-start", "skipped")
    ns.Emit("FG_TUTORIAL_CHANGED")
  end)
end)
