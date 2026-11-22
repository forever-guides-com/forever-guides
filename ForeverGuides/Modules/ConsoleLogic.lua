-- Console variables (CVars), logic side without frames: reading, writing with a check of what the client
-- kept, profiles with a snapshot per character, the way back and the matching console text. The client is
-- reached through one small api table (get, default, set, combat), so the tests swap it for a fake.
local _, ns = ...

local C = {}
ns.ConsoleLogic = C

local D = ns.ConsoleVars

C.SAME_TOLERANCE = 0.0005

-- Client api -----------------------------------------------------------------------------------------

local function pick(table_, name, global)
  local fn = type(table_) == "table" and table_[name] or nil
  if type(fn) == "function" then
    return fn
  end
  fn = rawget(_G, global)
  return type(fn) == "function" and fn or nil
end

-- Every call is guarded: a build without one of the functions answers nil instead of raising.
function C.RealApi()
  local api = {}
  function api.get(name)
    local fn = pick(rawget(_G, "C_CVar"), "GetCVar", "GetCVar")
    if not fn then
      return nil
    end
    local ok, value = pcall(fn, name)
    if ok and value ~= nil then
      return tostring(value)
    end
    return nil
  end
  function api.default(name)
    local fn = pick(rawget(_G, "C_CVar"), "GetCVarDefault", "GetCVarDefault")
    if not fn then
      return nil
    end
    local ok, value = pcall(fn, name)
    if ok and value ~= nil then
      return tostring(value)
    end
    return nil
  end
  -- true, or false plus "error" (the call raised) or "rejected" (the client refused the name or value).
  function api.set(name, value)
    local fn = pick(rawget(_G, "C_CVar"), "SetCVar", "SetCVar")
    if not fn then
      return false, "error"
    end
    local ok, result = pcall(fn, name, value)
    if not ok then
      return false, "error"
    end
    if result == false then
      return false, "rejected"
    end
    return true
  end
  -- True when the client reports the variable as secure (addon code cannot write it); nil without the call.
  function api.secure(name)
    local fn = pick(rawget(_G, "C_CVar"), "GetCVarInfo", "GetCVarInfo")
    if not fn then
      return nil
    end
    local out = { pcall(fn, name) }
    if not out[1] then
      return nil
    end
    local info = out[2]
    if type(info) == "table" then
      return info.secure == true
    end
    -- Positional answer: value, default, accountWide, characterWide, locked, secure, readOnly.
    return out[7] == true
  end
  -- Restarts the graphics engine (gxRestart). Answers false when this build has neither way to do it.
  function api.restart()
    local fn = rawget(_G, "RestartGx")
    local how = "RestartGx"
    if type(fn) ~= "function" then
      fn, how = rawget(_G, "ConsoleExec"), "ConsoleExec"
    end
    if type(fn) ~= "function" then
      return false
    end
    local ok = pcall(fn, how == "ConsoleExec" and "gxRestart" or nil)
    return ok
  end
  function api.combat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then
      return false
    end
    local ok, value = pcall(fn)
    return ok and value == true
  end
  return api
end

-- Values ---------------------------------------------------------------------------------------------

-- A number without trailing zeros: 0.85, 4, -1.
function C.Fmt(n)
  local s = string.format("%.4f", n)
  s = s:gsub("0+$", "")
  s = s:gsub("%.$", "")
  return s
end

-- The text the client takes: toggles as 1 or 0, numbers trimmed, anything else as it is.
function C.Normalize(value)
  if value == true then
    return "1"
  elseif value == false then
    return "0"
  end
  local n = tonumber(value)
  if n then
    return C.Fmt(n)
  end
  return tostring(value)
end

-- Two client values are the same when their numbers agree within a tolerance or their texts agree.
function C.Same(a, b)
  if a == nil or b == nil then
    return a == b
  end
  local x, y = tonumber(a), tonumber(b)
  if x and y then
    return math.abs(x - y) < C.SAME_TOLERANCE
  end
  return tostring(a):lower() == tostring(b):lower()
end

-- A variable the client keeps addon code from writing: our data flag or what the client reports.
function C.IsSecure(api, name)
  local var = D.byName[name]
  if var and var.secure then
    return true
  end
  return api.secure ~= nil and api.secure(name) == true
end

function C.Command(name, value)
  return "/console " .. name .. " " .. C.Normalize(value)
end

-- Writing --------------------------------------------------------------------------------------------

-- Sets one variable and reads it back. Result: { name, want, before, got, ok, reason, clamped, ignored }.
-- reason: "combat" (nothing written), "secure" (the client allows no write from addons), "missing" (the client does not know the name), "rejected", "error".
function C.Apply(api, name, value)
  local want = C.Normalize(value)
  local r = { name = name, want = want }
  if api.combat() then
    r.reason = "combat"
    return r
  end
  r.before = api.get(name)
  if r.before == nil then
    r.reason = "missing"
    return r
  end
  if C.IsSecure(api, name) then
    r.reason = "secure"
    return r
  end
  local ok, why = api.set(name, want)
  if not ok then
    r.reason = why or "rejected"
    return r
  end
  r.ok = true
  r.got = api.get(name)
  r.clamped = r.got ~= nil and not C.Same(r.got, want)
  -- The client took the call and kept the old value: nothing was changed, not even to a nearer value.
  r.ignored = r.clamped and C.Same(r.got, r.before) or false
  return r
end

-- Names, current value and default of one variable (nil values stay nil).
function C.Info(api, name)
  local current = api.get(name)
  return {
    name = name,
    exists = current ~= nil,
    current = current,
    default = current ~= nil and api.default(name) or nil,
  }
end

-- Snapshot, profiles, way back -----------------------------------------------------------------------

