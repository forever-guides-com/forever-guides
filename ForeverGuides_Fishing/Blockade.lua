-- Detects that the game blocked a protected call of this add-on (ADDON_ACTION_BLOCKED). One blocked
-- call is enough: the helper switches itself off and tells the player, it never fails silently.
-- Pure: the controller feeds it the event and acts on the answer.
local _, fish = ...
if not fish.FG then
  return
end

local B = {}
fish.Blockade = B

local Watch = {}
Watch.__index = Watch

-- addons: the add-on names whose blocked calls count (a list of names).
function B.New(addons)
  local own = {}
  for _, name in ipairs(addons) do
    own[name] = true
  end
  return setmetatable({ own = own, count = 0, func = nil }, Watch)
end

-- Feeds the event. Returns true when the call belongs to this add-on.
function Watch:Note(addon, func)
  if type(addon) ~= "string" or not self.own[addon] then
    return false
  end
  self.count = self.count + 1
  self.func = type(func) == "string" and func ~= "" and func or "?"
  return true
end

-- { func, count } of what was blocked, nil when nothing was.
function Watch:Info()
  if self.count == 0 then
    return nil
  end
  return { func = self.func, count = self.count }
end

function Watch:Reset()
  self.count, self.func = 0, nil
end
