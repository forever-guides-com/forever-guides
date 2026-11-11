-- Small 3D portraits for the boss rows (instance page, boss tab of the dungeon map). A row that has no symbol file
-- but a creature display ID (boss.dp), or only a creature ID (boss.npc), binds its portrait frame here. A few PlayerModel frames are pooled and handed
-- to the bound frames that are visible inside their scroll area, at most MAX_MODELS at a time, so a long boss list
-- costs the same as a short one. Models load only while a bound frame is shown: when the page is left or hidden
-- every model goes back to the pool and the tick stops. A display the client cannot load keeps the placeholder
-- symbol of the row (it is only hidden once the client reports the model as loaded). Nothing here is protected,
-- every game call is guarded, so it is safe in combat.
local _, ns = ...

local BP = {}
ns.BossPortrait = BP

BP.MAX_MODELS = 12
local TICK = 0.2

local hosts = {} -- host frame -> { display or creature, symbol }
local models = {} -- every model made so far
local free = {} -- the models that are not on a host
local ticker
local unsupported = false

local function cameraOnHead(model)
  if type(model.SetPortraitZoom) == "function" then
    pcall(model.SetPortraitZoom, model, 1)
  end
  if type(model.SetPosition) == "function" then
    pcall(model.SetPosition, model, 0, 0, 0)
  end
  if type(model.SetFacing) == "function" then
    pcall(model.SetFacing, model, 0)
  end
end

local function newModel()
  if unsupported then
    return nil
  end
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, ticker)
  if not (ok and type(model) == "table" and type(model.SetDisplayInfo) == "function") then
    unsupported = true
    return nil
  end
  model:SetScript("OnModelLoaded", function(self)
    cameraOnHead(self)
    local host = self.fgHost
    local entry = host and hosts[host]
    if entry and entry.symbol then
      -- The model has something to draw: the placeholder symbol behind it goes.
      entry.symbol:SetAlpha(0)
    end
  end)
  models[#models + 1] = model
  return model
end

local function release(host)
  local entry = hosts[host]
  local model = entry and entry.model
  if not model then
    return
  end
  entry.model = nil
  model.fgHost = nil
  model:Hide()
  pcall(model.ClearModel, model)
  model:ClearAllPoints()
  model:SetParent(ticker)
  if entry.symbol then
    entry.symbol:SetAlpha(1)
  end
  free[#free + 1] = model
end

local function attach(host, entry)
  local model = table.remove(free) or newModel()
  if not model then
    return false
  end
  model:SetParent(host)
  model:ClearAllPoints()
  model:SetAllPoints(host)
  model:SetFrameLevel(host:GetFrameLevel())
  model.fgHost = host
  local ok = pcall(function()
    model:ClearModel()
    if entry.display then
      model:SetDisplayInfo(entry.display)
    else
      model:SetCreature(entry.creature)
    end
  end)
  if not ok then
    model.fgHost = nil
    model:Hide()
    model:SetParent(ticker)
    free[#free + 1] = model
    return false
  end
  entry.model = model
  cameraOnHead(model)
  model:Show()
  return true
end

local function scrollOf(frame)
  local parent = frame:GetParent()
  while parent do
    if type(parent.GetObjectType) == "function" and parent:GetObjectType() == "ScrollFrame" then
      return parent
    end
    parent = type(parent.GetParent) == "function" and parent:GetParent() or nil
  end
end

-- True when the frame is shown and (when it sits in a scroll area) at least partly inside the visible part of it.
local function inView(host)
  if not host:IsVisible() then
    return false
  end
  local scroll = scrollOf(host)
  if not scroll then
    return true
  end
  local top, bottom, viewTop, viewBottom = host:GetTop(), host:GetBottom(), scroll:GetTop(), scroll:GetBottom()
  if not (top and bottom and viewTop and viewBottom) then
    return true
  end
  return top >= viewBottom and bottom <= viewTop
end

-- Hands the models to the hosts in view (the highest first) and takes them from the others. Returns the number of
-- hosts in view.
function BP.Update()
  local wanted = {}
  for host in pairs(hosts) do
    if inView(host) then
      wanted[#wanted + 1] = host
    else
      release(host)
    end
  end
  table.sort(wanted, function(a, b)
    return (a:GetTop() or 0) > (b:GetTop() or 0)
  end)
  for i, host in ipairs(wanted) do
    local entry = hosts[host]
    if i > BP.MAX_MODELS then
      release(host)
    elseif not entry.model and not entry.failed then
      entry.failed = not attach(host, entry)
    end
  end
  return #wanted
end

local function ensureTicker()
  if ticker then
    return
  end
  ticker = CreateFrame("Frame")
  local elapsed = TICK
  ticker:SetScript(
    "OnUpdate",
    ns.Wrap("bossportrait-tick", function(self, dt)
      elapsed = elapsed + (dt or 0)
      if elapsed < TICK then
        return
      end
      elapsed = 0
      if BP.Update() == 0 then
        -- Nothing is in view (page left): the pool stays but holds no model, the tick rests until a host shows again.
        self:Hide()
      end
    end)
  )
  ticker.fgWake = function()
    elapsed = TICK
    ticker:Show()
  end
end

-- Binds a frame to a display ID, or to a creature ID when the boss has no display ID (the client looks the model up).
-- symbol is the texture of the row that shows the placeholder meanwhile. Returns false when this client has no 3D
-- models (the row keeps its symbol).
function BP.Bind(host, display, symbol, creature)
  local hasDisplay = type(display) == "number" and display > 0
  local hasCreature = not hasDisplay and type(creature) == "number" and creature > 0
  if not (hasDisplay or hasCreature) then
    BP.Unbind(host)
    return false
  end
  ensureTicker()
  display = hasDisplay and display or nil
  creature = hasCreature and creature or nil
  local entry = hosts[host]
  if entry and (entry.display ~= display or entry.creature ~= creature) then
    release(host)
    entry = nil
  end
  if not entry then
    entry = { display = display, creature = creature }
    hosts[host] = entry
  end
  entry.symbol = symbol
  entry.failed = false
  if not host.fgPortraitHook then
    host.fgPortraitHook = true
    host:HookScript("OnShow", function()
      ticker.fgWake()
    end)
  end
  ticker.fgWake()
  return not unsupported
end

function BP.Unbind(host)
  if hosts[host] then
    release(host)
    hosts[host] = nil
  end
end

-- The number of models that are on a host right now.
function BP.Active()
  local n = 0
  for _, entry in pairs(hosts) do
    n = n + (entry.model and 1 or 0)
  end
  return n
end

function BP.PoolSize()
  return #models
end

function BP.Bound(host)
  return hosts[host] ~= nil
end
