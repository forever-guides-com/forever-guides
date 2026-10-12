-- Copy dialog (exports, reports) and confirm dialog. Links are not
-- clickable in-game, so everything leaving the game goes through a
-- pre-selected text field and Ctrl+C.
local _, ns = ...
local W = ns.W

local Dialogs = { open = {} }
ns.Dialogs = Dialogs

local function base(name, width, height)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(width, height)
  f:SetPoint("CENTER")
  -- Above every window that opens a dialog (those sit in DIALOG): confirm and sub dialogs never
  -- open behind their window.
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  W.Fill(f, "bg", 0.97)
  local shell = ns.WindowShell.Attach(f, { role = "h2", titleHeight = 40, shadow = true })
  local close = W.Action(shell.titleBar, { icon = "close", size = 22, tooltip = "common.close" })
  close:SetPoint("RIGHT", -8, 0)
  f.title = shell.titleText
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 16, 0)
  f.title:SetPoint("RIGHT", close, "LEFT", -8, 0)
  close:SetScript("OnClick", function()
    f:Hide()
  end)
  f:SetScript("OnShow", function()
    Dialogs.open[f] = true
    f:SetScale(ns.Theme.windowScale())
  end)
  f:SetScript("OnHide", function()
    Dialogs.open[f] = nil
  end)
  -- A hook, so a module that sets its own OnShow keeps it: the newest dialog is on top and on screen.
  f:HookScript("OnShow", function()
    f:Raise()
    ns.WindowShell.FitToScreen(f)
  end)
  ns.WindowShell.RegisterEsc(f)
  f:Hide()
  return f
end

function Dialogs.closeTop()
  for f in pairs(Dialogs.open) do
    if f:IsShown() then
      f:Hide()
      return true
    end
  end
  return false
end

