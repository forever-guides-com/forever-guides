-- Own professions, pure data side (no frames, no game calls). The three sources the client may
-- offer arrive as plain rows and become one shape:
--   { name, skill, max, id (skill line id or nil), kind = "primary" | "secondary" }
-- Capture reads the game (Professions.lua), the character overview shows the result (RosterView.lua).
local _, ns = ...

local P = {}
ns.ProfessionLogic = P

P.MAX = 8
P.PRIMARY_SHOWN = 2
P.FORMS = { "full", "short", "skill" }

local LIMIT = 1000
local SHORT_NAME = 8
local DAY = 86400

-- Names of the professions in both languages; the skill list of the older clients has no flag for them.
local KNOWN = {}
for _, name in ipairs({
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Inscription",
  "Jewelcrafting",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
  "Alchemie",
  "Schmiedekunst",
  "Verzauberkunst",
  "Ingenieurskunst",
  "Kräuterkunde",
  "Inschriftenkunde",
  "Juwelenschleifen",
  "Lederverarbeitung",
  "Bergbau",
  "Kürschnerei",
  "Schneiderei",
}) do
  KNOWN[name] = "primary"
end
for _, name in ipairs({
  "Cooking",
  "Fishing",
  "First Aid",
  "Archaeology",
  "Kochkunst",
  "Angeln",
  "Erste Hilfe",
  "Archäologie",
}) do
  KNOWN[name] = "secondary"
end

-- Header texts of the skill list that hold professions.
local HEADERS = {
  Professions = "primary",
  Berufe = "primary",
  ["Secondary Skills"] = "secondary",
  Nebenberufe = "secondary",
}

function P.KnownKind(name)
  return KNOWN[name]
end

local function whole(v)
  if type(v) ~= "number" or v ~= v or v < 0 or v > LIMIT then
    return 0
  end
  return math.floor(v)
end

local function make(name, skill, max, id, kind)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return {
    name = name:sub(1, 40),
    skill = whole(skill),
    max = whole(max),
    id = type(id) == "number" and id >= 1 and id <= 1e8 and math.floor(id) or nil,
    kind = kind == "secondary" and "secondary" or "primary",
  }
end

local function byOrder(a, b)
  if a.kind ~= b.kind then
    return a.kind == "primary"
  end
  local an, bn = a.name:lower(), b.name:lower()
  if an ~= bn then
    return an < bn
  end
  return a.skill > b.skill
end

-- A sorted copy: primary professions first, then by name.
function P.Sort(list)
  local out = {}
  for _, p in ipairs(type(list) == "table" and list or {}) do
    if type(p) == "table" and type(p.name) == "string" then
      out[#out + 1] = p
    end
  end
  table.sort(out, byOrder)
  return out
end

-- Sorted, without duplicates by name, at most MAX; nil when nothing is left.
local function finish(list)
  local seen, out = {}, {}
  for _, p in ipairs(P.Sort(list)) do
    if not seen[p.name] and #out < P.MAX then
      seen[p.name] = true
      out[#out + 1] = p
    end
  end
  return #out > 0 and out or nil
end

-- Source 1, GetProfessions + GetProfessionInfo. rows: { slot, name, skill, max, skillLine }, slots 1 and
-- 2 are the primary professions, the others the secondary ones.
function P.FromProfessions(rows)
  local out = {}
  for _, r in ipairs(type(rows) == "table" and rows or {}) do
    if type(r) == "table" then
      out[#out + 1] = make(r.name, r.skill, r.max, r.id, (tonumber(r.slot) or 1) <= 2 and "primary" or "secondary")
    end
  end
  return finish(out)
end

-- Source 2, GetNumSkillLines + GetSkillLineInfo. lines: { name, header (bool), skill, max } in list
-- order; the rows below a professions header count, so do rows with a known profession name.
-- extraPrimary and extraSecondary: header texts of the client (global strings) on top of the built-in ones.
function P.FromSkillLines(lines, extraPrimary, extraSecondary)
  local headers = {}
  for k, v in pairs(HEADERS) do
    headers[k] = v
  end
  for _, h in ipairs(type(extraPrimary) == "table" and extraPrimary or {}) do
    headers[h] = "primary"
  end
  for _, h in ipairs(type(extraSecondary) == "table" and extraSecondary or {}) do
    headers[h] = "secondary"
  end
  local out, section = {}, nil
  for _, l in ipairs(type(lines) == "table" and lines or {}) do
    if type(l) == "table" and type(l.name) == "string" then
      if l.header then
        section = headers[l.name]
      else
        local kind = KNOWN[l.name] or section
        if kind and (whole(l.skill) > 0 or whole(l.max) > 0) then
          out[#out + 1] = make(l.name, l.skill, l.max, nil, kind)
        end
      end
    end
  end
  return finish(out)
end

-- Source 3, C_TradeSkillUI. rows: { id, name, skill, max, parent } one per skill line. Expansion
-- lines of one profession fold into the line with the highest maximum, under the parent's name.
function P.FromTradeSkills(rows)
  local best, order = {}, {}
  for _, r in ipairs(type(rows) == "table" and rows or {}) do
    if type(r) == "table" then
      local name = type(r.parent) == "string" and r.parent ~= "" and r.parent or r.name
      if type(name) == "string" and name ~= "" and whole(r.max) > 0 then
        local old = best[name]
        if not old then
          order[#order + 1] = name
        end
        if not old or whole(r.max) > whole(old.max) then
          best[name] = r
        end
      end
    end
  end
  local out = {}
  for _, name in ipairs(order) do
    local r = best[name]
    out[#out + 1] = make(name, r.skill, r.max, r.id, KNOWN[name] or "primary")
  end
  return finish(out)
end

-- Display ---------------------------------------------------------------------------------

-- The professions a cell shows: up to PRIMARY_SHOWN primary ones, the secondary ones on request.
function P.Shown(list, withSecondary)
  local out, primary = {}, 0
  for _, p in ipairs(P.Sort(list)) do
    if p.kind == "secondary" then
      if withSecondary then
        out[#out + 1] = p
      end
    elseif primary < P.PRIMARY_SHOWN then
      primary = primary + 1
      out[#out + 1] = p
    end
  end
  return out
end

local function cutName(name, max)
  local chars = {}
  for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = ch
  end
  if #chars <= max then
    return name
  end
  return table.concat(chars, "", 1, max) .. "."
end

local function skillText(p)
  return p.max > 0 and (p.skill .. "/" .. p.max) or tostring(p.skill)
end

-- "full": "Blacksmithing 74/150", "short": the name cut ("Blacksmi. 74/150"), "skill": "74/150".
function P.Text(p, form)
  if form == "skill" then
    return skillText(p)
  elseif form == "short" then
    return cutName(p.name, SHORT_NAME) .. " " .. skillText(p)
  end
  return p.name .. " " .. skillText(p)
end

function P.IsFull(p)
  return p.max > 0 and p.skill >= p.max
end

-- Theme token of a profession's text: full skill is green, else nil (the default color).
function P.Tone(p)
  return P.IsFull(p) and "success" or nil
end

-- Whole days since the reading, nil without a time.
function P.AgeDays(at, now)
  if type(at) ~= "number" or at <= 0 or type(now) ~= "number" then
    return nil
  end
  return math.max(0, math.floor((now - at) / DAY))
end
