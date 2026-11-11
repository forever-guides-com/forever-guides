-- Widget "Instanzkarte-Bild": the picture of one instance for a card or a header band. A gradient and a
-- symbol stand behind the loading screen of the client (FileDataID, no file in the add-on), so an
-- instance without a usable picture is never an empty spot and a picture that is still loading does not
-- flicker. The choice and the cut are in Modules/InstanceArtLogic.lua. The texture is given back
-- (SetTexture(nil)) when the widget hides and set again when it shows, so a page of 34 pictures holds
-- graphics memory only while it is visible.
--
--   local art = ns.InstanceArt.Create(parent)
--   art:SetInstance(inst)       -- a table of Data.Instances
--   art:Layout(w, h)            -- size of the box; h defaults to the card ratio 16:5
--   art:Release()               -- gives the texture back (also on hide)
--   art:GetChoice()             -- result of InstanceArtLogic.Choose
local _, ns = ...
local Theme, A = ns.Theme, ns.InstanceArtLogic

local Art = {}
ns.InstanceArt = Art

-- Symbol size in px: half the height of the box, within these limits.
Art.SYMBOL_MIN, Art.SYMBOL_MAX = 16, 40

-- Drawn symbols on the 12 by 12 grid of ns.IconDraw: a gate for a dungeon, a crown for a raid.
ns.IconDraw.register(A.SYMBOL.dungeon, function(p)
  p:Rect(2, 5, 2, 6)
  p:Rect(8, 5, 2, 6)
  p:Rect(3, 3, 6, 2)
  p:Rect(4, 2, 4, 1)
  p:Rect(5, 8, 2, 3, "accent2")
end)

ns.IconDraw.register(A.SYMBOL.raid, function(p)
  p:Rect(1, 9, 10, 2)
  p:Rect(1, 4, 2, 5)
  p:Rect(5, 2, 2, 7)
  p:Rect(9, 4, 2, 5)
  p:Rect(3, 6, 2, 3)
  p:Rect(7, 6, 2, 3)
end)

-- Paints the gradient from the left to the right tone. A client with SetGradient (new or old argument
-- form) gets a real gradient; without it the left tone fills the box and a half transparent right tone
-- covers its right half.
local function paintGradient(self, left, right)
  local base, cover = self.base, self.cover
  local ok = false
  if type(base.SetGradient) == "function" then
    base:SetColorTexture(1, 1, 1, 1)
    local color = rawget(_G, "CreateColor")
    if type(color) == "function" then
      ok = pcall(function()
        base:SetGradient("HORIZONTAL", color(left[1], left[2], left[3], 1), color(right[1], right[2], right[3], 1))
      end)
    end
    if not ok then
      ok = pcall(base.SetGradient, base, "HORIZONTAL", left[1], left[2], left[3], right[1], right[2], right[3])
    end
  end
  if ok then
    cover:Hide()
  else
    base:SetColorTexture(left[1], left[2], left[3], 1)
    cover:SetColorTexture(right[1], right[2], right[3], 0.5)
    cover:Show()
  end
end

local function scale(tone, k)
  return { tone[1] * k, tone[2] * k, tone[3] * k }
end

local Methods = {}

function Methods:Paint()
  local choice = self.choice
  if not choice then
    return
  end
  local left, right = A.Tones(choice.family)
  local contrast = Theme.highContrast()
  -- High contrast: the placeholder tones and the picture are darkened so text on a plaque stays readable.
  local k = contrast and A.CONTRAST_DIM or 1
  paintGradient(self, scale(left, k), scale(right, k))
  local isImage = choice.kind == "image" and self:IsShown()
  if isImage then
    self.image:SetTexture(choice.fid)
    self.image:SetAlpha(contrast and A.CONTRAST_DIM or 1)
    self.image:Show()
    self.symbol:Hide()
    self:ApplyCoords()
  else
    self.image:SetTexture(nil)
    self.image:Hide()
    self.symbol:Draw(choice.symbol)
    self.symbol:SetTint("textSecondary")
    self.symbol:Show()
  end
end

function Methods:ApplyCoords()
  local choice = self.choice
  if not (choice and choice.kind == "image") then
    return
  end
  local w, h = self.boxW, self.boxH
  self.image:SetTexCoord(A.Coords(choice, w, h))
end

function Methods:SetInstance(inst)
  self.inst = inst
  self.choice = inst and A.Choose(inst) or nil
  self:Paint()
end

-- Size of the box. Without a height the box takes the card ratio (16:5).
function Methods:Layout(w, h)
  w = (type(w) == "number" and w > 0) and w or self:GetWidth()
  h = (type(h) == "number" and h > 0) and h or w * A.RATIO_H / A.RATIO_W
  self.boxW, self.boxH = w, h
  self:SetSize(w, h)
  local size = math.max(Art.SYMBOL_MIN, math.min(Art.SYMBOL_MAX, math.floor(h / 2)))
  self.symbol:SetIconSize(size)
  self:ApplyCoords()
end

function Methods:Release()
  self.image:SetTexture(nil)
  self.image:Hide()
end

function Methods:GetChoice()
  return self.choice
end

-- True while the gradient and the symbol are shown instead of a client picture.
function Methods:IsPlaceholder()
  return self.choice == nil or self.choice.kind ~= "image"
end

function Art.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetClipsChildren(true)
  f.base = f:CreateTexture(nil, "BACKGROUND")
  f.base:SetAllPoints()
  f.cover = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.cover:SetPoint("TOPRIGHT")
  f.cover:SetPoint("BOTTOMRIGHT")
  f.cover:SetPoint("LEFT", f, "CENTER")
  f.image = f:CreateTexture(nil, "ARTWORK")
  f.image:SetAllPoints()
  f.symbol = ns.IconDraw.new(f, Art.SYMBOL_MAX)
  f.symbol:SetPoint("CENTER")
  f.boxW, f.boxH = f:GetWidth(), f:GetHeight()
  for name, fn in pairs(Methods) do
    f[name] = fn
  end
  f:HookScript("OnHide", function(self)
    self:Release()
  end)
  f:HookScript("OnShow", function(self)
    self:Paint()
  end)
  ns.Bind(f, function(self)
    self:Paint()
  end)
  return f
end
