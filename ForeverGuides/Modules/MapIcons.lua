-- Symbols of the places on the map page: one symbol per kind of place (flight master, harbor,
-- ...) and the badge that draws it, shared by the pins, the place cards and the legend.
-- Sources in this order: (a) a client atlas, used only when C_Texture.GetAtlasInfo knows it,
-- (b) a white shape texture of the addon (Media\map_*.png),
-- tinted with the faction color, used only when the client can resolve its path,
-- (c) a drawn fallback: a colored disc, or a square with a border when no disc texture is
-- known to exist, with one letter of the kind. The fallback alone carries every kind.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme

local MI = {}
ns.MapIcons = MI

ns.AddLocale("enUS", {
  ["map.kind.inn"] = "Inn",
  ["map.kind.raidEntrance"] = "Raid entrance",
})
ns.AddLocale("deDE", {
  ["map.kind.inn"] = "Gasthaus",
  ["map.kind.raidEntrance"] = "Raideingang",
})

-- Kinds in legend order. The data (Data\Travel.lua k) uses city, flightMaster, harbor,
-- instanceEntrance, landmark, tram and zeppelinTower; portal and inn are drawn when places of
-- that kind show up. raidEntrance (the raid markers of Modules/MapMarkerLogic.lua) is not in the
-- legend list, no place of the map data has that kind.
MI.KINDS =
  { "city", "flightMaster", "harbor", "zeppelinTower", "tram", "portal", "instanceEntrance", "landmark", "inn" }

-- Data kinds that share the symbol of another kind; anything unknown draws as a landmark.
local ALIAS = { capital = "city", placeholder = "landmark", zone = "landmark" }

-- Label priority of a kind, smaller first (bigger places are named first on a crowded map).
local RANK = {
  city = 1,
  flightMaster = 2,
  harbor = 3,
  zeppelinTower = 3,
  tram = 3,
  portal = 3,
  instanceEntrance = 4,
  raidEntrance = 4,
  landmark = 5,
  inn = 6,
}

-- Atlas names that might exist per kind, best first. These are candidates, verified at
-- runtime with C_Texture.GetAtlasInfo; none of them is assumed to exist.
local ATLAS = {
  city = { "poi-town" },
  flightMaster = { "TaxiNode_Neutral", "Taxi_Frame_Gray" },
  harbor = {
    "poi-transportation-boat",
    "Boat",
    "FlightMaster_Ferry-Taxi_Frame_Gray",
    "FlightMaster_Ferry-UI-Taxi-Icon-Nub",
    "TaxiNode_Continent_Neutral",
  },
  zeppelinTower = { "poi-transportation-zeppelin", "Zeppelin" },
  tram = { "poi-transportation-tram" },
  portal = { "MagePortalAlliance", "MagePortalHorde" },
  instanceEntrance = { "Dungeon", "Raid" },
  raidEntrance = { "Raid", "Dungeon" },
  landmark = { "poi-hub", "VignetteEvent" },
  inn = { "Innkeeper" },
}

-- Shape file (in Media\) per kind, second choice after the atlas.
local SHAPE = {
  flightMaster = "map_diamond.png",
  harbor = "map_square.png",
  zeppelinTower = "map_triangle.png",
  tram = "map_hexagon.png",
  portal = "map_star8.png",
}

-- Fallback letter and plate color (Theme token) per kind. The letter is the same in every
-- language, so the legend and the pins always agree.
local LETTER = {
  city = "C",
  flightMaster = "F",
  harbor = "H",
  zeppelinTower = "Z",
  tram = "T",
  portal = "P",
  instanceEntrance = "I",
  raidEntrance = "R",
  landmark = "L",
  inn = "B",
}
local PLATE = {
  city = "accent",
  flightMaster = "actionHi",
  harbor = "textSecondary",
  zeppelinTower = "success",
  tram = "warning",
  portal = "sectionLocked",
  instanceEntrance = "parchment",
  raidEntrance = "warning",
  landmark = "textMuted",
  inn = "sectionAvailable",
}

-- The faction frame: Alliance blue, Horde red, everything else (both factions) gold.
local FRAME = { A = "alliance", H = "horde" }

MI.DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
MI.RING = 2 -- width of the faction frame around the symbol
MI.DIM_ALPHA = 0.55 -- dimmed symbol, e.g. an undiscovered flight point (not the filter dim of MapPins)
MI.MEDIA = "Interface\\AddOns\\ForeverGuides\\Media\\"

