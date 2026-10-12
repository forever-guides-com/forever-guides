-- The computed route on the map canvas: one polyline per leg out of a pooled set of Line
-- objects (never more than MR.MAX_LINES), a line style per transport (color alone never carries
-- the meaning), a direction arrow in the middle of every leg and numbered stops. Pure helpers
-- first (styles, dash plan, line budget, edge point), then Attach, which draws. MapPage.lua
-- hands in what only it knows (positions per view, zone, names) through the Attach context.
local _, ns = ...
local W, L, Theme, MI = ns.W, ns.L, ns.Theme, ns.MapIcons

local MR = {}
ns.MapRoute = MR

MR.MAX_LINES = 400
MR.HIT = 24 -- click and hover area of stops and legs, never smaller than the 24 px target size

local STOP, STOP_OFFSET = 18, 10
local ARROW, EDGE_MIN, EDGE_INSET = 7, 30, 8
local LABEL_MAX = 140
local SCALES = { 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64 }

ns.AddLocale("enUS", {
  ["map.route.stopTip"] = "Stop %d of %d",
})

ns.AddLocale("deDE", {
  ["map.route.stopTip"] = "Halt %d von %d",
})

-- Styles ---------------------------------------------------------------------------------------
-- pattern = alternating on/off lengths in px (nil = solid), shadow = dark underline for contrast,
-- jump = the leg is a jump (portal, teleport, spell): dotted with a ring at both ends.
MR.STYLES = {
  flight = { kind = "solid", token = "actionHi", shadow = true },
  boat = { kind = "dash", token = "info", pattern = { 12, 7 }, shadow = true },
  zeppelin = { kind = "dashdot", token = "warning", pattern = { 12, 5, 3, 5 }, shadow = true },
  tram = { kind = "longdash", token = "accent", pattern = { 20, 6 }, shadow = true },
  portal = { kind = "dot", token = "accent2", pattern = { 3, 9 }, jump = true },
  teleport = { kind = "dot", token = "accent2", pattern = { 3, 9 }, jump = true },
  spell = { kind = "dot", token = "accent2", pattern = { 3, 9 }, jump = true },
  walk = { kind = "thin", token = "textSecondary", pattern = { 5, 5 }, thin = true },
}

function MR.Style(mode)
  return MR.STYLES[mode] or MR.STYLES.walk
end

-- Line thickness: 2 px on a small map, 3 px on a wide one, walking stays thin.
function MR.Thickness(canvasWidth, style)
  if style and style.thin then
    return 1
  end
  return (tonumber(canvasWidth) or 0) >= 700 and 3 or 2
end

