-- Badge textures (Media/Badge*.png): hexagon mark without lettering for chat lines (|T...|t) and nameplates.
--
-- A release only ships a Media file when a Lua file names its stem, so SIZES spells every stem out as a
-- literal; tests/test_badgeassets.py checks the files and keeps this list in step.
local _, ns = ...

local B = {}
ns.BadgeAssets = B

local DIR = "Interface\\AddOns\\ForeverGuides\\Media\\"

-- Pixel size to file stem, produced by tools/make_badge.py.
B.SIZES = {
  [16] = "Badge16",
  [32] = "Badge32",
  [64] = "Badge64",
}

-- Texture path of the smallest badge that is at least `height` pixels tall (the largest one beyond 64).
function B.Path(height)
  local pick = 64
  for _, size in ipairs({ 16, 32, 64 }) do
    if size >= (height or 0) then
      pick = size
      break
    end
  end
  return DIR .. B.SIZES[pick] .. ".png"
end
