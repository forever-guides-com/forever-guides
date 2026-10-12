-- Character overview, data side: the row registry and the cell values, no frames.
-- A row is { id, label (locale key), default (on or off at the start), value(char, ctx) ->
-- cell, tip(char, ctx) -> title, text }. A cell is a table the page paints:
--   text, plain (shorter form when text is too wide), hex (class color "#rrggbb"),
--   color (theme token), suffix (muted text behind text), icon (texture path),
--   check (draw a check mark), tone (theme token of the check), status (for tests, tooltips),
--   strike (draw a thin line over text), note (show the note marker).
-- A raid row is one line per raid, its cell shows the boss kills of the week as "x/n"
-- (RaidWeek).
-- The professions row (on by default) shows up to two primary professions, one per line, secondary ones
-- with the switch "professions.secondary" (ProfessionLogic); its cell tells how many lines it needs (`lines`).
-- The access block (off by default, only with Data.Access) is one line per instance with a check
-- mark or "n/m" (AccessView).
-- Rows with their own switch: every registered row except the names (the header line is
-- always there), one per raid ("raid:<slug>"), the access block ("access"), the todo block
-- ("todos") and each todo ("todo:<id>"). Row switches and the sort mode live in CharRoster, a todo's switch is its
-- `enabled` flag in RosterTodos.
local _, ns = ...
local L = ns.L

ns.AddLocale("enUS", {
  ["chars.row.name"] = "Character",
  ["chars.row.level"] = "Level",
  ["chars.row.class"] = "Class",
  ["chars.row.faction"] = "Faction",
  ["chars.row.guild"] = "Guild",
  ["chars.row.ilvl"] = "Item level",
  ["chars.row.gold"] = "Gold",
  ["chars.row.zone"] = "Zone",
  ["chars.row.seen"] = "Last seen",
  ["chars.row.raids"] = "Raids",
  ["chars.row.todos"] = "Todos",
  ["chars.row.alltodos"] = "All todos",
  ["chars.row.todos.strike"] = "Strike through done",
  ["chars.todo.addRow"] = "+ Add own todo",
  ["chars.tip.note"] = "Note: %s",
  ["chars.tip.noteHint"] = "Right-click: note",
  ["chars.row.professions"] = "Professions",
  ["chars.row.professions.secondary"] = "Secondary professions",
  ["chars.row.pvp"] = "PvP",
  ["chars.row.rep"] = "Reputation",
  ["chars.row.playtime"] = "Played time",
  ["chars.row.stats"] = "Statistics",
  ["chars.row.fresh"] = "Data status",
  ["chars.fresh.fresh"] = "Current",
  ["chars.fresh.aging"] = "Older",
  ["chars.fresh.stale"] = "Outdated",
  ["chars.fresh.never"] = "never",
  ["chars.fresh.inventory"] = "Inventory",
  ["chars.fresh.raids"] = "Raid locks",
  ["chars.fresh.hint"] = "Log in, open bank and professions",
  ["chars.tip.goldAll"] = "All characters: %s",
  ["chars.tip.prof.age"] = "Updated: %s",
  ["chars.you"] = "(you)",
  ["chars.faction.A"] = "Alliance",
  ["chars.faction.H"] = "Horde",
  ["chars.seen.today"] = "today",
  ["chars.seen.yesterday"] = "yesterday",
  ["chars.seen.days"] = "%d d ago",
  ["chars.seen.weeks"] = "%d w ago",
  ["chars.seen.months"] = "%d mo ago",
  ["chars.date"] = "%Y-%m-%d %H:%M",
  ["chars.dur.days"] = "%d d %d h",
  ["chars.dur.hours"] = "%d h %d min",
  ["chars.tip.level"] = "%s, level %s",
  ["chars.tip.zone"] = "Zone: %s",
  ["chars.tip.gold"] = "Gold: %s",
  ["chars.tip.seen"] = "Last seen: %s",
  ["chars.tip.raid"] = "Raid: %s",
  ["chars.tip.expires"] = "Lock ends in %s",
  ["chars.tip.week"] = "Killed this week (%d/%d)",
  ["chars.tip.open"] = "Open:",
  ["chars.tip.optional"] = "(optional)",
  ["chars.tip.reset"] = "Reset in %s",
  ["chars.tip.lastDone"] = "Last ticked: %s",
  ["chars.tip.never"] = "Never ticked",
  ["chars.tip.click"] = "Click to tick",
  ["chars.tip.reset.never"] = "Reset: never",
  ["chars.tip.reset.daily"] = "Reset: daily",
  ["chars.tip.reset.weekly"] = "Reset: weekly",
  ["chars.status.killed"] = "Killed",
  ["chars.status.open"] = "Open",
  ["chars.status.unknown"] = "Unknown",
  ["chars.status.done"] = "Done",
  ["chars.status.progress"] = "%d of %d killed",
})

