-- Window styles ("skins"): the look of the window shell on top of the color theme.
--
--   flat     today's look: flat fills and 1 px edges (nothing in here is drawn for it)
--   forever  the look of the game's own windows: stone background, metal frame, gold title in
--            the game's display font, red close button. Blizzard art only, nothing is shipped.
--
--   Skins.list[id] = { id, nameKey, palette = { token = "#rrggbb" }, metrics = { ... } }
--   Skins.ORDER                  ids in the order of the settings dropdown
--   Skins.cleanId(v)             a known id, else the default
--   Skins.currentId()            the saved id (settings.skin, validated)
--   Skins.isForever()            true while the Forever look is in force. High contrast wins:
--                                there it behaves like flat. Colorblind mode keeps the chosen
--                                style and only swaps the red/green pair (UI/Theme.lua).
--   Skins.current()              the entry in force (flat while high contrast is on)
--   Skins.palette(token)         color override of the skin in force, nil for flat (Theme.rgb)
--   Skins.Apply(owner, kind, want)
--     kind "rock"  tiled stone texture behind the content of a window frame
--     kind "nine"  metal frame (NineSlice) on the edge overlay of a shell, surrounding the window
--                  (part.offset / part.outset per side, see buildNine)
--     kind "close" red close button art on a button
--     The part is built on first need and shown or hidden to match the skin (or `want`), so a
--     switch needs no rebuild. Returns the part while it is shown, nil when the skin is off or the
--     client lacks the art: the caller keeps its flat look then.
--   Skins.BandRect(edge)         the metal bar at the top of a shell (`edge` = shell.edge, the owner
--                                of the "nine" part): { top, bottom, height } in frame units, top and bottom
--                                measured upwards from the top edge of the window (top 0, bottom -height). nil while the metal frame is
--                                not in force (flat look, art missing), so a caller keeps its flat layout then.
--   Skins.NineOf(edge)           the built metal frame of a shell (shown or not), nil when none was built
--   Skins.StyleTitle(fontString, role, family[, maxSize])   title font for the skin in force, at most maxSize
--   Skins.Close(button)          dresses a window close button (follows the skin on every refresh)
--   Skins.CloseSize(band)        side of that button: the standard size, smaller inside the metal bar
local _, ns = ...
local Theme = ns.Theme

local Skins = { failures = {} }
ns.Skins = Skins

Skins.DEFAULT = "flat"
Skins.ORDER = { "flat", "forever" }

-- Client art. Atlas names and file paths as they exist in the Forever client.
Skins.ART = {
  rock = "Interface\\FrameGeneral\\UI-Background-Rock",
  nineLayouts = { "ButtonFrameTemplateNoPortrait", "Dialog" },
  close = {
    normal = "RedButton-Exit",
    pressed = "RedButton-exit-pressed",
    highlight = "RedButton-Highlight",
  },
}

Skins.list = {
  flat = {
    id = "flat",
    nameKey = "settings.skin.flat",
    palette = {},
    metrics = {},
  },
  forever = {
    id = "forever",
    nameKey = "settings.skin.forever",
    -- Dark warm surfaces under light text, gold for titles and highlights. Contrast of text,
    -- accents and the action color on every surface is checked in tests/test_skins.lua.
    palette = {
      bg = "#17130e",
      surface = "#1e1913",
      surface2 = "#28211a",
      surface3 = "#33291f",
      text = "#f5efe0",
      textSecondary = "#ddd2bb",
      textMuted = "#b8aa8f",
      accent = "#ffe27a",
      accent2 = "#ffd100",
      accentDim = "#a68a2e",
      action = "#7a1e16",
      actionHi = "#ff8f78",
    },
    metrics = {
      titleFont = "Fonts\\MORPHEUS.TTF",
      titleMinSize = 12,
      -- Multiplied onto the stone, so light text keeps its contrast on every spot of it.
      rockTint = { 0.55, 0.5, 0.45 },
      -- Title strip in the metal bar (UI/WindowShell.lua): margin = gap to the window edge, textPad = the title is at
      -- most bar height minus this tall, metal = height of the visible metal bar of the top edge (measured in the
      -- client: rim, streaks and lower rim, about 18 px; the tile around it is taller and carries clear padding), the
      -- bar of every window is this tall at most, gap = the least space above and below a control in the bar.
      -- backdrop = the dark metal of the bar interior (measured in the client): the title colors keep 4.5:1 on it
      -- (tests/test_skins.lua) and it fills the clear sliver at the inner edge of the sides. bleed = how far that
      -- fill reaches under the metal past the window (side) and past the upper edge of the bar (top). Both stay
      -- below the thickness of the metal; top is 0: nothing of the fill lies above the metal.
      bar = {
        margin = 8,
        textPad = 4,
        metal = 18,
        gap = 2,
        backdrop = "#403b36",
        bleed = { side = 3, top = 0 },
      },
    },
  },
}

