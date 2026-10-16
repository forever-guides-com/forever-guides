-- Pure layout rules for the main window (breakpoints, size bounds).
local _, ns = ...

local Layout = {
  DEFAULT_W = 960,
  DEFAULT_H = 620,
  MIN_W = 720,
  MIN_H = 480,
  MAX_W = 1600,
  MAX_H = 1100,
  SIDEBAR_FULL = 184,
  SIDEBAR_ICONS = 44,
  COLLAPSE_BELOW = 860,
  ONE_COLUMN_BELOW = 760,
}
ns.Layout = Layout

-- contentWidth decides columns; the sidebar collapses when the user asked
-- for it or the window is narrower than the breakpoint. forceFull keeps the full sidebar (the
-- navigation edit mode needs the room for its controls).
function Layout.compute(width, userCollapsed, forceFull)
  local collapsed = not forceFull and (userCollapsed or width < Layout.COLLAPSE_BELOW)
  local sidebar = collapsed and Layout.SIDEBAR_ICONS or Layout.SIDEBAR_FULL
  local content = width - sidebar
  return {
    sidebar = collapsed and "icons" or "full",
    sidebarWidth = sidebar,
    contentWidth = content,
    columns = width < Layout.ONE_COLUMN_BELOW and 1 or 2,
  }
end

-- maxW / maxH default to the fixed caps; the main window passes Layout.maxSize instead.
function Layout.clampSize(w, h, maxW, maxH)
  local U = ns.U
  return U.clamp(w or Layout.DEFAULT_W, Layout.MIN_W, maxW or Layout.MAX_W),
    U.clamp(h or Layout.DEFAULT_H, Layout.MIN_H, maxH or Layout.MAX_H)
end

-- Largest window size (in the window's own units) that still fits the screen at this zoom: a
-- window of width w covers w * scale screen units. The minimum size wins on a tiny screen.
-- Without a usable screen size the fixed caps apply.
function Layout.maxSize(screenW, screenH, scale)
  local function limit(screen, minimum, fallback)
    if type(screen) ~= "number" or type(scale) ~= "number" or screen ~= screen or screen <= 0 or scale <= 0 then
      return fallback
    end
    return math.max(minimum, math.floor(screen / scale))
  end
  return limit(screenW, Layout.MIN_W, Layout.MAX_W), limit(screenH, Layout.MIN_H, Layout.MAX_H)
end

-- Window center after a zoom from oldScale to newScale that keeps the center of an anchor
-- (a control inside the window) at the same screen spot. All coordinates are screen units; the
-- anchor's distance to the window center scales linearly with the zoom.
function Layout.zoomCenter(centerX, centerY, anchorX, anchorY, oldScale, newScale)
  local ratio = newScale / oldScale
  return anchorX - (anchorX - centerX) * ratio, anchorY - (anchorY - centerY) * ratio
end

-- Moves a window center so that a window of this extent lies inside the screen; a window larger
-- than the screen is centered on it.
function Layout.keepOnScreen(center, extent, screen)
  if extent >= screen then
    return screen / 2
  end
  return ns.U.clamp(center, extent / 2, screen - extent / 2)
end
