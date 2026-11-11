-- The trustee of borrowed game settings (sound, soft interaction target, name plates). The helper borrows
-- a setting for the length of a cast and gives it back afterwards. The rules:
--   * a setting that already has the wanted value is not touched and never restored,
--   * what we write is read back, the value the client really holds is what counts (the range is capped),
--   * at the end only a setting that still holds the value we wrote is restored: if the player or
--     another add-on changed it meanwhile, their value stays,
--   * the ledger is saved after every change, so a reload or a restart in the middle of a cast
--     restores the original values at the next start. A ledger older than the expiry is dropped
--     without a write: the player may have changed the setting on purpose since then.
-- Pure: the game is reached through the env table (get, set, now, save).
local _, fish = ...
if not fish.FG then
  return
end

local T = {}
fish.Trustee = T

-- Twelve hours: a fishing session, not a day.
T.EXPIRY = 12 * 60 * 60

-- Values of console variables are strings, 1 and "1.000000" are the same value.
function T.Same(a, b)
  if a == b then
    return true
  end
  local x, y = tonumber(a), tonumber(b)
  return x ~= nil and y ~= nil and x == y
end

local Trustee = {}
Trustee.__index = Trustee

local function copy(list)
  local out = {}
  for i, value in ipairs(list) do
    out[i] = value
  end
  return out
end

-- env.get(name) -> string or nil (nil: the client has no such setting)
-- env.set(name, value) -> true when the write went through
-- env.now() -> seconds, comparable across sessions (server time)
-- env.save(snapshot or nil) -> keeps the ledger in the SavedVariables
-- env.expiry (optional) -> seconds, default T.EXPIRY
function T.New(env)
  assert(type(env) == "table", "trustee needs an env")
  return setmetatable({ env = env, held = {}, order = {} }, Trustee)
end

function Trustee:_save()
  self.env.save(self:Snapshot())
end

function Trustee:_forget(name)
  self.held[name] = nil
  for i, held in ipairs(self.order) do
    if held == name then
      table.remove(self.order, i)
      break
    end
  end
end

-- Gives one setting back if it still holds our value. Returns "restored", "foreign" (someone else
-- changed it, left alone) or "failed" (the write did not go through, the entry stays for the next try).
function Trustee:_giveBack(name)
  local entry = self.held[name]
  local now = self.env.get(name)
  if now == nil or not T.Same(now, entry.set) then
    self:_forget(name)
    return "foreign"
  end
  if not self.env.set(name, entry.original) then
    return "failed"
  end
  self:_forget(name)
  return "restored"
end

-- wanted: { [name] = value } for the whole time of the loan. Settings borrowed earlier that are not
-- wanted any more go back at once. Returns { set = { names }, capped = { [name] = value the client holds },
-- failed = { names }, kept = { names that need no write } }.
function Trustee:Borrow(wanted)
  local result = { set = {}, capped = {}, failed = {}, kept = {} }
  for _, name in ipairs(copy(self.order)) do
    if wanted[name] == nil then
      self:_giveBack(name)
    end
  end
  local names = {}
  for name in pairs(wanted) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local value = wanted[name]
    local now = self.env.get(name)
    local entry = self.held[name]
    -- Changed by someone else while we held it: their value is the new original.
    if entry and now ~= nil and not T.Same(now, entry.set) then
      self:_forget(name)
      entry = nil
    end
    if now ~= nil and not entry then
      if T.Same(now, value) then
        result.kept[#result.kept + 1] = name
      elseif self.env.set(name, value) then
        local after = self.env.get(name)
        self.held[name] = { original = now, set = after ~= nil and after or value }
        self.order[#self.order + 1] = name
        result.set[#result.set + 1] = name
        if after ~= nil and not T.Same(after, value) then
          result.capped[name] = after
        end
      else
        result.failed[#result.failed + 1] = name
      end
    elseif entry and not T.Same(entry.set, value) and not T.Same(now, value) then
      -- Still ours, the wanted value moved (a slider): write the new value, keep the original.
      if self.env.set(name, value) then
        local after = self.env.get(name)
        entry.set = after ~= nil and after or value
        result.set[#result.set + 1] = name
      else
        result.failed[#result.failed + 1] = name
      end
    end
  end
  self:_save()
  return result
end

-- Gives everything back. Returns { restored = n, foreign = n, failed = n }.
function Trustee:Release()
  local out = { restored = 0, foreign = 0, failed = 0 }
  for _, name in ipairs(copy(self.order)) do
    local state = self:_giveBack(name)
    out[state] = out[state] + 1
  end
  self:_save()
  return out
end

-- True while at least one setting is on loan.
function Trustee:Active()
  return #self.order > 0
end

function Trustee:Names()
  return copy(self.order)
end

-- The ledger as plain data for the SavedVariables, nil when nothing is on loan.
function Trustee:Snapshot()
  if #self.order == 0 then
    return nil
  end
  local entries = {}
  for _, name in ipairs(self.order) do
    local entry = self.held[name]
    entries[name] = { original = entry.original, set = entry.set }
  end
  return { time = self.env.now(), entries = entries }
end

local function valid(snapshot)
  if type(snapshot) ~= "table" or type(snapshot.time) ~= "number" or type(snapshot.entries) ~= "table" then
    return false
  end
  for name, entry in pairs(snapshot.entries) do
    if
      type(name) ~= "string"
      or type(entry) ~= "table"
      or type(entry.original) ~= "string"
      or type(entry.set) ~= "string"
    then
      return false
    end
  end
  return true
end

-- At the start of a session: puts back what a session that ended in the middle of a cast left behind.
-- Returns "none" (nothing saved), "invalid" (damaged, dropped), "expired" (too old, dropped) or
-- "recovered", and the counts { restored, foreign, failed }. A setting that failed stays in the ledger.
function Trustee:Recover(snapshot)
  if snapshot == nil then
    return "none"
  end
  local age = valid(snapshot) and self.env.now() - snapshot.time
  if not age then
    self.env.save(nil)
    return "invalid"
  end
  if age < 0 or age > (self.env.expiry or T.EXPIRY) then
    self.env.save(nil)
    return "expired"
  end
  local names = {}
  for name in pairs(snapshot.entries) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local entry = snapshot.entries[name]
    self.held[name] = { original = entry.original, set = entry.set }
    self.order[#self.order + 1] = name
  end
  local counts = self:Release()
  return "recovered", counts
end