ns.AddLocale("enUS", {
  ["settings.skin"] = "Window style",
  ["settings.skin.flat"] = "Flat",
  ["settings.skin.forever"] = "WoW Forever",
  ["settings.skinHint"] = "Forever: metal frame, stone, gold title\nHigh contrast uses Flat",
})
ns.AddLocale("deDE", {
  ["settings.skin"] = "Fensterstil",
  ["settings.skin.flat"] = "Flach",
  ["settings.skin.forever"] = "WoW Forever",
  ["settings.skinHint"] = "Forever: Metallrahmen, Fels, Goldtitel\nHoher Kontrast nutzt Flach",
})

function Skins.cleanId(v)
  return Skins.list[v] and v or Skins.DEFAULT
end

function Skins.currentId()
  local s = ns.db and ns.db.settings
  return Skins.cleanId(s and s.skin)
end

-- The id in force: high contrast always gets the flat look. Colorblind mode does not change the
-- style, its red/green swap is a token override above the skin palette.
function Skins.activeId()
  local id = Skins.currentId()
  if id == Skins.DEFAULT or Theme.highContrast() then
    return Skins.DEFAULT
  end
  return id
end

function Skins.current()
  return Skins.list[Skins.activeId()]
end

function Skins.isForever()
  return Skins.activeId() == "forever"
end

function Skins.palette(token)
  return Skins.current().palette[token]
end

-- Parts -------------------------------------------------------------------------------------

-- Atlas known to the client? Without the API the question cannot be answered, SetAtlas is
-- guarded anyway.
local function atlasKnown(name)
  local api = rawget(_G, "C_Texture")
  if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then
    return true
  end
  local ok, info = pcall(api.GetAtlasInfo, name)
  return ok and info ~= nil
end

local function buildRock(frame)
  local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  tex:SetAllPoints()
  tex:SetTexture(Skins.ART.rock, "REPEAT", "REPEAT")
  tex:SetHorizTile(true)
  tex:SetVertTile(true)
  tex:SetVertexColor(unpack(Skins.list.forever.metrics.rockTint))
  return tex
end

-- The metal frame surrounds the window: its pieces are measured after the layout and `nine` is
-- anchored outwards on the sides and the bottom, so no piece covers content. The top is the one bar of the window: the
-- top anchor of `nine` lies at the upper edge of the window and the layout draws the rim of its top pieces right there
-- (the tile carries clear padding above the rim, the layout lets the corners hang 16 px over the frame). The metal
-- bar below the rim is the title bar of the window: Skins.bandHeight tall, nothing of the metal lies above the
-- window or below the bar. The top pieces keep the size of their art, a stretch would move the rim. It is a child of
-- the shell's edge overlay, so it never changes an inner size.
-- nine.offset = how far the anchors of `nine` lie outside the window, nine.outset = how far the
-- outermost visible piece reaches (what the window needs to stay on screen), both { left, right, top, bottom }.
Skins.NINE_OVERLAP = 1
-- A piece is as large as its art tile, and a tile carries clear padding around the rim it shows. The
-- size of a tile therefore says little about the metal, so the anchor of a side never lies further out
-- than this (the same as the fixed inset used when nothing can be measured): the window and the metal
-- stay together whatever the tiles measure.
Skins.NINE_MAX_OFFSET = 8
-- The top is not listed: its anchor lies on the upper edge of the window.
Skins.NINE_FALLBACK = { left = 8, right = 8, bottom = 8 }
-- Typical reach of a layout piece past the frame (12 to 16 px), used only when nothing can be measured.
local NINE_FALLBACK_REACH = 16
local NINE_MAX = 96