ns.AddLocale("deDE", {
  ["chars.row.name"] = "Charakter",
  ["chars.row.level"] = "Stufe",
  ["chars.row.class"] = "Klasse",
  ["chars.row.faction"] = "Fraktion",
  ["chars.row.guild"] = "Gilde",
  ["chars.row.ilvl"] = "Gegenstandsstufe",
  ["chars.row.gold"] = "Gold",
  ["chars.row.zone"] = "Zone",
  ["chars.row.seen"] = "Zuletzt gesehen",
  ["chars.row.raids"] = "Raids",
  ["chars.row.todos"] = "Todos",
  ["chars.row.alltodos"] = "Alle Todos",
  ["chars.row.todos.strike"] = "Erledigte durchstreichen",
  ["chars.todo.addRow"] = "+ Punkt hinzufügen",
  ["chars.tip.note"] = "Notiz: %s",
  ["chars.tip.noteHint"] = "Rechtsklick: Notiz",
  ["chars.row.professions"] = "Berufe",
  ["chars.row.professions.secondary"] = "Nebenberufe zeigen",
  ["chars.row.pvp"] = "PvP",
  ["chars.row.rep"] = "Ruf",
  ["chars.row.playtime"] = "Spielzeit",
  ["chars.row.stats"] = "Statistiken",
  ["chars.row.fresh"] = "Datenstand",
  ["chars.fresh.fresh"] = "Aktuell",
  ["chars.fresh.aging"] = "Älter",
  ["chars.fresh.stale"] = "Veraltet",
  ["chars.fresh.never"] = "nie",
  ["chars.fresh.inventory"] = "Bestand",
  ["chars.fresh.raids"] = "Raid-Sperren",
  ["chars.fresh.hint"] = "Einloggen, Bank und Berufe öffnen",
  ["chars.tip.goldAll"] = "Alle Charaktere: %s",
  ["chars.tip.prof.age"] = "Stand: %s",
  ["chars.you"] = "(du)",
  ["chars.faction.A"] = "Allianz",
  ["chars.faction.H"] = "Horde",
  ["chars.seen.today"] = "heute",
  ["chars.seen.yesterday"] = "gestern",
  ["chars.seen.days"] = "vor %d T",
  ["chars.seen.weeks"] = "vor %d Wo",
  ["chars.seen.months"] = "vor %d Mon",
  ["chars.date"] = "%d.%m.%Y %H:%M",
  ["chars.dur.days"] = "%d T %d Std",
  ["chars.dur.hours"] = "%d Std %d Min",
  ["chars.tip.level"] = "%s, Stufe %s",
  ["chars.tip.zone"] = "Zone: %s",
  ["chars.tip.gold"] = "Gold: %s",
  ["chars.tip.seen"] = "Zuletzt: %s",
  ["chars.tip.raid"] = "Raid: %s",
  ["chars.tip.expires"] = "Sperre endet in %s",
  ["chars.tip.week"] = "Diese Woche getötet (%d/%d)",
  ["chars.tip.open"] = "Offen:",
  ["chars.tip.optional"] = "(optional)",
  ["chars.tip.reset"] = "Reset in %s",
  ["chars.tip.lastDone"] = "Zuletzt abgehakt: %s",
  ["chars.tip.never"] = "Noch nie abgehakt",
  ["chars.tip.click"] = "Klick zum Abhaken",
  ["chars.tip.reset.never"] = "Reset: nie",
  ["chars.tip.reset.daily"] = "Reset: täglich",
  ["chars.tip.reset.weekly"] = "Reset: wöchentlich",
  ["chars.status.killed"] = "Getötet",
  ["chars.status.open"] = "Offen",
  ["chars.status.unknown"] = "Unbekannt",
  ["chars.status.done"] = "Erledigt",
  ["chars.status.progress"] = "%d von %d getötet",
})

local V = {}
ns.RosterView = V

V.RAID_MAX = 20
V.BOSS_MAX = 24

