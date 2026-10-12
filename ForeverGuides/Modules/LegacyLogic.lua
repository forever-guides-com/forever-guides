-- Legacy editor rules (pure, no frames, no game access): build state, rule checks as warnings, the
-- website exchange format (v2 read/write, v1 read) and the mapping to client node ranks.
-- Data: ns.Data.LegacyTrees (perks, edges), ns.Data.LegacyGrid (client positions). Mirrors the calculator of
-- forever-guides.com/<de|en>/wow-forever/legacy.
-- build = { ranks = { [perkKey] = rank } }, only ranks above 0 are stored.
-- Every rule is a warning, never a block: the client rules are only partly verified (see LL.DEFAULT_RULES).
local _, ns = ...

local LL = {}
ns.LegacyLogic = LL

-- budgetMode "pool": one limit over all trees (one shared currency, 4225, confirmed in the client:
-- 3 free, 13 spent, 16 in total over all trees). "perTree": the limit applies to each tree (what the website
-- calculates).
-- edgeStrict true: the source of an edge needs its maximum rank (the client does not let the target be bought
-- earlier); false: rank 1 is enough.
-- columnGates: points to spend in the same tree before a grid column opens, by column (x = 2400, 3150, 3900).
-- Observed in the client: only the first column open at 0 and 3 points and all three open at 10 points; the exact
-- steps 5 and 10 are the rule taken over from the website and the client is yet to confirm them. false uses
-- the gate of each perk as the website lists it (Data/LegacyTrees.lua).
LL.DEFAULT_RULES = { budgetMode = "pool", limit = 16, edgeStrict = true, columnGates = { 0, 5, 10 } }

local SITE = "https://forever-guides.com/%s/wow-forever/legacy"
local SET = "forever-legacy"

-- v1 digits follow the perk slots of the website source: nine per category, including the two "coming soon"
-- slots (digit 0). A segment with only the seven real perks is read as well.
local SLOTS = {
  professions = { prefix = "professions", soon = { 7, 8 } },
  adventure = { prefix = "adventure", soon = { 4, 5 } },
  progression = { prefix = "resourcefulness", soon = { 4, 5 } },
}

local TEXT_KEYS = {
  overmax = "legacy.warn.overmax",
  gate = "legacy.warn.gate",
  edge = "legacy.warn.edge",
  budget = "legacy.warn.budget.pool",
  placeholder = "legacy.warn.placeholder",
  unknown = "legacy.warn.unknown",
}

ns.AddLocale("enUS", {
  ["legacy.tree.professions"] = "Professions",
  ["legacy.tree.adventure"] = "Adventure",
  ["legacy.tree.progression"] = "Resourcefulness",
  ["legacy.summary"] = "%s, total %d of %d",
  ["legacy.warn.overmax"] = "%s: rank %d is above the maximum of %d.",
  ["legacy.warn.gate"] = "%s needs %d points spent in %s first (you have %d).",
  ["legacy.warn.edge"] = "%s needs %s first.",
  ["legacy.warn.edge.full"] = "%s needs %s at full rank first.",
  ["legacy.warn.budget.pool"] = "%d points spent, %d are allowed in total.",
  ["legacy.warn.budget.tree"] = "%s: %d points spent, %d are allowed per tree.",
  ["legacy.warn.placeholder"] = "%s is a placeholder and cannot be part of a build.",
  ["legacy.warn.unknown"] = "%s is not a known perk.",
  ["legacy.err.empty"] = "The text is empty.",
  ["legacy.err.nocode"] = "The link contains no Legacy code.",
  ["legacy.err.format"] = "The code is neither version 1 nor version 2.",
  ["legacy.err.version"] = "This code version is not supported.",
  ["legacy.err.pair"] = "An entry in the code is malformed.",
  ["legacy.err.rank"] = "A rank in the code is not a whole number from 0.",
  ["legacy.err.segments"] = "The old code needs three sections.",
  ["legacy.err.length"] = "A section of the old code has the wrong length.",
})

