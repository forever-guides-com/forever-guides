-- Picture of an instance for the cards and the header band (Modules/InstanceArt.lua draws it): which
-- loading screen of the client belongs to an instance, how it is cut to a box (the card is 16:5), and
-- the gradient and symbol that stand in when an instance has no usable picture. Pure logic: the only game
-- lookup is the file check of Modules/AssetFiles.lua, and a test can hand in its own check.
-- Data: ns.Data.DungeonAssets (loading[name] = { fid, src }), unchanged. The pictures come from the client
-- by FileDataID, the add-on ships none.
local _, ns = ...

local A = {}
ns.InstanceArtLogic = A

-- Card ratio, width to height.
A.RATIO_W, A.RATIO_H = 16, 5

-- Instances that never show a client picture. The old Hyjal screen belongs to a different map, the
-- placeholder stands in until the client has a screen for this raid.
A.EXCLUDED = { ["Hyjal Summit"] = true }

-- Where the picture sits in its texture while the real size is not known: the old narrow screens hold
-- a 4:3 picture in the top part of a square texture, the others fill the whole texture. `aspect` is the
-- width to height ratio of the picture, `v` the share of the texture height it covers.
A.SOURCE = {
  narrow = { aspect = 4 / 3, v = 0.75 },
  wide = { aspect = 16 / 10, v = 1 },
  wide169 = { aspect = 16 / 9, v = 1 },
  main = { aspect = 16 / 9, v = 1 },
}

-- Placeholder families. Order of the list is the order of the tests and of any legend.
A.FAMILIES = { "cave", "fortress", "crypt", "jungle", "sea", "fire", "raid" }

-- Family per English instance name; a raid is "raid", anything else unlisted "fortress".
A.FAMILY = {
  ["Alcaz Prison"] = "fortress",
  ["Blackfathom Deeps"] = "sea",
  ["Blackmaw Hold"] = "fortress",
  ["Blackrock Depths"] = "fire",
  ["City of Dalaran"] = "fortress",
  ["Dire Maul - East"] = "jungle",
  ["Dire Maul - North"] = "jungle",
  ["Dire Maul - West"] = "jungle",
  ["Excavation Site: Wetlands"] = "cave",
  ["Gnomeregan"] = "cave",
  ["Hall of Thanes"] = "fortress",
  ["Krol'dok Stronghold"] = "fortress",
  ["Lower Blackrock Spire"] = "fire",
  ["Maraudon"] = "cave",
  ["Ragefire Chasm"] = "fire",
  ["Razorfen Downs"] = "crypt",
  ["Razorfen Kraul"] = "jungle",
  ["Ruins of Lordaeron"] = "crypt",
  ["Scarlet Monastery"] = "fortress",
  ["Scholomance"] = "crypt",
  ["Shadowfang Keep"] = "fortress",
  ["Shaper's Terrace"] = "jungle",
  ["Stormwind Stockade"] = "fortress",
  ["Stratholme"] = "crypt",
  ["Sunken Temple"] = "jungle",
  ["The Deadmines"] = "cave",
  ["The Drowned City"] = "sea",
  ["Uldaman"] = "cave",
  ["Upper Blackrock Spire"] = "fire",
  ["Wailing Caverns"] = "jungle",
  ["Zul'Farrak"] = "cave",
}

-- Left and right tone of the gradient per family as { r, g, b } in 0..255. All tones are dark, so the
-- symbol (token "text") keeps at least 4.5:1 against both of them (checked in tests/test_instanceart.lua).
A.TONES = {
  cave = { { 74, 58, 44 }, { 44, 34, 24 } },
  fortress = { { 85, 88, 95 }, { 43, 45, 51 } },
  crypt = { { 63, 74, 58 }, { 31, 42, 46 } },
  jungle = { { 47, 90, 58 }, { 22, 48, 31 } },
  sea = { { 31, 90, 122 }, { 15, 44, 69 } },
  fire = { { 138, 58, 28 }, { 58, 18, 8 } },
  raid = { { 90, 58, 122 }, { 36, 18, 47 } },
}

-- Glyph names of the drawn symbols (registered in Modules/InstanceArt.lua).
A.SYMBOL = { dungeon = "instance-dungeon", raid = "instance-raid" }

-- Share of the picture that stays visible in high contrast mode (the cards darken their pictures).
A.CONTRAST_DIM = 0.6

-- Vertical or horizontal position of the cut per instance, 0 (top or left) to 1 (bottom or right).
-- Empty until the measurement in the game says which pictures need a different cut.
A.FOCUS = {}

