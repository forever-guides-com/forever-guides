-- Registry of the simulation tools of the cursor ring editor (ns.CursorSim): later features register a view
-- bar button ("In combat", "Spell cast") and keep their preview state in the one shared table `sim` that the
-- editor hands to every render as ctx.sim. Nothing here runs on its own and nothing is saved: a simulation
-- is never an undo step and never marks the layout as changed (the editor only redraws).
--
-- The editor shows at most CanvasEditor.MAX_TOOLS buttons. Rule: the first registrations win, a tool that
-- would be the next one is dropped, Register returns false, "limit" for it and Dropped() lists its id.
local _, ns = ...

local S = {}
ns.CursorSim = S

local DEFAULT_MAX = 4

local tools = {} -- registration order
local dropped = {}
local sim = {}

local function maxTools()
  local editor = ns.CanvasEditor
  return editor and type(editor.MAX_TOOLS) == "number" and editor.MAX_TOOLS or DEFAULT_MAX
end

local function indexOf(id)
  for i, tool in ipairs(tools) do
    if tool.id == id then
      return i
    end
  end
  return nil
end

-- tool = { id, label (locale key), icon (name of ns.UI_ICONS), toggle (bool), onClick(active, sim) }.
-- Registering an id again replaces that tool in place. Returns true, or false and a reason: "invalid" for a
-- tool without a usable id or label, "limit" for one beyond the room of the editor.
function S.Register(tool)
  if not (type(tool) == "table" and type(tool.id) == "string" and tool.id ~= "") then
    return false, "invalid"
  end
  if type(tool.label) ~= "string" or tool.label == "" then
    return false, "invalid"
  end
  local entry = {
    id = tool.id,
    label = tool.label,
    icon = type(tool.icon) == "string" and tool.icon or nil,
    toggle = tool.toggle == true,
    active = tool.active == true,
    onClick = type(tool.onClick) == "function" and tool.onClick or nil,
  }
  local at = indexOf(entry.id)
  if at then
    tools[at] = entry
    return true
  end
  if #tools >= maxTools() then
    dropped[#dropped + 1] = entry.id
    return false, "limit"
  end
  tools[#tools + 1] = entry
  return true
end

-- The tools in registration order as CanvasEditor.Open takes them; a click reaches onClick(active, sim).
function S.Tools()
  local out = {}
  for i, tool in ipairs(tools) do
    out[i] = {
      id = tool.id,
      label = tool.label,
      icon = tool.icon,
      toggle = tool.toggle,
      active = tool.active,
      onClick = function(active)
        if tool.onClick then
          tool.onClick(active, sim)
        end
      end,
    }
  end
  return out
end

-- Ids of the tools that did not fit, in the order they were offered.
function S.Dropped()
  local out = {}
  for i, id in ipairs(dropped) do
    out[i] = id
  end
  return out
end

-- The shared simulation table. Always the same table, the editor keeps the reference while it is open.
function S.State()
  return sim
end

-- Draws the preview again while the editor is open; no undo step, the layout stays as clean as it was.
local function redraw()
  local editor = ns.CanvasEditor
  if editor and type(editor.Redraw) == "function" and (type(editor.IsOpen) ~= "function" or editor.IsOpen()) then
    editor.Redraw()
  end
end

-- Sets one field of the simulation (nil removes it) and redraws when the value changed.
function S.Set(key, value)
  if type(key) ~= "string" or sim[key] == value then
    return
  end
  sim[key] = value
  redraw()
end

-- Simulation sources: features that can be previewed without a fight (GCD, cast, swing, health, trail)
-- register one source each; the single "Simulate" tool of the editor drives all of them together.
ns.AddLocale("enUS", { ["cursor.sim.play"] = "Simulate" })
ns.AddLocale("deDE", { ["cursor.sim.play"] = "Simulation" })

local STEP = 0.05
local sources = {} -- id -> { reset, step }
local sourceOrder = {}
local playing, ticker, clock = false, nil, 0

local function stopPlay()
  playing = false
  clock = 0
  if ticker and type(ticker.Cancel) == "function" then
    ticker:Cancel()
  end
  ticker = nil
  for _, id in ipairs(sourceOrder) do
    local source = sources[id]
    if source and source.reset then
      ns.Safe("cursorsim.reset", source.reset, sim)
    end
  end
end

local function tick()
  clock = clock + STEP
  for _, id in ipairs(sourceOrder) do
    local source = sources[id]
    if source and source.step then
      ns.Safe("cursorsim.step", source.step, sim, STEP, clock)
    end
  end
  redraw()
end

local function setPlaying(active)
  if active == playing then
    return
  end
  if not active then
    stopPlay()
    redraw()
    return
  end
  local timer = rawget(_G, "C_Timer")
  if not (type(timer) == "table" and type(timer.NewTicker) == "function") then
    return
  end
  playing = true
  clock = 0
  ticker = timer.NewTicker(STEP, tick)
  tick()
end

-- source = { reset = function(sim), step = function(sim, dt, t) }: step advances the preview state of one
-- feature in `sim` (dt seconds since the last step, t seconds since the simulation started), reset clears
-- it. The first source also registers the editor tool "Simulate". Returns true or false and a reason.
function S.RegisterSource(id, source)
  if not (type(id) == "string" and id ~= "" and type(source) == "table" and type(source.step) == "function") then
    return false, "invalid"
  end
  if not sources[id] then
    sourceOrder[#sourceOrder + 1] = id
  end
  sources[id] = { reset = type(source.reset) == "function" and source.reset or nil, step = source.step }
  if indexOf("play") == nil then
    return S.Register({
      id = "play",
      label = "cursor.sim.play",
      icon = "play",
      toggle = true,
      onClick = function(active)
        setPlaying(active == true)
      end,
    })
  end
  return true
end

function S.IsPlaying()
  return playing
end

-- Back to an empty simulation, in place; a running simulation stops.
function S.Reset()
  if playing then
    stopPlay()
  end
  local any = next(sim) ~= nil
  for key in pairs(sim) do
    sim[key] = nil
  end
  if any then
    redraw()
  end
end
