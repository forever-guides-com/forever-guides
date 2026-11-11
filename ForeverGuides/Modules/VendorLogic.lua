-- Vendors for the professions, pure side (no frames, no game calls): turns the vendor data file
-- (ForeverGuides_Professions/VendorData.lua) into an index by NPC and by item, finds the sellers of an item
-- (faction, distance, price), builds the tooltip lines and filters and sorts the vendors for the page
-- (Modules/VendorsPage.lua). The game side (loading, zone names, player position) is Modules/VendorSource.lua.
local _, ns = ...

local V = {}
ns.VendorLogic = V

-- Sellers named in a tooltip line block, the rest is counted.
V.MAX_SELLERS = 3

-- Kinds of vendor in the order the page lists them: filter value, locale key part.
V.KINDS = { "g", "r", "m", "k", "x", "f", "d", "b", "p", "t" }

ns.AddLocale("enUS", {
  ["vendor.header"] = "Sold by:",
  ["vendor.line"] = "%s (%s): %s",
  ["vendor.lineNoPrice"] = "%s (%s)",
  ["vendor.stack"] = "%s for %d",
  ["vendor.limited"] = "limited stock",
  ["vendor.restricted"] = "needs standing or a quest",
  ["vendor.more"] = "and %d more",
  ["vendor.free"] = "free",
})
ns.AddLocale("deDE", {
  ["vendor.header"] = "Verkauft von:",
  ["vendor.line"] = "%s (%s): %s",
  ["vendor.lineNoPrice"] = "%s (%s)",
  ["vendor.stack"] = "%s für %d",
  ["vendor.limited"] = "begrenzter Vorrat",
  ["vendor.restricted"] = "braucht Ruf oder eine Quest",
  ["vendor.more"] = "und %d weitere",
  ["vendor.free"] = "gratis",
})

local function list(value)
  return type(value) == "table" and value or {}
end

local function whole(v, min)
  return type(v) == "number" and v >= min and v == math.floor(v) and v or nil
end

-- Flags of an offer (data: 1 limited stock, 2 conditional, 3 both).
function V.Limited(flags)
  return (flags or 0) % 2 == 1
end

function V.Restricted(flags)
  return (flags or 0) >= 2
end

-- True when bit i (from 1) of the mask is set.
function V.HasBit(mask, i)
  return type(mask) == "number" and math.floor(mask / 2 ^ (i - 1)) % 2 == 1
end

-- Index ---------------------------------------------------------------------------------------------

