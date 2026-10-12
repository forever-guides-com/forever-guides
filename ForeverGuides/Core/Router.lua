-- Page registry plus navigation history. Paths look like
-- "instances/hall-of-thanes/quests": the first segment is the page id, the
-- rest are params for that page. No UI code here.
local _, ns = ...

local Router = {}
Router.__index = Router
ns.RouterClass = Router

local MAX_HISTORY = 20

function Router.new(onChange)
  return setmetatable({ pages = {}, order = {}, back = {}, fwd = {}, current = nil, onChange = onChange }, Router)
end

-- page = { id, group, icon, title (locale key), aliases = {..}, build(parent), show(page, params), placeholder }
function Router:register(page)
  assert(type(page.id) == "string", "page id required")
  if not self.pages[page.id] then
    self.order[#self.order + 1] = page.id
  end
  self.pages[page.id] = page
  return page
end

function Router:get(id)
  return self.pages[id]
end

-- Sorted by page.order, then registration order.
function Router:list()
  local out = {}
  for i, id in ipairs(self.order) do
    out[#out + 1] = { page = self.pages[id], i = i }
  end
  table.sort(out, function(a, b)
    local oa, ob = a.page.order or 1000, b.page.order or 1000
    if oa ~= ob then
      return oa < ob
    end
    return a.i < b.i
  end)
  for i, entry in ipairs(out) do
    out[i] = entry.page
  end
  return out
end

function Router:resolve(nameOrAlias)
  nameOrAlias = tostring(nameOrAlias or ""):lower()
  if self.pages[nameOrAlias] then
    return nameOrAlias
  end
  for _, id in ipairs(self.order) do
    for _, alias in ipairs(self.pages[id].aliases or {}) do
      if alias == nameOrAlias then
        return id
      end
    end
  end
  return nil
end

function Router.parse(path)
  local parts = {}
  for part in tostring(path or ""):gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  local id = table.remove(parts, 1)
  return id, parts
end

local function push(stack, value)
  stack[#stack + 1] = value
  while #stack > MAX_HISTORY do
    table.remove(stack, 1)
  end
end

function Router:_set(path)
  self.current = path
  if self.onChange then
    local id, params = Router.parse(path)
    self.onChange(path, self.pages[id], params)
  end
end

-- Returns false for unknown pages; the current page stays.
function Router:navigate(path)
  local id = Router.parse(path)
  if not id or not self.pages[id] then
    return false
  end
  if path == self.current then
    self:_set(path)
    return true
  end
  if self.current then
    push(self.back, self.current)
  end
  self.fwd = {}
  self:_set(path)
  return true
end

function Router:goBack()
  local path = table.remove(self.back)
  if not path then
    return false
  end
  push(self.fwd, self.current)
  self:_set(path)
  return true
end

function Router:goForward()
  local path = table.remove(self.fwd)
  if not path then
    return false
  end
  push(self.back, self.current)
  self:_set(path)
  return true
end

function Router:canBack()
  return #self.back > 0
end

function Router:canForward()
  return #self.fwd > 0
end

-- [{ label = title-key-or-text, path = "a/b" }, ...]; params are shown raw
-- unless the page provides crumbLabel(param, index).
function Router:crumbs(path)
  local id, params = Router.parse(path or self.current)
  local page = id and self.pages[id]
  if not page then
    return {}
  end
  local out = { { label = page.title, path = id, isKey = true } }
  local acc = id
  for i, param in ipairs(params) do
    acc = acc .. "/" .. param
    local label = page.crumbLabel and page.crumbLabel(param, i) or param
    out[#out + 1] = { label = label, path = acc }
  end
  return out
end

-- Shared instance; MainFrame sets onChange.
ns.Router = Router.new()
