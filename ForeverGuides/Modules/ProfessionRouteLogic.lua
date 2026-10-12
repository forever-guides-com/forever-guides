-- Profession routes, pure side (no frames, no game calls): own professions to route slugs, the
-- step for a skill, progress, the reagent sums of a skill range with surcharge and stock, grouping
-- by source, costs and the two text formats (import line, plain list). The data shape is
-- in docs/BERUFSROUTE-FORMAT.md, the game side is Modules/ProfessionShop.lua.
local _, ns = ...

local R = {}
ns.ProfessionRouteLogic = R

-- Route slugs of the website, in the order the page lists them.
R.SLUGS = {
  "alchemy",
  "blacksmithing",
  "cooking",
  "enchanting",
  "engineering",
  "first-aid",
  "fishing",
  "herbalism",
  "leatherworking",
  "mining",
  "skinning",
  "tailoring",
}

-- Names in both client languages and the base skill line id the client reports.
R.PROFESSIONS = {
  alchemy = { en = "Alchemy", de = "Alchemie", id = 171 },
  blacksmithing = { en = "Blacksmithing", de = "Schmiedekunst", id = 164 },
  cooking = { en = "Cooking", de = "Kochkunst", id = 185 },
  enchanting = { en = "Enchanting", de = "Verzauberkunst", id = 333 },
  engineering = { en = "Engineering", de = "Ingenieurskunst", id = 202 },
  ["first-aid"] = { en = "First Aid", de = "Erste Hilfe", id = 129 },
  fishing = { en = "Fishing", de = "Angeln", id = 356 },
  herbalism = { en = "Herbalism", de = "Kräuterkunde", id = 182 },
  leatherworking = { en = "Leatherworking", de = "Lederverarbeitung", id = 165 },
  mining = { en = "Mining", de = "Bergbau", id = 186 },
  skinning = { en = "Skinning", de = "Kürschnerei", id = 393 },
  tailoring = { en = "Tailoring", de = "Schneiderei", id = 197 },
}

-- Order of the source groups in lists and exports.
R.GROUPS = { "vendor", "auction", "gather", "craft" }
R.DEFAULT_SOURCE = "auction"
R.DEFAULT_SURCHARGE = 10
R.MAX_SURCHARGE = 100
R.MAX_SKILL = 1000
R.CALLER = "ForeverGuides"

local BY_NAME, BY_ID, GROUP_SET = {}, {}, {}
for slug, p in pairs(R.PROFESSIONS) do
  BY_NAME[p.en:lower()] = slug
  BY_NAME[p.de:lower()] = slug
  BY_ID[p.id] = slug
end
for _, g in ipairs(R.GROUPS) do
  GROUP_SET[g] = true
end

-- Slugs ---------------------------------------------------------------------------------------

-- Slug of a profession row { name, id } (see ProfessionLogic), nil for a profession without a route.
function R.SlugOf(p)
  if type(p) ~= "table" then
    return nil
  end
  if type(p.name) == "string" and BY_NAME[p.name:lower()] then
    return BY_NAME[p.name:lower()]
  end
  return type(p.id) == "number" and BY_ID[p.id] or nil
end

-- A slug or a profession name in either language ("alchemie", "First Aid") to the slug.
function R.SlugFromText(text)
  text = type(text) == "string" and ns.U.trim(text):lower() or ""
  if R.PROFESSIONS[text] then
    return text
  end
  return BY_NAME[text] or BY_NAME[text:gsub("%-", " ")]
end

-- Display name of a slug in the active language.
function R.Name(slug)
  local p = R.PROFESSIONS[slug]
  return p and ns.T({ de = p.de, en = p.en }) or tostring(slug)
end

