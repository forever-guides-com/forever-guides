-- Rules and data of the value elements of the mouse cursor ring (ns.CursorValuesLogic), without WoW API:
-- the props of the health ring, the resource ring and the range indicator (registered with
-- CursorLogic.Register), the item ladder as data, the rules that build the spell ladder from spell facts,
-- the source chains, the range state of an answer, the colour of a low
-- health ring, the resource colour, the editor sweep and the "vitals" preset. Drawing and the game
-- readings live in CursorValues.lua.
local _, ns = ...
local U, CU, XB = ns.U, ns.CursorLogic, ns.XpBarLayout

local V = {}
ns.CursorValuesLogic = V

-- Where a ring starts, in degrees clockwise from the top.
V.START_ANGLES = { 0, 90, 180, 270 }
V.HEALTH_MODES = { "threat", "fixed" }
V.POWER_MODES = { "power", "fixed" }
V.RANGE_MODES = { "auto", "melee", "band", "near8", "far28", "spell" }
V.DEFAULT_MODE = "auto"
-- Modes of saved elements that were renamed.
V.LEGACY_MODES = { ranged = "band", item = "band", near10 = "near8", swing = "melee" }
V.RANGE_STYLES = { "ring", "dot" }
-- How a range element shows itself: the ring or dot, the distance band as text, or both.
V.DISPLAYS = { "shape", "text", "both" }
V.TEXT_FORMATS = { "band", "upper", "short" }
V.UNKNOWN_TEXT = "?"
V.UNKNOWN_TEXT_MAX = 8
V.SPELL_ID_MAX = 4000000

-- Share of the health at which the low colour is fully reached; the full colour is reached at 100 percent.
V.LOW_AT = 0.25

-- The item ladder per relation of the target: the items whose IsItemInRange(id, "target") answers for a
-- distance band, nearest first. The ids of a band are asked in order and the first answer that is a boolean
-- counts (the client answers nil for an item it cannot use on this target, and which ids answer depends on
-- the target). A step marked `unconfirmed` has ids nobody saw answer a boolean in the client: it stays in the
-- data and is skipped when a band is picked. Adding ids or bands is a change of this table only.
V.LADDER = {
  hostile = {
    { yards = 5, items = { 8149 } },
    { yards = 10, items = { 17626, 10699, 17689 } },
    { yards = 15, items = { 33069 }, unconfirmed = true },
    { yards = 20, items = { 10645, 21519 } },
    { yards = 25, items = { 13289 } },
    { yards = 30, items = { 835, 17202, 7734 } },
    { yards = 35, items = { 18904 } },
    { yards = 40, items = { 28767, 18640, 1713, 5205, 5323, 8346, 11562 }, unconfirmed = true },
  },
  friendly = {
    { yards = 5, items = { 8149 } },
    { yards = 10, items = { 17626, 17689 }, unconfirmed = true },
    { yards = 15, items = { 1251, 2581, 3530, 3531, 6450, 6451, 8544, 14529, 14530 } },
    { yards = 20, items = { 21519 } },
    { yards = 25, items = { 13289 } },
    { yards = 30, items = { 1180 } },
    { yards = 35, items = { 18904 } },
    { yards = 40, items = { 1713, 5205, 5323, 8346, 11562, 18640 }, unconfirmed = true },
  },
}
V.RELATIONS = { "hostile", "friendly" }
-- The bands of the spell ladder (0 is the default of the relation) and the defaults. A melee spell has no range
-- of its own, the game answers it for the reach of a melee swing: that is the 5 yard band.
V.BANDS = { 5, 10, 15, 20, 25, 30, 35, 40 }
V.DEFAULT_BANDS = { hostile = 20, friendly = 15 }
V.MELEE_YARDS = 5

-- Whether some relation has a confirmed item step at `yards`.
local function confirmedAnywhere(yards)
  for _, relation in ipairs({ "hostile", "friendly" }) do
    for _, step in ipairs(V.LADDER[relation]) do
      if step.yards == yards and not step.unconfirmed then
        return true
      end
    end
  end
  return false
end

