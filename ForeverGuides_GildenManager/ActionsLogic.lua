-- Rules for the writing guild actions, no game calls: which action needs which right, the rank
-- rules, the pause between two actions, the typed-name check and the local action log
-- (guild.actions = list of { t, action, name, old, new }, oldest first, at most the setting maxActions).
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
AL.MAX_TEXT = 60
-- Seconds between two writing actions when no pause is given (the setting pauseSec is the pause in use).
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
  "gone",
  "rankChanged",
  "alreadyDone",
  "needCount",
  "ruleChanged",
  "rosterStale",
  "rankMismatch",
  "unverified",
  "expired",
  "stopped",
  "clientNote",
  "clientRank",
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
-- back never blocks. pause: the pause in seconds (the setting), AL.GAP when missing.
function AL.Wait(last, now, pause)
  if type(last) ~= "number" or type(now) ~= "number" or now < last then
    return 0
  end
  return math.max(0, (type(pause) == "number" and pause or AL.GAP) - (now - last))
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

-- Results a log entry may carry: the call went out (sent), the roster showed the change (verified) or
-- did not (mismatch, unverified).
AL.RESULTS = { sent = true, verified = true, unverified = true, mismatch = true }

local function rankField(v)
  return type(v) == "number" and v % 1 == 0 and v >= 0 and v <= MAX_RANK and v or nil
end

-- The optional fields of a run step (rule, result, ranks for the undo) next to the five basic ones.
local function extras(e, out)
  out.rule = text(e.rule) ~= "" and text(e.rule) or nil
  out.result = AL.RESULTS[e.result] and e.result or nil
  out.from, out.to = rankField(e.from), rankField(e.to)
  out.undone = e.undone == true or nil
  return out
end

-- Drops what SavedVariables left malformed, in place.
function AL.Clean(guild)
  local clean = {}
  for _, e in ipairs(type(guild.actions) == "table" and guild.actions or {}) do
    if type(e) == "table" and type(e.t) == "number" and e.t == e.t and AL.LOGGED[e.action] and text(e.name) ~= "" then
      clean[#clean + 1] =
        extras(e, { t = e.t, action = e.action, name = text(e.name), old = text(e.old), new = text(e.new) })
    end
  end
  guild.actions = gm.GuildStore.Trim(clean, gm.GuildStore.Limit(guild, "maxActions"))
  -- Anything but a real boolean falls back to the safe default (dry run on).
  if type(guild.settings.dryRun) ~= "boolean" then
    guild.settings.dryRun = gm.GuildStore.DEFAULTS.dryRun
  end
end

-- entry: { action, name, old, new, rule, result, from, to }. False for an entry that is not worth a
-- line, else true and the stored entry (a later result may be written into it).
function AL.Record(guild, entry, now)
  if type(entry) ~= "table" or not AL.LOGGED[entry.action] or text(entry.name) == "" then
    return false
  end
  local stored = extras(entry, {
    t = type(now) == "number" and now or 0,
    action = entry.action,
    name = text(entry.name),
    old = text(entry.old),
    new = text(entry.new),
  })
  guild.actions[#guild.actions + 1] = stored
  gm.GuildStore.Trim(guild.actions, gm.GuildStore.Limit(guild, "maxActions"))
  return true, stored
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
