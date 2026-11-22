-- Tooltips for our spot symbols on the farm HUD. The HUD is click-through by design (no mouse on the HUD, on
-- the minimap in it or on our pins), so the symbols cannot take OnEnter. Instead a throttled cursor poll finds
-- the pin under the cursor (MinimapLayer.HitAt, the grid of GatheringMapLogic.Index / Hit) and shows the same
-- tooltip as the minimap pins (MinimapLayer.TipText) with the distance in yards.
--
-- Two steps keep it free while the mouse is elsewhere: Tick (called from the HUD's own update, a bounds check
-- every WATCH seconds) starts the poll frame only when the cursor is over the HUD; the poll frame looks every
-- POLL seconds and hides itself, with the tooltip, when the cursor leaves, the HUD hides, a fight starts or the
-- client's own blip tooltips take the mouse. Nothing here enables the mouse of any frame.
local _, ns = ...
local Layer, ML = ns.MinimapLayer, ns.MinimapPinLogic

local T = {}
ns.FarmHudTip = T

-- Seconds between two bounds checks while the poll is off, and between two looks of the poll.
T.WATCH, T.POLL = 0.1, 0.05

local frame, allowed, poll
local acc, pollAcc = 0, 0
-- The pin the tooltip shows now, and the whole yards in it.
local shown, shownDist

-- Offset of the cursor from the center of a frame in the units of that frame. cursorX/Y are the raw
-- GetCursorPosition values, scale the effective scale of the frame, (centerX, centerY) its GetCenter. nil
-- when a number is unusable.
function T.Offset(cursorX, cursorY, scale, centerX, centerY)
  if not (ML.finite(cursorX) and ML.finite(cursorY) and ML.finite(scale) and scale > 0) then
    return nil
  end
  if not (ML.finite(centerX) and ML.finite(centerY)) then
    return nil
  end
  return cursorX / scale - centerX, cursorY / scale - centerY
end

-- Is the offset within the square of the given half width?
function T.Inside(dx, dy, half)
  return ML.finite(dx) and ML.finite(dy) and ML.finite(half) and math.abs(dx) <= half and math.abs(dy) <= half
end

-- The cursor as an offset from the center of the minimap and the half width of the minimap, or nil.
local function cursor()
  local mm = rawget(_G, "Minimap")
  local get = rawget(_G, "GetCursorPosition")
  if not (mm and type(get) == "function") then
    return nil
  end
  local ok, cx, cy = pcall(get)
  if not ok then
    return nil
  end
  local ok2, mx, my = pcall(mm.GetCenter, mm)
  if not ok2 then
    return nil
  end
  local half = Layer.Readable(Layer.Call(mm.GetWidth, mm))
  local dx, dy = T.Offset(
    Layer.Readable(cx),
    Layer.Readable(cy),
    Layer.Readable(Layer.Call(mm.GetEffectiveScale, mm)),
    Layer.Readable(mx),
    Layer.Readable(my)
  )
  if dx and half then
    return dx, dy, half / 2
  end
end

local function clear()
  if shown then
    shown, shownDist = nil, nil
    local tip = rawget(_G, "GameTooltip")
    if tip and frame and tip:GetOwner() == frame then
      tip:Hide()
    end
  end
end

-- Cursor over the HUD, HUD shown, no fight, nothing else holding the mouse: the offset, else nil.
local function over()
  if not (frame and frame:IsShown() and allowed and allowed() and not Layer.Flag("InCombatLockdown")) then
    return nil
  end
  local dx, dy, half = cursor()
  if dx and T.Inside(dx, dy, half) then
    return dx, dy
  end
end

-- Stops the poll and removes our tooltip. Returns "stop".
function T.Stop()
  clear()
  if poll then
    poll:Hide()
  end
  return "stop"
end

-- One look of the poll: shows, keeps or removes the tooltip of the pin under the cursor. Returns "tip", "none"
-- (the cursor is on the HUD, on no symbol) or "stop" (the poll has ended).
function T.Step()
  local dx, dy = over()
  if not dx then
    return T.Stop()
  end
  local hit = Layer.HitAt(dx, dy)
  if not hit then
    clear()
    return "none"
  end
  local dist = ML.finite(hit.dist) and math.floor(hit.dist + 0.5) or nil
  if hit ~= shown or dist ~= shownDist then
    local title, text = Layer.TipText(hit.itemId, hit.spot, hit.dist)
    if not title then
      clear()
      return "none"
    end
    ns.ShowTooltip(frame, title, text, { anchor = "ANCHOR_CURSOR" })
    shown, shownDist = hit, dist
  end
  return "tip"
end

local function onPoll(_, dt)
  pollAcc = pollAcc + (tonumber(dt) or 0)
  if pollAcc < T.POLL then
    return
  end
  pollAcc = 0
  ns.Safe("farmhud-tip", T.Step)
end

-- Ties the poll to the HUD frame. allow() says whether the poll may run (false while the client's blip tooltips
-- have the mouse of the minimap).
function T.Bind(hud, allow)
  frame, allowed = hud, allow
  if not poll then
    poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", onPoll)
    poll:Hide()
  end
end

-- Called with the elapsed time from the HUD's own update. Starts the poll when the cursor is over the HUD.
function T.Tick(dt)
  acc = acc + (tonumber(dt) or 0)
  if acc < T.WATCH then
    return
  end
  acc = 0
  if poll and not poll:IsShown() and over() then
    pollAcc = T.POLL
    poll:Show()
  end
end

-- Is the poll running?
function T.Active()
  return poll ~= nil and poll:IsShown()
end

-- The frame of the poll (tests), nil before Bind.
function T.PollFrame()
  return poll
end
