-- One line of text with a button: the layout that PackageUI.Banner (add-ons that are missing) and
-- OptInNotice.Banner (sharing that is off) have in common. The button sits right of the text from
-- SIDE_MIN pixels of width, narrower it goes below; without a button the text takes the width.
-- In a Stack it needs nothing else (fgGridLayout), hosts without a stack call Fit(width).
local _, ns = ...
local W = ns.W

local AB = {}
ns.ActionBanner = AB

AB.BUTTON_W = 190
AB.BUTTON_H = 24
AB.GAP = 8
-- From this width the button sits right of the text, narrower it goes below.
AB.SIDE_MIN = 460

-- Places text and button for the given width and returns the height. Also the Stack hook.
local function fit(b, width)
  width = math.max(1, width)
  b.fitWidth = width
  local text, button = b.text, b.button
  local buttonW, buttonH = b.buttonWidth, AB.BUTTON_H
  text:ClearAllPoints()
  button:ClearAllPoints()
  if not button:IsShown() then
    text:SetWidth(width)
    text:SetPoint("TOPLEFT", 0, 0)
    local h = math.max(text:GetStringHeight(), 1)
    b:SetHeight(h)
    return h
  end
  if width >= AB.SIDE_MIN then
    text:SetWidth(width - buttonW - AB.GAP)
    local textH = text:GetStringHeight()
    local h = math.max(textH, buttonH)
    text:SetPoint("TOPLEFT", 0, -math.floor((h - textH) / 2))
    button:SetPoint("TOPRIGHT", 0, -math.floor((h - buttonH) / 2))
    b:SetHeight(h)
    return h
  end
  text:SetWidth(width)
  text:SetPoint("TOPLEFT", 0, 0)
  button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -AB.GAP)
  local h = text:GetStringHeight() + AB.GAP + buttonH
  b:SetHeight(h)
  return h
end

-- opts: buttonKey (locale key of the label), tooltip + tooltipText (locale keys of the button's tooltip),
-- buttonWidth (default BUTTON_W), onClick, opens (true: the
-- button opens a window, false: it does so in some states, b.button:SetOpens(on) switches it), color (text color,
-- default warning). Fields: text, button; methods Fit(width) -> height and Refit() -> true when the
-- height changed (after the texts changed; a banner that was never fitted stays as it is).
function AB.New(parent, opts)
  opts = opts or {}
  local b = CreateFrame("Frame", nil, parent)
  b.buttonWidth = opts.buttonWidth or AB.BUTTON_W
  b.text = W.Text(b, { role = "ui", color = opts.color or "warning", wrap = true })
  b.button = W.Button(b, {
    key = opts.buttonKey,
    width = b.buttonWidth,
    height = AB.BUTTON_H,
    opens = opts.opens,
    tooltip = opts.tooltip,
    tooltipText = opts.tooltipText,
    onClick = opts.onClick,
  })
  if opts.opens then
    -- The button grew by its "opens" mark: the layout reserves the real width.
    b.buttonWidth = b.button:GetWidth()
  end
  b.fgGridLayout = fit
  b.Fit = fit
  b:SetHeight(AB.BUTTON_H)

  function b:Refit()
    if not self.fitWidth then
      return false
    end
    local before = self:GetHeight()
    fit(self, self.fitWidth)
    return self:GetHeight() ~= before
  end

  b:HookScript("OnSizeChanged", function(self, width)
    if width and width > 0 and width ~= self.fitWidth and self:IsShown() then
      fit(self, width)
    end
  end)
  return b
end
