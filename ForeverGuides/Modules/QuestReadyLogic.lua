-- Pure rules of the "quest ready" and "quest progress" chat lines (Modules/QuestReady.lua): which quests of
-- the log just became ready to hand in, which objectives counted up, the texts, and the waiting lines to
-- the group. No game calls.
local _, ns = ...

local QR = {}
ns.QuestReadyLogic = QR

-- The quest log never holds more than this many entries, longer readings are cut.
QR.MAX_ENTRIES = 200

-- known: { [questId] = complete } of the last reading, nil before the first one. entries: { id, complete,
-- title } from the log, complete is nil where the game gave no answer. Returns the new memory and the
-- entries that went from open to ready since the last reading. The first reading, quests that were not
-- in the log before (a half loaded log lists them late) and unreadable answers never announce.
function QR.Diff(known, entries)
  local fresh, ready = {}, {}
  for _, entry in ipairs(entries) do
    local id = entry.id
    if type(id) == "number" and id > 0 and fresh[id] == nil then
      local complete = entry.complete
      if complete == nil and known then
        complete = known[id]
      end
      fresh[id] = complete
      if known and known[id] == false and entry.complete == true then
        ready[#ready + 1] = entry
      end
    end
  end
  return fresh, ready
end

-- The log call answers with true, false or the old numbers (1 ready, -1 failed, nil open).
function QR.Complete(value)
  if value == true or value == 1 then
    return true
  end
  if value == false or value == -1 or value == 0 or value == nil then
    return false
  end
  return nil
end

-- The title of the line, a quest without a readable name shows its number.
function QR.Name(entry)
  if type(entry.title) == "string" and entry.title ~= "" then
    return entry.title
  end
  return "#" .. tostring(entry.id)
end

function QR.Line(template, entry)
  return (string.format(template, QR.Name(entry)))
end

-- Group line ---------------------------------------------------------------------------------------------

-- Seconds between two lines to the group, several quests finishing together do not flood the channel.
QR.GAP = 1

-- Chat type for the group: facts { group, instance, raid } as booleans. Nil when solo.
function QR.Channel(facts)
  if type(facts) ~= "table" or facts.group ~= true then
    return nil
  end
  if facts.instance == true then
    return "INSTANCE_CHAT"
  end
  return facts.raid == true and "RAID" or "PARTY"
end

-- The quest as shown in the group line: the client link when it is a real quest link, else the bracketed
-- title (the number for a quest without a readable name).
function QR.Reference(link, entry)
  if type(link) == "string" and link:find("|Hquest:", 1, true) then
    return link
  end
  return "[" .. QR.Name(entry) .. "]"
end

-- Line head -----------------------------------------------------------------------------------------------

-- Chat cannot carry textures, only raid marks. The raid marks are the choices "rt1".."rt8".
QR.MARKS = { "rt1", "rt2", "rt3", "rt4", "rt5", "rt6", "rt7", "rt8" }
-- The logo choice goes out as the diamond mark plus a no-break space (U+00A0). Everybody sees a diamond, a
-- receiver with the add-on swaps exactly this start for the logo (QR.ShowLogo). The no-break space keeps it
-- apart from a plain "{rt3} " that the player picked as an icon.
QR.LOGO_MARK = "{rt3}\194\160"
QR.LOGO_SIZE = 14

-- The stored choice, anything unknown counts as the logo.
function QR.CleanIcon(value)
  if value == "none" then
    return value
  end
  for _, mark in ipairs(QR.MARKS) do
    if value == mark then
      return value
    end
  end
  return "logo"
end

-- Start of a group line: icon, then the addon name when wanted. Everything else of the line follows.
function QR.Head(icon, prefixOn, prefixText)
  icon = QR.CleanIcon(icon)
  local mark = ""
  if icon == "logo" then
    mark = QR.LOGO_MARK
  elseif icon ~= "none" then
    mark = "{" .. icon .. "} "
  end
  return mark .. (prefixOn and prefixText or "")
end

-- The line with its head. A prefix of nil counts as on.
function QR.Decorate(body, icon, prefixOn, prefixText)
  return QR.Head(icon, prefixOn ~= false, prefixText) .. body
end

-- Receiver side: the line with the leading logo mark replaced by `logoMarkup`, nil when the line does not start
-- with exactly that mark. Only the start is touched, a mark further in the text stays as it is.
function QR.ShowLogo(msg, logoMarkup)
  if type(msg) ~= "string" or type(logoMarkup) ~= "string" or logoMarkup == "" then
    return nil
  end
  if msg:sub(1, #QR.LOGO_MARK) ~= QR.LOGO_MARK or #msg > 255 then
    return nil
  end
  return logoMarkup .. " " .. msg:sub(#QR.LOGO_MARK + 1)
end

-- Waiting lines to the group. Push takes each quest once per session, PushKeyed holds one line per key
-- (a newer line replaces the waiting one). Lines leave at least GAP apart.
function QR.NewQueue()
  local queue = { items = {}, seen = {}, last = nil }

  -- False when the quest was queued before.
  function queue.Push(id, text)
    if queue.seen[id] then
      return false
    end
    queue.seen[id] = true
    queue.items[#queue.items + 1] = { text = text }
    return true
  end

  function queue.PushKeyed(key, text)
    for _, item in ipairs(queue.items) do
      if item.key == key then
        item.text = text
        return
      end
    end
    queue.items[#queue.items + 1] = { key = key, text = text }
  end

  function queue.Clear()
    queue.items = {}
  end

  function queue.Size()
    return #queue.items
  end

  -- The next line when the gap has passed, else nil and the seconds to wait.
  function queue.Pop(now)
    if #queue.items == 0 then
      return nil, 0
    end
    if queue.last and now - queue.last < QR.GAP then
      return nil, QR.GAP - (now - queue.last)
    end
    queue.last = now
    return table.remove(queue.items, 1).text, 0
  end

  return queue
end

-- Quest progress ------------------------------------------------------------------------------------------

-- Seconds an objective count rests before its line is sent, kill quests change every few seconds and only
-- the newest count of the window counts.
QR.COALESCE = 3

-- known: { [questId] = { [index] = fulfilled } } of the last reading, nil before the first one. entries:
-- { id, title, objectives } with objectives = { { text, have, need, finished } } or nil when unreadable. Returns
-- the new memory and the objectives whose count went up since the last reading (each with id and index).
-- The first reading, quests new to the log, counts going down and unreadable answers never report.
function QR.DiffProgress(known, entries)
  local fresh, up = {}, {}
  for _, entry in ipairs(entries) do
    local id = entry.id
    if type(id) == "number" and id > 0 and fresh[id] == nil then
      local old = known and known[id]
      local counts = {}
      if type(entry.objectives) == "table" then
        for index, objective in ipairs(entry.objectives) do
          local have = objective.have
          if type(have) ~= "number" and type(objective.finished) == "boolean" then
            have = objective.finished and 1 or 0
          end
          if type(have) == "number" then
            counts[index] = have
            if old and type(old[index]) == "number" and have > old[index] then
              up[#up + 1] = { id = id, title = entry.title, index = index, objective = objective }
            end
          else
            counts[index] = old and old[index] or nil
          end
        end
      else
        counts = old or {}
      end
      fresh[id] = counts
    end
  end
  return fresh, up
end

-- The objective part of the line. The client text mostly carries "3/10" already, then it stays as it is.
-- Objectives without a count (need of 1 or none) end in the done word.
function QR.ObjectiveText(objective, doneWord)
  local name = type(objective.text) == "string" and objective.text or ""
  local need = objective.need
  if type(need) ~= "number" or need <= 1 then
    return name == "" and doneWord or (name .. " " .. doneWord)
  end
  if name:find("%d+%s*/%s*%d+") then
    return name
  end
  local count = tostring(objective.have) .. "/" .. tostring(need)
  return name == "" and count or (name .. " " .. count)
end

-- template takes the objective text first, then the quest reference.
function QR.ProgressLine(template, reference, objective, doneWord)
  return (string.format(template, QR.ObjectiveText(objective, doneWord), reference))
end

-- Objective lines resting for COALESCE seconds. A newer line of the same key replaces the resting one and
-- keeps its due time, so a steady stream still sends about one line per window.
function QR.NewCoalescer()
  local box = { items = {}, order = {} }

  function box.Push(key, text, now)
    local item = box.items[key]
    if item then
      item.text = text
      return
    end
    box.items[key] = { text = text, due = now + QR.COALESCE }
    box.order[#box.order + 1] = key
  end

  -- Lines that are due, as { key, text } in the order they arrived.
  function box.Take(now)
    local out, rest = {}, {}
    for _, key in ipairs(box.order) do
      local item = box.items[key]
      if item.due <= now then
        out[#out + 1] = { key = key, text = item.text }
        box.items[key] = nil
      else
        rest[#rest + 1] = key
      end
    end
    box.order = rest
    return out
  end

  function box.Size()
    return #box.order
  end

  function box.Clear()
    box.items, box.order = {}, {}
  end

  return box
end
