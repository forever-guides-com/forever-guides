-- Aura logic without WoW API (ns.AuraLogic), the base of the aura element of the mouse cursor ring: which spell
-- ids count as one aura, the repair of the saved props, which answer a proc takes, the summary of an aura's
-- readable fields, when the element shows (condition and the shared show rule) and what a game event means for
-- one element. The code that talks to the game reads every value protected and passes only what it could read;
-- a value the game keeps secret arrives as nil.
local _, ns = ...

local A = {}
ns.AuraLogic = A

local SL = ns.ShowLogic
local WE = ns.WeaponEnchantLogic
local CC = ns.CooldownCore
local WF = ns.WellFedLogic

-- What the element follows: an aura on a unit, the activation glow of a spell (a proc such as Revenge), or the
-- temporary enchantment of a weapon (poison, sharpening stone, oil, shaman weapon buff; WeaponEnchantLogic). The
-- weapon enchantment has an element of its own now: "weapon" stays readable here only so an old layout or string
-- can still be turned into it (CursorWeapon.lua), the panel of the aura element offers UI_SOURCES.
A.SOURCES = { "aura", "proc", "weapon" }
A.UI_SOURCES = { "aura", "proc" }
-- The props of the aura element that say what it follows and how. The weapon element does not store them.
A.SOURCE_PROPS = {
  "source",
  "unit",
  "mineOnly",
  "spellBase",
  "spellExact",
  "rankMode",
  "procMode",
  "procAuraId",
  "auraType",
  "anyWellFed",
}
A.UNITS = { "player", "target", "focus", "pet" }
-- aura: shows while the aura is there, missing: only while it is gone, always: dimmed while it is gone.
A.WHEN = { "active", "missing", "always" }
-- How a proc is read: the first variant that answers, the overlay of the spell, or an aura by id.
A.PROC_MODES = { "auto", "overlay", "aura" }
-- What the element does in combat when the game answers no aura lookup and none of the readable signals says
-- how it stands: keeps showing the state before the fight, hides, or dims it.
A.COMBAT_STALE = { "keep", "hide", "dim" }
-- The kind of aura on the player the native container is asked for: a buff (HELPFUL) or a debuff (HARMFUL).
A.AURA_TYPES = { "buff", "debuff" }
-- Which rank of the chosen spell counts: every rank of its chain (max), or only the chosen id (exact).
A.RANK_MODES = CC.RANK_MODES
A.SPELL_ID_MAX = 4000000
A.SAMPLES = { WARRIOR = 6673 }

A.DEFAULTS = {
  source = "aura",
  spellBase = 0,
  spellExact = 0,
  rankMode = "max",
  unit = "player",
  mineOnly = false,
  when = "active",
  dimAlpha = 0.35,
  combatStale = "keep",
  pulseOnEnd = false,
  permanentCounts = false,
  procMode = "auto",
  procAuraId = 0,
  auraType = "buff",
  showWhen = "always",
  showBelow = SL.BELOW_DEFAULT,
  weaponHand = WE.DEFAULTS.weaponHand,
  weaponWarn = WE.DEFAULTS.weaponWarn,
  anyWellFed = WF.DEFAULTS.anyWellFed,
}

-- The default props of the weapon element from the ones of the aura element: everything but what an aura follows
-- (SOURCE_PROPS) and its computed timer, `trackDefaults` being the defaults of AuraTrackLogic.
function A.WeaponDefaults(auraDefaults, trackDefaults)
  local out = {}
  for key, value in pairs(auraDefaults) do
    out[key] = value
  end
  for _, key in ipairs(A.SOURCE_PROPS) do
    out[key] = nil
  end
  for key in pairs(trackDefaults) do
    out[key] = nil
  end
  return out
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

function A.Sample(class)
  return A.SAMPLES[class]
end

-- Ids ---------------------------------------------------------------------------------------------------

-- The ids that count as one aura: the saved base id, every rank of its chain and the extra ids (the id of a
-- proc aura). Nothing is chosen for 0.
function A.IdSet(base, extra)
  local ids = {}
  if finite(base) and base > 0 then
    ids[base] = true
    for _, spell in ipairs(ns.DataApi.RankChain(base)) do
      ids[spell.id] = true
    end
  end
  for _, id in ipairs(extra or {}) do
    if finite(id) and id > 0 then
      ids[id] = true
    end
  end
  return ids
end

-- The ids that count for a spell of an element: only the chosen id in the mode "exact", else every rank of the
-- chain of the base id. `base` is the spell of the element (p.spellBase) or another base such as the aura id
-- of a proc, which has no exact id of its own.
function A.SpellIds(p, base)
  base = base or p.spellBase
  if p.rankMode ~= "exact" then
    return A.IdSet(base)
  end
  local id = base == p.spellBase and CC.ExactOf(p) or base
  return finite(id) and id > 0 and { [id] = true } or {}
