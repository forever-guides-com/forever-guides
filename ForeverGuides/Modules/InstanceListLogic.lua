-- Logic of the instance card grid (Modules/InstanceCards.lua): the filter (type, faction, level, favorites,
-- search), the order with the favorites first, the texts of the plaques and the foot, the column count, the
-- order in which a narrow card shortens its plaques and the movement of the keyboard cursor. Pure logic, no
-- game access: the data comes from RefLogic and InstanceLevelLogic, the favorites from a predicate.
local _, ns = ...

ns.AddLocale("enUS", {
  ["instances.card.level"] = "Level %d-%d",
  ["instances.card.levelOne"] = "Level %d",
  ["instances.card.levelTo"] = "Level ?-%d",
  ["instances.card.levelNone"] = "Level ?",
  ["instances.card.quests.one"] = "%d quest",
  ["instances.card.quests.other"] = "%d quests",
  ["instances.card.questsLoading"] = "Quests: ...",
  ["instances.card.questsNone"] = "Quests: -",
  ["instances.card.players"] = "%s players",
  ["instances.card.type.dungeon"] = "Dungeon",
  ["instances.card.type.raid"] = "Raid",
  ["instances.card.tip.location"] = "Location: %s",
  ["instances.card.tip.bosses"] = "Bosses: %d",
})

ns.AddLocale("deDE", {
  ["instances.card.level"] = "Stufe %d-%d",
  ["instances.card.levelOne"] = "Stufe %d",
  ["instances.card.levelTo"] = "Stufe ?-%d",
  ["instances.card.levelNone"] = "Stufe ?",
  ["instances.card.quests.one"] = "%d Quest",
  ["instances.card.quests.other"] = "%d Quests",
  ["instances.card.questsLoading"] = "Quests: ...",
  ["instances.card.questsNone"] = "Quests: -",
  ["instances.card.players"] = "%s Spieler",
  ["instances.card.type.dungeon"] = "Dungeon",
  ["instances.card.type.raid"] = "Raid",
  ["instances.card.tip.location"] = "Ort: %s",
  ["instances.card.tip.bosses"] = "Bosse: %d",
})

local IL = {}
ns.InstanceListLogic = IL

-- Narrowest card and the space between cards. Columns = floor((width + gap) / (narrowest + gap)).
IL.CARD_MIN, IL.GAP = 230, 10
IL.LEVEL_MAX = 99
IL.KINDS = { "all", "dungeon", "raid" }
IL.SORTS = { "name", "level" }

local function number(value, default)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return default
  end
  return value
end

-- Columns -----------------------------------------------------------------------------------------

function IL.Columns(width)
  return math.max(1, math.floor((number(width, 0) + IL.GAP) / (IL.CARD_MIN + IL.GAP)))
end

-- Whole pixels per card, so the cards of a row end flush at the right edge or a few pixels before it.
function IL.CardWidth(width, columns)
  columns = math.max(1, columns or IL.Columns(width))
  return math.max(1, math.floor((number(width, 0) - IL.GAP * (columns - 1)) / columns))
end

-- Filter ------------------------------------------------------------------------------------------

