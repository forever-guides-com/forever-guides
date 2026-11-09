-- Weapon enchantment logic without WoW API (ns.WeaponEnchantLogic), the base of the source "weapon" of the aura
-- element: poisons, sharpening stones, weightstones, oils, lures and the shaman weapon buffs are enchantments of the
-- weapon, not auras. This file reads both hands through a reader the game side injects (the call of the client
-- that exists, a fallback for the other one, never an error when neither does), normalizes what comes back, picks
-- the hand, decides present, missing or not applicable, keeps the run of the time left stable for the ring, and
-- names the enchantment from the data table (Data/WeaponEnchants.lua). A value the game keeps secret arrives as
-- nil from the reader's `plain` and is never compared or calculated with.
local _, ns = ...

local W = {}
ns.WeaponEnchantLogic = W

-- Which hand the element follows: the main hand, the off hand, or whichever has an enchantment (the one with the
-- least time left; missing only when no weapon carries one).
W.HANDS = { "any", "main", "off" }
W.ORDER = { "main", "off" }
-- INVSLOT_MAINHAND and INVSLOT_OFFHAND.
W.SLOT = { main = 16, off = 17 }
-- Enum.ItemClass.Weapon: a shield, an off-hand item or an empty hand has no weapon to enchant.
W.WEAPON_CLASS = 2
W.WARN_MAX = 3600
-- A new reading of the same enchantment that moves its end by more than this many seconds is a new run (the
-- enchantment was applied again).
W.DRIFT = 2

