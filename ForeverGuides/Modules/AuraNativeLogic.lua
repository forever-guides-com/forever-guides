-- Logic of the native aura container without WoW API (ns.AuraNativeLogic). In combat the game keeps aura values
-- secret, but a native AuraContainer fills its buttons itself: icon, ring, time and stacks come from the engine
-- and Lua never reads a value. This file decides what the add-on does with it: which mode an aura element runs in
-- (native, calculated, live), the spec of a slot and its key, the choices of the container pool (the game never
-- destroys a container, so containers are kept and reused), which calls of a container combat allows, the slot
-- and text variants the game side tries one after the other, how the native display shows (threshold, placeholder)
-- and the status line of the panel. The game side is AuraNative.lua.
local _, ns = ...

local N = {}
ns.AuraNativeLogic = N

local AL = ns.AuraLogic
local SL = ns.ShowLogic

-- Containers the pool makes at most; every one stays as a frame for the rest of the session.
N.POOL_MAX = 24
-- Slot keys one container may use: every try of a slot form and every rebuilt slot takes a new one.
N.SLOT_MAX = 12
N.UNIT = "player"
-- The filter string of the slot for the type of the aura on the player.
N.FILTER = { buff = "HELPFUL", debuff = "HARMFUL" }

-- How the condition "only while the aura is missing" works with the native display. Lua may not know whether
-- the aura is there, so the symbol has to be hidden by something the engine does. Only the strategies in
-- MISSING_READY are built; the others wait for a measurement and resolve to computed.
N.MissingStrategy = { clip = "clip", eraser = "eraser", textgate = "textgate", computed = "computed" }
N.MISSING = { "computed", "clip", "eraser", "textgate" }
N.MISSING_DEFAULT = "computed"
N.MISSING_READY = { computed = true, clip = true }

-- The strategy a saved dev setting stands for.
function N.Strategy(value)
  if type(value) == "string" and N.MISSING_READY[value] then
    return value
  end
  return N.MISSING_DEFAULT
end

-- Mode ----------------------------------------------------------------------------------------------------------

-- What the element runs on in combat. caps = { container = false when the client has no native container (true or
-- nil, not tried yet in a fight: it is asked for), strategy = the missing strategy }. Returns { mode = "native" | "calc" | "live", reason }: calc is
-- the computed timer (the activation, the learned duration), live the state read before the fight. reason says why
-- native was not taken: "mode" (chosen), "source", "unit", "unavailable", "missing".
function N.Plan(p, caps)
  caps = caps or {}
  local mode = p.trackMode
  if mode == "live" then
    return { mode = "live", reason = "mode" }
  elseif p.source ~= "aura" then
    return { mode = "live", reason = "source" }
  elseif p.unit ~= N.UNIT then
    return { mode = "live", reason = "unit" }
  elseif mode == "cast" then
    return { mode = "calc", reason = "mode" }
  elseif caps.container == false then
    return { mode = "calc", reason = "unavailable" }
  elseif p.when == "missing" and caps.strategy ~= N.MissingStrategy.clip then
    return { mode = "calc", reason = "missing" }
  end
  return { mode = "native" }
end

-- Spec -------------------------------------------------------------------------------------------------------------

-- What a container slot is told: the unit, the filter string and the sorted spell ids (every rank of the aura).
function N.Spec(p, ids)
  return { unit = N.UNIT, filter = N.FILTER[p.auraType] or N.FILTER.buff, ids = ids }
end

-- Two specs with the same key need no rebuild.
function N.SpecKey(spec)
  if type(spec) ~= "table" then
    return ""
  end
  return table.concat({ spec.unit, spec.filter, table.concat(spec.ids, ",") }, "|")
end

-- The ids as a set, the form the game's filter takes.
function N.FilterSet(ids)
  local set = {}
  for _, id in ipairs(ids) do
    set[id] = true
  end
  return set
end

-- The forms of the AddAuraSlot options tried in this order (the shape of candidateFilters is not measured): both
-- places at once, the nested one, the direct one. The first without an error is kept for the session.
N.SLOT_FORMS = { "both", "nested", "direct" }

function N.SlotOptions(form, ids, initialize)
  local set = N.FilterSet(ids)
  local options = { initializeFrame = initialize }
  if form ~= "direct" then
    options.candidateFilters = { includeSpellIDs = set }
  end
  if form ~= "nested" then
    options.includeSpellIDs = set
  end
  return options
end

-- The filters of the update call (SetAuraSlotCandidateFilters), which takes them without the options around.
function N.FilterOptions(ids)
  return { includeSpellIDs = N.FilterSet(ids) }
end

