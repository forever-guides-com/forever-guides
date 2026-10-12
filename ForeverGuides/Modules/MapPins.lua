-- Place pins on the map page canvas: one pooled button per place (canvas.dots[slug]) that
-- carries the symbol of its kind with the faction frame, the hover and selection glow, the
-- Start and Goal flags and a name label. Labels go through the collision plan of MapMarkers, in
-- the order Start, Goal, selection, hover, then kind and name. MapPage.lua hands in what only
-- it knows (positions, state, clicks) through the Attach context.
local _, ns = ...
local W, Theme, MI, MM = ns.W, ns.Theme, ns.MapIcons, ns.MapMarkers

local MP = {}
ns.MapPins = MP

MP.MIN_SIZE, MP.MAX_SIZE = 14, 22
-- Symbol size setting in percent of the size above (the page default is smaller than 100).
MP.SCALE_MIN, MP.SCALE_MAX, MP.SCALE_STEP, MP.SCALE_DEFAULT = 50, 200, 10, 70
-- From this magnification (percent) every place gets a name, like inside a zone.
MP.ALL_NAMES_FROM = 200
MP.HIT = 24 -- click area, never smaller than the 24 px target size
MP.DIM_ALPHA = 0.25

local WIDTH_PER_PX = 40 -- canvas width that earns one pixel of pin size
local LABEL_GAP, LABEL_MAX, LABEL_PAD = 3, 120, 2
local WINDOW_MARGIN = LABEL_MAX + 24
local FLAG_H, FLAG_PAD = 13, 8
local DASH_PAD, DASH_LEN = 5, 0.4
local GLOW_HOVER, GLOW_SELECTED = 0.4, 0.2

ns.AddLocale("enUS", {
  ["map.flag.start"] = "Start",
  ["map.flag.dest"] = "Goal",
  ["map.pin.neutral"] = "Both factions",
})

ns.AddLocale("deDE", {
  ["map.flag.start"] = "Start",
  ["map.flag.dest"] = "Ziel",
  ["map.pin.neutral"] = "Beide Fraktionen",
})

-- Pure logic ---------------------------------------------------------------------------

-- The symbol size setting as a valid step; anything that is not a number gives the default.
function MP.ClampScale(value)
  local v = tonumber(value)
  if not v or v ~= v then
    return MP.SCALE_DEFAULT
  end
  v = math.floor(v / MP.SCALE_STEP + 0.5) * MP.SCALE_STEP
  return math.max(MP.SCALE_MIN, math.min(MP.SCALE_MAX, v))
end

-- Pin edge in pixels for a map width: 14 on a small map up to 22 on a big one, times the size
-- setting (percent, nil = 100).
function MP.PinSize(canvasWidth, scale)
  local size = math.floor((tonumber(canvasWidth) or 0) / WIDTH_PER_PX)
  size = math.max(MP.MIN_SIZE, math.min(MP.MAX_SIZE, size))
  if scale == nil then
    return size
  end
  return math.floor(size * MP.ClampScale(scale) / 100 + 0.5)
end

-- Kinds that carry a name on the world view without a zone open: the cities and the transport
-- hubs the route planner is about. The many flight masters are named inside a zone or when the
-- map is magnified.
local WORLD_NAMES = { city = true, zeppelinTower = true, harbor = true, tram = true, portal = true }

-- True when a place asks for a name label. Start, Goal, selection and hover always do (they are
-- what the player is working with); the rest follows the names switch.
function MP.WantsName(role, kind, dimmed, namesOn, allNames)
  if dimmed then
    return false
  end
  if role ~= nil then
    return true
  end
  return namesOn and (allNames or WORLD_NAMES[MI.KindOf(kind)] == true) or false
end

-- "start" | "dest" | "selected" | "hover" | nil, strongest first.
function MP.RoleOf(state, slug)
  return (state.start == slug and "start")
    or (state.dest == slug and "dest")
    or (state.selected == slug and "selected")
    or (state.hover == slug and "hover")
    or nil
end

local ROLE_RANK = { start = 1, dest = 2, selected = 3, hover = 4 }

-- Priority order of the pins, which is also the order of the labels: places the filter dims
-- come last, then Start, Goal, selection, hover, then the kind (cities first) and the name.
-- items[i] = { slug, name, kind, role?, dimmed? }
function MP.Order(items)
  table.sort(items, function(a, b)
    local da, db = a.dimmed == true, b.dimmed == true
    if da ~= db then
      return db
    end
    local ra, rb = ROLE_RANK[a.role] or 9, ROLE_RANK[b.role] or 9
    if ra ~= rb then
      return ra < rb
    end
    local ka, kb = MI.Rank(a.kind), MI.Rank(b.kind)
    if ka ~= kb then
      return ka < kb
    end
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then
      return na < nb
    end
    return a.slug < b.slug
  end)
end

-- Drawing ------------------------------------------------------------------------------

