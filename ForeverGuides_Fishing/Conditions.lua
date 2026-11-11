-- When fishing is possible: the conditions as pure logic over a table of facts the game layer reads.
-- The first failing condition names the reason, in a fixed order, so the status line and the tests
-- always agree. A fact the client could not tell (nil) never blocks, except for the two facts that
-- make fishing possible at all: the spell and the rod.
local _, fish = ...
if not fish.FG then
  return
end

local C = {}
fish.Conditions = C

-- Reason codes in the order they are checked. Each has a text "fishing.why.<code>".
C.REASONS = {
  "spell",
  "rod",
  "combat",
  "control",
  "vehicle",
  "flying",
  "mounted",
  "swimming",
  "stealth",
  "falling",
  "moving",
}

-- Fact name that blocks when it is true, per reason. spell and rod are the other way round.
local BLOCKING = {
  combat = "combat",
  control = "controlLost",
  vehicle = "vehicle",
  flying = "flying",
  mounted = "mounted",
  swimming = "swimming",
  stealth = "stealthed",
  falling = "falling",
  moving = "moving",
}

-- facts: spell (a fishing spell is known), rod (a fishing rod is in the main hand), combat, controlLost,
-- vehicle, flying, mounted, swimming (also underwater), stealthed, falling, moving.
-- ctx.mountedOk: riding does not block (only the double click may set it).
-- Returns true, or false and the reason code.
function C.Evaluate(facts, ctx)
  facts = type(facts) == "table" and facts or {}
  local mountedOk = type(ctx) == "table" and ctx.mountedOk == true
  for _, reason in ipairs(C.REASONS) do
    if reason == "spell" then
      if facts.spell ~= true then
        return false, reason
      end
    elseif reason == "rod" then
      if facts.rod ~= true then
        return false, reason
      end
    elseif not (reason == "mounted" and mountedOk) and facts[BLOCKING[reason]] == true then
      return false, reason
    end
  end
  return true
end
