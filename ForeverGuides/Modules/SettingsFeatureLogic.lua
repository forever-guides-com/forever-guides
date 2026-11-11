-- Rules for the settings features (Modules/SettingsFeatures.lua): resolving a feature, a card or a
-- word to its place, the aliases of the old tab ids and the width check of the tab rows. Pure
-- logic, no game API. `data` is the registry table; it defaults to ns.SettingsFeatures.
local _, ns = ...

local L = {}
ns.SettingsFeatureLogic = L

-- A row of tabs holds at most this many buttons and a feature name at most this many characters.
L.MAX_PER_ROW = 8
L.MAX_NAME = 26
-- Width model of a tab button: characters times CHAR, PAD around the text, GAP between two
-- buttons. The game measures the real text; this model is for the registry test.
L.CHAR, L.PAD, L.GAP = 6, 24, 8
-- Content width of the settings page in the default window (960 px) at font size 1.
L.DEFAULT_ROW = 744

local function registry(data)
  return data or ns.SettingsFeatures
end

local function fold(text)
  local out = ns.SearchLogic and ns.SearchLogic.fold(text) or tostring(text or ""):lower()
  return (out:gsub("[%s%-_%.]", ""))
end
L.fold = fold

-- Number of characters (UTF-8 aware).
function L.Chars(text)
  return select(2, tostring(text or ""):gsub("[^\128-\191]", ""))
end

-- Lookup tables, built once per registry table.
local cache = setmetatable({}, { __mode = "k" })

