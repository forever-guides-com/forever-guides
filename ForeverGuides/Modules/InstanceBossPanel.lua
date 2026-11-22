-- Bosses tab of the instances page as list and detail, like the loot (Modules/InstanceBossView.lua). Left: the
-- regular bosses in the order of the data (picture, number, name, level and kill state), below them under a small
-- heading the rare enemies (boss.rare) that show up only now and then. Rares that share one spawn spot (same
-- boss.rg) are one entry "One of: A, B, C"; without rg every rare is its own entry. Right: the chosen entry, per
-- boss the portrait that opens the 3D model, the name as a heading, number or the word rare, level, tags and state,
-- then its abilities or the note that none are recorded yet. Under the panel width of the loot view the detail
-- sits under the list. Up and down move the focus through the list (the page does that), a focused entry is the
-- chosen one, Enter moves the focus into the detail. A boss in the detail is the heading form of the boss row of
-- Modules/InstanceView.lua.
local _, ns = ...
local W, L, Theme, IV, BV = ns.W, ns.L, ns.Theme, ns.InstanceView, ns.InstanceBossView

ns.AddLocale("enUS", {
  ["instances.bosses.selectTip"] = "Shows the abilities of this boss.",
  ["instances.bosses.rareHeading"] = "Rare enemies (show up only now and then)",
  ["instances.bosses.oneOf"] = "One of: %s",
  ["instances.bosses.rareNote"] = "Rare enemy: shows up only now and then.",
  ["instances.bosses.rareGroupNote"] = "These rare enemies share one spot. Only one of them shows up at a time.",
})

ns.AddLocale("deDE", {
  ["instances.bosses.selectTip"] = "Zeigt die Fähigkeiten dieses Bosses.",
  ["instances.bosses.rareHeading"] = "Seltene Gegner (erscheinen nur manchmal)",
  ["instances.bosses.oneOf"] = "Einer von: %s",
  ["instances.bosses.rareNote"] = "Seltener Gegner: erscheint nur manchmal.",
  ["instances.bosses.rareGroupNote"] = "Diese seltenen Gegner teilen sich einen Platz. Es erscheint immer nur einer davon.",
})

local BP = {}
ns.InstanceBossPanel = BP

local PAD = 8

local function register(frame, activate)
  ns.Focus.register(frame, activate)
end

