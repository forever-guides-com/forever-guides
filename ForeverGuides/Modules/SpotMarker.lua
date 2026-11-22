-- The marker of a spot with several possible items (GatheringMapLogic.Marker): colored arcs on the rim of the
-- symbol, one per item (dimmed when the item is not selected), and the number of possible items at the lower
-- right. Only textures and a font string of our own frame; the map symbols (GatheringMap.lua) and the minimap
-- pins (MinimapLayer.lua) share it. The decision what to draw is in GatheringMapLogic.
local _, ns = ...
local Theme, MI, GM = ns.Theme, ns.MapIcons, ns.GatheringMapLogic

local SM = {}
ns.SpotMarker = SM

-- Width of an arc in screen px and of the dark backing around it (the arcs need it against light terrain).
SM.ARC_WIDTH = 2
SM.BACKING = 1
-- Counts above this show as "9+".
SM.MAX_COUNT = 9

-- Quadrant of the disc texture per slot, and the corner of the quarter that touches the center.
local QUADS = {
  { coords = { 0.5, 1, 0, 0.5 }, corner = "BOTTOMLEFT" },
  { coords = { 0.5, 1, 0.5, 1 }, corner = "TOPLEFT" },
  { coords = { 0, 0.5, 0.5, 1 }, corner = "TOPRIGHT" },
  { coords = { 0, 0.5, 0, 0.5 }, corner = "BOTTOMRIGHT" },
}

-- A marker on `parent` around the texture `anchor` (the symbol). Nothing is shown until Paint.
function SM.New(parent, anchor)
  local m = { parent = parent, anchor = anchor, disc = MI.DiscKnown(), arcs = {} }
  m.back = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
  m.back:SetPoint("CENTER", anchor, "CENTER")
  if m.disc then
    m.back:SetTexture(MI.DISC)
  end
  m.back:Hide()
  for i = 1, #QUADS do
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
    if m.disc then
      t:SetTexture(MI.DISC)
    end
    t:SetTexCoord(unpack(QUADS[i].coords))
    t:Hide()
    m.arcs[i] = t
  end
  m.text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  m.text:SetPoint("CENTER", anchor, "BOTTOMRIGHT", 0, 0)
  ns.Bind(m.text, function(f)
    Theme.applyFont(f, "micro", "body", "OUTLINE")
    f:SetTextColor(Theme.color("text"))
  end)
  m.text:Hide()
  return m
end

-- A tinted disc where the disc texture is known, a plain square otherwise.
local function color(m, t, r, g, b, a)
  if m.disc then
    t:SetVertexColor(r, g, b, a)
  else
    t:SetColorTexture(r, g, b, a)
  end
end

function SM.Hide(m)
  m.back:Hide()
  for _, t in ipairs(m.arcs) do
    t:Hide()
  end
  m.text:Hide()
end

-- Shows `marker` (GM.Marker) around a symbol of `size` canvas units with a dark edge of `ring` units; unit =
-- canvas units per screen px, alpha scales everything.
function SM.Paint(m, marker, size, ring, alpha, unit)
  unit = unit or 1
  for _, t in ipairs(m.arcs) do
    t:Hide()
  end
  local segments = marker.segments
  if segments then
    local rim = size + 2 * (ring + SM.ARC_WIDTH * unit)
    local backing = rim + 2 * SM.BACKING * unit
    m.back:SetSize(backing, backing)
    color(m, m.back, Theme.color("bg", 0.85 * alpha))
    m.back:Show()
    for _, seg in ipairs(segments) do
      local r, g, b = GM.ItemColor(seg.id)
      for _, q in ipairs(seg.quads) do
        local t = m.arcs[q]
        t:ClearAllPoints()
        t:SetPoint(QUADS[q].corner, m.anchor, "CENTER")
        t:SetSize(rim / 2, rim / 2)
        color(m, t, r, g, b, (seg.dim and GM.DIM_ARC_ALPHA or 1) * alpha)
        t:Show()
      end
    end
  else
    m.back:Hide()
  end
  local count = marker.count
  m.text:SetScale(unit)
  m.text:SetText(count > SM.MAX_COUNT and (SM.MAX_COUNT .. "+") or tostring(count))
  m.text:SetAlpha(alpha)
  m.text:Show()
end