ns.AddLocale("deDE", {
  ["legacy.tree.professions"] = "Berufe",
  ["legacy.tree.adventure"] = "Abenteuer",
  ["legacy.tree.progression"] = "Findigkeit",
  ["legacy.summary"] = "%s, zusammen %d von %d",
  ["legacy.warn.overmax"] = "%s: Rang %d liegt über dem Maximum von %d.",
  ["legacy.warn.gate"] = "%s braucht zuerst %d ausgegebene Punkte in %s (du hast %d).",
  ["legacy.warn.edge"] = "%s braucht zuerst %s.",
  ["legacy.warn.edge.full"] = "%s braucht zuerst %s auf vollem Rang.",
  ["legacy.warn.budget.pool"] = "Du hast %d Punkte ausgegeben, erlaubt sind %d zusammen.",
  ["legacy.warn.budget.tree"] = "%s: %d Punkte ausgegeben, erlaubt sind %d je Baum.",
  ["legacy.warn.placeholder"] = "%s ist ein Platzhalter und gehört in keinen Build.",
  ["legacy.warn.unknown"] = "%s ist kein bekannter Perk.",
  ["legacy.err.empty"] = "Der Text ist leer.",
  ["legacy.err.nocode"] = "Der Link enthält keinen Legacy-Code.",
  ["legacy.err.format"] = "Der Code ist weder Version 1 noch Version 2.",
  ["legacy.err.version"] = "Diese Code-Version wird nicht unterstützt.",
  ["legacy.err.pair"] = "Ein Eintrag im Code ist fehlerhaft.",
  ["legacy.err.rank"] = "Ein Rang im Code ist keine ganze Zahl ab 0.",
  ["legacy.err.segments"] = "Der alte Code braucht drei Bereiche.",
  ["legacy.err.length"] = "Ein Bereich des alten Codes hat die falsche Länge.",
})

-- Data index ------------------------------------------------------------------

local index

