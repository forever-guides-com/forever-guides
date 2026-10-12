-- Footer controls of the main window, the same look as the bar under game windows: "Opacity
-- - 75 % + [slider]" and "Zoom - 100 % +  [slider]". Values live in settings.mainAlpha and
-- settings.scale (Main.SetAlpha, Main.SetScale). group:Fit(roomFull, roomMin) picks the level
-- from the room the footer leaves: with sliders, numbers and buttons only, then without the
-- captions. The controls are never cut, the data status in the footer gives way instead.
local _, ns = ...
local W, Theme, U, L = ns.W, ns.Theme, ns.U, ns.L

local FC = {}
ns.FooterControls = FC

FC.ZOOM_STEP = 0.1
FC.ZOOM_MIN, FC.ZOOM_MAX, FC.ZOOM_SLIDER_STEP = 70, 150, 5
FC.ALPHA_STEP = 5
FC.HEIGHT, FC.BUTTON = 18, 18
FC.VALUE_WIDTH, FC.SLIDER_WIDTH = 32, 76
FC.PAD, FC.GAP, FC.SEPARATE = 4, 2, 4

ns.AddLocale("enUS", {
  ["footer.opacity"] = "Opacity",
  ["footer.opacityTip"] = "Backgrounds only\n0 % = invisible",
  ["footer.opacityOut"] = "Less opaque",
  ["footer.opacityIn"] = "More opaque",
  ["footer.opacityValue"] = "Click: %d %%\nArrows: change",
  ["footer.zoom"] = "Zoom",
  ["footer.zoomOut"] = "Zoom out",
  ["footer.zoomIn"] = "Zoom in",
  ["footer.zoomValue"] = "Click: 100 %\nArrows: change",
  ["footer.slider"] = "Drag or mouse wheel",
})
ns.AddLocale("deDE", {
  ["footer.opacity"] = "Deckkraft",
  ["footer.opacityTip"] = "Nur Hintergründe\n0 % = unsichtbar",
  ["footer.opacityOut"] = "Weniger deckend",
  ["footer.opacityIn"] = "Mehr deckend",
  ["footer.opacityValue"] = "Klick: %d %%\nPfeile: ändern",
  ["footer.zoom"] = "Zoom",
  ["footer.zoomOut"] = "Verkleinern",
  ["footer.zoomIn"] = "Vergrößern",
  ["footer.zoomValue"] = "Klick: 100 %\nPfeile: ändern",
  ["footer.slider"] = "Ziehen oder Mausrad",
})

local function alphaPercent()
  return U.round(Theme.mainAlpha() * 100)
end

local function zoomPercent()
  return U.round(Theme.windowScale() * 100)
end

local function alphaBy(dir)
  ns.Main.SetAlpha(alphaPercent() + dir * FC.ALPHA_STEP)
end

-- Every zoom change names the control the user is working with as the anchor: the window scales
-- around it, so it stays under the mouse.
local function zoomBy(dir, anchor)
  ns.Main.SetScale(Theme.windowScale() + dir * FC.ZOOM_STEP, anchor)
end