local function index(data)
  local hit = cache[data]
  if hit then
    return hit
  end
  local ix = { feature = {}, card = {}, cardFeature = {}, groupFeatures = {} }
  for _, group in ipairs(data.GROUPS) do
    ix.groupFeatures[group] = {}
  end
  for _, f in ipairs(data.FEATURES) do
    ix.feature[f.id] = f
    local list = ix.groupFeatures[f.group]
    if list then
      list[#list + 1] = f
    end
    for _, card in ipairs(f.cards or {}) do
      ix.card[card.id] = card
      ix.cardFeature[card.id] = f.id
    end
  end
  cache[data] = ix
  return ix
end

function L.Feature(id, data)
  return index(registry(data)).feature[id]
end

function L.Group(featureId, data)
  local f = index(registry(data)).feature[featureId]
  return f and f.group
end

-- Features of a group in tab order.
function L.GroupFeatures(group, data)
  return index(registry(data)).groupFeatures[group] or {}
end

-- The feature an id names: a feature id itself or the target of an old tab id. nil when unknown.
function L.ResolveFeature(id, data)
  data = registry(data)
  if type(id) ~= "string" then
    return nil
  end
  local ix = index(data)
  if ix.feature[id] then
    return id
  end
  local alias = data.ALIASES[id]
  return alias and ix.feature[alias] and alias or nil
end

-- Unknown ids mean the first feature, like the stored tab of the old page.
function L.FeatureOrFirst(id, data)
  data = registry(data)
  return L.ResolveFeature(id, data) or data.FEATURES[1].id
end

-- The feature of a card id. Dynamic cards (the consent functions) match by their prefix.
function L.CardFeature(cardId, data)
  data = registry(data)
  if type(cardId) ~= "string" then
    return nil
  end
  local owner = index(data).cardFeature[cardId]
  if owner then
    return owner
  end
  for _, f in ipairs(data.FEATURES) do
    if f.dynamic and cardId:sub(1, #f.dynamic) == f.dynamic and #cardId > #f.dynamic then
      return f.id
    end
  end
end

-- Feature and card of a jump, Select(feature or old tab id, card). The card id is the more exact
-- address and wins over a feature named next to it. A lone card id works as well.
function L.Target(featureId, cardId, data)
  data = registry(data)
  local byCard = cardId and L.CardFeature(cardId, data)
  if byCard then
    return byCard, cardId
  end
  local feature = L.ResolveFeature(featureId, data)
  if feature then
    return feature, nil
  end
  local owner = L.CardFeature(featureId, data)
  if owner then
    return owner, featureId
  end
end

-- The registry entry of a card, nil for a dynamic card.
function L.Card(cardId, data)
  return index(registry(data)).card[cardId]
end

-- Card ids of a feature in page order. planned = false leaves out cards no module builds yet.
function L.Cards(featureId, data, planned)
  local f = index(registry(data)).feature[featureId]
  local out = {}
  for _, card in ipairs(f and f.cards or {}) do
    if planned ~= false or not card.planned then
      out[#out + 1] = card.id
    end
  end
  return out
end

local function locales(data)
  return data.LOCALES or { "enUS", "deDE" }
end

-- Resolves a word of the player (an id or a name in either language, an old tab id, a card id or a card
-- title) to { feature, card } or nil. text(key, locale) answers the locale text.
function L.Resolve(word, text, data)
  data = registry(data)
  local ix = index(data)
  local key = fold(word)
  if key == "" then
    return nil
  end
  for _, f in ipairs(data.FEATURES) do
    if fold(f.id) == key then
      return { feature = f.id }
    end
  end
  for _, f in ipairs(data.FEATURES) do
    for _, locale in ipairs(locales(data)) do
      local name = text and text("settings.feature." .. f.id, locale)
      if name and fold(name) == key then
        return { feature = f.id }
      end
    end
  end
  for old, target in pairs(data.ALIASES) do
    if fold(old) == key and ix.feature[target] then
      return { feature = target }
    end
  end
  for _, f in ipairs(data.FEATURES) do
    for _, card in ipairs(f.cards or {}) do
      local match = fold(card.id) == key
      for _, locale in ipairs(locales(data)) do
        local title = card.titleKey and text and text(card.titleKey, locale)
        if title and fold(title) == key then
          match = true
        end
      end
      if match then
        return { feature = f.id, card = card.id }
      end
    end
  end
  return nil
end

-- Width of a row of labels: every label measured, padded and separated by a gap. opts.measure(label)
-- replaces the character model, opts.scale widens the text (font size).
function L.RowWidth(labels, opts)
  opts = opts or {}
  local measure = opts.measure or function(label)
    return L.Chars(label) * L.CHAR * (opts.scale or 1)
  end
  local total = 0
  for _, label in ipairs(labels) do
    total = total + measure(label) + (opts.pad or L.PAD)
  end
  return total + math.max(0, #labels - 1) * (opts.gap or L.GAP)
end

-- The rows of the page in one language: the groups, then the features of every group.
function L.Rows(text, locale, data)
  data = registry(data)
  local groups = {}
  for _, g in ipairs(data.GROUPS) do
    groups[#groups + 1] = text("settings.group." .. g, locale) or g
  end
  local rows = { { name = "groups", labels = groups } }
  for _, g in ipairs(data.GROUPS) do
    local labels = {}
    for _, f in ipairs(L.GroupFeatures(g, data)) do
      labels[#labels + 1] = text("settings.feature." .. f.id, locale) or f.id
    end
    rows[#rows + 1] = { name = g, labels = labels }
  end
  return rows
end

-- The widest row in both languages: { width, row, locale }.
function L.WidestRow(text, opts, data)
  data = registry(data)
  local best = { width = 0 }
  for _, locale in ipairs(locales(data)) do
    for _, row in ipairs(L.Rows(text, locale, data)) do
      local w = L.RowWidth(row.labels, opts)
      if w > best.width then
        best = { width = w, row = row.name, locale = locale }
      end
    end
  end
  return best
end

-- Whether the tab rows fit into `available` pixels. current is the mode now (true = rows); going
-- back to rows needs `hysteresis` pixels to spare, so the page does not flip at the border.
function L.RowsFit(widest, available, current, hysteresis)
  if current then
    return widest <= available
  end
  return widest + (hysteresis or 12) <= available
end

-- Problems of the registry as a list of texts, empty when it keeps the rules of the design: every
-- feature in a known group with a name and keywords in both languages, a unique id, every card
-- in exactly one feature, at most MAX_PER_ROW features per group and groups, names up to MAX_NAME
-- characters and no row wider than DEFAULT_ROW at font size 1.
function L.Validate(text, data)
  data = registry(data)
  local problems = {}
  local function bad(msg)
    problems[#problems + 1] = msg
  end
  local groups, features, cards = {}, {}, {}
  if #data.GROUPS > L.MAX_PER_ROW then
    bad("more than " .. L.MAX_PER_ROW .. " groups")
  end
  for _, g in ipairs(data.GROUPS) do
    groups[g] = 0
    for _, locale in ipairs(locales(data)) do
      for _, key in ipairs({ "settings.group." .. g, "settings.group." .. g .. ".long" }) do
        if not text(key, locale) then
          bad(locale .. " text missing: " .. key)
        end
      end
    end
  end
  for _, f in ipairs(data.FEATURES) do
    if features[f.id] then
      bad("duplicate feature " .. f.id)
    end
    features[f.id] = true
    if groups[f.group] == nil then
      bad("feature " .. f.id .. " has an unknown group")
    else
      groups[f.group] = groups[f.group] + 1
    end
    for _, locale in ipairs(locales(data)) do
      local name = text("settings.feature." .. f.id, locale)
      if not name then
        bad(locale .. " name missing: " .. f.id)
      elseif L.Chars(name) > L.MAX_NAME then
        bad(locale .. " name of " .. f.id .. " is longer than " .. L.MAX_NAME)
      end
      if not text("settings.feature." .. f.id .. ".keywords", locale) then
        bad(locale .. " text missing: settings.feature." .. f.id .. ".keywords")
      end
    end
    if #(f.cards or {}) == 0 and not f.dynamic then
      bad("feature " .. f.id .. " has no card")
    end
    for _, card in ipairs(f.cards or {}) do
      if cards[card.id] then
        bad("card " .. card.id .. " is in " .. cards[card.id] .. " and " .. f.id)
      end
      cards[card.id] = f.id
      for _, locale in ipairs(locales(data)) do
        if card.titleKey and not text(card.titleKey, locale) then
          bad(locale .. " title missing: " .. card.titleKey)
        end
      end
    end
  end
  for g, count in pairs(groups) do
    if count > L.MAX_PER_ROW then
      bad("group " .. g .. " has " .. count .. " features")
    end
    if count == 0 then
      bad("group " .. g .. " is empty")
    end
  end
  for old, target in pairs(data.ALIASES) do
    if not features[target] then
      bad("alias " .. old .. " points to unknown " .. target)
    end
  end
  local widest = L.WidestRow(text, nil, data)
  if widest.width > L.DEFAULT_ROW then
    bad(string.format("row %s (%s) is %d px wide", tostring(widest.row), tostring(widest.locale), widest.width))
  end
  return problems
end
