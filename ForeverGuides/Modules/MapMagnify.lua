-- Magnifier of the world view on the map page (100 to 400 percent): the canvas grows inside a
-- clipping viewport and slides under it, so pins, labels, route and zone hit tests keep working
-- in canvas pixels. This file owns the zoom state, the mouse wheel, the drag to pan and the
-- "-" / percent / "+" bar. MapPage.lua hands in the frames and the few things only it knows.
local _, ns = ...
local W, MM = ns.W, ns.MapMarkers

local MG = {}
ns.MapMagnify = MG

MG.MIN, MG.MAX, MG.STEP = 100, 400, 25
MG.DRAG_PX = 4 -- cursor travel that turns a press into a drag, a plain click stays a click
MG.BUTTON, MG.VALUE_W, MG.INSET = 24, 48, 6
MG.REPAINT_SECONDS = 0.05

ns.AddLocale("enUS", {
  ["map.mag.in"] = "Zoom in",
  ["map.mag.out"] = "Zoom out",
  ["map.mag.reset"] = "Reset zoom",
  ["map.mag.tip"] = "Mouse wheel zooms\nDrag moves the map",
})

ns.AddLocale("deDE", {
  ["map.mag.in"] = "Vergrößern",
  ["map.mag.out"] = "Verkleinern",
  ["map.mag.reset"] = "Zoom zurücksetzen",
  ["map.mag.tip"] = "Mausrad zoomt\nZiehen verschiebt die Karte",
})

-- Pure logic ---------------------------------------------------------------------------
-- The pan is kept as fractions of the viewport (x, y <= 0: how far the canvas is pushed up and
-- left), so a resized window keeps the view.

function MG.Clamp(percent)
  local p = tonumber(percent)
  if not p or p ~= p then
    return MG.MIN
  end
  return math.max(MG.MIN, math.min(MG.MAX, p))
end

-- Offset of a canvas of `level` times the viewport: it always covers the viewport.
function MG.ClampOffset(offset, level)
  return math.max(1 - level, math.min(0, tonumber(offset) or 0))
end

function MG.New()
  return { percent = MG.MIN, x = 0, y = 0 }
end

-- Zooms to `percent` and keeps the map point under the anchor (fractions of the viewport) fixed.
function MG.Zoom(state, percent, ax, ay)
  local old = state.percent / 100
  state.percent = MG.Clamp(percent)
  local new = state.percent / 100
  ax, ay = tonumber(ax) or 0.5, tonumber(ay) or 0.5
  state.x = MG.ClampOffset(ax - (ax - state.x) * new / old, new)
  state.y = MG.ClampOffset(ay - (ay - state.y) * new / old, new)
end

function MG.PanTo(state, x, y)
  local level = state.percent / 100
  state.x, state.y = MG.ClampOffset(x, level), MG.ClampOffset(y, level)
end