-- faction: the default of the filter, "A", "H" or "all" (the player's own faction as long as it is known).
function IL.NewFilter(faction)
  return {
    kind = "all",
    faction = (faction == "A" or faction == "H") and faction or "all",
    level = nil,
    query = "",
    favorites = false,
    favoritesFirst = true,
    sort = "level",
  }
end

-- The faction choice shared by the instance page and the quest tab: a saved "A", "H" or "all", else the faction of
-- the player (`player`: "A", "H" or nil), else "all". Anything else saved is dropped.
function IL.Faction(saved, player)
  if saved == "A" or saved == "H" or saved == "all" then
    return saved
  end
  return (player == "A" or player == "H") and player or "all"
end

-- True while nothing but the default is set (the sort and the favorites switch are no filter).
function IL.IsDefault(filter, faction)
  local base = IL.NewFilter(faction)
  return filter.kind == base.kind
    and filter.faction == base.faction
    and filter.level == nil
    and (filter.query or "") == ""
    and not filter.favorites
end

-- A level typed into the box: whole number from 1 to LEVEL_MAX, else nil (no level filter).
function IL.ParseLevel(text)
  local n = ns.InstanceLevelLogic.QueryLevel(text)
  if n and n >= 1 and n <= IL.LEVEL_MAX then
    return n
  end
  return nil
end

local function defaultFavorite(inst)
  return ns.InstanceDisplay.IsFavorite(ns.RefLogic.InstanceSlug(inst))
end

-- The instances of the grid in display order. isFavorite(inst) -> bool defaults to the saved favorites,
-- match(text, query) to the search of the addon. The order is the one of RefLogic.Instances (name or level),
-- with the favorites in front of the others when filter.favoritesFirst, each group in its own order.
function IL.Apply(filter, isFavorite, match)
  isFavorite = isFavorite or defaultFavorite
  local kind = (filter.kind == "dungeon" or filter.kind == "raid") and filter.kind or nil
  local faction = (filter.faction == "A" or filter.faction == "H") and filter.faction or nil
  local found = ns.RefLogic.Instances(
    kind,
    faction,
    filter.query or "",
    match or ns.SearchLogic.match,
    filter.sort == "level" and "level" or "name"
  )
  local level = number(filter.level, nil)
  local first, rest = {}, {}
  for _, inst in ipairs(found) do
    local fav = isFavorite(inst)
    if (not level or ns.InstanceLevelLogic.Covers(inst, level)) and (fav or not filter.favorites) then
      table.insert(fav and filter.favoritesFirst and first or rest, inst)
    end
  end
  for _, inst in ipairs(rest) do
    first[#first + 1] = inst
  end
  return first
end

function IL.Total()
  return #((ns.Data and ns.Data.Instances) or {})
end

-- What the grid shows: noData (no data package), noFavorites (only favorites asked, none saved), empty (the
-- filter hides everything) or ok.
function IL.State(hasData, shown, filter, favoriteCount)
  if not hasData then
    return "noData"
  end
  if filter.favorites and (favoriteCount or 0) == 0 then
    return "noFavorites"
  end
  if shown == 0 then
    return "empty"
  end
  return "ok"
end

-- Texts -------------------------------------------------------------------------------------------

-- "Level 13-20", a single value "Level 60" (also a start without an end or a range of one level), "Level ?-20"
-- for an end without a start and "Level ?" for none. The gap itself is named by the tooltip.
function IL.LevelText(inst, L)
  L = L or ns.L
  local info = ns.InstanceLevelLogic.Of(inst, L)
  local from, to = info.from, info.to
  if from and to and from ~= to then
    return string.format(L["instances.card.level"], from, to)
  elseif from then
    return string.format(L["instances.card.levelOne"], from)
  elseif to then
    return string.format(L["instances.card.levelTo"], to)
  end
  return L["instances.card.levelNone"]
end

-- status: result of InstanceDataAccess.Ensure ("ok", "combat", "missing", "noData"), count: quests of the
-- instance. A count is shown only with the data in place; during a fight the load waits, "..." stands in.
function IL.QuestText(status, count, L)
  L = L or ns.L
  if status == "ok" and type(count) == "number" then
    return string.format(L["instances.card.quests." .. (count == 1 and "one" or "other")], count)
  elseif status == "combat" then
    return L["instances.card.questsLoading"]
  end
  return L["instances.card.questsNone"]
end

function IL.PlayersText(inst, L)
  L = L or ns.L
  local size = inst.gs or inst.pl
  return string.format(L["instances.card.players"], size ~= nil and tostring(size) or "?")
end

-- The plaques of a card: type (kind, word), faction (value, word; nil for both factions), announced (text; nil
-- unless announced) and level (text).
function IL.Plaques(inst, L)
  L = L or ns.L
  local LL = ns.InstanceLevelLogic
  local kind = inst.t == "raid" and "raid" or "dungeon"
  local out = {
    type = { kind = kind, word = L["instances.card.type." .. kind] },
    level = IL.LevelText(inst, L),
  }
  local faction = LL.Faction(inst)
  if faction ~= "B" then
    out.faction = { value = faction, word = L["kit.faction." .. faction] }
  end
  if LL.Announced(inst) then
    out.announced = L["instances.announced"]
  end
  return out
end

-- Parts of the foot line below the name: players, faction (not for both) and the day the instance opens, plus
-- the quest count when the plaque has no room for it (extra).
function IL.FootParts(inst, L, extra)
  L = L or ns.L
  local LL = ns.InstanceLevelLogic
  local parts = { IL.PlayersText(inst, L) }
  local faction = LL.Faction(inst)
  if faction ~= "B" then
    parts[#parts + 1] = L["kit.faction." .. faction]
  end
  local release = LL.Of(inst, L).releaseText
  if release then
    parts[#parts + 1] = release
  end
  if extra and extra ~= "" then
    parts[#parts + 1] = extra
  end
  return parts
end

-- Lines of the card tooltip below the name: the other language, type and faction in words (the plaques may
-- show a symbol only), the level lines of the data (entry, recommended, gap), location and counts.
function IL.TipLines(inst, L, questText)
  L = L or ns.L
  local R, LL = ns.RefLogic, ns.InstanceLevelLogic
  local lines = {}
  local _, otherName = R.Names(inst.n)
  if otherName then
    lines[#lines + 1] = { text = otherName, color = "textMuted" }
  end
  local plaques = IL.Plaques(inst, L)
  local kind = plaques.type.word
  if plaques.faction then
    kind = kind .. ", " .. plaques.faction.word
  end
  lines[#lines + 1] = kind
  local info = LL.Of(inst, L)
  lines[#lines + 1] = info.text
  for _, bit in ipairs({ info.entryText or false, info.recommendedText or false }) do
    if bit then
      lines[#lines + 1] = bit
    end
  end
  if info.gapText then
    lines[#lines + 1] = { text = info.gapText, color = "textMuted" }
  end
  if info.announced then
    lines[#lines + 1] = { text = info.announcedTip, color = "warning" }
  end
  local loc = R.Names(inst.loc)
  if loc then
    lines[#lines + 1] = string.format(L["instances.card.tip.location"], loc)
  end
  lines[#lines + 1] = string.format(L["instances.card.tip.bosses"], #(inst.bo or {}))
  lines[#lines + 1] = questText
  return lines
end

-- Plaque fit ---------------------------------------------------------------------------------------

local function sum(list, gap)
  local total = 0
  for _, w in ipairs(list) do
    total = total + w
  end
  return total + gap * math.max(0, #list - 1)
end

-- Decides how the plaques of one card share the picture when the width runs out. avail: width between the
-- inner edges of the picture. m (widths in px): gap, pad, imageH, plaqueH, starW, starH, typeWord and typeIcon
-- (type plaque with and without its word), factionWord and factionIcon (nil without a faction plaque),
-- announced (nil without the mark), quest (nil without a quest plaque), level.
-- Order of the cut: the faction word goes first, the type word second (both stay as a symbol, the tooltip names
-- them), then the quest count leaves the top row and goes below the star, or into the foot when the picture has
-- no room for a second plaque there. The level plaque is never cut, moved or hidden.
-- Returns { typeWord, factionWord, quest = "top" | "below" | "foot" | "none" }.
function IL.FitPlaques(avail, m)
  local gap = m.gap or 4
  local function topRow(typeWord, factionWord, questOnTop)
    local left = { typeWord and m.typeWord or m.typeIcon }
    if m.factionWord then
      left[#left + 1] = factionWord and m.factionWord or m.factionIcon
    end
    if m.announced then
      left[#left + 1] = m.announced
    end
    local right = { m.starW }
    if questOnTop and m.quest then
      table.insert(right, 1, m.quest)
    end
    return sum(left, gap) + gap + sum(right, gap)
  end
  for _, step in ipairs({ { true, true }, { true, false }, { false, false } }) do
    if topRow(step[1], step[2], true) <= avail then
      return { typeWord = step[1], factionWord = step[2], quest = m.quest and "top" or "none" }
    end
  end
  local out = { typeWord = false, factionWord = false, quest = "none" }
  if m.quest then
    local side = m.level + gap + m.quest <= avail
    local tall = not m.imageH
      or (m.pad or 0) * 2 + math.max(m.starH or 0, m.plaqueH or 0) + gap + (m.plaqueH or 0) <= m.imageH
    out.quest = (side and tall) and "below" or "foot"
  end
  return out
end

-- Color ---------------------------------------------------------------------------------------------

-- The color a plaque of the given opacity shows over a picture of one color (rgb tables, 0 to 1): the worst
-- case for text on it is a white or a black picture.
function IL.Composite(fg, alpha, bg)
  return {
    fg[1] * alpha + bg[1] * (1 - alpha),
    fg[2] * alpha + bg[2] * (1 - alpha),
    fg[3] * alpha + bg[3] * (1 - alpha),
  }
end

-- Keyboard cursor -------------------------------------------------------------------------------------

-- New index of the cursor. move: left, right (one card), up, down (one row), home, end. Edges stop the
-- cursor; down from a card above a shorter last row lands on the last card.
function IL.Move(index, count, columns, move)
  if count < 1 then
    return nil
  end
  columns = math.max(1, columns)
  index = math.max(1, math.min(count, index or 1))
  if move == "left" then
    return math.max(1, index - 1)
  elseif move == "right" then
    return math.min(count, index + 1)
  elseif move == "home" then
    return 1
  elseif move == "end" then
    return count
  elseif move == "up" then
    return index - columns >= 1 and index - columns or index
  elseif move == "down" then
    if index + columns <= count then
      return index + columns
    end
    local lastRow, row = math.ceil(count / columns), math.ceil(index / columns)
    return row < lastRow and count or index
  end
  return index
end
