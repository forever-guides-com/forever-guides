-- Pure side of the list "Guild members on the map" and of the member markers on the add-on map: the
-- rows (store entries joined with the guild list, filtered like the world map pins), search, sort,
-- the cells, the column layout for a window width, the keyboard cursor and the empty state. No frames,
-- no game calls: the windows are Modules/GuildMapList.lua and Modules/MapGuildMarkers.lua.
local _, ns = ...
local GLG, PN, U = ns.WorldMapGuildLogic, ns.PlayerName, ns.U

local GML = {}
ns.GuildMapListLogic = GML

GML.COLUMNS = { "name", "class", "rank", "level", "zone", "age" }
GML.ACTIONS = { "waypoint", "whisper", "invite" }

-- Least width of a column in px at the normal font size, and how the rest of the width is shared.
GML.MIN = { name = 110, class = 84, rank = 84, level = 44, zone = 130, age = 64 }
GML.WEIGHT = { name = 3, class = 2, rank = 2, level = 0, zone = 4, age = 0 }
-- Columns that give way first when the window is narrow (their text is in the row tooltip).
GML.DROP = { "rank", "class" }
GML.PAGE = 8 -- rows a page key moves

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Rows ---------------------------------------------------------------------------------------------

-- The members that have a position, with what the guild list tells about them. `entries`: the views of
-- ns.GuildMapStore.All(), `roster`: the members of ns.GuildData.Get() (nil when the list is empty), `opts`:
-- the clamped options of WorldMapGuildLogic.Current(), `env`: me (own name), className(class, fallback),
-- mapName(id). The own character and the members the filter hides are left out; a member the guild list
-- does not know passes (see WorldMapGuildLogic.Passes). Sorted by key.
function GML.Rows(entries, roster, opts, env)
  local byKey = {}
  for _, m in ipairs(roster or {}) do
    byKey[m.key] = m
  end
  local out = {}
  for _, e in ipairs(entries or {}) do
    local m = byKey[e.key]
    local known = m ~= nil
    local member = { known = known, level = m and m.level, rank = m and m.rank, online = m and m.online }
    if not PN.Equal(e.name, env.me) and GLG.Passes(opts, member) then
      local map = env.mapName and env.mapName(e.map) or nil
      out[#out + 1] = {
        key = e.key,
        name = e.name,
        short = (GLG.ShortName(e.name):gsub("|", "")),
        known = known,
        class = m and m.class or "",
        className = m and env.className(m.class, m.className) or "",
        rank = m and finite(m.rank) and m.rank >= 0 and m.rank or nil,
        rankName = m and m.rankName or "",
        level = m and finite(m.level) and m.level or 0,
        rosterZone = m and m.zone or "",
        zone = (type(map) == "string" and map ~= "" and map) or (m and m.zone) or "",
        online = m and m.online or nil,
        guid = m and m.guid or nil,
        map = e.map,
        x = e.x,
        y = e.y,
        mode = e.mode,
        approx = e.mode == "zone",
        check = e.check,
        state = e.state,
        age = e.age,
      }
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

