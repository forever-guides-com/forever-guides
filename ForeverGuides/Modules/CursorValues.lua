-- The value elements of the mouse cursor ring (ns.CursorValues): the health ring, the resource ring and the
-- range indicator, drawn for CanvasRender and the layout editor (rules and data: CursorValuesLogic.lua).
--
-- The game hides the health and resource of the player from add-ons, so a ring never reads or computes with
-- such a value: it is handed to the engine untouched (StatusBar:SetValue, a radial texture percent, a colour
-- curve) and the code only ever calls issecretvalue on it. No number is shown on a ring for that reason.
-- The fill uses the first of three ways the client offers: a status bar in radial mode, a radial texture, a
-- plain bar. Events only set a dirty flag; a throttled OnUpdate runs only while there is something to feed.
-- The range indicator is a state (in, out, unknown) taken from readable answers, or a distance band as text
-- built from the same answers, never a measured distance. Its first source is a ladder of the player's own
-- spells, read from the spellbook while a range element is drawn.
local _, ns = ...
local U, L, CU, E, A, V = ns.U, ns.L, ns.CursorLogic, ns.CursorElements, ns.CursorAssets, ns.CursorValuesLogic
local XB = ns.XpBarLayout

local M = {}
ns.CursorValues = M

local FLUSH = 0.05 -- 20 Hz at most
local PULSE = 0.2 -- 5 Hz for the item and spell ladders
local PLAYER, TARGET = "player", "target"
local LINEAR_STEM = "fill-square"
local MAX_CURVES = 16