W.DEFAULTS = {
  weaponHand = "any",
  weaponWarn = 300,
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function identity(v)
  return v
end

-- Props ---------------------------------------------------------------------------------------------------

-- The weapon props of a saved element, repaired. weaponWarn is the seconds under which the time counts as low, 0
-- turns the warning off.
function W.Clean(raw, d)
  local hand = d.weaponHand
  for _, h in ipairs(W.HANDS) do
    if raw.weaponHand == h then
      hand = h
    end
  end
  local warn = d.weaponWarn
  if finite(raw.weaponWarn) then
    warn = math.min(math.max(math.floor(raw.weaponWarn + 0.5), 0), W.WARN_MAX)
  end
  return { weaponHand = hand, weaponWarn = warn }
end

-- Whether a time left counts as low. A time nobody could read never does.
function W.Warn(remaining, threshold)
  return finite(remaining) and finite(threshold) and threshold > 0 and remaining <= threshold
end

-- The charges as text, nil when there are none (or none readable).
function W.ChargeText(charges)
  if finite(charges) and charges >= 1 then
    return tostring(math.floor(charges))
  end
  return nil
end

-- Equipment -----------------------------------------------------------------------------------------------

-- Whether a hand holds something that can carry an enchantment. hasItem: an item sits in the slot; classID: its
-- item class, nil when the game could not tell (an item of unknown class counts, so a missing enchantment is
-- not hidden by a failed lookup).
function W.EquippedWeapon(hasItem, classID)
  if not hasItem then
    return false
  end
  if classID == nil then
    return true
  end
  return classID == W.WEAPON_CLASS
end

-- Reading -------------------------------------------------------------------------------------------------

-- What a reading says about one hand. `info` is the table of the new call, plain(v) gives v or nil for a secret.
-- Returns nil (nothing on the weapon), { hand, secret = true } (the game keeps the whole answer secret) or
-- { hand, enchantID, charges, remainingSec, permanent, unknown }: remainingSec is the time left in seconds,
-- permanent an enchantment that has charges and no end, unknown one whose time could not be read.
function W.Entry(hand, info, plain)
  plain = plain or identity
  if rawequal(info, nil) or rawequal(info, false) then
    return nil
  end
  local t = plain(info)
  if type(t) ~= "table" then
    return { hand = hand, secret = true }
  end
  local ms, expires = plain(t.remainingTimeMs), plain(t.hasExpirationTime)
  local id, charges = plain(t.enchantID), plain(t.chargesRemaining)
  local e = {
    hand = hand,
    enchantID = finite(id) and id or nil,
    charges = finite(charges) and math.max(0, math.floor(charges)) or 0,
  }
  if expires == false then
    e.permanent = true
  elseif finite(ms) then
    e.remainingSec = math.max(0, ms / 1000)
  else
    e.unknown = true
  end
  return e
end

-- The same for the values of the older call (has, expiration in ms, charges, enchantment id of one hand).
function W.LegacyEntry(hand, has, ms, charges, id, plain)
  plain = plain or identity
  local on = plain(has)
  if on == nil then
    if not rawequal(has, nil) then
      return { hand = hand, secret = true }
    end
    return nil
  end
  if not (on == true or (finite(on) and on > 0)) then
    return nil
  end
  local time, count, ench = plain(ms), plain(charges), plain(id)
  local e = {
    hand = hand,
    enchantID = finite(ench) and ench or nil,
    charges = finite(count) and math.max(0, math.floor(count)) or 0,
  }
  if finite(time) and time > 0 then
    e.remainingSec = time / 1000
  elseif finite(time) and e.charges > 0 then
    e.permanent = true
  else
    e.unknown = true
  end
  return e
end

-- Reads both hands. reader = { temporary = function(slot) (the new call, nothing when the hand has no enchantment),
-- legacy = function() (the older call: has, ms, charges, id for the main hand, then the same for the off hand),
-- plain = function(v) (v, or nil for a secret value) }. The new call is tried first; a call that raises or is
-- missing hands over to the older one. Returns { how = "temporary" | "legacy" | nil, main, off }; how is nil when
-- no call answered.
function W.Read(reader)
  local out = {}
  if type(reader) ~= "table" then
    return out
  end
  local plain = reader.plain or identity
  if type(reader.temporary) == "function" then
    local first, second = { pcall(reader.temporary, W.SLOT.main) }, { pcall(reader.temporary, W.SLOT.off) }
    if first[1] and second[1] then
      out.how = "temporary"
      out.main = W.Entry("main", first[2], plain)
      out.off = W.Entry("off", second[2], plain)
      return out
    end
  end
  if type(reader.legacy) == "function" then
    local r = { pcall(reader.legacy) }
    if r[1] then
      out.how = "legacy"
      out.main = W.LegacyEntry("main", r[2], r[3], r[4], r[5], plain)
      out.off = W.LegacyEntry("off", r[6], r[7], r[8], r[9], plain)
    end
  end
  return out
end

-- Picking ---------------------------------------------------------------------------------------------------

-- The time that orders two enchanted hands: the least left first, one without a readable time last.
local function order(e)
  return e.remainingSec or math.huge
end

-- Which hand the element looks at and what it holds. `equip` = { main, off }, whether the hand holds a weapon
-- (nil counts as yes). Returns { applicable, present, hand, entry, secret }: not applicable when no hand of the
-- choice holds a weapon (nothing can be missing), present false when a weapon has no enchantment, secret when
-- the game kept the answer for the hand secret.
function W.Pick(choice, reading, equip)
  equip = equip or {}
  local hands = { choice }
  if choice == "any" or (choice ~= "main" and choice ~= "off") then
    hands = W.ORDER
  end
  local best, secret, bare
  for _, hand in ipairs(hands) do
    local e = reading[hand]
    if e and e.secret then
      secret = secret or e
    elseif e then
      if not best or order(e) < order(best) then
        best = e
      end
    elseif equip[hand] ~= false and not bare then
      bare = hand
    end
  end
  if best then
    return { applicable = true, present = true, hand = best.hand, entry = best }
  elseif secret then
    return { applicable = true, secret = true, hand = secret.hand }
  elseif bare then
    return { applicable = true, present = false, hand = bare }
  end
  return { applicable = false }
end

-- Run -------------------------------------------------------------------------------------------------------

-- The run of the time left of one enchantment: { hand, id, endAt, duration, startAt, charges }. It stays the
-- same table while the readings agree on the end, so the ring is not fed again with every poll. A reading that
-- moves the end (the enchantment was applied again, or another one took the place) starts a new run whose length
-- is the one of the data table when it fits, else the time left at that moment. A reading without a time gives a
-- run without an end.
function W.Track(mem, e, now, base)
  if not finite(e.remainingSec) then
    return { hand = e.hand, id = e.enchantID, charges = e.charges }
  end
  local endAt = now + e.remainingSec
  if mem and mem.endAt and mem.id == e.enchantID and mem.hand == e.hand and math.abs(mem.endAt - endAt) <= W.DRIFT then
    mem.charges = e.charges
    return mem
  end
  local duration = e.remainingSec
  if finite(base) and base > duration then
    duration = base
  end
  return {
    hand = e.hand,
    id = e.enchantID,
    endAt = endAt,
    duration = duration,
    startAt = endAt - duration,
    charges = e.charges,
  }
end

-- State -----------------------------------------------------------------------------------------------------

-- The state of the element for one reading. p holds weaponHand and weaponWarn, mem is the run kept from the last
-- call (nil at the start), data the table ns.Data.WeaponEnchants.e. Returns s = { applicable, present, hand,
-- enchantID, remaining, permanent, unknown, charges, stacks, low, stale, startAt, duration, mem }. present is nil
-- when nothing can be said (no call answered, or the game keeps the answer secret and no run is known); a secret
-- answer keeps the run of the last readable one going until its end passes.
function W.State(p, reading, equip, mem, now, data)
  if type(reading) ~= "table" or reading.how == nil then
    return { applicable = false, unreadable = true }
  end
  local pick = W.Pick(p.weaponHand, reading, equip)
  if not pick.applicable then
    return { applicable = false }
  end
  if pick.present == false then
    return { applicable = true, present = false, hand = pick.hand }
  end
  if pick.secret then
    if mem and finite(mem.endAt) and finite(now) then
      if now >= mem.endAt then
        return { applicable = true, present = false, hand = mem.hand }
      end
      local remaining = mem.endAt - now
      return {
        applicable = true,
        present = true,
        stale = true,
        hand = mem.hand,
        enchantID = mem.id,
        remaining = remaining,
        charges = mem.charges,
        stacks = W.ChargeText(mem.charges),
        low = W.Warn(remaining, p.weaponWarn),
        startAt = mem.startAt,
        duration = mem.duration,
        mem = mem,
      }
    end
    return { applicable = true, hand = pick.hand, mem = mem }
  end
  local e = pick.entry
  local entry = type(data) == "table" and finite(e.enchantID) and data[e.enchantID] or nil
  local run = W.Track(mem, e, now, entry and entry.d)
  return {
    applicable = true,
    present = true,
    hand = e.hand,
    enchantID = e.enchantID,
    remaining = e.remainingSec,
    permanent = e.permanent,
    unknown = e.unknown,
    charges = e.charges,
    stacks = W.ChargeText(e.charges),
    low = W.Warn(e.remainingSec, p.weaponWarn),
    startAt = run.startAt,
    duration = run.duration,
    mem = run,
  }
end

-- Names ------------------------------------------------------------------------------------------------------

-- Name and symbol of an enchantment from the data table (entries { en, de, s = spell, d = seconds, i = icon }).
-- Without an entry the name is `fallbackName` and the symbol the one of the weapon in the hand; an entry without
-- an icon takes the weapon's as well. `pick(entry)` chooses the language, English by default.
function W.Describe(enchantID, data, weaponIcon, fallbackName, pick)
  local entry = type(data) == "table" and finite(enchantID) and data[enchantID] or nil
  if entry then
    local name = pick and pick(entry) or entry.en or entry.de
    return { name = name or fallbackName, icon = entry.i or weaponIcon, spell = entry.s, known = true }
  end
  return { name = fallbackName, icon = weaponIcon, known = false }
end

-- What each hand holds, for the panel: a list of { hand, kind, entry } in the order main, off. kind is "enchanted",
-- "bare" (a weapon without an enchantment), "none" (no weapon) or "secret".
function W.Hands(reading, equip)
  equip = equip or {}
  local list = {}
  for _, hand in ipairs(W.ORDER) do
    local e = type(reading) == "table" and reading[hand] or nil
    local kind
    if e and e.secret then
      kind = "secret"
    elseif e then
      kind = "enchanted"
    elseif equip[hand] == false then
      kind = "none"
    else
      kind = "bare"
    end
    list[#list + 1] = { hand = hand, kind = kind, entry = e }
  end
  return list
end