-- A dashed frame around a place pin (eight short strokes, two per side) for a position that
-- is only estimated; the strokes are created on first use. on == false hides them.
local function paintDashed(dot, on, token, size)
  if not on then
    for _, t in ipairs(dot.dashes or {}) do
      t:Hide()
    end
    return
  end
  if not dot.dashes then
    dot.dashes = {}
    for i = 1, 8 do
      dot.dashes[i] = dot:CreateTexture(nil, "OVERLAY")
    end
  end
  local side = size + 2 * DASH_PAD
  local len = math.max(2, math.floor(side * DASH_LEN))
  -- { point, w, h } per stroke: two on the top and bottom, two on the left and right.
  local strokes = {
    { "TOPLEFT", len, 1 },
    { "TOPRIGHT", len, 1 },
    { "BOTTOMLEFT", len, 1 },
    { "BOTTOMRIGHT", len, 1 },
    { "TOPLEFT", 1, len },
    { "BOTTOMLEFT", 1, len },
    { "TOPRIGHT", 1, len },
    { "BOTTOMRIGHT", 1, len },
  }
  for i, st in ipairs(strokes) do
    local t = dot.dashes[i]
    local sx = st[1]:find("LEFT") and -DASH_PAD or DASH_PAD
    local sy = st[1]:find("TOP") and DASH_PAD or -DASH_PAD
    t:ClearAllPoints()
    t:SetPoint(st[1], dot.badge.box, st[1], sx, sy)
    t:SetSize(st[2], st[3])
    t:SetColorTexture(Theme.color(token))
    t:Show()
  end
end

-- The Start or Goal flag above the pin (below it when the pin sits at the top edge), shifted
-- sideways so it stays on the canvas. key == nil hides it.
local function paintFlag(dot, key, token, x, y, size, cw)
  dot.flagBg:SetShown(key ~= nil)
  dot.flagText:SetShown(key ~= nil)
  if not key then
    return
  end
  W.SetText(dot.flagText, key)
  local w = math.ceil(dot.flagText:GetStringWidth()) + FLAG_PAD
  local dx = math.max(w / 2 - x, 0) - math.max(x + w / 2 - cw, 0)
  dot.flagBg:SetSize(w, FLAG_H)
  dot.flagBg:SetColorTexture(Theme.color(token))
  dot.flagBg:ClearAllPoints()
  if y - size / 2 - MI.RING - 1 - FLAG_H >= 0 then
    dot.flagBg:SetPoint("BOTTOM", dot.badge.box, "TOP", dx, MI.RING + 1)
  else
    dot.flagBg:SetPoint("TOP", dot.badge.box, "BOTTOM", dx, -(MI.RING + 1))
  end
  dot.flagText:ClearAllPoints()
  dot.flagText:SetPoint("CENTER", dot.flagBg, "CENTER")
end