-- The raid twin of a variable when the client knows it.
function C.RaidTwin(api, name)
  local var = D.byName[name]
  if var and var.raid and api.get(var.raid) ~= nil then
    return var.raid
  end
  return nil
end

-- Steps of a profile in its order, with the raid twins right behind their variable when raid is on.
function C.ProfileSteps(api, id, raid)
  local out = {}
  for _, step in ipairs(D.profiles[id] or {}) do
    out[#out + 1] = { name = step[1], value = step[2] }
    local twin = raid and C.RaidTwin(api, step[1])
    if twin then
      out[#out + 1] = { name = twin, value = step[2] }
    end
  end
  return out
end

-- Everything a graphics preset can reset: all graphics variables and their raid twins, preset first.
function C.GraphicsNames(api)
  local gfx = {}
  for _, g in ipairs(D.groups) do
    gfx[g.id] = g.gfx == true
  end
  local out = {}
  for _, var in ipairs(D.vars) do
    if gfx[var.group] then
      out[#out + 1] = var.name
      local twin = C.RaidTwin(api, var.name)
      if twin then
        out[#out + 1] = twin
      end
    end
  end
  return out
end

-- Steps that set every given variable to the client default (variables without a default are left out).
function C.DefaultSteps(api, names)
  local out = {}
  for _, name in ipairs(names) do
    local info = C.Info(api, name)
    if info.default ~= nil then
      out[#out + 1] = { name = name, value = info.default }
    end
  end
  return out
end

-- Counts of one run: applied (written), clamped (list of results the client changed), missing, failed, skipped
-- (secure variables, not written),
-- restart (a value that needs gxRestart changed), results (all of them).
local function newSummary()
  return { applied = 0, clamped = {}, missing = 0, failed = 0, skipped = 0, restart = false, results = {} }
end

local function runSteps(api, steps)
  local sum = newSummary()
  for _, step in ipairs(steps) do
    local r = C.Apply(api, step.name, step.value)
    sum.results[#sum.results + 1] = r
    if r.reason == "combat" then
      sum.blocked = "combat"
      return sum
    elseif r.reason == "missing" then
      sum.missing = sum.missing + 1
    elseif r.reason == "secure" then
      sum.skipped = sum.skipped + 1
    elseif not r.ok then
      sum.failed = sum.failed + 1
    else
      sum.applied = sum.applied + 1
      if r.clamped then
        sum.clamped[#sum.clamped + 1] = r
      end
      local var = D.byName[step.name]
      if var and var.restart and not C.Same(r.before, r.got) then
        sum.restart = true
      end
    end
  end
  return sum
end

-- Saves the current values of `names` into the store, then writes the steps. Nothing happens in combat.
-- store: { save(snapshot), load(), clear() }. label names the run in the snapshot.
function C.Run(api, store, label, steps, names)
  if api.combat() then
    return { blocked = "combat", applied = 0, clamped = {}, missing = 0, failed = 0, skipped = 0, restart = false, results = {} }
  end
  local snap = { label = label, at = ns.U.now(), names = {}, values = {} }
  for _, name in ipairs(names) do
    local value = api.get(name)
    -- Secure variables are never written, so there is nothing to bring back.
    if value ~= nil and not C.IsSecure(api, name) then
      snap.names[#snap.names + 1] = name
      snap.values[name] = value
    end
  end
  store.save(snap)
  return runSteps(api, steps)
end

function C.ApplyProfile(api, store, id, raid)
  return C.Run(api, store, id, C.ProfileSteps(api, id, raid), C.GraphicsNames(api))
end

-- Sets everything this page knows to the client default, with the raid twins when raid is on. The values
-- before go into the snapshot.
function C.ResetAll(api, store, raid)
  local names = {}
  for _, var in ipairs(D.vars) do
    names[#names + 1] = var.name
    local twin = raid and C.RaidTwin(api, var.name)
    if twin then
      names[#names + 1] = twin
    end
  end
  return C.Run(api, store, "defaults", C.DefaultSteps(api, names), names)
end

-- Writes the saved values back (the preset first, it is the first name of the snapshot) and drops the snapshot.
function C.Restore(api, store)
  local snap = store.load()
  if type(snap) ~= "table" or type(snap.names) ~= "table" or #snap.names == 0 then
    return { empty = true, applied = 0, clamped = {}, missing = 0, failed = 0, skipped = 0, restart = false, results = {} }
  end
  if api.combat() then
    return { blocked = "combat", applied = 0, clamped = {}, missing = 0, failed = 0, skipped = 0, restart = false, results = {} }
  end
  local steps = {}
  for _, name in ipairs(snap.names) do
    if snap.values[name] ~= nil then
      steps[#steps + 1] = { name = name, value = snap.values[name] }
    end
  end
  local sum = runSteps(api, steps)
  store.clear()
  return sum
end

-- Console lines of the current values of the given names, one per line.
function C.CommandText(api, names)
  local lines = {}
  for _, name in ipairs(names) do
    local value = api.get(name)
    if value ~= nil then
      lines[#lines + 1] = C.Command(name, value)
    end
  end
  return table.concat(lines, "\n")
end

-- Per character store: the snapshot and the raid option live in ForeverGuidesCharDB.console.
function C.CharStore()
  local function node()
    local c = ns.charDB and ns.charDB.console
    return type(c) == "table" and c or nil
  end
  return {
    load = function()
      local c = node()
      return c and c.snapshot or nil
    end,
    save = function(snap)
      ns.Store.setChar("console.snapshot", snap)
    end,
    clear = function()
      ns.Store.setChar("console.snapshot", nil)
    end,
  }
end

function C.RaidOn()
  local c = ns.charDB and ns.charDB.console
  return type(c) == "table" and c.raid == true
end

function C.SetRaid(on)
  ns.Store.setChar("console.raid", on == true or nil)
end
