-- Rare enemies, find window and sightings, pure side (no frames, no client calls): the list of found
-- rares with paging and expiry, the macro of the click-to-target button, the decision to wait for the end
-- of combat, the saved window position and the history of sightings with its dedupe, cap and export. The
-- window is Modules/RareFound.lua, the detection that feeds both is Modules/RareDetect.lua.
local _, ns = ...

local RFL = {}
ns.RareFoundLogic = RFL

-- Entries in the window (newest first) and the seconds one stays.
RFL.MAX_ENTRIES = 5
RFL.TTL = 300
-- The client cuts a macro at 255 characters.
RFL.MACRO_MAX = 255
-- Sightings kept, and when a new one counts as the same: same npc and map within this many map percent and
-- seconds.
RFL.SIGHTINGS_MAX = 500
RFL.SIGHT_DISTANCE = 2
RFL.SIGHT_WINDOW = 600

-- The list ----------------------------------------------------------------------------------------------

-- Puts the entry ({ id, unitName }) first with its time. The same rare moves up instead of doubling; the
-- oldest entry beyond MAX_ENTRIES drops.
function RFL.Add(list, entry, now)
  entry.t = now
  for i = #list, 1, -1 do
    if list[i].id == entry.id then
      table.remove(list, i)
    end
  end
  table.insert(list, 1, entry)
  while #list > RFL.MAX_ENTRIES do
    table.remove(list)
  end
  return list
end

-- Drops what is older than the ttl. A clock that went back keeps the entry. Returns how many were dropped.
function RFL.Prune(list, now, ttl)
  ttl = ttl or RFL.TTL
  local dropped = 0
  for i = #list, 1, -1 do
    local t = list[i].t
    if now >= t and now - t >= ttl then
      table.remove(list, i)
      dropped = dropped + 1
    end
  end
  return dropped
end

-- The index after one step (dir -1 or 1) over count entries, wrapping around; 1 for an empty or single list.
function RFL.Step(index, count, dir)
  if count <= 1 then
    return 1
  end
  return (index - 1 + dir) % count + 1
end

function RFL.Clamp(index, count)
  return math.max(1, math.min(index, math.max(count, 1)))
end

-- Click to target -------------------------------------------------------------------------------------------

-- The name the client shows: the unit's own name when the detection had a unit, else the data name.
function RFL.TargetName(unitName, name)
  if type(unitName) == "string" and unitName ~= "" then
    return unitName
  end
  return name
end

-- Macro of the button, nil for a name the macro parser would cut or misread (control characters, escape
-- sequences, option brackets and the clause separator) or that does not fit. Quotes and apostrophes are
-- plain text there.
function RFL.Macro(name)
  if type(name) ~= "string" then
    return nil
  end
  name = name:match("^%s*(.-)%s*$")
  if name == "" or name:find("[%c|%[%];]") then
    return nil
  end
  local text = "/cleartarget\n/targetexact " .. name
  return #text <= RFL.MACRO_MAX and text or nil
end

-- Secure attributes and the layout of a protected button change only outside of combat: "queue" waits for
-- PLAYER_REGEN_ENABLED, "show" works at once.
function RFL.Route(inCombat)
  return inCombat and "queue" or "show"
end

-- A model counts as shown once the client reports a file for it.
function RFL.HasModel(fileId)
  return type(fileId) == "number" and fileId > 0
end

-- Saved position ------------------------------------------------------------------------------------------

local ANCHORS = {
  TOPLEFT = true,
  TOP = true,
  TOPRIGHT = true,
  LEFT = true,
  CENTER = true,
  RIGHT = true,
  BOTTOMLEFT = true,
  BOTTOM = true,
  BOTTOMRIGHT = true,
}

-- Default of the window: bottom center above the action bars.
RFL.DEFAULT_POSITION = { point = "BOTTOM", rel = "BOTTOM", x = 0, y = 230 }

local function number(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- A coordinate or offset: a sane number.
local function finite(v)
  return number(v) and v > -1e6 and v < 1e6
end

-- The saved { point, rel, x, y } when it is usable, else the default; damaged files cannot place the window
-- off screen.
function RFL.Position(saved, default)
  if type(saved) ~= "table" or not (ANCHORS[saved.point] and ANCHORS[saved.rel]) then
    return default.point, default.rel, default.x, default.y
  end
  return saved.point, saved.rel, finite(saved.x) and saved.x or default.x, finite(saved.y) and saved.y or default.y
end

-- Sightings ---------------------------------------------------------------------------------------------

-- Percent of the map (0..1 from the client) rounded to 0.1.
function RFL.Percent(fraction)
  if not finite(fraction) then
    return nil
  end
  return math.floor(fraction * 1000 + 0.5) / 10
end

local function sameSpot(a, b)
  if a.x == nil or b.x == nil or a.y == nil or b.y == nil then
    return a.x == nil and b.x == nil
  end
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy <= RFL.SIGHT_DISTANCE * RFL.SIGHT_DISTANCE
end

-- Appends { npc, map, x, y, t } (x and y optional) unless the same npc was seen on the same map nearby and
-- recently. The oldest entry drops beyond SIGHTINGS_MAX. Returns true when it was added.
function RFL.AddSighting(items, s)
  for i = #items, 1, -1 do
    local o = items[i]
    if o.npc == s.npc and o.map == s.map and s.t >= o.t and s.t - o.t < RFL.SIGHT_WINDOW and sameSpot(o, s) then
      return false
    end
  end
  items[#items + 1] = { npc = s.npc, map = s.map, x = s.x, y = s.y, t = s.t }
  while #items > RFL.SIGHTINGS_MAX do
    table.remove(items, 1)
  end
  return true
end

-- The saved section of the account, created or repaired: wrong entries drop, the cap holds.
function RFL.Section(db)
  local s = db.rareSightings
  if type(s) ~= "table" then
    s = {}
    db.rareSightings = s
  end
  s.v = 1
  local clean = {}
  for _, o in ipairs(type(s.items) == "table" and s.items or {}) do
    if type(o) == "table" and number(o.npc) and number(o.map) and number(o.t) then
      clean[#clean + 1] =
        { npc = o.npc, map = o.map, x = finite(o.x) and o.x or nil, y = finite(o.y) and o.y or nil, t = o.t }
    end
  end
  while #clean > RFL.SIGHTINGS_MAX do
    table.remove(clean, 1)
  end
  s.items = clean
  return s
end

-- One line per sighting, "npc,map,x,y,time" (time as seconds since 1970, empty x and y without a position),
-- after a header line.
function RFL.Export(items)
  local out = { "npc,map,x,y,time" }
  for _, o in ipairs(items) do
    out[#out + 1] = string.format(
      "%d,%d,%s,%s,%d",
      o.npc,
      o.map,
      o.x and string.format("%.1f", o.x) or "",
      o.y and string.format("%.1f", o.y) or "",
      o.t
    )
  end
  return table.concat(out, "\n")
end
