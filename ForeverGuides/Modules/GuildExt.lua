-- Hooks of the guild page for add-ons (Forever Guides: GildenManager). The page asks for the
-- registered entries when it is built; every callback runs through ns.Safe, so a faulty add-on
-- cannot break the page. Data goes out read-only: nothing here changes the guild.
--   RegisterTab{ id, key, order, build(parent, ctx), onShow(ctx, body) }
--     build returns the body frame of the tab (optional body:fgGridLayout(width) answers its
--     height, else its own height counts). onShow runs on every refresh while the tab is open.
--   RegisterDetail{ id, order, lines(member, ctx), actions(member, ctx) }
--     lines: list of strings in the detail card of a guild member; actions: list of
--     { key = locale key, onClick = function(member, ctx) }, at most 6 buttons.
--   RegisterColumn{ id, key, order, value(member) } text in the member list, switchable by the player.
--   ctx: Roster() (GuildData snapshot, do not change it), Rights(), Selected(), Select(member), Refresh().
-- A registration with the same id replaces the old one; a faulty spec is reported to the error
-- catcher and answers false. A registration after the page was built (the add-on is loaded on
-- demand) sends the message FG_GUILDEXT_CHANGED (kind, id), the page then updates itself.
local _, ns = ...
local GL = ns.GuildLogic

local E = { version = 1 }
ns.GuildExt = E

local DEFAULT_ORDER = 100
local MAX_ID = 32
local RESERVED_TABS = { guild = true }

local registry = { tab = {}, detail = {}, column = {} }
local sequence = 0

local function checkId(id)
  if type(id) ~= "string" or id == "" or #id > MAX_ID or id:find("[^%w_%-]") then
    error("bad id: " .. tostring(id), 0)
  end
end

local function needFunction(spec, field)
  if type(spec[field]) ~= "function" then
    error(field .. " must be a function", 0)
  end
end

local function needKey(spec)
  if type(spec.key) ~= "string" or spec.key == "" then
    error("key must be a locale key", 0)
  end
end

-- Per kind: checks the spec and names the fields that are kept (functions are wrapped).
local KINDS = {
  tab = function(spec)
    if RESERVED_TABS[spec.id] then
      error("id is taken by the page: " .. spec.id, 0)
    end
    needKey(spec)
    needFunction(spec, "build")
    return { "key" }, { "build", "onShow" }
  end,
  detail = function(spec)
    if type(spec.lines) ~= "function" and type(spec.actions) ~= "function" then
      error("lines or actions must be a function", 0)
    end
    return {}, { "lines", "actions" }
  end,
  column = function(spec)
    for _, id in ipairs(GL.COLUMNS.guild) do
      if id == spec.id then
        error("id is a column of the page: " .. id, 0)
      end
    end
    needKey(spec)
    needFunction(spec, "value")
    return { "key" }, { "value" }
  end,
}

local function add(kind, spec)
  if type(spec) ~= "table" then
    error("spec must be a table", 0)
  end
  checkId(spec.id)
  local plain, callbacks = KINDS[kind](spec)
  local order = type(spec.order) == "number" and spec.order == spec.order and spec.order or DEFAULT_ORDER
  local entry = { id = spec.id, order = order }
  for _, field in ipairs(plain) do
    entry[field] = spec[field]
  end
  for _, field in ipairs(callbacks) do
    if type(spec[field]) == "function" then
      entry[field] = ns.Wrap("guildext:" .. kind .. ":" .. spec.id .. ":" .. field, spec[field])
    end
  end
  local list = registry[kind]
  for i, old in ipairs(list) do
    if old.id == entry.id then
      entry.seq = old.seq
      list[i] = entry
      return true
    end
  end
  sequence = sequence + 1
  entry.seq = sequence
  list[#list + 1] = entry
  return true
end

local function register(kind, spec)
  local ok, done = ns.Safe("guildext:register " .. kind, add, kind, spec)
  if ok and done == true then
    -- The page may be built already (add-on loaded later): it rebuilds tabs, columns and detail lines.
    ns.Emit("FG_GUILDEXT_CHANGED", kind, spec.id)
    return true
  end
  return false
end

function E.RegisterTab(spec)
  return register("tab", spec)
end

function E.RegisterDetail(spec)
  return register("detail", spec)
end

function E.RegisterColumn(spec)
  return register("column", spec)
end

-- kind: "tab", "detail" or "column". Copies sorted by order, then by first registration.
function E.Entries(kind)
  local out = {}
  for i, entry in ipairs(registry[kind] or {}) do
    local copy = {}
    for k, v in pairs(entry) do
      copy[k] = v
    end
    out[i] = copy
  end
  table.sort(out, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.seq < b.seq
  end)
  return out
end

-- Own guild rights as the game answers them: the note rights of GuildData.Rights plus the rank
-- and text rights an add-on needs before it offers an action. Reading only.
local RANK_RIGHTS = {
  invite = "CanGuildInvite",
  promote = "CanGuildPromote",
  demote = "CanGuildDemote",
  remove = "CanGuildRemove",
  officerEdit = "CanEditOfficerNote",
  motd = "CanEditMOTD",
  guildInfo = "CanEditGuildInfo",
}

function E.Rights()
  local rights = ns.GuildData.Rights()
  for field, api in pairs(RANK_RIGHTS) do
    rights[field] = ns.GuildData.Can(api) == true
  end
  return rights
end

-- True as soon as an add-on has registered anything.
function E.Loaded()
  return #registry.tab + #registry.detail + #registry.column > 0
end

-- An add-on hands a table of its own functions to companions under its id (Share), a companion
-- asks for it with OnShared(id, fn): fn(handle) runs at once when the handle exists, else when it
-- arrives. The handle belongs to the add-on, the page does not use it.
local shared, waiting = {}, {}

function E.Share(id, handle)
  shared[id] = handle
  for _, fn in ipairs(waiting[id] or {}) do
    ns.Safe("guildext:shared " .. id, fn, handle)
  end
end

function E.OnShared(id, fn)
  if shared[id] then
    ns.Safe("guildext:shared " .. id, fn, shared[id])
    return
  end
  waiting[id] = waiting[id] or {}
  table.insert(waiting[id], fn)
end
