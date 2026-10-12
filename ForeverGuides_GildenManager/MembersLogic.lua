-- Main and alt links and own notes per guild member, no game calls. The store is
-- gm.db.members[key] = { name, main, mainKey, note } with the roster key of the member (lower case
-- name). Links stay flat: a main has no main, so a member with alts cannot become an alt itself.
local _, gm = ...
if not gm.ext then
  return
end
local PN, U = gm.FG.PlayerName, gm.FG.U

local ML = {}
gm.MembersLogic = ML

ML.MAX_NOTE = 120

local function text(v)
  return type(v) == "string" and v or ""
end

-- One line, no control characters or pipes (colour codes), cut at MAX_NOTE characters.
function ML.CleanNote(s)
  s = text(s):gsub("[%z\1-\31\127|]", " "):gsub("%s+", " ")
  return PN.Cut(U.trim(s), ML.MAX_NOTE)
end

local function keep(store, key)
  local e = store[key]
  if e and e.main == "" and e.note == "" then
    store[key] = nil
  end
end

local function touch(store, member)
  local e = store[member.key]
  if not e then
    e = { name = member.name, main = "", mainKey = "", note = "" }
    store[member.key] = e
  end
  e.name = member.name
  return e
end

-- Drops what SavedVariables left malformed, in place.
function ML.Clean(db)
  if type(db.members) ~= "table" then
    db.members = {}
  end
  for key, e in pairs(db.members) do
    if type(key) ~= "string" or key == "" or type(e) ~= "table" then
      db.members[key] = nil
    else
      e.name = text(e.name) ~= "" and e.name or key
      e.main = PN.Normalize(text(e.main))
      e.mainKey = PN.Lower(e.main)
      e.note = ML.CleanNote(e.note)
      keep(db.members, key)
    end
  end
end

-- Name of the main of the member, nil for a main or an unknown member.
function ML.MainOf(store, key)
  local e = store[key]
  return e and e.main ~= "" and e.main or nil
end

-- Names of the members that point to this one as their main, sorted.
function ML.AltsOf(store, key)
  local out = {}
  for k, e in pairs(store) do
    if k ~= key and e.mainKey == key then
      out[#out + 1] = e.name
    end
  end
  table.sort(out, function(a, b)
    return PN.Lower(a) < PN.Lower(b)
  end)
  return out
end

-- member: { key, name } of the roster. An empty name or the member itself removes the link.
-- Answers true, or false and the reason: "hasAlts" (the member is a main of others), "mainIsAlt"
-- (the chosen main has a main itself).
function ML.SetMain(store, member, name)
  name = PN.Normalize(text(name))
  local mainKey = PN.Lower(name)
  if name == "" or mainKey == member.key then
    local e = store[member.key]
    if e then
      e.main, e.mainKey = "", ""
      keep(store, member.key)
    end
    return true
  end
  if #ML.AltsOf(store, member.key) > 0 then
    return false, "hasAlts"
  end
  if ML.MainOf(store, mainKey) then
    return false, "mainIsAlt"
  end
  local e = touch(store, member)
  e.main, e.mainKey = name, mainKey
  return true
end

-- Returns the stored note, "" when it was cleared.
function ML.SetNote(store, member, note)
  note = ML.CleanNote(note)
  if note == "" then
    local e = store[member.key]
    if e then
      e.note = ""
      keep(store, member.key)
    end
    return ""
  end
  touch(store, member).note = note
  return note
end
