-- Forever Chat, the class of a writer (pure, no game access): which class token counts as known and the cache of the
-- classes seen in this session, keyed by the name key of the player. ChatClass.lua asks the game, ChatThread.lua
-- colors the name.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local CL = {}
chat.ClassLogic = CL

-- The cache drops everything when it is full: names seen again are read from the game once more.
CL.MAX = 600

-- The class token (upper case) when it is one of the known classes (a table token = true), else nil.
function CL.Token(value, known)
  if type(value) ~= "string" or type(known) ~= "table" then
    return nil
  end
  local token = value:upper()
  return known[token] and token or nil
end

function CL.NewCache(max)
  return { max = max or CL.MAX, count = 0, items = {} }
end

-- Keeps the class of a name key. Returns whether it was kept.
function CL.Remember(cache, key, class)
  if type(key) ~= "string" or key == "" or type(class) ~= "string" then
    return false
  end
  if cache.items[key] == nil then
    if cache.count >= cache.max then
      cache.items, cache.count = {}, 0
    end
    cache.count = cache.count + 1
  end
  cache.items[key] = class
  return true
end

function CL.Lookup(cache, key)
  return type(key) == "string" and cache.items[key] or nil
end