-- Width or height of a layout piece (`getter` = "GetWidth" or "GetHeight"), nil when unreadable.
local function pieceDim(nine, name, getter)
  local piece = nine[name]
  if type(piece) ~= "table" or type(piece[getter]) ~= "function" then
    return nil
  end
  local ok, v = pcall(piece[getter], piece)
  if ok and type(v) == "number" and v > 0 and v < NINE_MAX then
    return v
  end
end

-- How far the anchor of a corner lies outside the frame on one side (negative = inside).
local function pieceReach(nine, name, side)
  local piece = nine[name]
  if type(piece) ~= "table" or type(piece.GetPoint) ~= "function" then
    return nil
  end
  local ok, point, _, _, x, y = pcall(piece.GetPoint, piece, 1)
  if not ok or type(point) ~= "string" then
    return nil
  end
  if side == "left" and point:find("LEFT") then
    return -(tonumber(x) or 0)
  elseif side == "right" and point:find("RIGHT") then
    return tonumber(x) or 0
  elseif side == "top" and point:find("TOP") then
    return tonumber(y) or 0
  elseif side == "bottom" and point:find("BOTTOM") then
    return -(tonumber(y) or 0)
  end
  return 0
end

-- Height of the metal bar of the window that owns `owner` (the edge overlay of a shell): the visible metal of the top
-- edge, at most as tall as the title area of the window (`owner.stripHeight`) so the bar never covers content, and at
-- most as tall as the art of the top edge (`tile`, when known).
function Skins.bandHeight(owner, tile)
  local height = Skins.list.forever.metrics.bar.metal
  local strip = owner and owner.stripHeight
  if type(strip) == "number" and strip > 0 then
    height = math.min(height, strip)
  end
  if type(tile) == "number" and tile > 0 then
    height = math.min(height, tile)
  end
  return height
end

-- Offset and outset of `nine` per side, nil when a piece cannot be measured. The thickness of a side is its
-- edge piece (the bottom band also counts the corners); the reach comes from the layout's own offsets of the corner
-- anchors. The top anchor lies on the upper edge of the window whatever the pieces measure: the rim is drawn there and
-- the hang of the corners over it is clear padding, so nothing visible lies above the window (outset.top = 0).
local function measureNine(nine)
  local bottom = pieceDim(nine, "BottomEdge", "GetHeight")
  local left = pieceDim(nine, "LeftEdge", "GetWidth")
  local right = pieceDim(nine, "RightEdge", "GetWidth")
  if not (pieceDim(nine, "TopEdge", "GetHeight") and bottom and left and right) then
    return nil
  end
  for _, name in ipairs({ "BottomLeftCorner", "BottomRightCorner" }) do
    bottom = math.max(bottom, pieceDim(nine, name, "GetHeight") or 0)
  end
  local thickness = { left = left, right = right, bottom = bottom }
  local corners = {
    left = { "TopLeftCorner", "BottomLeftCorner" },
    right = { "TopRightCorner", "BottomRightCorner" },
    top = { "TopLeftCorner", "TopRightCorner" },
    bottom = { "BottomLeftCorner", "BottomRightCorner" },
  }
  local offset, outset = {}, {}
  for side, names in pairs(corners) do
    local near, far
    for _, name in ipairs(names) do
      local reach = pieceReach(nine, name, side)
      if reach then
        near = near and math.min(near, reach) or reach
        far = far and math.max(far, reach) or reach
      end
    end
    -- Without a readable anchor the pieces are taken to sit on the frame (reach 0).
    near, far = near or 0, far or 0
    if side == "top" then
      offset.top, outset.top = 0, 0
    else
      offset[side] = math.min(Skins.NINE_MAX_OFFSET, math.max(0, thickness[side] - near - Skins.NINE_OVERLAP))
      outset[side] = math.min(NINE_MAX, math.max(0, offset[side] + far))
    end
  end
  return offset, outset