local copy
-- titleKey: locale key; hintKey: optional locale key shown above the text; actions: optional list
-- of { key = locale key, onClick = function } buttons left of "select all".
function Dialogs.Copy(titleKey, text, hintKey, actions)
  if not copy then
    copy = base("ForeverGuidesCopyDialog", 560, 360)
    copy.hint = W.Text(copy, { role = "ui", color = "textSecondary", wrap = true })
    copy.hint:SetPoint("TOPLEFT", 16, -44)
    copy.hint:SetPoint("RIGHT", -16, 0)
    -- Native ScrollFrame + EditBox, modeled directly on EllesmereUI's own
    -- working export/copy popup (confirmed rendering text correctly on
    -- this same Forever client). Our own W.ScrollArea abstraction failed
    -- to show text here across several attempts despite the content
    -- being genuinely present the whole time (confirmed via
    -- Ctrl+A/Ctrl+C), so this bypasses it entirely rather than patching
    -- it again.
    local area = CreateFrame("ScrollFrame", nil, copy)
    area:SetFrameLevel(copy:GetFrameLevel() + 1)
    area:SetPoint("TOPLEFT", 16, -84)
    area:SetPoint("BOTTOMRIGHT", -16, 52)
    area:EnableMouseWheel(true)
    W.Fill(area, "surface", 1)

    local content = CreateFrame("Frame", nil, area)
    content:SetWidth(area:GetWidth() > 0 and area:GetWidth() or 528)
    content:SetHeight(1)
    area:SetScrollChild(content)

    local bar
    local function updateBar()
      if not bar then
        return
      end
      local maxScroll = math.max(0, content:GetHeight() - area:GetHeight())
      local visibleFrac = (area:GetHeight() > 0 and content:GetHeight() > 0)
          and math.min(1, area:GetHeight() / content:GetHeight())
        or 1
      local pos = maxScroll > 0 and (area:GetVerticalScroll() / maxScroll) or 0
      bar:Update(visibleFrac, pos)
    end
    bar = W.Scrollbar(area, function(frac)
      local maxScroll = math.max(0, content:GetHeight() - area:GetHeight())
      area:SetVerticalScroll(maxScroll * frac)
      updateBar()
    end)

    local eb = CreateFrame("EditBox", nil, content)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetHeight(1)
    eb:SetPoint("TOPLEFT", content, "TOPLEFT", 6, 0)
    eb:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, 0)
    ns.Bind(eb, function()
      ns.Theme.applyFont(eb, "ui", "body")
      eb:SetTextColor(ns.Theme.color("text"))
    end)
    eb:SetScript("OnEscapePressed", function()
      copy:Hide()
    end)
    local function refreshHeight()
      C_Timer.After(0.01, function()
        local lineHeight = (eb.GetLineHeight and eb:GetLineHeight()) or 14
        local needed = W.EditLineCount(eb) * lineHeight
        local viewportH = area:GetHeight() or 100
        local h = math.max(needed, viewportH)
        content:SetHeight(h)
        eb:SetHeight(h)
        updateBar()
      end)
    end
    -- Read-only: typing restores the original text.
    eb:SetScript("OnTextChanged", function(self, user)
      if user then
        self:SetText(copy.value or "")
        self:HighlightText()
      end
      refreshHeight()
    end)
    area:SetScript("OnSizeChanged", function(self, w)
      content:SetWidth(math.max(1, w))
      refreshHeight()
    end)
    area:SetScript("OnMouseWheel", function(self, delta)
      local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
      local target = self:GetVerticalScroll() - delta * 40
      if target < 0 then
        target = 0
      elseif target > maxScroll then
        target = maxScroll
      end
      self:SetVerticalScroll(target)
      updateBar()
    end)
    content:EnableMouse(true)
    content:SetScript("OnMouseDown", function()
      eb:SetFocus()
    end)
    copy.edit = eb
    copy.refreshHeight = refreshHeight
    local keys = W.Text(copy, { key = "copy.hint", role = "micro", color = "textMuted" })
    keys:SetPoint("BOTTOMLEFT", 16, 20)
    copy.keys = keys
    copy.actions = {}
    local done = W.Action(copy, {
      label = "act.close",
      icon = "close",
      tooltip = "common.close",
      variant = "primary",
      width = 110,
      onClick = function()
        copy:Hide()
      end,
    })
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    local sel = W.Button(copy, {
      key = "copy.select",
      width = 130,
      onClick = function()
        eb:SetFocus()
        eb:HighlightText()
      end,
    })
    sel:SetPoint("RIGHT", done, "LEFT", -8, 0)
    copy.sel = sel
  end
  actions = actions or {}
  local anchor = copy.sel
  for i, action in ipairs(actions) do
    local button = copy.actions[i]
    if not button then
      button = W.Button(copy, { key = action.key, width = 130 })
      copy.actions[i] = button
    end
    W.SetText(button.label, action.key)
    button:SetScript("OnClick", ns.Wrap("button", action.onClick))
    button:ClearAllPoints()
    button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    button:Show()
    anchor = button
  end
  for i = #actions + 1, #copy.actions do
    copy.actions[i]:Hide()
  end
  copy.keys:SetShown(#actions == 0)
  W.SetText(copy.title, titleKey)
  W.SetText(copy.hint, hintKey)
  copy.value = text or ""
  copy.edit:SetText(copy.value)
  copy:Show()
  copy.refreshHeight()
  local eb = copy.edit
  C_Timer.After(0.05, function()
    eb:SetFocus()
    eb:HighlightText()
  end)
  return copy
end

local confirm
function Dialogs.Confirm(titleKey, textKey, onYes, onNo)
  if not confirm then
    confirm = base("ForeverGuidesConfirmDialog", 420, 170)
    confirm.text = W.Text(confirm, { role = "text", wrap = true })
    confirm.text:SetPoint("TOPLEFT", 16, -48)
    confirm.text:SetPoint("RIGHT", -16, 0)
    confirm.yes = W.Action(
      confirm,
      { label = "act.confirm", icon = "check", tooltip = "common.confirm", variant = "primary", width = 110 }
    )
    confirm.yes:SetPoint("BOTTOMRIGHT", -16, 14)
    confirm.no = W.Action(confirm, { label = "act.cancel", icon = "close", tooltip = "common.cancel", width = 110 })
    confirm.no:SetPoint("RIGHT", confirm.yes, "LEFT", -8, 0)
  end
  confirm.no:SetScript(
    "OnClick",
    ns.Wrap("confirm-no", function()
      confirm:Hide()
      if onNo then
        onNo()
      end
    end)
  )
  W.SetText(confirm.title, titleKey)
  W.SetText(confirm.text, textKey)
  confirm.yes:SetScript(
    "OnClick",
    ns.Wrap("confirm", function()
      confirm:Hide()
      onYes()
    end)
  )
  confirm:Show()
end

-- Generic dialog shell for modules (e.g. feedback form).
function Dialogs.Create(name, width, height)
  return base(name, width, height)
end
