-- Opt-in register for everything that goes to or comes from other add-on users. No game calls, no
-- network: other modules ask Consent.Allows(fn, dir, aud) and write only through Consent.Set.
-- Account values live in ns.db.consent, a character may override single flags in ns.charDB.consent
-- (absent flag = inherits). Everything is off until the player switches it on; anything unknown,
-- missing or damaged counts as off.
local _, ns = ...
local U = ns.U

local Consent = {}
ns.Consent = Consent

Consent.VERSION = 1
Consent.MAX_LOG = 30
Consent.DIRECTIONS = { "send", "receive" }
Consent.AUDIENCES = { "group", "guild", "chat", "world" }
-- Who made a decision: the player in the settings, the setup wizard, or the migration of an old switch.
Consent.BY = { user = true, wizard = true, migrated = true }
-- Replaceable in tests.
Consent.clock = U.now

local DIR_SET, AUD_SET = {}, {}
for _, d in ipairs(Consent.DIRECTIONS) do
  DIR_SET[d] = true
end
for _, a in ipairs(Consent.AUDIENCES) do
  AUD_SET[a] = true
end

local defs, order = {}, {}

local function now()
  local t = Consent.clock()
  return type(t) == "number" and t == t and t or 0
end

local function text(v, max)
  return type(v) == "string" and #v > 0 and #v <= max
end

-- Copy of a non-empty list of unique strings that all belong to `allowed`, else nil.
local function pick(list, allowed)
  if type(list) ~= "table" or #list == 0 then
    return nil
  end
  local out, seen = {}, {}
  for i = 1, #list do
    local v = list[i]
    if type(v) ~= "string" or not allowed[v] or seen[v] then
      return nil
    end
    seen[v] = true
    out[i] = v
  end
  return out
end

