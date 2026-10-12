-- Global search: scored token match over a cached index (names in both languages, aliases,
-- subtitles). Pure logic, no WoW API. New entry kinds join through S.RegisterSource.
local _, ns = ...

local S = {}
ns.SearchLogic = S

local find, sub, byte, concat = string.find, string.sub, string.byte, table.concat

local FOLD = { ["ä"] = "a", ["Ä"] = "a", ["ö"] = "o", ["Ö"] = "o", ["ü"] = "u", ["Ü"] = "u", ["ß"] = "ss" }

function S.fold(text)
  return (tostring(text or ""):gsub("[\195][\132\164\150\182\156\188\159]", FOLD):lower())
end

-- Plain folded substring test, also the filter of the instance list (RefLogic.Instances).
function S.match(text, query)
  return S.fold(text):find(S.fold(query), 1, true) ~= nil
end

-- Percent-encoding of a query for a URL (only unreserved characters stay).
function S.urlEncode(text)
  return (tostring(text or ""):gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", byte(c))
  end))
end

-- Address of the website search; only the typed query is part of it.
function S.WebUrl(website, lang, query)
  return website .. "/" .. lang .. "/wow-forever/suche?q=" .. S.urlEncode(query)
end

-- Limits and weights -------------------------------------------------------------------

S.MAX_PER_KIND = 25
-- Hits per group on the results page before "show more".
S.GROUP_LIMIT = 10
S.RECENT_MAX = 8
S.BEST_COUNT = 8
S.THRESHOLD = 40
S.EXPECTED_BOOST = 1.3

-- Points of a query token against one word.
local POINTS = { exact = 100, prefix = 80, synonym = 70, substring = 50, typo = 60, typoStep = 10 }
-- A query word typed with ae, oe or ue instead of the umlaut (the data keeps the umlaut).
local VARIANT_POINTS = { exact = 95, prefix = 75 }
local FIELD_OTHER, FIELD_ALIAS, FIELD_SUB = 0.9, 0.9, 0.3
local BONUS_SEQUENCE, BONUS_START = 20, 15
local LENGTH_PENALTY, LENGTH_PENALTY_MAX = 0.15, 8

-- Weight per kind without a question pattern (missing = 1.0). Abilities are numerous and
-- often only mention a place ("Portal: Ironforge"), so they rank like quests.
S.KIND_WEIGHT = { quest = 0.9, boss = 0.9, place = 0.9, ability = 0.9 }

-- Filler words of the query (folded). Names keep theirs.
S.STOPWORDS = {
  "wo",
  "finde",
  "ich",
  "wer",
  "verkauft",
  "lerne",
  "den",
  "die",
  "das",
  "where",
  "find",
  "can",
  "i",
  "who",
  "sells",
  "the",
}

-- Question patterns: the longest matching phrase at the start of the query is removed and the
-- expected kinds get S.EXPECTED_BOOST.
S.INTENTS = {
  {
    phrases = { "wo finde ich", "wo finde", "where can i find", "where do i find", "where to find" },
    kinds = { "gather", "item", "boss", "trainer", "weaponMaster", "vendor" },
  },
  {
    phrases = { "wer verkauft", "wo kaufe ich", "who sells", "where can i buy", "where to buy" },
    kinds = { "vendor" },
  },
  {
    phrases = { "wo lerne ich", "wo kann ich lernen", "where can i learn", "where do i learn", "where to learn" },
    kinds = { "trainer", "weaponMaster", "professionTrainer", "recipe" },
  },
}