local function number(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Cut ---------------------------------------------------------------------------------------------

-- TexCoord rectangle (left, right, top, bottom) that cuts the picture to a box of w by h (default the
-- card ratio), without stretching: the full width stays and the box takes a strip of the height when it is
-- wider than the picture, the other way round when it is narrower. src is the source kind of
-- Data.DungeonAssets ("narrow", "main", ...), tw and th (optional) the real texture size: a square texture
-- holds the 4:3 picture in its top part, any other size is the picture itself. focus (0 to 1, default
-- 0.5 = centered) moves the strip inside the slack.
function A.Strip(src, tw, th, w, h, focus)
  local s = A.SOURCE[src] or A.SOURCE.main
  local aspect, v = s.aspect, s.v
  if number(tw) and number(th) and tw > 0 and th > 0 then
    if tw == th then
      aspect, v = 4 / 3, 0.75
    else
      aspect, v = tw / th, 1
    end
  end
  if not (number(w) and number(h) and w > 0 and h > 0) then
    w, h = A.RATIO_W, A.RATIO_H
  end
  focus = number(focus) and clamp(focus, 0, 1) or 0.5
  local want = w / h
  local l, r, t, b = 0, 1, 0, v
  if want > aspect then
    local strip = v * aspect / want
    t = (v - strip) * focus
    b = t + strip
  elseif want < aspect then
    local strip = want / aspect
    l = (1 - strip) * focus
    r = l + strip
  end
  return l, r, t, b
end

-- Choice ------------------------------------------------------------------------------------------

local function name(inst)
  local en = inst and inst.n and inst.n.en
  return type(en) == "string" and en ~= "" and en or nil
end

-- The pictures of an instance in the order they are tried: { { fid, src }, ... }. The loading screen of its
-- map first, then the screen of its map data, nothing for an excluded instance or one without an ID.
function A.Candidates(inst)
  local en = name(inst)
  local D = ns.Data and ns.Data.DungeonAssets
  local out = {}
  if not (en and D) or A.EXCLUDED[en] then
    return out
  end
  local own = D.loading and D.loading[en]
  if own and number(own.fid) then
    out[#out + 1] = { fid = own.fid, src = own.src }
  end
  local map = D.maps and D.maps[en]
  if map and number(map.lo) and not (own and own.fid == map.lo) then
    out[#out + 1] = { fid = map.lo, src = "main" }
  end
  return out
end

-- Result of the file check for one ID: { found = true | false | nil, w, h }. found false is the client
-- saying it does not have the file; nil is "cannot tell" and counts as usable.
local function fileCheck(fid)
  local F = ns.AssetFiles
  if not (F and F.HasInfo()) then
    return {}
  end
  return F.cache[fid] or F.Check(fid)
end

function A.Family(inst)
  local en = name(inst)
  if en and A.FAMILY[en] then
    return A.FAMILY[en]
  end
  return inst and inst.t == "raid" and "raid" or "fortress"
end

function A.Symbol(inst)
  return inst and inst.t == "raid" and A.SYMBOL.raid or A.SYMBOL.dungeon
end

function A.Focus(inst)
  local en = name(inst)
  local focus = en and A.FOCUS[en]
  return number(focus) and clamp(focus, 0, 1) or 0.5
end

-- What a card or band shows for an instance:
--   kind     "image" (a client picture) or "placeholder" (gradient and symbol)
--   fid, src, w, h  the picture and its real size when the client told it (kind "image")
--   reason   why a placeholder: "excluded", "noid" (no ID in the data) or "missing" (the client lacks the file)
--   family, symbol, focus, name  always set
-- `check(fid)` answers { found, w, h } and defaults to the file check of the client.
function A.Choose(inst, check)
  check = check or fileCheck
  local choice = { family = A.Family(inst), symbol = A.Symbol(inst), focus = A.Focus(inst), name = name(inst) }
  local en = name(inst)
  if en and A.EXCLUDED[en] then
    choice.kind, choice.reason = "placeholder", "excluded"
    return choice
  end
  local list, lacking = A.Candidates(inst), 0
  for _, candidate in ipairs(list) do
    local r = check(candidate.fid) or {}
    if r.found == false then
      lacking = lacking + 1
    else
      choice.kind, choice.fid, choice.src = "image", candidate.fid, candidate.src
      choice.w, choice.h = r.w, r.h
      return choice
    end
  end
  choice.kind = "placeholder"
  choice.reason = lacking > 0 and "missing" or "noid"
  return choice
end

-- TexCoord rectangle of a choice cut to a box of w by h (default the card ratio).
function A.Coords(choice, w, h)
  return A.Strip(choice and choice.src, choice and choice.w, choice and choice.h, w, h, choice and choice.focus)
end

-- Gradient tones of a family as two { r, g, b } triples in 0..1 (the left and the right end).
function A.Tones(family)
  local tones = A.TONES[family] or A.TONES.fortress
  local out = {}
  for i, tone in ipairs(tones) do
    out[i] = { tone[1] / 255, tone[2] / 255, tone[3] / 255 }
  end
  return out[1], out[2]
end

-- A tone as "#rrggbb" (for the contrast math of the tests).
function A.ToneHex(family, side)
  local tone = (A.TONES[family] or A.TONES.fortress)[side == "right" and 2 or 1]
  return string.format("#%02x%02x%02x", tone[1], tone[2], tone[3])
end
