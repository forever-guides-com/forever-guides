-- Guild members on the real minimap: source "guild" of the pin layer (MinimapLayer.lua). The positions come
-- from ns.GuildMapStore, joined with the guild list (class, rank, level, online); the selection and the look
-- rules are in MinimapGuildLogic.lua and WorldMapGuildLogic.lua. The symbol is the one of the world map in
-- a small form: a hexagon with a dark contour in the class color, a hollow one (a ring) for an old or odd
-- report, a diamond for an approximate place, a bigger hexagon with a number for several members close
-- together. Colour never carries the state alone: shape and fill do. The pins share the cap of the layer
-- (the gathering pins come first), only members on the player's continent within the reach show, nothing in
-- instances, members of the player's group are left out. The layer frame has no mouse, so there is no
-- tooltip: the details are on the world map and in the member list. The source wants the layer only while
-- the option and the receive consent are on. It reads no secret value and builds no texture in combat
-- (a pin without parts waits for the next layout).
local _, ns = ...
local Layer, MGL, GLG = ns.MinimapLayer, ns.MinimapGuildLogic, ns.WorldMapGuildLogic
local Store, Consent, GD, PN, Theme = ns.GuildMapStore, ns.Consent, ns.GuildData, ns.PlayerName, ns.Theme

local MG = {}
ns.MinimapGuildSource = MG

local MEDIA = "Interface\\AddOns\\ForeverGuides\\Media\\"
local SHAPES = { hexagon = MEDIA .. "map_hexagon.png", diamond = MEDIA .. "map_diamond.png" }
local TICK_W, TICK_H, TICK_GAP = 3, 2, 1
local MAX_TICKS = 3

local function receiving()
  return Consent.Allows("guildMap", "receive", "guild")
end

-- Does the player want guild members on the minimap?
function MG.Enabled()
  return GLG.Current().showMini and receiving()
end

-- Parts ---------------------------------------------------------------------------------------------

-- The textures and the text of one pin, made once on the layer frame. nil in combat.
local function build(pin, host)
  if ns.InCombat() then
    return nil
  end
  local parts = {
    edge = host:CreateTexture(nil, "ARTWORK", nil, 1),
    body = host:CreateTexture(nil, "ARTWORK", nil, 2),
    hole = host:CreateTexture(nil, "ARTWORK", nil, 3),
    ticks = {},
    count = host:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
    label = host:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
  }
  for i = 1, MAX_TICKS do
    parts.ticks[i] = {
      edge = host:CreateTexture(nil, "ARTWORK", nil, 4),
      bar = host:CreateTexture(nil, "ARTWORK", nil, 5),
    }
  end
  for _, fs in ipairs({ parts.count, parts.label }) do
    Theme.applyFont(fs, "micro", "body")
    fs:SetTextColor(Theme.color("text"))
  end
  pin.guild = parts
  return parts
end

local function hideParts(pin)
  local parts = pin.guild
  if not parts then
    return
  end
  parts.edge:Hide()
  parts.body:Hide()
  parts.hole:Hide()
  parts.count:Hide()
  parts.label:Hide()
  for _, tick in ipairs(parts.ticks) do
    tick.edge:Hide()
    tick.bar:Hide()
  end
end

local function shape(tex, kind, anchor, size, r, g, b, a)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", anchor, "CENTER")
  tex:SetTexture(SHAPES[kind])
  tex:SetSize(size, size)
  tex:SetVertexColor(r, g, b, a)
  tex:Show()
end

local function paintTicks(parts, anchor, spec, size, alpha)
  local bg = { Theme.color("bg", 0.95 * alpha) }
  for i, tick in ipairs(parts.ticks) do
    local on = i <= spec.ticks
    tick.edge:SetShown(on)
    tick.bar:SetShown(on)
    if on then
      local x = (i - (spec.ticks + 1) / 2) * (TICK_W + TICK_GAP)
      local y = size / 2 + MGL.CONTOUR + 1
      tick.edge:ClearAllPoints()
      tick.edge:SetPoint("BOTTOM", anchor, "CENTER", x, y - 1)
      tick.edge:SetSize(TICK_W + 2, TICK_H + 2)
      tick.edge:SetColorTexture(unpack(bg))
      tick.bar:ClearAllPoints()
      tick.bar:SetPoint("BOTTOM", anchor, "CENTER", x, y)
      tick.bar:SetSize(TICK_W, TICK_H)
      local r, g, b = Theme.color("accent2")
      tick.bar:SetColorTexture(r, g, b, alpha)
    end
  end
end

