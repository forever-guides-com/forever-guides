-- Pixel icons for the desktop-style widgets, drawn from pooled solid color
-- textures (no texture file names). Glyphs live on a 12x12 grid, y points
-- down; at 24 px one grid unit is exactly two screen pixels.
--
--   local icon = ns.IconDraw.new(parent, 24)
--   icon:Draw("pencil")          -- registered name, text glyph or drawer fn(p)
--   icon:SetTint("accent")       -- recolors every "fg" part
--
-- A drawer function receives the icon as painter `p` and calls p:Rect,
-- p:Outline, p:Line and p:Ellipse in grid units. The optional last argument
-- of every call is a theme color token; nil or "fg" follows the tint.
local _, ns = ...
local W, Theme = ns.W, ns.Theme

local IconDraw = { glyphs = {}, GRID = 12 }
ns.IconDraw = IconDraw
local GRID = IconDraw.GRID

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

local Methods = {}

local function paintTexture(icon, tex)
  local token = tex.token
  if token == nil or token == "fg" then
    token = icon.tint
  end
  tex:SetColorTexture(Theme.color(token))
end

local function take(icon)
  local tex = table.remove(icon.pool) or icon:CreateTexture(nil, "ARTWORK")
  tex:Show()
  icon.used[#icon.used + 1] = tex
  return tex
end

function Methods:Rect(x, y, w, h, token)
  if w <= 0 or h <= 0 then
    return nil
  end
  if self.mirror then
    x = GRID - x - w
  end
  local u = self.unit
  local tex = take(self)
  tex.token = token
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", self, "TOPLEFT", x * u, -y * u)
  tex:SetSize(w * u, h * u)
  paintTexture(self, tex)
  return tex
end

function Methods:Outline(x, y, w, h, token)
  self:Rect(x, y, w, 1, token)
  self:Rect(x, y + h - 1, w, 1, token)
  self:Rect(x, y + 1, 1, h - 2, token)
  self:Rect(x + w - 1, y + 1, 1, h - 2, token)
end

-- One grid unit thick, stair-stepped; runs of cells in one row or column
-- merge into a single texture.
function Methods:Line(x1, y1, x2, y2, token)
  x1, y1, x2, y2 = floor(x1 + 0.5), floor(y1 + 0.5), floor(x2 + 0.5), floor(y2 + 0.5)
  local dx, dy = abs(x2 - x1), abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx - dy
  local shallow = dx >= dy
  local cells = {}
  local x, y = x1, y1
  while true do
    cells[#cells + 1] = { x, y }
    if x == x2 and y == y2 then
      break
    end
    local e2 = 2 * err
    if e2 > -dy then
      err = err - dy
      x = x + sx
    end
    if e2 < dx then
      err = err + dx
      y = y + sy
    end
  end
  local i = 1
  while i <= #cells do
    local first, j = cells[i], i
    while cells[j + 1] and cells[j + 1][shallow and 2 or 1] == first[shallow and 2 or 1] do
      j = j + 1
    end
    local last = cells[j]
    self:Rect(
      min(first[1], last[1]),
      min(first[2], last[2]),
      abs(last[1] - first[1]) + 1,
      abs(last[2] - first[2]) + 1,
      token
    )
    i = j + 1
  end
end

-- Ellipse inscribed in the box, one texture per row (filled) or per row edge.
function Methods:Ellipse(x, y, w, h, filled, token)
  local rows = {}
  for j = 0, h - 1 do
    local ny = (j + 0.5 - h / 2) / (h / 2)
    local half = math.sqrt(max(0, 1 - ny * ny)) * w / 2
    local x0 = floor(w / 2 - half + 0.5)
    local x1 = floor(w / 2 + half + 0.5)
    if x1 <= x0 then
      x1 = x0 + 1
    end
    rows[j] = { x0, x1 }
  end
  for j = 0, h - 1 do
    local x0, x1 = rows[j][1], rows[j][2]
    local span = x1 - x0
    if filled or j == 0 or j == h - 1 then
      self:Rect(x + x0, y + j, span, 1, token)
    else
      local up, down = rows[j - 1], rows[j + 1]
      local left = max(1, up[1] - x0, down[1] - x0)
      local right = max(1, x1 - up[2], x1 - down[2])
      self:Rect(x + x0, y + j, min(left, span), 1, token)
      self:Rect(x + x1 - min(right, span), y + j, min(right, span), 1, token)
    end
  end
end

function Methods:Clear()
  for _, tex in ipairs(self.used) do
    tex:Hide()
    self.pool[#self.pool + 1] = tex
  end
  self.used = {}
  if self.letterText then
    self.letterText:Hide()
  end
end

local function showText(icon, text)
  if not icon.letterText then
    icon.letterText = W.Text(icon, { role = "h3", color = "textSecondary", justify = "CENTER" })
    icon.letterText:SetPoint("CENTER", 0, 0)
  end
  W.SetText(icon.letterText, nil, text)
  W.SetColor(icon.letterText, icon.tint)
  icon.letterText:Show()
end

-- glyph: registered name, drawer function(p, pixelSize), or any other string
-- (shown as text). A drawer that errors or paints nothing falls back to
-- `letter`, or the upper-cased first character of the name. Returns true
-- when the glyph was drawn as intended.
function Methods:Draw(glyph, letter)
  self:Clear()
  self.glyph, self.letter = glyph, letter
  local fn = type(glyph) == "function" and glyph or IconDraw.glyphs[glyph]
  if not fn then
    showText(self, type(glyph) == "string" and glyph or letter or "?")
    return true
  end
  self.mirror = false
  local ok = ns.Safe("icon-draw", fn, self, self.pixel)
  self.mirror = false
  if ok and #self.used > 0 then
    return true
  end
  self:Clear()
  showText(self, letter or (type(glyph) == "string" and glyph:sub(1, 1):upper()) or "?")
  return false
end

function Methods:SetTint(token)
  self.tint = token or "textSecondary"
  for _, tex in ipairs(self.used) do
    paintTexture(self, tex)
  end
  if self.letterText then
    W.SetColor(self.letterText, self.tint)
  end
end

function Methods:SetIconSize(pixel)
  self.pixel = pixel
  self.unit = pixel / GRID
  self:SetSize(pixel, pixel)
  if self.glyph ~= nil then
    self:Draw(self.glyph, self.letter)
  end
end

-- Number of textures the current glyph uses.
function Methods:TextureCount()
  return #self.used
end

function IconDraw.register(name, fn)
  IconDraw.glyphs[name] = fn
end

function IconDraw.has(name)
  return IconDraw.glyphs[name] ~= nil
end

function IconDraw.names()
  return ns.U.sortedKeys(IconDraw.glyphs)
end

-- Icon holder of pixel x pixel size. Textures are pooled per holder, so
-- redrawing (new glyph, new size) never leaks regions.
function IconDraw.new(parent, pixel)
  local icon = CreateFrame("Frame", nil, parent)
  icon.pool, icon.used, icon.tint, icon.mirror = {}, {}, "textSecondary", false
  for name, fn in pairs(Methods) do
    icon[name] = fn
  end
  icon:SetIconSize(pixel or 24)
  ns.Bind(icon, function(self)
    for _, tex in ipairs(self.used) do
      paintTexture(self, tex)
    end
    if self.letterText then
      W.SetColor(self.letterText, self.tint)
    end
  end)
  return icon
end

-- Glyphs --------------------------------------------------------------------

local glyphs = IconDraw.glyphs

glyphs.pencil = function(p)
  p:Line(3, 8, 8, 3)
  p:Line(4, 8, 9, 3)
  p:Rect(9, 2, 2, 2, "accent2")
  p:Rect(2, 9, 2, 2, "accent2")
end

glyphs.bucket = function(p)
  p:Outline(2, 5, 7, 6)
  p:Rect(2, 5, 7, 2)
  p:Line(3, 5, 5, 2)
  p:Line(5, 2, 7, 5)
  p:Rect(10, 6, 2, 3, "accent2")
end

glyphs.eraser = function(p)
  p:Outline(2, 3, 8, 5)
  p:Rect(2, 3, 3, 5)
  p:Rect(1, 9, 10, 1, "accent2")
end

glyphs.picker = function(p)
  p:Line(2, 9, 7, 4)
  p:Line(3, 9, 8, 4)
  p:Rect(8, 1, 3, 3)
  p:Rect(1, 10, 2, 1, "accent2")
end

glyphs.magnifier = function(p)
  p:Ellipse(1, 1, 7, 7, false)
  p:Line(7, 7, 10, 10)
  p:Line(8, 7, 11, 10)
end

glyphs.line = function(p)
  p:Line(2, 9, 9, 2)
  p:Line(3, 9, 10, 2)
end

glyphs.rectangle = function(p)
  p:Outline(1, 3, 10, 6)
end

glyphs.ellipse = function(p)
  p:Ellipse(1, 2, 10, 8, false)
end

glyphs["select-rect"] = function(p)
  for x = 1, 9, 4 do
    p:Rect(x, 2, 2, 1)
    p:Rect(x, 9, 2, 1)
  end
  for y = 4, 7, 3 do
    p:Rect(1, y, 1, 2)
    p:Rect(10, y, 1, 2)
  end
end

glyphs.undo = function(p)
  p:Line(1, 4, 4, 1)
  p:Line(1, 4, 4, 7)
  p:Rect(2, 4, 8, 1)
  p:Rect(9, 5, 1, 5)
  p:Rect(5, 9, 4, 1)
end

glyphs.redo = function(p)
  p.mirror = true
  glyphs.undo(p)
end

glyphs.save = function(p)
  p:Outline(1, 1, 10, 10)
  p:Rect(3, 1, 6, 3)
  p:Rect(3, 7, 6, 4)
end

glyphs.share = function(p)
  p:Rect(8, 1, 3, 3)
  p:Rect(1, 4, 3, 4)
  p:Rect(8, 8, 3, 3)
  p:Line(4, 5, 8, 2)
  p:Line(4, 6, 8, 9)
end

glyphs["flip-h"] = function(p)
  for y = 1, 10, 3 do
    p:Rect(5, y, 2, 2)
  end
  p:Outline(1, 3, 3, 6)
  p:Rect(8, 3, 3, 6)
end

glyphs["flip-v"] = function(p)
  for x = 1, 10, 3 do
    p:Rect(x, 5, 2, 2)
  end
  p:Outline(3, 1, 6, 3)
  p:Rect(3, 8, 6, 3)
end

glyphs.check = function(p)
  p:Line(1, 6, 4, 9)
  p:Line(4, 9, 10, 3)
end

glyphs["chevron-down"] = function(p)
  p:Line(2, 4, 6, 8)
  p:Line(6, 8, 10, 4)
end

glyphs["chevron-right"] = function(p)
  p:Line(4, 2, 8, 6)
  p:Line(8, 6, 4, 10)
end

glyphs.plus = function(p)
  p:Rect(5, 2, 2, 8)
  p:Rect(2, 5, 8, 2)
end

glyphs.minus = function(p)
  p:Rect(2, 5, 8, 2)
end

glyphs.close = function(p)
  p:Line(2, 2, 9, 9)
  p:Line(9, 2, 2, 9)
end

glyphs.fit = function(p)
  p:Rect(1, 1, 4, 1)
  p:Rect(1, 1, 1, 4)
  p:Rect(7, 1, 4, 1)
  p:Rect(10, 1, 1, 4)
  p:Rect(1, 10, 4, 1)
  p:Rect(1, 7, 1, 4)
  p:Rect(7, 10, 4, 1)
  p:Rect(10, 7, 1, 4)
end
