-- The guild line in item tooltips outside our windows: which members can make the item, one line for the
-- ones online and one for the others (names per guild list, at most three each). Only while receiving the
-- crafts of the guild is on AND the directory knows a crafter of a recipe that makes the item; no hint, no
-- advertising and no question: it reads what is stored and nothing else. The item to recipe link comes from
-- the recipe data that is already loaded, without it the line stays out. Appended by InventoryTooltip.
local _, ns = ...
local L, Consent = ns.L, ns.Consent
local CVL, CD = ns.CraftersViewLogic, ns.CraftDirectory

local CT = {}
ns.CraftersTooltip = CT

ns.AddLocale("enUS", {
  ["cv.tip.online"] = "Guild, online: %s",
  ["cv.tip.offline"] = "Guild, offline: %s",
  ["cv.tip.more"] = "%s +%d",
})
ns.AddLocale("deDE", {
  ["cv.tip.online"] = "Gilde, online: %s",
  ["cv.tip.offline"] = "Gilde, offline: %s",
  ["cv.tip.more"] = "%s +%d",
})

CT.MAX_NAMES = 3
-- Seconds a result is kept (the directory changes slowly; FG_CRAFT_UPDATE drops it earlier).
CT.KEEP = 10

local cache, cacheSize = {}, 0
local MAX_CACHE = 100

local function drop()
  cache, cacheSize = {}, 0
end

local function names(list)
  local out = {}
  for i = 1, math.min(#list, CT.MAX_NAMES) do
    out[i] = list[i].name
  end
  local text = table.concat(out, ", ")
  if #list > CT.MAX_NAMES then
    text = string.format(L["cv.tip.more"], text, #list - CT.MAX_NAMES)
  end
  return text
end

local function build(itemId)
  local spells = CVL.ItemIndex(rawget(ns, "RecipeData"))[itemId]
  if not spells then
    return nil
  end
  local seen, all = {}, {}
  for _, spell in ipairs(spells) do
    for _, entry in ipairs((CD.Crafters(spell))) do
      if not seen[entry.key] then
        seen[entry.key] = true
        all[#all + 1] = entry
      end
    end
  end
  if #all == 0 then
    return nil
  end
  local online, other = {}, {}
  for _, entry in ipairs(CVL.Sort(all)) do
    local into = entry.online == true and online or other
    into[#into + 1] = entry
  end
  local lines = {}
  if #online > 0 then
    lines[#lines + 1] = string.format(L["cv.tip.online"], names(online))
  end
  if #other > 0 then
    lines[#lines + 1] = string.format(L["cv.tip.offline"], names(other))
  end
  return lines
end

-- The text lines for an item id, nil when the line stays out. The table is cached, do not change it.
function CT.Lines(itemId)
  if type(itemId) ~= "number" or not Consent.Allows(CD.FN, "receive", "guild") then
    return nil
  end
  local now = CD.now()
  local hit = cache[itemId]
  if hit and now >= hit.at and now - hit.at < CT.KEEP then
    return hit.lines or nil
  end
  local ok, lines = pcall(build, itemId)
  if not ok then
    ns.Log.warn("crafters tooltip failed: %s", tostring(lines))
    lines = nil
  end
  if cacheSize >= MAX_CACHE then
    drop()
  end
  if not cache[itemId] then
    cacheSize = cacheSize + 1
  end
  cache[itemId] = { at = now, lines = lines or false }
  return lines
end

ns.On("FG_CRAFT_UPDATE", drop)
ns.On("FG_GUILD_UPDATE", drop)
ns.On("FG_CONSENT_CHANGED", drop)
ns.On("FG_CONSENT_WITHDRAWN", drop)
