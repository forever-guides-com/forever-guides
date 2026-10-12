-- Internal log (ring buffer) and the error list. ns.Safe / ns.Wrap record errors raised
-- inside our own entry points here; the catcher (Modules/ErrorCatcher.lua) adds the
-- rest through a chained error handler and never replaces or locks it.
local _, ns = ...
local U = ns.U

local Ring = {}
Ring.__index = Ring
ns.Ring = Ring

function Ring.new(capacity, store)
  return setmetatable({ cap = capacity, items = store or {} }, Ring)
end

function Ring:push(item)
  local items = self.items
  items[#items + 1] = item
  while #items > self.cap do
    table.remove(items, 1)
  end
end

function Ring:list()
  return self.items
end

function Ring:clear()
  for i = #self.items, 1, -1 do
    self.items[i] = nil
  end
end

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local log = Ring.new(200)
local Log = { ring = log }
ns.Log = Log

local function write(level, fmt, ...)
  local ok, msg = pcall(string.format, tostring(fmt), ...)
  if not ok then
    msg = tostring(fmt)
  end
  log:push({ t = U.now(), l = level, m = msg })
  -- Optional sink that prints the log to chat; without it the ring buffer is all there is.
  if Log.sink then
    pcall(Log.sink, level, msg)
  end
end

for level in pairs(LEVELS) do
  Log[level] = function(fmt, ...)
    write(level, fmt, ...)
  end
end

-- Errors -----------------------------------------------------------------

-- One list for our own ns.Safe errors and for what the catcher records. Entry: msg, ctx,
-- kind ("error", "blocked", "forbidden", "warning"), addon, stack, count, first, last
-- (server time), session (of the last occurrence). Old entries lack kind, addon, session.
local MAX_STORED = 100
local MAX_MSG = 500
local MAX_STACK = 1500
local SESSION_CAP = 100
local Errors = { list = {}, sessionCount = 0, dropped = 0, MAX_STORED = MAX_STORED }
ns.Errors = Errors

-- Cuts to `max` bytes with an ellipsis, never inside a UTF-8 sequence.
function Errors.clip(text, max)
  text = tostring(text or "")
  if #text <= max then
    return text
  end
  text = text:sub(1, max - 3)
  local i = #text
  while i > 0 and text:byte(i) >= 128 and text:byte(i) < 192 do
    i = i - 1
  end
  local lead = i > 0 and text:byte(i) or 0
  if lead >= 192 then
    local need = lead >= 240 and 4 or (lead >= 224 and 3 or 2)
    if #text - i + 1 < need then
      text = text:sub(1, i - 1)
    end
  end
  return text .. "..."
end

local function sessionId()
  local meta = ns.db and ns.db.meta
  return meta and meta.sessions or 0
end

-- The entry seen longest ago goes first; equal times drop the earlier one.
local function evict()
  while #Errors.list > MAX_STORED do
    local oldest = 1
    for i = 2, #Errors.list do
      if (Errors.list[i].last or 0) < (Errors.list[oldest].last or 0) then
        oldest = i
      end
    end
    table.remove(Errors.list, oldest)
  end
end

-- Persisted list survives /reload; attached once SavedVariables are ready.
function Errors.attach(storeList)
  for _, e in ipairs(Errors.list) do
    e.session = e.session or sessionId()
    storeList[#storeList + 1] = e
  end
  Errors.list = storeList
  evict()
end

local function shortStack(stack)
  local lines = {}
  for line in tostring(stack or ""):gmatch("[^\n]+") do
    if line:find("ForeverGuides", 1, true) then
      lines[#lines + 1] = (line:gsub("^.-AddOns[/\\]", ""))
      if #lines >= 6 then
        break
      end
    end
  end
  return table.concat(lines, "\n")
end

-- spec: msg, kind, addon, ctx, stack (already shortened). Returns entry, isNew; nil when a
-- repeat is dropped because the session already counted SESSION_CAP occurrences.
function Errors.add(spec)
  local msg = Errors.clip(spec.msg, MAX_MSG)
  local kind = spec.kind or "error"
  local addon = spec.addon or "ForeverGuides"
  local now = U.now()
  for _, e in ipairs(Errors.list) do
    if e.msg == msg and (e.kind or "error") == kind and (e.addon or "ForeverGuides") == addon then
      if Errors.sessionCount >= SESSION_CAP then
        Errors.dropped = Errors.dropped + 1
        return nil
      end
      Errors.sessionCount = Errors.sessionCount + 1
      e.count = e.count + 1
      e.last = now
      e.session = sessionId()
      if (e.stack or "") == "" and spec.stack and spec.stack ~= "" then
        e.stack = Errors.clip(spec.stack, MAX_STACK)
      end
      if ns.Emit then
        ns.Emit("FG_ERRORS_CHANGED")
      end
      return e, false
    end
  end
  Errors.sessionCount = Errors.sessionCount + 1
  local entry = {
    msg = msg,
    ctx = spec.ctx or addon,
    kind = kind,
    addon = addon,
    stack = Errors.clip(spec.stack or "", MAX_STACK),
    count = 1,
    first = now,
    last = now,
    session = sessionId(),
  }
  Errors.list[#Errors.list + 1] = entry
  evict()
  write("error", "%s: %s", tostring(entry.ctx), msg)
  if ns.Emit then
    ns.Emit("FG_ERRORS_CHANGED")
    ns.Emit("FG_ERROR_NEW", entry)
  end
  return entry, true
end

function Errors.record(context, message, stack)
  return (Errors.add({ msg = tostring(message), ctx = context, stack = shortStack(stack) }))
end

function Errors.count()
  local n = 0
  for _, e in ipairs(Errors.list) do
    n = n + e.count
  end
  return n
end

function Errors.clear()
  for i = #Errors.list, 1, -1 do
    Errors.list[i] = nil
  end
  Errors.sessionCount = 0
  if ns.Emit then
    ns.Emit("FG_ERRORS_CHANGED")
  end
end

local traceback = (type(debugstack) == "function" and function()
  return debugstack(3)
end) or (debug and debug.traceback) or function()
  return ""
end

-- Runs fn protected; returns ok plus up to five results.
function ns.Safe(context, fn, ...)
  local stack
  local ok, a, b, c, d, e = xpcall(fn, function(err)
    stack = traceback()
    return err
  end, ...)
  if not ok then
    Errors.record(context, a, stack)
    return false
  end
  return true, a, b, c, d, e
end

function ns.Wrap(context, fn)
  return function(...)
    return select(2, ns.Safe(context, fn, ...))
  end
end
