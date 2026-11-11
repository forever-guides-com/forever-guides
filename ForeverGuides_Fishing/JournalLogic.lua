-- What the catch journal shows, as plain tables: the fish with their counts, the places with the fish caught
-- there, the figures per fish and place, search and sort. Pure: the journal data and the names come in, rows
-- come out. Shares and rates are computed here and never stored.
local _, fish = ...
if not fish.FG then
  return
end

local J = {}
fish.JournalLogic = J

J.FISH_SORTS = { "name", "count", "last", "places" }
J.PLACE_SORTS = { "name", "count", "last", "kinds" }

-- Search -----------------------------------------------------------------------------------------------------------

-- Letters with marks fold to the plain letter, so "Muräne" is found by "murane" and "Maräne" by "marane".
local FOLD = {
  ["ä"] = "a",
  ["Ä"] = "a",
  ["ö"] = "o",
  ["Ö"] = "o",
  ["ü"] = "u",
  ["Ü"] = "u",
  ["ß"] = "ss",
  ["à"] = "a",
  ["á"] = "a",
  ["â"] = "a",
  ["ã"] = "a",
  ["å"] = "a",
  ["À"] = "a",
  ["Á"] = "a",
  ["Â"] = "a",
  ["è"] = "e",
  ["é"] = "e",
  ["ê"] = "e",
  ["ë"] = "e",
  ["È"] = "e",
  ["É"] = "e",
  ["Ê"] = "e",
  ["Ë"] = "e",
  ["ì"] = "i",
  ["í"] = "i",
  ["î"] = "i",
  ["ï"] = "i",
  ["Ì"] = "i",
  ["Í"] = "i",
  ["Î"] = "i",
  ["Ï"] = "i",
  ["ò"] = "o",
  ["ó"] = "o",
  ["ô"] = "o",
  ["õ"] = "o",
  ["Ò"] = "o",
  ["Ó"] = "o",
  ["Ô"] = "o",
  ["Õ"] = "o",
  ["ù"] = "u",
  ["ú"] = "u",
  ["û"] = "u",
  ["Ù"] = "u",
  ["Ú"] = "u",
  ["Û"] = "u",
  ["ç"] = "c",
  ["Ç"] = "c",
  ["ñ"] = "n",
  ["Ñ"] = "n",
  ["ý"] = "y",
  ["ÿ"] = "y",
  ["Ý"] = "y",
  ["\194\160"] = " ",
  ["\226\128\131"] = " ",
  ["\226\128\137"] = " ",
}

-- Lower case, marks folded, odd spaces turned into spaces.
function J.Fold(text)
  if type(text) ~= "string" then
    return ""
  end
  local out = text:gsub("[\194-\244][\128-\191]*", function(char)
    return FOLD[char]
  end)
  return out:lower()
end