-- The drawn parts of a leg of `len` px as { { from, to }, ... } offsets along it. A solid leg is
-- one part, a pattern repeats on, off, on, off ... with every length times `scale`.
function MR.Dashes(len, pattern, scale)
  if not pattern then
    return len >= 1 and { { 0, len } } or {}
  end
  local out, at, i = {}, 0, 1
  scale = scale or 1
  while at < len do
    local step = pattern[i] * scale
    if i % 2 == 1 then
      out[#out + 1] = { at, math.min(at + step, len) }
    end
    at = at + step
    i = i % #pattern + 1
  end
  return out
end

-- How many lines a leg costs at a pattern scale: its parts (twice with the shadow) and the arrow.
local function legCost(leg, scale)
  local parts = #MR.Dashes(leg.len, leg.style.pattern, scale)
  return parts * (leg.style.shadow and 2 or 1) + (leg.arrow and 2 or 0)
end

-- Fits legs (each { len, style, arrow }) into `budget` lines: the coarsest pattern scale that is
-- needed (dashes get longer, never more numerous), and when even that does not fit, only the
-- first legs. Returns { scale, count (legs drawn), capped, lines }.
function MR.Plan(legs, budget)
  budget = budget or MR.MAX_LINES
  local function total(scale)
    local sum = 0
    for _, leg in ipairs(legs) do
      sum = sum + legCost(leg, scale)
    end
    return sum
  end
  for _, scale in ipairs(SCALES) do
    local sum = total(scale)
    if sum <= budget then
      return { scale = scale, count = #legs, capped = false, lines = sum }
    end
  end
  local scale, used, count = SCALES[#SCALES], 0, 0
  for i, leg in ipairs(legs) do
    local cost = legCost(leg, scale)
    if used + cost > budget then
      break
    end
    used, count = used + cost, i
  end
  return { scale = scale, count = count, capped = true, lines = used }
end

-- Where a ray from (px, py) along (dx, dy) leaves the canvas rectangle shrunk by `inset`.
function MR.EdgePoint(px, py, dx, dy, w, h, inset)
  inset = inset or 0
  local loX, hiX, loY, hiY = inset, w - inset, inset, h - inset
  px, py = math.max(loX, math.min(hiX, px)), math.max(loY, math.min(hiY, py))
  if math.abs(dx) < 1e-9 and math.abs(dy) < 1e-9 then
    dx, dy = 0, -1
  end
  local t = math.huge
  if dx > 1e-9 then
    t = math.min(t, (hiX - px) / dx)
  elseif dx < -1e-9 then
    t = math.min(t, (loX - px) / dx)
  end
  if dy > 1e-9 then
    t = math.min(t, (hiY - py) / dy)
  elseif dy < -1e-9 then
    t = math.min(t, (loY - py) / dy)
  end
  return px + dx * t, py + dy * t
end

-- A text key for a list of steps; the same route gives the same key.
function MR.Signature(steps)
  if not steps then
    return ""
  end
  local parts = {}
  for i, s in ipairs(steps) do
    parts[i] = s.from .. ">" .. s.to .. ":" .. s.mode
  end
  return table.concat(parts, "|")
end

-- A small picture of the style for the step list: { { x, w }, ... } inside `width` px.
function MR.Swatch(style, width)
  local out = {}
  for i, d in ipairs(MR.Dashes(width, style.pattern, 0.6)) do
    out[i] = { d[1], d[2] - d[1] }
  end
  return out
end

-- Attach -------------------------------------------------------------------------------------
-- ctx = {
--   canvas
--   point(slug)         x, y in canvas px (y down) of a place on the current view, or nil
--   zone()              slug of the open zone, nil on the world, island and flat views
--   inZone(slug)        true when the place belongs to the open zone
--   outside(slug)       x, y of a place outside the zone projected into the zone's canvas px
--                       (may lie beyond the canvas), or nil
--   name(slug)          localized place name
--   viewKey()           text that changes whenever positions change (view, tab, art)
--   picking()           true while a click on a place sets start/goal (no hover areas then)
--   legTip(i)           tooltip title and text of leg i
--   hoverChanged(i)     leg i is hovered (nil = none), from the map or from the list
-- }
-- Returns the controller: SetRoute, Paint, SetHover, Release, Used, Capped, plus the counters
-- rebuilds and restyles and the pools.
function MR.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { rebuilds = 0, restyles = 0, legs = {}, hover = nil, capped = false, steps = nil }
  local lines = { shadow = {}, main = {} }
  local lineUsed = { shadow = 0, main = 0 }
  local stops, hits, rings, labels = {}, {}, {}, {}
  local stopUsed, hitUsed, ringUsed, labelUsed = 0, 0, 0, 0
  local lastKey
  ctl.pool = { lines = lines, stops = stops, hits = hits, rings = rings, labels = labels }

  local overlay = CreateFrame("Frame", nil, canvas)
  overlay:SetAllPoints()
  overlay:SetFrameLevel(canvas:GetFrameLevel() + 14)
  ctl.overlay = overlay

  function ctl.Used()
    return lineUsed.shadow + lineUsed.main
  end

  function ctl.Capped()
    return ctl.capped
  end

  -- Pool ---------------------------------------------------------------------------------------
  local function acquireLine(shadow)
    if not canvas.CreateLine or ctl.Used() >= MR.MAX_LINES then
      return nil
    end
    local kind = shadow and "shadow" or "main"
    local n = lineUsed[kind] + 1
    local line = lines[kind][n]
    if not line then
      line = canvas:CreateLine(nil, "ARTWORK", nil, shadow and 1 or 2)
      lines[kind][n] = line
    end
    lineUsed[kind] = n
    return line
  end

  local function setHover(i)
    if ctl.hover == i then
      return
    end
    ctl.hover = i
    ctl.Restyle()
    if ctx.hoverChanged then
      ctx.hoverChanged(i)
    end
  end

  local function newHit()
    local b = CreateFrame("Button", nil, overlay)
    b:SetSize(MR.HIT, MR.HIT)
    b:SetScript("OnEnter", function(self)
      setHover(self.leg)
      if self.tipTitle then
        ns.ShowTooltip(self, self.tipTitle, self.tipText)
      end
    end)
    b:SetScript("OnLeave", function(self)
      ns.HideTooltip()
      if ctl.hover == self.leg then
        setHover(nil)
      end
    end)
    return b
  end

  local function newStop()
    local b = newHit()
    b.ring = b:CreateTexture(nil, "ARTWORK")
    b.ring:SetPoint("CENTER")
    b.ring:SetSize(STOP, STOP)
    b.fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.fill:SetPoint("CENTER")
    b.fill:SetSize(STOP - 4, STOP - 4)
    b.num = W.Text(b, { role = "micro", color = "text", justify = "CENTER" })
    b.num:SetPoint("CENTER")
    return b
  end

  local function newRing()
    local r = { outer = overlay:CreateTexture(nil, "ARTWORK"), inner = overlay:CreateTexture(nil, "ARTWORK", nil, 1) }
    return r
  end

  local function newLabel()
    local l = { bg = overlay:CreateTexture(nil, "ARTWORK", nil, 2) }
    l.text = W.Text(overlay, { role = "micro", color = "text", justify = "CENTER" })
    return l
  end

  local function release()
    for _, kind in ipairs({ "shadow", "main" }) do
      for i = 1, lineUsed[kind] do
        lines[kind][i]:Hide()
      end
      lineUsed[kind] = 0
    end
    for i = 1, stopUsed do
      stops[i]:Hide()
    end
    for i = 1, hitUsed do
      hits[i]:Hide()
    end
    for i = 1, ringUsed do
      rings[i].outer:Hide()
      rings[i].inner:Hide()
    end
    for i = 1, labelUsed do
      labels[i].bg:Hide()
      labels[i].text:Hide()
    end
    stopUsed, hitUsed, ringUsed, labelUsed = 0, 0, 0, 0
    ctl.legs = {}
    ctl.capped = false
  end

  -- Gives every line back and forgets what was drawn, so the next Paint builds again.
  function ctl.Release()
    release()
    lastKey = nil
  end

  -- Styling ------------------------------------------------------------------------------------
  local function paintPart(part, lit, dim)
    local thick = part.thick + (lit and 2 or 0)
    part.line:SetThickness(thick)
    if part.role == "shadow" then
      part.line:SetColorTexture(Theme.color("bg", lit and 0.9 or (dim and 0.2 or 0.7)))
    else
      part.line:SetColorTexture(Theme.color(part.token, lit and 1 or (dim and 0.35 or 0.9)))
    end
  end

  local function restyleAll()
    for i, leg in pairs(ctl.legs) do
      local lit = ctl.hover == i
      local dim = ctl.hover ~= nil and not lit
      for _, part in ipairs(leg.parts) do
        paintPart(part, lit, dim)
      end
    end
  end

  -- Hover only changes thickness and brightness of the lines that exist, nothing is rebuilt.
  function ctl.Restyle()
    ctl.restyles = ctl.restyles + 1
    restyleAll()
  end

  function ctl.SetHover(i)
    setHover(i)
  end

  -- Drawing ------------------------------------------------------------------------------------
  local function addLine(leg, role, ax, ay, bx, by, thick, token)
    local line = acquireLine(role == "shadow")
    if not line then
      return
    end
    line:ClearAllPoints()
    line:SetStartPoint("TOPLEFT", canvas, ax, -ay)
    line:SetEndPoint("TOPLEFT", canvas, bx, -by)
    line:Show()
    local part = { line = line, role = role, thick = thick, token = token }
    leg.parts[#leg.parts + 1] = part
    paintPart(part, false, false)
  end

  local function addLabel(text, x, y, cw, ch)
    labelUsed = labelUsed + 1
    local l = labels[labelUsed]
    if not l then
      l = newLabel()
      labels[labelUsed] = l
    end
    W.SetText(l.text, nil, text)
    local tw = math.min(math.ceil(l.text:GetStringWidth()), LABEL_MAX)
    local th = math.ceil(l.text:GetStringHeight())
    local bw, bh = tw + 8, th + 4
    local cx = math.max(bw / 2, math.min(cw - bw / 2, x))
    local cy = math.max(bh / 2, math.min(ch - bh / 2, y))
    l.text:SetWidth(tw)
    l.text:ClearAllPoints()
    l.text:SetPoint("CENTER", canvas, "TOPLEFT", cx, -cy)
    l.bg:ClearAllPoints()
    l.bg:SetPoint("CENTER", canvas, "TOPLEFT", cx, -cy)
    l.bg:SetSize(bw, bh)
    l.bg:SetColorTexture(Theme.color("bg", 0.8))
    l.bg:Show()
    l.text:Show()
    return bw, bh
  end

  local function addRing(x, y, token)
    ringUsed = ringUsed + 1
    local r = rings[ringUsed]
    if not r then
      r = newRing()
      rings[ringUsed] = r
    end
    local disc = MI.DiscKnown()
    for _, tex in ipairs({ r.outer, r.inner }) do
      tex:ClearAllPoints()
      tex:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
    end
    r.outer:SetSize(14, 14)
    r.inner:SetSize(8, 8)
    MI.Paint(r.outer, disc, Theme.color(token))
    MI.Paint(r.inner, disc, Theme.color("bg", 0.95))
    r.outer:Show()
    r.inner:Show()
  end

  local function addHit(leg, x, y)
    hitUsed = hitUsed + 1
    local b = hits[hitUsed]
    if not b then
      b = newHit()
      hits[hitUsed] = b
    end
    b.leg = leg.i
    b.tipTitle, b.tipText = ctx.legTip(leg.i)
    b:ClearAllPoints()
    b:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
    b:EnableMouse(not ctx.picking())
    b:Show()
  end

  -- The chevron of a direction arrow: two lines back from the tip.
  local function addArrow(leg, tx, ty, ux, uy, token)
    local nx, ny = -uy, ux
    local bx, by = tx - ux * ARROW, ty - uy * ARROW
    addLine(leg, "arrow", bx + nx * ARROW * 0.6, by + ny * ARROW * 0.6, tx, ty, 2, token)
    addLine(leg, "arrow", bx - nx * ARROW * 0.6, by - ny * ARROW * 0.6, tx, ty, 2, token)
  end

  -- A leg as geometry: full (both ends on the view) or edge (one end beyond the zone). Nil when
  -- it cannot be placed.
  local function resolve(i, step, zone, cw, ch)
    local ax, ay = ctx.point(step.from)
    local bx, by = ctx.point(step.to)
    if not zone then
      if ax and bx then
        return { i = i, ax = ax, ay = ay, bx = bx, by = by }
      end
      return nil
    end
    local inA, inB = ctx.inZone(step.from), ctx.inZone(step.to)
    if inA and inB then
      if ax and bx then
        return { i = i, ax = ax, ay = ay, bx = bx, by = by }
      end
      return nil
    end
    local here, there = nil, nil
    if inA and ax then
      here, there = { ax, ay, step.from }, step.to
    elseif inB and bx then
      here, there = { bx, by, step.to }, step.from
    end
    if not here or ctx.inZone(there) then
      return nil
    end
    local ox, oy = ctx.outside(there)
    local dx, dy = 0, -1
    if ox then
      dx, dy = ox - here[1], oy - here[2]
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-9 then
      dx, dy, len = 0, -1, 1
    end
    local ux, uy = dx / len, dy / len
    local ex, ey = MR.EdgePoint(here[1], here[2], ux, uy, cw, ch, EDGE_INSET)
    -- A place right at the edge still gets a visible stub.
    if math.sqrt((ex - here[1]) ^ 2 + (ey - here[2]) ^ 2) < EDGE_MIN then
      ex = math.max(0, math.min(cw, here[1] + ux * EDGE_MIN))
      ey = math.max(0, math.min(ch, here[2] + uy * EDGE_MIN))
    end
    local leg = { i = i, edge = true, label = ctx.name(there), farX = ex, farY = ey }
    if here[3] == step.from then
      leg.ax, leg.ay, leg.bx, leg.by = here[1], here[2], ex, ey
    else
      leg.ax, leg.ay, leg.bx, leg.by = ex, ey, here[1], here[2]
    end
    return leg
  end

  local function drawLeg(leg, scale, cw)
    local style = leg.style
    local ux, uy = (leg.bx - leg.ax) / math.max(leg.len, 1e-9), (leg.by - leg.ay) / math.max(leg.len, 1e-9)
    local thick = MR.Thickness(cw, style)
    leg.parts = {}
    ctl.legs[leg.i] = leg
    for _, d in ipairs(MR.Dashes(leg.len, style.pattern, scale)) do
      local x1, y1 = leg.ax + ux * d[1], leg.ay + uy * d[1]
      local x2, y2 = leg.ax + ux * d[2], leg.ay + uy * d[2]
      if style.shadow then
        addLine(leg, "shadow", x1, y1, x2, y2, thick + 2, nil)
      end
      addLine(leg, "main", x1, y1, x2, y2, thick, style.token)
    end
    local mx, my = (leg.ax + leg.bx) / 2, (leg.ay + leg.by) / 2
    if leg.arrow then
      addArrow(leg, mx + ux * ARROW * 0.5, my + uy * ARROW * 0.5, ux, uy, style.token)
    end
    if style.jump and not leg.edge then
      addRing(leg.ax, leg.ay, style.token)
      addRing(leg.bx, leg.by, style.token)
    end
    addHit(leg, mx, my)
  end

  local function drawStops(steps, zone, cw, ch)
    local total = #steps + 1
    for k = 1, total do
      local slug = k <= #steps and steps[k].from or steps[#steps].to
      local x, y = ctx.point(slug)
      if x and (not zone or ctx.inZone(slug)) then
        stopUsed = stopUsed + 1
        local b = stops[stopUsed]
        if not b then
          b = newStop()
          stops[stopUsed] = b
        end
        local arriving = steps[math.min(k, #steps)]
        local token = MR.Style(arriving.mode).token
        local disc = MI.DiscKnown()
        MI.Paint(b.ring, disc, Theme.color(token))
        MI.Paint(b.fill, disc, Theme.color("bg", 0.95))
        W.SetText(b.num, nil, tostring(k))
        b.leg = math.max(1, k - 1)
        b.tipTitle = ctx.name(slug)
        b.tipText = string.format(L["map.route.stopTip"], k, total)
        b:ClearAllPoints()
        b:SetPoint(
          "CENTER",
          canvas,
          "TOPLEFT",
          math.max(STOP / 2, math.min(cw - STOP / 2, x + STOP_OFFSET)),
          -math.max(STOP / 2, math.min(ch - STOP / 2, y - STOP_OFFSET))
        )
        b:EnableMouse(not ctx.picking())
        b:Show()
      end
    end
  end

  local function rebuild(cw, ch)
    ctl.rebuilds = ctl.rebuilds + 1
    release()
    local steps = ctl.steps
    if not steps or #steps == 0 or cw < 2 or ch < 2 then
      return
    end
    local zone = ctx.zone()
    local legs = {}
    for i, step in ipairs(steps) do
      local leg = resolve(i, step, zone, cw, ch)
      if leg then
        leg.style = MR.Style(step.mode)
        leg.len = math.sqrt((leg.bx - leg.ax) ^ 2 + (leg.by - leg.ay) ^ 2)
        leg.arrow = leg.len >= 14
        legs[#legs + 1] = leg
      end
    end
    local plan = MR.Plan(legs, MR.MAX_LINES)
    ctl.capped = plan.capped
    ctl.scale = plan.scale
    for k = 1, plan.count do
      drawLeg(legs[k], plan.scale, cw)
      if legs[k].edge then
        addLabel(legs[k].label, legs[k].farX, legs[k].farY, cw, ch)
      end
    end
    drawStops(steps, zone, cw, ch)
    restyleAll()
  end

  -- The route to draw (list of steps) or nil. The same route keeps what is drawn.
  function ctl.SetRoute(steps)
    ctl.steps = steps
    ctl.sig = MR.Signature(steps)
    if ctl.hover and not (steps and steps[ctl.hover]) then
      ctl.hover = nil
    end
  end

  -- Called after every canvas size change; builds only when the route, the view, the canvas size
  -- or the picking state changed since the last build.
  function ctl.Paint()
    if not canvas:IsVisible() then
      ctl.Release()
      return ctl.capped
    end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local key = table.concat({
      ctx.viewKey(),
      math.floor(cw),
      math.floor(ch),
      tostring(ctx.picking()),
      ctl.sig or "",
    }, "#")
    if key ~= lastKey then
      lastKey = key
      rebuild(cw, ch)
    end
    return ctl.capped
  end

  -- A map that shows again draws the route again, from the pool.
  canvas:HookScript("OnShow", function()
    ctl.Paint()
  end)

  -- Colors and text sizes come from the theme: a theme or language change draws once more.
  ns.Bind(overlay, function()
    lastKey = nil
    if ctl.steps then
      ctl.Paint()
    end
  end)

  return ctl
end
