-- Pure side of the list "Crafters in the guild" (CraftersView.lua): the state of the window, the order of
-- the members, the texts of a row, the ready-made chat lines and the keyboard cursor. Also the index from
-- an item to the recipes that make it (for the item tooltip and the shopping list). No frames, no game
-- calls, nothing here sends a message.
local _, ns = ...
local PN = ns.PlayerName

local CV = {}
ns.CraftersViewLogic = CV

-- A member whose data is older than this many seconds is shown dimmed as "old".
CV.OLD_SECONDS = 7 * 86400
-- The text of a chat line must fit the chat edit box.
CV.MAX_TEXT = 250
-- Rows from which the list scrolls (the window grows up to this many rows, then a scroll bar takes over).
CV.PAGE = 6

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- States ---------------------------------------------------------------------------------------------------

-- "off" (receiving is off), "noGuild", "hits" (at least one crafter), "asking" (the question is open and
-- nobody answered yet), "nobody" (no member shares: coverage 0), "none" (members share, none knows it).
-- c: receiving, inGuild, count, info (CraftDirectory.Crafters second value).
function CV.State(c)
  if not c.receiving then
    return "off"
  end
  if not c.inGuild then
    return "noGuild"
  end
  if (c.count or 0) > 0 then
    return "hits"
  end
  local info = c.info or {}
  if info.asking then
    return "asking"
  end
  if (info.sharing or 0) == 0 then
    return "nobody"
  end
  return "none"
end

-- "12 of 87 members share their recipes"; without a loaded guild list only the shared part is known.
function CV.CoverageText(info, L)
  info = info or {}
  local sharing, total = info.sharing or 0, info.total or 0
  if total > 0 then
    return string.format(L["cv.coverage"], sharing, total)
  end
  return string.format(L["cv.coverageShort"], sharing)
end

-- Order ----------------------------------------------------------------------------------------------------

local function rank(entry)
  if entry.online == true then
    return 0
  end
  return entry.online == nil and 1 or 2
end

local function before(a, b)
  local ra, rb = rank(a), rank(b)
  if ra ~= rb then
    return ra < rb
  end
  local sa, sb = a.skill or 0, b.skill or 0
  if sa ~= sb then
    return sa > sb
  end
  local na, nb = PN.Lower(tostring(a.name)), PN.Lower(tostring(b.name))
  if na ~= nb then
    return na < nb
  end
  return tostring(a.key) < tostring(b.key)
end

