-- Inventory of all characters, the pure side: snapshot cleaning and budget, counting per item,
-- the rows and the text lines of the item tooltip. No game access, Inventory.lua reads the game.
--
-- ns.db.inventory[charKey] = {
--   t = server time of the last write,
--   at = { [area] = server time of the last capture of that area },
--   bags / bank / equip / mail = { [itemId] = count },
-- }
-- The bank and mail areas keep their last visit until the next one.
-- The account bank belongs to no character: its area accountBank lives in one snapshot under
-- Logic.ACCOUNT_KEY (by = key of the character that captured it) and the tooltip shows it as
-- its own row.
-- The guild bank belongs to no character either: one snapshot per guild under
-- Logic.GuildKey(guild name, realm), shared by every member, tab by tab:
--   { t = server time of the last write, name = guild name, by = key of the capturing character,
--     tabs = { [tab] = { t = server time of that tab's capture, items = { [itemId] = count } } } }
-- A tab keeps its last capture until its own data arrives again. The budget is its own (see
-- Logic.MAX_GUILD_ENTRIES), no character area is involved.
local _, ns = ...

local Logic = {}
ns.InventoryLogic = Logic

ns.AddLocale("enUS", {
  ["inv.title"] = "Owned",
  ["inv.part.bags"] = "Bags",
  ["inv.part.bank"] = "Bank",
  ["inv.part.accountBank"] = "Account bank",
  ["inv.part.guildBank"] = "Guild bank (%s)",
  ["inv.part.equip"] = "Equipped",
  ["inv.part.mail"] = "Mail",
  ["inv.total"] = "Total: %d",
  ["inv.more"] = "and %d more",
})
ns.AddLocale("deDE", {
  ["inv.title"] = "Besitz",
  ["inv.part.bags"] = "Taschen",
  ["inv.part.bank"] = "Bank",
  ["inv.part.accountBank"] = "Kontobank",
  ["inv.part.guildBank"] = "Gildenbank (%s)",
  ["inv.part.equip"] = "Ausrüstung",
  ["inv.part.mail"] = "Post",
  ["inv.total"] = "Gesamt: %d",
  ["inv.more"] = "und %d weitere",
})

-- Areas in the order the tooltip names them.
Logic.AREAS = { "bags", "bank", "equip", "mail", "accountBank" }
Logic.ACCOUNT_AREA = "accountBank"
-- Not a roster key, so no character row and no roster purge ever touches it.
Logic.ACCOUNT_KEY = "@account"
-- Table entries per character over all areas (the SavedVariables size stays small).
Logic.MAX_ENTRIES = 800
-- Guild bank snapshots: key prefix (not a roster key, like ACCOUNT_KEY), the table entries over all
-- tabs and the tab numbers the client has (MAX_GUILDBANK_TABS). Eight tabs of 98 slots hold at most
-- 784 distinct stacks, so the cap only ever trims damaged data; the smallest stacks go first.
Logic.GUILD_PREFIX = "@guild:"
Logic.MAX_GUILD_ENTRIES = 800
Logic.MAX_GUILD_TABS = 8
Logic.MAX_GUILD_NAME = 60
Logic.MAX_COUNT = 1e6
Logic.MAX_ITEM_ID = 1e8
Logic.MAX_LINES = 8
Logic.STALE_DAYS = 14

local AREA_SET = {}
for _, area in ipairs(Logic.AREAS) do
  AREA_SET[area] = true
end
-- The area that gives up entries first when the budget is exceeded.
local TRIM_ORDER = { "mail", "accountBank", "bank", "bags", "equip" }

local function number(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

-- Item id of a number or an item link; nil for anything else.
function Logic.ItemId(v)
  if type(v) == "string" then
    v = tonumber(v:match("item:(%d+)"))
  end
  v = number(v, 1, Logic.MAX_ITEM_ID)
  return v and math.floor(v) or nil
end

-- Adds a stack to a tally { [itemId] = count }. Invalid input is ignored.
function Logic.Add(tally, item, count)
  local id = Logic.ItemId(item)
  count = number(count, 1, math.huge)
  if id and count then
    tally[id] = math.min(Logic.MAX_COUNT, (tally[id] or 0) + math.floor(math.min(count, Logic.MAX_COUNT)))
  end
  return tally
end

-- Adds the tally `from` (one container) to the tally `into` (one area).
function Logic.Merge(into, from)
  if type(from) == "table" then
    for id, count in pairs(from) do
      Logic.Add(into, id, count)
    end
  end
  return into
end

local function size(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- Smallest stacks of the least important area go first, ties by the higher id.
local function trim(snap)
  local over = -Logic.MAX_ENTRIES
  for _, area in ipairs(Logic.AREAS) do
    over = over + size(snap[area])
  end
  for _, area in ipairs(TRIM_ORDER) do
    if over <= 0 then
      return
    end
    local tally, ids = snap[area], {}
    for id in pairs(tally) do
      ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
      if tally[a] ~= tally[b] then
        return tally[a] < tally[b]
      end
      return a > b
    end)
    for i = 1, math.min(over, #ids) do
      tally[ids[i]] = nil
    end
    over = over - #ids
  end
end

-- A clean copy of a stored snapshot (damaged entries dropped, budget applied); always a table.
function Logic.Clean(raw)
  raw = type(raw) == "table" and raw or {}
  local snap = { t = number(raw.t, 0, 1e11) or 0, at = {} }
  if type(raw.by) == "string" and #raw.by <= 120 then
    snap.by = raw.by
  end
  local at = type(raw.at) == "table" and raw.at or {}
  for _, area in ipairs(Logic.AREAS) do
    snap[area] = Logic.Merge({}, type(raw[area]) == "table" and raw[area] or nil)
    snap.at[area] = number(at[area], 0, 1e11) or (next(snap[area]) and snap.t) or nil
  end
  trim(snap)
  return snap
end

-- Replaces one area with a fresh tally at time `now`; the other areas stay as they were.
function Logic.SetArea(snap, area, tally, now)
  if not AREA_SET[area] then
    return snap
  end
  snap[area] = Logic.Merge({}, tally)
  snap.at = type(snap.at) == "table" and snap.at or {}
  snap.at[area] = now
  snap.t = now
  trim(snap)
  return snap
end

-- Guild bank ---------------------------------------------------------------------------------

-- Key of a guild snapshot; nil without a usable name or realm. The realm loses spaces and hyphens
-- like in a roster key, so both realm spellings of the client give the same key.
function Logic.GuildKey(name, realm)
  if type(name) ~= "string" or name == "" or #name > Logic.MAX_GUILD_NAME or type(realm) ~= "string" then
    return nil
  end
  realm = realm:gsub(" ", ""):gsub("%-", "")
  if realm == "" then
    return nil
  end
  return Logic.GUILD_PREFIX .. name .. "-" .. realm
end

function Logic.IsGuildKey(key)
  return type(key) == "string" and key:sub(1, #Logic.GUILD_PREFIX) == Logic.GUILD_PREFIX
end

-- A whole tab number the client has, else nil.
local function tabNumber(v)
  v = number(v, 1, Logic.MAX_GUILD_TABS)
  return v and v == math.floor(v) and v or nil
end

-- Table entries over all tabs of a guild snapshot.
function Logic.GuildEntries(snap)
  local n = 0
  for _, tab in pairs(type(snap) == "table" and type(snap.tabs) == "table" and snap.tabs or {}) do
    n = n + (type(tab) == "table" and size(tab.items) or 0)
  end
  return n
end

-- Smallest stacks first over all tabs, ties by the higher item id, then the higher tab.
local function trimGuild(snap)
  local list = {}
  for tab, entry in pairs(snap.tabs) do
    for id, n in pairs(entry.items) do
      list[#list + 1] = { tab = tab, id = id, n = n }
    end
  end
  local over = #list - Logic.MAX_GUILD_ENTRIES
  if over <= 0 then
    return
  end
  table.sort(list, function(a, b)
    if a.n ~= b.n then
      return a.n < b.n
    end
    if a.id ~= b.id then
      return a.id > b.id
    end
    return a.tab > b.tab
  end)
  for i = 1, over do
    snap.tabs[list[i].tab].items[list[i].id] = nil
  end
end

-- A clean copy of a stored guild snapshot (damaged tabs and entries dropped, budget applied).
function Logic.CleanGuild(raw)
  raw = type(raw) == "table" and raw or {}
  local snap = { t = number(raw.t, 0, 1e11) or 0, tabs = {} }
  if type(raw.name) == "string" and #raw.name <= Logic.MAX_GUILD_NAME then
    snap.name = raw.name
  end
  if type(raw.by) == "string" and #raw.by <= 120 then
    snap.by = raw.by
  end
  for tab, entry in pairs(type(raw.tabs) == "table" and raw.tabs or {}) do
    tab = tabNumber(tab)
    if tab and type(entry) == "table" then
      snap.tabs[tab] = { t = number(entry.t, 0, 1e11) or snap.t, items = Logic.Merge({}, entry.items) }
    end
  end
  trimGuild(snap)
  return snap
end

-- Replaces one tab with a fresh tally at time `now`; the other tabs stay as they were. An empty
-- tally is a reading too (the tab was emptied).
function Logic.SetGuildTab(snap, tab, tally, now)
  tab = tabNumber(tab)
  if not tab then
    return snap
  end
  snap.tabs = type(snap.tabs) == "table" and snap.tabs or {}
  snap.tabs[tab] = { t = now, items = Logic.Merge({}, tally) }
  snap.t = now
  trimGuild(snap)
  return snap
end

-- Count of one item over all tabs and the time of the oldest tab that holds it (nil without it).
function Logic.GuildCount(snap, itemId)
  local sum, oldest = 0, nil
  for _, tab in pairs(type(snap) == "table" and type(snap.tabs) == "table" and snap.tabs or {}) do
    local n = type(tab) == "table" and type(tab.items) == "table" and tab.items[itemId]
    if type(n) == "number" and n > 0 then
      sum = sum + n
      local t = number(tab.t, 0, 1e11) or 0
      oldest = oldest and math.min(oldest, t) or t
    end
  end
  return sum, oldest
end

-- Counts of one item per area and their sum.
function Logic.Counts(snap, itemId)
  local parts, sum = {}, 0
  for _, area in ipairs(Logic.AREAS) do
    local tally = type(snap) == "table" and snap[area]
    local n = type(tally) == "table" and tally[itemId]
    n = type(n) == "number" and n > 0 and n or 0
    -- A character never owns the account bank, counting it here would add it once per character.
    if area == Logic.ACCOUNT_AREA then
      n = 0
    end
    parts[area] = n
    sum = sum + n
  end
  return parts, sum
end

-- The account bank as one row of its own; nil when it holds none of the item.
local function accountRow(snap, itemId, now)
  local tally = type(snap) == "table" and snap[Logic.ACCOUNT_AREA]
  local n = type(tally) == "table" and tally[itemId]
  if type(n) ~= "number" or n <= 0 then
    return nil
  end
  local t = number(snap.t, 0, 1e11) or 0
  return {
    key = Logic.ACCOUNT_KEY,
    name = ns.L["inv.part.accountBank"],
    account = true,
    current = false,
    sum = n,
    parts = {},
    t = t,
    old = now ~= nil and now - t >= Logic.STALE_DAYS * 86400,
  }
end

-- The guild bank of the current guild as one row of its own; nil when it holds none of the item.
-- guild: { key, name }. The row is old when the oldest tab that holds the item is.
local function guildRow(inv, guild, itemId, now)
  if type(guild) ~= "table" or type(guild.key) ~= "string" or type(inv[guild.key]) ~= "table" then
    return nil
  end
  local n, t = Logic.GuildCount(inv[guild.key], itemId)
  if n <= 0 then
    return nil
  end
  return {
    key = guild.key,
    name = ns.L["inv.part.guildBank"]:format(tostring(guild.name)),
    shared = true,
    current = false,
    sum = n,
    parts = {},
    t = t,
    old = now ~= nil and now - t >= Logic.STALE_DAYS * 86400,
  }
end

-- Rows -------------------------------------------------------------------------------------

-- One row per character that owns the item. chars: { key, display, class, faction, current,
-- hidden }, inv: key -> snapshot. opts: faction (show only this one), currentFirst (else by
-- name), now (server time, for the age), guild ({ key, name } of the current character's guild: its
-- bank is one more row).
function Logic.Rows(chars, inv, itemId, opts)
  opts = opts or {}
  local rows = {}
  for _, c in ipairs(chars) do
    local snap = inv[c.key]
    local sameSide = not opts.faction or not c.faction or c.faction == opts.faction
    if type(snap) == "table" and not c.hidden and sameSide then
      local parts, sum = Logic.Counts(snap, itemId)
      if sum > 0 then
        local t = number(snap.t, 0, 1e11) or 0
        rows[#rows + 1] = {
          key = c.key,
          name = c.display,
          class = c.class,
          current = c.current == true,
          sum = sum,
          parts = parts,
          t = t,
          old = opts.now ~= nil and opts.now - t >= Logic.STALE_DAYS * 86400,
        }
      end
    end
  end
  local byName = opts.currentFirst == false
  table.sort(rows, function(a, b)
    if not byName then
      if a.current ~= b.current then
        return a.current
      end
      if a.t ~= b.t then
        return a.t > b.t
      end
    end
    local an, bn = a.name:lower(), b.name:lower()
    if an ~= bn then
      return an < bn
    end
    return a.key < b.key
  end)
  rows[#rows + 1] = accountRow(inv[Logic.ACCOUNT_KEY], itemId, opts.now)
  rows[#rows + 1] = guildRow(inv, opts.guild, itemId, opts.now)
  return rows
end

-- What the tooltip shows: nil when nobody owns the item, else { rows (at most `max`), more (rows
-- left out), total, multi }. The current character counts like any other, wherever the item is.
function Logic.Model(rows, max)
  if #rows == 0 then
    return nil
  end
  max = max or Logic.MAX_LINES
  local model = { rows = {}, more = math.max(0, #rows - max), total = 0, multi = #rows >= 2 }
  for i, row in ipairs(rows) do
    model.total = model.total + row.sum
    if i <= max then
      model.rows[i] = row
    end
  end
  return model
end

-- Text ---------------------------------------------------------------------------------------

local function hex(r, g, b)
  local function byte(v)
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
  end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Class color as "rrggbb", half way to grey for old data; nil for an unknown class.
function Logic.ClassHex(class, dim)
  local colors = rawget(_G, "RAID_CLASS_COLORS")
  local c = type(colors) == "table" and type(class) == "string" and colors[class] or nil
  local r, g, b
  if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
    r, g, b = c.r, c.g, c.b
  elseif ns.Theme and ns.Theme.classColors[class] then
    r, g, b = ns.U.hex(ns.Theme.classColors[class])
  else
    return nil
  end
  if dim then
    r, g, b = (r + 0.5) / 2, (g + 0.5) / 2, (b + 0.5) / 2
  end
  return hex(r, g, b)
end

-- "<name>: <sum> (Bags 5, Bank 20, ...)" with the non-empty parts only.
function Logic.RowText(row, colors)
  local L = ns.L
  if row.account or row.shared then
    return string.format("%s: %d", row.name, row.sum)
  end
  local parts = {}
  for _, area in ipairs(Logic.AREAS) do
    if area ~= Logic.ACCOUNT_AREA and row.parts[area] > 0 then
      parts[#parts + 1] = L["inv.part." .. area] .. " " .. row.parts[area]
    end
  end
  local name = row.name
  local color = colors and Logic.ClassHex(row.class, row.old)
  if color then
    name = "|cff" .. color .. name .. "|r"
  end
  return string.format("%s: %d (%s)", name, row.sum, table.concat(parts, ", "))
end

-- The tooltip lines of a model: { text, kind = "header"|"row"|"more"|"total", old }.
function Logic.Lines(model, colors)
  local L = ns.L
  local lines = { { text = L["inv.title"], kind = "header" } }
  for _, row in ipairs(model.rows) do
    lines[#lines + 1] = { text = Logic.RowText(row, colors), kind = "row", old = row.old }
  end
  if model.more > 0 then
    lines[#lines + 1] = { text = L["inv.more"]:format(model.more), kind = "more" }
  end
  if model.multi then
    lines[#lines + 1] = { text = L["inv.total"]:format(model.total), kind = "total" }
  end
  return lines
end