-- The forms in the order to try: the one that worked first.
function N.FormOrder(remembered)
  local list, known = {}, false
  for _, form in ipairs(N.SLOT_FORMS) do
    known = known or form == remembered
  end
  if known then
    list[1] = remembered
  end
  for _, form in ipairs(N.SLOT_FORMS) do
    if form ~= remembered or not known then
      list[#list + 1] = form
    end
  end
  return list
end

-- Pool -------------------------------------------------------------------------------------------------------------

-- Whether the game withholds aura values or the add-on is in combat: builds wait then. Both are true, false or nil.
function N.Restricted(aurasSecret, inCombat)
  return AL.Restricted(nil, aurasSecret, inCombat)
end

function N.CanBuild(restricted)
  return restricted ~= true
end

function N.Full(total, max)
  return total >= max
end

-- What to do for an element that wants a container. i = { restricted, warm (a free container still holds this
-- exact configuration for this element), free (free containers), total, max }. "warm": use it as it is (only
-- calls combat allows), "cold": rebuild a free one, "create": make a new one, "pending": wait for the end of the
-- fight, "limit": the pool is full.
function N.AcquireAction(i)
  if i.warm then
    return "warm"
  elseif not N.CanBuild(i.restricted) then
    return "pending"
  elseif i.free > 0 then
    return "cold"
  elseif not N.Full(i.total, i.max) then
    return "create"
  end
  return "limit"
end

-- What to do when the spec of a held container changes: "keep", "apply" (outside a fight) or "defer" (the last
-- configuration stays on show until the fight ends).
function N.ReconfigureAction(i)
  if i.same then
    return "keep"
  end
  return N.CanBuild(i.restricted) and "apply" or "defer"
end

-- The state of one pool entry: free (kept, nobody uses it), active (built and used) or fallback (the game refused
-- a call, the element shows the computed display). An element that waits for a container has no entry yet (the
-- pool lists it as pending); an entry in use stays active while a rebuild waits, the last configuration shows.
local NEXT = {
  free = { acquire = "active", fail = "fallback", release = "free" },
  active = { defer = "active", release = "free", fail = "fallback" },
  fallback = { acquire = "active", release = "free", fail = "fallback" },
}

function N.Next(state, event)
  local row = NEXT[state]
  if row == nil then
    return "free"
  end
  return row[event] or state
end

-- Calls of a container that combat allows (measured in the client: the engine accepted them). Everything else
-- waits until the fight is over.
N.COMBAT_CALLS = { SetEnabled = true, UpdateAllAuras = true, SetAuraSlotEnabled = true }

function N.Allowed(name, restricted)
  return restricted ~= true or N.COMBAT_CALLS[name] == true
end

-- The container methods the game side needs; a client without one has no usable container.
N.REQUIRED = {
  "SetEnabled",
  "SetAuraProcessingPolicy",
  "SetUnit",
  "AddAuraSlot",
  "UpdateAllAuras",
  "SetAuraSlotEnabled",
}

-- Text -------------------------------------------------------------------------------------------------------------

-- The ways to bind the duration text of a button, the first that the game accepts: the formatter and the colour
-- curve, the formatter, no options (the game's own text).
N.TEXT_WAYS = { "full", "formatter", "plain" }

-- The ways worth trying, in order. refused = { [way] = true } holds the ones the game refused this session.
function N.TextWays(hasFormatter, hasCurve, refused)
  local list = {}
  for _, way in ipairs(N.TEXT_WAYS) do
    local possible = way == "plain" or (hasFormatter and (way == "formatter" or hasCurve))
    if possible and not refused[way] then
      list[#list + 1] = way
    end
  end
  return list
end

-- The options table of a way, nil for the plain call and for a way that lacks a part.
function N.TextOptions(way, formatter, curve, property)
  if way == "full" and formatter ~= nil and curve ~= nil and property ~= nil then
    return { textFormatter = formatter, textColor = { curve = curve, property = property } }
  elseif way == "formatter" and formatter ~= nil then
    return { textFormatter = formatter }
  end
  return nil
end

-- Display ----------------------------------------------------------------------------------------------------------

-- Whether the native display shows, from the computed state of the aura (used for the threshold only: the
-- engine's own button is the truth about the aura). s = { present, remaining, permanent, canCurve }. Returns
-- { mode = "show" | "hide" | "curve", dim = false }.
function N.Visible(p, s)
  if s.present ~= true then
    return { mode = "show", dim = false }
  end
  local mode = SL.Decide(p, {
    idle = false,
    remaining = s.remaining,
    permanent = s.permanent,
    canCurve = s.canCurve,
  })
  return { mode = mode, dim = false }
end

-- The symbol under the native button: the condition "always" shows the dimmed grey icon (the button covers it
-- while the aura is there), "missing" the plain grey icon (a clip hides it while the aura is there), "active"
-- none.
function N.Placeholder(p)
  if p.when == "always" then
    return { shown = true, alpha = p.dimAlpha or 1, desaturated = true }
  elseif p.when == "missing" then
    return { shown = true, alpha = 1, desaturated = true }
  end
  return { shown = false, alpha = 1, desaturated = false }
end

-- Status -----------------------------------------------------------------------------------------------------------

-- The status line of the panel for one element. ctx = { poolFull, failed }. Returns { key, color, notes }: key
-- "native", "calc" or "live" (what the engine or the add-on does in combat), color a theme colour name, notes the
-- reasons and limits to say in addition.
function N.Status(p, caps, ctx)
  ctx = ctx or {}
  local plan = N.Plan(p, caps)
  local notes = {}
  if plan.mode == "native" and (ctx.poolFull or ctx.failed) then
    return { key = "calc", color = "warning", notes = { ctx.failed and "failed" or "poolFull" } }
  end
  if plan.mode == "native" then
    if p.when == "missing" then
      notes[#notes + 1] = "clip"
    end
    if p.showWhen == "below" then
      notes[#notes + 1] = "limits"
    end
    return { key = "native", color = "success", notes = notes }
  elseif plan.mode == "calc" then
    if plan.reason == "unavailable" or plan.reason == "missing" then
      notes[1] = plan.reason
    end
    return { key = "calc", color = "warning", notes = notes }
  end
  if plan.reason == "unit" or plan.reason == "source" then
    notes[1] = plan.reason
  end
  return { key = "live", color = "danger", notes = notes }
end
