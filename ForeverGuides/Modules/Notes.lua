-- Notes model: ForeverGuidesDB.notes = { v, items = { note }, trash = { { note, deleted } }, ui }.
-- The order of `items` is the manual order chosen by the user (new notes go to
-- the top), `manualOrder` marks that the one-time migration from the old
-- "last changed" order ran. Editing or opening a note never reorders.
-- Create/update/delete with limits, trash, tags, search, and export/import in the
-- exchange string format (type "notes"). Pure logic, no UI. Imported data is
-- never trusted: whitelisted fields, clamped numbers, sanitized text, and it
-- is only added after the user confirms a preview.
local _, ns = ...
local U, C, M, S = ns.U, ns.MacroCore, ns.Markup, ns.SearchLogic

local N = {
  MAX_TITLE = 60,
  MAX_TEXT = M.MAX_TEXT,
  MAX_TAGS = 8,
  MAX_TAG = 24,
  MAX_NOTES = 200,
  WARN_NOTES = 150,
  MAX_TRASH = 50,
  TRASH_DAYS = 30,
  MAX_ITEMS = 50,
  MAX_TOKENS = 8,
  MAX_PASTE = 256 * 1024,
}
ns.Notes = N

-- The client only loads fonts from its own "Fonts\" folder, never from an addon folder.
N.FONT_KEYS = { "frizqt", "arialn", "morpheus", "skurri" }
N.FONT_FILES = {
  frizqt = "Fonts\\FRIZQT__.TTF",
  arialn = "Fonts\\ARIALN.TTF",
  morpheus = "Fonts\\MORPHEUS.TTF",
  skurri = "Fonts\\SKURRI.TTF",
}
-- Font key of the removed bundled Open Sans, migrated to the default font on load.
N.LEGACY_FONT_KEY = "opensans"
N.SIZE_MIN, N.SIZE_MAX = 9, 24
N.ALPHA_MIN = 0.3
N.SCALE_MIN, N.SCALE_MAX = 0.5, 2

-- Text/background pairs, each with a contrast of at least 4.5:1.
N.THEMES = {
  { id = "dark", fg = "f3eee2", bg = "1a1a1a" },
  { id = "parchment", fg = "2b1d0e", bg = "e8d9b5" },
  { id = "night", fg = "e6eefc", bg = "14213d" },
  { id = "forest", fg = "e8f5e1", bg = "1b3a26" },
  { id = "paper", fg = "111111", bg = "f2f2f2" },
  { id = "contrast", fg = "ffffff", bg = "000000" },
}

N.DEFAULT_STYLE = { font = "frizqt", size = 13, fg = "f3eee2", bg = "1a1a1a", alpha = 0.92 }
N.DEFAULT_WINDOW = { open = false, sticky = false, x = nil, y = nil, w = 300, h = 220, scale = 1, minimized = false }
N.WINDOW_MIN_W, N.WINDOW_MIN_H, N.WINDOW_MAX_W, N.WINDOW_MAX_H = 240, 120, 900, 900

N.random = math.random

local ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

-- Root --------------------------------------------------------------------------

function N.root()
  local db = ns.db
  local r = type(db.notes) == "table" and db.notes or {}
  db.notes = r
  r.v = r.v or 1
  r.items = type(r.items) == "table" and r.items or {}
  r.trash = type(r.trash) == "table" and r.trash or {}
  r.ui = type(r.ui) == "table" and r.ui or {}
  r.lastOpened = type(r.lastOpened) == "string" and r.lastOpened or ""
  if not r.manualOrder then
    -- Keep the order users saw so far (last changed first), ties by position.
    local rank = {}
    for i, note in ipairs(r.items) do
      rank[note] = i
    end
    table.sort(r.items, function(a, b)
      local ua, ub = type(a.updated) == "number" and a.updated or 0, type(b.updated) == "number" and b.updated or 0
      if ua ~= ub then
        return ua > ub
      end
      return rank[a] < rank[b]
    end)
    r.manualOrder = true
  end
  if r.windowStyleV ~= 1 then
    r.windowStyleV = 1
    for _, note in ipairs(r.items) do
      N.migrateWindowStyle(note)
    end
    for _, entry in ipairs(r.trash) do
      N.migrateWindowStyle(type(entry) == "table" and entry.note or nil)
    end
  end
  if r.legacyFontV ~= 1 then
    r.legacyFontV = 1
    local function reset(note)
      local style = type(note) == "table" and note.style
      if type(style) == "table" and style.font == N.LEGACY_FONT_KEY then
        style.font = N.DEFAULT_STYLE.font
      end
    end
    for _, note in ipairs(r.items) do
      reset(note)
    end
    for _, entry in ipairs(r.trash) do
      reset(type(entry) == "table" and entry.note or nil)
    end
  end
  return r
