-- Suggestions for main and alt links, no game calls. Read-only: nothing here links anyone. A suggestion is
-- a hint { key, name, mainKey, mainName, score, confidence, reasons } the player confirms with a click or
-- discards (the discard is remembered in guild.altSkip[pair] = day).
--
-- Signals (a suggestion needs at least one, a name that is not a known member never counts):
--   * a note (guild note, officer note when readable, own note) that names another member in a common
--     pattern: "Alt von X", "Alt of X", "Twink von X", "Twink X", "Main: X", "X's alt", "(X)"
--   * two members with the same note text (weak, the direction is a guess: the better rank is the main)
-- Not used: "Alt: X" (the note of a main may list its alts that way, so the direction is open) and online
-- times. The roster only gives the time since the last visit, which is too coarse to tell one player's
-- characters from two players who play in the same evening hours.
local _, gm = ...
if not gm.ext then
  return
end
local PN = gm.FG.PlayerName
local ML = gm.MembersLogic

local AS = {}
gm.AltSuggest = AS

AS.MAX_SUGGESTIONS = 100
AS.MAX_DISMISSED = 500
-- Same note text counts only from this length on and only when exactly two members carry it.
AS.MIN_SAME_NOTE = 10
AS.HIGH, AS.MEDIUM = 85, 50

-- Note patterns on the lower case text: the pattern ends with an empty capture at the first letter of the
-- name. score: how sure the pattern is, code: locale key gm.alt.reason.<code>.
local PATTERNS = {
  { "%f[%a]alt%s+von%s+()", 90, "altOf" },
  { "%f[%a]alt%s+of%s+()", 90, "altOf" },
  { "%f[%a]twink%s+von%s+()", 90, "altOf" },
  { "%f[%a]twink%s+of%s+()", 90, "altOf" },
  { "%f[%a]twink%s+()", 75, "altOf" },
  { "%f[%a]zweitchar%s+von%s+()", 85, "altOf" },
  { "%f[%a]main%s+von%s+()", 85, "mainIs" },
  { "%f[%a]main%s+of%s+()", 85, "mainIs" },
  { "%f[%a]main%s*:%s*()", 85, "mainIs" },
  { "%(()", 55, "paren" },
}
-- "Xandor's alt": the name stands in front.
local POSSESSIVE = { "()[%w\128-\255]+'s%s+alts?%f[%A]", "()[%w\128-\255]+'s%s+twinks?%f[%A]" }

local SOURCES = { "public", "officer", "own" }

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v == math.floor(v) and v or nil
end