-- Lookups of the client, cached per name; MI.Reset forgets them (tests, probe).
local atlasSeen, fileSeen, specs = {}, {}, {}

function MI.Reset()
  atlasSeen, fileSeen, specs = {}, {}, {}
end

local function atlasKnown(name)
  if atlasSeen[name] == nil then
    local get = C_Texture and C_Texture.GetAtlasInfo
    local ok, info = false, nil
    if get then
      ok, info = pcall(get, name)
    end
    atlasSeen[name] = ok and info ~= nil
  end
  return atlasSeen[name]
end

-- Without a file lookup in the client a missing file cannot be told from a present one (it
-- renders as a green square), so a path counts as known only when the lookup says so.
local function fileKnown(path)
  if fileSeen[path] == nil then
    local get = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
    local ok, id = false, nil
    if get then
      ok, id = pcall(get, path)
    end
    fileSeen[path] = ok and id ~= nil
  end
  return fileSeen[path]
end

function MI.DiscKnown()
  return fileKnown(MI.DISC)
end

-- The symbol kind a data kind is drawn as.
function MI.KindOf(k)
  if RANK[k] then
    return k
  end
  return ALIAS[k] or "landmark"
end

function MI.Rank(k)
  return RANK[MI.KindOf(k)]
end

function MI.KindName(k)
  return L["map.kind." .. MI.KindOf(k)]
end

function MI.FactionToken(f)
  return FRAME[f] or "accent2"
end

-- { kind, source = "atlas" | "shape" | "fallback", atlas?, shape? (file name), texture? (its
-- path), letter, plate, tried = { atlas names } }
function MI.Spec(k)
  local kind = MI.KindOf(k)
  local spec = specs[kind]
  if not spec then
    spec = { kind = kind, source = "fallback", letter = LETTER[kind], plate = PLATE[kind], tried = ATLAS[kind] }
    for _, name in ipairs(ATLAS[kind]) do
      if atlasKnown(name) then
        spec.source, spec.atlas = "atlas", name
        break
      end
    end
    local file = SHAPE[kind]
    if spec.source == "fallback" and file and fileKnown(MI.MEDIA .. file) then
      spec.source, spec.shape, spec.texture = "shape", file, MI.MEDIA .. file
    end
    specs[kind] = spec
  end
  return spec
end

-- Paints a texture as a disc (the disc texture, tinted) or, without one, as a flat square.
local function paint(tex, disc, r, g, b, a)
  if disc then
    tex:SetTexture(MI.DISC)
    tex:SetVertexColor(r, g, b, a)
  else
    tex:SetColorTexture(r, g, b, a)
  end
end
MI.Paint = paint

