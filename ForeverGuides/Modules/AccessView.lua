-- Access requirements of instances, the game side and the views: reads the game for the
-- current character (items, quests, reputation, level), the "Access" tab of the instance
-- details and the block of the character overview. Checks and totals: AccessLogic.lua,
-- data: ns.Data.Access. Every game call goes through pcall, a missing API gives "unknown".
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit
local Logic = ns.AccessLogic
local I = ns.ItemInfo

ns.AddLocale("enUS", {
  ["access.none"] = "Access requirements not recorded yet.",
  ["access.sum"] = "Access: %d of %d",
  ["access.sumAll"] = "Access: all met",
  ["access.sumUnknown"] = "%d unknown",
  ["access.filter"] = "Still missing",
  ["access.filterEmpty"] = "Nothing missing.",
  ["access.kind.item"] = "Item",
  ["access.kind.quest"] = "Quest",
  ["access.kind.rep"] = "Reputation",
  ["access.kind.level"] = "Level",
  ["access.kind.note"] = "Note",
  ["access.source"] = "Get it from: %s",
  ["access.optional"] = "optional",
  ["access.unverified"] = "not confirmed",
  ["access.repNeed"] = "from %s",
  ["access.levelName"] = "Level %d",
  ["access.state.yes"] = "Done",
  ["access.state.no"] = "Missing",
  ["access.state.unknown"] = "Not readable",
  ["access.standing.1"] = "Hated",
  ["access.standing.2"] = "Hostile",
  ["access.standing.3"] = "Unfriendly",
  ["access.standing.4"] = "Neutral",
  ["access.standing.5"] = "Friendly",
  ["access.standing.6"] = "Honored",
  ["access.standing.7"] = "Revered",
  ["access.standing.8"] = "Exalted",
  ["chars.row.access"] = "Access",
  ["chars.tip.access.none"] = "Not recorded yet",
  ["chars.tip.access.at"] = "Status of %s",
  ["chars.tip.access.login"] = "Updates when you play it",
})

ns.AddLocale("deDE", {
  ["access.none"] = "Zugangsbedingungen noch nicht erfasst.",
  ["access.sum"] = "Zugang: %d von %d",
  ["access.sumAll"] = "Zugang: alles erfüllt",
  ["access.sumUnknown"] = "%d unbekannt",
  ["access.filter"] = "Mir fehlt noch",
  ["access.filterEmpty"] = "Nichts fehlt.",
  ["access.kind.item"] = "Gegenstand",
  ["access.kind.quest"] = "Quest",
  ["access.kind.rep"] = "Ruf",
  ["access.kind.level"] = "Stufe",
  ["access.kind.note"] = "Hinweis",
  ["access.source"] = "Bekommst du bei: %s",
  ["access.optional"] = "optional",
  ["access.unverified"] = "nicht bestätigt",
  ["access.repNeed"] = "ab %s",
  ["access.levelName"] = "Stufe %d",
  ["access.state.yes"] = "Erfüllt",
  ["access.state.no"] = "Fehlt",
  ["access.state.unknown"] = "Nicht lesbar",
  ["access.standing.1"] = "Hasserfüllt",
  ["access.standing.2"] = "Feindselig",
  ["access.standing.3"] = "Unfreundlich",
  ["access.standing.4"] = "Neutral",
  ["access.standing.5"] = "Freundlich",
  ["access.standing.6"] = "Wohlwollend",
  ["access.standing.7"] = "Respektvoll",
  ["access.standing.8"] = "Ehrfürchtig",
  ["chars.row.access"] = "Zugänge",
  ["chars.tip.access.none"] = "Noch nicht erfasst",
  ["chars.tip.access.at"] = "Stand vom %s",
  ["chars.tip.access.login"] = "Aktualisiert beim Spielen",
})

local V = {}
ns.AccessView = V

local SAVE_DELAY = 2

-- Game reads -----------------------------------------------------------------------------

local function itemCount(id)
  local c = rawget(_G, "C_Item")
  local fn = type(c) == "table" and c.GetItemCount or rawget(_G, "GetItemCount")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, n = pcall(fn, id, true)
  return ok and I.readable(n) and n or nil
end

local function questDone(id)
  local c = rawget(_G, "C_QuestLog")
  local fn = type(c) == "table" and c.IsQuestFlaggedCompleted or rawget(_G, "IsQuestFlaggedCompleted")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, done = pcall(fn, id)
  if ok and type(done) == "boolean" then
    return done
  end
  return nil
end

