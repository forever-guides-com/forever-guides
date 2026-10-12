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
})
ns.AddLocale("deDE", {
  ["map.kind.inn"] = "Gasthaus",
})

-- Kinds in legend order. The data (Data\Travel.lua k) uses city, flightMaster, harbor,
-- instanceEntrance, landmark, tram and zeppelinTower; portal and inn are drawn when places of
-- that kind show up.
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
  landmark = "textMuted",
  inn = "sectionAvailable",
}

-- The faction frame: Alliance blue, Horde red, everything else (both factions) gold.
local FRAME = { A = "alliance", H = "horde" }

MI.DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
MI.RING = 2 -- width of the faction frame around the symbol
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

  -- kind: a data kind, faction: "A" | "H" | "B", size: edge of the symbol without the frame.
  function b:Set(kind, faction, size, estimated)
    local spec = MI.Spec(kind)
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
      self.letter:Show()
    end
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