-- Text helpers ------------------------------------------------------------------------

local STOP = { of = true, the = true, der = true, die = true, das = true, des = true, von = true, vom = true }

-- Cuts to `max` characters (not bytes) and marks the cut.
function V.Cut(text, max)
  if type(text) ~= "string" or text == "" then
    return "?"
  end
  local list = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    list[#list + 1] = ch
  end
  if #list <= max then
    return text
  end
  return (table.concat(list, "", 1, max - 2):gsub(" +$", "")) .. ".."
end

-- Short form of an instance name: small words dropped, then cut.
function V.ShortName(name, max)
  if type(name) ~= "string" then
    return "?"
  end
  local words = {}
  for w in name:gmatch("[^ ]+") do
    words[#words + 1] = w
  end
  if #words > 2 then
    local kept = {}
    for _, w in ipairs(words) do
      if not STOP[w:lower()] then
        kept[#kept + 1] = w
      end
    end
    name = table.concat(kept, " ")
  end
  return V.Cut(name, max or V.RAID_MAX)
end

function V.Duration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  if days > 0 then
    return string.format(L["chars.dur.days"], days, hours)
  end
  return string.format(L["chars.dur.hours"], hours, math.floor(seconds % 3600 / 60))
end

local function dateText(seconds)
  if type(seconds) ~= "number" or seconds <= 0 then
    return nil
  end
  local ok, text = pcall(date, L["chars.date"], seconds)
  return ok and text or nil
end

local function agoText(days)
  if not days or days == 0 then
    return L["chars.seen.today"]
  elseif days == 1 then
    return L["chars.seen.yesterday"]
  elseif days < 14 then
    return string.format(L["chars.seen.days"], days)
  elseif days < 60 then
    return string.format(L["chars.seen.weeks"], math.floor(days / 7))
  end
  return string.format(L["chars.seen.months"], math.floor(days / 30))
end

local function seenText(char)
  return agoText(not char.current and ns.CharRoster.DaysSince(char.seen) or nil)
end

local function classHex(char)
  return char.class and ns.PageKit.ClassColorHex(char.class) or nil
end

local function className(char)
  return char.class and ns.RefLogic.className(char.class) or nil
end

-- A cell as one string with color escapes (name in class color, marker muted).
function V.Format(cell)
  local text = cell.text or ""
  if cell.hex and text ~= "" then
    text = "|cff" .. cell.hex:sub(2) .. text .. "|r"
  end
  if cell.suffix then
    text = text .. " " .. ns.Theme.hexText("textMuted", cell.suffix)
  end
  return text
end

-- Registry ------------------------------------------------------------------------------

V.defs = {}

-- Adds a row, or replaces the one with the same id.
function V.Register(def)
  for i, d in ipairs(V.defs) do
    if d.id == def.id then
      V.defs[i] = def
      return def
    end
  end
  V.defs[#V.defs + 1] = def
  return def
end

local function coins(char, plain)
  return ns.CostLogic.Format(char.money, plain and { plain = true } or nil) or "0"
end

local function nameTip(char)
  local lines = {}
  local cls = className(char)
  lines[#lines + 1] = string.format(L["chars.tip.level"], cls or "?", tostring(char.level or "?"))
  if char.zone then
    lines[#lines + 1] =
      string.format(L["chars.tip.zone"], char.subzone and (char.zone .. ", " .. char.subzone) or char.zone)
  end
  lines[#lines + 1] = string.format(L["chars.tip.gold"], coins(char, true))
  local when = dateText(char.seen)
  if when then
    lines[#lines + 1] = string.format(L["chars.tip.seen"], when)
  end
  return char.display .. "-" .. char.realm, table.concat(lines, "\n")
end

V.Register({
  id = "name",
  label = "chars.row.name",
  default = true,
  value = function(char)
    return { text = char.display, hex = classHex(char), suffix = char.current and L["chars.you"] or nil }
  end,
  tip = nameTip,
})
V.Register({
  id = "level",
  label = "chars.row.level",
  default = true,
  value = function(char)
    return { text = char.level and tostring(char.level) or "-" }
  end,
})
V.Register({
  id = "class",
  label = "chars.row.class",
  default = true,
  value = function(char)
    return { text = className(char) or "-", hex = classHex(char) }
  end,
})
V.Register({
  id = "faction",
  label = "chars.row.faction",
  default = false,
  value = function(char)
    local f = char.faction
    if not f then
      return { text = "-" }
    end
    return { text = L["chars.faction." .. f], icon = ns.PageKit.FACTION_CREST[f] }
  end,
})
V.Register({
  id = "guild",
  label = "chars.row.guild",
  default = false,
  value = function(char)
    return { text = char.guild or "-" }
  end,
})
V.Register({
  id = "ilvl",
  label = "chars.row.ilvl",
  default = true,
  value = function(char)
    return { text = char.ilvl and string.format("%.0f", char.ilvl) or "-" }
  end,
})
V.Register({
  id = "gold",
  label = "chars.row.gold",
  default = true,
  value = function(char)
    return { text = coins(char), plain = coins(char, true) }
  end,
  tip = function(char)
    local text = coins(char, true)
    local count, total = ns.CharRoster.Totals(ns.CharRoster.List())
    if count > 1 then
      text = text .. "\n" .. string.format(L["chars.tip.goldAll"], ns.CostLogic.Format(total, { plain = true }) or "0")
    end
    return L["chars.row.gold"], text
  end,
})
V.Register({
  id = "zone",
  label = "chars.row.zone",
  default = false,
  value = function(char)
    return { text = char.zone or "-" }
  end,
  tip = function(char)
    return L["chars.row.zone"], char.zone and (char.subzone and (char.zone .. ", " .. char.subzone) or char.zone) or "-"
  end,
})
V.Register({
  id = "seen",
  label = "chars.row.seen",
  default = false,
  value = function(char)
    return { text = seenText(char) }
  end,
  tip = function(char)
    return L["chars.row.seen"], dateText(char.seen) or "-"
  end,
})

-- Professions ---------------------------------------------------------------------------------

V.LINES_MAX = 6

-- One line per profession, full skill in green. `form` is a ProfessionLogic form.
local function professionText(list, form)
  local PL = ns.ProfessionLogic
  local out = {}
  for _, p in ipairs(list) do
    local line = PL.Text(p, form)
    local tone = PL.Tone(p)
    out[#out + 1] = tone and ns.Theme.hexText(tone, line) or line
  end
  return table.concat(out, "\n")
end

local function professionTip(char, ctx)
  local list = ns.ProfessionLogic.Sort(char.professions)
  if #list == 0 then
    return nil
  end
  local lines = { professionText(list, "full") }
  local days = ns.ProfessionLogic.AgeDays(char.professionsAt, ctx and ctx.now or ns.CharRoster.Now())
  if days then
    lines[#lines + 1] = ns.Theme.hexText("textMuted", string.format(L["chars.tip.prof.age"], agoText(days)))
  end
  return L["chars.row.professions"], table.concat(lines, "\n")
end

-- Up to two primary professions, one per line; "-" without a stored reading. The shorter forms
-- are what the page falls back to when the column is too narrow.
V.Register({
  id = "professions",
  label = "chars.row.professions",
  default = true,
  multiline = true,
  value = function(char)
    local list = ns.ProfessionLogic.Shown(char.professions, V.Enabled("professions.secondary", false))
    if #list == 0 then
      return { text = "-" }
    end
    return {
      text = professionText(list, "full"),
      plain = { professionText(list, "short"), professionText(list, "skill") },
      lines = #list,
    }
  end,
  tip = professionTip,
})

-- Statistics rows (PvP, reputation, played time, statistics) -------------------------------------

-- The text forms come from RosterStatsLogic; a character without a reading shows "-" and no tooltip.
for _, kind in ipairs({ "pvp", "rep", "playtime", "stats" }) do
  V.Register({
    id = kind,
    label = "chars.row." .. kind,
    default = kind ~= "stats",
    value = function(char)
      local sum = ns.RosterStatsLogic.Summary(char, kind)
      return sum and { text = sum.text, plain = sum.plain } or { text = "-" }
    end,
    tip = function(char, ctx)
      local lines = ns.RosterStatsLogic.TooltipLines(char, kind, ctx and ctx.now)
      return lines and L["chars.row." .. kind], lines and table.concat(lines, "\n")
    end,
  })
end

-- Data status -------------------------------------------------------------------------------------

V.FRESH_DAYS = 3
V.AGING_DAYS = 14
local DAY = 86400
local FRESH_TONE = { fresh = "success", aging = "warning", stale = "danger" }

-- Server time of the stored inventory of a character, nil without one.
local function inventoryAt(char)
  local inv = type(ns.db) == "table" and type(ns.db.inventory) == "table" and ns.db.inventory[char.key]
  local at = type(inv) == "table" and inv.t
  return type(at) == "number" and at > 0 and at or nil
end

-- A stored, empty profession list: nothing to read, so a missing reading time is no gap.
local function withoutProfessions(char)
  return type(char.professions) == "table" and #char.professions == 0
end

-- The modules the tooltip lists, each with the time of its last reading. skip leaves a line out.
local FRESH_MODULES = {
  {
    label = "chars.row.professions",
    at = function(char)
      return char.professionsAt
    end,
    skip = function(char)
      return not char.professionsAt and withoutProfessions(char)
    end,
  },
  {
    label = "chars.row.playtime",
    at = function(char)
      return char.playedAt
    end,
  },
  {
    label = "chars.row.pvp",
    at = function(char)
      return char.pvp and char.pvp.at
    end,
  },
  {
    label = "chars.row.rep",
    at = function(char)
      return char.rep and char.rep.at
    end,
  },
  { label = "chars.fresh.inventory", at = inventoryAt },
  {
    label = "chars.fresh.raids",
    at = function(char)
      return char.raidsAt
    end,
  },
}

-- "fresh" up to 3 days, "aging" up to 14, else "stale". The oldest of last seen, played time,
-- professions and (when stored) inventory counts, a missing one is "stale". A character without
-- professions needs no profession reading.
function V.Freshness(char, now)
  local professionsAt = char.professionsAt or (withoutProfessions(char) and math.huge) or 0
  local oldest = math.min(char.seen or 0, char.playedAt or 0, professionsAt, inventoryAt(char) or math.huge)
  if oldest <= 0 then
    return "stale"
  end
  local age = now - oldest
  return age <= V.FRESH_DAYS * DAY and "fresh" or age <= V.AGING_DAYS * DAY and "aging" or "stale"
end

local function sinceText(at, now)
  if not at then
    return L["chars.fresh.never"]
  end
  local days = math.max(0, math.floor((now - at) / DAY))
  if days <= 1 then
    return agoText(days)
  end
  return string.format(L["chars.seen.days"], days)
end

-- Colour and word together, so the state does not rest on colour alone.
V.Register({
  id = "fresh",
  label = "chars.row.fresh",
  default = true,
  value = function(char, ctx)
    local state = V.Freshness(char, ctx and ctx.now or ns.CharRoster.Now())
    return { text = L["chars.fresh." .. state], color = FRESH_TONE[state], status = state }
  end,
  tip = function(char, ctx)
    local now = ctx and ctx.now or ns.CharRoster.Now()
    local lines = {}
    for _, m in ipairs(FRESH_MODULES) do
      if not (m.skip and m.skip(char)) then
        lines[#lines + 1] = L[m.label] .. ": " .. sinceText(m.at(char), now)
      end
    end
    if V.Freshness(char, now) ~= "fresh" then
      lines[#lines + 1] = ns.Theme.hexText("textMuted", L["chars.fresh.hint"])
    end
    return L["chars.row.fresh"], table.concat(lines, "\n")
  end,
})

-- Raids -----------------------------------------------------------------------------------

-- Forever raids that have a boss list, by level then name: { key = "raid:<slug>", inst }.
function V.Raids(instances)
  local R = ns.RefLogic
  local out = {}
  for _, inst in ipairs(instances or (ns.Data and ns.Data.Instances) or {}) do
    if inst.t == "raid" and type(inst.bo) == "table" and #inst.bo > 0 and type(inst.n) == "table" then
      out[#out + 1] = { key = "raid:" .. R.InstanceSlug(inst), inst = inst }
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

-- Everything one overview draw needs; `opts.instances` replaces the data for tests.
function V.Context(now, opts)
  now = now or ns.CharRoster.Now()
  opts = opts or {}
  return {
    now = now,
    offset = ns.RosterTodos.ServerOffset(now),
    instances = opts.instances,
    raids = V.Raids(opts.instances),
    access = ns.AccessView.Instances(opts.instances),
    defs = ns.RosterTodos.Defs(),
  }
end

local function raidName(raid)
  return ns.T(raid.inst.n)
end

-- Killed count, boss total and killed list of the current week. The total falls back to the
-- boss list when the raid has no usable key.
local function weekProgress(row, char)
  local killed, total, list = ns.RaidWeek.Progress(char.key, ns.RaidWeekLogic.RaidKey(row.inst))
  return killed, total > 0 and total or #row.inst.bo, list
end

local function raidCell(row, char)
  local killed, total = weekProgress(row, char)
  local state = killed == 0 and "none" or killed >= total and "done" or "partial"
  local color = { none = "textMuted", partial = "accent2", done = "success" }
  return { text = killed .. "/" .. total, color = color[state], status = state }
end

local function bossLabel(name, opt)
  return opt and (name .. " " .. L["chars.tip.optional"]) or name
end

local function raidTip(row, char, ctx)
  local killed, total, list = weekProgress(row, char)
  local lines = { string.format(L["chars.tip.week"], killed, total) }
  local done = {}
  for _, b in ipairs(list) do
    done[b.key] = true
    lines[#lines + 1] = ns.TimeText.Stamp(b.at) .. "  " .. bossLabel(b.name, b.opt)
  end
  local open = {}
  for i, boss in ipairs(row.inst.bo) do
    if not done[ns.RaidWeekLogic.BossKey(boss, i)] then
      open[#open + 1] = ns.Theme.hexText("textMuted", bossLabel(ns.T(boss.n) or "?", boss.opt))
    end
  end
  if #open > 0 then
    lines[#lines + 1] = ns.Theme.hexText("textMuted", L["chars.tip.open"])
    for _, text in ipairs(open) do
      lines[#lines + 1] = text
    end
  end
  local reset = ns.RaidWeek.NextReset()
  if reset then
    lines[#lines + 1] = string.format(L["chars.tip.reset"], V.Duration(reset - ctx.now))
  end
  return raidName(row.raid), table.concat(lines, "\n")
end

-- Todos ------------------------------------------------------------------------------------

local function lastTick(char, id)
  local e = char.todos and char.todos.values and char.todos.values[id]
  return e and e.done and e.at or nil
end

local function todoTip(row, char)
  local def = row.def
  local at = lastTick(char, def.id)
  local lines = {
    at and dateText(at) and string.format(L["chars.tip.lastDone"], dateText(at)) or L["chars.tip.never"],
    L["chars.tip.reset." .. def.reset],
  }
  local note = ns.RosterTodos.Note(char.key, def.id)
  if note then
    -- A pipe in a note must not start a color or link escape.
    lines[#lines + 1] = string.format(L["chars.tip.note"], (note:gsub("|", "||")))
  end
  lines[#lines + 1] = L["chars.tip.click"]
  lines[#lines + 1] = ns.Theme.hexText("textMuted", L["chars.tip.noteHint"])
  return def.name, table.concat(lines, "\n")
end

-- Rows -------------------------------------------------------------------------------------

function V.Enabled(id, default)
  return ns.CharRoster.RowEnabled(id, default)
end

-- The switches of the row panel in display order: { id, label, default, todo (definition
-- id of a todo's own switch) }.
function V.Switches(ctx)
  ctx = ctx or V.Context()
  local out = {}
  for _, def in ipairs(V.defs) do
    if def.id ~= "name" then
      out[#out + 1] = { id = def.id, label = L[def.label], default = def.default }
      if def.id == "professions" then
        out[#out + 1] =
          { id = "professions.secondary", label = L["chars.row.professions.secondary"], default = false, sub = true }
      end
    end
  end
  for _, raid in ipairs(ctx.raids) do
    out[#out + 1] = { id = raid.key, label = V.ShortName(raidName(raid), V.RAID_MAX * 2), default = true }
  end
  if #ctx.access > 0 then
    out[#out + 1] = { id = "access", label = L["chars.row.access"], default = false }
  end
  out[#out + 1] = { id = "todos", label = L["chars.row.alltodos"], default = true }
  if #ctx.defs > 0 then
    out[#out + 1] = { id = "todos.strike", label = L["chars.row.todos.strike"], default = true, sub = true }
  end
  for _, def in ipairs(ctx.defs) do
    out[#out + 1] = { id = "todo:" .. def.id, label = def.name, default = true, todo = def.id }
  end
  return out
end

function V.SwitchOn(s)
  if s.todo then
    local def = ns.RosterTodos.Get(s.todo)
    return def ~= nil and def.enabled
  end
  return V.Enabled(s.id, s.default)
end

function V.SetSwitch(s, on)
  if s.todo then
    ns.RosterTodos.SetEnabled(s.todo, on)
  else
    ns.CharRoster.SetRow(s.id, on)
  end
end

-- The shown rows of one draw. `header` is the name row, it fills the sticky top line and
-- stays even when every other row is off. Kinds: row, section, raid, access, todo, add (the
-- "add own todo" line at the end of the todo block, its label is the button).
function V.Rows(ctx)
  local header
  local rows = {}
  for _, def in ipairs(V.defs) do
    if def.id == "name" then
      header = def
    elseif V.Enabled(def.id, def.default) then
      rows[#rows + 1] = { kind = "row", id = def.id, label = L[def.label], def = def }
    end
  end
  local raids = {}
  for _, raid in ipairs(ctx.raids) do
    if V.Enabled(raid.key, true) then
      raids[#raids + 1] = raid
    end
  end
  if #raids > 0 then
    rows[#rows + 1] = { kind = "section", id = "raids", label = L["chars.row.raids"] }
    for _, raid in ipairs(raids) do
      rows[#rows + 1] = {
        kind = "raid",
        id = raid.key,
        label = V.ShortName(raidName(raid), V.RAID_MAX),
        raid = raid,
        inst = raid.inst,
      }
    end
  end
  if #ctx.access > 0 and V.Enabled("access", false) then
    rows[#rows + 1] = { kind = "section", id = "access", label = L["chars.row.access"] }
    for _, item in ipairs(ctx.access) do
      rows[#rows + 1] = {
        kind = "access",
        id = "access:" .. item.key,
        label = V.ShortName(ns.T(item.inst.n), V.RAID_MAX),
        access = item,
      }
    end
  end
  if V.Enabled("todos", true) then
    rows[#rows + 1] = { kind = "section", id = "todos", label = L["chars.row.todos"] }
    for _, def in ipairs(ctx.defs) do
      if def.enabled then
        rows[#rows + 1] = { kind = "todo", id = "todo:" .. def.id, label = V.Cut(def.name, V.BOSS_MAX), def = def }
      end
    end
    rows[#rows + 1] = { kind = "add", id = "todo:add", label = L["chars.todo.addRow"] }
  end
  return { header = header, rows = rows }
end

-- Text lines a row needs: the most any of the characters has (1 for rows of one line).
function V.Lines(row, chars, ctx)
  local n = 1
  if row.kind == "row" and row.def.multiline then
    for _, char in ipairs(chars) do
      n = math.max(n, row.def.value(char, ctx).lines or 1)
    end
  end
  return math.min(n, V.LINES_MAX)
end

-- The cell of a row and a character, the header uses the name row.
function V.Cell(row, char, ctx)
  local kind = row.kind
  if kind == "row" then
    return row.def.value(char, ctx)
  elseif kind == "raid" then
    return raidCell(row, char)
  elseif kind == "access" then
    return ns.AccessView.CharCell(row.access, char, ctx)
  elseif kind == "todo" then
    local done = ns.RosterTodos.IsDone(char.key, row.def.id, ctx.now, ctx.offset)
    local cell = {
      check = done,
      tone = "success",
      status = done and "done" or "open",
      note = ns.RosterTodos.Note(char.key, row.def.id) ~= nil,
    }
    if done and V.Enabled("todos.strike", true) then
      -- The point's own text, struck through, in the cell of every character that ticked it.
      local name = row.def.name
      cell.strike, cell.color = true, "textSecondary"
      cell.text, cell.plain = V.Cut(name, 16), { V.Cut(name, 11), V.Cut(name, 7) }
    end
    return cell
  end
  return {}
end

-- Title and text of a cell tooltip, nil without one.
function V.Tip(row, char, ctx)
  local kind = row.kind
  if kind == "raid" then
    return raidTip(row, char, ctx)
  elseif kind == "access" then
    return ns.AccessView.CharTip(row.access, char, ctx)
  elseif kind == "todo" then
    return todoTip(row, char)
  elseif kind == "row" then
    if row.def.tip then
      return row.def.tip(char, ctx)
    end
    local cell = row.def.value(char, ctx)
    if cell.text and cell.text ~= "" and cell.text ~= "-" then
      return row.label, cell.text
    end
  end
  return nil
end

function V.Interactive(row)
  return row.kind == "todo"
end

-- Click on a cell: ticks or unticks a todo. Returns true when something changed.
function V.Activate(row, char)
  if row.kind == "todo" then
    return ns.RosterTodos.Toggle(char.key, row.def.id)
  end
  return false
end
