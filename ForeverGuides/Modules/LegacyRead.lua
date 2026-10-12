-- Reads the character's own Legacy state through C_Traits: free, spent and maximum points (currency 4225),
-- rank and availability of every perk node, and the texts and icons of the perks at run time.
-- Read only: nothing is bought, committed or selected. Every call is existence-checked and wrapped in pcall,
-- values that are secret are dropped, and nothing is read in combat. A failing call leaves a gap in the result,
-- never a Lua error. read() gives the state or nil plus a reason ("combat", "noapi", "noconfig", "unreadable").
local _, ns = ...
local LL = ns.LegacyLogic

local LR = {}
ns.LegacyRead = LR

ns.AddLocale("enUS", {
  ["legacy.read.err.combat"] = "Not possible in combat.",
  ["legacy.read.err.noapi"] = "The game does not offer the Legacy data in this version.",
  ["legacy.read.err.noconfig"] = "The Legacy trees are not available for this character yet.",
  ["legacy.read.err.unreadable"] = "The Legacy perks could not be read.",
})

ns.AddLocale("deDE", {
  ["legacy.read.err.combat"] = "Im Kampf nicht möglich.",
  ["legacy.read.err.noapi"] = "Das Spiel stellt die Vermächtnis-Daten in dieser Version nicht bereit.",
  ["legacy.read.err.noconfig"] = "Die Vermächtnis-Bäume sind für diesen Charakter noch nicht verfügbar.",
  ["legacy.read.err.unreadable"] = "Die Vermächtnis-Perks konnten nicht gelesen werden.",
})

-- C_Traits functions the read needs; GetEntryInfo and GetDefinitionInfo only add the client text of a perk.
local REQUIRED = { "GetConfigIDByTreeID", "GetNodeInfo", "GetTreeCurrencyInfo" }

local function isSecret(value)
  local check = rawget(_G, "issecretvalue")
  if type(check) ~= "function" then
    return false
  end
  local ok, secret = pcall(check, value)
  return not ok or secret == true
end

-- nil for secret values, otherwise the value itself.
local function clean(value)
  if isSecret(value) then
    return nil
  end
  return value
end

local function number(value)
  value = clean(value)
  if type(value) == "number" and value == value then
    return value
  end
end

local function flag(value)
  value = clean(value)
  if type(value) == "boolean" then
    return value
  end
end