function FC.Build(footer)
  local group = CreateFrame("Frame", nil, footer)
  group:SetSize(FC.PAD, FC.HEIGHT)
  -- Own plate and edge: the controls stay visible on a fully transparent window.
  W.Fill(group, "surface2", 0.9)
  W.Border(group, "white", 0.3)

  local function label(key)
    return W.Text(group, { key = key, role = "micro", color = "textSecondary" })
  end
  local function step(icon, tooltip, tooltipText, onClick)
    local b = W.Action(group, { icon = icon, size = FC.BUTTON, tooltip = tooltip, tooltipText = tooltipText })
    b:SetScript("OnClick", ns.Wrap("footer-controls", onClick))
    return b
  end
  local function value(onClick, tooltip, tooltipText)
    return W.ValueButton(
      group,
      { width = FC.VALUE_WIDTH, onClick = onClick, tooltip = tooltip, tooltipText = tooltipText }
    )
  end
  local function divider()
    local line = group:CreateTexture(nil, "ARTWORK")
    line:SetSize(1, FC.HEIGHT - 6)
    line:SetColorTexture(1, 1, 1, 0.25)
    return line
  end

  group.alphaLabel = label("footer.opacity")
  group.alphaOut = step("minus", "footer.opacityOut", "footer.opacityTip", function()
    alphaBy(-1)
  end)
  group.alphaValue = value(
    function()
      ns.Main.SetAlpha(Theme.ALPHA_DEFAULT)
    end,
    "footer.opacity",
    function()
      return string.format(L["footer.opacityValue"], Theme.ALPHA_DEFAULT)
    end
  )
  group.alphaIn = step("plus", "footer.opacityIn", "footer.opacityTip", function()
    alphaBy(1)
  end)
  group.alphaSlider = W.CompactSlider(group, {
    min = Theme.ALPHA_MIN,
    max = Theme.ALPHA_MAX,
    step = FC.ALPHA_STEP,
    width = FC.SLIDER_WIDTH,
    set = function(v)
      ns.Main.SetAlpha(v)
    end,
    tooltip = "footer.opacity",
    tooltipText = "footer.slider",
  })
  group.divider = divider()

  group.zoomLabel = label("footer.zoom")
  group.zoomOut = step("minus", "footer.zoomOut", nil, function()
    zoomBy(-1, group.zoomOut)
  end)
  group.zoomValue = value(function()
    ns.Main.SetScale(1, group.zoomValue)
  end, "footer.zoom", "footer.zoomValue")
  group.zoomText = group.zoomValue.text
  group.zoomIn = step("plus", "footer.zoomIn", nil, function()
    zoomBy(1, group.zoomIn)
  end)
  -- While the thumb is held only the number follows, the window scales on release around the
  -- thumb (a live zoom would re-layout under the mouse on every step). Wheel and arrow keys apply
  -- at once.
  group.zoomSlider = W.CompactSlider(group, {
    min = FC.ZOOM_MIN,
    max = FC.ZOOM_MAX,
    step = FC.ZOOM_SLIDER_STEP,
    width = FC.SLIDER_WIDTH,
    applyOn = "release",
    preview = function(v)
      group.zoomText:SetText(string.format("%d %%", v))
    end,
    set = function(v)
      ns.Main.SetScale(v / 100, W.ThumbAnchor(group.zoomSlider))
    end,
    tooltip = "footer.zoom",
    tooltipText = "footer.slider",
  })

  -- Arrow keys change the value while one of the buttons has the focus.
  for _, b in ipairs({ group.alphaOut, group.alphaIn, group.alphaValue }) do
    b.fgArrow = function(_, dir)
      alphaBy(dir)
    end
  end
  for _, b in ipairs({ group.zoomOut, group.zoomIn, group.zoomValue }) do
    b.fgArrow = function(self, dir)
      zoomBy(dir, self)
    end
  end

  -- Widest number "100 %" in the current font; keeps the value buttons wide enough.
  local probe = W.Text(group, { role = "micro", text = "100 %" })
  probe:Hide()

  -- Places everything left to right and returns the width. withLabels / withSliders pick the level.
  local function layout(withLabels, withSliders)
    local x = FC.PAD
    local valueWidth = math.max(FC.VALUE_WIDTH, math.ceil(probe:GetStringWidth()) + 4)
    local function put(widget, width)
      widget:ClearAllPoints()
      widget:SetPoint("LEFT", group, "LEFT", x, 0)
      x = x + width + FC.GAP
    end
    local function block(caption, out, number, inn, slider)
      caption:SetShown(withLabels)
      if withLabels then
        local width = math.ceil(caption:GetStringWidth()) + 2
        caption:SetWidth(width)
        put(caption, width)
      end
      put(out, FC.BUTTON)
      number:SetWidth(valueWidth)
      put(number, valueWidth)
      put(inn, FC.BUTTON)
      slider:SetShown(withSliders)
      if withSliders then
        x = x + 1
        put(slider, FC.SLIDER_WIDTH)
      end
    end
    block(group.alphaLabel, group.alphaOut, group.alphaValue, group.alphaIn, group.alphaSlider)
    x = x - FC.GAP + FC.SEPARATE
    group.divider:ClearAllPoints()
    group.divider:SetPoint("LEFT", group, "LEFT", x, 0)
    x = x + 1 + FC.SEPARATE
    block(group.zoomLabel, group.zoomOut, group.zoomValue, group.zoomIn, group.zoomSlider)
    local width = x - FC.GAP + FC.PAD
    group:SetWidth(width)
    return width
  end

  -- roomFull: width the controls may take while the data status stays whole; roomMin: width
  -- left when the data status is cut to its minimum. nil: no limit.
  function group:Fit(roomFull, roomMin)
    local full = roomFull or math.huge
    local least = roomMin or math.huge
    if layout(true, true) <= full then
      return group:GetWidth()
    end
    if layout(true, false) <= least then
      return group:GetWidth()
    end
    return layout(false, false)
  end

  local function paint()
    local pct = alphaPercent()
    group.alphaValue.text:SetText(string.format("%d %%", pct))
    group.alphaOut:SetEnabled(pct > Theme.ALPHA_MIN)
    group.alphaIn:SetEnabled(pct < Theme.ALPHA_MAX)
    group.alphaSlider:Sync(pct)

    local zoom = zoomPercent()
    group.zoomText:SetText(string.format("%d %%", zoom))
    group.zoomOut:SetEnabled(zoom > FC.ZOOM_MIN)
    group.zoomIn:SetEnabled(zoom < FC.ZOOM_MAX)
    group.zoomSlider:Sync(zoom)
  end
  ns.Bind(group, paint)
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if path == "settings.scale" or path == "settings.mainAlpha" then
      paint()
    end
  end)
  group:Fit()
  return group
end