-- Words that mean the same (German and English), one group per line. Only safe pairs.
S.SYNONYMS = {
  { "Kraut", "Kräuter", "herb", "herbs" },
  { "Erz", "Erze", "ore", "ores" },
  { "Händler", "Haendler", "vendor", "vendors", "merchant" },
  { "Lehrer", "trainer", "trainers" },
  { "Boss", "Bosse", "bosses" },
  { "Dungeon", "Dungeons", "Instanz", "Instanzen" },
  { "Quest", "Quests", "Aufgabe", "Aufgaben" },
  { "Flugmeister", "flightmaster" },
  { "Zeppelin", "airship" },
  { "Rezept", "Rezepte", "recipe", "recipes" },
  { "Beruf", "Berufe", "profession", "professions" },
  { "Schmiedekunst", "blacksmithing" },
  { "Alchemie", "alchemy" },
  { "Schneiderei", "tailoring" },
  { "Lederverarbeitung", "leatherworking" },
  { "Verzauberkunst", "enchanting" },
  { "Ingenieurskunst", "engineering" },
  { "Kochkunst", "cooking" },
  { "Bergbau", "mining" },
  { "Kräuterkunde", "herbalism" },
  { "Angeln", "fishing" },
  { "Eisenschmiede", "Ironforge" },
  { "Sturmwind", "Stormwind" },
  { "Unterstadt", "Undercity" },
  { "Silberwald", "Silverpine" },
}

-- Kind order (tie-break and grouping), extended by S.RegisterSource.
S.KINDS = {}

-- Text handling -------------------------------------------------------------------------

