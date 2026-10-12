-- Raster widget for drawings: paints a DrawingLogic drawing at a given scale
-- (pixels per cell) with pooled solid-color textures. The bitmap is never
-- stored as textures per cell: every row is cut into runs of equal color and
-- each run is one texture (cells of the background color get none, one
-- texture behind everything shows it). Edits repaint only the bands they touch.
-- Preview changesets of the soft-edge tools carry colors that are not in the
-- palette yet: ch.virtual[-index] (see DrawingLogic).
-- Overlays (selection marquee, shape/move preview) use their own textures and
-- never touch the bitmap.
--
-- Background map. A drawing may carry the key of a map (d.map, see DrawingLogic cleanMap and
-- DrawingMap). The view lays its tiles (ns.MapReveal.DrawBase, one pooled texture per 256 px tile,
-- 12 to about 40 of them) under the cells, fitted undistorted into the sheet (MapRevealLogic.Fit),
-- on a dark ground, at the opacity of the map. Cells of the background color then show the map.
-- The tiles count into the budget below (V.Usage, Stats().map) and go back to the pool with the
-- cells when the view is hidden. A key this client cannot resolve shows the sheet without a map
-- (View.mapReason says why).
--
-- Render budget. Every texture costs frame time in the client, so a view has a
-- budget (V.BUDGET) and reduces detail instead of falling off a cliff.
-- Measured in the Forever client (build 70245, 1920x1080, UI scale 0.711),
-- rectangle textures on one frame:
--     2000 -> 56.8 fps    5000 -> 50.2    10000 -> 43.4    20000 -> 34.5    40000 -> 23.7
-- which is 17.6, 19.9, 23.0, 29.0 and 42.2 ms per frame: about 0.65 ms per 1000
-- textures on top of a 58 to 60 fps baseline. The editor may use 16000 (about
-- 10 ms while it is open), a drawing window 3000 and all visible windows
-- together 6000, the page preview and the chat viewer 4000 each, and everything
-- visible at once at most 20000. Views are served first come, first served: a
-- view that is shown while others hold the budget gets what is left and
-- degrades further. A hidden view releases its textures into its pool (a hidden
-- view costs nothing), and closing or hiding one lets squeezed views repaint.
--
-- When the exact picture (one texture per run per row) needs more textures than
-- the view may use, the display degrades step by step and stops at the first
-- step that fits (the stored drawing is never touched):
--   merged  rows are cut into bands of V.BAND_ROWS and equal runs of adjacent
--           rows (same columns, same color) become one taller rectangle. Lossless.
--   culled  when the view knows its scroll viewport (SetViewport) and the picture
--           is zoomed beyond it, only the bands and columns within one screen of
--           the viewport are painted and repainted on scroll. Lossless for what
--           is visible.
--   tones   soft-edge helper colors (d.auto) are mapped to fewer tones per channel
--           (V.TONES, 8, then 4, then 2) so neighbouring cells merge. Positions
--           stay, only color values change. A level is skipped when it would not
--           change any color.
--   step    last resort: every k-th cell in both directions (blocky picture).
-- The steps are kept while the drawing is edited (no flicker) and only go up.
-- Refresh(true) / Restore() evaluate from the start again, Stats().canRestore
-- tells whether the exact picture fits again.
-- opts: scale, grid, kind (budget group, see V.BUDGET), maxTextures (own cap),
-- skipBackground (see View:SetSkipBackground).
local _, ns = ...
local D = ns.DrawingLogic

local V = {
  -- Textures a view of that kind may use (per view); `windows` is the sum over
  -- all visible drawing windows, `global` the sum over everything visible.
  BUDGET = {
    editor = 16000,
    window = 3000,
    windows = 6000,
    page = 4000,
    viewer = 4000,
    global = 20000,
    -- Measured frame time per 1000 textures (ms), only used for explanations.
    msPer1000 = 0.65,
  },
  BAND_ROWS = 16,
  TONES = { 8, 4, 2 },
  MAX_OVERLAY = 4000,
  GRID_MIN_SCALE = 4,
  MAX_STEP = 16,
  -- Ground under a background map (gray level 0..1), so the tiles never blend into a white sheet.
  MAP_GROUND = 0.06,
  -- Tolerance (RGB distance) up to which a soft-edge cell takes the color of a
  -- neighbouring solid cell in the tones step, per tone level.
  SNAP = { [8] = 40, [4] = 110, [2] = math.huge },
  VIEWPORT_DELAY = 0.05,
}
ns.DrawingView = V

