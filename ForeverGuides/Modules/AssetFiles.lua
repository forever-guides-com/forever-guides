-- Which file IDs of the dungeon art (Data.DungeonAssets) this client really has, and how big they are.
-- The dungeon views crop a picture by its real size. C_Texture.GetTextureInfo is used when the client
-- has it; the game's own API documentation does not list it, so every answer can also be "unknown".
local _, ns = ...

local F = {}
ns.AssetFiles = F

-- id -> { id, found = true | false | nil, w, h, file, loaded }; nil found = no existence test.
F.cache = {}
F.last = nil

function F.HasInfo()
  return type(C_Texture) == "table" and type(C_Texture.GetTextureInfo) == "function"
end

-- GetTextureInfo answers with width and height or nil for an unknown file; a table with width
-- and height is read as well. With `tex` the file is also set on that texture and read back
-- (GetTexture, IsObjectLoaded). Nothing here may raise.
function F.Check(id, tex)
  local r = { id = id }
  if F.HasInfo() then
    local ok, a, b = pcall(C_Texture.GetTextureInfo, id)
    if ok then
      r.found = a ~= nil and a ~= false
      if type(a) == "table" then
        r.w, r.h = a.width, a.height
      elseif r.found then
        r.w, r.h = a, b
      end
    end
  end
  if tex then
    tex:SetTexture(id)
    local ok, file = pcall(tex.GetTexture, tex)
    r.file = ok and file or nil
    if type(tex.IsObjectLoaded) == "function" then
      local okLoaded, loaded = pcall(tex.IsObjectLoaded, tex)
      if okLoaded then
        r.loaded = loaded
      end
    end
    F.last = { file = r.file, loaded = r.loaded }
  end
  F.cache[id] = r
  return r
end

function F.Reset()
  F.cache, F.last = {}, nil
end