-- Entries of the list: { key, rare, members = { { boss, index (place in inst.bo) } }, position (regular only) }.
-- Regular bosses first, then the rares in the order of their first member. Returns the entries, the number of
-- regular bosses and the position of the first rare entry (nil without rares).
function BP.Entries(inst)
  local regular, rares, groups = {}, {}, {}
  for i, boss in ipairs(inst and inst.bo or {}) do
    local member = { boss = boss, index = i }
    if boss.rare ~= true then
      regular[#regular + 1] = { key = "b" .. i, members = { member }, position = #regular + 1 }
    elseif boss.rg ~= nil and groups[boss.rg] then
      local members = groups[boss.rg].members
      members[#members + 1] = member
    else
      local entry =
        { key = boss.rg ~= nil and ("g" .. tostring(boss.rg)) or ("b" .. i), rare = true, members = { member } }
      if boss.rg ~= nil then
        groups[boss.rg] = entry
      end
      rares[#rares + 1] = entry
    end
  end
  local count = #regular
  local out = regular
  for _, entry in ipairs(rares) do
    out[#out + 1] = entry
  end
  return out, count, #rares > 0 and count + 1 or nil
end

local function nameOf(member)
  return (ns.RefLogic.Names(member.boss.n)) or "?"
end

-- Title of a list entry and its plain form: "1. Name" for a regular boss, "Name  rare" or "One of: A, B" for rares,
-- with the words optional and heroic.
local function titleOf(entry)
  local members = entry.members
  if #members > 1 then
    local names = {}
    for i, member in ipairs(members) do
      names[i] = nameOf(member)
    end
    local text = string.format(L["instances.bosses.oneOf"], table.concat(names, ", "))
    local rare = L["instances.bosses.rare"]
    return text .. "  " .. Theme.hexText("textMuted", rare), text .. ", " .. rare
  end
  local boss = members[1].boss
  local name = IV.Dual(boss.n) or "?"
  local text = entry.rare and name or string.format("%d. %s", entry.position, name)
  local plain = entry.rare and nameOf(members[1]) or string.format("%d. %s", entry.position, nameOf(members[1]))
  local tags = {}
  if entry.rare then
    tags[#tags + 1] = { "textMuted", L["instances.bosses.rare"] }
  elseif boss.opt then
    tags[#tags + 1] = { "textMuted", L["instances.bosses.optional"] }
  end
  if boss.hc then
    tags[#tags + 1] = { "warning", L["instances.bosses.heroic"] }
  end
  for _, tag in ipairs(tags) do
    text = text .. "  " .. Theme.hexText(tag[1], tag[2])
    plain = plain .. ", " .. tag[2]
  end
  return text, plain
end

-- Second line of a list entry: level and kill state, nil when the data knows neither. A group shows the state only.
local function subOf(inst, entry)
  local bits = {}
  if #entry.members == 1 then
    bits[#bits + 1] = IV.BossLevel(entry.members[1].boss)
  end
  for _, member in ipairs(entry.members) do
    local progress = IV.ProgressText(inst, member.index)
    if progress then
      bits[#bits + 1] = progress
      break
    end
  end
  return #bits > 0 and table.concat(bits, " · ") or nil
end

local function makeDetail(view)
  local d = CreateFrame("Frame", nil, view)
  W.Fill(d, "surface", 1)
  d.note = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.rows = BV.Pool()

  function d:NewRow()
    local row = IV.BossRow(self, { heading = true })
    -- Only rows after the first keep the divider: it parts the bosses of a group.
    row.line:SetShown(false)
    return row
  end

  function d:fgLayout(width)
    local inner = math.max(40, width - 2 * PAD)
    local y = 0
    if self.note:IsShown() then
      self.note:ClearAllPoints()
      self.note:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
      self.note:SetWidth(inner)
      y = PAD + math.ceil(self.note:GetStringHeight())
    end
    for i = 1, self.rows.used do
      local row = self.rows.list[i]
      row.line:SetShown(i < self.rows.used)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -y)
      row:SetWidth(inner)
      local h = row:fgLayout(inner)
      row:SetHeight(h)
      y = y + h
    end
    return y
  end
  return d
end

-- parent: the frame the view sits in. Methods: :SetInstance(inst), :Select(key), :FocusDetail(), :Stops() (own
-- keyboard targets in display order), :fgGridLayout(width) -> height. .count: number of bosses. .onChange(): asks
-- the owner for a layout.
function BP.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.count = 0
  f.list = {}
  f.entries = BV.Pool()
  f.rareHead = W.Text(f, { key = "instances.bosses.rareHeading", role = "micro", color = "textMuted", wrap = true })
  f.rareHead:Hide()
  f.heads = {}
  f.detail = makeDetail(f)
  -- The first row exists from the start, so the detail has its place in the keyboard order of the page.
  BV.Take(f.detail.rows, function()
    return f.detail:NewRow()
  end)
  f.detail.rows.used = 0
  BV.HideRest(f.detail.rows)
  f.detail:Hide()

  local function changed()
    if f.onChange then
      f.onChange()
    end
  end

  local hooks = {
    share = true,
    select = function(e)
      f:Select(e.entryKey)
    end,
    tip = function()
      return L["instances.bosses.selectTip"]
    end,
    open = function()
      BV.OpenDetail(f)
    end,
    activate = function()
      f:FocusDetail()
    end,
  }

  local function find(key)
    for _, entry in ipairs(f.list) do
      if entry.key == key then
        return entry
      end
    end
  end

  local function paintEntry(e, entry)
    e.entryKey = entry.key
    e.share:SetTarget(IV.BossSharePayload(f.inst, entry.members[1].boss))
    e.fgSelected = f.selected == entry.key or nil
    local text, plain = titleOf(entry)
    local sub = subOf(f.inst, entry)
    e.label = sub and (plain .. ", " .. sub) or plain
    e.title:SetText(text)
    e.sub:SetText(sub or "")
    e.sub:SetShown(sub ~= nil)
    IV.PaintBossImage(e.portrait, e.pic, f.inst, entry.members[1].boss)
    BV.PaintSelected(e)
  end

  local function paintDetail()
    local d = f.detail
    local entry = f.selected and find(f.selected)
    d.rows.used = 0
    d:SetShown(entry ~= nil)
    if entry then
      local note = entry.rare
        and L[#entry.members > 1 and "instances.bosses.rareGroupNote" or "instances.bosses.rareNote"]
      d.note:SetText(note or "")
      d.note:SetShown(note ~= nil)
      for _, member in ipairs(entry.members) do
        local row = BV.Take(d.rows, function()
          return d:NewRow()
        end)
        IV.PaintBossRow(row, {
          inst = f.inst,
          boss = member.boss,
          index = member.index,
          position = entry.position,
          total = f.regular,
          rare = entry.rare,
        })
      end
    end
    BV.HideRest(d.rows)
  end

  -- Detail targets per boss: the heading (opens the 3D model when the boss has one) and the ability chips.
  local function detailStops()
    local out = {}
    for _, row in ipairs(f.detail.rows.list) do
      out[#out + 1] = row.modelName
      for _, chip in ipairs(row.chips:Frames()) do
        out[#out + 1] = chip
      end
    end
    return out
  end

  function f:Stops()
    local out = {}
    for _, e in ipairs(self.entries.list) do
      out[#out + 1] = e
    end
    for _, stop in ipairs(detailStops()) do
      out[#out + 1] = stop
    end
    return out
  end

  -- Entries, rows and chips come from pools and register late, at the end of the page: keep all of them in one
  -- block at the place of the first one, in display order.
  function f:OrderFocus()
    local items = ns.Focus.items
    local stops, own = self:Stops(), {}
    for _, stop in ipairs(stops) do
      own[stop] = true
    end
    local at
    for i = #items, 1, -1 do
      if own[items[i]] then
        table.remove(items, i)
        at = i
      end
    end
    at = at or #items + 1
    for offset, stop in ipairs(stops) do
      table.insert(items, math.min(at + offset - 1, #items + 1), stop)
    end
  end

  -- Chooses an entry by its key. The choice stays when the instance is painted again.
  function f:Select(key)
    if not key or self.selected == key or not find(key) then
      return
    end
    self.selected = key
    for i = 1, self.entries.used do
      local e = self.entries.list[i]
      e.fgSelected = e.entryKey == key or nil
      BV.PaintSelected(e)
    end
    paintDetail()
    self:OrderFocus()
    changed()
  end

  -- Encounter ID of the chosen entry (first member of a rare group), nil without one.
  function f:SelectedBossId()
    local entry = self.selected and find(self.selected)
    local boss = entry and entry.members[1].boss
    return boss and boss.eid or nil
  end

  -- Chooses the entry that holds the boss with this encounter ID (a page link). False when none does.
  function f:SelectBossId(id)
    for _, entry in ipairs(self.list) do
      for _, member in ipairs(entry.members) do
        if member.boss.eid == id then
          self:Select(entry.key)
          return true
        end
      end
    end
    return false
  end

  function f:FocusDetail()
    for _, stop in ipairs(detailStops()) do
      if stop:IsVisible() then
        ns.Focus.set(stop)
        return true
      end
    end
    return false
  end

  function f:SetInstance(inst)
    local list, regular, firstRare = BP.Entries(inst)
    local sameInst = self.inst == inst
    if not sameInst then
      self.fgShowDetail = false
    end
    self.inst, self.list, self.regular = inst, list, regular
    self.count = inst and inst.bo and #inst.bo or 0
    if not (sameInst and self.selected and find(self.selected)) then
      self.selected = list[1] and list[1].key or nil
    end
    self.entries.used = 0
    for _, entry in ipairs(list) do
      local e = BV.Take(self.entries, function()
        return BV.NewEntry(f, register, hooks)
      end)
      paintEntry(e, entry)
    end
    BV.HideRest(self.entries)
    self.heads = firstRare and { [firstRare] = self.rareHead } or {}
    self.rareHead:SetShown(firstRare ~= nil)
    paintDetail()
    self:OrderFocus()
  end

  function f:fgGridLayout(width, room)
    self.fgFill = room and room.fill or nil
    return BV.SplitLayout(self, self.entries, self.detail, width, self.heads)
  end

  return f
end