end

-- What the aura lookup of an element searches for: the ids, and for a well fed buff (any food counts) every
-- well fed id plus the names to compare a readable aura name with. spellName is the name of the chosen spell when
-- the game gave it. Returns the id set and the name set (nil when only ids count).
function A.LookFor(p, ids, spellName)
  if WF.Applies(p, spellName) then
    return WF.Join(ids), WF.Names()
  end
  return ids, nil
end

-- Whether a readable spell id belongs to the set; a secret id (nil) never does.
function A.Matches(ids, spellId)
  return finite(spellId) and ids[spellId] == true
end

-- Props ---------------------------------------------------------------------------------------------------

-- The aura props of a saved element, repaired. mineOnly follows the unit (own auras only on a target or focus)
-- until the user has saved a choice.
function A.Clean(raw, d)
  local p = {
    source = oneOf(raw.source, A.SOURCES, d.source),
    unit = oneOf(raw.unit, A.UNITS, d.unit),
    when = oneOf(raw.when, A.WHEN, d.when),
    procMode = oneOf(raw.procMode, A.PROC_MODES, d.procMode),
    combatStale = oneOf(raw.combatStale, A.COMBAT_STALE, d.combatStale),
    auraType = oneOf(raw.auraType, A.AURA_TYPES, d.auraType),
    permanentCounts = type(raw.permanentCounts) == "boolean" and raw.permanentCounts or d.permanentCounts,
    pulseOnEnd = type(raw.pulseOnEnd) == "boolean" and raw.pulseOnEnd or d.pulseOnEnd,
    rankMode = oneOf(raw.rankMode, A.RANK_MODES, d.rankMode),
    spellBase = finite(raw.spellBase) and math.min(math.max(math.floor(raw.spellBase + 0.5), 0), A.SPELL_ID_MAX)
      or d.spellBase,
    spellExact = finite(raw.spellExact) and math.min(math.max(math.floor(raw.spellExact + 0.5), 0), A.SPELL_ID_MAX)
      or d.spellExact,
    procAuraId = finite(raw.procAuraId) and math.min(math.max(math.floor(raw.procAuraId + 0.5), 0), A.SPELL_ID_MAX)
      or d.procAuraId,
    dimAlpha = finite(raw.dimAlpha) and math.min(math.max(raw.dimAlpha, 0), 1) or d.dimAlpha,
  }
  if type(raw.mineOnly) == "boolean" then
    p.mineOnly = raw.mineOnly
  else
    p.mineOnly = p.unit == "target" or p.unit == "focus"
  end
  p.showWhen, p.showBelow = SL.Clean(raw, d.showWhen, d.showBelow, SL.AURA_SHOW_WHEN)
  for key, value in pairs(WE.Clean(raw, d)) do
    p[key] = value
  end
  for key, value in pairs(WF.Clean(raw, d)) do
    p[key] = value
  end
  return p
end

-- Whether an aura counts as the player's own, from the readable fields isFromPlayerOrPlayerPet (boolean) and
-- sourceUnit (string); nil when neither could be read. The caller lets an unknown aura pass.
function A.IsMine(fromPlayer, sourceUnit)
  if type(fromPlayer) == "boolean" then
    return fromPlayer
  end
  if type(sourceUnit) == "string" then
    return sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle"
  end
  return nil
end

-- Readings -------------------------------------------------------------------------------------------------

-- Whether a proc is active and which variant said so. overlay and aura are true, false or nil (the variant could
-- not answer). auto takes the overlay, then the aura: a true answer wins, else the first false one stands.
-- Returns present (true, false or nil) and the variant ("overlay" or "aura").
function A.ProcPresent(mode, overlay, aura)
  if mode == "overlay" then
    return overlay, overlay ~= nil and "overlay" or nil
  elseif mode == "aura" then
    return aura, aura ~= nil and "aura" or nil
  end
  if overlay == true then
    return true, "overlay"
  elseif aura == true then
    return true, "aura"
  elseif overlay == false then
    return false, "overlay"
  elseif aura == false then
    return false, "aura"
  end
  return nil, nil
end

-- What readable fields say about an aura: { remaining, permanent, stacks }. `f` holds duration, expirationTime
-- and applications, each nil when the game kept it secret. An aura with a duration of 0 never ends; stacks only
-- count from two on.
function A.Summary(f, now)
  local out = {}
  if finite(f.duration) then
    out.permanent = f.duration <= 0
    if not out.permanent and finite(f.expirationTime) and finite(now) then
      out.remaining = math.max(0, f.expirationTime - now)
    end
  end
  out.stacks = A.StackText(f.applications) and f.applications or nil
  return out
end

-- The stack count as text, nil below two (nothing to show) or when unreadable.
function A.StackText(applications)
  if finite(applications) and applications >= 2 then
    return tostring(math.floor(applications))
  end
  return nil
