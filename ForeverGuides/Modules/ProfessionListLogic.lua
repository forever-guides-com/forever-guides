-- Pure side of the editable shopping list: the saved shape per character, its migration, own
-- positions, the edits of route lines (amount, removed), the lines of a plan with both applied and
-- the packed text that travels in a chat link. The game side is ProfessionList.lua.
--
-- ns.db.profRoute.list = {
--   [characterKey] = {
--     seq = 12,                                 -- counter for the order of adding
--     items = { { id, slug, qty, done, order, de, en, icon }, ... },   -- own positions
--     edits = { [slug] = { [itemId] = { qty, hidden } } },             -- changes to route lines
--     ticks = { [key] = true },                 -- ticked material rows, see PL.TickKey
--   },
-- }
-- ns.db.profRoute.v = 2 (1 = before the list: only opts and checked, both stay as they are).
local _, ns = ...
local R = ns.ProfessionRouteLogic

local PL = {}
ns.ProfessionListLogic = PL

PL.SCHEMA = 2
PL.MAX_QTY = 9999
PL.MAX_ITEMS = 200
PL.MAX_ID = 99999999
-- Crafting yourself resolves the materials of a crafted item, and the materials of those when they are
-- crafted too: this deep and this many derived lines at most.
PL.MAX_DEPTH = 4
PL.MAX_DERIVED = 200
-- Ticked material rows kept per character.
PL.MAX_TICKS = 2000

-- Values --------------------------------------------------------------------------------------

-- A whole amount 1..MAX_QTY, nil for anything else.
function PL.Qty(v)
  local n = tonumber(v)
  if not n or n ~= n or n < 1 then
    return nil
  end
  return math.min(math.floor(n), PL.MAX_QTY)
end

-- The amount to buy of a row: a whole number min..MAX_QTY, nil for anything else.
function PL.BuyQty(v, min)
  local n = tonumber(v)
  if not n or n ~= n or n < min then
    return nil
  end
  return math.min(math.floor(n), PL.MAX_QTY)
end

-- The lowest amount to buy of a row. With the stock subtracted a row the stock already covers (have above
-- 0) may go down to 0, its target is then what is there; otherwise the target would be 0, so 1 is the lowest.
function PL.MinQty(line, deduct)
  return deduct == true and (line.have or 0) > 0 and 0 or 1
end

-- A whole item id, nil for anything else.
function PL.Id(v)
  local n = tonumber(v)
  if not n or n ~= n or n < 1 or n > PL.MAX_ID or n ~= math.floor(n) then
    return nil
  end
  return n
end

-- Tick keys ---------------------------------------------------------------------------------------
--
-- A material row (a line that is derived from a crafted item) is ticked per occurrence, not per item
-- id: the same material under two reasons has two keys and ticks on its own. The key is the path of
-- item ids from the head down to the row, behind the origin of the head: "o:118/1/5" (own position 118,
-- material 1, its material 5) or "r:alchemy:4/1" (route line 4 of the alchemy route, material 1). Heads
-- and route lines keep their own tick (own flag, route tick per item id), only materials use these keys.

-- True for a well formed key.
function PL.TickKey(key)
  if type(key) ~= "string" or #key > 120 then
    return false
  end
  local path = key:match("^o:([%d/]+)$") or key:match("^r:[%a%-]+:([%d/]+)$")
  if not path then
    return false
  end
  for id in (path .. "/"):gmatch("([^/]*)/") do
    if not id:match("^%d+$") then
      return false
    end
  end
  return true
end

-- The key of the head of an own position and of a route line.
function PL.HeadKey(line, slug)
  if line.own then
    return "o:" .. line.id
  end
  return "r:" .. tostring(line.slug or slug or "") .. ":" .. line.id
end

-- Ticks or unticks a key of a character entry. Returns false when the key is refused (malformed, or the
-- limit is reached).
function PL.SetTick(chr, key, on)
  if not PL.TickKey(key) then
    return false
  end
  if not on then
    chr.ticks[key] = nil
    return true
  end
  if not chr.ticks[key] then
    local n = 0
    for _ in pairs(chr.ticks) do
      n = n + 1
    end
    if n >= PL.MAX_TICKS then
      return false
    end
  end
  chr.ticks[key] = true
  return true
