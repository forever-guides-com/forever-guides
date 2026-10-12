-- Macro library in the SavedVariables (ns.db.macros, schema 2): entries with tags, favorite, folder
-- and an optional two-language title, plus the last versions of every overwritten macro.
-- Pure table logic (no WoW API, no UI). The migration from schema 1 runs once in Core/Store.lua.
--   ns.db.macros = { v = 2, library = { entry }, nextId, ui = {}, backups = { [key] = { version } } }
--   entry   = { id, name, icon, body, mode, perChar, source, gameName, created, updated,
--               tags = { "tag" }, fav = bool, folder = "", title = { de, en } | nil }
--   version = { t, kind = "game" | "library", name, icon, body, perChar }
local _, ns = ...
local C = ns.MacroCore

local Lib = {
  SCHEMA = 2,
  MAX_TAGS = 8,
  MAX_TAG = 24,
  MAX_FOLDER = 24,
  MAX_TITLE = 40,
  MAX_BACKUPS = 5,
  MAX_BACKUP_KEYS = 60,
}
ns.MacroLibrary = Lib

local function str(value)
  return type(value) == "string" and value or ""
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One line of text without control characters or pipes, blanks collapsed, at most n characters.
local function line(s, n)
  s = tostring(s or ""):gsub("[%z\1-\31\127|]", " "):gsub("%s+", " ")
  return C.truncateChars(trim(s), n)
end

-- Cleaners -------------------------------------------------------------------------------------

function Lib.cleanTag(tag)
  return (line(tag, Lib.MAX_TAG):gsub(",", ""))
end

