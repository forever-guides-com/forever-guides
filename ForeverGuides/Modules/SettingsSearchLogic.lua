-- Search over everything the settings offer: the menu pages, the tabs (features), the cards and every single
-- setting with its name, its explanation, its card and its tab. Pure logic, no frames. The settings come from
-- the generated data of Modules/SettingsIndexData.lua (the built cards, read once by a tool) and the registry
-- of Modules/SettingsFeatures.lua, so the index needs no card to be built and no add-on to be loaded.
--
-- Ranking: a hit in the name beats a hit in the surroundings (tab, card, keywords), which beats a hit in the
-- explanation; inside a class a start of the name or a word start beats a part of a word. Case, umlauts and the
-- spelling ae, oe, ue, ss do not matter, a word stem is found by its start ("sammel").
local _, ns = ...

local SL = {}
ns.SettingsSearchLogic = SL

local find, sub = string.find, string.sub

-- Points of a query word against a word of the index, the weight of each field and of each kind of entry.
local POINTS = { exact = 100, prefix = 85, variantExact = 95, variantPrefix = 80, synonym = 70, part = 50 }
local FIELD = { name = 1, alt = 0.85, context = 0.5, keyword = 0.45, hint = 0.25 }
local KIND = { page = 1.12, feature = 1.05, card = 0.92, setting = 1 }
local MIN_TOKEN = 20
local BONUS_NAME, BONUS_START, BONUS_SEQUENCE = 15, 20, 10
local LENGTH_PENALTY, LENGTH_PENALTY_MAX = 0.15, 8
-- Points a setting of a tab that the query names gets over settings elsewhere (suggestions only).
local AFFINITY = 25

-- Rows of the suggestion list: at most this many hits, of which at most NAV_FIRST are pages and tabs while
-- settings are there to fill the rest.
SL.MAX_SUGGESTIONS, SL.NAV_FIRST = 8, 3
-- A setting that only matches through its card or tab (not through its own words) shows at most this many
-- times per card and in all in the suggestions.
SL.CONTEXT_PER_CARD, SL.CONTEXT_MAX = 2, 4
SL.MIN_QUERY = 2

-- Classes of a hit: the words of the name, the surroundings, the explanation.
SL.NAME, SL.CONTEXT, SL.HINT = 1, 2, 3

local function fold(text)
  return ns.SearchLogic.fold(text)
end

local function words(text)
  return ns.SearchLogic.Tokens(text)
end

-- The text of a key in one language. A card of a sub-add-on carries the texts of its keys itself, its own locale
-- is not there while the add-on is off.
local function textOf(key, locale, card)
  if not key then
    return nil
  end
  local table_ = ns.Locales and ns.Locales[locale]
  local text = table_ and table_[key]
  if text then
    return text
  end
  local snapshot = card and card.text and card.text[key]
  return snapshot and snapshot[locale == "deDE" and "de" or "en"] or nil
end
SL.TextOf = textOf

-- One line of plain text: colors, line breaks and runs of blanks go.
local function clean(text)
  if not text then
    return nil
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
  text = text:match("^%s*(.-)%s*$")
  return text ~= "" and text or nil
end

local function other(locale)
  return locale == "deDE" and "enUS" or "deDE"
end

-- Index ---------------------------------------------------------------------------------------------------------

local index

function SL.Reset()
  index = nil
end

