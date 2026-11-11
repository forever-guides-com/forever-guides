-- Every call into the game made by the fishing helper, in one place. All of them are looked up at call
-- time, run in a protected call and hand back nil for a function the client does not have or a value it
-- hides (secret values are checked before anything reads them). The logic files never touch the game.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local Guard = FG.AutoGuard

local G = {}
fish.Game = G

-- Fishing spells of the clients: the casts of the classic ranks and later expansions, the profession ranks
-- and the later "Fishing" spells. Which one counts is whichever the character knows; they all carry the same
-- name, so a client that knows another id is still found by name (see G.FindSpell).
G.SPELLS = {
  7620,
  7731,
  7732,
  18248,
  33095,
  51294,
  7733,
  7734,
  110410,
  131474,
  131475,
  131476,
  158743,
  271990,
}

-- Skill line of the profession Fishing in the profession and skill lists.
G.SKILL_LINE = 356
-- Limits of the searches (the action bars of the clients have at most 180 slots).
G.MAX_ACTION_SLOT = 180
G.MAX_BOOK_ITEMS = 600
G.MAX_SKILLS = 200
-- Seconds a failed search is not repeated (a found spell is kept until the spells change).
G.SEARCH_PAUSE = 3

-- The main hand slot and the item class and subclass of a fishing rod.
G.MAIN_HAND = 16
G.WEAPON_CLASS = 2
G.ROD_SUBCLASS = 20

local IS_SPELL = {}
for _, id in ipairs(G.SPELLS) do
  IS_SPELL[id] = true
end

-- Ids the character was seen to channel (learned from a running line), in the order they were learned.
local learned, learnedSet = {}, {}
-- The last search ({ found, method, id, searched, trail }) and what the next call may reuse.
local detection, cache
-- The name of the profession Fishing as the profession list gave it.
local professionName

-- The first values of a game function, secret ones as nil; nil for everything when it is missing or fails.
local function query(path, ...)
  local ok, found, a, b, c, d, e, f, g, h, i = pcall(Guard.Call, path, ...)
  if not ok or not found then
    return nil
  end
  return Guard.Safe(a),
    Guard.Safe(b),
    Guard.Safe(c),
    Guard.Safe(d),
    Guard.Safe(e),
    Guard.Safe(f),
    Guard.Safe(g),
    Guard.Safe(h),
    Guard.Safe(i)
end

-- True when the game function exists and answers true.
local function yes(path, ...)
  return (query(path, ...)) == true
end

function G.Now()
  local now = query("GetTime")
  return type(now) == "number" and now or 0
end

-- Seconds that stay comparable across sessions (server time, else the system clock).
function G.Epoch()
  local now = query("GetServerTime") or query("time")
  return type(now) == "number" and now or 0
end

function G.InCombat()
  return yes("InCombatLockdown") or yes("UnitAffectingCombat", "player")
end