end

local NINE_PIECES = {
  "TopLeftCorner",
  "TopRightCorner",
  "BottomLeftCorner",
  "BottomRightCorner",
  "TopEdge",
  "BottomEdge",
  "LeftEdge",
  "RightEdge",
}

-- The first atlas a layout needs that the client does not know, nil when all eight are there (or cannot be
-- told). A missing atlas draws nothing, so a frame without one of its pieces would hang open.
local function missingNineAtlas(nine, layout)
  local layouts = rawget(_G, "NineSliceLayouts")
  local spec = type(layouts) == "table" and layouts[layout] or nil
  for _, name in ipairs(NINE_PIECES) do
    local piece = nine[name]
    local atlas = type(spec) == "table" and type(spec[name]) == "table" and spec[name].atlas or nil
    if type(atlas) ~= "string" and type(piece) == "table" and type(piece.GetAtlas) == "function" then
      local ok, got = pcall(piece.GetAtlas, piece)
      atlas = ok and type(got) == "string" and got or nil
    end
    if type(atlas) == "string" and not atlasKnown(atlas) then
      return atlas
    end
  end
end

-- A frame with the first layout of the list that applies and has all of its art, nil with the reason otherwise.
-- One frame takes the layouts in turn (a later layout replaces the pieces of an earlier one).
local function applyNineLayout(edge)
  local util = rawget(_G, "NineSliceUtil")
  if type(util) ~= "table" or type(util.ApplyLayoutByName) ~= "function" then
    return nil, "no usable NineSlice layout"
  end
  local nine = CreateFrame("Frame", nil, edge)
  nine:EnableMouse(false)
  local why = "no usable NineSlice layout"
  for _, layout in ipairs(Skins.ART.nineLayouts) do
    local ok, err = pcall(util.ApplyLayoutByName, nine, layout)
    local missing = ok and missingNineAtlas(nine, layout)
    if ok and not missing then
      nine.layoutName = layout
      return nine
    end
    why = missing and ("atlas " .. missing .. " missing") or tostring(err)
  end
  nine:Hide()
  return nil, why
end

local function buildNine(edge)
  local nine, why = applyNineLayout(edge)
  if not nine then
    error(why, 0)
  end
  local height = Skins.bandHeight(edge, pieceDim(nine, "TopEdge", "GetHeight"))
  local ok, offset, outset = pcall(measureNine, nine)
  if not (ok and offset) then
    Skins.failures.nineMeasure = ok and "piece sizes unreadable" or tostring(offset)
    ns.Log.warn("metal frame not measured, fixed insets used: %s", Skins.failures.nineMeasure)
    offset, outset = {}, {}
    for side, value in pairs(Skins.NINE_FALLBACK) do
      offset[side], outset[side] = value, value + NINE_FALLBACK_REACH
    end
    offset.top, outset.top = 0, 0
  end
  nine.offset, nine.outset = offset, outset
  -- The metal bar: from the upper edge of the window (the rim) down by the bar height, inside the window.
  nine.band = { top = 0, bottom = -height, height = height }
  nine:SetPoint("TOPLEFT", edge, "TOPLEFT", -offset.left, offset.top)
  nine:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", offset.right, -offset.bottom)
  return nine
end

