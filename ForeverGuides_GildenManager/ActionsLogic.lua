-- Rules for the writing guild actions, no game calls: which action needs which right, the rank
-- rules, the pause between two actions, the typed-name check and the local action log
-- (gm.db.log = list of { t, action, name, old, new }, oldest first, at most MAX_LOG entries).
-- A check answers { ok = true } or { ok = false, reason = code }; the text of a code is the locale
-- key "gm.why.<code>". A right that is missing or unknown always means no.
local _, gm = ...
if not gm.ext then
  return
end
local PN, U = gm.FG.PlayerName, gm.FG.U

local AL = {}
gm.ActionsLogic = AL

AL.MAX_NOTE = 31
AL.MAX_LOG = 200
AL.MAX_TEXT = 60
-- Seconds between two writing actions.
AL.GAP = 2
-- Rank indexes of a guild run 0 (master) to 9.
local MAX_RANK = 9

-- Action -> field of the table of GuildExt.Rights().
AL.RIGHT = {
  invite = "invite",
  promote = "promote",
  demote = "demote",
  remove = "remove",
  editNote = "publicNote",
  viewOfficerNote = "officerNote",
  editOfficerNote = "officerEdit",
  editMotd = "motd",
  editGuildInfo = "guildInfo",
}
-- Actions that change the guild; only these are logged.
AL.LOGGED = { promote = true, demote = true, remove = true, editNote = true, editOfficerNote = true }
-- Actions on a member: the target must be known. The rank rules apply to RANKED only.
local TARGETED = { promote = true, demote = true, remove = true, editNote = true, editOfficerNote = true }
local RANKED = { promote = true, demote = true, remove = true }

-- Every reason code the logic and the game side answer, for the locale check.
AL.REASONS = {
  "unknownAction",
  "noRight",
  "noTarget",
  "unknownRank",
  "self",
  "leader",
  "notLower",
  "promoteCap",
  "lowest",
  "combat",
  "throttle",
  "noApi",
  "noGuid",
  "failed",
  "unchanged",
  "nameMismatch",
}

local YES = { ok = true }

local function no(reason)
  return { ok = false, reason = reason }
end

local function rankOf(m)
  local r = type(m) == "table" and m.rank
  return type(r) == "number" and r % 1 == 0 and r >= 0 and r <= MAX_RANK and r or nil
end

-- action: key of AL.RIGHT. rights: GuildExt.Rights(). ctx (rank rules and targets only):
-- self = { key, rank } and target = { key, rank } roster rows, lowest = rank index of the lowest rank.
function AL.Check(action, rights, ctx)
  local field = AL.RIGHT[action]
  if not field then
    return no("unknownAction")
  end
  if type(rights) ~= "table" or rights[field] ~= true then
    return no("noRight")
  end
  if not TARGETED[action] then
    return YES
  end
  ctx = type(ctx) == "table" and ctx or {}
  local me, target = ctx.self, ctx.target
  if type(target) ~= "table" or type(target.key) ~= "string" or target.key == "" then
    return no("noTarget")
  end
  if not RANKED[action] then
    return YES
  end
  local mine, theirs = rankOf(me), rankOf(target)
  if not mine then
    return no("unknownRank")
  end
  if me.key == target.key then
    return no("self")
  end
  if not theirs then
    return no("unknownRank")
  end
  if theirs == 0 then
    return no("leader")
  end
  if theirs <= mine then
    return no("notLower")
  end
  if action == "promote" and theirs - 1 <= mine then
    return no("promoteCap")
  end
  if action == "demote" then
    local lowest = rankOf({ rank = ctx.lowest })
    if not lowest then
      return no("unknownRank")
    end
    if theirs >= lowest then
      return no("lowest")
    end
  end
  return YES
end

-- Rank index after the action, nil for actions that keep the rank.
function AL.NewRank(action, target)
  local r = rankOf(target)
  if not r then
    return nil
  end
  if action == "promote" then
    return r - 1
  elseif action == "demote" then
    return r + 1
  end
end

-- Rank index of the lowest rank: the highest of the rank count the game reports (nil when unknown)
-- and the ranks the roster shows. Too low only hides a demotion, the server decides anyway.
function AL.Lowest(ranks, count)
  local best = type(count) == "number" and count % 1 == 0 and count >= 1 and count - 1 or nil
  for _, r in ipairs(type(ranks) == "table" and ranks or {}) do
    local index = rankOf({ rank = type(r) == "table" and r.index })
    if index and (not best or index > best) then
      best = index
    end
  end
  return best
end

-- Seconds left until the next writing action may run, 0 when it may run now. A clock that went
-- back never blocks.
function AL.Wait(last, now)
  if type(last) ~= "number" or type(now) ~= "number" or now < last then
    return 0
  end
  return math.max(0, AL.GAP - (now - last))
end

-- True when the typed text is the name of the member (case and own realm do not matter).
function AL.NameConfirmed(typed, name)
  return type(typed) == "string" and type(name) == "string" and PN.Equal(typed, name)
end

-- One line, at most MAX_NOTE characters, the same limit the game applies to guild notes.
function AL.CleanNote(s)
  return U.trim(PN.Cut(gm.MembersLogic.CleanNote(s), AL.MAX_NOTE))
end

-- Log ------------------------------------------------------------------------------------------------

local function text(v)
  return type(v) == "string" and PN.Cut(v, AL.MAX_TEXT) or ""
end

local function trim(list)
  while #list > AL.MAX_LOG do
    table.remove(list, 1)
  end
end

-- Drops what SavedVariables left malformed, in place.
function AL.Clean(db)
  local clean = {}
  for _, e in ipairs(type(db.log) == "table" and db.log or {}) do
    if type(e) == "table" and type(e.t) == "number" and e.t == e.t and AL.LOGGED[e.action] and text(e.name) ~= "" then
      clean[#clean + 1] = { t = e.t, action = e.action, name = text(e.name), old = text(e.old), new = text(e.new) }
    end
  end
  trim(clean)
  db.log = clean
  db.dryRun = db.dryRun == true
end

-- entry: { action, name, old, new }. False for an entry that is not worth a line.
function AL.Record(db, entry, now)
  if type(entry) ~= "table" or not AL.LOGGED[entry.action] or text(entry.name) == "" then
    return false
  end
  db.log[#db.log + 1] = {
    t = type(now) == "number" and now or 0,
    action = entry.action,
    name = text(entry.name),
    old = text(entry.old),
    new = text(entry.new),
  }
  trim(db.log)
  return true
end

-- Newest first. needle: part of the name, the old or new value or the label of the action (label(action)).
function AL.Filter(list, needle, label)
  needle = PN.Lower(U.trim(type(needle) == "string" and needle or ""))
  local out = {}
  for i = #list, 1, -1 do
    local e = list[i]
    if needle == "" then
      out[#out + 1] = e
    else
      for _, field in ipairs({ e.name, e.old, e.new, label and label(e.action) or "" }) do
        if PN.Lower(field):find(needle, 1, true) then
          out[#out + 1] = e
          break
        end
      end
    end
  end
  return out
end
