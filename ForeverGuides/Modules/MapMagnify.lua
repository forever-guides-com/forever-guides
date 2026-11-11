-- Magnifier of the world view and of the zone view on the map page and of the dungeon map (100 to 400
-- percent): the canvas grows inside a clipping viewport and slides under it, so pins, labels, route and
-- zone hit tests keep working in canvas pixels. Every view has its own zoom state. This file owns the zoom
-- states, the mouse wheel, the drag to pan, the keys and the "-" / percent / "+" bar. The hosts
-- (MapPage.lua, DungeonMapView.lua) hand in the frames and the few things only they know.
local _, ns = ...
local W, MM = ns.W, ns.MapMarkers

local MG = {}
ns.MapMagnify = MG

MG.MIN, MG.MAX, MG.STEP = 100, 400, 25
MG.DRAG_PX = 4 -- cursor travel that turns a press into a drag, a plain click stays a click
MG.BUTTON, MG.VALUE_W, MG.INSET = 24, 48, 6
MG.REPAINT_SECONDS = 0.05
MG.PAN_STEP = 0.1 -- share of the viewport one arrow key moves the map
-- The views that zoom, each with a state of its own. A host with other views passes ctx.views.
MG.VIEWS = { "world", "zone" }
-- A source pixel is magnified at most this many times, and the least a map may zoom in (percent).
MG.SOURCE_SCALE, MG.MIN_LIMIT = 3, 200

ns.AddLocale("enUS", {
  ["map.mag.in"] = "Zoom in",
  ["map.mag.out"] = "Zoom out",
  ["map.mag.reset"] = "Reset zoom",
  ["map.mag.tip"] = "Mouse wheel zooms\nDrag moves the map",
  ["map.mag.blocked"] = "Not available in combat.",
})

ns.AddLocale("deDE", {
  ["map.mag.in"] = "Vergrößern",
  ["map.mag.out"] = "Verkleinern",
  ["map.mag.reset"] = "Zoom zurücksetzen",
  ["map.mag.tip"] = "Mausrad zoomt\nZiehen verschiebt die Karte",
  ["map.mag.blocked"] = "Im Kampf nicht verfügbar.",
})

-- Pure logic ---------------------------------------------------------------------------
-- The pan is kept as fractions of the viewport (x, y <= 0: how far the canvas is pushed up and
-- left), so a resized window keeps the view.

-- Highest zoom of a view: the limit of its map (see MG.MaxPercent) or the general maximum.
function MG.Limit(state)
  return state.max or MG.MAX
end

-- `max` is the highest value a view allows (default MG.MAX).
function MG.Clamp(percent, max)
  local p = tonumber(percent)
  if not p or p ~= p then
    return MG.MIN
  end
  return math.max(MG.MIN, math.min(max or MG.MAX, p))
end

-- Highest zoom of a map picture: a source pixel is magnified at most MG.SOURCE_SCALE times, so
-- 300 * source width / shown width, rounded to a step, kept between MG.MIN_LIMIT and MG.MAX.
function MG.MaxPercent(sourceW, shownW)
  if type(sourceW) ~= "number" or type(shownW) ~= "number" or sourceW ~= sourceW or shownW ~= shownW then
    return MG.MAX
  end
  if sourceW <= 0 or shownW <= 0 then
    return MG.MAX
  end
  local percent = MG.SOURCE_SCALE * 100 * sourceW / shownW
  local stepped = math.floor(percent / MG.STEP + 0.5) * MG.STEP
  return math.max(MG.MIN_LIMIT, math.min(MG.MAX, stepped))
end

-- Offset of a canvas of `level` times the viewport: it always covers the viewport.
function MG.ClampOffset(offset, level)
  return math.max(1 - level, math.min(0, tonumber(offset) or 0))
end

function MG.New()
  return { percent = MG.MIN, x = 0, y = 0 }
end

-- Back to 100 percent in place, so everything that holds the state sees it.
function MG.ResetState(state)
  state.percent, state.x, state.y = MG.MIN, 0, 0
end

-- One state per view: { world = state, zone = state } or one per key of `keys`.
function MG.NewViews(keys)
  local views = {}
  for _, key in ipairs(keys or MG.VIEWS) do
    views[key] = MG.New()
  end
  return views
end