-- A new list: online first, then unknown, then offline; each by skill (high first), then by name.
function CV.Sort(list)
  local out = {}
  for _, entry in ipairs(list or {}) do
    if type(entry) == "table" and type(entry.name) == "string" then
      out[#out + 1] = entry
    end
  end
  table.sort(out, before)
  return out
end

-- Texts -----------------------------------------------------------------------------------------------------

-- "12 s", "5 min", "3 h", "2 d" ago, as a text of the locale; nil for a time in the future or no number.
function CV.Age(seconds, L)
  if not finite(seconds) or seconds < 0 then
    return nil
  end
  if seconds < 60 then
    return string.format(L["cv.age.s"], math.floor(seconds))
  elseif seconds < 3600 then
    return string.format(L["cv.age.min"], math.floor(seconds / 60))
  elseif seconds < 86400 then
    return string.format(L["cv.age.h"], math.floor(seconds / 3600))
  end
  return string.format(L["cv.age.d"], math.floor(seconds / 86400))
end

-- The texts of one row of the list. entry: an item of CraftDirectory.Crafters; env: now (epoch seconds),
-- jobName(slug), zone is already in the entry. Names are never cut: "First Last" stays whole.
function CV.Row(entry, now, L, env)
  local zone = type(entry.zone) == "string" and entry.zone or ""
  local status, kind
  if entry.online == true then
    kind = "online"
    status = zone ~= "" and string.format(L["cv.online.zone"], zone) or L["cv.online"]
  elseif entry.online == false then
    kind = "offline"
    local ago = finite(entry.agoMin) and CV.Age(entry.agoMin * 60, L)
    status = ago and string.format(L["cv.offline.ago"], ago) or L["cv.offline"]
  else
    kind = "unknown"
    status = L["cv.unknownStatus"]
  end
  local age = finite(entry.seen) and CV.Age(now - entry.seen, L) or nil
  local source
  if entry.source == "live" then
    source = age and string.format(L["cv.source.live"], age) or L["cv.source.liveNow"]
  else
    source = age and string.format(L["cv.source.cache"], age) or L["cv.source.cacheNow"]
  end
  local old = entry.stale == true or (finite(entry.seen) and now - entry.seen > CV.OLD_SECONDS)
  if entry.stale then
    source = source .. " " .. L["cv.stale"]
  end
  local skill = (finite(entry.skill) and finite(entry.max) and entry.max > 0)
      and string.format("%d/%d", entry.skill, entry.max)
    or tostring(entry.skill or "")
  local job = env and env.jobName and env.jobName(entry.slug) or entry.slug or ""
  return {
    key = entry.key,
    name = entry.name,
    job = job,
    skill = skill,
    head = job ~= "" and (job .. " " .. skill) or skill,
    status = status,
    statusKind = kind,
    source = source,
    old = old == true,
    stale = entry.stale == true,
  }
end

-- Chat lines ------------------------------------------------------------------------------------------------

local function plainText(s)
  return (tostring(s or ""):gsub("[\r\n]", " "))
end

-- The text of the whisper and of the guild line. `what` is the link (or the name) of the recipe.
function CV.WhisperText(what, L)
  return string.format(L["cv.tpl.whisper"], plainText(what))
end

function CV.GuildText(what, L)
  return string.format(L["cv.tpl.guild"], plainText(what))
end

-- The text for the chat edit box: "/w First Last text" or "/g text" (the chat command picks the channel).
-- Returns nil for an empty name or an empty or too long text, so nothing half-finished is prepared.
function CV.ChatLine(kind, name, text)
  if type(text) ~= "string" or text == "" or #text > CV.MAX_TEXT then
    return nil
  end
  if kind == "guild" then
    return "/g " .. text
  end
  name = PN.Clean(name)
  if name == "" then
    return nil
  end
  return "/w " .. name .. " " .. text
end

-- Reasons CraftDirectory.Ask gives (key suffix of "cv.why.*"); an unknown one falls back to "other".
local WHY = {
  consent = true,
  guild = true,
  spell = true,
  unregistered = true,
  combat = true,
  pending = true,
  cached = true,
  throttle = true,
}

function CV.WhyKey(reason)
  return "cv.why." .. (WHY[reason] and reason or "other")
end

-- Keyboard cursor ---------------------------------------------------------------------------------------------

-- shape[r] is the number of controls in row r (row 0 is the tool bar). Returns the cell of a key from
-- (row, col) or nil when the key moves nothing. Up and down skip rows without controls.
function CV.Navigate(shape, row, col, key)
  local last = #shape
  local function clamp(r, c)
    return r, math.max(1, math.min(c, shape[r]))
  end
  local function step(delta)
    local r = row + delta
    while r >= 0 and r <= last do
      if (shape[r] or 0) > 0 then
        return clamp(r, col)
      end
      r = r + delta
    end
  end
  if key == "DOWN" then
    return step(1)
  elseif key == "UP" then
    return step(-1)
  elseif key == "LEFT" then
    if col > 1 then
      return row, col - 1
    end
  elseif key == "RIGHT" then
    if col < (shape[row] or 0) then
      return row, col + 1
    end
  elseif key == "HOME" then
    for r = 0, last do
      if (shape[r] or 0) > 0 then
        return r, 1
      end
    end
  elseif key == "END" then
    for r = last, 0, -1 do
      if (shape[r] or 0) > 0 then
        return r, shape[r]
      end
    end
  end
  return nil
end

-- Tab order: every control in reading order, wrapping around. delta is 1 or -1.
function CV.Next(shape, row, col, delta)
  local flat, at = {}, 0
  for r = 0, #shape do
    for c = 1, shape[r] or 0 do
      flat[#flat + 1] = { r, c }
      if r == row and c == col then
        at = #flat
      end
    end
  end
  if #flat == 0 then
    return nil
  end
  at = at == 0 and (delta > 0 and 1 or #flat) or ((at - 1 + delta) % #flat) + 1
  return flat[at][1], flat[at][2]
end

-- Item to recipes --------------------------------------------------------------------------------------------

local indexFor, indexSize, index

-- spells[item] = the spell ids of the recipes that make the item, ascending. data is ns.RecipeData
-- (slug -> { list }); rebuilt when the table or the number of its professions changes.
function CV.ItemIndex(data)
  if type(data) ~= "table" then
    return {}
  end
  local size = 0
  for _ in pairs(data) do
    size = size + 1
  end
  if indexFor == data and indexSize == size and index then
    return index
  end
  local out = {}
  for _, entry in pairs(data) do
    for _, r in ipairs(type(entry) == "table" and type(entry.list) == "table" and entry.list or {}) do
      if type(r) == "table" and type(r.s) == "number" and type(r.i) == "number" then
        local list = out[r.i] or {}
        out[r.i] = list
        list[#list + 1] = r.s
      end
    end
  end
  for _, list in pairs(out) do
    table.sort(list)
  end
  indexFor, indexSize, index = data, size, out
  return out
end

-- The recipe of a spell id in the list of one profession, nil when it is not in there.
function CV.FindRecipe(list, spell)
  for _, r in ipairs(list or {}) do
    if type(r) == "table" and r.s == spell then
      return r
    end
  end
end
