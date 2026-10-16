-- /fg inventory: why does the item tooltip show no stock of the other characters? Prints to chat
-- which tooltip API carries the block, the setting, what was recorded per character and, for the
-- item under the mouse (or one given as link or id), the count per character. Reads only.
local _, ns = ...
local Logic, Inv, Tip = ns.InventoryLogic, ns.Inventory, ns.InventoryTooltip
local L = ns.L

local D = {}
ns.InventoryDiag = D

ns.AddLocale("enUS", {
  ["inv.diag.title"] = "Inventory check",
  ["inv.diag.hook"] = "Stock block in the tooltip: connected",
  ["inv.diag.hookNone"] = "Stock block in the tooltip: not connected, it cannot show",
  ["inv.diag.hookPath"] = "Detail for support, tooltip connection: %s",
  ["inv.diag.setting"] = "Setting inventory in tooltip: %s",
  ["inv.diag.on"] = "on",
  ["inv.diag.off"] = "off",
  ["inv.diag.chars"] = "Characters recorded: %d",
  ["inv.diag.charsNone"] = "Characters recorded: none yet, log in on each character once",
  ["inv.diag.char"] = "%s%s: last capture %s, %d items%s",
  ["inv.diag.you"] = " (current)",
  ["inv.diag.hidden"] = ", hidden in the overview",
  ["inv.diag.never"] = "never",
  ["inv.diag.account"] = "Account bank: last capture %s, %d items",
  ["inv.diag.guild"] = "Guild bank %s: last capture %s, %d items in %d tabs",
  ["inv.diag.errors"] = "Captured errors from the tooltip or capture: %d, last: %s",
  ["inv.diag.noItem"] = "No item: hover an item in your bags and type /fg inventory again, or use /fg inventory <item link or id>.",
  ["inv.diag.item"] = "Item %d:",
  ["inv.diag.owner"] = "  %s",
  ["inv.diag.nobody"] = "  no recorded character owns it",
  ["inv.diag.shown"] = "The tooltip shows the block for it.",
  ["inv.diag.notShown"] = "The tooltip shows nothing for it (only you own it, or nobody, or the setting is off).",
  ["inv.diag.failed"] = "Inventory check failed: %s",
})
ns.AddLocale("deDE", {
  ["inv.diag.title"] = "Bestand-Prüfung",
  ["inv.diag.hook"] = "Bestand im Tooltip: angebunden",
  ["inv.diag.hookNone"] = "Bestand im Tooltip: nicht angebunden, der Block kann nicht erscheinen",
  ["inv.diag.hookPath"] = "Detail für den Support, Tooltip-Anbindung: %s",
  ["inv.diag.setting"] = "Einstellung Bestand im Tooltip: %s",
  ["inv.diag.on"] = "an",
  ["inv.diag.off"] = "aus",
  ["inv.diag.chars"] = "Erfasste Charaktere: %d",
  ["inv.diag.charsNone"] = "Erfasste Charaktere: noch keine, auf jedem Charakter einmal einloggen",
  ["inv.diag.char"] = "%s%s: letzte Erfassung %s, %d Items%s",
  ["inv.diag.you"] = " (aktuell)",
  ["inv.diag.hidden"] = ", in der Übersicht ausgeblendet",
  ["inv.diag.never"] = "nie",
  ["inv.diag.account"] = "Kontobank: letzte Erfassung %s, %d Items",
  ["inv.diag.guild"] = "Gildenbank %s: letzte Erfassung %s, %d Items in %d Reitern",
  ["inv.diag.errors"] = "Erfasste Fehler aus Tooltip oder Erfassung: %d, zuletzt: %s",
  ["inv.diag.noItem"] = "Kein Item: Mauszeiger in den Taschen auf ein Item halten und /fg inventar erneut tippen, oder /fg inventar <Item-Link oder ID> nutzen.",
  ["inv.diag.item"] = "Item %d:",
  ["inv.diag.owner"] = "  %s",
  ["inv.diag.nobody"] = "  kein erfasster Charakter besitzt es",
  ["inv.diag.shown"] = "Der Tooltip zeigt dafür den Block.",
  ["inv.diag.notShown"] = "Der Tooltip zeigt dafür nichts (nur du besitzt es, niemand, oder die Einstellung ist aus).",
  ["inv.diag.failed"] = "Bestand-Prüfung fehlgeschlagen: %s",
})

local API_NAMES = { "postcall", "script", "methods" }

local function stored()
  return type(ns.db) == "table" and type(ns.db.inventory) == "table" and ns.db.inventory or {}
end

-- Distinct items over all areas of a snapshot.
local function itemCount(snap)
  local n = 0
  for _, area in ipairs(Logic.AREAS) do
    for _ in pairs(type(snap) == "table" and type(snap[area]) == "table" and snap[area] or {}) do
      n = n + 1
    end
  end
  return n
end

local function stamp(t)
  if type(t) ~= "number" or t <= 0 then
    return L["inv.diag.never"]
  end
  local fmt = rawget(_G, "date") or (os and os.date)
  local ok, text = pcall(fmt, "%Y-%m-%d %H:%M", t)
  return ok and text or tostring(t)
end

