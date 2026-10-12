-- Map image mode of the map page. The art layer of a zone map looks like the unexplored map, the
-- colored areas are overlay pictures on top of it. "Revealed" (default) draws all overlays of the
-- zone from the load-on-demand add-on ForeverGuides_MapData (docs/MAPOVERLAY-FORMAT.md), "Exploration"
-- draws only the pieces the player explored (C_MapExplorationInfo). Both go through MR.Draw. The
-- calculation lives in ns.MapRevealLogic; this file holds the texture pool, the data access with its
-- lazy loading and the switch with the data banner.
local _, ns = ...
local W = ns.W
local RL = ns.MapRevealLogic

local MR = {}
ns.MapReveal = MR

MR.ADDON = "ForeverGuides_MapData"
MR.ROW_W = 212
-- Draw sub-levels on the canvas: the map tiles first, the overlay pictures on them. Pins, route and
-- markers are frames above the canvas, so they always lie on top of both.
MR.BASE_SUBLEVEL, MR.SUBLEVEL = 1, 2

ns.AddLocale("enUS", {
  ["map.reveal.on"] = "Revealed",
  ["map.reveal.onTip"] = "All areas of the zone map in color.",
  ["map.reveal.explore"] = "Exploration",
  ["map.reveal.exploreTip"] = "Zone view: only the areas you explored, the rest dark.",
  ["map.reveal.pkg"] = "Map data",
})
ns.AddLocale("deDE", {
  ["map.reveal.on"] = "Aufgedeckt",
  ["map.reveal.onTip"] = "Alle Gebiete der Zonenkarte in Farbe.",
  ["map.reveal.explore"] = "Erkundung",
  ["map.reveal.exploreTip"] = "Zonenansicht: nur deine erkundeten Gebiete, der Rest dunkel.",
  ["map.reveal.pkg"] = "Kartendaten",
})

-- Setting ----------------------------------------------------------------------------------------

function MR.Revealed()
  return ns.Store.get("settings.mapReveal") ~= false
end

function MR.SetRevealed(on)
  ns.Store.set("settings.mapReveal", on and true or false)
end

-- Data -------------------------------------------------------------------------------------------

-- One load attempt per session: a data add-on that is missing or off does not appear without the
-- banner button.
local attempted = false
-- artId -> { list = overlay list of the data, pieces = draw commands }
local cache = {}

local function overlays()
  local all = rawget(ns, "MapOverlays")
  return type(all) == "table" and all or nil
end

function MR.Available()
  return overlays() ~= nil
end

-- True when the data is there. Loads the add-on once when it is switched on and not loaded yet; a
-- missing or switched off add-on is left to the banner.
function MR.Ensure()
  if overlays() then
    return true
  end
  local package = ns.PackageUI
  if attempted or not package or package.State(MR.ADDON) ~= "idle" then
    return false
  end
  local ok, reason = package.Enable(MR.ADDON)
  attempted = reason ~= "COMBAT"
  return ok and overlays() ~= nil
end

-- True when the banner for the data add-on should be offered: the data is not there and either a
-- zone map needs it or the add-on is missing or switched off. A switched on add-on that is not
-- loaded yet is loaded by the first zone map, no banner before that.
function MR.BannerWanted(zoomed)
  if overlays() then
    return false
  end
  local state = ns.PackageUI.State(MR.ADDON)
  return zoomed or state == "off" or state == "missing"
end

-- Draw commands of all overlays of the map art, calculated once per art id. nil without the data
-- (the map then shows the plain tiles), an empty list for an art without overlays.
function MR.Pieces(artId)
  if type(artId) ~= "number" or not MR.Ensure() then
    return nil
  end
  local list = overlays()[artId]
  if type(list) ~= "table" then
    return {}
  end
  local entry = cache[artId]
  if not entry or entry.list ~= list then
    entry = { list = list, pieces = RL.Pieces(list) }
    cache[artId] = entry
  end
  return entry.pieces
end

-- Forgets the load attempt and the calculated lists (tests).
function MR.Reset()
  attempted = false
  cache = {}
end

-- Drawing ----------------------------------------------------------------------------------------

-- The box the art is drawn into, in canvas pixels: x, y, w, h. Default is the whole canvas.
local function boxOf(canvas, box)
  if box then
    return box.x, box.y, box.w, box.h
  end
  return 0, 0, canvas:GetWidth(), canvas:GetHeight()
end

