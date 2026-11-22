-- Trainer spells the character learned, for the level overview. Some trainer entries (rogue poisons) are
-- crafting recipes, not spellbook spells, so the spell APIs never report them as known. Two sources fill
-- the set: trainer entries the window marks as "used" and the chat line of a fresh purchase.
--
-- ForeverGuidesCharDB.learnedSpells = { [spell id] = true }, per character, only ever grows.
local _, ns = ...

local K = {}
ns.LearnedSpells = K

local MAX = 3000
local DELAY = 0.3
local session = {}

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local res = { pcall(fn, ...) }
  if not res[1] then
    return nil
  end
  return unpack(res, 2, 8)
end

local function saved()
  local char = ns.charDB
  if type(char) ~= "table" then
    return nil
  end
  if type(char.learnedSpells) ~= "table" then
    char.learnedSpells = {}
  end
  return char.learnedSpells
end

function K.Reset()
  session = {}
end

function K.Has(id)
  if type(id) ~= "number" then
    return false
  end
  local db = saved()
  return session[id] == true or (db ~= nil and db[id] == true)
end

-- Adds spell ids. Returns how many were new; FG_LEARNED_SPELLS follows when there were any.
function K.Mark(ids)
  local db = saved()
  local added, count = 0, 0
  if db then
    for _ in pairs(db) do
      count = count + 1
    end
  end
  for _, id in ipairs(ids) do
    if type(id) == "number" and id > 0 and not K.Has(id) then
      session[id] = true
      if db and count < MAX then
        db[id] = true
        count = count + 1
      end
      added = added + 1
    end
  end
  if added > 0 then
    ns.Emit("FG_LEARNED_SPELLS", added)
  end
  return added
end

-- Trainer window ------------------------------------------------------------------------------------

local function rankOf(text)
  return type(text) == "string" and tonumber(text:match("(%d+)")) or nil
end

-- Reads the open trainer window and keeps every entry the client marks as already learned.
function K.CaptureTrainer()
  local total = try(GetNumTrainerServices)
  local _, class = UnitClass("player")
  if not (type(total) == "number" and total > 0 and class and ns.CostCapture) then
    return 0
  end
  local ids = {}
  for i = 1, math.min(total, 400) do
    local name, status, texture, _, subText = try(GetTrainerServiceInfo, i)
    if status == "used" and type(name) == "string" then
      local id = ns.CostCapture.ResolveId(i, name, rankOf(subText), texture, class)
      if id then
        ids[#ids + 1] = id
      end
    end
  end
  return K.Mark(ids)
end

-- Chat line ---------------------------------------------------------------------------------------

-- Lua pattern for a game string such as "You have learned a new spell: %s.", nil without the string.
local function patternOf(name)
  local fmt = rawget(_G, name)
  if type(fmt) ~= "string" then
    return nil
  end
  local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end

-- Spell id of a learn message: the spell link when the line has one, else name and rank.
function K.ParseMessage(text)
  -- A secret line (another player's chat in a restricted state) cannot be matched.
  text = ns.AutoGuard.Safe(text)
  if type(text) ~= "string" then
    return nil
  end
  for _, key in ipairs({ "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_RECIPE_S" }) do
    local p = patternOf(key)
    local what = p and text:match(p)
    if what then
      local linked = tonumber(what:match("|Hspell:(%d+)"))
      if linked then
        return linked
      end
      local plain = what:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
      plain = plain:match("%[(.-)%]") or plain
      local rank = rankOf(plain:match("%((.-)%)"))
      local name = plain:gsub("%(.-%)", ""):match("^%s*(.-)%s*$")
      local _, class = UnitClass("player")
      return ns.CostCapture and ns.CostCapture.ResolveId(nil, name, rank, nil, class) or nil
    end
  end
end

ns.On("CHAT_MSG_SYSTEM", function(_, text)
  local id = K.ParseMessage(text)
  if id then
    K.Mark({ id })
  end
end)

for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE" }) do
  ns.On(event, function()
    ns.Debounce("learned-spells-trainer", DELAY, K.CaptureTrainer)
  end)
end