local function plain(text)
  return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The item under the mouse: the tooltip that is open right now.
local function hoveredItem()
  local tip = rawget(_G, "GameTooltip")
  if type(tip) ~= "table" then
    return nil
  end
  local ok, shown = pcall(function()
    return tip:IsShown()
  end)
  if not (ok and shown) then
    return nil
  end
  local data
  if type(tip.GetTooltipData) == "function" then
    local got, value = pcall(tip.GetTooltipData, tip)
    data = got and value or nil
  end
  return Tip.ItemIdOf(tip, data)
end

-- The report lines (plain text) for `argument` (item link, id or empty for the hovered item).
function D.Lines(argument)
  local out = {}
  local function add(key, ...)
    out[#out + 1] = select("#", ...) > 0 and L[key]:format(...) or L[key]
  end
  add("inv.diag.title")

  local used = {}
  for _, name in ipairs(API_NAMES) do
    if Tip.apis and Tip.apis[name] then
      used[#used + 1] = name
    end
  end
  add(#used > 0 and "inv.diag.hook" or "inv.diag.hookNone")
  add("inv.diag.setting", L[Inv.Enabled() and "inv.diag.on" or "inv.diag.off"])

  local inv, chars = stored(), Tip.Characters()
  local listed = {}
  for _, c in ipairs(chars) do
    if inv[c.key] ~= nil then
      listed[#listed + 1] = c
    end
  end
  if #listed == 0 then
    add("inv.diag.charsNone")
  else
    add("inv.diag.chars", #listed)
  end
  for _, c in ipairs(listed) do
    local snap = inv[c.key]
    add(
      "inv.diag.char",
      c.display,
      c.current and L["inv.diag.you"] or "",
      stamp(type(snap) == "table" and snap.t),
      itemCount(snap),
      c.hidden and L["inv.diag.hidden"] or ""
    )
  end
  local account = inv[Logic.ACCOUNT_KEY]
  if type(account) == "table" and itemCount(account) > 0 then
    add("inv.diag.account", stamp(account.t), itemCount(account))
  end
  local guildKeys = {}
  for key in pairs(inv) do
    if Logic.IsGuildKey(key) then
      guildKeys[#guildKeys + 1] = key
    end
  end
  table.sort(guildKeys)
  for _, key in ipairs(guildKeys) do
    local snap = inv[key]
    if type(snap) == "table" and Logic.GuildEntries(snap) > 0 then
      local tabs = 0
      for _ in pairs(type(snap.tabs) == "table" and snap.tabs or {}) do
        tabs = tabs + 1
      end
      add("inv.diag.guild", tostring(snap.name or key), stamp(snap.t), Logic.GuildEntries(snap), tabs)
    end
  end

  local failed, last = 0, nil
  for _, e in ipairs(ns.Errors.list) do
    if tostring(e.ctx):find("inventory", 1, true) then
      failed, last = failed + (tonumber(e.count) or 1), tostring(e.msg)
    end
  end
  if failed > 0 then
    add("inv.diag.errors", failed, last)
  end

  local id = argument and argument ~= "" and Logic.ItemId(tonumber(argument) or argument) or hoveredItem()
  if not id then
    add("inv.diag.noItem")
    add("inv.diag.hookPath", #used > 0 and table.concat(used, ", ") or "-")
    return out
  end
  add("inv.diag.item", id)
  local owners = 0
  for _, c in ipairs(chars) do
    local parts, sum = Logic.Counts(inv[c.key], id)
    if sum > 0 then
      owners = owners + 1
      local row = { name = c.display, sum = sum, parts = parts, account = false }
      out[#out + 1] = L["inv.diag.owner"]:format(plain(Logic.RowText(row, false)))
    end
  end
  local accountCount = type(account) == "table"
    and type(account[Logic.ACCOUNT_AREA]) == "table"
    and account[Logic.ACCOUNT_AREA][id]
  if type(accountCount) == "number" and accountCount > 0 then
    owners = owners + 1
    out[#out + 1] = L["inv.diag.owner"]:format(
      plain(Logic.RowText({ name = L["inv.part.accountBank"], sum = accountCount, parts = {}, account = true }))
    )
  end
  local guildKey, guildName = Inv.GuildKey()
  local guildCount = guildKey and Logic.GuildCount(inv[guildKey], id) or 0
  if guildCount > 0 then
    owners = owners + 1
    local name = L["inv.part.guildBank"]:format(tostring(guildName))
    out[#out + 1] =
      L["inv.diag.owner"]:format(plain(Logic.RowText({ name = name, sum = guildCount, parts = {}, shared = true })))
  end
  if owners == 0 then
    add("inv.diag.nobody")
  end
  add(Tip.Lines(id) and "inv.diag.shown" or "inv.diag.notShown")
  add("inv.diag.hookPath", #used > 0 and table.concat(used, ", ") or "-")
  return out
end

function D.Slash(argument)
  local ok, lines = pcall(D.Lines, argument)
  if not ok then
    ns.Notify.chat(L["inv.diag.failed"]:format(tostring(lines)))
    return
  end
  for _, line in ipairs(lines) do
    ns.Notify.chat(line)
  end
end
