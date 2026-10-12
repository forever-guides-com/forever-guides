-- Trainer prices: what an ability or weapon skill costs at the trainer. Pure
-- logic over the generated data (Data\TrainerCosts.lua: the Forever
-- Guides prices, Classic prices as fallback) and the prices the client showed in a
-- trainer window (ns.CostCapture, they win).
-- A price is { cost = copper | nil, source = "observed" | "confirmed" | "forever" | "classic",
-- suspect, differs = Classic copper where the Forever data disagrees }.
local _, ns = ...
local L = ns.L

local CL = {}
ns.CostLogic = CL

ns.AddLocale("enUS", {
  ["cost.legend"] = "~ = uncertain price, not confirmed in game",
  ["cost.tip.forever"] = "Price from the Forever Guides data, not confirmed in game",
  ["cost.tip.differs"] = "Forever Guides: %s, Classic: %s, not confirmed in game",
  ["cost.tip.classic"] = "Classic price, not confirmed in Forever\nOpen the trainer to see the real price",
  ["cost.tip.observed"] = "Seen in the trainer window",
  ["cost.tip.suspect"] = "Level differs from Classic, price may be another rank",
  ["cost.sum"] = "Total: %s",
  ["cost.sumUnknown"] = "+ %d without price",
  ["cost.availableTotal"] = "Everything learnable now: %s",
  ["cost.weaponsTotal"] = "All skills with a teacher: %s",
})

ns.AddLocale("deDE", {
  ["cost.legend"] = "~ = unsicherer Preis, im Spiel unbestätigt",
  ["cost.tip.forever"] = "Preis aus den Forever-Guides-Daten, nicht im Spiel bestätigt",
  ["cost.tip.differs"] = "Forever Guides: %s, Classic: %s, im Spiel nicht bestätigt",
  ["cost.tip.classic"] = "Classic-Preis, in Forever unbestätigt\nLehrer öffnen zeigt den echten Preis",
  ["cost.tip.observed"] = "Im Lehrerfenster gesehen",
  ["cost.tip.suspect"] = "Stufe weicht von Classic ab, Preis evtl. anderer Rang",
  ["cost.sum"] = "Summe: %s",
  ["cost.sumUnknown"] = "+ %d ohne Preis",
  ["cost.availableTotal"] = "Alles Lernbare jetzt: %s",
  ["cost.weaponsTotal"] = "Alle Fertigkeiten mit Lehrer: %s",
})

local function static()
  return ns.Data and ns.Data.TrainerCosts or {}
end

local function number(v)
  return type(v) == "number" and v > 0 and v or nil
end

-- What the client showed: scope is a class token or "WM" (weapon masters).
local function observed(scope, id)
  local cc = ns.CostCapture
  local e = cc and cc.Get(scope, id)
  return e and number(e.cost) or nil
end

-- Prices ---------------------------------------------------------------------------

-- Static copper price of a trainer spell (class trainer first, then weapon
-- master), nil when unknown.
function CL.Static(spellId, class)
  local d = static()
  local byClass = class and d.byClass and d.byClass[class]
  return number(byClass and byClass[spellId])
    or number(d.costs and d.costs[spellId])
    or number(d.skills and d.skills[spellId])
end

-- "forever" for ids the data took from the Forever data, else "classic".
local function sourceOf(spellId)
  local src = static().src
  return src and src[spellId] == "w" and "forever" or "classic"
end

local function differsOf(spellId)
  local d = static().differs
  return d and number(d[spellId]) or nil
end

-- Class trainer spell: copper, source, suspect, differs (Classic copper when
-- the Forever data disagrees). class is the class token the trainer belongs to
-- (optional, only matters for skills that cost differently per class).
function CL.Cost(spellId, class)
  if type(spellId) ~= "number" then
    return nil
  end
  local seen = class and observed(class, spellId)
  if seen then
    return seen, "observed", false
  end
  local copper = CL.Static(spellId, class)
  if copper then
    local suspect = static().suspect ~= nil and static().suspect[spellId] == true
    return copper, sourceOf(spellId), suspect, differsOf(spellId)
  end
  return nil
end

-- Weapon master skill spell: copper, source, false, differs. Order: observed,
-- confirmed (data.confirmed: prices checked in game, One-Handed Swords 10 silver and
-- Polearms 1 gold from level 20, the other weapons assumed equal),
-- Forever data, Classic.
function CL.SkillCost(skillSpellId, class)
  if type(skillSpellId) ~= "number" then
    return nil
  end
  local seen = observed("WM", skillSpellId) or (class and observed(class, skillSpellId))
  if seen then
    return seen, "observed", false
  end
  local copper = number(static().skills and static().skills[skillSpellId])
  if copper then
    local confirmed = static().confirmed
    if confirmed and confirmed[skillSpellId] == true then
      return copper, "confirmed", false
    end
    return copper, sourceOf(skillSpellId), false, differsOf(skillSpellId)
  end
  return nil
end