local function buildClose(button)
  local names = Skins.ART.close
  if not atlasKnown(names.normal) then
    error("atlas " .. names.normal .. " missing", 0)
  end
  local art = CreateFrame("Frame", nil, button)
  art:SetAllPoints()
  art:EnableMouse(false)
  art:SetFrameLevel(button:GetFrameLevel() + 2)
  local normal = art:CreateTexture(nil, "ARTWORK")
  normal:SetAllPoints()
  normal:SetAtlas(names.normal)
  local pressed, glow
  if atlasKnown(names.pressed) then
    pressed = art:CreateTexture(nil, "ARTWORK")
    pressed:SetAllPoints()
    pressed:SetAtlas(names.pressed)
    pressed:Hide()
  end
  if atlasKnown(names.highlight) then
    glow = art:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetAtlas(names.highlight)
    glow:SetBlendMode("ADD")
    glow:Hide()
  end
  button:HookScript("OnMouseDown", function()
    if pressed then
      normal:Hide()
      pressed:Show()
    end
  end)
  button:HookScript("OnMouseUp", function()
    normal:Show()
    if pressed then
      pressed:Hide()
    end
  end)
  button:HookScript("OnEnter", function()
    if glow then
      glow:Show()
    end
  end)
  button:HookScript("OnLeave", function()
    if glow then
      glow:Hide()
    end
  end)
  return art
end

local BUILD = { rock = buildRock, nine = buildNine, close = buildClose }
local parts = setmetatable({}, { __mode = "k" })

function Skins.Apply(owner, kind, want)
  if want == nil then
    want = Skins.isForever()
  end
  local own = parts[owner]
  if not own then
    own = {}
    parts[owner] = own
  end
  local part = own[kind]
  if part == nil and want then
    local ok, built = pcall(BUILD[kind], owner)
    if not ok then
      Skins.failures[kind] = tostring(built)
      ns.Log.warn("skin part %s not built: %s", kind, tostring(built))
    end
    part = ok and built or false
    own[kind] = part
  end
  if part then
    part:SetShown(want)
  end
  return want and part or nil
end

-- The band of the metal frame for the owner of the "nine" part (the edge overlay of a shell), nil unless
-- the frame is shown. A copy, so a caller cannot change the measurement.
function Skins.BandRect(owner)
  local own = parts[owner]
  local nine = Skins.isForever() and own and own.nine
  local band = nine and nine:IsShown() and nine.band
  if not band then
    return nil
  end
  return { top = band.top, bottom = band.bottom, height = band.height }
end

-- The built metal frame of an owner (the edge overlay of a shell), shown or not, nil when none was built. For the
-- measurement report (Modules/FrameStatus.lua), read only.
function Skins.NineOf(owner)
  local own = parts[owner]
  return own and own.nine or nil
end

-- Fonts ---------------------------------------------------------------------------------------

-- maxSize caps the title (a title in the metal band must fit the band), never below the font floor.
function Skins.StyleTitle(fs, role, family, maxSize)
  if Skins.isForever() then
    local metrics = Skins.current().metrics
    local size = math.max(metrics.titleMinSize, Theme.fontSize(role))
    if maxSize then
      size = math.min(size, math.max(Theme.fontFloor(), maxSize))
    end
    if fs:SetFont(metrics.titleFont, size, "") then
      fs:SetShadowOffset(1, -1)
      fs:SetShadowColor(0, 0, 0, 0.9)
      return
    end
  end
  Theme.applyFont(fs, role, family)
end

-- Side of the close button of a window: the standard size, in the metal bar (`band` = Skins.BandRect) at most the bar
-- minus the gap above and below.
function Skins.CloseSize(band)
  local size = ns.W.CLOSE_SIZE
  if not band then
    return size
  end
  local bar = Skins.list.forever.metrics.bar
  return math.min(size, math.max(12, band.height - 2 * bar.gap))
end

-- Window close buttons: the art of the skin replaces the "x" glyph, flat keeps it. Inside the metal bar the button
-- is sized to the bar.
function Skins.Close(button)
  ns.Bind(button, function()
    local shell = ns.WindowShell.OfTitleBar(button:GetParent())
    if shell then
      Skins.Apply(shell.edge, "nine")
      local side = Skins.CloseSize(Skins.BandRect(shell.edge))
      button:SetSize(side, side)
    end
    local art = Skins.Apply(button, "close")
    local mark = button.glyph or button.icon
    if mark then
      mark:SetShown(art == nil)
    end
  end)
end
