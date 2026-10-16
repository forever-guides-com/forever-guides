-- One event frame for the whole addon. Names starting with "FG_" are
-- internal messages and never registered with the game. ADDON_LOADED and PLAYER_ENTERING_WORLD are
-- not replayed for late handlers (their arguments cannot be rebuilt); only PLAYER_LOGIN is.
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

-- True once this add-on has seen PLAYER_LOGIN itself.
local loginSeen = false

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    loginSeen = true
  end
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
  -- PLAYER_LOGIN fires once; a handler registered after it (a sub-addon loaded in a running session)
  -- would never run. The late handler gets one deferred call, with the event name only. Our own
  -- login must have passed too, so a client that answers IsLoggedIn early on a reload cannot run
  -- the handlers of the normal start twice.
  local loggedIn = rawget(_G, "IsLoggedIn")
  if event == "PLAYER_LOGIN" and loginSeen and type(loggedIn) == "function" and loggedIn() then
    local function replay()
      ns.Safe(event, fn, event)
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, replay)
    else
      replay()
    end
  end
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