-- Words of a text in original spelling: apostrophes vanish, other punctuation separates.
local function split(text)
  text = tostring(text or ""):gsub("['`]", ""):gsub("\226\128[\152\153]", ""):gsub("\226\128[\147\148]", " ")
  local out = {}
  for w in text:gsub("[^%w\128-\255]+", " "):gmatch("%S+") do
    out[#out + 1] = w
  end
  return out
end

local function foldedWords(text)
  local out = split(text)
  for i, w in ipairs(out) do
    out[i] = S.fold(w)
  end
  return out
end
S.Tokens = foldedWords

-- Optimal string alignment distance (insert, delete, replace, swap of neighbours), nil above max.
local rowA, rowB, rowC = {}, {}, {}
local function distance(a, b, max)
  local la, lb = #a, #b
  if la - lb > max or lb - la > max then
    return nil
  end
  local prev2, prev, cur = rowA, rowB, rowC
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    cur[0] = i
    local ca = byte(a, i)
    local rowMin = i
    for j = 1, lb do
      local v = prev[j - 1] + (ca == byte(b, j) and 0 or 1)
      if prev[j] + 1 < v then
        v = prev[j] + 1
      end
      if cur[j - 1] + 1 < v then
        v = cur[j - 1] + 1
      end
      if i > 1 and j > 1 and ca == byte(b, j - 1) and byte(a, i - 1) == byte(b, j) and prev2[j - 2] + 1 < v then
        v = prev2[j - 2] + 1
      end
      cur[j] = v
      if v < rowMin then
        rowMin = v
      end
    end
    if rowMin > max then
      return nil
    end
    prev2, prev, cur = prev, cur, prev2
  end
  local d = prev[lb]
  return d <= max and d or nil
end
S.distance = distance

-- Typo candidates need the same first letter or the same second and third letter.
local function sameStart(a, b)
  return byte(a, 1) == byte(b, 1) or sub(a, 2, 3) == sub(b, 2, 3)
end

local function typoLimit(len)
  if len >= 7 then
    return 2
  end
  return len >= 4 and 1 or 0
end

-- "duesterbruch" -> "dusterbruch": the folded umlaut spelling, nil when the word has no ae, oe, ue.
local function umlautVariant(token)
  if #token < 3 then
    return nil
  end
  local v = token:gsub("([aou])e", "%1")
  return v ~= token and v or nil
end

-- Lookup tables built once from the data above.
local stopSet, intents, synGroup

local function prepareTables()
  if stopSet then
    return
  end
  stopSet = {}
  for _, w in ipairs(S.STOPWORDS) do
    stopSet[w] = true
  end
  intents = {}
  for _, intent in ipairs(S.INTENTS) do
    local kinds = {}
    for _, k in ipairs(intent.kinds) do
      kinds[k] = true
    end
    for _, phrase in ipairs(intent.phrases) do
      intents[#intents + 1] = { words = foldedWords(phrase), kinds = kinds }
    end
  end
  synGroup = {}
  for _, group in ipairs(S.SYNONYMS) do
    local words = {}
    for i, w in ipairs(group) do
      words[i] = S.fold(w)
    end
    for _, w in ipairs(words) do
      synGroup[w] = synGroup[w] or words
    end
  end
end

-- { tokens = folded query words without filler, kinds = set or nil }
local function parseQuery(query)
  prepareTables()
  local words = foldedWords(query)
  local kinds, skip = nil, 0
  for _, p in ipairs(intents) do
    local n = #p.words
    if n > skip and n <= #words then
      local same = true
      for i = 1, n do
        if words[i] ~= p.words[i] then
          same = false
          break
        end
      end
      if same then
        kinds, skip = p.kinds, n
      end
    end
  end
  local rest, kept = {}, {}
  for i = skip + 1, #words do
    rest[#rest + 1] = words[i]
    if not stopSet[words[i]] then
      kept[#kept + 1] = words[i]
    end
  end
  -- A query made of filler only (for example "die") is searched as typed.
  return { tokens = #kept > 0 and kept or rest, kinds = kinds }
end

-- Index -----------------------------------------------------------------------------------

local sources, registered, batches = {}, {}, {}
local version = 0
-- Kinds whose source failed during the last index build, and the kinds already reported.
local failed, reported = {}, {}

-- Registers the source of one entry kind. fn(add) calls add(name, subtitle, path, aliases, data)
-- per entry: name is a string or { de, en }, aliases an optional list of strings, data a payload
-- handed back on the hit. New kinds sort behind the existing ones. o.weight sets the kind weight
-- (default 1.0). The kind label is the locale key "search.kind.<kind>" of the registering module.
-- Without fn the kind is filled through S.NewBatch (entries built in slices over several frames).
function S.RegisterSource(kind, fn, o)
  if not registered[kind] then
    registered[kind] = true
    S.KINDS[#S.KINDS + 1] = kind
  end
  sources[kind] = fn
  if o and o.weight then
    S.KIND_WEIGHT[kind] = o.weight
  end
  version = version + 1
end

local index

-- Drops the cached index (changed data or sources); the next search rebuilds it.
function S.ResetIndex()
  index = nil
end

-- Kinds (in S.KINDS order) whose source failed in the current index.
function S.FailedKinds()
  local out = {}
  for _, kind in ipairs(S.KINDS) do
    if failed[kind] then
      out[#out + 1] = kind
    end
  end
  return out
end

-- Called once per kind with (kind, error) when its source fails; set by the results page.
S.OnSourceError = nil

local function newField(text, weight, isName, vocab)
  local raw = split(text)
  local words = {}
  for i, w in ipairs(raw) do
    words[i] = S.fold(w)
    if isName and not vocab.names[words[i]] then
      vocab.names[words[i]] = w
    end
    vocab.all[words[i]] = true
  end
  return { words = words, joined = concat(words, " "), weight = weight, name = isName }
end

local function sortedKeys(set)
  local list = {}
  for w in pairs(set) do
    list[#list + 1] = w
  end
  table.sort(list)
  return list
end

-- One index entry (nil without a display name); its words also go into vocab.
local function makeEntry(kind, locale, vocab, name, subtitle, path, aliases, data)
  local display = ns.T(name)
  if not display or display == "" then
    return nil
  end
  local fields = { newField(display, 1, true, vocab) }
  if type(name) == "table" then
    local other = locale == "deDE" and name.en or name.de
    if other and other ~= "" and S.fold(other) ~= S.fold(display) then
      fields[#fields + 1] = newField(other, FIELD_OTHER, true, vocab)
    end
  end
  for _, alias in ipairs(aliases or {}) do
    fields[#fields + 1] = newField(alias, FIELD_ALIAS, true, vocab)
  end
  if subtitle and subtitle ~= "" then
    -- Many entries share one subtitle (the instance of a boss, the profession of a recipe): one
    -- immutable field serves them all.
    local field = vocab.subs[subtitle]
    if not field then
      field = newField(subtitle, FIELD_SUB, false, vocab)
      vocab.subs[subtitle] = field
    end
    fields[#fields + 1] = field
  end
  local parts = {}
  for i, f in ipairs(fields) do
    parts[i] = f.joined
  end
  -- Eight keys at most: a ninth would double the hash part of every entry.
  return {
    kind = kind,
    name = display,
    sub = subtitle,
    path = path,
    data = data,
    fields = fields,
    hay = " " .. concat(parts, " ") .. " ",
  }
end

-- Entries of a kind that a module builds in slices over several frames (data add-ons that load on
-- demand). b.add(name, subtitle, path, aliases, data) works like the add of a source, b.done()
-- hands the finished list to the index (the kind must be registered without a source). A batch is
-- built for the language active at S.NewBatch and only used while that language is active.
function S.NewBatch(kind)
  local b = { locale = ns.GetActiveLocale(), entries = {}, vocab = { names = {}, all = {}, subs = {} } }
  function b.add(...)
    local e = makeEntry(kind, b.locale, b.vocab, ...)
    if e then
      b.entries[#b.entries + 1] = e
    end
  end
  function b.done()
    batches[kind] = b
    index = nil
  end
  return b
end

-- Language of the finished batch of a kind, nil without one.
function S.BatchLocale(kind)
  return batches[kind] and batches[kind].locale or nil
end

local function buildIndex()
  local locale = ns.GetActiveLocale()
  local vocab = { names = {}, all = {}, subs = {} }
  local entries = {}
  failed = {}
  local function push(e)
    e.order = #entries
    entries[#entries + 1] = e
  end
  for _, kind in ipairs(S.KINDS) do
    local source, batch = sources[kind], batches[kind]
    if source then
      -- One broken source costs its own kind, never the others.
      local before = #entries
      local ok, err = pcall(source, function(...)
        local e = makeEntry(kind, locale, vocab, ...)
        if e then
          push(e)
        end
      end)
      if not ok then
        for i = #entries, before + 1, -1 do
          entries[i] = nil
        end
        failed[kind] = true
        if not reported[kind] then
          reported[kind] = true
          if ns.Log then
            ns.Log.warn("search source %s failed: %s", kind, tostring(err))
          end
          if S.OnSourceError then
            pcall(S.OnSourceError, kind, err)
          end
        end
      end
    elseif batch and batch.locale == locale then
      for _, e in ipairs(batch.entries) do
        push(e)
      end
      for w, display in pairs(batch.vocab.names) do
        vocab.names[w] = vocab.names[w] or display
      end
      for w in pairs(batch.vocab.all) do
        vocab.all[w] = true
      end
    end
  end
  return {
    locale = locale,
    version = version,
    entries = entries,
    vocab = vocab,
    words = sortedKeys(vocab.all),
    nameWords = sortedKeys(vocab.names),
    matchers = {},
    matcherCount = 0,
  }
end

local function getIndex()
  if not index or index.locale ~= ns.GetActiveLocale() or index.version ~= version then
    index = buildIndex()
  end
  return index
end
S.GetIndex = getIndex

-- Scoring ---------------------------------------------------------------------------------

-- Per query token: typo neighbours in the vocabulary and synonyms, found once per token.
local function matcher(idx, token)
  local m = idx.matchers[token]
  if m then
    return m
  end
  prepareTables()
  local len = #token
  m = { token = token, len = len, fuzzy = {}, syn = {}, var = umlautVariant(token) }
  local limit = typoLimit(len)
  if limit > 0 then
    for _, w in ipairs(idx.words) do
      if w ~= token and sameStart(token, w) then
        local d = distance(token, w, limit)
        if d then
          m.fuzzy[w] = d
        end
      end
    end
  end
  for _, w in ipairs(synGroup[token] or {}) do
    if w ~= token then
      m.syn[w] = true
    end
  end
  m.alt = next(m.fuzzy) ~= nil or next(m.syn) ~= nil
  if idx.matcherCount >= 300 then
    idx.matchers, idx.matcherCount = {}, 0
  end
  idx.matchers[token] = m
  idx.matcherCount = idx.matcherCount + 1
  return m
end

local function wordScore(m, w)
  local t = m.token
  if w == t then
    return POINTS.exact
  end
  if m.len >= 2 and sub(w, 1, m.len) == t then
    return POINTS.prefix
  end
  if m.syn[w] then
    return POINTS.synonym
  end
  local v = m.var
  if v then
    if w == v then
      return VARIANT_POINTS.exact
    elseif sub(w, 1, #v) == v then
      return VARIANT_POINTS.prefix
    end
  end
  local s = find(w, t, 1, true) and POINTS.substring or 0
  if v and s < POINTS.substring and find(w, v, 1, true) then
    s = POINTS.substring
  end
  local d = m.fuzzy[w]
  if d and POINTS.typo - POINTS.typoStep * d > s then
    s = POINTS.typo - POINTS.typoStep * d
  end
  return s
end

-- Points of one entry before the kind weight, nil when a token is missing or the sum is below
-- the threshold.
local function scoreEntry(e, ms, joined)
  local total = 0
  for _, m in ipairs(ms) do
    if not (m.alt or find(e.hay, m.token, 1, true) or (m.var and find(e.hay, m.var, 1, true))) then
      return nil
    end
    local best = 0
    for _, f in ipairs(e.fields) do
      if f.weight * POINTS.exact > best then
        local top = 0
        for _, w in ipairs(f.words) do
          local s = wordScore(m, w)
          if s > top then
            top = s
            if s == POINTS.exact then
              break
            end
          end
        end
        if top * f.weight > best then
          best = top * f.weight
        end
      end
    end
    if best <= 0 then
      return nil
    end
    total = total + best
  end
  local sequence, starts = false, false
  for _, f in ipairs(e.fields) do
    if f.name then
      if sub(f.joined, 1, #joined) == joined then
        starts = true
      end
      for i = 1, #f.words - #ms + 1 do
        local run = #ms > 1
        for k = 1, #ms do
          if run and wordScore(ms[k], f.words[i + k - 1]) <= 0 then
            run = false
          end
        end
        if run then
          sequence = true
          break
        end
      end
    end
  end
  if sequence then
    total = total + BONUS_SEQUENCE
  end
  if starts then
    total = total + BONUS_START
  end
  total = total - math.min(LENGTH_PENALTY_MAX, LENGTH_PENALTY * math.max(0, #e.fields[1].joined - #joined))
  return total >= S.THRESHOLD and total or nil
end

local function sortHits(hits)
  table.sort(hits, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.order ~= b.order then
      return a.order < b.order
    end
    -- Equal quality: the shorter name first, then alphabetical.
    if a.len ~= b.len then
      return a.len < b.len
    end
    if a.key ~= b.key then
      return a.key < b.key
    end
    return a.i < b.i
  end)
end

local function newHit(e, score, order)
  return {
    kind = e.kind,
    name = e.name,
    sub = e.sub,
    path = e.path,
    data = e.data,
    score = score,
    order = order[e.kind],
    key = e.fields[1].joined,
    len = #e.fields[1].joined,
    i = e.order,
  }
end

-- Last resort without any hit: the query without spaces inside a name with spaces
-- ("hundemeister" finds "Hunde Meister"). Names only, so nothing is stored per entry.
local function collectSquashed(idx, q, order)
  local needle = concat(q.tokens)
  local hits = {}
  if #needle < 4 then
    return hits
  end
  for _, e in ipairs(idx.entries) do
    local best
    for _, f in ipairs(e.fields) do
      if f.name then
        local flat = f.joined:gsub(" ", "")
        local at = find(flat, needle, 1, true)
        if at then
          local points = (at == 1 and POINTS.prefix or POINTS.substring)
            - math.min(LENGTH_PENALTY_MAX, LENGTH_PENALTY * (#flat - #needle))
          best = math.max(best or 0, points * f.weight)
        end
      end
    end
    if best and best >= S.THRESHOLD then
      local boost = q.kinds and q.kinds[e.kind] and S.EXPECTED_BOOST or 1
      hits[#hits + 1] = newHit(e, best * (S.KIND_WEIGHT[e.kind] or 1) * boost, order)
    end
  end
  return hits
end

-- All entries above the threshold, best first.
local function collect(idx, q)
  local ms = {}
  for i, t in ipairs(q.tokens) do
    ms[i] = matcher(idx, t)
  end
  local joined = concat(q.tokens, " ")
  local order = {}
  for i, k in ipairs(S.KINDS) do
    order[k] = i
  end
  local hits = {}
  for _, e in ipairs(idx.entries) do
    local raw = scoreEntry(e, ms, joined)
    if raw then
      local boost = q.kinds and q.kinds[e.kind] and S.EXPECTED_BOOST or 1
      hits[#hits + 1] = newHit(e, raw * (S.KIND_WEIGHT[e.kind] or 1) * boost, order)
    end
  end
  if #hits == 0 then
    hits = collectSquashed(idx, q, order)
  end
  sortHits(hits)
  return hits
end

-- "Did you mean": every token without any match is replaced by the closest name word; the
-- corrected query is only offered when it finds something.
local function suggest(idx, q)
  local words, display = idx.nameWords, idx.vocab.names
  local out, changed = {}, false
  for i, t in ipairs(q.tokens) do
    local known = false
    for _, w in ipairs(idx.words) do
      if find(w, t, 1, true) then
        known = true
        break
      end
    end
    if known then
      out[i] = display[t] or t
    else
      local limit = #t >= 8 and 2 or (#t >= 4 and 1 or 0)
      local bestWord, bestD
      for _, w in ipairs(words) do
        if sameStart(t, w) then
          local d = distance(t, w, bestD and bestD - 1 or limit)
          if d then
            bestWord, bestD = w, d
          end
        end
      end
      if not bestWord then
        return nil
      end
      out[i], changed = display[bestWord], true
    end
  end
  if not changed then
    return nil
  end
  local text = concat(out, " ")
  return #collect(idx, parseQuery(text)) > 0 and text or nil
end

-- Returns { items, best, total, more, suggestion }:
--   best        the top hits of all kinds mixed, best first (at most o.best, default S.BEST_COUNT),
--   items       all hits grouped by kind in S.KINDS order, best first, at most o.limit per kind,
--   more        { [kind] = hidden count },
--   counts      { [kind] = all hits of the kind },
--   suggestion  corrected query, only when nothing reaches the threshold.
-- Each hit is { kind, name, sub, path, data, score }.
function S.Search(query, o)
  o = o or {}
  local result = { items = {}, best = {}, total = 0, more = {}, counts = {} }
  local q = parseQuery(query)
  if #q.tokens == 0 then
    return result
  end
  local idx = getIndex()
  local hits = collect(idx, q)
  result.total = #hits
  for i = 1, math.min(#hits, o.best or S.BEST_COUNT) do
    result.best[i] = hits[i]
  end
  local limit = o.limit or S.MAX_PER_KIND
  -- o.limits[kind] overrides the limit of single kinds (an expanded group).
  local limits = o.limits or {}
  local groups, counts = {}, result.counts
  for _, h in ipairs(hits) do
    counts[h.kind] = (counts[h.kind] or 0) + 1
    if counts[h.kind] <= (limits[h.kind] or limit) then
      local g = groups[h.kind] or {}
      groups[h.kind] = g
      g[#g + 1] = h
    end
  end
  for _, kind in ipairs(S.KINDS) do
    for _, h in ipairs(groups[kind] or {}) do
      result.items[#result.items + 1] = h
    end
    local cap = limits[kind] or limit
    if (counts[kind] or 0) > cap then
      result.more[kind] = counts[kind] - cap
    end
  end
  if #hits == 0 then
    result.suggestion = suggest(idx, q)
  end
  return result
end

-- Flat list rows for the results page: a header, the best hits, then the remaining hits (hits
-- already shown above are not repeated). Without groupLabel one "all" header precedes them.
-- With groupLabel(kind, count) every kind gets a header { header, kind, name } and, when hits are
-- hidden by the limit, a row { more = true, kind, hidden } behind its hits.
function S.ListRows(result, bestLabel, allLabel, groupLabel)
  local rows, shown = {}, {}
  if #result.best > 0 then
    rows[1] = { header = true, name = bestLabel }
    for _, h in ipairs(result.best) do
      rows[#rows + 1] = h
      shown[h] = true
    end
  end
  if groupLabel then
    local byKind = {}
    for _, h in ipairs(result.items) do
      if not shown[h] then
        byKind[h.kind] = byKind[h.kind] or {}
        table.insert(byKind[h.kind], h)
      end
    end
    for _, kind in ipairs(S.KINDS) do
      local list, hidden = byKind[kind] or {}, result.more[kind] or 0
      if #list > 0 or hidden > 0 then
        local count = result.counts and result.counts[kind] or (#list + hidden)
        rows[#rows + 1] = { header = true, kind = kind, name = groupLabel(kind, count) }
        for _, h in ipairs(list) do
          rows[#rows + 1] = h
        end
        if hidden > 0 then
          rows[#rows + 1] = { more = true, kind = kind, hidden = hidden }
        end
      end
    end
    return rows
  end
  local headed = false
  for _, h in ipairs(result.items) do
    if not shown[h] then
      if not headed then
        rows[#rows + 1] = { header = true, name = allLabel }
        headed = true
      end
      rows[#rows + 1] = h
    end
  end
  return rows
end

-- Highlight ------------------------------------------------------------------------------------

local MAX_SPANS = 3

local function wordStart(hay, at)
  return at == 1 or find(sub(hay, at - 1, at - 1), "[^%w\128-\255]") ~= nil
end

-- Byte ranges { from, to } of the query words inside a display text in its original spelling
-- (umlauts and apostrophes handled like in the match), at most three, sorted and merged.
function S.Spans(text, query)
  text = tostring(text or "")
  local folded, from, to, n = {}, {}, {}, 0
  local i, len = 1, #text
  while i <= len do
    local b = byte(text, i)
    local size = b >= 240 and 4 or (b >= 224 and 3 or (b >= 192 and 2 or 1))
    local ch = sub(text, i, i + size - 1)
    if ch ~= "'" and ch ~= "`" and ch ~= "\226\128\152" and ch ~= "\226\128\153" then
      local f = S.fold(ch)
      for k = 1, #f do
        n = n + 1
        folded[n], from[n], to[n] = sub(f, k, k), i, i + size - 1
      end
    end
    i = i + size
  end
  local hay = concat(folded)
  local found = {}
  for _, token in ipairs(parseQuery(query).tokens) do
    for _, needle in ipairs({ token, umlautVariant(token) or token }) do
      local first, chosen
      local init = 1
      while true do
        local s, e = find(hay, needle, init, true)
        if not s then
          break
        end
        first = first or { s, e }
        if wordStart(hay, s) then
          chosen = { s, e }
          break
        end
        init = s + 1
      end
      chosen = chosen or first
      if chosen then
        found[#found + 1] = { from = from[chosen[1]], to = to[chosen[2]] }
        break
      end
    end
  end
  table.sort(found, function(a, b)
    return a.from < b.from
  end)
  local out = {}
  for _, r in ipairs(found) do
    local last = out[#out]
    -- Words that only a space apart read as one phrase.
    if last and r.from <= last.to + 2 then
      last.to = math.max(last.to, r.to)
    elseif #out < MAX_SPANS then
      out[#out + 1] = r
    end
  end
  return out
end

-- Recent searches ------------------------------------------------------------------------------

local MAX_RECENT_LENGTH = 60

-- Stored list (untrusted SavedVariables) as a clean list: strings only, trimmed, unique
-- ignoring case, newest first, at most S.RECENT_MAX.
function S.CleanRecent(list)
  local out, seen = {}, {}
  for _, q in ipairs(type(list) == "table" and list or {}) do
    if type(q) == "string" and #out < S.RECENT_MAX then
      q = q:match("^%s*(.-)%s*$")
      local key = S.fold(q)
      if q ~= "" and #q <= MAX_RECENT_LENGTH and not seen[key] then
        seen[key] = true
        out[#out + 1] = q
      end
    end
  end
  return out
end

-- The list with query put in front (an equal one moves up).
function S.PushRecent(list, query)
  local merged = { query }
  for _, q in ipairs(type(list) == "table" and list or {}) do
    merged[#merged + 1] = q
  end
  return S.CleanRecent(merged)
end

-- Built-in sources -------------------------------------------------------------------------

-- Page titles in both languages straight from the locale tables, the page's own words as aliases.
local function pageTitle(key)
  local loc = ns.Locales or {}
  local de, en = loc.deDE and loc.deDE[key], loc.enUS and loc.enUS[key]
  if de or en then
    return { de = de, en = en }
  end
  return ns.L[key]
end

S.RegisterSource("page", function(add)
  for _, page in ipairs(ns.Router and ns.Router:list() or {}) do
    if page.sidebar ~= false then
      add(pageTitle(page.title), nil, page.id, page.aliases)
    end
  end
end)

S.RegisterSource("class", function(add)
  for _, c in ipairs((ns.Data or {}).Classes or {}) do
    add(c.n, nil, "classes/" .. c.id)
  end
end)

S.RegisterSource("race", function(add)
  for _, r in ipairs((ns.Data or {}).Races or {}) do
    add(r.n, nil, "classes/races/" .. r.slug)
  end
end)

local function eachInstance(fn)
  for _, i in ipairs((ns.Data or {}).Instances or {}) do
    fn(i, ns.RefLogic.InstanceSlug(i))
  end
end

S.RegisterSource("instance", function(add)
  eachInstance(function(i, slug)
    add(i.n, i.lv, "instances/" .. slug)
  end)
end)

S.RegisterSource("boss", function(add)
  eachInstance(function(i, slug)
    for _, b in ipairs(i.bo or {}) do
      add(b.n, ns.T(i.n), "instances/" .. slug .. "/bosses")
    end
  end)
end)

S.RegisterSource("quest", function(add)
  eachInstance(function(i, slug)
    for _, quest in ipairs(i.q or {}) do
      add(quest.n, ns.T(i.n), "instances/" .. slug .. "/quests")
    end
  end)
end)

S.RegisterSource("place", function(add)
  for _, n in ipairs((ns.Data or {}).Travel and ns.Data.Travel.nodes or {}) do
    add(n.n, n.z, "map/" .. n.s)
  end
end)

S.RegisterSource("trainer", function(add)
  for _, t in ipairs((ns.Data or {}).Trainers and ns.Data.Trainers.trainers or {}) do
    add(t.n, ns.RefLogic.className(t.c), "trainers/" .. t.c)
  end
end)

S.RegisterSource("weaponMaster", function(add)
  for _, t in ipairs((ns.Data or {}).Weapons and ns.Data.Weapons.trainers or {}) do
    if t.n then
      add(t.n, ns.T(t.z), "weapons")
    end
  end
end)

S.RegisterSource("weapon", function(add)
  for id, skill in pairs((ns.Data or {}).Weapons and ns.Data.Weapons.skills or {}) do
    add(skill, nil, "weapons/" .. id)
  end
end)

S.RegisterSource("ability", function(add)
  local R = ns.RefLogic
  for _, class in ipairs(R.CLASSES) do
    for _, a in ipairs(R.LearnList(class)) do
      add(a.n, R.className(class), "levels/" .. class)
    end
  end
end)
