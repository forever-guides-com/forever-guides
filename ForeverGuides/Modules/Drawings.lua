-- Drawings storage: ForeverGuidesDB.drawings = { v, manualOrder, items = { {
-- id, name, w, h, data, created, updated } } }. `data` is the encoded string of
-- DrawingLogic.Encode, so a drawing costs at most MAX_BYTES. The order of
-- `items` is the manual order (new drawings go to the top). Opening or viewing
-- a drawing never changes order or timestamps; `updated` only moves when the
-- encoded content or the name really changes.
-- Exchange strings use the envelope of Core\Strings.lua with type "drawing"
-- (one drawing) or "drawings" (backup). Imported data is never trusted: every
-- drawing is fully decoded and re-encoded, names are sanitized, and nothing is
-- added before the caller confirms a preview.
local _, ns = ...
local U, C, D = ns.U, ns.MacroCore, ns.DrawingLogic

local DR = {
  KIND = "drawing",
  KIND_BACKUP = "drawings",
  MAX_ITEMS = 60,
  MAX_NAME = 60,
  MAX_BYTES = D.MAX_ENCODED,
  MAX_TOKENS = 8,
  MAX_PASTE = 256 * 1024,
}
ns.Drawings = DR

DR.random = math.random

local ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

local function changed(kind, id)
  if ns.Emit then
    ns.Emit("FG_DRAWINGS_CHANGED", kind, id)
  end
end

-- One line, no control characters, at most MAX_NAME characters. May be empty,
-- the UI shows its own fallback label then.
function DR.cleanName(name)
  local s = C.sanitize(tostring(name or "")):gsub("%s+", " ")
  return C.sanitize(C.truncateChars(U.trim(s), DR.MAX_NAME))
end