end

local function changed(kind, id)
  if ns.Emit then
    ns.Emit("FG_NOTES_CHANGED", kind, id)
  end
end

-- Cleaning ----------------------------------------------------------------------

local function num(v, lo, hi, default)
  v = tonumber(v)
  if not v or v ~= v then
    return default
  end
  return U.clamp(v, lo, hi)
end

function N.cleanTitle(title)
  local s = C.sanitize(tostring(title or "")):gsub("%s+", " ")
  s = U.trim(s)
  local cut = C.sanitize(C.truncateChars(s, N.MAX_TITLE))
  return cut, cut ~= s
end

-- Accepts a list or "a, b, c". Unique ignoring case, at most MAX_TAGS.
function N.cleanTags(tags)
  local list = {}
  if type(tags) == "string" then
    for part in tags:gmatch("[^,;]+") do
      list[#list + 1] = part
    end
  elseif type(tags) == "table" then
    for i = 1, math.min(#tags, 64) do
      list[#list + 1] = tags[i]
    end
  end
  local out, seen = {}, {}
  for _, raw in ipairs(list) do
    if type(raw) == "string" then
      local tag = C.sanitize(C.truncateChars(U.trim((C.sanitize(raw):gsub("[,;]", " "):gsub("%s+", " "))), N.MAX_TAG))
      local key = S.fold(tag)
      if tag ~= "" and not seen[key] then
        seen[key] = true
        out[#out + 1] = tag
        if #out >= N.MAX_TAGS then
          break
        end
      end
    end
  end
  return out
end

local function hex6(v, default)
  if type(v) == "string" and v:match("^%x%x%x%x%x%x$") then
    return v:lower()
  end
  return default
end

local function fontKey(v, default)
  if type(v) ~= "string" then
    return default
  end
  if N.FONT_FILES[v] or v:match("^lsm:[%w _%-%.]+$") and #v <= 44 then
    return v
  end
  return default
end

function N.cleanStyle(style, base)
  base = base or N.DEFAULT_STYLE
  style = type(style) == "table" and style or {}
  return {
    font = fontKey(style.font, base.font),
    size = math.floor(num(style.size, N.SIZE_MIN, N.SIZE_MAX, base.size) + 0.5),
    fg = hex6(style.fg, base.fg),
    bg = hex6(style.bg, base.bg),
    alpha = U.round(num(style.alpha, N.ALPHA_MIN, 1, base.alpha), 0.01),
  }
end

function N.cleanWindow(w, base)
  base = base or N.DEFAULT_WINDOW
  w = type(w) == "table" and w or {}
  local out = {
    open = w.open == true,
    sticky = w.sticky == true,
    w = math.floor(num(w.w, N.WINDOW_MIN_W, N.WINDOW_MAX_W, base.w)),
    h = math.floor(num(w.h, N.WINDOW_MIN_H, N.WINDOW_MAX_H, base.h)),
    scale = U.round(num(w.scale, N.SCALE_MIN, N.SCALE_MAX, base.scale), 0.05),
    minimized = w.minimized == true,
  }
  if type(w.x) == "number" and type(w.y) == "number" then
    out.x, out.y = U.clamp(w.x, -10000, 10000), U.clamp(w.y, -10000, 10000)
  end
  -- Look overrides of this window (nil = follow the global window defaults).
  out.bg = hex6(w.bg, nil)
  local alpha = num(w.alpha, 0, 1, nil)
  out.alpha = alpha and U.round(alpha, 0.01)
  if type(w.autoHide) == "boolean" then
    out.autoHide = w.autoHide
  end
  return out
end

-- A note's own background color and opacity (Notes page, import, old versions) become
-- per-window overrides, so they keep winning over the global window defaults.
function N.migrateWindowStyle(note)
  if type(note) ~= "table" or type(note.style) ~= "table" then
    return
  end
  note.window = type(note.window) == "table" and note.window or {}
  local d = N.DEFAULT_STYLE
  local bg = hex6(note.style.bg, nil)
  if note.window.bg == nil and bg and bg ~= d.bg then
    note.window.bg = bg
  end
  local alpha = num(note.style.alpha, 0, 1, nil)
  if note.window.alpha == nil and alpha and math.abs(alpha - d.alpha) > 0.001 then
    note.window.alpha = U.round(alpha, 0.01)
  end
end

-- IDs ---------------------------------------------------------------------------

local function idTaken(id)
  local r = N.root()
  for _, n in ipairs(r.items) do
    if n.id == id then
      return true
    end
  end
  for _, t in ipairs(r.trash) do
    if t.note and t.note.id == id then
      return true
    end
  end
  return false
end

function N.newId()
  for _ = 1, 100 do
    local chars = {}
    for i = 1, 8 do
      local k = N.random(#ALPHABET)
      chars[i] = ALPHABET:sub(k, k)
    end
    local id = table.concat(chars)
    if not idTaken(id) then
      return id
    end
  end
  error("notes: no free id")
end

-- CRUD --------------------------------------------------------------------------

function N.get(id)
  for _, n in ipairs(N.root().items) do
    if n.id == id then
      return n
    end
  end
end

function N.count()
  return #N.root().items
end

function N.displayTitle(note)
  if note.title and note.title ~= "" then
    return note.title
  end
  return ns.L["notes.untitled"]
end

-- fields: title, text, tags, fav, style. Returns note or nil, "limit".
function N.create(fields, source)
  fields = fields or {}
  local r = N.root()
  if #r.items >= N.MAX_NOTES then
    return nil, "limit"
  end
  local now = U.now()
  local note = {
    id = N.newId(),
    title = N.cleanTitle(fields.title),
    text = M.sanitize(fields.text or ""),
    tags = N.cleanTags(fields.tags),
    fav = fields.fav == true,
    created = now,
    updated = now,
    style = N.cleanStyle(fields.style),
    window = N.cleanWindow(nil),
    source = source,
  }
  N.migrateWindowStyle(note)
  table.insert(r.items, 1, note)
  changed("create", note.id)
  return note
end

-- Remembers the note the Notes page shows first. No event, no timestamp, no reorder:
-- opening a note must not touch the list.
function N.setLastOpened(id)
  if N.get(id) then
    N.root().lastOpened = id
  end
end

-- The note to show when the Notes page opens: the last opened one while it exists,
-- else the most recently changed one, else the first, else nil (no notes).
function N.startNote()
  local r = N.root()
  local note = N.get(r.lastOpened)
  if note then
    return note
  end
  for _, candidate in ipairs(r.items) do
    if not note or (candidate.updated or 0) > (note.updated or 0) then
      note = candidate
    end
  end
  return note
end

-- Shallow equality for arrays and flat maps.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- patch: title, text, tags, fav, style (merged), window (merged). `updated`
-- only moves when a content value really changes, not for window moves and
-- not for writes of the same value. Never touches the list order. Nothing is
-- emitted when nothing changed.
function N.update(id, patch)
  local note = N.get(id)
  if not note then
    return nil
  end
  local content, window = false, false
  if patch.title ~= nil then
    local title = N.cleanTitle(patch.title)
    content = content or title ~= note.title
    note.title = title
  end
  if patch.text ~= nil then
    local text = M.sanitize(patch.text)
    content = content or text ~= note.text
    note.text = text
  end
  if patch.tags ~= nil then
    local tags = N.cleanTags(patch.tags)
    content = content or not same(tags, note.tags)
    note.tags = tags
  end
  if patch.fav ~= nil then
    local fav = patch.fav == true
    content = content or fav ~= note.fav
    note.fav = fav
  end
  local winPatch = patch.window
  if patch.style ~= nil then
    local style = N.cleanStyle(patch.style, note.style)
    content = content or not same(style, note.style)
    -- A changed background or opacity from the Notes page is also the look of the note window.
    if style.bg ~= note.style.bg or style.alpha ~= note.style.alpha then
      winPatch = U.copy(winPatch or {})
      if winPatch.bg == nil and style.bg ~= note.style.bg then
        winPatch.bg = style.bg
      end
      if winPatch.alpha == nil and style.alpha ~= note.style.alpha then
        winPatch.alpha = style.alpha
      end
    end
    note.style = style
  end
  if winPatch ~= nil then
    local merged = U.copy(note.window)
    -- resetStyle drops the look overrides; false clears one (nil cannot travel in a patch).
    if winPatch.resetStyle then
      merged.bg, merged.alpha, merged.autoHide = nil, nil, nil
    end
    for k, v in pairs(winPatch) do
      merged[k] = v
    end
    local clean = N.cleanWindow(merged, N.DEFAULT_WINDOW)
    window = not same(clean, note.window)
    note.window = clean
  end
  if content then
    note.updated = U.now()
  end
  if content or window then
    changed(content and "update" or "window", id)
  end
  return note
end

function N.duplicate(id)
  local note = N.get(id)
  if not note then
    return nil
  end
  local copy, why = N.create({
    title = note.title .. " 2",
    text = note.text,
    tags = note.tags,
    style = note.style,
  })
  if copy then
    local w = note.window
    N.update(copy.id, { window = { bg = w.bg or false, alpha = w.alpha or false, autoHide = w.autoHide } })
  end
  return copy, why
end

-- Trash -------------------------------------------------------------------------

function N.pruneTrash(now)
  now = now or U.now()
  local trash = N.root().trash
  local keep = {}
  for _, t in ipairs(trash) do
    if type(t) == "table" and type(t.note) == "table" and now - (t.deleted or 0) <= N.TRASH_DAYS * 86400 then
      keep[#keep + 1] = t
    end
  end
  table.sort(keep, function(a, b)
    return (a.deleted or 0) > (b.deleted or 0)
  end)
  while #keep > N.MAX_TRASH do
    keep[#keep] = nil
  end
  for i = 1, math.max(#trash, #keep) do
    trash[i] = keep[i]
  end
end

function N.delete(id)
  local r = N.root()
  for i, note in ipairs(r.items) do
    if note.id == id then
      table.remove(r.items, i)
      note.window = N.cleanWindow(note.window)
      note.window.open = false
      r.trash[#r.trash + 1] = { note = note, deleted = U.now() }
      N.pruneTrash()
      changed("delete", id)
      return true
    end
  end
  return false
end

function N.trashList()
  local out = {}
  for _, t in ipairs(N.root().trash) do
    out[#out + 1] = t
  end
  table.sort(out, function(a, b)
    return (a.deleted or 0) > (b.deleted or 0)
  end)
  return out
end

-- Returns note or nil, "limit" | "missing".
function N.restore(id)
  local r = N.root()
  for i, t in ipairs(r.trash) do
    if t.note and t.note.id == id then
      if #r.items >= N.MAX_NOTES then
        return nil, "limit"
      end
      table.remove(r.trash, i)
      local note = t.note
      if N.get(note.id) then
        note.id = N.newId()
      end
      table.insert(r.items, 1, note)
      changed("restore", note.id)
      return note
    end
  end
  return nil, "missing"
end

function N.purge(id)
  local trash = N.root().trash
  for i, t in ipairs(trash) do
    if t.note and t.note.id == id then
      table.remove(trash, i)
      changed("purge", id)
      return true
    end
  end
  return false
end

function N.emptyTrash()
  local trash = N.root().trash
  local n = #trash
  for i = n, 1, -1 do
    trash[i] = nil
  end
  changed("purge")
  return n
end

-- Tags and search ----------------------------------------------------------------

-- Sorted { name, count }.
function N.allTags()
  local counts, names = {}, {}
  for _, note in ipairs(N.root().items) do
    for _, tag in ipairs(note.tags or {}) do
      local key = S.fold(tag)
      if not counts[key] then
        counts[key] = 0
        names[key] = tag
      end
      counts[key] = counts[key] + 1
    end
  end
  local out = {}
  for key, count in pairs(counts) do
    out[#out + 1] = { name = names[key], count = count }
  end
  table.sort(out, function(a, b)
    return S.fold(a.name) < S.fold(b.name)
  end)
  return out
end

-- opts: query, tag, fav (only favorites), sort = "manual" (default, stored
-- order) | "updated" | "created" | "title".
function N.list(opts)
  opts = opts or {}
  local query = S.fold(U.trim(opts.query or ""))
  local tag = opts.tag and opts.tag ~= "" and S.fold(opts.tag) or nil
  local out = {}
  for i, note in ipairs(N.root().items) do
    local ok = not (opts.fav and not note.fav)
    if ok and tag then
      ok = false
      for _, t in ipairs(note.tags or {}) do
        if S.fold(t) == tag then
          ok = true
          break
        end
      end
    end
    if ok and query ~= "" then
      local hay = S.fold(note.title .. "\n" .. M.plain(note.text) .. "\n" .. table.concat(note.tags or {}, " "))
      ok = hay:find(query, 1, true) ~= nil
    end
    if ok then
      out[#out + 1] = { note = note, i = i }
    end
  end
  local sort = opts.sort or "manual"
  if sort ~= "manual" then
    table.sort(out, function(a, b)
      local x, y = a.note, b.note
      if sort == "title" then
        local tx, ty = S.fold(x.title), S.fold(y.title)
        if tx ~= ty then
          return tx < ty
        end
      elseif sort == "created" then
        if x.created ~= y.created then
          return (x.created or 0) > (y.created or 0)
        end
      elseif x.updated ~= y.updated then
        return (x.updated or 0) > (y.updated or 0)
      end
      return a.i < b.i
    end)
  end
  for i, entry in ipairs(out) do
    out[i] = entry.note
  end
  return out
end

-- Manual order ---------------------------------------------------------------------

local function indexOf(items, id)
  for i, note in ipairs(items) do
    if note.id == id then
      return i
    end
  end
end

-- Moves a note directly before (or, with `after`, behind) another note.
-- Returns true when the position changed.
function N.reorder(id, anchorId, after)
  local items = N.root().items
  local from = indexOf(items, id)
  if id == anchorId or not from or not indexOf(items, anchorId) then
    return false
  end
  local note = table.remove(items, from)
  local at = indexOf(items, anchorId)
  local to = after and at + 1 or at
  table.insert(items, to, note)
  if to == from then
    return false
  end
  changed("order", id)
  return true
end

-- edge: "top" | "bottom". Returns true when the position changed.
function N.moveToEdge(id, edge)
  local items = N.root().items
  local from = indexOf(items, id)
  if not from then
    return false
  end
  local to = edge == "top" and 1 or #items
  if to == from then
    return false
  end
  table.insert(items, to, table.remove(items, from))
  changed("order", id)
  return true
end

-- One step up (dir -1) or down (dir 1) among the notes of `visible` (the
-- filtered list the user sees, defaults to all). False at the edges.
function N.step(id, dir, visible)
  visible = visible or N.list()
  local i = indexOf(visible, id)
  local neighbor = i and visible[i + dir]
  if not neighbor then
    return false
  end
  return N.reorder(id, neighbor.id, dir > 0)
end

function N.findByTitle(query)
  local q = S.fold(U.trim(query or ""))
  if q == "" then
    return nil
  end
  local best
  for _, note in ipairs(N.root().items) do
    local t = S.fold(note.title)
    if t == q then
      return note
    end
    if not best and t:find(q, 1, true) then
      best = note
    end
  end
  return best
end

-- Export / import ----------------------------------------------------------------

function N.pack(note)
  local st = note.style or N.DEFAULT_STYLE
  return {
    title = note.title,
    text = note.text,
    tags = note.tags,
    style = { font = st.font, size = st.size, fg = st.fg, bg = st.bg, alpha = st.alpha },
  }
end

-- notes: list of note tables. Returns a list of strings (each within the input
-- limit and MAX_ITEMS), or nil, reason.
function N.exportStrings(notes)
  local strings = {}
  local function emit(from, to)
    local items = {}
    for i = from, to do
      items[#items + 1] = N.pack(notes[i])
    end
    local s, why = ns.Strings.encode("notes", { items = items })
    if not s then
      return false, why
    end
    if #s > ns.Strings.MAX_INPUT * 0.9 and to > from then
      local mid = math.floor((from + to) / 2)
      local ok, err = emit(from, mid)
      if not ok then
        return false, err
      end
      return emit(mid + 1, to)
    end
    strings[#strings + 1] = s
    return true
  end
  local from = 1
  while from <= #notes do
    local to = math.min(from + N.MAX_ITEMS - 1, #notes)
    local ok, why = emit(from, to)
    if not ok then
      return nil, why
    end
    from = to + 1
  end
  return strings
end

function N.exportText(notes)
  local out = {}
  for _, note in ipairs(notes) do
    local plain = M.plain(note.text)
    out[#out + 1] = #notes == 1 and plain or ("### " .. N.displayTitle(note) .. "\n" .. plain)
  end
  return table.concat(out, "\n\n")
end

local function cleanImported(raw)
  if type(raw) ~= "table" or type(raw.text) ~= "string" or #raw.text > N.MAX_TEXT * 4 then
    return nil
  end
  if raw.title ~= nil and type(raw.title) ~= "string" then
    return nil
  end
  local title, titleCut = N.cleanTitle(raw.title or "")
  local text = M.sanitize(raw.text)
  local full = M.sanitize(raw.text, N.MAX_TEXT * 4)
  return {
    title = title,
    text = text,
    tags = N.cleanTags(raw.tags),
    style = N.cleanStyle(raw.style),
    cut = titleCut or M.length(full) > M.length(text),
  }
end

local function fromEnvelope(env)
  if env.type ~= "notes" then
    return nil, "type"
  end
  if type(env.v) ~= "number" or env.v > ns.Strings.VERSION then
    return nil, "version"
  end
  local items = env.data and env.data.items
  if type(items) ~= "table" or #items < 1 or #items > N.MAX_ITEMS then
    return nil, "items", 0
  end
  local out = {}
  for i, raw in ipairs(items) do
    local item = cleanImported(raw)
    if not item then
      return nil, "items", i
    end
    out[i] = item
  end
  return out
end

local function fromPlain(text)
  local first = text:match("^%s*([^\n]*)")
  first = first:gsub("^#+%s*", "")
  local title, titleCut = N.cleanTitle(first)
  local clean = M.sanitize(text)
  return {
    {
      title = title,
      text = clean,
      tags = {},
      style = N.cleanStyle(nil),
      cut = titleCut or M.length(M.sanitize(text, N.MAX_TEXT * 4)) > M.length(clean),
    },
  }
end

local function looksEncoded(token)
  return #token >= 20 and token:match("^[%w%(%)]+$") ~= nil
end

-- Returns { source = "strings"|"json"|"text", items = { { title, text, tags, style, cut } } }
-- or nil, code[, index]. Never adds anything to the database.
function N.parseImport(text)
  text = U.trim(text or "")
  if text == "" then
    return nil, "empty"
  end
  if #text > N.MAX_PASTE then
    return nil, "too-large"
  end
  local tokens = {}
  for token in text:gmatch("%S+") do
    tokens[#tokens + 1] = token
  end
  local multi = #tokens > 1
  if multi then
    for _, token in ipairs(tokens) do
      if not looksEncoded(token) then
        multi = false
        break
      end
    end
  end
  if multi then
    if #tokens > N.MAX_TOKENS then
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
        return nil, err, at
      end
      for _, item in ipairs(items) do
        all[#all + 1] = item
      end
      if #all > N.MAX_NOTES then
        return nil, "items", index
      end
    end
    return { source = "strings", items = all }
  end
  if #text > ns.Strings.MAX_INPUT then
    return nil, "too-large"
  end
  local env, why = ns.Strings.decode(text)
  local source = "strings"
  if not env and why == "too-large" then
    return nil, why
  end
  if not env and text:sub(1, 1) == "{" then
    local ok, decoded = pcall(ns.Json.decode, text)
    if ok and type(decoded) == "table" and type(decoded.type) == "string" and type(decoded.data) == "table" then
      env, source = decoded, "json"
    end
  end
  if env then
    local items, err, index = fromEnvelope(env)
    if not items then
      return nil, err, index
    end
    return { source = source, items = items }
  end
  if not text:find("%s") and #text > 20 then
    return nil, "decode"
  end
  return { source = "text", items = fromPlain(text) }
end

-- Adds parsed items as new notes (new IDs, source recorded) as one block on top
-- that keeps the order of `items`. Returns added, skipped.
function N.importItems(items, kind)
  local added = 0
  local take = math.min(#items, math.max(0, N.MAX_NOTES - N.count()))
  -- New notes go to the top, so the last one is created first.
  for i = take, 1, -1 do
    if N.create(items[i], { kind = kind or "paste", at = U.now() }) then
      added = added + 1
    end
  end
  return added, #items - added
end