-- Unique tags (compared without case), blanks dropped, at most MAX_TAGS.
function Lib.cleanTags(list)
  local out, seen = {}, {}
  for _, raw in ipairs(type(list) == "table" and list or {}) do
    local tag = Lib.cleanTag(raw)
    local key = tag:lower()
    if tag ~= "" and not seen[key] and #out < Lib.MAX_TAGS then
      seen[key] = true
      out[#out + 1] = tag
    end
  end
  return out
end

-- "a, b ,c" -> { "a", "b", "c" } for the tag field of the editor.
function Lib.parseTags(text)
  local list = {}
  for part in (str(text) .. ","):gmatch("([^,]*),") do
    list[#list + 1] = part
  end
  return Lib.cleanTags(list)
end

function Lib.tagText(tags)
  return table.concat(tags or {}, ", ")
end

function Lib.cleanFolder(folder)
  return line(folder, Lib.MAX_FOLDER)
end

-- { de, en } with a text of at most MAX_TITLE characters in at least one language, else nil.
function Lib.cleanTitle(title)
  if type(title) ~= "table" then
    return nil
  end
  local de, en = line(title.de, Lib.MAX_TITLE), line(title.en, Lib.MAX_TITLE)
  if de == "" and en == "" then
    return nil
  end
  return { de = de ~= "" and de or nil, en = en ~= "" and en or nil }
end

function Lib.cleanName(name)
  name = C.truncateChars(line(name, 200), C.MAX_NAME)
  return name ~= "" and name or "Makro"
end

-- A clean copy of a stored entry, or nil when it is not a table. `taken` (set of ids) gets the
-- id; an id that is missing or used twice is replaced by `nextId()`.
function Lib.cleanEntry(raw, taken, nextId)
  if type(raw) ~= "table" then
    return nil
  end
  local id = type(raw.id) == "number" and raw.id == math.floor(raw.id) and raw.id > 0 and raw.id or nil
  if not id or taken[id] then
    id = nextId()
  end
  taken[id] = true
  local now = ns.U.now()
  local created = type(raw.created) == "number" and raw.created or now
  return {
    id = id,
    name = Lib.cleanName(raw.name),
    icon = type(raw.icon) == "number" and raw.icon or nil,
    body = C.sanitize(str(raw.body), true):sub(1, C.MAX_SOURCE),
    mode = raw.mode == "ids" and "ids" or "names",
    perChar = raw.perChar ~= false,
    source = type(raw.source) == "string" and raw.source or "local",
    gameName = type(raw.gameName) == "string" and raw.gameName or nil,
    created = created,
    updated = type(raw.updated) == "number" and raw.updated or created,
    tags = Lib.cleanTags(raw.tags),
    fav = raw.fav == true,
    folder = Lib.cleanFolder(raw.folder),
    title = Lib.cleanTitle(raw.title),
  }
end

-- Migration schema 1 -> 2 (called from Store.migrations[4], `db` is the whole account table).
-- Entries without a mode choice of the new kind get "names": IDs are no longer the default
-- because /cast <ID> is not assigned in the client.
function Lib.migrate(db)
  local old = type(db.macros) == "table" and db.macros or {}
  local taken, library = {}, {}
  local top = type(old.nextId) == "number" and old.nextId or 1
  for _, raw in ipairs(type(old.library) == "table" and old.library or {}) do
    if type(raw) == "table" and type(raw.id) == "number" and raw.id >= top then
      top = raw.id + 1
    end
  end
  local function nextId()
    local id = top
    top = top + 1
    return id
  end
  for _, raw in ipairs(type(old.library) == "table" and old.library or {}) do
    local entry = Lib.cleanEntry(raw, taken, nextId)
    if entry then
      entry.mode = "names"
      library[#library + 1] = entry
    end
  end
  local ui = type(old.ui) == "table" and old.ui or {}
  if ui.mode == "ids" then
    ui.mode = "names"
  end
  db.macros = { v = Lib.SCHEMA, library = library, nextId = top, ui = ui, backups = {} }
end

-- Access ---------------------------------------------------------------------------------------

-- The stored table. Shape is guaranteed by the store defaults and the migration, nothing is repaired here.
function Lib.db()
  return ns.db.macros
end

function Lib.find(id, db)
  for _, e in ipairs((db or Lib.db()).library) do
    if e.id == id then
      return e
    end
  end
end

function Lib.findByName(name, db)
  for _, e in ipairs((db or Lib.db()).library) do
    if e.name == name then
      return e
    end
  end
end

-- New entry from a table of fields (name, icon, body, mode, perChar, source ...), returned with its id.
function Lib.add(fields, db)
  db = db or Lib.db()
  local taken = {}
  for _, e in ipairs(db.library) do
    taken[e.id] = true
  end
  local entry = Lib.cleanEntry(fields, taken, function()
    local id = db.nextId
    db.nextId = db.nextId + 1
    return id
  end)
  if entry.id >= db.nextId then
    db.nextId = entry.id + 1
  end
  entry.created = ns.U.now()
  entry.updated = entry.created
  db.library[#db.library + 1] = entry
  return entry
end

function Lib.remove(id, db)
  db = db or Lib.db()
  for i, e in ipairs(db.library) do
    if e.id == id then
      table.remove(db.library, i)
      db.backups["e" .. id] = nil
      return true
    end
  end
  return false
end

-- Name that is free in the library: "Name", "Name 2", ... within 16 characters.
function Lib.uniqueName(name, db)
  local taken = {}
  for _, e in ipairs((db or Lib.db()).library) do
    taken[e.name] = true
  end
  return ns.MacroShare.uniqueName(name, taken)
end

-- Copy of an entry under a free name (tags, favorite and folder carry over, the game link does not).
function Lib.duplicate(id, db)
  local source = Lib.find(id, db)
  if not source then
    return nil
  end
  return Lib.add({
    name = Lib.uniqueName(source.name, db),
    icon = source.icon,
    body = source.body,
    mode = source.mode,
    perChar = source.perChar,
    source = "local",
    tags = source.tags,
    fav = source.fav,
    folder = source.folder,
    title = source.title,
  }, db)
end

function Lib.setFav(id, fav, db)
  local e = Lib.find(id, db)
  if e then
    e.fav = fav and true or false
    return true
  end
  return false
end

-- Backups --------------------------------------------------------------------------------------

-- Key of the versions of one macro: "e<id>" for a library entry, else the game macro by name and place.
function Lib.backupKey(entryId, gameName, perChar)
  if entryId then
    return "e" .. entryId
  end
  return "g" .. (perChar and "c:" or "a:") .. str(gameName)
end

local function sameVersion(a, b)
  return a.body == b.body and a.name == b.name and a.icon == b.icon
end

-- Keeps `version` (newest first, at most MAX_BACKUPS per macro, at most MAX_BACKUP_KEYS macros).
-- A version equal to the newest one is not stored twice. Returns true when it was stored.
function Lib.saveBackup(key, version, db)
  db = db or Lib.db()
  local copy = {
    t = version.t or ns.U.now(),
    kind = version.kind == "game" and "game" or "library",
    name = str(version.name),
    icon = type(version.icon) == "number" and version.icon or nil,
    body = str(version.body):sub(1, 2048),
    perChar = version.perChar == true,
  }
  local list = db.backups[key]
  if not list then
    list = {}
    db.backups[key] = list
  end
  if list[1] and sameVersion(list[1], copy) then
    return false
  end
  table.insert(list, 1, copy)
  for i = #list, Lib.MAX_BACKUPS + 1, -1 do
    list[i] = nil
  end
  local keys = {}
  for k, versions in pairs(db.backups) do
    keys[#keys + 1] = { key = k, t = versions[1] and versions[1].t or 0 }
  end
  if #keys > Lib.MAX_BACKUP_KEYS then
    table.sort(keys, function(a, b)
      return a.t > b.t
    end)
    for i = Lib.MAX_BACKUP_KEYS + 1, #keys do
      db.backups[keys[i].key] = nil
    end
  end
  return true
end

function Lib.backups(key, db)
  return (db or Lib.db()).backups[key] or {}
end

-- Changes an entry; the previous version goes to the backups when name, icon or body change.
-- fields: any of name, icon, body, mode, perChar, tags, fav, folder, title, gameName.
function Lib.update(id, fields, db)
  db = db or Lib.db()
  local e = Lib.find(id, db)
  if not e then
    return nil
  end
  local next = {
    name = fields.name ~= nil and Lib.cleanName(fields.name) or e.name,
    icon = fields.icon ~= nil and fields.icon or e.icon,
    body = fields.body ~= nil and C.sanitize(str(fields.body), true):sub(1, C.MAX_SOURCE) or e.body,
  }
  if next.name ~= e.name or next.icon ~= e.icon or next.body ~= e.body then
    Lib.saveBackup(
      "e" .. id,
      { kind = "library", name = e.name, icon = e.icon, body = e.body, perChar = e.perChar },
      db
    )
  end
  e.name, e.icon, e.body = next.name, next.icon, next.body
  if fields.mode ~= nil then
    e.mode = fields.mode == "ids" and "ids" or "names"
  end
  if fields.perChar ~= nil then
    e.perChar = fields.perChar and true or false
  end
  if fields.tags ~= nil then
    e.tags = Lib.cleanTags(fields.tags)
  end
  if fields.fav ~= nil then
    e.fav = fields.fav and true or false
  end
  if fields.folder ~= nil then
    e.folder = Lib.cleanFolder(fields.folder)
  end
  if fields.title ~= nil then
    e.title = Lib.cleanTitle(fields.title)
  end
  if fields.gameName ~= nil then
    e.gameName = fields.gameName ~= "" and fields.gameName or nil
  end
  e.updated = ns.U.now()
  return e
end

-- Views ----------------------------------------------------------------------------------------

-- Title in the addon language when there is one, else the macro name.
function Lib.displayTitle(entry, lang)
  local t = entry.title
  if t then
    return (lang == "de" and (t.de or t.en)) or (t.en or t.de) or entry.name
  end
  return entry.name
end

local function norm(s)
  return ns.MacroSpells.normalize(s or "")
end

-- All distinct tags and folders in use, sorted.
function Lib.tagsInUse(db)
  local set, out = {}, {}
  for _, e in ipairs((db or Lib.db()).library) do
    for _, tag in ipairs(e.tags) do
      if not set[tag:lower()] then
        set[tag:lower()] = true
        out[#out + 1] = tag
      end
    end
  end
  table.sort(out, function(a, b)
    return norm(a) < norm(b)
  end)
  return out
end

function Lib.foldersInUse(db)
  local set, out = {}, {}
  for _, e in ipairs((db or Lib.db()).library) do
    if e.folder ~= "" and not set[e.folder] then
      set[e.folder] = true
      out[#out + 1] = e.folder
    end
  end
  table.sort(out, function(a, b)
    return norm(a) < norm(b)
  end)
  return out
end

-- Entries that match opts and are sorted. opts:
--   query    words that all appear in the name, title, tags, folder or body (umlauts and case ignored)
--   scope    "all" | "account" | "character"
--   fav      true = favorites only
--   folder   a folder name
--   tag      a tag
--   problem  true = only entries for which hasProblem(entry) is true
--   hasProblem(entry) -> bool
--   sort     "name" (default, favorites first) | "recent"
function Lib.list(opts, db)
  opts = opts or {}
  db = db or Lib.db()
  local words = {}
  for word in norm(opts.query):gmatch("[^%s]+") do
    words[#words + 1] = word
  end
  local out = {}
  for _, e in ipairs(db.library) do
    local keep = true
    if opts.scope == "account" then
      keep = not e.perChar
    elseif opts.scope == "character" then
      keep = e.perChar
    end
    if keep and opts.fav and not e.fav then
      keep = false
    end
    if keep and opts.folder and opts.folder ~= "" and e.folder ~= opts.folder then
      keep = false
    end
    if keep and opts.tag and opts.tag ~= "" then
      local found = false
      for _, tag in ipairs(e.tags) do
        found = found or tag:lower() == opts.tag:lower()
      end
      keep = found
    end
    if keep and opts.problem then
      keep = opts.hasProblem ~= nil and opts.hasProblem(e) == true
    end
    if keep and #words > 0 then
      local haystack = norm(table.concat({
        e.name,
        e.title and e.title.de or "",
        e.title and e.title.en or "",
        table.concat(e.tags, " "),
        e.folder,
        e.body,
      }, " "))
      for _, word in ipairs(words) do
        if not haystack:find(word, 1, true) then
          keep = false
          break
        end
      end
    end
    if keep then
      out[#out + 1] = e
    end
  end
  local byRecent = opts.sort == "recent"
  table.sort(out, function(a, b)
    if byRecent then
      if a.updated ~= b.updated then
        return a.updated > b.updated
      end
    elseif a.fav ~= b.fav then
      return a.fav
    end
    local na, nb = norm(a.name), norm(b.name)
    if na ~= nb then
      return na < nb
    end
    return a.id < b.id
  end)
  return out
end

-- Counts for the header: used entries by place.
function Lib.counts(db)
  local account, character, fav = 0, 0, 0
  for _, e in ipairs((db or Lib.db()).library) do
    if e.perChar then
      character = character + 1
    else
      account = account + 1
    end
    if e.fav then
      fav = fav + 1
    end
  end
  return { account = account, character = character, fav = fav, total = account + character }
end