-- The words of a search text (folded, split at spaces).
function J.Words(query)
  local words = {}
  for word in J.Fold(query):gmatch("%S+") do
    words[#words + 1] = word
  end
  return words
end

-- True when every word is somewhere in the text (all words, part of a word is enough).
function J.Matches(words, haystack)
  for _, word in ipairs(words) do
    if not haystack:find(word, 1, true) then
      return false
    end
  end
  return true
end

-- Figures ----------------------------------------------------------------------------------------------------------

-- A share in percent with one decimal, nil when there is nothing to divide by.
function J.Percent(part, total)
  if type(part) ~= "number" or type(total) ~= "number" or total <= 0 then
    return nil
  end
  return math.min(100, math.floor(part / total * 1000 + 0.5) / 10)
end

-- hits out of casts in percent, nil without a cast.
function J.Rate(hits, casts)
  return J.Percent(hits, casts)
end

-- The length of a bar as a fraction 0..1 for a share in percent (nil share: an empty bar). A bar is always the true
-- share, 100 % is a full bar.
function J.Fraction(share)
  if type(share) ~= "number" or share <= 0 then
    return 0
  end
  return math.min(1, share / 100)
end

-- The least a bar that has anything in it shows, in pixels, so that a small share is still seen.
J.MIN_BAR_PX = 1

-- Pixels of a bar of `width` for a share in percent: whole pixels, 0 for an empty bar, never wider than the bar and
-- never narrower than J.MIN_BAR_PX unless the bar itself is narrower.
function J.BarWidth(share, width)
  if type(width) ~= "number" or width <= 0 then
    return 0
  end
  local fraction = J.Fraction(share)
  if fraction == 0 then
    return 0
  end
  return math.min(width, math.max(J.MIN_BAR_PX, math.floor(width * fraction + 0.5)))
end

-- The best places of a place list (rows as J.FishPlaces gives them), at most `count`.
function J.Top(rows, count)
  local out = {}
  for index = 1, math.min(count or 3, #rows) do
    out[index] = rows[index]
  end
  return out
end

-- Names ------------------------------------------------------------------------------------------------------------

local function unknownName()
  local L = fish.FG.L
  return L and L["fishing.fish.unknown"] or "?"
end

-- The stored name goes along: it is the client name from an earlier session, better than a stand-in.
local function itemName(item, id, names)
  local live = names and names.item and names.item(id, item and item.nm) or nil
  if type(live) == "string" and live ~= "" then
    return live
  end
  if item and item.nm then
    return item.nm
  end
  return nil
end

local function placeName(ledger, key, names)
  local live = names and names.place and names.place(key) or nil
  if type(live) == "string" and live ~= "" then
    return live
  end
  local zone = ledger.zones[key]
  if zone and zone.nm then
    return zone.nm
  end
  if type(key) == "string" and key:sub(1, 1) == "n" then
    return key:sub(2)
  end
  return nil
end

J.ItemName, J.PlaceName = itemName, placeName

-- Sorting ----------------------------------------------------------------------------------------------------------

local function byText(a, b)
  if a.fold ~= b.fold then
    return a.fold < b.fold
  end
  return a.sortKey < b.sortKey
end

-- Orders rows by the sort key. name: A to Z. The other keys: the larger value first, ties by name.
local function order(rows, sort, field)
  table.sort(rows, function(a, b)
    if sort ~= "name" then
      local x, y = a[field[sort]] or 0, b[field[sort]] or 0
      if x ~= y then
        return x > y
      end
    end
    return byText(a, b)
  end)
end

local FISH_FIELD = { count = "n", last = "last", places = "places" }
local PLACE_FIELD = { count = "n", last = "last", kinds = "kinds" }

-- Fish --------------------------------------------------------------------------------------------------------------

-- The fish of a ledger as rows. opts: query (text), sort (one of J.FISH_SORTS), place (a place key: only fish
-- caught there, n counts that place), names = { item = function(id), place = function(key) }.
function J.Fish(ledger, opts)
  opts = opts or {}
  local words = J.Words(opts.query)
  local rows = {}
  -- The bar of a row is its share of all catches, or of the catches at the place when a place is chosen.
  local whole = 0
  if opts.place then
    whole = ledger.zones[opts.place] and ledger.zones[opts.place].n or 0
  else
    for _, item in pairs(ledger.items) do
      whole = whole + item.n
    end
  end
  for id, item in pairs(ledger.items) do
    local at = opts.place and item.zones[opts.place] or nil
    if not opts.place or at then
      local name = itemName(item, id, opts.names)
      local text = { J.Fold(name or unknownName()) }
      local places, top, topN = 0, nil, -1
      for key, zone in pairs(item.zones) do
        places = places + 1
        local label = placeName(ledger, key, opts.names)
        text[#text + 1] = J.Fold(label or "")
        if zone.n > topN or (zone.n == topN and tostring(key) < tostring(top)) then
          top, topN = key, zone.n
        end
      end
      if J.Matches(words, table.concat(text, " ")) then
        rows[#rows + 1] = {
          id = id,
          name = name or unknownName(),
          known = name ~= nil,
          n = at and at.n or item.n,
          share = J.Percent(at and at.n or item.n, whole),
          total = item.n,
          first = item.first,
          last = at and at.last or item.last,
          best = at and at.best or item.best,
          places = places,
          top = top,
          topName = top and placeName(ledger, top, opts.names) or nil,
          fold = J.Fold(name or unknownName()),
          sortKey = id,
        }
      end
    end
  end
  local placeLabel = opts.place and placeName(ledger, opts.place, opts.names) or nil
  for _, row in ipairs(rows) do
    row.whole = whole
    row.placeName = placeLabel
    -- The bar is the share of the percent column, on the same base.
    row.bar = row.share or 0
  end
  order(rows, opts.sort or "name", FISH_FIELD)
  return rows
end

-- The places of one fish: where it was caught, how much, which share of all catches there (share) and which share
-- of the catches of this fish happened there (ofFish), the best session and the last time. Most first, ties by
-- name. Plus the share of all catches of the ledger as "share" and the number of places as "kinds".
function J.FishPlaces(ledger, id, names)
  local item = ledger.items[id]
  if not item then
    return nil
  end
  local rows = {}
  for key, at in pairs(item.zones) do
    local zone = ledger.zones[key]
    local name = placeName(ledger, key, names)
    rows[#rows + 1] = {
      key = key,
      name = name or "?",
      n = at.n,
      share = J.Percent(at.n, zone and zone.n or 0),
      ofFish = J.Percent(at.n, item.n),
      best = at.best,
      last = at.last,
      fold = J.Fold(name or "?"),
      sortKey = key,
    }
  end
  table.sort(rows, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return byText(a, b)
  end)
  local all = 0
  for _, other in pairs(ledger.items) do
    all = all + other.n
  end
  return {
    id = id,
    name = itemName(item, id, names) or unknownName(),
    n = item.n,
    share = J.Percent(item.n, all),
    kinds = #rows,
    first = item.first,
    last = item.last,
    best = item.best,
    places = rows,
  }
end

-- Places -----------------------------------------------------------------------------------------------------------

-- The places of a ledger as rows. opts: query (place name or a fish caught there), sort (J.PLACE_SORTS), names.
function J.Places(ledger, opts)
  opts = opts or {}
  local words = J.Words(opts.query)
  local fishAt = {}
  for id, item in pairs(ledger.items) do
    for key in pairs(item.zones) do
      local list = fishAt[key] or {}
      fishAt[key] = list
      list[#list + 1] = J.Fold(itemName(item, id, opts.names) or "")
    end
  end
  local rows = {}
  for key, zone in pairs(ledger.zones) do
    -- A place that only has casts and no catch yet is listed too: the journal shows where the line was out.
    local name = placeName(ledger, key, opts.names)
    local list = fishAt[key] or {}
    local text = J.Fold(name or "") .. " " .. table.concat(list, " ")
    if J.Matches(words, text) then
      rows[#rows + 1] = {
        key = key,
        name = name or "?",
        n = zone.n,
        casts = zone.casts,
        hits = zone.hits,
        rate = J.Rate(zone.hits, zone.casts),
        -- The catch rate itself is the length of the bar, 100 % is a full bar.
        bar = J.Rate(zone.hits, zone.casts),
        last = zone.last,
        kinds = #list,
        fold = J.Fold(name or "?"),
        sortKey = key,
      }
    end
  end
  order(rows, opts.sort or "name", PLACE_FIELD)
  return rows
end

-- The fish of one place with count, share of the catches there, best session and last time.
function J.PlaceFish(ledger, key, names)
  local zone = ledger.zones[key]
  if not zone then
    return nil
  end
  local rows = {}
  for id, item in pairs(ledger.items) do
    local at = item.zones[key]
    if at then
      local name = itemName(item, id, names)
      rows[#rows + 1] = {
        id = id,
        name = name or unknownName(),
        n = at.n,
        share = J.Percent(at.n, zone.n),
        best = at.best,
        last = at.last,
        fold = J.Fold(name or unknownName()),
        sortKey = id,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return byText(a, b)
  end)
  return {
    key = key,
    name = placeName(ledger, key, names) or "?",
    n = zone.n,
    casts = zone.casts,
    hits = zone.hits,
    rate = J.Rate(zone.hits, zone.casts),
    last = zone.last,
    kinds = #rows,
    fish = rows,
  }
end

-- Keys -------------------------------------------------------------------------------------------------------------

-- The next value of a list after `current` (the first one when current is not in it).
function J.Next(list, current)
  for index, value in ipairs(list) do
    if value == current then
      return list[index % #list + 1]
    end
  end
  return list[1]
end

-- The row selected after a navigation key. count rows, page = rows per page. Returns the same index for a key
-- that is no navigation key, and 0 when there are no rows.
function J.Move(index, count, key, page)
  if count <= 0 then
    return 0
  end
  index = math.max(1, math.min(count, index or 1))
  page = math.max(1, page or 1)
  if key == "UP" then
    return math.max(1, index - 1)
  elseif key == "DOWN" then
    return math.min(count, index + 1)
  elseif key == "PAGEUP" then
    return math.max(1, index - page)
  elseif key == "PAGEDOWN" then
    return math.min(count, index + page)
  elseif key == "HOME" then
    return 1
  elseif key == "END" then
    return count
  end
  return index
end