local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, w in ipairs(list) do
      out[#out + 1] = w
    end
  end
  return out
end

local function entry(kind, uid, fields)
  fields.kind, fields.uid = kind, uid
  fields.nameJ = table.concat(fields.nameW, " ")
  fields.nameSq = fields.nameJ:gsub(" ", "")
  return fields
end

-- The menu pages (the entries of the sidebar), found by their title in both languages and their own words.
local function pageEntries(out, locale)
  for _, page in ipairs(ns.Router and ns.Router:list() or {}) do
    if page.sidebar ~= false and page.id ~= "search" then
      local name = clean(textOf(page.title, locale)) or clean(ns.L[page.title])
      if name and name ~= page.title then
        local alt = {}
        for _, a in ipairs(page.aliases or {}) do
          alt[#alt + 1] = fold(a)
        end
        local altName = clean(textOf(page.title, other(locale)))
        out[#out + 1] = entry("page", "page:" .. page.id, {
          name = name,
          nameW = words(name),
          altW = concat(altName and words(altName) or {}, alt),
          ctxW = {},
          kwW = {},
          hintW = {},
          page = page.id,
          path = ns.L["settings.search.page"],
          order = #out + 1,
        })
      end
    end
  end
end

local function wordsOfKeywords(feature, locale)
  local out = {}
  for _, loc in ipairs({ locale, other(locale) }) do
    local text = textOf("settings.feature." .. feature .. ".keywords", loc)
    if text then
      out = concat(out, words(text))
    end
  end
  return out
end

local function build(locale)
  local SF = ns.SettingsFeatures
  local out = {}
  pageEntries(out, locale)
  local featureInfo = {}
  for _, f in ipairs(SF.FEATURES) do
    local name = clean(textOf("settings.feature." .. f.id, locale))
    local altName = clean(textOf("settings.feature." .. f.id, other(locale)))
    if name then
      local groupName = clean(textOf("settings.group." .. f.group .. ".long", locale)) or ""
      local kw = wordsOfKeywords(f.id, locale)
      local info = {
        name = name,
        groupName = groupName,
        nameW = words(name),
        altW = altName and words(altName) or {},
        kwW = kw,
        groupW = words(groupName),
      }
      featureInfo[f.id] = info
      out[#out + 1] = entry("feature", "feature:" .. f.id, {
        name = name,
        nameW = info.nameW,
        altW = info.altW,
        ctxW = info.groupW,
        kwW = kw,
        hintW = {},
        feature = f.id,
        featureName = name,
        path = groupName,
        order = #out + 1,
      })
    end
  end
  for _, card in ipairs(ns.SettingsIndexData or {}) do
    local info = featureInfo[card.feature]
    if info then
      local title = clean(textOf(card.title, locale, card))
      local altTitle = clean(textOf(card.title, other(locale), card))
      local cardPath = info.groupName .. " > " .. info.name
      local ctx = concat(info.nameW, info.altW, title and words(title) or {}, altTitle and words(altTitle) or {})
      local cardInfo = { title = title }
      local sameAsControl = false
      for _, control in ipairs(card.controls or {}) do
        local controlName = clean(textOf(control.key, locale, card))
        sameAsControl = sameAsControl or (title ~= nil and controlName ~= nil and fold(controlName) == fold(title))
      end
      if title and fold(title) ~= fold(info.name) and not sameAsControl then
        local intro = clean(textOf(card.intro, locale, card))
        out[#out + 1] = entry("card", "card:" .. card.id, {
          name = title,
          nameW = words(title),
          altW = altTitle and words(altTitle) or {},
          ctxW = concat(info.nameW, info.altW, info.groupW),
          kwW = info.kwW,
          hintW = intro and words(intro) or {},
          hint = intro,
          feature = card.feature,
          featureName = info.name,
          card = card.id,
          cardTitle = title,
          addon = card.addon,
          path = cardPath,
          order = #out + 1,
        })
      end
      for position, control in ipairs(card.controls or {}) do
        local name = clean(textOf(control.key, locale, card))
        local altName = clean(textOf(control.key, other(locale), card))
        if name then
          local hint = clean(textOf(control.hint, locale, card)) or clean(textOf(control.tip, locale, card))
          local altHint = clean(textOf(control.hint, other(locale), card))
            or clean(textOf(control.tip, other(locale), card))
          out[#out + 1] = entry("setting", "setting:" .. card.id .. ":" .. control.key, {
            name = name,
            nameW = words(name),
            altW = altName and words(altName) or {},
            ctxW = ctx,
            kwW = info.kwW,
            hintW = concat(hint and words(hint) or {}, altHint and words(altHint) or {}),
            hint = hint,
            feature = card.feature,
            featureName = info.name,
            card = card.id,
            cardTitle = cardInfo.title,
            control = control.id or control.key,
            controlKey = control.key,
            controlKind = control.kind,
            addon = card.addon,
            path = cardInfo.title and (cardPath .. " > " .. cardInfo.title) or cardPath,
            order = #out + 1,
            position = position,
          })
        end
      end
    end
  end
  return { locale = locale, entries = out }