local View = {}
View.__index = View

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local BG = D.BACKGROUND
local SKIP = -1

-- Degradation levels in order (0-based). `band` is the number of sampled rows
-- that may merge into one rectangle, `cull` limits the picture to the viewport
-- window, `tones` quantizes soft-edge colors, `step` samples every k-th cell.
local STAGES = {
  [0] = { name = "exact", band = 1 },
  [1] = { name = "merged", band = V.BAND_ROWS, rgb = true },
  [2] = { name = "culled", band = V.BAND_ROWS, rgb = true, cull = true },
}
local TONE_FIRST = 3
for i, tones in ipairs(V.TONES) do
  STAGES[TONE_FIRST - 1 + i] = { name = "tones", band = V.BAND_ROWS, rgb = true, cull = true, tones = tones }
end
local TONE_LAST = TONE_FIRST - 1 + #V.TONES
local STEP = TONE_LAST + 1
STAGES[STEP] = { name = "step", band = V.BAND_ROWS, rgb = true, cull = true, tones = V.TONES[#V.TONES], step = true }
V.STEP_LEVEL = STEP

-- Every view (weak), for the budget accounting across views.
local views = setmetatable({}, { __mode = "k" })

-- Largest scale that fits w x h cells into maxW x maxH pixels. Whole numbers
-- keep the pixels sharp, below 1 the scale is fractional (never above the box).
function V.FitScale(w, h, maxW, maxH)
  local s = min(maxW / w, maxH / h)
  if s >= 1 then
    return floor(s)
  end
  return max(0.25, floor(s * 100) / 100)
end

-- Textures a visible view holds right now (bitmap, grid lines, map tiles and preview).
local function objectsOf(v)
  return v.active + v.gridShown + (v.mapShown or 0) + (v.overlayShown or 0)
end

-- Textures all visible views hold: { total, windows, kinds = { kind = n } }.
function V.Usage()
  local u = { total = 0, windows = 0, kinds = {} }
  for v in pairs(views) do
    if v.frame:IsVisible() then
      local n = objectsOf(v)
      u.total = u.total + n
      u.kinds[v.kind] = (u.kinds[v.kind] or 0) + n
      if v.kind == "window" then
        u.windows = u.windows + n
      end
    end
  end
  return u
end

-- How many bitmap textures `self` may use now: its own cap, limited by what the
-- other visible views leave of the global and of the window budget.
local function allowance(self)
  local others, windows = 0, 0
  for v in pairs(views) do
    if v ~= self and v.frame:IsVisible() then
      local n = objectsOf(v)
      others = others + n
      if v.kind == "window" then
        windows = windows + n
      end
    end
  end
  local a = min(self.cap, V.BUDGET.global - others - self.gridShown - (self.mapShown or 0))
  if self.kind == "window" then
    a = min(a, V.BUDGET.windows - windows)
  end
  return max(0, a)
end

local function rebalance(from)
  if V.rebalancing then
    return
  end
  V.rebalancing = true
  for v in pairs(views) do
    if v ~= from and v.squeezed and v.drawing and v.frame:IsVisible() then
      v:Refresh(true)
    end
  end
  V.rebalancing = false
end

function V.New(parent, opts)
  opts = opts or {}
  local frame = CreateFrame("Frame", nil, parent)
  local kind = V.BUDGET[opts.kind] and opts.kind or "viewer"
  local self = setmetatable({
    frame = frame,
    scale = opts.scale or 4,
    grid = opts.grid == true,
    kind = kind,
    cap = opts.maxTextures or V.BUDGET[kind],
    rows = {},
    free = {},
    made = 0,
    active = 0,
    k = 1,
    level = 0,
    gridShown = 0,
    overlay = {},
    gridTex = {},
  }, View)
  self.limit = self.cap
  self.bg = frame:CreateTexture(nil, "BACKGROUND")
  self.bg:SetAllPoints()
  self.bg:SetColorTexture(1, 1, 1, 1)
  self.skipBackground = opts.skipBackground == true
  self.bg:SetShown(not self.skipBackground)
  self.fill = frame:CreateTexture(nil, "OVERLAY", nil, 1)
  self.fill:SetColorTexture(1, 1, 1, 0.14)
  self.fill:Hide()
  self.edges = {}
  for i = 1, 4 do
    local e = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    e:SetColorTexture(1, 0.85, 0.2, 1)
    e:Hide()
    self.edges[i] = e
  end
  views[self] = true
  -- Hidden (also through a parent): hand the textures back, repaint on show.
  frame:HookScript("OnHide", function()
    self:Suspend()
  end)
  frame:HookScript("OnShow", function()
    if self.suspended and self.drawing then
      self:Refresh(true)
    end
  end)
  return self
end

-- Pixel position of cell boundary i (0 = left/top edge of the first cell).
local function edge(self, i)
  return floor(i * self.scale + 0.5)
end

-- Background map ---------------------------------------------------------------------

-- Background texture: the color of the sheet, a dark ground under a map, nothing when skipped.
local function paintGround(self)
  local d = self.drawing
  if self.mapArt then
    local g = V.MAP_GROUND
    self.bg:SetColorTexture(g, g, g)
    self.bg:Show()
    return
  end
  if d then
    local bg = d.palette[BG]
    self.bg:SetColorTexture(bg[1] / 255, bg[2] / 255, bg[3] / 255)
  end
  self.bg:SetShown(not self.skipBackground)
end

-- Lays the tiles of the map under the cells (or hides them). Runs before the budget is worked out.
local function paintMap(self)
  local d, MR = self.drawing, ns.MapReveal
  local art, reason
  if d and self.map and ns.DrawingMap then
    local resolved, _, why = ns.DrawingMap.Resolve(self.map)
    art, reason = resolved, why
  end
  self.mapReason = self.map and not art and (reason or "missing") or nil
  self.mapArt = art
  if not art then
    self.mapShown = 0
    -- Hidden and without its file, so a removed map does not stay in memory.
    MR.ReleaseTextures(self.frame)
    paintGround(self)
    return
  end
  local layer = art.layer
  local x, y, w, h = ns.MapRevealLogic.Fit(layer.layerWidth, layer.layerHeight, edge(self, d.w), edge(self, d.h))
  self.mapShown = MR.DrawBase(self.frame, art, { alpha = self.map.alpha / 100, box = { x = x, y = y, w = w, h = h } })
  paintGround(self)
end

local function newTexture(self, sublevel)
  local t = self.frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
  t:Hide()
  return t
end

local function acquire(self)
  local t = table.remove(self.free)
  if not t then
    if self.active >= self.limit then
      return nil
    end
    t = newTexture(self, 0)
    self.made = self.made + 1
  elseif self.active >= self.limit then
    self.free[#self.free + 1] = t
    return nil
  end
  self.active = self.active + 1
  return t
end

local function release(self, t)
  t:Hide()
  t.c = nil
  self.free[#self.free + 1] = t
  self.active = self.active - 1
end

local function releaseBand(self, b)
  local list = self.rows[b]
  if list then
    for i = #list, 1, -1 do
      release(self, list[i])
      list[i] = nil
    end
    self.rows[b] = nil
  end
end

local function releaseAll(self)
  for b in pairs(self.rows) do
    releaseBand(self, b)
  end
end

-- Planning ------------------------------------------------------------------------
-- A configuration (cfg) says how a drawing is cut into rectangles: bh = cells per
-- band, k = sampling step, keys = display key per palette index (SKIP: no
-- texture), color = rgb per key, x0..x1 / b0..b1 = columns and bands to paint.

local function quantize(v, tones)
  local steps = tones - 1
  return floor(floor(v / 255 * steps + 0.5) * 255 / steps + 0.5)
end

-- Display keys: the palette index itself (exact) or the packed rgb, so equal
-- colors of different entries merge. In the tones step soft-edge helper colors
-- (d.auto) are marked in `auto` and get their own key at `tones` levels per
-- channel, used when no neighbouring cell takes them over (see `plan`).
local function buildKeys(d, st)
  local keys, color, auto, hasAuto = {}, {}, {}, false
  for c, p in ipairs(d.palette) do
    if c == BG then
      keys[c] = SKIP
    elseif not st.rgb then
      keys[c] = c
      color[c] = { p[1] / 255, p[2] / 255, p[3] / 255 }
    else
      local r, g, b = p[1], p[2], p[3]
      if st.tones and D.isAuto(d, c) then
        r, g, b = quantize(r, st.tones), quantize(g, st.tones), quantize(b, st.tones)
        auto[c], hasAuto = true, true
      end
      local key = (r * 256 + g) * 256 + b
      keys[c] = key
      color[key] = color[key] or { r / 255, g / 255, b / 255 }
    end
  end
  return keys, color, auto, hasAuto
end

local function makeCfg(self, level, k)
  local d, st = self.drawing, STAGES[level]
  local step = st.step and k or 1
  local cfg = { level = level, k = step, bh = st.band * step, cull = st.cull == true, palN = #d.palette }
  cfg.keys, cfg.color, cfg.auto, cfg.hasAuto = buildKeys(d, st)
  cfg.key = level .. ":" .. step .. ":" .. (st.tones or 0)
  if st.tones then
    cfg.snap2 = V.SNAP[st.tones] ^ 2
    cfg.dist = {}
  end
  local w, h, bh = d.w, d.h, cfg.bh
  local cx0, cx1, cy0, cy1 = 1, w, 1, h
  local vp = self.vp
  if cfg.cull and vp then
    -- The viewport plus one screen of margin on every side.
    local s, vw, vh = self.scale, vp.r - vp.l, vp.b - vp.t
    cx0, cx1 = max(1, floor((vp.l - vw) / s) + 1), min(w, ceil((vp.r + vw) / s))
    cy0, cy1 = max(1, floor((vp.t - vh) / s) + 1), min(h, ceil((vp.b + vh) / s))
    cfg.reduced = cx0 > 1 or cx1 < w or cy0 > 1 or cy1 < h
  end
  cfg.x0, cfg.x1 = floor((cx0 - 1) / step) * step + 1, cx1
  cfg.b0, cfg.b1 = floor((cy0 - 1) / bh) + 1, floor((cy1 - 1) / bh) + 1
  if cx1 < cx0 or cy1 < cy0 then
    cfg.b1 = cfg.b0 - 1
  end
  return cfg
end

-- Scratch arrays of the planner (one band at a time, never kept).
local PX0, PX1, PY0, PY1, PK = {}, {}, {}, {}, {}
local openIdx, openStamp, rowKeys, serial = {}, {}, {}, 0

-- The key of soft-edge cell c (palette) between its neighbours on the row: the
-- color of the closer non-soft neighbour (a user color or the background) when
-- it lies within the tolerance of the tones step, else the cell's own tone.
local function snapKey(cfg, pal, cells, i, c, left, right)
  local keys, auto, dist = cfg.keys, cfg.auto, cfg.dist
  local best, bestD = nil, cfg.snap2
  for n = 1, 2 do
    local o = n == 1 and left and cells[i - left] or n == 2 and right and cells[i + right]
    if o and not auto[o] then
      local id = c * 512 + o
      local d2 = dist[id]
      if not d2 then
        local p, q = pal[c], pal[o]
        d2 = (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2
        dist[id] = d2
      end
      if d2 <= bestD then
        best, bestD = o, d2
      end
    end
  end
  return best and keys[best] or keys[c]
end

-- Cuts band b into rectangles: runs of equal key in a sampled row, extended
-- downwards while the next sampled row has the identical run. Fills the scratch
-- arrays (cell columns PX0..PX1, cell rows PY0..PY1, key PK), returns their count.
local function plan(self, cfg, b)
  local d, k, keys, auto = self.drawing, cfg.k, cfg.keys, cfg.auto
  local w, h, cells, pal = d.w, d.h, d.cells, d.palette
  local xa, xe = cfg.x0, cfg.x1
  local ya, yz = (b - 1) * cfg.bh + 1, min(h, b * cfg.bh)
  local snap = cfg.hasAuto and cfg.snap2
  serial = serial + 1
  local stamp, n, prev = serial * 1024, 0, nil
  for y = ya, yz, k do
    local ye, base = min(h, y + k - 1), (y - 1) * w
    for x = xa, xe, k do
      local c = cells[base + x]
      if snap and auto[c] then
        rowKeys[x] = snapKey(cfg, pal, cells, base + x, c, x - k >= 1 and k, x + k <= w and k)
      else
        rowKeys[x] = keys[c] or SKIP
      end
    end
    local x = xa
    while x <= xe do
      local key = rowKeys[x]
      local last = x
      while last + k <= xe and rowKeys[last + k] == key do
        last = last + k
      end
      if key ~= SKIP then
        local xz = min(xe, last + k - 1)
        local i = prev and openIdx[x]
        if i and openStamp[x] == stamp + prev and PX1[i] == xz and PK[i] == key then
          PY1[i] = ye
        else
          n = n + 1
          i = n
          PX0[i], PX1[i], PY0[i], PY1[i], PK[i] = x, xz, y, ye, key
        end
        openIdx[x], openStamp[x] = i, stamp + y
      end
      x = last + k
    end
    prev = y
  end
  return n
end

-- Rectangles of the whole configuration, or nil as soon as there are more than `limit`.
local function count(self, cfg, limit)
  local n = 0
  for b = cfg.b0, cfg.b1 do
    n = n + plan(self, cfg, b)
    if n > limit then
      return nil
    end
  end
  return n
end

-- Paints band b: pooled textures get the planned rectangles. Returns false when
-- the texture limit is reached.
local function paintBand(self, cfg, b)
  local n = plan(self, cfg, b)
  local list = self.rows[b]
  if not list then
    list = {}
    self.rows[b] = list
  end
  local color = cfg.color
  for i = 1, n do
    local t = list[i]
    if not t then
      t = acquire(self)
      if not t then
        -- Out of textures: leave the rest of the band empty, the caller rebuilds.
        return false
      end
      list[i] = t
    end
    local x0, x1, y0, y1 = edge(self, PX0[i] - 1), edge(self, PX1[i]), edge(self, PY0[i] - 1), edge(self, PY1[i])
    local key = PK[i]
    if t.x0 ~= x0 or t.x1 ~= x1 or t.y0 ~= y0 or t.y1 ~= y1 or t.c ~= key then
      t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0, -y0)
      t:SetSize(max(1, x1 - x0), max(1, y1 - y0))
      t:SetColorTexture(unpack(color[key]))
      t.x0, t.x1, t.y0, t.y1, t.c = x0, x1, y0, y1, key
    end
    if not t:IsShown() then
      t:Show()
    end
  end
  for i = #list, n + 1, -1 do
    release(self, list[i])
    list[i] = nil
  end
  return true
end

-- Picks the first level from `from` on whose rectangle count fits `limit`:
-- level, cfg, count (nil when even the coarsest sampling is over the limit).
local function decide(self, from)
  local limit = self.limit
  for level = from, TONE_LAST do
    local cfg = makeCfg(self, level)
    local same = level > from and ((level == 2 and not cfg.reduced) or (level >= TONE_FIRST and not cfg.hasAuto))
    if not same then
      local n = count(self, cfg, limit)
      if n then
        return level, cfg, n
      end
    end
  end
  local cfg
  for k = (from == STEP and self.k > 1) and self.k or 2, V.MAX_STEP do
    cfg = makeCfg(self, STEP, k)
    local n = count(self, cfg, limit)
    if n then
      return STEP, cfg, n
    end
  end
  return STEP, cfg, nil
end

-- A new auto color since the last Refresh (soft edges) needs a key.
local function syncCfg(self)
  local cfg = self.cfg
  if cfg and cfg.palN ~= #self.drawing.palette then
    cfg = makeCfg(self, cfg.level, cfg.k)
    self.cfg = cfg
  end
  return cfg
end

-- Rectangle count of a degradation level for the current drawing, scale and
-- viewport (diagnostics and tests). For the step level pass the step k.
function View:CountLevel(level, k)
  if not (self.drawing and STAGES[level]) then
    return 0
  end
  local cfg = makeCfg(self, level, k or 2)
  return count(self, cfg, math.huge), cfg
end

-- Grid lines ----------------------------------------------------------------------

local function paintGrid(self)
  local d = self.drawing
  local show = self.grid and d and self.scale >= V.GRID_MIN_SCALE
  local key = show and (d.w .. "x" .. d.h .. "@" .. self.scale)
  if key == self.gridKey then
    return
  end
  self.gridKey = key
  local used = 0
  if show then
    local width, height = edge(self, d.w), edge(self, d.h)
    local function line(vertical, i)
      used = used + 1
      local t = self.gridTex[used]
      if not t then
        t = self.frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetColorTexture(0.5, 0.5, 0.5, 0.45)
        self.gridTex[used] = t
      end
      t:ClearAllPoints()
      if vertical then
        t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", min(edge(self, i), width - 1), 0)
        t:SetSize(1, height)
      else
        t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -min(edge(self, i), height - 1))
        t:SetSize(width, 1)
      end
      t:Show()
    end
    for i = 0, d.w do
      line(true, i)
    end
    for i = 0, d.h do
      line(false, i)
    end
  end
  for i = #self.gridTex, used + 1, -1 do
    self.gridTex[i]:Hide()
  end
  self.gridShown = used
end

-- Public API -----------------------------------------------------------------------

-- Full repaint. Keeps the degradation level (it only goes up while the drawing
-- is edited); `fresh` starts from the exact picture again, which a new drawing,
-- size or scale does anyway.
function View:Refresh(fresh)
  local d = self.drawing
  if not d then
    local had = self.active > 0 or (self.mapShown or 0) > 0
    releaseAll(self)
    self.cfg, self.level, self.k, self.sizeKey, self.canRestore, self.over = nil, 0, 1, nil, false, false
    self.frame:SetSize(1, 1)
    paintMap(self)
    paintGrid(self)
    if had then
      rebalance(self)
    end
    return
  end
  local sizeKey = d.w .. "x" .. d.h .. "@" .. self.scale
  local sized = self.sizeKey ~= sizeKey
  paintMap(self)
  self.limit = allowance(self)
  local level, cfg, n = decide(self, (fresh or sized) and 0 or self.level)
  if sized or not self.cfg or self.cfg.key ~= cfg.key then
    releaseAll(self)
  end
  self.cfg, self.level, self.k, self.sizeKey = cfg, level, cfg.k, sizeKey
  self.over, self.suspended = n == nil, false
  self.squeezed = self.limit < self.cap and (level > 0 or n == nil)
  self.canRestore = level > 0 and count(self, makeCfg(self, 0), self.limit) ~= nil
  self.frame:SetSize(max(1, edge(self, d.w)), max(1, edge(self, d.h)))
  for b in pairs(self.rows) do
    if b < cfg.b0 or b > cfg.b1 then
      releaseBand(self, b)
    end
  end
  for b = cfg.b0, cfg.b1 do
    paintBand(self, cfg, b)
  end
  paintGrid(self)
  self:SetOverlay(nil)
  self:SetSelection(self.selection)
end

-- Starts over from the exact picture (the offer "full display" in the editor).
function View:Restore()
  self:Refresh(true)
  return self.level
end

-- Hands every texture back to the pool (the frame was hidden).
function View:Suspend()
  local had = self.active > 0 or (self.mapShown or 0) > 0
  releaseAll(self)
  ns.MapReveal.ReleaseTextures(self.frame)
  self.mapShown = 0
  self.suspended = self.drawing ~= nil
  self.sizeKey = nil
  if had then
    rebalance(self)
  end
end

-- Shows `drawing` (read by reference, edits to it are shown by the repaint
-- calls) with its background map (drawing.map). nil empties the view.
function View:SetDrawing(drawing)
  self.drawing = drawing
  self.map = drawing and drawing.map or nil
  self.selection = nil
  self.level, self.k = 0, 1
  self:Refresh(true)
end

function View:SetScale(scale)
  scale = max(0.25, scale)
  if scale ~= self.scale then
    self.scale = scale
    self:Refresh()
  end
end

-- Shows another background map (the stored key { kind, id | key + floor, alpha }, nil for none)
-- under the current drawing, which keeps its own `map` field for the caller to maintain.
function View:SetMap(map)
  self.map = map
  if self.drawing then
    self:Refresh()
  end
end

-- Leaves out the background texture, so only the cells that differ from the
-- background color show (cells of the background color never get a texture). A background
-- map keeps its dark ground.
function View:SetSkipBackground(on)
  self.skipBackground = on == true
  paintGround(self)
end

function View:SetGrid(on)
  self.grid = on == true
  paintGrid(self)
end

-- The part of the picture that is visible, in pixels from its top left corner
-- (left, top, right, bottom; may reach beyond the picture), nil when everything
-- is visible. Only the culled level uses it: when the visible part gets close to
-- the edge of what is painted, the window is repainted after a short delay
-- (`now` does it at once). No work happens per scroll step otherwise.
function View:SetViewport(left, top, right, bottom, now)
  if type(left) == "number" and type(top) == "number" and type(right) == "number" and type(bottom) == "number" then
    self.vp = { l = left, t = top, r = right, b = bottom }
  else
    self.vp = nil
  end
  local cfg = self.cfg
  if not (cfg and cfg.cull and self.drawing) then
    return
  end
  -- Whether a culled window applies at all depends on the viewport: start over.
  if now and makeCfg(self, cfg.level, cfg.k).reduced ~= cfg.reduced then
    return self:Refresh(true)
  end
  if not (self.vp and cfg.reduced) then
    return
  end
  -- Stale when the viewport is nearer than half a screen to a side of the window
  -- that does not end at the edge of the picture.
  local vp, s, d = self.vp, self.scale, self.drawing
  local mx, my = (vp.r - vp.l) / 2, (vp.b - vp.t) / 2
  local wl, wr = (cfg.x0 - 1) * s, cfg.x1 * s
  local wt, wb = (cfg.b0 - 1) * cfg.bh * s, min(d.h, cfg.b1 * cfg.bh) * s
  local stale = (wl > 0 and vp.l - mx < wl)
    or (wr < edge(self, d.w) and vp.r + mx > wr)
    or (wt > 0 and vp.t - my < wt)
    or (wb < edge(self, d.h) and vp.b + my > wb)
  if not stale then
    return
  end
  if now then
    self:FlushViewport()
  elseif not self.vpPending then
    self.vpPending = true
    ns.Debounce(self, V.VIEWPORT_DELAY, function()
      self:FlushViewport()
    end)
  end
end

-- Repaints the window around the current viewport (pooled textures are reused).
function View:FlushViewport()
  self.vpPending = false
  local old = self.cfg
  if not (self.drawing and old and old.cull) then
    return
  end
  local cfg = makeCfg(self, old.level, old.k)
  if cfg.x0 == old.x0 and cfg.x1 == old.x1 and cfg.b0 == old.b0 and cfg.b1 == old.b1 and cfg.palN == old.palN then
    return
  end
  self.cfg, self.limit = cfg, allowance(self)
  for b in pairs(self.rows) do
    if b < cfg.b0 or b > cfg.b1 then
      releaseBand(self, b)
    end
  end
  for b = cfg.b0, cfg.b1 do
    if not paintBand(self, cfg, b) then
      -- The new window is denser than the old one: level up.
      return self:Refresh()
    end
  end
end

-- Repaints the cell rows y1..y2 after the bitmap changed there.
function View:RepaintRows(y1, y2)
  local d = self.drawing
  local cfg = d and syncCfg(self)
  if not cfg then
    return
  end
  self.limit = allowance(self)
  y1, y2 = max(1, floor(y1)), min(d.h, floor(y2))
  for b = floor((y1 - 1) / cfg.bh) + 1, floor((y2 - 1) / cfg.bh) + 1 do
    if b >= cfg.b0 and b <= cfg.b1 and not paintBand(self, cfg, b) then
      -- Over the texture limit: re-evaluate the level once.
      return self:Refresh()
    end
  end
end

-- Repaints exactly the bands a changeset (cells list) touched. A resize
-- changeset moves every cell index, so it rebuilds the rows (Refresh notices
-- the new size and hands the textures back to the pool).
function View:ApplyChangeset(ch)
  local d = self.drawing
  if d and ch and ch.kind == "resize" then
    return self:Refresh()
  end
  local cfg = d and ch and ch.n > 0 and syncCfg(self)
  if not cfg then
    return
  end
  self.limit = allowance(self)
  local w, bh, seen, order = d.w, cfg.bh, {}, {}
  for i = 1, ch.n do
    local b = floor(floor((ch.cells[i] - 1) / w) / bh) + 1
    if not seen[b] then
      seen[b] = true
      order[#order + 1] = b
    end
  end
  for _, b in ipairs(order) do
    if b >= cfg.b0 and b <= cfg.b1 and not paintBand(self, cfg, b) then
      return self:Refresh()
    end
  end
end

-- Mouse cursor in pixels from the top left corner of the picture (may lie
-- outside it), or nil when the frame has no position yet.
function View:CursorPoint()
  local cx, cy = GetCursorPosition()
  local s = self.frame:GetEffectiveScale()
  local left, top = self.frame:GetLeft(), self.frame:GetTop()
  if not (self.drawing and cx and left and top and s and s > 0) then
    return nil
  end
  return cx / s - left, top - cy / s
end

-- Cell under the mouse cursor (not clamped, may lie outside the drawing), or
-- nil when the frame has no position yet.
function View:CursorCell()
  local px, py = self:CursorPoint()
  if not px then
    return nil
  end
  return floor(px / self.scale) + 1, floor(py / self.scale) + 1
end

-- runs: bitmap textures in use, objects: those plus grid lines (what the budget
-- counts), limit: what this view may use now, cap: its own budget, level/stage:
-- the degradation step (0..STEP, "exact" | "merged" | "culled" | "tones" |
-- "step"), tones: levels per channel in the tones step, step: sampling step,
-- coarse: step sampling is active, culled: only a window is painted, canRestore:
-- the exact picture would fit again, over: not even the coarsest step fits.
function View:Stats()
  local cfg = self.cfg
  local st = STAGES[self.level]
  return {
    runs = self.active,
    objects = self.active + self.gridShown + (self.mapShown or 0),
    map = self.mapShown or 0,
    limit = self.limit,
    cap = self.cap,
    kind = self.kind,
    pool = self.made,
    level = self.level,
    stage = st.name,
    tones = st.tones,
    step = self.k,
    coarse = self.k > 1,
    culled = cfg ~= nil and cfg.reduced == true,
    canRestore = self.canRestore == true,
    over = self.over == true,
    overlay = self.overlayShown or 0,
  }
end

-- Marquee around the cells x1..y2 (clamped to the drawing), nil hides it.
function View:SetSelection(x1, y1, x2, y2)
  local d = self.drawing
  if type(x1) == "table" then
    x1, y1, x2, y2 = x1[1], x1[2], x1[3], x1[4]
  end
  if not (d and x1) then
    self.selection = nil
    self.fill:Hide()
    for _, e in ipairs(self.edges) do
      e:Hide()
    end
    return
  end
  local a, b = max(1, min(x1, x2)), max(1, min(y1, y2))
  local c, e = min(d.w, max(x1, x2)), min(d.h, max(y1, y2))
  if a > c or b > e then
    return self:SetSelection(nil)
  end
  self.selection = { x1, y1, x2, y2 }
  local px0, py0, px1, py1 = edge(self, a - 1), edge(self, b - 1), edge(self, c), edge(self, e)
  local w, h = px1 - px0, py1 - py0
  local t = 2
  local function put(tex, x, y, tw, th)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
    tex:SetSize(max(1, tw), max(1, th))
    tex:Show()
  end
  put(self.fill, px0, py0, w, h)
  put(self.edges[1], px0, py0, w, t)
  put(self.edges[2], px0, py1 - t, w, t)
  put(self.edges[3], px0, py0, t, h)
  put(self.edges[4], px1 - t, py0, t, h)
end

-- Draws a preview changeset (cells + new colors, as from a tool with
-- preview = true) on top of the bitmap, nil removes it. Capped at MAX_OVERLAY
-- textures, the rest of a huge preview is left out.
function View:SetOverlay(ch)
  local d = self.drawing
  local used = 0
  if d and ch and ch.n > 0 then
    local w, perRow, ys, virtual = d.w, {}, {}, ch.virtual
    for i = 1, ch.n do
      local idx = ch.cells[i]
      local y = floor((idx - 1) / w) + 1
      local list = perRow[y]
      if not list then
        list = {}
        perRow[y] = list
        ys[#ys + 1] = y
      end
      -- x and palette index (-4095..256) in one number, so a plain sort orders by x.
      list[#list + 1] = (idx - (y - 1) * w) * 8192 + ch.new[i] + 4096
    end
    table.sort(ys)
    for _, y in ipairs(ys) do
      local list = perRow[y]
      table.sort(list)
      local i = 1
      while i <= #list do
        local x, c = floor(list[i] / 8192), list[i] % 8192 - 4096
        local last = x
        local j = i
        while list[j + 1] and floor(list[j + 1] / 8192) == last + 1 and list[j + 1] % 8192 - 4096 == c do
          j = j + 1
          last = last + 1
        end
        if used >= V.MAX_OVERLAY then
          break
        end
        local p = c < 0 and virtual and virtual[-c] or d.palette[c]
        if p then
          used = used + 1
          local t = self.overlay[used]
          if not t then
            t = self.frame:CreateTexture(nil, "ARTWORK", nil, 1)
            self.overlay[used] = t
          end
          local x0, x1 = edge(self, x - 1), edge(self, last)
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0, -edge(self, y - 1))
          t:SetSize(max(1, x1 - x0), max(1, edge(self, y) - edge(self, y - 1)))
          t:SetColorTexture(p[1] / 255, p[2] / 255, p[3] / 255)
          t:Show()
        end
        i = j + 1
      end
    end
  end
  for i = #self.overlay, used + 1, -1 do
    self.overlay[i]:Hide()
  end
  self.overlayShown = used
end

-- Hides everything and hands all textures back to the pool.
function View:Clear()
  self.drawing = nil
  self:Refresh()
  self:SetOverlay(nil)
  self:SetSelection(nil)
end
