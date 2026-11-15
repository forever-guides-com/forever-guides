-- Pure part of the skill order at the game's talent window (Modules/TalentFrameOrder.lua): which steps of the
-- active build are already learned (or staged), which one is due next, and the step numbers per talent node.
-- No game calls: the purchased ranks come in as { [nodeID] = ranks } (TalentApply.readNodeRanks).
local _, ns = ...
local TO = ns.TalentOrder

local F = {}
ns.TalentFrameOrderLogic = F

-- Rows of the order: { index, sid, rank, talent, level, done, next }. A step is done when the node holds at
-- least its rank. The next step is the first open step of a talent the data knows; without readable ranks
-- (nil) nothing is done and no step is next. Returns the rows and the index of the next step (nil: none).
function F.Rows(specs, order, nodeRanks)
  local rows, nextIndex = {}, nil
  for i, step in ipairs(order) do
    local talent = TO.TalentOf(specs, step)
    local have = talent and talent.node and nodeRanks and nodeRanks[talent.node] or 0
    local row = {
      index = i,
      sid = step.sid,
      rank = step.rank,
      talent = talent,
      level = TO.StepLevel(i),
      done = talent ~= nil and have >= step.rank,
      next = false,
    }
    if nodeRanks and talent and not row.done and not nextIndex then
      nextIndex, row.next = i, true
    end
    rows[i] = row
  end
  return rows, nextIndex
end

-- { [nodeID] = entry } for every talent that has a node id. entry: first (index of the first step), steps (all
-- step indexes), done (per step: learned), next (index of the next open step, nil when all are learned) and more
-- (true when steps follow after next).
function F.Numbers(rows)
  local out = {}
  for _, row in ipairs(rows) do
    local node = row.talent and row.talent.node
    if node then
      local entry = out[node]
      if not entry then
        entry = { first = row.index, steps = {}, done = {}, more = false }
        out[node] = entry
      end
      local n = #entry.steps + 1
      entry.steps[n] = row.index
      entry.done[n] = row.done == true
      if entry.next then
        entry.more = true
      elseif not row.done then
        entry.next = row.index
      end
    end
  end
  return out
end

-- The text on the talent: the next open step, with "+" when more ranks follow; nil for a learned talent.
function F.MarkText(entry)
  if not entry.next then
    return nil
  end
  return tostring(entry.next) .. (entry.more and "+" or "")
end

-- The ready check mark of the game: the client fonts have no check glyph.
F.DONE_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

-- The step numbers as text "3, 7, 12"; learned steps carry the check mark.
function F.StepsText(entry)
  local parts = {}
  for i, n in ipairs(entry.steps) do
    parts[i] = tostring(n) .. (entry.done and entry.done[i] and (" " .. F.DONE_MARK) or "")
  end
  return table.concat(parts, ", ")
end

-- The rows the list shows and the position of each step in it ({ [stepIndex] = position }): without the
-- learned steps when hideDone is set.
function F.Visible(rows, hideDone)
  local list, pos = {}, {}
  for _, row in ipairs(rows) do
    if not (hideDone and row.done) then
      list[#list + 1] = row
      pos[row.index] = #list
    end
  end
  return list, pos
end

-- Text for the collapsed bar: one capital letter per line, a space becomes an empty line. The client cannot
-- rotate a font string, stacked letters read top to bottom.
function F.Vertical(text)
  local out = {}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch == " " and "" or ch:upper()
  end
  return table.concat(out, "\n")
end

-- Counts of the rows: done steps and all steps.
function F.Progress(rows)
  local done = 0
  for _, row in ipairs(rows) do
    if row.done then
      done = done + 1
    end
  end
  return done, #rows
end