-- A symbol on `parent`: faction frame, plate, atlas or letter, glow and selection ring. All
-- parts are regions of the parent, nothing is created again when the badge is set to another
-- kind. The owner anchors badge.box (an invisible region) and sets the size through Set.
function MI.NewBadge(parent)
  local b = { level = 0 }
  b.box = parent:CreateTexture(nil, "BACKGROUND")
  b.sel = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
  b.ring = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.plate = parent:CreateTexture(nil, "BORDER")
  b.icon = parent:CreateTexture(nil, "ARTWORK", nil, 0)
  b.glow = parent:CreateTexture(nil, "ARTWORK", nil, 3)
  b.glow:SetBlendMode("ADD")
  b.letter = W.Text(parent, { role = "micro", color = "bg", justify = "CENTER" })

  local function around(tex, extra)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", b.box, "CENTER")
    tex:SetSize(b.size + 2 * extra, b.size + 2 * extra)
  end

  -- kind: a data kind, faction: "A" | "H" | "B", size: edge of the symbol without the frame,
  -- estimated: frame at reduced opacity, dim: faded and desaturated symbol (the owner also says so in the tooltip),
  -- letter: draws the plate with this letter whatever atlas or shape the client has, with an outline.
  function b:Set(kind, faction, size, estimated, dim, letter)
    local spec = MI.Spec(kind)
    if letter then
      spec = { kind = spec.kind, source = "fallback", letter = letter, plate = spec.plate, tried = spec.tried }
    end
    local disc = MI.DiscKnown()
    self.spec, self.faction, self.size, self.shape = spec, faction, size, disc and "disc" or "square"
    self.token = MI.FactionToken(faction)
    self.box:SetSize(size, size)
    around(self.ring, MI.RING)
    around(self.sel, MI.RING + 2)
    around(self.plate, 0)
    around(self.glow, 0)
    paint(self.ring, disc, Theme.color(self.token, estimated and 0.65 or 1))
    paint(self.glow, disc, 1, 1, 1, 1)
    if spec.source == "atlas" then
      paint(self.plate, disc, Theme.color("bg", 0.9))
      around(self.icon, -1)
      self.icon:SetAtlas(spec.atlas)
      self.icon:SetVertexColor(1, 1, 1, 1)
      self.icon:Show()
      self.letter:Hide()
    elseif spec.source == "shape" then
      -- The shape file is white, the faction color comes from the vertex color.
      paint(self.plate, disc, Theme.color("bg", 0.9))
      around(self.icon, -2)
      self.icon:SetTexture(spec.texture)
      self.icon:SetVertexColor(Theme.color(self.token, estimated and 0.65 or 1))
      self.icon:Show()
      self.letter:Hide()
    else
      paint(self.plate, disc, Theme.color(spec.plate))
      self.icon:Hide()
      self.letter:ClearAllPoints()
      self.letter:SetPoint("CENTER", self.box, "CENTER")
      W.SetText(self.letter, nil, spec.letter)
      if letter then
        Theme.applyFont(self.letter, "micro", "body", "OUTLINE")
      end
      self.letter:Show()
    end
    -- The alpha goes on the parts one by one, the glow and the selection ring keep their own.
    local alpha = dim and MI.DIM_ALPHA or 1
    for _, part in ipairs({ self.ring, self.plate, self.icon, self.letter }) do
      part:SetAlpha(alpha)
    end
    self.icon:SetDesaturated(dim == true)
    self.dim = dim == true
    self:Highlight(self.level)
    self:Select(self.selected)
  end

  -- level 0..1: the white glow over the symbol (hover and selection).
  function b:Highlight(level)
    self.level = level
    self.glow:SetAlpha(level)
    self.glow:SetShown(level > 0)
  end

  function b:Select(on)
    self.selected = on == true
    paint(self.sel, MI.DiscKnown(), Theme.color("text"))
    self.sel:SetShown(self.selected)
  end

  return b
end

-- Text arrows for a client without line objects, by quarter turn: east, north, west, south.
local ARROW_TEXT = { ">", "^", "<", "v" }

-- Opacity of the strokes of an estimated arrow.
local FAINT = 0.7

local function canDrawLines()
  return ns.can.lineObject and ns.can.lineThickness and ns.can.lineColorTexture or false
end

-- How the zone transition arrow draws on this client, for /fg mapdiag: whether line objects exist, whether
-- the client resolves the triangle file of the add-on (the arrow no longer needs it) and the file lookup used.
function MI.ArrowInfo()
  local lookup = (C_Texture and C_Texture.GetFileIDFromPath and "C_Texture.GetFileIDFromPath")
    or (GetFileIDFromPath and "GetFileIDFromPath")
    or "none"
  return {
    lines = canDrawLines(),
    fileKnown = fileKnown(MI.MEDIA .. SHAPE.zeppelinTower),
    lookup = lookup,
  }
end