local function text(value)
  value = clean(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
end

local function traitsApi(name)
  local traits = rawget(_G, "C_Traits")
  local fn = type(traits) == "table" and traits[name] or nil
  return type(fn) == "function" and fn or nil
end

local function call(fn, ...)
  if not fn then
    return nil
  end
  local ok, result = pcall(fn, ...)
  if ok then
    return clean(result)
  end
end

local function field(tbl, key)
  if type(tbl) ~= "table" then
    return nil
  end
  local ok, value = pcall(function()
    return tbl[key]
  end)
  if ok then
    return value
  end
end

local function inCombat()
  local fn = rawget(_G, "InCombatLockdown")
  if type(fn) ~= "function" then
    return false
  end
  local ok, locked = pcall(fn)
  return not ok or locked == true
end

-- nil when the state can be read now, otherwise the reason: "combat" or "noapi".
function LR.blocked()
  if inCombat() then
    return "combat"
  end
  for _, name in ipairs(REQUIRED) do
    if not traitsApi(name) then
      return "noapi"
    end
  end
end

-- The currency line of a tree: GetTreeCurrencyInfo answers a list of currencies (or one entry).
local function currencyOf(list, currencyID)
  if type(list) ~= "table" then
    return nil
  end
  local entries = field(list, "quantity") ~= nil and { list } or list
  local first
  for _, entry in ipairs(entries) do
    if type(entry) == "table" then
      first = first or entry
      if number(field(entry, "traitCurrencyID")) == currencyID then
        return entry
      end
    end
  end
  return first
end

-- Client entry of a node: the spell and the own description of the first entry (all entries of the tiered
-- node carry the same text), nil when the client does not answer.
local function entryText(configID, node)
  local getEntry, getDefinition = traitsApi("GetEntryInfo"), traitsApi("GetDefinitionInfo")
  local entryID = type(node.entries) == "table" and node.entries[1] or nil
  if not getEntry or not getDefinition or not entryID then
    return
  end
  local entry = call(getEntry, configID, entryID)
  local definitionID = number(field(entry, "definitionID"))
  if not definitionID then
    return
  end
  local definition = call(getDefinition, definitionID)
  node.spell = number(field(definition, "spellID"))
  node.overrideDescription = text(field(definition, "overrideDescription"))
end

local function sameList(a, b)
  if #a ~= #b then
    return false
  end
  for i, v in ipairs(a) do
    if v ~= b[i] then
      return false
    end
  end
  return true
end

-- One perk node. Returns nil for a node the client does not know (answers nothing, ID 0 or another ID) and for
-- a node whose rank is unreadable (secret): a guessed rank 0 would let the planner buy ranks that exist.
local function readNode(configID, perk, getNode)
  local info = call(getNode, configID, perk.node)
  if type(info) ~= "table" then
    return nil
  end
  local id = number(field(info, "ID"))
  if id ~= nil and id ~= perk.node then
    return nil
  end
  local max = number(field(info, "maxRanks"))
  if not max or max < 1 then
    return nil
  end
  local rank = number(field(info, "ranksPurchased")) or number(field(info, "currentRank"))
  if not rank then
    return nil
  end
  local node = {
    rank = math.max(0, math.min(max, math.floor(rank))),
    max = max,
    available = flag(field(info, "isAvailable")),
    canBuy = flag(field(info, "canPurchaseRank")),
    entries = {},
  }
  local entryIDs = field(info, "entryIDs")
  if type(entryIDs) == "table" then
    for _, entryID in ipairs(entryIDs) do
      node.entries[#node.entries + 1] = number(entryID)
    end
  end
  -- A different node shape than the data (after a patch): shown as a hint, the rank itself stays usable.
  node.shapeChanged = max ~= perk.ranks or not sameList(node.entries, perk.entries)
  entryText(configID, node)
  return node
end

-- Free points, points spent and the points in the tree come from the tree currency (all three trees share one
-- currency, so the first answer counts for the pool).
local function readTree(state, tree, configID, getNode)
  local D = ns.Data.LegacyTrees
  local entry = currencyOf(call(traitsApi("GetTreeCurrencyInfo"), configID, tree.tree, false), D.currency)
  local record = {}
  if entry then
    record.spent = number(field(entry, "spentInTree"))
    if state.max == nil then
      state.free = number(field(entry, "quantity"))
      state.max = number(field(entry, "maxQuantity"))
      state.spent = number(field(entry, "spent"))
    end
  end
  state.trees[tree.tree] = record
  local read = 0
  for _, perk in ipairs(tree.nodes) do
    local node = readNode(configID, perk, getNode)
    if node then
      state.nodes[perk.node] = node
      read = read + 1
    else
      state.missing[#state.missing + 1] = perk.node
    end
  end
  return read
end

-- state = {
--   free, max, spent        points of the shared pool (numbers or nil when the client did not say)
--   hasPoints               the pool exists (maximum above 0, or ranks are bought); false before the first point
--   poolKnown               the client answered the point counts (free, max, spent)
--   trees = { [treeId] = { spent } }
--   nodes = { [nodeId] = { rank, max, available, canBuy, entries, shapeChanged, spell, overrideDescription } }
--   missing = { nodeId, ... } perk nodes the client did not answer
--   build, ignored          the ranks as a LegacyLogic build and the node ids it left out
-- }
function LR.read()
  local why = LR.blocked()
  if why then
    return nil, why
  end
  local D = ns.Data.LegacyTrees
  local getConfig, getNode = traitsApi("GetConfigIDByTreeID"), traitsApi("GetNodeInfo")
  local state = { nodes = {}, trees = {}, missing = {} }
  local configs, nodesRead = 0, 0
  for _, tree in ipairs(D.trees) do
    local configID = number(call(getConfig, tree.tree))
    if configID then
      configs = configs + 1
      nodesRead = nodesRead + readTree(state, tree, configID, getNode)
    else
      for _, perk in ipairs(tree.nodes) do
        state.missing[#state.missing + 1] = perk.node
      end
    end
  end
  if configs == 0 then
    return nil, "noconfig"
  end
  if nodesRead == 0 then
    return nil, "unreadable"
  end
  local ranks = {}
  for node, info in pairs(state.nodes) do
    ranks[node] = info.rank
  end
  state.build, state.ignored = LL.fromNodeRanks(ranks)
  state.poolKnown = state.max ~= nil
  state.hasPoints = (state.max or 0) > 0
  for _, info in pairs(state.nodes) do
    state.hasPoints = state.hasPoints or info.rank > 0
  end
  return state
end

-- Texts and icons at run time --------------------------------------------------------------------

local function spellApi(name)
  local spell = rawget(_G, "C_Spell")
  local fn = type(spell) == "table" and spell[name] or nil
  return type(fn) == "function" and fn or nil
end

-- Full description of a spell, nil when the client has none yet (the text loads lazily, ask again later).
function LR.spellDescription(spellID)
  spellID = number(spellID)
  if not spellID then
    return nil
  end
  return text(call(spellApi("GetSpellDescription"), spellID))
end

-- Icon (file id or path) of a spell, nil when unknown.
function LR.spellIcon(spellID)
  spellID = number(spellID)
  local value = spellID and call(spellApi("GetSpellTexture"), spellID)
  if type(value) == "number" or type(value) == "string" and value ~= "" then
    return value
  end
end

-- The text of a perk: the own description the client set on its entry, else the description of its spell.
-- node: the state entry of the perk (optional).
function LR.describe(perk, node)
  if node and node.overrideDescription then
    return node.overrideDescription
  end
  return LR.spellDescription(node and node.spell or perk.spell)
end
