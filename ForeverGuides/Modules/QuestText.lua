-- Description and goal text of the instance quests (data file InstanceQuestText_<n>.lua of the data add-on).
-- The data keeps the client placeholders ($n name, $c class, $r race, $g male:female;); Fill resolves them with the
-- own character, or a neutral word when the client does not tell. Pure except Player, which reads the client.
local _, ns = ...

local QT = {}
ns.QuestText = QT

ns.AddLocale("enUS", { ["questtext.someone"] = "adventurer" })
ns.AddLocale("deDE", { ["questtext.someone"] = "Abenteurer" })

local function safe(value)
  local guard = ns.AutoGuard
  return guard and guard.Safe(value) or nil
end

local function read(name)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, "player")
  return ok and safe(value) or nil
end

local function word(value)
  return type(value) == "string" and value ~= "" and value or nil
end

-- { name, class, race, sex } of the own character, a field is nil when the client does not give it.
function QT.Player()
  return {
    name = word(read("UnitName")),
    class = word(read("UnitClass")),
    race = word(read("UnitRace")),
    sex = read("UnitSex"),
  }
end

-- The text with its placeholders resolved. who: { name, class, race, sex } (sex 3 is female, anything else male).
-- Unknown placeholders are dropped so no marker reaches the screen.
function QT.Fill(text, who)
  if type(text) ~= "string" then
    return nil
  end
  who = who or {}
  local someone = ns.L["questtext.someone"]
  text = text:gsub("%$[gG]%s*([^:;]*):%s*([^;]*);", function(male, female)
    return (who.sex == 3 and female or male):match("^%s*(.-)%s*$")
  end)
  return (
    text:gsub("%$(%a)", function(code)
      local key = code:lower()
      if key == "n" then
        return who.name or someone
      elseif key == "c" then
        return who.class or someone
      elseif key == "r" then
        return who.race or someone
      end
      return ""
    end)
  )
end

local function field(id, key)
  local all = rawget(ns, "InstanceQuestTexts")
  local row = type(all) == "table" and type(id) == "number" and all[id] or nil
  local texts = type(row) == "table" and row[key] or nil
  -- A German-only text never reaches a non-German client.
  local text = type(texts) == "table" and (ns.GetActiveLocale() == "deDE" and (texts.de or texts.en) or texts.en) or nil
  return type(text) == "string" and text ~= "" and text or nil
end

-- Description and goal of a quest in the language of the client (English when there is no translation; a text
-- that exists in German only shows on a German client), each nil when there is none. Needs the data add-on loaded (Modules/InstanceDataAccess.lua does that).
function QT.Get(id, who)
  who = who or QT.Player()
  return QT.Fill(field(id, "d"), who), QT.Fill(field(id, "o"), who)
end
