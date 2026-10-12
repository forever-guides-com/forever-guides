-- One event frame for the whole addon. Names starting with "FG_" are
-- internal messages and never registered with the game.
local _, ns = ...

local listeners = {}
local frame = CreateFrame("Frame")

local function dispatch(event, ...)
  local list = listeners[event]
  if not list then
    return
  end
  for i = 1, #list do
    ns.Safe(event, list[i], event, ...)
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  dispatch(event, ...)
end)

local function isInternal(event)
  return event:sub(1, 3) == "FG_"
end

function ns.On(event, fn)
  local list = listeners[event]
  if not list then
    list = {}
    listeners[event] = list
    if not isInternal(event) then
      local ok = pcall(frame.RegisterEvent, frame, event)
      if not ok then
        ns.Log.warn("event %s not available", event)
      end
    end
  end
  list[#list + 1] = fn
end

function ns.Emit(message, ...)
  dispatch(message, ...)
end

-- Throttled timers without OnUpdate: coalesces calls within `delay`.
local pending = {}
function ns.Debounce(key, delay, fn)
  if pending[key] then
    return
  end
  pending[key] = true
  local function run()
    pending[key] = nil
    ns.Safe("debounce", fn)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, run)
  else
    run()
  end
end