-- Lays the base tiles of an art over the canvas (box: a rectangle of it, default all of it). The art
-- is { layer = { layerWidth, layerHeight, tileWidth, tileHeight }, textures = file ids row by row}, as
-- MapWorld.LoadArt returns it; a dungeon floor has the same shape. Edge tiles are cropped to the
-- layer size, the rest of a tile is padding. The textures sit in the pool canvas.artTiles; art == nil
-- hides them. opts: alpha (default 1), shade (vertex color 0..1, default 1), box.
-- Returns the number of textures in use.
function MR.DrawBase(canvas, art, opts)
  opts = opts or {}
  local pool = canvas.artTiles
  if not pool then
    pool = {}
    canvas.artTiles = pool
  end
  local used = 0
  if art then
    local layer = art.layer
    local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
    local cols, rows = math.ceil(lw / tw), math.ceil(lh / th)
    local bx, by, bw, bh = boxOf(canvas, opts.box)
    local sx, sy = bw / lw, bh / lh
    local shade = opts.shade or 1
    for i, fileId in ipairs(art.textures) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      if row >= rows then
        break
      end
      if type(fileId) == "number" and fileId > 0 then
        used = used + 1
        local tile = pool[used]
        if not tile then
          tile = canvas:CreateTexture(nil, "BACKGROUND", nil, MR.BASE_SUBLEVEL)
          pool[used] = tile
        end
        local visW, visH = math.min(tw, lw - col * tw), math.min(th, lh - row * th)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", bx + col * tw * sx, -(by + row * th * sy))
        tile:SetSize(visW * sx, visH * sy)
        tile:SetTexCoord(0, visW / tw, 0, visH / th)
        tile:SetTexture(fileId)
        tile:SetAlpha(opts.alpha or 1)
        tile:SetVertexColor(shade, shade, shade)
        tile:Show()
      end
    end
  end
  for i = used + 1, #pool do
    pool[i]:Hide()
  end
  return used
end

-- Hands the file memory of both pools back (the canvas is hidden or shows another map). The
-- textures stay in the pools for the next map.
function MR.ReleaseTextures(canvas)
  for _, pool in ipairs({ canvas.artTiles or {}, canvas.overlayTiles or {} }) do
    for _, tex in ipairs(pool) do
      tex:SetTexture(nil)
      tex:Hide()
    end
  end
end

-- Draws the commands over the canvas, which shows the whole art layer stretched to its size (or to
-- `box`, see MR.DrawBase). The textures sit in a pool on the canvas (canvas.overlayTiles) that is
-- reused from zone to zone and never grows past RL.MAX_PIECES; the list order is the stacking
-- order. art or pieces == nil hides everything. Returns the number of textures in use.
function MR.Draw(canvas, art, pieces, alpha, box)
  local pool = canvas.overlayTiles
  if not pool then
    pool = {}
    canvas.overlayTiles = pool
  end
  local used = 0
  if art and pieces then
    local layer = art.layer
    local bx, by, cw, ch = boxOf(canvas, box)
    for _, piece in ipairs(pieces) do
      if used >= RL.MAX_PIECES then
        break
      end
      used = used + 1
      local tex = pool[used]
      if not tex then
        tex = canvas:CreateTexture(nil, "BACKGROUND", nil, MR.SUBLEVEL)
        pool[used] = tex
      end
      local left, top, w, h = RL.Place(piece, layer.layerWidth, layer.layerHeight, cw, ch)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", bx + left, -(by + top))
      tex:SetSize(w, h)
      tex:SetTexCoord(0, piece.u, 0, piece.v)
      tex:SetTexture(piece.id)
      tex:SetAlpha(alpha or 1)
      tex:Show()
    end
  end
  for i = used + 1, #pool do
    pool[i]:Hide()
  end
  return used
end

-- Switch and banner ------------------------------------------------------------------------------

-- ctx = {
--   toolbar     parent frame of the controls
--   changed()   the mode changed or the data arrived: the page paints again
--   resized()   optional, the banner changed its height on its own
-- }
-- Returns the controller: row (the two buttons, place it with row:SetWidthAvailable), banner (the
-- ns.PackageUI banner for the data add-on), Paint (shows the chosen button, also after a change of
-- the setting from elsewhere).
function MR.Attach(ctx)
  local ctl = {}
  local rings = {}

  function ctl.Paint()
    local on = MR.Revealed()
    rings.reveal.show(on)
    rings.explore.show(not on)
  end

  local function choose(on)
    if MR.Revealed() ~= on then
      MR.SetRevealed(on)
      ctl.Paint()
      ctx.changed()
    end
  end

  ctl.row = ns.FlowLayout.ButtonRow(ctx.toolbar, {
    {
      id = "reveal",
      key = "map.reveal.on",
      width = 100,
      tooltip = "map.reveal.on",
      tooltipText = "map.reveal.onTip",
      onClick = function()
        choose(true)
      end,
    },
    {
      id = "explore",
      key = "map.reveal.explore",
      width = 100,
      tooltip = "map.reveal.explore",
      tooltipText = "map.reveal.exploreTip",
      onClick = function()
        choose(false)
      end,
    },
  }, { gap = 4 })
  -- The chosen button carries a ring: a shape, not only a color.
  for _, id in ipairs({ "reveal", "explore" }) do
    rings[id] = W.Border(ctl.row:GetButton(id), "accent2", 1, 2)
  end
  ctl.Paint()
  ns.On("FG_UI_REFRESHED", ctl.Paint)

  ctl.banner = ns.PackageUI.Banner(ctx.toolbar, MR.ADDON, {
    labelKey = "map.reveal.pkg",
    onLoaded = ctx.changed,
    onResize = ctx.resized,
  })
  return ctl
end