-- Zooms to `percent` and keeps the map point under the anchor (fractions of the viewport) fixed.
function MG.Zoom(state, percent, ax, ay)
  local old = state.percent / 100
  state.percent = MG.Clamp(percent, MG.Limit(state))
  local new = state.percent / 100
  ax, ay = tonumber(ax) or 0.5, tonumber(ay) or 0.5
  state.x = MG.ClampOffset(ax - (ax - state.x) * new / old, new)
  state.y = MG.ClampOffset(ay - (ay - state.y) * new / old, new)
end

function MG.PanTo(state, x, y)
  local level = state.percent / 100
  state.x, state.y = MG.ClampOffset(x, level), MG.ClampOffset(y, level)
end

-- Zooms to `percent` (within the limit of the view) with the canvas point (fx, fy), fractions of the
-- canvas, in the middle of the viewport as far as the pan allows.
function MG.CenterOn(state, fx, fy, percent)
  state.percent = MG.Clamp(percent, MG.Limit(state))
  local level = state.percent / 100
  state.x = MG.ClampOffset(0.5 - (tonumber(fx) or 0.5) * level, level)
  state.y = MG.ClampOffset(0.5 - (tonumber(fy) or 0.5) * level, level)
end

-- ctx = {
--   viewport, canvas       the clipping frame and the (bigger) map frame inside it
--   views                  optional list of the view names this host zooms (default MG.VIEWS)
--   view()                 the view that is shown, a name of `views` (nil: nothing zooms, like the
--                          schematic island view)
--   barParent              optional, the frame the bar is a child of (default: the viewport); it is placed
--                          in the corner of the viewport either way
--   dragAllowed()          false while a click on the map means something else (marker mode)
--   changed()              lays the page out again after a zoom step
--   moved()                repaints what depends on the visible part (pins) while the map is dragged
--   blocked()              optional, a locale key while zooming is not allowed (the host knows why): wheel
--                          and keys do nothing, the bar is dimmed and its tooltips give the reason
-- }
-- Returns the controller: state (of the shown view), Active, Percent, Place, Window, Reset, ResetView,
-- SetMax, CenterOn, Refresh, In, Out, Wheel, Key, WasDrag, bar.
function MG.Attach(ctx)
  local viewport, canvas = ctx.viewport, ctx.canvas
  local L = ns.L
  local keys = ctx.views or MG.VIEWS
  local views = MG.NewViews(keys)
  local state = views[keys[1]]
  local ctl = { state = state, views = views }
  if viewport.SetClipsChildren then
    viewport:SetClipsChildren(true)
  end

  -- Takes the state of the shown view; answers its name, nil while no view zooms.
  local function sync()
    local key = ctx.view()
    if key and views[key] then
      state = views[key]
      ctl.state = state
      return key
    end
  end

  function ctl.Active()
    return sync() ~= nil
  end

  function ctl.Percent()
    return ctl.Active() and state.percent or MG.MIN
  end

  -- Bar ----------------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, ctx.barParent or viewport)
  bar:SetFrameLevel(viewport:GetFrameLevel() + 300)
  bar:SetSize(2 * MG.BUTTON + MG.VALUE_W + 4, MG.BUTTON + 4)
  bar:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -MG.INSET, MG.INSET)
  -- Mouse on: a click between the buttons must not fall through and open a zone.
  bar:EnableMouse(true)
  W.Fill(bar, "surface2", 0.9)
  W.Border(bar, "white", 0.3)
  ctl.bar = bar

  -- The locale key of the reason zooming is off right now, else nil.
  function ctl.Blocked()
    return ctx.blocked and ctx.blocked() or nil
  end

  local function change(percent, ax, ay)
    if ctl.Blocked() then
      return
    end
    MG.Zoom(state, percent, ax, ay)
    ctx.changed()
  end

  function ctl.In()
    sync()
    change(state.percent + MG.STEP)
  end

  function ctl.Out()
    sync()
    change(state.percent - MG.STEP)
  end

  -- 100 percent in the shown view only; the caller lays the page out.
  function ctl.ResetShown()
    if sync() then
      MG.ResetState(state)
    end
  end

  -- Back to 100 percent without a layout, in every view (page shown again, other tab).
  function ctl.Reset()
    for _, key in ipairs(keys) do
      MG.ResetState(views[key])
    end
  end

  -- Highest zoom of a view (the picture decides, see MG.MaxPercent); a zoom above it is taken back.
  function ctl.SetMax(key, max)
    local view = views[key]
    if view then
      view.max = max
      if view.percent > MG.Limit(view) then
        MG.Zoom(view, MG.Limit(view))
      end
    end
  end

  -- The shown view at `percent` with the canvas point (fx, fy) in the middle; the caller lays out.
  function ctl.CenterOn(fx, fy, percent)
    if sync() and not ctl.Blocked() then
      MG.CenterOn(state, fx, fy, percent)
    end
  end

  -- The same for one view (another zone opened).
  function ctl.ResetView(key)
    if views[key] then
      MG.ResetState(views[key])
    end
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
    tooltipText = function()
      local why = ctl.Blocked()
      return L[why or "map.mag.tip"]
    end,
    onClick = function()
      if not ctl.Blocked() then
        ctl.ResetShown()
        ctx.changed()
      end
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

  -- While zooming is blocked the tooltip of a step button names the reason below its title.
  for _, b in ipairs({ bar.out, bar.zoomIn }) do
    b:HookScript("OnEnter", function(self)
      local why = ctl.Blocked()
      if why then
        ns.ShowTooltip(self, L[self.fgNameKey], L[why])
      end
    end)
  end

  local function paintBar()
    local active = ctl.Active()
    bar:SetShown(active)
    bar.value.text:SetText(string.format("%d %%", state.percent))
    local free = ctl.Blocked() == nil
    bar.out:SetEnabled(free and state.percent > MG.MIN)
    bar.zoomIn:SetEnabled(free and state.percent < MG.Limit(state))
    bar.value:SetEnabled(free)
  end

  -- Repaints the bar after a change of the limit or of the block (combat started or ended).
  function ctl.Refresh()
    paintBar()
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
  -- The wheel handler of the nearest ancestor (page scroll, window zoom), or nil.
  local function ancestorWheel()
    local p = viewport:GetParent()
    while p do
      local handler = p.GetScript and p:GetScript("OnMouseWheel")
      if handler then
        return p, handler
      end
      p = p:GetParent()
    end
  end

  -- The window zoom key (a registry action) hands the turn on, so the zoom of the window keeps working over
  -- the picture. Without a key the window zoom has no gesture to hand on.
  function ctl.Wheel(delta)
    if not ctl.Active() or not tonumber(delta) or delta == 0 then
      return
    end
    if ns.Keys.Get("windowScale") ~= "none" and ns.Keys.Matches("windowScale") then
      local owner, handler = ancestorWheel()
      if handler then
        handler(owner, delta)
      end
      return
    end
    if ctl.Blocked() then
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

  -- Keys of the shown view: + and - zoom, the arrows move the map, 0 puts it back. True when the key
  -- did something, so the caller keeps it from the game; a key that would change nothing stays free.
  function ctl.Key(key)
    if not ctl.Active() then
      return false
    end
    if ctl.Blocked() then
      return false
    end
    if key == "=" or key == "+" or key == "NUMPADPLUS" then
      if state.percent >= MG.Limit(state) then
        return false
      end
      ctl.In()
      return true
    elseif key == "-" or key == "NUMPADMINUS" then
      if state.percent <= MG.MIN then
        return false
      end
      ctl.Out()
      return true
    elseif state.percent <= MG.MIN then
      return false
    elseif key == "0" or key == "NUMPAD0" then
      ctl.ResetShown()
      ctx.changed()
      return true
    end
    local dx, dy = 0, 0
    if key == "LEFT" then
      dx = MG.PAN_STEP
    elseif key == "RIGHT" then
      dx = -MG.PAN_STEP
    elseif key == "UP" then
      dy = MG.PAN_STEP
    elseif key == "DOWN" then
      dy = -MG.PAN_STEP
    else
      return false
    end
    local vw, vh = viewport:GetWidth(), viewport:GetHeight()
    MG.PanTo(state, state.x + dx, state.y + dy)
    ctl.Place(vw, vh)
    ctx.moved()
    return true
  end

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
    if ctl.Blocked() then
      return
    end
    ctl.drag = { cx = cx, cy = cy, x = state.x, y = state.y, view = sync() }
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
    if sync() ~= d.view then
      ctl.drag = nil
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