-- data: ForeverGuides.VendorData. Returns { list = entries by NPC id, byNpc, byItem = { [item id] = { { vendor,
-- offer } } }, bits = { [slug] = bit position } }. An entry: { npc, name, map, x, y (fractions of the map), faction,
-- kinds (letters), mask, zoneEn, offers = { { id, price, flags, count } } }. A row that is not well formed is skipped.
function V.Build(data)
  data = list(data)
  local index = { list = {}, byNpc = {}, byItem = {}, bits = {} }
  for i, slug in ipairs(list(data.professions)) do
    index.bits[slug] = i
  end
  local stacks, maps = list(data.stacks), list(data.maps)
  local ids = {}
  for npc, row in pairs(list(data.vendors)) do
    if whole(npc, 1) and type(row) == "table" then
      ids[#ids + 1] = npc
    end
  end
  table.sort(ids)
  for _, npc in ipairs(ids) do
    local row = data.vendors[npc]
    local x, y = tonumber(row[3]), tonumber(row[4])
    if type(row[1]) == "string" and whole(row[2], 1) and x and y and type(row[8]) == "table" then
      local entry = {
        npc = npc,
        name = row[1],
        map = row[2],
        x = x / 100,
        y = y / 100,
        faction = (row[5] == "A" or row[5] == "H") and row[5] or "B",
        kinds = type(row[6]) == "string" and row[6] or "",
        mask = tonumber(row[7]) or 0,
        zoneEn = type(maps[row[2]]) == "string" and maps[row[2]] ~= "" and maps[row[2]] or nil,
        offers = {},
      }
      local flat = row[8]
      for i = 1, #flat - 2, 3 do
        local id = whole(flat[i], 1)
        if id then
          local offer = { id = id, price = tonumber(flat[i + 1]) or 0, flags = tonumber(flat[i + 2]) or 0 }
          offer.count = whole(stacks[id], 2) or 1
          entry.offers[#entry.offers + 1] = offer
          local at = index.byItem[id]
          if not at then
            at = {}
            index.byItem[id] = at
          end
          at[#at + 1] = { vendor = entry, offer = offer }
        end
      end
      index.list[#index.list + 1] = entry
      index.byNpc[npc] = entry
    end
  end
  return index
end

-- Sellers --------------------------------------------------------------------------------------------

-- True when the faction (A, H, else everybody) may use the vendor (neutral vendors serve both).
function V.Allows(entry, faction)
  return (faction ~= "A" and faction ~= "H") or entry.faction == "B" or entry.faction == faction
end

local function better(a, b)
  local ra, rb = V.Restricted(a.offer.flags), V.Restricted(b.offer.flags)
  if ra ~= rb then
    return not ra
  end
  if (a.yards ~= nil) ~= (b.yards ~= nil) then
    return a.yards ~= nil
  end
  if a.yards and b.yards and a.yards ~= b.yards then
    return a.yards < b.yards
  end
  if a.offer.price ~= b.offer.price then
    return a.offer.price < b.offer.price
  end
  if a.vendor.name ~= b.vendor.name then
    return a.vendor.name < b.vendor.name
  end
  return a.vendor.npc < b.vendor.npc
end

-- The sellers of an item, best first: free of conditions, nearest (when from = { map, x, y } and
-- opts.distance(fromMap, fx, fy, toMap, tx, ty) give a distance), cheapest, by name. opts.faction (A or H)
-- drops the vendors of the other faction. Returns { { vendor, offer, yards } }, empty for an unknown item.
function V.Sellers(index, itemId, opts)
  opts = opts or {}
  local out = {}
  for _, row in ipairs(list(index and index.byItem[itemId])) do
    if V.Allows(row.vendor, opts.faction) then
      local yards
      if opts.from and opts.distance then
        local v = row.vendor
        yards = opts.distance(opts.from.map, opts.from.x, opts.from.y, v.map, v.x, v.y)
      end
      out[#out + 1] = { vendor = row.vendor, offer = row.offer, yards = yards }
    end
  end
  table.sort(out, better)
  return out
end

-- Text of the price of an offer: "20s", "20s for 5", "free" for none. money(copper) gives the coin text.
function V.PriceText(offer, money)
  local text = offer.price > 0 and money(offer.price) or nil
  if not text then
    return ns.L["vendor.free"]
  end
  if offer.count > 1 then
    text = string.format(ns.L["vendor.stack"], text, offer.count)
  end
  return text
end

-- Notes behind a line of a seller: limited stock, conditions.
local function notes(offer)
  local out = {}
  if V.Limited(offer.flags) then
    out[#out + 1] = ns.L["vendor.limited"]
  end
  if V.Restricted(offer.flags) then
    out[#out + 1] = ns.L["vendor.restricted"]
  end
  return #out > 0 and (" (" .. table.concat(out, ", ") .. ")") or ""
end

-- Text line of one seller: "Name (Zone): price (notes)". ctx.zone(entry) names the zone, ctx.money(copper) the coins.
function V.SellerText(seller, ctx)
  local zone = ctx.zone(seller.vendor) or "?"
  return string.format(ns.L["vendor.line"], seller.vendor.name, zone, V.PriceText(seller.offer, ctx.money))
    .. notes(seller.offer)
end

-- Tooltip lines of the sellers: the header, up to MAX_SELLERS lines, "and n more". nil without a seller.
function V.Lines(sellers, ctx)
  if #sellers == 0 then
    return nil
  end
  local lines = { ns.L["vendor.header"] }
  for i, seller in ipairs(sellers) do
    if i > V.MAX_SELLERS then
      lines[#lines + 1] = string.format(ns.L["vendor.more"], #sellers - V.MAX_SELLERS)
      break
    end
    lines[#lines + 1] = V.SellerText(seller, ctx)
  end
  return lines
end

-- Page ----------------------------------------------------------------------------------------------

-- True when the vendor sells something for the profession slug (bit of the mask).
function V.ForProfession(entry, index, slug)
  local bit = index.bits[slug]
  return bit ~= nil and V.HasBit(entry.mask, bit)
end

-- True when the vendor has the kind letter (V.KINDS).
function V.HasKind(entry, kind)
  return entry.kinds:find(kind, 1, true) ~= nil
end

-- The text a search compares: name, zone names and the names of the offers (f.zoneText(entry), f.itemName(id)).
local function haystack(entry, f)
  local parts = { entry.name, entry.zoneEn or "" }
  if f.zoneText then
    parts[#parts + 1] = f.zoneText(entry) or ""
  end
  if f.itemName then
    for _, offer in ipairs(entry.offers) do
      parts[#parts + 1] = f.itemName(offer.id) or ""
    end
  end
  return table.concat(parts, " ")
end

-- f: index, slug (profession, else all), kind (letter, else all), faction (A or H, else all), query (every word has
-- to occur), match(text, word), zoneText(entry), itemName(id).
function V.Filter(entries, f)
  f = f or {}
  local words = ns.TrainerSearchLogic.Words(f.query)
  local out = {}
  for _, e in ipairs(list(entries)) do
    local ok = V.Allows(e, f.faction)
      and (f.slug == nil or f.slug == "all" or (f.index and V.ForProfession(e, f.index, f.slug)))
      and (f.kind == nil or f.kind == "all" or V.HasKind(e, f.kind))
    if ok and #words > 0 then
      ok = ns.TrainerSearchLogic.MatchAll(haystack(e, f), words, f.match)
    end
    if ok then
      out[#out + 1] = e
    end
  end
  return out
end

local FACTION_ORDER = { A = 1, H = 2, B = 3 }

-- In place: by zone name (zoneKey(entry), default the English name), faction, name, NPC id.
function V.Sort(entries, zoneKey)
  zoneKey = zoneKey or function(e)
    return e.zoneEn or ""
  end
  local keys = {}
  for _, e in ipairs(entries) do
    keys[e] = tostring(zoneKey(e) or "")
  end
  table.sort(entries, function(a, b)
    if keys[a] ~= keys[b] then
      return keys[a] < keys[b]
    end
    if a.faction ~= b.faction then
      return FACTION_ORDER[a.faction] < FACTION_ORDER[b.faction]
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.npc < b.npc
  end)
  return entries
end

-- { vendors, offers } counted over a list of entries.
function V.Count(entries)
  local offers = 0
  for _, e in ipairs(entries) do
    offers = offers + #e.offers
  end
  return #entries, offers
end

-- The place the Map and Waypoint buttons act on: { map, x, y, label, zone }.
function V.Place(entry, zoneName)
  return { map = entry.map, x = entry.x, y = entry.y, label = entry.name, zone = zoneName }
end
