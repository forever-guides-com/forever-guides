-- Forever Chat, the rules of the symbol choice (pure, no frames, no game access): which file ids may be a symbol of
-- a team, the pages of the grid and the cursor on a page. The symbols are the macro icons of the game (the same
-- list the macro editor offers); ChatIconPicker.lua draws the grid.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local TL = chat.TeamsLogic

local IP = {}
chat.IconPickerLogic = IP

-- Most symbols on a page, and the most the picker keeps from all the lists together.
IP.PAGE_MAX = 60
IP.KEEP = 20000
-- The functions of the game that fill a table with icon file ids, in the order they are asked.
IP.SOURCES = { "GetMacroIcons", "GetLooseMacroIcons", "GetMacroItemIcons" }

-- The list of symbols: the default symbol first, then every whole number of the lists (each once, no names),
-- from `read(name)` (the function of the game or nil) and `catalog()` (file ids the add-on itself knows, used
-- when the game gives none). Every call is guarded: a failing source is skipped.
function IP.Gather(read, catalog)
  local out, seen = {}, {}
  local function add(list)
    for _, id in ipairs(type(list) == "table" and list or {}) do
      if #out >= IP.KEEP then
        return
      end
      local clean = type(id) == "number" and TL.CleanIcon(id) or nil
      if clean and not seen[clean] then
        seen[clean] = true
        out[#out + 1] = clean
      end
    end
  end
  add({ TL.LIMITS.DEFAULT_ICON })
  local found = false
  for _, name in ipairs(IP.SOURCES) do
    local fn = type(read) == "function" and read(name) or nil
    if type(fn) == "function" then
      local list = {}
      local ok = pcall(fn, list)
      if ok and #list > 0 then
        found = true
        add(list)
      end
    end
  end
  if not found and type(catalog) == "function" then
    local ok, list = pcall(catalog)
    if ok then
      add(list)
    end
  end
  return out
end

-- Columns for a width: the cell and the gap in pixels. At least 3, at most 12.
function IP.Columns(width, cell, gap)
  local cols = math.floor((width + gap) / (cell + gap))
  return math.max(3, math.min(12, cols))
end

-- Symbols on a page: whole rows, never more than PAGE_MAX.
function IP.PerPage(cols, rows)
  local per = math.max(1, math.floor(cols)) * math.max(1, math.floor(rows))
  return math.min(IP.PAGE_MAX, per)
end

function IP.Pages(count, per)
  return math.max(1, math.ceil(math.max(0, count) / math.max(1, per)))
end

-- The ids of a page (the page is held between the first and the last). Returns the ids, the page and the pages.
function IP.Page(list, page, per)
  local pages = IP.Pages(#list, per)
  page = math.max(1, math.min(pages, math.floor(tonumber(page) or 1)))
  local out = {}
  for i = (page - 1) * per + 1, math.min(#list, page * per) do
    out[#out + 1] = list[i]
  end
  return out, page, pages
end

-- The page that holds a symbol, 1 when it is not in the list.
function IP.PageOf(list, icon, per)
  for i, id in ipairs(list) do
    if id == icon then
      return math.floor((i - 1) / per) + 1
    end
  end
  return 1
end

-- The cursor (1 to n on the page) after a key: arrows move by one or a row, Home and End jump. Returns the
-- cursor, and the page step (-1 or 1) when the key leaves the page, 0 otherwise.
function IP.Move(cursor, key, cols, n)
  local target
  if key == "LEFT" then
    target = cursor - 1
  elseif key == "RIGHT" then
    target = cursor + 1
  elseif key == "UP" then
    target = cursor - cols
  elseif key == "DOWN" then
    target = cursor + cols
  elseif key == "HOME" then
    return 1, 0
  elseif key == "END" then
    return n, 0
  else
    return cursor, 0
  end
  if target < 1 then
    return cursor, -1
  elseif target > n then
    return cursor, 1
  end
  return target, 0
end