-- { trees, perk = { [key] = perk }, treeOf = { [key] = tree }, treeById, keyOfNode, soon = { [key] = true } }
local function data()
  if index then
    return index
  end
  local D = ns.Data.LegacyTrees
  index = { trees = D.trees, perk = {}, treeOf = {}, treeById = {}, keyOfNode = {}, soon = {}, order = {} }
  for _, tree in ipairs(D.trees) do
    index.treeById[tree.tree] = tree
    for _, perk in ipairs(tree.nodes) do
      index.perk[perk.key] = perk
      index.treeOf[perk.key] = tree
      index.keyOfNode[perk.node] = perk.key
      index.order[#index.order + 1] = perk.key
    end
    local layout = SLOTS[tree.cat]
    for n = 1, #layout.soon do
      index.soon[layout.prefix .. "-soon-" .. n] = true
    end
  end
  return index
end

local function lang(locale)
  if locale == nil then
    locale = ns.GetActiveLocale and ns.GetActiveLocale() or "enUS"
  end
  return (locale == "deDE" or locale == "de") and "de" or "en"
end

-- Text of a locale key in "enUS"/"deDE" (or "en"/"de"), default the active locale; falls back to enUS.
function LL.text(textKey, locale)
  local code = lang(locale) == "de" and "deDE" or "enUS"
  local t = ns.Locales[code]
  local v = t and t[textKey] or ns.Locales.enUS[textKey]
  return v or textKey
end

local function rankOf(build, key)
  local r = tonumber(build.ranks[key])
  if not r or r ~= r or r < 1 then
    return 0
  end
  return math.floor(r)
end

local function mergeRules(rules)
  local out = {}
  for k, v in pairs(LL.DEFAULT_RULES) do
    out[k] = v
  end
  if type(rules) == "table" then
    for k in pairs(LL.DEFAULT_RULES) do
      if rules[k] ~= nil then
        out[k] = rules[k]
      end
    end
  end
  if out.budgetMode ~= "perTree" then
    out.budgetMode = "pool"
  end
  if type(out.columnGates) ~= "table" then
    out.columnGates = false
  end
  return out
end

-- The rules as validate sees them: the defaults with the given overrides applied.
function LL.rules(rules)
  return mergeRules(rules)
end

-- Points a perk needs in its tree before it opens: the gate of its grid column, or the gate the website lists
-- for the perk when the rules carry no column gates.
local function gateOf(perk, rules)
  local gates = rules.columnGates
  return gates and tonumber(gates[perk.col]) or perk.gate
end

-- rules: optional, like in validate.
function LL.gateOf(perk, rules)
  if type(perk) == "string" then
    perk = data().perk[perk]
  end
  return perk and gateOf(perk, mergeRules(rules)) or 0
end

-- Build state -------------------------------------------------------------------

function LL.new()
  return { ranks = {} }
end

function LL.copy(build)
  local out = LL.new()
  for key, rank in pairs(build.ranks) do
    out.ranks[key] = rank
  end
  return out
end

-- Clamps to 0..max. Returns the stored rank, or nil and "unknown" for keys that are no real perk
-- (placeholders included), so no placeholder ever enters a build through this door.
function LL.setRank(build, key, rank)
  local perk = data().perk[key]
  if not perk then
    return nil, "unknown"
  end
  rank = tonumber(rank)
  rank = (rank and rank == rank) and math.floor(rank) or 0
  rank = math.min(perk.ranks, math.max(0, rank))
  build.ranks[key] = rank > 0 and rank or nil
  return rank
end

-- { total, byTree = { [treeId] = n }, byCat = { [cat] = n } }; unknown keys are not counted.
function LL.spent(build)
  local d = data()
  local out = { total = 0, byTree = {}, byCat = {} }
  for _, tree in ipairs(d.trees) do
    out.byTree[tree.tree], out.byCat[tree.cat] = 0, 0
  end
  for key in pairs(d.perk) do
    local r = rankOf(build, key)
    if r > 0 then
      local tree = d.treeOf[key]
      out.total = out.total + r
      out.byTree[tree.tree] = out.byTree[tree.tree] + r
      out.byCat[tree.cat] = out.byCat[tree.cat] + r
    end
  end
  return out
end

-- Points still free. pool: total and every byTree entry hold the shared remainder; perTree: byTree holds
-- the remainder of each tree and total their sum (negative values mean over budget).
function LL.unspentLimit(build, rules)
  rules = mergeRules(rules)
  local spent = LL.spent(build)
  local out = { byTree = {} }
  if rules.budgetMode == "pool" then
    out.total = rules.limit - spent.total
    for id in pairs(spent.byTree) do
      out.byTree[id] = out.total
    end
  else
    out.total = 0
    for id, n in pairs(spent.byTree) do
      out.byTree[id] = rules.limit - n
      out.total = out.total + out.byTree[id]
    end
  end
  return out
end

-- Rules ---------------------------------------------------------------------------

local function warn(list, code, key, fields)
  local w = fields or {}
  w.code, w.key, w.textKey = code, key, w.textKey or TEXT_KEYS[code]
  list[#list + 1] = w
end

-- Warning fields: code, key (perk, nil for budget), textKey, plus tree, have, need, other as the code needs.
-- gate: points in the category that come from perks with a lower gate. Perks of the same gate cannot open
-- each other, so only the lower gates count (the order of purchases in the game is reproducible this way).
function LL.validate(build, rules)
  rules = mergeRules(rules)
  local d = data()
  local warnings = {}
  local spent = LL.spent(build)
  for _, tree in ipairs(d.trees) do
    for _, perk in ipairs(tree.nodes) do
      local rank = rankOf(build, perk.key)
      if rank > perk.ranks then
        warn(warnings, "overmax", perk.key, { tree = tree.tree, have = rank, need = perk.ranks })
      end
      local gate = gateOf(perk, rules)
      if rank > 0 and gate > 0 then
        local have = 0
        for _, other in ipairs(tree.nodes) do
          if gateOf(other, rules) < gate then
            have = have + rankOf(build, other.key)
          end
        end
        if have < gate then
          warn(warnings, "gate", perk.key, { tree = tree.tree, have = have, need = gate })
        end
      end
      for _, node in ipairs(perk.unlocks) do
        local target = d.keyOfNode[node]
        local need = rules.edgeStrict and perk.ranks or 1
        if target and rankOf(build, target) > 0 and rankOf(build, perk.key) < need then
          warn(warnings, "edge", target, {
            tree = tree.tree,
            other = perk.key,
            have = rankOf(build, perk.key),
            need = need,
            textKey = rules.edgeStrict and "legacy.warn.edge.full" or nil,
          })
        end
      end
    end
    if rules.budgetMode == "perTree" and spent.byTree[tree.tree] > rules.limit then
      warn(warnings, "budget", nil, {
        tree = tree.tree,
        have = spent.byTree[tree.tree],
        need = rules.limit,
        textKey = "legacy.warn.budget.tree",
      })
    end
  end
  if rules.budgetMode == "pool" and spent.total > rules.limit then
    warn(warnings, "budget", nil, { have = spent.total, need = rules.limit })
  end
  local stray = {}
  for key, rank in pairs(build.ranks) do
    if not d.perk[key] and (tonumber(rank) or 0) > 0 then
      stray[#stray + 1] = key
    end
  end
  table.sort(stray)
  for _, key in ipairs(stray) do
    warn(warnings, d.soon[key] and "placeholder" or "unknown", key)
  end
  return { ok = #warnings == 0, warnings = warnings, spent = spent }
end

-- Display helpers ---------------------------------------------------------------------

-- Perks of a tree as the grid shows them: by column, then row.
function LL.perksOf(treeId)
  local tree = data().treeById[treeId]
  local list = {}
  for i, perk in ipairs(tree and tree.nodes or {}) do
    list[i] = perk
  end
  table.sort(list, function(a, b)
    if a.col ~= b.col then
      return a.col < b.col
    end
    return a.row < b.row
  end)
  return list
end

-- Client grid position { x, y } of a perk (table or key), nil for unknown perks.
function LL.position(perk)
  if type(perk) == "string" then
    perk = data().perk[perk]
  end
  local at = perk and ns.Data.LegacyGrid.nodes[perk.node]
  return at and { x = at.x, y = at.y } or nil
end

-- perk: a perk table or its key.
function LL.name(perk, locale)
  if type(perk) == "string" then
    perk = data().perk[perk]
  end
  if not perk then
    return ""
  end
  return perk.n[lang(locale)] or perk.n.en
end

function LL.treeName(treeId, locale)
  local tree = data().treeById[treeId]
  return tree and LL.text("legacy.tree." .. tree.cat, locale) or ""
end

-- Warning as text in the given locale (default the active one).
function LL.warningText(w, locale)
  local fmt = LL.text(w.textKey, locale)
  if w.code == "overmax" then
    return fmt:format(LL.name(w.key, locale), w.have, w.need)
  elseif w.code == "gate" then
    return fmt:format(LL.name(w.key, locale), w.need, LL.treeName(w.tree, locale), w.have)
  elseif w.code == "edge" then
    return fmt:format(LL.name(w.key, locale), LL.name(w.other, locale))
  elseif w.code == "budget" and w.tree then
    return fmt:format(LL.treeName(w.tree, locale), w.have, w.need)
  elseif w.code == "budget" then
    return fmt:format(w.have, w.need)
  end
  return fmt:format(w.key)
end

-- "Professions 7, Adventure 5, Resourcefulness 4, total 16 of 16".
function LL.summary(build, locale, rules)
  rules = mergeRules(rules)
  local spent = LL.spent(build)
  local parts = {}
  for _, tree in ipairs(data().trees) do
    parts[#parts + 1] = LL.treeName(tree.tree, locale) .. " " .. spent.byTree[tree.tree]
  end
  local limit = rules.budgetMode == "perTree" and rules.limit * #parts or rules.limit
  return LL.text("legacy.summary", locale):format(table.concat(parts, ", "), spent.total, limit)
end

-- Exchange format -------------------------------------------------------------------------
-- v2: "v2." then "<key>.<rank>" pairs joined by "_", ranks above 0 only, sorted by key.
-- v1 (read only): one digit per website slot, categories joined by "-".

-- Known keys with a rank above 0, clamped to the maximum, sorted by key.
function LL.export(build)
  local d = data()
  local keys = {}
  for key in pairs(d.perk) do
    if rankOf(build, key) > 0 then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for i, key in ipairs(keys) do
    keys[i] = key .. "." .. math.min(d.perk[key].ranks, rankOf(build, key))
  end
  return "v2." .. table.concat(keys, "_")
end

local function escape(text)
  return (text:gsub("[^%w%-%._~]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

function LL.exportUrl(build, locale)
  return SITE:format(lang(locale)) .. "?set=" .. SET .. "&l=" .. escape(LL.export(build))
end

local function bad(reason)
  return nil, "bad input", reason
end

local function readV2(body, build, report)
  local seen, order = {}, {}
  if body ~= "" then
    for pair in (body .. "_"):gmatch("([^_]*)_") do
      local key, rank = pair:match("^([%w%-]+)%.(.*)$")
      if not key then
        return bad("pair")
      end
      if not rank:match("^%d+$") then
        return bad("rank")
      end
      if seen[key] ~= nil then
        report.duplicates[#report.duplicates + 1] = key
      else
        order[#order + 1] = key
      end
      seen[key] = tonumber(rank) -- last one wins
    end
  end
  local d = data()
  for _, key in ipairs(order) do
    local perk = d.perk[key]
    if not perk then
      report.unknownKeys[#report.unknownKeys + 1] = key
    else
      local rank = seen[key]
      if rank > perk.ranks then
        report.clamped[#report.clamped + 1] = { key = key, from = rank, to = perk.ranks }
        rank = perk.ranks
      end
      if rank > 0 then
        build.ranks[key] = rank
      end
    end
  end
  return build
end

local function readV1(code, build, report)
  local segments = {}
  for segment in (code .. "-"):gmatch("([^%-]*)%-") do
    segments[#segments + 1] = segment
  end
  local d = data()
  if #segments ~= #d.trees then
    return bad("segments")
  end
  for i, tree in ipairs(d.trees) do
    local layout, segment = SLOTS[tree.cat], segments[i]
    local slots = {}
    if #segment == 9 then
      local real, soon = 1, 0
      for slot = 1, 9 do
        if slot == layout.soon[1] or slot == layout.soon[2] then
          soon = soon + 1
          slots[slot] = { soon = layout.prefix .. "-soon-" .. soon }
        else
          slots[slot] = { perk = tree.nodes[real] }
          real = real + 1
        end
      end
    elseif #segment == #tree.nodes then
      for slot, perk in ipairs(tree.nodes) do
        slots[slot] = { perk = perk }
      end
    else
      return bad("length")
    end
    for slot, entry in ipairs(slots) do
      local digit = tonumber(segment:sub(slot, slot))
      if digit > 0 and entry.soon then
        report.unknownKeys[#report.unknownKeys + 1] = entry.soon
      elseif digit > 0 then
        local perk = entry.perk
        if digit > perk.ranks then
          report.clamped[#report.clamped + 1] = { key = perk.key, from = digit, to = perk.ranks }
          digit = perk.ranks
        end
        build.ranks[perk.key] = digit
      end
    end
  end
  return build
end

local function squash(text)
  return (text:gsub("%s+", ""))
end

local function percentDecode(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Accepts the full link, "?set=...&l=<code>" or the bare code, with spaces and line breaks anywhere.
-- Returns build, report = { unknownKeys, clamped, duplicates, version = 1|2, source = "url"|"code" }.
-- Bad input returns nil, "bad input", reason (empty, nocode, format, version, pair, rank, segments, length).
-- A key that appears twice: the last rank wins and the key is listed in report.duplicates.
function LL.import(text)
  text = type(text) == "string" and squash(text) or ""
  if text == "" then
    return bad("empty")
  end
  local report = { unknownKeys = {}, clamped = {}, duplicates = {}, source = "code" }
  local code = text:match("[%?&]l=([^&#]*)")
  if code then
    report.source = "url"
    code = squash(percentDecode(code))
  elseif text:find("[%?=/:]") then
    return bad("nocode")
  else
    code = squash(percentDecode(text))
  end
  if code == "" then
    return bad(report.source == "url" and "nocode" or "empty")
  end
  local build = LL.new()
  local result, err, reason
  if code:match("^v2%.") then
    report.version = 2
    result, err, reason = readV2(code:sub(4), build, report)
  elseif code:match("^[%d%-]+$") then
    report.version = 1
    result, err, reason = readV1(code, build, report)
  elseif code:match("^v%d+%.") then
    return bad("version")
  else
    return bad("format")
  end
  if not result then
    return nil, err, reason
  end
  return build, report
end

-- Client nodes ------------------------------------------------------------------------------

-- { [nodeId] = rank } for all 21 perks (0 for perks without points). The tiered node (Talented) carries
-- only its rank here; which entry belongs to which rank is the business of the apply layer.
function LL.toNodeRanks(build)
  local d = data()
  local map = {}
  for _, tree in ipairs(d.trees) do
    for _, perk in ipairs(tree.nodes) do
      map[perk.node] = math.min(perk.ranks, rankOf(build, perk.key))
    end
  end
  return map
end

-- Placeholders, unknown nodes and values that are no numbers are ignored, ranks are clamped.
-- Returns the build and the list of ignored node ids.
function LL.fromNodeRanks(map)
  local d = data()
  local build, ignored = LL.new(), {}
  local ids = {}
  for node in pairs(map) do
    ids[#ids + 1] = node
  end
  table.sort(ids, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, node in ipairs(ids) do
    local key = d.keyOfNode[node]
    if not key or not tonumber(map[node]) then
      ignored[#ignored + 1] = node
    else
      LL.setRank(build, key, map[node])
    end
  end
  return build, ignored
end
