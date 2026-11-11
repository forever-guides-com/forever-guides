-- Pure rules of the "quest ready" chat line (Modules/QuestReady.lua): which quests of the log just
-- became ready to hand in, and the text of the line. No game calls.
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