-- The bands the player can choose: those with a confirmed item step for at least one relation.
V.PICKER_BANDS = {}
for _, yards in ipairs(V.BANDS) do
  if confirmedAnywhere(yards) then
    V.PICKER_BANDS[#V.PICKER_BANDS + 1] = yards
  end
end
-- A saved band stays valid when it is not offered any more: spells still answer there.
V.BAND_VALUES = { 0 }
for _, yards in ipairs(V.BANDS) do
  V.BAND_VALUES[#V.BAND_VALUES + 1] = yards
end
-- Band of a saved element of the removed "ranged" mode that names none the player can choose, and the
-- bands of earlier versions that moved.
V.LEGACY_BAND = 30
V.LEGACY_BANDS = { [8] = 5 }

-- Abilities that fire on the next swing: the client answers their range check true at any distance, so they
-- say nothing about the melee reach. Heroic Strike, Cleave, Raptor Strike and Maul, all ranks.
V.NEXT_SWING = {}
for _, id in ipairs({
  78,
  284,
  285,
  1608,
  11564,
  11565,
  11566,
  11567,
  25286,
  845,
  7369,
  11608,
  11609,
  20569,
  2973,
  14260,
  14261,
  14262,
  14263,
  14264,
  14265,
  14266,
  6807,
  6808,
  6809,
  8972,
  9745,
  8973,
  9880,
  9881,
}) do
  V.NEXT_SWING[id] = true
end

-- Whether a spell of the book (a table with id and base) is an on-next-swing ability.
function V.IsNextSwing(entry)
  return type(entry) == "table" and (V.NEXT_SWING[entry.id] == true or V.NEXT_SWING[entry.base] == true)
end

-- Every item id of the ladder once, in ladder order: what the module asks the client to load.
function V.AllItemIds()
  local out, seen = {}, {}
  for _, relation in ipairs(V.RELATIONS) do
    for _, step in ipairs(V.LADDER[relation]) do
      for _, id in ipairs(step.items) do
        if not seen[id] then
          seen[id] = true
          out[#out + 1] = id
        end
      end
    end
  end
  return out
end

-- Seconds an unanswered item request counts as pending, and after how long a lone changed answer is checked again.
V.LOAD_SECONDS = 10
V.SETTLE_SECONDS = 0.3
-- Spells of the spellbook ladder: at most this many per band and this many melee candidates.
V.BAND_SPELLS = 3
V.MELEE_SPELLS = 8

-- The places an answer can come from. kind picks the game call; `index` is the CheckInteractDistance
-- distance and `yards` its rough distance. "ladder" is the spellbook ladder: the melee spell or the spells
-- of the band.
V.SOURCES = {
  ladder = { kind = "ladder" },
  item = { kind = "item" },
  interact3 = { kind = "interact", index = 3, yards = 8 },
  interact4 = { kind = "interact", index = 4, yards = 28 },
  spell = { kind = "spell" },
}

-- The sources a mode asks, in order, per relation of the target. The first one that answers true or false
-- decides. A hostile target asks the spells first, a friendly one the items first. The melee reach asks the
-- 5 yard item first, then the instant melee spells and last the coarse interact distance.
local function chains(hostile, friendly)
  return { hostile = hostile, friendly = friendly or hostile }
end

local AUTO_HOSTILE = { "ladder", "item", "interact3", "interact4" }
local AUTO_FRIENDLY = { "item", "ladder", "interact3", "interact4" }

V.CHAINS = {
  auto = chains(AUTO_HOSTILE, AUTO_FRIENDLY),
  melee = chains({ "item", "ladder", "interact3" }),
  band = chains({ "ladder", "item" }, { "item", "ladder" }),
  near8 = chains({ "interact3" }),
  far28 = chains({ "interact4" }),
  spell = chains({ "spell" }),
}

-- Editor samples (share 0..1) used until the simulation moves them.
V.SAMPLE = { health = 0.7, power = 0.6 }

-- Colour of a power bar that the game gave no colour for.
V.POWER_FALLBACK = "4aa8ff"

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function whole(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v + 0.5), lo, hi) or default
end

local function flag(v, default)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function opacity(v, default)
  return finite(v) and U.clamp(v, 0, 1) or default
end

-- Ladder -----------------------------------------------------------------------------------------------

-- The relation of the target: "hostile" for one the player can attack, "friendly" for a friend, nil when
-- neither is known (both ladders are tried then).
function V.Relation(attackable, friend)
  if attackable == true then
    return "hostile"
  elseif friend == true then
    return "friendly"
  end
  return nil
end

-- The band asked for: the chosen one, or the default of the relation for 0.
function V.WantedBand(relation, band)
  if finite(band) and band > 0 then
    return band
  end
  return V.DEFAULT_BANDS[relation] or V.DEFAULT_BANDS.hostile
end

-- The confirmed step of the ladder of `relation` nearest to `wanted` yards (the larger one when two are equally
-- near). Returns yards and a copy of the item ids, nil when the relation has no confirmed step.
function V.PickBand(relation, wanted)
  local best
  for _, step in ipairs(V.LADDER[relation] or {}) do
    if not step.unconfirmed then
      local gap, bestGap = math.abs(step.yards - wanted), best and math.abs(best.yards - wanted)
      if not best or gap < bestGap or (gap == bestGap and step.yards > best.yards) then
        best = step
      end
    end
  end
  if not best then
    return nil
  end
  local ids = {}
  for i, id in ipairs(best.items) do
    ids[i] = id
  end
  return best.yards, ids
end

-- The first answer of `ask(id)` over the ids that is a boolean; nil when no item can tell (the client
-- answers nil for an item it cannot use on this target).
function V.FirstAnswer(ids, ask)
  for _, id in ipairs(ids) do
    local answer = ask(id)
    if answer == true or answer == false then
      return answer
    end
  end
  return nil
end

-- The item source: asks the ladder of the relation (both ladders, hostile first, without a relation) for
-- the chosen band with `ask(id)`. Returns the answer and { band, wanted, relation } of the band that
-- answered, nil when no item can tell.
function V.AskItems(relation, band, ask)
  for _, rel in ipairs(relation and { relation } or V.RELATIONS) do
    local wanted = V.WantedBand(rel, band)
    local yards, ids = V.PickBand(rel, wanted)
    if yards then
      local answer = V.FirstAnswer(ids, ask)
      if answer ~= nil then
        return answer, { band = yards, wanted = wanted, relation = rel }
      end
    end
  end
  return nil
end

-- The 5 yard band a spell range rounds up to: 8 yards is the 10 yard band, 28 the 30 yard band. nil for a
-- melee reach (5 yards and less) and for a range beyond the ladder.
function V.BandOf(range)
  if not finite(range) or range <= V.MELEE_YARDS or range > V.BANDS[#V.BANDS] then
    return nil
  end
  return math.ceil(range / 5) * 5
end

function V.NewLadder()
  return { melee = {}, hostile = {}, friendly = {} }
end

local function addTo(list, id, cap)
  for _, known in ipairs(list) do
    if known == id then
      return
    end
  end
  if #list < cap then
    list[#list + 1] = id
  end
end

local function addToBand(steps, yards, id)
  for _, step in ipairs(steps) do
    if step.yards == yards then
      addTo(step.spells, id, V.BAND_SPELLS)
      return
    end
  end
  steps[#steps + 1] = { yards = yards, spells = { id } }
  table.sort(steps, function(a, b)
    return a.yards < b.yards
  end)
end

-- The spellbook ladder of `entries` ({ id, passive, harmful, helpful, minRange, maxRange } per spell the
-- player has): the melee candidates (harmful, reach of 5 yards or less, no on-next-swing ability), the harmful
-- spells by band of their range for hostile targets and the helpful ones for friendly targets. A passive
-- spell is no source,
-- and neither is one with a minimum range: its false also means "too close". A missing helpful flag counts
-- as helpful for a spell that is not harmful.
function V.BuildLadder(entries)
  local ladder = V.NewLadder()
  for _, e in ipairs(type(entries) == "table" and entries or {}) do
    if
      type(e) == "table"
      and finite(e.id)
      and e.id > 0
      and e.passive ~= true
      and not (finite(e.minRange) and e.minRange > 0)
      and finite(e.maxRange)
      and e.maxRange >= 0
    then
      local helpful = e.helpful
      if helpful == nil then
        helpful = e.harmful == false
      end
      local yards = V.BandOf(e.maxRange)
      if e.harmful == true then
        if e.maxRange <= V.MELEE_YARDS then
          if not V.IsNextSwing(e) then
            addTo(ladder.melee, e.id, V.MELEE_SPELLS)
          end
        elseif yards then
          addToBand(ladder.hostile, yards, e.id)
        end
      elseif helpful == true and yards then
        addToBand(ladder.friendly, yards, e.id)
      end
    end
  end
  return ladder
end

-- The band asked for: the 5 yard band for "melee", the chosen one, the melee reach for a default band when
-- the player has a melee spell and the target is not a friend, else 0 (the default of the relation).
function V.EffectiveBand(mode, band, relation, hasMelee)
  if mode == "melee" then
    return V.MELEE_YARDS
  end
  if finite(band) and band > 0 then
    return band
  end
  if hasMelee == true and relation ~= "friendly" then
    return V.MELEE_YARDS
  end
  return 0
end

-- The spell source: asks the spells of the ladder for the chosen band with `ask(id)` (both relations, hostile
-- first, without a relation). A hostile target at the melee reach asks the melee candidates. The first
-- boolean wins. Returns the answer and { kind, band, wanted, relation, spell }, nil when no spell can tell.
function V.AskSpells(ladder, relation, band, ask)
  ladder = type(ladder) == "table" and ladder or V.NewLadder()
  for _, rel in ipairs(relation and { relation } or V.RELATIONS) do
    local wanted = V.WantedBand(rel, band)
    local kind, yards, ids = "spell", V.BandOf(wanted), nil
    if rel == "hostile" and wanted <= V.MELEE_YARDS then
      kind, yards, ids = "melee", V.MELEE_YARDS, ladder.melee
    else
      for _, step in ipairs(ladder[rel] or {}) do
        if step.yards == yards then
          ids = step.spells
        end
      end
    end
    for _, id in ipairs(ids or {}) do
      local answer = ask(id)
      if answer == true or answer == false then
        return answer, { kind = kind, band = yards, wanted = wanted, relation = rel, spell = id }
      end
    end
  end
  return nil
end

-- The chain of a mode for the relation of the target (a copy); a friendly target has its own order, anything
-- else asks like a hostile one. A mode that is not known asks like "auto". "auto" at the melee reach (`band`
-- of 5 yards or less, not for a friend) asks like "melee".
function V.Chain(mode, relation, band)
  local out = {}
  local entry = V.CHAINS[mode] or V.CHAINS[V.DEFAULT_MODE]
  if entry == V.CHAINS.auto and relation ~= "friendly" and finite(band) and band > 0 and band <= V.MELEE_YARDS then
    entry = V.CHAINS.melee
  end
  for i, id in ipairs(entry[relation == "friendly" and "friendly" or "hostile"]) do
    out[i] = id
  end
  return out
end

-- Whether the chain of `mode` asks the source `id` for any relation, or, with `kind`, any source of that kind.
function V.Asks(mode, idOrKind)
  for _, relation in ipairs(V.RELATIONS) do
    for _, id in ipairs(V.Chain(mode, relation)) do
      local def = V.SOURCES[id]
      if id == idOrKind or (def and def.kind == idOrKind) then
        return true
      end
    end
  end
  return false
end

-- Whether the mode needs the 5 Hz tick: its distance sources have no event of their own.
function V.Polls(mode)
  return V.Asks(mode, "interact") or V.Asks(mode, "item") or V.Asks(mode, "ladder")
end

-- Asks the sources of `chain` in order with `ask(id)`, which answers true, false or nil and may add a table
-- of details (the band of an item). A call that fails or answers anything but true or false passes to the
-- next source. Returns the state, the id of the source that answered and its details; the state is
-- "unknown" (and the id nil) only when no source answered.
function V.Resolve(chain, ask)
  for _, id in ipairs(chain) do
    local ok, answer, info = pcall(ask, id)
    if ok and (answer == true or answer == false) then
      return V.RangeState(answer), id, info
    end
  end
  return "unknown", nil
end

-- The status line of a range element: where the answer came from (an item or a spell with its band and the
-- relation of the target, an item also with the band it was asked for when the ladder had none there),
-- "no answer", "spell not known" or "no target".
function V.StatusText(state, source, info)
  local L = ns.L
  if state == "none" then
    return L["cursor.values.status.none"]
  end
  if state == "unknown" and type(info) == "table" then
    if info.notKnown then
      return L["cursor.values.status.notKnown"]
    elseif info.guarded then
      return L["cursor.values.status.guarded"]
    elseif info.items == "loading" then
      return L["cursor.values.status.loading"]
    elseif info.items == "silent" then
      return L["cursor.values.status.itemsSilent"]
    end
  end
  if (state == "in" or state == "out") and source then
    local named = type(info) == "table" and V.DEFAULT_BANDS[info.relation]
    local name
    if source == "item" and named then
      local key = info.band == info.wanted and "cursor.values.source.item" or "cursor.values.source.itemNear"
      name = string.format(L[key], info.band, L["cursor.values.relation." .. info.relation], info.wanted or 0)
    elseif source == "ladder" and named then
      local relation = L["cursor.values.relation." .. info.relation]
      if info.kind == "melee" then
        name = string.format(L["cursor.values.source.spellMelee"], relation)
      else
        name = string.format(L["cursor.values.source.spellBand"], info.band or 0, relation)
      end
    else
      name = L["cursor.values.source." .. (source == "item" and "itemPlain" or source)]
    end
    return string.format(L["cursor.values.status"], name)
  end
  return L["cursor.values.status.unknown"]
end

-- "in" or "out" for a boolean answer, "unknown" for anything else: an answer of nil is never "out".
function V.RangeState(answer)
  if answer == true then
    return "in"
  elseif answer == false then
    return "out"
  end
  return "unknown"
end

-- The state to show after a new answer, so that answers that alternate do not flash. `shown` is the state on
-- screen (nil for none yet), `pending` the differing answer seen so far ({ state }), `state` the new
-- answer. A first answer, "none" (target gone or changed) and a return to the shown state apply at once; a
-- different one applies when it comes twice in a row (the module evaluates again after V.SETTLE_SECONDS, so a
-- lone answer does not wait for an event). Returns the state to show and the pending answer, nil when none.
function V.Settle(shown, pending, state)
  if shown == nil or shown == "none" or state == "none" or state == shown then
    return state, nil
  end
  if type(pending) == "table" and pending.state == state then
    return state, nil
  end
  return shown, { state = state }
end

-- Distance text ----------------------------------------------------------------------------------------------

-- Yards of the coarse interact checks (CheckInteractDistance 3 and 4) as measured, what a preview shows until
-- the simulation moves it, and how long the sweep holds each band.
V.INTERACT_NEAR, V.INTERACT_FAR = 10, 28
V.SAMPLE_YARDS = 22
V.SWEEP_BAND_SECONDS = 1.5

-- The confirmed steps of the item ladder of `relation` as { yards, items }, nearest first. Without a relation
-- the steps of both ladders are merged, the ids of the hostile one first.
function V.TextBands(relation)
  local out, byYards = {}, {}
  for _, rel in ipairs(V.LADDER[relation] and { relation } or V.RELATIONS) do
    for _, step in ipairs(V.LADDER[rel]) do
      if not step.unconfirmed then
        local entry = byYards[step.yards]
        if not entry then
          entry = { yards = step.yards, items = {} }
          byYards[step.yards] = entry
          out[#out + 1] = entry
        end
        for _, id in ipairs(step.items) do
          addTo(entry.items, id, math.huge)
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.yards < b.yards
  end)
  return out
end

-- The distance band the answers put the target in: { lo, hi, source } with hi nil for an open band (beyond lo).
-- `answers` holds true or false per item band (yards), interact3, interact4 and melee; a missing key is no
-- answer. The first item band that answers true wins and starts where the last answering band below it ended;
-- when every answering band says false the band is open above the highest of them. Without item answers the
-- coarse interact distances speak, then the melee spell. nil when nothing answered.
function V.Band(answers, relation)
  if type(answers) ~= "table" then
    return nil
  end
  local below, answered = 0, false
  for _, step in ipairs(V.TextBands(relation)) do
    if answers[step.yards] == true then
      return { lo = below, hi = step.yards, source = "item" }
    elseif answers[step.yards] == false then
      below, answered = step.yards, true
    end
  end
  if answered then
    return { lo = below, source = "item" }
  end
  local near, far = answers.interact3, answers.interact4
  if near == true then
    return { lo = 0, hi = V.INTERACT_NEAR, source = "interact3" }
  elseif far == true then
    return { lo = near == false and V.INTERACT_NEAR or 0, hi = V.INTERACT_FAR, source = "interact4" }
  elseif far == false then
    return { lo = V.INTERACT_FAR, source = "interact4" }
  elseif near == false then
    return { lo = V.INTERACT_NEAR, source = "interact3" }
  end
  if answers.melee == true then
    return { lo = 0, hi = V.MELEE_YARDS, source = "melee" }
  elseif answers.melee == false then
    return { lo = V.MELEE_YARDS, source = "melee" }
  end
  return nil
end

-- The text of the band of `answers`: "20-25" (format "band"), "<=25" ("upper") or "25" ("short"); an open band
-- is "35+" in every format. Returns the text and the band, the unknown text and nil when nothing answered.
function V.BandText(answers, relation, format, unknownText)
  local band = V.Band(answers, relation)
  if not band then
    return type(unknownText) == "string" and unknownText or V.UNKNOWN_TEXT, nil
  end
  if not band.hi then
    return band.lo .. "+", band
  elseif format == "upper" then
    return "<=" .. band.hi, band
  elseif format == "short" then
    return tostring(band.hi), band
  end
  return band.lo .. "-" .. band.hi, band
end

-- The distance the colours of the text compare with: the chosen one, the melee reach for the "melee" mode, the
-- default of the relation for 0.
function V.TextThreshold(mode, band, relation)
  return V.WantedBand(relation, V.EffectiveBand(mode, band, relation, false))
end

-- "in" when the whole band lies within `chosen` yards, "out" when it does not, "unknown" without a band.
function V.TextState(band, chosen)
  if type(band) ~= "table" then
    return "unknown"
  end
  return band.hi and finite(chosen) and band.hi <= chosen and "in" or "out"
end

local function bandIndex(yards)
  for i, step in ipairs(V.BANDS) do
    if yards <= step then
      return i
    end
  end
  return #V.BANDS
end

-- Where a band lies on the ladder, 0 (nearest) to 1 (an open band beyond the last step).
function V.BandPosition(band)
  if type(band) ~= "table" then
    return 1
  end
  local index = band.hi and bandIndex(band.hi) or math.min(#V.BANDS, bandIndex(band.lo) + 1)
  return U.clamp((index - 1) / (#V.BANDS - 1), 0, 1)
end

-- The colour (r, g, b) of the text of `band`: the unknown colour without a band; with `colorByBand` the in and
-- out colours blended by the position of the band; else the in colour inside `chosen` yards and the out colour
-- beyond.
function V.TextColor(p, band, chosen)
  if type(band) ~= "table" then
    return U.hex(p.colorUnknown)
  end
  if p.colorByBand then
    local t = V.BandPosition(band)
    local ir, ig, ib = U.hex(p.colorIn)
    local fr, fg, fb = U.hex(p.colorOut)
    return ir + (fr - ir) * t, ig + (fg - ig) * t, ib + (fb - ib) * t
  end
  return U.hex(V.TextState(band, chosen) == "in" and p.colorIn or p.colorOut)
end

-- The answers of a target `yards` away, as the ladder of `relation` would give them: true on every band that
-- reaches it. The preview and the simulation render their text from this.
function V.AnswersFromYards(yards, relation)
  local answers = {}
  if finite(yards) then
    for _, step in ipairs(V.TextBands(relation)) do
      answers[step.yards] = yards <= step.yards
    end
  end
  return answers
end

-- The distance the editor sweep has after `t` seconds: each band of the hostile ladder in turn, then beyond it.
function V.SweepYards(t)
  local bands = V.TextBands("hostile")
  local at = math.floor((finite(t) and t or 0) / V.SWEEP_BAND_SECONDS) % (#bands + 1) + 1
  return bands[at] and bands[at].yards or bands[#bands].yards + 5
end

-- Colours --------------------------------------------------------------------------------------------------

-- The colour of a health ring that holds `share` (0..1) of its health: the low colour up to LOW_AT, the full
-- colour from 100 percent, blended in between. Returns r, g, b (0..1).
function V.ThreatColor(share, full, low)
  local t = finite(share) and U.clamp((share - V.LOW_AT) / (1 - V.LOW_AT), 0, 1) or 1
  local fr, fg, fb = U.hex(hex(full, "ffffff"))
  local lr, lg, lb = U.hex(hex(low, "ffffff"))
  return lr + (fr - lr) * t, lg + (fg - lg) * t, lb + (fb - lb) * t
end

local function channels(r, g, b)
  if finite(r) and finite(g) and finite(b) then
    return U.clamp(r, 0, 1), U.clamp(g, 0, 1), U.clamp(b, 0, 1)
  end
  return nil
end

-- The colour of a resource: the colour the game names with the power type (r, g, b), else the entry of the
-- game's colour table by token or by type, else the fallback. Everything here is readable data.
function V.PowerColor(powerType, token, r, g, b, colors)
  local cr, cg, cb = channels(r, g, b)
  if cr then
    return cr, cg, cb
  end
  if type(colors) == "table" then
    local entry = (type(token) == "string" and colors[token]) or (finite(powerType) and colors[powerType]) or nil
    if type(entry) == "table" then
      cr, cg, cb = channels(entry.r, entry.g, entry.b)
      if cr then
        return cr, cg, cb
      end
    end
  end
  return U.hex(V.POWER_FALLBACK)
end

-- Editor sweep -----------------------------------------------------------------------------------------------

V.SWEEP = { health = 6, power = 4, range = 2 }

-- Preview state after `t` seconds: health falls from 100 to 20 percent every 6 s, the resource from 100 to 0
-- every 4 s, and the range flips every 2 s. Plain numbers for the render of the editor.
function V.Sweep(t)
  t = finite(t) and t or 0
  local health = 1 - (1 - 0.2) * ((t % V.SWEEP.health) / V.SWEEP.health)
  local power = 1 - (t % V.SWEEP.power) / V.SWEEP.power
  return health, power, math.floor(t / V.SWEEP.range) % 2 == 0
end

-- Element types ----------------------------------------------------------------------------------------------

local function ringProps(raw, d, modes)
  return {
    shape = oneOf(raw.shape, CU.SHAPE_IDS, d.shape),
    thickness = whole(raw.thickness, d.thickness, CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX),
    startAngle = finite(raw.startAngle) and (math.floor(raw.startAngle / 90 + 0.5) % 4) * 90 or d.startAngle,
    reverse = raw.reverse == true,
    colorMode = oneOf(raw.colorMode, modes, d.colorMode),
    color = hex(raw.color, d.color),
    alpha = opacity(raw.alpha, d.alpha),
    bgAlpha = opacity(raw.bgAlpha, d.bgAlpha),
  }
end

CU.Register("health", {
  defaults = {
    shape = "circle",
    thickness = 4,
    startAngle = 0,
    reverse = false,
    colorMode = "threat",
    color = "3fd05c",
    lowColor = "e5484d",
    alpha = 1,
    bgAlpha = 0.25,
  },
  size = { 64, 64 },
  clean = function(raw, d)
    local p = ringProps(raw, d, V.HEALTH_MODES)
    p.lowColor = hex(raw.lowColor, d.lowColor)
    return p
  end,
})

CU.Register("power", {
  defaults = {
    shape = "circle",
    thickness = 4,
    startAngle = 0,
    reverse = false,
    colorMode = "power",
    color = V.POWER_FALLBACK,
    alpha = 1,
    bgAlpha = 0.25,
  },
  size = { 48, 48 },
  clean = function(raw, d)
    return ringProps(raw, d, V.POWER_MODES)
  end,
})

-- The mode and band of a saved element: a renamed mode keeps its meaning (the removed "ranged" mode becomes
-- the band check of its band) and a band that moved goes to its new place.
local function rangeModeBand(raw, d)
  local mode, band = raw.mode, raw.band
  if finite(band) and V.LEGACY_BANDS[band] then
    band = V.LEGACY_BANDS[band]
  end
  if mode == "ranged" and not oneOf(band, V.BANDS, nil) then
    band = V.LEGACY_BAND
  end
  mode = V.LEGACY_MODES[mode] or mode
  return oneOf(mode, V.RANGE_MODES, d.mode), oneOf(band, V.BAND_VALUES, d.band)
end

CU.Register("range", {
  defaults = {
    mode = V.DEFAULT_MODE,
    band = 0,
    spellId = 0,
    style = "ring",
    thickness = 3,
    hostileOnly = true,
    colorIn = "3fd05c",
    colorOut = "e5484d",
    colorUnknown = "9ca3af",
    alpha = 1,
    display = "shape",
    font = "frizqt",
    fontSize = 14,
    outline = "outline",
    shadow = true,
    textFormat = "band",
    unknownText = V.UNKNOWN_TEXT,
    colorByBand = false,
  },
  size = { 24, 24 },
  clean = function(raw, d)
    local mode, band = rangeModeBand(raw, d)
    return {
      mode = mode,
      band = band,
      spellId = whole(raw.spellId, d.spellId, 0, V.SPELL_ID_MAX),
      style = oneOf(raw.style, V.RANGE_STYLES, d.style),
      thickness = whole(raw.thickness, d.thickness, CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX),
      hostileOnly = flag(raw.hostileOnly, d.hostileOnly),
      colorIn = hex(raw.colorIn, d.colorIn),
      colorOut = hex(raw.colorOut, d.colorOut),
      colorUnknown = hex(raw.colorUnknown, d.colorUnknown),
      alpha = opacity(raw.alpha, d.alpha),
      display = oneOf(raw.display, V.DISPLAYS, d.display),
      font = type(raw.font) == "string" and #raw.font <= 44 and raw.font or d.font,
      fontSize = whole(raw.fontSize, d.fontSize, XB.SIZE_MIN, XB.SIZE_MAX),
      outline = oneOf(raw.outline, XB.OUTLINES, d.outline),
      shadow = flag(raw.shadow, d.shadow),
      textFormat = oneOf(raw.textFormat, V.TEXT_FORMATS, d.textFormat),
      unknownText = type(raw.unknownText) == "string" and #raw.unknownText <= V.UNKNOWN_TEXT_MAX and raw.unknownText
        or d.unknownText,
      colorByBand = flag(raw.colorByBand, d.colorByBand),
    }
  end,
})

-- Presets ----------------------------------------------------------------------------------------------------

-- Health ring outside, resource ring inside and a range dot in the middle. The data of a preset is kept here;
-- CursorLogic builds the layout from it with its own helpers.
V.PRESETS = {
  vitals = {
    { id = "health", type = "health", size = 76, props = { thickness = 3 } },
    { id = "power", type = "power", size = 58, props = { thickness = 3 } },
    { id = "range", type = "range", size = 10, props = { style = "dot" } },
  },
  -- The distance band as text under the cursor: the text sits on the bottom edge of the frame, and the frame is
  -- centred on the hotspot like every element of a preset.
  distance = {
    { id = "range", type = "range", w = 72, h = 72, props = { display = "text", fontSize = 18, outline = "outline" } },
  },
}
V.PRESET_IDS = { "vitals", "distance" }

local function builderOf(id)
  return function(el, build)
    local elements = {}
    for i, item in ipairs(V.PRESETS[id]) do
      elements[i] = el(item.id, item.type, item.w or item.size, item.h or item.size, item.props)
    end
    return build(id, elements)
  end
end

for _, id in ipairs(V.PRESET_IDS) do
  if type(CU.RegisterPreset) == "function" then
    CU.RegisterPreset(id, builderOf(id))
  end
end

ns.AddLocale("enUS", {
  ["cursor.type.health"] = "Health ring",
  ["cursor.type.power"] = "Resource ring",
  ["cursor.type.range"] = "Range",
  ["cursor.type.health.desc"] = "Shows your health as a ring that fills with it. The game hides the exact value, so there is no number.",
  ["cursor.type.power.desc"] = "Shows your mana, rage or energy as a ring. The game hides the exact value, so there is no number.",
  ["cursor.type.range.desc"] = "Shows whether your target is in range, as a ring or dot in three colors or as text with the distance band, for example 20-25.",
  ["cursor.range.display"] = "Display",
  ["cursor.range.display.shape"] = "Ring or dot",
  ["cursor.range.display.text"] = "Text",
  ["cursor.range.display.both"] = "Ring or dot and text",
  ["cursor.range.textFormat"] = "Text format",
  ["cursor.range.textFormat.band"] = "Band (20-25)",
  ["cursor.range.textFormat.upper"] = "Upper limit (<=25)",
  ["cursor.range.textFormat.short"] = "Number only (25)",
  ["cursor.range.unknownText"] = "Text when unknown",
  ["cursor.range.colorByBand"] = "Color by distance",
  ["cursor.range.textNote"] = "The text shows the distance band from the range checks. The colors compare it with the chosen distance.",
  ["cursor.values.status"] = "Source: %s",
  ["cursor.values.status.none"] = "Source: no target",
  ["cursor.values.status.unknown"] = "Source: no answer",
  ["cursor.values.status.notKnown"] = "Source: spell not known",
  ["cursor.values.status.loading"] = "Source: loading item data",
  ["cursor.values.status.itemsSilent"] = "Source: no answer from items",
  ["cursor.values.status.guarded"] = "Source: combat: friendly target limited",
  ["cursor.values.source.interact3"] = "interact 8 yd",
  ["cursor.values.source.interact4"] = "interact 28 yd",
  ["cursor.values.source.item"] = "item %d yd (%s)",
  ["cursor.values.source.itemNear"] = "item %d yd (%s), nearest to %d yd",
  ["cursor.values.source.itemPlain"] = "item",
  ["cursor.values.source.ladder"] = "spell",
  ["cursor.values.source.spellMelee"] = "melee spell (%s)",
  ["cursor.values.source.spellBand"] = "spell %d yd (%s)",
  ["cursor.values.relation.hostile"] = "hostile",
  ["cursor.values.relation.friendly"] = "friendly",
  ["cursor.values.source.spell"] = "spell",
  ["cursor.values.source.sim"] = "simulation",
  ["cursor.preset.vitals"] = "Health, resource and range",
  ["cursor.preset.distance"] = "Distance text",
})
ns.AddLocale("deDE", {
  ["cursor.type.health"] = "Lebensring",
  ["cursor.type.power"] = "Ressourcenring",
  ["cursor.type.range"] = "Reichweite",
  ["cursor.type.health.desc"] = "Zeigt dein Leben als Ring, der sich damit füllt. Das Spiel verbirgt den genauen Wert, deshalb gibt es keine Zahl.",
  ["cursor.type.power.desc"] = "Zeigt dein Mana, deine Wut oder Energie als Ring. Das Spiel verbirgt den genauen Wert, deshalb gibt es keine Zahl.",
  ["cursor.type.range.desc"] = "Zeigt, ob dein Ziel in Reichweite ist, als Ring oder Punkt in drei Farben oder als Text mit dem Entfernungsbereich, zum Beispiel 20-25.",
  ["cursor.range.display"] = "Anzeige",
  ["cursor.range.display.shape"] = "Ring oder Punkt",
  ["cursor.range.display.text"] = "Text",
  ["cursor.range.display.both"] = "Ring oder Punkt und Text",
  ["cursor.range.textFormat"] = "Textformat",
  ["cursor.range.textFormat.band"] = "Bereich (20-25)",
  ["cursor.range.textFormat.upper"] = "Obergrenze (<=25)",
  ["cursor.range.textFormat.short"] = "Nur Zahl (25)",
  ["cursor.range.unknownText"] = "Text bei unbekannt",
  ["cursor.range.colorByBand"] = "Farbe nach Entfernung",
  ["cursor.range.textNote"] = "Der Text zeigt den Entfernungsbereich aus den Reichweitenprüfungen. Die Farben vergleichen ihn mit der gewählten Entfernung.",
  ["cursor.values.status"] = "Quelle: %s",
  ["cursor.values.status.none"] = "Quelle: kein Ziel",
  ["cursor.values.status.unknown"] = "Quelle: keine Antwort",
  ["cursor.values.status.notKnown"] = "Quelle: Zauber nicht bekannt",
  ["cursor.values.status.loading"] = "Quelle: Gegenstandsdaten werden geladen",
  ["cursor.values.status.itemsSilent"] = "Quelle: keine Antwort von Gegenständen",
  ["cursor.values.status.guarded"] = "Quelle: Kampf, freundliches Ziel eingeschränkt",
  ["cursor.values.source.interact3"] = "Interaktion 8 m",
  ["cursor.values.source.interact4"] = "Interaktion 28 m",
  ["cursor.values.source.item"] = "Gegenstand %d m (%s)",
  ["cursor.values.source.itemNear"] = "Gegenstand %d m (%s), nächste Stufe zu %d m",
  ["cursor.values.source.itemPlain"] = "Gegenstand",
  ["cursor.values.source.ladder"] = "Zauber",
  ["cursor.values.source.spellMelee"] = "Nahkampfzauber (%s)",
  ["cursor.values.source.spellBand"] = "Zauber %d m (%s)",
  ["cursor.values.relation.hostile"] = "feindlich",
  ["cursor.values.relation.friendly"] = "freundlich",
  ["cursor.values.source.spell"] = "Zauber",
  ["cursor.values.source.sim"] = "Simulation",
  ["cursor.preset.vitals"] = "Leben, Ressource und Reichweite",
  ["cursor.preset.distance"] = "Entfernungstext",
})