-- ctx = {
--   viewport, canvas       the clipping frame and the (bigger) map frame inside it
--   active()               true while the world view is shown (the only view that zooms)
--   dragAllowed()          false while a click on the map means something else (marker mode)
--   changed()              lays the page out again after a zoom step
--   moved()                repaints what depends on the visible part (pins) while the map is dragged
-- }
-- Returns the controller: state, Active, Percent, Place, Window, Reset, In, Out, Wheel, WasDrag, bar.
function MG.Attach(ctx)
  local viewport, canvas = ctx.viewport, ctx.canvas
  local state = MG.New()
  local ctl = { state = state }
  if viewport.SetClipsChildren then
    viewport:SetClipsChildren(true)
  end

  function ctl.Active()
    return ctx.active() == true
  end

  function ctl.Percent()
    return ctl.Active() and state.percent or MG.MIN
  end

  -- Bar ----------------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, viewport)
  bar:SetFrameLevel(viewport:GetFrameLevel() + 300)
  bar:SetSize(2 * MG.BUTTON + MG.VALUE_W + 4, MG.BUTTON + 4)
  bar:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -MG.INSET, MG.INSET)
  -- Mouse on: a click between the buttons must not fall through and open a zone.
  bar:EnableMouse(true)
  W.Fill(bar, "surface2", 0.9)
  W.Border(bar, "white", 0.3)
  ctl.bar = bar

  local function change(percent, ax, ay)
    MG.Zoom(state, percent, ax, ay)
    ctx.changed()
  end

  function ctl.In()
    change(state.percent + MG.STEP)
  end

  function ctl.Out()
    change(state.percent - MG.STEP)
  end

  -- Back to 100 percent without a layout (page shown again, other view).
  function ctl.Reset()
    state.percent, state.x, state.y = MG.MIN, 0, 0
  end

  bar.out = W.Action(bar, {
    icon = "minus",
    size = MG.BUTTON,
    tooltip = "map.mag.out",
    onClick = function()
      ctl.Out()
    end,
  })
  bar.out:SetPoint("LEFT", bar, "LEFT", 2, 0)
  bar.value = W.ValueButton(bar, {
    width = MG.VALUE_W,
    height = MG.BUTTON,
    tooltip = "map.mag.reset",
    tooltipText = "map.mag.tip",
    onClick = function()
      ctl.Reset()
      ctx.changed()
    end,
  })
  bar.value:SetPoint("LEFT", bar.out, "RIGHT", 0, 0)
  bar.zoomIn = W.Action(bar, {
    icon = "plus",
    size = MG.BUTTON,
    tooltip = "map.mag.in",
    onClick = function()
      ctl.In()
    end,
  })
  bar.zoomIn:SetPoint("LEFT", bar.value, "RIGHT", 0, 0)

  local function paintBar()
    local active = ctl.Active()
    bar:SetShown(active)
    bar.value.text:SetText(string.format("%d %%", state.percent))
    bar.out:SetEnabled(state.percent > MG.MIN)
    bar.zoomIn:SetEnabled(state.percent < MG.MAX)
  end

  -- Layout ---------------------------------------------------------------------------------
  -- Sizes the canvas for a viewport of vw x vh px and pushes it to the pan; the hit area of the
  -- canvas shrinks to the visible part, so the overhang never catches a click meant for the
  -- controls around the map.
  function ctl.Place(vw, vh)
    local active = ctl.Active()
    local level = active and state.percent / 100 or 1
    if active then
      MG.PanTo(state, state.x, state.y)
    end
    local x, y = active and state.x or 0, active and state.y or 0
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", viewport, "TOPLEFT", x * vw, -y * vh)
    canvas:SetSize(vw * level, vh * level)
    if canvas.SetHitRectInsets then
      canvas:SetHitRectInsets(-x * vw, (level - 1 + x) * vw, -y * vh, (level - 1 + y) * vh)
    end
    canvas:EnableMouseWheel(active)
    paintBar()
  end

  -- The visible part of the canvas in canvas px: left, top, width, height.
  function ctl.Window()
    local vw, vh = viewport:GetWidth(), viewport:GetHeight()
    if not ctl.Active() then
      return 0, 0, canvas:GetWidth(), canvas:GetHeight()
    end
    return -state.x * vw, -state.y * vh, vw, vh
  end

  -- Wheel and drag ---------------------------------------------------------------------------
  function ctl.Wheel(delta)
    if not ctl.Active() or not tonumber(delta) or delta == 0 then
      return
    end
    local fx, fy = MM.CursorFraction(viewport)
    local function unit(v)
      return math.max(0, math.min(1, v or 0.5))
    end
    change(state.percent + (delta > 0 and 1 or -1) * MG.STEP, unit(fx), unit(fy))
  end
  canvas:SetScript("OnMouseWheel", function(_, delta)
    ns.Safe("map-wheel", ctl.Wheel, delta)
  end)

  -- True after a press that moved the map; the click that ends it is not a click on the map.
  function ctl.WasDrag()
    return ctl.dragged == true
  end

  canvas:HookScript("OnMouseDown", function(_, button)
    ctl.dragged = false
    if button ~= "LeftButton" or not ctl.Active() or state.percent <= MG.MIN then
      return
    end
    if ctx.dragAllowed and not ctx.dragAllowed() then
      return
    end
    local cx, cy = GetCursorPosition()
    ctl.drag = { cx = cx, cy = cy, x = state.x, y = state.y }
  end)

  local function endDrag()
    if ctl.drag and ctl.dragged then
      ctx.moved()
    end
    ctl.drag = nil
  end
  canvas:HookScript("OnMouseUp", endDrag)

  local elapsed = 0
  canvas:HookScript("OnUpdate", function(_, dt)
    local d = ctl.drag
    if not d then
      return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      endDrag()
      return
    end
    local cx, cy = GetCursorPosition()
    local scale = viewport:GetEffectiveScale()
    local vw, vh = viewport:GetWidth(), viewport:GetHeight()
    if not (scale and scale > 0 and vw > 0 and vh > 0) then
      return
    end
    local dx, dy = (cx - d.cx) / scale, (cy - d.cy) / scale
    if not ctl.dragged then
      if math.max(math.abs(dx), math.abs(dy)) < MG.DRAG_PX then
        return
      end
      ctl.dragged = true
    end
    -- Cursor up pushes the map up, which is a smaller (more negative) y.
    MG.PanTo(state, d.x + dx / vw, d.y - dy / vh)
    ctl.Place(vw, vh)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= MG.REPAINT_SECONDS then
      elapsed = 0
      ctx.moved()
    end
  end)
  canvas:HookScript("OnHide", function()
    ctl.drag = nil
  end)

  return ctl
end