end

-- Drops the ticks below an own position (it left the list).
function PL.DropTicks(chr, id)
  local head, below = "o:" .. id, "o:" .. id .. "/"
  for key in pairs(chr.ticks) do
    if key == head or key:sub(1, #below) == below then
      chr.ticks[key] = nil
    end
  end
end

-- Drops every tick of the materials of own positions and of the route of one profession (every tick of
-- the list for slug = nil).
function PL.ClearTicks(chr, slug)
  local route = slug and ("r:" .. slug .. ":")
  for key in pairs(chr.ticks) do
    if not route or key:sub(1, 2) == "o:" or key:sub(1, #route) == route then
      chr.ticks[key] = nil
    end
  end
end

-- Saved shape ------------------------------------------------------------------------------------

local function text(v)
  return type(v) == "string" and v ~= "" and v or nil
end

local function cleanItem(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local id, qty = PL.Id(raw.id), PL.Qty(raw.qty)
  if not (id and qty) then
    return nil
  end
  return {
    id = id,
    slug = type(raw.slug) == "string" and R.PROFESSIONS[raw.slug] and raw.slug or nil,
    qty = qty,
    done = raw.done == true,
    order = math.max(0, math.floor(tonumber(raw.order) or 0)),
    de = text(raw.de),
    en = text(raw.en),
    icon = text(raw.icon),
  }
end

local function cleanEdit(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out = { qty = PL.Qty(raw.qty), hidden = raw.hidden == true or nil }
  if out.qty or out.hidden then
    return out
  end
end

-- A clean copy of the saved entry of one character: damaged positions and edits are dropped, the
-- counter is raised above every order in use.
function PL.CleanChar(raw)
  local out = { seq = 0, items = {}, edits = {}, ticks = {} }
  if type(raw) ~= "table" then
    return out
  end
  local seen = {}
  for _, entry in ipairs(type(raw.items) == "table" and raw.items or {}) do
    local item = cleanItem(entry)
    if item and not seen[item.id] and #out.items < PL.MAX_ITEMS then
      seen[item.id] = true
      out.items[#out.items + 1] = item
      out.seq = math.max(out.seq, item.order)
    end
  end
  for slug, byId in pairs(type(raw.edits) == "table" and raw.edits or {}) do
    if type(slug) == "string" and type(byId) == "table" then
      for id, entry in pairs(byId) do
        local edit = PL.Id(id) and cleanEdit(entry)
        if edit then
          out.edits[slug] = out.edits[slug] or {}
          out.edits[slug][PL.Id(id)] = edit
        end
      end
    end
  end
  local n = 0
  for key, on in pairs(type(raw.ticks) == "table" and raw.ticks or {}) do
    if on == true and PL.TickKey(key) and n < PL.MAX_TICKS then
      out.ticks[key] = true
      n = n + 1
    end
  end
  out.seq = math.max(out.seq, math.floor(tonumber(raw.seq) or 0))
  return out
end

-- Brings the saved table of the profession route to the current schema, in place. Schema 1 held
-- only opts and checked: both stay untouched, the list is new. Returns the table.
function PL.Migrate(root)
  if type(root) ~= "table" then
    return root
  end
  local list = type(root.list) == "table" and root.list or {}
  for key, entry in pairs(list) do
    list[key] = type(key) == "string" and PL.CleanChar(entry) or nil
  end
  root.list = list
  root.v = math.max(tonumber(root.v) or 1, PL.SCHEMA)
  return root
end

-- Own positions ----------------------------------------------------------------------------------

-- The position with this item id, nil when there is none.
function PL.Find(chr, id)
  for index, item in ipairs(chr.items) do
    if item.id == id then
      return item, index
    end
  end
end

-- Adds an own position or raises the amount of the one with the same item. entry: { id, slug, de,
-- en, icon }. Returns the position and "added" | "raised", or nil and "limit" | "invalid".
function PL.AddItem(chr, entry, qty)
  local id = type(entry) == "table" and PL.Id(entry.id)
  if not id then
    return nil, "invalid"
  end
  qty = PL.Qty(qty) or 1
  local item = PL.Find(chr, id)
  if item then
    item.qty = math.min(item.qty + qty, PL.MAX_QTY)
    return item, "raised"
  end
  if #chr.items >= PL.MAX_ITEMS then
    return nil, "limit"
  end
  chr.seq = chr.seq + 1
  item = cleanItem({
    id = id,
    slug = entry.slug,
    qty = qty,
    order = chr.seq,
    de = entry.de,
    en = entry.en,
    icon = entry.icon,
  })
  chr.items[#chr.items + 1] = item
  return item, "added"
end

-- The change record of a route line, created when missing.
function PL.Edit(chr, slug, id)
  chr.edits[slug] = chr.edits[slug] or {}
  chr.edits[slug][id] = chr.edits[slug][id] or {}
  return chr.edits[slug][id]
end

-- Drops an empty change record and an empty slug table.
function PL.Tidy(chr, slug, id)
  local byId = chr.edits[slug]
  if byId and byId[id] and not (byId[id].qty or byId[id].hidden) then
    byId[id] = nil
  end
  if byId and next(byId) == nil then
    chr.edits[slug] = nil
  end
end

-- Lines -------------------------------------------------------------------------------------------

-- Route lines with the changes applied (removed ones left out, amount replaced, the total follows the
-- amount) plus the own positions as lines of the same shape, in the order of adding. The amount of a
-- line here is the target (need), PL.Allocate takes the stock off afterwards.
-- ctx: slug of the route, edits { [itemId] = change } of that slug, items (own positions), name(item),
-- source(item), price(item, source) -> copper | nil.
-- Returns the lines and the number of removed route lines.
function PL.Apply(lines, ctx)
  local out, hidden = {}, 0
  local edits = ctx.edits or {}
  for _, line in ipairs(lines or {}) do
    local edit = edits[line.id]
    if edit and edit.hidden then
      hidden = hidden + 1
    else
      local copy = {}
      for k, v in pairs(line) do
        copy[k] = v
      end
      copy.slug, copy.base = ctx.slug, line.qty
      if edit and edit.qty then
        copy.qty = edit.qty
        copy.total = copy.price and copy.price * copy.qty or nil
      end
      copy.need = copy.qty
      out[#out + 1] = copy
    end
  end
  for _, item in ipairs(ctx.items or {}) do
    local source = ctx.source(item)
    local price = ctx.price(item, source)
    out[#out + 1] = {
      id = item.id,
      name = ctx.name(item),
      de = item.de,
      en = item.en,
      icon = item.icon,
      source = source,
      need = item.qty,
      have = 0,
      qty = item.qty,
      price = price,
      total = price and price * item.qty or nil,
      done = item.done,
      own = true,
      slug = item.slug,
    }
  end
  return out, hidden
end

-- Stock and progress ----------------------------------------------------------------------------------

local function stateOf(line)
  return line.have <= 0 and "none" or line.complete and "complete" or "partial"
end

local function allocateOne(line, left, stock, deduct)
  local need = line.need or line.qty
  local free = left[line.id]
  if free == nil then
    free = math.max(0, math.floor(tonumber(stock[line.id]) or 0))
  end
  local have = math.min(need, free)
  left[line.id] = free - have
  line.need, line.have = need, have
  line.qty = deduct and need - have or need
  line.total = line.price and line.price * line.qty or nil
  line.complete = have >= need
  line.state = stateOf(line)
end

-- Takes the stock { [itemId] = count } over the lines in list order, in place: have is what the stock
-- covers of the target (need), complete = have reached need, state = "none" | "partial" | "complete".
-- The stock of an item is used once: when several lines want the same item the earlier line gets it
-- first (route lines before own positions, each in list order). With deduct the amount to buy (qty)
-- is need - have, without it qty stays the target and have is for information only.
function PL.Allocate(lines, stock, deduct)
  local left = {}
  stock = type(stock) == "table" and stock or {}
  for _, line in ipairs(lines or {}) do
    allocateOne(line, left, stock, deduct)
  end
  return lines
end

-- Allocate plus crafting. A line whose source is "craft" (or an own position, which is bought at the
-- auction house by default) and whose recipe is known (opts.recipe) can be crafted yourself or bought at
-- the auction house, the choice is per item (opts.choice):
--   "auction": the item is a normal buy line with the auction house as its source.
--   "craft" (the default): the item itself is not bought (line.crafted), its materials follow as lines
--   of their own (line.derived, depth 1, 2 ...), directly after it: crafts = ceil(amount to craft /
--   output count), each material needs crafts x its count. A material that is crafted itself and set
--   to craft is resolved the same way, up to PL.MAX_DEPTH levels; an item that is already being
--   resolved further up (a cycle) stays a plain line.
-- The stock covers the crafted item first (fewer crafts), then the materials. All lines of an item
-- share its stock in list order, the materials of a crafted item come right after it. The lines carry
-- the origin they belong to (line.from "route" | "own"), derived lines the one of the item they come from.
-- opts: stock, deduct, slug (of the derived lines), recipe(id) -> { mats = { { id, qty } }, out } | nil,
-- choice(id) -> "craft" | "auction" | nil, derive(id, recipe) -> fields of a line | nil (name, source,
-- price ...), auctionPrice(id) -> copper | nil, ticks { [key] = true } (the saved ticks of the material
-- rows). A derived line carries its key (see PL.TickKey) and done, its tick, like an own position does.
-- Returns every line in order (the given ones with their materials).
function PL.Resolve(lines, opts)
  opts = opts or {}
  local left, out, derived = {}, {}, 0
  local stock = type(opts.stock) == "table" and opts.stock or {}
  local deduct = opts.deduct == true
  local ticks = type(opts.ticks) == "table" and opts.ticks or {}
  local visit

  local function expand(line, recipe, path)
    local crafts = math.ceil(line.qty / math.max(1, tonumber(recipe.out) or 1))
    local mats, order = {}, {}
    for _, m in ipairs(recipe.mats or {}) do
      local id, n = tonumber(m[1]), tonumber(m[2])
      if id and n and n > 0 then
        if not mats[id] then
          order[#order + 1] = id
          mats[id] = 0
        end
        mats[id] = mats[id] + n
      end
    end
    line.crafts = crafts
    path[line.id] = true
    for _, id in ipairs(order) do
      if derived >= PL.MAX_DERIVED or crafts <= 0 then
        break
      end
      derived = derived + 1
      local child = opts.derive and opts.derive(id, recipe) or {}
      child.id, child.derived, child.slug = id, true, line.slug or opts.slug
      child.key = line.key .. "/" .. id
      child.done = ticks[child.key] == true
      child.need = crafts * mats[id]
      child.qty, child.have = child.need, 0
      child.source = child.source or R.DEFAULT_SOURCE
      visit(child, line.from, line.depth + 1, path)
    end
    path[line.id] = nil
  end

  function visit(line, origin, depth, path)
    line.from, line.depth = origin, depth
    local recipe
    local single = line.own and depth == 0 and line.source == R.DEFAULT_SOURCE
    if (line.source == "craft" or single) and opts.recipe and depth < PL.MAX_DEPTH and not path[line.id] then
      recipe = opts.recipe(line.id)
    end
    if recipe then
      line.craftable = true
      line.choice = opts.choice and opts.choice(line.id) == "auction" and "auction" or "craft"
      if line.choice == "auction" then
        line.source = "auction"
        line.price = opts.auctionPrice and opts.auctionPrice(line.id) or nil
      else
        line.source = "craft"
      end
    end
    allocateOne(line, left, stock, deduct)
    out[#out + 1] = line
    if recipe and line.choice == "craft" then
      line.crafted, line.price, line.total = true, nil, nil
      expand(line, recipe, path)
    end
  end

  for _, line in ipairs(lines or {}) do
    line.key = PL.HeadKey(line, opts.slug)
    visit(line, line.own and "own" or "route", 0, {})
  end
  return out
end

-- Done: ticked (route line) or flagged (own position), or covered by the stock while the stock is
-- being subtracted.
function PL.Done(line, checked, deduct)
  return R.IsDone(line, checked) or (deduct == true and line.complete == true)
end

-- The lines that still have to be bought (a crafted item is not bought, its materials are), and how
-- many the stock covers (counted while subtracting).
function PL.Open(lines, deduct)
  local out, covered = {}, 0
  for _, line in ipairs(lines or {}) do
    if deduct and line.complete then
      covered = covered + 1
    elseif not line.crafted then
      out[#out + 1] = line
    end
  end
  return out, covered
end

-- The list as both windows show it ---------------------------------------------------------------------

-- The same item from several origins as one line: the amounts add up, the line carries its parts. An item
-- crafted yourself is not bought, so it is no row here: its materials are (the item is shown by reason).
local function mergeLines(lines)
  local byId, order = {}, {}
  for _, line in ipairs(lines) do
    if not line.crafted then
      if not byId[line.id] then
        byId[line.id] = {}
        order[#order + 1] = byId[line.id]
      end
      table.insert(byId[line.id], line)
    end
  end
  local out = {}
  for _, parts in ipairs(order) do
    local line = parts[1]
    if #parts > 1 then
      line = {}
      for k, v in pairs(parts[1]) do
        line[k] = v
      end
      line.merged, line.parts, line.base = true, parts, nil
      line.need, line.have, line.qty = 0, 0, 0
      for _, part in ipairs(parts) do
        line.need, line.have, line.qty = line.need + part.need, line.have + part.have, line.qty + part.qty
      end
      line.total = line.price and line.price * line.qty or nil
      line.complete = line.have >= line.need
      line.state = stateOf(line)
      line.derived, line.crafted, line.craftable, line.choice = true, false, false, nil
      for _, part in ipairs(parts) do
        line.derived = line.derived and part.derived == true
        line.fixed = line.fixed or part.derived == true
        if part.craftable then
          line.craftable, line.choice = true, part.choice
        end
      end
    end
    out[#out + 1] = line
  end
  return out
end

-- One row of the view for a line.
local function lineRow(line, ctx)
  local manual, done = true, true
  for _, part in ipairs(line.parts or { line }) do
    manual = manual and R.IsDone(part, ctx.checked)
    done = done and PL.Done(part, ctx.checked, ctx.deduct)
  end
  return {
    kind = "line",
    line = line,
    slug = line.slug,
    ticked = done,
    auto = done and not manual,
    have = line.have,
    need = line.need,
    qty = line.qty,
    state = line.state,
    depth = ctx.nested and line.depth or 0,
    craftable = line.craftable == true,
    choice = line.choice,
    crafted = line.crafted == true,
    -- Only a row of exactly one own position or route line has an amount of its own, even when it is
    -- crafted (its materials follow the amount). A merged row is a sum and a derived row (a material of an
    -- item crafted yourself) follows from its recipe: neither can be typed over. A derived line goes away
    -- with the item it comes from.
    editable = not line.parts and not line.derived,
    removable = not line.derived and not line.fixed,
  }
end

-- The rows of one block of lines in the order of the source groups, the lines still open and how many
-- rows are done. nested: the materials of a crafted item follow it (by reason), else every line is
-- on its own.
local function blockRows(lines, ctx)
  local tops, kids, last = {}, {}, nil
  for _, line in ipairs(lines) do
    if ctx.nested and line.derived and last then
      table.insert(kids[last], line)
    else
      tops[#tops + 1] = line
      kids[line] = {}
      last = line
    end
  end
  local rows, pending, ticked = {}, {}, 0
  local function add(line)
    local row = lineRow(line, ctx)
    rows[#rows + 1] = row
    if row.ticked then
      ticked = ticked + 1
    else
      pending[#pending + 1] = line
    end
  end
  for _, g in ipairs(R.Group(tops)) do
    for _, line in ipairs(g.lines) do
      add(line)
      for _, kid in ipairs(kids[line]) do
        add(kid)
      end
    end
  end
  return rows, pending, ticked
end

-- Both windows read the list through this one function, so they cannot differ. lines: the lines of the
-- plan after edits and stock (PL.Allocate or PL.Resolve), all of them, the covered ones too.
-- opts: mode ("combined" | "reason"), checked (route ticks), deduct (the stock is subtracted),
-- label(origin) -> header text of the route block.
-- Combined: one row per item over all origins. By reason: the route block with a header row, then one
-- group per own position whose head is the item itself (a line row with head = true, kids = number of
-- material rows, kidsTicked, open = copper of the open materials) and whose materials follow it; an item
-- that is in several origins is repeated with the amount of that origin. Stock is allocated before this
-- (PL.Allocate), so both modes show the same numbers.
-- Returns { mode, rows (headers and lines), lines (only the line rows), count, ticked, open (copper of
-- the open lines: the total of the whole list that both windows pin over the rows), unpriced (open lines
-- without a price) }. A header row is { kind = "header", origin, label, count, ticked, open, unpriced, sep },
-- a line row { kind = "line", line, slug, ticked, auto, have, need, qty, state, origin, depth, craftable,
-- choice, crafted, editable, removable }. sep marks the first row of every group but the
-- first one of the by reason view (a header row or a head row): the windows draw a gap and a rule there.
-- A head row also has members, every line below it (all levels, ticked or not): ticking the head ticks
-- them. The materials of an item crafted yourself are lines of their own: merged into the other rows by
-- item in the combined view (the crafted item itself is no row there), under the item (depth 1, 2 ...) in
-- the by reason view.
function PL.View(lines, opts)
  opts = opts or {}
  local ctx = { checked = opts.checked, deduct = opts.deduct == true, nested = opts.mode == "reason" }
  local view = { mode = opts.mode == "reason" and "reason" or "combined", rows = {}, lines = {}, ticked = 0 }
  local blocks
  if view.mode == "reason" then
    local route, own = {}, {}
    for _, line in ipairs(lines or {}) do
      table.insert((line.from or (line.own and "own" or "route")) == "own" and own or route, line)
    end
    blocks = { { origin = "route", lines = route } }
    -- Every own position is a group of its own: the item as the head, its materials below.
    for _, line in ipairs(own) do
      if line.derived and #blocks > 1 then
        table.insert(blocks[#blocks].lines, line)
      else
        blocks[#blocks + 1] = { origin = "own", group = true, lines = { line } }
      end
    end
  else
    blocks = { { lines = mergeLines(lines or {}) } }
  end
  local pendingAll = {}
  for _, block in ipairs(blocks) do
    local rows, pending, ticked = blockRows(block.lines, ctx)
    if #rows > 0 then
      if block.group then
        local head, top = rows[1], block.lines[1]
        local kids = {}
        for _, line in ipairs(pending) do
          if line ~= top then
            kids[#kids + 1] = line
          end
        end
        head.head, head.kids, head.kidsTicked = true, #rows - 1, ticked - (head.ticked and 1 or 0)
        head.open = R.Cost(R.Group(kids))
        head.members = {}
        for i = 2, #rows do
          head.members[#head.members + 1] = rows[i].line
        end
        head.sep = #view.rows > 0
      elseif block.origin then
        local open, unpriced = R.Cost(R.Group(pending))
        view.rows[#view.rows + 1] = {
          kind = "header",
          origin = block.origin,
          label = opts.label and opts.label(block.origin) or block.origin,
          count = #rows,
          ticked = ticked,
          open = open,
          unpriced = unpriced,
          sep = #view.rows > 0,
        }
      end
      for _, row in ipairs(rows) do
        row.origin = block.origin
        view.rows[#view.rows + 1] = row
        view.lines[#view.lines + 1] = row
      end
      for _, line in ipairs(pending) do
        pendingAll[#pendingAll + 1] = line
      end
      view.ticked = view.ticked + ticked
    end
  end
  view.count = #view.lines
  view.open, view.unpriced = R.Cost(R.Group(pendingAll))
  return view
end

-- Search ------------------------------------------------------------------------------------------------

local function lowerOf(str)
  local PN = rawget(ns, "PlayerName")
  return PN and PN.Lower and PN.Lower(str) or str:lower()
end

-- The rows of a view that match a search text, as a view of its own (the given one is not changed, rows
-- are shared, only the first row of a group may be a copy). Case insensitive part of the name the row
-- shows (row.line.name, a header: its label). Combined: only the matching rows. By reason: a group stays
-- when its head matches (all of its rows then) or any of its rows does (those rows, the head is kept), the
-- separators are set again for what is left. Counters of the view (count, ticked, open) stay those of the
-- whole list, matches is the number of line rows left. The members of a head stay all of its rows: a tick
-- on the head still reaches the hidden ones. An empty text returns the view itself.
function PL.Filter(view, search)
  local needle = lowerOf((type(search) == "string" and search or ""):match("^%s*(.-)%s*$"))
  if needle == "" then
    return view
  end
  local function hit(row)
    local name = row.kind == "header" and row.label or row.line and row.line.name
    return type(name) == "string" and lowerOf(name):find(needle, 1, true) ~= nil
  end
  local groups, current = {}, nil
  for _, row in ipairs(view.rows) do
    if view.mode == "reason" and (row.kind == "header" or row.head) then
      current = { head = row, rows = {} }
      groups[#groups + 1] = current
    else
      if not current then
        current = { rows = {} }
        groups[#groups + 1] = current
      end
      current.rows[#current.rows + 1] = row
    end
  end
  local out = {}
  for k, v in pairs(view) do
    out[k] = v
  end
  out.rows, out.lines, out.filtered = {}, {}, true
  local first = true
  for _, group in ipairs(groups) do
    local all = group.head and hit(group.head)
    local keep = {}
    for _, row in ipairs(group.rows) do
      if all or hit(row) then
        keep[#keep + 1] = row
      end
    end
    if all or #keep > 0 then
      local head = group.head
      if head then
        local copy = {}
        for k, v in pairs(head) do
          copy[k] = v
        end
        copy.sep = not first
        first = false
        out.rows[#out.rows + 1] = copy
        if copy.kind == "line" then
          out.lines[#out.lines + 1] = copy
        end
      end
      for _, row in ipairs(keep) do
        out.rows[#out.rows + 1] = row
        out.lines[#out.lines + 1] = row
      end
    end
  end
  out.matches = #out.lines
  return out
end

-- Packed text of a list ---------------------------------------------------------------------------

local PACK_VERSION = "1"

-- The list as text for a chat link: a version line, then one line per position
-- "<item id>,<amount>,<0|1 done>,<profession slug>". Names are not in it, the receiver's client knows
-- them by the item id.
function PL.Pack(lines, checked)
  local out = { PACK_VERSION }
  for _, line in ipairs(lines or {}) do
    if #out > PL.MAX_ITEMS then
      break
    end
    local qty = math.min(line.qty, PL.MAX_QTY)
    out[#out + 1] = string.format("%d,%d,%d,%s", line.id, qty, R.IsDone(line, checked) and 1 or 0, line.slug or "")
  end
  return table.concat(out, "\n")
end

-- Reads a packed text. Returns the positions { id, qty, done, slug } or nil and a reason ("version" |
-- "empty" | "format"). Every field is checked, anything over the limits is refused.
function PL.Unpack(raw)
  if type(raw) ~= "string" then
    return nil, "format"
  end
  local first, rest = raw:match("^([^\n]*)\n?(.*)$")
  if first ~= PACK_VERSION then
    return nil, "version"
  end
  local out = {}
  for line in (rest .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      local id, qty, done, slug = line:match("^(%d+),(%d+),([01]),([%a%-]*)$")
      id = id and PL.Id(id)
      -- An amount over the limit is refused, not cut.
      qty = qty and PL.Qty(qty) == tonumber(qty) and PL.Qty(qty)
      if not (id and qty) or #out >= PL.MAX_ITEMS then
        return nil, "format"
      end
      out[#out + 1] = { id = id, qty = qty, done = done == "1", slug = R.PROFESSIONS[slug] and slug or nil }
    end
  end
  if #out == 0 then
    return nil, "empty"
  end
  return out
end
