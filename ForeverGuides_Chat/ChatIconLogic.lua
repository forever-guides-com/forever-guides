-- Forever Chat, the rules of the two small icons that open the window (pure, no frames, no game access): the
-- button on the screen and the icon on the minimap. Size and position limits, the angle on the minimap ring,
-- the badge text and the unread counts per kind. ChatButton.lua and ChatMinimap.lua draw them.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local IL = {}
chat.IconLogic = IL

IL.SIZE_MIN, IL.SIZE_MAX, IL.SIZE_DEFAULT = 24, 96, 40
-- Default angle (degrees, counter clockwise from the right) of the minimap icon. The icon of the main add-on
-- sits at 200, so the two never lie on each other.
IL.ANGLE_DEFAULT = 160
-- Minimap icons sit this far outside the edge of the minimap.
IL.RING_OFFSET = 8

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- A size inside the limits, whole pixels. Anything but a number gives the default.
function IL.ClampSize(size)
  if not isNumber(size) then
    return IL.SIZE_DEFAULT
  end
  return math.floor(math.max(IL.SIZE_MIN, math.min(IL.SIZE_MAX, size)) + 0.5)
end

-- The top left corner (x from the left edge, y from the bottom edge of the screen, in screen units) of a square
-- button of this size, moved inside the screen. A missing or broken place gives nil, the caller centers it.
function IL.ClampPosition(x, y, size, width, height)
  if not (isNumber(x) and isNumber(y) and isNumber(width) and isNumber(height) and width > 0 and height > 0) then
    return nil
  end
  size = IL.ClampSize(size)
  local maxX, maxY = math.max(0, width - size), math.max(size, height)
  return math.max(0, math.min(maxX, x)), math.max(size, math.min(maxY, y))
end

-- The size after pulling the corner grip by dx to the right and dy up (screen units, down is negative). Right and
-- down make it bigger, the mean of both moves counts so a diagonal pull feels even.
function IL.ResizeBy(start, dx, dy)
  if not (isNumber(dx) and isNumber(dy)) then
    return IL.ClampSize(start)
  end
  return IL.ClampSize(IL.ClampSize(start) + (dx - dy) / 2)
end

-- Degrees on the ring (0 to 360) of the cursor as seen from the center of the minimap. nil for a broken input.
function IL.AngleTo(cx, cy, mx, my)
  if not (isNumber(cx) and isNumber(cy) and isNumber(mx) and isNumber(my)) then
    return nil
  end
  return math.deg(math.atan2(cy - my, cx - mx)) % 360
end

function IL.ClampAngle(angle)
  return isNumber(angle) and angle % 360 or IL.ANGLE_DEFAULT
end

-- Offset of the icon from the center of the minimap for an angle and the width of the minimap.
function IL.RingOffset(angle, minimapWidth)
  local radius = (isNumber(minimapWidth) and minimapWidth or 140) / 2 + IL.RING_OFFSET
  local rad = math.rad(IL.ClampAngle(angle))
  return math.cos(rad) * radius, math.sin(rad) * radius
end

-- The badge text of an unread total: empty for none, the number up to 99, then "99+".
function IL.BadgeText(total)
  return chat.Unread.Label(isNumber(total) and total or 0)
end

-- Unread lines per tab of the list: { whisper, group, guild, channel } (Conversations.TAB_ORDER), and their sum.
function IL.Counts(state)
  local Conv, Unread = chat.Conversations, chat.Unread
  local counts, total = {}, 0
  for _, tab in ipairs(Conv.TAB_ORDER) do
    local sum = 0
    for _, conv in ipairs(type(state) == "table" and Conv.Sorted(state, tab) or {}) do
      sum = sum + Unread.Count(conv)
    end
    counts[tab] = sum
    total = total + sum
  end
  return counts, total
end

-- Marks every conversation as read. Returns the number of conversations that changed.
function IL.MarkAllRead(state)
  local changed = 0
  for _, conv in pairs(type(state) == "table" and state.convs or {}) do
    if chat.Unread.Count(conv) > 0 or conv.marked then
      chat.Unread.MarkRead(conv)
      changed = changed + 1
    end
  end
  return changed
end

-- Whether a switchable icon shows: its switch is on (or it is being edited) and the messenger runs.
function IL.Visible(switch, running, editing)
  return running == true and (switch == true or editing == true)
end
