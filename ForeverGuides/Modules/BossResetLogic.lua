-- When the reset question may appear on entering an instance (pure logic, no UI and no events;
-- Modules/BossReset.lua connects it). Stored boss progress belongs to a run; whoever enters again after a
-- longer break may be starting a new one, and only the player knows.
local _, ns = ...

local BRL = {}
ns.BossResetLogic = BRL

-- Seconds since the latest kill that still count as the same visit (a wipe and a quick return).
BRL.FRESH = 600
-- Seconds an answer holds for its instance; it matches the lifetime of a visit without a lockout.
BRL.ANSWER_TTL = 2 * 3600

-- A real entry: the player stands in an instance that differs from the one before the zone change, and it is no
-- login and no reload. Moving between floors of one instance keeps the instance ID, so it is no entry.
function BRL.IsEntry(previousId, currentId, initialLogin, reloadingUi)
  return currentId ~= nil and currentId ~= previousId and not initialLogin and not reloadingUi
end

-- The reason not to ask, nil when the question is due. facts = { enabled, killed, lastKill, now, locked, answeredAt }:
-- the setting, the number of bosses stored as defeated, the time of the latest kill (nil when unknown), the clock,
-- whether a lockout of the game lists kills of the instance and the time of the last answer for it.
function BRL.Skip(facts)
  if not facts.enabled then
    return "off"
  end
  if not (type(facts.killed) == "number" and facts.killed > 0) then
    return "empty"
  end
  if facts.locked then
    return "locked"
  end
  if type(facts.lastKill) == "number" and facts.now - facts.lastKill < BRL.FRESH then
    return "fresh"
  end
  if type(facts.answeredAt) == "number" and facts.now - facts.answeredAt < BRL.ANSWER_TTL then
    return "answered"
  end
  return nil
end
