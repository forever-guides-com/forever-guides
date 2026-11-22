-- Detail views of the instances page (Modules/InstancesPage.lua): the header with the loading screen, the
-- map button and the numbers, and the pooled row lists for bosses and quests (the items are in
-- Modules/InstanceItemsView.lua). Data:
-- ns.Data.Instances and ns.Data.DungeonAssets. Every game call goes through pcall, so a missing API
-- shows a placeholder and never raises.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit

ns.AddLocale("enUS", {
  ["instances.map"] = "Map",
  ["instances.banner.facts"] = "Key facts",
  ["instances.split.back"] = "‹ Back to the list",
  ["instances.split.back.tip"] = "Returns to the list (Esc).",
  ["instances.tabs.more"] = "More",
  ["instances.map.tip"] = "Shows the entrance on the world map.",
  ["instances.map.none"] = "No entrance position in the data for this instance.",
  ["instances.dtab.items"] = "Items",
  ["instances.head.quests.one"] = "1 quest",
  ["instances.head.quests.other"] = "%d quests",
  ["instances.pick.text"] = "Pick a dungeon or raid from the list to see its bosses, quests, rewards and entrance.",
  ["instances.abilities"] = "Abilities",
  ["instances.abilities.none"] = "Abilities: not recorded yet",
  ["instances.abilities.summary"] = "Abilities are recorded for %d of %d bosses.",
  ["instances.bosses.level"] = "Level %d",
  ["instances.bosses.position"] = "Boss %d of %d",
  ["instances.bosses.rare"] = "rare",
  ["instances.spell.unknown"] = "Spell %d",
  ["instances.spell.unknownMeta"] = "not known to this client",
  ["instances.items.loot"] = "No loot tables in the data yet.\nThe loot capture records items you find yourself.",
  ["instances.items.open"] = "Open loot capture",
  ["instances.items.none"] = "No items recorded for this instance yet.",
  ["instances.items.from"] = "Reward for: %s",
  ["instances.quest.weak"] = "Weakly confirmed: no quest ID in the data, details may be incomplete.",
  ["instances.gap.badge"] = "Data incomplete",
  ["instances.gap.title"] = "Data incomplete",
  ["instances.gap.hint"] = "Missing only means not recorded yet. It may still exist.",
  ["instances.gap.head"] = "Data status: incomplete",
  ["instances.gap.complete"] = "Data status: nothing missing",
  ["instances.gap.id"] = "No game instance ID.",
  ["instances.gap.name"] = "Instance name in English only.",
  ["instances.gap.level"] = "Level not recorded.",
  ["instances.gap.levelRange"] = "Level range missing, only the recommended level is known.",
  ["instances.gap.levelTo"] = "Upper level not recorded.",
  ["instances.gap.levelFrom"] = "Lower level not recorded.",
  ["instances.gap.entrance"] = "No entrance position.",
  ["instances.gap.map"] = "No dungeon map.",
  ["instances.gap.bosses"] = "No bosses recorded.",
  ["instances.gap.bossNames"] = "%d of %d boss names in English only.",
  ["instances.gap.loot"] = "No loot recorded for %d of %d bosses.",
  ["instances.gap.abilities"] = "No abilities recorded for %d of %d bosses.",
  ["instances.gap.questIds"] = "%d of %d quests without quest ID (weakly confirmed).",
  ["instances.gap.access"] = "Access requirements not recorded yet.",
})

ns.AddLocale("deDE", {
  ["instances.map"] = "Karte",
  ["instances.banner.facts"] = "Eckdaten",
  ["instances.split.back"] = "‹ Zurück zur Liste",
  ["instances.split.back.tip"] = "Zurück zur Liste (Esc).",
  ["instances.tabs.more"] = "Mehr",
  ["instances.map.tip"] = "Zeigt den Eingang auf der Weltkarte.",
  ["instances.map.none"] = "Für diese Instanz ist in den Daten kein Eingang erfasst.",
  ["instances.dtab.items"] = "Items",
  ["instances.head.quests.one"] = "1 Quest",
  ["instances.head.quests.other"] = "%d Quests",
  ["instances.pick.text"] = "Wähle einen Dungeon oder Raid aus der Liste, dann siehst du Bosse, Quests, Belohnungen und Eingang.",
  ["instances.abilities"] = "Fähigkeiten",
  ["instances.abilities.none"] = "Fähigkeiten: noch nicht erfasst",
  ["instances.abilities.summary"] = "Bei %d von %d Bossen sind Fähigkeiten erfasst.",
  ["instances.bosses.level"] = "Stufe %d",
  ["instances.bosses.position"] = "Boss %d von %d",
  ["instances.bosses.rare"] = "selten",
  ["instances.spell.unknown"] = "Zauber %d",
  ["instances.spell.unknownMeta"] = "diesem Client unbekannt",
  ["instances.items.loot"] = "Noch keine Beutetabellen in den Daten.\nDie Beuteerfassung erfasst, was du selbst findest.",
  ["instances.items.open"] = "Beuteerfassung öffnen",
  ["instances.items.none"] = "Für diese Instanz sind noch keine Items erfasst.",
  ["instances.items.from"] = "Belohnung für: %s",
  ["instances.quest.weak"] = "Schwach belegt: keine Quest-ID in den Daten, Angaben können unvollständig sein.",
  ["instances.gap.badge"] = "Daten unvollständig",
  ["instances.gap.title"] = "Daten unvollständig",
  ["instances.gap.hint"] = "„Fehlt“ heißt nur: noch nicht erfasst. Es kann trotzdem existieren.",
  ["instances.gap.head"] = "Datenstand: unvollständig",
  ["instances.gap.complete"] = "Datenstand: nichts fehlt",
  ["instances.gap.id"] = "Keine Instanz-ID des Spiels.",
  ["instances.gap.name"] = "Instanzname nur auf Englisch.",
  ["instances.gap.level"] = "Stufe nicht erfasst.",
  ["instances.gap.levelRange"] = "Stufenbereich fehlt, nur die empfohlene Stufe ist bekannt.",
  ["instances.gap.levelTo"] = "Obergrenze der Stufe nicht erfasst.",
  ["instances.gap.levelFrom"] = "Untergrenze der Stufe nicht erfasst.",
  ["instances.gap.entrance"] = "Keine Eingangsposition.",
  ["instances.gap.map"] = "Keine Dungeonkarte.",
  ["instances.gap.bosses"] = "Keine Bosse erfasst.",
  ["instances.gap.bossNames"] = "%d von %d Bossnamen nur auf Englisch.",
  ["instances.gap.loot"] = "Bei %d von %d Bossen ist keine Beute erfasst.",
  ["instances.gap.abilities"] = "Bei %d von %d Bossen sind keine Fähigkeiten erfasst.",
  ["instances.gap.questIds"] = "%d von %d Quests ohne Quest-ID (schwach belegt).",
  ["instances.gap.access"] = "Zugangsbedingungen noch nicht erfasst.",
})