local EVENTS = {
  health = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
  power = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
  range = { "PLAYER_TARGET_CHANGED" },
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Game readings -----------------------------------------------------------------------------------------------

local function api(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn or nil
end

local function field(tableName, name)
  local t = rawget(_G, tableName)
  local fn = type(t) == "table" and t[name] or nil
  return type(fn) == "function" and fn or nil
end

-- Whether the client hides `value`. An answer that cannot be had counts as hidden.
local function isSecret(value)
  local check = api("issecretvalue")
  if not check then
    return false
  end
  local ok, hidden = pcall(check, value)
  return not ok or hidden == true
end

local function plain(value)
  if isSecret(value) then
    return nil
  end
  return value
end

-- true or false for a readable boolean, else nil.
local function boolOrNil(value)
  value = plain(value)
  if value == true or value == false then
    return value
  end
  return nil
end

-- The upper bound for a status bar: a hidden value goes to the engine as it is, a readable one is at least 1.
local function bound(value)
  if isSecret(value) then
    return value
  end
  return finite(value) and value >= 1 and value or 1
end

local function targetExists()
  local exists = api("UnitExists")
  return exists ~= nil and boolOrNil(exists(TARGET)) == true
end

local function targetAttackable()
  local can = api("UnitCanAttack")
  return can ~= nil and boolOrNil(can(PLAYER, TARGET)) == true
end

-- Capabilities --------------------------------------------------------------------------------------------------

local caps

-- What the client can do, found once by trying it on a throw-away bar and texture. path is the way the ring
-- is filled: "statusbar" (a status bar in radial mode), "texture" (a radial texture fed with a percent that
-- the game scales to 0..1), "linear" (a plain bar).
local function detect()
  local c = { path = "linear", curve = false }
  local enum = rawget(_G, "Enum")
  local modes = type(enum) == "table" and enum.StatusBarRenderMode or nil
  c.radialMode = type(modes) == "table" and modes.Radial or nil
  local constants = rawget(_G, "CurveConstants")
  c.zero = type(constants) == "table" and constants.ZeroToOne or nil
  local util = rawget(_G, "C_CurveUtil")
  c.curve = type(util) == "table" and type(util.CreateColorCurve) == "function" and api("CreateColor") ~= nil
  local okBar, bar = pcall(CreateFrame, "StatusBar", nil, UIParent)
  bar = okBar and type(bar) == "table" and bar or nil
  c.bar = bar ~= nil
    and type(bar.SetStatusBarTexture) == "function"
    and type(bar.SetMinMaxValues) == "function"
    and type(bar.SetValue) == "function"
  c.radialBar = c.bar
    and c.radialMode ~= nil
    and type(bar.SetRenderMode) == "function"
    and pcall(bar.SetRenderMode, bar, c.radialMode)
  local okTex, tex = pcall(function()
    return UIParent:CreateTexture()
  end)
  tex = okTex and type(tex) == "table" and tex or nil
  c.radialTexture = tex ~= nil
    and c.zero ~= nil
    and type(tex.SetRadialProgressBarPercent) == "function"
    and pcall(tex.SetRadialProgressBarPercent, tex, 0.5)
  if c.radialBar then
    c.path = "statusbar"
  elseif c.radialTexture then
    c.path = "texture"
  elseif not c.bar then
    c.path = "none"
  end
  -- The throw-away objects draw nothing, hidden all the same.
  if bar then
    pcall(bar.Hide, bar)
  end
  if tex then
    pcall(tex.Hide, tex)
  end
  return c
end

function M.Caps()
  if not caps then
    caps = detect()
  end
  return caps
end

-- Forgets what was found, for a client that changed or a test that changes the world.
function M.ResetCaps()
  caps = nil
end

-- A colour curve from the full colour at 100 percent to the low colour at LOW_AT and below, cached by colours;
-- nil when the client has no colour curves. The engine evaluates it, no Lua code compares the health.
local curves, curveCount = {}, 0

local function threatCurve(full, low)
  if not M.Caps().curve then
    return nil
  end
  local key = full .. ":" .. low
  local cached = curves[key]
  if cached ~= nil then
    return cached or nil
  end
  if curveCount >= MAX_CURVES then
    curves, curveCount = {}, 0
  end
  local ok, made = pcall(function()
    local curve = rawget(_G, "C_CurveUtil").CreateColorCurve()
    local enum = rawget(_G, "Enum")
    local kinds = type(enum) == "table" and enum.LuaCurveType or nil
    if type(kinds) == "table" and kinds.Linear ~= nil and type(curve.SetType) == "function" then
      curve:SetType(kinds.Linear)
    end
    local newColor = api("CreateColor")
    local fr, fg, fb = U.hex(full)
    local lr, lg, lb = U.hex(low)
    curve:AddPoint(0, newColor(lr, lg, lb, 1))
    curve:AddPoint(V.LOW_AT, newColor(lr, lg, lb, 1))
    curve:AddPoint(1, newColor(fr, fg, fb, 1))
    return curve
  end)
  curves[key] = ok and made or false
  curveCount = curveCount + 1
  return ok and made or nil
end

-- Element state ---------------------------------------------------------------------------------------------------

-- The drawing state kept on the element frame: the objects it made, the props of the last render and whether
-- it was drawn for the editor (plain preview values) or for the game (the real player).
local function stateOf(frame)
  local st = frame.fgValues
  if not st then
    st = { frame = frame }
    frame.fgValues = st
  end
  return st
end

local function sideOf(frame, element)
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not (finite(w) and finite(h) and w > 0 and h > 0) then
    w, h = element.w, element.h
  end
  return finite(w) and finite(h) and w > 0 and h > 0 and (w + h) / 2 or CU.Size("ring")[1]
end

local function share(v, default)
  return finite(v) and U.clamp(v, 0, 1) or default
end

-- Sets the tint of the fill; the values may be hidden, they go to the engine as they are.
local function tint(st, r, g, b)
  local alpha = st.cfg.alpha
  if st.fill == "bar" then
    st.bar:SetStatusBarColor(r, g, b, alpha)
  elseif st.fill == "texture" then
    st.tex:SetVertexColor(r, g, b, alpha)
  end
end

local function tintHex(st, color)
  local r, g, b = U.hex(color)
  tint(st, r, g, b)
end

-- The faint full ring (or strip) behind the fill, in the colour the ring has when full.
local function paintBackground(st, r, g, b)
  local bg, alpha = st.bg, st.cfg.bgAlpha
  if not bg then
    return
  end
  if alpha <= 0 then
    bg:Hide()
    return
  end
  if st.path == "linear" then
    bg:SetColorTexture(r, g, b, alpha)
  else
    bg:SetTexture(st.texture)
    bg:SetVertexColor(r, g, b, alpha)
  end
  bg:Show()
end

local function readPowerColor()
  local powerType = api("UnitPowerType")
  if not powerType then
    return V.PowerColor()
  end
  local kind, token, r, g, b = powerType(PLAYER)
  return V.PowerColor(plain(kind), plain(token), plain(r), plain(g), plain(b), rawget(_G, "PowerBarColor"))
end

-- The colour a ring has when full, from its mode.
local function baseColor(p)
  if p.colorMode == "power" then
    return readPowerColor()
  end
  return U.hex(p.color)
end

-- Radial extras (where a ring starts and which way it fills) on a radial texture, where the client has them.
local function radialExtras(region, p)
  if type(region) ~= "table" then
    return
  end
  local start = region.SetRadialProgressBarStartOffset
  if type(start) == "function" then
    pcall(start, region, p.startAngle / 360)
  end
  local reverse = region.SetRadialProgressBarReverse
  if type(reverse) == "function" then
    pcall(reverse, region, p.reverse)
  end
end

-- A region over the whole frame (ring) or over a strip across it (the plain bar).
local function place(st, region, p)
  region:ClearAllPoints()
  if st.path == "linear" then
    region:SetPoint("LEFT", st.frame, "LEFT", 0, 0)
    region:SetPoint("RIGHT", st.frame, "RIGHT", 0, 0)
    region:SetHeight(math.max(2, p.thickness))
  else
    region:SetAllPoints(st.frame)
  end
end

local function barOf(st)
  if not st.bar then
    st.bar = CreateFrame("StatusBar", nil, st.frame)
  end
  return st.bar
end

local function textureOf(st)
  if not st.tex then
    st.tex = st.frame:CreateTexture(nil, "ARTWORK")
  end
  return st.tex
end

-- Builds the objects of the way the client fills the ring and hides those of the others.
local function setupFill(st, p)
  local c = M.Caps()
  st.path = c.path
  if not st.bg then
    st.bg = st.frame:CreateTexture(nil, "BACKGROUND")
  end
  place(st, st.bg, p)
  if c.path == "statusbar" or c.path == "linear" then
    local bar = barOf(st)
    place(st, bar, p)
    bar:SetStatusBarTexture(c.path == "linear" and E.Texture(LINEAR_STEM) or st.texture)
    if c.path == "statusbar" then
      pcall(bar.SetRenderMode, bar, c.radialMode)
      radialExtras(bar:GetStatusBarTexture(), p)
    else
      pcall(bar.SetReverseFill, bar, p.reverse)
    end
    bar:Show()
    st.fill = "bar"
    if st.tex then
      st.tex:Hide()
    end
  elseif c.path == "texture" then
    local tex = textureOf(st)
    place(st, tex, p)
    tex:SetTexture(st.texture)
    radialExtras(tex, p)
    tex:Show()
    st.fill = "texture"
    if st.bar then
      st.bar:Hide()
    end
  else
    st.fill = nil
  end
end

-- The fill holds `value` of 0..1: plain numbers of the editor preview.
local function setShare(st, value)
  if st.fill == "texture" then
    st.tex:SetRadialProgressBarPercent(value)
  elseif st.fill == "bar" then
    st.bar:SetMinMaxValues(0, 1)
    st.bar:SetValue(value)
  end
end

-- Spellbook ladder ----------------------------------------------------------------------------------------------

-- The spells of the player as a ladder (see V.BuildLadder): built from the spellbook while a range element is
-- drawn for the game, kept until the spellbook changes.
local LADDER_EVENTS = { "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE" }
local MAX_BOOK_ITEMS = 2000
local ladder

local function number(value)
  value = plain(value)
  return finite(value) and value or nil
end

local function enumValue(group, name, default)
  local enum = rawget(_G, "Enum")
  local list = type(enum) == "table" and enum[group] or nil
  local value = type(list) == "table" and list[name] or nil
  return finite(value) and value or default
end

-- Whether the player knows the spell: true or false, nil when the client cannot say.
local function spellKnown(id)
  for _, name in ipairs({ "IsSpellKnownOrInSpellBook", "IsSpellKnown", "IsSpellInSpellBook" }) do
    local fn = field("C_SpellBook", name)
    if fn then
      local ok, answer = pcall(fn, id)
      if ok and boolOrNil(answer) ~= nil then
        return boolOrNil(answer)
      end
    end
  end
  return nil
end

-- The spell that stands in for `id` right now (a talent or an aura can replace a spell); `id` when none.
local function overrideOf(id)
  local find = field("C_SpellBook", "FindSpellOverrideByID")
  if find then
    local ok, replaced = pcall(find, id)
    replaced = ok and number(replaced) or nil
    if replaced and replaced > 0 then
      return replaced
    end
  end
  return id
end

-- { id, passive } of the player's spellbook, read through its skill lines and slots; nil when the client has
-- no such functions. Spells of another specialization and entries that are no spell are left out.
local function bookSpells()
  local count = field("C_SpellBook", "GetNumSpellBookSkillLines")
  local lineInfo = field("C_SpellBook", "GetSpellBookSkillLineInfo")
  local itemInfo = field("C_SpellBook", "GetSpellBookItemInfo")
  if not (count and lineInfo and itemInfo) then
    return nil
  end
  local bank = enumValue("SpellBookSpellBank", "Player", 0)
  local spell = enumValue("SpellBookItemType", "Spell", 1)
  local out = {}
  local okCount, lines = pcall(count)
  for index = 1, okCount and number(lines) or 0 do
    pcall(function()
      local line = lineInfo(index)
      if type(line) ~= "table" or isSecret(line) or line.offSpecID ~= nil then
        return
      end
      local offset, size = number(line.itemIndexOffset), number(line.numSpellBookItems)
      for slot = (offset or 0) + 1, (offset or 0) + (size or 0) do
        if #out >= MAX_BOOK_ITEMS then
          return
        end
        local item = itemInfo(slot, bank)
        if
          type(item) == "table"
          and not isSecret(item)
          and plain(item.itemType) == spell
          and item.isOffSpec ~= true
        then
          local id = number(item.spellID) or number(item.actionID)
          if id then
            out[#out + 1] = { id = id, passive = plain(item.isPassive) == true }
          end
        end
      end
    end)
  end
  return out
end

-- Without a readable spellbook: the spells of the class from the add-on's own data that the player's level
-- allows (and the client does not call unknown), highest rank first.
local function dataSpells()
  local data = ns.DataApi
  local unitClass = api("UnitClass")
  if not (data and type(data.SpellsForClass) == "function" and unitClass) then
    return nil
  end
  local okClass, _, class = pcall(unitClass, PLAYER)
  if not (okClass and type(plain(class)) == "string") then
    return nil
  end
  local unitLevel = api("UnitLevel")
  local okLevel, level = pcall(unitLevel or function() end, PLAYER)
  level = okLevel and number(level) or nil
  local found = {}
  for _, entry in ipairs(data.SpellsForClass(class)) do
    if entry.k == "spell" and finite(entry.id) and (level == nil or entry.l == nil or entry.l <= level) then
      if spellKnown(entry.id) ~= false then
        found[#found + 1] = { id = entry.id, passive = false }
      end
    end
  end
  local out = {}
  for i = #found, 1, -1 do
    out[#out + 1] = found[i]
  end
  return out
end

-- The facts of one spell the ladder needs. `id` is what the spell is replaced by right now, `base` what the
-- book listed.
local function describe(base, passive)
  local id = overrideOf(base)
  local entry = { id = id, base = base }
  local info = field("C_Spell", "GetSpellInfo")
  if info then
    local ok, data = pcall(info, id)
    if ok and type(data) == "table" and not isSecret(data) then
      pcall(function()
        local name = plain(data.name)
        entry.name = type(name) == "string" and name or nil
        entry.minRange, entry.maxRange = number(data.minRange), number(data.maxRange)
      end)
    end
  end
  local function flag(name)
    local fn = field("C_Spell", name)
    if fn then
      local ok, answer = pcall(fn, id)
      if ok then
        return boolOrNil(answer)
      end
    end
    return nil
  end
  entry.harmful, entry.helpful = flag("IsSpellHarmful"), flag("IsSpellHelpful")
  entry.passive = passive == true or flag("IsSpellPassive") == true
  return entry
end

-- Reads the spellbook (or, without one, the class data) fresh: { origin = "spellbook", "data" or "none",
-- entries = the facts per spell, ladder }. The probe calls this too.
function M.ReadSpellbook()
  local list, origin = bookSpells(), "spellbook"
  if not list or #list == 0 then
    list, origin = dataSpells(), "data"
  end
  local entries, seen = {}, {}
  for _, item in ipairs(list or {}) do
    local entry = describe(item.id, item.passive)
    if not seen[entry.id] then
      seen[entry.id] = true
      entries[#entries + 1] = entry
    end
  end
  return { origin = list and origin or "none", entries = entries, ladder = V.BuildLadder(entries) }
end

-- The cached ladder; an empty one when the spellbook cannot be read.
function M.Ladder()
  if not ladder then
    local ok, book = pcall(M.ReadSpellbook)
    ladder = ok and type(book) == "table" and book.ladder or V.NewLadder()
  end
  return ladder
end

-- Whether a ladder is cached (for tests).
function M.LadderCached()
  return ladder ~= nil
end

-- Range ---------------------------------------------------------------------------------------------------------

-- The relation of the target for the item ladder: hostile, friendly, or nil when the game names neither.
local function targetRelation()
  local isFriend = api("UnitIsFriend")
  local friend = isFriend ~= nil and boolOrNil(isFriend(PLAYER, TARGET)) or nil
  return V.Relation(targetAttackable(), friend)
end

-- Whether the player is in combat lockdown (false when the client cannot say).
local function inLockdown()
  local lock = api("InCombatLockdown")
  if not lock then
    return false
  end
  local ok, locked = pcall(function()
    return lock()
  end)
  return ok and boolOrNil(locked) == true
end

-- What the last range evaluation met: whether an item source was asked and whether the combat guard held a
-- call back.
local trace = { items = false, guarded = false }

-- The one place that calls an item or interact distance function. In combat lockdown a target that cannot be
-- attacked makes the client raise a blocked-call error, so the call is skipped then (spells have no such
-- limit). Returns true, false, or nil when there is no answer.
local function askProtected(fn, a, b)
  if not fn then
    return nil
  end
  if inLockdown() and not targetAttackable() then
    trace.guarded = true
    return nil
  end
  local ok, answer = pcall(function()
    return fn(a, b)
  end)
  if ok then
    return boolOrNil(answer)
  end
  return nil
end

-- Item data requests: every ladder item is requested once per session while a range element is drawn (the
-- request is cheap and an item without data may answer nil). GET_ITEM_INFO_RECEIVED marks an id as received
-- and the element is evaluated again. A request counts as pending for V.LOAD_SECONDS after the first one.
local requested, received, pendingSince = {}, {}, nil

local function clock()
  local now = api("GetTime")
  local ok, t = pcall(function()
    return now and now()
  end)
  return ok and number(t) or 0
end

local function requestItems()
  local request = field("C_Item", "RequestLoadItemDataByID")
  if not request then
    return
  end
  for _, id in ipairs(V.AllItemIds()) do
    if not requested[id] then
      requested[id] = true
      pendingSince = pendingSince or clock()
      pcall(function()
        request(id)
      end)
    end
  end
end

-- Whether a requested item has not answered with its data yet and the wait is not over.
local function itemsLoading()
  if not pendingSince or clock() - pendingSince >= V.LOAD_SECONDS then
    return false
  end
  for id in pairs(requested) do
    if not received[id] then
      return true
    end
  end
  return false
end

-- Forgets the requests, for a test that changes the world.
function M.ResetItemRequests()
  requested, received, pendingSince = {}, {}, nil
end

-- The answer of one spell of the ladder for the target: true, false, or nil.
local function askLadderSpell(spell)
  local inRange = field("C_Spell", "IsSpellInRange")
  if inRange then
    local ok, answer = pcall(inRange, spell, TARGET)
    if ok then
      return boolOrNil(answer)
    end
  end
  return nil
end

-- One item check, asked once per evaluation: `memo` keeps the answer (or the lack of one) by item id, so the
-- chain and the distance text never ask an id twice in a tick.
local function askItem(memo, fn, id)
  local hit = memo[id]
  if hit == nil then
    hit = { askProtected(fn, id, TARGET) }
    memo[id] = hit
  end
  return hit[1]
end

-- What one source of the chain says about the target: true, false, or nil when it cannot tell (the call is
-- missing, fails, or answers something that is not a readable boolean); an item or a spell of the ladder
-- also hands back its band. `band` is the band asked for (V.EffectiveBand).
local function askSource(id, p, relation, band, memo)
  local def = V.SOURCES[id]
  if not def then
    return nil
  end
  if def.kind == "interact" then
    return askProtected(api("CheckInteractDistance"), TARGET, def.index)
  elseif def.kind == "item" then
    local itemInRange = field("C_Item", "IsItemInRange")
    if itemInRange then
      trace.items = true
      return V.AskItems(relation, band, function(item)
        return askItem(memo, itemInRange, item)
      end)
    end
  elseif def.kind == "ladder" then
    return V.AskSpells(M.Ladder(), relation, band, askLadderSpell)
  elseif def.kind == "spell" then
    local inRange = field("C_Spell", "IsSpellInRange")
    if inRange and p.spellId > 0 then
      return boolOrNil(inRange(overrideOf(p.spellId), TARGET))
    end
  end
  return nil
end

-- The details of an evaluation that nothing answered: the combat guard held a call back, or the items said
-- nothing (still loading or silent). nil when no item was asked.
local function silentInfo()
  if trace.guarded then
    return { guarded = true }
  elseif trace.items then
    return { items = itemsLoading() and "loading" or "silent" }
  end
  return nil
end

-- The chain of the mode for the target: the state ("in", "out", "unknown"), the id of the source that answered
-- and its details.
local function chainState(p, relation, memo)
  -- A player with a melee spell that answers for this target gets the melee reach as the default band; the
  -- candidates alone prove nothing (a spell without a target answers nil).
  local hasMelee = p.mode ~= "melee"
    and p.band == 0
    and relation ~= "friendly"
    and V.Asks(p.mode, "ladder")
    and V.AskSpells(M.Ladder(), "hostile", V.MELEE_YARDS, askLadderSpell) ~= nil
  local band = V.EffectiveBand(p.mode, p.band, relation, hasMelee)
  local state, source, info = V.Resolve(V.Chain(p.mode, relation, band), function(id)
    return askSource(id, p, relation, band, memo)
  end)
  if state == "unknown" then
    if p.mode == "spell" and p.spellId > 0 then
      -- A spell the player does not have never answers; say so instead of "no answer".
      if spellKnown(p.spellId) == false and spellKnown(overrideOf(p.spellId)) ~= true then
        info = { notKnown = true }
      end
    else
      info = silentInfo() or info
    end
  end
  return state, source, info
end

-- The distance text of a range element: the answers of every item band of the ladder (nearest first, up to the
-- first that says true), the interact distances when no item answered and the melee spell when those are
-- silent too, turned into the band text. Returns { state, source, info, text, band, chosen } where state, source
-- and info describe the answer the way the chain does (for the status line).
local function textView(p, relation, memo)
  local answers, anyItem = {}, false
  local itemInRange = field("C_Item", "IsItemInRange")
  if itemInRange then
    trace.items = true
    for _, step in ipairs(V.TextBands(relation)) do
      local answer = V.FirstAnswer(step.items, function(id)
        return askItem(memo, itemInRange, id)
      end)
      answers[step.yards] = answer
      anyItem = anyItem or answer ~= nil
      if answer == true then
        break
      end
    end
  end
  if not anyItem then
    local interact = api("CheckInteractDistance")
    answers.interact3 = askProtected(interact, TARGET, 3)
    if answers.interact3 ~= true then
      answers.interact4 = askProtected(interact, TARGET, 4)
    end
    if answers.interact3 == nil and answers.interact4 == nil and relation ~= "friendly" then
      answers.melee = V.AskSpells(M.Ladder(), "hostile", V.MELEE_YARDS, askLadderSpell)
    end
  end
  local text, band = V.BandText(answers, relation, p.textFormat, p.unknownText)
  local chosen = V.TextThreshold(p.mode, p.band, relation)
  local view = { state = V.TextState(band, chosen), text = text, band = band, chosen = chosen }
  if not band then
    view.info = silentInfo()
  elseif band.source == "item" then
    local yards = band.hi or band.lo
    view.source = "item"
    view.info = { band = yards, wanted = yards, relation = relation or "hostile" }
  elseif band.source == "melee" then
    view.source, view.info = "ladder", { kind = "melee", relation = "hostile" }
  else
    view.source = band.source
  end
  return view
end

-- "in", "out", "unknown" for the target of a range element, or "none" when nothing is to be shown (no target,
-- or no hostile one where that is asked for), the id of the source that answered and its details. An element that
-- shows text gets its distance text as the fourth value; with text alone the text decides the state.
local function rangeState(p)
  if not targetExists() then
    return "none"
  end
  if p.hostileOnly and not targetAttackable() then
    return "none"
  end
  trace.items, trace.guarded = false, false
  local relation = targetRelation()
  local memo = {}
  local state, source, info
  if p.display ~= "text" then
    state, source, info = chainState(p, relation, memo)
    if p.display == "shape" then
      return state, source, info
    end
  end
  local view = textView(p, relation, memo)
  if p.display == "text" then
    return view.state, view.source, view.info, view
  end
  return state, source, info, view
end

-- The status line of the range panel shows where the last answer came from. Only the element of the game
-- (or, while none is drawn for the game, the editor preview) writes it.
local status, statusText

local function showStatus()
  if statusText then
    statusText:SetText(
      V.StatusText(status and status.state or "none", status and status.source, status and status.info)
    )
  end
end

local function publish(state, source, info)
  status = { state = state, source = source, info = info }
  showStatus()
end

-- The text of a range element: made on first use, its font set before any text goes in. The font is applied
-- again only when font, size or outline changed.
local function textOf(st)
  local p = st.cfg
  local fs = st.rangeText
  if not fs then
    fs = st.frame:CreateFontString(nil, "OVERLAY")
    st.rangeText = fs
  end
  local key = p.font .. "|" .. p.fontSize .. "|" .. p.outline
  if key ~= st.fontKey then
    st.fontKey = key
    XB.ApplyFont(fs, { font = p.font, size = p.fontSize, outline = p.outline })
  end
  return fs
end

-- Places the text on the bottom edge of the frame (inside it for text alone, below it next to the ring or dot),
-- so a taller frame moves it away from the centre.
local function layoutText(st)
  local fs, p = textOf(st), st.cfg
  fs:SetJustifyH("CENTER")
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  fs:ClearAllPoints()
  if p.display == "both" then
    fs:SetPoint("TOP", st.frame, "BOTTOM", 0, -2)
  else
    fs:SetPoint("BOTTOM", st.frame, "BOTTOM", 0, 0)
  end
end

local function paintText(st, view)
  local p, fs = st.cfg, st.rangeText
  if p.display == "shape" or not view then
    if fs then
      fs:Hide()
    end
    return
  end
  fs = textOf(st)
  local r, g, b = V.TextColor(p, view.band, view.chosen)
  fs:SetTextColor(r, g, b, p.alpha)
  ns.WindowStyle.ApplyShadow(fs, p.shadow, r, g, b)
  fs:SetText(view.text)
  fs:Show()
end

-- Paints what `held` says ({ state, view }): the ring or dot in the colour of the state unless the element shows
-- text alone, the text from the view.
local function paintRange(st, held)
  local tex, p = st.rangeTex, st.cfg
  local state = held.state
  if state == "none" then
    tex:Hide()
    paintText(st, nil)
    return
  end
  if p.display == "text" then
    tex:Hide()
  else
    local color = state == "in" and p.colorIn or state == "out" and p.colorOut or p.colorUnknown
    local r, g, b = U.hex(color)
    tex:SetVertexColor(r, g, b, p.alpha)
    tex:Show()
  end
  paintText(st, held.view)
end

-- Feeding the game's values ---------------------------------------------------------------------------------

local function feedHealth(st)
  local p, c = st.cfg, M.Caps()
  local percent = api("UnitHealthPercent")
  if st.fill == "texture" then
    if percent then
      st.tex:SetRadialProgressBarPercent(percent(PLAYER, true, c.zero))
    end
  elseif st.fill == "bar" then
    local health, maxHealth = api("UnitHealth"), api("UnitHealthMax")
    if health and maxHealth then
      st.bar:SetMinMaxValues(0, bound(maxHealth(PLAYER)))
      st.bar:SetValue(health(PLAYER))
    end
  end
  if p.colorMode == "threat" and percent then
    local curve = threatCurve(p.color, p.lowColor)
    if curve then
      local color = percent(PLAYER, true, curve)
      if type(color) == "table" and not isSecret(color) then
        local r, g, b
        if type(color.GetRGB) == "function" then
          r, g, b = color:GetRGB()
        else
          r, g, b = color.r, color.g, color.b
        end
        tint(st, r, g, b)
        return
      end
    end
  end
  tintHex(st, p.color)
end

local function feedPower(st)
  local p, c = st.cfg, M.Caps()
  local typeOf = api("UnitPowerType")
  local kind = typeOf and plain((typeOf(PLAYER))) or nil
  if st.fill == "texture" then
    local percent = api("UnitPowerPercent")
    if percent then
      st.tex:SetRadialProgressBarPercent(percent(PLAYER, true, c.zero))
    end
  elseif st.fill == "bar" then
    local power, maxPower = api("UnitPower"), api("UnitPowerMax")
    if power and maxPower then
      st.bar:SetMinMaxValues(0, bound(maxPower(PLAYER, kind)))
      st.bar:SetValue(power(PLAYER, kind))
    end
  end
  local r, g, b = baseColor(p)
  if p.colorMode == "fixed" then
    r, g, b = U.hex(p.color)
  end
  tint(st, r, g, b)
  paintBackground(st, r, g, b)
end

-- Set while a differing range answer waits to be confirmed: the OnUpdate script then evaluates again after
-- V.SETTLE_SECONDS, also for sources that have no 5 Hz tick.
local settling, settleAcc = false, 0

local function feed(st)
  if st.kind == "health" then
    feedHealth(st)
  elseif st.kind == "power" then
    feedPower(st)
  else
    local state, source, info, view = rangeState(st.cfg)
    -- A changed answer shows only once it holds, so answers that alternate do not flash. The text is part of
    -- what has to hold.
    local key = view and state .. "|" .. view.text or state
    local shown, pending = V.Settle(st.shown, st.pending, key)
    st.shown, st.pending = shown, pending
    if pending then
      settling = true
    end
    if shown == key then
      st.held = { state = state, source = source, info = info, view = view }
    end
    paintRange(st, st.held)
    publish(st.held.state, st.held.source, st.held.info)
  end
end

-- Rendering -------------------------------------------------------------------------------------------------------

local active = {} -- frame -> state of the elements that listen to the game
local sync

local function renderRing(kind, frame, element, ctx)
  local p = CU.Props(kind, element.props, { element.w, element.h })
  local st = stateOf(frame)
  st.kind, st.cfg, st.editor = kind, p, type(ctx) == "table" and ctx.editor == true
  st.texture = E.Texture(A.NearestStroke(p.shape, p.thickness, sideOf(frame, element)) or A.RingStem(p.shape, 4))
  setupFill(st, p)
  if st.editor then
    local sim = type(ctx.sim) == "table" and ctx.sim or {}
    local value = share(sim[kind], V.SAMPLE[kind])
    setShare(st, value)
    local r, g, b = baseColor(p)
    if p.colorMode == "threat" then
      r, g, b = V.ThreatColor(value, p.color, p.lowColor)
    end
    tint(st, r, g, b)
    paintBackground(st, baseColor(p))
    return
  end
  if kind == "health" then
    paintBackground(st, U.hex(p.color))
  end
  -- The first values come with drive; a redraw of a driven element feeds again, its props may have changed.
  if active[frame] then
    ns.Safe("cursorvalues." .. kind, feed, st)
    sync()
  end
end

local function renderHealth(frame, element, ctx)
  renderRing("health", frame, element, ctx)
end

local function renderPower(frame, element, ctx)
  renderRing("power", frame, element, ctx)
end

-- Whether a range element is drawn for the game right now.
local function rangeDrawn()
  for _, st in pairs(active) do
    if st.kind == "range" then
      return true
    end
  end
  return false
end

local function renderRange(frame, element, ctx)
  local p = CU.Props("range", element.props)
  local st = stateOf(frame)
  st.kind, st.cfg, st.editor = "range", p, type(ctx) == "table" and ctx.editor == true
  -- A draw follows an edit or a new layout: its first answer shows at once.
  st.shown, st.pending = nil, nil
  if not st.rangeTex then
    st.rangeTex = frame:CreateTexture(nil, "ARTWORK")
    st.rangeTex:SetAllPoints(frame)
  end
  local stem = p.style == "dot" and A.RingStem("circle")
    or A.NearestStroke("circle", p.thickness, sideOf(frame, element))
  st.rangeTex:SetTexture(E.Texture(stem or A.RingStem("circle", 4)))
  if p.display == "shape" then
    paintText(st, nil)
  else
    layoutText(st)
  end
  if st.editor then
    local sim = type(ctx.sim) == "table" and ctx.sim or {}
    local state, view = sim.rangeIn == false and "out" or "in", nil
    if p.display ~= "shape" then
      -- The preview renders from a distance in yards, the way the game renders from the answers.
      local yards = finite(sim.rangeYards) and sim.rangeYards or V.SAMPLE_YARDS
      local text, band = V.BandText(V.AnswersFromYards(yards, "hostile"), "hostile", p.textFormat, p.unknownText)
      view = { text = text, band = band, chosen = V.TextThreshold(p.mode, p.band, "hostile") }
      if p.display == "text" then
        state = V.TextState(band, view.chosen)
      end
    end
    paintRange(st, { state = state, view = view })
    if not rangeDrawn() then
      publish(state, "sim")
    end
    return
  end
  if active[frame] then
    ns.Safe("cursorvalues.range", feed, st)
    sync()
  end
end

-- Listening -------------------------------------------------------------------------------------------------------

local watcher
local registered = {} -- event -> true
local spellOn = {} -- spell id -> true
local dirty, scripted, pulseOn = false, false, false
local acc, pulse = 0, 0

local function flush()
  for _, st in pairs(active) do
    ns.Safe("cursorvalues." .. st.kind, feed, st)
  end
end

local function onUpdate(_, elapsed)
  acc = acc + elapsed
  if dirty and acc >= FLUSH then
    acc, dirty = 0, false
    flush()
  end
  if pulseOn then
    pulse = pulse + elapsed
    if pulse >= PULSE then
      pulse, dirty = 0, true
    end
  end
  if settling then
    settleAcc = settleAcc + elapsed
    if settleAcc >= V.SETTLE_SECONDS then
      settleAcc, settling, dirty = 0, false, true
    end
  end
  if not dirty and not pulseOn and not settling then
    scripted = false
    watcher:SetScript("OnUpdate", nil)
  end
end

local function arm()
  if watcher and not scripted then
    scripted = true
    watcher:SetScript("OnUpdate", onUpdate)
  end
end

local function onEvent(_, event, ...)
  if event == "GET_ITEM_INFO_RECEIVED" then
    local id = number((...))
    if not (id and requested[id] and not received[id]) then
      return
    end
    received[id] = true
  elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_LOGIN" then
    ladder = nil
  end
  dirty = true
  if event == "PLAYER_TARGET_CHANGED" then
    -- A new target shows its first answer at once.
    for _, st in pairs(active) do
      st.shown, st.pending = nil, nil
    end
    sync()
  end
  arm()
end

local function listen(event)
  local ok
  if event:find("^UNIT_") then
    ok = pcall(watcher.RegisterUnitEvent, watcher, event, PLAYER)
  else
    ok = pcall(watcher.RegisterEvent, watcher, event)
  end
  if not ok then
    ns.Log.warn("event %s not available", event)
  end
  registered[event] = true
end

-- Brings the registrations, the range checks of the game and the item ticker in line with the elements that
-- are drawn for the game. Nothing stays on when none is left.
function sync()
  local want, any = { events = {}, spells = {}, pulse = false, ladder = false, items = false }, false
  for _, st in pairs(active) do
    any = true
    for _, event in ipairs(EVENTS[st.kind]) do
      want.events[event] = true
    end
    local p = st.cfg
    if st.kind == "range" then
      -- The distance text asks the item ladder, the interact distances and the melee spell on every tick.
      local text = p.display ~= "shape"
      if text or V.Asks(p.mode, "item") then
        want.items = true
        want.events.GET_ITEM_INFO_RECEIVED = true
      end
      if p.display ~= "text" and V.Asks(p.mode, "spell") and p.spellId > 0 then
        want.spells[overrideOf(p.spellId)] = true
        want.events.SPELL_RANGE_CHECK_UPDATE = true
      end
      if text or V.Asks(p.mode, "ladder") then
        want.ladder = true
        for _, event in ipairs(LADDER_EVENTS) do
          want.events[event] = true
        end
      end
      if text or V.Polls(p.mode) then
        want.pulse = true
      end
    end
  end
  if any and not watcher then
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", ns.Wrap("cursorvalues-event", onEvent))
  end
  for event in pairs(want.events) do
    if not registered[event] then
      listen(event)
    end
  end
  for event in pairs(registered) do
    if not want.events[event] then
      watcher:UnregisterEvent(event)
      registered[event] = nil
    end
  end
  if want.items then
    requestItems()
  end
  local spell = field("C_Spell", "EnableSpellRangeCheck")
  if spell then
    for id in pairs(want.spells) do
      if not spellOn[id] then
        ns.Safe("cursorvalues.spell", spell, id, true)
      end
    end
    for id in pairs(spellOn) do
      if not want.spells[id] then
        ns.Safe("cursorvalues.spell", spell, id, false)
      end
    end
  end
  spellOn = want.spells
  if not want.ladder then
    ladder = nil
  end
  pulseOn = want.pulse and targetExists()
  if not any then
    dirty, settling = false, false
  end
  if pulseOn or settling then
    arm()
  elseif not dirty and scripted then
    scripted = false
    watcher:SetScript("OnUpdate", nil)
  end
end

-- Runs once after the first draw of an element for the game: from now on the game's events keep it current.
local function drive(frame)
  local st = frame.fgValues
  if not st or st.editor then
    return
  end
  active[frame] = st
  sync()
  ns.Safe("cursorvalues." .. st.kind, feed, st)
end

local function release(frame)
  if active[frame] then
    active[frame] = nil
    sync()
    if not rangeDrawn() then
      status = nil
      showStatus()
    end
  end
end

-- The frame that holds the event registrations, nil until an element was drawn for the game.
function M.Watcher()
  return watcher
end

function M.ActiveCount()
  local n = 0
  for _ in pairs(active) do
    n = n + 1
  end
  return n
end

function M.IsDirty()
  return dirty
end

-- The state and source of the last range answer ("sim" while only the editor preview is drawn), nil when
-- there is none.
function M.Status()
  if status then
    return status.state, status.source, status.info
  end
  return nil
end

function M.SpellChecks()
  local out = {}
  for id in pairs(spellOn) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

-- Editor panels ---------------------------------------------------------------------------------------------------

local NOTE_HEIGHT = 64
local BAND_NOTE_HEIGHT = 48

ns.AddLocale("enUS", {
  ["cursor.values.note"] = "The game hides health and resource values from add-ons, so these rings show no numbers.",
  ["cursor.values.start"] = "Starts at",
  ["cursor.values.start.0"] = "Top",
  ["cursor.values.start.90"] = "Right",
  ["cursor.values.start.180"] = "Bottom",
  ["cursor.values.start.270"] = "Left",
  ["cursor.values.reverse"] = "Fill counterclockwise",
  ["cursor.values.colorMode"] = "Color mode",
  ["cursor.values.colorMode.threat"] = "Turns red when low",
  ["cursor.values.colorMode.fixed"] = "Fixed color",
  ["cursor.values.colorMode.power"] = "Color of the resource",
  ["cursor.values.lowColor"] = "Low health color",
  ["cursor.values.background"] = "Background ring",
  ["cursor.values.rangeMode"] = "Range check",
  ["cursor.values.rangeMode.auto"] = "Automatic (recommended)",
  ["cursor.values.rangeMode.melee"] = "Melee (about 5 yards)",
  ["cursor.values.rangeMode.band"] = "By distance (spells and items)",
  ["cursor.values.rangeMode.near8"] = "Close (about 8 yards)",
  ["cursor.values.rangeMode.far28"] = "Far (about 28 yards)",
  ["cursor.values.rangeMode.spell"] = "Spell",
  ["cursor.values.band"] = "Distance",
  ["cursor.values.band.default"] = "Default (by target)",
  ["cursor.values.bandText"] = "%d yards",
  ["cursor.values.bandNote"] = "Only distances with a confirmed check are offered. Any other value uses the nearest one.",
  ["cursor.values.spellId"] = "Spell ID",
  ["cursor.values.rangeStyle"] = "Look",
  ["cursor.values.rangeStyle.ring"] = "Ring",
  ["cursor.values.rangeStyle.dot"] = "Dot",
  ["cursor.values.hostileOnly"] = "Only with a hostile target",
  ["cursor.values.colorIn"] = "In range",
  ["cursor.values.colorOut"] = "Out of range",
  ["cursor.values.colorUnknown"] = "Unknown",
})
ns.AddLocale("deDE", {
  ["cursor.values.note"] = "Das Spiel verbirgt Lebens- und Ressourcenwerte vor Addons, deshalb zeigen diese Ringe keine Zahlen.",
  ["cursor.values.start"] = "Beginnt bei",
  ["cursor.values.start.0"] = "Oben",
  ["cursor.values.start.90"] = "Rechts",
  ["cursor.values.start.180"] = "Unten",
  ["cursor.values.start.270"] = "Links",
  ["cursor.values.reverse"] = "Gegen den Uhrzeigersinn füllen",
  ["cursor.values.colorMode"] = "Farbmodus",
  ["cursor.values.colorMode.threat"] = "Wird rot bei wenig Leben",
  ["cursor.values.colorMode.fixed"] = "Feste Farbe",
  ["cursor.values.colorMode.power"] = "Farbe der Ressource",
  ["cursor.values.lowColor"] = "Farbe bei wenig Leben",
  ["cursor.values.background"] = "Hintergrundring",
  ["cursor.values.rangeMode"] = "Reichweitenprüfung",
  ["cursor.values.rangeMode.auto"] = "Automatisch (empfohlen)",
  ["cursor.values.rangeMode.melee"] = "Nahkampf (etwa 5 Meter)",
  ["cursor.values.rangeMode.band"] = "Nach Entfernung (Zauber und Gegenstände)",
  ["cursor.values.rangeMode.near8"] = "Nah (etwa 8 Meter)",
  ["cursor.values.rangeMode.far28"] = "Weit (etwa 28 Meter)",
  ["cursor.values.rangeMode.spell"] = "Zauber",
  ["cursor.values.band"] = "Entfernung",
  ["cursor.values.band.default"] = "Standard (nach Ziel)",
  ["cursor.values.bandText"] = "%d Meter",
  ["cursor.values.bandNote"] = "Es gibt nur Entfernungen mit bestätigter Prüfung. Jeder andere Wert nutzt die nächste davon.",
  ["cursor.values.spellId"] = "Zauber-ID",
  ["cursor.values.rangeStyle"] = "Aussehen",
  ["cursor.values.rangeStyle.ring"] = "Ring",
  ["cursor.values.rangeStyle.dot"] = "Punkt",
  ["cursor.values.hostileOnly"] = "Nur mit feindlichem Ziel",
  ["cursor.values.colorIn"] = "In Reichweite",
  ["cursor.values.colorOut"] = "Außer Reichweite",
  ["cursor.values.colorUnknown"] = "Unbekannt",
})

local function controls()
  return ns.CanvasEditor.Controls
end

local function newPanel(parent, kind, element, onChange, build)
  return controls().NewPanel(parent, {
    element = element,
    onChange = onChange,
    build = build,
    props = function(raw, current)
      return CU.Props(kind, raw, current and { current.w, current.h })
    end,
  })
end

-- Rows that show or hide with a prop need the panel stacked again after a write.
local function restack(state)
  local panel = state.panel
  if type(rawget(panel, "Refresh")) == "function" then
    panel:Refresh()
  end
end

local function when(add, shown)
  return function(frame, height)
    return add(frame, height, shown)
  end
end

local function note(state, add, key, height, shown)
  local row = CreateFrame("Frame", nil, state.panel)
  local text = ns.W.Text(row, { key = key or "cursor.values.note", role = "ui", color = "textSecondary", wrap = true })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  text:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  add(row, height or NOTE_HEIGHT, shown)
end

-- One muted line that says where the range answer comes from; showStatus keeps it current.
local STATUS_HEIGHT = 20

local function statusRow(state, add)
  local row = CreateFrame("Frame", nil, state.panel)
  statusText = ns.W.Text(row, { role = "ui", color = "textSecondary" })
  statusText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
  statusText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  showStatus()
  add(row, STATUS_HEIGHT)
end

local function choiceRow(state, add, label, key, options, shown)
  local C = controls()
  add(
    C.Choice(state.panel, {
      label = label,
      options = options,
      get = function()
        return state.get(key)
      end,
      set = function(value)
        state.write(key, value)
        restack(state)
      end,
    }),
    C.HEIGHT.choice,
    shown
  )
end

local function sliderRow(state, add, label, key, min, max, step, format, shown)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = label,
      min = min,
      max = max,
      step = step,
      get = function()
        return state.get(key)
      end,
      set = function(v)
        state.write(key, v)
      end,
      format = format,
    }),
    C.HEIGHT.slider,
    shown
  )
end

local function percentText(v)
  return v .. "%"
end

-- A slider in percent for a prop that holds 0..1.
local function percentRow(state, add, label, key, shown)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = label,
      min = 0,
      max = 100,
      step = 5,
      get = function()
        return math.floor(state.get(key) * 100 + 0.5)
      end,
      set = function(v)
        state.write(key, v / 100)
      end,
      format = percentText,
    }),
    C.HEIGHT.slider,
    shown
  )
