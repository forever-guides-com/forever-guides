-- Level ranges of the zones for the world map (WorldMapZoneLevels.lua): the zone records of Data.Travel by map
-- id and by name, the range text, its color against the player's level and the label place of a zone.
-- Pure logic, no frames. Cities and zones without a verified range have no entry.
local _, ns = ...
local QL = ns.QuestListLogic

local ZL = {}
ns.ZoneLevelLogic = ZL

local function whole(v)
  return type(v) == "number" and v >= 1 and v == math.floor(v)
end

-- "30-40", or "5" when both ends are the same; nil without a valid range.
function ZL.Range(lmin, lmax)
  lmax = lmax or lmin
  if not (whole(lmin) and whole(lmax) and lmax >= lmin) then
    return nil
  end
  return lmin == lmax and tostring(lmin) or (lmin .. "-" .. lmax)
end

-- Difficulty bucket of QL.Difficulty for a range: the near end when the player is outside it, yellow inside.
function ZL.Bucket(lmin, lmax, player)
  if not (whole(lmin) and type(player) == "number") then
    return nil
  end
  lmax = lmax or lmin
  if player < lmin then
    return QL.Difficulty(lmin, player)
  elseif player > lmax then
    return QL.Difficulty(lmax, player)
  end
  return "yellow"
end

-- The range in the color of its bucket as a color escape string, uncolored without a player level.
function ZL.Colored(lmin, lmax, player)
  local text = ZL.Range(lmin, lmax)
  local bucket = text and ZL.Bucket(lmin, lmax, player)
  if not bucket then
    return text
  end
  return "|cff" .. QL.COLORS[bucket]:gsub("^#", "") .. text .. "|r"
end

-- Middle of a rectangle { left, right, top, bottom } in the fractions of its map, nil for a broken one.
function ZL.Center(rect)
  if type(rect) ~= "table" then
    return nil
  end
  local l, r, t, b = rect.left, rect.right, rect.top, rect.bottom
  if not (type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number") then
    return nil
  end
  return (l + r) / 2, (t + b) / 2
end

-- Entries of the zones that carry a range: { byMap = { [um] = entry }, byName = { [name] = entry }, list }.
-- entry = { slug, um, lmin, lmax }. Placeholders (zones of Forever whose range is not confirmed) stay out, unless zl = true (range confirmed by the client).
-- extraName(um) may give the name the client uses for the map.
function ZL.Index(zones, extraName)
  local index = { byMap = {}, byName = {}, list = {} }
  for _, z in ipairs(zones or {}) do
    if (z.k == "zone" or z.zl == true) and z.um and ZL.Range(z.lmin, z.lmax) then
      local entry = { slug = z.s, um = z.um, lmin = z.lmin, lmax = z.lmax or z.lmin }
      index.byMap[z.um] = entry
      index.list[#index.list + 1] = entry
      for _, name in ipairs({ z.n and z.n.en or false, z.n and z.n.de or false, extraName and extraName(z.um) or false }) do
        if name then
          index.byName[name] = entry
        end
      end
    end
  end
  return index
end
