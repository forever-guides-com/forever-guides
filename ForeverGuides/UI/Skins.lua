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
--   Skins.isForever()            true while the Forever look is in force. High contrast and
--                                colorblind mode win: there it behaves like flat.
--   Skins.current()              the entry in force (flat while one of those modes is on)
--   Skins.palette(token)         color override of the skin in force, nil for flat (Theme.rgb)
--   Skins.Apply(owner, kind, want)
--     kind "rock"  tiled stone texture behind the content of a window frame
--     kind "nine"  metal frame (NineSlice) on the edge overlay of a shell, surrounding the window
--                  (part.offset / part.outset per side, see buildNine)
--     kind "close" red close button art on a button
--     The part is built on first need and shown or hidden to match the skin (or `want`), so a
--     switch needs no rebuild. Returns the part while it is shown, nil when the skin is off or the
--     client lacks the art: the caller keeps its flat look then.
--   Skins.StyleTitle(fontString, role, family)   title font for the skin in force
--   Skins.Close(button)          dresses a window close button (follows the skin on every refresh)
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
    },
  },
}

ns.AddLocale("enUS", {
  ["settings.skin"] = "Window style",
  ["settings.skin.flat"] = "Flat",
  ["settings.skin.forever"] = "WoW Forever",
  ["settings.skinHint"] = "Forever: metal frame, stone, gold title\nHigh contrast and colorblind use Flat",
})
ns.AddLocale("deDE", {
  ["settings.skin"] = "Fensterstil",
  ["settings.skin.flat"] = "Flach",
  ["settings.skin.forever"] = "WoW Forever",
  ["settings.skinHint"] = "Forever: Metallrahmen, Fels, Goldtitel\nHoher Kontrast und Farbenblind nutzen Flach",
})

function Skins.cleanId(v)
  return Skins.list[v] and v or Skins.DEFAULT
end

function Skins.currentId()
  local s = ns.db and ns.db.settings
  return Skins.cleanId(s and s.skin)
end

-- The id in force: the two accessibility modes always get the flat look.
function Skins.activeId()
  local id = Skins.currentId()
  -- Theme.rgb asks on every call: the default skin never pays for the CVar lookup.
  if id == Skins.DEFAULT or Theme.highContrast() or Theme.colorblind() then
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
-- anchored outwards, so no piece covers content (the top band is as thick as the layout makes it,
-- the title strip of the window lies below it). It is a child of the shell's edge overlay, so it never changes an inner size.
-- nine.offset = how far the anchors of `nine` lie outside the window, nine.outset = how far the
-- outermost piece reaches (what the window needs to stay on screen), both { left, right, top, bottom }.
Skins.NINE_OVERLAP = 1
Skins.NINE_FALLBACK = { left = 8, right = 8, top = 28, bottom = 8 }
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

-- Offset and outset of `nine` per side, nil when a piece cannot be measured. The thickness of a
-- side is its edge piece (the top and bottom bands also count the corners, which are as high
-- as the band); the reach comes from the layout's own offsets of the corner anchors.
local function measureNine(nine)
  local top = pieceDim(nine, "TopEdge", "GetHeight")
  local bottom = pieceDim(nine, "BottomEdge", "GetHeight")
  local left = pieceDim(nine, "LeftEdge", "GetWidth")
  local right = pieceDim(nine, "RightEdge", "GetWidth")
  if not (top and bottom and left and right) then
    return nil
  end
  for _, name in ipairs({ "TopLeftCorner", "TopRightCorner" }) do
    top = math.max(top, pieceDim(nine, name, "GetHeight") or 0)
  end
  for _, name in ipairs({ "BottomLeftCorner", "BottomRightCorner" }) do
    bottom = math.max(bottom, pieceDim(nine, name, "GetHeight") or 0)
  end
  local thickness = { left = left, right = right, top = top, bottom = bottom }
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
    offset[side] = math.min(NINE_MAX, math.max(0, thickness[side] - near - Skins.NINE_OVERLAP))
    outset[side] = math.min(NINE_MAX, math.max(0, offset[side] + far))
  end
  return offset, outset
end

local function buildNine(edge)
  local nine = CreateFrame("Frame", nil, edge)
  nine:EnableMouse(false)
  local util = rawget(_G, "NineSliceUtil")
  local applied = type(util) == "table" and type(util.ApplyLayoutByName) == "function"
  if applied then
    applied = false
    for _, layout in ipairs(Skins.ART.nineLayouts) do
      if pcall(util.ApplyLayoutByName, nine, layout) then
        applied = true
        break
      end
    end
  end
  if not applied then
    nine:Hide()
    error("no usable NineSlice layout", 0)
  end
  local ok, offset, outset = pcall(measureNine, nine)
  if not (ok and offset) then
    Skins.failures.nineMeasure = ok and "piece sizes unreadable" or tostring(offset)
    ns.Log.warn("metal frame not measured, fixed insets used: %s", Skins.failures.nineMeasure)
    offset, outset = {}, {}
    for side, value in pairs(Skins.NINE_FALLBACK) do
      offset[side], outset[side] = value, value + NINE_FALLBACK_REACH
    end
  end
  nine.offset, nine.outset = offset, outset
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

-- Fonts ---------------------------------------------------------------------------------------

function Skins.StyleTitle(fs, role, family)
  if Skins.isForever() then
    local metrics = Skins.current().metrics
    local size = math.max(metrics.titleMinSize, Theme.fontSize(role))
    if fs:SetFont(metrics.titleFont, size, "") then
      fs:SetShadowOffset(1, -1)
      fs:SetShadowColor(0, 0, 0, 0.9)
      return
    end
  end
  Theme.applyFont(fs, role, family)
end

-- Window close buttons: the art of the skin replaces the "x" glyph, flat keeps it.
function Skins.Close(button)
  ns.Bind(button, function()
    local art = Skins.Apply(button, "close")
    local mark = button.glyph or button.icon
    if mark then
      mark:SetShown(art == nil)
    end
  end)
end