-- Called by the layer for every shown pin: draws pin.custom.spec at the anchor. false when the parts
-- cannot be made now (combat).
local function paint(pin, host, anchor, alpha, scale)
  local parts = pin.guild or build(pin, host)
  if not parts then
    return false
  end
  local custom = pin.custom
  local spec, color = custom.spec, custom.color
  local size = math.max(4, math.floor(spec.size * scale + 0.5))
  local bgr, bgg, bgb = Theme.color("bg")
  local fade = spec.hollow and MGL.HOLLOW_ALPHA * alpha or alpha
  local c = MGL.CONTOUR
  if spec.cluster then
    size = math.floor(size * MGL.CLUSTER_FACTOR + 0.5)
    local r, g, b = Theme.color("accent2")
    shape(parts.edge, "hexagon", anchor, size + 2 * c, r, g, b, fade)
    shape(parts.body, "hexagon", anchor, size, bgr, bgg, bgb, fade)
    parts.hole:Hide()
    parts.count:ClearAllPoints()
    parts.count:SetPoint("CENTER", anchor, "CENTER")
    parts.count:SetText(tostring(spec.cluster))
    parts.count:SetAlpha(fade)
    parts.count:Show()
  else
    shape(parts.edge, spec.shape, anchor, size + 2 * c, bgr, bgg, bgb, fade)
    shape(parts.body, spec.shape, anchor, size, color[1], color[2], color[3], fade)
    if spec.hollow then
      shape(parts.hole, spec.shape, anchor, math.max(2, math.floor(size * 0.5)), bgr, bgg, bgb, fade)
    else
      parts.hole:Hide()
    end
    parts.count:Hide()
  end
  paintTicks(parts, anchor, spec, size, fade)
  parts.label:ClearAllPoints()
  parts.label:SetPoint("LEFT", anchor, "CENTER", size / 2 + c + 2, 0)
  parts.label:SetText(spec.text)
  parts.label:SetAlpha(fade)
  parts.label:SetShown(spec.text ~= "")
  return true
end

-- Data ---------------------------------------------------------------------------------------------

local function colorOf(member, opts)
  local WMG = ns.WorldMapGuildPins
  if WMG and WMG.ClassColor then
    return WMG.ClassColor(member, opts)
  end
  return { Theme.color("textSecondary") }
end

local function parentOf(id)
  local api = rawget(_G, "C_Map")
  local info = type(api) == "table" and Layer.Call(api.GetMapInfo, id) or nil
  return type(info) == "table" and Layer.Readable(info.parentMapID) or nil
end

-- Is the member in the player's party or raid? A secret answer counts as no.
local function inGroup(name)
  for _, api in ipairs({ "UnitInParty", "UnitInRaid" }) do
    local value = Layer.Call(rawget(_G, api), name)
    if not Layer.Secret(value) and value == true then
      return true
    end
  end
  return false
end

local function rosterByKey()
  local snap = GD.Get()
  local out = {}
  for _, m in ipairs(snap and snap.members or {}) do
    out[m.key] = m
  end
  return out
end

local function source(view, add)
  local opts = GLG.Current()
  if not (opts.showMini and receiving()) then
    return
  end
  local entries = Store.All()
  if #entries == 0 then
    return
  end
  local me = PN.Self()
  local ctx = {
    opts = opts,
    cont = view.cont,
    wx = view.wx,
    wy = view.wy,
    reach = view.reach,
    roster = rosterByKey(),
    isSelf = function(name)
      return PN.Equal(name, me)
    end,
    inGroup = inGroup,
    frameOf = Layer.ZoneFrame,
    parentOf = parentOf,
  }
  local items = MGL.Collect(entries, ctx)
  local yards = MGL.GroupYards(MGL.Size(opts.miniSize), view.radius, view.halfW)
  for _, group in ipairs(MGL.Groups(items, ctx, yards, opts.group)) do
    local spec = MGL.Spec(group, opts)
    local custom = {
      size = spec.size,
      spec = spec,
      color = colorOf(spec.member, opts),
      paint = paint,
      hide = hideParts,
    }
    if add(group.wx, group.wy, nil, "guild", custom) == false then
      break
    end
  end
end

Layer.RegisterSource("guild", source, MG.Enabled)

-- Switches and data ----------------------------------------------------------------------------------

-- New, changed, removed or expired positions (debounced by the store) and a new guild list: the next look
-- lays the pins out again. Reports that age from current to old are picked up by the layer's own refresh.
local function relayout()
  Layer.Invalidate()
end

-- The layer frame is only made outside of combat; PLAYER_REGEN_ENABLED applies what waited.
local function apply()
  if not ns.InCombat() then
    Layer.Apply()
  end
  Layer.Invalidate()
end

ns.On("FG_GUILDMAP_UPDATE", relayout)
ns.On("FG_GUILD_UPDATE", relayout)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.guildMap") then
    apply()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == "guildMap" then
    apply()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == "guildMap" then
    apply()
  end
end)
