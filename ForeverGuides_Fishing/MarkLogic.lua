-- The own icon at the bobber: when it is wanted, when it may be shown and where it sits. Pure: the game
-- is read by Game.lua and handed in as plain facts, the frame work is done by Mark.lua.
--
-- The game draws its interaction icon at the height of the name plate of the soft target, and for the
-- bobber that is far above the float. The own icon hangs on the same plate as a child, so it takes the
-- scale of the plate and a fixed gap holds at every camera distance. The gap is set by the player.
local _, fish = ...
if not fish.FG then
  return
end

local M = {}
fish.MarkLogic = M

-- Size of the icon in pixels, its frame strata and the texture used when the game icon cannot be copied
-- (a dot of the add-on, no client file is needed).
M.SIZE = 32
M.STRATA = "HIGH"
M.FALLBACK = "Interface\\AddOns\\ForeverGuides\\Media\\Cursor\\fill-circle.png"

-- The icon is wanted while the option is on, the line is out and the helper is not switched off.
function M.Wanted(options, channeling, blocked)
  return channeling == true and blocked ~= true and fish.Options.MarkOn(options)
end

-- The gap below the plate center in pixels, inside the slider limits (the default for anything else).
function M.Offset(value)
  local clean = fish.Options.CleanValue("markOffset", value)
  if clean == nil then
    return fish.Options.SLIDERS.markOffset.default
  end
  return clean
end

-- True when the icon may be shown for the soft target. facts: exists and object (true or false, nil when
-- the client hides them), plate (the plate frame or nil) and secret (false only when the plate says its
-- anchoring may be read). A plate the client hides, no plate and a creature all mean no icon.
function M.Show(facts)
  if type(facts) ~= "table" or facts.plate == nil then
    return false
  end
  if facts.object == false then
    return false
  end
  if facts.exists ~= true and facts.object ~= true then
    return false
  end
  return facts.secret == false
end