end

local function get()
  local locale = ns.GetActiveLocale()
  if not index or index.locale ~= locale then
    index = build(locale)
  end
  return index
end

-- All entries of the active language (for the tests and the page of results).
function SL.Entries()
  return get().entries
end

-- Scoring --------------------------------------------------------------------------------------------------------

local synonyms
local function synonymsOf(token)
  if not synonyms then
    synonyms = {}
    for _, group in ipairs(ns.SearchLogic.SYNONYMS or {}) do
      local set = {}
      for _, w in ipairs(group) do
        set[fold(w)] = true
      end
      for w in pairs(set) do
        synonyms[w] = synonyms[w] or set
      end
    end
  end
  return synonyms[token]
end

-- The spelling with ae, oe, ue taken as the folded umlaut ("kraeuter" is "krauter"), nil without one.
local function variantOf(token)
  if #token < 3 then
    return nil
  end
  local v = token:gsub("([aou])e", "%1")
  return v ~= token and v or nil
end

local function prepare(token)
  return { token = token, len = #token, variant = variantOf(token), syn = synonymsOf(token) }
end

local function wordPoints(q, w)
  local t = q.token
  if w == t then
    return POINTS.exact
  end
  if q.len >= 2 and sub(w, 1, q.len) == t then
    return POINTS.prefix
  end
  local v = q.variant
  if v then
    if w == v then
      return POINTS.variantExact
    elseif sub(w, 1, #v) == v then
      return POINTS.variantPrefix
    end
  end
  if q.syn and q.syn[w] then
    return POINTS.synonym
  end
  if q.len >= 4 and find(w, t, 1, true) then
    return POINTS.part
  end
  if v and #v >= 4 and find(w, v, 1, true) then
    return POINTS.part
  end
  return 0
end

local function best(q, list, exactOnly)
  local top = 0
  for _, w in ipairs(list) do
    local p = wordPoints(q, w)
    if exactOnly and p < POINTS.prefix then
      p = 0
    end
    if p > top then
      top = p
      if top == POINTS.exact then
        break
      end
    end
  end
  return top
end

-- Points of one query word and the class it was found in, nil below the minimum. The words of the explanation
-- count with their start only, a part of a word there is noise.
local function tokenScore(q, e, single)
  local name = best(q, e.nameW) * FIELD.name
  if single and name < POINTS.part and q.len >= 4 then
    -- "chatname" finds "Chat-Name": the name without its blanks.
    local at = find(e.nameSq, q.token, 1, true)
    if at then
      name = (at == 1 and POINTS.variantPrefix or POINTS.part) * FIELD.name
    end
  end
  local points, class = name, SL.NAME
  local function take(value, as)
    if value > points then
      points, class = value, as
    end
  end
  take(best(q, e.altW) * FIELD.alt, SL.NAME)
  take(best(q, e.ctxW) * FIELD.context, SL.CONTEXT)
  take(best(q, e.kwW) * FIELD.keyword, SL.CONTEXT)
  take(best(q, e.hintW, true) * FIELD.hint, SL.HINT)
  if points < MIN_TOKEN then
    return nil
  end
  return points, class
end

local function startsWith(joined, query)
  return sub(joined, 1, #query) == query
end

-- A run of the query words in a row inside the name.
local function inSequence(e, qs)
  if #qs < 2 then
    return false
  end
  for i = 1, #e.nameW - #qs + 1 do
    local run = true
    for k = 1, #qs do
      if wordPoints(qs[k], e.nameW[i + k - 1]) <= 0 then
        run = false
        break
      end
    end
    if run then
      return true
    end
  end
  return false
end

-- { score, class } of an entry for the prepared query, nil when a word is missing.
local function scoreEntry(e, qs, joined)
  local sum, class = 0, SL.NAME
  for _, q in ipairs(qs) do
    local points, c = tokenScore(q, e, #qs == 1)
    if not points then
      return nil
    end
    sum = sum + points
    if c > class then
      class = c
    end
  end
  local score = sum / #qs
  if class == SL.NAME then
    score = score + BONUS_NAME
    if inSequence(e, qs) then
      score = score + BONUS_SEQUENCE
    end
  end
  if startsWith(e.nameJ, joined) then
    score = score + BONUS_START
  end
  score = score * (KIND[e.kind] or 1)
  score = score - math.min(LENGTH_PENALTY_MAX, LENGTH_PENALTY * math.max(0, #e.nameJ - #joined))
  return score, class
end

local function missing(e)
  if not e.addon then
    return false
  end
  return not (ns.SettingsPage and ns.SettingsPage.HasCard and ns.SettingsPage.HasCard(e.card))
end

-- The hit handed to the interface. `sub` is the line under the name (the place), `hint` the explanation.
local function hitOf(e, score, class)
  local hit = {
    kind = e.kind,
    uid = e.uid,
    name = e.name,
    sub = e.path,
    hint = e.hint,
    feature = e.feature,
    featureName = e.featureName,
    card = e.card,
    cardTitle = e.cardTitle,
    control = e.control,
    controlKey = e.controlKey,
    page = e.page,
    addon = e.addon,
    missing = missing(e),
    score = score,
    class = class,
    order = e.order,
    position = e.position,
    key = fold(e.name),
  }
  if hit.missing then
    local title = ns.L["subaddon." .. e.addon .. ".title"]
    hit.pending = string.format(ns.L["settings.search.pending"], title)
  end
  return hit
end

local function better(a, b)
  if a.class ~= b.class then
    return a.class < b.class
  end
  if a.score ~= b.score then
    return a.score > b.score
  end
  if a.order ~= b.order then
    return a.order < b.order
  end
  return a.uid < b.uid
end

-- Every hit of a query, best first: name hits, then hits in the surroundings, then hits in the explanation.
-- Entries with the same name in the same tab count once (the first wins).
function SL.Search(query)
  local tokens = words(query or "")
  if #tokens == 0 then
    return {}
  end
  local qs = {}
  for i, t in ipairs(tokens) do
    qs[i] = prepare(t)
  end
  local joined = table.concat(tokens, " ")
  local hits = {}
  for _, e in ipairs(get().entries) do
    local score, class = scoreEntry(e, qs, joined)
    if score then
      hits[#hits + 1] = hitOf(e, score, class)
    end
  end
  table.sort(hits, better)
  local seen, out = {}, {}
  for _, h in ipairs(hits) do
    local id = h.kind .. "|" .. tostring(h.feature) .. "|" .. h.key
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = h
    end
  end
  return out
end

local function isNav(hit)
  return hit.kind == "page" or hit.kind == "feature"
end

-- Whether a typed text is long enough to be suggested for (SL.MIN_QUERY letters without blanks).
function SL.Long(query)
  local letters = fold(query or ""):gsub("%s", "")
  return #letters >= SL.MIN_QUERY
end

-- The suggestion list for a typed query: { nav = { hits }, items = { hits }, more = hidden hits, total }.
-- Pages and tabs come first (pages before tabs; a tab that only matches through its keywords only when no page or
-- tab matches by name), then single settings. Settings that only match through their card or tab keep the
-- order of the card (its main switch first), at most CONTEXT_PER_CARD per card. Explanations never decide alone.
function SL.Suggest(query)
  local result = { nav = {}, items = {}, more = 0, total = 0 }
  if not SL.Long(query) then
    return result
  end
  local all = SL.Search(query)
  result.total = #all
  local nav, named, context = {}, {}, {}
  local namedNav, tabs = 0, {}
  for _, h in ipairs(all) do
    if h.class < SL.HINT then
      if isNav(h) then
        nav[#nav + 1] = h
        if h.class == SL.NAME then
          namedNav = namedNav + 1
          if h.feature and h.kind == "feature" then
            tabs[h.feature] = true
          end
        end
      elseif h.class == SL.NAME then
        named[#named + 1] = h
      elseif h.kind == "setting" then
        context[#context + 1] = h
      end
    end
  end
  -- Pages first, then tabs, each in the order of its score.
  local kept = {}
  for _, h in ipairs(nav) do
    if h.class == SL.NAME or namedNav == 0 then
      kept[#kept + 1] = h
    end
  end
  table.sort(kept, function(a, b)
    if a.class ~= b.class then
      return a.class < b.class
    end
    if a.kind ~= b.kind then
      return a.kind == "page"
    end
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.order < b.order
  end)
  -- A setting of a tab the query names comes before the same kind of hit elsewhere.
  local function affinity(h)
    return tabs[h.feature] and AFFINITY or 0
  end
  table.sort(named, function(a, b)
    local sa, sb = a.score + affinity(a), b.score + affinity(b)
    if sa ~= sb then
      return sa > sb
    end
    return a.order < b.order
  end)
  -- The surroundings: card by card (the card with the best hit first), inside a card by position.
  local cardScore = {}
  for _, h in ipairs(context) do
    cardScore[h.card] = math.max(cardScore[h.card] or 0, h.score + affinity(h))
  end
  table.sort(context, function(a, b)
    if a.card ~= b.card then
      if cardScore[a.card] ~= cardScore[b.card] then
        return cardScore[a.card] > cardScore[b.card]
      end
      return a.card < b.card
    end
    return (a.position or 0) < (b.position or 0)
  end)
  -- A card is left out when one of its settings is listed anyway.
  local listed, items = {}, {}
  for _, h in ipairs(named) do
    if h.kind == "setting" then
      listed[h.card] = true
    end
  end
  for _, h in ipairs(named) do
    if h.kind == "setting" or not listed[h.card] then
      items[#items + 1] = h
    end
  end
  local perCard, contextCount = {}, 0
  for _, h in ipairs(context) do
    local n = (perCard[h.card] or 0) + 1
    perCard[h.card] = n
    if n <= SL.CONTEXT_PER_CARD and contextCount < SL.CONTEXT_MAX then
      contextCount = contextCount + 1
      items[#items + 1] = h
    end
  end
  local room = SL.MAX_SUGGESTIONS
  local itemCount = math.min(#items, room - math.min(#kept, SL.NAV_FIRST))
  local navCount = math.min(#kept, room - itemCount)
  for i = 1, navCount do
    result.nav[i] = kept[i]
  end
  for i = 1, itemCount do
    result.items[i] = items[i]
  end
  result.more = result.total - navCount - itemCount
  return result
end

-- The hits of the page of results: tabs, cards and settings (the menu pages have their own group there),
-- grouped by tab. Tabs come in the order of their best hit. { groups = { { feature, name, hits } }, total }.
function SL.Results(query)
  local groups, byFeature, total = {}, {}, 0
  for _, h in ipairs(SL.Search(query)) do
    if h.kind ~= "page" then
      local g = byFeature[h.feature]
      if not g then
        g = { feature = h.feature, name = h.featureName, group = h.sub, hits = {} }
        byFeature[h.feature] = g
        groups[#groups + 1] = g
      end
      g.hits[#g.hits + 1] = h
      total = total + 1
    end
  end
  return { groups = groups, total = total }
end

-- Resolves a word typed after /fg einstellungen: a tab or a card by its id or its name in either language, an
-- old tab id. Returns { feature, card } or nil.
function SL.Resolve(word)
  return ns.SettingsFeatureLogic.Resolve(word, function(key, locale)
    return textOf(key, locale)
  end)
end