local function standing(id)
  local c = rawget(_G, "C_Reputation")
  if type(c) == "table" and type(c.GetFactionDataByID) == "function" then
    local ok, data = pcall(c.GetFactionDataByID, id)
    if ok and type(data) == "table" and I.readable(data.reaction) then
      return data.reaction
    end
  end
  local fn = rawget(_G, "GetFactionInfoByID")
  if type(fn) == "function" then
    local ok, _, _, value = pcall(fn, id)
    if ok and I.readable(value) then
      return value
    end
  end
  return nil
end

local function playerLevel()
  local fn = rawget(_G, "UnitLevel")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, level = pcall(fn, "player")
  return ok and I.readable(level) and level or nil
end

-- The check environment of the current character.
function V.Env()
  local key = ns.CharRoster.CurrentKey()
  local inv = type(ns.db) == "table" and type(ns.db.inventory) == "table" and key and ns.db.inventory[key] or nil
  return {
    itemCount = itemCount,
    quest = questDone,
    standing = standing,
    level = playerLevel(),
    inventory = inv,
  }
end

-- Model ----------------------------------------------------------------------------------

local function accessData()
  return type(ns.Data) == "table" and type(ns.Data.Access) == "table" and ns.Data.Access or nil
end

-- The condition list of an instance, nil without data.
function V.List(inst)
  local data = accessData()
  local list = data and data[R.InstanceSlug(inst)]
  return type(list) == "table" and #list > 0 and list or nil
end

-- Instances with access data by level then key: { key, inst, list }. `instances` replaces the
-- instance data for tests.
function V.Instances(instances)
  local out = {}
  for _, inst in ipairs(instances or (ns.Data and ns.Data.Instances) or {}) do
    local list = type(inst.n) == "table" and V.List(inst)
    if list then
      out[#out + 1] = { key = R.InstanceSlug(inst), inst = inst, list = list }
    end
  end
  table.sort(out, function(a, b)
    local la, lb = R.InstanceLevel(a.inst) or 0, R.InstanceLevel(b.inst) or 0
    if la ~= lb then
      return la < lb
    end
    return a.key < b.key
  end)
  return out
end

-- Rows of an instance for a faction ("A"/"H"/nil), nil without data. missingOnly drops the met
-- ones. The second to fourth result are done, total and unknown of the whole list.
function V.Model(inst, faction, missingOnly)
  local list = V.List(inst)
  if not list then
    return nil
  end
  local rows = Logic.Evaluate(Logic.Conditions(list, { faction = faction }), V.Env())
  local done, total, unknown = Logic.Summary(rows)
  if missingOnly then
    rows = Logic.Missing(rows)
  end
  return rows, done, total, unknown
end

local function condName(cond)
  local name = ns.T(cond.name)
  if type(name) ~= "string" or name == "" then
    if cond.kind == "level" and tonumber(cond.need) then
      name = string.format(L["access.levelName"], cond.need)
    else
      name = L["access.kind." .. cond.kind] .. (cond.id and (" #" .. tostring(cond.id)) or "")
    end
  end
  return name
end

local function standingName(cond)
  local key = "access.standing." .. tostring(cond.need)
  return L[key] ~= key and L[key] or nil
end

-- Tab rows -------------------------------------------------------------------------------

local PAD, BOX = 6, 18

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetClipsChildren(true)
  row.box = CreateFrame("Frame", nil, row)
  row.box:SetSize(BOX, BOX)
  W.Fill(row.box, "surface2")
  row.border = W.Border(row.box, "white", 0.4)
  row.check = W.CheckMark(row.box, 14, "success")
  row.check:SetPoint("CENTER")
  row.unknown = W.Text(row.box, { text = "?", role = "ui", color = "textMuted", justify = "CENTER" })
  row.unknown:SetPoint("CENTER")
  row.box:EnableMouse(true)
  row.box:SetScript("OnEnter", function()
    local item = row.item
    if item and item.state then
      W.Tooltip.Show(row.box, { title = condName(item.cond), text = L["access.state." .. item.state] })
    end
  end)
  row.box:SetScript("OnLeave", W.Tooltip.Hide)
  row.name = W.Text(row, { role = "ui", wrap = true })
  row.meta = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
  row.source = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.actions = W.MapActionButtons(row)
  row.map, row.marker = row.actions.map, row.actions.marker
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)

  function row:fgLayout(width)
    local x = PAD + BOX + 8
    local linksW = 0
    self.actions:ClearAllPoints()
    if self.actions:IsShown() then
      self.actions:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -PAD)
      linksW = self.actions:GetWidth() + 8
    end
    self.box:ClearAllPoints()
    self.box:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    local textW = math.max(40, width - x - PAD - linksW)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", x, -PAD)
    self.name:SetWidth(textW)
    local y = PAD + math.ceil(self.name:GetStringHeight()) + 2
    self.meta:ClearAllPoints()
    self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
    self.meta:SetWidth(textW)
    y = y + math.ceil(self.meta:GetStringHeight()) + 2
    if self.source:IsShown() then
      self.source:ClearAllPoints()
      self.source:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      self.source:SetWidth(textW)
      y = y + math.ceil(self.source:GetStringHeight()) + 2
    end
    return math.max(PAD * 2 + BOX, y + PAD - 2)
  end
  return row