-- The professions of the character that have a route: { slug, name, skill, max } in list order,
-- one entry per slug.
function R.OwnRoutes(list)
  local out, seen = {}, {}
  for _, p in ipairs(type(list) == "table" and list or {}) do
    local slug = R.SlugOf(p)
    if slug and not seen[slug] then
      seen[slug] = true
      out[#out + 1] = { slug = slug, name = p.name, skill = tonumber(p.skill) or 0, max = tonumber(p.max) or 0 }
    end
  end
  return out
end

-- A whole number in 0..max, nil for anything else.
function R.Whole(v, max)
  v = tonumber(v)
  if not v or v ~= v or v < 0 or v > (max or R.MAX_SKILL) then
    return nil
  end
  return math.floor(v)
end

-- Steps ---------------------------------------------------------------------------------------

local function stepsOf(data)
  return type(data) == "table" and type(data.steps) == "table" and data.steps or {}
end

-- "done" once the skill has reached the end of the step, "current" for the first step that is not
-- done, "open" after it.
function R.Status(step, skill, isFirstOpen)
  if skill >= (tonumber(step.to) or 0) then
    return "done"
  end
  return isFirstOpen and "current" or "open"
end

-- Every step with its status: { step, i, status }. A skill at or above the last step leaves no
-- current step.
function R.Steps(data, skill)
  skill = R.Whole(skill) or 0
  local out, currentSeen = {}, false
  for i, step in ipairs(stepsOf(data)) do
    local firstOpen = not currentSeen and skill < (tonumber(step.to) or 0)
    if firstOpen then
      currentSeen = true
    end
    out[#out + 1] = { step = step, i = i, status = R.Status(step, skill, firstOpen) }
  end
  return out
end

-- Index of the current step, nil without steps or when the route is finished.
function R.CurrentIndex(data, skill)
  for _, e in ipairs(R.Steps(data, skill)) do
    if e.status == "current" then
      return e.i
    end
  end
  return nil
end

-- Progress: { frac 0..1 of the route maximum, done steps, total steps, current index or nil }.
function R.Progress(data, skill)
  skill = R.Whole(skill) or 0
  local steps = R.Steps(data, skill)
  local done, current = 0, nil
  for _, e in ipairs(steps) do
    if e.status == "done" then
      done = done + 1
    elseif e.status == "current" then
      current = e.i
    end
  end
  local max = tonumber(type(data) == "table" and data.max) or 0
  return { frac = max > 0 and math.min(1, skill / max) or 0, done = done, total = #steps, current = current }
end

-- The steps that lie in the skill range from..to, each with the number of crafts that range needs:
-- a step the range only touches counts in proportion, rounded up. { step, i, crafts }.
function R.Range(data, from, to)
  from = R.Whole(from) or 0
  to = R.Whole(to) or R.MAX_SKILL
  local out = {}
  for i, step in ipairs(stepsOf(data)) do
    local a, b = tonumber(step.from) or 0, tonumber(step.to) or 0
    local lo, hi = math.max(a, from), math.min(b, to)
    if hi > lo or (a == b and a >= from and a <= to) then
      local crafts = tonumber(step.crafts) or 0
      if b > a and (lo > a or hi < b) then
        crafts = math.ceil(crafts * (hi - lo) / (b - a))
      end
      out[#out + 1] = { step = step, i = i, crafts = crafts }
    end
  end
  return out
end

-- Needs ---------------------------------------------------------------------------------------

local function item(data, id)
  local items = type(data) == "table" and type(data.items) == "table" and data.items or {}
  return type(items[id]) == "table" and items[id] or {}
end

-- A surcharge in percent, whole, 0..MAX_SURCHARGE, the default for anything else.
function R.Surcharge(v)
  local n = R.Whole(v, R.MAX_SURCHARGE)
  if n == nil then
    return R.DEFAULT_SURCHARGE
  end
  return n
end

local function sortName(line)
  return (line.name or ""):lower()
end

-- Sum of the reagents of the skill range from..to.
-- opts: surcharge (percent on top, default 10), stock { [itemId] = count } taken off afterwards,
-- auctionPrice(itemId) -> copper or nil for items bought at the auction house.
-- Returns the lines { id, name, icon, q, source, need, have, qty, price, total } (only items with
-- qty > 0, sorted by name) and the number of items the stock covers completely.
function R.Needs(data, from, to, opts)
  opts = opts or {}
  local pct = R.Surcharge(opts.surcharge)
  local raw, order = {}, {}
  for _, e in ipairs(R.Range(data, from, to)) do
    for _, m in ipairs(type(e.step.mats) == "table" and e.step.mats or {}) do
      local id, qty = tonumber(m[1]), tonumber(m[2])
      if id and qty and qty > 0 then
        if not raw[id] then
          raw[id] = 0
          order[#order + 1] = id
        end
        raw[id] = raw[id] + e.crafts * qty
      end
    end
  end
  local stock = type(opts.stock) == "table" and opts.stock or {}
  local lines, covered = {}, 0
  for _, id in ipairs(order) do
    local info = item(data, id)
    -- Whole numbers only: n * (100 + pct) / 100 has no float noise for integers.
    local need = math.ceil(raw[id] * (100 + pct) / 100)
    local have = math.min(need, math.max(0, math.floor(tonumber(stock[id]) or 0)))
    local qty = need - have
    if qty > 0 then
      local source = GROUP_SET[info.buy] and info.buy or R.DEFAULT_SOURCE
      local price
      if source == "vendor" then
        price = tonumber(info.price)
      elseif source == "auction" and type(opts.auctionPrice) == "function" then
        price = tonumber(opts.auctionPrice(id))
      end
      if price and price <= 0 then
        price = nil
      end
      lines[#lines + 1] = {
        id = id,
        name = ns.T({ de = info.de, en = info.en }) or ("item:" .. id),
        de = info.de,
        en = info.en,
        icon = info.icon,
        q = info.q,
        source = source,
        need = need,
        have = have,
        qty = qty,
        price = price,
        total = price and price * qty or nil,
      }
    else
      covered = covered + 1
    end
  end
  table.sort(lines, function(a, b)
    local an, bn = sortName(a), sortName(b)
    if an ~= bn then
      return an < bn
    end
    return a.id < b.id
  end)
  return lines, covered
end

-- The lines by source in the order of R.GROUPS, empty groups left out:
-- { source, lines, total (copper of the priced lines), unpriced (lines without a price, only for the
-- sources that can be priced) }.
function R.Group(lines)
  local by = {}
  for _, line in ipairs(lines or {}) do
    local g = by[line.source]
    if not g then
      g = { source = line.source, lines = {}, total = 0, unpriced = 0 }
      by[line.source] = g
    end
    g.lines[#g.lines + 1] = line
    if line.total then
      g.total = g.total + line.total
    elseif line.source == "vendor" or line.source == "auction" then
      g.unpriced = g.unpriced + 1
    end
  end
  local out = {}
  for _, source in ipairs(R.GROUPS) do
    if by[source] then
      out[#out + 1] = by[source]
    end
  end
  return out
end

-- Total copper of the groups and the number of lines that had no price.
function R.Cost(groups)
  local total, unpriced = 0, 0
  for _, g in ipairs(groups or {}) do
    total = total + g.total
    unpriced = unpriced + g.unpriced
  end
  return total, unpriced
end

-- Stock -----------------------------------------------------------------------------------------

-- Item counts { [itemId] = n } over the inventory snapshots of ns.InventoryLogic (bags, bank,
-- equipment, mail; the account bank counts once). keys: the character keys to count; withAccount adds
-- the account bank.
function R.Stock(inventory, keys, withAccount)
  local Inv = ns.InventoryLogic
  local out = {}
  local function add(snap, areas)
    for _, area in ipairs(areas) do
      local tally = type(snap) == "table" and snap[area]
      for id, n in pairs(type(tally) == "table" and tally or {}) do
        if type(id) == "number" and type(n) == "number" and n > 0 then
          out[id] = (out[id] or 0) + n
        end
      end
    end
  end
  local own = {}
  for _, area in ipairs(Inv.AREAS) do
    if area ~= Inv.ACCOUNT_AREA then
      own[#own + 1] = area
    end
  end
  inventory = type(inventory) == "table" and inventory or {}
  for _, key in ipairs(keys or {}) do
    add(inventory[key], own)
  end
  if withAccount then
    add(inventory[Inv.ACCOUNT_KEY], { Inv.ACCOUNT_AREA })
  end
  return out
end

-- Texts -----------------------------------------------------------------------------------------

-- Characters that would end a search string or a list in the import line format.
local function cleanName(name)
  return (tostring(name or ""):gsub('[;"^\r\n]', " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end
R.CleanName = cleanName

-- Search string of one item in the format of the import line: the fields joined by ";" are the name (in quotes for an exact match),
-- category, item level from/to, level from/to, crafted level from/to, price from/to, quality, tier
-- ("#" when empty), expansion and quantity.
function R.SearchString(name, qty)
  local fields = { '"' .. cleanName(name) .. '"' }
  for i = 2, 11 do
    fields[i] = ""
  end
  fields[12] = "#"
  fields[13] = ""
  fields[14] = qty and qty > 0 and tostring(math.floor(qty)) or ""
  return table.concat(fields, ";")
end

-- The search string of an item: through the converter of the connected addon when given (convert(term) ->
-- string, may fail), else built by hand.
function R.Search(name, qty, convert)
  if type(convert) == "function" then
    local ok, res = pcall(convert, { searchString = cleanName(name), isExact = true, quantity = qty })
    if ok and type(res) == "string" and res ~= "" then
      return res
    end
  end
  return R.SearchString(name, qty)
end

-- The lines that are not ticked off yet.
function R.Pending(lines, checked)
  local out = {}
  for _, line in ipairs(lines or {}) do
    if not (type(checked) == "table" and checked[line.id]) then
      out[#out + 1] = line
    end
  end
  return out
end

-- The lines worth sending to the auction house: not bought at a vendor, not ticked off.
function R.Wanted(lines, checked)
  local out = {}
  for _, line in ipairs(lines or {}) do
    if line.source ~= "vendor" and not (type(checked) == "table" and checked[line.id]) then
      out[#out + 1] = line
    end
  end
  return out
end

-- Name of a shopping list: "Forever Guides <profession> <from>-<to>", no characters the import breaks on.
function R.ListName(professionName, from, to)
  return cleanName(string.format("Forever Guides %s %d-%d", professionName or "", from or 0, to or 0))
end

-- The search strings of the wanted lines; nameOf(line) gives the name the client knows the item by.
function R.Searches(lines, checked, convert, nameOf)
  local out = {}
  for _, line in ipairs(R.Wanted(lines, checked)) do
    out[#out + 1] = R.Search(type(nameOf) == "function" and nameOf(line) or line.name, line.qty, convert)
  end
  return out
end

-- One line in the format of the import box: list name and search strings joined by "^".
function R.ImportText(listName, searches)
  return cleanName(listName) .. "^" .. table.concat(searches or {}, "^")
end

local function money(copper)
  return ns.CostLogic.Format(copper, { plain = true })
end

-- Plain shopping list: a heading per source, "<qty>x <name>" with the price when known.
-- opts: checked { [itemId] = true } marks ticked lines with "[x]", title, groupTitle(source).
function R.ListText(groups, opts)
  opts = opts or {}
  local out = {}
  if opts.title then
    out[#out + 1] = opts.title
  end
  for _, g in ipairs(groups or {}) do
    out[#out + 1] = (opts.groupTitle and opts.groupTitle(g.source) or g.source) .. ":"
    for _, line in ipairs(g.lines) do
      local text =
        string.format("%s%dx %s", (opts.checked and opts.checked[line.id]) and "[x] " or "", line.qty, line.name)
      local price = line.total and money(line.total)
      out[#out + 1] = price and (text .. " (" .. price .. ")") or text
    end
  end
  return table.concat(out, "\n")
end
