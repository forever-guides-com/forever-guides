-- Row and reward model of the instance quest list and its detail pane, without any game API (the frames are
-- Modules/QuestChainView.lua and Modules/InstanceQuestPanel.lua). Quest fields read here: id, n, f, l, dg (server
-- tag 81 dungeon or 62 raid), st ("in" or "out": accepted inside or outside the instance), rw ({ id, n, c, ch }), xp, mo (copper).
local _, ns = ...

local QL = {}
ns.QuestListLogic = QL

QL.OBJECTIVE_LINES, QL.OBJECTIVE_CHARS = 2, 70

-- Base colors of the difficulty buckets (the classic quest log), the view lifts them to AA contrast.
QL.COLORS = {
  red = "#ff4a4a",
  orange = "#ff8040",
  yellow = "#ffd100",
  green = "#40c040",
  grey = "#9a9a9a",
}

-- Level from which a quest turns grey: the green range of the client, else the classic mob gray-level rule
-- (the client rule is not exposed to the addon on every build).
function QL.GreyLevel(player)
  if player <= 5 then
    return 0
  elseif player <= 39 then
    return player - 5 - math.floor(player / 10)
  elseif player <= 59 then
    return player - 1 - math.floor(player / 5)
  end
  return player - 9
end

-- "red", "orange", "yellow", "green" or "grey" for a quest level against the player level, nil without both.
function QL.Difficulty(level, player, grey)
  if type(level) ~= "number" or type(player) ~= "number" then
    return nil
  end
  local diff = level - player
  if diff >= 5 then
    return "red"
  elseif diff >= 3 then
    return "orange"
  elseif diff >= -2 then
    return "yellow"
  end
  return level > (grey or QL.GreyLevel(player)) and "green" or "grey"
end

-- Up to OBJECTIVE_LINES compact lines of an objective text: blank lines dropped, white space collapsed, a long
-- line cut at a word with "...".
function QL.Objectives(text)
  local out = {}
  if type(text) ~= "string" then
    return out
  end
  for line in text:gmatch("[^\r\n]+") do
    line = line:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if line ~= "" then
      if #line > QL.OBJECTIVE_CHARS then
        line = line:sub(1, QL.OBJECTIVE_CHARS):gsub("%s*[^%s]*$", "") .. "..."
      end
      out[#out + 1] = line
      if #out >= QL.OBJECTIVE_LINES then
        break
      end
    end
  end
  return out
end

-- "dungeon" or "raid": the server tag of the quest, else the type of the instance.
function QL.Kind(entry)
  local tag = entry.quest and entry.quest.dg
  if tag == 62 then
    return "raid"
  elseif tag == 81 then
    return "dungeon"
  end
  return entry.inst and entry.inst.t == "raid" and "raid" or "dungeon"
end

-- Rows of the list: the direct quests of the entries (chain links are no rows) that the faction filter keeps
-- ("all", "A" or "H"; a quest of both factions stays), in the order of the entries.
-- opts: player (level), grey (grey level of the client), pre = { [quest id] = number of prequests },
-- text(entry) -> objective text. Each row: { entry, level, bucket, faction ("A", "H" or nil for both), kind,
-- start ("in", "out" or nil), pre, objectives }.
function QL.Rows(entries, filter, opts)
  opts = opts or {}
  local rows = {}
  for _, e in ipairs(entries or {}) do
    if e.direct and (filter == "all" or filter == nil or e.faction == "B" or e.faction == filter) then
      rows[#rows + 1] = {
        entry = e,
        level = e.level,
        bucket = QL.Difficulty(e.level, opts.player, opts.grey),
        faction = e.faction ~= "B" and e.faction or nil,
        kind = QL.Kind(e),
        start = e.quest and (e.quest.st == "in" or e.quest.st == "out") and e.quest.st or nil,
        pre = opts.pre and opts.pre[e.id or 0] or 0,
        objectives = QL.Objectives(opts.text and opts.text(e)),
      }
    end
  end
  return rows
end

-- Reward model of a quest: { choice = tiles, fixed = tiles, xp, money } with tile = { id, name, count, choice }.
-- name(id, stored) gives the client name of an item; the stored English name and "#id" are the fallbacks.
function QL.Rewards(q, name)
  local out = { choice = {}, fixed = {} }
  for _, r in ipairs(type(q.rw) == "table" and q.rw or {}) do
    local label = name and name(r.id, r.n) or nil
    local tile = {
      id = r.id,
      name = (type(label) == "string" and label ~= "") and label or r.n or (r.id and "#" .. r.id) or "?",
      count = type(r.c) == "number" and r.c > 1 and r.c or nil,
      choice = r.ch == true,
    }
    local list = tile.choice and out.choice or out.fixed
    list[#list + 1] = tile
  end
  out.xp = type(q.xp) == "number" and q.xp > 0 and q.xp or nil
  out.money = type(q.mo) == "number" and q.mo > 0 and q.mo or nil
  return out
end

-- True when the model has nothing to show.
function QL.RewardsEmpty(model)
  return #model.choice == 0 and #model.fixed == 0 and not model.xp and not model.money
end

-- The other instances (wings) of the data that list the same quest as a direct quest, in data order.
function QL.OtherInstances(inst, id, instances)
  local out = {}
  if type(id) ~= "number" then
    return out
  end
  for _, other in ipairs(instances or {}) do
    if other ~= inst then
      for _, q in ipairs(other.q or {}) do
        if q.id == id and q.n and q.direct ~= false then
          out[#out + 1] = other
          break
        end
      end
    end
  end
  return out
end
