-- Race data access for the classes page: ordered races, class availability,
-- ability icons. Data: ns.Data.RaceInfo (generated), order from WeaponRaces.
local _, ns = ...

local RL = {}
ns.RaceLogic = RL

local ICON_DIR = "Interface\\Icons\\"
RL.UNKNOWN_ICON = ICON_DIR .. "INV_Misc_QuestionMark"

-- Status of a racial ability against Classic: Theme color of its dot.
RL.STATUS_COLOR = { new = "success", changed = "warning", unchanged = "textMuted" }

local function info()
  return ns.Data and ns.Data.RaceInfo or {}
end

function RL.Info(slug)
  return info()[slug]
end

-- Races in website order (Alliance first), each { slug, s, f, n } so the list
-- also feeds K.RaceButtons.
function RL.Races(faction)
  local out = {}
  for _, race in ipairs(ns.Data and ns.Data.WeaponRaces and ns.Data.WeaponRaces.races or {}) do
    local entry = info()[race.s]
    if entry and (faction == nil or faction == "all" or entry.f == faction) then
      out[#out + 1] = { slug = race.s, s = race.s, f = entry.f, n = entry.n }
    end
  end
  return out
end

-- "new" (only in Forever), "available" or "locked" for a race and a class token.
function RL.ClassState(slug, class)
  local entry = info()[slug]
  local c = entry and entry.classes and entry.classes[class]
  if not c or not c.a then
    return "locked"
  end
  return c.new and "new" or "available"
end

function RL.ClassCount(slug)
  local n = 0
  for _, class in ipairs(ns.RefLogic.CLASSES) do
    if RL.ClassState(slug, class) ~= "locked" then
      n = n + 1
    end
  end
  return n
end

-- Races that get the class as a new option in Forever.
function RL.NewRaces(class)
  local out = {}
  for _, race in ipairs(RL.Races()) do
    if RL.ClassState(race.slug, class) == "new" then
      out[#out + 1] = race
    end
  end
  return out
end

-- Texture path of a racial ability icon (file name below Interface\Icons). When
-- the client can look files up and does not know the file, the question mark
-- stands in; without a lookup the path is used as it is.
function RL.IconPath(name)
  local path = ICON_DIR .. tostring(name or "")
  local lookup = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
  if not name or name == "" then
    return RL.UNKNOWN_ICON
  end
  if lookup then
    local ok, id = pcall(lookup, path)
    if ok and id == nil then
      return RL.UNKNOWN_ICON
    end
  end
  return path
end
