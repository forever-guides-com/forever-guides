-- Decisions of the property panels of the canvas editor without WoW API (ns.PanelLogic): the folded sections
-- (state kept for the session, which rows take room), which options matter for the chosen mode, and the combat
-- verdict of a cooldown element. The frames are built in CanvasEditorControls.lua, the aura verdict comes from
-- AuraNativeLogic. Every rule treats a missing value as "shown", so a prop it does not know never hides a row.
local _, ns = ...

local P = {}
ns.PanelLogic = P

-- Folds ---------------------------------------------------------------------------------------------------------

-- The open or closed state of named sections. `default` of a call is the state of a section that was never
-- touched (open when omitted).
function P.NewFolds()
  local state = {}
  local folds = {}
  function folds.isOpen(key, default)
    local v = state[key]
    if v == nil then
      return default ~= false
    end
    return v
  end
  function folds.set(key, open)
    state[key] = open == true
  end
  function folds.toggle(key, default)
    local open = not folds.isOpen(key, default)
    state[key] = open
    return open
  end
  return folds
end

-- Which rows of a panel take room. rows = list of { header = id } (the heading of a section) or { section = id|nil,
-- shown = boolean } (a row, `shown` its own condition). A row in a closed section is hidden, a heading is shown
-- while at least one row of its section passes its own condition (an empty section has no heading).
-- `isOpen(id)` is the state of a section. Returns a list of booleans in row order.
function P.Visible(rows, isOpen)
  local live = {}
  for _, row in ipairs(rows) do
    if row.section ~= nil and row.shown then
      live[row.section] = true
    end
  end
  local out = {}
  for i, row in ipairs(rows) do
    if row.header ~= nil then
      out[i] = live[row.header] == true
    elseif row.section ~= nil then
      out[i] = row.shown == true and isOpen(row.section) == true
    else
      out[i] = row.shown == true
    end
  end
  return out
end

-- Relevance ------------------------------------------------------------------------------------------------------

-- Whether the colour of the state without a count matters. A cooldown draws it only while ready is visible
-- (the rules "always" and "ready") or when the end pulses in it; an aura or a weapon enchantment while its missing
-- state can show (any condition but "while active") or when its end pulses.
function P.ReadyColorShown(kind, p)
  if kind == "aura" or kind == "weapon" then
    return p.when ~= "active" or p.pulseOnEnd ~= false
  end
  return p.showWhen == "always" or p.showWhen == "ready" or p.warn ~= "off"
end

-- Whether the place of the time text matters: the game number inside the ring sits in the ring, the other
-- looks (and every look on a bar) are placed by the setting.
function P.TimerPositionShown(p)
  return not (p.timerMode == "engine" and p.style ~= "bar")
end

-- Whether each property row of a group panel matters for its arrangement `mode` (and for the sorting `sort`).
-- Returns { gap, gapY, cols, grow, lineGrow, align, cell, justify, collapse, sort, sortDir, radius, start, dir,
-- arc } as booleans. An unknown mode shows every row, like every rule here.
local ARRANGED = { row = true, column = true, grid = true, circle = true }
function P.GroupRowsShown(mode, sort)
  local known = ARRANGED[mode] == true or mode == "free"
  local function on(...)
    if not known then
      return true
    end
    for _, m in ipairs({ ... }) do
      if m == mode then
        return true
      end
    end
    return false
  end
  local arranged = not known or mode ~= "free"
  return {
    gap = on("row", "column", "grid"),
    gapY = on("grid"),
    cols = on("grid"),
    grow = on("row", "column", "grid"),
    lineGrow = on("grid"),
    align = on("row", "column"),
    cell = arranged,
    justify = on("row", "column", "grid"),
    collapse = arranged,
    sort = arranged,
    sortDir = arranged and sort ~= "manual",
    radius = on("circle"),
    start = on("circle"),
    dir = on("circle"),
    arc = on("circle"),
  }
end

-- Combat verdict -------------------------------------------------------------------------------------------------

-- The verdict word of a status key, for the headline "Works in combat: <verdict>".
P.VERDICTS = {
  native = "yes",
  calc = "calc",
  partial = "partial",
  live = "no",
  none = "no",
  fixed = "fixed",
  readable = "readable",
}

function P.Verdict(key)
  return P.VERDICTS[key] or "no"
end

-- Nothing chosen to show yet: a spell or pet spell of id 0, an item by id of 0.
local function nothingChosen(p)
  if p.source == "item" then
    return p.itemMode == "id" and (p.itemId or 0) <= 0
  end
  return p.spellBase ~= nil and p.spellBase <= 0
end

-- What a cooldown element does in combat. p = the props (source, spellBase, itemMode, itemId, showWhen,
-- colorCurve, style), caps = what the client offers { itemObject, curve, bar } (false = missing, anything else
-- is taken as there). Returns { key, color, notes }: key "native" (the engine draws ring, bar and time from the
-- duration object), "partial" (the same with a limit named in notes) or "none" (nothing to show in combat),
-- color a theme colour name, notes the reasons to say in addition.
function P.CooldownStatus(p, caps)
  caps = caps or {}
  if nothingChosen(p) then
    return { key = "none", color = "danger", notes = { "nothing" } }
  end
  if p.source == "item" and caps.itemObject == false then
    return { key = "none", color = "danger", notes = { "item" } }
  end
  local notes = {}
  if p.showWhen == "below" and caps.curve == false then
    notes[#notes + 1] = "below"
  end
  if p.colorCurve == true and caps.curve == false then
    notes[#notes + 1] = "curve"
  end
  if p.style == "bar" and caps.bar == false then
    notes[#notes + 1] = "bar"
  end
  if #notes > 0 then
    return { key = "partial", color = "warning", notes = notes }
  end
  return { key = "native", color = "success", notes = notes }
end
