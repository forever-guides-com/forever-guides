-- Keyboard of the layer window (LayerWindow.lua): Tab and the arrow keys walk the buttons of the window (Shift is
-- never read, so Tab only goes forward and Up goes back), Enter and Space press, Esc closes through the Esc
-- stack of the addon. The order is the switches, read again, the other buttons, the rows of the list, the title
-- bar; a disabled button is skipped. At the edge of the visible rows the list scrolls under the focus.
local _, ns = ...

local K = {}
ns.LayerWindowKeys = K

-- Buttons in reading order: the switches, read again, the other buttons, the rows of the list, the title bar.
local function buttons(f, rows)
  local net = f.net
  local out = { net.share, net.host, f.refresh, net.best, net.cancel }
  for _, row in ipairs(rows) do
    out[#out + 1] = row.btn
  end
  out[#out + 1] = f.look
  out[#out + 1] = f.close
  return out
end

local function ownFocus(f, rows)
  for _, item in ipairs(buttons(f, rows)) do
    if item == ns.Focus.current then
      return true
    end
  end
  return false
end

local function focusables(f, rows)
  local out = {}
  for _, item in ipairs(buttons(f, rows)) do
    if item:IsVisible() and item:IsEnabled() then
      out[#out + 1] = item
    end
  end
  return out
end

-- True when the list has entries beyond its last (step 1) or first (step -1) visible row.
local function canScroll(rows, count, step)
  local first, last
  for _, row in ipairs(rows) do
    if row:IsShown() then
      first = math.min(first or row.index, row.index)
      last = math.max(last or row.index, row.index)
    end
  end
  if step > 0 then
    return last ~= nil and last < count
  end
  return first ~= nil and first > 1
end

local function move(f, rows, count, step)
  local items = focusables(f, rows)
  local at = 0
  for i, item in ipairs(items) do
    if item == ns.Focus.current then
      at = i
    end
  end
  local current, following = items[at], items[at + step]
  -- At the edge of the visible rows the list scrolls under the focus, so every entry is reachable. A row
  -- without a button has none to focus: the list goes on until one is under the focus again.
  if current and current.fgRow and not (following and following.fgRow) and canScroll(rows, count, step) then
    repeat
      f.list:ScrollBy(step)
    until current:IsVisible() or not canScroll(rows, count, step)
    if current:IsVisible() then
      ns.Focus.set(current)
      return true
    end
  end
  if #items == 0 then
    return false
  end
  at = at + step
  if at < 1 then
    at = #items
  elseif at > #items then
    at = 1
  end
  ns.Focus.set(items[at])
  return true
end

local function handleKey(f, rows, count, key)
  if key == "ESCAPE" then
    return ns.EscStack.Close(f)
  end
  local own = ownFocus(f, rows)
  if key == "TAB" and (own or f:IsMouseOver()) then
    return move(f, rows, count, 1)
  elseif own and (key == "DOWN" or key == "UP") then
    return move(f, rows, count, key == "DOWN" and 1 or -1)
  elseif own and (key == "ENTER" or key == "SPACE") then
    return ns.Focus.activate()
  end
  return false
end

-- True when the focus is on a button of window f. rows: the row frames of the list.
function K.OwnFocus(f, rows)
  return ownFocus(f, rows)
end

-- A key press in window f; true when it was used. count: the entries of the list.
function K.Handle(f, rows, count, key)
  return handleKey(f, rows, count, key)
end
