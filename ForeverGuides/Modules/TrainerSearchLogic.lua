-- Search of the trainer pages, pure side (no frames, no game calls): the words of a query, the
-- name folding (case, accents, apostrophes) and the filter that every word has to pass. The pages
-- are Modules/ProfessionTrainersPage.lua (profession trainers) and Modules/TrainersPage.lua (class trainers).
local _, ns = ...

local S = {}
ns.TrainerSearchLogic = S

-- Names ------------------------------------------------------------------------------------------

-- Second UTF-8 byte (after \195) of a Latin letter with an accent -> the plain letter.
local ACCENT = {}
for b = 160, 165 do
  ACCENT[b] = "a"
end
ACCENT[167] = "c"
for b = 168, 171 do
  ACCENT[b] = "e"
end
for b = 172, 175 do
  ACCENT[b] = "i"
end
ACCENT[177] = "n"
for b = 178, 182 do
  ACCENT[b] = "o"
end
for b = 185, 188 do
  ACCENT[b] = "u"
end
ACCENT[189], ACCENT[191] = "y", "y"

local function foldAccent(second)
  local b = second:byte()
  if b == 159 then
    return ""
  end
  return ACCENT[b < 160 and b + 32 or b] or ""
end

-- Lower case, no accents, no apostrophes or punctuation, single spaces ("Tel'Athir" = "TEL’ATHIR").
function S.NormalizeName(text)
  text = tostring(text or ""):gsub("\226\128\153", ""):gsub("\195([\128-\191])", foldAccent)
  text = text:lower():gsub("'", ""):gsub("[^a-z0-9 ]", "")
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Text as the search compares it: the sharp s becomes "ss" first (the normal form would drop it), then
-- the normal form of the names.
function S.Fold(text)
  local search = ns.SearchLogic
  return S.NormalizeName(search and search.fold(text) or text)
end

-- Query -------------------------------------------------------------------------------------------

-- True when the query holds at least one word.
function S.HasQuery(query)
  return tostring(query or ""):find("%S") ~= nil
end

-- The blank separated words of a query.
function S.Words(query)
  local words = {}
  for word in tostring(query or ""):gmatch("%S+") do
    words[#words + 1] = word
  end
  return words
end

local function plainMatch(text, word)
  return text:lower():find(word:lower(), 1, true) ~= nil
end

-- Folded containment: case, accents and apostrophes do not matter. A word that folds to nothing ("?") matches.
function S.Match(text, word)
  return S.Fold(text):find(S.Fold(word), 1, true) ~= nil
end

-- True when every word occurs in the text. match(text, word) defaults to a plain, case-insensitive test.
function S.MatchAll(text, words, match)
  match = match or plainMatch
  for _, word in ipairs(words) do
    if not match(text, word) then
      return false
    end
  end
  return true
end

-- Class trainers -----------------------------------------------------------------------------------

local function names(value, out)
  if type(value) == "table" then
    out[#out + 1] = value.de
    out[#out + 1] = value.en
  elseif type(value) == "string" then
    out[#out + 1] = value
  end
end

-- What a class trainer is searched by: the name and the place name (German and English), the zone
-- names (zones[t.z] = { de, en }, nil without the data).
function S.TrainerText(t, zones)
  local parts = {}
  names(t.n, parts)
  names(t.p, parts)
  names(type(zones) == "table" and zones[t.z] or nil, parts)
  return table.concat(parts, " ")
end

-- The trainers (list of class trainer tables) that match the query, in their order. An empty query
-- keeps all.
function S.FilterTrainers(trainers, query, zones)
  local words = S.Words(query)
  if #words == 0 then
    return trainers
  end
  local out = {}
  for _, t in ipairs(trainers) do
    if S.MatchAll(S.TrainerText(t, zones), words, S.Match) then
      out[#out + 1] = t
    end
  end
  return out
end
