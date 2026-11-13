-- The way to one control of a settings card: find its frame (by its id or the locale key of its name), open the
-- "More settings" section that holds it, scroll it into view, mark it for a moment and give it the keyboard
-- focus. Used by ns.SettingsPage.Select(feature, card, control) for the search, the links and the commands.
local _, ns = ...
local W = ns.W

local SJ = {}
ns.SettingsJump = SJ

-- Seconds the mark stays. With "Reduce motion" it stays until the next jump or until the player leaves the tab.
SJ.MARK_SECONDS = 1.5
-- Space kept above a control that was scrolled to.
SJ.TOP_MARGIN = 28

local function field(frame, name)
  return type(frame) == "table" and rawget(frame, name) or nil
end

local function matches(frame, ref)
  if field(frame, "fgId") == ref then
    return true
  end
  local spec = field(frame, "fgSetting")
  return spec ~= nil and spec.key == ref
end

-- The first frame below root (or root itself) whose id or name key is ref, in creation order.
function SJ.Find(root, ref)
  if not root or ref == nil then
    return nil
  end
  if matches(root, ref) then
    return root
  end
  for _, child in ipairs({ root:GetChildren() }) do
    local hit = SJ.Find(child, ref)
    if hit then
      return hit
    end
  end
  return nil
end

-- The frame of a control in a card of a settings view: card is the card table of the grid.
function SJ.FindInCard(card, ref)
  local hit = SJ.Find(card.frame, ref)
  if hit then
    return hit
  end
  -- A text line is a region of its frame and not a child: the sections list theirs themselves.
  for _, acc in ipairs(card.accordions or {}) do
    hit = acc.FindControl and acc:FindControl(ref)
    if hit then
      return hit
    end
  end
  return nil
end

local function isInside(frame, ancestor)
  local f = frame
  while f do
    if f == ancestor then
      return true
    end
    f = f:GetParent()
  end
  return false
end

-- Opens (for now, the saved state stays) every "More settings" section of the card that holds the frame.
function SJ.Reveal(card, frame, ref)
  local opened = false
  for _, acc in ipairs(card.accordions or {}) do
    if (frame and isInside(frame, acc.body)) or (ref ~= nil and acc.Has and acc:Has(ref)) then
      if not acc:IsOpen() then
        acc:Open(false)
        opened = true
      end
    end
  end
  return opened
end

-- Vertical position the page scrolls to so that the control stands near the top of the viewport.
function SJ.ScrollTarget(card, frame)
  local base = card.top or 0
  local top, cardTop = frame:GetTop(), card.frame:GetTop()
  if not (top and cardTop) then
    return base
  end
  return math.max(0, base + (cardTop - top) - SJ.TOP_MARGIN)
end

-- The one focusable frame of a control (a toggle is one, a slider holds one inside).
function SJ.Focusable(frame)
  for _, item in ipairs(ns.Focus.items) do
    local f = item
    while f do
      if f == frame then
        return item
      end
      f = f:GetParent()
    end
  end
  return nil
end

-- True while the mark lies fully inside the viewport of the page. Measured from the offset inside the content
-- and the scroll position, so it does not depend on when the client solved the frames after a scroll.
local function inViewport(view, hl)
  local top, bottom, contentTop = hl:GetTop(), hl:GetBottom(), view.content:GetTop()
  local scroll, height = view.area:GetVerticalScroll(), view.area:GetHeight()
  if not (top and bottom and contentTop and scroll and height) then
    return true
  end
  local offset = contentTop - top
  return offset >= scroll and offset + (top - bottom) <= scroll + height
end

-- The client does not always clip the children of the scroll content: the mark is drawn only while its control
-- is inside the viewport, and comes back when the page scrolls back.
function SJ.Fit(view)
  local hl = view.fgMark
  if hl then
    hl:SetShown(hl.fgActive == true and inViewport(view, hl))
  end
end

local function mark(view)
  local hl = view.fgMark
  if hl then
    return hl
  end
  hl = CreateFrame("Frame", nil, view.content)
  view.area:HookScript("OnVerticalScroll", function()
    SJ.Fit(view)
  end)
  view.area:HookScript("OnHide", function()
    SJ.ClearMark(view)
  end)
  W.Fill(hl, "accent2", 0.14)
  hl.border = W.Border(hl, "accent2", 1, 2)
  hl:EnableMouse(false)
  hl:Hide()
  view.fgMark = hl
  return hl
end

-- Marks the control with a frame around it; hides it after SJ.MARK_SECONDS unless motion is reduced.
function SJ.Mark(view, frame)
  local hl = mark(view)
  hl:ClearAllPoints()
  hl:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
  hl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
  -- A text line is a region without a frame level of its own, it sits on the level of its parent.
  local owner = frame.GetFrameLevel and frame or frame:GetParent() or view.content
  hl:SetFrameLevel(owner:GetFrameLevel() + 4)
  hl.fgToken = (hl.fgToken or 0) + 1
  local token = hl.fgToken
  hl.fgActive = true
  SJ.Fit(view)
  if not ns.Theme.reduceMotion() then
    C_Timer.After(SJ.MARK_SECONDS, function()
      if hl.fgToken == token then
        hl.fgActive = false
        hl:Hide()
      end
    end)
  end
  return hl
end

function SJ.ClearMark(view)
  if view.fgMark then
    view.fgMark.fgToken = (view.fgMark.fgToken or 0) + 1
    view.fgMark.fgActive = false
    view.fgMark:Hide()
  end
end

-- Jumps to the control inside a card of a built view: reveal, scroll, mark, focus. `relayout` is called after a
-- section opened (the page lays out its cards again). Returns the frame, nil when the card has no such control.
function SJ.Go(view, card, ref, relayout)
  local frame = SJ.FindInCard(card, ref)
  if not frame then
    return nil
  end
  if SJ.Reveal(card, frame, ref) and relayout then
    relayout()
  end
  view.area:ScrollTo(SJ.ScrollTarget(card, frame))
  SJ.Mark(view, frame)
  local focus = SJ.Focusable(frame)
  if focus then
    ns.Focus.set(focus)
  end
  -- The client may place the frames a moment later: the scroll position is corrected once.
  C_Timer.After(0, function()
    if frame:IsVisible() then
      view.area:ScrollTo(SJ.ScrollTarget(card, frame))
      SJ.Fit(view)
    end
  end)
  return frame
end