-- ctx = {
--   canvas                      its .dots table is the pool, keyed by place slug
--   data()                      the travel data
--   state                       { start, dest, selected, hover } place slugs
--   filter()                    returns visible(node), false for a place the filters hide
--   pos(node)                   x, -y in canvas pixels, nil when the view has no spot for it
--   name(slug), tip(node)       tooltip title and text
--   dim()                       dim the hidden places instead of dropping them
--   zoomed()                    true inside a zone (every place gets a label then)
--   symbols(), names()          optional: the switches of the page (nil = on)
--   scale()                     optional: symbol size in percent (nil = 100)
--   window()                    optional: left, top, width, height of the visible map part in
--                               canvas px (a magnified map); pins outside it are not drawn
--   percent()                   optional: magnification in percent (nil = 100)
--   markers                     the MapMarkers controller (mode, Points)
--   onClick(slug, button), hover(slug), unhover(slug)
-- }
-- Returns the controller: Paint, dots.
function MP.Attach(ctx)
  local canvas = ctx.canvas
  local dots = canvas.dots
  local ctl = { dots = dots }

  local function newDot(n)
    local dot = CreateFrame("Button", nil, canvas)
    dot:SetSize(MP.HIT, MP.HIT)
    dot.badge = MI.NewBadge(dot)
    dot.badge.box:SetPoint("CENTER")
    dot.labelBg = dot:CreateTexture(nil, "OVERLAY", nil, -2)
    dot.label = W.Text(dot, { role = "micro", color = "text" })
    dot.flagBg = dot:CreateTexture(nil, "OVERLAY", nil, -1)
    dot.flagText = W.Text(dot, { role = "micro", color = "bg", justify = "CENTER" })
    dot:SetScript("OnEnter", function(self)
      ctx.hover(self.slug)
      ns.ShowTooltip(self, ctx.name(self.slug), ctx.tip(self.node))
    end)
    dot:SetScript("OnLeave", function(self)
      ns.HideTooltip()
      ctx.unhover(self.slug)
    end)
    dot:SetScript(
      "OnClick",
      ns.Wrap("map-dot", function(self, button)
        ctx.onClick(self.slug, button)
      end)
    )
    dot.slug, dot.node = n.s, n
    dots[n.s] = dot
    return dot
  end

  -- Repaints every pin; pins come from the pool and a pin that stays shown is never hidden
  -- and shown again (a hover repaint must not drop the pin under the cursor).
  function ctl.Paint()
    local data = ctx.data()
    if not data then
      return
    end
    local st, dim, zoomed = ctx.state, ctx.dim(), ctx.zoomed()
    local wl, wt, cw, ch = 0, 0, canvas:GetWidth(), canvas:GetHeight()
    if ctx.window then
      wl, wt, cw, ch = ctx.window()
    end
    local size = MP.PinSize(cw, ctx.scale and ctx.scale() or nil)
    local namesOn = not ctx.names or ctx.names()
    local allNames = zoomed or (ctx.percent ~= nil and ctx.percent() >= MP.ALL_NAMES_FROM)
    local visibleFn, items, used = ctx.filter(), {}, {}
    if ctx.symbols and not ctx.symbols() then
      visibleFn = function()
        return false
      end
      dim = false
    end
    for _, n in ipairs(data.nodes) do
      local visible = visibleFn(n)
      local x, y
      if visible or dim then
        x, y = ctx.pos(n)
      end
      -- Beyond the visible part (plus the room a symbol and its name need) nothing is drawn.
      if x and (x < wl - WINDOW_MARGIN or x > wl + cw + WINDOW_MARGIN) then
        x = nil
      elseif y and (-y < wt - WINDOW_MARGIN or -y > wt + ch + WINDOW_MARGIN) then
        x = nil
      end
      if x then
        used[n.s] = true
        items[#items + 1] = {
          dot = dots[n.s] or newDot(n),
          node = n,
          slug = n.s,
          kind = n.k,
          name = ctx.name(n.s),
          x = x,
          y = -y,
          dimmed = not visible,
          role = visible and MP.RoleOf(st, n.s) or nil,
        }
      end
    end
    for slug, dot in pairs(dots) do
      if not used[slug] then
        dot:Hide()
      end
    end
    MP.Order(items)

    local level = canvas:GetFrameLevel()
    local plan = {}
    for i, it in ipairs(items) do
      local dot, n = it.dot, it.node
      dot:SetAlpha(it.dimmed and MP.DIM_ALPHA or 1)
      dot:EnableMouse(not ctx.markers.mode and not it.dimmed)
      -- A city sits above the small pins around it, so its symbol and name stay readable.
      local isCity = MI.KindOf(it.kind) == "city"
      local lift = (it.role == "hover" and 12) or (it.role and 8) or (it.dimmed and 1) or (isCity and 4) or 2
      dot:SetFrameLevel(level + lift)
      dot.filtered = it.dimmed
      dot.badge:Set(n.k, n.f, size, n.est)
      dot.badge:Select(not it.dimmed and st.selected == it.slug)
      dot.badge:Highlight(it.role == "hover" and GLOW_HOVER or (it.role == "selected" and GLOW_SELECTED or 0))
      paintDashed(dot, n.est == true and zoomed and not it.dimmed, dot.badge.token, size)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", canvas, "TOPLEFT", it.x, -it.y)
      dot:Show()
      -- Labels: see MP.WantsName; the plan works relative to the visible part of the map.
      local wants = MP.WantsName(it.role, it.kind, it.dimmed, namesOn, allNames)
      local item = { x = it.x - wl, y = it.y - wt, w = 0, h = 0, skip = not wants, force = isCity }
      if wants then
        W.SetText(dot.label, nil, it.name)
        item.w = math.min(math.ceil(dot.label:GetStringWidth()), LABEL_MAX)
        item.h = math.ceil(dot.label:GetStringHeight())
      end
      plan[i] = item
    end

    local offset = size / 2 + MI.RING + LABEL_GAP
    local obstacles = {}
    for i, p in ipairs(ctx.markers.Points()) do
      obstacles[i] = { x = p.x - wl, y = p.y - wt }
    end
    local sides = MM.PlanLabels(plan, cw, ch, size / 2 + MI.RING + 1, LABEL_GAP, obstacles)
    for i, it in ipairs(items) do
      local dot, side = it.dot, sides[i]
      dot.label:SetShown(side ~= false)
      dot.labelBg:SetShown(side ~= false)
      if side then
        dot.label:SetWidth(plan[i].w)
        dot.label:ClearAllPoints()
        if side == "right" then
          dot.label:SetPoint("LEFT", dot, "CENTER", offset, 0)
          dot.label:SetJustifyH("LEFT")
        else
          dot.label:SetPoint("RIGHT", dot, "CENTER", -offset, 0)
          dot.label:SetJustifyH("RIGHT")
        end
        dot.labelBg:ClearAllPoints()
        dot.labelBg:SetPoint("TOPLEFT", dot.label, "TOPLEFT", -LABEL_PAD, LABEL_PAD)
        dot.labelBg:SetPoint("BOTTOMRIGHT", dot.label, "BOTTOMRIGHT", LABEL_PAD, -LABEL_PAD)
        dot.labelBg:SetColorTexture(Theme.color("bg", 0.6))
      end
      local key, token
      if not it.dimmed and st.start == it.slug then
        key, token = "map.flag.start", "success"
      elseif not it.dimmed and st.dest == it.slug then
        key, token = "map.flag.dest", "warning"
      end
      paintFlag(dot, key, token, it.x, it.y, size, cw)
    end
  end

  return ctl
end
