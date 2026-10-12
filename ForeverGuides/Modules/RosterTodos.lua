-- Own todo rows of the character overview. The definitions are account-wide
-- (ns.db.todoDefs), the ticks are per character (roster entry .todos.values[id]).
--
-- Definition: { id, name, icon (optional), reset = "never"|"daily"|"weekly", weekday (1 =
-- Sunday .. 7), hour, min (all optional: the reset time, else ns.db.rosterReset),
-- enabled }. The default reset is Tuesday 07:00 server time. Nothing here knows the server
-- time zone: the offset comes from the client's server clock (GetGameTime) or is 0.
--
-- Notes (one line, NOTE_MAX characters) per character and row live in ns.db.todoNotes[charKey][id].
-- They are kept apart from the roster entry on purpose: CharRoster.Clean rebuilds the entry
-- on every capture and would drop a field it does not know. A reset never touches a note.
local _, ns = ...
local U = ns.U

local T = {}
ns.RosterTodos = T

T.MAX_DEFS = 50
local DAY, WEEK = 86400, 604800
local FALLBACK = { weekday = 3, hour = 7, min = 0 }
local RESETS = { never = true, daily = true, weekly = true }

local function text(v, max)
  if type(v) ~= "string" then
    return nil
  end
  v = U.trim(v):sub(1, max or 60)
  return v ~= "" and v or nil
end

