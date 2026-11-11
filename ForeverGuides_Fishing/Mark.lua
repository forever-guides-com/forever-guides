-- The own icon at the bobber (option "Own icon at the bobber"): a small frame as a child of the name plate
-- of the soft target, shown only while the line is out and the plate can be read. It holds one frame for
-- the whole session and hangs it on the plate anew whenever the plate, the target or the gap changes.
-- Every game call goes through Game.lua, no frame of the game is moved or changed.
local _, fish = ...
if not fish.FG then
  return
end

local Logic = fish.MarkLogic

local M = {}
fish.Mark = M

local mark, placedOn, placedGap

-- Lets go of the plate: hidden, no anchor, no parent. Safe to call at any time.
function M.Hide()
  if mark and placedOn ~= nil then
    fish.Game.HideMark(mark)
  end
  placedOn, placedGap = nil, nil
end

-- Brings the icon in line: shown on the plate of the soft target when `on` and the facts allow it, else
-- hidden. `force` hangs it on the plate anew (a new soft target on the same plate). Returns true while
-- the icon is shown.
function M.Update(on, gap, force)
  if not on then
    M.Hide()
    return false
  end
  local g = fish.Game
  local facts = g.SoftTarget()
  if not Logic.Show(facts) then
    M.Hide()
    return false
  end
  local offset = Logic.Offset(gap)
  if not force and placedOn == facts.plate and placedGap == offset then
    return true
  end
  mark = mark or g.NewMark(Logic.SIZE, Logic.STRATA)
  if not mark then
    return false
  end
  if not g.PlaceMark(mark, facts.plate, offset, Logic.FALLBACK) then
    -- Half hung on the plate: let go of it whatever was placed before.
    g.HideMark(mark)
    placedOn, placedGap = nil, nil
    return false
  end
  placedOn, placedGap = facts.plate, offset
  return true
end

function M.Shown()
  return placedOn ~= nil
end
