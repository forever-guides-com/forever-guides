-- Own professions of the logged-in character, written into its roster entry (CharRoster) for the
-- character overview. The client may offer different APIs, so three ways are tried in turn, each
-- behind an existence check and pcall; the first one that yields professions wins. When none does
-- (no API, errors, an empty list) the stored professions stay as they are.
local _, ns = ...
local Logic = ns.ProfessionLogic

local M = {}
ns.Professions = M

local UPDATE_DELAY = 2
local MAX_SLOTS = 6
local MAX_SKILL_LINES = 200
local MAX_TRADE_LINES = 80

-- Way 1: GetProfessions + GetProfessionInfo.
local function viaProfessions()
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
    return nil
  end
  local ok, list = pcall(function()
    return { GetProfessions() }
  end)
  if not ok then
    return nil
  end
  local rows = {}
  for slot = 1, MAX_SLOTS do
    if type(list[slot]) == "number" then
      local okInfo, name, _, skill, max, _, _, line = pcall(GetProfessionInfo, list[slot])
      if okInfo and name then
        rows[#rows + 1] = { slot = slot, name = name, skill = skill, max = max, id = line }
      end
    end
  end
  return Logic.FromProfessions(rows)
end

local function headerTexts(...)
  local out = {}
  for _, key in ipairs({ ... }) do
    if type(_G[key]) == "string" then
      out[#out + 1] = _G[key]
    end
  end
  return out
end

-- Way 2: GetNumSkillLines + GetSkillLineInfo.
local function viaSkillLines()
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then
    return nil
  end
  local okCount, count = pcall(GetNumSkillLines)
  if not okCount or type(count) ~= "number" then
    return nil
  end
  local lines = {}
  for i = 1, math.min(count, MAX_SKILL_LINES) do
    local ok, name, header, _, skill, _, _, max = pcall(GetSkillLineInfo, i)
    if ok and name then
      lines[#lines + 1] = { name = name, header = header == true or header == 1, skill = skill, max = max }
    end
  end
  return Logic.FromSkillLines(lines, headerTexts("TRADE_SKILLS", "PROFESSIONS"), headerTexts("SECONDARY_SKILLS"))
end

-- Way 3: C_TradeSkillUI skill lines.
local function viaTradeSkills()
  local api = C_TradeSkillUI
  if
    type(api) ~= "table"
    or type(api.GetAllProfessionTradeSkillLines) ~= "function"
    or type(api.GetProfessionInfoBySkillLineID) ~= "function"
  then
    return nil
  end
  local ok, ids = pcall(api.GetAllProfessionTradeSkillLines)
  if not ok or type(ids) ~= "table" then
    return nil
  end
  local rows = {}
  for i, id in ipairs(ids) do
    if i > MAX_TRADE_LINES then
      break
    end
    local okInfo, info = pcall(api.GetProfessionInfoBySkillLineID, id)
    if okInfo and type(info) == "table" then
      rows[#rows + 1] = {
        id = id,
        name = info.professionName,
        skill = info.skillLevel,
        max = info.maxSkillLevel,
        parent = info.parentProfessionName,
      }
    end
  end
  return Logic.FromTradeSkills(rows)
end

local WAYS = { viaProfessions, viaSkillLines, viaTradeSkills }

-- The professions of the current character, nil when no way delivers any.
function M.Read()
  for _, way in ipairs(WAYS) do
    local list = way()
    if list then
      return list
    end
  end
  return nil
end

-- Reads and stores. Returns true when the roster entry was written.
function M.Capture()
  local Roster = ns.CharRoster
  if not Roster.Enabled() then
    return false
  end
  local list = M.Read()
  local key = list and Roster.CurrentKey()
  if not key then
    return false
  end
  local now = Roster.Now()
  if Roster.SetProfessions(key, list, now) then
    return true
  end
  -- The entry does not exist yet (first login): create it, then write.
  return Roster.Capture() ~= nil and Roster.SetProfessions(key, list, now)
end

local function schedule()
  ns.Debounce("professions-update", UPDATE_DELAY, M.Capture)
end
M.Schedule = schedule

for _, event in ipairs({
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "SKILL_LINES_CHANGED",
  "TRADE_SKILL_UPDATE",
  "TRADE_SKILL_SHOW",
  "CHAT_MSG_SKILL",
}) do
  ns.On(event, schedule)
end