-- Rows that contain the words of `text` (case-insensitive, all of them) in name, class, rank or zone.
-- An empty text keeps every row.
function GML.Search(rows, text)
  local words = {}
  for word in PN.Lower(U.trim(text or "")):gmatch("%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then
    return rows
  end
  local out = {}
  for _, row in ipairs(rows) do
    local hay = PN.Lower(table.concat({ row.short, row.className, row.rankName, row.zone, row.rosterZone }, "\n"))
    local all = true
    for _, word in ipairs(words) do
      if not hay:find(word, 1, true) then
        all = false
        break
      end
    end
    if all then
      out[#out + 1] = row
    end
  end
  return out
end

-- The value a column sorts by; nil for "not known" (such a row goes last in both directions).
local SORT = {
  name = function(r)
    return PN.Lower(r.short)
  end,
  class = function(r)
    return r.className ~= "" and PN.Lower(r.className) or nil
  end,
  rank = function(r)
    return r.rank
  end,
  level = function(r)
    return r.level > 0 and r.level or nil
  end,
  zone = function(r)
    return r.zone ~= "" and PN.Lower(r.zone) or nil
  end,
  age = function(r)
    return finite(r.age) and r.age or nil
  end,
}

-- Sorts the rows in place by a column, ties by name and key. `descending` flips the order of known values.
function GML.Sort(rows, column, descending)
  local value = SORT[column] or SORT.name
  table.sort(rows, function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then
      if va == nil then
        return false
      elseif vb == nil then
        return true
      elseif descending then
        return va > vb
      end
      return va < vb
    end
    local na, nb = PN.Lower(a.short), PN.Lower(b.short)
    if na ~= nb then
      return na < nb
    end
    return a.key < b.key
  end)
  return rows
end

-- The column a click on a header makes the sort: a new column starts ascending (the age too, the
-- newest report first), the same column turns around.
function GML.NextSort(column, descending, clicked)
  if clicked == column then
    return column, not descending
  end
  return clicked, false
end

-- Cells ---------------------------------------------------------------------------------------------

-- "12 s" or "3 min" from the locale keys gml.age.s and gml.age.min.
function GML.AgeText(age, L)
  local n, unit = GLG.AgeParts(age)
  return string.format(L[unit == "s" and "gml.age.s" or "gml.age.min"], n)
end

-- The text of one cell; "-" where the guild list does not tell.
function GML.Cell(row, column, L)
  if column == "name" then
    return row.short
  elseif column == "class" then
    return row.className ~= "" and row.className or "-"
  elseif column == "rank" then
    return row.rankName ~= "" and row.rankName or "-"
  elseif column == "level" then
    return row.level > 0 and tostring(row.level) or "-"
  elseif column == "zone" then
    return row.zone ~= "" and row.zone or "-"
  end
  return GML.AgeText(row.age, L)
end

-- Lines of a tooltip for a row (level and class, rank, zone of the guild list, age, the state of the
-- report). `paint(kind, text)` colours a line ("muted" or "warning"), default: no colour.
function GML.TipLines(row, L, paint)
  paint = paint or function(_, text)
    return text
  end
  local lines = {}
  if row.level > 0 then
    lines[#lines + 1] = string.format(L["wm.guild.tip.level"], row.level, row.className)
  end
  if row.rankName ~= "" then
    lines[#lines + 1] = string.format(L["wm.guild.tip.rank"], row.rankName)
  end
  if row.rosterZone ~= "" then
    lines[#lines + 1] = string.format(L["wm.guild.tip.zone"], row.rosterZone)
  end
  local n, unit = GLG.AgeParts(row.age)
  lines[#lines + 1] = string.format(L[unit == "s" and "wm.guild.tip.age" or "wm.guild.tip.ageMin"], n)
  if row.approx then
    lines[#lines + 1] = paint("muted", L["wm.guild.tip.approx"])
  end
  if row.state ~= "current" then
    lines[#lines + 1] = paint("warning", L["wm.guild.tip.old"])
  elseif row.check == "jump" then
    lines[#lines + 1] = paint("warning", L["wm.guild.tip.jump"])
  end
  return lines
end

-- Layout ----------------------------------------------------------------------------------------------

-- The columns of a row for a window: { id, x, w } left to right inside `width` px, with `reserve` px at the
-- right for the action buttons. `scale` widens the least widths with the font size. A narrow window drops
-- columns (GML.DROP, rank first) until the rest fits; the extra width goes to the columns that have a weight.
function GML.Layout(width, reserve, scale, gap)
  scale, gap = finite(scale) and scale > 0 and scale or 1, gap or 6
  local avail = math.max(0, (finite(width) and width or 0) - (reserve or 0))
  local shown = {}
  for _, id in ipairs(GML.COLUMNS) do
    shown[#shown + 1] = id
  end
  local function need()
    local sum = gap * (#shown - 1)
    for _, id in ipairs(shown) do
      sum = sum + math.floor(GML.MIN[id] * scale + 0.5)
    end
    return sum
  end
  for _, drop in ipairs(GML.DROP) do
    if need() > avail then
      for i, id in ipairs(shown) do
        if id == drop then
          table.remove(shown, i)
          break
        end
      end
    end
  end
  local extra, weights = math.max(0, avail - need()), 0
  for _, id in ipairs(shown) do
    weights = weights + GML.WEIGHT[id]
  end
  local out, x = {}, 0
  for _, id in ipairs(shown) do
    local w = math.floor(GML.MIN[id] * scale + 0.5)
    if weights > 0 then
      w = w + math.floor(extra * GML.WEIGHT[id] / weights)
    end
    out[#out + 1] = { id = id, x = x, w = w }
    x = x + w + gap
  end
  return out
end

-- Keyboard cursor --------------------------------------------------------------------------------------

-- Moves the cursor { row, col } for a key. Row 0 is the header (col 1 to #COLUMNS: the sort buttons), row 1
-- and up are the list rows (col 0 the row, col 1 to #ACTIONS its buttons). Returns the new row and col, nil
-- for a key the list does not use. `rows`: number of list rows.
function GML.Navigate(row, col, key, rows)
  local last = #GML.ACTIONS
  local function limit(r)
    return r == 0 and #GML.COLUMNS or last
  end
  if key == "DOWN" or key == "UP" then
    local to = math.max(0, math.min(rows, row + (key == "DOWN" and 1 or -1)))
    if to == row then
      return row, col
    end
    if row == 0 then
      return to, 0
    end
    return to, to == 0 and 1 or col
  elseif key == "HOME" then
    return rows > 0 and 1 or 0, 0
  elseif key == "END" then
    return rows, rows > 0 and 0 or 1
  elseif key == "PAGEDOWN" or key == "PAGEUP" then
    if rows == 0 then
      return 0, col
    end
    local step = key == "PAGEDOWN" and GML.PAGE or -GML.PAGE
    return math.max(1, math.min(rows, row + step)), 0
  elseif key == "LEFT" then
    return row, math.max(row == 0 and 1 or 0, col - 1)
  elseif key == "RIGHT" then
    return row, math.min(limit(row), col + 1)
  end
  return nil
end

-- What Enter does at a cursor: "sort" with the column, "action" with its id, or nil.
function GML.Activate(row, col)
  if row == 0 then
    return "sort", GML.COLUMNS[col]
  end
  return "action", GML.ACTIONS[col == 0 and 1 or col]
end

-- Actions and state ------------------------------------------------------------------------------------

-- Where the waypoint goes: the map, the point (the middle for a zone-only report) and the title.
function GML.Target(row)
  return row.map, row.x or 0.5, row.y or 0.5, row.short
end

-- The three row actions with their state. `block`: why an invite is not possible now (key suffix of
-- "invite.why.*") or nil.
function GML.ActionState(row, block)
  return {
    { id = "waypoint", enabled = finite(row.map) },
    { id = "whisper", enabled = true },
    { id = "invite", enabled = block == nil, reason = block },
  }
end

-- Why the list shows no row: "off" (receiving is off), "noGuild", "none" (nothing received yet),
-- "filtered" (search or filter hides all), nil when there are rows.
function GML.EmptyReason(receiving, inGuild, total, shown)
  if not receiving then
    return "off"
  elseif not inGuild then
    return "noGuild"
  elseif shown > 0 then
    return nil
  elseif total > 0 then
    return "filtered"
  end
  return "none"
end
