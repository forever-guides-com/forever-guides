-- What the symbol in front of an element of the layout list stands for, without WoW API: the spell, item, equipment
-- slot or weapon hand an element points at, else the glyph of its type. ElementIcon.lua turns a target into a
-- texture. The props are read as they are saved, a missing or broken field never raises.
local _, ns = ...

local EI = {
  -- Glyph (name of ns.UI_ICONS) per element type, `fallback` for any other type.
  GLYPHS = {
    group = "folder",
    ring = "marker",
    shape = "star",
    cross = "pin",
    gcd = "history",
    cast = "history",
    swing = "history",
    health = "info",
    power = "info",
    range = "info",
    trail = "play",
    click = "play",
    aura = "tag",
    weapon = "star-outline",
    spellcd = "history",
    itemcount = "tag",
  },
  FALLBACK = "tag",
  -- Equipment slots of the main and the off hand weapon (the slot ids the client uses).
  WEAPON_SLOT = { main = 16, off = 17 },
}
ns.ElementIconLogic = EI

local function whole(v)
  return type(v) == "number" and v == v and v > 0 and v < 2 ^ 31 and math.floor(v) or 0
end

-- The spell a spell-like element means: the exact id for the exact rank choice, else the base id.
local function spellOf(p, fallback)
  local base = whole(p.spellBase)
  local id = base
  if p.rankMode == "exact" then
    local exact = whole(p.spellExact)
    id = exact > 0 and exact or base
  end
  return id > 0 and id or fallback
end

-- The glyph name of an element type.
function EI.GlyphOf(kind)
  return EI.GLYPHS[kind] or EI.FALLBACK
end

local function glyph(kind)
  return { kind = "glyph", glyph = EI.GlyphOf(kind) }
end

-- The target of an element of type `kind` with `props`: { kind = "spell", id } | { kind = "item", id } |
-- { kind = "slot", slot } | { kind = "glyph", glyph }. Nothing chosen gives the glyph of the type.
function EI.Target(kind, props)
  local p = type(props) == "table" and props or {}
  if kind == "weapon" or (kind == "aura" and p.source == "weapon") then
    return { kind = "slot", slot = EI.WEAPON_SLOT[p.weaponHand == "off" and "off" or "main"] }
  elseif kind == "aura" then
    local id = spellOf(p, whole(p.procAuraId))
    if id > 0 then
      return { kind = "spell", id = id }
    end
  elseif kind == "spellcd" then
    if p.source == "item" then
      local itemId = whole(p.itemId)
      if p.itemMode == "id" and itemId > 0 then
        return { kind = "item", id = itemId }
      elseif p.itemMode ~= "id" then
        local slot = whole(p.itemSlot)
        if slot > 0 then
          return { kind = "slot", slot = slot }
        end
      end
    else
      local id = spellOf(p, 0)
      if id > 0 then
        return { kind = "spell", id = id }
      end
    end
  elseif kind == "itemcount" then
    local id = whole(p.itemId)
    if id > 0 then
      return { kind = "item", id = id }
    end
  end
  return glyph(kind)
end

-- Same target as a short string, for a cache or a comparison.
function EI.Key(target)
  if target.kind == "glyph" then
    return "glyph:" .. target.glyph
  end
  return target.kind .. ":" .. tostring(target.id or target.slot)
end