end

local function colorAlphaRow(state, add, label, colorKey, shown)
  local C = controls()
  add(
    C.ColorAlpha(state.panel, {
      label = label,
      owner = state.owner(),
      default = "ffffff",
      get = function()
        return state.get(colorKey)
      end,
      alpha = function()
        return state.get("alpha")
      end,
      set = function(color, alpha)
        state.write(colorKey, color)
        state.write("alpha", alpha)
      end,
    }),
    C.HEIGHT.colorAlpha,
    shown
  )
end

local function shapeRow(state, add)
  local items = {}
  for i, shape in ipairs(A.SHAPES) do
    items[i] = { shape.id, A.RingStem(shape.id, 4), shape.key }
  end
  local gallery = controls().Gallery(state.panel, {
    label = "cursor.panel.shape",
    items = items,
    resolve = E.Texture,
    get = function()
      return state.get("shape")
    end,
    set = function(value)
      state.write("shape", value)
    end,
  })
  add(gallery, gallery:GetHeight())
end

local function ringPanel(kind, modes, parent, element, onChange)
  return newPanel(parent, kind, element, onChange, function(state, add)
    local C = controls()
    note(state, add)
    shapeRow(state, add)
    sliderRow(
      state,
      add,
      "cursor.panel.thickness",
      "thickness",
      CU.RING_THICKNESS_MIN,
      CU.RING_THICKNESS_MAX,
      1,
      function(v)
        return v .. " px"
      end
    )
    choiceRow(state, add, "cursor.values.start", "startAngle", C.Choices(V.START_ANGLES, "cursor.values.start."))
    C.ToggleRow(state, add, "cursor.values.reverse", "reverse")
    choiceRow(state, add, "cursor.values.colorMode", "colorMode", C.Choices(modes, "cursor.values.colorMode."))
    local function fixed()
      return state.get("colorMode") ~= "power"
    end
    colorAlphaRow(state, add, "cursor.panel.color", "color", fixed)
    percentRow(state, add, "canvas.opacity", "alpha", function()
      return not fixed()
    end)
    if kind == "health" then
      C.ColorRow(
        state,
        when(add, function()
          return state.get("colorMode") == "threat"
        end),
        "cursor.values.lowColor",
        "lowColor",
        "e5484d"
      )
    end
    percentRow(state, add, "cursor.values.background", "bgAlpha")
  end)