local IV = {}
ns.InstanceView = IV

IV.PORTRAIT = 64
IV.ICON = 32
local PAD = 8
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Shown for a boss without a symbol when the client lacks the generic boss image too, so no boss row stays blank.
IV.PLACEHOLDER = QUESTION

-- Text helpers --------------------------------------------------------------------------------

function IV.Plural(value)
  return value ~= nil and tostring(value) or L["instances.unknown"]
end

-- Name in the active language, the other language muted behind it when it differs.
function IV.Dual(field)
  local main, other = R.Names(field)
  if main and other then
    return main .. "  " .. Theme.hexText("textMuted", other)
  end
  return main
end

-- One text per gap of the instance (ns.InstanceGaps), in the order of the data stand.
function IV.GapLines(inst)
  local lines = {}
  for _, gap in ipairs(ns.InstanceGaps.Of(inst)) do
    local text = L["instances.gap." .. gap.key]
    lines[#lines + 1] = gap.count and string.format(text, gap.count, gap.total) or text
  end
  return lines
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b, c = pcall(fn, ...)
  if ok then
    return a, b, c
  end
end

-- Name of an instance quest in the client language (the title of the game when the data has none).
function IV.QuestName(q)
  return ns.QuestNames and ns.QuestNames.Name(q) or ns.T(q.n)
end

-- Lines of one quest, the head line first. Shared by the quest text and the quest rows.
function IV.QuestLines(q, byId)
  local function names(ids)
    local out = {}
    for _, id in ipairs(ids) do
      out[#out + 1] = byId[id] and IV.QuestName(byId[id]) or ("#" .. id)
    end
    return table.concat(out, ", ")
  end
  local lines = {
    Theme.hexText(
      "accent2",
      string.format(L["instances.quest.head"], IV.QuestName(q) or "?", IV.Plural(q.l), IV.Plural(q.rq))
    ),
  }
  if q.sn then
    local start = string.format(L["instances.quest.start"], q.sn)
    if q.sz then
      start = start .. " " .. string.format(L["instances.quest.startIn"], ns.T(q.sz) or "?")
    end
    local pos = K.Coord(q.x, q.y)
    start = start
      .. " ("
      .. (pos and string.format(L["instances.quest.pos"], tostring(q.m or "?"), pos) or L["instances.quest.noStartPos"])
      .. ")"
    lines[#lines + 1] = start
  end
  if q.en then
    lines[#lines + 1] = string.format(L["instances.quest.end"], q.en)
  end
  if q.pre and #q.pre > 0 then
    lines[#lines + 1] = string.format(L["instances.quest.pre"], names(q.pre))
  end
  if q.nxt and #q.nxt > 0 then
    lines[#lines + 1] = string.format(L["instances.quest.next"], names(q.nxt))
  end
  local rewards = {}
  if q.xp then
    rewards[#rewards + 1] = string.format(L["instances.quest.xp"], q.xp)
  end
  if q.mo and q.mo > 0 then
    rewards[#rewards + 1] = ns.CostLogic.Format(q.mo) or "0"
  end
  for _, r in ipairs(q.rw or {}) do
    local name = r.n or ("#" .. tostring(r.id))
    if r.c and r.c > 1 then
      name = r.c .. "x " .. name
    end
    if r.ch then
      name = name .. " (" .. L["instances.quest.choice"] .. ")"
    end
    rewards[#rewards + 1] = name
  end
  if #rewards > 0 then
    lines[#lines + 1] = string.format(L["instances.quest.reward"], table.concat(rewards, ", "))
  end
  if ns.InstanceGaps.QuestWeak(q) then
    lines[#lines + 1] = Theme.hexText("warning", L["instances.quest.weak"])
  end
  return lines
end

-- Header numbers: level, group size, location, bosses and quests of the faction.
function IV.HeadText(inst, faction)
  local lines = {}
  local info = ns.InstanceLevelLogic.Of(inst, L)
  lines[1] = info.text
  if info.announced then
    -- The mark names the state in words, so it never depends on color.
    local mark = info.announcedText .. (info.releaseText and (" · " .. info.releaseText) or "")
    lines[#lines + 1] = Theme.hexText("warning", mark)
  elseif info.releaseText then
    -- Plain words in the muted text color: a date, not a warning.
    lines[#lines + 1] = Theme.hexText("textMuted", info.releaseText)
  end
  -- Entry and recommended level stand apart from the range: they answer "may I go in" and "how strong should I be".
  local second = {}
  for _, bit in ipairs({ info.entryText or false, info.recommendedText or false }) do
    if bit then
      second[#second + 1] = bit
    end
  end
  if #second > 0 then
    lines[#lines + 1] = table.concat(second, " · ")
  end
  if info.gapText then
    lines[#lines + 1] = Theme.hexText("warning", info.gapText)
  end
  lines[#lines + 1] = string.format(L["instances.info.group"], IV.Plural(inst.gs))
  if inst.loc then
    lines[#lines + 1] = string.format(L["instances.info.location"], IV.Dual(inst.loc))
  end
  local bosses = #(inst.bo or {})
  local quests = #R.Quests(inst, faction)
  local bits = {
    string.format(L["instances.bosses.count." .. (bosses == 1 and "one" or "other")], bosses),
    string.format(L["instances.head.quests." .. (quests == 1 and "one" or "other")], quests)
      .. (faction and (" (" .. L["kit.faction." .. faction] .. ")") or ""),
  }
  lines[#lines + 1] = table.concat(bits, " · ")
  local progress = ns.BossProgress and type(inst.id) == "number" and ns.BossProgress.WingSummary(inst) or nil
  if progress then
    lines[#lines + 1] = ns.BossProgress.SummaryText(progress)
  end
  return table.concat(lines, "\n")
end

-- The first entrance of the data (the other kinds, like a meeting stone, come after), else nil.
function IV.Entrance(inst)
  local first
  for _, e in ipairs(inst.ent or {}) do
    if e.m and e.x and e.y then
      if e.k == "entrance" then
        return e
      end
      first = first or e
    end
  end
  return first
end

-- Quest rewards of the instance as one entry per item: { id, name, count, choice, quests }.
function IV.Rewards(inst, faction)
  local out, byId = {}, {}
  for _, q in ipairs(R.Quests(inst, faction)) do
    for _, r in ipairs(q.rw or {}) do
      local entry = r.id and byId[r.id]
      if entry then
        entry.choice = entry.choice and r.ch == true
      else
        entry = { id = r.id, name = r.n, count = r.c, choice = r.ch == true, quests = {} }
        out[#out + 1] = entry
        if r.id then
          byId[r.id] = entry
        end
      end
      entry.quests[#entry.quests + 1] = IV.QuestName(q) or "?"
    end
  end
  return out
end

-- Game lookups ----------------------------------------------------------------------------------

-- false only when the client says the file is unknown; nil when it cannot tell.
local function known(fid)
  local P = ns.AssetFiles
  if not P.HasInfo() then
    return nil
  end
  local r = P.cache[fid] or P.Check(fid)
  return r.found
end
IV.Known = known

-- Name and icon of a spell from the client, nil when the client does not know the spell.
function IV.SpellInfo(id)
  local api = rawget(_G, "C_Spell")
  local info = type(api) == "table" and call(api.GetSpellInfo, id) or nil
  if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
    return info.name, info.iconID or info.originalIconID
  end
  local name, _, icon = call(rawget(_G, "GetSpellInfo"), id)
  if type(name) == "string" and name ~= "" then
    return name, icon
  end
end

local function itemApi(name)
  local c = rawget(_G, "C_Item")
  return type(c) == "table" and c[name] or nil
end

local requested = {}

-- Item name from the client (it also names the item in tooltips), else the English data name.
function IV.ItemName(entry)
  local name = call(itemApi("GetItemNameByID") or rawget(_G, "GetItemInfo"), entry.id)
  if type(name) == "string" and name ~= "" then
    return name
  end
  if entry.id and not requested[entry.id] then
    requested[entry.id] = true
    call(itemApi("RequestLoadItemDataByID"), entry.id)
  end
  return entry.name or ("#" .. tostring(entry.id))
end

-- Quality 0 to 7 from the client, nil while it does not know the item.
function IV.ItemQuality(id)
  local quality = call(itemApi("GetItemQualityByID"), id)
  if type(quality) ~= "number" then
    local _, _, fromInfo = call(rawget(_G, "GetItemInfo"), id)
    quality = fromInfo
  end
  return type(quality) == "number" and quality or nil
end

function IV.ItemIcon(id)
  local icon = call(itemApi("GetItemIconByID") or rawget(_G, "GetItemIcon"), id)
  return (type(icon) == "number" or type(icon) == "string") and icon or QUESTION
end

-- Loading screen ----------------------------------------------------------------------------------

-- Where the picture sits in its texture (assumed until the real image size is read, see Modules/AssetFiles.lua):
-- the old narrow screens hold a 4:3 picture in the top part of a square texture, the others fill
-- the whole texture. `aspect` is the width to height ratio of the picture.
local SOURCE = {
  narrow = { aspect = 4 / 3, v = 0.75 },
  wide = { aspect = 16 / 10, v = 1 },
  wide169 = { aspect = 16 / 9, v = 1 },
  main = { aspect = 16 / 9, v = 1 },
}

-- TexCoord rectangle (left, right, top, bottom) that cuts the picture to a box of w by h, centered.
-- tw, th (optional) are the real texture size: a square texture holds the 4:3 picture in its top
-- part, any other size is taken as the picture itself.
function IV.Crop(src, w, h, tw, th)
  local s = SOURCE[src] or SOURCE.main
  local aspect, v = s.aspect, s.v
  if tw and th and tw > 0 and th > 0 then
    if tw == th then
      aspect, v = 4 / 3, 0.75
    else
      aspect, v = tw / th, 1
    end
  end
  local want = (w > 0 and h > 0) and w / h or aspect
  local l, r, t, b = 0, 1, 0, v
  if want > aspect then
    t = v * (1 - aspect / want) / 2
    b = v - t
  else
    l = (1 - want / aspect) / 2
    r = 1 - l
  end
  return l, r, t, b
end

-- The picture of an instance: { fid, src }. Order: the loading screen of its map (loading screen data), then
-- the Camelot screen of the instance, nothing otherwise. A file the client reports as unknown is skipped.
function IV.LoadingImage(inst)
  local D = ns.Data and ns.Data.DungeonAssets
  local key = inst and inst.n and inst.n.en
  if not (D and key) then
    return nil
  end
  local own = D.loading and D.loading[key]
  local map = D.maps and D.maps[key]
  local list = {}
  if own then
    list[#list + 1] = { fid = own.fid, src = own.src }
  end
  if map and map.lo and not (own and own.fid == map.lo) then
    list[#list + 1] = { fid = map.lo, src = "main" }
  end
  for _, candidate in ipairs(list) do
    if known(candidate.fid) ~= false then
      return candidate
    end
  end
end

-- Boss portrait: { fid, kind } with kind "own" (the boss image), "default" (the generic boss image)
-- or "placeholder" (no usable file, the question mark icon). Order: the portraits of the data, the boss model
-- image (Data.BossModels icon), the generic image, the placeholder.
function IV.Portrait(inst, boss)
  local D = ns.Data and ns.Data.DungeonAssets
  local list = D and D.portraits and D.portraits[inst.n.en]
  local own = list and boss.n and list[boss.n.en]
  if own and known(own) ~= false then
    return own, "own"
  end
  local entry = boss.n and ns.DataApi.BossModel(inst.n.en, boss.n.en)
  if entry and entry.icon and known(entry.icon) ~= false then
    return entry.icon, "own"
  end
  if D and D.ejDefault and known(D.ejDefault) ~= false then
    return D.ejDefault, "default"
  end
  return IV.PLACEHOLDER, "placeholder"
end

-- What a boss shows as its picture: { fid, kind, display, creature }. fid and kind come from IV.Portrait (the symbol
-- file, else the generic image or the placeholder symbol). display is the creature display ID of the 3D portrait that
-- goes over the fallback symbol, creature the creature ID that stands in for a missing display ID. Both are nil when
-- the boss has a symbol file or no model in the data.
function IV.BossImage(inst, boss)
  local fid, kind = IV.Portrait(inst, boss)
  local display = kind ~= "own" and ns.BossModelWindow.DisplayId(inst, boss) or nil
  local creature = kind ~= "own" and ns.BossModelWindow.CreatureId(inst, boss) or nil
  return { fid = fid, kind = kind, display = display, creature = creature }
end

-- Paints the picture of a boss into `pic` (a texture of the frame `host`). A boss without a symbol file keeps the
-- fallback symbol until its small 3D portrait has loaded. Used by the boss row, the Items group header and the
-- boss mark of an item row, so every place shows the same image. Returns the image.
function IV.PaintBossImage(host, pic, inst, boss)
  local image = IV.BossImage(inst, boss)
  pic:SetTexture(image.fid)
  if image.display or image.creature then
    ns.BossPortrait.Bind(host, image.display, pic, image.creature)
  else
    ns.BossPortrait.Unbind(host)
    pic:SetAlpha(1)
  end
  return image
end

-- Header ------------------------------------------------------------------------------------------

local BUTTON_H = 22
local CHIP_H = 22
local CHIP_PAD = 8
local ROW_GAP = 4

-- Map button with the icon and the short label (W.Action). Without a place it stays focusable but
-- dimmed and the tooltip says why (same rule as the dim list actions).
local function newMapButton(parent, onClick)
  local b = W.Action(parent, {
    label = "act.map",
    icon = "map",
    height = BUTTON_H,
    opens = true,
    onClick = onClick,
    manual = true,
  })
  b.fgNameKey = "instances.map"
  local function show()
    ns.ShowTooltip(
      b,
      L["instances.map"],
      b.fgPlace and L["instances.map.tip"] or L["instances.map.none"],
      { hint = L["action.opensWindow"] }
    )
  end
  b:HookScript("OnEnter", show)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = show, ns.HideTooltip
  function b:SetPlace(place)
    self.fgPlace = place
    self:SetAlpha(place and 1 or 0.45)
  end
  return b
end

-- "Data incomplete" button with the list of gaps as its tooltip (mouse and keyboard focus). It stays a button so
-- the keyboard user reaches the list too.
local function newGapButton(parent)
  local b
  local function gapLines()
    local lines = {}
    for _, line in ipairs(b.fgLines or {}) do
      lines[#lines + 1] = "· " .. line
    end
    return lines
  end
  b = W.Action(parent, {
    key = "instances.gap.badge",
    icon = "alert",
    variant = "ghost",
    height = BUTTON_H,
    onClick = function()
      ns.Print(L["instances.gap.title"] .. "\n" .. table.concat(gapLines(), "\n"))
    end,
  })
  local function show()
    local lines = gapLines()
    ns.ShowTooltip(b, L["instances.gap.title"], table.concat(lines, "\n"), { hint = L["instances.gap.hint"] })
  end
  b:HookScript("OnEnter", show)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = show, ns.HideTooltip
  return b
end

-- One fact of the banner: a dark label with text.
local function newChip(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(CHIP_H)
  c.fill = c:CreateTexture(nil, "BACKGROUND")
  c.fill:SetAllPoints()
  ns.Bind(c.fill, function(t)
    t:SetColorTexture(Theme.scrim(Theme.highContrast() and 0.92 or 0.7))
  end)
  c.text = W.Text(c, { role = "ui", color = "text" })
  c.text:SetPoint("CENTER")
  return c
end

local function chipWidth(chip)
  return math.ceil(chip.text:GetStringWidth()) + 2 * CHIP_PAD
end

-- Facts of the banner as { text } chips, in reading order: level entry, group size, counts, kill progress, and the
-- mark of an announced instance. Plain words, so no fact depends on color.
function IV.BannerChips(inst, faction)
  local info = ns.InstanceLevelLogic.Of(inst, L)
  local chips = {}
  local second = {}
  for _, bit in ipairs({ info.entryText or false, info.recommendedText or false }) do
    if bit then
      second[#second + 1] = bit
    end
  end
  if #second > 0 then
    chips[#chips + 1] = { text = table.concat(second, " · ") }
  end
  chips[#chips + 1] = { text = ns.InstanceListLogic.PlayersText(inst, L) }
  local bosses = #(inst.bo or {})
  local quests = #R.Quests(inst, faction)
  chips[#chips + 1] = {
    text = string.format(L["instances.bosses.count." .. (bosses == 1 and "one" or "other")], bosses)
      .. " · "
      .. string.format(L["instances.head.quests." .. (quests == 1 and "one" or "other")], quests),
    counts = true,
  }
  local progress = ns.BossProgress and type(inst.id) == "number" and ns.BossProgress.WingSummary(inst) or nil
  if progress then
    chips[#chips + 1] = { text = ns.BossProgress.SummaryText(progress) }
  end
  if info.announced then
    chips[#chips + 1] = {
      text = Theme.hexText("warning", info.announcedText .. (info.releaseText and (" · " .. info.releaseText) or "")),
    }
  elseif info.releaseText then
    chips[#chips + 1] = { text = Theme.hexText("textMuted", info.releaseText) }
  end
  return chips
end

-- Compact banner: the loading screen behind a dark gradient, left the name with "level · zone" (and the buttons
-- "All instances" and "Reset" above it), right the fact chips, the map button and the data hint. The page measures
-- it (:Measure) before it asks the layout logic and places it with :Apply(width, layout).
-- opts.onBack: the click of the back button.
function IV.Header(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.art = ns.InstanceArt.Create(f)
  -- A child frame draws above the art, so the gradient and the texts live in one frame over it.
  f.over = CreateFrame("Frame", nil, f)
  f.over:SetFrameLevel(f.art:GetFrameLevel() + 2)
  f.shade = f.over:CreateTexture(nil, "BACKGROUND")
  f.shade:SetAllPoints()
  ns.Bind(f.shade, function(t)
    -- At least 60 percent black behind any text (AA contrast on every picture), more in high contrast.
    local strong, weak = Theme.highContrast() and 0.95 or 0.88, Theme.highContrast() and 0.92 or 0.6
    t:SetColorTexture(1, 1, 1, 1)
    local color = rawget(_G, "CreateColor")
    local ok = type(t.SetGradient) == "function"
      and type(color) == "function"
      and pcall(t.SetGradient, t, "HORIZONTAL", color(0, 0, 0, strong), color(0, 0, 0, weak))
    if not ok then
      t:SetColorTexture(Theme.scrim(strong))
    end
  end)
  f.name = W.Text(f.over, { role = "h2", family = "heading", color = "accent2" })
  f.name:SetWordWrap(false)
  f.sub = W.Text(f.over, { role = "ui", color = "textSecondary" })
  f.sub:SetWordWrap(false)
  f.back = W.Action(f.over, {
    label = "instances.back",
    icon = "chevron-left",
    variant = "ghost",
    height = BUTTON_H,
    opens = false,
    tooltip = "instances.back",
    tooltipText = "instances.back.tip",
    onClick = opts and opts.onBack,
  })
  f.reset = ns.InstanceReset.Button(f.over)
  f.reset:SetVariant("ghost")
  f.reset:SetHeight(BUTTON_H)
  f.mapButton = newMapButton(f.over, function()
    local place = f.mapButton.fgPlace
    if place then
      K.PlaceOnMap(place)
    end
  end)
  f.gapButton = newGapButton(f.over)
  f.chips, f.chipData = {}, {}
  f.summary = newChip(f.over)
  f.summary:EnableMouse(true)
  local function showFacts()
    ns.ShowTooltip(f.summary, L["instances.banner.facts"], f.fgFactsTip or "")
  end
  f.summary:SetScript("OnEnter", showFacts)
  f.summary:SetScript("OnLeave", ns.HideTooltip)
  f.summary.fgName = function()
    return f.summary.text:GetText()
  end
  f.summary.fgDescription = function()
    return f.fgFactsTip
  end
  f.summary.fgOnFocus, f.summary.fgOnBlur = showFacts, ns.HideTooltip
  ns.Focus.register(f.summary, function() end)
  f.summary:Hide()

  function f:SetInstance(inst, faction)
    self:SetShown(inst ~= nil)
    if not inst then
      return
    end
    -- self.inst keeps the last instance shown while the cards are on screen.
    self.inst = inst
    local name = R.Names(inst.n)
    self.name:SetText(IV.Dual(inst.n) or "?")
    local info = ns.InstanceLevelLogic.Of(inst, L)
    local zone = inst.loc and R.Names(inst.loc) or nil
    self.sub:SetText(zone and (info.text .. " · " .. zone) or info.text)
    self.chipData = IV.BannerChips(inst, faction)
    local counts = ""
    for i, data in ipairs(self.chipData) do
      local chip = self.chips[i]
      if not chip then
        chip = newChip(self.over)
        self.chips[i] = chip
      end
      chip.text:SetText(data.text)
      if data.counts then
        counts = data.text
      end
    end
    -- The summary keeps the counts, the tooltip names every fact of the instance.
    self.summary.text:SetText(counts .. " · …")
    self.fgFactsTip = IV.HeadText(inst, faction)
    local entrance = IV.Entrance(inst)
    self.mapButton:SetPlace(
      entrance and { map = entrance.m, x = entrance.x, y = entrance.y, label = name or inst.n.en } or nil
    )
    self.gapButton.fgLines = IV.GapLines(inst)
    self.hasGap = #self.gapButton.fgLines > 0
    self.art:SetInstance(inst)
  end

  -- Widths the layout logic needs: { nameW, chipWidths, actionW, summaryW }.
  function f:Measure()
    local chipWidths, actions = {}, {}
    for i = 1, #self.chipData do
      chipWidths[i] = chipWidth(self.chips[i])
    end
    self.mapButton:SetWidth(self.mapButton:Fit())
    actions[1] = self.mapButton:GetWidth()
    if self.hasGap then
      actions[2] = self.gapButton:Fit(400)
    end
    return {
      nameW = math.ceil(self.name:GetStringWidth()),
      buttonsW = self.back:Fit() + 6 + self.reset:Fit(),
      chipWidths = chipWidths,
      actionW = actions,
      summaryW = chipWidth(self.summary),
    }
  end

  -- Items of the right block in reading order: the chips (or the summary), the map button, the data hint.
  local function rightItems(self, layout)
    local items = {}
    if not layout.bannerCollapsed then
      if layout.chipsMode == "wrap" then
        for i = 1, #self.chipData do
          items[#items + 1] = self.chips[i]
        end
      else
        items[#items + 1] = self.summary
      end
    end
    if not layout.bannerCollapsed then
      items[#items + 1] = self.mapButton
      if self.hasGap then
        items[#items + 1] = self.gapButton
      end
    end
    return items
  end

  -- Places everything for a layout of the logic (width: the page column). Returns the height.
  function f:Apply(width, layout)
    local ILL = ns.InstanceLayoutLogic
    local PADX, collapsed, h = ILL.BANNER_PAD, layout.bannerCollapsed, layout.bannerH
    self.art:ClearAllPoints()
    self.art:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.art:Layout(width, h)
    self.over:ClearAllPoints()
    self.over:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.over:SetSize(width, h)

    -- Left block.
    -- Both buttons keep their label while the row has room; the reset gives its label up first, then the back button.
    local avail = width - 2 * PADX
    local backW = self.back:Fit(avail - self.reset:Fit(0) - 6)
    self.back:SetWidth(backW)
    self.reset:SetWidth(self.reset:Fit(avail - backW - 6))
    for _, frame in ipairs({ self.back, self.reset, self.name, self.sub }) do
      frame:ClearAllPoints()
    end
    self.sub:SetShown(not collapsed)
    local nameW = math.max(40, layout.nameW)
    if collapsed then
      self.back:SetPoint("LEFT", self.over, "LEFT", PADX, 0)
      self.reset:SetPoint("LEFT", self.back, "RIGHT", 6, 0)
      self.name:SetPoint("LEFT", self.reset, "RIGHT", 10, 0)
      local used = self.back:GetWidth() + self.reset:GetWidth() + 3 * PADX + 6
      self.name:SetWidth(math.max(40, math.min(nameW, width - used)))
    else
      self.back:SetPoint("TOPLEFT", self.over, "TOPLEFT", PADX, -6)
      self.reset:SetPoint("LEFT", self.back, "RIGHT", 6, 0)
      self.name:SetPoint("TOPLEFT", self.over, "TOPLEFT", PADX, -32)
      self.name:SetWidth(nameW)
      self.sub:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -2)
      self.sub:SetWidth(nameW)
    end

    -- Right block, packed into lines and aligned to the right padding.
    local items = rightItems(self, layout)
    for i, chip in ipairs(self.chips) do
      chip:SetShown(not collapsed and layout.chipsMode == "wrap" and i <= #self.chipData)
    end
    self.summary:SetShown(not collapsed and layout.chipsMode == "summary")
    self.mapButton:SetShown(not collapsed)
    self.gapButton:SetShown(self.hasGap == true and not collapsed)
    local room = layout.chipRoom
    local gap = ILL.CHIP_GAP
    local widths, lines, line, x = {}, {}, {}, 0
    for i, item in ipairs(items) do
      local w = item:GetWidth()
      if item == self.gapButton then
        w = math.min(item:Fit(room), room)
      elseif item ~= self.mapButton then
        w = chipWidth(item)
      end
      item:SetWidth(w)
      widths[i] = w
      if x > 0 and x + w > room then
        lines[#lines + 1], line, x = line, {}, 0
      end
      line[#line + 1] = i
      x = x + w + gap
    end
    lines[#lines + 1] = line
    local blockH = #lines * BUTTON_H + (#lines - 1) * ROW_GAP
    local top = math.max(2, math.floor((h - blockH) / 2))
    if layout.bannerStacked then
      top = ILL.BANNER_H + ILL.STACK_GAP
    end
    for n, indexes in ipairs(lines) do
      local lineW = -gap
      for _, i in ipairs(indexes) do
        lineW = lineW + widths[i] + gap
      end
      local cx = width - PADX - lineW
      for _, i in ipairs(indexes) do
        local item = items[i]
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", self.over, "TOPLEFT", cx, -(top + (n - 1) * (BUTTON_H + ROW_GAP)))
        cx = cx + widths[i] + gap
      end
    end
    self:SetSize(width, h)
    return h
  end

  return f
end

-- Rows --------------------------------------------------------------------------------------------

local function newLine(row)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(Theme.fillColor("line"))
  end)
end

-- Boss rows: portrait, name with tags and the ability chips. opts.heading: the detail of the bosses tab
-- (Modules/InstanceBossPanel.lua), the plain name as a heading and the number, level, tags and state on a line below.
local function makeBossRow(parent, opts)
  local heading = opts and opts.heading or false
  local row = CreateFrame("Frame", nil, parent)
  row.heading = heading
  row.portrait = CreateFrame("Frame", nil, row)
  row.portrait:SetSize(IV.PORTRAIT, IV.PORTRAIT)
  row.pic = row.portrait:CreateTexture(nil, "ARTWORK")
  row.pic:SetAllPoints()
  row.name = W.Text(row, { role = heading and "h3" or "text", color = "text", wrap = true })
  row.meta = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.meta:SetShown(heading)
  row.abLabel = W.Text(row, { key = "instances.abilities", role = "micro", color = "textMuted" })
  row.chips = K.ChipRow(row)
  -- Shown instead of the abilities when the data has none for this boss, so a gap reads as "not recorded".
  row.abNone = W.Text(row, { key = "instances.abilities.none", role = "micro", color = "textSecondary", wrap = true })
  -- Abilities known by name only (no spell ID): a plain line, no chips without a symbol.
  row.names = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  newLine(row)
  -- Page link of this boss (instances/<slug>/bosses/<eid>), hidden for a boss without an ID.
  row.share = ns.PageShare.Button(row, {})
  -- Portrait and name open the 3D model of a boss that has one.
  row.modelPic = ns.BossModelWindow.Hotspot(row, row.portrait)
  row.modelName = ns.BossModelWindow.Hotspot(row, row.name, true)

  function row:fgLayout(width)
    local textX = IV.PORTRAIT + 12
    local shareW = self.share:IsShown() and (self.share:GetWidth() + 8) or 0
    local textW = math.max(40, width - textX - shareW)
    self.share:ClearAllPoints()
    self.share:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -PAD)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -PAD)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.name:SetWidth(textW)
    -- An explicit height gives the click area over the name its size.
    self.name:SetHeight(math.max(1, math.ceil(self.name:GetStringHeight())))
    local y = PAD + math.ceil(self.name:GetStringHeight()) + 4
    if self.meta:IsShown() then
      self.meta:ClearAllPoints()
      self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      self.meta:SetWidth(textW)
      y = y + math.ceil(self.meta:GetStringHeight()) + 6
    end
    if self.abMissing then
      self.abNone:ClearAllPoints()
      self.abNone:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      self.abNone:SetWidth(textW)
      y = y + math.ceil(self.abNone:GetStringHeight()) + 2
    elseif self.hasAbilities then
      self.abLabel:ClearAllPoints()
      self.abLabel:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      y = y + math.ceil(self.abLabel:GetStringHeight()) + 2
      if self.chips:IsShown() then
        self.chips:ClearAllPoints()
        self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        self.chips:SetWidth(textW)
        y = y + self.chips:Layout(textW)
      end
      if self.names:IsShown() then
        self.names:ClearAllPoints()
        self.names:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        self.names:SetWidth(textW)
        y = y + math.ceil(self.names:GetStringHeight()) + 2
      end
    end
    return math.max(IV.PORTRAIT + PAD * 2, y + PAD, self.share:IsShown() and (PAD * 2 + self.share:GetHeight()) or 0)
  end
  return row
end

-- Chips for the abilities with a spell ID, and the names of those that have a name only.
local function abilityChips(list)
  local chips, names = {}, {}
  for _, a in ipairs(list or {}) do
    if a.s then
      local name, icon = IV.SpellInfo(a.s)
      chips[#chips + 1] = {
        icon = icon or QUESTION,
        name = name or string.format(L["instances.spell.unknown"], a.s),
        meta = name and "" or L["instances.spell.unknownMeta"],
        sid = a.s,
      }
    elseif a.n then
      local name = ns.T(a.n)
      if name and name ~= "" then
        names[#names + 1] = name
      end
    end
  end
  return chips, names
end

-- Word for the kill state of a boss in this run ("defeated", "probably defeated"), nil while it is open. index is
-- the place in inst.bo; wings share one progress state, WingStatus moves it to the place in the whole dungeon.
function IV.ProgressText(inst, index)
  local progress = ns.BossProgress and ns.BossProgress.WingStatus(inst, index)
  if progress then
    return L[progress == "confirmed" and "bossprogress.defeated" or "bossprogress.likely"]
  end
end

-- Level of a boss as text ("Level 28"), nil when the data has none.
function IV.BossLevel(boss)
  return type(boss.lvl) == "number" and string.format(L["instances.bosses.level"], boss.lvl) or nil
end

-- Page link of a boss: instances/<slug>/bosses/<eid>, nil when the data has no encounter ID.
function IV.BossSharePayload(inst, boss)
  if not (inst and boss and type(boss.eid) == "number") then
    return nil
  end
  return "instances/" .. R.InstanceSlug(inst) .. "/bosses/" .. boss.eid
end

-- item = { inst, boss, index }; heading rows also take position and total (place among the regular bosses) or
-- rare = true.
local function paintBossRow(row, item)
  local boss = item.boss
  row.share:SetTarget(IV.BossSharePayload(item.inst, boss))
  local progress = IV.ProgressText(item.inst, item.index)
  if row.heading then
    row.name:SetText(IV.Dual(boss.n) or "?")
    local bits = {
      item.rare and L["instances.bosses.rare"]
        or string.format(L["instances.bosses.position"], item.position or item.index, item.total or item.index),
    }
    bits[#bits + 1] = IV.BossLevel(boss)
    -- A rare is optional by nature, the word rare says it already.
    bits[#bits + 1] = boss.opt and not item.rare and L["instances.bosses.optional"] or nil
    bits[#bits + 1] = boss.hc and L["instances.bosses.heroic"] or nil
    bits[#bits + 1] = progress
    row.meta:SetText(table.concat(bits, " · "))
  else
    local text = string.format("%d. %s", item.index, IV.Dual(boss.n) or "?")
    if boss.opt then
      text = text .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
    end
    if boss.hc then
      text = text .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
    end
    if progress then
      text = text .. "  " .. Theme.hexText("textMuted", progress)
    end
    row.name:SetText(text)
  end
  row.modelPic:SetBoss(item.inst, boss)
  row.modelName:SetBoss(item.inst, boss)
  local image = IV.PaintBossImage(row.portrait, row.pic, item.inst, boss)
  row.portraitKind = image.kind
  row.hasPortrait = image.display ~= nil
  local chips, names = abilityChips(boss.ab)
  row.hasAbilities = #chips > 0 or #names > 0
  row.abMissing = not ns.InstanceGaps.HasAbilities(boss)
  row.abNone:SetShown(row.abMissing)
  row.abLabel:SetShown(row.hasAbilities)
  row.chips:SetShown(#chips > 0)
  row.chips:SetChips(chips)
  row.names:SetShown(#names > 0)
  row.names:SetText(table.concat(names, ", "))
end

IV.BossRow, IV.PaintBossRow = makeBossRow, paintBossRow

-- Quest rows: head line, details and the map buttons of the start position.
local function makeQuestRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.title = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.body = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.actions = W.MapActionButtons(row, { share = true })
  newLine(row)

  function row:fgLayout(width)
    local textW = width
    self.actions:ClearAllPoints()
    if self.actions:IsShown() then
      self.actions:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -PAD)
      textW = width - self.actions:GetWidth() - 8
    end
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -PAD)
    self.title:SetWidth(math.max(40, textW))
    local y = PAD + math.ceil(self.title:GetStringHeight()) + 2
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.body:SetWidth(math.max(40, width))
    y = y + math.ceil(self.body:GetStringHeight())
    return math.max(y + PAD, self.actions:IsShown() and (PAD * 2 + self.actions:GetHeight()) or 0)
  end
  return row
end

-- item = { quest, lines }
local function paintQuestRow(row, item)
  local q, lines = item.quest, item.lines
  local title = lines[1]
  if q.f == "A" or q.f == "H" then
    title = title .. "  " .. Theme.hexText("textMuted", L["kit.faction." .. q.f])
  elseif item.mixed then
    title = title .. "  " .. Theme.hexText("textMuted", L["kit.faction.all"])
  end
  row.title:SetText(title)
  local body = {}
  for i = 2, #lines do
    body[#body + 1] = lines[i]
  end
  row.body:SetText(table.concat(body, "\n"))
  row.body:SetShown(#body > 0)
  local place = q.m and q.x and q.y and { map = q.m, x = q.x, y = q.y, label = q.sn or ns.T(q.n) } or nil
  row.actions:SetPlace(place)
  row.actions:SetShare(ns.QuestChainView.SharePayload(item.inst, { id = q.id }))
end

-- Pooled lists. Each one takes the instance and the faction ("A", "H" or nil) with :SetInstance.
function IV.BossList(parent)
  local list = K.RowPool(parent, makeBossRow)
  function list:SetInstance(inst)
    local items = {}
    for i, boss in ipairs(inst and inst.bo or {}) do
      items[i] = { inst = inst, boss = boss, index = i }
    end
    self.count = #items
    self:Sync(items, paintBossRow)
  end
  return list
end

-- Quests grouped Alliance, Horde, both, each group by level and name.
function IV.GroupedQuests(quests)
  local copy = {}
  for i, q in ipairs(quests) do
    copy[i] = q
  end
  return ns.InstanceLevelLogic.Sort(copy, true, false, function(a, b)
    if (a.l or 0) ~= (b.l or 0) then
      return (a.l or 0) < (b.l or 0)
    end
    return (ns.T(a.n) or "") < (ns.T(b.n) or "")
  end)
end

function IV.QuestList(parent)
  local list = K.RowPool(parent, makeQuestRow)
  function list:SetInstance(inst, faction)
    local items, byId = {}, {}
    for _, q in ipairs(inst and inst.q or {}) do
      byId[q.id or 0] = q
    end
    local quests = inst and IV.GroupedQuests(R.Quests(inst, faction)) or {}
    local mixed = false
    for _, q in ipairs(quests) do
      mixed = mixed or q.f == "A" or q.f == "H"
    end
    for _, q in ipairs(quests) do
      items[#items + 1] = { inst = inst, quest = q, lines = IV.QuestLines(q, byId), mixed = mixed }
    end
    self.count = #items
    self:Sync(items, paintQuestRow)
  end
  return list
end