local function newId(used)
  for _ = 1, 100 do
    local chars = {}
    for i = 1, 8 do
      local k = DR.random(#ALPHABET)
      chars[i] = ALPHABET:sub(k, k)
    end
    local id = table.concat(chars)
    if not used[id] then
      used[id] = true
      return id
    end
  end
  error("drawings: no free id")
end

local function num(v, default)
  return type(v) == "number" and v == v and v or default
end

-- Root -------------------------------------------------------------------------------

local checked

-- Repairs the saved structure once per database table. Unreadable pictures are
-- kept (the encoded data may only be unreadable because LibDeflate is missing);
-- only entries without an id-able table or data string are unusable.
local function validate(r)
  r.v = r.v or 1
  r.manualOrder = true
  local items, used, now = {}, {}, U.now()
  for i = 1, type(r.items) == "table" and #r.items or 0 do
    local raw = r.items[i]
    if type(raw) == "table" and type(raw.data) == "string" then
      local id = type(raw.id) == "string" and raw.id:match("^%w+$") and #raw.id <= 16 and raw.id or nil
      if not id or used[id] then
        id = newId(used)
      end
      used[id] = true
      items[#items + 1] = {
        id = id,
        name = DR.cleanName(raw.name),
        w = D.validDims(raw.w, raw.h) and raw.w or 0,
        h = D.validDims(raw.w, raw.h) and raw.h or 0,
        data = raw.data,
        created = num(raw.created, now),
        updated = num(raw.updated, num(raw.created, now)),
      }
    end
  end
  r.items = items
end

function DR.root()
  local db = ns.db
  local r = type(db.drawings) == "table" and db.drawings or {}
  db.drawings = r
  if checked ~= r then
    checked = r
    validate(r)
  end
  return r
end

-- CRUD ---------------------------------------------------------------------------------

local function indexOf(id)
  for i, item in ipairs(DR.root().items) do
    if item.id == id then
      return i
    end
  end
end

function DR.get(id)
  local i = indexOf(id)
  return i and DR.root().items[i]
end

function DR.count()
  return #DR.root().items
end

-- Remembers the drawing the Drawings page shows first. No event, no timestamp, no reorder.
function DR.setLastOpened(id)
  if DR.get(id) then
    DR.root().lastOpened = id
  end
end

-- The drawing to show when the page opens: the last opened one while it exists, else the
-- first in the list, else nil (no drawings).
function DR.startItem()
  local r = DR.root()
  return DR.get(r.lastOpened) or r.items[1]
end

-- The items in manual order (a copy of the list, the item tables are live).
function DR.list()
  local out = {}
  for i, item in ipairs(DR.root().items) do
    out[i] = item
  end
  return out
end

-- Fresh, independent drawing for editing or preview, or nil, reason (the
-- decode reasons of DrawingLogic.Decode, "missing" for an unknown id).
function DR.load(id)
  local item = DR.get(id)
  if not item then
    return nil, "missing"
  end
  return D.Decode(item.data)
end

-- Inserts a new drawing at position `at` (default top) without announcing it.
local function insert(name, drawing, at)
  local r = DR.root()
  if #r.items >= DR.MAX_ITEMS then
    return nil, "limit"
  end
  local data, why, size = D.Encode(drawing)
  if not data then
    return nil, why, size
  end
  local used = {}
  for _, item in ipairs(r.items) do
    used[item.id] = true
  end
  local now = U.now()
  local item = {
    id = newId(used),
    name = DR.cleanName(name),
    w = drawing.w,
    h = drawing.h,
    data = data,
    created = now,
    updated = now,
  }
  table.insert(r.items, at or 1, item)
  return item
end

-- Stores an existing drawing as a new entry. Returns item or nil, reason
-- ("limit" | "too-large" | "dims" | "palette" | "cells" | "shape"); "too-large"
-- adds the encoded length as third result.
function DR.add(name, drawing, at)
  local item, why, size = insert(name, drawing, at)
  if item then
    DR.root().lastOpened = item.id
    changed("create", item.id)
  end
  return item, why, size
end

-- New blank drawing (white background, default palette) on top of the list.
function DR.create(name, w, h)
  local drawing, why = D.new(w, h)
  if not drawing then
    return nil, why
  end
  return DR.add(name, drawing)
end

-- Saves an edited drawing. Returns item, didChange or nil, reason. Writing the
-- same picture again keeps `updated` and emits nothing.
function DR.update(id, drawing)
  local item = DR.get(id)
  if not item then
    return nil, "missing"
  end
  local data, why, size = D.Encode(drawing)
  if not data then
    return nil, why, size
  end
  DR.root().lastOpened = id
  if data == item.data and item.w == drawing.w and item.h == drawing.h then
    return item, false
  end
  item.data, item.w, item.h = data, drawing.w, drawing.h
  item.updated = U.now()
  changed("update", id)
  return item, true
end

function DR.rename(id, name)
  local item = DR.get(id)
  if not item then
    return nil
  end
  local clean = DR.cleanName(name)
  if clean == item.name then
    return item, false
  end
  item.name = clean
  item.updated = U.now()
  changed("rename", id)
  return item, true
end

-- Copy right below the original. Returns item or nil, reason.
function DR.duplicate(id)
  local i = indexOf(id)
  if not i then
    return nil, "missing"
  end
  local item = DR.root().items[i]
  local drawing, why = DR.load(id)
  if not drawing then
    return nil, why
  end
  return DR.add(item.name .. " 2", drawing, i + 1)
end

-- Permanent, the UI asks for confirmation first.
function DR.delete(id)
  local i = indexOf(id)
  if not i then
    return false
  end
  table.remove(DR.root().items, i)
  changed("delete", id)
  return true
end

-- One step up (dir -1) or down (dir 1). False at the edges.
function DR.move(id, dir)
  local items = DR.root().items
  local i = indexOf(id)
  local j = i and i + (dir < 0 and -1 or 1)
  if not j or j < 1 or j > #items then
    return false
  end
  items[i], items[j] = items[j], items[i]
  changed("order", id)
  return true
end

-- Export ---------------------------------------------------------------------------------

local function pack(item)
  return { name = item.name, code = item.data }
end

-- Exchange string for one drawing, or nil, reason.
function DR.exportString(id)
  local item = DR.get(id)
  if not item then
    return nil, "missing"
  end
  local s, why = ns.Strings.encode(DR.KIND, pack(item))
  if s and #s > ns.Strings.MAX_INPUT then
    return nil, "too-large"
  end
  return s, why
end

-- Backup of `items` (default all) as a list of exchange strings, each within
-- the input limit, at most MAX_TOKENS of them. Returns the list or nil, reason.
function DR.exportBackup(items)
  items = items or DR.list()
  if #items == 0 then
    return nil, "empty"
  end
  local strings = {}
  local limit = ns.Strings.MAX_INPUT * 0.9
  local function emit(from, to)
    local packed = {}
    for i = from, to do
      packed[#packed + 1] = pack(items[i])
    end
    local s, why = ns.Strings.encode(DR.KIND_BACKUP, { items = packed })
    if not s then
      return false, why
    end
    if #s > limit and to > from then
      local mid = math.floor((from + to) / 2)
      local ok, err = emit(from, mid)
      if not ok then
        return false, err
      end
      return emit(mid + 1, to)
    end
    if #s > ns.Strings.MAX_INPUT then
      return false, "too-large"
    end
    strings[#strings + 1] = s
    return true
  end
  local ok, why = emit(1, #items)
  if not ok then
    return nil, why
  end
  if #strings > DR.MAX_TOKENS then
    return nil, "too-many"
  end
  return strings
end

-- Import ---------------------------------------------------------------------------------

local function fromEnvelope(env)
  local data = env.data
  local raws
  if env.type == DR.KIND then
    raws = { data }
  elseif env.type == DR.KIND_BACKUP then
    raws = data.items
  else
    return nil, "type"
  end
  if env.v > ns.Strings.VERSION then
    return nil, "version"
  end
  if type(raws) ~= "table" or #raws < 1 or #raws > DR.MAX_ITEMS then
    return nil, "items"
  end
  local out = {}
  for i, raw in ipairs(raws) do
    if type(raw) ~= "table" or type(raw.code) ~= "string" or (raw.name ~= nil and type(raw.name) ~= "string") then
      return nil, "items", i
    end
    local drawing = D.Decode(raw.code)
    if not drawing then
      return nil, "drawing", i
    end
    out[i] = { name = DR.cleanName(raw.name), drawing = drawing }
  end
  return out
end

-- Reads one or several pasted exchange strings (whitespace separated, backup
-- parts). Returns { items = { { name, drawing } } } or nil, code[, index]
-- with code "empty" | "too-large" | "too-many" | "decode" | "json" | "shape" |
-- "type" | "version" | "items" | "drawing". Never touches the database.
function DR.parseImport(text)
  text = U.trim(text or "")
  if text == "" then
    return nil, "empty"
  end
  if #text > DR.MAX_PASTE then
    return nil, "too-large"
  end
  local tokens = {}
  for token in text:gmatch("%S+") do
    tokens[#tokens + 1] = token
  end
  if #tokens > DR.MAX_TOKENS then
    return nil, "too-many"
  end
  local all = {}
  for index, token in ipairs(tokens) do
    local env, why = ns.Strings.decode(token)
    if not env then
      return nil, why, index
    end
    local items, err, at = fromEnvelope(env)
    if not items then
      return nil, err, at or index
    end
    for _, item in ipairs(items) do
      all[#all + 1] = item
    end
    if #all > DR.MAX_ITEMS then
      return nil, "items", index
    end
  end
  return { items = all }
end

-- Adds parsed items as new drawings (new IDs) as one block on top that keeps
-- the order of `items`. Returns added, skipped (skipped = over the limit).
function DR.importItems(items)
  local take = math.min(#items, math.max(0, DR.MAX_ITEMS - DR.count()))
  local added = 0
  -- New drawings go to the top, so the last one goes in first.
  for i = take, 1, -1 do
    if insert(items[i].name, items[i].drawing) then
      added = added + 1
    end
  end
  if added > 0 then
    changed("import")
  end
  return added, #items - added
end