end

function M.HealthPanel(parent, element, onChange)
  return ringPanel("health", V.HEALTH_MODES, parent, element, onChange)
end

function M.PowerPanel(parent, element, onChange)
  return ringPanel("power", V.POWER_MODES, parent, element, onChange)
end

function M.RangePanel(parent, element, onChange)
  return newPanel(parent, "range", element, onChange, function(state, add)
    local C = controls()
    choiceRow(state, add, "cursor.range.display", "display", C.Choices(V.DISPLAYS, "cursor.range.display."))
    local function shapeShown()
      return state.get("display") ~= "text"
    end
    local function textShown()
      return state.get("display") ~= "shape"
    end
    choiceRow(state, add, "cursor.values.rangeMode", "mode", C.Choices(V.RANGE_MODES, "cursor.values.rangeMode."))
    statusRow(state, add)
    local bands = { { value = 0, key = "cursor.values.band.default" } }
    -- A saved band that is no longer offered stays in the list while it is chosen.
    local offered = {}
    for _, yards in ipairs(V.PICKER_BANDS) do
      offered[yards] = true
    end
    for _, yards in ipairs(V.BANDS) do
      if offered[yards] or yards == state.get("band") then
        bands[#bands + 1] = { value = yards, text = string.format(L["cursor.values.bandText"], yards) }
      end
    end
    -- The distance is the threshold of the text colors too, so text offers it for every mode but "melee".
    local function bandShown()
      local mode = state.get("mode")
      return mode == "auto" or mode == "band" or (textShown() and mode ~= "melee")
    end
    choiceRow(state, add, "cursor.values.band", "band", bands, bandShown)
    note(state, add, "cursor.values.bandNote", BAND_NOTE_HEIGHT, bandShown)
    add(
      C.Number(state.panel, {
        label = "cursor.values.spellId",
        min = 0,
        max = V.SPELL_ID_MAX,
        step = 1,
        labelWidth = 90,
        get = function()
          return state.get("spellId")
        end,
        set = function(v)
          state.write("spellId", v)
        end,
      }),
      C.HEIGHT.number,
      function()
        return state.get("mode") == "spell" and shapeShown()
      end
    )
    choiceRow(
      state,
      add,
      "cursor.values.rangeStyle",
      "style",
      C.Choices(V.RANGE_STYLES, "cursor.values.rangeStyle."),
      shapeShown
    )
    sliderRow(
      state,
      add,
      "cursor.panel.thickness",
      "thickness",
      CU.RING_THICKNESS_MIN,
      CU.RING_THICKNESS_MAX,
      1,
      function(v)
        return v .. " px"
      end,
      function()
        return shapeShown() and state.get("style") == "ring"
      end
    )
    add(
      C.Font(state.panel, {
        label = "xpbar.panel.font",
        get = function()
          return state.get("font")
        end,
        set = function(key)
          state.write("font", key)
        end,
      }),
      C.HEIGHT.choice,
      textShown
    )
    sliderRow(state, add, "xpbar.panel.size", "fontSize", XB.SIZE_MIN, XB.SIZE_MAX, 1, nil, textShown)
    choiceRow(state, add, "xpbar.panel.outline", "outline", C.Choices(XB.OUTLINES, "xpbar.panel.outline."), textShown)
    C.ToggleRow(state, when(add, textShown), "xpbar.panel.shadow", "shadow")
    choiceRow(
      state,
      add,
      "cursor.range.textFormat",
      "textFormat",
      C.Choices(V.TEXT_FORMATS, "cursor.range.textFormat."),
      textShown
    )
    add(
      C.Text(state.panel, {
        label = "cursor.range.unknownText",
        maxLetters = V.UNKNOWN_TEXT_MAX,
        get = function()
          return state.get("unknownText")
        end,
        set = function(text)
          state.write("unknownText", text)
        end,
      }),
      C.HEIGHT.text,
      textShown
    )
    C.ToggleRow(state, when(add, textShown), "cursor.range.colorByBand", "colorByBand")
    note(state, add, "cursor.range.textNote", BAND_NOTE_HEIGHT, textShown)
    C.ToggleRow(state, add, "cursor.values.hostileOnly", "hostileOnly")
    colorAlphaRow(state, add, "cursor.values.colorIn", "colorIn")
    C.ColorRow(state, add, "cursor.values.colorOut", "colorOut", "e5484d")
    C.ColorRow(state, add, "cursor.values.colorUnknown", "colorUnknown", "9ca3af")
  end)
end

-- Registry ----------------------------------------------------------------------------------------------------------

E.Register("health", { render = renderHealth, drive = drive, release = release, panel = M.HealthPanel })
E.Register("power", { render = renderPower, drive = drive, release = release, panel = M.PowerPanel })
E.Register("range", { render = renderRange, drive = drive, release = release, panel = M.RangePanel })

-- The editor preview: health falls, the resource drains and the range flips while the simulation plays.
local sim = ns.CursorSim
if sim and type(sim.RegisterSource) == "function" then
  sim.RegisterSource("values", {
    reset = function(state)
      state.health, state.power, state.rangeIn, state.rangeYards = nil, nil, nil, nil
    end,
    step = function(state, _, t)
      state.health, state.power, state.rangeIn = V.Sweep(t)
      state.rangeYards = V.SweepYards(t)
    end,
  })
end