-- Level list item (ability, or weapon with how it is acquired): { cost, source, suspect }.
-- Skills known from the start have no price.
function CL.ItemPrice(item, class)
  local copper, source, suspect, differs
  if item.kind == "weapon" then
    local id = ns.LevelLogic.SKILL_SPELLS[item.skill]
    if item.a == "weaponMaster" then
      copper, source, suspect, differs = CL.SkillCost(id, class)
    elseif item.a == "classTrainer" then
      copper, source, suspect, differs = CL.Cost(id, class)
    end
  else
    copper, source, suspect, differs = CL.Cost(item.sid, class)
    -- Spell level and trainer level agree (the list took them from the spell data): no other rank.
    suspect = suspect and not item.confirmed
    -- No spell id at all: the Classic price by class, name and rank.
    local byName = not item.sid and class and item.n and item.n.en and static().byName
    if byName and not copper then
      copper = number(byName[ns.LevelLogic.NameKey(class, item.n.en, item.rank)])
      source = copper and "classic" or nil
    end
  end
  return { cost = copper, source = source, suspect = suspect or false, differs = differs }
end

-- Formatting -----------------------------------------------------------------------

-- Coin text for a copper amount, nil for 0 or nothing: the amount in front of its
-- own coin icon, gold, silver and copper, parts that are 0 left out. The icons are
-- inline textures at text height (0:0), they take their color from the texture,
-- the digits from the text color of the surface. Built here on purpose instead of
-- GetCoinTextureString, so the look never depends on the client's helper.
-- opts.plain: "1g 20s 5k" for places where escapes do not render (exports, logs).
local ICON_FORMAT = "|TInterface\\MoneyFrame\\%s:0:0:2:0|t"
local PARTS = {
  { unit = 10000, mod = nil, letter = "g", icon = "UI-GoldIcon" },
  { unit = 100, mod = 100, letter = "s", icon = "UI-SilverIcon" },
  { unit = 1, mod = 100, letter = "k", icon = "UI-CopperIcon" },
}

function CL.Format(copper, opts)
  if type(copper) ~= "number" or copper < 1 then
    return nil
  end
  copper = math.floor(copper)
  local plain = opts and opts.plain
  local parts = {}
  for _, p in ipairs(PARTS) do
    local n = math.floor(copper / p.unit)
    if p.mod then
      n = n % p.mod
    end
    if n > 0 then
      parts[#parts + 1] = plain and (n .. p.letter) or (n .. string.format(ICON_FORMAT, p.icon))
    end
  end
  return table.concat(parts, " ")
end

-- A price is uncertain when it is a Classic price or the Forever data and Classic
-- disagree. Seen in the trainer window, confirmed in game or the Forever data alone:
-- certain enough.
local function uncertain(price)
  return price.source == "classic" or (price.source == "forever" and price.differs ~= nil)
end

-- Price text with the "~" marker for uncertain prices, nil without a price.
function CL.Text(price, opts)
  local text = price and CL.Format(price.cost, opts)
  if not text then
    return nil
  end
  return uncertain(price) and (text .. " ~") or text
end

-- Tooltip text that explains where a price comes from. Confirmed prices look like
-- any normal price: no marker, no tooltip (nil).
function CL.Tip(price)
  if not (price and price.cost) then
    return nil
  end
  local text
  if price.source == "observed" then
    text = L["cost.tip.observed"]
  elseif price.source == "confirmed" then
    return nil
  elseif price.source == "forever" then
    text = price.differs
        and string.format(L["cost.tip.differs"], CL.Format(price.cost) or "?", CL.Format(price.differs) or "?")
      or L["cost.tip.forever"]
  else
    text = L["cost.tip.classic"]
  end
  if price.suspect then
    text = text .. "\n" .. L["cost.tip.suspect"]
  end
  return text
end

-- Sums -----------------------------------------------------------------------------

-- prices: list of { cost, source }. Unknown prices are counted, not guessed.
-- Returns { total, known, unknown, classic } (classic = known prices that carry the "~").
function CL.Sum(prices)
  local sum = { total = 0, known = 0, unknown = 0, classic = 0 }
  for _, p in ipairs(prices) do
    if p.cost then
      sum.total = sum.total + p.cost
      sum.known = sum.known + 1
      if uncertain(p) then
        sum.classic = sum.classic + 1
      end
    else
      sum.unknown = sum.unknown + 1
    end
  end
  return sum
end

-- Sum of the level list items, class selects class dependent prices.
function CL.SumItems(items, class)
  local prices = {}
  for i, item in ipairs(items) do
    prices[i] = CL.ItemPrice(item, class)
  end
  return CL.Sum(prices)
end

-- "Total: 3g 40s 5k ~ + 2 without price" for a sum, nil when there is nothing
-- to say. fmt is the locale key of the lead-in (default "cost.sum").
function CL.SumText(sum, opts)
  local coins = CL.Format(sum.total, opts)
  if not coins then
    return nil
  end
  local text = string.format(L[(opts and opts.key) or "cost.sum"], sum.classic > 0 and (coins .. " ~") or coins)
  if sum.unknown > 0 then
    text = text .. " " .. string.format(L["cost.sumUnknown"], sum.unknown)
  end
  return text
end