-- Up to two words starting at pos of the original text, longest first: "Anna Berg", "Anna".
local function words(text, pos)
  local first = text:match("^[%w\128-\255]+", pos)
  if not first then
    return {}
  end
  local out = {}
  local second = text:match("^%s+([%w\128-\255]+)", pos + #first)
  if second then
    out[1] = first .. " " .. second
  end
  out[#out + 1] = first
  return out
end

-- Every { list = name candidates, score, code } of one note, in pattern order.
local function mentions(text)
  local found = {}
  if type(text) ~= "string" or text == "" then
    return found
  end
  local lo = text:lower()
  for _, p in ipairs(PATTERNS) do
    local from = 1
    while true do
      local pos = lo:match(p[1], from)
      if not pos then
        break
      end
      local list = words(text, pos)
      if p[3] == "paren" then
        -- A bracket counts only around exactly one name: "(Xandor)".
        local closed = {}
        for _, w in ipairs(list) do
          if text:match("^%s*%)", pos + #w) then
            closed[#closed + 1] = w
          end
        end
        list = closed
      end
      if #list > 0 then
        found[#found + 1] = { list = list, score = p[2], code = p[3] }
      end
      from = pos + 1
    end
  end
  for _, pat in ipairs(POSSESSIVE) do
    for pos in lo:gmatch(pat) do
      local w = text:match("^[%w\128-\255]+", pos)
      if w then
        found[#found + 1] = { list = { w }, score = 90, code = "possessive" }
      end
    end
  end
  return found
end
AS.Mentions = mentions

-- The key pair of a suggestion in the dismissed set.
function AS.PairKey(altKey, mainKey)
  return altKey .. ">" .. mainKey
end

local function rootOf(store, key)
  local e = store[key]
  return e and e.mainKey ~= "" and e.mainKey or key
end

local function hasAlts(store, key)
  for k, e in pairs(store) do
    if k ~= key and e.mainKey == key then
      return true
    end
  end
  return false
end

-- Whether alt may become an alt of main: the links stay flat (see MembersLogic.SetMain).
local function linkable(store, altKey, mainKey)
  if altKey == mainKey or rootOf(store, altKey) == rootOf(store, mainKey) then
    return false
  end
  local a = store[altKey]
  if a and a.mainKey ~= "" then
    return false
  end
  return not hasAlts(store, altKey)
end

local function better(a, b)
  if a.rank ~= b.rank and a.rank and b.rank then
    return a.rank < b.rank
  end
  return a.key < b.key
end

local function confidence(score)
  return score >= AS.HIGH and "high" or score >= AS.MEDIUM and "medium" or "low"
end

-- input = { store = guild.members, rows = roster members { key, name, rank, note, officerNote },
-- dismissed = guild.altSkip, officerNote = true when the officer notes may be used }.
-- Answers a list sorted by score (best first), then name. Never raises on damaged input.
function AS.Find(input)
  local store = type(input.store) == "table" and input.store or {}
  local dismissed = type(input.dismissed) == "table" and input.dismissed or {}
  local people, byKey = {}, {}
  local function person(key, name)
    local p = byKey[key]
    if not p then
      p = { key = key, name = name, texts = {} }
      byKey[key] = p
      people[#people + 1] = p
    end
    return p
  end
  for key, e in pairs(store) do
    if type(key) == "string" and type(e) == "table" then
      person(key, type(e.name) == "string" and e.name or key).texts.own = e.note
    end
  end
  for _, row in ipairs(type(input.rows) == "table" and input.rows or {}) do
    if type(row) == "table" and type(row.key) == "string" then
      local p = person(row.key, type(row.name) == "string" and row.name or row.key)
      p.name, p.rank = type(row.name) == "string" and row.name or p.name, row.rank
      p.texts.public = row.note
      p.texts.officer = input.officerNote == true and row.officerNote or nil
    end
  end
  table.sort(people, function(a, b)
    return a.key < b.key
  end)

  local best = {}
  local function offer(alt, main, score, reason)
    local root = byKey[rootOf(store, main.key)]
    if not root or not linkable(store, alt.key, root.key) or dismissed[AS.PairKey(alt.key, root.key)] then
      return
    end
    local id = AS.PairKey(alt.key, root.key)
    local s = best[id]
    if not s then
      s = { key = alt.key, name = alt.name, mainKey = root.key, mainName = root.name, score = 0, reasons = {} }
      best[id] = s
    end
    s.reasons[#s.reasons + 1] = reason
    -- A second, independent signal lifts the score a little, never above 100.
    s.score = #s.reasons == 1 and score or math.min(100, math.max(s.score, score) + 10)
  end

  for _, p in ipairs(people) do
    for _, source in ipairs(SOURCES) do
      for _, m in ipairs(mentions(p.texts[source])) do
        for _, candidate in ipairs(m.list) do
          local other = byKey[PN.Key(candidate)]
          if other then
            if other.key ~= p.key then
              offer(p, other, m.score, { code = m.code, source = source, name = other.name })
            end
            break
          end
        end
      end
    end
  end

  -- The same note text on exactly two members.
  local same = {}
  for _, p in ipairs(people) do
    for _, source in ipairs({ "public", "own" }) do
      local text = type(p.texts[source]) == "string" and p.texts[source]:lower():match("^%s*(.-)%s*$") or ""
      if #text >= AS.MIN_SAME_NOTE and text:find("%a") then
        same[text] = same[text] or {}
        table.insert(same[text], p)
      end
    end
  end
  local texts = {}
  for text in pairs(same) do
    texts[#texts + 1] = text
  end
  table.sort(texts)
  for _, text in ipairs(texts) do
    local pair = same[text]
    if #pair == 2 and pair[1].key ~= pair[2].key then
      local main, alt = pair[1], pair[2]
      if not better(main, alt) then
        main, alt = alt, main
      end
      if not linkable(store, alt.key, rootOf(store, main.key)) then
        main, alt = alt, main
      end
      offer(alt, main, 40, { code = "sameNote", source = "public", name = main.name })
    end
  end

  -- Two notes that name each other: one suggestion, the surer or the smaller key.
  local out = {}
  for id, s in pairs(best) do
    local back = best[AS.PairKey(s.mainKey, s.key)]
    if not back or s.score > back.score or (s.score == back.score and id < AS.PairKey(back.key, back.mainKey)) then
      s.confidence = confidence(s.score)
      out[#out + 1] = s
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.name ~= b.name then
      return PN.Lower(a.name) < PN.Lower(b.name)
    end
    return a.mainKey < b.mainKey
  end)
  for i = #out, AS.MAX_SUGGESTIONS + 1, -1 do
    out[i] = nil
  end
  return out
end

-- "Verknüpfen": links the alt to its main in the store. Answers true, or false and the reason of
-- MembersLogic.SetMain ("hasAlts", "mainIsAlt") or "changed" when the situation moved since the list was made.
function AS.Link(store, suggestion)
  if not linkable(store, suggestion.key, suggestion.mainKey) then
    return false, "changed"
  end
  return ML.SetMain(store, { key = suggestion.key, name = suggestion.name }, suggestion.mainName)
end

-- "Verwerfen": remembers the pair so it does not come back. today: day number (the oldest pair goes when the
-- set is full).
function AS.Dismiss(dismissed, suggestion, today)
  local id = AS.PairKey(suggestion.key, suggestion.mainKey)
  if dismissed[id] == nil then
    local n, oldest = 0, nil
    for k, day in pairs(dismissed) do
      n = n + 1
      if not oldest or day < dismissed[oldest] or (day == dismissed[oldest] and k < oldest) then
        oldest = k
      end
    end
    if n >= AS.MAX_DISMISSED then
      dismissed[oldest] = nil
    end
  end
  dismissed[id] = whole(today) or 0
end

-- Repairs guild.altSkip in place: only "<alt>><main>" strings with a day number stay.
function AS.Clean(guild)
  local clean, n = {}, 0
  if type(guild.altSkip) == "table" then
    for k, day in pairs(guild.altSkip) do
      if type(k) == "string" and #k <= 200 and k:find(">", 1, true) and whole(day) and n < AS.MAX_DISMISSED then
        clean[k], n = day, n + 1
      end
    end
  end
  guild.altSkip = clean
end

local clean = gm.CleanGuild
if clean then
  function gm.CleanGuild(guild)
    clean(guild)
    AS.Clean(guild)
  end
end