-- A zone transition arrow on `parent`: a plate with a frame, an arrow of three line strokes (shaft and
-- two head lines, drawn by the client, so no texture file is involved) turned to the direction, and a glow
-- for hover. Without line objects the plate carries a text arrow. The owner anchors arrow.box and sets size
-- and direction through Set. A dashed arrow (an estimate) draws the shaft as short pieces (arrow.dashes,
-- made when first needed) and a little fainter.
function MI.NewArrow(parent)
  local a = { level = 0, strokes = {}, dashes = {} }
  a.box = parent:CreateTexture(nil, "BACKGROUND")
  a.ring = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  a.plate = parent:CreateTexture(nil, "BORDER")
  a.glow = parent:CreateTexture(nil, "ARTWORK", nil, 3)
  a.glow:SetBlendMode("ADD")
  a.letter = W.Text(parent, { role = "micro", color = "text", justify = "CENTER" })
  if canDrawLines() then
    for i = 1, 3 do
      a.strokes[i] = parent:CreateLine(nil, "ARTWORK", nil, 1)
    end
  end

  local function around(tex, extra)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", a.box, "CENTER")
    tex:SetSize(a.size + 2 * extra, a.size + 2 * extra)
  end

  local function stroke(line, p, thickness, alpha)
    line:SetThickness(thickness)
    line:SetColorTexture(Theme.color("text", alpha))
    line:SetStartPoint("CENTER", a.box, p[1], p[2])
    line:SetEndPoint("CENTER", a.box, p[3], p[4])
    line:Show()
  end

  -- size: edge of the plate without the frame, angle: direction in radians, counterclockwise from
  -- east as on the map, dashed: draw it as an estimate.
  function a:Set(size, angle, dashed)
    local disc = MI.DiscKnown()
    angle = angle or 0
    dashed = dashed == true
    self.size, self.angle, self.dashed = size, angle, dashed
    self.box:SetSize(size, size)
    around(self.ring, MI.RING)
    around(self.plate, 0)
    around(self.glow, 0)
    paint(self.ring, disc, Theme.color("accent2", 1))
    paint(self.plate, disc, Theme.color("bg", 0.9))
    paint(self.glow, disc, 1, 1, 1, 1)
    if #self.strokes > 0 then
      local shape, thickness = ns.ZoneBorderLogic.ArrowLines(angle, size, dashed)
      local alpha = dashed and FAINT or 1
      local heads = #shape - 2
      stroke(self.strokes[2], shape[heads + 1], thickness, alpha)
      stroke(self.strokes[3], shape[heads + 2], thickness, alpha)
      if dashed then
        self.strokes[1]:Hide()
        for i = 1, heads do
          self.dashes[i] = self.dashes[i] or parent:CreateLine(nil, "ARTWORK", nil, 1)
          stroke(self.dashes[i], shape[i], thickness, alpha)
        end
      else
        stroke(self.strokes[1], shape[1], thickness, alpha)
      end
      for i = dashed and heads + 1 or 1, #self.dashes do
        self.dashes[i]:Hide()
      end
      self.letter:Hide()
    else
      self.letter:ClearAllPoints()
      self.letter:SetPoint("CENTER", self.box, "CENTER")
      W.SetText(self.letter, nil, ARROW_TEXT[math.floor(angle / (math.pi / 2) + 0.5) % 4 + 1])
      self.letter:SetAlpha(dashed and FAINT or 1)
      self.letter:Show()
    end
    self:Highlight(self.level)
  end

  function a:Highlight(level)
    self.level = level
    self.glow:SetAlpha(level)
    self.glow:SetShown(level > 0)
  end

  return a
end

local function num(v)
  return type(v) == "number" and string.format("%.4g", v) or tostring(v)
end

-- The look of a badge as text lines for /fg mapdiag: the symbol it chose and every part with its texture or
-- atlas, shown state, size, alpha, tint and draw layer. Each line is built on its own and never raises.
function MI.Describe(badge)
  local lines = {}
  local function add(fn)
    local ok, text = pcall(fn)
    lines[#lines + 1] = ok and text or ("  error: " .. tostring(text))
  end
  add(function()
    local spec = badge.spec
    local known = {}
    for _, name in ipairs(spec.tried or {}) do
      known[#known + 1] = name .. "=" .. (atlasKnown(name) and "yes" or "no")
    end
    return string.format(
      "  symbol: kind=%s source=%s atlas=%s shape=%s letter=%s plate=%s disc=%s size=%s atlases: %s",
      spec.kind,
      spec.source,
      tostring(spec.atlas),
      tostring(spec.shape),
      spec.letter,
      spec.plate,
      badge.shape,
      num(badge.size),
      #known > 0 and table.concat(known, " ") or "none"
    )
  end)
  -- A font string has no atlas, and an unset one has no text: neither may fall through to a texture method.
  local function content(part)
    if part:GetObjectType() == "FontString" then
      return part:GetText()
    end
    return (part.GetAtlas and part:GetAtlas()) or part:GetTexture()
  end
  for _, name in ipairs({ "box", "sel", "ring", "plate", "icon", "glow", "letter" }) do
    add(function()
      local part = badge[name]
      local layer, sub = part:GetDrawLayer()
      local tint = part.GetVertexColor or part.GetTextColor
      local r, g, b, a
      if tint then
        r, g, b, a = tint(part)
      end
      return string.format(
        "  %s: %s shown=%s size=%sx%s alpha=%s color=%s,%s,%s,%s layer=%s/%s",
        name,
        tostring(content(part)),
        tostring(part:IsShown()),
        num(part:GetWidth()),
        num(part:GetHeight()),
        num(part:GetAlpha()),
        num(r),
        num(g),
        num(b),
        num(a),
        tostring(layer),
        tostring(sub)
      )
    end)
  end
  return lines
end
