-- Detail views of the instances page (Modules/InstancesPage.lua): the header with the loading screen, the
-- map button and the numbers, and the pooled row lists for bosses and quests (the items are in
-- Modules/InstanceItemsView.lua). Data:
-- ns.Data.Instances and ns.Data.DungeonAssets. Every game call goes through pcall, so a missing API
-- shows a placeholder and never raises.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit

ns.AddLocale("enUS", {
  ["instances.map"] = "Map",
  ["instances.map.tip"] = "Show the entrance on the world map",
  ["instances.map.none"] = "No entrance position in the data for this instance.",
  ["instances.dtab.items"] = "Items",
  ["instances.head.recommended"] = "recommended from level %d",
  ["instances.head.quests.one"] = "1 quest",
  ["instances.head.quests.other"] = "%d quests",
  ["instances.pick.text"] = "Pick a dungeon or raid from the list to see its bosses, quests, rewards and entrance.",
  ["instances.abilities"] = "Abilities",
  ["instances.spell.unknown"] = "Spell %d",
  ["instances.spell.unknownMeta"] = "not known to this client",
  ["instances.items.loot"] = "No loot tables in the data yet.\nItems you find yourself are recorded by the loot capture.",
  ["instances.items.open"] = "Open loot capture",
  ["instances.items.none"] = "No items recorded for this instance yet.",
  ["instances.items.from"] = "Reward for: %s",
  ["instances.quest.weak"] = "Weakly confirmed: no quest ID in the data, details may be incomplete.",
  ["instances.gap.badge"] = "Data incomplete",
  ["instances.gap.title"] = "Data incomplete",
  ["instances.gap.hint"] = "Missing means not recorded yet, not that it does not exist.",
  ["instances.gap.head"] = "Data stand: incomplete",
  ["instances.gap.complete"] = "Data stand: nothing missing",
  ["instances.gap.id"] = "No game instance ID.",
  ["instances.gap.name"] = "Instance name in English only.",
  ["instances.gap.level"] = "Level not recorded.",
  ["instances.gap.levelRange"] = "Level range missing, only the recommended level is known.",
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
  ["instances.map.tip"] = "Eingang auf der Weltkarte zeigen",
  ["instances.map.none"] = "Für diese Instanz ist in den Daten kein Eingang erfasst.",
  ["instances.dtab.items"] = "Items",
  ["instances.head.recommended"] = "empfohlen ab Stufe %d",
  ["instances.head.quests.one"] = "1 Quest",
  ["instances.head.quests.other"] = "%d Quests",
  ["instances.pick.text"] = "Wähle einen Dungeon oder Raid aus der Liste, dann siehst du Bosse, Quests, Belohnungen und Eingang.",
  ["instances.abilities"] = "Fähigkeiten",
  ["instances.spell.unknown"] = "Zauber %d",
  ["instances.spell.unknownMeta"] = "dem Client unbekannt",
  ["instances.items.loot"] = "Noch keine Beutetabellen in den Daten.\nWas du selbst findest, erfasst die Beute-Erfassung.",
  ["instances.items.open"] = "Beute-Erfassung öffnen",
  ["instances.items.none"] = "Für diese Instanz sind noch keine Items erfasst.",
  ["instances.items.from"] = "Belohnung für: %s",
  ["instances.quest.weak"] = "Schwach belegt: keine Quest-ID in den Daten, Angaben können unvollständig sein.",
  ["instances.gap.badge"] = "Daten unvollständig",
  ["instances.gap.title"] = "Daten unvollständig",
  ["instances.gap.hint"] = "Fehlt heißt noch nicht erfasst, nicht dass es das nicht gibt.",
  ["instances.gap.head"] = "Datenstand: unvollständig",
  ["instances.gap.complete"] = "Datenstand: nichts fehlt",
  ["instances.gap.id"] = "Keine Spiel-Instanz-ID.",
  ["instances.gap.name"] = "Instanzname nur auf Englisch.",
  ["instances.gap.level"] = "Stufe nicht erfasst.",
  ["instances.gap.levelRange"] = "Stufenbereich fehlt, nur die empfohlene Stufe ist bekannt.",
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

-- Lines of one quest, the head line first. Shared by the quest text and the quest rows.
function IV.QuestLines(q, byId)
  local function names(ids)
    local out = {}
    for _, id in ipairs(ids) do
      out[#out + 1] = byId[id] and ns.T(byId[id].n) or ("#" .. id)
    end
    return table.concat(out, ", ")
  end
  local lines = {
    Theme.hexText(
      "accent2",
      string.format(L["instances.quest.head"], ns.T(q.n) or "?", IV.Plural(q.l), IV.Plural(q.rq))
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
    rewards[#rewards + 1] = R.Money(q.mo)
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
  local level = ns.InstanceLevelLabel(inst)
  if inst.lv and inst.rl then
    level = level .. " · " .. string.format(L["instances.head.recommended"], inst.rl)
  end
  lines[1] = level
  lines[2] = string.format(L["instances.info.group"], IV.Plural(inst.gs))
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
  local progress = ns.BossProgress and type(inst.id) == "number" and ns.BossProgress.Summary(inst.id) or nil
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
      entry.quests[#entry.quests + 1] = ns.T(q.n) or "?"
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
-- or "initial" (no usable file, the caller draws the first letter in a circle).
function IV.Portrait(inst, boss)
  local D = ns.Data and ns.Data.DungeonAssets
  local list = D and D.portraits and D.portraits[inst.n.en]
  local own = list and boss.n and list[boss.n.en]
  if own and known(own) ~= false then
    return own, "own"
  end
  if D and D.ejDefault and known(D.ejDefault) ~= false then
    return D.ejDefault, "default"
  end
  return nil, "initial"
end

local function firstLetter(text)
  return (tostring(text or "?"):match("[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
end
IV.FirstLetter = firstLetter

-- Header ------------------------------------------------------------------------------------------

local IMG_W, IMG_H = 192, 108
local SIDE_MIN = 440 -- the picture sits beside the text from this width on
local BUTTON_H = 26

-- Map button with the icon and the short label (W.Action). Without a place it stays focusable but
-- dimmed and the tooltip says why (same rule as the dim list actions).
local function newMapButton(parent, onClick)
  local b = W.Action(parent, { label = "act.map", icon = "map", height = BUTTON_H, onClick = onClick, manual = true })
  b.fgNameKey = "instances.map"
  local function show()
    ns.ShowTooltip(b, L["instances.map"], b.fgPlace and L["instances.map.tip"] or L["instances.map.none"])
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

-- Picture, name with second name, numbers and the map button of the chosen instance.
-- fgGridLayout(width) places everything and returns the height, so a page Stack can hold it.
function IV.Header(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.box = CreateFrame("Frame", nil, f)
  W.Fill(f.box, "surface", 1)
  W.Border(f.box, "white")
  f.picture = f.box:CreateTexture(nil, "ARTWORK")
  f.picture:SetPoint("TOPLEFT", 1, -1)
  f.picture:SetPoint("BOTTOMRIGHT", -1, 1)
  f.name = W.Text(f, { role = "h2", family = "heading", color = "accent2", wrap = true })
  f.alt = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.meta = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.mapButton = newMapButton(f, function()
    local place = f.mapButton.fgPlace
    if place then
      K.PlaceOnMap(place)
    end
  end)
  f.gapButton = newGapButton(f)

  function f:SetInstance(inst, faction)
    self.inst, self.image = inst, nil
    self:SetShown(inst ~= nil)
    if not inst then
      return
    end
    local name, other = R.Names(inst.n)
    self.name:SetText(name or "?")
    self.alt:SetText(other or "")
    self.alt:SetShown(other ~= nil)
    self.meta:SetText(IV.HeadText(inst, faction))
    local entrance = IV.Entrance(inst)
    self.mapButton:SetPlace(
      entrance and { map = entrance.m, x = entrance.x, y = entrance.y, label = name or inst.n.en } or nil
    )
    self.gapButton.fgLines = IV.GapLines(inst)
    self.gapButton:SetShown(#self.gapButton.fgLines > 0)
    self.image = IV.LoadingImage(inst)
    self.picture:SetTexture(self.image and self.image.fid or nil)
    self.box:SetShown(self.image ~= nil)
  end

  function f:fgGridLayout(width)
    local side = width >= SIDE_MIN
    local textX, textW, y = 0, width, 0
    if self.image then
      local boxW = side and IMG_W or width
      self.box:ClearAllPoints()
      self.box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.box:SetSize(boxW, IMG_H)
      local P = ns.AssetFiles
      local info = P.cache[self.image.fid]
      self.picture:SetTexCoord(IV.Crop(self.image.src, boxW - 2, IMG_H - 2, info and info.w, info and info.h))
      if side then
        textX, textW = IMG_W + 12, width - IMG_W - 12
      else
        y = IMG_H + 8
      end
    end
    local function place(item, gap)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      item:SetWidth(textW)
      y = y + math.ceil(item:GetStringHeight()) + gap
    end
    place(self.name, 2)
    if self.alt:IsShown() then
      place(self.alt, 4)
    end
    place(self.meta, 8)
    self.mapButton:SetWidth(self.mapButton:Fit())
    self.mapButton:ClearAllPoints()
    self.mapButton:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
    if self.gapButton:IsShown() then
      local gapW = math.min(self.gapButton:Fit(textW), textW)
      self.gapButton:SetWidth(gapW)
      self.gapButton:ClearAllPoints()
      if self.mapButton:GetWidth() + 8 + gapW <= textW then
        self.gapButton:SetPoint("LEFT", self.mapButton, "RIGHT", 8, 0)
      else
        y = y + BUTTON_H + 6
        self.gapButton:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      end
    end
    y = y + BUTTON_H
    local height = math.max(y, self.image and side and IMG_H or 0)
    self:SetHeight(height)
    return height
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
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
end

-- Grid of 12 on 12: a filled circle of 24 rows, so the 64 px disc has soft edges.
local function drawDisc(p)
  local rows = 24
  for j = 0, rows - 1 do
    local ny = (j + 0.5 - rows / 2) / (rows / 2)
    local half = math.sqrt(math.max(0, 1 - ny * ny)) * 6
    p:Rect(6 - half, j * 0.5, 2 * half, 0.5, "surface3")
  end
end

IV.DrawDisc = drawDisc

-- Boss rows: portrait, name with tags and the ability chips.
local function makeBossRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.portrait = CreateFrame("Frame", nil, row)
  row.portrait:SetSize(IV.PORTRAIT, IV.PORTRAIT)
  row.pic = row.portrait:CreateTexture(nil, "ARTWORK")
  row.pic:SetAllPoints()
  row.letter = W.Text(row.portrait, { role = "title", family = "heading", color = "accent2", justify = "CENTER" })
  row.letter:SetPoint("CENTER")
  row.name = W.Text(row, { role = "text", color = "text", wrap = true })
  row.abLabel = W.Text(row, { key = "instances.abilities", role = "micro", color = "textMuted" })
  row.chips = K.ChipRow(row)
  newLine(row)

  function row:fgLayout(width)
    local textX = IV.PORTRAIT + 12
    local textW = math.max(40, width - textX)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -PAD)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.name:SetWidth(textW)
    local y = PAD + math.ceil(self.name:GetStringHeight()) + 4
    if self.hasAbilities then
      self.abLabel:ClearAllPoints()
      self.abLabel:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      y = y + math.ceil(self.abLabel:GetStringHeight()) + 2
      self.chips:ClearAllPoints()
      self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
      self.chips:SetWidth(textW)
      y = y + self.chips:Layout(textW)
    end
    return math.max(IV.PORTRAIT + PAD * 2, y + PAD)
  end
  return row
end

local function abilityChips(list)
  local chips = {}
  for _, a in ipairs(list or {}) do
    local name, icon = IV.SpellInfo(a.s)
    chips[#chips + 1] = {
      icon = icon or QUESTION,
      name = name or string.format(L["instances.spell.unknown"], a.s),
      meta = name and "" or L["instances.spell.unknownMeta"],
      sid = a.s,
    }
  end
  return chips
end

-- item = { inst, boss, index }
local function paintBossRow(row, item)
  local boss = item.boss
  local text = string.format("%d. %s", item.index, IV.Dual(boss.n) or "?")
  if boss.opt then
    text = text .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
  end
  if boss.hc then
    text = text .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
  end
  local progress = ns.BossProgress and ns.BossProgress.Status(item.inst.id, item.index)
  if progress then
    text = text
      .. "  "
      .. Theme.hexText("textMuted", L[progress == "confirmed" and "bossprogress.defeated" or "bossprogress.likely"])
  end
  row.name:SetText(text)
  local fid, kind = IV.Portrait(item.inst, boss)
  row.portraitKind = kind
  row.pic:SetTexture(fid)
  row.pic:SetShown(fid ~= nil)
  -- The disc is 24 textures, so only a row that needs it builds it.
  if fid == nil and not row.disc then
    row.disc = ns.IconDraw.new(row.portrait, IV.PORTRAIT)
    row.disc:SetPoint("TOPLEFT")
    row.disc:Draw(drawDisc, "?")
  end
  if row.disc then
    row.disc:SetShown(fid == nil)
  end
  row.letter:SetText(firstLetter(R.Names(boss.n)))
  row.letter:SetShown(fid == nil)
  local chips = abilityChips(boss.ab)
  row.hasAbilities = #chips > 0
  row.abLabel:SetShown(row.hasAbilities)
  row.chips:SetShown(row.hasAbilities)
  row.chips:SetChips(chips)
end

-- Quest rows: head line, details and the map buttons of the start position.
local function makeQuestRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.title = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.body = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.actions = W.MapActionButtons(row)
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

function IV.QuestList(parent)
  local list = K.RowPool(parent, makeQuestRow)
  function list:SetInstance(inst, faction)
    local items, byId = {}, {}
    for _, q in ipairs(inst and inst.q or {}) do
      byId[q.id or 0] = q
    end
    for _, q in ipairs(inst and R.Quests(inst, faction) or {}) do
      items[#items + 1] = { quest = q, lines = IV.QuestLines(q, byId) }
    end
    self.count = #items
    self:Sync(items, paintQuestRow)
  end
  return list
end