-- A function that runs fn after the delay, false without a timer.
function G.After(delay, fn)
  local timer = rawget(_G, "C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return false
  end
  return (pcall(timer.After, delay, fn))
end

-- Spell and rod ------------------------------------------------------------------------------------------

-- The name of a spell, nil when the client does not tell.
function G.SpellName(id)
  local name = query("C_Spell.GetSpellName", id)
  if type(name) ~= "string" then
    local info = query("C_Spell.GetSpellInfo", id)
    name = type(info) == "table" and info.name or nil
  end
  if type(name) ~= "string" then
    name = query("GetSpellInfo", id)
  end
  return type(name) == "string" and name or nil
end

-- The ids of the fishing spells: the list, then what the character was seen to channel.
local function allIds()
  local out = {}
  for _, id in ipairs(G.SPELLS) do
    out[#out + 1] = id
  end
  for _, id in ipairs(learned) do
    out[#out + 1] = id
  end
  return out
end

local function norm(name)
  return type(name) == "string" and name ~= "" and name:lower() or nil
end

-- The lower-case names a fishing spell or the profession goes by, each with an id to answer with.
local function nameSet()
  local names = {}
  for _, id in ipairs(allIds()) do
    local name = norm(G.SpellName(id))
    if name and not names[name] then
      names[name] = id
    end
  end
  local profession = norm(professionName)
  if profession and not names[profession] then
    names[profession] = G.SPELLS[1]
  end
  return names
end

-- The ways to ask a client whether a spell is known, by id.
local ID_CALLS =
  { "IsPlayerSpell", "IsSpellKnown", "C_SpellBook.IsSpellKnown", "C_SpellBook.IsSpellKnownOrInSpellBook" }
-- The calls that give the slot of a spell in the spell book.
local SLOT_CALLS = { "C_SpellBook.FindSpellBookSlotForSpell", "FindSpellBookSlotBySpellID" }

-- Every search returns the id it found (or nil) and whether the client had anything to search with.

-- Method "id": the client says a spell of the list is known.
local function searchIds()
  local available = false
  for _, path in ipairs(ID_CALLS) do
    available = Guard.Has(path) or available
  end
  if not available then
    return nil, false
  end
  for _, id in ipairs(allIds()) do
    for _, path in ipairs(ID_CALLS) do
      if yes(path, id) then
        return id, true
      end
    end
  end
  return nil, true
end

local function bankPlayer()
  local enum = rawget(_G, "Enum")
  local banks = type(enum) == "table" and enum.SpellBookSpellBank or nil
  return type(banks) == "table" and banks.Player or 0
end

-- The id of the spell book entry whose name is a fishing name, searched through the skill lines of the
-- modern spell book. seen counts the entries looked at over both books.
local function bookModern(names, seen)
  if
    not (Guard.Has("C_SpellBook.GetNumSpellBookSkillLines") and Guard.Has("C_SpellBook.GetSpellBookSkillLineInfo"))
  then
    return nil, false
  end
  local bank = bankPlayer()
  local lines = query("C_SpellBook.GetNumSpellBookSkillLines")
  for line = 1, type(lines) == "number" and lines or 0 do
    local info = query("C_SpellBook.GetSpellBookSkillLineInfo", line)
    local ok = type(info) == "table"
    local offset, size = ok and info.itemIndexOffset, ok and info.numSpellBookItems
    if type(offset) == "number" and type(size) == "number" then
      for slot = offset + 1, offset + size do
        seen.count = seen.count + 1
        if seen.count > G.MAX_BOOK_ITEMS then
          return nil, true
        end
        local hit = names[norm(query("C_SpellBook.GetSpellBookItemName", slot, bank))]
        if hit then
          local item = query("C_SpellBook.GetSpellBookItemInfo", slot, bank)
          local id = type(item) == "table" and item.spellID or nil
          return type(id) == "number" and id or hit, true
        end
      end
    end
  end
  return nil, true
end

-- The same through the spell tabs of the classic spell book.
local function bookClassic(names, seen)
  if not (Guard.Has("GetNumSpellTabs") and Guard.Has("GetSpellTabInfo")) then
    return nil, false
  end
  local tabs = query("GetNumSpellTabs")
  for tab = 1, type(tabs) == "number" and tabs or 0 do
    local _, _, offset, size = query("GetSpellTabInfo", tab)
    if type(offset) == "number" and type(size) == "number" then
      for slot = offset + 1, offset + size do
        seen.count = seen.count + 1
        if seen.count > G.MAX_BOOK_ITEMS then
          return nil, true
        end
        local name = query("GetSpellBookItemName", slot, "spell")
        if type(name) ~= "string" then
          name = query("GetSpellName", slot, "spell")
        end
        local hit = names[norm(name)]
        if hit then
          return hit, true
        end
      end
    end
  end
  return nil, true
end

-- Method "book": the spell book gives a slot for a fishing id, or holds an entry with a fishing name.
local function searchBook(names)
  local available = false
  for _, path in ipairs(SLOT_CALLS) do
    if Guard.Has(path) then
      available = true
      for _, id in ipairs(allIds()) do
        if type(query(path, id)) == "number" then
          return id, true
        end
      end
    end
  end
  local seen = { count = 0 }
  local id, ready = bookModern(names, seen)
  if id then
    return id, true
  end
  local old, oldReady = bookClassic(names, seen)
  return old, old ~= nil or available or ready or oldReady
end

-- Method "profession": the profession list or the skill list holds Fishing (by skill line or by name). The
-- profession gives no spell, so the answer is the id the name belongs to, else the first of the list.
local function searchProfession(names)
  local available = false
  if Guard.Has("GetProfessions") and Guard.Has("GetProfessionInfo") then
    available = true
    local list = { query("GetProfessions") }
    for position = 1, 9 do
      local index = list[position]
      if type(index) == "number" then
        local name, _, _, _, _, _, line = query("GetProfessionInfo", index)
        if line == G.SKILL_LINE or names[norm(name)] then
          professionName = type(name) == "string" and name or professionName
          return names[norm(name)] or G.SPELLS[1], true
        end
      end
    end
  end
  if Guard.Has("GetNumSkillLines") and Guard.Has("GetSkillLineInfo") then
    available = true
    local count = query("GetNumSkillLines")
    for index = 1, math.min(type(count) == "number" and count or 0, G.MAX_SKILLS) do
      local name, header = query("GetSkillLineInfo", index)
      if header ~= true and header ~= 1 and names[norm(name)] then
        professionName = name
        return names[norm(name)], true
      end
    end
  end
  return nil, available
end

-- Method "channel": the character was seen to channel a fishing spell the list does not know.
local function searchChannel()
  return learned[1], Guard.Has("UnitChannelInfo")
end

-- Method "bar": an action button holds a fishing spell (by id or by name).
local function searchBar(names)
  if not Guard.Has("GetActionInfo") then
    return nil, false
  end
  for slot = 1, G.MAX_ACTION_SLOT do
    local kind, id = query("GetActionInfo", slot)
    if kind == "spell" and type(id) == "number" then
      if IS_SPELL[id] or learnedSet[id] or names[norm(G.SpellName(id))] then
        return id, true
      end
    end
  end
  return nil, true
end

-- In the order they are tried; the code is the key of the text that names the method.
local METHODS = {
  { "id", searchIds },
  { "book", searchBook },
  { "profession", searchProfession },
  { "channel", searchChannel },
  { "bar", searchBar },
}

-- Looks for the fishing spell with every method in turn and stops at the first hit. Returns the id (nil
-- when none) and the report { found, method, id, searched, trail }: searched lists the methods the client
-- could answer, trail each of them with its result. A method that raises counts as unavailable.
function G.FindSpell()
  local names = nameSet()
  local report = { found = false, searched = {}, trail = {} }
  for _, method in ipairs(METHODS) do
    local ok, id, available = pcall(method[2], names)
    if not ok then
      id, available = nil, false
    end
    if available then
      report.searched[#report.searched + 1] = method[1]
      report.trail[#report.trail + 1] = { method = method[1], hit = id ~= nil }
    end
    if id ~= nil then
      report.found, report.method, report.id = true, method[1], id
      break
    end
  end
  detection = report
  cache = report.found and { id = report.id } or { at = G.Now() }
  return report.id, report
end

-- The id of a fishing spell the character knows, nil when there is none. A found spell is kept until the
-- spells change (G.ForgetSpell), a failed search is not repeated within G.SEARCH_PAUSE seconds.
function G.KnownSpell()
  if cache then
    if cache.id then
      return cache.id
    end
    local now = G.Now()
    if now > 0 and cache.at and now - cache.at < G.SEARCH_PAUSE then
      return nil
    end
  end
  return (G.FindSpell())
end

-- The next KnownSpell looks again.
function G.ForgetSpell()
  cache = nil
end

-- The report of the last search, nil before the first.
function G.Detection()
  return detection
end

local MAX_LEARNED = 8

-- The ids the character was seen to channel as a fishing spell.
function G.Learned()
  local out = {}
  for i, id in ipairs(learned) do
    out[i] = id
  end
  return out
end

-- Remembers a spell id the character channels as a fishing spell and tells G.OnLearn. True when it was new.
function G.Learn(id)
  if type(id) ~= "number" or id <= 0 or IS_SPELL[id] or learnedSet[id] or #learned >= MAX_LEARNED then
    return false
  end
  learned[#learned + 1] = id
  learnedSet[id] = true
  cache = nil
  if type(G.OnLearn) == "function" then
    pcall(G.OnLearn, G.Learned())
  end
  return true
end

-- Replaces the remembered ids (what the character saved earlier).
function G.SetLearned(list)
  learned, learnedSet, cache = {}, {}, nil
  for _, id in ipairs(type(list) == "table" and list or {}) do
    if type(id) == "number" and id > 0 and not IS_SPELL[id] and not learnedSet[id] and #learned < MAX_LEARNED then
      learned[#learned + 1] = id
      learnedSet[id] = true
    end
  end
end

-- The key of the character the remembered ids belong to (the saved data is shared by the account).
function G.CharKey()
  local name = query("UnitName", "player")
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local realm = query("GetRealmName") or query("GetNormalizedRealmName")
  return name .. "-" .. (type(realm) == "string" and realm or "")
end

-- True when a fishing rod is in the main hand.
function G.HasRod()
  local item = query("GetInventoryItemID", "player", G.MAIN_HAND)
  if type(item) ~= "number" then
    return false
  end
  local _, _, _, _, _, class, subclass = query("C_Item.GetItemInfoInstant", item)
  if class == nil then
    _, _, _, _, _, class, subclass = query("GetItemInfoInstant", item)
  end
  return class == G.WEAPON_CLASS and subclass == G.ROD_SUBCLASS
end

-- The channel is a fishing channel: one of the spell ids sits among the values of the channel info
-- (the place of the id differs between clients), or the name is the name of a fishing spell.
function G.IsFishingChannel(values, spellName)
  if type(values) ~= "table" or values[1] == nil then
    return false
  end
  for index = 6, 10 do
    local value = values[index]
    if type(value) == "number" and (IS_SPELL[value] or learnedSet[value]) then
      return true
    end
  end
  return spellName ~= nil and values[1] == spellName
end

-- The spell id inside the values of a channel info (its place differs between clients), nil when none.
local function channelId(values)
  for _, index in ipairs({ 8, 9, 7 }) do
    local value = values[index]
    if type(value) == "number" and value > 0 then
      return value
    end
  end
  return nil
end

-- True while the player channels a fishing spell. A line whose name is a fishing name counts as well, and
-- its spell id is remembered, so a client with another id is found from the next time on.
function G.Channeling()
  local values = { query("UnitChannelInfo", "player") }
  if values[1] == nil then
    return false
  end
  local known = G.KnownSpell()
  local fishing = G.IsFishingChannel(values, known and G.SpellName(known) or nil)
  if not fishing then
    local name = norm(values[1])
    fishing = name ~= nil and nameSet()[name] ~= nil
  end
  if fishing then
    G.Learn(channelId(values))
  end
  return fishing
end

-- True when a spell id (an event argument) is a fishing spell.
function G.IsFishingSpell(id)
  return type(id) == "number" and (IS_SPELL[id] == true or learnedSet[id] == true)
end

-- The facts Conditions.Evaluate reads.
function G.Facts()
  local speed = query("GetUnitSpeed", "player")
  return {
    spell = G.KnownSpell() ~= nil,
    rod = G.HasRod(),
    combat = G.InCombat(),
    controlLost = query("HasFullControl") == false,
    vehicle = yes("UnitInVehicle", "player") or yes("UnitHasVehicleUI", "player"),
    flying = yes("IsFlying"),
    mounted = yes("IsMounted"),
    swimming = yes("IsSwimming") or yes("IsSubmerged"),
    stealthed = yes("IsStealthed"),
    falling = yes("IsFalling"),
    moving = type(speed) == "number" and speed > 0,
  }
end

-- Settings -------------------------------------------------------------------------------------------------

-- The value of a console variable as text, nil when the client has no such variable or hides it.
function G.GetCvar(name)
  local value = query("C_CVar.GetCVar", name)
  if value == nil then
    value = query("GetCVar", name)
  end
  return value ~= nil and tostring(value) or nil
end

-- True when the write went through (a client that answers nothing counts as done, false is a refusal).
function G.SetCvar(name, value)
  for _, path in ipairs({ "C_CVar.SetCVar", "SetCVar" }) do
    local ok, found, result = pcall(Guard.Call, path, name, value)
    if ok and found then
      return result ~= false
    end
  end
  return false
end

-- Keys and the mouse ----------------------------------------------------------------------------------------

-- The keys bound to a binding name (up to two), as the game names them.
function G.Keys(binding)
  local out = {}
  for _, key in ipairs({ query("GetBindingKey", binding) }) do
    if type(key) == "string" and key ~= "" then
      out[#out + 1] = key
    end
  end
  return out
end

function G.MouseDown(button)
  return yes("IsMouseButtonDown", button)
end

-- True when the mouse is over the game world, not over a window of the interface. A client that cannot
-- tell counts as the world.
function G.OverWorld()
  local world = rawget(_G, "WorldFrame")
  local foci = query("GetMouseFoci")
  if type(foci) == "table" then
    return #foci == 0 or (#foci == 1 and foci[1] == world)
  end
  if Guard.Has("GetMouseFocus") then
    local focus = query("GetMouseFocus")
    return focus == nil or focus == world
  end
  return true
end

-- Secure frames ------------------------------------------------------------------------------------------------

local COMBAT_STATE = "fishcombat"
-- A fight drops the override bindings of the owner, they can not change in combat anyway.
local COMBAT_SNIPPET = [[
  if newstate == "combat" then
    self:ClearBindings()
  end
]]

-- A frame that owns override bindings and drops them when combat starts. nil when the client refuses.
function G.NewOwner(name)
  local create = rawget(_G, "CreateFrame")
  if type(create) ~= "function" then
    return nil
  end
  local ok, frame = pcall(create, "Frame", name, rawget(_G, "UIParent"), "SecureHandlerStateTemplate")
  if not ok or type(frame) ~= "table" then
    return nil
  end
  pcall(frame.SetAttribute, frame, "_onstate-" .. COMBAT_STATE, COMBAT_SNIPPET)
  query("RegisterStateDriver", frame, COMBAT_STATE, "[combat] combat; nocombat")
  return frame
end

-- The secure button that casts the fishing spell. Its spell is set with SetSpell, never in combat.
function G.NewCastButton(name)
  local create = rawget(_G, "CreateFrame")
  if type(create) ~= "function" then
    return nil
  end
  local ok, button = pcall(create, "Button", name, rawget(_G, "UIParent"), "SecureActionButtonTemplate")
  if not ok or type(button) ~= "table" then
    return nil
  end
  pcall(button.RegisterForClicks, button, "AnyDown", "AnyUp")
  pcall(button.SetAttribute, button, "type", "spell")
  return button
end

function G.SetSpell(button, spell)
  return (pcall(button.SetAttribute, button, "spell", spell))
end

function G.GetSpell(button)
  local ok, value = pcall(button.GetAttribute, button, "spell")
  return ok and value or nil
end

-- A frame that hears every key press and lets it go on to the bindings (the press is not taken away).
-- onKey(key) gets the key as the game names it, without the modifiers. nil when the client refuses.
function G.NewKeyWatcher(onKey)
  local create = rawget(_G, "CreateFrame")
  if type(create) ~= "function" then
    return nil
  end
  local ok, frame = pcall(create, "Frame", nil, rawget(_G, "UIParent"))
  if not ok or type(frame) ~= "table" then
    return nil
  end
  pcall(frame.SetScript, frame, "OnKeyDown", function(_, key)
    pcall(onKey, key)
  end)
  return frame
end

-- Switches the listening on or off. It is only allowed to listen when the press goes on, so the propagation
-- is set first and a refusal leaves the keyboard alone. Never in combat. Returns true when it is as asked.
function G.WatchKeys(frame, on)
  if type(frame) ~= "table" or G.InCombat() then
    return false
  end
  if on then
    if not pcall(frame.SetPropagateKeyboardInput, frame, true) then
      return false
    end
  end
  return (pcall(frame.EnableKeyboard, frame, on == true))
end

-- The binding commands of the two modes.
function G.Command(mode, buttonName)
  if mode == "cast" then
    return "CLICK " .. buttonName .. ":LeftButton"
  elseif mode == "reel" then
    return "INTERACTTARGET"
  end
  return nil
end

-- Puts the override bindings of a mode on the keys, owned by `owner`; "off" drops them. Returns true, or
-- false and the text of the error.
function G.Write(owner, mode, keys, buttonName)
  local clear = rawget(_G, "ClearOverrideBindings")
  local set = rawget(_G, "SetOverrideBinding")
  if type(clear) ~= "function" or type(set) ~= "function" then
    return false, "no binding functions"
  end
  local ok, err = pcall(clear, owner)
  if not ok then
    return false, tostring(err)
  end
  local command = G.Command(mode, buttonName)
  if not command then
    return true
  end
  for _, key in ipairs(keys) do
    ok, err = pcall(set, owner, true, key, command)
    if not ok then
      return false, tostring(err)
    end
  end
  return true
end

-- The own icon at the bobber -------------------------------------------------------------------------------------

local SOFT = "softinteract"

-- True when the client hides the anchoring of the plate from add-ons. A client without that call has no
-- hidden anchors, an answer that is missing or itself hidden counts as hidden.
local function anchoringHidden(plate)
  local check = plate.IsAnchoringSecret
  if type(check) ~= "function" then
    return false
  end
  local ok, value = pcall(check, plate)
  if not ok then
    return true
  end
  return Guard.Safe(value) ~= false
end

-- What the icon needs to know about the soft target: { exists, object, plate, secret }. exists and object
-- are true or false, nil when the client hides them (world objects do not count for UnitExists, so both
-- are read). plate is the name plate frame of the target, nil when there is none, secret is true when its
-- anchoring is hidden.
function G.SoftTarget()
  local out = { exists = query("UnitExists", SOFT), object = query("UnitIsGameObject", SOFT) }
  local plate = query("C_NamePlate.GetNamePlateForUnit", SOFT)
  if type(plate) == "table" then
    out.plate = plate
    out.secret = anchoringHidden(plate)
  end
  return out
end

-- The frame of the icon: { frame, tex }, nil when the client refuses.
function G.NewMark(size, strata)
  local create = rawget(_G, "CreateFrame")
  if type(create) ~= "function" then
    return nil
  end
  local ok, mark = pcall(function()
    local frame = create("Frame", nil, rawget(_G, "UIParent"))
    frame:Hide()
    frame:SetSize(size, size)
    frame:SetFrameStrata(strata)
    frame:EnableMouse(false)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(frame)
    return { frame = frame, tex = tex }
  end)
  return ok and type(mark) == "table" and mark or nil
end

-- The icon of the game for the soft target goes into the texture. Where the client takes a second argument
-- (low priority icons) it is tried first. Returns true when the texture holds something afterwards.
local function paintFromGame(tex)
  local set = rawget(_G, "SetUnitCursorTexture")
  if type(set) ~= "function" then
    return false
  end
  for _, extra in ipairs({ { true }, {} }) do
    pcall(tex.SetTexture, tex, nil)
    if pcall(set, tex, SOFT, unpack(extra)) then
      local okAtlas, atlas = pcall(tex.GetAtlas, tex)
      local okFile, file = pcall(tex.GetTexture, tex)
      if (okAtlas and Guard.Safe(atlas) ~= nil) or (okFile and Guard.Safe(file) ~= nil) then
        return true
      end
    end
  end
  return false
end

-- Hangs the icon on the plate as its child, `offset` pixels below the plate center, and shows it. It takes
-- the scale of the plate and ignores the see-through state of its parent. false when the client refuses
-- the anchor.
function G.PlaceMark(mark, plate, offset, fallback)
  local frame = mark.frame
  if not pcall(frame.SetParent, frame, plate) then
    return false
  end
  local okLevel, level = pcall(plate.GetFrameLevel, plate)
  level = okLevel and Guard.Safe(level) or nil
  if type(level) == "number" then
    pcall(frame.SetFrameLevel, frame, level + 1)
  end
  pcall(frame.ClearAllPoints, frame)
  if not pcall(frame.SetPoint, frame, "CENTER", plate, "CENTER", 0, offset) then
    return false
  end
  pcall(frame.SetIgnoreParentAlpha, frame, true)
  if not paintFromGame(mark.tex) then
    pcall(mark.tex.SetTexture, mark.tex, fallback)
  end
  pcall(frame.Show, frame)
  return true
end

-- Lets go of the plate: hidden, no anchor, no parent.
function G.HideMark(mark)
  local frame = mark.frame
  pcall(frame.Hide, frame)
  pcall(frame.ClearAllPoints, frame)
  pcall(frame.SetParent, frame, nil)
end

-- Loot ----------------------------------------------------------------------------------------------------------------

function G.LootOpen()
  local frame = rawget(_G, "LootFrame")
  if type(frame) == "table" and type(frame.IsShown) == "function" then
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
  end
  return false
end

function G.IsFishingLoot()
  return yes("IsFishingLoot")
end

function G.LootCount()
  local count = query("GetNumLootItems")
  return type(count) == "number" and count or 0
end

function G.LootSlot(slot)
  return (pcall(Guard.Call, "LootSlot", slot))
end

function G.ConfirmLoot(slot)
  return (pcall(Guard.Call, "ConfirmLootSlot", slot))
end

-- The catch journal -------------------------------------------------------------------------------------------------

-- true, false, or nil when the client has no IsFishingLoot or hides its answer.
function G.FishingLootState()
  local answer = query("IsFishingLoot")
  if type(answer) == "boolean" then
    return answer
  end
  return nil
end

-- The numeric id inside an item link, nil for anything else (a hidden link included).
function G.ItemIdOfLink(link)
  if type(link) ~= "string" then
    return nil
  end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

-- The loot window as the catch rules read it: { fishing, slots = { { item, qty, source } } }. A slot without
-- a readable item (money, currency, a hidden link) is left out.
function G.LootSnapshot()
  local snap = { fishing = G.FishingLootState(), slots = {} }
  for slot = 1, G.LootCount() do
    local id = G.ItemIdOfLink(query("GetLootSlotLink", slot))
    if id then
      local _, _, qty = query("GetLootSlotInfo", slot)
      local source = query("GetLootSourceInfo", slot)
      snap.slots[#snap.slots + 1] = {
        item = id,
        qty = type(qty) == "number" and qty or 1,
        source = type(source) == "string" and source or nil,
      }
    end
  end
  return snap
end

-- Where the player is: { id = map id | nil, name = text | nil }. The map name is preferred, the zone text is the
-- fallback.
function G.Zone()
  local id = query("C_Map.GetBestMapForUnit", "player")
  id = type(id) == "number" and id > 0 and id or nil
  local name
  if id then
    local info = query("C_Map.GetMapInfo", id)
    if type(info) == "table" then
      local ok, value = pcall(function()
        return info.name
      end)
      name = ok and Guard.Safe(value) or nil
    end
  end
  if type(name) ~= "string" or name == "" then
    name = query("GetRealZoneText")
  end
  return { id = id, name = type(name) == "string" and name ~= "" and name or nil }
end

-- The current character: { key, name, realm }. The guid is the key, name and realm are the fallback.
function G.Character()
  local guid = query("UnitGUID", "player")
  local name = query("UnitName", "player")
  local realm = query("GetRealmName")
  name = type(name) == "string" and name or nil
  realm = type(realm) == "string" and realm or nil
  local key = type(guid) == "string" and guid or (name and (name .. "-" .. (realm or "?"))) or nil
  return { key = key, name = name, realm = realm }
end

-- The name of an item in the client language, nil until the client has it (it is asked for then).
function G.ItemName(id)
  local name = query("C_Item.GetItemInfo", id)
  if type(name) ~= "string" then
    name = query("GetItemInfo", id)
  end
  if type(name) == "string" and name ~= "" then
    return name
  end
  query("C_Item.RequestLoadItemDataByID", id)
  return nil
end

-- Fish names ------------------------------------------------------------------------------------------------------

-- Items the lists wait for (ids), the ones the client could not deliver, the frame that hears the delivery.
local missing, failed, nameFrame = {}, {}, nil
local namesPending = false

local function syncNameEvent()
  if not nameFrame then
    return
  end
  if next(missing) then
    pcall(nameFrame.RegisterEvent, nameFrame, "GET_ITEM_INFO_RECEIVED")
  else
    pcall(nameFrame.UnregisterEvent, nameFrame, "GET_ITEM_INFO_RECEIVED")
  end
end

-- One redraw for a burst of deliveries.
local function announceNames()
  if namesPending then
    return
  end
  namesPending = true
  if not G.After(0.25, function()
    namesPending = false
    FG.Emit("FG_FISHING_NAMES")
  end) then
    namesPending = false
    FG.Emit("FG_FISHING_NAMES")
  end
end

local function onItemInfo(_, event, id, success)
  if event ~= "GET_ITEM_INFO_RECEIVED" or not missing[id] then
    return
  end
  missing[id] = nil
  if success == false then
    failed[id] = true
  end
  syncNameEvent()
  announceNames()
end

local function watchName(id)
  if failed[id] then
    return
  end
  missing[id] = true
  if not nameFrame then
    local create = rawget(_G, "CreateFrame")
    if type(create) ~= "function" then
      return
    end
    local ok, frame = pcall(create, "Frame")
    if not ok or type(frame) ~= "table" then
      return
    end
    nameFrame = frame
    pcall(frame.SetScript, frame, "OnEvent", onItemInfo)
  end
  syncNameEvent()
end

-- The name of a fish for a list: the client name, else the name stored from an earlier session, else the English
-- name of FishNames.lua, else a neutral text. Never an item number. While the client has no name the item is
-- loaded and FG_FISHING_NAMES fires once it arrives.
function G.FishName(id, stored)
  local name = G.ItemName(id)
  if name then
    missing[id] = nil
    return name
  end
  watchName(id)
  if type(stored) == "string" and stored ~= "" then
    return stored
  end
  local known = fish.FishNames and fish.FishNames.names[id]
  return known or FG.L["fishing.fish.unknown"]
end

-- Stops listening for item data, the lists are not on screen any more.
function G.StopNameWatch()
  missing = {}
  syncNameEvent()
end

-- The name of an area (zone or sub zone) in the client language, nil when the client does not tell.
function G.AreaName(id)
  local name = query("C_Map.GetAreaInfo", id)
  if type(name) ~= "string" then
    name = query("GetAreaInfo", id)
  end
  return type(name) == "string" and name ~= "" and name or nil
end

-- The icon (file id or path) of an item, nil when the client does not tell.
function G.ItemIcon(id)
  local icon = query("C_Item.GetItemIconByID", id)
  if icon == nil then
    local _, _, _, _, instant = query("C_Item.GetItemInfoInstant", id)
    icon = instant
  end
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

-- The quality (0 poor to 7 heirloom) of an item, nil until the client has the item.
function G.ItemQuality(id)
  local quality = query("C_Item.GetItemQualityByID", id)
  if type(quality) ~= "number" then
    quality = select(3, query("C_Item.GetItemInfo", id))
  end
  return type(quality) == "number" and quality or nil
end

-- The hyperlink of an item: the client's own link when it has the item, else the bare "item:id" form that the
-- tooltip also takes. The item data is asked for in both cases that are not cached yet.
function G.ItemLink(id)
  if type(id) ~= "number" then
    return nil
  end
  local _, link = query("C_Item.GetItemInfo", id)
  if type(link) == "string" and link ~= "" then
    return link
  end
  query("C_Item.RequestLoadItemDataByID", id)
  return "item:" .. id
end

-- A link for the chat: the client's own link for a cached item, else a plain link built from the name that is
-- known. nil when neither exists (a link without a name would show as a number).
function G.ChatLink(id, name)
  local _, link = query("C_Item.GetItemInfo", id)
  if type(link) == "string" and link:find("|H", 1, true) then
    return link
  end
  if type(id) == "number" and type(name) == "string" and name ~= "" then
    return string.format("|Hitem:%d::::::::::::::|h[%s]|h", id, name)
  end
  return nil
end

-- Puts an item link into the chat edit box that is open. False when no box is open or the client has no such call.
function G.InsertLink(link)
  if type(link) ~= "string" or link == "" then
    return false
  end
  if query("ChatFrameUtil.InsertLink", link) == true then
    return true
  end
  return query("ChatEdit_InsertLink", link) == true
end

-- True while the Shift key is held.
function G.ShiftDown()
  return yes("IsShiftKeyDown")
end

-- The name of a spell or an item as text for a recipe line, nil when unknown.
function G.RecipeName(spell)
  return G.SpellName(spell)
end