local function int(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return math.floor(v)
end

-- Notes ------------------------------------------------------------------------------

T.NOTE_MAX = 120

-- One line, at most NOTE_MAX characters (not bytes); nil when nothing is left.
local function cleanNote(v)
  if type(v) ~= "string" then
    return nil
  end
  v = U.trim((v:gsub("%c+", " ")))
  local n = 0
  for i = 1, #v do
    local b = v:byte(i)
    if b < 128 or b >= 192 then
      n = n + 1
      if n > T.NOTE_MAX then
        v = U.trim(v:sub(1, i - 1))
        break
      end
    end
  end
  return v ~= "" and v or nil
end
T.CleanNote = cleanNote

-- Removes every note `drop(charKey, id)` says yes to, and every damaged one. Empty
-- per-character tables go too. Returns the number of removed notes.
local function dropNotes(drop)
  local all = type(ns.db) == "table" and ns.db.todoNotes
  if all == nil then
    return 0
  elseif type(all) ~= "table" then
    ns.db.todoNotes = nil
    return 1
  end
  local count = 0
  for key, per in pairs(all) do
    if type(per) ~= "table" then
      all[key] = nil
      count = count + 1
    else
      for id, note in pairs(per) do
        if type(id) ~= "string" or cleanNote(note) == nil or drop(key, id) then
          per[id] = nil
          count = count + 1
        end
      end
      if next(per) == nil then
        all[key] = nil
      end
    end
  end
  return count
end

-- Definitions ------------------------------------------------------------------------

local function cleanDef(raw)
  local id = type(raw) == "table" and text(raw.id, 40)
  local name = id and text(raw.name, 60)
  if not name then
    return nil
  end
  return {
    id = id,
    name = name,
    icon = text(raw.icon, 120),
    reset = RESETS[raw.reset] and raw.reset or "never",
    weekday = int(raw.weekday, 1, 7),
    hour = int(raw.hour, 0, 23),
    min = int(raw.min, 0, 59),
    enabled = raw.enabled ~= false,
  }
end

local function cleanDefs(raw)
  local out, seen = {}, {}
  for _, r in ipairs(type(raw) == "table" and raw or {}) do
    local def = #out < T.MAX_DEFS and cleanDef(r)
    if def and not seen[def.id] then
      seen[def.id] = true
      out[#out + 1] = def
    end
  end
  return out
end

-- The stored list, replaced by its clean form (a damaged value is dropped).
local function stored()
  ns.db.todoDefs = cleanDefs(ns.db.todoDefs)
  return ns.db.todoDefs
end

local function changed()
  ns.Emit("FG_ROSTER_CHANGED")
end

local function find(list, id)
  for i, d in ipairs(list) do
    if d.id == id then
      return d, i
    end
  end
end

function T.Defs()
  return type(ns.db) == "table" and cleanDefs(ns.db.todoDefs) or {}
end

function T.Get(id)
  return (find(T.Defs(), id))
end

-- A name typed in the UI: the clean name, or nil and "empty", "long" (more than NAME_MAX
-- characters) or "dup" (another row has it, ignoring case). `exceptId` is the row being renamed.
T.NAME_MAX = 40
function T.CheckName(name, exceptId)
  name = type(name) == "string" and U.trim(name) or ""
  if name == "" then
    return nil, "empty"
  elseif select(2, name:gsub("[^\128-\191]", "")) > T.NAME_MAX then
    return nil, "long"
  end
  for _, d in ipairs(T.Defs()) do
    if d.id ~= exceptId and d.name:lower() == name:lower() then
      return nil, "dup"
    end
  end
  return name
end

-- Returns the new id, nil and "name" (empty name) or "full" (too many rows).
-- opts: icon, reset, weekday, hour, min.
function T.Add(name, opts)
  if type(ns.db) ~= "table" then
    return nil, "name"
  end
  name = text(name, 60)
  if not name then
    return nil, "name"
  end
  local list = stored()
  if #list >= T.MAX_DEFS then
    return nil, "full"
  end
  local top = 0
  for _, d in ipairs(list) do
    top = math.max(top, tonumber(d.id:match("^t(%d+)$")) or 0)
  end
  opts = opts or {}
  local def = cleanDef({
    id = "t" .. (top + 1),
    name = name,
    icon = opts.icon,
    reset = opts.reset,
    weekday = opts.weekday,
    hour = opts.hour,
    min = opts.min,
  })
  list[#list + 1] = def
  changed()
  return def.id
end

function T.Rename(id, name)
  local def = find(stored(), id)
  name = text(name, 60)
  if not (def and name) then
    return false
  end
  def.name = name
  changed()
  return true
end

function T.SetEnabled(id, on)
  local def = find(stored(), id)
  if not def then
    return false
  end
  def.enabled = on and true or false
  changed()
  return true
end

-- reset: "never", "daily" or "weekly"; when is { weekday, hour, min } or nil for the
-- default time.
function T.SetReset(id, reset, when)
  local def = find(stored(), id)
  if not (def and RESETS[reset]) then
    return false
  end
  when = when or {}
  def.reset = reset
  def.weekday, def.hour, def.min = int(when.weekday, 1, 7), int(when.hour, 0, 23), int(when.min, 0, 59)
  changed()
  return true
end

-- Deletes the row and every character's ticks and notes of it.
function T.Remove(id)
  local list = stored()
  local _, i = find(list, id)
  if not i then
    return false
  end
  table.remove(list, i)
  dropNotes(function(_, noteId)
    return noteId == id
  end)
  for _, e in pairs(type(ns.db.roster) == "table" and ns.db.roster or {}) do
    if type(e) == "table" and type(e.todos) == "table" and type(e.todos.values) == "table" then
      e.todos.values[id] = nil
    end
  end
  changed()
  return true
end

-- Puts the row at newIndex (clamped).
function T.Move(id, newIndex)
  local list = stored()
  local def, i = find(list, id)
  if not def or type(newIndex) ~= "number" then
    return false
  end
  table.remove(list, i)
  table.insert(list, math.max(1, math.min(#list + 1, math.floor(newIndex))), def)
  changed()
  return true
end

-- Reset times ------------------------------------------------------------------------

-- The reset time of a definition: its own fields, else the saved default, else Tuesday 07:00.
function T.SpecFor(def)
  local saved = type(ns.db) == "table" and type(ns.db.rosterReset) == "table" and ns.db.rosterReset or {}
  def = def or {}
  return {
    weekday = def.weekday or int(saved.weekday, 1, 7) or FALLBACK.weekday,
    hour = def.hour or int(saved.hour, 0, 23) or FALLBACK.hour,
    min = def.min or int(saved.min, 0, 59) or FALLBACK.min,
  }
end

-- Saves the default reset time (weekday 1 = Sunday, server time). False for bad values.
function T.SetDefaultTime(weekday, hour, min)
  weekday, hour, min = int(weekday, 1, 7), int(hour, 0, 23), int(min, 0, 59)
  if not (weekday and hour and min and type(ns.db) == "table") then
    return false
  end
  ns.Store.set("rosterReset", { weekday = weekday, hour = hour, min = min })
  return true
end

-- Seconds the server clock is ahead of UTC, in steps of 15 minutes: the server's hour and
-- minute against UTC. 0 when the client does not tell.
function T.ServerOffset(now)
  local ok, hour, minute = pcall(GetGameTime)
  if not (ok and type(hour) == "number" and type(minute) == "number") then
    return 0
  end
  local utc = date("!*t", now)
  local diff = (hour * 60 + minute) - (utc.hour * 60 + utc.min)
  diff = ((diff + 720) % 1440) - 720
  return math.floor(diff / 15 + 0.5) * 900
end

-- The latest reset at or before `now` (UTC seconds). `offset` is the server clock's
-- distance from UTC in seconds. Pure.
function T.LastReset(reset, spec, now, offset)
  local wall = now + offset
  local parts = date("!*t", wall)
  local boundary = wall - (parts.hour * 3600 + parts.min * 60 + parts.sec) + spec.hour * 3600 + spec.min * 60
  if boundary > wall then
    boundary = boundary - DAY
  end
  if reset == "weekly" then
    boundary = boundary - ((date("!*t", boundary).wday - spec.weekday) % 7) * DAY
  end
  return boundary - offset
end

-- The next reset after `now`, nil for rows that never reset.
function T.NextReset(def, now, offset)
  if not def or (def.reset ~= "daily" and def.reset ~= "weekly") then
    return nil
  end
  now = now or ns.CharRoster.Now()
  offset = offset or T.ServerOffset(now)
  return T.LastReset(def.reset, T.SpecFor(def), now, offset) + (def.reset == "weekly" and WEEK or DAY)
end

local function lastReset(def, now, offset)
  now = now or ns.CharRoster.Now()
  return T.LastReset(def.reset, T.SpecFor(def), now, offset or T.ServerOffset(now))
end

-- Ticks --------------------------------------------------------------------------------

local function entry(key)
  local t = type(ns.db) == "table" and ns.db.roster
  local e = type(t) == "table" and t[key]
  return type(e) == "table" and e or nil
end

local function valueOf(key, id)
  local e = entry(key)
  local v = e and type(e.todos) == "table" and type(e.todos.values) == "table" and e.todos.values[id]
  return type(v) == "table" and v or nil
end

-- Ticked and not yet reset by a daily or weekly reset since.
function T.IsDone(key, id, now, offset)
  local def = T.Get(id)
  local v = def and valueOf(key, id)
  if not (v and v.done == true) then
    return false
  end
  if def.reset == "never" then
    return true
  end
  return type(v.at) == "number" and v.at >= lastReset(def, now, offset)
end

function T.Set(key, id, done, now)
  local e = entry(key)
  if not (e and T.Get(id)) then
    return false
  end
  if type(e.todos) ~= "table" or type(e.todos.values) ~= "table" then
    e.todos = { values = {} }
  end
  e.todos.values[id] = { done = done and true or false, at = now or ns.CharRoster.Now() }
  changed()
  return true
end

function T.Toggle(key, id, now, offset)
  return T.Set(key, id, not T.IsDone(key, id, now, offset), now)
end

-- The note of a character's row, nil without one.
function T.Note(key, id)
  local all = type(ns.db) == "table" and ns.db.todoNotes
  local per = type(all) == "table" and all[key]
  return type(per) == "table" and cleanNote(per[id]) or nil
end

-- Saves the cleaned note; nil or an empty text removes it. False for an unknown character
-- or row, or when `note` is neither a string nor nil.
function T.SetNote(key, id, note)
  if not (entry(key) and T.Get(id)) or (note ~= nil and type(note) ~= "string") then
    return false
  end
  local clean = cleanNote(note)
  if clean == T.Note(key, id) then
    return true
  end
  if clean == nil then
    ns.db.todoNotes[key][id] = nil
    if next(ns.db.todoNotes[key]) == nil then
      ns.db.todoNotes[key] = nil
    end
  else
    if type(ns.db.todoNotes) ~= "table" then
      ns.db.todoNotes = {}
    end
    if type(ns.db.todoNotes[key]) ~= "table" then
      ns.db.todoNotes[key] = {}
    end
    ns.db.todoNotes[key][id] = clean
  end
  changed()
  return true
end

-- Clears the ticks whose reset has passed, the ticks of rows that no longer exist and notes
-- without a row or character. Run at login and when the overview opens. Returns the number
-- of changes.
function T.ApplyResets(now, offset)
  if type(ns.db) ~= "table" or type(ns.db.roster) ~= "table" then
    return 0
  end
  now = now or ns.CharRoster.Now()
  offset = offset or T.ServerOffset(now)
  local defs = {}
  for _, d in ipairs(T.Defs()) do
    defs[d.id] = d
  end
  local count = 0
  for _, e in pairs(ns.db.roster) do
    local values = type(e) == "table" and type(e.todos) == "table" and e.todos.values
    for id, v in pairs(type(values) == "table" and values or {}) do
      local def = defs[id]
      if not def then
        values[id] = nil
        count = count + 1
      elseif type(v) == "table" and v.done == true and def.reset ~= "never" then
        if type(v.at) ~= "number" or v.at < lastReset(def, now, offset) then
          v.done = false
          count = count + 1
        end
      end
    end
  end
  count = count + dropNotes(function(key, id)
    return defs[id] == nil or type(ns.db.roster[key]) ~= "table"
  end)
  if count > 0 then
    changed()
  end
  return count
end

ns.On("PLAYER_LOGIN", function()
  T.ApplyResets()
end)