end

-- Combat ---------------------------------------------------------------------------------------------------

-- Whether a lookup that finds nothing proves nothing now. spell is the answer of C_Secrets.ShouldSpellAuraBeSecret
-- for the aura and auras that of ShouldAurasBeSecret (true, false or nil when the client cannot say). A yes from
-- either counts, and so does the fight itself: a "not secret" answer is not trusted in combat, because a lookup
-- the game answers with nil for a buff that still runs would read as "missing".
function A.Restricted(spell, auras, inCombat)
  return spell == true or auras == true or inCombat == true
end

-- Whether an update names the remembered aura instance as removed. `removed` is the list of instance ids the
-- event carried, only the ones the game let the add-on read.
function A.RemovesInstance(removed, id)
  if type(removed) ~= "table" or not finite(id) then
    return false
  end
  for _, v in ipairs(removed) do
    if v == id then
      return true
    end
  end
  return false
end

-- Whether the aura is there, when the lookup may be withheld. i holds
--   lookup: true (found), false (not found), nil (no reader answered);
--   restricted: the game withholds lookups now (A.Restricted);
--   memory: an aura instance was seen before, memoryObject: the game still gives a duration object for it;
--   removed: an event named that instance removed; last: whether the aura was there at the last trusted reading;
--   calc: what the computed timer says (true running, false ended, nil nothing known), drives: it decides alone;
--   knownEnd: the end time read before the fight (plain), now: the time now.
-- A found aura is always there. Without a restriction the lookup stands. Under one, a lookup that finds nothing
-- proves nothing: a removal event ends it, a duration object of the remembered instance keeps it, the computed
-- timer counts it, else the last trusted state stands (stale) unless its known end time has passed (expired), and
-- without one the state is unknown. A timer that drives (the mode "cast") decides before any lookup, and no timer
-- means no aura.
-- Returns present (true, false or nil), how ("lookup", "removed", "instance", "calc", "expired", "stale",
-- "none") and stale.
function A.Presence(i)
  if i.drives then
    return i.calc == true, "calc", false
  elseif i.lookup == true then
    return true, "lookup", false
  elseif not i.restricted then
    return i.lookup, "lookup", false
  elseif i.removed then
    return false, "removed", false
  elseif i.memory and i.memoryObject then
    return true, "instance", false
  elseif i.calc ~= nil then
    return i.calc, "calc", false
  elseif i.last ~= nil then
    if i.last == true and finite(i.knownEnd) and finite(i.now) and i.now >= i.knownEnd then
      return false, "expired", false
    end
    return i.last, "stale", true
  end
  return nil, "none", false
end

-- Visibility -----------------------------------------------------------------------------------------------

-- Whether the element shows. p holds when, showWhen, showBelow, permanentCounts; s = { present, remaining,
-- permanent, canCurve, unknown }, present nil when the aura could not be read. Returns { mode = "show" | "hide" |
-- "curve", dim }: dim grays an absent aura of the condition "always" and an active one whose duration is unknown
-- (the computed timer has no time to show).
function A.Visible(p, s)
  if s.present == nil then
    return { mode = "hide", dim = false }
  end
  if not s.present then
    if p.when == "active" then
      return { mode = "hide", dim = false }
    end
    return { mode = "show", dim = p.when == "always" }
  end
  if p.when == "missing" then
    return { mode = "hide", dim = false }
  end
  local mode = SL.Decide(p, {
    idle = false,
    remaining = s.remaining,
    permanent = s.permanent,
    canCurve = s.canCurve,
  })
  return { mode = mode, dim = s.unknown == true and mode ~= "hide" }
end

-- Events ---------------------------------------------------------------------------------------------------

-- What a game event means for one element: "resolve" (the spell list changed), "refresh" (read the aura again)
-- or nil. own = { unit, ids, source }; a1 is the first event argument, nil when the game keeps it secret (a missing
-- payload refreshes instead of being missed). The inventory events only matter to the source "weapon".
function A.Route(event, own, a1)
  if event == "SPELLS_CHANGED" then
    return "resolve"
  elseif event == "UNIT_AURA" then
    return (a1 == nil or a1 == own.unit) and "refresh" or nil
  elseif event == "PLAYER_TARGET_CHANGED" then
    return own.unit == "target" and "refresh" or nil
  elseif event == "PLAYER_FOCUS_CHANGED" then
    return own.unit == "focus" and "refresh" or nil
  elseif event == "UNIT_PET" then
    return own.unit == "pet" and "refresh" or nil
  elseif event == "UNIT_INVENTORY_CHANGED" then
    return own.source == "weapon" and (a1 == nil or a1 == "player") and "refresh" or nil
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    return own.source == "weapon" and "refresh" or nil
  elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
    return (a1 == nil or own.ids[a1]) and "refresh" or nil
  end
  return nil
end