-- Registers one function. Returns true, or false and the name of the field that was refused.
function Consent.Register(def)
  if type(def) ~= "table" then
    return false, "def"
  end
  if type(def.id) ~= "string" or not def.id:find("^%a%w*$") or #def.id > 24 then
    return false, "id"
  end
  if defs[def.id] then
    return false, "duplicate"
  end
  for _, key in ipairs({ "labelKey", "hintKey", "infoKey" }) do
    if not text(def[key], 64) then
      return false, key
    end
  end
  local fields = {}
  if def.fields ~= nil then
    if type(def.fields) ~= "table" then
      return false, "fields"
    end
    for i, f in ipairs(def.fields) do
      if not text(f, 24) or not f:find("^%a[%w_]*$") then
        return false, "fields"
      end
      fields[i] = f
    end
  end
  local audiences = pick(def.audiences, AUD_SET)
  if not audiences then
    return false, "audiences"
  end
  local directions = pick(def.directions, DIR_SET)
  if not directions then
    return false, "directions"
  end
  local entry = {
    id = def.id,
    labelKey = def.labelKey,
    hintKey = def.hintKey,
    infoKey = def.infoKey,
    fields = fields,
    audiences = audiences,
    directions = directions,
    audSet = {},
    dirSet = {},
  }
  for _, a in ipairs(audiences) do
    entry.audSet[a] = true
  end
  for _, d in ipairs(directions) do
    entry.dirSet[d] = true
  end
  defs[def.id] = entry
  order[#order + 1] = def.id
  return true
end

-- Copies of the registered functions in registration order.
function Consent.List()
  local out = {}
  for i, id in ipairs(order) do
    local d = defs[id]
    out[i] = {
      id = d.id,
      labelKey = d.labelKey,
      hintKey = d.hintKey,
      infoKey = d.infoKey,
      fields = U.copy(d.fields),
      audiences = U.copy(d.audiences),
      directions = U.copy(d.directions),
    }
  end
  return out
end

-- Which functions exist in this build. The settings tab lists only those; a package marks its function
-- when the feature is there. "layer" is a placeholder and never shows.
local available = {}
local HIDDEN = { layer = true }

function Consent.MarkAvailable(id)
  if type(id) ~= "string" or not defs[id] then
    return false, "function"
  end
  if HIDDEN[id] then
    return false, "hidden"
  end
  available[id] = true
  return true
end

-- True for a placeholder that no list ever shows.
function Consent.IsHidden(id)
  return HIDDEN[id] == true
end

function Consent.IsAvailable(id)
  return type(id) == "string" and available[id] == true and not HIDDEN[id]
end

-- Repair of stored data -------------------------------------------------------------------------

local function cleanFlags(raw)
  local out = {}
  if type(raw) == "table" then
    for _, aud in ipairs(Consent.AUDIENCES) do
      if type(raw[aud]) == "boolean" then
        out[aud] = raw[aud]
      end
    end
  end
  return out
end

local function cleanTimes(raw)
  local out = {}
  if type(raw) == "table" then
    for _, aud in ipairs(Consent.AUDIENCES) do
      local t = raw[aud]
      if type(t) == "number" and t == t and t >= 0 and t < math.huge then
        out[aud] = t
      end
    end
  end
  return out
end

local function number(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v or 0
end

-- One entry: flags per direction and audience, the time each flag was switched on (since), the time
-- of the last change, who changed it and with which version, and wd, the counter of withdrawals.
local function cleanItem(raw)
  raw = type(raw) == "table" and raw or {}
  local since = type(raw.since) == "table" and raw.since or {}
  return {
    send = cleanFlags(raw.send),
    receive = cleanFlags(raw.receive),
    since = { send = cleanTimes(since.send), receive = cleanTimes(since.receive) },
    at = number(raw.at),
    by = type(raw.by) == "string" and #raw.by <= 16 and raw.by or "",
    ver = type(raw.ver) == "string" and #raw.ver <= 24 and raw.ver or "",
    wd = math.floor(number(raw.wd)),
  }
end

local function cleanLogEntry(raw)
  if type(raw) ~= "table" or type(raw.fn) ~= "string" or #raw.fn > 24 then
    return nil
  end
  local value
  if type(raw.value) == "boolean" then
    value = raw.value
  end
  return {
    t = number(raw.t),
    fn = raw.fn,
    dir = type(raw.dir) == "string" and #raw.dir <= 8 and raw.dir or "",
    aud = type(raw.aud) == "string" and #raw.aud <= 8 and raw.aud or "",
    value = value,
    by = type(raw.by) == "string" and #raw.by <= 16 and raw.by or "",
    scope = raw.scope == "char" and "char" or "account",
    reset = raw.reset == true or nil,
  }
end

-- A well formed copy of stored consent data. Entries of functions this version does not know stay.
function Consent.Clean(raw)
  raw = type(raw) == "table" and raw or {}
  local out = { v = Consent.VERSION, items = {}, log = {} }
  if type(raw.items) == "table" then
    for id, item in pairs(raw.items) do
      if type(id) == "string" and id:find("^%a%w*$") and #id <= 24 and type(item) == "table" then
        out.items[id] = cleanItem(item)
      end
    end
  end
  if type(raw.log) == "table" then
    for i = math.max(1, #raw.log - Consent.MAX_LOG + 1), #raw.log do
      out.log[#out.log + 1] = cleanLogEntry(raw.log[i])
    end
  end
  return out
end

-- Reading and writing the stores -----------------------------------------------------------------

local function accountRoot()
  local db = ns.db
  if type(db) ~= "table" then
    return nil
  end
  local c = db.consent
  if type(c) ~= "table" or type(c.items) ~= "table" or type(c.log) ~= "table" then
    db.consent = Consent.Clean(c)
  end
  return db.consent
end

local function charRoot()
  local cdb = ns.charDB
  if type(cdb) ~= "table" then
    return nil
  end
  local c = cdb.consent
  if type(c) ~= "table" or type(c.items) ~= "table" then
    c = Consent.Clean(c)
    c.log = nil
    cdb.consent = c
  end
  return c
end

local function touch(items, fn)
  items[fn] = cleanItem(items[fn])
  return items[fn]
end

local function flag(item, dir, aud)
  if type(item) ~= "table" or type(item[dir]) ~= "table" then
    return nil
  end
  return item[dir][aud]
end

-- Effective value, the store it came from ("char" or "account") and that entry. A character entry
-- written before the last withdrawal of the function (other wd) does not count.
local function lookup(fn, dir, aud)
  local def = type(fn) == "string" and defs[fn]
  if not def or type(dir) ~= "string" or not def.dirSet[dir] or type(aud) ~= "string" or not def.audSet[aud] then
    return nil
  end
  local db, cdb = ns.db, ns.charDB
  local acct = type(db) == "table"
    and type(db.consent) == "table"
    and type(db.consent.items) == "table"
    and db.consent.items[fn]
  local mine = type(cdb) == "table"
    and type(cdb.consent) == "table"
    and type(cdb.consent.items) == "table"
    and cdb.consent.items[fn]
  if mine and mine.wd == (type(acct) == "table" and acct.wd or 0) then
    local v = flag(mine, dir, aud)
    if type(v) == "boolean" then
      return v, "char", mine
    end
  end
  return flag(acct, dir, aud) == true, "account", acct
end

local function log(entry)
  local list = accountRoot().log
  entry.t = now()
  list[#list + 1] = cleanLogEntry(entry)
  while #list > Consent.MAX_LOG do
    table.remove(list, 1)
  end
end

-- The one question other modules may ask. Unknown function, direction or audience: false.
function Consent.Allows(fn, dir, aud)
  return lookup(fn, dir, aud) == true
end

-- When the effective flag was switched on (epoch), nil while it is off.
function Consent.Since(fn, dir, aud)
  local v, _, item = lookup(fn, dir, aud)
  if v ~= true or type(item) ~= "table" or type(item.since) ~= "table" or type(item.since[dir]) ~= "table" then
    return nil
  end
  return item.since[dir][aud]
end

local function check(fn, dir, aud, by, scope)
  local def = type(fn) == "string" and defs[fn]
  if not def then
    return nil, "function"
  end
  if type(dir) ~= "string" or not def.dirSet[dir] then
    return nil, "direction"
  end
  if type(aud) ~= "string" or not def.audSet[aud] then
    return nil, "audience"
  end
  if type(by) ~= "string" or not Consent.BY[by] then
    return nil, "by"
  end
  if scope ~= "account" and scope ~= "char" then
    return nil, "scope"
  end
  return def
end

-- Switches one flag. scope "account" (default) or "char" (this character only), by "user" (default),
-- "wizard" or "migrated". Returns true, or false and the name of the refused argument.
function Consent.Set(fn, dir, aud, value, by, scope)
  by, scope = by == nil and "user" or by, scope == nil and "account" or scope
  local def, why = check(fn, dir, aud, by, scope)
  if not def then
    return false, why
  end
  if type(value) ~= "boolean" then
    return false, "value"
  end
  local root = accountRoot()
  if not root then
    return false, "store"
  end
  local target
  if scope == "account" then
    target = touch(root.items, fn)
  else
    local mine = charRoot()
    if not mine then
      return false, "store"
    end
    target = touch(mine.items, fn)
    local acct = root.items[fn]
    local wd = acct and acct.wd or 0
    if target.wd ~= wd then
      target.send, target.receive, target.since, target.wd = {}, {}, { send = {}, receive = {} }, wd
    end
  end
  if target[dir][aud] == value then
    return true
  end
  local t = now()
  target[dir][aud] = value
  target.since[dir][aud] = value and t or nil
  target.at, target.by, target.ver = t, by, ns.version or ""
  log({ fn = fn, dir = dir, aud = aud, value = value, by = by, scope = scope })
  if ns.Emit then
    ns.Emit("FG_CONSENT_CHANGED", fn, dir, aud, Consent.Allows(fn, dir, aud))
  end
  return true
end

-- Removes the override of this character, the flag inherits from the account again.
function Consent.Reset(fn, dir, aud, by)
  by = by == nil and "user" or by
  local def, why = check(fn, dir, aud, by, "char")
  if not def then
    return false, why
  end
  local mine = charRoot()
  local item = mine and mine.items[fn]
  if type(item) ~= "table" or flag(item, dir, aud) == nil then
    return true
  end
  local before = Consent.Allows(fn, dir, aud)
  item[dir][aud] = nil
  if type(item.since) == "table" and type(item.since[dir]) == "table" then
    item.since[dir][aud] = nil
  end
  if next(item.send) == nil and next(item.receive) == nil then
    mine.items[fn] = nil
  end
  log({ fn = fn, dir = dir, aud = aud, by = by, scope = "char", reset = true })
  local after = Consent.Allows(fn, dir, aud)
  if after ~= before then
    if ns.Emit then
      ns.Emit("FG_CONSENT_CHANGED", fn, dir, aud, after)
    end
  end
  return true
end

local function withdraw(def, by)
  local root = accountRoot()
  if not root then
    return false
  end
  local item = touch(root.items, def.id)
  for _, dir in ipairs(def.directions) do
    for _, aud in ipairs(def.audiences) do
      item[dir][aud] = false
    end
  end
  item.since = { send = {}, receive = {} }
  item.at, item.by, item.ver, item.wd = now(), by, ns.version or "", item.wd + 1
  -- Entries of other characters die with the counter; this one is cleared at once.
  local mine = charRoot()
  if mine then
    mine.items[def.id] = nil
  end
  if ns.Emit then
    ns.Emit("FG_CONSENT_WITHDRAWN", def.id)
  end
  return true
end

-- Everything of one function off for the account and for this character, send and receive.
function Consent.Withdraw(fn, by)
  by = by == nil and "user" or by
  local def = type(fn) == "string" and defs[fn]
  if not def or type(by) ~= "string" or not Consent.BY[by] then
    return false
  end
  if not withdraw(def, by) then
    return false
  end
  log({ fn = fn, dir = "*", aud = "*", value = false, by = by, scope = "account" })
  return true
end

-- How many flags of the function this character overrides (0: it follows the account everywhere).
function Consent.Overrides(fn)
  local def = type(fn) == "string" and defs[fn]
  local n = 0
  if def then
    for _, dir in ipairs(def.directions) do
      for _, aud in ipairs(def.audiences) do
        local _, source = lookup(fn, dir, aud)
        if source == "char" then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- Withdraws every registered function. Returns how many were processed.
function Consent.WithdrawAll(by)
  by = by == nil and "user" or by
  if type(by) ~= "string" or not Consent.BY[by] then
    return 0
  end
  local n = 0
  for _, id in ipairs(order) do
    if withdraw(defs[id], by) then
      n = n + 1
    end
  end
  if n > 0 then
    log({ fn = "*", dir = "*", aud = "*", value = false, by = by, scope = "account" })
  end
  return n
end

-- Numbers for the settings tab and the diagnosis, no names: flags in total and on, functions with
-- anything on, flags this character overrides, and the count of on flags per function.
function Consent.Summary()
  local s = { functions = #order, total = 0, active = 0, activeFunctions = 0, overrides = 0, byFunction = {} }
  for _, id in ipairs(order) do
    local def, n = defs[id], 0
    for _, dir in ipairs(def.directions) do
      for _, aud in ipairs(def.audiences) do
        local v, source = lookup(id, dir, aud)
        s.total = s.total + 1
        if v == true then
          n = n + 1
        end
        if source == "char" then
          s.overrides = s.overrides + 1
        end
      end
    end
    s.byFunction[id] = n
    s.active = s.active + n
    if n > 0 then
      s.activeFunctions = s.activeFunctions + 1
    end
  end
  return s
end

-- The last changes, oldest first, at most MAX_LOG.
function Consent.Log()
  local root = accountRoot()
  return root and U.copy(root.log) or {}
end

-- The old switch peerShare (item level and professions to group and guild) becomes consent for
-- peerStats and professions; everything else starts off. Runs once from Store.init before the defaults
-- (marker: account.consent exists), later runs only repair the table. The old keys stay, the beta
-- keys layerShare and layerHost go.
function Consent.Migrate(account)
  if type(account) ~= "table" then
    return nil
  end
  local s = type(account.settings) == "table" and account.settings or nil
  if s then
    s.layerShare, s.layerHost = nil, nil
  end
  if account.consent ~= nil then
    -- A table of a newer version stays as it is.
    local c = account.consent
    if not (type(c) == "table" and type(c.v) == "number" and c.v > Consent.VERSION) then
      account.consent = Consent.Clean(c)
    end
    return account.consent
  end
  local root = Consent.Clean(nil)
  if s and s.peerShare == true then
    local t = now()
    local before = type(account.meta) == "table" and account.meta.version
    for _, id in ipairs({ "peerStats", "professions" }) do
      local item = cleanItem(nil)
      item.send.group, item.send.guild = true, s.peerShareGuild ~= false
      item.receive.group, item.receive.guild = true, true
      for _, dir in ipairs(Consent.DIRECTIONS) do
        for aud, on in pairs(item[dir]) do
          item.since[dir][aud] = on and t or nil
        end
      end
      item.at, item.by, item.ver = t, "migrated", type(before) == "string" and #before <= 24 and before or ""
      root.items[id] = item
      root.log[#root.log + 1] = cleanLogEntry({ t = t, fn = id, dir = "*", aud = "*", value = true, by = "migrated" })
    end
  end
  account.consent = root
  return root
end

-- Functions of the add-on. Texts come with the settings tab (keys consent.<id>.label, .hint, .info).
local BUILT_IN = {
  { "peerStats", { "ilvl" }, { "group", "guild" } },
  { "professions", { "jobs", "skill" }, { "group", "guild" } },
  { "presenceMark", { "presence" }, { "group", "guild" } },
  { "crestMark", { "crests" }, { "group", "guild" } },
  { "linkShare", { "notes", "drawings", "builds", "lists" }, { "chat" } },
  { "guildMap", { "position" }, { "guild" } },
  { "crafting", { "recipes" }, { "guild" } },
  { "gmShare", { "rules" }, { "guild" } },
  { "chatPeer", { "extras" }, { "chat" } },
  { "teamChat", { "teams" }, { "chat" } },
  -- Placeholder for a later layer network, nothing uses it yet.
  { "layer", { "layer" }, { "world" } },
}
for _, row in ipairs(BUILT_IN) do
  Consent.Register({
    id = row[1],
    labelKey = "consent." .. row[1] .. ".label",
    hintKey = "consent." .. row[1] .. ".hint",
    infoKey = "consent." .. row[1] .. ".info",
    fields = row[2],
    audiences = row[3],
    directions = Consent.DIRECTIONS,
  })
end
