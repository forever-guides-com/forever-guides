-- The game's own macros: reading, creating, replacing. Nothing here runs without a click
-- (Modules/Macros*.lua), never in combat: a request made in combat waits in a queue and runs at
-- PLAYER_REGEN_ENABLED. Every write reads the game's macro list fresh first (other macro addons
-- change it too), checks the limits again and keeps the overwritten version in the backups.
local _, ns = ...
local C, Lib = ns.MacroCore, ns.MacroLibrary

local G = { pending = {}, order = {} }
ns.MacroGame = G

local function try(fn, ...)
  return pcall(fn, ...)
end

function G.inCombat()
  local ok, locked = try(InCombatLockdown)
  return not ok or locked == true
end

-- Places the client reports (120 account, 30 character), else the constants of MacroCore.
function G.limits()
  local account = tonumber(rawget(_G, "MAX_ACCOUNT_MACROS")) or C.MAX_ACCOUNT
  local character = tonumber(rawget(_G, "MAX_CHARACTER_MACROS")) or C.MAX_CHARACTER
  return { account = account, character = character }
end

-- Fresh read of the game's macros: list of { index, name, icon, body, perChar } and the used
-- counts { account, character }.
function G.list()
  local list = {}
  local ok, account, character = try(GetNumMacros)
  account, character = ok and account or 0, ok and character or 0
  local first = G.limits().account
  local function scan(from, n, perChar)
    for i = 1, n do
      local index = from + i
      local iOk, name, icon, body = try(GetMacroInfo, index)
      if iOk and name and name ~= "" then
        list[#list + 1] = { index = index, name = name, icon = icon, body = body or "", perChar = perChar }
      end
    end
  end
  scan(0, account, false)
  scan(first, character, true)
  return list, { account = account, character = character }
end

function G.find(list, name, perChar)
  for _, g in ipairs(list) do
    if g.name == name and g.perChar == perChar then
      return g
    end
  end
end

-- Result -> locale key, args and level for a message line.
function G.describe(result, request)
  local scope = request and request.perChar and "macros.status.scope.character" or "macros.status.scope.account"
  local status = result.status
  if status == "created" then
    return "macros.status.applied", { scope, result.used, result.max }, "success"
  elseif status == "edited" then
    return result.verified == false and "macros.status.replacedCut" or "macros.status.replaced", {}, "success"
  elseif status == "queued" then
    return "macros.status.queued", {}, "info"
  elseif status == "failed" then
    return "macros.status.applyFailed", {}, "error"
  elseif status == "error" then
    local e = result.error
    if e == "full" then
      return "macros.status.full", { result.used, result.max, scope }, "error"
    elseif e == "length" then
      return "macros.status.length", { result.chars }, "error"
    end
    return "macros.status." .. e, {}, "warning"
  end
  return "macros.status.applyFailed", {}, "error"
end

-- Writes now (call only outside combat). request: { name, icon, body (text for the game), perChar,
-- entryId (library entry), linked (the entry was put into the game under this name before),
-- confirmed (the replacement was confirmed) }. Returns { status = "created" | "edited" | "confirm"
-- | "error" | "failed", ... }; "confirm" means a different game macro has this name, nothing was written.
function G.write(request)
  local list, counts = G.list()
  local limits = G.limits()
  local linked
  if request.linked then
    local g = G.find(list, request.name, request.perChar)
    linked = g and g.index
  end
  local plan = C.planApply({
    name = request.name,
    rendered = request.body,
    perChar = request.perChar,
    combat = G.inCombat(),
    game = list,
    counts = counts,
    linked = linked,
    maxAccount = limits.account,
    maxCharacter = limits.character,
  })
  if plan.error then
    plan.status = "error"
    return plan
  end
  if plan.action == "confirm" and not request.confirmed then
    return { status = "confirm", index = plan.index }
  end
  if plan.action == "create" then
    local ok, index = try(CreateMacro, request.name, request.icon, request.body, request.perChar or nil)
    if not (ok and index) then
      return { status = "failed" }
    end
    local used = (request.perChar and counts.character or counts.account) + 1
    return {
      status = "created",
      index = index,
      used = used,
      max = request.perChar and limits.character or limits.account,
    }
  end
  local old
  for _, g in ipairs(list) do
    if g.index == plan.index then
      old = g
    end
  end
  if old and old.body ~= request.body then
    Lib.saveBackup(Lib.backupKey(request.entryId, old.name, old.perChar), {
      kind = "game",
      name = old.name,
      icon = old.icon,
      body = old.body,
      perChar = old.perChar,
    })
  end
  local ok = try(EditMacro, plan.index, request.name, request.icon, request.body)
  if not ok then
    return { status = "failed" }
  end
  local rOk, _, _, body = try(GetMacroInfo, plan.index)
  return { status = "edited", index = plan.index, verified = not rOk or body == nil or body == request.body }
end

-- Writes now or, in combat, waits for the end of the fight. onDone(result) runs when it was written
-- (or failed); a second request for the same macro replaces the waiting one.
-- Returns the result of the write, or { status = "queued" }.
function G.apply(request)
  if G.inCombat() then
    local key = (request.perChar and "c:" or "a:") .. request.name
    if not G.pending[key] then
      G.order[#G.order + 1] = key
    end
    G.pending[key] = request
    return { status = "queued" }
  end
  local result = G.write(request)
  if request.onDone then
    request.onDone(result, request)
  end
  return result
end

function G.pendingCount()
  return #G.order
end

function G.cancelPending()
  G.pending, G.order = {}, {}
end

-- End of combat: runs the waiting requests in the order they were made.
function G.flush()
  if G.inCombat() or #G.order == 0 then
    return
  end
  local order, pending = G.order, G.pending
  G.pending, G.order = {}, {}
  for _, key in ipairs(order) do
    local request = pending[key]
    local result = G.write(request)
    if result.status == "confirm" and request.confirm then
      request.confirm(function()
        request.confirmed = true
        local again = G.write(request)
        if request.onDone then
          request.onDone(again, request)
        end
      end)
    elseif request.onDone then
      request.onDone(result, request)
    end
  end
end

ns.On("PLAYER_REGEN_ENABLED", G.flush)
