-- Which layout a player uses, without WoW API (ns.LayoutAssign). A display with a layout library (the mouse
-- cursor ring) resolves the layout in three steps: the assignment for this character, else the assignment for
-- the class of this character, else the account default. An assignment names a layout and has one of two
-- scopes: "char" (this character only) or "class" (every character of that class on the account).
--
-- Storage (decided by the host, see LayoutSet): the character assignment is one layout id in the character
-- store, the class assignments are a map { [classToken] = layoutId } in the account settings. Every value that is
-- missing, unknown or points at a layout that is gone counts as "not assigned" and the next step answers.
-- The three steps are one ordered list in Candidates: a later "by situation" step (fishing, mounted, combat)
-- is one more entry in front of the class step, nothing else here changes.
local _, ns = ...

local LA = {
  SCOPES = { "char", "class" },
  MAX_TOKEN = 24,
}
ns.LayoutAssign = LA

local function text(v)
  return type(v) == "string" and v ~= "" and v or nil
end

-- A class token as the game spells it (MAGE, DEATHKNIGHT), nil for anything else.
function LA.CleanToken(v)
  if type(v) == "string" and #v <= LA.MAX_TOKEN and v:find("^%u[%u_]*$") then
    return v
  end
end

-- A scope as stored or picked: "char", "class" or nil.
function LA.CleanScope(v)
  if v == "char" or v == "class" then
    return v
  end
end

-- The class map with every entry valid; a copy, the input stays as it is.
function LA.CleanClasses(raw)
  local out = {}
  if type(raw) == "table" then
    for token, id in pairs(raw) do
      if LA.CleanToken(token) and text(id) then
        out[token] = id
      end
    end
  end
  return out
end

local function classId(classes, token)
  token = LA.CleanToken(token)
  if token and type(classes) == "table" then
    return text(classes[token])
  end
end

-- The steps in the order they win: { { source, id }, ... }. An entry without an id is left out.
function LA.Candidates(accountId, charId, classes, token)
  local out = {}
  if text(charId) then
    out[#out + 1] = { source = "char", id = charId }
  end
  if classId(classes, token) then
    out[#out + 1] = { source = "class", id = classId(classes, token) }
  end
  out[#out + 1] = { source = "account", id = accountId }
  return out
end

-- The layout in effect: returns its id (nil when nothing names an existing layout), where it comes from ("char",
-- "class" or "account"; nil without an id) and whether an assignment in front of the winner points at a layout
-- that is gone. `has(id)` tells whether a layout exists.
function LA.Resolve(accountId, charId, classes, token, has)
  local stale = false
  for _, step in ipairs(LA.Candidates(accountId, charId, classes, token)) do
    if type(step.id) == "string" and step.id ~= "" and has(step.id) == true then
      return step.id, step.source, stale
    end
    if step.source ~= "account" then
      stale = true
    end
  end
  return nil, nil, stale
end

-- How layout `id` is assigned for this player: "char", "class" or nil. A character assignment hides a class
-- assignment of the same layout (the layout is used either way).
function LA.ScopeOf(id, charId, classes, token)
  if text(id) == nil then
    return nil
  end
  if charId == id then
    return "char"
  end
  if classId(classes, token) == id then
    return "class"
  end
end

-- The class tokens that use layout `id`, sorted.
function LA.ClassesOf(id, classes)
  local out = {}
  if type(classes) == "table" then
    for token, value in pairs(classes) do
      if value == id and LA.CleanToken(token) then
        out[#out + 1] = token
      end
    end
  end
  table.sort(out)
  return out
end

-- The assignment after layout `id` gets `scope` for this player (nil: not assigned any more). Returns the new
-- character id (nil: none), the new class map (a copy) and a reason when nothing could change ("scope",
-- "class" for a class scope without a class token). The old assignment of this layout for the other scope goes
-- away, so a layout never sits in both places and nothing stays behind when the scope changes back.
function LA.Plan(charId, classes, token, id, scope)
  local map = LA.CleanClasses(classes)
  charId = text(charId)
  token = LA.CleanToken(token)
  if text(id) == nil then
    return charId, map, "scope"
  end
  if scope ~= nil and not LA.CleanScope(scope) then
    return charId, map, "scope"
  end
  if scope == "class" and not token then
    return charId, map, "class"
  end
  if charId == id then
    charId = nil
  end
  if token and map[token] == id then
    map[token] = nil
  end
  if scope == "char" then
    charId = id
  elseif scope == "class" then
    map[token] = id
  end
  return charId, map
end

-- Every assignment to layout `id` removed (the layout is deleted). Returns the new character id and class map.
function LA.Forget(charId, classes, id)
  local map = LA.CleanClasses(classes)
  for token, value in pairs(map) do
    if value == id then
      map[token] = nil
    end
  end
  charId = text(charId)
  return charId ~= id and charId or nil, map
end

-- Whether two class maps hold the same entries.
function LA.SameClasses(a, b)
  a, b = LA.CleanClasses(a), LA.CleanClasses(b)
  for token, id in pairs(a) do
    if b[token] ~= id then
      return false
    end
  end
  for token in pairs(b) do
    if a[token] == nil then
      return false
    end
  end
  return true
end

-- Whether a class map holds nothing (the host stores nil then).
function LA.IsEmpty(classes)
  return type(classes) ~= "table" or next(classes) == nil
end

-- The entries of `list` ({ name, ... }) whose name holds `query` (plain text, any case, surrounding space
-- ignored). An empty query keeps everything; the order stays.
function LA.Filter(list, query)
  query = type(query) == "string" and query:match("^%s*(.-)%s*$"):lower() or ""
  if query == "" then
    return list
  end
  local out = {}
  for _, entry in ipairs(list) do
    if type(entry.name) == "string" and entry.name:lower():find(query, 1, true) then
      out[#out + 1] = entry
    end
  end
  return out
end

-- The item an arrow key moves to in a list of `count` items from `index` (nil: nothing picked yet). Up and Down
-- stop at the ends, Home and End jump, a page moves by `page`. Returns nil for an empty list or another key.
function LA.Move(count, index, key, page)
  if type(count) ~= "number" or count < 1 then
    return nil
  end
  local at = type(index) == "number" and index or nil
  local target
  if key == "DOWN" then
    target = at and at + 1 or 1
  elseif key == "UP" then
    target = at and at - 1 or count
  elseif key == "HOME" then
    target = 1
  elseif key == "END" then
    target = count
  elseif key == "PAGEDOWN" then
    target = (at or 0) + (page or 5)
  elseif key == "PAGEUP" then
    target = (at or count + 1) - (page or 5)
  else
    return nil
  end
  return math.max(1, math.min(count, target))
end

-- The size of the "manage layouts" dialog for an editor window of `editorW` x `editorH` on a screen of
-- `screenW` x `screenH` (all in the units of the dialog): wide enough for the row controls, about 88 percent of
-- the editor height, never over the screen. Returns width, height.
function LA.DialogSize(editorW, editorH, screenW, screenH)
  local function num(v, default)
    return type(v) == "number" and v == v and v > 0 and v < math.huge and v or default
  end
  local w = math.max(640, math.min(980, math.floor(num(editorW, 1020) * 0.8)))
  local h = math.max(420, math.floor(num(editorH, 640) * 0.88))
  w = math.min(w, math.max(480, math.floor(num(screenW, w) - 40)))
  h = math.min(h, math.max(360, math.floor(num(screenH, h) - 40)))
  return w, h
end
