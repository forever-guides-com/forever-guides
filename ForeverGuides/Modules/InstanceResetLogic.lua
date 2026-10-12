-- Instance reset, pure part (no game calls): turns the game's format strings into Lua patterns, reads
-- the names out of the system messages, collects them without duplicates and builds one chat line
-- that fits the 255 byte limit of SendChatMessage.
local _, ns = ...

local RL = {}
ns.InstanceResetLogic = RL

-- Seconds after the trigger in which the system messages are collected into one line.
RL.WINDOW = 2
RL.MAX_LINE = 255
RL.MAX_NAMES = 40

-- A game format ("%s has been reset.", "%1$s wurde zurueckgesetzt.") as an anchored pattern with one
-- capture per placeholder. nil for anything that is not a string with a placeholder.
function RL.Pattern(format)
  if type(format) ~= "string" or format == "" then
    return nil
  end
  -- "%%" is a literal percent sign, "%s" and "%1$s" are the placeholders.
  local marked = format:gsub("%%%%", "\2")
  local count
  marked, count = marked:gsub("%%%d*%$?s", "\1")
  if count == 0 then
    return nil
  end
  marked = marked:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("\2", "%%%%")
  return "^" .. marked:gsub("\1", "(.-)") .. "$"
end

-- Instance name from the captured text: a link keeps its bracket text, color codes and stray pipes
-- go (a pipe in a chat line is an escape code). Empty names are dropped.
function RL.CleanName(name)
  if type(name) ~= "string" then
    return nil
  end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  name = name:match("|H.-|h%[(.-)%]|h") or name
  name = name:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    return nil
  end
  return name
end

-- patterns: list of { kind, pattern }. Returns the kind and the cleaned name of the first match.
function RL.Parse(text, patterns)
  if type(text) ~= "string" then
    return nil
  end
  for _, p in ipairs(patterns or {}) do
    local name = text:match(p.pattern)
    if name then
      name = RL.CleanName(name)
      if name then
        return p.kind, name
      end
    end
  end
  return nil
end

-- A fresh collection: { done = {}, failed = {}, seen = {} }.
function RL.NewBatch()
  return { done = {}, failed = {}, seen = {} }
end

-- Adds a name to "done" or "failed" once. A name that was reset is never also listed as failed.
function RL.Add(batch, kind, name)
  local list = batch[kind]
  if not list or type(name) ~= "string" then
    return false
  end
  if #batch.done + #batch.failed >= RL.MAX_NAMES then
    return false
  end
  local key = name:lower()
  if kind == "failed" and batch.seen["done:" .. key] then
    return false
  end
  if batch.seen[kind .. ":" .. key] then
    return false
  end
  batch.seen[kind .. ":" .. key] = true
  list[#list + 1] = name
  return true
end

-- One line "<head with %s>", the names joined by ", ". Too long: as many names as fit, then
-- "<more with %d>"; none fit: only the count text. head, more, count are format strings.
function RL.Line(names, head, more, count, limit)
  limit = limit or RL.MAX_LINE
  local total = #names
  for take = total, 0, -1 do
    local parts = {}
    for i = 1, take do
      parts[i] = names[i]
    end
    local list
    if take == total then
      list = table.concat(parts, ", ")
    elseif take > 0 then
      list = table.concat(parts, ", ") .. " " .. string.format(more, total - take)
    else
      list = string.format(count, total)
    end
    local line = string.format(head, list)
    if #line <= limit then
      return line
    end
  end
  return string.format(head, string.format(count, total)):sub(1, limit)
end