end

local function paintRow(row, item)
  local cond, state = item.cond, item.state
  row.item = item
  row.box:SetShown(state ~= nil)
  row.check:SetShown(state == "yes")
  row.unknown:SetShown(state == "unknown")
  row.border.set(state == "yes" and "success" or "white", state == "yes" and 1 or 0.4)

  local name = condName(cond)
  if cond.kind == "rep" and standingName(cond) then
    name = name .. "  " .. Theme.hexText("textMuted", string.format(L["access.repNeed"], standingName(cond)))
  end
  row.name:SetText(name)

  local meta = { L["access.kind." .. cond.kind] }
  if cond.optional then
    meta[#meta + 1] = L["access.optional"]
  end
  local text = table.concat(meta, " · ")
  if cond.verified == false then
    text = text .. " · " .. Theme.hexText("warning", L["access.unverified"])
  end
  row.meta:SetText(text)

  local source = ns.T(cond.source)
  row.source:SetShown(type(source) == "string" and source ~= "")
  if row.source:IsShown() then
    row.source:SetText(string.format(L["access.source"], source))
  end

  local hasPos = cond.mapId ~= nil and cond.x ~= nil and cond.y ~= nil
  row.actions:SetPlace(hasPos and { map = cond.mapId, x = cond.x, y = cond.y, label = condName(cond) } or nil)
end

-- The tab body: summary line, the "still missing" filter and the condition rows. Lays itself
-- out through fgGridLayout, so it works inside a page Stack. onChange() runs after a change
-- of the filter (the page lays out again).
function V.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.state = { inst = nil, faction = nil, missing = false }
  f.summary = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.filter = W.Checkbox(f, {
    key = "access.filter",
    get = function()
      return f.state.missing
    end,
    set = function(on)
      f.state.missing = on
      f:Refresh()
      if f.onChange then
        f.onChange()
      end
    end,
  })
  f.note = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.pool = K.RowPool(f, makeRow)

  function f:SetInstance(inst, faction)
    self.state.inst, self.state.faction = inst, faction
    self:Refresh()
  end

  function f:Refresh()
    local s = self.state
    local rows, done, total, unknown
    if s.inst then
      rows, done, total, unknown = V.Model(s.inst, s.faction, s.missing)
    end
    local has = rows ~= nil
    self.pool:Sync(rows or {}, paintRow)
    self.filter:SetShown(has)
    self.filter.Refresh()
    local sum = ""
    if has and total > 0 then
      sum = done == total and L["access.sumAll"] or string.format(L["access.sum"], done, total)
      if unknown > 0 then
        sum = sum .. " · " .. string.format(L["access.sumUnknown"], unknown)
      end
    end
    self.summary:SetText(sum)
    self.summary:SetShown(sum ~= "")
    local note = ""
    if not has then
      note = L["access.none"]
    elseif #rows == 0 and s.missing then
      note = L["access.filterEmpty"]
    end
    self.note:SetText(note)
    self.note:SetShown(note ~= "")
  end

  function f:fgGridLayout(width)
    local y = 0
    for _, item in ipairs({ self.summary, self.note }) do
      if item:IsShown() then
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        item:SetWidth(width)
        y = y + math.ceil(item:GetStringHeight()) + 6
      end
    end
    if self.filter:IsShown() then
      self.filter:ClearAllPoints()
      self.filter:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.filter:SetWidth(math.min(width, 260))
      y = y + 22 + 6
    end
    self.pool:ClearAllPoints()
    self.pool:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.pool:SetWidth(width)
    y = y + self.pool:fgGridLayout(width)
    self:SetHeight(math.max(1, y))
    return y
  end

  K.Anchor("FG.Instances.Access", f)
  return f
end

-- Character overview -----------------------------------------------------------------------

-- Rows of the current character per overview draw (one check per instance), cached in ctx.
local function liveRows(item, char, ctx)
  local cache = ctx and ctx.accessRows
  if ctx and not cache then
    cache = {}
    ctx.accessRows = cache
  end
  local id = item.key .. "|" .. tostring(char.faction)
  if cache and cache[id] then
    return cache[id]
  end
  local rows = Logic.Evaluate(Logic.Conditions(item.list, { faction = char.faction }), V.Env())
  if cache then
    cache[id] = rows
  end
  return rows
end

-- done, total, unknown, at of one instance and character; nil without a state. The current
-- character is checked live, the others show their last saved state.
local function charState(item, char, ctx)
  if char.current then
    local rows = liveRows(item, char, ctx)
    local done, total, unknown = Logic.Summary(rows)
    return done, total, unknown, nil, rows
  end
  local total = Logic.Total(Logic.Conditions(item.list, { faction = char.faction }))
  local saved = Logic.Saved(char.access, item.key, total)
  if saved then
    return saved.done, saved.total, 0, saved.at
  end
  return nil, total, nil
end

-- The cell of the overview row (see RosterView): a check mark when everything is met, else "n/m".
function V.CharCell(item, char, ctx)
  local done, total, unknown = charState(item, char, ctx)
  if total == 0 then
    return { text = "-", color = "textMuted", status = "none" }
  end
  if done == nil or unknown == total then
    return { text = "?", color = "textMuted", status = "unknown" }
  end
  if done == total then
    return { check = true, tone = "success", status = "done" }
  end
  local partial = done > 0
  return {
    text = done .. "/" .. total,
    color = partial and "accent2" or "textMuted",
    status = partial and "partial" or "none",
  }
end

local MARK = { yes = { "success", "+" }, no = { "textMuted", "-" }, unknown = { "textMuted", "?" } }

-- Title and text of the cell tooltip.
function V.CharTip(item, char, ctx)
  local done, total, unknown, at, rows = charState(item, char, ctx)
  local lines = {}
  if done == nil then
    lines[1] = L["chars.tip.access.none"]
    lines[2] = Theme.hexText("textMuted", L["chars.tip.access.login"])
    return ns.T(item.inst.n), table.concat(lines, "\n")
  end
  lines[1] = done == total and L["access.sumAll"] or string.format(L["access.sum"], done, total)
  if unknown and unknown > 0 then
    lines[1] = lines[1] .. " · " .. string.format(L["access.sumUnknown"], unknown)
  end
  if rows then
    for _, row in ipairs(rows) do
      local mark = row.state and MARK[row.state]
      if mark then
        lines[#lines + 1] = Theme.hexText(mark[1], mark[2]) .. " " .. condName(row.cond)
      end
    end
  elseif at and at > 0 then
    local ok, when = pcall(date, L["chars.date"], at)
    if ok then
      lines[#lines + 1] = Theme.hexText("textMuted", string.format(L["chars.tip.access.at"], when))
    end
  end
  return ns.T(item.inst.n), table.concat(lines, "\n")
end

-- Writes the state of the current character into its roster entry (access). An instance that
-- cannot be read at all keeps its last state. Emits FG_ROSTER_CHANGED when a count changed.
function V.Save()
  local Roster = ns.CharRoster
  if not Roster.Enabled() or type(ns.db) ~= "table" or type(ns.db.roster) ~= "table" then
    return false
  end
  local key = Roster.CurrentKey()
  local entry = key and ns.db.roster[key]
  local items = V.Instances()
  if type(entry) ~= "table" or #items == 0 then
    return false
  end
  local faction = K.PlayerFaction() or (Roster.Clean(entry) or {}).faction
  local old = Logic.CleanSaved(entry.access) or {}
  local env, now = V.Env(), Roster.Now()
  local new, changed = {}, false
  for _, item in ipairs(items) do
    local done, total, unknown = Logic.Summary(Logic.Evaluate(Logic.Conditions(item.list, { faction = faction }), env))
    local prev = old[item.key]
    if total > 0 and total <= Logic.MAX_COUNT and unknown < total then
      new[item.key] = { done = done, total = total, at = now }
      changed = changed or not prev or prev.done ~= done or prev.total ~= total
    else
      new[item.key] = prev
    end
  end
  entry.access = next(new) and new or nil
  if changed then
    ns.Emit("FG_ROSTER_CHANGED")
  end
  return changed
end

-- Without access data no timer is started at all (bag events come often).
local function schedule()
  local data = accessData()
  if data and next(data) then
    ns.Debounce("access-save", SAVE_DELAY, V.Save)
  end
end

for _, event in ipairs({
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "QUEST_TURNED_IN",
  "BAG_UPDATE_DELAYED",
  "UPDATE_FACTION",
  "FG_ROSTER_CHANGED",
}) do
  ns.On(event, schedule)
end
