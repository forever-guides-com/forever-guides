-- Records the catches for the journal. It listens to the fishing channel and to the loot window, asks the
-- rules (CatchRules) what is a catch and writes it through CatchStore. It never changes a game setting and
-- never touches a protected frame, so a blocked call of the helper does not stop it. Everything it reads
-- from the game goes through Game.lua.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local Store, Rules = fish.CatchStore, fish.CatchRules

local R = {}
fish.Recorder = R

local EVENTS = {
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "LOOT_READY",
  "LOOT_OPENED",
  "LOOT_CLOSED",
}

local db, journal, status, session, optionsOf
local cast, castZone, channeling, stoppedAt
local pending = {}
local frame
local registered = {}

local function game()
  return fish.Game
end

local function wanted()
  local options = optionsOf and optionsOf() or nil
  return status ~= "newer" and journal ~= nil and options ~= nil and options.recordCatches == true
end

local function changed()
  FG.Emit("FG_FISHING_JOURNAL")
end

-- Events ----------------------------------------------------------------------------------------------------------

local function setEvents(on)
  if not frame then
    return
  end
  for _, event in ipairs(EVENTS) do
    if on and not registered[event] then
      registered[event] = pcall(frame.RegisterEvent, frame, event) or nil
    elseif not on and registered[event] then
      pcall(frame.UnregisterEvent, frame, event)
      registered[event] = nil
    end
  end
  if on and not registered.GET_ITEM_INFO_RECEIVED and next(pending) then
    registered.GET_ITEM_INFO_RECEIVED = pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED") or nil
  elseif registered.GET_ITEM_INFO_RECEIVED and (not on or not next(pending)) then
    pcall(frame.UnregisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
    registered.GET_ITEM_INFO_RECEIVED = nil
  end
end

-- Listens only while the option is on and the stored data is usable.
function R.Sync()
  setEvents(wanted())
end

-- Names ------------------------------------------------------------------------------------------------------------

-- Writes the name of an item into the ledgers that hold it.
local function nameItem(id, name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  local done = false
  local function put(ledger)
    local item = ledger and ledger.items[id]
    if item and item.nm ~= name then
      item.nm = name:sub(1, Store.LIMITS.nameLength)
      done = true
    end
  end
  put(journal.account)
  for _, entry in pairs(journal.chars) do
    put(entry.ledger)
  end
  return done
end

local function onItemInfo(id)
  if type(id) ~= "number" or not pending[id] then
    return
  end
  if nameItem(id, game().ItemName(id)) then
    pending[id] = nil
    changed()
  end
  if not next(pending) then
    R.Sync()
  end
end

-- Catches ----------------------------------------------------------------------------------------------------------

local function newCast()
  cast = Rules.NewCast()
end

local function onChannelStart(unit, spellId)
  if unit ~= "player" then
    return
  end
  local g = game()
  if not (g.IsFishingSpell(spellId) or g.Channeling()) then
    return
  end
  newCast()
  channeling, stoppedAt = true, nil
  castZone = g.Zone()
  Store.NoteCast(journal, g.Character(), castZone, g.Epoch())
  changed()
end

local function onChannelStop(unit)
  if unit == "player" and channeling then
    channeling, stoppedAt = false, game().Now()
  end
end

local function onLoot()
  local g = game()
  cast = cast or Rules.NewCast()
  local ctx = { channeling = channeling == true }
  if stoppedAt then
    ctx.sinceStop = g.Now() - stoppedAt
  end
  local found = Rules.Catches(g.LootSnapshot(), ctx, cast)
  if #found == 0 then
    return
  end
  local char, zone, when = g.Character(), castZone or g.Zone(), g.Epoch()
  local key = Store.ZoneKey(zone)
  for _, got in ipairs(found) do
    local inItem, inZone = session:Add(got.item, key, got.qty)
    local name = g.ItemName(got.item)
    local first = not cast.hit
    cast.hit = true
    Store.Record(journal, char, zone, {
      item = got.item,
      qty = got.qty,
      time = when,
      name = name,
      sessionItem = inItem,
      sessionZone = inZone,
      first = first,
    })
    if not name then
      pending[got.item] = true
    end
  end
  R.Sync()
  changed()
end

local function onLootClosed()
  newCast()
end

-- One entry for every event, also what the tests call.
function R.OnEvent(event, ...)
  if not wanted() then
    return
  end
  if event == "UNIT_SPELLCAST_CHANNEL_START" then
    local unit, _, spellId = ...
    onChannelStart(unit, spellId)
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    onChannelStop((...))
  elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
    onLoot()
  elseif event == "LOOT_CLOSED" then
    onLootClosed()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    onItemInfo((...))
  end
end

-- Session --------------------------------------------------------------------------------------------------------

-- The journal of this session (nil while the stored data is from a later version).
function R.Journal()
  if status == "newer" then
    return nil
  end
  return journal
end

-- "fresh", "ok", "migrated" or "newer".
function R.Status()
  return status
end

-- The character the journal reads for "this character".
function R.CharKey()
  return game().Character().key
end

-- Starts with the SavedVariables table of the helper. options is a function that returns the clean options.
function R.Start(saved, options)
  db = type(saved) == "table" and saved or {}
  optionsOf = options
  journal, status = Store.Migrate(db.journal)
  if status ~= "newer" then
    db.journal = journal
  end
  session = Store.NewSession()
  cast, castZone, channeling, stoppedAt = nil, nil, false, nil
  pending = {}
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
      FG.Safe("fishing journal:" .. event, R.OnEvent, event, ...)
    end)
  end
  R.Sync()
end

function R.Stop()
  setEvents(false)
  db, journal, status, session = nil, nil, nil, nil
end

-- The player switched the recording on or off.
FG.On("FG_FISHING_CHANGED", function(_, id)
  if id == "recordCatches" and journal then
    R.Sync()
  end
end)

-- What the tests look at.
function R.Parts()
  return { frame = frame, pending = pending, session = session, registered = registered }
end
